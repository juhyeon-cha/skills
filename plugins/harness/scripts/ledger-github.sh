#!/usr/bin/env bash
# GitHub 백엔드 — 이슈 · sub-issue(계층) · blocked-by(순서) · 라벨 · 코멘트 · Projects v2(멀티 레포 묶음).
# ledger.sh 가 부른다(직접 부르지 않는다). 명령 문면은 harness-m8gg.3.1 의 실측 그대로다.
#
# ledger.json = {"backend":"github","owner":"<o>","project":<n>}
#   owner   Projects v2 의 소유자(사용자 login). **이슈가 사는 레포의 소유자도 이 값이다.**
#   project Projects v2 번호. 없으면 create 가 item-add 를 건너뛰지 않고 rc≠0 이다 — `ledger.sh init` 이 만든다.
#
# id 형식: <repo>#<번호> (예: harness#57). 번호만으로는 멀티 레포에서 레포를 못 짚는다.
# 이슈를 만드는 레포: -l 의 `repo:` 라벨 **정확히 하나**. 0개거나 2개 이상이면 rc≠0(폴백 없음) —
# 이 어댑터는 이름의 실재를 확인할 등록부를 읽지 않으므로, 애매한 입력을 여기서 세워 막는다.
# 여러 레포에 걸치는 스토리는 만든 뒤 `label add` 로 나머지 `repo:` 라벨을 더한다.
# 레포 slug 는 `owner/<repo 이름>` 이다 — 대상 레포 등록부를 읽지 않는다. 이름의 실재는 gh 가 판정한다.
# **천장**: 그래서 owner 가 다른 대상 레포(다른 org·다른 사용자)에는 닿지 못한다. 등록부에 그 레포의 url 이
#   있어도 이 어댑터는 읽지 않는다. 지금 등재된 레포가 전부 같은 owner 라 무해하다 — 갈리는 날 이 자리를 고친다.
#
# **원장의 경계는 Projects v2 소속이다** (사용자 결정 2026-09-06). list·ready 는 등재 레포의 이슈를
# 받아 각 이슈의 projectItems 로 project 소속을 보고 거른다 — 거르지 않으면 경계가 "등재 레포의 모든
# 이슈" 가 되어 남의 레포 백로그가 원장으로 읽힌다 (실측 2026-09-06: 픽스처 152건 중 약 120건이
# 대상 레포 자신의 이슈였고 열린 29건은 전부 그쪽이었다 — harness-kw0l.3.2 의 note).
# 소속을 **이슈 쪽에서** 판정하는 이유: `gh project item-list` 는 item-add 직후 그 항목을 내지 않는다
# (M0 실측). 이슈의 projectItems 는 같은 질의에 얹히므로 레포마다 GraphQL 1회 그대로다.
# **show·children 은 id 로 직접 읽으므로 소속을 요구하지 않는다** — 이미 아는 id 를 못 읽게 막는 것은
# 경계가 아니라 사고다. 소속 필터는 "무엇이 원장의 목록인가" 를 정할 뿐이다.
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
#   actor                마지막 `ACTOR: <값>` 코멘트의 <값> (없으면 null) — 그 항목을 잡은 세션이다.
#                        assignee 와 갈리는 이유: 이 백엔드의 claim 은 assignee 에 `@me`(사람의 GitHub
#                        로그인)를 넣고 세션 actor 는 코멘트로 남기므로 한 필드가 둘을 겸할 수 없다.
#                        정지 가드(hooks/stop-resume.sh)가 `.actor // .assignee` 로 읽는다 —
#                        beads·notion 은 그 개념이 assignee 하나뿐이라 actor 가 같은 값이다.
#                        줄의 **마지막 공백 구분 토큰**을 값으로 읽는다 — claim 이 남기는 것은
#                        `ACTOR: <값>` 한 토큰이지만 스토리 항목의 ACTOR note 는 `ACTOR: <레포> <값>`
#                        이라(harness:develop 1절) 첫 토큰을 읽으면 스토리에서 레포 이름을 집는다.
#   parent               sub-issue 부모의 <repo>#<number> (없으면 null)
#   dependencies         blocked_by 목록 [{id, status, dependency_type:"blocks"}] — FIELDS 의 blockedBy 에서
#                        나오므로 show 만이 아니라 list·children 등 norm 을 거치는 모든 산출물에 실린다.
#   priority             2 고정 (대응 필드 없음)
#   created_at·updated_at·closed_at
#
# ponytail: 라벨·코멘트·자식은 first:100, blockedBy 는 first:50, 이슈의 projectItems 는 first:20,
# sprints 의 project 필드는 first:100 까지만 읽는다 — 그 이상은 페이지네이션이 필요하다
# (한 이슈가 21개 넘는 프로젝트에 들면 소속을 놓친다).
set -uo pipefail
: "${LEDGER_ROOT:?ledger.sh 를 통해 불러라}"; : "${LEDGER_CONFIG:?ledger.sh 를 통해 불러라}"

die() { echo "ledger-github: $*" >&2; exit 1; }

# 워크트리 배선 — 이 백엔드는 워크트리에 아무것도 두지 않는다. 이슈는 원격에 있고 루트는
# HARNESS_ROOT 또는 ~/.harness-workspace/ledger.json(lib/harness-root.sh)으로 찾는다. gh 없이도 답한다.
[ "${1:-}" = "wire-worktree" ] && { echo "ledger-github: 워크트리 배선 없음 — 루트는 HARNESS_ROOT 또는 클론 루트 직속의 ledger.json 으로 찾는다"; exit 0; }
# 원격 반영 검사 — 이슈가 원격 자체라 앞서 있을 로컬 사본이 없다. checks/ledger-check.sh 가 부른다.
[ "${1:-}" = "sync-check" ] && { echo "✓ 원장 게이트 통과 — 원격 반영 대상 없음 (github 백엔드: 이슈가 원격 자체다)"; exit 0; }
# 사람이 읽는 자기 UI — 갖는다. scripts/board.sh 가 이것으로 렌더 여부를 정한다(코어는 백엔드
# 이름을 열거하지 않는다). 위 둘과 같이 gh 검사 앞에 둔다 — 답이 상수라 원장에 닿지 않는다.
[ "${1:-}" = "has-ui" ] && { echo "GitHub 의 이슈·Projects 화면"; exit 0; }
OWNER="$(jq -r '.owner // empty' "$LEDGER_CONFIG")"
PROJECT="$(jq -r '.project // empty' "$LEDGER_CONFIG")"
[ -n "$OWNER" ] || die "$LEDGER_CONFIG 에 owner 가 없다"
command -v gh >/dev/null 2>&1 || die "gh 가 PATH 에 없다 — GitHub 백엔드는 gh 로 원장에 닿는다"
gh auth status >/dev/null 2>&1 || die "gh 인증이 없다 — 사람이 gh auth login 을 먼저 한다"

