#!/usr/bin/env bash
# workspace-cleanup.sh 의 핵심 경로를 고정하는 게이트 — 생성 왕복(workspace-check.sh)의 대칭.
#   ① 정상 정리 — 워크트리·로컬 스토리 브랜치·부트스트랩 마커가 사라지고 **클론은 남는다**.
#      무시된 부트스트랩 산출물(node_modules/)이 정리를 막지 않는다
#   ② 미커밋 변경 → 지우지 않고 rc=1, 무엇이 남았는지 출력. **--force 로도 뚫리지 않는다**
#   ③ 미푸시 커밋 → 지우지 않고 rc=1 + 커밋 목록 출력. --force 면 진행한다
#   ④ 푸시된 커밋은 막지 않는다 (②③ 이 "항상 막는 규칙"이 아님을 증명하는 대조군)
#   ⑤ fetch --prune 실패(원격 소실) → 미푸시 판정의 근거가 없으므로 손대지 않는다
#   ⑥ 워크트리가 아닌 잔존 디렉토리 → 지우지 않고 rc=1
#   ⑦ 이미 정리된 상태에 다시 불러도 rc=0 (멱등)
#   ⑧ 심볼릭 경로로 워크트리 안에 서 있는 호출자도 가드에 걸린다 (자기 CWD 삭제 방지)
#   ⑨ 브랜치 삭제만 실패해도 제거한 워크트리는 stdout 에 실린다 — 반쯤 정리된 레포와
#      손도 안 댄 레포를 호출자가 구분할 수 있어야 한다
#   ⑩ 다른 스토리의 워크트리 등록은 보존된다 — 등록부 정리는 레포 전역이라 실체가
#      일시적으로 안 보이는(볼륨 언마운트) 남의 등록까지 지운다. 그 지점을 스토리로 좁혔다
#   ⑪ 등록부에 없는 repo: 라벨 → rc=1
#
# **⑪ 은 bead 에 등록부에 없는 라벨을 붙인다 — 그 뒤의 모든 절은 rc 가 1 로 고정된다.**
# rc 를 보는 절은 전부 ⑪ 앞에 둔다. 뒤에 붙이면 그 절의 rc 단언이 조용히 오염된다
# (실측 2026-08-22: ⑩ 을 뒤에 뒀더니 rc=0 단언이 실패했다).
#
# 임시 bare origin + 클론으로 상황을 만들고 HARNESS_CLONE_ROOT 를 임시 디렉토리로 돌려
# 실제 ~/.harness-workspace 는 건드리지 않는다 (workspace-check.sh 와 같은 격리 방식).
# 워크트리에서도 그대로 돈다 — 워크트리의 원장은 hooks/enter-worktree.sh 가 배선한다.
set -uo pipefail
# 하네스 루트(원장의 자리 — 검사용 bead 를 만든다)는 lib/harness-root.sh 가 낸다. 못 찾으면 rc=1.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ROOT="$(bash "$PLUGIN_ROOT/lib/harness-root.sh")" || exit 1
cd "$ROOT" || { echo "✗ 하네스 루트로 이동하지 못했다: $ROOT" >&2; exit 1; }

TMP=$(mktemp -d)
BEAD=""
GITC=(-c user.email=check@harness -c user.name=harness-check)
export HARNESS_CLONE_ROOT="$TMP/clones"

cleanup() {
  [[ -n "$BEAD" ]] && bd delete "$BEAD" --force >/dev/null 2>&1
  rm -rf "$TMP"
}
trap cleanup EXIT

fail=0
step() {
  local label="$1"; shift
  if "$@"; then echo "  ✓ ${label}"; else echo "  ✗ FAILED: ${label}"; fail=1; fi
}
has_text() { case "$2" in *"$1"*) return 0;; *) return 1;; esac; }
no_branch() { ! git -C "$CLONE" show-ref --verify --quiet "refs/heads/worktree-$BEAD"; }
has_branch() { git -C "$CLONE" show-ref --verify --quiet "refs/heads/worktree-$BEAD"; }
is_repo() { git -C "$1" rev-parse --git-dir >/dev/null 2>&1; }

# ── 준비: bare origin, 등록 대상 클론 ──
git init -q --bare "$TMP/origin.git"
git clone -q "$TMP/origin.git" "$TMP/seed" 2>/dev/null
( cd "$TMP/seed" && printf 'node_modules/\n' > .gitignore && echo one > a.txt \
  && git add . && git "${GITC[@]}" commit -qm first && git push -q origin HEAD )
DEFAULT_BRANCH=$(git -C "$TMP/seed" symbolic-ref --short HEAD)

