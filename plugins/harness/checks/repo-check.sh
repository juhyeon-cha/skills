#!/usr/bin/env bash
# scripts/repo.sh 의 클론 루트 층(apply)을 고정하는 게이트.
#   ① apply r → rc=0 · <클론루트>/.harness-root == 하네스 루트 · 재실행해도 rc=0 (멱등)
#   ② 클론의 .claude/ 아래를 쓰지 않는다 — 플러그인은 user scope 로 한 번 설치되므로 클론에 등록이 없다:
#      이미 있던 .claude/settings.local.json 의 내용이 apply 전후로 같고 .claude/settings.json 도 생기지 않는다
#   ③ .harness-root 가 다른 경로를 담고 있으면 rc≠0 이고 stderr 에 두 경로가 모두 있다 (덮어쓰지 않는다)
#   ④ list 에 하네스 루트 행이 있고 플러그인 행은 없다
# 가짜 하네스 루트(HARNESS_ROOT — 판별자 ledger.json 과 repos.json)와 가짜 클론 루트
# (HARNESS_CLONE_ROOT)로만 돈다 — 실제 ~/.harness-workspace 도 실제 원장도 건드리지 않는다.
# PATH 를 /usr/bin:/bin 으로 좁혀 claude 를 뺀다 — repo.sh 가 claude 를 부르지 않는다는 것도 이 PATH 에서 드러난다.
set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

HROOT="$TMP/hroot"
export HARNESS_ROOT="$HROOT" HARNESS_CLONE_ROOT="$TMP/clones"
mkdir -p "$HROOT" "$HARNESS_CLONE_ROOT" && printf '{"backend":"beads"}\n' > "$HROOT/ledger.json"
jq -n '{repos: [{name: "r", url: "unused", default_branch: "main", check: "true", bootstrap: ""}]}' > "$HROOT/repos.json"
git init -q "$HARNESS_CLONE_ROOT/r"
CLONE="$HARNESS_CLONE_ROOT/r"
LOCAL_SETTINGS="$CLONE/.claude/settings.local.json"
ERRF="$TMP/err.txt"

run() { PATH=/usr/bin:/bin bash "$PLUGIN_ROOT/scripts/repo.sh" "$@"; }

fail=0
step() {
  local label="$1"; shift
  if "$@"; then echo "  ✓ ${label}"; else echo "  ✗ FAILED: ${label}"; fail=1; fi
}
has_text() { case "$2" in *"$1"*) return 0;; *) return 1;; esac; }
lacks_text() { ! has_text "$1" "$2"; }

echo "── ① apply ──"
run apply r >/dev/null 2>"$ERRF"; rc=$?
step "rc=0"                                  [ "$rc" -eq 0 ]
step ".harness-root == 하네스 루트"           [ "$(cat "$HARNESS_CLONE_ROOT/.harness-root" 2>/dev/null)" = "$HROOT" ]
run apply r >/dev/null 2>&1; rc=$?
step "재실행 rc=0"                            [ "$rc" -eq 0 ]

echo "── ② 클론의 .claude/ 를 쓰지 않는다 ──"
mkdir -p "$(dirname "$LOCAL_SETTINGS")"
SEED='{"permissions":{"allow":["x"]}}'
printf '%s\n' "$SEED" > "$LOCAL_SETTINGS"
run apply r >/dev/null 2>&1; rc=$?
step "rc=0"                                  [ "$rc" -eq 0 ]
step "기존 settings.local.json 내용 동일"      [ "$(cat "$LOCAL_SETTINGS")" = "$SEED" ]
step "<클론>/.claude/settings.json 이 없다"    test ! -e "$CLONE/.claude/settings.json"

echo "── ③ .harness-root 가 다른 경로 ──"
printf '%s\n' "$TMP/other-root" > "$HARNESS_CLONE_ROOT/.harness-root"
run apply r >/dev/null 2>"$ERRF"; rc=$?
step "rc≠0"                                  [ "$rc" -ne 0 ]
step "stderr 에 기존 경로"                    has_text "$TMP/other-root" "$(cat "$ERRF")"
step "stderr 에 지금 루트"                    has_text "$HROOT" "$(cat "$ERRF")"
step "덮어쓰지 않았다"                        [ "$(cat "$HARNESS_CLONE_ROOT/.harness-root")" = "$TMP/other-root" ]
printf '%s\n' "$HROOT" > "$HARNESS_CLONE_ROOT/.harness-root"

echo "── ④ list ──"
OUT=$(run list 2>/dev/null)
step "하네스 루트 행"                         has_text "하네스 루트: $HROOT" "$OUT"
step "플러그인 행 없음"                       lacks_text "플러그인:" "$OUT"

exit $fail
