#!/usr/bin/env bash
# EnterWorktree 흐름의 왕복을 고정하는 게이트 — 생성은 네이티브 도구(세션 없이는 재현할 수 없다)라
# 그 도구가 하는 일을 `git worktree add -b worktree-<id> <클론>/.claude/worktrees/<id> origin/<기본브랜치>`
# 로 재현하고(실측 2026-09-05, claude -p: name=X → 경로 .claude/worktrees/X · 브랜치 worktree-X),
# 그 위에 PostToolUse 훅(hooks/enter-worktree.sh)을 표본 payload 로 돌린 뒤 scripts/workspace-cleanup.sh
# 로 되돌린다.
#   ① 훅 — .beads/redirect 가 하네스 원장을 가리키고, 클론 exclude 에 .beads 가 등재되며,
#      워크트리에서 부른 lib/harness-root.sh 가 그 배선을 따라 하네스 루트를 낸다
#   ② 부트스트랩 폴백 — 자기 EnterWorktree 훅이 없는 레포에서 1회 실행 + 형제 마커, 재진입은 마커로
#      건너뛰고, 마커가 없으면 재시도한다
#   ③ 자기 EnterWorktree 훅을 가진 레포에서는 bootstrap 을 돌리지 않는다
#   ④ cwd 가 워크트리 밖이면 아무것도 만들지 않고 rc=0
#   ⑤ 하네스 루트를 못 찾으면 rc=2 이고 stderr 가 "원장 배선 실패" 를 든다 — PostToolUse 훅 실패는
#      도구 호출을 막지 않고 exit 2 의 stderr 만 Claude 에게 실리므로, 그 출구와 문구가 유일한 신호다
#   ⑥ cleanup — git worktree list 에서 경로가 사라지고 브랜치 worktree-<id> 와 마커도 없다
# 임시 bare origin + 클론으로 상황을 만들고 HARNESS_CLONE_ROOT 를 임시 디렉토리로 돌려 실제
# ~/.harness-workspace 는 건드리지 않는다. 훅의 하네스 루트는 HARNESS_ROOT 로 물린다 — 갓 만든
# 워크트리에는 redirect 가 없어 헬퍼가 .harness-root 파일에 기대는데, 그 파일은 이 머신의 상태다.
set -uo pipefail
# 하네스 루트(원장의 자리 — 검사용 bead 를 만든다)는 lib/harness-root.sh 가 낸다. 못 찾으면 rc=1.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ROOT="$(bash "$PLUGIN_ROOT/lib/harness-root.sh")" || exit 1
cd "$ROOT" || { echo "✗ 하네스 루트로 이동하지 못했다: $ROOT" >&2; exit 1; }
TMP=$(mktemp -d)
BEAD=""
GITC=(-c user.email=check@harness -c user.name=harness-check)
export HARNESS_CLONE_ROOT="$TMP/clones"
HOOK="$PLUGIN_ROOT/hooks/enter-worktree.sh"

# 원장은 어댑터로 — 검사용 bead 의 생성·삭제(--ephemeral·delete 는 beads 전용 인자다).
ledger() { HARNESS_ROOT="$ROOT" bash "$PLUGIN_ROOT/scripts/ledger.sh" "$@"; }
cleanup() {
  [[ -n "$BEAD" ]] && ledger delete "$BEAD" --force >/dev/null 2>&1
  rm -rf "$TMP"
}
trap cleanup EXIT

fail=0
step() {
  local label="$1"; shift
  if "$@"; then echo "  ✓ ${label}"; else echo "  ✗ FAILED: ${label}"; fail=1; fi
}
has_text() { case "$2" in *"$1"*) return 0;; *) return 1;; esac; }
is_repo() { git -C "$1" rev-parse --git-dir >/dev/null 2>&1; }

# ── 준비: bare origin, 등록 대상 클론 ──
git init -q "$TMP/seed"
( cd "$TMP/seed" && printf 'node_modules/\n' > .gitignore && echo one > a.txt \
  && git add . && git "${GITC[@]}" commit -qm first )
