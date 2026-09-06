#!/usr/bin/env bash
# scripts/repo.sh 의 클론 루트 층(apply)을 고정하는 게이트.
#   ① apply r → rc=0 · <클론루트>/.harness-root == 하네스 루트 · 재실행해도 rc=0 (멱등)
#   ② 클론의 .claude/ 아래를 쓰지 않는다 — 플러그인은 user scope 로 한 번 설치되므로 클론에 등록이 없다:
#      이미 있던 .claude/settings.local.json 의 내용이 apply 전후로 같고 .claude/settings.json 도 생기지 않는다
#   ③ .harness-root 가 다른 경로를 담고 있으면 rc≠0 이고 stderr 에 두 경로가 모두 있다 (덮어쓰지 않는다)
#   ④ list 에 하네스 루트 행이 있고 플러그인 행은 없다
#   ⑤ 게이트 명령의 출처는 클론의 .harness.json 이다 — 있으면 check 가 그 값이고, 없으면 rc≠0 이고
#      stderr 가 그 경로를 든다 (등록부의 값으로 폴백하지 않는다)
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
# 등록부는 **클론 루트 직속**이다. 하네스 루트에는 옛 자리 파일을 일부러 남겨 둔다 — 새 코드가
# 그것을 읽으면 아래 ⑥ 이 떨어진다(두 자리를 다 읽으면 어느 쪽이 원본인지 흐려진다).
jq -n '{repos: [{name: "r", url: "unused"}]}' > "$HARNESS_CLONE_ROOT/repos.json"
jq -n '{repos: [{name: "옛자리", url: "읽으면-안-된다"}]}' > "$HROOT/repos.json"
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

echo "── ⑤ 게이트 명령의 출처는 클론의 .harness.json ──"
# 파일이 없는 상태가 먼저다 — 등록부에 값이 없으므로 폴백할 자리도 없다는 것을 여기서 못박는다.
OUT=$(run check r 2>"$ERRF"); rc=$?
step "파일 없음 → rc≠0"                       [ "$rc" -ne 0 ]
step "파일 없음 → stderr 가 그 경로를 든다"    has_text "$CLONE/.harness.json" "$(cat "$ERRF")"
step "파일 없음 → stdout 에 게이트 명령이 없다" [ -z "$OUT" ]
step "list 도 그 부재를 드러낸다"              has_text "$CLONE/.harness.json 없음" "$(run list 2>/dev/null)"
printf '{"check":"bash scripts/gate.sh","default_branch":"trunk"}\n' > "$CLONE/.harness.json"
OUT=$(run check r 2>"$ERRF"); rc=$?
step "파일 있음 → rc=0"                       [ "$rc" -eq 0 ]
step "파일 있음 → check 값 그대로"             [ "$OUT" = "bash scripts/gate.sh" ]
step "list 의 check·브랜치가 그 파일 값이다"   bash -c 'case "$1" in *"check: bash scripts/gate.sh"*) case "$1" in *"브랜치: trunk"*) exit 0;; esac;; esac; exit 1' _ "$(run list 2>/dev/null)"
printf '{"check":""}\n' > "$CLONE/.harness.json"
OUT=$(run check r 2>"$ERRF"); rc=$?
step "check 가 빈 값 → rc≠0 (빈 게이트를 통과로 읽지 않는다)" [ "$rc" -ne 0 ]

echo "── ⑥ 등록부의 자리는 클론 루트 직속 ──"
OUT=$(run list 2>/dev/null)
step "클론 루트 직속 등록부의 항목을 낸다"      has_text "url:   unused" "$OUT"
step "하네스 루트의 옛 파일을 읽지 않는다"      lacks_text "읽으면-안-된다" "$OUT"

echo "── ⑦ url 파생 ──"
# url 이 비면 원장의 owner 와 이름으로 파생한다. owner 도 없으면 죽는다 — 클론할 곳을 모르는 채로
# 진행하면 restore 가 조용히 아무것도 하지 않는다.
jq -n '{repos: [{name: "r", url: ""}]}' > "$HARNESS_CLONE_ROOT/repos.json"
printf '{"backend":"beads"}\n' > "$HROOT/ledger.json"
OUT=$(run list 2>/dev/null)
step "url 이 비고 owner 도 없다 → list 가 그 사실을 드러낸다" has_text "url 도 owner 도 없다" "$OUT"
rm -rf "${HARNESS_CLONE_ROOT:?}/r"
run restore r >/dev/null 2>"$ERRF"; rc=$?
step "url 도 owner 도 없는 restore → rc≠0"     [ "$rc" -ne 0 ]
step "그 stderr 가 url 과 owner 를 함께 든다"   bash -c 'case "$1" in *url*) case "$1" in *owner*) exit 0;; esac;; esac; exit 1' _ "$(cat "$ERRF")"
printf '{"backend":"beads","owner":"fx-owner"}\n' > "$HROOT/ledger.json"
OUT=$(run list 2>/dev/null)
step "owner 가 있으면 url 을 owner/name 으로 파생한다" \
  has_text "url:   https://github.com/fx-owner/r.git" "$OUT"

exit $fail