mkdir -p "$HARNESS_CLONE_ROOT"
git clone -q "$TMP/origin.git" "$HARNESS_CLONE_ROOT/wcclean" 2>/dev/null
CLONE="$HARNESS_CLONE_ROOT/wcclean"

# 부트스트랩 산출물은 무시되는 경로에 쓴다 — 실제 레포의 node_modules 와 같은 성질.
# 정리가 이것 때문에 막히면 게이트 ① 이 깨진다.
jq -n --arg b "$DEFAULT_BRANCH" \
  '{repos: [{name: "wcclean", url: "unused-in-this-check", default_branch: $b, check: "true",
             bootstrap: "mkdir -p node_modules && echo ran > node_modules/mark"}]}' \
  > "$TMP/manifest.json"

BEAD=$(bd create "wcclean: workspace-cleanup.sh 게이트용" -t task --ephemeral -l "repo:wcclean" --silent)
[[ -n "$BEAD" ]] || { echo "  ✗ FAILED: 검사용 bead 생성"; exit 1; }

WT="$CLONE/.claude/worktrees/$BEAD"
MARKER="$CLONE/.claude/worktrees/.bootstrapped-$BEAD"

# EnterWorktree 의 재현 — 트리는 git worktree add(name=<id> → 브랜치 worktree-<id>, 실측 2026-09-05)로,
# 원장 배선·부트스트랩은 PostToolUse 훅(hooks/enter-worktree.sh)으로. 트리가 이미 있으면(재진입)
# 훅만 다시 돈다 — path 로 들어간 호출과 같다. 훅의 하네스 루트는 HARNESS_ROOT 로 물린다.
run_ws() {
  [[ -d "$WT" ]] || git -C "$CLONE" "${GITC[@]}" worktree add -q -b "worktree-$BEAD" "$WT" "origin/$DEFAULT_BRANCH" >/dev/null 2>&1
  printf '{"session_id":"wcclean","hook_event_name":"PostToolUse","tool_name":"EnterWorktree","cwd":"%s"}' "$WT" \
    | HARNESS_ROOT="$ROOT" REPOS_MANIFEST="$TMP/manifest.json" bash "$PLUGIN_ROOT/hooks/enter-worktree.sh" >/dev/null 2>&1
}
run_cl() { REPOS_MANIFEST="$TMP/manifest.json" "$PLUGIN_ROOT/scripts/workspace-cleanup.sh" "$BEAD" "$@"; }

echo "── ① 정상 정리 ──"
run_ws
step "준비: 워크트리 생성됨"     [ -d "$WT" ]
step "준비: 부트스트랩 마커"     [ -f "$MARKER" ]
step "준비: 무시되는 산출물"     [ -f "$WT/node_modules/mark" ]
ERRF="$TMP/cleanup-err.txt"
OUT=$(run_cl 2>"$ERRF"); rc=$?            # stdout 은 계약 채널, stderr 는 진단
step "정상 정리 rc=0"            [ "$rc" -eq 0 ]
step "stdout 이 이름+경로 형식"  [ "$OUT" = "$(printf 'wcclean\t%s' "$WT")" ]
step "워크트리 디렉토리 사라짐"  [ ! -e "$WT" ]
step "로컬 스토리 브랜치 사라짐" no_branch
step "부트스트랩 마커 사라짐"    [ ! -e "$MARKER" ]
step "클론은 남아 있다"          is_repo "$CLONE"
step "워크트리 등록부도 비었다"  [ "$(git -C "$CLONE" worktree list --porcelain | grep -c '^worktree ')" = "1" ]
# 무시된 파일은 미커밋 검사(status --short)에도 안 잡히고 git 의 remove 도 거부하지 않아
# 그대로 사라진다 — 워크트리의 .env 가 그 경우다. 막지 않기로 한 결정은 유지하되(그러지
# 않으면 node_modules 로 정리가 막힌다) **드러나기는 하는지**를 못박는다.
step "무시된 파일이 함께 사라짐을 알린다" has_text "무시된 파일" "$(cat "$ERRF")"
step "무엇이 사라지는지 이름을 댄다"      has_text "node_modules" "$(cat "$ERRF")"

