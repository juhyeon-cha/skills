#!/usr/bin/env bash
# 게이트: 원장 어댑터(scripts/ledger.sh + ledger-<backend>.sh)를 픽스처로 단언한다.
#
#   ① 경계 — .harness.json 없음·backend 허용값 밖은 rc≠0 이고 stderr 한 줄이 원인을 이름으로 든다.
#      --help 의 목록이 플러그인이 실제 부르는 bd 하위 명령 전수(grep 으로 파생)를 덮는다.
#      세 백엔드의 has-ui 답(UI 이름 한 줄 / 빈 출력)이 원장에 닿지 않고 나온다 — 어댑터의 계약이다.
#   ② beads 동등성(읽기) — 실제 하네스 원장을 .beads/redirect 로 가리키는 사본 루트에서
#      ledger.sh 의 list·show --json 이 bd -C <루트> 의 것과 바이트 단위로 같다.
#      **backend 가 beads 일 때만 돈다.** 그 밖의 백엔드에서는 대조할 bd 원장이 루트에 없으므로
#      사유 한 줄(⊘)과 함께 건너뛴다 — 조용한 통과가 아니라 명시적 건너뜀이다.
#   ③ beads 왕복(쓰기) — 임시 `bd init` 픽스처에서 create·note·dep add·update·label·close·
#      children·ready 를 bd 의 인자 규약 그대로 한 번씩 돌려 show --json 으로 확인한다.
#      실제 원장에는 쓰지 않는다.
#   ④ github 오프라인 — gh 를 PATH 에서 빼거나 가짜 gh 로 바꿔 인자 파싱·JSON 형태·실패 경로를 본다.
#      실제 GitHub 에 닿는 쓰기 실증은 오케스트레이터가 실증 레포에서 돈다(harness-m8gg.4.2 acceptance 4).
#   ⑤ notion 오프라인 — 가짜 curl 로 인자 파싱·요청 본문·JSON 형태·실패 경로(토큰 없음·401·404)를 본다.
#      실제 Notion 에 닿는 쓰기 실증은 오케스트레이터가 실증 DB 에서 돈다(harness-m8gg.4.3 acceptance 3).
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
BACKEND="$(jq -r '.ledger.backend // empty' "$ROOT/.harness.json" 2>/dev/null)"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail=0
step() {
  local label="$1"; shift
  if "$@"; then echo "  ✓ ${label}"; else echo "  ✗ FAILED: ${label}"; fail=1; fi
}
has_text() { case "$2" in *"$1"*) return 0;; *) return 1;; esac; }

# run <루트> <인자…> — HARNESS_ROOT 를 픽스처로 물려 ledger.sh 를 돌리고 OUT·ERR·RC 에 채집한다.
# rc 는 파이프 밖에서 잡는다 (../docs/development.md "Shell traps").
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
step ".harness.json 없음 → rc≠0" [ "$RC" -ne 0 ]
step ".harness.json 없음 → stderr 한 줄이 .harness.json 을 든다" \
  bash -c '[ "$(printf "%s\n" "$1" | grep -c .)" -eq 1 ] && printf "%s" "$1" | grep -q ".harness.json"' _ "$ERR"

mkdir -p "$TMP/badconf"; printf '{"ledger":{"backend":"jira"}}\n' > "$TMP/badconf/.harness.json"
run "$TMP/badconf" list
step "backend 허용값 밖 → rc≠0" [ "$RC" -ne 0 ]
step "backend 허용값 밖 → stderr 가 허용값 셋을 든다" \
  bash -c 'printf "%s" "$1" | grep -q beads && printf "%s" "$1" | grep -q github && printf "%s" "$1" | grep -q notion' _ "$ERR"

HELP=$(bash "$LEDGER" --help 2>&1); help_rc=$?
step "--help rc 0" [ "$help_rc" -eq 0 ]
# 하위 명령 집합은 플러그인 트리에서 파생한다 (harness-m8gg.4.1 acceptance 2 의 측정 명령 그대로).
# CHANGELOG.md 와 docs/ 는 뺀다 — 둘 다 호출 자리가 아니라 사람이 읽는 기록·설명이다. CHANGELOG 는 걷어낸 명령의
# 이름을 들고, docs/(harness-m8gg.8.11 로 옮겨온 다섯 문서)는 산문 안의 명령 인용(prime·doctor·pick)과 "-C <root>`) are" 같은
# 문장 조각이 하위 명령으로 잡힌다(실측: 옮긴 직후 빠짐 6개 — are block byte doctor pick prime. 이 주석 자신이 그 형태를
# 인용해도 잡히므로 여기서는 명령 이름 앞에 실행 파일 이름을 붙이지 않는다).
MEASURED=$(grep -rhoE --exclude=CHANGELOG.md --exclude-dir=docs '\bbd (-C [^ ]+ )?[a-z-]+' "$PLUGIN_ROOT" | awk '{print $NF}' | sort -u)
missing=""
for tok in $MEASURED; do
  printf '%s\n' "$HELP" | grep -qw -- "$tok" || missing="$missing $tok"
done
step "--help 가 스프린트 등재 하위 명령을 든다 (sprint-add <YYYY-SNN> · 세 백엔드가 같은 인자)" \
  bash -c 'printf "%s" "$1" | grep -q "sprint-add <YYYY-SNN>"' _ "$HELP"
step "--help 가 측정된 bd 하위 명령 전수를 덮는다 (측정 $(printf '%s\n' "$MEASURED" | grep -c .)개, 빠짐:${missing:- 없음})" [ -z "$missing" ]

# ── has-ui 계약 (skills#152) ──────────────────────────────────────────
# scripts/board.sh 는 이 하위 명령의 답 하나로 렌더 여부를 정한다. 그래서 세 백엔드가 여기에
# 무엇을 답하는지가 어댑터의 계약이고, 답이 조용히 바뀌면 투영이 조용히 사라지거나 되살아난다.
# 계약: UI 를 갖는 백엔드는 그 UI 이름을 stdout 한 줄로 내고, 갖지 않는 백엔드는 아무것도 내지
# 않는다. **둘 다 rc 0 이고, rc≠0 은 "없다" 가 아니라 "답하지 못했다" 다** — board.sh 가 rc≠0 에서
# 그리지 않고 멈추는 근거가 이 줄이다.
# 극성: 가짜 gh·curl·bd 를 PATH 앞에 세워 **원장에 닿는 순간 rc≠0 · stderr 가 생기게** 한다.
# 그래서 "gh 검사·토큰 검사보다 앞의 상수" 라는 성질 자체가 판정 대상이다. 픽스처의 .harness.json 은
# owner·database_id 도 비워 둔다 — 그 검사보다도 앞이어야 통과한다.
UIBIN="$TMP/uibin"; mkdir -p "$UIBIN"
for c in gh curl bd; do
  printf '#!/bin/sh\necho "원장에 닿았다: %s" >&2\nexit 9\n' "$c" > "$UIBIN/$c"
  chmod +x "$UIBIN/$c"
done
has_ui() {  # has_ui <backend> — 그 backend 만 적힌 .harness.json 픽스처에서 has-ui 를 돌린다
  local root="$TMP/ui-$1"
  mkdir -p "$root"; printf '{"ledger":{"backend":"%s"}}\n' "$1" > "$root/.harness.json"
  OUT=$(env -u NOTION_TOKEN PATH="$UIBIN:$PATH" HARNESS_ROOT="$root" bash "$LEDGER" has-ui 2>"$TMP/err"); RC=$?
  ERR=$(cat "$TMP/err")
}
one_line() { [ "$(printf '%s\n' "$1" | grep -c .)" -eq 1 ]; }

has_ui beads
step "has-ui beads: rc 0 · 빈 출력(UI 없음) · 원장(bd)에 닿지 않는다" \
  bash -c '[ "$1" -eq 0 ] && [ -z "$2" ] && [ -z "$3" ]' _ "$RC" "$OUT" "$ERR"
has_ui github
step "has-ui github: rc 0 · UI 이름 한 줄 · owner·gh 검사보다 앞이다 (원장에 닿지 않는다)" \
  bash -c '[ "$1" -eq 0 ] && [ -z "$3" ]' _ "$RC" "$OUT" "$ERR"
step "has-ui github: 출력이 정확히 한 줄이다" one_line "$OUT"
has_ui notion
step "has-ui notion: rc 0 · UI 이름 한 줄 · NOTION_TOKEN·curl 검사보다 앞이다 (원장에 닿지 않는다)" \
  bash -c '[ "$1" -eq 0 ] && [ -z "$3" ]' _ "$RC" "$OUT" "$ERR"
step "has-ui notion: 출력이 정확히 한 줄이다" one_line "$OUT"

# 마감 판정 줄(맨 아래)이 이 라벨을 그대로 쓴다 — 건너뛴 절이 통과 항목으로 열거되면
# 게이트가 꺼진 상태와 통과한 상태가 같은 문장으로 보인다.
if [ "$BACKEND" = beads ]; then
EQUIV_LABEL="beads 동등성"
echo "── ② beads 동등성 — 실제 원장 읽기 ──"
COPY="$TMP/copy"; mkdir -p "$COPY/.beads"
# 대조 루트 자신이 redirect 로 배선된 사본 루트일 수 있다(HARNESS_ROOT 로 물린 검사 픽스처). bd 는 redirect
# 사슬을 거부하므로("redirect chains not allowed", bd 1.2.2 실측) 한 홉을 여기서 풀어 실제 원장 디렉토리를 쓴다.
LEDGER_DIR="$ROOT/.beads"
[ -r "$LEDGER_DIR/redirect" ] && LEDGER_DIR="$(head -1 "$LEDGER_DIR/redirect")"
printf '%s\n' "$LEDGER_DIR" > "$COPY/.beads/redirect"
printf '{"ledger":{"backend":"beads"}}\n' > "$COPY/.harness.json"
# 이 어댑터가 bd 에 더하는 것은 actor 키 하나뿐이다(harness-kw0l.3.1 — 어댑터의 계약). 그래서
# 동등성은 **actor 를 뺀 뒤** 대조하고, actor 자체는 바로 아래에서 따로 단언한다. 두 단언을 하나로
# 합치면 어느 쪽이 깨졌는지가 diff 한 줄에 묻힌다.
run "$COPY" list --status open --json
bd -C "$ROOT" list --status open --json | jq 'map(del(.actor))' > "$TMP/bd-list.json" 2>/dev/null
printf '%s\n' "$OUT" > "$TMP/ledger-list.json"
jq 'map(del(.actor))' "$TMP/ledger-list.json" > "$TMP/ledger-list-noactor.json"
step "list --status open --json 이 actor 를 뺀 채로 bd -C <루트> 와 같다" diff -q "$TMP/ledger-list-noactor.json" "$TMP/bd-list.json"
step "actor 키가 모든 항목에 있고 값이 assignee 다 (bd 가 빼는 빈 assignee 는 null)" \
  bash -c 'jq -e "length > 0 and all(has(\"actor\") and .actor == (.assignee // null))" "$1" >/dev/null' _ "$TMP/ledger-list.json"
first_id=$(jq -r '.[0].id // empty' "$TMP/bd-list.json")
if [ -n "$first_id" ]; then
  run "$COPY" show "$first_id" --json
  bd -C "$ROOT" show "$first_id" --json | jq 'map(del(.actor))' > "$TMP/bd-show.json" 2>/dev/null
  printf '%s\n' "$OUT" | jq 'map(del(.actor))' > "$TMP/ledger-show.json"
  step "show $first_id --json 이 actor 를 뺀 채로 bd -C <루트> 와 같다" diff -q "$TMP/ledger-show.json" "$TMP/bd-show.json"
else
  echo "  ✗ FAILED: 열린 이슈가 0건이라 show 동등성을 대조하지 못했다"; fail=1
fi

else
  EQUIV_LABEL="beads 동등성 ⊘ 건너뜀(backend=${BACKEND:-없음})"
  echo "── ② beads 동등성 — 건너뜀 (backend=${BACKEND:-없음}) ──"
  echo "  ⊘ 실제 원장이 beads 가 아니라 bd 로 대조할 수 없다 — 이 절은 bd -C <루트> 와의 바이트 대조이고, 그 루트에 .beads 가 없다"
fi

echo "── ③ beads 왕복 — 임시 원장 쓰기 ──"
FX="$TMP/fx"; mkdir -p "$FX"
( cd "$FX" && bd init --prefix lac ) >/dev/null 2>&1 || { echo "  ✗ FAILED: 픽스처 bd init"; fail=1; }
printf '{"ledger":{"backend":"beads"}}\n' > "$FX/.harness.json"
printf '본문 첫 줄\n둘째 줄\n' > "$TMP/body.txt"

run "$FX" create "부모" -t feature --silent; P="$OUT"
step "create --silent 가 id 만 낸다" bash -c '[ "$(printf "%s\n" "$1" | grep -c .)" -eq 1 ] && [ "$1" != "${1#lac-}" ]' _ "$P"
run "$FX" create "자식" -t task --parent "$P" -l repo:x,rail:r1 --acceptance "완료 조건" --body-file "$TMP/body.txt" --silent; C="$OUT"
run "$FX" show "$C" --json
step "create 의 -t·--parent·-l·--acceptance·--body-file 이 show --json 에 그대로 있다" \
  bash -c 'printf "%s" "$1" | jq -e --arg p "$2" ".[0] | .issue_type == \"task\" and .parent == \$p and (.labels | index(\"repo:x\") != null) and (.labels | index(\"rail:r1\") != null) and .acceptance_criteria == \"완료 조건\" and (.description | startswith(\"본문 첫 줄\"))" >/dev/null' _ "$OUT" "$P"

