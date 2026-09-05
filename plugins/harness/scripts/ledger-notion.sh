#!/usr/bin/env bash
# Notion 백엔드 — 데이터베이스 한 개의 페이지가 이슈다. REST 만 쓴다(curl + NOTION_TOKEN 환경 변수 —
# 어댑터가 bash 라 MCP 를 못 부른다). ledger.sh 가 부른다(직접 부르지 않는다). 요청 문면은
# harness-m8gg.3.2 의 실측 그대로다 (Notion-Version 2022-06-28).
#
# ledger.json = {"backend":"notion","database_id":"<id>"}. 토큰은 NOTION_TOKEN 환경 변수뿐이고
# 파일에 두지 않는다 — 없으면 rc≠0.
#
# DB 스키마(T0.2 그대로 + init 이 더하는 둘):
#   Name(title) · Type(select epic|feature|task|…) · Status(select open|in_progress|blocked|deferred|closed) ·
#   Parent(relation 자기) · Blocked by(relation 자기) · Acceptance(rich_text) · Labels(multi_select) ·
#   Description(rich_text, init 이 더한다) · Assignee(rich_text, init 이 더한다)
# 자기 관계는 생성 요청에 못 넣는다(실측) — init 은 create → PATCH 두 단계다.
#
# id 는 페이지 id(uuid). JSON 키 대응표 (bd 키 ← Notion):
#   id                   페이지 id
#   title                Name
#   description          Description
#   acceptance_criteria  Acceptance
#   status               Status (없으면 open)
#   issue_type           Type (없으면 task)
#   labels               Labels 의 이름들, 정렬
#   notes                페이지 자식 문단 블록을 "\n" 로 이은 문자열 (0건이면 null) — note·ACTOR:·close 사유가 전부 여기
#   assignee             Assignee (빈 문자열이면 null)
#   parent               Parent 관계의 첫 페이지 id (없으면 null)
#   dependencies         show 에만: Blocked by 목록 [{id, status, dependency_type:"blocks"}]
#   priority             2 고정
#   created_at·updated_at
#
# ponytail: notes 는 페이지마다 블록 조회 1회라 list 는 페이지 수만큼 요청한다(Notion 은 초당 3건 안팎).
# 블록·관계는 첫 100건까지만 읽는다.
set -uo pipefail
: "${LEDGER_ROOT:?ledger.sh 를 통해 불러라}"; : "${LEDGER_CONFIG:?ledger.sh 를 통해 불러라}"

die() { echo "ledger-notion: $*" >&2; exit 1; }

# 워크트리 배선 — 이 백엔드는 워크트리에 아무것도 두지 않는다. 페이지는 원격에 있고 루트는
# HARNESS_ROOT 또는 ~/.harness-workspace/.harness-root(lib/harness-root.sh)로 찾는다. 토큰 없이도 답한다.
[ "${1:-}" = "wire-worktree" ] && { echo "ledger-notion: 워크트리 배선 없음 — 루트는 HARNESS_ROOT 또는 클론 루트의 .harness-root 로 찾는다"; exit 0; }
# 원격 반영 검사 — 페이지가 원격 자체라 앞서 있을 로컬 사본이 없다. checks/ledger-check.sh 가 부른다.
[ "${1:-}" = "sync-check" ] && { echo "✓ 원장 게이트 통과 — 원격 반영 대상 없음 (notion 백엔드: 페이지가 원격 자체다)"; exit 0; }

DB="$(jq -r '.database_id // empty' "$LEDGER_CONFIG")"
[ -n "${NOTION_TOKEN:-}" ] || die "NOTION_TOKEN 환경 변수가 없다 — 통합 토큰을 환경 변수로만 준다(파일에 두지 않는다)"
command -v curl >/dev/null 2>&1 || die "curl 이 PATH 에 없다 — Notion 백엔드는 REST 로 원장에 닿는다"

TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
API="https://api.notion.com/v1"