echo "── ② 미커밋 변경 → 지우지 않는다 (--force 로도) ──"
run_ws
echo dirty > "$WT/untracked.txt"
OUT=$(run_cl 2>&1); rc=$?
step "미커밋 rc=1"               [ "$rc" -eq 1 ]
step "무엇이 남았는지 출력"      has_text "untracked.txt" "$OUT"
# 이 스크립트의 검사가 판정했음을 못박는다 — git 자신의 `worktree remove` 도 untracked
# 가 있으면 거부하므로(2중 방어), 메시지를 단언하지 않으면 우리 검사를 통째로 지워도
# rc=1 이 유지돼 게이트가 조용히 통과한다 (변조 실측 2026-08-21).
step "우리 검사가 판정했다"      has_text "미커밋 변경이 있다" "$OUT"
step "워크트리 유지"             [ -d "$WT" ]
step "브랜치 유지"               has_branch
OUT=$(run_cl --force 2>&1); rc=$?
step "--force 로도 rc=1"         [ "$rc" -eq 1 ]
step "--force 로도 워크트리 유지" [ -d "$WT" ]

echo "── ③ 미푸시 커밋 → 지우지 않는다. --force 면 진행 ──"
rm -f "$WT/untracked.txt"
( cd "$WT" && echo two > b.txt && git add b.txt && git "${GITC[@]}" commit -qm "unpushed-work" )
OUT=$(run_cl 2>&1); rc=$?
step "미푸시 rc=1"               [ "$rc" -eq 1 ]
step "남은 커밋을 출력"          has_text "unpushed-work" "$OUT"
step "워크트리 유지"             [ -d "$WT" ]
OUT=$(run_cl --force 2>&1); rc=$?
step "--force rc=0"              [ "$rc" -eq 0 ]
step "--force 후 워크트리 없음"  [ ! -e "$WT" ]
step "--force 후 브랜치 없음"    no_branch

echo "── ④ 푸시된 커밋은 막지 않는다 (대조군) ──"
run_ws
( cd "$WT" && echo three > c.txt && git add c.txt && git "${GITC[@]}" commit -qm "pushed-work" \
  && git push -q origin HEAD )
OUT=$(run_cl 2>&1); rc=$?
step "푸시됨 → rc=0"             [ "$rc" -eq 0 ]
step "워크트리 사라짐"           [ ! -e "$WT" ]
step "브랜치 사라짐"             no_branch

echo "── ⑤ fetch --prune 실패 → 손대지 않는다 ──"
run_ws
mv "$TMP/origin.git" "$TMP/origin-gone.git"
OUT=$(run_cl 2>&1); rc=$?
mv "$TMP/origin-gone.git" "$TMP/origin.git"
step "fetch 실패 rc=1"           [ "$rc" -eq 1 ]
step "이유를 밝힌다"             has_text "fetch --prune 실패" "$OUT"
step "워크트리 유지"             [ -d "$WT" ]

echo "── ⑥ 워크트리가 아닌 잔존 디렉토리 → 지우지 않는다 ──"
run_cl >/dev/null 2>&1                    # ⑤ 에서 남은 것을 정상 정리
step "선행 정리 확인"            [ ! -e "$WT" ]
mkdir -p "$WT/사람의-파일"
OUT=$(run_cl 2>&1); rc=$?
step "잔존 디렉토리 rc=1"        [ "$rc" -eq 1 ]
step "디렉토리 유지"             [ -d "$WT/사람의-파일" ]
rm -rf "$WT"

echo "── ⑦ 멱등: 이미 정리된 상태 ──"
# stdout 과 stderr 를 섞지 않는다 — 섞으면 아래 "stdout 이 비어 있다" 단언이 진단 문구
# 때문에 항상 거짓이 되어, 계약 위반을 못 보는 채로 통과하던 종전 형태로 돌아간다.
OUT=$(run_cl 2>"$ERRF"); rc=$?
step "재실행 rc=0"               [ "$rc" -eq 0 ]
step "지울 것이 없었음을 밝힌다" has_text "이미 정리된 상태" "$(cat "$ERRF")"
# stdout 은 "제거했다"는 계약이다. 아무것도 제거하지 않았는데 줄이 나오면 파싱하는
# 호출자가 방금 제거했다고 믿는다 — 종전에는 \t 만 담긴 줄이 나왔다.
step "제거한 것이 없으면 stdout 이 비어 있다" [ -z "$OUT" ]
step "클론은 여전히 남아 있다"   is_repo "$CLONE"