DEFAULT_BRANCH=$(git -C "$TMP/seed" symbolic-ref --short HEAD)
git clone -q --bare "$TMP/seed" "$TMP/origin.git"
mkdir -p "$HARNESS_CLONE_ROOT"
git clone -q "$TMP/origin.git" "$HARNESS_CLONE_ROOT/wscheck" 2>/dev/null
CLONE="$HARNESS_CLONE_ROOT/wscheck"

# bootstrap 은 무시되는 경로에 실행 표식을 남긴다 — 실행 횟수를 게이트가 세고, 정리가 그것으로 막히지 않게.
jq -n --arg b "$DEFAULT_BRANCH" \
  '{repos: [{name: "wscheck", url: "unused-in-this-check", default_branch: $b, check: "true",
             bootstrap: "mkdir -p node_modules && echo ran >> node_modules/BOOT_MARK"}]}' \
  > "$TMP/manifest.json"

BEAD=$(ledger create "wscheck: EnterWorktree 왕복 게이트용" -t task --ephemeral -l "repo:wscheck" --silent)
[[ -n "$BEAD" ]] || { echo "  ✗ FAILED: 검사용 bead 생성" ; exit 1; }

WT="$CLONE/.claude/worktrees/$BEAD"
MARKER="$CLONE/.claude/worktrees/.bootstrapped-$BEAD"
BOOT="$WT/node_modules/BOOT_MARK"

# EnterWorktree 가 하는 일의 재현 — 트리만 만든다. 훅은 따로 부른다.
mk_tree() { git -C "$CLONE" "${GITC[@]}" worktree add -q -b "worktree-$BEAD" "$WT" "origin/$DEFAULT_BRANCH" 2>/dev/null; }
# PostToolUse 훅 실행 — payload 의 cwd 하나가 입력이다. $1 = cwd. 나머지 인자는 env 재정의.
run_hook() {
  local cwd="$1"; shift
  printf '{"session_id":"wscheck","hook_event_name":"PostToolUse","tool_name":"EnterWorktree","cwd":"%s"}' "$cwd" \
    | env HARNESS_ROOT="$ROOT" REPOS_MANIFEST="$TMP/manifest.json" "$@" bash "$HOOK"
}
run_cl() { REPOS_MANIFEST="$TMP/manifest.json" "$PLUGIN_ROOT/scripts/workspace-cleanup.sh" "$BEAD"; }

echo "── ① 훅: 원장 배선 ──"
mk_tree
step "준비: 트리가 worktree-<id> 브랜치로 만들어졌다" [ "$(git -C "$WT" branch --show-current)" = "worktree-$BEAD" ]
ERRF="$TMP/hook-err.txt"
run_hook "$WT" 2>"$ERRF"; rc=$?
step "훅 rc=0"                        [ "$rc" -eq 0 ]
step "redirect 가 하네스 원장을 가리킨다" [ "$(cat "$WT/.beads/redirect" 2>/dev/null)" = "$ROOT/.beads" ]
step "가리키는 곳이 실재한다"           [ -d "$(cat "$WT/.beads/redirect" 2>/dev/null)" ]
step "클론 exclude 에 .beads 등재"      grep -qxF ".beads" "$CLONE/.git/info/exclude"
step "클론 exclude 에 .claude/worktrees/ 등재" grep -qxF ".claude/worktrees/" "$CLONE/.git/info/exclude"
# 재진입 경로 — HARNESS_ROOT 없이 워크트리에서 부른 루트 탐색기가 배선을 따라 하네스 루트를 낸다
# (HARNESS_CLONE_ROOT 가 임시 디렉토리라 .harness-root 폴백은 없다 — 배선이 유일한 출처다).
step "워크트리에서 lib/harness-root.sh 가 배선을 따라 하네스 루트를 낸다" \
  [ "$(cd "$WT" && env -u HARNESS_ROOT bash "$PLUGIN_ROOT/lib/harness-root.sh" 2>/dev/null)" = "$ROOT" ]
