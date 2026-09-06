#!/usr/bin/env bash
# 원장 이전 도구 — beads 원장의 열린 항목을 github 백엔드로 옮긴다.
#   plan   읽기: bd 에서 열린 항목 전수를 JSON 배열로 낸다 (gh 를 부르지 않는다)
#   apply  쓰기: plan 대로 이슈·Project·코멘트·sub-issue·blocked_by 를 만든다 (map 으로 멱등)
#   verify 대조: map 의 id 마다 이슈를 읽어 plan 과 전수 비교한다
#
# **이슈 규약의 단일 소유는 scripts/ledger-github.sh 의 머리 주석이다** — id 형식 <repo>#<번호> ·
# 본문의 "## Acceptance" 절 · type:/status: 라벨 · repos.json 의 url 에서 파생하는 레포 slug.
# 여기서 다시 정의하지 않고 그대로 따른다. 이 도구가 더하는 것은 셋뿐이다:
#   · 본문 첫 줄 "beads: <원 id>" — 옮긴 뒤에도 원 id 로 되짚는다.
#   · repo 결정 규칙(2026-09-06 사용자 결정): 첫 repo: 라벨이 harness 이거나 repo: 라벨이 없으면
#     skills · 그 밖은 그 라벨 그대로 · repos.json 에 없는 이름이면 rc 1. harness 레포는 폐기
#     예정이라 이슈를 두지 않는다 — 어느 트리를 건드리는지는 남은 repo: 라벨이 든다.
#   · map 파일 "<beads id> <repo>#<번호>" — apply 의 멱등 근거이자 verify 의 대조 대상.
#
# 사용:
#   ledger-migrate.sh plan   --from <하네스루트> [--only <id,…>] [--label <라벨>] > plan.json
#   ledger-migrate.sh apply  --plan plan.json --map map.txt [--from <루트>] [--only <id,…>]
#   ledger-migrate.sh verify --plan plan.json --map map.txt [--from <루트>]
#
# apply·verify 는 bd 를 부르지 않는다 — 대상 좌표는 --from 루트의 ledger.json(github 의
# owner·project)과 repos.json 이 든다. 실증처럼 다른 Project 에 쓸 때는 그 owner·project 를 든
# ledger.json 과 repos.json 사본을 둔 루트를 --from 으로 준다(원장 자체는 건드리지 않는다).
# --from 을 생략하면 lib/harness-root.sh 가 찾는 루트를 쓴다.
#
# 라벨을 더 붙이려면 **plan --label** 에 준다 — apply 와 verify 가 같은 plan 을 보므로 라벨 집합
# 비교가 어긋나지 않는다(apply 에만 붙이면 verify 가 그 라벨을 모른다).
#
# verify 는 검색·목록으로 판정하지 않는다: 생성 직후 gh issue list 는 5 중 3 만 냈고 39초 뒤에야
# 5 였으며 gh project item-list 도 새 항목을 즉시 내지 않았다(harness-kw0l.1.1 실측). map 의
# id 별 조회로만 읽고, Project 소속도 이슈 쪽 projectItems 에서 읽는다.
set -uo pipefail

die() { echo "ledger-migrate: $*" >&2; exit 1; }

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
command -v jq >/dev/null 2>&1 || die "jq 가 없다"

# ── 공통 ──────────────────────────────────────────────────────────────
resolve_root() { # <--from 값 또는 빈 문자열> → 하네스 루트
  if [ -n "$1" ]; then printf '%s\n' "$1"; else bash "$PLUGIN_ROOT/lib/harness-root.sh" || exit 1; fi
}
repos_json() { [ -r "$1/repos.json" ] || die "$1/repos.json 이 없다 — 이슈가 살 레포 목록의 출처다"; printf '%s/repos.json' "$1"; }
slug_of() { # <repo 이름> <루트> → owner/name
  local url
  url="$(jq -r --arg n "$1" '.repos[] | select(.name == $n) | .url' "$2/repos.json" 2>/dev/null | head -1)"
  [ -n "$url" ] || die "repos.json 에 없는 레포 '$1'"
  url="${url%.git}"; url="${url#*github.com/}"; url="${url#*github.com:}"
  printf '%s\n' "$url"
}
need_gh() {
  command -v gh >/dev/null 2>&1 || die "gh 가 PATH 에 없다"
  gh auth status >/dev/null 2>&1 || die "gh 인증이 없다 — 사람이 gh auth login 을 먼저 한다"
}

