#!/usr/bin/env bash
# 단언은 bash -c '…' 안의 jq 식이다 — 그 안의 $1·$OUT 같은 것은 이 셸이 아니라 자식 셸·jq 의
# 변수이므로 단일 인용이 맞다. 이 파일 전체에서 SC2016 을 끈다(맨 shellcheck 도 rc 0 이 되게).
# shellcheck disable=SC2016
#
# 게이트: 이전 도구(scripts/ledger-migrate.sh)를 픽스처로 단언한다. 네트워크에 닿지 않는다.
#
#   ① plan   — 가짜 bd 의 원장에서 열린 항목만 · repo 결정 규칙 · 본문 첫 줄 · 라벨 · deps · notes.
#   ② plan 실패 경로 — repos.json 에 없는 레포 라벨이면 rc 1 이고 stdout 에 아무것도 내지 않는다.
#   ③ apply  — 위상 순(부모·의존 먼저) · 이슈 생성 · map 기록 · 2회 실행 뒤 이슈 수가 늘지 않는다(멱등).
#   ④ apply 실패 경로 — gh 가 죽는 항목에서 멈추고 rc 1, map 에는 성공한 것까지만. --plan 없으면 rc 1.
#   ⑤ verify — 전부 같으면 rc 0 과 "verify: N/N 일치" · 라벨을 하나 지우면 rc 1 과 그 id·필드 ·
#      map 이 plan 보다 짧으면 rc 1("옮기지 않은 항목 K건") · Project 가 없거나 번호가 다르면 rc 1.
#   ⑥ 미완(PENDING) 줄 청소 — 이슈가 있으면 지우고 그 항목만 다시 만든다(완료 줄은 건너뛴다) ·
#      이슈가 이미 없으면(HTTP 404) 경고만 남기고 줄을 버린다 · 404 가 아닌 사유로 확인조차
#      못 하면 줄을 남긴 채 죽는다(rc≠0 을 "없다"로 읽으면 다음 실행이 중복 이슈를 만든다).
#
# 가짜 gh 는 **실측 payload 형태**를 낸다 — 코드가 기대하는 모양을 흉내 내면 단언이 거짓 통과한다.
# 특히 Project 소속: GraphQL 은 projectItems.nodes[].project.number 를 싣고, REST(gh issue view
# --json projectItems)는 번호 없이 status·title 만 낸다(2026-09-06 실측). 두 형태가 그대로 있다.
#
# 실제 GitHub 에 닿는 실증(Project 소속·색인 지연)은 오케스트레이터가 실증 레포에서 돈다
# (harness-kw0l.2.1 acceptance 5 · 2.2 acceptance 4).
# set -e 를 쓰지 않는다 — 첫 실패에서 죽으면 나머지 사유가 보고되지 않는다.
set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MIG="$PLUGIN_ROOT/scripts/ledger-migrate.sh"
command -v jq >/dev/null 2>&1 || { echo "✗ jq 가 없다 — 이 검사는 jq 없이 판정할 수 없다" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail=0
step() { local label="$1"; shift; if "$@"; then echo "  ✓ ${label}"; else echo "  ✗ FAILED: ${label}"; fail=1; fi; }

BIN="$TMP/bin"; mkdir -p "$BIN"
ln -s "$(command -v jq)" "$BIN/jq"
export PATH="$BIN:/usr/bin:/bin"

# ── 픽스처 루트 ───────────────────────────────────────────────────────
ROOT="$TMP/root"; mkdir -p "$ROOT"
cat > "$ROOT/repos.json" <<'EOF'
{"repos":[
  {"name":"skills","url":"https://github.com/juhyeon-cha/skills.git"},
  {"name":"sap-harness","url":"https://github.com/juhyeon-cha/sap-harness.git"},
  {"name":"ghost","url":"https://github.com/juhyeon-cha/ghost.git"}
]}
EOF
printf '{"backend":"github","owner":"juhyeon-cha","project":4}\n' > "$ROOT/ledger.json"

# 가짜 bd — list --all --json 과 show --json <id…> 만 낸다. 원장 내용은 $FAKE_BD_DATA 가 든다.
cat > "$BIN/bd" <<'FAKEBD'
#!/usr/bin/env bash
args=(); while [ $# -gt 0 ]; do case "$1" in -C) shift 2 ;; *) args+=("$1"); shift ;; esac; done
case "${args[0]}" in
  list) jq '.' "$FAKE_BD_DATA" ;;
  show)
    ids='[]'
    for a in "${args[@]:1}"; do case "$a" in --json|show) ;; *) ids="$(printf '%s' "$ids" | jq --arg i "$a" '. + [$i]')" ;; esac; done
    jq --argjson ids "$ids" 'map(select(.id as $i | $ids | index($i)))' "$FAKE_BD_DATA" ;;
  *) echo "fake bd: 모르는 명령 ${args[0]}" >&2; exit 1 ;;
