#!/usr/bin/env bash
# GitHub 백엔드 — 이슈 · sub-issue(계층) · blocked-by(순서) · 라벨 · 코멘트 · Projects v2(멀티 레포 묶음).
# ledger.sh 가 부른다(직접 부르지 않는다). 명령 문면은 harness-m8gg.3.1 의 실측 그대로다.
#
# ledger.json = {"backend":"github","owner":"<o>","project":<n>}
#   owner   Projects v2 의 소유자(사용자 login). 이슈가 사는 레포의 소유자는 repos.json 의 url 이 정한다.
#   project Projects v2 번호. 없으면 create 가 item-add 를 건너뛰지 않고 rc≠0 이다 — `ledger.sh init` 이 만든다.
#
# id 형식: <repo>#<번호> (예: harness#57). 번호만으로는 멀티 레포에서 레포를 못 짚는다.
# 이슈를 만드는 레포: -l 의 첫 repo: 라벨 → 없으면 --parent 의 레포 → 둘 다 없으면 rc≠0(폴백 없음).
# 레포 slug(owner/name)는 하네스 루트 repos.json 의 url 에서 파생한다 — 등재되지 않은 레포는 rc≠0.
#
# JSON 키 대응표 (bd 키 ← GitHub):
#   id                   <repo>#<number>
#   title                title
#   description          body 에서 "## Acceptance" 절 앞
#   acceptance_criteria  body 의 "## Acceptance" 절 본문 (없으면 "")
#   status               CLOSED → closed · status:<s> 라벨 → <s> · 그 밖 → open
#   issue_type           type:<t> 라벨 (없으면 task) — 사용자 소유 레포에 Issue Types 가 없어 라벨로 간다
#   labels               라벨 전부 − type:·status: (인코딩용 라벨은 뺀다), 정렬
#   notes                코멘트 본문을 "\n" 로 이은 문자열 (0건이면 null) — note·ACTOR:·close 사유가 전부 여기
#   assignee             첫 assignee 의 login (없으면 null)
#   parent               sub-issue 부모의 <repo>#<number> (없으면 null)
#   dependencies         show 에만: blocked_by 목록 [{id, status, dependency_type:"blocks"}]
#   priority             2 고정 (대응 필드 없음)
#   created_at·updated_at·closed_at
#
# ponytail: 라벨·코멘트·자식은 first:100 까지만 읽는다 — 그 이상은 페이지네이션이 필요하다.
set -uo pipefail
: "${LEDGER_ROOT:?ledger.sh 를 통해 불러라}"; : "${LEDGER_CONFIG:?ledger.sh 를 통해 불러라}"

die() { echo "ledger-github: $*" >&2; exit 1; }

# 워크트리 배선 — 이 백엔드는 워크트리에 아무것도 두지 않는다. 이슈는 원격에 있고 루트는
# HARNESS_ROOT 또는 ~/.harness-workspace/.harness-root(lib/harness-root.sh)로 찾는다. gh 없이도 답한다.
[ "${1:-}" = "wire-worktree" ] && { echo "ledger-github: 워크트리 배선 없음 — 루트는 HARNESS_ROOT 또는 클론 루트의 .harness-root 로 찾는다"; exit 0; }

OWNER="$(jq -r '.owner // empty' "$LEDGER_CONFIG")"
PROJECT="$(jq -r '.project // empty' "$LEDGER_CONFIG")"
[ -n "$OWNER" ] || die "$LEDGER_CONFIG 에 owner 가 없다"
command -v gh >/dev/null 2>&1 || die "gh 가 PATH 에 없다 — GitHub 백엔드는 gh 로 원장에 닿는다"
gh auth status >/dev/null 2>&1 || die "gh 인증이 없다 — 사람이 gh auth login 을 먼저 한다"

