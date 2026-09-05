#!/bin/bash
# 원장(SSOT — scripts/ledger.sh 가 읽는 어느 백엔드든) → 사람이 읽는 스토리 문서 트리 렌더러.
# 사용: scripts/board.sh <스프린트ID>   (형식: YYYY-SNN)  → docs/sprints/<ID>/
#       scripts/board.sh backlog                          → docs/backlog/
#       scripts/board.sh adr                              → docs/adr/
#       scripts/board.sh all                              → sprints.json 의 스프린트 전부 + backlog + adr
# 산출물은 git 밖이다(.gitignore) — 원장이 SSOT 이고 이 트리는 사람이 로컬에서 읽는 투영이다.
# post-merge·post-checkout 훅이 `all` 을 불러 pull·checkout 뒤 다시 그린다.
# 출력(스프린트·백로그):
#   index.md                     — 대상의 스토리 표
#   <슬러그>/index.md            — 스토리 (디렉토리명 = slug: 라벨. 대상 안에서 유일해야 한다)
#   <슬러그>/M<N>.md             — 마일스톤 + 태스크 (스토리 내 bead id 순으로 M1 부터)
# 출력(adr):
#   index.md                     — 결정 표
#   <슬러그>.md                  — 결정 1건 (파일명 = slug: 라벨. 대상 안에서 유일해야 한다)
# 메타데이터는 frontmatter, 문서는 생성물 — 수정은 원장에서 하고 재실행한다.
# 필수 메타데이터가 없거나 형식이 틀리면(슬러그 문자·등록부 밖 레일) 폴백 없이 실패한다.
#
# **입력은 epic 전수에서 파생한다** (ADR harness-bjj D2).
# sprint: 라벨은 **출력 경로만** 가른다 — 있으면 docs/sprints/<ID>/, 없으면 docs/backlog/.
# 렌더 여부는 가르지 않는다. 종전에는 sprint 라벨 질의가 곧 입력이라 라벨 없는 스토리는
# 어떤 투영에도 나타나지 않았고, 그 문서는 존재 자체가 게이트 밖이었다.
# 백로그는 status != closed 로 좁힌다 — 스프린트 쪽 EXEMPT_SPRINT 같은 아카이브 출구가
# 없어 그대로 두면 끝난 스토리 디렉토리를 영구히 들고 간다. 대가: 백로그 스토리가 닫히면
# 그 문서가 사라진다(스프린트 스토리는 닫혀도 남는다).
#
# **adr 대상의 입력은 issue_type == decision 전수다 — status 로 좁히지 않는다.**
# 결정은 닫혀도 사라지지 않는다: 대체된 결정도 왜 대체됐는지와 함께 남아야 계보가 읽힌다.
# 대체 관계는 dependencies 의 supersedes 로 표시한다 — 그 간선은 **대체된(옛) bead** 에
# 있고 depends_on_id 가 대체한(새) bead 다 (실측 2026-08-29: harness-jrw 05:36:43 →
# harness-fva 05:37:00, `bd supersede <옛> --with <새>` 가 만든 간선).
set -euo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

TARGET="${1:?사용법: scripts/board.sh <스프린트ID>|backlog|adr|all (스프린트 ID 형식: YYYY-SNN)}"
if [[ "$TARGET" == "all" ]]; then
  ROOT="$(bash "$PLUGIN_ROOT/lib/harness-root.sh")" || exit 1
  [[ -f "$ROOT/sprints.json" ]] || { echo "스프린트 등록부가 없다: $ROOT/sprints.json" >&2; exit 1; }
  for id in $(jq -r '.sprints | keys[]' "$ROOT/sprints.json"); do bash "$0" "$id" || exit 1; done
  bash "$0" backlog || exit 1
  exec bash "$0" adr
fi
if [[ "$TARGET" == "backlog" ]]; then
  MODE="backlog"; NAME="backlog"; TITLE="백로그"; FRONTMATTER="backlog: true"
elif [[ "$TARGET" == "adr" ]]; then
  MODE="adr"; NAME="adr"; TITLE="결정 기록 (ADR)"; FRONTMATTER="adr: true"
elif [[ "$TARGET" =~ ^[0-9]{4}-S[0-9]{2}$ ]]; then
  MODE="sprint"; NAME="$TARGET"; TITLE="스프린트 $TARGET"; FRONTMATTER="sprint: $TARGET"