# 이슈에 붙일 라벨 전부 = type:<type> + status:<status>(open·closed 는 라벨 없음) + plan 의 labels.
# apply(쓰기)와 verify(대조)가 같은 문자열을 만들어야 하므로 한 자리에 둔다.
LABELS_JQ='([ "type:" + .type ]
  + (if .status == "open" or .status == "closed" then [] else [ "status:" + .status ] end)
  + (.labels // [])) | unique'

# 부모·의존이 먼저 오도록 위상 정렬한다. 순환이면 남은 것을 원래 순서로 뒤에 붙인다(멈추지 않는다).
# ponytail: 준비된 항목을 매 바퀴 다시 훑는 O(n²) — 원장 규모(백 단위)에서 잰 값이 아니라 형태로
# 고른 것이다. 수천 건이 되면 Kahn 큐로 바꾼다.
TSORT_JQ='. as $all | [ $all[].id ] as $ids
  | { done: [], rest: $all }
  | until(.rest | length == 0;
      (.done | map(.id)) as $d
      | (.rest | map(select(
          ([ (.parent // empty) ] + (.deps // []))
          | all(. as $x | ($ids | index($x)) == null or ($d | index($x)) != null)))) as $ready
      | if ($ready | length) == 0 then { done: (.done + .rest), rest: [] }
        else { done: (.done + $ready),
               rest: (.rest | map(select(.id as $i | ($ready | map(.id) | index($i)) == null))) } end)
  | .done'

map_lookup() { # <beads id> <map 파일> → <repo>#<번호> (없으면 빈 문자열)
  [ -r "$2" ] || return 0
  awk -v k="$1" '$1 == k { print $2; exit }' "$2"
}

# ── plan ──────────────────────────────────────────────────────────────
cmd_plan() {
  local from="" only="" extra="[]" root plan bad ids detail
  while [ $# -gt 0 ]; do
    case "$1" in
      --from) from="$2"; shift 2 ;;
      --only) only="$2"; shift 2 ;;
      --label) extra="$(printf '%s' "$extra" | jq --arg l "$2" '. + [$l]')"; shift 2 ;;
      *) die "plan: 모르는 인자 '$1'" ;;
    esac
  done
  root="$(resolve_root "$from")" || exit 1
  repos_json "$root" >/dev/null
  command -v bd >/dev/null 2>&1 || die "bd 가 PATH 에 없다 — plan 은 beads 원장을 읽는다"

  local all
  all="$(bd -C "$root" list --all -n 0 --json)" || die "bd list 를 읽지 못했다 ($root)"
  ids="$(printf '%s' "$all" | jq -r --arg only "$only" '
    ($only | if . == "" then null else split(",") end) as $sel
    | [ .[] | select(.status != "closed") | .id ]
    | if $sel == null then . else map(select(. as $i | $sel | index($i))) end
    | .[]')" || die "열린 항목을 고르지 못했다"
  [ -n "$ids" ] || die "옮길 열린 항목이 0건이다 (--only 가 아무것도 고르지 못했는가)"

  # shellcheck disable=SC2086  # id 목록은 공백으로 갈라 넘긴다 (bd show 는 여러 id 를 받는다)
  detail="$(bd -C "$root" show --json $ids)" || die "bd show 를 읽지 못했다"

  plan="$(printf '%s' "$detail" | jq --argjson extra "$extra" '
    map(
      (.labels // []) as $ls
      | ([ $ls[] | select(startswith("repo:")) | ltrimstr("repo:") ] | first) as $r0
      | (if ($r0 == null or $r0 == "harness") then "skills" else $r0 end) as $repo
      | ((.description // "") | rtrimstr("\n")) as $desc
      | ((.acceptance_criteria // "") | rtrimstr("\n")) as $acc
      | ((.notes // "") | split("\n") | map(select(test("\\S")))) as $notes
      | { id: .id,
          repo: $repo,
          type: .issue_type,
          status: .status,
          title: .title,
          body: ([ "beads: " + .id ]
                 + (if $desc == "" then [] else [ $desc ] end)
                 + (if $acc == "" then [] else [ "## Acceptance\n\n" + $acc ] end) | join("\n\n")),
          labels: (($ls | map(select((startswith("type:") or startswith("status:")) | not))) + $extra | unique),
          parent: .parent,
          deps: [ .dependencies[]? | select(.dependency_type == "blocks") | .id ],
          notes: ($notes + (if .status == "in_progress" and (.assignee // "") != ""
                            then [ "ACTOR: " + .assignee ] else [] end)) })')" \
    || die "plan 을 만들지 못했다"

  # repos.json 에 없는 레포는 여기서 죽는다 — 아무것도 내지 않는다(부분 plan 을 남기지 않는다).
  bad="$(printf '%s' "$plan" | jq -r --slurpfile r "$root/repos.json" '
    ([ $r[0].repos[].name ]) as $names
    | .[] | select(.repo as $x | ($names | index($x)) == null) | "\(.id) → repo:\(.repo)"')"
  [ -z "$bad" ] || { printf '%s\n' "$bad" >&2; die "repos.json 에 없는 레포 라벨이 있다 (위 $(printf '%s\n' "$bad" | grep -c .)건) — 라벨을 고치거나 레포를 등재하라"; }

  printf '%s\n' "$plan"
}

# ── apply ─────────────────────────────────────────────────────────────
cmd_apply() {
  local from="" planf="" mapf="" only="" root owner project items n=0 skipped=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --from) from="$2"; shift 2 ;;
      --plan) planf="$2"; shift 2 ;;
      --map) mapf="$2"; shift 2 ;;
      --only) only="$2"; shift 2 ;;
      *) die "apply: 모르는 인자 '$1'" ;;
    esac
  done
  [ -n "$planf" ] || die "apply: --plan <파일> 이 필요하다"
  [ -r "$planf" ] || die "apply: plan 파일을 읽지 못했다: $planf"
  [ -n "$mapf" ] || die "apply: --map <파일> 이 필요하다 (멱등의 근거다)"
  root="$(resolve_root "$from")" || exit 1
  repos_json "$root" >/dev/null
  [ -r "$root/ledger.json" ] || die "$root/ledger.json 이 없다 — owner·project 의 출처다"
  owner="$(jq -r '.owner // empty' "$root/ledger.json")"
  project="$(jq -r '.project // empty' "$root/ledger.json")"
  [ -n "$owner" ] || die "$root/ledger.json 에 owner 가 없다"
  [ -n "$project" ] || die "$root/ledger.json 에 project 가 없다 — 이슈를 Projects v2 에 넣지 못한다"
  need_gh
  touch "$mapf" || die "map 파일을 쓰지 못한다: $mapf"

  items="$(jq -c --arg only "$only" "
    (\$only | if . == \"\" then null else split(\",\") end) as \$sel
    | (if \$sel == null then . else map(select(.id as \$i | \$sel | index(\$i))) end)
    | $TSORT_JQ | .[]" "$planf")" || die "plan 을 정렬하지 못했다"

  local tmp; tmp="$(mktemp -d)" || die "임시 디렉토리를 만들지 못했다"
  trap 'rm -rf "$tmp"' EXIT

  while IFS= read -r item; do
    [ -n "$item" ] || continue
    local id repo slug title labels url num already
    id="$(printf '%s' "$item" | jq -r .id)"
    already="$(map_lookup "$id" "$mapf")"
    if [ -n "$already" ]; then skipped=$((skipped + 1)); echo "· 건너뜀 $id → $already (map 에 있다)"; continue; fi
    repo="$(printf '%s' "$item" | jq -r .repo)"
    title="$(printf '%s' "$item" | jq -r .title)"
    labels="$(printf '%s' "$item" | jq -r "$LABELS_JQ | join(\",\")")"
    slug="$(slug_of "$repo" "$root")" || exit 1
    printf '%s' "$item" | jq -r .body > "$tmp/body"

    for l in $(printf '%s' "$labels" | tr ',' ' '); do
      gh label create "$l" -R "$slug" --force >/dev/null 2>&1 || die "라벨 '$l' 를 $slug 에 만들지 못했다 ($id)"
    done
    url="$(gh issue create -R "$slug" -t "$title" -F "$tmp/body" -l "$labels" 2>/dev/null)" \
      || die "gh issue create 실패: $id ($slug)"
    [ -n "$url" ] || die "gh issue create 가 URL 을 내지 않았다: $id ($slug)"
    num="${url##*/}"
    # 만든 즉시 기록한다 — 여기서 죽어도 다시 돌릴 때 같은 이슈를 두 번 만들지 않는다.
    printf '%s %s#%s\n' "$id" "$repo" "$num" >> "$mapf" || die "map 에 쓰지 못했다: $mapf"
    n=$((n + 1))

    gh project item-add "$project" --owner "$owner" --url "$url" >/dev/null 2>&1 \
      || die "Project $project 에 넣지 못했다: $id ($repo#$num)"

    while IFS= read -r note; do
      [ -n "$note" ] || continue
      gh issue comment "$num" -R "$slug" -b "$note" >/dev/null 2>&1 || die "코멘트를 달지 못했다: $id ($repo#$num)"
    done < <(printf '%s' "$item" | jq -r '.notes[]?')

    local parent pmapped pslug pnum cnode pnode
    parent="$(printf '%s' "$item" | jq -r '.parent // empty')"
    if [ -n "$parent" ]; then
      pmapped="$(map_lookup "$parent" "$mapf")"
      if [ -n "$pmapped" ]; then
        pslug="$(slug_of "${pmapped%%#*}" "$root")" || exit 1
        pnum="${pmapped##*#}"
        pnode="$(gh api "repos/$pslug/issues/$pnum" --jq .node_id 2>/dev/null)" || die "부모 node_id 조회 실패: $parent"
        cnode="$(gh api "repos/$slug/issues/$num" --jq .node_id 2>/dev/null)" || die "node_id 조회 실패: $id"
        gh api graphql -f query='mutation($p:ID!,$c:ID!){ addSubIssue(input:{issueId:$p, subIssueId:$c}) { issue { number } } }' \
          -f p="$pnode" -f c="$cnode" >/dev/null 2>&1 || die "addSubIssue 실패: $parent ← $id"
      else
        echo "  ⚠ $id 의 부모 $parent 가 map 에 없다 — sub-issue 를 걸지 않았다" >&2
      fi
    fi

    local dep dmapped dslug dnum dbid
    while IFS= read -r dep; do
      [ -n "$dep" ] || continue
      dmapped="$(map_lookup "$dep" "$mapf")"
      if [ -z "$dmapped" ]; then echo "  ⚠ $id 의 의존 대상 $dep 이 map 에 없다 — blocked_by 를 걸지 않았다" >&2; continue; fi
      dslug="$(slug_of "${dmapped%%#*}" "$root")" || exit 1
      dnum="${dmapped##*#}"
      dbid="$(gh api "repos/$dslug/issues/$dnum" --jq .id 2>/dev/null)" || die "의존 대상 id 조회 실패: $dep"
      gh api -X POST "repos/$slug/issues/$num/dependencies/blocked_by" -F issue_id="$dbid" >/dev/null 2>&1 \
        || die "blocked_by 를 걸지 못했다: $id ← $dep"
    done < <(printf '%s' "$item" | jq -r '.deps[]?')

    echo "✓ $id → $repo#$num"
  done <<EOF
$items
EOF

  echo "apply: 새로 만든 항목 ${n}건 · 건너뛴 항목 ${skipped}건 (map $mapf)"
}

# ── verify ────────────────────────────────────────────────────────────
cmd_verify() {
  local from="" planf="" mapf="" root project total=0 bad=0 missing
  while [ $# -gt 0 ]; do
    case "$1" in
      --from) from="$2"; shift 2 ;;
      --plan) planf="$2"; shift 2 ;;
      --map) mapf="$2"; shift 2 ;;
      *) die "verify: 모르는 인자 '$1'" ;;
    esac
  done
  [ -n "$planf" ] || die "verify: --plan <파일> 이 필요하다"
  [ -r "$planf" ] || die "verify: plan 파일을 읽지 못했다: $planf"
  [ -n "$mapf" ] || die "verify: --map <파일> 이 필요하다"
  [ -r "$mapf" ] || die "verify: map 파일을 읽지 못했다: $mapf"
  root="$(resolve_root "$from")" || exit 1
  repos_json "$root" >/dev/null
  project="$(jq -r '.project // empty' "$root/ledger.json" 2>/dev/null)"
  [ -n "$project" ] || die "$root/ledger.json 에 project 가 없다 — Project 소속을 판정할 수 없다"
  need_gh

  total="$(jq 'length' "$planf")"
  # 부분 이전을 통과로 읽지 않는다 — map 에 없는 plan 항목은 그 자체로 실패다.
  missing="$(jq -r --rawfile m "$mapf" '
    ($m | split("\n") | map(select(. != "") | split(" ")[0])) as $done
    | .[] | select(.id as $i | ($done | index($i)) == null) | .id' "$planf")"
  if [ -n "$missing" ]; then
    printf '%s\n' "$missing" | sed 's/^/✗ /;s/$/ 옮기지 않았다 (map 에 없다)/'
    echo "옮기지 않은 항목 $(printf '%s\n' "$missing" | grep -c .)건"
    bad=1
  fi

  local item id mapped repo num slug o r node exp act
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    id="$(printf '%s' "$item" | jq -r .id)"
    mapped="$(map_lookup "$id" "$mapf")"
    [ -n "$mapped" ] || continue   # 위에서 이미 실패로 셌다
    repo="${mapped%%#*}"; num="${mapped##*#}"
    slug="$(slug_of "$repo" "$root")" || exit 1
    o="${slug%%/*}"; r="${slug##*/}"

    node="$(gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){ repository(owner:$o,name:$r){ issue(number:$n){ title body labels(first:100){nodes{name}} comments{totalCount} parent{number repository{name}} } } }' \
      -f o="$o" -f r="$r" -F n="$num" 2>/dev/null | jq -e '.data.repository.issue' 2>/dev/null)" || {
      echo "✗ $id ($mapped) issue: 읽지 못했다"; bad=1; continue; }

    say() { echo "✗ $id ($mapped) $1: 기대 [$2] 실제 [$3]"; bad=1; }

    exp="$(printf '%s' "$item" | jq -r .title)"; act="$(printf '%s' "$node" | jq -r .title)"
    [ "$exp" = "$act" ] || say title "$exp" "$act"

    exp="$(printf '%s' "$item" | jq -r "$LABELS_JQ | join(\",\")")"
    act="$(printf '%s' "$node" | jq -r '[.labels.nodes[].name] | unique | join(",")')"
    [ "$exp" = "$act" ] || say labels "$exp" "$act"

    exp="beads: $id"; act="$(printf '%s' "$node" | jq -r '.body | split("\n")[0]')"
    [ "$exp" = "$act" ] || say "body 첫 줄" "$exp" "$act"

    exp="$(printf '%s' "$item" | jq -r '.body | split("\n## Acceptance\n") | if length > 1 then (.[1:] | join("\n## Acceptance\n")) else "" end | ltrimstr("\n") | rtrimstr("\n")')"
    act="$(printf '%s' "$node" | jq -r '.body | split("\n## Acceptance\n") | if length > 1 then (.[1:] | join("\n## Acceptance\n")) else "" end | ltrimstr("\n") | rtrimstr("\n")')"
    [ "$exp" = "$act" ] || say "acceptance 절" "${exp:0:40}…" "${act:0:40}…"

    # 기대 부모·의존은 map 에 옮겨진 것만이다 — 부분 plan(--only)에서 밖을 가리키는 간선은 걸리지 않는다.
    exp="$(map_lookup "$(printf '%s' "$item" | jq -r '.parent // empty')" "$mapf")"
    act="$(printf '%s' "$node" | jq -r 'if .parent then (.parent.repository.name + "#" + (.parent.number|tostring)) else "" end')"
    [ "$exp" = "$act" ] || say parent "${exp:--}" "${act:--}"

    exp=""
    while IFS= read -r dep; do
      [ -n "$dep" ] || continue
      dep="$(map_lookup "$dep" "$mapf")"
      [ -n "$dep" ] && exp="$exp$dep
"
    done < <(printf '%s' "$item" | jq -r '.deps[]?')
    exp="$(printf '%s' "$exp" | grep -v '^$' | sort | tr '\n' ',')"
    act="$(gh api "repos/$slug/issues/$num/dependencies/blocked_by" 2>/dev/null \
      | jq -r '.[] | (.repository_url | split("/") | last) + "#" + (.number|tostring)' | sort | tr '\n' ',')"
    [ "$exp" = "$act" ] || say blocked_by "${exp:--}" "${act:--}"

    exp="$(printf '%s' "$item" | jq '.notes | length')"
    act="$(printf '%s' "$node" | jq -r '.comments.totalCount')"
    [ "$exp" = "$act" ] || say "코멘트 수" "$exp" "$act"

    # Project 소속은 이슈 쪽에서 읽는다 — item-list 는 생성 직후 새 항목을 내지 않는다(1.1 실측).
    act="$(gh issue view "$num" -R "$slug" --json projectItems 2>/dev/null \
      | jq -r --arg p "$project" '[.projectItems[]? | (.number // .project.number // empty) | tostring] | index($p) // ""')"
    [ -n "$act" ] || say "Project 소속" "project $project" "없음"
  done < <(jq -c '.[]' "$planf")

  if [ "$bad" -ne 0 ]; then exit 1; fi
  echo "verify: $total/$total 일치"
}

case "${1:-}" in
  plan) shift; cmd_plan "$@" ;;
  apply) shift; cmd_apply "$@" ;;
  verify) shift; cmd_verify "$@" ;;
  *) die "plan | apply | verify 중 하나가 필요하다 (받은 것: '${1:-}') — 사용법은 이 파일의 머리 주석" ;;
esac