# napi <METHOD> <경로> [JSON 본문] → 응답 본문. 2xx 가 아니면 rc≠0 이고 stderr 에 HTTP 상태와 응답의 code.
napi() {
  local m="$1" p="$2" code rc
  if [ $# -ge 3 ]; then
    printf '%s' "$3" > "$TMPD/req"
    code="$(curl -sS -o "$TMPD/resp" -w '%{http_code}' -X "$m" "$API/$p" \
      -H "Authorization: Bearer $NOTION_TOKEN" -H "Notion-Version: 2022-06-28" -H "Content-Type: application/json" \
      --data-binary "@$TMPD/req" 2>"$TMPD/curlerr")"; rc=$?
  else
    code="$(curl -sS -o "$TMPD/resp" -w '%{http_code}' -X "$m" "$API/$p" \
      -H "Authorization: Bearer $NOTION_TOKEN" -H "Notion-Version: 2022-06-28" 2>"$TMPD/curlerr")"; rc=$?
  fi
  [ "$rc" -eq 0 ] || die "curl 실패 (rc=$rc) $m /v1/$p: $(head -1 "$TMPD/curlerr")"
  case "$code" in
    2*) cat "$TMPD/resp" ;;
    *) die "HTTP $code $(jq -r '.code // "?"' "$TMPD/resp" 2>/dev/null) — $m /v1/$p: $(jq -r '.message // ""' "$TMPD/resp" 2>/dev/null | head -c 200)" ;;
  esac
}