else
  echo "대상 형식 위반: '$TARGET' (스프린트 ID 는 YYYY-SNN, 백로그는 backlog, 결정 기록은 adr)" >&2
  exit 1
fi

# 하네스 루트는 lib/harness-root.sh 가 낸다 — 스크립트 위치로 파생하지 않는다 (플러그인은 하네스 루트 밖에 산다).
ROOT="$(bash "$PLUGIN_ROOT/lib/harness-root.sh")" || exit 1
RAILS="$ROOT/rails.json"
[[ -f "$RAILS" ]] || { echo "레일 등록부가 없다: $RAILS" >&2; exit 1; }
if [[ "$MODE" == "sprint" ]]; then
  OUT="$ROOT/docs/sprints/$NAME"
else
  OUT="$ROOT/docs/$NAME"
fi

# 입력 파생: epic 전수를 받아 이 대상에 속하는 epic 을 고르고 그 **자손 전부**를 붙인다.
# 자손을 라벨이 아니라 parent 사슬로 모으는 이유: 백로그 스토리의 하위에는 sprint 라벨이
# 없어 라벨 질의로는 마일스톤 0개가 되고, 그 상태도 rc=0 으로 성공한다 (실측 2026-08-19).
# 원장은 어댑터로 읽는다 — 백엔드가 무엇이든 같은 JSON 키다(scripts/ledger.sh). 루트는 위에서 찾은 값을 그대로 물린다.
ALL_JSON=$(HARNESS_ROOT="$ROOT" bash "$PLUGIN_ROOT/scripts/ledger.sh" list --all --json -n 0)
# JSON 은 항상 printf 로 파이프한다 — echo 는 backslash 확장 셸(sh, xpg_echo)에서
# 필드 안의 \n·\uXXXX 를 raw 제어문자로 바꿔 jq 가 rc=5 로 죽는다 (실측 2026-08-19).
if [[ "$MODE" == "adr" ]]; then
  # 결정은 계층이 없다 — 자손을 붙이지 않고 전수를 그대로 쓴다.
  JSON=$(printf '%s' "$ALL_JSON" | jq '[.[] | select(.issue_type == "decision")]')
  SEL_TYPE="decision"
else
  SEL_TYPE="epic"
JSON=$(printf '%s' "$ALL_JSON" | jq --arg mode "$MODE" --arg name "$NAME" '
  def selected:
    .issue_type == "epic" and
    (if $mode == "backlog"
     then .status != "closed" and (((.labels // []) | any(startswith("sprint:"))) | not)
     else ((.labels // []) | any(. == "sprint:" + $name)) end);
  (map({key: .id, value: .}) | from_entries) as $byid
  | ([.[] | select(selected) | .id] | map({key: ., value: true}) | from_entries) as $sel
  | [ .[] | select(
        [limit(8; recurse(if .parent then $byid[.parent] else empty end))]
        | any(.[]; $sel[.id] != null)) ]')
fi
# limit(8) 은 조상 사슬을 거슬러 오르는 상한이다. 계층이 스토리–마일스톤–태스크 **3단**이라
# 8 이면 다섯 단이 남고, 상한을 두는 목적 자체는 **순환 방지**다 — parent 가 서로를 가리키면
# recurse 가 끝나지 않는다. 넘치는 깊이의 이슈는 조상을 못 찾아 렌더에서 **조용히** 빠진다.
# board-check 의 상속 검사도 같은 상한을 쓴다 — 3단을 넘기려면 둘을 함께 올린다.
#
# **0건은 스프린트에서만 실패다.** 백로그·adr 은 비는 것이 정상 상태다(스토리가 전부
# 스프린트에 편입됐거나 닫혔다 · 신규 하네스는 epic 도 decision 도 없다) — 빈 표 index.md 를 낸다.
if [[ "$MODE" == "sprint" ]] \
   && [[ "$(printf '%s' "$JSON" | jq '[.[] | select(.issue_type == "epic")] | length')" -eq 0 ]]; then
  echo "sprint:$NAME 라벨이 붙은 스토리(epic)가 없다" >&2
  exit 1
fi

# 타임스탬프를 넣지 않는다 — 같은 bd 상태면 바이트 동일(결정론). 재렌더가 diff 를 만들지 않는다.
HEADER="<!-- bd 생성 문서. 직접 수정 금지 — bd 로 수정 후 scripts/board.sh $TARGET 재실행 -->"

glyph() { # 상태 → 원장(beads)과 같은 기호
  case "$1" in
    open) echo "○" ;; in_progress) echo "◐" ;; blocked) echo "●" ;;
    closed) echo "✓" ;; deferred) echo "❄" ;; pinned) echo "📌" ;;
    # 폴백은 남긴다 — 지우면 bd 에 상태가 하나 늘 때 렌더가 죽는다. 대신 그 상태의
    # 행은 상태 열에 값이 두 번 나오므로(기호 자리에 값이 오고 값이 또 온다) 눈에 띈다.
    *) echo "$1" ;;
  esac
}

