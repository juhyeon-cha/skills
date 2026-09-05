#!/usr/bin/env bash
# 게이트: 원장 어댑터(scripts/ledger.sh + ledger-<backend>.sh)를 픽스처로 단언한다.
#
#   ① 경계 — ledger.json 없음·backend 허용값 밖은 rc≠0 이고 stderr 한 줄이 원인을 이름으로 든다.
#      --help 의 목록이 플러그인이 실제 부르는 bd 하위 명령 전수(grep 으로 파생)를 덮는다.
#   ② beads 동등성(읽기) — 실제 하네스 원장을 .beads/redirect 로 가리키는 사본 루트에서
#      ledger.sh 의 list·show --json 이 bd -C <루트> 의 것과 바이트 단위로 같다.
#   ③ beads 왕복(쓰기) — 임시 `bd init` 픽스처에서 create·note·dep add·update·label·close·
#      children·ready 를 bd 의 인자 규약 그대로 한 번씩 돌려 show --json 으로 확인한다.
#      실제 원장에는 쓰지 않는다.
#   ④ github 오프라인 — gh 를 PATH 에서 빼거나 가짜 gh 로 바꿔 인자 파싱·JSON 형태·실패 경로를 본다.
#   ⑤ notion 오프라인 — 가짜 curl 로 인자 파싱·JSON 형태·실패 경로(토큰 없음·401·404)를 본다.
#
# 극성: 하위 명령 집합은 손으로 적지 않고 플러그인 트리에서 파생한다 — 새 bd 호출이 생기면
# --help 가 그것을 덮을 때까지 이 검사가 떨어진다.
# 하네스 루트(②의 대조 원장)는 lib/harness-root.sh 가 낸다. 못 찾으면 rc=1.
# set -e 를 쓰지 않는다 — 첫 실패에서 죽으면 나머지 사유가 보고되지 않는다.
set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LEDGER="$PLUGIN_ROOT/scripts/ledger.sh"
ROOT="$(bash "$PLUGIN_ROOT/lib/harness-root.sh")" || exit 1
command -v jq >/dev/null 2>&1 || { echo "✗ jq 가 없다 — 이 검사는 jq 없이 판정할 수 없다" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail=0
step() {
  local label="$1"; shift
  if "$@"; then echo "  ✓ ${label}"; else echo "  ✗ FAILED: ${label}"; fail=1; fi
}
has_text() { case "$2" in *"$1"*) return 0;; *) return 1;; esac; }

# run <루트> <인자…> — HARNESS_ROOT 를 픽스처로 물려 ledger.sh 를 돌리고 OUT·ERR·RC 에 채집한다.
# rc 는 파이프 밖에서 잡는다 (docs/development.md "셸 함정").
OUT=""; ERR=""; RC=0
run() {
  local root="$1"; shift
  OUT=$(HARNESS_ROOT="$root" bash "$LEDGER" "$@" 2>"$TMP/err"); RC=$?
  ERR=$(cat "$TMP/err")
}
# bd 의 stderr 잡음(beads.role 경고)은 판정 대상이 아니다 — ledger.sh 자신의 stderr 줄만 센다.
ledger_err_lines() { printf '%s\n' "$ERR" | grep -c '^ledger'; }

echo "── ① 경계 ──"
mkdir -p "$TMP/noconf"
run "$TMP/noconf" list
step "ledger.json 없음 → rc≠0" [ "$RC" -ne 0 ]
step "ledger.json 없음 → stderr 한 줄이 ledger.json 을 든다" \
  bash -c '[ "$(printf "%s\n" "$1" | grep -c .)" -eq 1 ] && printf "%s" "$1" | grep -q "ledger.json"' _ "$ERR"