# ── create 의 라벨 상속 (skills#179). 어댑터가 부모의 sprint:·rail:·repo: 를 물려주고 slug: 는
#    물려주지 않는다. **beads 에서 보는 것은 "떼어지는가" 다** — bd 는 만들 때 부모 라벨을 통째로
#    물려주므로, 계약 밖의 것을 어댑터가 걷어내지 않으면 slug: 가 하위로 새고 문서 경로가 겹친다.
run "$FX" create "상속 부모" -t feature -l sprint:2026-S02,rail:r1,repo:skills,slug:r1-inherit --silent; IP="$OUT"
run "$FX" create "상속 자식" -t task --parent "$IP" --silent; IC="$OUT"; ic_rc=$RC
run "$FX" show "$IC" --json
step "create --parent: sprint:·rail:·repo: 를 물려받고 slug: 는 물려받지 않는다" \
  bash -c '[ "$2" -eq 0 ] && printf "%s" "$1" | jq -e ".[0].labels | (index(\"sprint:2026-S02\") != null) and (index(\"rail:r1\") != null) and (index(\"repo:skills\") != null) and (index(\"slug:r1-inherit\") == null)" >/dev/null' _ "$OUT" "$ic_rc"
run "$FX" create "명시 우선" -t task --parent "$IP" -l repo:other --silent; IE="$OUT"
run "$FX" show "$IE" --json
step "create --parent: -l 로 명시한 접두사가 이기고(repo:other) 명시 안 한 접두사는 물려받는다(rail:r1·sprint:)" \
  bash -c 'printf "%s" "$1" | jq -e ".[0].labels | (index(\"repo:other\") != null) and (index(\"repo:skills\") == null) and (index(\"rail:r1\") != null) and (index(\"sprint:2026-S02\") != null)" >/dev/null' _ "$OUT"

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
# ── actor 키 (harness-kw0l.3.1). 어댑터의 계약은 "백엔드가 무엇이든 같은 JSON 키" 다 — beads 는
#    그 개념이 assignee 하나뿐이지만 키가 셋 중 둘에만 있으면 소비자가 `// .assignee` 폴백을
#    잊는 순간 여기서만 조용히 어긋난다. github·notion 경로에만 단언이 있어 그 구멍을 못 잡았다.
step "actor 키가 show --json 에 있고 assignee 와 같은 값이다 (github·notion 과 같은 키)" \
  bash -c 'printf "%s" "$1" | jq -e ".[0] | has(\"actor\") and .actor == .assignee and .actor == \"chk actor\"" >/dev/null' _ "$OUT"
run "$FX" list --status in_progress --json
step "list --json 의 항목에도 actor 키가 있다 (정지 가드가 실제로 읽는 경로)" \
  bash -c 'printf "%s" "$1" | jq -e "length > 0 and all(.actor == .assignee)" >/dev/null' _ "$OUT"
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

# ── jq 경로 판별 (harness-kw0l.3.1 리뷰 MUST FIX 1). 판별은 **읽기 하위 명령 한정**과 **argv 원소
#    완전 일치** 둘 다여야 한다. 처음 판은 `case " $* " in *" --json "*` 이었고, 그것은 인자 **값**
#    안의 토큰까지 잡아 쓰기 명령을 jq 로 보냈다 — 그러면 **쓰기가 이미 일어난 뒤** 출력이 jq 파싱
#    오류로 죽어 rc 5(jq 실측)가 되고 stdout 이 사라진다. `create --silent` 의 id 를 잃은 채 실패하니
#    재시도가 중복 생성이 된다.
#    가설이 아니다: 실측 2026-09-06, 하네스 원장 1089건 중 **31건**이 title·acceptance·description 에
#    ` --json ` 을 갖고 있다(`jq '[.[]|select((.title+.acceptance_criteria+.description)|test(" --json "))]|length'`).
#    develop 의 "원장에 본문을 넘기는 형태" 가 그 본문을 `--acceptance "$(cat …)"` 로 인자에 싣는다.
run "$FX" create "제목에 --json 이 든다" -t task --silent; J="$OUT"; j_rc=$RC
step "본문에 --json 이 든 create --silent 의 stdout 이 id 한 줄로 온전하다 (id 소실 → 재시도 중복 생성)" \
  bash -c '[ "$2" -eq 0 ] && [ "$(printf "%s\n" "$1" | grep -c .)" -eq 1 ] && [ "$1" != "${1#lac-}" ]' _ "$J" "$j_rc"
run "$FX" note "$J" "그 --json 경로를 고쳤다"
step "본문에 --json 이 든 note 가 rc 0 이고 stderr 에 jq 파싱 오류가 없다" \
  bash -c '[ "$2" -eq 0 ] && ! printf "%s" "$1" | grep -q "parse error"' _ "$ERR" "$RC"
run "$FX" close "$J" --reason "그 --json 경로를 고쳤다"; close_rc=$RC; close_err="$ERR"
run "$FX" show "$J" --json
step "본문에 --json 이 든 close 가 rc 0 이고 닫힘·사유·메모가 온전하다" \
  bash -c '[ "$2" -eq 0 ] && ! printf "%s" "$3" | grep -q "parse error" && printf "%s" "$1" | jq -e ".[0] | .status == \"closed\" and .close_reason == \"그 --json 경로를 고쳤다\" and (.notes | contains(\"그 --json 경로를 고쳤다\"))" >/dev/null' _ "$OUT" "$close_rc" "$close_err"
# 읽기 명령 한정 쪽 — history --json 은 커밋 레코드 배열이라 이슈가 아니다. jq 를 타면 그 레코드에
# actor:null 이 심긴다. 완전 일치만으로는 막히지 않는 형태라 여기서 따로 든다.
run "$FX" history "$J" --json
step "history --json 은 jq 를 타지 않는다 (이슈 아닌 레코드에 actor 를 심지 않는다)" \
  bash -c '[ "$2" -eq 0 ] && printf "%s" "$1" | jq -e "type == \"array\" and length > 0 and all(has(\"actor\") | not)" >/dev/null' _ "$OUT" "$RC"

# ── 등록부 질의 (skills#143). 이 백엔드의 값은 <루트>/rails.json · sprints.json 에서 온다.
#    별도 루트를 쓰는 이유: 파일이 **없는** 판을 먼저 세워야 "빈 배열 rc 0 으로 삼키지 않는다" 가
#    판정되고, FX 는 위 왕복이 쓰는 원장이라 파일을 붙였다 뗐다 할 자리가 아니다. bd 는 부르지
#    않는 경로라 bd init 도 필요 없다.
RG="$TMP/reg"; mkdir -p "$RG"; printf '{"ledger":{"backend":"beads"}}\n' > "$RG/.harness.json"
for sub in rails sprints; do
  run "$RG" "$sub" --json
  step "$sub: 등록부 파일이 없으면 rc≠0 이고 stderr 가 $sub.json 을 이름으로 든다 (빈 배열 rc 0 으로 삼키지 않는다)" \
    bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q "$3.json"' _ "$RC" "$ERR" "$sub"
done
printf '{"rails":{"r1":{"owner":"juhyeon-cha","description":"x"},"r2":{"owner":"dongqdev","description":"y"}}}\n' > "$RG/rails.json"
printf '{"sprints":{"2026-S01":{"status":"closed"},"2026-S02":{"status":"active"}}}\n' > "$RG/sprints.json"
run "$RG" rails --json
step "rails: 등재된 레일 수와 출력 배열 길이가 같고 id·owner 가 파일 그대로다" \
  bash -c '[ "$2" -eq 0 ] && printf "%s" "$1" | jq -e "length == 2 and .[0] == {id:\"r1\",owner:\"juhyeon-cha\"} and .[1] == {id:\"r2\",owner:\"dongqdev\"}" >/dev/null' _ "$OUT" "$RC"
run "$RG" sprints --json
step "sprints: id 는 등재 키이고 status 는 active|closed 둘 중 하나다" \
  bash -c '[ "$2" -eq 0 ] && printf "%s" "$1" | jq -e "map(.id) == [\"2026-S01\",\"2026-S02\"] and all(.status == \"active\" or .status == \"closed\")" >/dev/null' _ "$OUT" "$RC"
# ── 스프린트 등재 (skills#181). 등재의 경계(ID 형식·중복·인자 수)는 ledger.sh 한 자리이고
#    백엔드는 쓰기만 한다. 그래서 경계 단언은 여기 한 번만 세우고, 나머지 두 백엔드에서는
#    **각자의 쓰기 모양**과 "중복은 그쪽에서도 rc≠0" 만 본다.
#    아래 대조군 픽스처(status:진행중 등)가 이 파일을 덮기 **전에** 둔다 — 그 뒤에서는
#    sprints 자체가 rc≠0 이라 등재의 왕복을 세울 수 없다.
run "$RG" sprint-add 2026-S04
step "sprint-add beads: sprints.json 에 키를 더하고 rc 0 · stdout 한 줄이 무엇에 썼는지 말한다" \
  bash -c '[ "$2" -eq 0 ] && printf "%s" "$1" | grep -q "2026-S04"' _ "$OUT" "$RC"
run "$RG" sprints --json
step "sprint-add beads: 등재 **뒤** sprints --json 이 그것을 active 로 낸다 (등재의 왕복)" \
  bash -c '[ "$2" -eq 0 ] && printf "%s" "$1" | jq -e "any(.[]; .id == \"2026-S04\" and .status == \"active\")" >/dev/null' _ "$OUT" "$RC"
run "$RG" sprint-add 2026-S04
step "sprint-add: 이미 있는 ID 를 다시 등재하면 rc≠0 이고 stderr 가 그 ID 를 든다 (조용히 덮어쓰지 않는다)" \
  bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q "2026-S04"' _ "$RC" "$ERR"
run "$RG" sprint-add 2026S04
step "sprint-add: ID 형식이 YYYY-SNN 이 아니면 rc≠0 이고 stderr 가 그 형식을 든다" \
  bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q "YYYY-SNN"' _ "$RC" "$ERR"
run "$RG" sprint-add 2026-S05 2026-S06
step "sprint-add: 인자가 스프린트 ID 하나가 아니면 rc≠0" [ "$RC" -ne 0 ]
# 등재가 0건인 것과 파일이 없는 것은 다른 상태다 — 앞은 rc 0 의 빈 배열, 뒤는 위에서 본 rc≠0.
printf '{"rails":{}}\n' > "$RG/rails.json"
run "$RG" rails --json
step "rails: 파일은 있고 등재가 0건이면 rc 0 의 빈 배열이다 (파일 없음과 구별된다)" \
  bash -c '[ "$2" -eq 0 ] && printf "%s" "$1" | jq -e "length == 0" >/dev/null' _ "$OUT" "$RC"
# 계약을 깨는 값을 그대로 흘리면 소비자(board-check)가 그것을 등재로 읽는다.
printf '{"rails":{"r9":{"description":"owner 가 없다"}}}\n' > "$RG/rails.json"
run "$RG" rails --json
step "rails: owner 없는 레일 → rc≠0 이고 stderr 가 그 레일 id 를 든다 (owner:null 을 흘리지 않는다)" \
  bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q r9' _ "$RC" "$ERR"
printf '{"sprints":{"2026-S03":{"status":"진행중"}}}\n' > "$RG/sprints.json"
run "$RG" sprints --json
step "sprints: status 가 active|closed 밖이면 rc≠0 (낯선 값을 그대로 흘리지 않는다)" [ "$RC" -ne 0 ]
run "$RG" rails --all
step "rails: --json 밖의 인자 → rc≠0" [ "$RC" -ne 0 ]

echo "── ④ github 오프라인 — 가짜 gh ──"
# jq·bash 만 보이고 gh 는 없는 PATH. 가짜 gh 는 호출 전부를 LOG 에 남기고 정해진 답을 낸다.
mkdir -p "$TMP/jqbin" "$TMP/ghbin"
ln -s "$(command -v jq)" "$TMP/jqbin/jq"
NOGH_PATH="$TMP/jqbin:/usr/bin:/bin"
GH="$TMP/ghbin"; mkdir -p "$GH"
printf '{"ledger":{"backend":"github","owner":"juhyeon-cha","project":4}}\n' > "$GH/.harness.json"
LOG="$TMP/gh.log"
cat > "$TMP/ghbin/gh" <<'FAKE'
#!/usr/bin/env bash
# 가짜 gh — 호출을 기록하고 정해진 답을 낸다. 판정은 기록과 답의 형태로 한다.
printf '%s\n' "$*" >> "$FAKE_GH_LOG"
# blockedBy — 이슈 번호로 정해지는 픽스처. 같은 GraphQL 질의가 실어 오므로 node() 안에서 붙인다.
# 57 은 열린 58 에 막히고, 58 은 닫힌 59 에만 막힌다 → ready 는 58 만 내야 한다.
# 72 는 절단 픽스처다: totalCount 가 받은 노드 수보다 크다 (first:N 을 넘은 응답).
bb() { case "$1" in
  57) printf '{"totalCount":1,"nodes":[{"number":58,"state":"OPEN","repository":{"name":"harness"}}]}' ;;
  58) printf '{"totalCount":1,"nodes":[{"number":59,"state":"CLOSED","repository":{"name":"harness"}}]}' ;;
  72) printf '{"totalCount":9,"nodes":[{"number":59,"state":"CLOSED","repository":{"name":"harness"}}]}' ;;
  *)  printf '{"totalCount":0,"nodes":[]}' ;;