# ── 조회 캐시 ─────────────────────────────────────────────────────────
# 종전에는 field·label_of·children_of 가 **호출마다 전체 JSON 을 jq 로 재파싱**했다.
# 필드 접근 하나에 프로세스 하나라 O(항목 × 필드) 로 늘고, 이 스프린트(스토리 6개)에서
# 렌더 1회에 jq 가 177번 떴다 [실측 2026-08-22]. 아래 세 캐시를 **한 번의 jq 패스씩**
# 으로 만들고 조회는 파일에서 한다.
#
# 값은 base64 로 감싼다. description·notes 는 개행을 담은 자유 텍스트라 한 줄 형식이
# 그대로는 깨진다 — TSV 를 쓰면서 값에 탭·개행이 들어오는 것을 막는 유일한 방법이
# 인코딩이다. 문자열이 아닌 값(배열·수)은 tojson 으로 눕힌다.
#
# 정확성 근거: 이 스크립트의 출력은 **결정론**(같은 bd 상태 = 같은 바이트)이다.
# 정리는 아래 OUT·LOCK 이 정해진 뒤의 trap 이 함께 맡는다 — 여기서 걸면 그 trap 이
# 덮어써 캐시가 남는다.
CACHE_DIR="$(mktemp -d)"

# ① 필드: 이슈 한 줄 — <id>:<status>:<title>:<description>:<notes>:<acceptance>:<close_reason>
# 이슈당 한 줄이라 조회도 이슈당 한 번이다 — grep -m1 이 첫 일치에서 멈추므로 파일 전체를
# 훑지 않는다. 필드마다 한 줄이면 조회 한 번이 파일 전체 스캔이 되어 그것이 렌더 시간의
# 대부분을 차지한다 (실측 근거는 harness-5qyb.1.1).
# 컬럼은 렌더가 실제로 읽는 6개로 고정한다 — 새 필드가 필요하면 여기에 컬럼을 늘린다.
# 구분자가 콜론인 이유 둘: base64 알파벳에 없고, **탭은 IFS 공백**이라 빈 값이 연속되면
# read 가 탭 런을 하나로 합쳐 뒤 필드가 자리를 당겨 온다(빈 close_reason 이 흔하다).
printf '%s' "$JSON" | jq -r '
  def b: if . == null then "" else (if type == "string" then . else tojson end | @base64) end;
  .[] | [.id, (.status|b), (.title|b), (.description|b), (.notes|b), (.acceptance_criteria|b), (.close_reason|b)]
  | join(":")
' > "$CACHE_DIR/fields"