step "워크트리 git status 가 비어 있다 (배선이 untracked 로 뜨지 않는다)" [ -z "$(git -C "$WT" status --short)" ]

echo "── ② 부트스트랩 폴백 ──"
step "부트스트랩 실행됨"               [ "$(grep -c ran "$BOOT" 2>/dev/null)" = "1" ]
step "형제 마커 생성"                  [ -f "$MARKER" ]
run_hook "$WT" 2>/dev/null; rc=$?
step "재진입 rc=0"                     [ "$rc" -eq 0 ]
step "재진입은 부트스트랩을 건너뛴다"   [ "$(grep -c ran "$BOOT" 2>/dev/null)" = "1" ]
rm -f "$MARKER"
run_hook "$WT" 2>/dev/null
step "마커 부재 시 재시도"             [ "$(grep -c ran "$BOOT" 2>/dev/null)" = "2" ]
step "재시도 후 마커 복원"             [ -f "$MARKER" ]

echo "── ③ 자기 EnterWorktree 훅을 가진 레포 ──"
mkdir -p "$WT/.claude"
printf '%s\n' '{"hooks":{"PostToolUse":[{"matcher":"EnterWorktree","hooks":[]}]}}' > "$WT/.claude/settings.json"
rm -f "$MARKER"
run_hook "$WT" 2>"$ERRF"; rc=$?
step "rc=0"                            [ "$rc" -eq 0 ]
step "bootstrap 을 돌리지 않는다"       [ "$(grep -c ran "$BOOT" 2>/dev/null)" = "2" ]
step "마커도 만들지 않는다"             [ ! -e "$MARKER" ]
step "소유자를 밝힌다"                  has_text "EnterWorktree 훅이 소유한다" "$(cat "$ERRF")"
rm -rf "$WT/.claude"

echo "── ④ cwd 가 워크트리 밖 ──"
run_hook "$CLONE" 2>/dev/null; rc=$?
step "rc=0"                            [ "$rc" -eq 0 ]
step "클론 루트에 redirect 를 만들지 않는다" [ ! -e "$CLONE/.beads/redirect" ]

echo "── ⑤ 하네스 루트를 못 찾는다 ──"
rm -rf "$WT/.beads"
run_hook "$WT" HARNESS_ROOT=/nonexistent 2>"$ERRF"; rc=$?
step "rc=2 (stderr 가 Claude 에게 실리는 출구)" [ "$rc" -eq 2 ]
step "stderr 가 원장 배선 실패를 든다"  has_text "원장 배선 실패" "$(cat "$ERRF")"
step "redirect 를 만들지 않았다"        [ ! -e "$WT/.beads/redirect" ]
run_hook "$WT" 2>/dev/null            # 정상 배선으로 복구 — ⑥ 의 입력

echo "── ⑥ cleanup 왕복 ──"
step "준비: 마커가 있다"               [ -f "$MARKER" ]
OUT=$(run_cl 2>"$ERRF"); rc=$?
step "cleanup rc=0"                    [ "$rc" -eq 0 ]
step "stdout 이 이름+경로 형식"         [ "$OUT" = "$(printf 'wscheck\t%s' "$WT")" ]
step "worktree list 에 경로가 없다"     bash -c '! git -C "$1" worktree list --porcelain | grep -qxF "worktree $2"' _ "$CLONE" "$WT"
step "디렉토리도 없다"                  [ ! -e "$WT" ]
step "브랜치 worktree-<id> 가 없다"     bash -c '! git -C "$1" show-ref --verify --quiet "refs/heads/worktree-$2"' _ "$CLONE" "$BEAD"
step "마커가 없다"                      [ ! -e "$MARKER" ]
step "클론은 남아 있다"                 is_repo "$CLONE"

exit $fail