echo "── ⑧ 심볼릭 경로로 선 호출자 → 자기 CWD 를 지우지 않는다 ──"
# 스크립트는 호출자가 서 있는 워크트리를 지우지 않는다. 그 판정이 논리 경로만 보면
# 같은 디렉토리를 심볼릭 경로로 들어온 호출자를 못 알아보고 자기 CWD 를 지운다 —
# 지운 뒤 그 셸의 CWD 는 없는 inode 가 되어 이후 명령이 알 수 없는 이유로 죽는다.
# macOS 의 /var→/private/var 처럼 심링크는 늘 곁에 있으므로 가설이 아니라 재현 대상이다.
run_ws
LINK="$TMP/wt-link"
ln -s "$WT" "$LINK"
OUT=$( cd "$LINK" && REPOS_MANIFEST="$TMP/manifest.json" "$PLUGIN_ROOT/scripts/workspace-cleanup.sh" "$BEAD" 2>&1 ); rc=$?
rm -f "$LINK"
step "심볼릭 경로 호출자 rc=1"   [ "$rc" -eq 1 ]
step "가드가 이유를 밝힌다"      has_text "정리 대상 워크트리 안에 서 있다" "$OUT"
step "워크트리 유지"             [ -d "$WT" ]
run_cl >/dev/null 2>&1           # 다음 절을 위해 정상 정리
step "후속 정리 확인"            [ ! -e "$WT" ]

echo "── ⑨ 브랜치 삭제만 실패해도 제거한 워크트리는 stdout 에 실린다 ──"
# 워크트리를 지운 뒤 브랜치 삭제가 실패하면 종전에는 continue 로 그 줄을 건너뛰어,
# **반쯤 정리된 레포와 손도 안 댄 레포가 구분되지 않았다.** 실패는 refs 디렉토리를
# 읽기 전용으로 만들어 주입한다 (브랜치 삭제만 막고 워크트리 제거는 막지 않는다).
run_ws
REFDIR="$CLONE/.git/refs/heads"   # worktree-<id> 는 refs/heads 직속 loose ref 다 (story/<id> 시절의 하위 디렉토리가 아니다)
step "준비: 워크트리 생성됨"     [ -d "$WT" ]
step "준비: 브랜치 ref 가 파일로 있다" [ -f "$REFDIR/worktree-$BEAD" ]
chmod 500 "$REFDIR"
OUT=$(run_cl 2>"$ERRF"); rc=$?
chmod 700 "$REFDIR"
step "브랜치 삭제 실패 → rc=1"   [ "$rc" -eq 1 ]
step "워크트리는 실제로 사라졌다" [ ! -e "$WT" ]
step "그래도 stdout 에 경로가 실린다" [ "$OUT" = "$(printf 'wcclean\t%s' "$WT")" ]
step "브랜치가 남았음을 밝힌다"  has_text "브랜치는 남는다" "$(cat "$ERRF")"
git -C "$CLONE" branch -D "worktree-$BEAD" >/dev/null 2>&1
step "뒷정리: 브랜치 제거됨"     no_branch

echo "── ⑩ 다른 스토리의 워크트리 등록은 보존된다 ──"
# 등록부 정리는 레포 전역이라, 실체가 일시적으로 안 보이는 다른 스토리의 등록까지
# 지운다(외부·네트워크 볼륨 언마운트). 이 스크립트의 나머지는 전부 스토리로 좁혀져
# 있으므로 이 지점도 좁혔다 — 남의 고아 등록이 섞여 있으면 손대지 않는다.
run_ws
OTHER_BEAD="other-$BEAD"
OTHER_WT="$CLONE/.claude/worktrees/$OTHER_BEAD"
git -C "$CLONE" "${GITC[@]}" worktree add -q -b "worktree-$OTHER_BEAD" "$OTHER_WT" >/dev/null 2>&1
step "준비: 다른 스토리의 워크트리 등록됨" [ -d "$OTHER_WT" ]
mv "$OTHER_WT" "$TMP/parked"     # 볼륨 언마운트 흉내 — 등록은 남고 실체만 사라진다
OUT=$(run_cl 2>"$ERRF"); rc=$?
step "우리 스토리 정리 rc=0"     [ "$rc" -eq 0 ]
step "우리 워크트리는 사라졌다"  [ ! -e "$WT" ]
step "다른 스토리의 등록이 남아 있다" has_text "$OTHER_BEAD" "$(git -C "$CLONE" worktree list --porcelain)"
step "손대지 않았음을 알린다"    has_text "이 스토리 밖의 등록도" "$(cat "$ERRF")"
mv "$TMP/parked" "$OTHER_WT"
git -C "$CLONE" worktree remove --force "$OTHER_WT" >/dev/null 2>&1
git -C "$CLONE" branch -D "worktree-$OTHER_BEAD" >/dev/null 2>&1

echo "── ⑪ 등록부에 없는 repo: 라벨 ──"
bd tag "$BEAD" repo:missing >/dev/null
OUT=$(run_cl 2>&1); rc=$?
step "누락 시 rc=1"              [ "$rc" -eq 1 ]

exit $fail