esac
FAKEBD
chmod +x "$BIN/bd"

# 가짜 gh — 이슈 상태를 $FAKE_GH_STATE 에 파일로 둔다(제목·본문·라벨·코멘트 수·부모·blocked_by·project).
# 호출은 전부 $FAKE_GH_LOG 에 남긴다. slug 에 ghost 가 들면 issue create 가 죽는다(실패 경로용).
# FAKE_GH_NET_FAIL=1 이면 auth status 말고 전부 통신 장애로 죽는다 — 404 와 장애를 가르는지 본다.
# 없는 이슈의 조회·삭제는 **실측 문구 그대로** "gh: Not Found (HTTP 404)" 를 stderr 에 낸다.
cat > "$BIN/gh" <<'FAKEGH'
#!/usr/bin/env bash
S="$FAKE_GH_STATE"; printf '%s\n' "$*" >> "$FAKE_GH_LOG"
arg_after() { local k="$1"; shift; while [ $# -gt 0 ]; do [ "$1" = "$k" ] && { printf '%s' "$2"; return; }; shift; done; }
kv() { local k="$1"; shift; for a in "$@"; do case "$a" in "$k"=*) printf '%s' "${a#*=}"; return ;; esac; done; }
if [ -n "${FAKE_GH_NET_FAIL:-}" ] && [ "$1 $2" != "auth status" ]; then
  echo "dial tcp: lookup api.github.com: no such host" >&2; exit 1
fi
case "$1 $2" in
  "auth status") exit 0 ;;
  "label create") exit 0 ;;
  "issue delete")
    n="$3"
    [ -f "$S/$n.title" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
    rm -f "$S/$n".*; exit 0 ;;
  "issue create")
    slug="$(arg_after -R "$@")"
    case "$slug" in *ghost*) echo "gh: could not create issue" >&2; exit 1 ;; esac
    n=$(( $(cat "$S/counter" 2>/dev/null || echo 100) + 1 )); echo "$n" > "$S/counter"
    arg_after -t "$@" > "$S/$n.title"; cp "$(arg_after -F "$@")" "$S/$n.body"
    arg_after -l "$@" | tr ',' '\n' | grep -v '^$' | sort > "$S/$n.labels"
    printf '%s' "$slug" > "$S/$n.repo"; : > "$S/$n.blocked"; echo 0 > "$S/$n.comments"
    echo "https://github.com/$slug/issues/$n"; exit 0 ;;
  "issue comment")
    n="$3"; echo $(( $(cat "$S/$n.comments") + 1 )) > "$S/$n.comments"; exit 0 ;;
  "issue view")
    # 실측 payload 그대로(2026-09-06): REST 의 projectItems 에는 **번호가 없고** status·title 뿐이다.
    # 코드가 기대하는 모양을 흉내 내지 않는다 — 여기로 Project 판정을 되돌리면 단언이 붉어진다.
    printf '{"projectItems":[{"status":{"name":"Todo"},"title":"harness-ledger-probe"}]}'; exit 0 ;;
  "project item-add")
    url="$(arg_after --url "$@")"; echo "$2x" >/dev/null; printf '%s' "$3" > "$S/${url##*/}.project"; exit 0 ;;
  "api graphql")
    if printf '%s' "$*" | grep -q addSubIssue; then
      p="$(kv p "$@")"; c="$(kv c "$@")"; p="${p#NODE_}"; c="${c#NODE_}"
      printf '%s#%s' "$(basename "$(cat "$S/$p.repo")")" "$p" > "$S/$c.parent"
      echo '{"data":{"addSubIssue":{"issue":{"number":0}}}}'; exit 0
    fi
    n="$(kv n "$@")"
    par='null'
    if [ -s "$S/$n.parent" ]; then
      pv="$(cat "$S/$n.parent")"
      par="$(jq -n --arg r "${pv%%#*}" --argjson n "${pv##*#}" '{number: $n, repository: {name: $r}}')"
    fi
    # GraphQL 의 projectItems 는 REST 와 형태가 다르다 — nodes[].project.number 로 번호가 실려 온다.
    pi='{"nodes":[]}'
    [ -s "$S/$n.project" ] && pi="$(jq -n --argjson p "$(cat "$S/$n.project")" '{nodes: [{project: {number: $p}}]}')"
    jq -n --rawfile t "$S/$n.title" --rawfile b "$S/$n.body" --rawfile l "$S/$n.labels" \
       --argjson c "$(cat "$S/$n.comments")" --argjson par "$par" --argjson pi "$pi" \
       '{data: {repository: {issue: {
          title: ($t | rtrimstr("\n")), body: $b,
          labels: {nodes: ($l | split("\n") | map(select(. != "")) | map({name: .}))},
          comments: {totalCount: $c}, parent: $par, projectItems: $pi}}}}'
    exit 0 ;;
