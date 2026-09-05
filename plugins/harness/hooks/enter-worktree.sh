#!/usr/bin/env bash
# 워크트리 원장 배선 — PostToolUse(EnterWorktree) 훅.
#
# EnterWorktree 가 만든(또는 path 로 들어간) 스토리 워크트리에 하네스 원장을 배선한다. 생성은
# 네이티브 도구의 몫이고 하네스 쪽에는 배선만 남는다(스토리 harness-lzs3 "결정됨": 대상 레포의
# EnterWorktree 훅이 부트스트랩을 소유하고, 플러그인 훅은 .beads/redirect 만 쓴다. repos.json 의
# bootstrap 은 그 훅이 없는 레포의 폴백이다). 정리는 scripts/workspace-cleanup.sh 가 대칭으로 한다.
#
# 하는 일 셋 — 전부 멱등이다:
#   ① <워크트리>/.beads/redirect 에 <하네스루트>/.beads 절대 경로를 쓴다. 이것이 없으면 워크트리의
#      bare bd 가 "bd init 으로 새 DB 를 만들라" 고 권하고, 따르면 원장이 이원화된다.
#   ② 클론의 .git/info/exclude 에 `.beads` 와 `.claude/worktrees/` 를 재보장한다 — 대상 레포는 그
#      이름을 gitignore 하지 않으므로 등재하지 않으면 워크트리 git status 에 뜬다. 통짜 `.beads` 라
#      추적 중인 파일(하네스 자신의 원장 뼈대)에는 닿지 않는다.
#   ③ 대상 레포에 자기 EnterWorktree 훅이 없으면 repos.json 의 bootstrap 을 1회 돌린다. 마커는
#      워크트리 밖 형제 파일(<클론>/.claude/worktrees/.bootstrapped-<이름>)이다 — 워크트리 안에 두면
#      대상 레포 체크아웃에 untracked 로 뜬다. 마커는 scripts/workspace-cleanup.sh 가 지운다.
#
# 페이로드 (실측 2026-09-05, claude -p, PostToolUse EnterWorktree): `cwd` 가 워크트리 절대 경로이고
# `tool_response.worktreePath`·`tool_response.worktreeBranch` 도 실린다. name=X 로 만들면 경로가
# <클론>/.claude/worktrees/X, 브랜치가 worktree-X 다. 판정은 cwd 하나로 한다 — path 로 기존
# 워크트리에 들어간 호출도 cwd 는 같은 자리다.
#
# 하네스 루트는 lib/harness-root.sh 가 낸다 — **워크트리를 CWD 로** 부른다(재진입이면 이미 있는
# redirect 를 따라가고, 첫 진입이면 ${HARNESS_CLONE_ROOT:-~/.harness-workspace}/.harness-root 또는
# HARNESS_ROOT 다). 못 찾으면 exit 2 와 stderr 의 "원장 배선 실패". PostToolUse 는 도구 실행 뒤라 훅 실패가
# 도구 호출을 막지 않고, exit 2 의 stderr 만 Claude 의 응답에 실린다(exit 1 은 사용자에게만 간다) —
# 그래서 실패 출구는 전부 exit 2 이고 그 문구가 유일한 신호다. 조용히 통과하지 않는다.
#
# cwd 가 `*/.claude/worktrees/*` 밖이면 아무것도 만들지 않고 rc=0 — 우리 워크트리가 아니다.
set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
say() { echo "[enter-worktree] $*" >&2; }
fail() { say "원장 배선 실패 — $*"; exit 2; }

command -v jq >/dev/null 2>&1 || fail "jq 가 없다 (페이로드를 읽을 수 없다)"
payload="$(cat)"
wt="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$wt" ] || fail "페이로드에 cwd 가 없다"

case "$wt" in
  */.claude/worktrees/*) ;;
  *) exit 0 ;;   # 우리 워크트리가 아니다 — 정상 출구
esac
[ -d "$wt" ] || fail "cwd 가 실재하지 않는다: $wt"

main="${wt%%/.claude/worktrees/*}"          # 워크트리를 소유한 클론(본 체크아웃)
rest="${wt#*/.claude/worktrees/}"
wtname="${rest%%/*}"                          # .claude/worktrees/ 바로 아래 한 칸 = 스토리 ID
repo="${main##*/}"                            # 클론 디렉토리 이름 = repos.json 의 name

# ① 원장 배선
ROOT="$(cd "$wt" && bash "$PLUGIN_ROOT/lib/harness-root.sh")" || fail "하네스 루트를 찾지 못했다 (워크트리 $wt). HARNESS_ROOT 를 지정하거나 ${HARNESS_CLONE_ROOT:-$HOME/.harness-workspace}/.harness-root 를 두라 (scripts/repo.sh 가 쓴다)"
LEDGER="$ROOT/.beads"
mkdir -p "$wt/.beads" && printf '%s\n' "$LEDGER" > "$wt/.beads/redirect" || fail "$wt/.beads/redirect 를 쓸 수 없다"
say "원장 배선: $wt/.beads/redirect → $LEDGER"

# ② 클론의 로컬 제외 목록 (git 이 아니면 건너뛴다 — 배선은 이미 끝났다)
exclude_file="$(git -C "$main" rev-parse --git-path info/exclude 2>/dev/null)" || exclude_file=""
if [ -n "$exclude_file" ]; then
  [[ "$exclude_file" = /* ]] || exclude_file="$main/$exclude_file"
  mkdir -p "$(dirname "$exclude_file")" && touch "$exclude_file"
  for line in ".claude/worktrees/" ".beads"; do
    grep -qxF "$line" "$exclude_file" 2>/dev/null || printf '%s\n' "$line" >> "$exclude_file"
  done
fi

# ③ 부트스트랩 폴백 — 대상 레포가 자기 EnterWorktree 훅을 가지면 그쪽이 소유한다.
own_hook=0
for f in "$wt/.claude/settings.json" "$wt/.claude/settings.local.json"; do
  [ -f "$f" ] || continue
  jq -e '.hooks.PostToolUse[]? | select(.matcher == "EnterWorktree")' "$f" >/dev/null 2>&1 && own_hook=1
done
if [ "$own_hook" -eq 1 ]; then
  say "부트스트랩: 대상 레포의 EnterWorktree 훅이 소유한다 — repos.json 의 bootstrap 은 돌리지 않는다"
  exit 0
fi
MANIFEST="${REPOS_MANIFEST:-$ROOT/repos.json}"   # 재정의는 검사 스크립트용
[ -f "$MANIFEST" ] || { say "부트스트랩: $MANIFEST 이 없다 — 건너뛴다"; exit 0; }
cmd="$(jq -r --arg n "$repo" '.repos[] | select(.name == $n) | .bootstrap // ""' "$MANIFEST" 2>/dev/null || true)"
[ -n "$cmd" ] || exit 0
marker="$main/.claude/worktrees/.bootstrapped-$wtname"
if [ -f "$marker" ]; then
  say "부트스트랩: 마커가 있다 ($marker) — 건너뛴다"
  exit 0
fi
say "부트스트랩: $repo — $cmd"
if (cd "$wt" && bash -c "$cmd") >&2; then
  touch "$marker"
  exit 0
fi
say "부트스트랩 실패: '$repo' — 원장 배선은 끝났고 워크트리는 남는다. 원인 해결 후 EnterWorktree(path) 로 다시 들어가면 부트스트랩부터 재시도한다"
exit 2