esac; }
node() { # <번호> <제목> <상태> <라벨 JSON> <부모 JSON> <본문> [<projectItems nodes JSON — 기본 project 4>]
  local pi='[{"project":{"number":4}}]'
  [ $# -ge 7 ] && pi="$7"
  printf '{"id":"NODE_%s","databaseId":100%s,"number":%s,"title":"%s","state":"%s","body":"%s","createdAt":"2026-09-05T00:00:00Z","updatedAt":"2026-09-05T00:00:00Z","closedAt":null,"repository":{"name":"harness"},"labels":{"nodes":%s},"assignees":{"nodes":[{"login":"juhyeon-cha"}]},"comments":{"nodes":[{"body":"메모"}]},"parent":%s,"blockedBy":%s,"projectItems":{"nodes":%s}}' \
    "$1" "$1" "$1" "$2" "$3" "$6" "$4" "$5" "$(bb "$1")" "$pi"
}
# actor 픽스처 — 코멘트만 갈아 끼운 노드. assignee 는 로그인명 그대로다(그것이 이 백엔드에서
# actor 와 assignee 가 갈리는 이유다 — ledger-github.sh 대응표).
node_actor() { # <번호> <코멘트 nodes JSON>
  printf '{"id":"NODE_%s","databaseId":100%s,"number":%s,"title":"actor 픽스처","state":"OPEN","body":"본문","createdAt":"2026-09-05T00:00:00Z","updatedAt":"2026-09-05T00:00:00Z","closedAt":null,"repository":{"name":"harness"},"labels":{"nodes":[{"name":"type:task"},{"name":"repo:harness"}]},"assignees":{"nodes":[{"login":"juhyeon-cha"}]},"comments":{"nodes":%s},"parent":null,"blockedBy":{"totalCount":0,"nodes":[]}}' \
    "$1" "$1" "$1" "$2"
}
# rails 픽스처 — rail: 라벨을 가진 epic. assignee 를 인자로 받는 것이 본 픽스처(node)와 다른 점이고,
# 그것이 rails 의 값 산출을 가르는 축이다(양성·충돌·없음).
# **본 픽스처와 갈라 둔다**(FAKE_GH_RAILS 로만 나온다): 같은 nodes 배열에 이 epic 들을 더하면
# 위의 건수 단언(list 의 `length == 2`·`length == 3`, 경계의 id 목록)이 함께 깨져, epic 하나를
# 더하는 일이 무관한 단언 넷을 고치는 일이 된다.
rail_epic() { # <번호> <레일 id> <assignees nodes JSON>
  printf '{"id":"NODE_%s","databaseId":100%s,"number":%s,"title":"레일 epic %s","state":"OPEN","body":"","createdAt":"2026-09-05T00:00:00Z","updatedAt":"2026-09-05T00:00:00Z","closedAt":null,"repository":{"name":"harness"},"labels":{"nodes":[{"name":"type:epic"},{"name":"repo:harness"},{"name":"rail:%s"}]},"assignees":{"nodes":%s},"comments":{"nodes":[]},"parent":null,"blockedBy":{"totalCount":0,"nodes":[]},"projectItems":{"nodes":[{"project":{"number":4}}]}}' \
    "$1" "$1" "$1" "$2" "$2" "$3"
}
N57='[{"name":"type:epic"},{"name":"repo:harness"},{"name":"status:blocked"}]'
N58='[{"name":"type:feature"},{"name":"repo:harness"},{"name":"rail:r1"}]'
N59='[{"name":"type:task"},{"name":"repo:harness"}]'
# 70·71 — 같은 레포에 살지만 원장의 경계(Project 4) 밖이다. 70 은 다른 프로젝트, 71 은 어느
# 프로젝트에도 없다(레포 자신의 이슈가 이 모양이다). 라벨을 57~59 와 같은 계열로 두어 경계가
# 새면 -t·-l 질의에도 걸리게 한다 — 걸리면 아래 단언이 떨어진다.
N70='[{"name":"type:task"},{"name":"repo:harness"},{"name":"rail:r1"}]'
# 63 — 상속의 부모. 계약이 가르는 네 접두사를 한 이슈에 다 담는다: sprint:·rail:·repo: 는 내려가고
# slug: 는 내려가지 않는다(스토리 고유 — 물려주면 문서 디렉토리 이름이 겹친다).
N63='[{"name":"type:epic"},{"name":"repo:harness"},{"name":"rail:r1"},{"name":"sprint:2026-S02"},{"name":"slug:r1-x"}]'
PI70='[{"project":{"number":9}}]'
PI71='[]'
case "$1 $2" in
  "auth status") [ -z "${FAKE_GH_AUTH_FAIL:-}" ] || exit 1; exit 0 ;;
  "label create"|"issue comment"|"issue close"|"issue edit"|"issue reopen") exit 0 ;;
  # item-add 는 rc 를 고를 수 있다 — create 의 판정이 그 rc 에 기대지 않는다는 것을 보는 축이다.
  # 실패판은 stderr 에 표지를 낸다: 호출부가 그것을 버리면 진짜 사유가 영영 보이지 않는다.
  "project item-add")
    [ -z "${FAKE_GH_ITEM_ADD_FAIL:-}" ] || { echo "FAKEGH_MARKER: item-add 가 낸 진짜 사유 (scope 부족)" >&2; exit 1; }
    exit 0 ;;
  "issue create")
    while [ $# -gt 0 ]; do [ "$1" = "-F" ] && cp "$2" "$FAKE_GH_LOG.body"; shift; done
    echo "https://github.com/juhyeon-cha/harness/issues/61"; exit 0 ;;
  "issue view") printf 'type:epic\nrepo:harness\nstatus:blocked\n'; exit 0 ;;
  "project view") echo '{"id":"PVT_x","number":4}'; exit 0 ;;
  "project create") echo '{"number":9}'; exit 0 ;;
  "api graphql")
    all="$*"
    # 변수에 배열이 있는 뮤테이션(sprint-add 의 updateProjectV2Field)은 -f 로 실을 수 없어 본문이
    # --input - 로 온다. 본문을 파일에 남겨 두어 단언이 variables 를 열어 볼 수 있게 한다.
    case "$all" in *--input*) gqlbody="$(cat)"; printf '%s' "$gqlbody" > "$FAKE_GH_LOG.gql"; all="$all $gqlbody" ;; esac
    case "$all" in
      *addSubIssue*) echo '{"data":{"addSubIssue":{}}}' ;;
      *updateProjectV2Field*) echo '{"data":{"updateProjectV2Field":{"projectV2Field":{"name":"Sprint"}}}}' ;;
      # ITERATION 필드 생성 — init 이 부르는 자리. gh project field-create 는 ITERATION 을
      # 지원하지 않아 이 뮤테이션이 유일한 통로다(M0 실측).
      *createProjectV2Field*) echo '{"data":{"createProjectV2Field":{"projectV2Field":{"name":"Sprint"}}}}' ;;
      # Projects v2 의 필드 목록 — sprints 와 init 이 읽는 자리. 세 판을 낸다:
      #   기본                    ITERATION 필드가 있고 iteration 이 두 개
      #   FAKE_GH_NO_ITERATION    ITERATION 필드가 없다 (configuration 이 없는 노드만)
      #   FAKE_GH_EMPTY_ITERATION 필드는 있고 iteration 이 0개 — 갓 init 한 하네스의 모양이다
      # 셋째 판이 실제와 같은 모양이라는 근거: 시험용 Projects v2 에 init 과 같은
      # createProjectV2Field(dataType: ITERATION) 을 돌려, 생성 응답과 별도 fields(first:100)
      # 질의 양쪽에서 configuration 의 iterations·completedIterations 가 둘 다 빈 배열임을 봤다
      # (2026-09-07, skills#167). 픽스처가 스스로를 근거로 삼지 않는다 — 실측을 옮긴 것이다.
      # 상태 필드가 없으므로 status 는 iterations(현재·미래)/completedIterations(종료일이 지난
      # 것) 두 목록에서만 갈린다. projectV2.id 는 init 이 뮤테이션에 넘길 node id 다.
      # 필드 노드의 id 와 iteration 의 startDate·duration 은 **sprint-add 만** 읽는다(sprints 는
      # title 뿐이다). 등재가 대체 API 라 되돌려 보낼 값이 여기서 나온다 — 없으면 sprint-add 가
      # 새 iteration 의 시작일을 계산하지 못한다.
      *"fields(first"*)
        if [ -n "${FAKE_GH_NO_ITERATION:-}" ]; then
          echo '{"data":{"user":{"projectV2":{"id":"PVT_x","fields":{"nodes":[{},{}]}}}}}'
        elif [ -n "${FAKE_GH_EMPTY_ITERATION:-}" ]; then
          echo '{"data":{"user":{"projectV2":{"id":"PVT_x","fields":{"nodes":[{},{"name":"Sprint","id":"PVTIF_x","configuration":{"duration":0,"iterations":[],"completedIterations":[]}}]}}}}}'
        else
          echo '{"data":{"user":{"projectV2":{"id":"PVT_x","fields":{"nodes":[{},{"name":"Sprint","id":"PVTIF_x","configuration":{"duration":14,"iterations":[{"title":"2026-S02","startDate":"2026-09-01","duration":14}],"completedIterations":[{"title":"2026-S01","startDate":"2026-08-18","duration":14}]}}]}}}}}'
        fi ;;
      # Projects v2 의 항목 — 읽기가 훑을 레포 목록의 출처다(등록부가 아니다). content 가
      # Issue 가 아닌 항목(draft)을 한 건 섞어 두어, 그것이 이름으로 새면 아래 단언이 떨어진다.
      *"items(first"*)
        [ -z "${FAKE_GH_ITEMS_FAIL:-}" ] || { echo 'gh: Could not resolve to a ProjectV2' >&2; exit 1; }
        if [ -n "${FAKE_GH_NO_ITEMS:-}" ]; then
          echo '[{"data":{"user":{"projectV2":{"items":{"nodes":[]}}}}}]'
        else
          echo '[{"data":{"user":{"projectV2":{"items":{"nodes":[{"content":{"repository":{"name":"harness"}}},{"content":{"repository":{"name":"harness"}}},{"content":{}}]}}}}}]'
        fi ;;
      *"subIssues(first"*) printf '{"data":{"repository":{"issue":{"subIssues":{"nodes":[%s,%s]}}}}}' "$(node 58 피처 OPEN "$N58" '{"number":57,"repository":{"name":"harness"}}' "")" "$(node 59 태스크 CLOSED "$N59" '{"number":58,"repository":{"name":"harness"}}' "")" ;;
      # 레포 이슈 목록. FAKE_GH_RAILS 가 있으면 rails 전용 판으로 **갈아 끼운다** — 더하지 않는다.
      # 본 픽스처의 건수·id 단언과 rails 의 값 산출 단언이 서로를 흔들지 않게 하는 자리다.
      *"issues(first"*)
        case "${FAKE_GH_RAILS:-}" in
          # (a) 레일 둘이 각자 owner 를 갖는 정상 판.
          ok) printf '[{"data":{"repository":{"issues":{"nodes":[%s,%s]}}}}]' \
                "$(rail_epic 80 r1 '[{"login":"juhyeon-cha"}]')" "$(rail_epic 81 r2 '[{"login":"dongqdev"}]')" ;;
          # (b) 한 레일(r1)의 epic 둘이 서로 다른 사람을 가리킨다.
          conflict) printf '[{"data":{"repository":{"issues":{"nodes":[%s,%s]}}}}]' \
                "$(rail_epic 80 r1 '[{"login":"juhyeon-cha"}]')" "$(rail_epic 82 r1 '[{"login":"dongqdev"}]')" ;;
          # (c) rail: 라벨은 있는데 assignee 가 없는 epic(83). 같은 판에 owner 를 가진 레일(r1)을
          #     함께 두어 "나머지 결과는 온전하다" 를 볼 수 있게 한다.
          blank) printf '[{"data":{"repository":{"issues":{"nodes":[%s,%s]}}}}]' \
                "$(rail_epic 80 r1 '[{"login":"juhyeon-cha"}]')" "$(rail_epic 83 r3 '[]')" ;;
          *) printf '[{"data":{"repository":{"issues":{"nodes":[%s,%s,%s,%s,%s]}}}}]' "$(node 57 에픽 OPEN "$N57" null '본문\n\n## Acceptance\n\n조건 1')" "$(node 58 피처 OPEN "$N58" '{"number":57,"repository":{"name":"harness"}}' "")" "$(node 59 태스크 CLOSED "$N59" null "")" "$(node 70 프로젝트밖 OPEN "$N70" null "" "$PI70")" "$(node 71 프로젝트없음 OPEN "$N70" null "" "$PI71")" ;;
        esac ;;
      # 소속 재확인 (skills#212) — create 가 item-add 뒤에 이슈를 다시 읽는 자리다. 기본은 소속,
      # FAKE_GH_NOT_IN_PROJECT 는 빈 목록(정말 안 들어간 판). 아래 n= 분기들보다 **앞**에 둔다 —
      # 이 질의도 -F n=<번호> 를 실어 가므로 뒤에 두면 그쪽이 먼저 집어 FIELDS 노드를 답한다.
      *'issue(number:$n){ projectItems'*)
        if [ -n "${FAKE_GH_NOT_IN_PROJECT:-}" ]; then
          echo '{"data":{"repository":{"issue":{"projectItems":{"nodes":[]}}}}}'
        else
          echo '{"data":{"repository":{"issue":{"projectItems":{"nodes":[{"project":{"number":4}}]}}}}}'
        fi ;;
      *"n=999"*) echo 'gh: Could not resolve to an Issue' >&2; exit 1 ;;
      # 없는 레포 — 등록부가 사라져 이름의 실재를 판정하는 것은 원격뿐이다(ledger-github.sh 머리 주석).
      *"r=nowhere"*) echo 'gh: Could not resolve to a Repository' >&2; exit 1 ;;
      # 70 — 프로젝트 밖 이슈. show 는 id 로 직접 읽으므로 소속을 요구하지 않는다(ledger-github.sh 머리 주석).
      *"n=70"*) printf '{"data":{"repository":{"issue":%s}}}' "$(node 70 프로젝트밖 OPEN "$N70" null "" "$PI70")" ;;
      # 72 — blockedBy 가 first:N 에 잘린 응답. 조용히 자르면 ready 가 막힌 것을 열렸다고 낸다.
      *"n=72"*) printf '{"data":{"repository":{"issue":%s}}}' "$(node 72 절단 OPEN "$N59" null "")" ;;
      # 58·63 — create --parent 가 라벨을 물려받으려고 직접 읽는 부모들. 이것이 없으면 아래 *) 가
      # 57 을 내어 "부모의 라벨" 단언이 엉뚱한 이슈를 보게 된다.
      *"n=58"*) printf '{"data":{"repository":{"issue":%s}}}' "$(node 58 피처 OPEN "$N58" '{"number":57,"repository":{"name":"harness"}}' "")" ;;
      *"n=63"*) printf '{"data":{"repository":{"issue":%s}}}' "$(node 63 상속부모 OPEN "$N63" null "")" ;;
      # 60 — ACTOR 코멘트가 하나. 뒤에 다른 note 가 더 붙어도 값이 살아야 한다.
      *"n=60"*) printf '{"data":{"repository":{"issue":%s}}}' \
        "$(node_actor 60 '[{"body":"메모"},{"body":"ACTOR: sess-abc123"},{"body":"두 번째 메모"}]')" ;;
      # 62 — ACTOR 코멘트가 둘이고 뒤엣것이 스토리 형태(`ACTOR: <레포> <값>`)다. 마지막 코멘트의
      #      마지막 토큰이 값이다 — 첫 토큰을 읽으면 레포 이름(harness)을 집는다.
      *"n=62"*) printf '{"data":{"repository":{"issue":%s}}}' \
        "$(node_actor 62 '[{"body":"ACTOR: sess-old111"},{"body":"ACTOR: harness sess-new222"}]')" ;;
      *) printf '{"data":{"repository":{"issue":%s}}}' "$(node 57 에픽 OPEN "$N57" null '본문\n\n## Acceptance\n\n조건 1\n')" ;;
    esac; exit 0 ;;
  "api -X"|"api repos"*)
    path=""; for a in "$@"; do case "$a" in repos/*) path="$a" ;; esac; done
    case "$path" in
      # 아래 blocked_by 분기 셋은 정상 경로에서 안 불린다(의존은 GraphQL 의 blockedBy 로 온다). 지우지 마라 —
      # 미끼다: REST 로 회귀하면 여기가 답을 주어 그 호출이 로그에 남고 "REST 0회" 단언이 잡는다.
      # 분기를 지우면 회귀가 "모르는 호출" 로 죽어 단언이 아니라 픽스처가 실패한다.
      */issues/57/dependencies/blocked_by) echo '[{"number":58,"state":"open","repository_url":"https://api.github.com/repos/juhyeon-cha/harness"}]' ;;
      */issues/58/dependencies/blocked_by) echo '[{"number":59,"state":"closed","repository_url":"https://api.github.com/repos/juhyeon-cha/harness"}]' ;;
      */dependencies/blocked_by) echo '[]' ;;
      *) n="${path##*/}"; case "$*" in *".node_id"*) echo "NODE_$n" ;; *) echo "100$n" ;; esac ;;
    esac; exit 0 ;;