# ② 자식: <부모id>\t<자식id>. id 는 dotted (harness-0r2.1.10) — 사전순 정렬은 .10 을
#    .2 앞에 놓아 자식 10개부터 M 번호가 어긋난다. 세그먼트를 숫자로 바꿔 자연 정렬한다.
printf '%s' "$JSON" | jq -r '
  [.[] | select(.parent != null)]
  | sort_by(.id | split(".") | map(tonumber? // .))
  | .[] | [.parent, .id] | @tsv
' > "$CACHE_DIR/children"

# ③ 라벨: <id>\t<라벨>. 접두사 필터는 조회 쪽에서 한다 (접두사가 호출마다 다르다).
printf '%s' "$JSON" | jq -r '
  .[] | .id as $i | (.labels // [])[] | [$i, .] | @tsv
' > "$CACHE_DIR/labels"

# ④ 대체 관계: <대체된id>\t<대체한id>. 간선은 옛 bead 에 있고 depends_on_id 가 새 bead 다.
printf '%s' "$JSON" | jq -r '
  .[] | .id as $i | (.dependencies // [])[] | select(.type == "supersedes")
  | [$i, .depends_on_id] | @tsv
' > "$CACHE_DIR/supersedes"

# base64 디코더는 GNU 가 -d, BSD/macOS 가 -D 다. 한쪽만 쓰면 다른 플랫폼에서 조용히
# 빈 값이 나와 문서가 통째로 비는데, 그 상태도 rc=0 이다. 첫 호출에 한 번 정한다.
if printf '' | base64 -d >/dev/null 2>&1; then B64D="-d"; else B64D="-D"; fi

# 이슈 하나의 여섯 필드를 한 줄로 받는다 — 호출자는 `IFS=: read -r _ s t d n a r`.
# 인코딩된 채로 묶어 내보내고 쓰는 자리에서 각각 d64 로 푼다. 먼저 풀어 묶으면 값 안의
# 개행·탭이 구분자와 섞인다.
fields() {
  grep -m1 "^${1//./\\.}:" "$CACHE_DIR/fields" || printf '::::::\n'
}
d64() {
  [[ -n "$1" ]] || return 0
  printf '%s' "$1" | base64 "$B64D" 2>/dev/null
}
label_of() {
  awk -F'\t' -v id="$1" -v p="$2" '
    $1==id && index($2, p)==1 { v=substr($2, length(p)+1); out = out ? out ", " v : v }
    END { if (out) print out }' "$CACHE_DIR/labels"
}
children_of() {
  awk -F'\t' -v pid="$1" '$1==pid {print $2}' "$CACHE_DIR/children"
}
superseded_by() {
  awk -F'\t' -v id="$1" '
    $1==id { out = out ? out ", " $2 : $2 }
    END { if (out) print out }' "$CACHE_DIR/supersedes"
}
# 마크다운 표 셀 이스케이프 — 제목·설명은 에이전트가 쓰는 자유 텍스트라 | 가 들어오면
# 그 행 이후 표 전체가 깨진다 (실측 2026-08-20).
esc_cell() { printf '%s' "$1" | sed 's/|/\\|/g'; }
# 자유 텍스트는 echo 로 내보내지 않는다 — 값이 -e/-n/-E 면 echo 가 옵션으로 삼킨다.
emit() { printf '%s\n' "$1"; }

# 최종 디렉토리에 직접 쓰지 않는다 — 병렬 세션이 공식 지원이라, rm -rf 후 재작성
# 중의 반쯤 빈 트리를 다른 세션이 읽을 수 있다. 임시 디렉토리는 숨김 이름(.render-*)이고,
# 시작 시 이전 실행의 잔존물(비정상 종료)을 정리한다. 같은 스프린트 동시 렌더는 잠금으로
# 직렬화한다 — rm 과 mv 의 인터리브가 중첩 쓰레기를 만들기 때문.
PARENT="$(dirname "$OUT")"
mkdir -p "$PARENT"
LOCK="$PARENT/.render-lock-$NAME"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "오류: $NAME 렌더가 이미 진행 중이다 ($LOCK 존재). 비정상 종료 잔존물이면 그 디렉토리를 지우고 재실행하라" >&2
  exit 1
fi
rm -rf "$PARENT/.render-$NAME."*   # 이전 비정상 종료의 잔존물
FINAL_OUT="$OUT"
OUT="$(mktemp -d "$PARENT/.render-$NAME.XXXXXX")"
trap 'rm -rf "$OUT" "$LOCK" "$CACHE_DIR"' EXIT

# ── 대상 index.md ────────────────────────────────────────────────
{
  echo "---"
  emit "$FRONTMATTER"
  echo "---"
  echo "$HEADER"
  echo
  echo "# $TITLE"
  echo
  if [[ "$MODE" == "adr" ]]; then
    echo "| 결정 | bead | 상태 | 대체한 결정 | 제목 |"
    echo "|---|---|---|---|---|"
  else
    echo "| 스토리 | bead | 레일 | 담당 | 상태 | 레포 | 제목 |"
    echo "|---|---|---|---|---|---|---|"
  fi
} > "$OUT/index.md"

# 슬러그가 곧 디렉토리명이다. 레일 ID 를 경로에 넣지 않는다 — 레일 이름이 바뀌면
# 과거 문서의 경로와 외부 링크까지 전부 바뀐다. 레일 정보는 frontmatter 와 index 표가
# 든다. 접두사가 사라졌으므로 **대상 안** 슬러그 유일성을 단언한다 — 스프린트 하나,
# 또는 백로그 전체가 그 단위다.
DUP=$(printf '%s' "$JSON" | jq -r --arg st "$SEL_TYPE" '
  [.[] | select(.issue_type==$st)
       | ((.labels // []) | map(select(startswith("slug:")) | sub("slug:";"")) | first // "")]
  | map(select(. != "")) | group_by(.) | map(select(length > 1) | .[0]) | .[]')
if [[ -n "$DUP" ]]; then
  echo "슬러그 충돌: $TARGET 안에 slug 가 중복된 $SEL_TYPE bead 가 있다 — $DUP" >&2
  echo "(slug 는 디렉토리명이라 대상 안에서 유일해야 한다. 라벨로 한쪽을 바꿔라)" >&2
  exit 1
fi

if [[ "$MODE" == "adr" ]]; then
for did in $(printf '%s' "$JSON" | jq -r 'sort_by(.id) | .[].id'); do
  slug=$(label_of "$did" "slug:")
  IFS=: read -r _ e_status e_title e_desc e_notes _ < <(fields "$did")
  status=$(d64 "$e_status")
  title=$(d64 "$e_title")

  # 폴백 없이 실패한다. 슬러그 없는 결정을 임의의 이름으로 그리면 원장을 고칠 이유가
  # 사라지고, 그 결정은 다음 렌더에서 이름이 바뀐다.
  [[ -n "$slug" ]] || { echo "결정 $did 에 slug: 라벨이 없다 (파일명이 된다 — ledger.sh label add $did slug:<이름>)" >&2; exit 1; }
  if [[ ! "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "슬러그 형식 위반: '$slug' (결정 $did) — 소문자·숫자·하이픈만, 첫 글자는 영숫자" >&2
    exit 1
  fi

  # 대체된 결정도 표에 남는다 — 행에 대체한 bead ID 를 실어 계보를 읽게 한다.
  sup=$(superseded_by "$did")
  emit "| [$slug](${slug}.md) | $did | $(glyph "$status") $status | ${sup:--} | $(esc_cell "$title") |" >> "$OUT/index.md"

  {
    echo "---"
    echo "decision: $did"
    emit "$FRONTMATTER"
    echo "status: $status"
    echo "slug: $slug"
    [[ -n "$sup" ]] && emit "superseded_by: $sup"
    echo "---"
    echo "$HEADER"
    echo
    emit "# $(glyph "$status") $title"
    [[ -n "$sup" ]] && { echo; emit "> 대체됨 — 이 결정을 대신하는 bead: $sup"; }
    desc=$(d64 "$e_desc")
    [[ -n "$desc" ]] && { echo; emit "$desc"; }
    notes=$(d64 "$e_notes")
    [[ -n "$notes" ]] && { echo; echo "<details><summary>기록 (bd notes)</summary>"; echo; emit "$notes"; echo; echo "</details>"; }
  } > "$OUT/${slug}.md"
done
else
for sid in $(printf '%s' "$JSON" | jq -r '[.[] | select(.issue_type=="epic")] | sort_by(.id) | .[].id'); do
  rail=$(label_of "$sid" "rail:")
  slug=$(label_of "$sid" "slug:")
  repos=$(label_of "$sid" "repo:")
  IFS=: read -r _ e_status e_title e_desc e_notes _ < <(fields "$sid")
  status=$(d64 "$e_status")
  title=$(d64 "$e_title")

  [[ -n "$rail" ]] || { echo "스토리 $sid 에 rail: 라벨이 없다" >&2; exit 1; }
  [[ -n "$slug" ]] || { echo "스토리 $sid 에 slug: 라벨이 없다 (plan-story 에서 부여)" >&2; exit 1; }
  # slug 는 경로가 된다 — 문자 집합을 단언하지 않으면 `../` 로 레포 밖에 쓰거나
  # `/` 로 하위 디렉토리가 갈라진다 (실측 2026-08-20: ../escaped 가 트리 밖에 생성됨).
  if [[ ! "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "슬러그 형식 위반: '$slug' (스토리 $sid) — 소문자·숫자·하이픈만, 첫 글자는 영숫자" >&2
    exit 1
  fi
  owner=$(jq -r --arg r "$rail" '.rails[$r].owner // empty' "$RAILS")
  [[ -n "$owner" ]] || { echo "레일 '$rail' 이 rails.json 에 없다 (스토리 $sid)" >&2; exit 1; }

  dir="$slug"

  emit "| [$dir]($dir/index.md) | $sid | $(esc_cell "$rail") | $(esc_cell "$owner") | $(glyph "$status") $status | $(esc_cell "$repos") | $(esc_cell "$title") |" >> "$OUT/index.md"

  # ── 스토리 index.md ───────────────────────────────────────────
  mkdir -p "$OUT/$dir"
  {
    echo "---"
    echo "story: $sid"
    emit "$FRONTMATTER"
    echo "status: $status"
    echo "rail: $rail"
    echo "owner: $owner"
    echo "slug: $slug"
    echo "repos: [$repos]"
    echo "---"
    echo "$HEADER"
    echo
    emit "# $(glyph "$status") $title"
    desc=$(d64 "$e_desc")
    [[ -n "$desc" ]] && { echo; echo "## 설명"; echo; emit "$desc"; }
    echo
    echo "## 마일스톤"
    echo
    echo "| 마일스톤 | bead | 상태 | 제목 |"
    echo "|---|---|---|---|"
    n=0
    for mid in $(children_of "$sid"); do
      n=$((n + 1))
      IFS=: read -r _ e_ms e_mt _ < <(fields "$mid")
      mstatus=$(d64 "$e_ms")
      emit "| [M$n](M$n.md) | $mid | $(glyph "$mstatus") $mstatus | $(esc_cell "$(d64 "$e_mt")") |"
    done
    notes=$(d64 "$e_notes")
    [[ -n "$notes" ]] && { echo; echo "<details><summary>기록 (bd notes)</summary>"; echo; emit "$notes"; echo; echo "</details>"; }
  } > "$OUT/$dir/index.md"

  # ── 마일스톤 M<N>.md ──────────────────────────────────────────
  n=0
  for mid in $(children_of "$sid"); do
    n=$((n + 1))
    IFS=: read -r _ e_ms e_mt e_mdesc _ < <(fields "$mid")
    mstatus=$(d64 "$e_ms")
    {
      echo "---"
      echo "milestone: $mid"
      echo "story: $sid"
      emit "$FRONTMATTER"
      echo "status: $mstatus"
      echo "---"
      echo "$HEADER"
      echo
      emit "# $(glyph "$mstatus") M$n — $(d64 "$e_mt")"
      echo
      echo "스토리: [$sid](index.md)"
      mdesc=$(d64 "$e_mdesc")
      [[ -n "$mdesc" ]] && { echo; emit "$mdesc"; }
      echo
      echo "## 태스크"
      for tid in $(children_of "$mid"); do
        IFS=: read -r _ e_ts e_tt _ e_tn e_acc e_reason < <(fields "$tid")
        tstatus=$(d64 "$e_ts")
        echo
        emit "### $(glyph "$tstatus") $tid — $(d64 "$e_tt")"
        echo
        echo "- 상태: $tstatus"
        acc=$(d64 "$e_acc")
        [[ -n "$acc" ]] && emit "- acceptance: $acc"
        reason=$(d64 "$e_reason")
        # 첫 줄(판정+커밋)만 펴고 나머지는 접는다 — 전문이 태스크당 수십 줄이라
        # 펴 두면 마일스톤 문서에서 태스크 목록 자체가 보이지 않는다.
        if [[ -n "$reason" ]]; then
          emit "- 종료 근거: ${reason%%$'\n'*}"
          rest="${reason#*$'\n'}"
          [[ "$rest" != "$reason" ]] && { echo; echo "<details><summary>종료 근거 전문</summary>"; echo; emit "$rest"; echo; echo "</details>"; }
        fi
        # 태스크 note — reviewer 의 NIT, evaluator 의 판정 근거, RETRY 카운터가
        # 전부 여기 쌓인다. 빼면 하네스의 주요 기록이 사람용 투영에서 사라진다.
        tnotes=$(d64 "$e_tn")
        [[ -n "$tnotes" ]] && { echo; echo "<details><summary>기록 (bd notes)</summary>"; echo; emit "$tnotes"; echo; echo "</details>"; }
      done
    } > "$OUT/$dir/M$n.md"
  done
done
fi

# 완성본으로 바꿔치기. rm 과 mv 사이의 짧은 부재 창은 남지만 잠금이 동시 렌더의
# 인터리브(중첩 이동)를 막고, 반쯤 쓰인 트리가 관측되는 창은 없앤다.
rm -rf "$FINAL_OUT"
mv "$OUT" "$FINAL_OUT"
rm -rf "$LOCK"
trap - EXIT

echo "$FINAL_OUT"
