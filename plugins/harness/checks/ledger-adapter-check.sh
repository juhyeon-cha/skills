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
#      실제 GitHub 에 닿는 쓰기 실증은 오케스트레이터가 실증 레포에서 돈다(harness-m8gg.4.2 acceptance 4).
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

echo "── ④ github 오프라인 — 가짜 gh ──"
# jq·bash 만 보이고 gh 는 없는 PATH. 가짜 gh 는 호출 전부를 LOG 에 남기고 정해진 답을 낸다.
mkdir -p "$TMP/jqbin" "$TMP/ghbin"
ln -s "$(command -v jq)" "$TMP/jqbin/jq"
NOGH_PATH="$TMP/jqbin:/usr/bin:/bin"
GH="$TMP/ghbin"; mkdir -p "$GH"
cat > "$GH/repos.json" <<'EOF'
{"repos":[{"name":"harness","url":"https://github.com/juhyeon-cha/harness.git","default_branch":"master","check":"true","bootstrap":""}]}
EOF
printf '{"backend":"github","owner":"juhyeon-cha","project":4}\n' > "$GH/ledger.json"
LOG="$TMP/gh.log"
cat > "$TMP/ghbin/gh" <<'FAKE'
#!/usr/bin/env bash
# 가짜 gh — 호출을 기록하고 정해진 답을 낸다. 판정은 기록과 답의 형태로 한다.
printf '%s\n' "$*" >> "$FAKE_GH_LOG"
node() { # <번호> <제목> <상태> <라벨 JSON> <부모 JSON> <본문>
  printf '{"id":"NODE_%s","databaseId":100%s,"number":%s,"title":"%s","state":"%s","body":"%s","createdAt":"2026-09-05T00:00:00Z","updatedAt":"2026-09-05T00:00:00Z","closedAt":null,"repository":{"name":"harness"},"labels":{"nodes":%s},"assignees":{"nodes":[{"login":"juhyeon-cha"}]},"comments":{"nodes":[{"body":"메모"}]},"parent":%s}' \
    "$1" "$1" "$1" "$2" "$3" "$6" "$4" "$5"
}
N57='[{"name":"type:epic"},{"name":"repo:harness"},{"name":"status:blocked"}]'
N58='[{"name":"type:feature"},{"name":"repo:harness"},{"name":"rail:r1"}]'
N59='[{"name":"type:task"},{"name":"repo:harness"}]'
case "$1 $2" in
  "auth status") [ -z "${FAKE_GH_AUTH_FAIL:-}" ] || exit 1; exit 0 ;;
  "label create"|"issue comment"|"issue close"|"issue edit"|"issue reopen"|"project item-add") exit 0 ;;
  "issue create")
    while [ $# -gt 0 ]; do [ "$1" = "-F" ] && cp "$2" "$FAKE_GH_LOG.body"; shift; done
    echo "https://github.com/juhyeon-cha/harness/issues/61"; exit 0 ;;
  "issue view") printf 'type:epic\nrepo:harness\nstatus:blocked\n'; exit 0 ;;
  "project view") echo '{"id":"PVT_x","number":4}'; exit 0 ;;
  "project create") echo '{"number":9}'; exit 0 ;;
  "api graphql")
    all="$*"
    case "$all" in
      *addSubIssue*) echo '{"data":{"addSubIssue":{}}}' ;;
      *"subIssues(first"*) printf '{"data":{"repository":{"issue":{"subIssues":{"nodes":[%s,%s]}}}}}' "$(node 58 피처 OPEN "$N58" '{"number":57,"repository":{"name":"harness"}}' "")" "$(node 59 태스크 CLOSED "$N59" '{"number":58,"repository":{"name":"harness"}}' "")" ;;
      *"issues(first"*) printf '[{"data":{"repository":{"issues":{"nodes":[%s,%s,%s]}}}}]' "$(node 57 에픽 OPEN "$N57" null '본문\n\n## Acceptance\n\n조건 1')" "$(node 58 피처 OPEN "$N58" '{"number":57,"repository":{"name":"harness"}}' "")" "$(node 59 태스크 CLOSED "$N59" null "")" ;;
      *"n=999"*) echo 'gh: Could not resolve to an Issue' >&2; exit 1 ;;
      *) printf '{"data":{"repository":{"issue":%s}}}' "$(node 57 에픽 OPEN "$N57" null '본문\n\n## Acceptance\n\n조건 1')" ;;
    esac; exit 0 ;;
  "api -X"|"api repos"*)
    path=""; for a in "$@"; do case "$a" in repos/*) path="$a" ;; esac; done
    case "$path" in
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

mkdir -p "$TMP/ghnoproj"; cp "$GH/repos.json" "$TMP/ghnoproj/"
printf '{"backend":"github","owner":"juhyeon-cha"}\n' > "$TMP/ghnoproj/ledger.json"
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
step "create 에 repo: 라벨도 --parent 도 없으면 rc≠0" [ "$RC" -ne 0 ]

grun show 'harness#57' --json
step "show --json 의 키가 bd 와 같다 (id·title·status·issue_type·labels·acceptance_criteria·notes·assignee·parent)" \
  bash -c 'printf "%s" "$1" | jq -e ".[0] | keys | contains([\"id\",\"title\",\"status\",\"issue_type\",\"labels\",\"acceptance_criteria\",\"notes\",\"assignee\",\"parent\",\"description\",\"dependencies\"])" >/dev/null' _ "$OUT"
step "show --json 의 값 대응: status:blocked 라벨→blocked · type:epic→epic · labels 에서 type:·status: 제거 · 코멘트→notes · 본문 절 분리" \
  bash -c 'printf "%s" "$1" | jq -e ".[0] | .id == \"harness#57\" and .status == \"blocked\" and .issue_type == \"epic\" and .labels == [\"repo:harness\"] and .notes == \"메모\" and .acceptance_criteria == \"조건 1\" and .description == \"본문\" and .assignee == \"juhyeon-cha\" and .parent == null and (.dependencies | length == 1) and .dependencies[0].id == \"harness#58\"" >/dev/null' _ "$OUT"
step "jq -r .[0].status 가 그대로 돈다" bash -c '[ "$(printf "%s" "$1" | jq -r ".[0].status")" = "blocked" ]' _ "$OUT"
grun show 'harness#999' --json
step "없는 id → rc≠0" [ "$RC" -ne 0 ]
grun show 57
step "형식 밖 id(번호만) → rc≠0" [ "$RC" -ne 0 ]
grun show 'nowhere#1'
step "repos.json 에 없는 레포 → rc≠0" [ "$RC" -ne 0 ]

grun children 'harness#57' --json
step "children --json 이 subIssues 2건을 parent 와 함께 낸다" \
  bash -c 'printf "%s" "$1" | jq -e "length == 2 and .[0].id == \"harness#58\" and .[0].parent == \"harness#57\" and .[1].status == \"closed\"" >/dev/null' _ "$OUT"
grun list --json
step "list --json 은 closed 를 뺀다 (3건 중 2건)" bash -c 'printf "%s" "$1" | jq -e "length == 2" >/dev/null' _ "$OUT"
grun list --all --json -n 0
step "list --all --json -n 0 은 전부 낸다 (3건)" bash -c 'printf "%s" "$1" | jq -e "length == 3" >/dev/null' _ "$OUT"
grun list -l repo:harness,rail:r1 --status open --json
step "list -l a,b --status open 은 AND 로 거른다 (58 만)" bash -c 'printf "%s" "$1" | jq -e "length == 1 and .[0].id == \"harness#58\"" >/dev/null' _ "$OUT"
grun list --label-pattern 'rail:*' --all --json
step "list --label-pattern glob (rail:* → 58 만)" bash -c 'printf "%s" "$1" | jq -e "length == 1 and .[0].id == \"harness#58\"" >/dev/null' _ "$OUT"
grun list -t task --all --json
step "list -t task (59 만)" bash -c 'printf "%s" "$1" | jq -e "length == 1 and .[0].id == \"harness#59\"" >/dev/null' _ "$OUT"
grun ready --json
step "ready 는 open 이고 blocked_by 가 전부 closed 인 것만 (57 은 58 에 막혀 빠지고, 58 은 든다)" \
  bash -c 'printf "%s" "$1" | jq -e "map(.id) == [\"harness#58\"]" >/dev/null' _ "$OUT"

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

if [ "$fail" -ne 0 ]; then
  echo "✗ 원장 어댑터 검사 실패 — 위 항목을 고쳐라"
  exit 1
fi
echo "✓ 원장 어댑터 검사 통과 — 경계 · beads 동등성 · beads 왕복 · github 오프라인"
