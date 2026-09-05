#!/usr/bin/env bash
# scripts/repo.sh 의 클론 루트 층 플러그인 적용(apply)을 고정하는 게이트.
#   ① apply r → rc=0 · <클론루트>/.harness-root == 하네스 루트 · settings.local.json 의
#      enabledPlugins["harness@skills"]==true · 클론 exclude 에 .claude/settings.local.json 행 1
#   ② 기존 settings.local.json 의 다른 키가 보존된다 · 재실행해도 exclude 행은 1 (멱등)
#   ③ .harness-root 가 다른 경로를 담고 있으면 rc≠0 이고 stderr 에 두 경로가 모두 있다 (덮어쓰지 않는다)
#   ④ list 에 플러그인 행과 하네스 루트 행이 있다
#   ⑤ claude 가 PATH 에 없어 설치가 실패해도 rc=0 이고 stderr 가 --plugin-dir 를 든다 — 설치 실패는 적용 실패가 아니다
#   ⑥ 가짜 claude(인자를 기록하고 정해진 rc 를 내는 shim)로: 설치가 성공하면 인자에 --scope local 이 있고
#      <클론>/.claude/settings.json 을 만들지 않으며 settings.local.json 도 직접 쓰지 않는다(install 의 몫);
#      설치가 rc=1 이면 ⑤ 와 같이 rc=0 · settings.local.json 에 플러그인 켜짐 · stderr 에 --plugin-dir
# 가짜 하네스 루트(HARNESS_ROOT — .beads/embeddeddolt 뼈대와 repos.json)와 가짜 클론 루트
# (HARNESS_CLONE_ROOT)로만 돈다 — 실제 ~/.harness-workspace 도 실제 원장도 건드리지 않는다.
# PATH 를 /usr/bin:/bin 으로 좁혀 claude 를 뺀다 — 진짜 설치가 이 검사의 부작용이 되지 않게 (⑤ 의 입력이기도 하다).
set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

HROOT="$TMP/hroot"
export HARNESS_ROOT="$HROOT" HARNESS_CLONE_ROOT="$TMP/clones"
mkdir -p "$HROOT/.beads/embeddeddolt" "$HARNESS_CLONE_ROOT"
jq -n '{repos: [{name: "r", url: "unused", default_branch: "main", check: "true", bootstrap: ""}]}' > "$HROOT/repos.json"
git init -q "$HARNESS_CLONE_ROOT/r"
CLONE="$HARNESS_CLONE_ROOT/r"
SETTINGS="$CLONE/.claude/settings.local.json"
ERRF="$TMP/err.txt"

run() { PATH=/usr/bin:/bin bash "$PLUGIN_ROOT/scripts/repo.sh" "$@"; }

fail=0
step() {
  local label="$1"; shift
  if "$@"; then echo "  ✓ ${label}"; else echo "  ✗ FAILED: ${label}"; fail=1; fi
}
has_text() { case "$2" in *"$1"*) return 0;; *) return 1;; esac; }
jq_true() { jq -e "$1" "$2" >/dev/null; }

echo "── ① apply ──"
run apply r >/dev/null 2>"$ERRF"; rc=$?
step "rc=0"                                  [ "$rc" -eq 0 ]
step ".harness-root == 하네스 루트"           [ "$(cat "$HARNESS_CLONE_ROOT/.harness-root" 2>/dev/null)" = "$HROOT" ]
step "settings.local.json 에 플러그인 켜짐"   jq_true '.enabledPlugins["harness@skills"] == true' "$SETTINGS"
step "exclude 에 settings.local.json 행 1"    [ "$(grep -cxF .claude/settings.local.json "$CLONE/.git/info/exclude")" = "1" ]

echo "── ② 기존 키 보존 · 멱등 ──"
printf '%s\n' '{"permissions":{"allow":["x"]}}' > "$SETTINGS"
run apply r >/dev/null 2>&1; rc=$?
step "rc=0"                                  [ "$rc" -eq 0 ]
step "permissions.allow[0]==x 보존"           jq_true '.permissions.allow[0] == "x"' "$SETTINGS"
step "플러그인도 켜짐"                        jq_true '.enabledPlugins["harness@skills"] == true' "$SETTINGS"
step "exclude 행은 여전히 1"                  [ "$(grep -cxF .claude/settings.local.json "$CLONE/.git/info/exclude")" = "1" ]

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
step "플러그인 행"                            has_text "플러그인: harness@skills 켜짐" "$OUT"
step "하네스 루트 행"                         has_text "하네스 루트: $HROOT" "$OUT"

echo "── ⑤ 설치 실패는 적용 실패가 아니다 ──"
run apply r >/dev/null 2>"$ERRF"; rc=$?
step "claude 없는 PATH 에서 rc=0"             [ "$rc" -eq 0 ]
step "stderr 가 --plugin-dir 를 든다"         has_text "--plugin-dir" "$(cat "$ERRF")"

echo "── ⑥ 가짜 claude — 성공 시 --scope local · 추적 settings.json 을 만들지 않는다 ──"
SHIM_DIR="$TMP/bin"; ARGS="$TMP/claude-args.txt"
mkdir -p "$SHIM_DIR"
cat > "$SHIM_DIR/claude" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$ARGS"
exit "\${CLAUDE_SHIM_RC:-0}"
EOF
chmod +x "$SHIM_DIR/claude"
run_shim() { PATH="$SHIM_DIR:/usr/bin:/bin" CLAUDE_SHIM_RC="$1" bash "$PLUGIN_ROOT/scripts/repo.sh" "${@:2}"; }
rm -f "$SETTINGS"
run_shim 0 apply r >/dev/null 2>"$ERRF"; rc=$?
step "rc=0"                                  [ "$rc" -eq 0 ]
step "shim 이 받은 인자에 --scope local"       has_text "--scope local" "$(cat "$ARGS" 2>/dev/null)"
step "<클론>/.claude/settings.json 이 없다"    test ! -e "$CLONE/.claude/settings.json"
step "settings.local.json 도 직접 쓰지 않았다" test ! -e "$SETTINGS"
run_shim 1 apply r >/dev/null 2>"$ERRF"; rc=$?
step "설치 rc=1 이어도 rc=0"                  [ "$rc" -eq 0 ]
step "폴백이 settings.local.json 에 켜 둔다"   jq_true '.enabledPlugins["harness@skills"] == true' "$SETTINGS"
step "stderr 가 --plugin-dir 를 든다"         has_text "--plugin-dir" "$(cat "$ERRF")"

exit $fail