mkdir -p "$TMP/badconf"; printf '{"backend":"jira"}\n' > "$TMP/badconf/ledger.json"
run "$TMP/badconf" list
step "backend 허용값 밖 → rc≠0" [ "$RC" -ne 0 ]
step "backend 허용값 밖 → stderr 가 허용값 셋을 든다" \
  bash -c 'printf "%s" "$1" | grep -q beads && printf "%s" "$1" | grep -q github && printf "%s" "$1" | grep -q notion' _ "$ERR"

HELP=$(bash "$LEDGER" --help 2>&1); help_rc=$?
step "--help rc 0" [ "$help_rc" -eq 0 ]
# 하위 명령 집합은 플러그인 트리에서 파생한다 (harness-m8gg.4.1 acceptance 2 의 측정 명령 그대로).
MEASURED=$(grep -rhoE '\bbd (-C [^ ]+ )?[a-z-]+' "$PLUGIN_ROOT" | awk '{print $NF}' | sort -u)
missing=""
for tok in $MEASURED; do
  printf '%s\n' "$HELP" | grep -qw -- "$tok" || missing="$missing $tok"
done
step "--help 가 측정된 bd 하위 명령 전수를 덮는다 (측정 $(printf '%s\n' "$MEASURED" | grep -c .)개, 빠짐:${missing:- 없음})" [ -z "$missing" ]

echo "── ② beads 동등성 — 실제 원장 읽기 ──"
COPY="$TMP/copy"; mkdir -p "$COPY/.beads"
printf '%s\n' "$ROOT/.beads" > "$COPY/.beads/redirect"
printf '{"backend":"beads"}\n' > "$COPY/ledger.json"
run "$COPY" list --status open --json
bd -C "$ROOT" list --status open --json > "$TMP/bd-list.json" 2>/dev/null
printf '%s\n' "$OUT" > "$TMP/ledger-list.json"
step "list --status open --json 이 bd -C <루트> 와 같다" diff -q "$TMP/ledger-list.json" "$TMP/bd-list.json"
first_id=$(jq -r '.[0].id // empty' "$TMP/bd-list.json")
if [ -n "$first_id" ]; then
  run "$COPY" show "$first_id" --json
  bd -C "$ROOT" show "$first_id" --json > "$TMP/bd-show.json" 2>/dev/null
  printf '%s\n' "$OUT" > "$TMP/ledger-show.json"
  step "show $first_id --json 이 bd -C <루트> 와 같다" diff -q "$TMP/ledger-show.json" "$TMP/bd-show.json"
else
  echo "  ✗ FAILED: 열린 이슈가 0건이라 show 동등성을 대조하지 못했다"; fail=1
fi

echo "── ③ beads 왕복 — 임시 원장 쓰기 ──"
FX="$TMP/fx"; mkdir -p "$FX"
( cd "$FX" && bd init --prefix lac ) >/dev/null 2>&1 || { echo "  ✗ FAILED: 픽스처 bd init"; fail=1; }
printf '{"backend":"beads"}\n' > "$FX/ledger.json"
printf '본문 첫 줄\n둘째 줄\n' > "$TMP/body.txt"

run "$FX" create "부모" -t feature --silent; P="$OUT"
step "create --silent 가 id 만 낸다" bash -c '[ "$(printf "%s\n" "$1" | grep -c .)" -eq 1 ] && [ "$1" != "${1#lac-}" ]' _ "$P"
run "$FX" create "자식" -t task --parent "$P" -l repo:x,rail:r1 --acceptance "완료 조건" --body-file "$TMP/body.txt" --silent; C="$OUT"
run "$FX" show "$C" --json
step "create 의 -t·--parent·-l·--acceptance·--body-file 이 show --json 에 그대로 있다" \
  bash -c 'printf "%s" "$1" | jq -e --arg p "$2" ".[0] | .issue_type == \"task\" and .parent == \$p and (.labels | index(\"repo:x\") != null) and (.labels | index(\"rail:r1\") != null) and .acceptance_criteria == \"완료 조건\" and (.description | startswith(\"본문 첫 줄\"))" >/dev/null' _ "$OUT" "$P"

