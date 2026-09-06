#!/usr/bin/env bash
# 게이트: 이전 도구(scripts/ledger-migrate.sh)를 픽스처로 단언한다. 네트워크에 닿지 않는다.
#
#   ① plan   — 가짜 bd 의 원장에서 열린 항목만 · repo 결정 규칙 · 본문 첫 줄 · 라벨 · deps · notes.
#   ② plan 실패 경로 — repos.json 에 없는 레포 라벨이면 rc 1 이고 stdout 에 아무것도 내지 않는다.
#   ③ apply  — 위상 순(부모·의존 먼저) · 이슈 생성 · map 기록 · 2회 실행 뒤 이슈 수가 늘지 않는다(멱등).
#   ④ apply 실패 경로 — gh 가 죽는 항목에서 멈추고 rc 1, map 에는 성공한 것까지만. --plan 없으면 rc 1.
#
# 실제 GitHub 에 닿는 실증(Project 소속·색인 지연)은 오케스트레이터가 실증 레포에서 돈다
# (harness-kw0l.2.1 acceptance 5).
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
cat > "$BIN/gh" <<'FAKEGH'
#!/usr/bin/env bash
S="$FAKE_GH_STATE"; printf '%s\n' "$*" >> "$FAKE_GH_LOG"
arg_after() { local k="$1"; shift; while [ $# -gt 0 ]; do [ "$1" = "$k" ] && { printf '%s' "$2"; return; }; shift; done; }
kv() { local k="$1"; shift; for a in "$@"; do case "$a" in "$k"=*) printf '%s' "${a#*=}"; return ;; esac; done; }
case "$1 $2" in
  "auth status") exit 0 ;;
  "label create") exit 0 ;;
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
    n="$3"; printf '{"projectItems":[{"number":%s}]}' "$(cat "$S/$n.project" 2>/dev/null || echo 0)"; exit 0 ;;
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
    jq -n --rawfile t "$S/$n.title" --rawfile b "$S/$n.body" --rawfile l "$S/$n.labels" \
       --argjson c "$(cat "$S/$n.comments")" --argjson par "$par" \
       '{data: {repository: {issue: {
          title: ($t | rtrimstr("\n")), body: $b,
          labels: {nodes: ($l | split("\n") | map(select(. != "")) | map({name: .}))},
          comments: {totalCount: $c}, parent: $par}}}}'
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
    case "$*" in *.node_id*) echo "NODE_$n" ;; *) echo "$(( n + 1000 ))" ;; esac; exit 0 ;;
esac
echo "fake gh: 모르는 호출 $*" >&2; exit 1
FAKEGH
chmod +x "$BIN/gh"

STATE="$TMP/ghstate"; mkdir -p "$STATE"
export FAKE_GH_STATE="$STATE" FAKE_GH_LOG="$TMP/gh.log"; : > "$FAKE_GH_LOG"

# 원장 픽스처 — x-2 를 맨 앞에 두어 위상 정렬(부모 x-1·의존 x-3 이 먼저)을 판정한다.
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
 {"id":"x-5","title":"미룬 것","status":"deferred","issue_type":"task","description":"","labels":["repo:sap-harness"],"parent":null,"dependencies":[]}
]
EOF
export FAKE_BD_DATA="$TMP/beads.json"

run() { OUT=$(bash "$MIG" "$@" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err"); }
OUT=""; ERR=""; RC=0

echo "── ① plan ──"
run plan --from "$ROOT"
step "plan rc 0" [ "$RC" -eq 0 ]
step "닫힌 항목을 뺀 4건" bash -c 'printf "%s" "$1" | jq -e "length == 4" >/dev/null' _ "$OUT"
step "repo 규칙: repo:harness→skills · 라벨 없음→skills · 그 밖은 그대로" \
  bash -c 'printf "%s" "$1" | jq -e "(map({(.id): .repo}) | add) == {\"x-1\":\"skills\",\"x-2\":\"sap-harness\",\"x-3\":\"skills\",\"x-5\":\"sap-harness\"}" >/dev/null' _ "$OUT"
step "본문 첫 줄이 beads: <id> 이고 그 뒤 description · ## Acceptance 절" \
  bash -c 'printf "%s" "$1" | jq -e ".[] | select(.id == \"x-1\") | .body == \"beads: x-1\n\n부모 본문\n\n## Acceptance\n\n조건 1\"" >/dev/null' _ "$OUT"
step "acceptance 가 없는 항목의 본문에는 ## Acceptance 절이 없다" \
  bash -c 'printf "%s" "$1" | jq -e ".[] | select(.id == \"x-3\") | .body == \"beads: x-3\n\n버그 본문\"" >/dev/null' _ "$OUT"
step "labels 는 원 라벨 그대로(repo: 포함)이고 type:·status: 를 담지 않는다" \
  bash -c 'printf "%s" "$1" | jq -e ".[] | select(.id == \"x-1\") | .labels == [\"harness\",\"repo:harness\",\"sprint:2026-S02\"]" >/dev/null' _ "$OUT"
step "deps 는 blocked_by 만 (parent-child 는 빼고 parent 로만 든다)" \
  bash -c 'printf "%s" "$1" | jq -e ".[] | select(.id == \"x-2\") | .deps == [\"x-3\"] and .parent == \"x-1\"" >/dev/null' _ "$OUT"
step "notes 는 빈 줄을 뺀 줄 배열 · in_progress 는 마지막에 ACTOR: 코멘트" \
  bash -c 'printf "%s" "$1" | jq -e ".[] | select(.id == \"x-2\") | .notes == [\"메모 한 줄\",\"메모 둘\",\"ACTOR: sess-abc\"]" >/dev/null' _ "$OUT"
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

if [ "$fail" -ne 0 ]; then echo "✗ ledger-migrate 검사 실패"; exit 1; fi
echo "✓ ledger-migrate 검사 통과 — plan · apply(멱등) · 실패 경로"