esac
echo "fake gh: 모르는 호출 $*" >&2; exit 1
FAKE
chmod +x "$TMP/ghbin/gh"
# grun <인자…> — 가짜 gh 를 PATH 앞에 두고 github 픽스처 루트로 돌린다.
grun() {
  OUT=$(PATH="$TMP/ghbin:$TMP/jqbin:/usr/bin:/bin" FAKE_GH_LOG="$LOG" HARNESS_ROOT="$GH" bash "$LEDGER" "$@" 2>"$TMP/err"); RC=$?
  ERR=$(cat "$TMP/err")
}
one_line_err() { [ "$(printf '%s\n' "$ERR" | grep -c .)" -eq 1 ]; }

OUT=$(PATH="$NOGH_PATH" HARNESS_ROOT="$GH" bash "$LEDGER" show 'harness#57' 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
step "gh 없음 → rc≠0 · stderr 한 줄이 gh 를 든다" bash -c '[ "$1" -ne 0 ] && [ "$(printf "%s\n" "$2" | grep -c .)" -eq 1 ] && printf "%s" "$2" | grep -q gh' _ "$RC" "$ERR"
OUT=$(PATH="$TMP/ghbin:$TMP/jqbin:/usr/bin:/bin" FAKE_GH_LOG="$LOG" FAKE_GH_AUTH_FAIL=1 HARNESS_ROOT="$GH" bash "$LEDGER" show 'harness#57' 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
step "gh auth status rc≠0 → rc≠0 · stderr 한 줄" bash -c '[ "$1" -ne 0 ] && [ "$(printf "%s\n" "$2" | grep -c .)" -eq 1 ]' _ "$RC" "$ERR"

mkdir -p "$TMP/ghnoproj"
printf '{"ledger":{"backend":"github","owner":"juhyeon-cha"}}\n' > "$TMP/ghnoproj/.harness.json"
: > "$LOG"
OUT=$(PATH="$TMP/ghbin:$TMP/jqbin:/usr/bin:/bin" FAKE_GH_LOG="$LOG" HARNESS_ROOT="$TMP/ghnoproj" bash "$LEDGER" create "x" -l repo:harness 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
step "project 키 없음 → create 가 이슈를 만들기 전에 rc≠0 (item-add 를 건너뛰지 않는다)" \
  bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q project && ! grep -q "^issue create" "$3"' _ "$RC" "$ERR" "$LOG"

: > "$LOG"; printf '본문\n' > "$TMP/gh-body.txt"
grun create "제목" -t task -l repo:harness,rail:r1 --parent 'harness#58' --acceptance "조건" --body-file "$TMP/gh-body.txt" --silent
step "create --silent 가 <repo>#<번호> 만 낸다" [ "$OUT" = "harness#61" ]
step "create → 라벨 생성(type:task·repo·rail) → issue create(-R·-t·-l) → addSubIssue(부모 58) → item-add(project 4) 순서" \
  bash -c 'grep -q "^label create type:task -R juhyeon-cha/harness --force$" "$1" && grep -q "^label create rail:r1 -R" "$1" \
    && grep -q "^issue create -R juhyeon-cha/harness -t 제목 -F .* -l type:task,repo:harness,rail:r1$" "$1" \
    && grep -q "addSubIssue.* -f p=NODE_58 -f c=NODE_61" "$1" \
    && grep -q "^project item-add 4 --owner juhyeon-cha --url https://github.com/juhyeon-cha/harness/issues/61$" "$1" \
    && [ "$(grep -n "^issue create" "$1" | cut -d: -f1)" -lt "$(grep -n "^project item-add" "$1" | cut -d: -f1)" ]' _ "$LOG"
step "create 의 본문이 <description>\\n\\n## Acceptance\\n\\n<acceptance> 형태다" \
  bash -c '[ "$(cat "$1")" = "$(printf "본문\n\n## Acceptance\n\n조건")" ]' _ "$LOG.body"
grun create "x" -t task
step "create 에 repo: 라벨도 --parent 도 없으면 rc≠0 (레포를 정할 출처가 없다)" [ "$RC" -ne 0 ]

# ── create 의 Project 등재 판정 (skills#212) ──────────────────────────
# 판정은 `gh project item-add` 의 **종료 코드가 아니라 다시 읽은 소속**이다. 이슈는 item-add
# 앞에서 이미 만들어지므로, rc 하나로 죽으면 실재하는 등재가 실패로 기록된다 — 이 스토리를
# 쪼갤 때 실제로 그랬다(skills#210 실측 ①②③). 이 레포 자신의 교리이기도 하다
# (../docs/guardrails.md 5-1 — 시도한 반영이 아니라 다시 세어본 결과가 판정한다).
grunenv() { # grunenv <VAR=값…> -- <ledger.sh 인자…>
  local -a e=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do e+=("$1"); shift; done
  shift
  OUT=$(PATH="$TMP/ghbin:$TMP/jqbin:/usr/bin:/bin" FAKE_GH_LOG="$LOG" HARNESS_ROOT="$GH" \
        env "${e[@]}" bash "$LEDGER" "$@" 2>"$TMP/err"); RC=$?
  ERR=$(cat "$TMP/err")
}
: > "$LOG"; grunenv FAKE_GH_ITEM_ADD_FAIL=1 -- create "제목" -t task -l repo:harness --silent
step "item-add 가 rc≠0 이어도 소속이 확인되면 create 가 통과한다 (rc=0 · id 를 낸다)" \
  bash -c '[ "$1" -eq 0 ] && [ "$2" = "harness#61" ]' _ "$RC" "$OUT"
step "소속을 실제로 **다시 읽었다** — item-add 뒤에 projectItems 질의가 있다" \
  bash -c 'grep -q projectItems "$1" \
    && [ "$(grep -n "^project item-add" "$1" | head -1 | cut -d: -f1)" -lt "$(grep -n projectItems "$1" | head -1 | cut -d: -f1)" ]' _ "$LOG"

: > "$LOG"; grunenv FAKE_GH_ITEM_ADD_FAIL=1 FAKE_GH_NOT_IN_PROJECT=1 -- create "제목" -t task -l repo:harness --silent
step "정말 소속이 아니면 create 가 죽는다 (rc≠0)" [ "$RC" -ne 0 ]
step "죽을 때 gh 자신의 stderr 가 메시지에 실린다 (>/dev/null 2>&1 로 버리지 않는다)" \
  has_text 'FAKEGH_MARKER' "$ERR"
# 반대쪽 극성 — **rc 0 이면 다시 읽지 않는다.** 소속 조회가 item-add 직후에 신선한지는 미측정이고
# (같은 계열의 item-list 는 직후에 새 항목을 내지 않는 것이 실측이다 — ../scripts/ledger-github.sh 머리 주석),
# 보고된 성공을 낡을 수 있는 조회로 뒤집으면 흔한 경로에서 거짓 실패가 난다. 이 두 줄이 그 경계를 든다.
: > "$LOG"; grunenv FAKE_GH_NOT_IN_PROJECT=1 -- create "제목" -t task -l repo:harness --silent
step "item-add 가 rc 0 이면 소속을 다시 읽지 않는다 (통과 · projectItems 질의 0회)" \
  bash -c '[ "$1" -eq 0 ] && ! grep -q projectItems "$2"' _ "$RC" "$LOG"

# 부정 대조군 — 판정 한 줄만 옛 형태(rc 만 본다)로 되돌린 어댑터 사본에서는 첫 픽스처가 죽는다
# (../docs/development.md "Checking that a check is alive"). 사본이 비지 않고 원본과 다름을 먼저 단언한다.
NEGP="$TMP/negplug"; mkdir -p "$NEGP/scripts"
cp "$PLUGIN_ROOT/scripts/ledger.sh" "$NEGP/scripts/ledger.sh"
step "부정 대조군 전제: 소속 재확인이 어댑터에 1줄 실재한다" \
  [ "$(grep -cE '^ *\[ "\$add_rc" -eq 0 \] \|\| in_project "\$slug" "\$num" \\$' "$PLUGIN_ROOT/scripts/ledger-github.sh")" -eq 1 ]
sed 's#^ *\[ "\$add_rc" -eq 0 \] || in_project "\$slug" "\$num" \\$#    [ "$add_rc" -eq 0 ] \\#' \
  "$PLUGIN_ROOT/scripts/ledger-github.sh" > "$NEGP/scripts/ledger-github.sh"
step "부정 대조군 사본이 원본과 다르다" bash -c '[ -s "$1" ] && [ -s "$2" ] && ! cmp -s "$1" "$2"' \
  _ "$PLUGIN_ROOT/scripts/ledger-github.sh" "$NEGP/scripts/ledger-github.sh"
: > "$LOG"
OUT=$(PATH="$TMP/ghbin:$TMP/jqbin:/usr/bin:/bin" FAKE_GH_LOG="$LOG" HARNESS_ROOT="$GH" \
      CLAUDE_PLUGIN_ROOT="$NEGP" FAKE_GH_ITEM_ADD_FAIL=1 bash "$NEGP/scripts/ledger.sh" \
      create "제목" -t task -l repo:harness --silent 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
step "부정 대조군: rc 만 보는 옛 형태는 같은 픽스처에서 죽는다 (rc≠0)" [ "$RC" -ne 0 ]
# 사본이 **엉뚱한 이유로** 죽은 것이 아님 — 죽은 자리가 그 판정이고, 이슈는 이미 만들어진 뒤다.
step "부정 대조군이 죽은 자리가 등재 판정이다 (이슈는 만들어졌다)" \
  bash -c 'printf "%s" "$1" | grep -q "Project 4" && grep -q "^issue create" "$2"' _ "$ERR" "$LOG"
# ── create 의 라벨 상속 (skills#179 · 스토리 skills#175 결정 1) ────────
# **방향이 뒤집힌 자리다.** 종전 단언은 "--parent 만으로는 레포를 정하지 않는다 — repo: 라벨 0개는
# rc≠0" 이었다(폴백 없음). 상속이 어댑터의 것이 된 뒤 그것은 폴백이 아니라 규칙이다 — 부모의
# repo: 를 물려받는 것이 세 백엔드 공통이고, 좁히기는 `-l` 로 명시해 이기는 쪽이 맡는다.
: > "$LOG"
grun create "x" -t task --parent 'harness#58'
step "create --parent: 부모(58)의 rail:·repo: 를 물려받아 -l 없이도 선다" \
  bash -c '[ "$1" -eq 0 ] && grep -q -- "-l type:task,rail:r1,repo:harness$" "$2"' _ "$RC" "$LOG"
: > "$LOG"
grun create "x" -t task -l repo:skills --parent 'harness#58'
step "create --parent: -l 로 명시한 접두사는 그쪽이 이기고(repo:skills) 명시 안 한 접두사는 물려받는다(rail:r1)" \
  bash -c '[ "$1" -eq 0 ] && grep -q -- "-l type:task,repo:skills,rail:r1$" "$2"' _ "$RC" "$LOG"
: > "$LOG"
grun create "x" -t task --parent 'harness#63'
step "create --parent: sprint:·rail:·repo: 는 물려받고 slug: 는 물려받지 않는다 (문서 경로가 겹친다)" \
  bash -c '[ "$1" -eq 0 ] && grep -q -- "-l type:task,rail:r1,repo:harness,sprint:2026-S02$" "$2" && ! grep -q "slug:" "$2"' _ "$RC" "$LOG"
: > "$LOG"
grun create "x" -t task --parent 'harness#999'
step "create --parent: 부모를 읽지 못하면 이슈를 만들지 않고 rc≠0 (상속할 라벨의 출처다)" \
  bash -c '[ "$1" -ne 0 ] && ! grep -q "^issue create" "$2"' _ "$RC" "$LOG"
# epic 의 assignee — 이 픽스처의 rails 는 [] 다(아래 rails 단언). 그래서 여기서 보는 것은 **없는
# 쪽**이다: 그 레일의 첫 epic 이면 assignee 없이 만들되 조용히 넘어가지 않는다. 있는 쪽(owner 가
# 실제로 들어가는 왕복)은 ⑤ notion 픽스처가 든다 — 그쪽 등록부 픽스처가 owner 를 갖는다.
: > "$LOG"
grun create "새 에픽" -t epic -l repo:harness,rail:r9
step "create -t epic + rail: 인데 그 레일의 owner 가 없으면 assignee 없이 만들고 stderr 가 그 레일을 든다" \
  bash -c '[ "$1" -eq 0 ] && printf "%s" "$2" | grep -q "r9" && ! grep -q "^api -X PATCH" "$3"' _ "$RC" "$ERR" "$LOG"
: > "$LOG"
grun create "x" -t task -l repo:harness,repo:skills
step "create: repo: 라벨 2개 → rc≠0 이고 stderr 가 그 개수를 든다 · 이슈를 만들지 않는다 (등록부가 사라진 자리를 메우는 판정)" \
  bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q "repo: 라벨이 2개" && ! grep -q "^issue create" "$3"' _ "$RC" "$ERR" "$LOG"

grun show 'harness#57' --json
step "show --json 의 키가 bd 와 같다 (id·title·status·issue_type·labels·acceptance_criteria·notes·assignee·actor·parent)" \
  bash -c 'printf "%s" "$1" | jq -e ".[0] | keys | contains([\"id\",\"title\",\"status\",\"issue_type\",\"labels\",\"acceptance_criteria\",\"notes\",\"assignee\",\"actor\",\"parent\",\"description\",\"dependencies\"])" >/dev/null' _ "$OUT"
step "show --json 의 값 대응: status:blocked 라벨→blocked · type:epic→epic · labels 에서 type:·status: 제거 · 코멘트→notes · 본문 절 분리" \
  bash -c 'printf "%s" "$1" | jq -e ".[0] | .id == \"harness#57\" and .status == \"blocked\" and .issue_type == \"epic\" and .labels == [\"repo:harness\"] and .notes == \"메모\" and .acceptance_criteria == \"조건 1\" and .description == \"본문\" and .assignee == \"juhyeon-cha\" and .parent == null and (.dependencies | length == 1) and .dependencies[0].id == \"harness#58\"" >/dev/null' _ "$OUT"
step "jq -r .[0].status 가 그대로 돈다" bash -c '[ "$(printf "%s" "$1" | jq -r ".[0].status")" = "blocked" ]' _ "$OUT"
# ── actor 키 (harness-kw0l.3.1). 정지 가드가 `.actor // .assignee` 로 읽는 필드다. github 은 이
#    둘이 갈린다 — assignee 는 claim 을 돌린 사람의 GitHub 로그인이고 actor 는 세션 값이다.
#    실패 경로를 같은 자리에서 함께 못박는다: ACTOR 코멘트가 없으면 actor 는 null 이다(57번).
step "actor 실패 경로: ACTOR 코멘트가 없는 이슈의 actor 는 null 이다 (assignee 로 새지 않는다)" \
  bash -c 'printf "%s" "$1" | jq -e ".[0] | has(\"actor\") and .actor == null and .assignee == \"juhyeon-cha\"" >/dev/null' _ "$OUT"
grun show 'harness#60' --json
step "actor: 마지막 ACTOR 코멘트의 값을 싣고 assignee 는 로그인명 그대로다 (둘이 갈린다)" \
  bash -c 'printf "%s" "$1" | jq -e ".[0] | .actor == \"sess-abc123\" and .assignee == \"juhyeon-cha\"" >/dev/null' _ "$OUT"
grun show 'harness#62' --json
step "actor: ACTOR 코멘트가 둘이면 마지막 것이고, 스토리 형태(ACTOR: <레포> <값>)는 마지막 토큰이다" \
  bash -c 'printf "%s" "$1" | jq -e ".[0].actor == \"sess-new222\"" >/dev/null' _ "$OUT"
# compose_body 는 본문을 "\n" 으로 끝낸다(위 픽스처 57 의 body 가 그 형태) — bd 처럼 acceptance_criteria 에 끝 개행이 없어야 한다.
step "본문 끝 개행이 acceptance_criteria 에 남지 않는다" bash -c 'printf "%s" "$1" | jq -e ".[0].acceptance_criteria | endswith(\"\\n\") | not" >/dev/null' _ "$OUT"
grun show 'harness#999' --json
step "없는 id → rc≠0" [ "$RC" -ne 0 ]
grun show 57
step "형식 밖 id(번호만) → rc≠0" [ "$RC" -ne 0 ]
grun show 'nowhere#1'
step "없는 레포 → rc≠0 (이름의 실재는 원격이 판정한다 — 등록부를 읽지 않는다)" [ "$RC" -ne 0 ]
step "slug 는 .harness.json 의 owner 와 repo 이름으로 파생한다 (등록부의 url 이 아니다)" \
  bash -c 'grep -q -- "-f o=juhyeon-cha" "$1" && grep -q -- "-f r=nowhere" "$1"' _ "$LOG"
# 레포 목록의 출처가 실패하면 삼키지 않는다 — 종전에는 레포 루프가 빈 채로 돌아 "이슈 0건" 으로
# rc 0 이 났다(harness-m8gg.4 verify-code 2차 관찰).
OUT=$(PATH="$TMP/ghbin:$TMP/jqbin:/usr/bin:/bin" FAKE_GH_LOG="$LOG" FAKE_GH_ITEMS_FAIL=1 HARNESS_ROOT="$GH" bash "$LEDGER" list --json 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
step "프로젝트 항목을 읽지 못하면 list → rc≠0 이고 stderr 가 project 번호를 든다 (빈 목록 rc 0 으로 삼키지 않는다)" \
  bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q "Project 4"' _ "$RC" "$ERR"
# 항목 0건은 갓 만든 빈 프로젝트의 정상 모양이다 — 실패가 아니라 rc 0 의 빈 배열 + stderr 한 줄.
OUT=$(PATH="$TMP/ghbin:$TMP/jqbin:/usr/bin:/bin" FAKE_GH_LOG="$LOG" FAKE_GH_NO_ITEMS=1 HARNESS_ROOT="$GH" bash "$LEDGER" list --json 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
step "프로젝트 항목 0건 → rc 0 · 빈 배열 · stderr 가 그 사실을 밝힌다 (빈 프로젝트는 실패가 아니다)" \
  bash -c '[ "$1" -eq 0 ] && printf "%s" "$2" | jq -e "length == 0" >/dev/null && printf "%s" "$3" | grep -q "항목이 0건"' _ "$RC" "$OUT" "$ERR"

grun children 'harness#57' --json
step "children --json 이 subIssues 2건을 parent 와 함께 낸다" \
  bash -c 'printf "%s" "$1" | jq -e "length == 2 and .[0].id == \"harness#58\" and .[0].parent == \"harness#57\" and .[1].status == \"closed\"" >/dev/null' _ "$OUT"
grun list --json
step "list --json 은 closed 를 뺀다 (프로젝트 안 3건 중 2건)" bash -c 'printf "%s" "$1" | jq -e "length == 2" >/dev/null' _ "$OUT"
# 정지 가드가 실제로 읽는 것은 show 가 아니라 `list --status in_progress --json` 이다 — 그쪽에도
# actor 키가 실려야 좁히기가 산다. show 에만 있으면 가드는 조용히 종전 동작으로 돌아간다.
step "list --json 의 항목에도 actor 키가 있다 (정지 가드가 읽는 경로)" \
  bash -c 'printf "%s" "$1" | jq -e "all(has(\"actor\"))" >/dev/null' _ "$OUT"
: > "$LOG"
grun list --all --json -n 0
step "list --all --json -n 0 은 프로젝트 안 전부를 낸다 (5건 중 3건)" bash -c 'printf "%s" "$1" | jq -e "length == 3" >/dev/null' _ "$OUT"
# ── 원장의 경계 = Projects v2 소속 (harness-kw0l.3.5) ─────────────────
# 픽스처의 레포 이슈 5건 중 70(다른 프로젝트)·71(프로젝트 없음)은 원장이 아니다. 거르지 않으면
# 경계가 "등재 레포의 모든 이슈" 가 되어 triage·status 가 남의 백로그를 원장으로 읽는다.
step "경계: 프로젝트 밖 이슈(70·71)가 읽기에 0건이고 프로젝트 안(57·58·59)은 전수다" \
  bash -c 'printf "%s" "$1" | jq -e "(map(.id) | sort) == [\"harness#57\",\"harness#58\",\"harness#59\"]" >/dev/null' _ "$OUT"
step "경계: 소속 판정에 gh project item-list 를 쓰지 않는다 (item-add 직후 안 나오는 목록이다)" \
  bash -c '! grep -q "^project item-list" "$1"' _ "$LOG"
step "호출 수: 읽기 한 번에 레포 목록 1회 + 레포마다 GraphQL 1회다 (이슈마다 1회가 아니다 — projectItems 를 같은 질의에 얹는다)" \
  bash -c '[ "$(grep -c "^api graphql" "$1")" -eq 2 ] && [ "$(grep -c "items(first" "$1")" -eq 1 ] && [ "$(grep -c "issues(first" "$1")" -eq 1 ]' _ "$LOG"
grun show 'harness#70' --json
step "경계 밖이어도 show 는 id 로 읽는다 (소속을 요구하지 않는다)" \
  bash -c '[ "$1" -eq 0 ] && printf "%s" "$2" | jq -e ".[0].id == \"harness#70\"" >/dev/null' _ "$RC" "$OUT"
# 없는 project 번호 → 조용한 전수가 아니라 0건이고, 0건이 정상 상태와 구별되도록 stderr 로 밝힌다.
mkdir -p "$TMP/ghbadproj"
printf '{"ledger":{"backend":"github","owner":"juhyeon-cha","project":99999}}\n' > "$TMP/ghbadproj/.harness.json"
OUT=$(PATH="$TMP/ghbin:$TMP/jqbin:/usr/bin:/bin" FAKE_GH_LOG="$LOG" HARNESS_ROOT="$TMP/ghbadproj" bash "$LEDGER" list --all --json -n 0 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
step "없는 project 번호 → 0건 + stderr 가 그 사실을 밝힌다 (rc 0 — 빈 프로젝트도 같은 모양이라 실패로 읽을 수 없다)" \
  bash -c '[ "$1" -eq 0 ] && printf "%s" "$2" | jq -e "length == 0" >/dev/null && printf "%s" "$3" | grep -q "99999"' _ "$RC" "$OUT" "$ERR"
OUT=$(PATH="$TMP/ghbin:$TMP/jqbin:/usr/bin:/bin" FAKE_GH_LOG="$LOG" HARNESS_ROOT="$TMP/ghnoproj" bash "$LEDGER" list --json 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
step "project 키 없음 → list 가 rc≠0 (경계를 정할 수 없는데 전수를 내지 않는다)" \
  bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q project' _ "$RC" "$ERR"
grun list -l repo:harness,rail:r1 --status open --json
step "list -l a,b --status open 은 AND 로 거른다 (58 만)" bash -c 'printf "%s" "$1" | jq -e "length == 1 and .[0].id == \"harness#58\"" >/dev/null' _ "$OUT"
grun list --label-pattern 'rail:*' --all --json
step "list --label-pattern glob (rail:* → 58 만)" bash -c 'printf "%s" "$1" | jq -e "length == 1 and .[0].id == \"harness#58\"" >/dev/null' _ "$OUT"
grun list -t task --all --json
step "list -t task (59 만)" bash -c 'printf "%s" "$1" | jq -e "length == 1 and .[0].id == \"harness#59\"" >/dev/null' _ "$OUT"
: > "$LOG"
grun ready --json
step "ready 는 open 이고 의존이 전부 closed 인 것만 (57 은 열린 58 에 막혀 빠지고, 58 은 닫힌 59 뿐이라 든다)" \
  bash -c 'printf "%s" "$1" | jq -e "map(.id) == [\"harness#58\"]" >/dev/null' _ "$OUT"
# 이 스토리의 완료 형상. 종전에는 열린 이슈마다 REST 를 한 번씩 불렀다 — 호출 수가 항목 수에 선형이었다.
step "ready 가 의존 조회 REST 를 한 번도 부르지 않는다 — 호출은 레포 목록 1회 + 레포마다 GraphQL 1회뿐이다" \
  bash -c '! grep -q "dependencies/blocked_by" "$1" && [ "$(grep -c "^api graphql" "$1")" -eq 2 ]' _ "$LOG"
grun show 'harness#72' --json
step "blockedBy 가 잘린 응답(totalCount 9 > 받은 노드 1) → rc≠0 · stderr 가 두 수를 함께 낸다 (조용히 자르지 않는다)" \
  bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q "totalCount=9" && printf "%s" "$2" | grep -q "받은 노드=1"' _ "$RC" "$ERR"

: > "$LOG"
grun dep add 'harness#60' 'harness#59'
step "dep add A B → B 의 숫자 id 조회 뒤 A 에 blocked_by POST" \
  bash -c '[ "$1" -eq 0 ] && grep -q "^api repos/juhyeon-cha/harness/issues/59 --jq .id$" "$2" && grep -q "^api -X POST repos/juhyeon-cha/harness/issues/60/dependencies/blocked_by -F issue_id=10059$" "$2"' _ "$RC" "$LOG"
: > "$LOG"
printf '{"from":"harness#60","to":"harness#58"}\n' | PATH="$TMP/ghbin:$TMP/jqbin:/usr/bin:/bin" FAKE_GH_LOG="$LOG" HARNESS_ROOT="$GH" bash "$LEDGER" dep add --file - >/dev/null 2>&1; rc=$?
step "dep add --file - (JSONL) 도 같은 POST 를 낸다" \
  bash -c '[ "$1" -eq 0 ] && grep -q "^api -X POST repos/juhyeon-cha/harness/issues/60/dependencies/blocked_by -F issue_id=10058$" "$2"' _ "$rc" "$LOG"
: > "$LOG"
grun note 'harness#57' "메모 하나"
grun note 'harness#57' --file "$TMP/gh-body.txt"
step "note <본문> · note --file → 코멘트" \
  bash -c 'grep -q "^issue comment 57 -R juhyeon-cha/harness -b 메모 하나$" "$1" && grep -q "^issue comment 57 -R juhyeon-cha/harness -b 본문$" "$1"' _ "$LOG"
: > "$LOG"
grun close 'harness#57' --reason-file "$TMP/gh-body.txt"
step "close --reason-file → 사유 코멘트와 함께 close" bash -c '[ "$1" -eq 0 ] && grep -q "^issue close 57 -R juhyeon-cha/harness -c 본문$" "$2"' _ "$RC" "$LOG"
: > "$LOG"
grun update 'harness#57' --claim --actor "skills sess-abc"
step "update --claim --actor → assignee @me · ACTOR: 코멘트 · status:in_progress 라벨(기존 status: 제거)" \
  bash -c '[ "$1" -eq 0 ] && grep -q "^issue edit 57 -R juhyeon-cha/harness --add-assignee @me$" "$2" && grep -q "^issue comment 57 -R juhyeon-cha/harness -b ACTOR: skills sess-abc$" "$2" && grep -q "^issue edit 57 -R juhyeon-cha/harness --remove-label status:blocked --add-label status:in_progress$" "$2"' _ "$RC" "$LOG"
: > "$LOG"
grun update 'harness#57' --status deferred
step "update --status deferred → status:deferred 라벨" bash -c 'grep -q -- "--add-label status:deferred$" "$1"' _ "$LOG"
: > "$LOG"
grun label add 'harness#57' slug:r1-x
grun label remove 'harness#57' rail:r1
step "label add|remove → --add-label · --remove-label" \
  bash -c 'grep -q "^issue edit 57 -R juhyeon-cha/harness --add-label slug:r1-x$" "$1" && grep -q "^issue edit 57 -R juhyeon-cha/harness --remove-label rail:r1$" "$1"' _ "$LOG"
grun dolt push
step "beads 전용 명령(dolt) → rc≠0" [ "$RC" -ne 0 ]
# ── 등록부 질의 (skills#144) ──────────────────────────────────────────
# 음성 경로 — **owner 를 어디서 파생하지 않는가**: 58 은 rail:r1 에 assignee 가 있으나 epic 이
# 아니고, 70 은 rail:r1 인 task 이며 프로젝트 밖이다. 둘 중 하나라도 새면 [] 가 깨진다.
grun rails --json
step "rails: epic 이 아닌 rail: 라벨(58 feature · 70 task)에서 owner 를 파생하지 않는다 → []" \
  bash -c '[ "$1" -eq 0 ] && printf "%s" "$2" | jq -e "length == 0" >/dev/null' _ "$RC" "$OUT"
# 값 산출 (skills#183). 위의 [] 는 **없는 쪽**만 세운다 — owner 가 실제로 어디서 와서 어떤 모양으로
# 나오는지는 여기서 못박는다. 판은 FAKE_GH_RAILS 가 갈아 끼운다(본 픽스처와 건수가 결합하지 않는다).
OUT=$(PATH="$TMP/ghbin:$TMP/jqbin:/usr/bin:/bin" FAKE_GH_LOG="$LOG" FAKE_GH_RAILS=ok HARNESS_ROOT="$GH" bash "$LEDGER" rails --json 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
step "rails 양성: id 는 epic 의 rail: 라벨이고 owner 는 그 epic 의 assignee 다 · 레일마다 한 항목이고 id 로 정렬된다" \
  bash -c '[ "$1" -eq 0 ] && printf "%s" "$2" | jq -e ". == [{id:\"r1\",owner:\"juhyeon-cha\"},{id:\"r2\",owner:\"dongqdev\"}]" >/dev/null' _ "$RC" "$OUT"
step "rails 양성: 아무 말도 남기지 않는다 (빠진 레일이 없다)" bash -c '[ -z "$1" ]' _ "$ERR"
OUT=$(PATH="$TMP/ghbin:$TMP/jqbin:/usr/bin:/bin" FAKE_GH_LOG="$LOG" FAKE_GH_RAILS=conflict HARNESS_ROOT="$GH" bash "$LEDGER" rails --json 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
step "rails 충돌: 한 레일의 epic 들이 서로 다른 assignee 를 가리키면 rc≠0 이고 stderr 가 레일 id 와 두 사람을 다 든다 (하나를 골라 덮지 않는다)" \
  bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q "r1=" && printf "%s" "$2" | grep -q dongqdev && printf "%s" "$2" | grep -q juhyeon-cha' _ "$RC" "$ERR"
OUT=$(PATH="$TMP/ghbin:$TMP/jqbin:/usr/bin:/bin" FAKE_GH_LOG="$LOG" FAKE_GH_RAILS=blank HARNESS_ROOT="$GH" bash "$LEDGER" rails --json 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
step "rails assignee 없음: 그 레일(r3)은 빠지고 나머지(r1)는 온전하다 — rc 는 0 이다" \
  bash -c '[ "$1" -eq 0 ] && printf "%s" "$2" | jq -e ". == [{id:\"r1\",owner:\"juhyeon-cha\"}]" >/dev/null' _ "$RC" "$OUT"
step "rails assignee 없음: 조용히 사라지지 않는다 — stderr 가 그 epic 의 id 를 든다" \
  bash -c 'printf "%s" "$1" | grep -q "harness#83"' _ "$ERR"
grun sprints --json
step "sprints: id 는 iteration 의 title 이고 status 는 iterations→active · completedIterations→closed" \
  bash -c '[ "$1" -eq 0 ] && printf "%s" "$2" | jq -e ". == [{id:\"2026-S01\",status:\"closed\"},{id:\"2026-S02\",status:\"active\"}]" >/dev/null' _ "$RC" "$OUT"
OUT=$(PATH="$TMP/ghbin:$TMP/jqbin:/usr/bin:/bin" FAKE_GH_LOG="$LOG" FAKE_GH_NO_ITERATION=1 HARNESS_ROOT="$GH" bash "$LEDGER" sprints --json 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
step "ITERATION 필드가 없으면 rc≠0 — 빈 배열은 '스프린트가 없다' 와 구별되지 않는다" \
  bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q ITERATION' _ "$RC" "$ERR"
for sub in rails sprints; do
  OUT=$(PATH="$TMP/ghbin:$TMP/jqbin:/usr/bin:/bin" FAKE_GH_LOG="$LOG" HARNESS_ROOT="$TMP/ghnoproj" bash "$LEDGER" "$sub" --json 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
  step "project 키 없음 → $sub 가 rc≠0 이고 stderr 한 줄이 project 를 이름으로 든다" \
    bash -c '[ "$1" -ne 0 ] && [ "$(printf "%s\n" "$2" | grep -c .)" -eq 1 ] && printf "%s" "$2" | grep -q project' _ "$RC" "$ERR"
done
# 갓 init 한 하네스의 모양 — 필드는 있고 iteration 이 0개다. 이것은 **정상 상태**라 rc 0 이고,
# 바로 위의 "필드가 없다"(rc≠0)와 문면으로 갈려야 한다. 갈리지 않으면 board-check 가 두 판을
# 같게 읽는다.
OUT=$(PATH="$TMP/ghbin:$TMP/jqbin:/usr/bin:/bin" FAKE_GH_LOG="$LOG" FAKE_GH_EMPTY_ITERATION=1 HARNESS_ROOT="$GH" bash "$LEDGER" sprints --json 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
step "필드는 있고 iteration 이 0개 → rc 0 의 빈 배열 (갓 init 한 하네스)" \
  bash -c '[ "$2" -eq 0 ] && printf "%s" "$1" | jq -e "length == 0" >/dev/null' _ "$OUT" "$RC"
step "그 빈 배열이 '스프린트가 없다' 임을 stderr 가 밝히고 '필드가 없다' 와 문면이 다르다" \
  bash -c 'printf "%s" "$1" | grep -q "iteration 이 하나도 없다" && ! printf "%s" "$1" | grep -q "ITERATION 필드가 없다"' _ "$ERR"

# ── init 이 ITERATION 필드를 만든다 (skills#167). 이 필드가 없으면 갓 세운 github 하네스가
#    문서화된 경로로 sprints 를 rc 0 으로 만들 수 없다 — 실제로 이 스토리의 오케스트레이터도
#    필드 생성 명령을 손으로 돌려야 했다.
: > "$LOG"
OUT=$(PATH="$TMP/ghbin:$TMP/jqbin:/usr/bin:/bin" FAKE_GH_LOG="$LOG" FAKE_GH_NO_ITERATION=1 HARNESS_ROOT="$GH" bash "$LEDGER" init 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
step "init: ITERATION 필드가 없으면 createProjectV2Field(dataType: ITERATION) 를 부른다" \
  bash -c '[ "$1" -eq 0 ] && grep -q "createProjectV2Field" "$2" && grep -q "dataType: ITERATION" "$2"' _ "$RC" "$LOG"
step "init: 뮤테이션이 project 의 node id 를 넘긴다 (번호가 아니다)" \
  bash -c 'grep -q "p=PVT_x" "$1"' _ "$LOG"
step "init: iteration 은 만들지 않는다 (스프린트 ID 는 사람이 정한다 — 자리를 채우면 없는 스프린트가 등재된다)" \
  bash -c '! grep -q "iterationConfiguration" "$1"' _ "$LOG"
step "init: 무엇을 만들었는지 한 줄로 말한다" bash -c 'printf "%s" "$1" | grep -q "ITERATION 필드"' _ "$OUT"
# ② 멱등 — project 가 이미 있는 .harness.json 에 다시 돌려도 필드를 겹쳐 만들지 않는다.
: > "$LOG"
OUT=$(PATH="$TMP/ghbin:$TMP/jqbin:/usr/bin:/bin" FAKE_GH_LOG="$LOG" HARNESS_ROOT="$GH" bash "$LEDGER" init 2>"$TMP/err"); RC=$?
step "init 멱등: ITERATION 필드가 이미 있으면 createProjectV2Field 를 부르지 않는다" \
  bash -c '[ "$1" -eq 0 ] && ! grep -q "createProjectV2Field" "$2"' _ "$RC" "$LOG"
step "init 멱등: 이미 있다는 사실을 필드 이름과 함께 한 줄로 말한다" \
  bash -c 'printf "%s" "$1" | grep -q "이미 있다" && printf "%s" "$1" | grep -q Sprint' _ "$OUT"
step "init 멱등: project 가 이미 있으므로 project create 도 부르지 않는다" \
  bash -c '! grep -q "^project create" "$1"' _ "$LOG"

# ── 스프린트 등재 (skills#181). GitHub 에는 "iteration 하나를 더한다" 는 API 가 없다 —
#    updateProjectV2Field 의 iterationConfiguration 이 **iterations 전체를 대체한다**(입력의
#    ProjectV2Iteration 에 id 가 없다). 그래서 여기서 못박는 것은 "새 것이 붙었는가" 만이 아니라
#    **읽은 것을 전부 되돌려 보내는가** 다: 완료분을 빠뜨리면 닫힌 스프린트가 등록부에서 사라지고
#    board-check 이 그 sprint: 라벨을 전부 미등재로 읽는다.
: > "$LOG"; rm -f "$LOG.gql"
grun sprint-add 2026-S03
step "sprint-add github: updateProjectV2Field 로 ITERATION 필드에 title=<ID> iteration 을 더한다" \
  bash -c '[ "$1" -eq 0 ] && jq -e ".variables.f == \"PVTIF_x\" and (.variables.it | map(.title)) == [\"2026-S01\",\"2026-S02\",\"2026-S03\"]" "$2" >/dev/null' _ "$RC" "$LOG.gql"
step "sprint-add github: 완료분까지 전부 되돌려 보낸다 (대체 API 라 빠뜨리면 등록부에서 사라진다)" \
  bash -c 'jq -e ".variables.it | length == 3 and all(.[]; has(\"startDate\") and has(\"duration\") and has(\"title\"))" "$1" >/dev/null' _ "$LOG.gql"
step "sprint-add github: 새 iteration 은 마지막 것이 끝난 다음 날부터이고 기간은 필드의 것이다 (겹치지 않는다)" \
  bash -c 'jq -e ".variables.it[2] == {title:\"2026-S03\", startDate:\"2026-09-15\", duration:14} and .variables.d == 14 and .variables.s == \"2026-08-18\"" "$1" >/dev/null' _ "$LOG.gql"
# 뮤테이션을 불렀는지는 **본문 파일의 실재**로 본다 — 로그 줄($*)에는 --input 뒤의 본문이 없어
# 뮤테이션 이름이 찍히지 않는다. 이름으로 grep 하면 불러도 통과하는 공허한 단언이 된다.
: > "$LOG"; rm -f "$LOG.gql"
grun sprint-add 2026-S02
step "sprint-add github: 이미 있는 ID → rc≠0 · stderr 가 그 ID 를 든다 · 뮤테이션을 부르지 않는다" \
  bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q "2026-S02" && [ ! -f "$3" ]' _ "$RC" "$ERR" "$LOG.gql"
OUT=$(PATH="$TMP/ghbin:$TMP/jqbin:/usr/bin:/bin" FAKE_GH_LOG="$LOG" FAKE_GH_NO_ITERATION=1 HARNESS_ROOT="$GH" bash "$LEDGER" sprint-add 2026-S03 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
step "sprint-add github: ITERATION 필드가 없으면 rc≠0 이고 stderr 가 ledger.sh init 을 가리킨다" \
  bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q "ledger.sh init"' _ "$RC" "$ERR"
# 갓 init 한 판 — 필드는 있고 iteration 이 0개다. 첫 스프린트는 오늘부터이고 기간은 필드의
# duration 이 0 이라 2주로 간다. 날짜를 값으로 박지 않는다(오늘이 바뀐다) — 형식과 관계만 본다.
: > "$LOG"; rm -f "$LOG.gql"
OUT=$(PATH="$TMP/ghbin:$TMP/jqbin:/usr/bin:/bin" FAKE_GH_LOG="$LOG" FAKE_GH_EMPTY_ITERATION=1 HARNESS_ROOT="$GH" bash "$LEDGER" sprint-add 2026-S01 2>"$TMP/err"); RC=$?
step "sprint-add github: iteration 이 0개인 필드(갓 init)에도 선다 — 첫 것 하나뿐이고 시작일이 YYYY-MM-DD 다" \
  bash -c '[ "$1" -eq 0 ] && jq -e "(.variables.it | length) == 1 and .variables.it[0].title == \"2026-S01\" and (.variables.it[0].startDate | test(\"^[0-9]{4}-[0-9]{2}-[0-9]{2}$\")) and .variables.it[0].duration == 14 and .variables.s == .variables.it[0].startDate" "$2" >/dev/null' _ "$RC" "$LOG.gql"

grun rails --all
step "rails: --json 밖의 인자 → rc≠0" [ "$RC" -ne 0 ]

echo "── ⑤ notion 오프라인 — 가짜 curl ──"
# 가짜 curl 은 요청(메서드·경로·본문)을 번호 붙여 기록하고 정해진 답을 낸다. 페이지 4개:
#   E(epic, blocked, Blocked by T) · F(feature, open, parent E, Blocked by T) · T(task, closed, parent F) · U(task, open, parent F, Blocked by F)
NT="$TMP/ntbin"; mkdir -p "$NT" "$TMP/ntroot"
printf '{"ledger":{"backend":"notion","database_id":"d0000000-0000-0000-0000-00000000000d"}}\n' > "$TMP/ntroot/.harness.json"
NLOG="$TMP/curl.log"
cat > "$NT/curl" <<'FAKE'
#!/usr/bin/env bash
# 가짜 curl — -o·-X·--data-binary @파일·URL 만 해석하고 상태 코드를 stdout 에 낸다(-w '%{http_code}' 의 자리).
out=""; m="GET"; url=""; data=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;; -X) m="$2"; shift 2 ;; -w|-H) shift 2 ;; --data-binary) data="${2#@}"; shift 2 ;;
    http*) url="$1"; shift ;; *) shift ;;
  esac
done
path="${url#https://api.notion.com/v1/}"
n=$(( $(grep -c . "$FAKE_CURL_LOG" 2>/dev/null) + 1 ))
printf '%s %s %s\n' "$n" "$m" "$path" >> "$FAKE_CURL_LOG"
[ -n "$data" ] && cp "$data" "$FAKE_CURL_LOG.$n"
respond() { printf '%s' "$2" > "$out"; printf '%s' "$1"; exit 0; }
E=e0000000-0000-0000-0000-000000000001; F=f0000000-0000-0000-0000-000000000002; T=t0000000-0000-0000-0000-000000000003; U=u0000000-0000-0000-0000-000000000004
page() { # <id> <제목> <type> <status> <labels JSON> <parent id 또는 ""> <blocked by id 또는 ""> <acceptance> <description> [assignee]
  printf '{"object":"page","id":"%s","created_time":"2026-09-05T00:00:00.000Z","last_edited_time":"2026-09-05T00:00:00.000Z","properties":{"Name":{"title":[{"plain_text":"%s"}]},"Type":{"select":{"name":"%s"}},"Status":{"select":{"name":"%s"}},"Labels":{"multi_select":%s},"Parent":{"relation":%s},"Blocked by":{"relation":%s},"Acceptance":{"rich_text":[{"plain_text":"%s"}]},"Description":{"rich_text":[{"plain_text":"%s"}]},"Assignee":{"rich_text":[{"plain_text":"%s"}]}}}' \
    "$1" "$2" "$3" "$4" "$5" "$( [ -n "$6" ] && printf '[{"id":"%s"}]' "$6" || printf '[]' )" "$( [ -n "$7" ] && printf '[{"id":"%s"}]' "$7" || printf '[]' )" "$8" "$9" "${10-juhyeon-cha}"
}
PE="$(page "$E" 에픽 epic blocked '[{"name":"repo:harness"}]' "" "$T" "조건 1" 본문)"
PF="$(page "$F" 피처 feature open '[{"name":"repo:harness"},{"name":"rail:r1"}]' "$E" "$T" "" "")"
PT="$(page "$T" 태스크 task closed '[{"name":"repo:harness"}]' "$F" "" "" "")"
PU="$(page "$U" 넷째 task open '[{"name":"repo:harness"}]' "$F" "$F" "" "")"
[ -n "${FAKE_NOTION_401:-}" ] && respond 401 '{"object":"error","status":401,"code":"unauthorized","message":"API token is invalid."}'
[ -n "${FAKE_NOTION_GET_FAIL:-}" ] && [ "$m $path" = "GET pages/$FAKE_NOTION_GET_FAIL" ] && respond 500 '{"object":"error","status":500,"code":"internal_server_error","message":"fake"}'
case "$m $path" in
  "GET pages/missing"*) respond 404 '{"object":"error","status":404,"code":"object_not_found","message":"Could not find page with ID: missing. Make sure the relevant pages and databases are shared with your integration."}' ;;
  "GET pages/$E") respond 200 "$PE" ;;
  "GET pages/$F") respond 200 "$PF" ;;
  "GET pages/$T") respond 200 "$PT" ;;
  "GET pages/$U") respond 200 "$PU" ;;
  "POST pages") respond 200 '{"object":"page","id":"n0000000-0000-0000-0000-00000000000e"}' ;;
  "PATCH pages/"*|"PATCH blocks/"*|"PATCH databases/"*) respond 200 '{"object":"page"}' ;;
  "POST databases") respond 200 '{"object":"database","id":"d0000000-0000-0000-0000-00000000000d"}' ;;
  "POST databases/"*"/query")
    # 등록부(rails·sprints)만 다른 페이지 집합을 본다 — 위 네 페이지에 레일 epic 과 스프린트를
    # 섞으면 list·ready 의 개수 단언이 전부 흔들린다. 질의 필터는 가짜라 무시하고(어댑터가
    # list_json 의 jq 로 한 번 더 거른다) 이 집합만 낸다.
    case "${FAKE_NOTION_REGISTRY:-}" in
      "") respond 200 "$(printf '{"results":[%s,%s,%s,%s],"has_more":false,"next_cursor":null}' "$PE" "$PF" "$PT" "$PU")" ;;
      conflict) respond 200 "$(printf '{"results":[%s,%s],"has_more":false,"next_cursor":null}' \
        "$(page ra00000-0000-0000-0000-00000000000a 레일에픽1 epic open '[{"name":"rail:r1"}]' "" "" "" "" juhyeon-cha)" \
        "$(page rb00000-0000-0000-0000-00000000000b 레일에픽2 epic open '[{"name":"rail:r1"}]' "" "" "" "" dongqdev)")" ;;
      *) respond 200 "$(printf '{"results":[%s,%s,%s,%s,%s],"has_more":false,"next_cursor":null}' \
        "$(page ra00000-0000-0000-0000-00000000000a 레일에픽 epic open '[{"name":"rail:r1"}]' "" "" "" "" juhyeon-cha)" \
        "$(page rb00000-0000-0000-0000-00000000000b 닫힌레일에픽 epic closed '[{"name":"rail:r2"}]' "" "" "" "" dongqdev)" \
        "$(page rc00000-0000-0000-0000-00000000000c 담당없는레일에픽 epic open '[{"name":"rail:r3"}]' "" "" "" "" '')" \
        "$(page s100000-0000-0000-0000-000000000011 2026-S01 sprint closed '[]' "" "" "" "")" \
        "$(page s200000-0000-0000-0000-000000000012 2026-S02 sprint in_progress '[]' "" "" "" "")")" ;;
    esac ;;
  "GET blocks/"*"/children"*) respond 200 '{"results":[{"type":"paragraph","paragraph":{"rich_text":[{"plain_text":"메모"}]}},{"type":"paragraph","paragraph":{"rich_text":[{"plain_text":"둘째"}]}}]}' ;;