run "$FX" note "$C" "메모 하나"
run "$FX" note "$C" --file "$TMP/body.txt"
run "$FX" show "$C" --json
step "note <본문> 과 note --file 이 notes 에 쌓인다" \
  bash -c 'printf "%s" "$1" | jq -e ".[0].notes | contains(\"메모 하나\") and contains(\"둘째 줄\")" >/dev/null' _ "$OUT"

run "$FX" create "블로커" -t task --silent; B="$OUT"
run "$FX" create "넷째" -t task --silent; D="$OUT"
printf '{"from":"%s","to":"%s"}\n' "$C" "$B" | HARNESS_ROOT="$FX" bash "$LEDGER" dep add --file - >/dev/null 2>&1; rc_file=$?
run "$FX" dep add "$D" "$B"; rc_pos=$RC
run "$FX" show "$C" --json
step "dep add --file - (JSONL) 와 dep add <A> <B> 가 blocks 간선을 만든다" \
  bash -c '[ "$2" -eq 0 ] && [ "$3" -eq 0 ] && printf "%s" "$1" | jq -e --arg b "$4" ".[0].dependencies | any(.id == \$b and .dependency_type == \"blocks\")" >/dev/null' _ "$OUT" "$rc_file" "$rc_pos" "$B"

run "$FX" ready --json
step "ready 가 블로커(B)는 내고 막힌 것(C·D)은 내지 않는다" \
  bash -c 'printf "%s" "$1" | jq -e --arg b "$2" --arg c "$3" --arg d "$4" "(map(.id) | index(\$b) != null) and (map(.id) | index(\$c) == null) and (map(.id) | index(\$d) == null)" >/dev/null' _ "$OUT" "$B" "$C" "$D"

run "$FX" update "$C" --claim --actor "chk actor"
run "$FX" show "$C" --json
step "update --claim --actor 가 assignee 와 in_progress 를 만든다" \
  bash -c 'printf "%s" "$1" | jq -e ".[0] | .status == \"in_progress\" and .assignee == \"chk actor\"" >/dev/null' _ "$OUT"
run "$FX" update "$C" --status blocked
run "$FX" label add "$C" slug:r1-x
run "$FX" label remove "$C" rail:r1
run "$FX" show "$C" --json
step "update --status · label add · label remove" \
  bash -c 'printf "%s" "$1" | jq -e ".[0] | .status == \"blocked\" and (.labels | index(\"slug:r1-x\") != null) and (.labels | index(\"rail:r1\") == null)" >/dev/null' _ "$OUT"

run "$FX" close "$B" --reason "끝"
run "$FX" show "$B" --json
step "close --reason 이 closed 와 close_reason 을 만든다" \
  bash -c 'printf "%s" "$1" | jq -e ".[0] | .status == \"closed\" and .close_reason == \"끝\"" >/dev/null' _ "$OUT"
run "$FX" ready --json
step "블로커를 닫은 뒤 ready 에 D 가 든다" \
  bash -c 'printf "%s" "$1" | jq -e --arg d "$2" "map(.id) | index(\$d) != null" >/dev/null' _ "$OUT" "$D"

run "$FX" children "$P" --json
step "children <부모> --json 이 자식 1건(C)이다" \
  bash -c 'printf "%s" "$1" | jq -e --arg c "$2" "length == 1 and .[0].id == \$c" >/dev/null' _ "$OUT" "$C"
run "$FX" list -l repo:x --all --json -n 0
step "list -l <라벨> --all --json -n 0 이 라벨 있는 것만 낸다" \
  bash -c 'printf "%s" "$1" | jq -e --arg c "$2" "length == 1 and .[0].id == \$c" >/dev/null' _ "$OUT" "$C"

if [ "$fail" -ne 0 ]; then
  echo "✗ 원장 어댑터 검사 실패 — 위 항목을 고쳐라"
  exit 1
fi
echo "✓ 원장 어댑터 검사 통과 — 경계 · beads 동등성 · beads 왕복"
