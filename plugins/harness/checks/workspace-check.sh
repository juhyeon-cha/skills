#!/usr/bin/env bash
# workspace.sh 의 핵심 경로를 고정하는 게이트
#   ① 정상 생성 — 낡은 로컬 HEAD 가 아니라 origin/<기본 브랜치> 최신 커밋 기준 (실측 결함의 회귀 방지)
#   ② 워크트리가 클론 안(<클론>/.claude/worktrees/<story-id>)에 생긴다
#   ③ stdout 계약 — "<레포이름>\t<절대경로>" 줄 목록
#   ④ 부트스트랩 — 생성 시 실행, 실패 시 rc=1, 재실행이 부트스트랩부터 재시도
#   ⑤ 재실행 멱등 (검증 통과한 재사용)
#   ⑥ 재사용 검증 — 깨진 잔존 디렉토리·클론과 무관한 독립 레포를 거부
#   ⑦ 등록부 누락 시 비-0 실패 + 성공분 유지
#   ⑧ 원장 배선 — .beads/redirect 가 실재하는 원장을 가리키고 제외 목록에 등재된다
# 임시 bare origin + 클론 2개로 "로컬이 낡은" 상황을 재현한다.
# HARNESS_CLONE_ROOT 를 임시 디렉토리로 돌려 실제 ~/.harness-workspace 는 건드리지 않는다.
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

# ── 준비: bare origin, 클론(등록 대상), 최신 커밋을 밀어넣는 다른 클론 ──
git init -q --bare "$TMP/origin.git"
git clone -q "$TMP/origin.git" "$TMP/seed" 2>/dev/null
( cd "$TMP/seed" && echo one > a.txt && git add . && git "${GITC[@]}" commit -qm first && git push -q origin HEAD )
DEFAULT_BRANCH=$(git -C "$TMP/seed" symbolic-ref --short HEAD)

# 등록 대상 클론: 첫 커밋 시점에 떠서 이후 커밋을 모른다 (= 낡은 로컬 HEAD)
mkdir -p "$HARNESS_CLONE_ROOT"
git clone -q "$TMP/origin.git" "$HARNESS_CLONE_ROOT/wscheck" 2>/dev/null

( cd "$TMP/seed" && echo two > b.txt && git add . && git "${GITC[@]}" commit -qm second && git push -q )
LATEST=$(git -C "$TMP/seed" rev-parse HEAD)   # origin 의 최신. wscheck 클론의 HEAD 는 한 커밋 뒤다

# bootstrap 은 실행 표식 파일을 남긴다 — 실행 여부·횟수를 게이트가 셀 수 있게.
jq -n --arg b "$DEFAULT_BRANCH" \
  '{repos: [{name: "wscheck", url: "unused-in-this-check", default_branch: $b, check: "true",
             bootstrap: "echo ran >> BOOT_MARK"}]}' \
  > "$TMP/manifest.json"

BEAD=$(bd create "wscheck: workspace.sh 게이트용" -t task --ephemeral -l "repo:wscheck" --silent)
[[ -n "$BEAD" ]] || { echo "  ✗ FAILED: 검사용 bead 생성" ; exit 1; }

run_ws() { REPOS_MANIFEST="$TMP/manifest.json" "$PLUGIN_ROOT/scripts/workspace.sh" "$BEAD"; }

# ── ①②③ 정상 생성 ──
OUT=$(run_ws 2>/dev/null); rc=$?
WT=$(echo "$OUT" | awk -F'\t' '$1=="wscheck"{print $2; exit}')
step "정상 생성 rc=0"            [ "$rc" -eq 0 ]
step "stdout 이 이름+경로 형식"  [ -n "$WT" ]
step "워크트리 존재"             [ -d "$WT" ]
step "클론 안에 생성"            [ "$WT" = "$HARNESS_CLONE_ROOT/wscheck/.claude/worktrees/$BEAD" ]
step "브랜치 story/<id>"         [ "$(git -C "$WT" branch --show-current)" = "story/$BEAD" ]
step "기준이 origin 최신 커밋"   [ "$(git -C "$WT" rev-parse HEAD)" = "$LATEST" ]
# 체크아웃이 실제로 끝났는가. 위 다섯은 HEAD·브랜치만 보므로 `worktree add --no-checkout`
# 뒤 checkout 이 끊긴 빈 트리를 통과시킨다 — 재사용 검증에는 인덱스 검사가 있는데 생성
# 쪽에는 없어 생긴 비대칭이다. 판정 수단도 그쪽과 같은 것으로 둔다(workspace.sh 의 재사용
# 검증) — 픽스처가 만드는 파일 이름에 묶으면 픽스처를 바꿀 때 이 단언이 함께 흔들린다.
step "트리가 체크아웃됨"         [ -n "$(git -C "$WT" ls-files | head -n 1)" ]