# ── 레포·id ───────────────────────────────────────────────────────────
slug_of() { # <repo 이름> → owner/name (repos.json 의 url 에서)
  local url
  url="$(jq -r --arg n "$1" '.repos[] | select(.name == $n) | .url' "$LEDGER_ROOT/repos.json" 2>/dev/null | head -1)"
  [ -n "$url" ] || die "repos.json 에 없는 레포 '$1' — 이슈가 살 레포는 등재된 것이어야 한다"
  url="${url%.git}"; url="${url#*github.com/}"; url="${url#*github.com:}"
  printf '%s\n' "$url"
}
REPO=""; NUM=""; SLUG=""
split_id() { # <repo>#<n> → REPO NUM SLUG
  case "$1" in
    *#*) REPO="${1%%#*}"; NUM="${1##*#}" ;;
    *) die "id 형식은 <repo>#<번호> 다: '$1'" ;;
  esac
  case "$NUM" in ''|*[!0-9]*) die "id 형식은 <repo>#<번호> 다: '$1'" ;; esac
  SLUG="$(slug_of "$REPO")" || exit 1
}
repos_all() { jq -r '.repos[].name' "$LEDGER_ROOT/repos.json"; }

# ── GraphQL ───────────────────────────────────────────────────────────
FIELDS='id databaseId number title state body createdAt updatedAt closedAt repository{name} labels(first:100){nodes{name}} assignees(first:10){nodes{login}} comments(first:100){nodes{body}} parent{number repository{name}}'
# bd 의 키로 정규화한다. body 는 "<description>\n\n## Acceptance\n\n<acceptance>" 로 쓰고 같은 자리에서 가른다.
NORM='def norm:
  ((.body // "") | if startswith("## Acceptance\n") then "\n" + . else . end | split("\n## Acceptance\n")) as $parts
  | (.labels.nodes | map(.name)) as $ls
  | { id: (.repository.name + "#" + (.number|tostring)),
      title: .title,
      description: (($parts[0] // "") | rtrimstr("\n")),
      acceptance_criteria: (if ($parts|length) > 1 then ($parts[1:] | join("\n## Acceptance\n") | ltrimstr("\n") | rtrimstr("\n")) else "" end),
      status: (if .state == "CLOSED" then "closed" else (($ls | map(select(startswith("status:"))) | first // "status:open") | ltrimstr("status:")) end),
      issue_type: (($ls | map(select(startswith("type:"))) | first // "type:task") | ltrimstr("type:")),
      labels: ($ls | map(select((startswith("type:") or startswith("status:")) | not)) | sort),
      notes: (if (.comments.nodes|length) == 0 then null else (.comments.nodes | map(.body) | join("\n")) end),
      assignee: (.assignees.nodes[0].login // null),
      parent: (if .parent then (.parent.repository.name + "#" + (.parent.number|tostring)) else null end),
      priority: 2,
      created_at: .createdAt, updated_at: .updatedAt, closed_at: .closedAt };'

fetch_issue() { # SLUG NUM → 원본 노드 JSON (없는 이슈면 gh 가 rc≠0)
  local o="${1%%/*}" r="${1##*/}" out
  out="$(gh api graphql -f query="query(\$o:String!,\$r:String!,\$n:Int!){ repository(owner:\$o,name:\$r){ issue(number:\$n){ $FIELDS } } }" -f o="$o" -f r="$r" -F n="$2" 2>/dev/null)" \
    || die "없는 id 이거나 읽지 못했다: $REPO#$2"
  printf '%s' "$out" | jq -e '.data.repository.issue' >/dev/null 2>&1 || die "없는 id: $REPO#$2"
  printf '%s' "$out" | jq '.data.repository.issue'
}
node_id() { gh api "repos/$1/issues/$2" --jq .node_id; }
db_id()   { gh api "repos/$1/issues/$2" --jq .id; }
blocked_by() { # SLUG NUM → [{id, status, dependency_type}]
  gh api "repos/$1/issues/$2/dependencies/blocked_by" 2>/dev/null \
    | jq '[.[] | {id: ((.repository_url | split("/") | last) + "#" + (.number|tostring)), status: (if .state == "closed" then "closed" else "open" end), dependency_type: "blocks"}]'
}
ensure_label() { gh label create "$2" -R "$1" --force >/dev/null 2>&1 || die "라벨 '$2' 를 $1 에 만들지 못했다"; }
add_sub_issue() { # 부모 SLUG NUM, 자식 SLUG NUM
  local p c
  p="$(node_id "$1" "$2")" || die "부모 node_id 조회 실패: $1#$2"
  c="$(node_id "$3" "$4")" || die "자식 node_id 조회 실패: $3#$4"
  gh api graphql -f query='mutation($p:ID!,$c:ID!){ addSubIssue(input:{issueId:$p, subIssueId:$c}) { issue { number } subIssue { number } } }' -f p="$p" -f c="$c" >/dev/null \
    || die "addSubIssue 실패: $1#$2 ← $3#$4"
}
compose_body() { # <description> <acceptance> → stdout
  printf '%s' "$1"
  [ -n "$2" ] && printf '\n\n## Acceptance\n\n%s' "$2"
  printf '\n'
}
read_body_file() { if [ "$1" = "-" ]; then cat; else cat "$1"; fi; }
labels_of() { gh issue view "$2" -R "$1" --json labels --jq '.labels[].name'; }
glob_to_re() { printf '^%s$\n' "$(printf '%s' "$1" | sed -e 's/[][\.^$(){}|+?\\]/\\&/g' -e 's/\*/.*/g')"; }

# ── list / ready ──────────────────────────────────────────────────────
list_json() { # 옵션을 파싱해 정규화된 JSON 배열을 낸다. 상태 필터가 closed 를 안 들면 OPEN 만 읽는다.
  local labels="" pattern="" status="" type="" parent="" all="" limit=50 o r states out="[]" re=""
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
  states="[OPEN]"
  case ",$status," in *,closed,*) states="[OPEN,CLOSED]" ;; esac
  [ -n "$all" ] && states="[OPEN,CLOSED]"
  for name in $(repos_all); do
    o="$(slug_of "$name")"; r="${o##*/}"; o="${o%%/*}"
    page="$(gh api graphql --paginate --slurp -f query="query(\$o:String!,\$r:String!,\$endCursor:String){ repository(owner:\$o,name:\$r){ issues(first:100, after:\$endCursor, states:$states){ nodes{ $FIELDS } pageInfo{hasNextPage endCursor} } } }" -f o="$o" -f r="$r" 2>/dev/null)" \
      || die "list: $o/$r 의 이슈를 읽지 못했다"
    out="$(printf '%s\n%s' "$out" "$page" | jq -s "$NORM"'.[0] + ([.[1][].data.repository.issues.nodes[]] | map(norm))')" \
      || die "list: $o/$r 의 응답을 정규화하지 못했다"
  done
  [ -n "$pattern" ] && re="$(glob_to_re "$pattern")"
  printf '%s' "$out" | jq --arg labels "$labels" --arg re "$re" --arg status "$status" --arg type "$type" --arg parent "$parent" --arg all "$all" --argjson limit "$limit" '
    ($labels | if . == "" then [] else split(",") end) as $need
    | ($status | if . == "" then [] else split(",") end) as $ss
    | map(. as $it | select(
        ($all != "" or $status != "" or $it.status != "closed")
        and ($status == "" or ($ss | index($it.status)) != null)
        and ($type == "" or $it.issue_type == $type)
        and ($parent == "" or $it.parent == $parent)
        and all($need[]; . as $l | any($it.labels[]?; . == $l))
        and ($re == "" or any($it.labels[]?; test($re)))))
    | if $limit > 0 then .[:$limit] else . end'
}
print_rows() { jq -r '.[] | "\(.id)\t\(.status)\t\(.issue_type)\t\(.title)"'; }
want_json() { case " $* " in *" --json "*) return 0 ;; *) return 1 ;; esac; }

cmd="${1:-}"; shift
case "$cmd" in
  init)
    title="harness-ledger"
    while [ $# -gt 0 ]; do case "$1" in --title) title="$2"; shift 2 ;; *) die "init: 모르는 인자 '$1'" ;; esac; done
    if [ -z "$PROJECT" ]; then
      PROJECT="$(gh project create --owner "$OWNER" --title "$title" --format json 2>/dev/null | jq -r '.number // empty')"
      [ -n "$PROJECT" ] || die "Projects v2 를 만들지 못했다 — 토큰에 project scope 가 없으면 사람이 일반 터미널에서 'gh auth refresh -h github.com -s project,read:project' 를 돌린다"
      tmp="$(mktemp)"; jq --argjson n "$PROJECT" '.project = $n' "$LEDGER_CONFIG" > "$tmp" && mv "$tmp" "$LEDGER_CONFIG"
    fi
    gh project view "$PROJECT" --owner "$OWNER" --format json >/dev/null 2>&1 \
      || die "Project $PROJECT (owner $OWNER) 를 읽지 못했다 — 번호가 틀렸거나 project scope 가 없다: 'gh auth refresh -h github.com -s project,read:project'"
    echo "✓ github 원장: owner=$OWNER project=$PROJECT ($LEDGER_CONFIG)"
    ;;

  create)
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
    [ -n "$PROJECT" ] || die "$LEDGER_CONFIG 에 project 가 없다 — 이슈를 Projects v2 에 넣지 못하므로 만들지 않는다 (ledger.sh init 이 만든다)"
    repo=""
    for l in $(printf '%s' "$labels" | tr ',' ' '); do case "$l" in repo:*) repo="${l#repo:}"; break ;; esac; done
    if [ -z "$repo" ] && [ -n "$parent" ]; then split_id "$parent"; repo="$REPO"; fi
    [ -n "$repo" ] || die "create: 이슈가 살 레포를 모른다 — -l repo:<이름> 또는 --parent 가 필요하다"
    slug="$(slug_of "$repo")" || exit 1
    all_labels="type:$type${labels:+,$labels}"
    for l in $(printf '%s' "$all_labels" | tr ',' ' '); do ensure_label "$slug" "$l"; done
    body="$(mktemp)"; compose_body "$desc" "$acc" > "$body"
    url="$(gh issue create -R "$slug" -t "$title" -F "$body" -l "$all_labels" 2>/dev/null)"; rc=$?; rm -f "$body"
    [ "$rc" -eq 0 ] && [ -n "$url" ] || die "gh issue create 실패 ($slug)"
    num="${url##*/}"
    if [ -n "$parent" ]; then split_id "$parent"; add_sub_issue "$SLUG" "$NUM" "$slug" "$num"; fi
    gh project item-add "$PROJECT" --owner "$OWNER" --url "$url" >/dev/null 2>&1 \
      || die "이슈 $repo#$num 은 만들었지만 Project $PROJECT 에 넣지 못했다 — project scope 또는 번호를 확인하라"
    if [ -n "$silent" ]; then echo "$repo#$num"; else echo "✓ Created issue: $repo#$num — $title"; fi
    ;;

  show)
    [ $# -gt 0 ] || die "show: id 가 필요하다"
    split_id "$1"; shift
    node="$(fetch_issue "$SLUG" "$NUM")" || exit 1
    deps="$(blocked_by "$SLUG" "$NUM")" || deps="[]"
    obj="$(printf '%s' "$node" | jq --argjson deps "$deps" "$NORM"'[norm + {dependencies: $deps}]')" || die "show: 응답을 정규화하지 못했다: $REPO#$NUM"
    if want_json "$@"; then printf '%s\n' "$obj"; else
      printf '%s' "$obj" | jq -r '.[0] | "\(.id) [\(.issue_type) · \(.status)] \(.title)\nlabels: \(.labels | join(", "))\nparent: \(.parent // "-")  assignee: \(.assignee // "-")\n\n\(.description)\n\nACCEPTANCE\n\(.acceptance_criteria)\n\nNOTES\n\(.notes // "")"'
    fi
    ;;

  children)
    [ $# -gt 0 ] || die "children: id 가 필요하다"
    split_id "$1"; shift
    o="${SLUG%%/*}"; r="${SLUG##*/}"
    out="$(gh api graphql -f query="query(\$o:String!,\$r:String!,\$n:Int!){ repository(owner:\$o,name:\$r){ issue(number:\$n){ subIssues(first:100){ nodes{ $FIELDS } } } } }" -f o="$o" -f r="$r" -F n="$NUM" 2>/dev/null)" \
      || die "없는 id 이거나 읽지 못했다: $REPO#$NUM"
    arr="$(printf '%s' "$out" | jq "$NORM"'[.data.repository.issue.subIssues.nodes[] | norm]')" || die "children: 응답을 정규화하지 못했다: $REPO#$NUM"
    if want_json "$@"; then printf '%s\n' "$arr"; else printf '%s' "$arr" | print_rows; fi
    ;;

  list)
    arr="$(list_json "$@")" || exit 1
    if want_json "$@"; then printf '%s\n' "$arr"; else printf '%s' "$arr" | print_rows; fi
    ;;

  ready)
    # open 이고 blocked_by 가 전부 closed 인 것 (bd ready 와 같이 in_progress·blocked·deferred 는 뺀다).
    # ponytail: 이슈마다 REST 한 번 — 열린 이슈 수만큼 호출한다.
    limit=50; args=""; json=""
    while [ $# -gt 0 ]; do
      case "$1" in -n|--limit) limit="$2"; shift 2 ;; --json) json=1; shift ;; -l|--label|--labels|-t|--type) args="$args $1 $2"; shift 2 ;; *) die "ready: 모르는 인자 '$1'" ;; esac
    done
    # shellcheck disable=SC2086
    arr="$(list_json --status open -n 0 $args)" || exit 1
    ready="[]"
    for id in $(printf '%s' "$arr" | jq -r '.[].id'); do
      split_id "$id"
      deps="$(blocked_by "$SLUG" "$NUM")" || die "blocked_by 조회 실패: $id"
      if printf '%s' "$deps" | jq -e 'all(.[]; .status == "closed")' >/dev/null; then
        ready="$(printf '%s' "$ready" | jq --arg id "$id" '. + [$id]')"
      fi
    done
    arr="$(printf '%s' "$arr" | jq --argjson r "$ready" --argjson limit "$limit" 'map(select(.id as $i | $r | index($i) != null)) | if $limit > 0 then .[:$limit] else . end')"
    if [ -n "$json" ]; then printf '%s\n' "$arr"; else printf '%s' "$arr" | print_rows; fi
    ;;

  note)
    [ $# -gt 0 ] || die "note: id 가 필요하다"
    split_id "$1"; shift
    text=""
    case "${1:-}" in
      --file) text="$(read_body_file "$2")" ;;
      --stdin) text="$(cat)" ;;
      "") die "note: 본문이 필요하다" ;;
      *) text="$1" ;;
    esac
    gh issue comment "$NUM" -R "$SLUG" -b "$text" >/dev/null 2>&1 || die "코멘트를 달지 못했다: $REPO#$NUM"
    echo "✓ Note added to $REPO#$NUM"
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
      split_id "$id"
      if [ -n "$reason" ]; then gh issue close "$NUM" -R "$SLUG" -c "$reason" >/dev/null 2>&1; else gh issue close "$NUM" -R "$SLUG" >/dev/null 2>&1; fi \
        || die "닫지 못했다: $id"
      echo "✓ Closed $id"
    done
    ;;

  update)
    [ $# -gt 0 ] || die "update: id 가 필요하다"
    split_id "$1"; shift
    status=""; claim=""; actor=""; parent=""; type=""; acc=""; desc=""; set_desc=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -s|--status) status="$2"; shift 2 ;;
        --claim) claim=1; shift ;;
        --actor) actor="$2"; shift 2 ;;
        --parent) parent="$2"; shift 2 ;;
        -t|--type) type="$2"; shift 2 ;;
        --acceptance) acc="$2"; shift 2 ;;
        --body-file) desc="$(read_body_file "$2")"; set_desc=1; shift 2 ;;
        -d|--description) desc="$2"; set_desc=1; shift 2 ;;
        --json) shift ;;
        *) die "update: 모르는 인자 '$1'" ;;
      esac
    done
    if [ -n "$claim" ]; then
      gh issue edit "$NUM" -R "$SLUG" --add-assignee @me >/dev/null 2>&1 || die "assignee 를 붙이지 못했다: $REPO#$NUM"
      [ -n "$actor" ] && { gh issue comment "$NUM" -R "$SLUG" -b "ACTOR: $actor" >/dev/null 2>&1 || die "ACTOR 코멘트 실패: $REPO#$NUM"; }
      [ -n "$status" ] || status="in_progress"
    fi
    if [ -n "$status" ] || [ -n "$type" ]; then
      cur="$(labels_of "$SLUG" "$NUM")" || die "라벨을 읽지 못했다: $REPO#$NUM"
      rm_args=""
      for l in $cur; do
        case "$l" in
          status:*) [ -n "$status" ] && rm_args="$rm_args --remove-label $l" ;;
          type:*) [ -n "$type" ] && rm_args="$rm_args --remove-label $l" ;;
        esac
      done
      add_args=""
      case "$status" in
        ""|open|closed) ;;
        *) ensure_label "$SLUG" "status:$status"; add_args="$add_args --add-label status:$status" ;;
      esac
      if [ -n "$type" ]; then ensure_label "$SLUG" "type:$type"; add_args="$add_args --add-label type:$type"; fi
      if [ -n "$rm_args$add_args" ]; then
        # shellcheck disable=SC2086
        gh issue edit "$NUM" -R "$SLUG" $rm_args $add_args >/dev/null 2>&1 || die "라벨을 바꾸지 못했다: $REPO#$NUM"
      fi
      case "$status" in
        closed) gh issue close "$NUM" -R "$SLUG" >/dev/null 2>&1 || die "닫지 못했다: $REPO#$NUM" ;;
        open|in_progress|blocked|deferred) gh issue reopen "$NUM" -R "$SLUG" >/dev/null 2>&1 || true ;;
      esac
    fi
    if [ -n "$parent" ]; then p="$SLUG"; n="$NUM"; split_id "$parent"; add_sub_issue "$SLUG" "$NUM" "$p" "$n"; SLUG="$p"; NUM="$n"; fi
    if [ -n "$acc" ] || [ -n "$set_desc" ]; then
      node="$(fetch_issue "$SLUG" "$NUM")" || exit 1
      [ -n "$set_desc" ] || desc="$(printf '%s' "$node" | jq -r "$NORM"'norm | .description')"
      [ -n "$acc" ] || acc="$(printf '%s' "$node" | jq -r "$NORM"'norm | .acceptance_criteria')"
      body="$(mktemp)"; compose_body "$desc" "$acc" > "$body"
      gh issue edit "$NUM" -R "$SLUG" -F "$body" >/dev/null 2>&1; rc=$?; rm -f "$body"
      [ "$rc" -eq 0 ] || die "본문을 바꾸지 못했다: $REPO#$NUM"
    fi
    echo "✓ Updated issue: $REPO#$NUM"
    ;;

  dep)
    sub="${1:-}"; shift
    [ "$sub" = "add" ] || die "dep: 'add' 만 지원한다 (받은 것: '$sub')"
    pairs=""
    if [ "${1:-}" = "--file" ]; then
      pairs="$(read_body_file "$2" | jq -r 'select(. != null) | "\(.from // .issue_id) \(.to // .depends_on_id)"')"
    else
      [ $# -ge 2 ] || die "dep add: <id> <의존 대상 id> 또는 --file - (JSONL {\"from\",\"to\"})"
      pairs="$1 $2"
    fi
    printf '%s\n' "$pairs" | while read -r a b; do
      [ -n "$a" ] || continue
      split_id "$b"; bid="$(db_id "$SLUG" "$NUM")" || die "의존 대상 id 조회 실패: $b"
      split_id "$a"
      gh api -X POST "repos/$SLUG/issues/$NUM/dependencies/blocked_by" -F issue_id="$bid" >/dev/null 2>&1 || die "blocked_by 를 걸지 못했다: $a ← $b"
      echo "✓ Added dependency: $a blocked by $b"
    done || exit 1
    ;;

  label)
    sub="${1:-}"; shift
    [ $# -ge 2 ] || die "label $sub: <id…> <라벨>"
    n=$#; label=""; i=0; ids=""
    for a in "$@"; do i=$((i + 1)); if [ "$i" -eq "$n" ]; then label="$a"; else ids="$ids $a"; fi; done
    for id in $ids; do
      split_id "$id"
      case "$sub" in
        add) ensure_label "$SLUG" "$label"; gh issue edit "$NUM" -R "$SLUG" --add-label "$label" >/dev/null 2>&1 || die "라벨을 붙이지 못했다: $id"; echo "✓ Added label '$label' to $id" ;;
        remove) gh issue edit "$NUM" -R "$SLUG" --remove-label "$label" >/dev/null 2>&1 || die "라벨을 떼지 못했다: $id"; echo "✓ Removed label '$label' from $id" ;;
        *) die "label: add|remove 만 지원한다 (받은 것: '$sub')" ;;
      esac
    done
    ;;

  *) die "'$cmd' 는 github 백엔드에 없다 (beads 전용이거나 모르는 명령) — ledger.sh --help" ;;
esac