esac
echo "fake curl: 모르는 요청 $m $path" >&2; exit 22
FAKE
chmod +x "$NT/curl"
E=e0000000-0000-0000-0000-000000000001; F=f0000000-0000-0000-0000-000000000002; T=t0000000-0000-0000-0000-000000000003; U=u0000000-0000-0000-0000-000000000004
NPATH="$NT:$TMP/jqbin:/usr/bin:/bin"
nrun() {
  OUT=$(PATH="$NPATH" FAKE_CURL_LOG="$NLOG" NOTION_TOKEN="fake-token" HARNESS_ROOT="$TMP/ntroot" bash "$LEDGER" "$@" 2>"$TMP/err"); RC=$?
  ERR=$(cat "$TMP/err")
}
# body_of <메서드> <경로 접두> — 기록에서 마지막으로 맞는 요청의 본문 파일 경로
body_of() { local n; n="$(grep " $1 $2" "$NLOG" | tail -1 | cut -d' ' -f1)"; [ -n "$n" ] && printf '%s' "$NLOG.$n"; }

OUT=$(env -u NOTION_TOKEN PATH="$NPATH" FAKE_CURL_LOG="$NLOG" HARNESS_ROOT="$TMP/ntroot" bash "$LEDGER" show "$E" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
step "NOTION_TOKEN 없음 → rc≠0 · stderr 한 줄이 NOTION_TOKEN 을 든다" bash -c '[ "$1" -ne 0 ] && [ "$(printf "%s\n" "$2" | grep -c .)" -eq 1 ] && printf "%s" "$2" | grep -q NOTION_TOKEN' _ "$RC" "$ERR"
# curl 만 없는 /usr/bin 사본 — 나머지 도구(dirname·sed·grep)는 그대로 보여야 어댑터 자신이 돈다.
mkdir -p "$TMP/usrbin-nocurl"
for f in /usr/bin/*; do b="${f##*/}"; [ "$b" = curl ] || ln -s "$f" "$TMP/usrbin-nocurl/$b"; done
OUT=$(PATH="$TMP/jqbin:$TMP/usrbin-nocurl:/bin" NOTION_TOKEN=x HARNESS_ROOT="$TMP/ntroot" bash "$LEDGER" show "$E" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
step "curl 없음 → rc≠0 · stderr 한 줄" bash -c '[ "$1" -ne 0 ] && [ "$(printf "%s\n" "$2" | grep -c .)" -eq 1 ] && printf "%s" "$2" | grep -q curl' _ "$RC" "$ERR"
OUT=$(PATH="$NPATH" FAKE_CURL_LOG="$NLOG" FAKE_NOTION_401=1 NOTION_TOKEN=bad HARNESS_ROOT="$TMP/ntroot" bash "$LEDGER" show "$E" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
step "401 → rc≠0 · stderr 에 상태와 응답의 code(unauthorized)" bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q 401 && printf "%s" "$2" | grep -q unauthorized' _ "$RC" "$ERR"
nrun show missing-0000 --json
step "404 → rc≠0 · stderr 에 응답의 code(object_not_found)" bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q 404 && printf "%s" "$2" | grep -q object_not_found' _ "$RC" "$ERR"
: > "$NLOG"
printf '본문\n' > "$TMP/nt-body.txt"
nrun create "제목" -t task -l repo:harness,rail:r1 --parent "$F" --acceptance "조건" --body-file "$TMP/nt-body.txt" --silent
step "create --silent 가 새 페이지 id 만 낸다" [ "$OUT" = "n0000000-0000-0000-0000-00000000000e" ]
step "create 의 POST /pages 본문: parent.database_id · Name · Type · Status=open · Labels · Acceptance · Description · Parent 관계" \
  bash -c 'jq -e --arg f "$2" ".parent.database_id == \"d0000000-0000-0000-0000-00000000000d\" and .properties.Name.title[0].text.content == \"제목\" and .properties.Type.select.name == \"task\" and .properties.Status.select.name == \"open\" and (.properties.Labels.multi_select | map(.name)) == [\"repo:harness\",\"rail:r1\"] and .properties.Acceptance.rich_text[0].text.content == \"조건\" and .properties.Description.rich_text[0].text.content == \"본문\" and .properties.Parent.relation[0].id == \$f" "$1" >/dev/null' _ "$(body_of POST pages)" "$F"
# ── create 의 라벨 상속과 epic 의 assignee (skills#179) ───────────────
# 위 create 는 `-l repo:harness,rail:r1` 을 직접 줬으므로 상속이 낼 것이 없다(명시가 이긴다).
# 여기서는 -l 없이 만들어 **물려받는 쪽**을 본다.
: > "$NLOG"
nrun create "상속 자식" -t task --parent "$F" --silent
step "create --parent: 부모(F)의 repo:·rail: 를 물려받는다 (백엔드가 무엇이든 같은 규칙)" \
  bash -c '[ "$1" -eq 0 ] && jq -e "(.properties.Labels.multi_select | map(.name) | sort) == [\"rail:r1\",\"repo:harness\"]" "$2" >/dev/null' _ "$RC" "$(body_of POST pages)"
# **assignee 의 양성 경로.** github 픽스처의 rails 는 [] 라 없는 쪽만 볼 수 있다 — 등록부가 owner 를
# 갖는 것은 이 픽스처(FAKE_NOTION_REGISTRY=1 의 r1 → juhyeon-cha)뿐이라 여기서 든다.
# (nreg 는 아래 등록부 절에서 정의되므로 여기서는 같은 환경을 그대로 편다)
: > "$NLOG"
OUT=$(PATH="$NPATH" FAKE_CURL_LOG="$NLOG" FAKE_NOTION_REGISTRY=1 NOTION_TOKEN="fake-token" HARNESS_ROOT="$TMP/ntroot" bash "$LEDGER" create "레일 에픽" -t epic -l rail:r1 --silent 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
step "create -t epic + rail: → 그 레일의 owner 가 assignee 로 들어간다 (출처는 rails --json)" \
  bash -c '[ "$1" -eq 0 ] && jq -e ".properties.Assignee.rich_text[0].text.content == \"juhyeon-cha\"" "$2" >/dev/null' _ "$RC" "$(body_of PATCH "pages/n0000000-0000-0000-0000-00000000000e")"

nrun show "$E" --json
step "show --json 의 키가 bd 와 같다" \
  bash -c 'printf "%s" "$1" | jq -e ".[0] | keys | contains([\"id\",\"title\",\"status\",\"issue_type\",\"labels\",\"acceptance_criteria\",\"notes\",\"assignee\",\"parent\",\"description\",\"dependencies\"])" >/dev/null' _ "$OUT"
step "show --json 의 값 대응: Status→status · Type→issue_type · Labels→labels · Acceptance · Description · 문단 블록→notes · Blocked by→dependencies" \
  bash -c 'printf "%s" "$1" | jq -e --arg t "$2" ".[0] | .status == \"blocked\" and .issue_type == \"epic\" and .labels == [\"repo:harness\"] and .acceptance_criteria == \"조건 1\" and .description == \"본문\" and .notes == \"메모\n둘째\" and .assignee == \"juhyeon-cha\" and .parent == null and .dependencies == [{id:\$t, status:\"closed\", dependency_type:\"blocks\"}]" >/dev/null' _ "$OUT" "$T"
nrun children "$F" --json
step "children --json 이 Parent contains 질의로 자식 2건(T·U)을 낸다" \
  bash -c 'printf "%s" "$1" | jq -e --arg f "$2" "length == 2 and all(.[]; .parent == \$f)" >/dev/null && jq -e --arg f "$2" ".filter.and | any(.[]; .property == \"Parent\" and .relation.contains == \$f)" "$3" >/dev/null' _ "$OUT" "$F" "$(body_of POST "databases/d0000000-0000-0000-0000-00000000000d/query")"
nrun list --json
step "list --json 은 closed 를 뺀다 (4건 중 3건) · 질의 필터에 Status does_not_equal closed" \
  bash -c 'printf "%s" "$1" | jq -e "length == 3" >/dev/null && jq -e ".filter.and | any(.[]; .property == \"Status\" and .select.does_not_equal == \"closed\")" "$2" >/dev/null' _ "$OUT" "$(body_of POST "databases/d0000000-0000-0000-0000-00000000000d/query")"
nrun list --all --json -n 0
step "list --all --json -n 0 은 전부 낸다 (4건)" bash -c 'printf "%s" "$1" | jq -e "length == 4" >/dev/null' _ "$OUT"
nrun list -l repo:harness,rail:r1 --status open --json
step "list -l a,b --status open 은 AND 로 거른다 (F 만) · 질의에 Labels contains 둘과 Status equals" \
  bash -c 'printf "%s" "$1" | jq -e --arg f "$2" "length == 1 and .[0].id == \$f" >/dev/null && jq -e "[.filter.and[] | select(.property == \"Labels\")] | length == 2" "$3" >/dev/null' _ "$OUT" "$F" "$(body_of POST "databases/d0000000-0000-0000-0000-00000000000d/query")"
nrun list -t task --all --json
step "list -t task (T·U)" bash -c 'printf "%s" "$1" | jq -e "length == 2 and all(.[]; .issue_type == \"task\")" >/dev/null' _ "$OUT"
nrun ready --json
step "ready 는 open 이고 Blocked by 가 전부 closed 인 것만 (F 만 — U 는 F 에 막히고 E 는 blocked)" \
  bash -c 'printf "%s" "$1" | jq -e --arg f "$2" "map(.id) == [\$f]" >/dev/null' _ "$OUT" "$F"
# 후보 페이지 자신의 GET 이 실패하면 "블로커 없음" 으로 읽혀 ready 에 들면 안 된다 — rc≠0 이고 stderr 가 상태를 든다.
OUT=$(PATH="$NPATH" FAKE_CURL_LOG="$NLOG" FAKE_NOTION_GET_FAIL="$U" NOTION_TOKEN=fake HARNESS_ROOT="$TMP/ntroot" bash "$LEDGER" ready --json 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
step "ready 중 후보 페이지 GET 실패 → rc≠0 · stderr 에 HTTP 500 (U 가 ready 에 들지 않는다)" \
  bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q 500' _ "$RC" "$ERR"
: > "$NLOG"
nrun dep add "$U" "$T"
step "dep add A B → A 의 Blocked by 에 기존(F) + B(T) 를 PATCH" \
  bash -c '[ "$1" -eq 0 ] && jq -e --arg f "$3" --arg t "$4" ".properties[\"Blocked by\"].relation | map(.id) | sort == ([\$f, \$t] | sort)" "$2" >/dev/null' _ "$RC" "$(body_of PATCH "pages/$U")" "$F" "$T"
: > "$NLOG"
printf '{"from":"%s","to":"%s"}\n' "$U" "$E" | PATH="$NPATH" FAKE_CURL_LOG="$NLOG" NOTION_TOKEN=fake HARNESS_ROOT="$TMP/ntroot" bash "$LEDGER" dep add --file - >/dev/null 2>&1; rc=$?
step "dep add --file - (JSONL) 도 같은 PATCH 를 낸다" \
  bash -c '[ "$1" -eq 0 ] && jq -e --arg e "$3" ".properties[\"Blocked by\"].relation | map(.id) | index(\$e) != null" "$2" >/dev/null' _ "$rc" "$(body_of PATCH "pages/$U")" "$E"
: > "$NLOG"
nrun note "$E" "메모 하나"
step "note → PATCH blocks/<id>/children 문단" \
  bash -c '[ "$1" -eq 0 ] && jq -e ".children[0].paragraph.rich_text[0].text.content == \"메모 하나\"" "$2" >/dev/null' _ "$RC" "$(body_of PATCH "blocks/$E/children")"
: > "$NLOG"
nrun close "$E" --reason-file "$TMP/nt-body.txt"
step "close --reason-file → Status=closed PATCH + 사유 블록" \
  bash -c '[ "$1" -eq 0 ] && jq -e ".properties.Status.select.name == \"closed\"" "$2" >/dev/null && jq -e ".children[0].paragraph.rich_text[0].text.content == \"본문\"" "$3" >/dev/null' _ "$RC" "$(body_of PATCH "pages/$E")" "$(body_of PATCH "blocks/$E/children")"
: > "$NLOG"
nrun update "$E" --claim --actor "skills sess-abc"
step "update --claim --actor → Status=in_progress · Assignee · ACTOR: 블록" \
  bash -c '[ "$1" -eq 0 ] && jq -e ".properties.Status.select.name == \"in_progress\" and .properties.Assignee.rich_text[0].text.content == \"skills sess-abc\"" "$2" >/dev/null && jq -e ".children[0].paragraph.rich_text[0].text.content == \"ACTOR: skills sess-abc\"" "$3" >/dev/null' _ "$RC" "$(body_of PATCH "pages/$E")" "$(body_of PATCH "blocks/$E/children")"
: > "$NLOG"
nrun update "$E" --status deferred
step "update --status deferred → Status=deferred" bash -c 'jq -e ".properties.Status.select.name == \"deferred\"" "$1" >/dev/null' _ "$(body_of PATCH "pages/$E")"
: > "$NLOG"
nrun label add "$E" slug:r1-x
step "label add → 기존 Labels + 새 라벨 PATCH" bash -c 'jq -e ".properties.Labels.multi_select | map(.name) == [\"repo:harness\",\"slug:r1-x\"]" "$1" >/dev/null' _ "$(body_of PATCH "pages/$E")"
: > "$NLOG"
nrun label remove "$E" repo:harness
step "label remove → 뺀 Labels PATCH" bash -c 'jq -e ".properties.Labels.multi_select == []" "$1" >/dev/null' _ "$(body_of PATCH "pages/$E")"
: > "$NLOG"
nrun init
step "init (database_id 있음) → PATCH databases/<id> 에 Parent·Blocked by 자기 관계와 Description·Assignee" \
  bash -c '[ "$1" -eq 0 ] && jq -e ".properties | has(\"Parent\") and has(\"Blocked by\") and has(\"Description\") and has(\"Assignee\") and .Parent.relation.database_id == \"d0000000-0000-0000-0000-00000000000d\"" "$2" >/dev/null' _ "$RC" "$(body_of PATCH "databases/d0000000-0000-0000-0000-00000000000d")"
# ── 등록부 질의 (skills#145). rails 는 epic 의 rail: 라벨 + Assignee, sprints 는 Type 이 sprint 인
#    페이지의 Name·Status 다. 픽스처는 FAKE_NOTION_REGISTRY 로 갈아 끼운 별도 페이지 집합이다.
nreg() { # <FAKE_NOTION_REGISTRY 값> <인자…>
  local mode="$1"; shift
  OUT=$(PATH="$NPATH" FAKE_CURL_LOG="$NLOG" FAKE_NOTION_REGISTRY="$mode" NOTION_TOKEN="fake-token" HARNESS_ROOT="$TMP/ntroot" bash "$LEDGER" "$@" 2>"$TMP/err"); RC=$?
  ERR=$(cat "$TMP/err")
}
# ② 토큰 없음 — 종전 스텁은 토큰 검사 **앞**에 있어 토큰 없이도 답했다. 실제로 원장을 읽는 지금은
#    그럴 근거가 없다. 두 하위 명령 다 본다.
for sub in rails sprints; do
  OUT=$(env -u NOTION_TOKEN PATH="$NPATH" FAKE_CURL_LOG="$NLOG" FAKE_NOTION_REGISTRY=1 HARNESS_ROOT="$TMP/ntroot" bash "$LEDGER" "$sub" --json 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
  step "$sub: NOTION_TOKEN 없음 → rc≠0 · stderr 한 줄이 NOTION_TOKEN 을 든다" \
    bash -c '[ "$1" -ne 0 ] && [ "$(printf "%s\n" "$2" | grep -c .)" -eq 1 ] && printf "%s" "$2" | grep -q NOTION_TOKEN' _ "$RC" "$ERR"
done
nreg 1 rails --json
step "rails: id 는 epic 의 rail: 라벨이고 owner 는 그 페이지의 Assignee다 · 닫힌 epic 도 든다(--all)" \
  bash -c '[ "$2" -eq 0 ] && printf "%s" "$1" | jq -e "map(.id) == [\"r1\",\"r2\"] and .[0].owner == \"juhyeon-cha\" and .[1].owner == \"dongqdev\"" >/dev/null' _ "$OUT" "$RC"
step "rails: Assignee 가 빈 epic(r3)은 빠지고 그 사실이 stderr 로 나온다 (rc 는 0 — 나머지 결과는 온전하다)" \
  bash -c '[ "$1" -eq 0 ] && printf "%s" "$2" | grep -q Assignee && ! printf "%s" "$3" | jq -e "any(.id == \"r3\")" >/dev/null' _ "$RC" "$ERR" "$OUT"
nreg conflict rails --json
step "rails: 한 레일의 epic 들이 서로 다른 Assignee 를 가리키면 rc≠0 (Assignee 가 rich_text 라 오타가 이 모양으로만 드러난다)" \
  bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q r1' _ "$RC" "$ERR"
nreg 1 sprints --json
step "sprints: id 는 Name 이고 status 는 Status select 다 (closed→closed · 그 밖→active)" \
  bash -c '[ "$2" -eq 0 ] && printf "%s" "$1" | jq -e ". == [{id:\"2026-S01\",status:\"closed\"},{id:\"2026-S02\",status:\"active\"}]" >/dev/null' _ "$OUT" "$RC"
step "sprints: 계약의 status 는 둘뿐이다" \
  bash -c 'printf "%s" "$1" | jq -e "all(.status == \"active\" or .status == \"closed\")" >/dev/null' _ "$OUT"
# 스프린트 페이지가 0건인 것은 정상 상태다 — rc 0 의 빈 배열이되 그것이 "읽지 못했다" 가 아님을 밝힌다
# (notion 에는 필드가 없어 github 의 "필드가 없다" 대조가 이 백엔드에서는 성립하지 않는다).
nreg "" sprints --json
step "sprints: Type 이 sprint 인 페이지가 0건 → rc 0 의 빈 배열이고 stderr 가 그것이 '스프린트가 없다' 임을 밝힌다" \
  bash -c '[ "$2" -eq 0 ] && printf "%s" "$1" | jq -e "length == 0" >/dev/null && printf "%s" "$3" | grep -q sprint' _ "$OUT" "$RC" "$ERR"
# ── 스프린트 등재 (skills#181). 이 백엔드에서 스프린트는 같은 DB 의 페이지 한 장이므로 등재도
#    페이지 한 장을 만드는 것이다 — **위 sprints 가 읽는 모양 그대로**여야 왕복이 성립한다.
#    (계획 문서 몇 곳이 이 자리를 "select option" 이라 적었었다 — skills#182 가 고쳤다. 낡은 것은
#     그 서술이지 메커니즘이 아니다: Notion 에서 상태를 가질 수 있는 것은 페이지뿐이라, select
#     option 을 더해도 sprints 는 그것을 내지 못한다. 읽는 자리와 같은 모양으로 쓴다.)
: > "$NLOG"
nreg 1 sprint-add 2026-S03
step "sprint-add notion: Type=sprint · Name=<ID> · Status=open 페이지 한 장을 만든다 (sprints 가 읽는 모양)" \
  bash -c '[ "$1" -eq 0 ] && jq -e ".parent.database_id == \"d0000000-0000-0000-0000-00000000000d\" and .properties.Type.select.name == \"sprint\" and .properties.Name.title[0].text.content == \"2026-S03\" and .properties.Status.select.name == \"open\"" "$2" >/dev/null' _ "$RC" "$(body_of POST pages)"
: > "$NLOG"
nreg 1 sprint-add 2026-S02
step "sprint-add notion: 이미 있는 ID → rc≠0 · stderr 가 그 ID 를 든다 · 페이지를 만들지 않는다" \
  bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q "2026-S02" && ! grep -q "POST pages$" "$3"' _ "$RC" "$ERR" "$NLOG"

nreg 1 rails --all
step "rails: --json 밖의 인자 → rc≠0" [ "$RC" -ne 0 ]

nrun dolt push
step "beads 전용 명령(dolt) → rc≠0" [ "$RC" -ne 0 ]

if [ "$fail" -ne 0 ]; then
  echo "✗ 원장 어댑터 검사 실패 — 위 항목을 고쳐라"
  exit 1
fi
echo "✓ 원장 어댑터 검사 통과 — 경계 · has-ui 계약(세 백엔드) · $EQUIV_LABEL · beads 왕복 · github 오프라인 · notion 오프라인"