# jq 공통: rt(문자열 → rich_text 배열, 2000자 단위) · norm(페이지 → bd 키)
JQLIB='def rt: . as $s | [range(0; ($s|length); 2000) as $i | {type:"text", text:{content: $s[$i:$i+2000]}}];
def txt: (. // []) | map(.plain_text) | join("");
def norm: {
  id: .id,
  title: (.properties.Name.title | txt),
  description: (.properties.Description.rich_text | txt),
  acceptance_criteria: (.properties.Acceptance.rich_text | txt),
  status: (.properties.Status.select.name // "open"),
  issue_type: (.properties.Type.select.name // "task"),
  labels: ([.properties.Labels.multi_select[]?.name] | sort),
  notes: null,
  assignee: ((.properties.Assignee.rich_text | txt) | if . == "" then null else . end),
  parent: (.properties.Parent.relation[0].id // null),
  priority: 2,
  created_at: .created_time, updated_at: .last_edited_time };'

get_page() { napi GET "pages/$1"; }
notes_of() { # <페이지 id> → 문단 블록을 이은 문자열 JSON (null 이면 null)
  napi GET "blocks/$1/children?page_size=100" | jq '[.results[] | select(.type == "paragraph") | .paragraph.rich_text | map(.plain_text) | join("")] | if length == 0 then null else join("\n") end'
}
with_notes() { # stdin: norm 된 배열 → notes 를 채운 배열
  local arr id n
  arr="$(cat)"
  for id in $(printf '%s' "$arr" | jq -r '.[].id'); do
    n="$(notes_of "$id")" || exit 1
    arr="$(printf '%s' "$arr" | jq --arg id "$id" --argjson n "$n" 'map(if .id == $id then .notes = $n else . end)')"
  done
  printf '%s' "$arr"
}
append_block() { # <페이지 id> <문단 본문>
  local body
  body="$(jq -n --arg t "$2" "$JQLIB"'{children: [{object:"block", type:"paragraph", paragraph:{rich_text: ($t | rt)}}]}')" || die "블록 본문을 만들지 못했다"
  napi PATCH "blocks/$1/children" "$body" >/dev/null
}
patch_props() { # <페이지 id> <properties JSON>
  local body
  body="$(jq -n --argjson p "$2" '{properties: $p}')" || die "속성 JSON 이 잘못됐다: $2"
  napi PATCH "pages/$1" "$body" >/dev/null
}
read_body_file() { if [ "$1" = "-" ]; then cat; else cat "$1"; fi; }
glob_to_re() { printf '^%s$\n' "$(printf '%s' "$1" | sed -e 's/[][\.^$(){}|+?\\]/\\&/g' -e 's/\*/.*/g')"; }
want_json() { case " $* " in *" --json "*) return 0 ;; *) return 1 ;; esac; }
print_rows() { jq -r '.[] | "\(.id)\t\(.status)\t\(.issue_type)\t\(.title)"'; }
need_db() { [ -n "$DB" ] || die "$LEDGER_CONFIG 에 database_id 가 없다 — ledger.sh init --parent-page <페이지 id> 가 만든다"; }

# query <필터 JSON 또는 ""> → 페이지 전수(정규화, notes 없음). has_more 를 따라간다.
query() {
  local filter="$1" cursor="" body page out="[]"
  while :; do
    body="$(jq -n --arg f "$filter" --arg c "$cursor" '{page_size: 100} + (if $f == "" then {} else {filter: ($f | fromjson)} end) + (if $c == "" then {} else {start_cursor: $c} end)')"
    page="$(napi POST "databases/$DB/query" "$body")" || exit 1
    out="$(printf '%s\n%s' "$out" "$page" | jq -s "$JQLIB"'.[0] + (.[1].results | map(norm))')" || die "query 응답을 정규화하지 못했다"
    cursor="$(printf '%s' "$page" | jq -r 'if .has_more then .next_cursor else "" end')"
    [ -n "$cursor" ] || break
  done
  printf '%s' "$out"
}

# list_json <옵션…> — 서버 필터(Status·Labels·Type·Parent)를 걸고 같은 조건을 jq 로 한 번 더 거른다.
list_json() {
  local labels="" pattern="" status="" type="" parent="" all="" limit=50 filter re="" arr
  while [ $# -gt 0 ]; do
    case "$1" in
      -l|--label|--labels) labels="$2"; shift 2 ;;
      --label-pattern) pattern="$2"; shift 2 ;;
      -s|--status) status="$2"; shift 2 ;;
      -t|--type) type="$2"; shift 2 ;;
      --parent) parent="$2"; shift 2 ;;
      --all) all=1; shift ;;
      -n|--limit) limit="$2"; shift 2 ;;
      --json) shift ;;
      *) die "list: 모르는 인자 '$1'" ;;
    esac
  done
  filter="$(jq -n -c --arg labels "$labels" --arg status "$status" --arg type "$type" --arg parent "$parent" --arg all "$all" '
    ([ ($labels | if . == "" then empty else split(",")[] end | {property:"Labels", multi_select:{contains: .}}),
       (if $type == "" then empty else {property:"Type", select:{equals: $type}} end),
       (if $parent == "" then empty else {property:"Parent", relation:{contains: $parent}} end),
       (if $status != "" then {or: [($status | split(",")[] | {property:"Status", select:{equals: .}})]}
        elif $all == "" then {property:"Status", select:{does_not_equal:"closed"}} else empty end) ]) as $and
    | if ($and | length) == 0 then "" else ({and: $and} | tojson) end' | jq -r .)"
  arr="$(query "$filter")" || exit 1
  [ -n "$pattern" ] && re="$(glob_to_re "$pattern")"
  arr="$(printf '%s' "$arr" | jq --arg labels "$labels" --arg re "$re" --arg status "$status" --arg type "$type" --arg parent "$parent" --arg all "$all" --argjson limit "$limit" '
    ($labels | if . == "" then [] else split(",") end) as $need
    | ($status | if . == "" then [] else split(",") end) as $ss
    | map(. as $it | select(
        ($all != "" or $status != "" or $it.status != "closed")
        and ($status == "" or ($ss | index($it.status)) != null)
        and ($type == "" or $it.issue_type == $type)
        and ($parent == "" or $it.parent == $parent)
        and all($need[]; . as $l | any($it.labels[]?; . == $l))
        and ($re == "" or any($it.labels[]?; test($re)))))
    | if $limit > 0 then .[:$limit] else . end')"
  printf '%s' "$arr" | with_notes
}