esac
# api repos/<slug>/issues/<n>[…]
path=""; for a in "$@"; do case "$a" in repos/*) path="$a" ;; esac; done
case "$path" in
  */dependencies/blocked_by)
    n="${path%/dependencies/blocked_by}"; n="${n##*/}"
    if printf '%s' "$*" | grep -q -- '-X POST'; then
      id="$(kv issue_id "$@")"; printf '%s\n' "$(( id - 1000 ))" >> "$S/$n.blocked"; exit 0
    fi
    printf '['; sep=""
    while read -r b; do
      [ -n "$b" ] || continue
      printf '%s{"number":%s,"repository_url":"https://api.github.com/repos/%s"}' "$sep" "$b" "$(cat "$S/$b.repo")"; sep=","
    done < "$S/$n.blocked"
    printf ']\n'; exit 0 ;;
  repos/*/issues/*)
    n="${path##*/}"
    [ -f "$S/$n.title" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
    case "$*" in *.node_id*) echo "NODE_$n" ;; *) echo "$(( n + 1000 ))" ;; esac; exit 0 ;;
esac
echo "fake gh: 모르는 호출 $*" >&2; exit 1
FAKEGH
chmod +x "$BIN/gh"

STATE="$TMP/ghstate"; mkdir -p "$STATE"
export FAKE_GH_STATE="$STATE" FAKE_GH_LOG="$TMP/gh.log"; : > "$FAKE_GH_LOG"