# ── ⑧ 원장 배선 — 배선이 없으면 워크트리의 bare bd 가 "bd init" 을 권해 원장이 이원화된다.
#    redirect 의 내용이 실재하는 디렉토리인지까지 본다 (파일만 있고 가리키는 곳이 없으면 같은 침묵).
step "원장 배선 파일"            [ -d "$(cat "$WT/.beads/redirect" 2>/dev/null)" ]
step "배선이 제외 목록에 등재"   grep -qxF ".beads" "$HARNESS_CLONE_ROOT/wscheck/.git/info/exclude"

# ── ④ 부트스트랩: 생성 시 1회 실행 + 마커 ──
step "부트스트랩 실행됨"         [ "$(grep -c ran "$WT/BOOT_MARK" 2>/dev/null)" = "1" ]
MARKER="$HARNESS_CLONE_ROOT/wscheck/.claude/worktrees/.bootstrapped-$BEAD"
step "부트스트랩 마커 생성"      [ -f "$MARKER" ]

# ── ⑤ 재실행 멱등: 부트스트랩 재실행 없음 ──
OUT2=$(run_ws 2>/dev/null); rc2=$?
WT2=$(echo "$OUT2" | awk -F'\t' '$1=="wscheck"{print $2; exit}')
step "재실행 rc=0"               [ "$rc2" -eq 0 ]
step "재실행 경로 동일"          [ "$WT2" = "$WT" ]
step "부트스트랩 중복 실행 없음" [ "$(grep -c ran "$WT/BOOT_MARK" 2>/dev/null)" = "1" ]

# ── ④-2 마커 없으면 재사용 경로가 부트스트랩을 재시도 (실패 잔존 복구 회귀 방지) ──
rm -f "$MARKER"
run_ws >/dev/null 2>&1
step "마커 부재 시 재시도"       [ "$(grep -c ran "$WT/BOOT_MARK" 2>/dev/null)" = "2" ]
step "재시도 후 마커 복원"       [ -f "$MARKER" ]

# ── ⑥ 재사용 검증: 깨진 잔존·고아 레포 거부 ──
git -C "$HARNESS_CLONE_ROOT/wscheck" worktree remove --force "$WT" 2>/dev/null
git -C "$HARNESS_CLONE_ROOT/wscheck" worktree prune 2>/dev/null
rm -rf "$WT"; mkdir -p "$WT"           # 워크트리 아님 — 일반 디렉토리 잔존
run_ws >/dev/null 2>&1; rc3=$?
step "깨진 잔존 → rc=1"          [ "$rc3" -eq 1 ]
rm -rf "$WT"
( git init -q "$WT" && cd "$WT" && git "${GITC[@]}" commit -q --allow-empty -m x \
  && git checkout -q -b "story/$BEAD" )   # 클론과 무관한 독립 레포, 브랜치명만 일치
run_ws >/dev/null 2>&1; rc4=$?
step "고아 레포 잔존 → rc=1"     [ "$rc4" -eq 1 ]
rm -rf "$WT"
git -C "$HARNESS_CLONE_ROOT/wscheck" worktree prune 2>/dev/null

# ── ⑦ 등록부 누락 실패: 없는 레포 라벨 추가 → rc 1, 기존 성공분 유지 ──
run_ws >/dev/null 2>&1                   # 정상 재생성
bd tag "$BEAD" repo:missing >/dev/null
run_ws >/dev/null 2>&1; rc5=$?
step "누락 시 rc=1"              [ "$rc5" -eq 1 ]
step "성공분 유지"               [ -d "$WT" ]

exit $fail