# ── 레포·id ───────────────────────────────────────────────────────────
slug_of() { # <repo 이름> → owner/name — owner 는 ledger.json 이 정한다(등록부를 읽지 않는다)
  [ -n "$1" ] || die "레포 이름이 비었다"
  printf '%s/%s\n' "$OWNER" "$1"
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
# 읽기가 훑을 레포 목록 — **Projects v2 항목이 사는 레포다.** 등록부를 읽지 않는다: 등록부는
# 머신 로컬이고 원장은 원격이라 둘이 갈리면 원격이 옳고, 이 백엔드의 원장 경계는 이미 project
# 소속이다(머리 주석). 항목이 0건이면 훑을 레포도 0개이고 그것은 갓 만든 빈 프로젝트의 정상
# 모양이므로 실패가 아니다 — 호출자가 stderr 로 밝힌다.
# ponytail: content 가 Issue 인 항목만 이름을 낸다 — draft 항목·PR 은 원장이 아니다.
repos_all() {
  local out
  out="$(gh api graphql --paginate --slurp -f query='query($o:String!,$n:Int!,$endCursor:String){ user(login:$o){ projectV2(number:$n){ items(first:100, after:$endCursor){ nodes{ content{ ... on Issue { repository{name} } } } pageInfo{hasNextPage endCursor} } } } }' -f o="$OWNER" -F n="$PROJECT" 2>/dev/null)" \
    || return 1
  printf '%s' "$out" | jq -r '[.[].data.user.projectV2.items.nodes[]?.content.repository.name // empty] | unique | .[]'
}

# ── GraphQL ───────────────────────────────────────────────────────────
FIELDS='id databaseId number title state body createdAt updatedAt closedAt repository{name} labels(first:100){nodes{name}} assignees(first:10){nodes{login}} comments(first:100){nodes{body}} parent{number repository{name}} blockedBy(first:50){totalCount nodes{number state repository{name}}}'
# bd 의 키로 정규화한다. body 는 "<description>\n\n## Acceptance\n\n<acceptance>" 로 쓰고 같은 자리에서 가른다.
NORM='def norm:
  ((.body // "") | if startswith("## Acceptance\n") then "\n" + . else . end | split("\n## Acceptance\n")) as $parts
  | (.labels.nodes | map(.name)) as $ls
  # 이 error() 는 norm 을 거치는 모든 읽기를 죽인다 — ready 뿐 아니라 list 도이고, 따라서
  # status·triage·board 까지 선다. 의존 51개짜리 이슈 하나면 그렇게 된다. 탈출구는 아래 메시지가
  # 이름으로 드는 FIELDS 의 blockedBy(first:N) 을 늘리는 플러그인 편집뿐이다.
  | (if .blockedBy.totalCount > (.blockedBy.nodes | length)
     then error("blockedBy 가 잘렸다: " + .repository.name + "#" + (.number|tostring)
                + " — totalCount=" + (.blockedBy.totalCount|tostring)
                + " 받은 노드=" + (.blockedBy.nodes|length|tostring)
                + " · FIELDS 의 blockedBy(first:N) 을 늘려라. 조용히 자르면 ready 가 막힌 것을 열렸다고 낸다.")
     else . end)
  | { id: (.repository.name + "#" + (.number|tostring)),
      title: .title,
      description: (($parts[0] // "") | rtrimstr("\n")),
      acceptance_criteria: (if ($parts|length) > 1 then ($parts[1:] | join("\n## Acceptance\n") | ltrimstr("\n") | rtrimstr("\n")) else "" end),
      status: (if .state == "CLOSED" then "closed" else (($ls | map(select(startswith("status:"))) | first // "status:open") | ltrimstr("status:")) end),
      issue_type: (($ls | map(select(startswith("type:"))) | first // "type:task") | ltrimstr("type:")),
      labels: ($ls | map(select((startswith("type:") or startswith("status:")) | not)) | sort),
      notes: (if (.comments.nodes|length) == 0 then null else (.comments.nodes | map(.body) | join("\n")) end),
      assignee: (.assignees.nodes[0].login // null),
      actor: ([.comments.nodes[].body
               | capture("^ACTOR:[ \t]*(?<v>[^\r\n]*)").v
               | (split(" ") | map(select(length > 0)) | last)]
              | map(select(. != null)) | last),
      dependencies: (.blockedBy.nodes | map({ id: (.repository.name + "#" + (.number|tostring)),
                                              status: (if .state == "CLOSED" then "closed" else "open" end),
                                              dependency_type: "blocks" })),
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
# 이슈가 Project $PROJECT 에 실제로 들어 있는가 — **다시 읽어서** 답한다. 소속은 create 가
# `gh project item-add` 의 종료 코드로 짐작하던 것이고, 그 짐작이 이슈는 만들어졌는데 rc 만
# 비-0 인 부분 등재를 실패로 읽었다(skills#210 실측). 질의는 읽기 경로의 PROJECT_FIELD 하나다.
in_project() { # SLUG NUM → 소속이면 rc 0
  local o="${1%%/*}" r="${1##*/}" out
  out="$(gh api graphql -f query="query(\$o:String!,\$r:String!,\$n:Int!){ repository(owner:\$o,name:\$r){ issue(number:\$n){ $PROJECT_FIELD } } }" -f o="$o" -f r="$r" -F n="$2" 2>/dev/null)" || return 1
  printf '%s' "$out" | jq -e --arg p "$PROJECT" \
    'any(.data.repository.issue.projectItems.nodes[]?; (.project.number | tostring) == $p)' >/dev/null 2>&1
}
node_id() { gh api "repos/$1/issues/$2" --jq .node_id; }
db_id()   { gh api "repos/$1/issues/$2" --jq .id; }
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
# 소속 판정용 필드. FIELDS 에 넣지 않는 이유: show·children 은 소속을 요구하지 않으므로(머리 주석)
# 그쪽 질의까지 무겁게 할 까닭이 없다. 읽기 경로에만 얹는다.
PROJECT_FIELD='projectItems(first:20){nodes{project{number}}}'
list_json() { # 옵션을 파싱해 정규화된 JSON 배열을 낸다. 상태 필터가 closed 를 안 들면 OPEN 만 읽는다.
  local labels="" pattern="" status="" type="" parent="" all="" limit=50 o r states out="[]" re="" nodes seen=0 kept=0
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
  # 레포 목록의 출처가 없으면 여기서 죽는다 — `for name in $(repos_all)` 안의 실패는 명령 치환에 갇혀 빈 루프가
  # 되고 "이슈 0건" 으로 rc 0 이 났다(harness-m8gg.4 verify-code 2차의 관찰). 실패를 삼키지 않는다.
  local names
  [ -n "$PROJECT" ] || die "list: $LEDGER_CONFIG 에 project 가 없다 — 읽기의 경계가 Projects v2 소속이라 번호 없이는 무엇이 원장인지 정할 수 없다 (ledger.sh init 이 만든다)"
  names="$(repos_all)" || die "list: Project $PROJECT (owner $OWNER) 의 항목을 읽지 못했다 — 이슈가 사는 레포 목록의 출처다"
  [ -n "$names" ] || echo "ledger-github: Project $PROJECT (owner $OWNER) 에 이슈 항목이 0건이다 — 훑을 레포가 없다. $LEDGER_CONFIG 의 project 번호를 확인하라." >&2
  for name in $names; do
    o="$(slug_of "$name")"; r="${o##*/}"; o="${o%%/*}"
    page="$(gh api graphql --paginate --slurp -f query="query(\$o:String!,\$r:String!,\$endCursor:String){ repository(owner:\$o,name:\$r){ issues(first:100, after:\$endCursor, states:$states){ nodes{ $FIELDS $PROJECT_FIELD } pageInfo{hasNextPage endCursor} } } }" -f o="$o" -f r="$r" 2>/dev/null)" \
      || die "list: $o/$r 의 이슈를 읽지 못했다"
    nodes="$(printf '%s' "$page" | jq '[.[].data.repository.issues.nodes[]]')" \
      || die "list: $o/$r 의 응답을 읽지 못했다"
    seen=$((seen + $(printf '%s' "$nodes" | jq 'length')))
    # 경계: Projects v2 소속. 번호는 문자열로 견줘 ledger.json 의 project 가 수가 아니어도 죽지 않는다.
    nodes="$(printf '%s' "$nodes" | jq --arg p "$PROJECT" 'map(select(any(.projectItems.nodes[]?; (.project.number | tostring) == $p)))')" \
      || die "list: $o/$r 의 project 소속을 판정하지 못했다"
    kept=$((kept + $(printf '%s' "$nodes" | jq 'length')))
    out="$(printf '%s\n%s' "$out" "$nodes" | jq -s "$NORM"'.[0] + (.[1] | map(norm))')" \
      || die "list: $o/$r 의 응답을 정규화하지 못했다"
  done
  # 없는(또는 틀린) project 번호는 조용히 "이슈 0건" 이 된다 — 0건은 정상 상태와 구별되지 않으므로
  # 그 사실을 stderr 로 밝힌다. rc 는 0 이다: 갓 만든 빈 프로젝트도 같은 모양이라 실패로 읽을 수 없다.
  if [ "$kept" -eq 0 ] && [ "$seen" -gt 0 ]; then
    echo "ledger-github: Project $PROJECT 에 든 이슈가 0건이다 — 등재 레포의 이슈 ${seen}건은 전부 프로젝트 밖이다. $LEDGER_CONFIG 의 project 번호를 확인하라." >&2
  fi
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
    # ── ITERATION 필드. **이 백엔드에서 스프린트의 원본이 그 필드다** — 없으면 sprints 가 답할
    # 수 없고, 갓 세운 하네스가 문서화된 경로로 스프린트를 읽을 수 없다(이 태스크의 배경).
    # gh project field-create 는 ITERATION 을 지원하지 않아 gh api graphql 로 만든다(M0 실측).
    #
    # **멱등하다** — 먼저 읽고 없을 때만 만든다. 있으면 이름을 들어 한 줄로 말하고 넘어간다.
    # 판별은 sprints 와 같은 축이다(configuration 이 있는 필드 = ITERATION 필드) — 두 자리가
    # 다른 기준으로 같은 필드를 찾으면 한쪽이 만든 것을 다른 쪽이 못 보는 판이 생긴다.
    #
    # 이름은 "Sprint" 다. sprints 는 dataType 으로 찾고 이름을 읽지 않으므로 값 자체는 계약이
    # 아니지만, 이미 서 있는 원장(project 5)이 손으로 만들어 쓰는 이름이 그것이라 맞춘다 —
    # 다른 이름을 쓰면 사람이 GitHub UI 에서 두 열을 보게 된다.
    #
    # **iteration 은 하나도 만들지 않는다.** iteration 의 title 이 곧 스프린트 ID(YYYY-SNN)이고
    # 그것은 사람이 plan-sprint 에서 정하는 값이라 init 이 알 수 없다. 자리를 채우려고 하나
    # 만들면 그것이 등록부에 실재하는 스프린트로 나온다 — 없는 것보다 나쁘다.
    #
    # **"갓 만든 ITERATION 필드는 iteration 이 0개다" 는 실측이다** — 아래 뮤테이션을 그대로
    # 시험용 Projects v2 에 돌려 확인했다(2026-09-07, skills#167 리뷰 대응). GitHub 이 기본
    # configuration 을 딸려 주면 갓 init 한 루트가 없는 스프린트를 등재하므로, 픽스처가 아니라
    # 실제 API 로 봐야 하는 자리다. 본 것 셋:
    #   ① createProjectV2Field 응답의 configuration = {duration:0, startDay:0,
    #      iterations:[], completedIterations:[]}
    #   ② 같은 필드를 별도 질의(fields(first:100))로 다시 읽어도 두 배열이 그대로 비어 있다
    #      — 생성 응답만 비어 보이는 착시가 아니다
    #   ③ 그 상태의 `ledger.sh sprints --json` 이 rc 0 · `[]` · 아래 "iteration 이 하나도 없다"
    #      stderr 한 줄
    # 시험용 project 는 지웠다. 픽스처(checks/ledger-adapter-check.sh 의 FAKE_GH_EMPTY_ITERATION)
    # 는 여기서 본 모양을 옮긴 것이지 그 반대가 아니다.
    # ponytail: 필드는 first:100(GraphQL 한 페이지 상한)까지만 읽는다. 그 이상이면 이미 있는
    # 필드를 못 보고 하나 더 만들 수 있다 — sprints 의 같은 천장과 한 짝이다.
    fq='query($o:String!,$n:Int!){ user(login:$o){ projectV2(number:$n){ id fields(first:100){ nodes{
          ... on ProjectV2IterationField { name configuration { iterations { title } } } } } } } }'
    fout="$(gh api graphql -f query="$fq" -f o="$OWNER" -F n="$PROJECT" 2>&1)" \
      || die "init: Projects v2 $PROJECT (owner $OWNER) 의 필드를 읽지 못했다 — $fout"
    have="$(printf '%s' "$fout" | jq -r '[.data.user.projectV2.fields.nodes[] | select(.configuration != null)] | first.name // empty')" \
      || die "init: 필드 응답을 읽지 못했다 — $fout"
    if [ -n "$have" ]; then
      echo "✓ ITERATION 필드 '$have' 가 이미 있다 — 다시 만들지 않는다"
    else
      pid="$(printf '%s' "$fout" | jq -r '.data.user.projectV2.id // empty')"
      [ -n "$pid" ] || die "init: Projects v2 $PROJECT 의 node id 를 읽지 못했다 — 번호가 틀렸거나, owner 가 사용자가 아니다(이 질의는 user(login:) 이라 조직 소유 project 에 닿지 않는다)"
      mq='mutation($p:ID!){ createProjectV2Field(input: {projectId: $p, dataType: ITERATION, name: "Sprint"})
            { projectV2Field { ... on ProjectV2IterationField { name } } } }'
      mout="$(gh api graphql -f query="$mq" -f p="$pid" 2>&1)" \
        || die "init: ITERATION 필드를 만들지 못했다 — $mout (토큰에 project scope 가 없으면 'gh auth refresh -h github.com -s project,read:project')"
      # "비어 있다" 는 위 실측(①②)의 결론이다 — 응답을 다시 읽어 확인하지는 않는다.
      echo "✓ ITERATION 필드 'Sprint' 를 만들었다 — iteration 은 비어 있다(스프린트 ID 는 plan-sprint 에서 사람이 정한다)"
    fi
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
    # 이슈가 살 레포는 `repo:` 라벨 정확히 하나가 정한다. 등록부가 사라져 이름의 실재를 여기서
    # 확인할 수 없으므로(머리 주석), 애매한 입력 — 0개(레포를 모른다) · 2개 이상(어느 쪽인지
    # 모른다) — 을 세워서 막는다. --parent 로 넘겨받던 폴백은 없앴다: 부모의 레포를 조용히
    # 물려받으면 라벨과 실제 자리가 갈린 이슈가 생긴다.
    repo=""; nrepo=0
    for l in $(printf '%s' "$labels" | tr ',' ' '); do case "$l" in repo:*) repo="${l#repo:}"; nrepo=$((nrepo + 1)) ;; esac; done
    [ "$nrepo" -eq 1 ] || die "create: repo: 라벨이 ${nrepo}개다 — 이슈가 살 레포는 정확히 하나여야 한다 (-l repo:<이름>). 여러 레포에 걸치는 스토리는 만든 뒤 'label add' 로 나머지를 더한다"
    slug="$(slug_of "$repo")" || exit 1
    all_labels="type:$type${labels:+,$labels}"
    for l in $(printf '%s' "$all_labels" | tr ',' ' '); do ensure_label "$slug" "$l"; done
    body="$(mktemp)"; compose_body "$desc" "$acc" > "$body"
    url="$(gh issue create -R "$slug" -t "$title" -F "$body" -l "$all_labels" 2>/dev/null)"; rc=$?; rm -f "$body"
    [ "$rc" -eq 0 ] && [ -n "$url" ] || die "gh issue create 실패 ($slug)"
    num="${url##*/}"
    if [ -n "$parent" ]; then split_id "$parent"; add_sub_issue "$SLUG" "$NUM" "$slug" "$num"; fi
    # **item-add 의 rc≠0 은 "안 들어갔다" 가 아니라 "모른다" 다.** 그때는 죽지 말고 소속을
    # **다시 읽어** 판정한다 (docs/guardrails.md 5-1 — 시도한 반영은 검사를 통과하지 못한다,
    # 종료 코드가 아니라 다시 세어본 결과가 판정한다). 이슈는 이 줄 **앞에서** 이미 만들어지므로
    # rc 하나로 죽으면 실재하는 등재가 실패로 기록된다 (skills#210 실측 ①② — 이 스토리를 쪼갤 때
    # 실제로 그랬다). gh 의 stderr 도 버리지 않고 죽을 때 싣는다 — 버리면 진짜 사유(scope 부족·
    # 번호 오류)가 영영 보이지 않는다 (같은 실측 ③).
    # **rc 0 에서는 다시 읽지 않는다.** 소속 조회가 item-add 직후에 신선한지는 미측정이고, 같은
    # 계열의 `gh project item-list` 는 직후에 새 항목을 내지 않는 것이 실측이다(머리 주석). 보고된
    # 성공을 낡을 수 있는 조회로 뒤집으면 흔한 경로에서 거짓 실패가 난다 — 그 대가가 이 자리가
    # 고치는 실패보다 크다. 검사가 그 극성을 든다(checks/ledger-adapter-check.sh ④).
    add_err="$(gh project item-add "$PROJECT" --owner "$OWNER" --url "$url" 2>&1 >/dev/null)"; add_rc=$?
    [ "$add_rc" -eq 0 ] || in_project "$slug" "$num" \
      || die "이슈 $repo#$num 은 만들었지만 Project $PROJECT 소속이 아니다 (item-add rc=$add_rc, 소속을 다시 읽어도 없다) — project scope 또는 번호를 확인하라${add_err:+ · gh: $add_err}"
    if [ -n "$silent" ]; then echo "$repo#$num"; else echo "✓ Created issue: $repo#$num — $title"; fi
    ;;

  show)
    [ $# -gt 0 ] || die "show: id 가 필요하다"
    split_id "$1"; shift
    node="$(fetch_issue "$SLUG" "$NUM")" || exit 1
    obj="$(printf '%s' "$node" | jq "$NORM"'[norm]')" || die "show: 응답을 정규화하지 못했다: $REPO#$NUM"
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
    # open 이고 의존이 전부 closed 인 것 (bd ready 와 같이 in_progress·blocked·deferred 는 뺀다).
    # 의존 관계는 list_json 의 GraphQL 질의가 blockedBy 로 이미 실어 온다 — 이슈마다 따로 부르지 않는다.
    limit=50; args=""; json=""
    while [ $# -gt 0 ]; do
      case "$1" in -n|--limit) limit="$2"; shift 2 ;; --json) json=1; shift ;; -l|--label|--labels|-t|--type) args="$args $1 $2"; shift 2 ;; *) die "ready: 모르는 인자 '$1'" ;; esac
    done
    # shellcheck disable=SC2086
    arr="$(list_json --status open -n 0 $args)" || exit 1
    arr="$(printf '%s' "$arr" | jq --argjson limit "$limit" 'map(select(all(.dependencies[]; .status == "closed"))) | if $limit > 0 then .[:$limit] else . end')" \
      || die "ready: 의존 관계로 거르지 못했다"
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
    status=""; claim=""; actor=""; parent=""; type=""; acc=""; desc=""; set_desc=""; assignee=""; set_assignee=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -s|--status) status="$2"; shift 2 ;;
        --claim) claim=1; shift ;;
        --actor) actor="$2"; shift 2 ;;
        -a|--assignee) assignee="$2"; set_assignee=1; shift 2 ;;
        --parent) parent="$2"; shift 2 ;;
        -t|--type) type="$2"; shift 2 ;;
        --acceptance) acc="$2"; shift 2 ;;
        --body-file) desc="$(read_body_file "$2")"; set_desc=1; shift 2 ;;
        -d|--description) desc="$2"; set_desc=1; shift 2 ;;
        --json) shift ;;
        *) die "update: 모르는 인자 '$1'" ;;
      esac
    done
    # --assignee 는 claim 과 **다른 경로**다: claim 은 실행자(@me)를 붙이고 status 를 in_progress 로
    # 옮기지만 이 옵션은 assignee 만 바꾼다(레일 담당자는 epic 의 assignee 다 — 스토리 skills#105).
    # 같이 주면 두 쓰기가 같은 필드를 겹쳐 어느 쪽이 남는지가 코드 순서에 달린다 — 거부한다.
    [ -n "$claim" ] && [ -n "$set_assignee" ] && die "update: --claim 과 --assignee 는 같이 쓸 수 없다 (claim 은 실행자를 넣고 status 를 옮긴다)"
    if [ -n "$claim" ]; then
      gh issue edit "$NUM" -R "$SLUG" --add-assignee @me >/dev/null 2>&1 || die "assignee 를 붙이지 못했다: $REPO#$NUM"
      [ -n "$actor" ] && { gh issue comment "$NUM" -R "$SLUG" -b "ACTOR: $actor" >/dev/null 2>&1 || die "ACTOR 코멘트 실패: $REPO#$NUM"; }
      [ -n "$status" ] || status="in_progress"
    fi
    if [ -n "$set_assignee" ]; then
      # 빈 문자열이면 지우기다. PATCH 는 assignees 목록을 **대체**하므로 넣기와 지우기가 한 경로다 —
      # gh issue edit 의 --remove-assignee 로 지우려면 현재 login 을 먼저 읽어야 해 왕복이 는다.
      # 대체이므로 assignee 가 2명 이상인 이슈에서는 나머지가 함께 지워진다. 이 어댑터의 계약이
      # assignee 1명(대응표: `.assignees.nodes[0].login`)이라 계약 안의 부작용이지만, 지워졌다는
      # 사실은 원장 JSON 으로 보이지 않는다.
      # **200 은 성공의 근거가 아니다**: PATCH 는 assign 할 수 없는 login 을 조용히 버리고 200 을 낸다.
      # 그래서 rc 가 아니라 **응답에 실린 assignees 를 대조한다**(응답에 갱신된 목록이 이미 실려 온다).
      # 앞에 GET repos/<slug>/assignees/<login> 선검사를 두는 길도 되지만, 그 GET 과 이 PATCH 사이가
      # 열려 있어 같은 구멍이 남으면서 왕복만 는다. login 은 대소문자를 가리지 않아 낮춰서 견준다.
      # **이 파이프라인의 rc 는 머리의 `set -o pipefail` 에 기댄다.** 그것이 없으면 gh 가 실패하며
      # 오류 본문({"message":"Not Found"})을 stdout 으로 흘릴 때 마지막 jq 의 rc 만 남고, 지우기
      # (--assignee "")에서는 그 대조가 참이 되어 실패가 성공으로 읽힌다(skills#160 재리뷰 실측).
      jq -n --arg a "$assignee" '{assignees: (if $a == "" then [] else [$a] end)}' \
        | gh api -X PATCH "repos/$SLUG/issues/$NUM" --input - 2>/dev/null \
        | jq -e --arg a "$assignee" '(.assignees[0].login // "" | ascii_downcase) == ($a | ascii_downcase)' >/dev/null \
        || die "assignee 를 '$assignee' 로 바꾸지 못했다: $REPO#$NUM — 원인 둘을 이 자리에서 가르지 않는다: (1) PATCH 자체가 실패했다(권한·네트워크·없는 이슈) (2) 200 을 받았으나 응답의 assignees 가 '$assignee' 가 아니다 — 레포 $SLUG 에 assign 할 수 없는 login 을 GitHub 이 조용히 버리는 경우다"
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

  sprint-add)
    # 스프린트 등재 — ITERATION 필드에 iteration 하나를 더한다(title 이 스프린트 ID). ID 형식
    # 판정과 중복 판정은 ledger.sh 가 이미 했다.
    #
    # **GitHub 에는 "iteration 하나를 더한다" 는 API 가 없다.** 있는 것은
    # `updateProjectV2Field(iterationConfiguration:{duration, startDate, iterations})` 하나이고
    # 그것은 **iterations 전체를 대체한다**(GitHub GraphQL 스키마: ProjectV2Iteration 입력에 id 가
    # 없다 — docs.github.com/en/graphql/reference/projects 의 UpdateProjectV2FieldInput ·
    # ProjectV2IterationFieldConfigurationInput · ProjectV2Iteration, 2026-09-07 확인).
    # 그래서 **읽은 것을 전부 되돌려 보내고 새 것 하나를 뒤에 붙인다** — completedIterations 까지
    # 함께 싣는다. 빠뜨리면 닫힌 스프린트가 등록부에서 사라지고 board-check 가 그 sprint: 라벨을
    # 전부 미등재로 읽는다.
    # **천장**: 대체이므로 항목↔iteration 연결은 보존되지 않는다(GitHub 커뮤니티 보고). 이 하네스는
    # 항목에 iteration 값을 넣지 않는다 — 스프린트 소속은 `sprint:` 라벨이고, 플러그인 트리에
    # updateProjectV2ItemFieldValue 호출이 0건이다(실측 grep). 사람이 GitHub UI 에서 손으로 넣은
    # 값이 있으면 그것은 잃는다.
    # **실제 GitHub 왕복으로 확인하지 않았다** — 판정은 아래 오프라인 픽스처뿐이다.
    [ $# -eq 1 ] || die "sprint-add: 인자는 스프린트 ID 하나다"
    sid="$1"
    [ -n "$PROJECT" ] || die "sprint-add: $LEDGER_CONFIG 에 project 가 없다 — 스프린트가 사는 ITERATION 필드가 그 프로젝트에 있다 (ledger.sh init 이 만든다)"
    fq='query($o:String!,$n:Int!){ user(login:$o){ projectV2(number:$n){ fields(first:100){ nodes{
          ... on ProjectV2IterationField { id configuration {
            duration
            iterations{ title startDate duration }
            completedIterations{ title startDate duration } } } } } } } }'
    fout="$(gh api graphql -f query="$fq" -f o="$OWNER" -F n="$PROJECT" 2>&1)" \
      || die "sprint-add: Projects v2 $PROJECT (owner $OWNER) 의 필드를 읽지 못했다 — $fout"
    fld="$(printf '%s' "$fout" | jq -c '[.data.user.projectV2.fields.nodes[]? | select(.configuration != null)] | first // empty')" \
      || die "sprint-add: 필드 응답을 읽지 못했다 — $fout"
    [ -n "$fld" ] || die "sprint-add: Projects v2 $PROJECT 의 필드(첫 100개) 안에 ITERATION 필드가 없다 — 이 백엔드에서 스프린트가 사는 자리가 그 필드다. 이 필드는 ledger.sh init 이 만든다(멱등): 'HARNESS_ROOT=<루트> ledger.sh init'"
    fid="$(printf '%s' "$fld" | jq -r '.id // empty')"
    [ -n "$fid" ] || die "sprint-add: ITERATION 필드의 node id 를 읽지 못했다"
    # 기간은 필드가 이미 쓰는 값을 그대로 쓴다. 갓 만든 필드는 duration 이 0 이라(skills#167 실측)
    # 그때만 2주를 쓴다 — GitHub UI 의 기본값이 2주다.
    dur="$(printf '%s' "$fld" | jq -r '.configuration.duration // 0')"
    case "$dur" in ''|*[!0-9]*|0) dur=14 ;; esac
    exist="$(printf '%s' "$fld" | jq -c '[(.configuration.completedIterations[]?), (.configuration.iterations[]?)]
                                          | map({title, startDate, duration}) | sort_by(.startDate)')" \
      || die "sprint-add: 지금 iteration 목록을 읽지 못했다"
    # 새 iteration 은 **마지막 것이 끝난 다음 날**부터다 — 겹치면 GitHub 이 어느 쪽을 현재로 볼지
    # 이 코드가 정하지 못한다. 하나도 없으면 오늘부터다.
    # date 는 BSD(-j -v)와 GNU(-d) 두 문면을 다 시도하고, 둘 다 실패하면 죽는다 — 빈 값을 Date! 에
    # 실어 보내면 GraphQL 오류 문면이 원인을 가린다.
    if [ "$(printf '%s' "$exist" | jq -r 'length')" = "0" ]; then
      start="$(date -u '+%Y-%m-%d')"
    else
      ls="$(printf '%s' "$exist" | jq -r '.[-1].startDate')"
      ld="$(printf '%s' "$exist" | jq -r '.[-1].duration')"
      start="$(date -u -j -v+"${ld}"d -f '%Y-%m-%d' "$ls" '+%Y-%m-%d' 2>/dev/null)" \
        || start="$(date -u -d "$ls + $ld days" '+%Y-%m-%d' 2>/dev/null)" || start=""
    fi
    case "$start" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
      *) die "sprint-add: 새 iteration 의 시작일을 계산하지 못했다 ('$start') — date 가 BSD(-j -v)도 GNU(-d)도 아니다" ;;
    esac
    iters="$(printf '%s' "$exist" | jq -c --arg t "$sid" --arg s "$start" --argjson d "$dur" \
      '. + [{title: $t, startDate: $s, duration: $d}]')" || die "sprint-add: 보낼 iteration 목록을 만들지 못했다"
    cstart="$(printf '%s' "$iters" | jq -r '.[0].startDate')"
    mq='mutation($f:ID!,$d:Int!,$s:Date!,$it:[ProjectV2Iteration!]!){
          updateProjectV2Field(input:{fieldId:$f, iterationConfiguration:{duration:$d, startDate:$s, iterations:$it}}){
            projectV2Field { ... on ProjectV2IterationField { name } } } }'
    # 변수에 배열이 있어 `gh api graphql -f` 로는 실을 수 없다(스칼라만 받는다) — 본문을 통째로
    # 만들어 --input - 로 넘긴다.
    req="$(jq -n --arg q "$mq" --arg f "$fid" --argjson d "$dur" --arg s "$cstart" --argjson it "$iters" \
      '{query: $q, variables: {f: $f, d: $d, s: $s, it: $it}}')" || die "sprint-add: 요청 본문을 만들지 못했다"
    mout="$(printf '%s' "$req" | gh api graphql --input - 2>&1)" \
      || die "sprint-add: iteration 을 더하지 못했다 — $mout (토큰에 project scope 가 없으면 'gh auth refresh -h github.com -s project,read:project')"
    printf '%s' "$mout" | jq -e '.data.updateProjectV2Field.projectV2Field' >/dev/null 2>&1 \
      || die "sprint-add: 뮤테이션이 200 을 냈지만 응답에 필드가 없다 — $mout"
    echo "✓ 스프린트 등재: $sid (github: Projects v2 $PROJECT 의 ITERATION 필드에 iteration — 시작 $start · ${dur}일)"
    ;;

  # 등록부 질의 — 이 백엔드가 자기 계층으로 답한다(스토리 skills#105 결정 2). beads 가 루트의
  # rails.json·sprints.json 을 읽는 자리에서 github 은 원장 자신(라벨·assignee·Projects v2)을 읽는다.
  # wire-worktree·sync-check 와 달리 위(gh 검사 앞)에 두지 않는다 — 그 둘은 gh 에 닿지 않는 상수
  # 응답이지만 이 둘은 실제로 원장을 읽으므로 OWNER·gh·인증이 다 필요하고, rails 는 아래에서
  # 정의되는 list_json 을 쓴다.
  rails|sprints)
    for a in "$@"; do [ "$a" = --json ] || die "$cmd: 모르는 인자 '$a' (사용: $cmd --json)"; done
    # 두 질의 모두 project 번호 없이는 답할 수 없다 — rails 는 읽기의 경계(Projects v2 소속)로,
    # sprints 는 Iteration 필드가 사는 곳으로 쓴다. 어느 키가 문제인지 이름으로 든다.
    [ -n "$PROJECT" ] || die "$cmd: $LEDGER_CONFIG 에 project 가 없다 (없거나 JSON 을 읽지 못했다) — rails 는 읽기의 경계가 Projects v2 소속이고 sprints 는 그 프로젝트의 Iteration 필드에서 나온다 (ledger.sh init 이 만든다)"
    case "$cmd" in
      rails)
        # owner 의 출처는 **epic 의 assignee** 하나뿐이다 — task 의 assignee 는 claim 실행자의
        # login 이라 레일 담당자가 아니다(사용자 결정, skills#141 note). 닫힌 epic 도 읽는다(--all):
        # 레일은 그 레일의 일이 다 끝나도 등록부에 남는 사람이라, 열린 epic 만 보면 조용히 사라진다.
        # 읽기는 list_json 을 그대로 쓴다 — 원장의 경계·라벨 필터·정규화가 이미 거기 있고, 여기만
        # 다른 경로로 읽으면 "무엇이 원장인가" 가 둘로 갈린다.
        epics="$(list_json --all -t epic --label-pattern 'rail:*' -n 0)" || exit 1
        # rail: 라벨은 있는데 assignee 가 없는 epic 은 owner 를 낼 수 없어 아래에서 빠진다. 그 레일이
        # 조용히 사라지는 것과 "레일이 없다" 는 구별되지 않으므로 이름을 든다. rc 는 0 이다 —
        # 다른 epic 이 같은 레일의 owner 를 대고 있으면 결과가 온전하다.
        blank="$(printf '%s' "$epics" | jq -r '[.[] | select(.assignee == null) | .id] | join(" ")')" \
          || die "rails: epic 목록을 읽지 못했다"
        [ -z "$blank" ] || echo "ledger-github: rails: assignee 가 없는 epic — $blank (그 epic 만으로는 레일 owner 를 파생할 수 없다: ledger.sh update <id> --assignee <login>)" >&2
        # 한 레일 = 한 사람(rails.json 의 계약)이라, 같은 레일의 epic 들이 서로 다른 사람을 가리키면
        # 어느 쪽이 owner 인지 코드가 정할 수 없다. 하나를 골라 덮지 않고 이름을 들어 죽는다.
        pairs='[ .[] | select(.assignee != null) | . as $e
                 | ($e.labels[] | select(startswith("rail:")) | ltrimstr("rail:"))
                 | {id: ., owner: $e.assignee} ] | group_by(.id)'
        conflict="$(printf '%s' "$epics" | jq -r "$pairs"' | map(select((map(.owner) | unique | length) > 1)
                      | "\(.[0].id)=" + (map(.owner) | unique | join("/"))) | join(" · ")')" \
          || die "rails: epic 의 rail: 라벨과 assignee 를 대조하지 못했다"
        [ -z "$conflict" ] || die "rails: 한 레일의 epic 들이 서로 다른 assignee 를 가리킨다 — $conflict (레일 담당자는 1명이다)"
        printf '%s' "$epics" | jq "$pairs"' | map(.[0]) | sort_by(.id)' \
          || die "rails: 출력을 만들지 못했다"
        ;;
      sprints)
        # id 는 iteration 의 **title**(사람이 정하는 YYYY-SNN)이다 — iteration 의 id 는 GitHub 이
        # 만드는 불투명 값(예 390d3281)이라 스프린트 ID 가 아니다(M0 실측, skills#140 note).
        #
        # status 의 출처: iteration 에는 상태 필드가 없고 startDate·duration 뿐이다(같은 실측).
        # **날짜 산술 대신 GitHub 자신이 가른 두 목록을 쓴다** — configuration.iterations 는 현재와
        # 앞으로 올 것, completedIterations 는 종료일이 지난 것이다. 날짜로 직접 파생하지 않는
        # 이유는 그 산술이 세 상태(과거·현재·미래)를 내는데 계약의 status 는 둘뿐이라서다: 아직
        # 시작하지 않은 스프린트를 closed 로 낼 수는 없고, GitHub 의 구분은 그것을 active 쪽에 둔다.
        # 이 파생은 sprints.json 이 금한 "닫힌 이슈 개수로 판정" 과도 다른 축이다 — 이슈를 보지 않는다.
        #
        # 읽기가 gh api graphql 인 이유: gh project field-list 는 필드의 id·name·type 만 내고
        # iteration 목록(configuration)을 내지 않는다. 필드 생성·iteration 추가도 같은 자리다 —
        # gh project field-create 에 ITERATION 이 없다(M0 실측).
        # ponytail: ITERATION 필드가 여럿이면 첫 번째만 읽는다. 지금 원장에 그런 판이 없다 —
        # 필드 이름을 계약으로 고정할 자리가 생기면 그때 이름으로 짚는다.
        # ponytail: 필드는 first:100(GraphQL 한 페이지 상한) 까지만 읽는다 — 그 이상이면
        # 페이지네이션이 필요하고, 아래 die 는 "첫 100개 안에 없다" 까지만 말한다.
        # ponytail: user(login:) 이라 조직 소유 project 에는 닿지 않는다 — 아래 die 가 사유로
        # 그 사실을 든다. 조직 소유 원장이 생기면 organization(login:) 으로 가른다.
        q='query($o:String!,$n:Int!){ user(login:$o){ projectV2(number:$n){ fields(first:100){ nodes{
             ... on ProjectV2IterationField { configuration {
               iterations{ title } completedIterations{ title } } } } } } } }'
        out="$(gh api graphql -f query="$q" -f o="$OWNER" -F n="$PROJECT" 2>&1)" \
          || die "sprints: Projects v2 $PROJECT (owner $OWNER) 의 필드를 읽지 못했다 — $out"
        printf '%s' "$out" | jq -e '.data.user.projectV2' >/dev/null 2>&1 \
          || die "sprints: 사용자 $OWNER 의 Projects v2 $PROJECT 를 읽지 못했다 — 번호가 틀렸거나, owner 가 사용자가 아니다(조직 소유 project 에는 이 질의가 닿지 않는다)"
        cfg="$(printf '%s' "$out" | jq -c '[.data.user.projectV2.fields.nodes[] | select(.configuration != null)] | first // empty')" \
          || die "sprints: 필드 응답을 읽지 못했다"
        [ -n "$cfg" ] || die "sprints: Projects v2 $PROJECT 의 필드(첫 100개) 안에 ITERATION 필드가 없다 — 이 백엔드에서 스프린트의 원본이 그 필드다. 빈 배열로 답하면 '스프린트가 없다' 와 구별되지 않아 board-check 가 모든 sprint: 라벨을 미등재로 읽는다. 이 필드는 ledger.sh init 이 만든다(skills#167) — 이 루트에서 'HARNESS_ROOT=<루트> ledger.sh init' 을 다시 돌려라. 멱등이라 이미 있는 project 는 그대로 두고 없는 필드만 만든다. 만든 직후의 필드에는 iteration 이 하나도 없고(실측), 스프린트는 'ledger.sh sprint-add <YYYY-SNN>' 이 iteration 으로 넣는다(title 이 스프린트 ID) — 그 절차는 harness:plan-sprint 1절이다"
        # 빈 배열이 나오는 판이 둘이고 **문면으로 갈린다.** 필드가 없으면 위에서 rc≠0 으로
        # 죽고(원장이 답할 수 없는 상태다), 필드는 있는데 iteration 이 0개면 여기서 rc 0 의 빈
        # 배열이다 — 갓 init 한 하네스가 그 모양이고 그것은 정상 상태다. 조용히 내면 둘이
        # 같은 문면이 되어 board-check 가 모든 sprint: 라벨을 미등재로 읽는다.
        out="$(printf '%s' "$cfg" | jq '[(.configuration.iterations[] | {id: .title, status: "active"}),
                                         (.configuration.completedIterations[] | {id: .title, status: "closed"})] | sort_by(.id)')" \
          || die "sprints: 출력을 만들지 못했다"
        [ "$(printf '%s' "$out" | jq -r 'length')" != "0" ] \
          || echo "ledger-github: sprints: ITERATION 필드는 있는데 iteration 이 하나도 없다 — '스프린트가 없다' 이고 '필드가 없다' 가 아니다. 스프린트는 'ledger.sh sprint-add <YYYY-SNN>' 이 그 필드에 iteration 으로 넣는다(title 이 스프린트 ID) — 그 절차는 harness:plan-sprint 1절이다" >&2
        printf '%s\n' "$out"
        ;;
    esac
    ;;

  *) die "'$cmd' 는 github 백엔드에 없다 (beads 전용이거나 모르는 명령) — ledger.sh --help" ;;
esac