cmd="${1:-}"; shift
case "$cmd" in
  init)
    parent_page=""; title="harness-ledger"
    while [ $# -gt 0 ]; do
      case "$1" in --parent-page) parent_page="$2"; shift 2 ;; --title) title="$2"; shift 2 ;; *) die "init: 모르는 인자 '$1'" ;; esac
    done
    base='{Name:{title:{}}, Type:{select:{options:[{name:"epic"},{name:"feature"},{name:"task"},{name:"bug"},{name:"chore"},{name:"decision"}]}}, Status:{select:{options:[{name:"open"},{name:"in_progress"},{name:"blocked"},{name:"deferred"},{name:"closed"}]}}, Acceptance:{rich_text:{}}, Labels:{multi_select:{}}, Description:{rich_text:{}}, Assignee:{rich_text:{}}}'
    if [ -z "$DB" ]; then
      [ -n "$parent_page" ] || die "$LEDGER_CONFIG 에 database_id 가 없다 — 새로 만들려면 init --parent-page <통합이 공유된 페이지 id>"
      DB="$(napi POST databases "$(jq -n --arg p "$parent_page" --arg t "$title" "{parent:{type:\"page_id\", page_id:\$p}, title:[{type:\"text\", text:{content:\$t}}], properties: $base}")" | jq -r '.id')" || exit 1
      [ -n "$DB" ] || die "DB 생성 응답에 id 가 없다"
      tmp="$(mktemp)"; jq --arg d "$DB" '.database_id = $d' "$LEDGER_CONFIG" > "$tmp" && mv "$tmp" "$LEDGER_CONFIG"
    fi
    # 자기 관계 둘 + init 이 더하는 속성 둘. 이미 있는 DB 에도 같은 PATCH 를 다시 보낼 수 있다(멱등).
    napi PATCH "databases/$DB" "$(jq -n --arg d "$DB" '{properties: {Parent:{relation:{database_id:$d, single_property:{}}}, "Blocked by":{relation:{database_id:$d, single_property:{}}}, Description:{rich_text:{}}, Assignee:{rich_text:{}}}}')" >/dev/null || exit 1
    echo "✓ notion 원장: database_id=$DB ($LEDGER_CONFIG)"
    ;;

  create)
    need_db
    [ $# -gt 0 ] || die "create: 제목이 필요하다"
    title="$1"; shift
    type="task"; labels=""; parent=""; acc=""; desc=""; silent=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -t|--type) type="$2"; shift 2 ;;
        -l|--labels|--label) labels="${labels:+$labels,}$2"; shift 2 ;;
        --parent) parent="$2"; shift 2 ;;
        --acceptance) acc="$2"; shift 2 ;;
        --body-file) desc="$(read_body_file "$2")"; shift 2 ;;
        --stdin) desc="$(cat)"; shift ;;
        -d|--description) desc="$2"; shift 2 ;;
        --silent) silent=1; shift ;;
        -p|--priority) shift 2 ;;
        --json) shift ;;
        *) die "create: 모르는 인자 '$1'" ;;
      esac
    done
    body="$(jq -n --arg db "$DB" --arg title "$title" --arg type "$type" --arg labels "$labels" --arg parent "$parent" --arg acc "$acc" --arg desc "$desc" "$JQLIB"'
      {parent:{database_id:$db},
       properties: ({Name:{title:($title|rt)}, Type:{select:{name:$type}}, Status:{select:{name:"open"}},
                     Labels:{multi_select: ($labels | if . == "" then [] else split(",") | map({name: .}) end)},
                     Acceptance:{rich_text:($acc|rt)}, Description:{rich_text:($desc|rt)}}
                    + (if $parent == "" then {} else {Parent:{relation:[{id:$parent}]}} end))}')"
    id="$(napi POST pages "$body" | jq -r '.id // empty')" || exit 1
    [ -n "$id" ] || die "페이지 생성 응답에 id 가 없다"
    if [ -n "$silent" ]; then echo "$id"; else echo "✓ Created issue: $id — $title"; fi
    ;;

  show)
    [ $# -gt 0 ] || die "show: id 가 필요하다"
    id="$1"; shift
    page="$(get_page "$id")" || exit 1
    notes="$(notes_of "$id")" || exit 1
    deps="[]"
    for b in $(printf '%s' "$page" | jq -r '.properties["Blocked by"].relation[]?.id'); do
      st="$(get_page "$b" | jq -r '.properties.Status.select.name // "open"')" || exit 1
      deps="$(printf '%s' "$deps" | jq --arg id "$b" --arg st "$st" '. + [{id:$id, status:$st, dependency_type:"blocks"}]')"
    done
    obj="$(printf '%s' "$page" | jq --argjson n "$notes" --argjson deps "$deps" "$JQLIB"'[norm + {notes: $n, dependencies: $deps}]')" || die "show: 응답을 정규화하지 못했다: $id"
    if want_json "$@"; then printf '%s\n' "$obj"; else
      printf '%s' "$obj" | jq -r '.[0] | "\(.id) [\(.issue_type) · \(.status)] \(.title)\nlabels: \(.labels | join(", "))\nparent: \(.parent // "-")  assignee: \(.assignee // "-")\n\n\(.description)\n\nACCEPTANCE\n\(.acceptance_criteria)\n\nNOTES\n\(.notes // "")"'
    fi
    ;;

  children)
    need_db
    [ $# -gt 0 ] || die "children: id 가 필요하다"
    id="$1"; shift
    arr="$(list_json --parent "$id" --all -n 0)" || exit 1
    if want_json "$@"; then printf '%s\n' "$arr"; else printf '%s' "$arr" | print_rows; fi
    ;;

  list)
    need_db
    arr="$(list_json "$@")" || exit 1
    if want_json "$@"; then printf '%s\n' "$arr"; else printf '%s' "$arr" | print_rows; fi
    ;;

  ready)
    # Status=open 이고 Blocked by 가 전부 closed 인 것. ponytail: 블로커마다 GET 1회.
    need_db
    limit=50; args=""; json=""
    while [ $# -gt 0 ]; do
      case "$1" in -n|--limit) limit="$2"; shift 2 ;; --json) json=1; shift ;; -l|--label|--labels|-t|--type) args="$args $1 $2"; shift 2 ;; *) die "ready: 모르는 인자 '$1'" ;; esac
    done
    # shellcheck disable=SC2086
    arr="$(list_json --status open -n 0 $args)" || exit 1
    ready="[]"
    for id in $(printf '%s' "$arr" | jq -r '.[].id'); do
      ok=1
      blockers="$(get_page "$id" | jq -r '.properties["Blocked by"].relation[]?.id')" || exit 1
      for b in $blockers; do
        st="$(get_page "$b" | jq -r '.properties.Status.select.name // "open"')" || exit 1
        [ "$st" = "closed" ] || { ok=0; break; }
      done
      [ "$ok" -eq 1 ] && ready="$(printf '%s' "$ready" | jq --arg id "$id" '. + [$id]')"
    done
    arr="$(printf '%s' "$arr" | jq --argjson r "$ready" --argjson limit "$limit" 'map(select(.id as $i | $r | index($i) != null)) | if $limit > 0 then .[:$limit] else . end')"
    if [ -n "$json" ]; then printf '%s\n' "$arr"; else printf '%s' "$arr" | print_rows; fi
    ;;

  note)
    [ $# -gt 0 ] || die "note: id 가 필요하다"
    id="$1"; shift
    case "${1:-}" in
      --file) text="$(read_body_file "$2")" ;;
      --stdin) text="$(cat)" ;;
      "") die "note: 본문이 필요하다" ;;
      *) text="$1" ;;
    esac
    append_block "$id" "$text" || exit 1
    echo "✓ Note added to $id"
    ;;

  close)
    ids=""; reason=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -r|--reason) reason="$2"; shift 2 ;;
        --reason-file) reason="$(read_body_file "$2")"; shift 2 ;;
        --force|--json) shift ;;
        -*) die "close: 모르는 인자 '$1'" ;;
        *) ids="$ids $1"; shift ;;
      esac
    done
    [ -n "$ids" ] || die "close: id 가 필요하다"
    for id in $ids; do
      patch_props "$id" '{"Status":{"select":{"name":"closed"}}}' || exit 1
      [ -n "$reason" ] && { append_block "$id" "$reason" || exit 1; }
      echo "✓ Closed $id"
    done
    ;;

  update)
    [ $# -gt 0 ] || die "update: id 가 필요하다"
    id="$1"; shift
    status=""; claim=""; actor=""; parent=""; type=""; acc=""; desc=""; set_desc=""; set_acc=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -s|--status) status="$2"; shift 2 ;;
        --claim) claim=1; shift ;;
        --actor) actor="$2"; shift 2 ;;
        --parent) parent="$2"; shift 2 ;;
        -t|--type) type="$2"; shift 2 ;;
        --acceptance) acc="$2"; set_acc=1; shift 2 ;;
        --body-file) desc="$(read_body_file "$2")"; set_desc=1; shift 2 ;;
        -d|--description) desc="$2"; set_desc=1; shift 2 ;;
        --json) shift ;;
        *) die "update: 모르는 인자 '$1'" ;;
      esac
    done
    if [ -n "$claim" ]; then [ -n "$status" ] || status="in_progress"; fi
    props="$(jq -n --arg status "$status" --arg actor "$actor" --arg claim "$claim" --arg parent "$parent" --arg type "$type" --arg acc "$acc" --arg set_acc "$set_acc" --arg desc "$desc" --arg set_desc "$set_desc" "$JQLIB"'
      {} + (if $status == "" then {} else {Status:{select:{name:$status}}} end)
         + (if $claim == "" then {} else {Assignee:{rich_text:($actor|rt)}} end)
         + (if $parent == "" then {} else {Parent:{relation:[{id:$parent}]}} end)
         + (if $type == "" then {} else {Type:{select:{name:$type}}} end)
         + (if $set_acc == "" then {} else {Acceptance:{rich_text:($acc|rt)}} end)
         + (if $set_desc == "" then {} else {Description:{rich_text:($desc|rt)}} end)')"
    [ "$props" != "{}" ] && { patch_props "$id" "$props" || exit 1; }
    [ -n "$claim" ] && [ -n "$actor" ] && { append_block "$id" "ACTOR: $actor" || exit 1; }
    echo "✓ Updated issue: $id"
    ;;

  dep)
    sub="${1:-}"; shift
    [ "$sub" = "add" ] || die "dep: 'add' 만 지원한다 (받은 것: '$sub')"
    if [ "${1:-}" = "--file" ]; then
      pairs="$(read_body_file "$2" | jq -r 'select(. != null) | "\(.from // .issue_id) \(.to // .depends_on_id)"')"
    else
      [ $# -ge 2 ] || die "dep add: <id> <의존 대상 id> 또는 --file - (JSONL {\"from\",\"to\"})"
      pairs="$1 $2"
    fi
    printf '%s\n' "$pairs" | while read -r a b; do
      [ -n "$a" ] || continue
      cur="$(get_page "$a" | jq -c '[.properties["Blocked by"].relation[]? | {id}]')" || exit 1
      patch_props "$a" "$(printf '%s' "$cur" | jq --arg b "$b" '{"Blocked by":{relation: (. + [{id:$b}] | unique)}}')" || exit 1
      echo "✓ Added dependency: $a blocked by $b"
    done || exit 1
    ;;

  label)
    sub="${1:-}"; shift
    [ $# -ge 2 ] || die "label $sub: <id…> <라벨>"
    n=$#; label=""; i=0; ids=""
    for a in "$@"; do i=$((i + 1)); if [ "$i" -eq "$n" ]; then label="$a"; else ids="$ids $a"; fi; done
    for id in $ids; do
      cur="$(get_page "$id" | jq -c '[.properties.Labels.multi_select[]?.name]')" || exit 1
      case "$sub" in
        add) new="$(printf '%s' "$cur" | jq --arg l "$label" '. + [$l] | unique')"; msg="✓ Added label '$label' to $id" ;;
        remove) new="$(printf '%s' "$cur" | jq --arg l "$label" 'map(select(. != $l))')"; msg="✓ Removed label '$label' from $id" ;;
        *) die "label: add|remove 만 지원한다 (받은 것: '$sub')" ;;
      esac
      patch_props "$id" "$(printf '%s' "$new" | jq '{Labels:{multi_select: map({name: .})}}')" || exit 1
      echo "$msg"
    done
    ;;

  *) die "'$cmd' 는 notion 백엔드에 없다 (beads 전용이거나 모르는 명령) — ledger.sh --help" ;;
esac