# 원장 픽스처 — x-2 를 맨 앞에 두어 위상 정렬(부모 x-1·의존 x-3 이 먼저)을 판정한다.
# x-5 의 부모 x-4 는 **닫혀 있어** plan 배열 밖이다 — 전수 plan 에서도 나는 형태다(실측 146건 중 12건).
cat > "$TMP/beads.json" <<'EOF'
[
 {"id":"x-2","title":"자식 태스크","status":"in_progress","issue_type":"task","assignee":"sess-abc",
  "description":"자식 본문","acceptance_criteria":"조건 2","notes":"메모 한 줄\n\n메모 둘",
  "labels":["repo:sap-harness","rail:r1"],"parent":"x-1",
  "dependencies":[{"id":"x-1","dependency_type":"parent-child"},{"id":"x-3","dependency_type":"blocks"}]},
 {"id":"x-1","title":"부모 에픽","status":"open","issue_type":"epic","description":"부모 본문",
  "acceptance_criteria":"조건 1","labels":["harness","repo:harness","sprint:2026-S02"],"parent":null,"dependencies":[]},
 {"id":"x-3","title":"라벨 없는 버그","status":"blocked","issue_type":"bug","description":"버그 본문",
  "labels":[],"parent":null,"dependencies":[]},
 {"id":"x-4","title":"닫힌 것","status":"closed","issue_type":"task","labels":["repo:skills"],"parent":null,"dependencies":[]},
 {"id":"x-5","title":"미룬 것","status":"deferred","issue_type":"task","description":"","labels":["repo:sap-harness"],"parent":"x-4","dependencies":[]}
]
EOF
export FAKE_BD_DATA="$TMP/beads.json"

# 하위 명령마다 stderr 를 모아 둔다 — 마지막 절(⑥)이 셸 오류가 섞이지 않았는지 전수로 본다.
# (2026-09-06 실증: apply 의 EXIT 트랩이 "tmp: unbound variable" 을 냈는데 rc 는 0 이라 31 단언이
#  전부 통과했다. stderr 를 보지 않는 검사는 이 부류를 못 잡는다.)
run() { OUT=$(bash "$MIG" "$@" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err"); cat "$TMP/err" >> "$TMP/err-$1"; }
OUT=""; ERR=""; RC=0

echo "── ① plan ──"
run plan --from "$ROOT"
step "plan rc 0" [ "$RC" -eq 0 ]
step "닫힌 항목을 뺀 4건" bash -c 'printf "%s" "$1" | jq -e "length == 4" >/dev/null' _ "$OUT"
step "repo 규칙: repo:harness→skills · 라벨 없음→skills · 그 밖은 그대로" \
  bash -c 'printf "%s" "$1" | jq -e "(map({(.id): .repo}) | add) == {\"x-1\":\"skills\",\"x-2\":\"sap-harness\",\"x-3\":\"skills\",\"x-5\":\"sap-harness\"}" >/dev/null' _ "$OUT"
step "본문 첫 줄이 beads: <id> 이고 그 뒤 description · ## Acceptance 절" \
  bash -c 'printf "%s" "$1" | jq -e ".[] | select(.id == \"x-1\") | .body == \"beads: x-1\n\n부모 본문\n\n## Acceptance\n\n조건 1\"" >/dev/null' _ "$OUT"
step "부모가 plan 밖(닫힌 x-4)이면 본문 둘째 줄이 beads-parent: <부모 id>" \
  bash -c 'printf "%s" "$1" | jq -e ".[] | select(.id == \"x-5\") | .body == \"beads: x-5\nbeads-parent: x-4\"" >/dev/null' _ "$OUT"
step "부모가 plan 안이면 beads-parent 줄이 없다" \
  bash -c 'printf "%s" "$1" | jq -e "all(.[] | select(.id == \"x-2\"); .body | contains(\"beads-parent\") | not)" >/dev/null' _ "$OUT"
step "acceptance 가 없는 항목의 본문에는 ## Acceptance 절이 없다" \
  bash -c 'printf "%s" "$1" | jq -e ".[] | select(.id == \"x-3\") | .body == \"beads: x-3\n\n버그 본문\"" >/dev/null' _ "$OUT"
step "labels 는 원 라벨 그대로(repo: 포함)이고 type:·status: 를 담지 않는다" \
  bash -c 'printf "%s" "$1" | jq -e ".[] | select(.id == \"x-1\") | .labels == [\"harness\",\"repo:harness\",\"sprint:2026-S02\"]" >/dev/null' _ "$OUT"
step "deps 는 blocked_by 만 (parent-child 는 빼고 parent 로만 든다)" \
  bash -c 'printf "%s" "$1" | jq -e ".[] | select(.id == \"x-2\") | .deps == [\"x-3\"] and .parent == \"x-1\"" >/dev/null' _ "$OUT"
step "notes 는 이슈당 원소 하나다 — 블롭을 줄로 쪼개지 않고 ACTOR 는 같은 원소 뒤에 붙는다" \
  bash -c 'printf "%s" "$1" | jq -e ".[] | select(.id == \"x-2\") | .notes == [\"메모 한 줄\n\n메모 둘\n\nACTOR: sess-abc\"]" >/dev/null' _ "$OUT"
step "note 가 없는 항목의 notes 는 빈 배열 · 전 항목의 원소 수가 1 이하" \
  bash -c 'printf "%s" "$1" | jq -e "(map(.notes|length)|max) == 1 and (.[] | select(.id == \"x-1\") | .notes) == []" >/dev/null' _ "$OUT"
run plan --from "$ROOT" --only x-1,x-3 --label probe:kw0l
step "--only 가 고른 것만 · --label 이 전 항목에 붙는다" \
  bash -c 'printf "%s" "$1" | jq -e "length == 2 and ([.[].id] == [\"x-1\",\"x-3\"]) and all(.[]; .labels | index(\"probe:kw0l\"))" >/dev/null' _ "$OUT"

echo "── ② plan 실패 경로 ──"
jq '. + [{"id":"x-9","title":"없는 레포","status":"open","issue_type":"task","labels":["repo:nowhere"],"parent":null,"dependencies":[]}]' \
  "$TMP/beads.json" > "$TMP/beads-bad.json"
OUT=$(FAKE_BD_DATA="$TMP/beads-bad.json" bash "$MIG" plan --from "$ROOT" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err")
step "repos.json 에 없는 레포 라벨 → rc 1 · stderr 가 그 id 를 든다 · stdout 은 비어 있다" \
  bash -c '[ "$1" -eq 1 ] && [ -z "$2" ] && printf "%s" "$3" | grep -q "x-9"' _ "$RC" "$OUT" "$ERR"

echo "── ③ apply · 멱등 ──"
bash "$MIG" plan --from "$ROOT" > "$TMP/plan.json" 2>/dev/null
MAP="$TMP/map.txt"; : > "$MAP"
run apply --from "$ROOT" --plan "$TMP/plan.json" --map "$MAP"
step "apply rc 0" [ "$RC" -eq 0 ]
step "map 이 4줄 · <beads id> <repo>#<번호> 형태" \
  bash -c '[ "$(grep -c . "$1")" -eq 4 ] && grep -qE "^x-1 skills#[0-9]+$" "$1" && grep -qE "^x-2 sap-harness#[0-9]+$" "$1"' _ "$MAP"
step "위상 순 — 부모 x-1 과 의존 x-3 이 x-2 보다 먼저 만들어졌다" \
  bash -c '[ "$(grep -n "^x-1 " "$1" | cut -d: -f1)" -lt "$(grep -n "^x-2 " "$1" | cut -d: -f1)" ] && [ "$(grep -n "^x-3 " "$1" | cut -d: -f1)" -lt "$(grep -n "^x-2 " "$1" | cut -d: -f1)" ]' _ "$MAP"
step "쓰기 순서: issue create → project item-add → issue comment (한 항목 안에서)" \
  bash -c 'c=$(grep -n "^issue create" "$1" | head -1 | cut -d: -f1); p=$(grep -n "^project item-add" "$1" | head -1 | cut -d: -f1); m=$(grep -n "^issue comment" "$1" | head -1 | cut -d: -f1); [ "$c" -lt "$p" ] && [ "$p" -lt "$m" ]' _ "$FAKE_GH_LOG"
step "type: 라벨과 status: 라벨을 붙인다 (open 은 status: 없음)" \
  bash -c 'grep -q -- "-l harness,repo:harness,sprint:2026-S02,type:epic$" "$1" && grep -q -- "status:in_progress" "$1" && grep -q -- "status:blocked" "$1"' _ "$FAKE_GH_LOG"
step "note 가 있는 항목(x-2)당 코멘트를 **한 번** 부른다 — 블롭을 줄로 쪼개지 않는다" \
  bash -c '[ "$(grep -c "^issue comment" "$1")" -eq 1 ]' _ "$FAKE_GH_LOG"
step "코멘트 본문은 -b 가 아니라 -F 파일로 넘긴다 (41001자를 argv 에 싣지 않는다)" \
  bash -c 'grep "^issue comment" "$1" | grep -q -- "-F " && ! grep "^issue comment" "$1" | grep -q -- "-b "' _ "$FAKE_GH_LOG"
step "sub-issue 와 blocked_by 를 건다" \
  bash -c 'grep -q addSubIssue "$1" && grep -q "dependencies/blocked_by" "$1"' _ "$FAKE_GH_LOG"
before=$(grep -c '^issue create' "$FAKE_GH_LOG")
run apply --from "$ROOT" --plan "$TMP/plan.json" --map "$MAP"
after=$(grep -c '^issue create' "$FAKE_GH_LOG")
step "같은 map 으로 다시 돌리면 이슈 수가 늘지 않는다(멱등) · map 도 4줄 그대로" \
  bash -c '[ "$1" -eq 0 ] && [ "$2" -eq "$3" ] && [ "$(grep -c . "$4")" -eq 4 ]' _ "$RC" "$before" "$after" "$MAP"

echo "── ④ apply 실패 경로 ──"
run apply --from "$ROOT" --map "$TMP/m2.txt"
step "--plan 없이 apply → rc 1" [ "$RC" -eq 1 ]
jq '[.[] | select(.id == "x-3")] + [{"id":"x-8","repo":"ghost","type":"task","status":"open","title":"유령","body":"beads: x-8","labels":[],"parent":null,"deps":[],"notes":[]}]' \
  "$TMP/plan.json" > "$TMP/plan-ghost.json"
MAP2="$TMP/map2.txt"; : > "$MAP2"
run apply --from "$ROOT" --plan "$TMP/plan-ghost.json" --map "$MAP2"
step "gh 가 죽는 항목에서 멈추고 rc 1 · map 에는 성공한 것까지만(1줄) · stderr 가 그 id 를 든다" \
  bash -c '[ "$1" -eq 1 ] && [ "$(grep -c . "$2")" -eq 1 ] && grep -q "^x-3 " "$2" && printf "%s" "$3" | grep -q "x-8"' _ "$RC" "$MAP2" "$ERR"

echo "── ⑤ verify ──"
run verify --from "$ROOT" --plan "$TMP/plan.json" --map "$MAP"
step "옮긴 결과가 plan 과 같으면 rc 0 · 마지막 줄이 verify: 4/4 일치" \
  bash -c '[ "$1" -eq 0 ] && [ "$(printf "%s\n" "$2" | tail -1)" = "verify: 4/4 일치" ]' _ "$RC" "$OUT"
n1="$(awk '$1 == "x-1" { print $2 }' "$MAP")"; n1="${n1##*#}"
cp "$STATE/$n1.labels" "$TMP/labels.bak"
grep -v '^sprint:2026-S02$' "$TMP/labels.bak" > "$STATE/$n1.labels"
run verify --from "$ROOT" --plan "$TMP/plan.json" --map "$MAP"
step "라벨 하나를 지우면 rc 1 이고 그 id 와 필드(labels)가 출력에 있다" \
  bash -c '[ "$1" -eq 1 ] && printf "%s" "$2" | grep -q "x-1" && printf "%s" "$2" | grep -q labels' _ "$RC" "$OUT"
cp "$TMP/labels.bak" "$STATE/$n1.labels"
run verify --from "$ROOT" --plan "$TMP/plan.json" --map "$MAP"
step "되돌리면 다시 rc 0" [ "$RC" -eq 0 ]
grep -v '^x-5 ' "$MAP" > "$TMP/map-short.txt"
run verify --from "$ROOT" --plan "$TMP/plan.json" --map "$TMP/map-short.txt"
step "map 에 없는 plan 항목이 있으면 rc 1 이고 '옮기지 않은 항목 1건'" \
  bash -c '[ "$1" -eq 1 ] && printf "%s" "$2" | grep -q "옮기지 않은 항목 1건" && printf "%s" "$2" | grep -q "x-5"' _ "$RC" "$OUT"
c1="$(cat "$STATE/$n1.comments")"; echo 9 > "$STATE/$n1.comments"
run verify --from "$ROOT" --plan "$TMP/plan.json" --map "$MAP"
step "코멘트 수가 notes 줄 수와 다르면 rc 1" \
  bash -c '[ "$1" -eq 1 ] && printf "%s" "$2" | grep -q "코멘트 수"' _ "$RC" "$OUT"
printf '%s\n' "$c1" > "$STATE/$n1.comments"
n2="$(awk '$1 == "x-2" { print $2 }' "$MAP")"; n2="${n2##*#}"
mv "$STATE/$n2.parent" "$TMP/parent.bak"
run verify --from "$ROOT" --plan "$TMP/plan.json" --map "$MAP"
step "sub-issue 가 없으면 rc 1 이고 parent 가 출력에 있다" \
  bash -c '[ "$1" -eq 1 ] && printf "%s" "$2" | grep -q "x-2" && printf "%s" "$2" | grep -q parent' _ "$RC" "$OUT"
mv "$TMP/parent.bak" "$STATE/$n2.parent"
mv "$STATE/$n2.project" "$TMP/project.bak"
run verify --from "$ROOT" --plan "$TMP/plan.json" --map "$MAP"
step "Project 소속이 없으면 rc 1 이고 그 id 가 출력에 있다" \
  bash -c '[ "$1" -eq 1 ] && printf "%s" "$2" | grep -q "x-2" && printf "%s" "$2" | grep -q Project' _ "$RC" "$OUT"
printf '7\n' > "$STATE/$n2.project"
run verify --from "$ROOT" --plan "$TMP/plan.json" --map "$MAP"
step "다른 Project(#7)에 들어 있으면 rc 1 이고 기대·실제 번호가 출력에 있다" \
  bash -c '[ "$1" -eq 1 ] && printf "%s" "$2" | grep -q "x-2" && printf "%s" "$2" | grep -q "기대 \[project 4\] 실제 \[7\]"' _ "$RC" "$OUT"
mv "$TMP/project.bak" "$STATE/$n2.project"
step "가짜 gh 의 REST projectItems 에는 번호가 없다 — 실측 payload 형태다(2)" \
  bash -c 'gh issue view 1 -R juhyeon-cha/skills --json projectItems | jq -e "(.projectItems[0] | has(\"number\") or has(\"project\")) | not" >/dev/null'
run verify --from "$ROOT" --plan "$TMP/plan.json" --map "$MAP"
step "되돌리면 다시 rc 0 (verify 가 상태를 바꾸지 않는다)" [ "$RC" -eq 0 ]

echo "── ⑥ 미완(PENDING) 줄 청소 ──"
# 이번 변경의 핵심 경로다 — 앞선 실행이 이슈를 만든 뒤 코멘트·간선을 끝내기 전에 죽은 자리를
# 재실행이 어떻게 처리하는가. 셋을 가른다: 이슈가 있으면 지우고 다시 만든다 · 404 면 줄만
# 버린다 · 404 가 아닌 사유로 확인조차 못 하면 줄을 남긴 채 죽는다(중복 이슈를 만들지 않는다).
MAP3="$TMP/map3.txt"
n3="$(awk '$1 == "x-3" { print $2 }' "$MAP")"; n3="${n3##*#}"
awk '{ if ($1 == "x-3") print $1, $2, "PENDING"; else print }' "$MAP" > "$MAP3"
before3=$(grep -c '^issue create' "$FAKE_GH_LOG")
run apply --from "$ROOT" --plan "$TMP/plan.json" --map "$MAP3"
after3=$(grep -c '^issue create' "$FAKE_GH_LOG")
new3="$(awk '$1 == "x-3" { print $2 }' "$MAP3")"; new3="${new3##*#}"
step "미완 줄의 이슈를 지우고 그 항목만 다시 만든다 — 완료 줄 3개는 건너뛰어 생성이 +1 이다" \
  bash -c '[ "$1" -eq 0 ] && [ "$(( $3 - $2 ))" -eq 1 ] && [ "$4" != "$5" ] && [ ! -f "$6/$4.title" ]' \
  _ "$RC" "$before3" "$after3" "$n3" "$new3" "$STATE"
step "지운 자취가 남는다 — 그 번호로 gh issue delete 를 불렀다" \
  bash -c 'grep -q "^issue delete $2 " "$1"' _ "$FAKE_GH_LOG" "$n3"
step "청소 뒤 map 은 4줄이고 전부 완료 형태다(PENDING 이 남지 않는다)" \
  bash -c '[ "$(grep -c . "$1")" -eq 4 ] && [ "$(grep -cE "^[^ ]+ [^ ]+$" "$1")" -eq 4 ]' _ "$MAP3"
MAP4="$TMP/map4.txt"
awk '$1 == "x-3" { print $1, $2, "PENDING" }' "$MAP3" > "$MAP4"
rm -f "$STATE/$new3".*                      # 사람이 손으로 지운 상황 — 조회가 404 다
run apply --from "$ROOT" --plan "$TMP/plan.json" --map "$MAP4" --only x-3
step "미완 줄의 이슈가 이미 없으면(HTTP 404) 경고만 남기고 줄을 버려 다시 만든다" \
  bash -c '[ "$1" -eq 0 ] && printf "%s" "$2" | grep -q "이슈가 이미 없다" && [ "$(grep -cE "^x-3 [^ ]+$" "$3")" -eq 1 ]' \
  _ "$RC" "$ERR" "$MAP4"
MAP5="$TMP/map5.txt"
awk '$1 == "x-3" { print $1, $2, "PENDING" }' "$MAP4" > "$MAP5"; cp "$MAP5" "$TMP/map5.bak"
OUT=$(FAKE_GH_NET_FAIL=1 bash "$MIG" apply --from "$ROOT" --plan "$TMP/plan.json" --map "$MAP5" --only x-3 2>"$TMP/err")
RC=$?; ERR=$(cat "$TMP/err"); cat "$TMP/err" >> "$TMP/err-apply"
step "404 가 아닌 사유(통신 장애)면 죽는다 — 미완 줄을 버리지 않는다(다음 실행의 중복 이슈 방지)" \
  bash -c '[ "$1" -eq 1 ] && printf "%s" "$2" | grep -q "확인하지도 못했다" && cmp -s "$3" "$4"' \
  _ "$RC" "$ERR" "$MAP5" "$TMP/map5.bak"

echo "── ⑦ stderr ──"
# 의도된 stderr(배열 밖 부모·의존 경고, die 메시지)는 통과해야 한다 — 셸 자신의 오류만 잡는다.
no_shell_error() {
  [ -f "$TMP/err-$1" ] || { echo "    ($1 을 한 번도 돌리지 않았다)"; return 1; }
  ! grep -nE 'unbound variable|command not found|No such file|syntax error|bad substitution|: line [0-9]+:' "$TMP/err-$1"
}
for c in plan apply verify; do step "$c 의 stderr 에 셸 오류가 없다" no_shell_error "$c"; done

if [ "$fail" -ne 0 ]; then echo "✗ ledger-migrate 검사 실패"; exit 1; fi
echo "✓ ledger-migrate 검사 통과 — plan · apply(멱등) · verify · 실패 경로"
