#!/usr/bin/env bash
# 게이트: 규약이 선언만 되고 강제되지 않던 단언들 (원장·설정·문서의 정적 검사).
# **대상은 둘이다** — 플러그인 트리(스킬·역할·훅·주입 블록)와 하네스 루트(원장·등록부·.gitignore).
# 하네스 루트는 lib/harness-root.sh 가 낸다. 못 찾으면 원장을 보는 검사는 **조용히 건너뛰지 않고
# 실패한다**(rc≠0) — 원장 없이 통과한 원장 검사는 검사가 아니다. 문서만 보는 검사는 그대로 돈다.
#   R5  (harness:develop 운영 규율) 태스크의 repo: 라벨은 정확히 1개                       [원장]
#   R18 (harness:develop 멀티 레포) repos.json 에 경로를 적지 않는다 — 키 집합 화이트리스트  [하네스 루트]
#   S12 (skills/setup/SKILL.md) 하네스 루트 .gitignore 의 필수 항목·금지 항목, 그리고 실물에만
#         있고 규약 문장이 안 드는 잔존 (세 대조)                                          [하네스 루트]
#   R-ACC (harness:develop 운영 규율) acceptance 없는 태스크는 착수(in_progress)하지 않는다   [원장]
#   R-REM (세션 블록 절대 금지 · ADR cycle-close(harness-dmy) 6.5) 낡은 문장의 잔존 — "PR 생성·
#         원격 반영은 전부 명시 지시 대상" 주장이 예외 둘 등재 뒤에도 남아 있는가 (양방향)  [플러그인]
#   C6  (세션 블록 「절대 금지」) 절이 살아 있고 강제 장치의 자리(docs/guardrails.md)를 가리킨다 [플러그인]
#   R40 (harness:develop 멀티 레포) repos.json 등재 이름 ↔ 클론 디렉토리 실재 (양방향)      [하네스 루트]
#   S22 (harness:develop 3-0) 한 워크트리에 두 태스크를 동시에 위임하지 않는다               [원장]
#   S24 (harness:develop 4-2) 하위가 전부 종료 상태인데 열려 있는 스토리                    [원장]
#   R-DATE (harness-dg0.6.30) 주입 블록에 YYYY-MM-DD 날짜가 없다                             [플러그인]
#   R-BEAD (harness-dg0.6.30) 주입 블록이 가리키는 bead ID 가 원장에 실재한다                [플러그인+원장]
#   R-WAIT (harness-dg0.6.39) 사람 대기 신호의 목록은 한 곳이 단일 소유하고, 그 절이
#         신호를 전부 들고 있으며, 절 밖에서 목록을 다시 적은 줄이 없다                     [플러그인]
#   R-DUP (harness-dg0.6.42) 스킬·역할 문서가 주입 블록의 문장을 그대로 복제하지
#         않는다 — 옮기지 말고 자리(파일·절 제목)를 가리킨다                                [플러그인]
#   R-BUDGET 주입 블록의 바이트 상한 — 상시 비용은 SessionStart 마다 실린다                 [플러그인]
#
# 극성 반전(harness:develop 운영 규율): 검사 대상을 손으로 나열하지 않는다.
#   R5  대상은 bd 원장의 태스크 전수에서 파생한다 (면제는 아래 사유 참조).
#   R18 관측 키는 repos.json 실물에서 파생하고 허용 집합과 양방향 대조한다.
#       허용 집합만이 손으로 적힌 목록이며 그것이 곧 화이트리스트다 — 새 키를
#       추가하면 이 검사가 실패하는 것이 의도다 (등재 없이 키가 늘지 않게).
#   R-ACC 대상은 원장에서 파생한다 — 착수의 기계적 표시(status=in_progress)를 가진
#         태스크 전수이며, 손으로 고른 id 목록이 없다.
#   S12 검사할 항목을 스크립트에 적지 않고 **setup/SKILL.md 원문에서 파싱한다.**
#       규약 문서에 항목을 더하면 검사가 자동으로 그것을 요구한다. 반대 방향의 대조는
#       하네스 루트 .gitignore 실물의 유효 줄 전수에서 파생하고, **하네스 소유가 아닌 줄만** 사유와
#       함께 면제표(S12_KEEP/S12_KEEP_WHY)에 등재한다 — 이것이 S12 의 유일한 손목록이다.
#       면제 키가 실물에 존재하는지 역방향으로 단언한다 (0건 면제 = 낡은 면제).
#   R-REM 후보는 스캔 경로 전체에서 패턴으로 파생하고, **남아야 하는 것만** 사유와 함께
#       면제표에 등재한다. 면제 키가 실제 후보에 존재하는지 역방향으로 단언한다.
#   C6  대상은 세션 블록 「절대 금지」 절의 **최상위 불릿 전수**를 원문에서 파싱한다 —
#       0건이면 실패다. 항목별 게이트 표기는 M1 이 블록에서 뺐다(harness-lzs3.2.3 — 강제 장치의
#       목록·한계는 하네스 루트 docs/guardrails.md 가 단일 소유한다) — 그래서 이 검사가 보는 것은
#       그 포인터가 절에 살아 있는가다. 면제 칸을 두지 않는다.
#   R40 두 집합을 **각각의 출처에서** 파생한다(등재부 = repos.json · 클론 루트 = 파일시스템)
#       — 한쪽에서만 파생하면 그 방향의 어긋남만 보인다. 클론 루트 쪽에서 레포가 아닌
#       디렉토리만 사유와 함께 면제하고, 면제 키의 실재를 역방향으로 단언한다.
#   S22 원장 쪽(동시 in_progress)과 파일시스템 쪽(그 스토리의 워크트리 수)에서 각각 파생해
#       비둘기집으로 판정한다 — 손으로 적은 스토리 면제가 없다.
#   S24 대상은 **하위를 가진 epic 전수**이고, 종료 상태 집합(closed·blocked·deferred)만
#       손으로 적힌 목록이다. bd 의 계산이 규율과 반대라 그 집합을 이 검사가 직접 든다.
#
# **0건 파생의 취급이 검사마다 갈린다.** C6·R40 은 문자 그대로 실패로 읽는다(대상이 갓
#   세팅한 트리에도 있다). S22·S24 는 갓 세팅한 트리에서 대상이 0건이라 그렇게 할 수
#   없고(setup/SKILL.md 1.7 의 A 검증표가 rc 0 을 요구한다), R5 와 **같은 함수**를 쓴다 —
#   `ledger_fields_ok`(파생이 의존하는 필드를 직접 단언한다). 그 대체가 못 잡는 것까지
#   실측으로 그 함수의 주석에 적혀 있다. 사유는 각 검사의 주석이 든다.
#   R-DATE·R-BEAD 모집단인 "항상 로드되는 파일 집합"은 플러그인에서는 주입 블록 하나다
#       (hooks/session-context.md — SessionStart 훅이 통째로 additionalContext 로 싣는다). 다른
#       상시 로드 문서는 플러그인이 만들지 않는다 (always_loaded_derive 의 주석). 면제 키의 역방향
#       단언도 같다.
#   R-WAIT 스캔 대상은 글롭(주입 블록 · 스킬 · 역할 정의)으로
#       판다. 손으로 적힌 목록은 WAIT_TOKENS 하나뿐이며 그것이 화이트리스트다 — 신호를
#       늘리면 여기 등재해야 하고, 등재하는 순간 "단일 소유 절이 그것을 들고 있는가"가
#       단언된다. 면제 키의 역방향 단언도 다른 검사와 같다. 1단 검색어와 서술어 토큰은
#       한국어·영어 대안을 함께 든다 — 스캔 대상에 영어 문서가 섞여도 계속 보게 하려는
#       것이다. **그 영어 낱말의 단일 소유는 WAIT_TRIGGER·WAIT_TOKENS 자신이다** — 문서에
#       같은 목록을 두지 않는다(두면 어긋나고, 어긋난 쪽을 따른 줄을 이 검사가 못 본다).
#   R-DUP 스캔 대상은 글롭(skills/*/SKILL.md · agents/*.md)으로 판다 —
#       새 스킬·새 역할의 기본값이 "검사됨" 이다. 원천은 R-DATE·R-BEAD 와 같은 상시 로드
#       모집단이다. 손으로 적힌 것은 임계값 RDUP_MIN 하나뿐이고, 그 값을 그렇게 고른
#       실측 근거(임계값별 적중과 오탐의 정체)는 그 검사의 주석이 든다. 글롭 뒤에 **언어
#       축소**가 한 겹 붙는다(한글 없는 파일 제외) — 이것도 손목록이 아니라 판정에서
#       파생하고, 사유·한계·제외 수의 취급은 그 검사의 주석이 든다.
#
# 배선: 플러그인의 자기 게이트 scripts/check-all.sh 가 checks/*.sh 전수로 돌린다(skills 레포의
#   커밋 게이트는 `claude plugin validate` 뿐이라 이 검사는 손으로, 또는 check-all 로 돈다).
#
# set -e 를 쓰지 않는다 — 검사 스크립트는 첫 실패에서 죽으면 안 된다. 실패는 fail=1 로
# 모아 전부 보고한다 (board-check.sh 와 같은 관례).
# 종료 코드는 파이프 밖에서 채집한다.
set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$PLUGIN_ROOT" || { echo "✗ 플러그인 루트로 이동하지 못했다: $PLUGIN_ROOT" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || { echo "✗ jq 가 없다 — 이 게이트는 jq 없이는 판정할 수 없다 (없으면 빈 질의 결과가 '위반 없음' 오진이 된다)" >&2; exit 1; }

# 하네스 루트 — 원장·등록부·.gitignore 의 자리. 한 번 찾고, 못 찾으면 그것을 쓰는 검사마다 실패한다.
HROOT="$(bash lib/harness-root.sh 2>/dev/null)" || HROOT=""
HROOT_ERR=""
[[ -n "$HROOT" ]] || HROOT_ERR="$(bash lib/harness-root.sh 2>&1 >/dev/null | head -1)"
need_hroot() {  # need_hroot <검사이름> — 하네스 루트가 없으면 ✗ 를 내고 1
  [[ -n "$HROOT" ]] && return 0
  echo "✗ $1 — 하네스 루트를 찾지 못했다 (${HROOT_ERR:-lib/harness-root.sh rc≠0}). 원장·등록부를 보는 검사라 건너뛰지 않고 실패한다 — 스토리 워크트리 안에서 돌리거나 HARNESS_ROOT 를 지정하라"
  return 1
}
bdl() { HARNESS_ROOT="$HROOT" bash scripts/ledger.sh "$@"; }   # 원장은 언제나 하네스 루트의 것이다 — 어댑터로 읽는다(CWD 는 플러그인 루트)

MANIFEST="${REPOS_MANIFEST:-$HROOT/repos.json}"   # 재정의는 검사 스크립트용 (hooks/enter-worktree.sh 와 같은 규약)
SETUP_SKILL="skills/setup/SKILL.md"
GITIGNORE="$HROOT/.gitignore"
BLOCK="hooks/session-context.md"                   # SessionStart 주입 블록 — 플러그인의 유일한 상시 로드 문서

fail=0

# ── 조상 추적 파생이 의존하는 필드의 단언 (R5·S22·S24 공유) ──────────
# 셋 다 `parent` 를 타고 조상을 추적해 대상을 파생한다. 세 번째 중복이라 여기로 뺀다
# (Rule of Three — 1~2번째 중복은 그대로 두고 3번째에 추출한다. 사용자 전역 규칙의 번호라 여기 적지 않는다). **R-ACC 는 여기 들어오지 않는다** —
# 그 검사의 파생은 태스크의 status 하나이고 조상을 타지 않는다(누락이 아니라 대상이 아니다).
#
# **이 단언이 잡는 것과 못 잡는 것을 실측으로 적는다** [2026-08-28 · bash 3.2.57(1) ·
#   macOS Darwin 25.6.0 · jq 1.8.2 · 실제 원장 234건(에폭 12 · parent 해소 관계 171)을
#   jq 로 변형해 대조]:
#   잡는다 — ① `id`/`issue_type`/`status` 중 하나라도 없는 이슈가 생기는 스키마 변경
#            ② `parent` 값이 원장에서 해소되지 않는 경우(조상 사슬이 끊겨 파생이 무효다)
#   **못 잡는다** — `parent` **키 이름 자체**가 바뀌는 스키마 변경. 그러면 `.parent` 가
#     전부 null 이라 ② 의 dangling 집합이 비고, 세 검사의 파생이 조용히 0건이 된다
#     [실측: 키를 `parentx` 로 바꾼 사본 234건에서 ①② 가 **둘 다 통과**하고 S24 의 "하위를
#     가진 스토리" 가 12건 → 0건. **R5 도 같이 통과한다** — 즉 이것은 S22·S24 가 R5 보다
#     약해서 생긴 구멍이 아니라 세 검사가 공유하는 구멍이다].
#     0건을 실패로 읽어 막을 수는 없다: 갓 세팅한 트리는 계층이 없어 같은 0건이고,
#     setup/SKILL.md 1.7 의 A 검증표가 그 트리에서 rc 0 을 요구한다. 데이터만 보고
#     "계층이 아직 없다"와 "키가 바뀌었다"를 가를 방법이 없어 **한계로 남긴다.**
ledger_fields_ok() {  # ledger_fields_ok <검사이름> <원장JSON>
  local name="$1" json="$2" bad dangling
  bad=$(printf '%s' "$json" | jq -r '[.[] | select((has("id") and has("issue_type") and has("status")) | not)] | length')
  if [[ "$bad" != "0" ]]; then
    echo "✗ $name — 원장 JSON 에 id/issue_type/status 가 없는 이슈가 ${bad}건이다. 스키마가 바뀌었다면 이 검사의 파생을 고쳐라 (안 고치면 조용히 0건 통과한다)"
    return 1
  fi
  dangling=$(printf '%s' "$json" | jq -r '
    (map({key: .id, value: .}) | from_entries) as $byid
    | [.[] | select(.parent != null and ($byid[.parent] == null)) | .id] | join(",")')
  if [[ -n "$dangling" ]]; then
    echo "✗ $name — parent 가 원장에서 해소되지 않는 이슈: $dangling. 조상 추적이 끊겨 대상 파생이 무효다"
    return 1
  fi
  return 0
}

# ── R5: 태스크의 repo: 라벨은 정확히 1개 ─────────────────────────────
# 위반하면 develop 이 어느 워크트리로 위임할지 판정하지 못해 착수를 거부한다.
#
# 대상 집합: **조상에 epic(스토리)이 있는 태스크 전수.** develop 이 위임하는 것이
# 정확히 그 집합이고, repo: 라벨의 출처(스토리 상속)도 거기서만 생긴다.
# 면제: **조상에 epic 이 없는 태스크.** 부모가 아예 없는 백로그 태스크(`bd list -l harness`
#       류)와, 부모는 있으나 조상 사슬 어디에도 스토리가 없는 태스크가 함께 걸린다.
#       스토리가 없으면 상속받을 repo: 라벨의 출처 자체가 없고 develop 이 위임하지도
#       않는다. 면제 사유가 구조적 조건이므로 id 를 손으로 적지 않는다.
# "대상 0건 조용한 통과" 대비: 대상 0건 자체를 실패로 만들면 갓 세팅한
# 프로젝트가 무조건 막히므로(setup/SKILL.md 1.7 의 A 검증표가 검사 대상 0건 통과를 전제한다), 대신
# **파생이 의존하는 필드를 직접 단언한다.** bd 의 JSON 스키마가 바뀌어 issue_type·id·parent
# 가 사라지면 파생이 조용히 0건을 내놓는데, 그 경우를 여기서 잡는다. 대상 건수는 항상 출력해
# 사람이 0건을 알아볼 수 있게 둔다.
check_r5() {
  local json rc out covered
  need_hroot R5 || return 1
  json=$(bdl list --all --json -n 0 2>/dev/null); rc=$?
  if [[ "$rc" -ne 0 || -z "$json" ]]; then
    echo "✗ R5 — ledger.sh list 실패 (rc=$rc): 원장 미가용 (하네스 루트 $HROOT)" >&2
    return 1
  fi

  # 파생이 의존하는 필드의 존재를 먼저 단언한다 (공유 자리 — 잡는 것과 못 잡는 것은
  # ledger_fields_ok 의 주석이 실측으로 든다).
  ledger_fields_ok R5 "$json" || return 1

  covered=$(printf '%s' "$json" | jq -r '
    (map({key: .id, value: .}) | from_entries) as $byid
    | def has_epic_ancestor:
        [limit(16; recurse(if .parent then $byid[.parent] else empty end))]
        | any(.[]; .issue_type == "epic");
      [.[] | select(.issue_type == "task" and has_epic_ancestor)] | length')

  out=$(printf '%s' "$json" | jq -r '
    (map({key: .id, value: .}) | from_entries) as $byid
    | def has_epic_ancestor:
        [limit(16; recurse(if .parent then $byid[.parent] else empty end))]
        | any(.[]; .issue_type == "epic");
      [.[] | select(.issue_type == "task" and has_epic_ancestor)]
    | map(. as $i | (($i.labels // []) | map(select(startswith("repo:")))) as $r
          | select(($r | length) != 1)
          | "\($i.id)\t\($r | length)\t\(if ($r | length) == 0 then "없음" else ($r | join(",")) end)\t\($i.title)")
    | .[]')

  if [[ -n "$out" ]]; then
    while IFS=$'\t' read -r tid n labels title; do
      [[ -z "$tid" ]] && continue
      echo "✗ R5 $tid — repo: 라벨이 ${n}개다 (정확히 1개여야 한다) [$labels] ($title)"
      if [[ "$n" == "0" ]]; then
        echo "    조치: 이 태스크가 실제로 건드리는 레포 하나를 붙여라 (ledger.sh label add $tid repo:<붙이는이름>) — 출처는 스토리의 repo: 라벨이다"
      else
        echo "    조치: 이 태스크가 실제로 건드리는 레포 하나만 남겨라 (ledger.sh label remove $tid repo:<빼는이름>)"
      fi
    done <<< "$out"
    return 1
  fi

  echo "✓ R5 태스크 repo: 라벨 정확히 1개 (대상 ${covered}건)"
  return 0
}

# ── R18: repos.json 키 집합 화이트리스트 + 경로형 값 금지 ────────────
# 허용 집합. 여기가 화이트리스트다 — repos.json 에 새 키가 생기면 이 검사가 실패한다.
R18_REQUIRED=(name url default_branch check)
R18_OPTIONAL=(bootstrap)
R18_TOP_REQUIRED=(repos)
R18_TOP_OPTIONAL=(doc)
check_r18() {
  local f=0 allowed top_allowed extra missing entry_fail
  need_hroot R18 || return 1
  if [[ ! -f "$MANIFEST" ]]; then
    echo "✗ R18 — $MANIFEST 이 없다"
    return 1
  fi
  jq empty "$MANIFEST" 2>/dev/null || { echo "✗ R18 — $MANIFEST 이 유효한 JSON 이 아니다"; return 1; }

  allowed=$(printf '%s\n' "${R18_REQUIRED[@]}" "${R18_OPTIONAL[@]}" | jq -R . | jq -sc .)
  top_allowed=$(printf '%s\n' "${R18_TOP_REQUIRED[@]}" "${R18_TOP_OPTIONAL[@]}" | jq -R . | jq -sc .)

  # 최상위 키 — 관측 집합에서 파생해 허용 밖을 잡는다.
  extra=$(jq -r --argjson a "$top_allowed" 'keys[] | select(. as $k | $a | index($k) | not)' "$MANIFEST")
  while IFS= read -r k; do
    [[ -z "$k" ]] && continue
    echo "✗ R18 $MANIFEST — 허용되지 않은 최상위 키 '$k' (허용: ${R18_TOP_REQUIRED[*]} ${R18_TOP_OPTIONAL[*]})"
    f=1
  done <<< "$extra"
  for k in "${R18_TOP_REQUIRED[@]}"; do
    jq -e --arg k "$k" 'has($k)' "$MANIFEST" >/dev/null || { echo "✗ R18 $MANIFEST — 필수 최상위 키 '$k' 가 없다"; f=1; }
  done

  jq -e '(.repos // []) | type == "array" and length > 0' "$MANIFEST" >/dev/null \
    || { echo "✗ R18 $MANIFEST — repos 가 비었거나 배열이 아니다 (대상 0건은 통과가 아니다)"; return 1; }

  # 각 항목의 관측 키를 실물에서 파생 → 허용 밖 / 필수 누락 양방향
  entry_fail=$(jq -r --argjson allowed "$allowed" --argjson req "$(printf '%s\n' "${R18_REQUIRED[@]}" | jq -R . | jq -sc .)" '
    .repos | to_entries[] | . as $e
    | ($e.value | keys) as $obs
    | (($obs - $allowed) | map("EXTRA\t\($e.key)\t\(.)")) + (($req - $obs) | map("MISSING\t\($e.key)\t\(.)"))
    | .[]' "$MANIFEST")
  if [[ -n "$entry_fail" ]]; then
    while IFS=$'\t' read -r kind idx key; do
      [[ -z "$kind" ]] && continue
      local name; name=$(jq -r --argjson i "$idx" '.repos[$i].name // "(name 없음)"' "$MANIFEST")
      if [[ "$kind" == "EXTRA" ]]; then
        echo "✗ R18 $MANIFEST repos[$idx] ($name) — 허용되지 않은 키 '$key' (허용: ${R18_REQUIRED[*]} ${R18_OPTIONAL[*]})"
        echo "    경로를 적으려는 것이라면 멈춰라 — 클론 위치는 ~/.harness-workspace/<name> 으로 고정이다 (scripts/repo.sh 가 관리)"
      else
        echo "✗ R18 $MANIFEST repos[$idx] ($name) — 필수 키 '$key' 가 없다"
      fi
      f=1
    done <<< "$entry_fail"
  fi

  # 경로형 값 금지: url 을 제외한 값이 '/' 로 시작하거나 '~/' 를 포함하면 손으로 적은 경로다.
  local pathy
  pathy=$(jq -r '
    .repos | to_entries[] | . as $e
    | $e.value | to_entries[]
    | select(.key != "url")
    | select((.value | type) == "string")
    | select((.value | test("^/")) or (.value | test("~/")))
    | "\($e.key)\t\(.key)\t\(.value)"' "$MANIFEST")
  if [[ -n "$pathy" ]]; then
    while IFS=$'\t' read -r idx key val; do
      [[ -z "$key" ]] && continue
      echo "✗ R18 $MANIFEST repos[$idx].$key — 절대 경로형 값이다: $val"
      f=1
    done <<< "$pathy"
  fi

  [[ "$f" -eq 0 ]] && echo "✓ R18 $MANIFEST 키 집합이 허용 집합과 일치, 경로형 값 없음"
  return "$f"
}

# ── S12: .gitignore 필수/금지 항목 + 실물 잔존 (세 대조) ─────────────
# 검사 항목을 스크립트에 적지 않고 setup/SKILL.md 원문에서 파싱한다. 원문 형식:
#   Add these to `.gitignore`: `A` · `B` · … . **Never gitignore `.harness-state`**
#   (setup/SKILL.md 이 영어 문서라 앵커도 영어다. 파서가 보는 것은 이 앵커 문자열과
#    ** 강조 경계뿐이고, 판정 구조는 언어와 무관하다.)
# 파싱이 실패하면 폴백으로 덮지 않고 명확히 실패한다 — 조용한 통과가 최악이다.
#
# **세 번째 대조 (2026-08-27, harness-dg0.6.37): 실물 → 규약 문장.** 위 둘은 규약 문장이
#   든 항목만 본다 — 이 트리의 .gitignore 에 하네스 산출물이 새로 늘어도 규약 문장이
#   그것을 안 들면 어느 검사도 안 본다. 실제로 그렇게 났다: 같은 스토리의 정지 가드
#   태스크가 런타임 산출물 둘을 만들며 .gitignore 에만 넣고 setup 지시에는 안 넣어,
#   **같은 커밋 안에서 한쪽 목록만 갱신됐다.** 새로 세우는 하네스는 그 둘을 커밋 대상으로
#   잡는다. 그래서 대조를 실물 쪽에서도 건다.
#
# 극성 반전: 검사 대상을 손으로 고르지 않는다 — .gitignore 의 유효 줄 전수에서 파생하고,
#   **하네스 소유가 아닌 줄만** 사유와 함께 아래 면제표에 등재한다. 새 줄의 기본값은
#   "검사됨" 이다. 면제 키가 실물에 실제로 있는지 역방향으로 단언한다(0건 면제 = 낡은
#   면제). 양쪽 파생(규약 문장의 필수 항목 · .gitignore 의 유효 줄)이 0건이면 실패다 —
#   0건 통과는 "위반 없음" 이 아니라 "안 봤음" 이다.
#
# 자리 — rules-check 인가 guardrail-check 인가: **rules-check 이고, 이유는 겹침이다.**
#   이 대조가 읽는 두 원본(setup/SKILL.md 의 규약 문장 · .gitignore 실물)은 S12 가 이미
#   파싱해 들고 있다. guardrail-check 에 새 절을 세우면 같은 문장을 두 번 파싱하게 되고,
#   규약 문장의 형식이 바뀔 때 고칠 파서가 둘이 된다. 성격으로도 이쪽이다 — 이것은 강제
#   장치(훅·설치기)가 살아 있는지가 아니라 **두 문서 목록이 서로 맞는지**를 보는 문서
#   규율이고, rules-check 이 그것을 본다.
#   **대가를 적어 둔다: rules-check 은 커밋 훅에 배선돼 있지 않다**(위 "배선" 항목).
#   guardrail-check 에 뒀다면 커밋마다 돌았을 것이다. 즉 이 검사는 **손으로 돌릴 때만**
#   잡으며, 두 목록이 다시 갈라진 채로 커밋·push 되는 것을 막지 못한다. 그래도 겹침을
#   택한 이유는 배선이 이 검사 하나 때문에 바뀔 문제가 아니기 때문이다 — 배선은
#   rules-check 전체의 결정이고 docs/guardrails.md 3절이 소유한다.
#
# 한계: 이것은 **두 등재의 대조**다. .gitignore 가 실제로 그 경로를 무시하는지(git 이
#   그렇게 동작하는지)는 보지 않는다.
#
# 면제표 — .gitignore 에 있으나 설치 절차 5항이 지시할 것이 **아닌** 줄.
S12_KEEP=(
  ".serena/"
  ".dolt/"
  "*.db"
  ".beads-credential-key"
  ".beads/proxieddb/"
)
S12_KEEP_WHY=(
  "외부 도구(serena)의 로컬 캐시 — 하네스가 만들지 않으므로 설치 절차의 소유가 아니다"
  "원장 초기화가 넣는다 (.gitignore 의 'Beads / Dolt files' 절 주석이 출처를 적는다) — 설치 절차 1.6 의 1항(ledger.sh init — beads 의 bd init)의 소유"
  "원장 초기화가 넣는다 — 같은 항"
  "원장 초기화가 넣는다 — 같은 항"
  "원장 초기화가 넣는다 — 같은 항"
)
check_s12() {
  local line req_part forbid_part required forbidden f=0 item
  need_hroot S12 || return 1
  [[ -f "$SETUP_SKILL" ]] || { echo "✗ S12 — $SETUP_SKILL 이 없다 (검사 항목의 출처)"; return 1; }
  [[ -f "$GITIGNORE" ]]   || { echo "✗ S12 — $GITIGNORE 이 없다"; return 1; }

  line=$(grep -m1 'Add these to `\.gitignore`:' "$SETUP_SKILL")
  if [[ -z "${line}" ]]; then
    echo "✗ S12 — $SETUP_SKILL 에서 'Add these to \`.gitignore\`:' 문장을 찾지 못했다 — 규약이 옮겨갔거나 파서가 낡았다. 둘 중 하나를 고쳐라"
    return 1
  fi

  # 파라미터 확장 ${x#*\*\*} 는 **매칭에 실패하면 입력을 그대로 반환한다.** 규약 문장에서
  # ** 강조가 빠지면 금지 절이 필수 절과 같은 문자열이 돼 required==forbidden 으로 조용히
  # 뒤집히고, 같은 실행이 방금 "요구"한 항목을 "금지 항목이 들어 있다"로 보고한다. 아래
  # 빈 값 가드는 양쪽 다 비어 있지 않아 발동하지 않는다 (harness-pig). 확장 전에 못박는다.
  if [[ "$(grep -o '\*\*' <<< "$line" | grep -c .)" -ne 2 ]]; then
    echo "✗ S12 — 규약 문장에서 ** 강조 구간(금지 항목 절)을 찾지 못했다 — 필수/금지 경계가 없으므로 파싱하지 않는다. $SETUP_SKILL 의 강조를 되살리거나 이 파서를 고쳐라. 원문: $line"
    return 1
  fi

  # 앵커 이후 ~ 첫 '**' 앞까지가 필수 항목, 그 뒤가 금지 항목 절.
  # 패턴을 따옴표로 감싸 백틱이 명령 치환으로 해석되지 않게 한다 (${x#*word} 의 word 는
  # 확장 대상이다). 최단 일치라 문장 뒤쪽의 'gitignore' 산문에는 걸리지 않는다.
  req_part=${line#*'Add these to `.gitignore`:'}
  forbid_part=${req_part#*\*\*}
  forbid_part=${forbid_part%%\*\**}   # 닫는 ** 이후의 산문에도 백틱 토큰이 있다 — 강조 구간만 남긴다
  req_part=${req_part%%\*\**}

  required=$(printf '%s' "$req_part"    | grep -o '`[^`]*`' | tr -d '`')
  forbidden=$(printf '%s' "$forbid_part" | grep -o '`[^`]*`' | tr -d '`')

  if [[ -z "$required" || -z "$forbidden" ]]; then
    echo "✗ S12 — 규약 문장을 파싱하지 못했다 (필수 항목 $(printf '%s' "$required" | grep -c . )건 / 금지 항목 $(printf '%s' "$forbidden" | grep -c . )건). 원문: $line"
    return 1
  fi

  # .gitignore 의 유효 항목 = 주석·빈 줄을 뺀 줄 전체 (실물에서 파생)
  local entries n_entries
  entries=$(grep -v '^[[:space:]]*#' "$GITIGNORE" | sed 's/[[:space:]]*$//' | grep -v '^$')
  n_entries=$(printf '%s' "$entries" | grep -c .)
  if [[ "$n_entries" -eq 0 ]]; then
    echo "✗ S12 — $GITIGNORE 에서 유효 항목을 0건 파생했다 — 0건 통과는 '위반 없음' 이 아니라 '안 봤음' 이다"
    return 1
  fi

  while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    if ! grep -qxF -- "$item" <<< "$entries"; then
      echo "✗ S12 $GITIGNORE — 필수 항목 '$item' 이 없다 ($SETUP_SKILL 이 요구한다)"
      f=1
    fi
  done <<< "$required"

  while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    if grep -qxF -- "$item" <<< "$entries"; then
      echo "✗ S12 $GITIGNORE — 금지 항목 '$item' 이 들어 있다 ($SETUP_SKILL: 설치 기록이라 커밋해야 sync 가 드리프트를 판정한다)"
      f=1
    fi
  done <<< "$forbidden"

  # 역방향 단언: 면제 키가 실물에 하나씩 있는가. 0건 면제는 낡은 면제이고, 낡은 면제는
  # 그 줄이 사라진 뒤에도 "검사됨" 으로 돌아오지 않게 막는다.
  local i k residual
  for i in "${!S12_KEEP[@]}"; do
    k="${S12_KEEP[$i]}"
    if ! grep -qxF -- "$k" <<< "$entries"; then
      echo "✗ S12 면제 '${k}' 가 $GITIGNORE 에 없다 — 낡은 면제다. 면제표(S12_KEEP)에서 빼라 (등재 사유: ${S12_KEEP_WHY[$i]})"
      f=1
    fi
  done

  # 잔존 = 규약 문장에도 면제표에도 없는 .gitignore 줄. 한쪽에만 있는 항목이 여기 남는다.
  residual="$entries"
  while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    residual=$(grep -vxF -- "$item" <<< "$residual")
  done <<< "$required"
  for k in "${S12_KEEP[@]}"; do
    residual=$(grep -vxF -- "$k" <<< "$residual")
  done
  while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    echo "✗ S12 $SETUP_SKILL — $GITIGNORE 의 '${item}' 을 규약 문장이 들지 않는다 (새로 세우는 하네스는 이것을 커밋 대상으로 잡는다). 문장에 더하거나, 하네스 소유가 아니면 사유와 함께 S12_KEEP 에 등재하라"
    f=1
  done <<< "$residual"

  [[ "$f" -eq 0 ]] && echo "✓ S12 $GITIGNORE 필수 $(printf '%s' "$required" | grep -c .)건 존재 · 금지 $(printf '%s' "$forbidden" | grep -c .)건 부재 · 실물 ${n_entries}건 중 규약 문장 미등재 0건 (면제 ${#S12_KEEP[@]}건 전부 실재)"
  return "$f"
}


# ── R-ACC: acceptance 없는 태스크는 착수(in_progress)되어 있지 않다 ──
# 규칙 원문(harness:develop 운영 규율): "acceptance 없는 태스크는 bd ready 에
# 떠도 착수 금지. 먼저 acceptance 를 채운다."
#
# **막는 지점이 "존재"가 아니라 "착수"다.** 백로그에 제목만 적어 두는 것은 정상이고,
# 그것까지 막으면 등재 자체가 무거워진다. 그래서 대상은 **착수의 기계적 표시**를 가진
# 태스크뿐이다 — `bd update --claim` 이 status 를 in_progress 로 바꾸므로 그것을 본다.
#
# board-check 의 acceptance 검사와 겹치지 않는다. 그쪽은 **스프린트 라벨이 붙은** 태스크의
# acceptance 존재를 보고(open 이어도 요구), 이쪽은 **라벨과 무관하게 착수된** 태스크를 본다.
# 그 갭이 이 검사의 이유다 — 스프린트 밖 백로그 태스크는 어느 게이트도 보지 않았다.
#
# 한계: **ephemeral(wisp) 이슈는 이 검사가 보지 못한다.** `bd list --all --json` 이 그것을
# 내지 않는다 [실측 2026-08-22: `--ephemeral` 로 만들어 claim 한 태스크가 목록에 0건].
# wisp 는 임시 이슈라 착수 대상이 아니므로 감수하지만, **이 검사의 픽스처를 wisp 로 만들면
# 아무것도 검출되지 않는다** — 대상 집합이 비어 조용히 통과한다. 일반 bead 로 만들어라.
check_racc() {
  local json rc schema_bad bad n
  need_hroot R-ACC || return 1
  json=$(bdl list --all --json -n 0 2>/dev/null); rc=$?
  if [[ "$rc" -ne 0 || -z "$json" ]]; then
    echo "✗ R-ACC — ledger.sh list 실패 (rc=$rc): 원장 미가용 (하네스 루트 $HROOT)" >&2
    return 1
  fi

  # 파생이 의존하는 필드를 먼저 단언한다. status 가 사라지면 in_progress 가 0건이 되어
  # **조용히 통과**한다 (대상 집합이 비면 어떤 게이트든 통과한다).
  # acceptance_criteria 는 요구하지 않는다 — 없는 이슈가 정상이고, 필드 자체가 사라지면
  # 전부 "빈 것"으로 읽혀 과검출로 드러난다(안전한 방향).
  schema_bad=$(printf '%s' "$json" | jq -r '[.[] | select((has("id") and has("issue_type") and has("status")) | not)] | length')
  if [[ "$schema_bad" != "0" ]]; then
    echo "✗ R-ACC — 원장 JSON 에 id/issue_type/status 가 없는 이슈가 ${schema_bad}건이다. 스키마가 바뀌었다면 이 검사의 파생을 고쳐라 (안 고치면 조용히 0건 통과한다)"
    return 1
  fi

  bad=$(printf '%s' "$json" | jq -r '
    [ .[]
      | select(.issue_type == "task"
               and .status == "in_progress"
               and (((.acceptance_criteria // "") | gsub("^\\s+|\\s+$"; "")) == "")) ]
    | .[] | "\(.id)\t\(.title)"')
  n=$(printf '%s' "$json" | jq -r '[.[] | select(.issue_type == "task" and .status == "in_progress")] | length')

  if [[ -n "$bad" ]]; then
    while IFS=$'\t' read -r id title; do
      [[ -z "$id" ]] && continue
      echo "✗ R-ACC $id — acceptance 없이 착수됐다 ($title). 채운 뒤 진행하라: ledger.sh update $id --acceptance \"<기계 판정 가능한 완료 조건>\""
    done <<< "$bad"
    return 1
  fi

  echo "✓ R-ACC 착수된 태스크 ${n}건 전부 acceptance 있음"
  return 0
}

# ── R-REM: 낡은 문장의 잔존 ────────────────────────────────────────
# 규칙 원문(세션 블록 "절대 금지" 첫 항목 + ADR harness-dmy
# 6.5): "PR 생성·원격 반영은 전부 사용자 명시 지시 대상" 이라는 주장은 예외 둘이
# 등재된 뒤로 낡았다. 그 주장을 하는 줄이 트리에 다시 생기면 여기서 잡는다.
#
# 극성 반전: 대상을 손으로 나열하지 않는다 — 스캔 경로 전체에서 패턴으로 파생하고,
#   **남아야 하는 것만** 사유와 함께 아래 면제표에 등재한다. 새 파일·새 줄의 기본값은
#   "검사됨" 이다. 면제 키가 실제 후보 집합에 존재하는지 역방향으로 단언한다.
#
# **두 번 훑는다 — 물리 줄과 논리 줄로. 잔존은 두 잔존의 합집합이다.** 어느 한쪽만
#   쓰면 반대 방향으로 조용히 샌다. 둘 다 실측된 경로다 [2026-08-27]:
#   - **접지 않으면** 개행 + 들여쓰기로 갈린 문장을 못 본다. CLAUDE.md:45(들여쓴 근거
#     문단과 그 아래 중첩 목록에 걸친 히트)가 후보에서 통째로 빠졌다 (HEAD 0ae4895).
#   - **접기만 하면** 낡은 줄이 **면제 앵커를 가진 논리 줄에 흡수된다.** 앵커 면제 줄
#     아래에 낡은 줄을 들여써 심으면 후보에는 잡히는데 잔존 0, rc=0 이었다. 같은 줄을
#     들여쓰지 않으면 잔존 1, rc=1 (verify-code 1회차 reviewer 의 A/B).
#   그래서 **접기는 "과검출 방향이라 안전" 하지 않다** — 이 주석의 초판이 그렇게 적었고
#   거짓이었다. 흡수 경로는 앵커 면제가 걸린 자리에서만 열리는데, 지금 그 자리가 하필
#   편집이 잦은 docs/usecases.md:262·:263·:298 과 docs/operations.md:53 이다.
#   물리 줄 훑기가 그것을 막는다 — 심은 줄은 그 자신이 앵커를 갖지 않으므로 물리 훑기의
#   잔존으로 남는다.
#
# **남는 한계 — 접기의 커버리지는 "들여쓴 이어짐" 하나뿐이다.** 갈린 문장은 이어지는
#   줄이 **들여써 있을 때만** 잡힌다. 앵커 흡수는 그 구멍의 한 갈래일 뿐이고 **앵커가
#   없어도 조용한 형태가 둘 더 있다.** 세 형태를 앵커 없는 파일 하나에 심어 재봤다
#   [실측 2026-08-27. 각 물리 줄이 단독으로는 패턴에 0건이고 한 줄로 이으면 1건임을
#   먼저 단언한 뒤 — 그 단언이 없으면 "조용함" 이 "재료가 애초에 안 걸림" 과 같다]:
#     들여쓴 이어짐                          -> 잡힌다 (잔존 1, rc=1)
#     **하드랩**(이어지는 줄이 안 들여써짐)  -> **조용하다 (잔존 0, rc=0)**
#     **빈 줄로 갈림**                       -> **조용하다 (잔존 0, rc=0)**
#   **도달 가능한 자리가 실재했다.** 그 실측의 대상은 리뷰 기록 8편(harness-uhy 계보)이
#   문장 중간에서 하드랩된 것이었고 실물 한 자리가 harness-uhy.5.1 note 로 옮겨간 그
#   기록의 13-14행이었다(한 문장이 두 물리 줄에 걸쳐 있고 둘째 줄이 안 들여써져
#   있다). **그 파일들은 harness-qae 가 원장으로 옮기며 트리에서 사라졌고, 지금 스캔
#   대상에 같은 형태가 남았는지는 재지 않았다** — 커버리지의 경계 자체는 그대로다.
#   좁은 예외가 아니라 **커버리지의 경계**다 — 이 주석의 앞 판은 이것을 "앵커와 겹치는
#   좁은 교집합" 으로 적어 실측보다 좁게 서술했다. 닫으려면 훑기를 하나 더 얹어야 하고
#   (문단 단위 접기) 그것은 이 태스크의 범위 밖이다.
#
# 역방향 단언은 **경로 필드만** 본다. 히트 줄 전체로 세면 다른 파일이 본문에서 인용한
#   경로까지 함께 잡혀 계수가 부풀고, 부푼 값은 면제가 낡아 0 이 되는 것을 가려 준다.
#   실측 [2026-08-27. 0ae4895 를 git archive 로 깨끗이 펼쳐 센 접힌 후보 **27줄** 기준.
#   이 주석의 앞 판은 28 이라고 적었는데, 그것은 작업 트리에서 잰 값이라 미커밋 상태가
#   섞여 있었다: 27 − operations.md:47(이미 고침) + 이 스크립트 자신의 자기 인용 2 = 28.
#   같은 값을 다른 트리에서 재면 안 맞는다]: implementer.md 키가 경로 필드로는
#   1, ADR 6.5 의 표기(경로 + 콜론)로 줄 전체를 세면 2 였다. 그 둘째 매칭은 당시
#   리뷰 기록(harness-uhy.3.4 note 로 옮겨간 그 기록의 21행)이 그 경로를 콜론까지
#   붙여 인용한 것이다. **무엇으로 셌는지를 안 적은 계수는 근거가 아니다** — 같은 키를 콜론 없는
#   부분문자열로 세면 전체 경로로 5, 파일명 'implementer.md' 만으로 6 이고,
#   harness-uhy.1.2 note 로 옮겨간 기록의 129행은 접두사 없이 적어 ADR 표기로는 0건이다.
#
# 기준값(변경 전 → 후). **ADR 이 적은 "9줄 → 0" 은 ADR 자신의 커밋에서만 참이다.**
#   - ADR 6.5 의 명령을 적힌 그대로 3fccfc2(ADR 6.5 가 쓰인 커밋)에 돌리면 **잔존 9줄**
#     — develop:45 · plan-story:59 · plan-sprint:49 · setup:90 · operations.md:45 ·
#     usecases.md:242·:262·:296 · development.md:52. **9 는 재현된다.**
#   - 같은 명령을 이 검사가 서기 직전(0ae4895)에 돌리면 **12줄**이다. M6 이 아홉 중
#     여덟을 고치는 동안 새 문장(setup:179·212·359·367 · retrospective:27 ·
#     guard-check:1373 · usecases:263·298·299)과 bd 투영(docs/backlog)이 들어왔다.
#   - **이 검사**(접기 + 아래 면제표 + docs/backlog 제외)를 0ae4895 에 돌리면 잔존
#     **1줄** — docs/operations.md:47 뿐이었다. 그 절이 CLAUDE.md 가 소유한 목록을
#     복제해, 같은 파일이 여섯 줄 위에서 "종점은 PR" 이라고 적고 아래에서 그 반대를
#     적고 있었다. 이 커밋이 그 절을 포인터로 바꿔 **0줄**로 만든다.
#     [측정: 2026-08-27, bash 3.2.57(1) / macOS Darwin 25.6.0, CWD = 이 레포 루트]
#
# 배선: **이 검사도 배선되지 않는다.** rules-check.sh 자체가 손으로 돌리는 게이트이므로
#   (위 "배선" 항목) 낡은 문장이 다시 생겨도 커밋·push 는 그대로 통과한다. ADR 7절 잔여 5
#   가 이것을 잔여로 등재해 두었다 — 여기서 닫히지 않는다.
#
# 부정 대조군(이 검사가 죽었는지): R_REM_SCAN_EXTRA 에 파일 하나를 얹으면 스캔 대상에
#   더해진다. plan-story 의 옛 문장을 되살린 사본을 그 경로로 주면 잔존이 1줄 이상이
#   되어야 한다. 사본이 원본과 같거나 만들어지지 않으면 그 자체가 실패다 — 두 파일의
#   실재를 먼저 단언하고 내용 차이를 봐라(비교 명령의 비-0 만으로 판정하지 마라:
#   부재의 rc=2 와 차이의 rc=1 이 셸 || 에서 같은 분기로 간다).
#   **그 둘로는 모자란다 — 되살린 줄 자체가 패턴에 걸리는지 함께 단언해라.** 실재와
#   차이는 대조군 성립의 필요조건이지 충분조건이 아니다. 실측: 이 검사를 세울 때 옛
#   문장을 514577c^ 의 59행에서 뽑았는데 그 행이 빈 줄이라 사본에 빈 줄만 덧붙었고,
#   cmp 는 "원본과 다르다" 로 통과했다. 대조군은 공허했는데 성립 단언은 전부 초록이었다.
#   (옛 문장이 실제로 있는 자리는 3fccfc2 의 plan-story:59 다.)
#
# 한계 — 파일 단위 면제의 폭: 아래 KEEPF 에 오른 파일은 **새로 생기는 줄의 기본값이
#   "검사 안 됨"** 이 된다. 극성 반전 규율과 방향이 반대이지만 ADR 6.5 가 파일 단위 면제를
#   승인했으므로 그대로 두며, **그 파일에 낡은 문장이 다시 들어오면 이 검사는 못 본다.**
#   좁히려면 앵커 면제로 옮겨라 — 대신 위 "흡수" 한계의 표면이 그만큼 넓어진다.
#
# 한계 — 앵커 면제의 폭: 앵커는 **파일 한정이 아니라 트리 전역 부분문자열**이다. 아래
#   KEEPL 의 사유가 파일·줄을 적는 것은 *지금 어디에 걸리는지*를 밝히는 것이지 발동
#   범위를 그 파일로 좁히는 것이 아니다 — 어느 파일에서든 그 문자열을 품은 새 히트가
#   생기면 조용히 면제된다. **역방향 단언은 ≥1건만 보므로 과폭을 잡지 못한다**(과소만
#   잡는다). 넷 중 "단계 5" 가 가장 덜 고유하다. 지금은 후보 2건(둘 다 usecases.md)이라
#   과폭이 아니지만, 면제를 더할 때는 그 문자열이 트리에서 얼마나 흔한지 먼저 세라.

RREM_FOLD='
FNR==1 { flush() }
{ line=$0
  if (ln>0 && line ~ /^[[:space:]]+[^[:space:]]/) { sub(/^[[:space:]]+/,"",line); buf=buf " " line; next }
  flush(); buf=line; ln=FNR; fn=FILENAME }
END { flush() }
function flush() { if (ln>0) printf "%s:%d:%s\n", fn, ln, buf; buf=""; ln=0; fn="" }
'

# 면제 — 경로 단위. 그 파일의 히트가 **전부** 남아야 하는 것일 때만 쓴다.
# 영어 문서(retrospective·setup 등)는 s1·s2 가 한국어 낱말만 들어 후보에 오르지 않는다 — 그 파일에
# 낡은 영어 문장이 새로 들어와도 R-REM 은 잡지 못한다(백로그 harness-53ro).
RREM_KEEPF=(
  "hooks/session-context.md"               # 예외 둘을 등재한 항목 본문. 개정 후 원문이다
  "agents/implementer.md"                  # 서브에이전트 금지는 이 결정이 유지한다 (ADR D5)
  "hooks/guard.sh"                         # r_remote 의 deny 메시지. 판정 로직도 문면도 안 바뀐다 (ADR D5)
  "checks/guard-check.sh"                  # 위 deny 문면에 대한 단언 문자열. guard.sh 와 짝이라 함께 남는다
  "checks/rules-check.sh"                  # 이 검사 자신. 무엇을 낡은 문장으로 보는지 서술하려면 그 문장을 인용해야 한다 — 자기 인용이 잔존으로 잡히는 것을 확인하고 등재했다
)
# 면제 — 앵커 문자열. 남는 줄과 고칠 줄을 함께 가진 파일에 쓴다(줄번호는 편집에 흔들린다).
# 지금은 없다 — 플러그인 트리에는 docs/ 의 실측 기록이 없다. (0건 면제표는 정상이다.)
RREM_KEEPL=()

# 면제표를 히트 목록에서 걷어낸다. 경로 키는 경로 필드에, 앵커 키는 줄 전체에 건다.
rrem_strip() {
  local out="$1" k
  for k in "${RREM_KEEPF[@]}"; do out=$(printf '%s\n' "$out" | awk -F: -v k="$k" '$1 != k'); done
  for k in ${RREM_KEEPL[@]+"${RREM_KEEPL[@]}"}; do out=$(printf '%s\n' "$out" | grep -vF -- "$k"); done
  printf '%s' "$out"
}

check_rrem() {
  local s1 s2 files hits hits_f hits_p resid n_cand_f n_cand_p n_res k c p scope f=0
  local -a flist=()

  s1='(PR|풀 리퀘스트)[^|]{0,60}(명시 지시|명시적 지시|사용자 승인|사람의 몫)|(명시 지시|명시적 지시|사용자 승인)[^|]{0,60}PR'
  s2='(원격 반영|GitHub 반영)[^|]{0,40}(명시 지시|명시적 지시|사용자 승인)|(명시 지시|명시적 지시)[^|]{0,40}(원격 반영|GitHub 반영)'

  # 스캔 대상은 플러그인 트리에서 파생한다 — git 이 보는 .md·.sh 전부(-co 는 추적 + 미추적, 무시 제외).
  # 플러그인 루트에서 부르므로 경로는 플러그인 상대다.
  files=$(git ls-files -co --exclude-standard -- . 2>/dev/null \
          | grep -E '\.(md|sh)$' | sort)
  while IFS= read -r p; do [[ -n "$p" ]] && flist+=("$p"); done <<< "$files"
  [[ -n "${R_REM_SCAN_EXTRA:-}" ]] && flist+=("$R_REM_SCAN_EXTRA")

  # 대상 단언 — 검사가 **무엇을 보는지** 못박는다. 파생이 조용히 좁아지면(경로 오타,
  # find 실패) 잔존 0 이 "위반 없음" 이 아니라 "안 봤음" 이 된다.
  for k in "hooks/session-context.md" "skills/develop/SKILL.md" "skills/plan-story/SKILL.md"; do
    if ! printf '%s\n' "${flist[@]}" | grep -qxF -- "$k"; then
      echo "✗ R-REM — 스캔 대상에 '$k' 가 없다 (${#flist[@]}건 파생). 파생이 좁아졌으면 잔존 0 은 '위반 없음' 이 아니라 '안 봤음' 이다"
      return 1
    fi
  done

  # 두 훑기. 역방향 단언은 합집합에서 센다 — 어느 훑기에서든 잡히면 그 면제는 살아 있다.
  hits_f=$(awk "$RREM_FOLD" "${flist[@]}" | grep -E "$s1|$s2")
  hits_p=$(awk '{printf "%s:%d:%s\n", FILENAME, FNR, $0}' "${flist[@]}" | grep -E "$s1|$s2")
  hits=$(printf '%s\n%s' "$hits_f" "$hits_p")
  n_cand_f=$(printf '%s' "$hits_f" | grep -c . )
  n_cand_p=$(printf '%s' "$hits_p" | grep -c . )

  # 역방향: 면제 키가 실제 후보 집합에 하나씩 잡히는가. 0건 면제는 낡은 면제다.
  for k in "${RREM_KEEPF[@]}"; do
    c=$(printf '%s\n' "$hits" | awk -F: -v k="$k" '$1 == k' | grep -c . )
    if [[ "$c" -lt 1 ]]; then
      echo "✗ R-REM 면제(경로) '$k' 가 후보에서 0건이다 — 낡은 면제이거나 대상 문장이 사라졌다. 면제표에서 빼라"
      f=1
    fi
  done
  for k in ${RREM_KEEPL[@]+"${RREM_KEEPL[@]}"}; do
    c=$(printf '%s\n' "$hits" | grep -cF -- "$k")
    if [[ "$c" -lt 1 ]]; then
      echo "✗ R-REM 면제(앵커) '$k' 가 후보에서 0건이다 — 앵커가 편집으로 사라졌거나 낡은 면제다. 면제표를 고쳐라"
      f=1
    fi
  done

  # 잔존 = 두 훑기의 잔존 합집합.
  # sort -u 는 **문자열이 같을 때만** 합친다 — 그래서 중복이 걷히는 것은 자식 줄이 없는
  # 최상위 줄뿐이다. 자식 줄의 위반은 접힘이 '부모:N:<이어붙인 본문>', 물리가
  # '자식:M:<그 줄>' 로 키가 달라 **한 위반이 두 줄로 보고되고 계수도 2가 된다**
  # [실측 2026-08-27: 앵커 없는 부모 아래에 낡은 줄을 들여써 심으니 잔존 2줄].
  # rc 는 어느 쪽이든 1 이라 게이트 판정은 같다. 사람이 목록을 읽을 때만 겹쳐 보인다.
  resid=$(printf '%s\n%s' "$(rrem_strip "$hits_f")" "$(rrem_strip "$hits_p")" | grep -v '^$' | sort -u)
  n_res=$(printf '%s' "$resid" | grep -c . )

  local scope="스캔 ${#flist[@]}파일 · 후보 접힘 ${n_cand_f}줄/물리 ${n_cand_p}줄 · 면제 ${#RREM_KEEPF[@]}경로+${#RREM_KEEPL[@]}앵커"
  if [[ "$n_res" -ne 0 ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "✗ R-REM $(printf '%s' "$line" | cut -d: -f1,2) — 낡은 문장이 남아 있다: $(printf '%s' "$line" | cut -d: -f3- | cut -c1-110)"
    done <<< "$resid"
    echo "✗ R-REM 낡은 문장 잔존 ${n_res}줄 ($scope). 고치거나, 남아야 하는 것이면 사유와 함께 면제표에 등재하라"
    return 1
  fi

  [[ "$f" -eq 0 ]] && echo "✓ R-REM 낡은 문장 잔존 0줄 ($scope 전부 1건 이상)"
  return "$f"
}

# ── C6: 세션 블록 「절대 금지」 절 — 살아 있고, 강제 장치의 자리를 가리킨다 ────────
# 종전 규칙(CLAUDE.md :30 "각 항목에 그것을 강제하는 게이트가 있는지를 함께 적는다")의 항목별
# 표기는 M1 이 주입 블록에서 뺐다(harness-lzs3.2.3) — 강제 장치의 전수 목록·한계는 하네스 루트
# docs/guardrails.md 가 단일 소유하고, 블록은 그 자리를 **가리키기만** 한다. 상시 비용(바이트)이
# 그 결정의 표적이었다. 그래서 이 검사가 보는 것은 둘이다:
#   ① `## 절대 금지` 절의 **최상위 불릿 전수**가 0건이 아니다 — 절이 옮겨가거나 파서가 낡으면
#      0건 파생이 '위반 없음' 이 아니라 '안 봤음' 이므로 실패로 읽는다.
#   ② 절이 강제 장치의 자리(`docs/guardrails.md`)를 가리킨다 — 항목별 표기를 뺀 대가가 이 포인터다.
#      포인터가 사라지면 "게이트가 있는가" 를 알 자리가 블록에서 통째로 사라진다.
# 극성 반전: 항목을 손으로 나열하지 않는다. 면제 칸은 두지 않는다.
#
# 부정 대조군(이 검사가 죽었는지): C6_BLOCK 으로 원문을 갈아끼운다. 포인터 문장을 지운 사본은
#   비-0 이어야 한다. **사본이 원본과 같거나 만들어지지 않으면 그 자체가 실패다.**
#
# 한계 — **포인터가 가리키는 문서의 내용은 보지 않는다.** 그 문서는 하네스 루트의 것이고 이 검사는
#   플러그인 트리를 본다. 종전의 "표기의 참·거짓은 보지 않는다" 와 같은 폭이다.
C6_DOC="${C6_BLOCK:-$BLOCK}"
C6_SECTION="## 절대 금지"
C6_POINTER="docs/guardrails.md"
check_c6() {
  local sec rows n f=0
  [[ -f "$C6_DOC" ]] || { echo "✗ C6 — $C6_DOC 이 없다 (검사 대상의 출처)"; return 1; }

  sec=$(awk -v sec="$C6_SECTION" '$0 == sec { inb = 1; next } inb && /^## / { inb = 0 } inb' "$C6_DOC")
  rows=$(printf '%s\n' "$sec" | grep -E '^- ')
  n=$(printf '%s' "$rows" | grep -c . )
  if [[ "$n" -eq 0 ]]; then
    echo "✗ C6 — $C6_DOC 에서 '$C6_SECTION' 절의 최상위 불릿을 0건 파생했다. 절이 옮겨갔거나 파서가 낡았다 — 둘 중 하나를 고쳐라. 0건 파생은 '위반 없음'이 아니라 '안 봤음'이다"
    return 1
  fi
  if ! printf '%s\n' "$sec" | grep -qF -- "$C6_POINTER"; then
    echo "✗ C6 $C6_DOC — '$C6_SECTION' 절이 강제 장치의 자리($C6_POINTER)를 가리키지 않는다. 항목별 게이트 표기를 뺀 대가가 이 포인터다 — 절 머리에 되살려라"
    f=1
  fi

  [[ "$f" -eq 0 ]] && echo "✓ C6 $C6_DOC '$C6_SECTION' 최상위 항목 ${n}건 · 강제 장치의 자리($C6_POINTER)를 가리킨다"
  return "$f"
}

# ── R40: repos.json 등재 이름 ↔ 클론 디렉토리 실재 (양방향) ───────────
# 규칙 원문(harness:develop 멀티 레포): "레포 등록과 클론은 scripts/repo.sh add
# <url> 이 함께 한다. 클론 위치는 ~/.harness-workspace/<이름> 으로 고정"
#
# **양방향이다 — 두 집합을 각각의 출처에서 파생한다.** scripts/repo.sh 의 cmd_list 는
#   `jq -r '.repos[].name'` 로 **등재부에서만** 파생해 클론 부재를 출력하고 rc 는 항상 0
#   이므로(repo.sh:170-189), 그것을 비-0 으로 바꾸는 것만으로는 절반이다. "클론은 있는데
#   등재가 없다" 쪽은 클론 루트에서 새로 파생해야 보인다.
#     방향 A  등재에 있는데 클론이 없다  → 세션을 열 클론이 없다(EnterWorktree 를 부를 자리가 없다)
#     방향 B  클론은 있는데 등재가 없다  → 게이트 명령(check)의 출처가 없는 트리가 남는다
#
# 0건 파생은 실패다. 양쪽 다 문자 그대로 적용한다. 명시적으로 실패시키는 이유는 **루트
#   경로가 어긋났을 때**(오타·HARNESS_CLONE_ROOT 오설정) 방향 B 가 조용히 0건이 되어
#   "불일치 없음"으로 읽히는 것을 가르기 위해서다.
#
# 극성 반전: 클론 루트의 디렉토리는 전수 파생하고, **레포가 아닌 것만** 사유와 함께
#   R40_KEEP 에 등재한다. 면제 키가 실제 클론 루트에 존재하는지 역방향으로 단언한다 —
#   없어진 면제는 낡은 면제다. 등재된 레포 이름을 면제로 쓰는 것도 함께 막는다(그러면
#   방향 A 가 그 레포를 안 본다). 지금 이 머신의 클론 루트에는 등재 밖 디렉토리가 없어
#   목록이 비어 있고, 그것이 정상이다 — 등재할 사유가 없다.
#
# 부정 대조군: HARNESS_CLONE_ROOT 로 가짜 루트를 준다 — 등재된 이름 하나가 빠진 루트는
#   방향 A 로, 등재에 없는 이름이 든 루트는 방향 B 로 각각 비-0 이어야 한다. **두 방향을
#   따로 흔들어야** 한 방향만 살아 있는 판을 잡는다(한쪽만 흔들면 나머지 방향은 0건인
#   채로 통과하고, 그 통과가 "봤는데 문제없음"으로 읽힌다).
R40_CLONE_ROOT="${HARNESS_CLONE_ROOT:-$HOME/.harness-workspace}"
R40_KEEP=()   # 클론 루트 안의 **레포가 아닌** 디렉토리. 등재할 때 사유를 함께 적는다
check_r40() {
  local names dirs missing extra n_names n_dirs k f=0

  need_hroot R40 || return 1
  [[ -f "$MANIFEST" ]] || { echo "✗ R40 — $MANIFEST 이 없다 (등재부의 출처)"; return 1; }
  names=$(jq -r '.repos[]?.name // empty' "$MANIFEST" | sort)
  n_names=$(printf '%s' "$names" | grep -c . )
  if [[ "$n_names" -eq 0 ]]; then
    echo "✗ R40 — $MANIFEST 에서 레포 이름을 0건 파생했다. 등재부가 비었거나 스키마가 바뀌었다 (위 R18 도 함께 볼 것)"
    return 1
  fi

  if [[ ! -d "$R40_CLONE_ROOT" ]]; then
    echo "✗ R40 — 클론 루트 $R40_CLONE_ROOT 가 없다. 등재 ${n_names}건 전부가 클론 없음이다 — scripts/repo.sh restore 로 복구하라 (루트 경로가 틀린 것이면 HARNESS_CLONE_ROOT 를 확인하라)"
    return 1
  fi
  # 클론 루트의 직속 디렉토리 전수. basename 만 취한다.
  dirs=$(find "$R40_CLONE_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|.*/||' | sort)
  n_dirs=$(printf '%s' "$dirs" | grep -c . )
  if [[ "$n_dirs" -eq 0 ]]; then
    echo "✗ R40 — 클론 루트 $R40_CLONE_ROOT 에서 디렉토리를 0건 파생했다. 루트가 비었거나 경로가 어긋났다 — 0건 파생은 '불일치 없음'이 아니라 '안 봤음'이다"
    return 1
  fi

  # 역방향 단언 ①: 면제 키가 실제 클론 루트에 있는가. 없으면 낡은 면제다.
  for k in ${R40_KEEP[@]+"${R40_KEEP[@]}"}; do
    if ! grep -qxF -- "$k" <<< "$dirs"; then
      echo "✗ R40 면제 '$k' 가 클론 루트($R40_CLONE_ROOT)에 없다 — 낡은 면제다. R40_KEEP 에서 빼라"
      f=1
    fi
  done
  # 역방향 단언 ②: 면제는 방향 B 에서만 걷어낸다. 등재된 이름을 면제로 가리면 방향 A 가 죽는다.
  for k in ${R40_KEEP[@]+"${R40_KEEP[@]}"}; do
    if grep -qxF -- "$k" <<< "$names"; then
      echo "✗ R40 면제 '$k' 가 $MANIFEST 에 등재된 이름이다 — 면제는 '레포가 아닌 디렉토리'에만 쓴다. 등재된 레포를 면제하면 방향 A 가 그 레포를 안 본다"
      f=1
    fi
  done

  missing=$(comm -23 <(printf '%s\n' "$names") <(printf '%s\n' "$dirs"))
  extra=$(comm -13 <(printf '%s\n' "$names") <(printf '%s\n' "$dirs"))
  for k in ${R40_KEEP[@]+"${R40_KEEP[@]}"}; do extra=$(printf '%s\n' "$extra" | grep -vxF -- "$k"); done

  while IFS= read -r k; do
    [[ -z "$k" ]] && continue
    echo "✗ R40 방향A — '$k' 는 $MANIFEST 에 등재됐는데 $R40_CLONE_ROOT/$k 클론이 없다. 세션을 열 클론이 없어 워크트리를 만들 수 없다 (EnterWorktree 를 부를 자리가 없다)"
    echo "    조치: scripts/repo.sh restore — 등재부에 있는데 클론이 없는 레포를 다시 클론한다"
    f=1
  done <<< "$missing"

  while IFS= read -r k; do
    [[ -z "$k" ]] && continue
    echo "✗ R40 방향B — $R40_CLONE_ROOT/$k 가 있는데 $MANIFEST 에 '$k' 등재가 없다. 게이트 명령(check)의 출처가 없는 트리다"
    echo "    조치: 대상 레포면 scripts/repo.sh add <url> --name $k 로 등재하고, 레포가 아니면 사유와 함께 이 검사의 R40_KEEP 에 등재하라"
    f=1
  done <<< "$extra"

  [[ "$f" -eq 0 ]] && echo "✓ R40 등재 ${n_names}건 ↔ 클론 루트 ${n_dirs}건 양방향 일치 (면제 ${#R40_KEEP[@]}건)"
  return "$f"
}

# ── 원장 JSON 의 출처 ─────────────────────────────────────────────────
# 부정 대조군은 이 파일을 갈아끼워 판정만 흔든다 — 원장 자체를 흔들면 되돌리기 비용이 크고,
# 다른 세션이 같은 원장을 쓰고 있다. 아래 S22·S24 만 쓴다 (R5·R-ACC 는 손대지 않는다 —
# 2번째 중복이고 레포 규율은 3번째에 추출하라고 한다).
ledger_json() {
  if [[ -n "${RULES_LEDGER_JSON:-}" ]]; then cat "$RULES_LEDGER_JSON"; return "$?"; fi
  bdl list --all --json -n 0 2>/dev/null
}

# ── S22: 한 워크트리에 두 태스크를 동시에 위임하지 않는다 ─────────────
# 규칙 원문(harness:develop 3-0): "**Do not delegate two tasks into one
# worktree at the same time.** The git staging area is a per-worktree shared resource, so even
# an `add` with explicit paths mixes with the other's `add` and `commit`." (실측 2026-08-21, 2회)
#
# **파생을 두 곳에서 한다 — 원장과 파일시스템.** 원장은 "같은 스토리 하위에 동시
#   in_progress 인 태스크" 를 내고(그 계수를 아래에서 **항상 출력한다** — 둘 이상인 칸은
#   위반이 아니어도 `·` 줄로 보인다), 파일시스템은 그 스토리에 실제로 존재하는 워크트리
#   수를 낸다. **비둘기집으로 판정한다**: 동시 in_progress 수가 워크트리 수를 넘으면 적어도
#   둘이 한 워크트리를 공유하는 것이 확정이다.
#
# **왜 "둘 이상"만으로 실패시키지 않는가.** ADR harness-pl7
#   의 S22 행은 "같은 스토리(= 워크트리)" 라는 등식 위에 서 있는데 **그 등식이 지금 참이
#   아니다** [실측 2026-08-28, 이 검사를 세우면서 관측 — bash 3.2.57 / macOS Darwin 25.6.0,
#   BEADS_DIR 미설정, CWD 는 하네스 루트: 스토리 harness-dg0 하위에 in_progress 태스크가
#   3건(harness-dg0.6.34 ·.36 ·.37)인데 같은 스토리의 워크트리가 4개 — harness-dg0 ·-a ·-b
#   ·-c]. 등식대로 판정하면 그 상태가 위반인데, S22 가 적은 **해악(워크트리 단위 공유
#   인덱스)은 성립하지 않는다.** 오탐은 규율을 압도하므로 실제 자원인 워크트리를 세는 쪽을
#   판정으로 삼는다.
#   손으로 적은 면제(스토리 ID 하나)로 덮지 않은 **1차 이유는 그것이 지금의 상태를 못 박는
#   것이기 때문이다** — 병렬은 끝나는데 면제는 남아, 정상 상태로 돌아온 다음 사람이 없는
#   위반을 면제받은 채로 간다. 이 레포에서는 그 낡음이 게이트로도 드러난다(역방향 단언을
#   **가변 집합**에 거는 관례라 낡은 면제 키가 실패한다 — 위 R40 의 R40_KEEP 이 그 형태다).
#   **뒤엣것은 관례에 기댄 부수 효과이지 논거가 아니다**: 정적 집합에 거는 면제는 낡아도
#   실패하지 않는다. 이 판정의 근거는 실제 자원(워크트리)을 세는 쪽이 옳다는 것 하나다.
#
# **repo 단위로 가른다.** 태스크의 repo: 라벨은 정확히 1개이고(위 R5 가 강제한다) 워크트리도
#   레포마다 따로 생기므로 대조 단위는 (스토리, 레포)다. 스토리로만 묶으면 멀티 레포
#   스토리에서 서로 다른 워크트리의 태스크가 한 칸에 섞인다. 세션 단위도 (스토리, 레포)다
#   (harness:develop 1절) — 스토리 bead 의 `ACTOR: <레포> <값>` note 가 레포마다 하나씩
#   붙는데, **이 검사는 그 note 를 읽지 않는다.** 레인은 태스크의 assignee 에서 파생하므로
#   fe 의 태스크가 sess-a, be 의 태스크가 sess-b 로 잡혀 있어도 칸이 다르다 — 아래 check_s22 의
#   멀티 레포 픽스처가 그것을 판정 도달로 든다.
#
# 한계 — **위임했는데 claim 하지 않으면 안 보인다.** 판정의 재료가 status=in_progress 이고
#   그 전이를 만드는 것은 `bd update --claim` 이다. develop 3-0 의 claim 규율이 함께 서야
#   성립한다 (natural-language(harness-pl7) 의 S22 행이 적은 한계와 같다).
# 한계 — **워크트리 수는 상한이지 배치가 아니다.** 워크트리가 3개 있고 태스크 2건이 그중
#   같은 하나에 위임돼 있으면 통과한다. 원장에 태스크↔워크트리 대응이 없어 확정할 수 없고,
#   확정할 수 없는 것을 추정으로 막지 않는다.
# **같은 actor(assignee)의 태스크는 한 레인이다** [harness-2a5.4 배치 verify-code 1회차 MUST FIX 2,
#   오케스트레이터 결정 2026-08-28]. 배치 모드(develop 3절)는 위임 전에 목록의 태스크 전부를
#   같은 actor 로 claim 하고 implementer 한 명이 순차로 돈다 — implementer 는 bd 쓰기가 note
#   뿐이라(guard.sh r_impl_bd) 태스크마다 claim 을 늦출 수 없고, 그 상태에서는 표시 없는
#   in_progress 가 N건이라 태스크 수로 세면 배치 중에 지킬 수 없는 검사가 된다. S22 의
#   대상은 **두 에이전트가 한 워크트리**이고 한 actor 의 순차 작업은 그 대상이 아니므로,
#   비둘기집의 분자는 태스크 수가 아니라 **서로 다른 assignee 의 수**다. assignee 가 빈
#   태스크는 저마다 한 레인으로 센다(엄격한 쪽 — claim 없는 in_progress 를 한 레인으로
#   합치면 미탐이 된다). 자기 시험은 아래 check_s22 의 actor 픽스처 둘이 든다.
# 한계 — **대상 0건을 실패로 읽지 않는다.** 갓 세팅한 트리는 스토리가 없어 파생이 0건이고,
#   그것을 실패로 만들면 skills/setup/SKILL.md 1.7 의 A 검증표(`rules-check.sh` rc 0)가
#   무조건 막힌다. 대신 **파생이 의존하는 필드를 직접 단언하고**(위 ledger_fields_ok — R5 와
#   같은 함수를 쓴다) 대상 건수를 항상 출력한다. **그 단언이 무엇을 못 잡는지는 그 함수의
#   주석이 실측으로 든다** — 요약하면 `parent` 키 이름 자체가 바뀌는 스키마 변경은 못 잡고,
#   그것은 R5 도 마찬가지다(세 검사가 공유하는 구멍이지 이 검사가 R5 보다 약한 것이 아니다).
#
# 부정 대조군: RULES_LEDGER_JSON 으로 원장 JSON 을 갈아끼운다 — 워크트리가 없는 스토리에
#   in_progress 2건을 넣은 사본은 비-0 이어야 한다. 사본의 실재와 원본과의 차이를 먼저
#   단언하고, **넣은 줄이 실제로 파생 집합에 들어오는지**도 함께 봐라(실재·차이는 대조군
#   성립의 필요조건이지 충분조건이 아니다 — 위 R-REM 의 같은 항목이 든 실측 참조).
S22_CLONE_ROOT="${HARNESS_CLONE_ROOT:-$HOME/.harness-workspace}"
# 스토리 ID 로 만들어진 워크트리 수. harness:develop 2절은 EnterWorktree 의 name 을 `<스토리ID>`
# 로 두게 하고, 병렬 진행은 `<스토리ID>-<접미>` 를 함께 쓴다 — 둘 다 같은 스토리의 워크트리다.
# 한계 — **`git worktree list` 가 아니라 디렉토리 실재를 센다.** 정리되지 않은 잔여
#   디렉토리(git 은 모르는데 파일시스템에는 남은 것)가 분모를 부풀려 **검출을 약화**시킨다.
#   미탐 쪽이라 안전한 방향이라 그대로 두지만, 이 레포에 정리 스크립트가 둘 있다는 것
#   (scripts/workspace-cleanup.sh)은 잔여가 실재하는 상태라는 뜻이다.
#   좁히려면 각 레포 클론에서 `git worktree list` 를 파생으로 써야 하는데, 그러면 이 검사가
#   클론마다 git 을 실행하게 된다(지금은 파일시스템만 본다).
s22_wt_count() {  # s22_wt_count <레포> <스토리ID>
  local d="$S22_CLONE_ROOT/$1/.claude/worktrees" n=0 p
  [[ -d "$d" ]] || { echo 0; return 0; }
  for p in "$d/$2" "$d/$2"-*; do [[ -d "$p" ]] && n=$((n + 1)); done
  echo "$n"
}
# **검증 대기(VERIFY_PENDING)는 동시 위임이 아니다.** 배치 모드(develop 3절)는 구현이 끝난
#   태스크를 닫지 않고 마지막 note 로 `VERIFY_PENDING: <커밋>` 을 남긴 채 in_progress 로 둔다.
#   그 태스크에는 지금 쓰는 implementer 가 없으므로 S22 가 막는 해악(공유 인덱스)이 성립하지
#   않는다 — 마지막 비어 있지 않은 note 줄이 그 표시로 시작하는 태스크는 세지 않는다. 판정은
#   hooks/stop-resume.sh 4b 와 같다(같은 표시, 같은 "마지막 줄"). 실측 2026-08-28:
#   배치 모드에서 harness-2a5.3.1·2a5.1.2 가 동시 in_progress 로 이 검사가 실패했다.
#   **아래 s22_judge 는 합성 원장으로 먼저 자기 판정을 시험한다** — 표시 없는 둘은 종전대로
#   실패하고(부정 대조군), 같은 둘에 표시만 붙이면 통과한다(판정 도달 — 표시를 읽는 줄이
#   죽으면 앞것과 같은 값이 나와 여기서 잡힌다). 두 픽스처는 notes 만 다르다.
s22_judge() {  # s22_judge <원장JSON> → 판정 줄 출력, rc = 위반 여부
  local json="$1" rows f=0 story repo cnt ids wt
  # (스토리, repo 라벨) 마다 동시 in_progress 태스크가 2건 이상인 칸 — 원장 쪽 파생.
  rows=$(printf '%s' "$json" | jq -r '
    (map({key: .id, value: .}) | from_entries) as $byid
    | def nearest_epic:
        [limit(16; recurse(if .parent then $byid[.parent] else empty end))]
        | map(select(.issue_type == "epic")) | first;
      def verify_pending:
        ((.notes // "") | split("\n") | map(select(test("\\S"))) | last // "") | startswith("VERIFY_PENDING");
      [ .[]
        | select(.issue_type == "task" and .status == "in_progress" and (verify_pending | not))
        | . as $t | (nearest_epic) as $s
        | select($s != null)
        | { s: $s.id,
            r: (((($t.labels // []) | map(select(startswith("repo:"))) | first) // "repo:(없음)") | ltrimstr("repo:")),
            lane: (($t.assignee // "") | if . == "" then "(미지정)" + $t.id else . end),
            id: $t.id } ]
    | group_by([.s, .r]) | map(select(length >= 2))
    | .[] | "\(.[0].s)\t\(.[0].r)\t\(length)\t\([.[].lane] | unique | length)\t\([.[].id] | sort | join(","))"')

  while IFS=$'\t' read -r story repo cnt lanes ids; do
    [[ -z "$story" ]] && continue
    wt=$(s22_wt_count "$repo" "$story")
    # 레인이 하나면 공유할 상대가 없다 — 워크트리 수와 무관하게 위반이 아니다(actor 픽스처는 워크트리 0).
    if [[ "$lanes" -ge 2 && "$lanes" -gt "$wt" ]]; then
      echo "✗ S22 $story (repo:$repo) — 동시 in_progress ${cnt}건이 actor ${lanes}명인데 이 스토리의 워크트리는 ${wt}개다: $ids"
      echo "    비둘기집: 적어도 두 actor 가 한 워크트리를 공유한다. git 스테이징 영역이 워크트리 단위 공유 자원이라 경로를 지정해 add 해도 상대의 add·commit 과 섞인다 (harness:develop 3-0, 실측 2026-08-21 2회)"
      echo "    조치: 하나만 남기고 나머지를 되돌리거나(ledger.sh update <ID> --status open), 스토리 워크트리를 나눠라. 같은 actor 의 순차 배치는 세지 않으니 claim 의 actor 가 갈렸는지 봐라. 배치 모드로 구현만 끝난 것이면 ledger.sh note <ID> \"VERIFY_PENDING: <커밋 해시>\" 를 남겨라 — 그 표시도 세지 않는다"
      f=1
    else
      echo "  · S22 $story (repo:$repo) — 동시 in_progress ${cnt}건 · actor ${lanes}명 / 워크트리 ${wt}개 (공유 확정 아님): $ids"
    fi
  done <<< "$rows"
  return "$f"
}
check_s22() {
  local json rc n_task n_epic n_vp f=0
  # 자기 판정 시험 — 실원장과 무관한 합성 원장. 레포 이름은 클론 루트에 없는 것이라 워크트리 0.
  local fx_s='{"id":"fx-s","issue_type":"epic","status":"in_progress"}'
  local fx_plain fx_marked
  fx_plain="[$fx_s,{\"id\":\"fx-a\",\"issue_type\":\"task\",\"status\":\"in_progress\",\"parent\":\"fx-s\",\"labels\":[\"repo:fx-none\"]},{\"id\":\"fx-b\",\"issue_type\":\"task\",\"status\":\"in_progress\",\"parent\":\"fx-s\",\"labels\":[\"repo:fx-none\"]}]"
  fx_marked=$(printf '%s' "$fx_plain" | jq -c '(.[] | select(.issue_type == "task")).notes = "구현 기록\n\nVERIFY_PENDING: 0000000"')
  if [[ -z "$fx_marked" || "$fx_plain" == "$fx_marked" ]]; then
    echo "✗ S22 자기 시험 — 표시 픽스처가 만들어지지 않았거나 원본과 같다 (jq 변형 실패). 판정 시험이 공허하다"
    return 1
  fi
  if s22_judge "$fx_plain" >/dev/null; then
    echo "✗ S22 부정 대조군 — 표시 없는 in_progress 둘이 한 스토리(워크트리 0)에 있는데 통과했다. 파생이 죽었다"
    return 1
  fi
  if ! s22_judge "$fx_marked" >/dev/null; then
    echo "✗ S22 판정 도달 — 같은 둘에 VERIFY_PENDING 표시만 붙였는데 여전히 실패한다. 표시를 읽는 줄이 죽었다"
    return 1
  fi
  # 레인 판정 — 같은 actor 의 둘은 한 레인이라 통과하고(판정 도달), actor 가 갈린 둘은 종전대로
  # 실패한다(부정 대조군 — 레인 계수가 항상 1 로 죽으면 여기서 잡힌다). 두 픽스처는 assignee 만 다르다.
  local fx_one_actor fx_two_actors
  fx_one_actor=$(printf '%s' "$fx_plain" | jq -c '(.[] | select(.issue_type == "task")).assignee = "fx-actor"')
  fx_two_actors=$(printf '%s' "$fx_plain" | jq -c '(.[] | select(.id == "fx-a")).assignee = "fx-actor-1" | (.[] | select(.id == "fx-b")).assignee = "fx-actor-2"')
  if [[ -z "$fx_one_actor" || -z "$fx_two_actors" || "$fx_one_actor" == "$fx_plain" || "$fx_one_actor" == "$fx_two_actors" ]]; then
    echo "✗ S22 자기 시험 — actor 픽스처가 만들어지지 않았거나 서로 같다 (jq 변형 실패). 레인 판정 시험이 공허하다"
    return 1
  fi
  if ! s22_judge "$fx_one_actor" >/dev/null; then
    echo "✗ S22 판정 도달 — 같은 actor 의 in_progress 둘(한 레인)이 워크트리 0 의 스토리에 있는데 실패한다. 레인을 세는 줄이 죽었다"
    return 1
  fi
  if s22_judge "$fx_two_actors" >/dev/null; then
    echo "✗ S22 부정 대조군 — actor 가 다른 in_progress 둘이 한 스토리(워크트리 0)에 있는데 통과했다. 레인 계수가 죽었다"
    return 1
  fi
  # 멀티 레포 — 두 레포를 문 스토리에 레포별 ACTOR note 둘(fe sess-a · be sess-b)이 있고 각 레포의
  # 태스크가 그 actor 로 잡혀 있으면 칸이 (스토리, fe)·(스토리, be) 로 갈려 위반이 아니다(판정 도달).
  # 위 fx_two_actors 와 다른 점은 repo 라벨뿐이다 — 같은 레포였으면 부정 대조군 그대로 실패한다.
  local fx_multi
  fx_multi=$(printf '%s' "$fx_two_actors" | jq -c '(.[] | select(.id == "fx-s")).notes = "ACTOR: fe fx-actor-1\nACTOR: be fx-actor-2" | (.[] | select(.id == "fx-a")).labels = ["repo:fe"] | (.[] | select(.id == "fx-b")).labels = ["repo:be"]')
  if [[ -z "$fx_multi" || "$fx_multi" == "$fx_two_actors" ]]; then
    echo "✗ S22 자기 시험 — 멀티 레포 픽스처가 만들어지지 않았거나 원본과 같다 (jq 변형 실패). (스토리, 레포) 판정 시험이 공허하다"
    return 1
  fi
  if ! s22_judge "$fx_multi" >/dev/null; then
    echo "✗ S22 판정 도달 — 레포가 갈린 actor 둘(fe sess-a · be sess-b)이 한 스토리에 있는데 실패한다. (스토리, 레포) 로 가르는 줄이 죽었다"
    return 1
  fi

  need_hroot S22 || return 1
  json=$(ledger_json); rc=$?
  if [[ "$rc" -ne 0 || -z "$json" ]]; then
    echo "✗ S22 — 원장 조회 실패 (rc=$rc, 하네스 루트 $HROOT)" >&2
    return 1
  fi

  # 파생이 의존하는 필드를 먼저 단언한다 (위 "대상 0건" 한계의 대체 — R5 와 같은 자리를
  # 공유한다. 잡는 것과 못 잡는 것은 ledger_fields_ok 의 주석이 실측으로 든다).
  ledger_fields_ok S22 "$json" || return 1
  n_task=$(printf '%s' "$json" | jq -r '[.[] | select(.issue_type == "task" and .status == "in_progress")] | length')
  n_epic=$(printf '%s' "$json" | jq -r '[.[] | select(.issue_type == "epic")] | length')
  n_vp=$(printf '%s' "$json" | jq -r '[.[] | select(.issue_type == "task" and .status == "in_progress" and (((.notes // "") | split("\n") | map(select(test("\\S"))) | last // "") | startswith("VERIFY_PENDING")))] | length')

  s22_judge "$json" || f=1

  [[ "$f" -eq 0 ]] && echo "✓ S22 동시 in_progress 의 actor 수가 워크트리 수를 넘는 (스토리, 레포) 없음 (스토리 ${n_epic}건 · in_progress 태스크 ${n_task}건, 그중 검증 대기 ${n_vp}건은 세지 않음 · 같은 actor 는 한 레인)"
  return "$f"
}

# ── S24: 하위가 전부 종료 상태인데 열려 있는 스토리 ───────────────────
# 규칙 원문(harness:develop 4-2): "Once every task is one of closed, blocked,
# or **deferred** … close the milestones and the story."
#
# **bd 의 계산과 반대 방향이다.** bd 는 `deferred` 를 열린 하위·블로커로 세므로
#   (harness:develop "결정 상태": 마감에 `bd close --force`·`bd dep remove` 우회가
#   필요하다) 그 계산에 맡기면 이 상태가 영원히 "아직 열린 하위가 있다"로 보인다. 그래서
#   종료 상태 집합을 이 검사가 직접 든다 — closed · blocked · deferred 셋. 같은 규율이
#   요구하는 취급("안 하기로 한 것은 남은 일이 아니다")이 기계로 표현되는 자리가 여기이고,
#   natural-language(harness-pl7) 가 R14 의 "완료 조건 절반은 S24 가 덮는다"고 적은 것이 이 뜻이다.
#
# 대상: **하위를 하나라도 가진 epic 전수**. 하위가 없는 epic 은 아직 분해되지 않은 스토리라
#   "전부 끝났다"가 성립하지 않는다 — 빈 집합에 대한 전칭은 자동으로 참이 되어 갓 만든
#   스토리를 전건 위반으로 만든다(0건 통과의 거울상이다).
# 열림: epic 의 status 가 open·in_progress 인 경우. blocked·deferred·closed 스토리는 지금
#   닫을 대상이 아니다.
#
# 한계 — **대상 0건을 실패로 읽지 않는다.** 사유와 대체는 위 S22 의 같은 항목과 같다
#   (setup/SKILL.md 1.7 의 A 검증표 · 공유 단언 ledger_fields_ok). **그 단언이 `parent` 키
#   이름 자체의 변경은 못 잡는다** — 이 검사의 파생이 전적으로 `parent` 위에 서므로 그때는
#   "하위를 가진 스토리 0건" 으로 조용히 통과한다. 실측과 사유는 그 함수의 주석이 든다.
# 한계 — **"닫아야 한다"까지만 말한다.** develop 4-1 의 통합 검증(멀티 레포)과 4-2 의 결과
#   요약 note 가 남았는지는 보지 않는다. 그쪽은 자연어라 기계가 볼 수 없다.
#
# 부정 대조군: RULES_LEDGER_JSON 으로 원장 JSON 을 갈아끼운다 — 열린 스토리의 하위를 전부
#   closed 로 바꾼 사본은 비-0 이어야 한다.
check_s24() {
  local json rc rows n_cov f=0 eid est n open
  need_hroot S24 || return 1
  json=$(ledger_json); rc=$?
  if [[ "$rc" -ne 0 || -z "$json" ]]; then
    echo "✗ S24 — 원장 조회 실패 (rc=$rc, 하네스 루트 $HROOT)" >&2
    return 1
  fi

  ledger_fields_ok S24 "$json" || return 1

  # `<epic id>\t<epic status>\t<하위 수>\t<종료 아닌 하위 수>` — 하위를 가진 epic 전수.
  rows=$(printf '%s' "$json" | jq -r '
    . as $all
    | (map({key: .id, value: .}) | from_entries) as $byid
    | (map(select(.parent != null)) | group_by(.parent)
       | map({key: .[0].parent, value: [.[].id]}) | from_entries) as $kids
    | def desc($id): ($kids[$id] // [])[] as $c | $c, desc($c);
      [ $all[] | select(.issue_type == "epic") | . as $e
        | [ desc($e.id) ] as $d
        | select(($d | length) > 0)
        | { id: $e.id, st: $e.status, n: ($d | length),
            open: ([ $d[] | $byid[.].status
                     | select(. != "closed" and . != "blocked" and . != "deferred") ] | length) } ]
    | .[] | "\(.id)\t\(.st)\t\(.n)\t\(.open)"')
  n_cov=$(printf '%s' "$rows" | grep -c . )

  while IFS=$'\t' read -r eid est n open; do
    [[ -z "$eid" ]] && continue
    [[ "$est" == "open" || "$est" == "in_progress" ]] || continue
    [[ "$open" -eq 0 ]] || continue
    echo "✗ S24 $eid — 하위 ${n}건이 전부 closed·blocked·deferred 인데 스토리가 $est 다"
    echo "    조치: harness:develop 4 의 스토리 마무리로 넘어가라 — 결과 요약을 ledger.sh note 로 남기고 마일스톤·스토리를 닫는다. beads 는 deferred 를 열린 하위로 세므로 마감에 'ledger.sh close $eid --force' 가 필요할 수 있고, 그 우회 사유를 close reason 에 적는다 (harness:develop '결정 상태')"
    f=1
  done <<< "$rows"

  [[ "$f" -eq 0 ]] && echo "✓ S24 하위가 전부 종료 상태인데 열려 있는 스토리 없음 (하위를 가진 스토리 ${n_cov}건)"
  return "$f"
}

# ── 모집단: 항상 로드되는 파일 집합 ──────────────────────────────────
# R-DATE·R-BEAD·R-DUP·R-BUDGET 이 공유한다. 플러그인에서 **상시 로드는 주입 블록 하나**다 —
# SessionStart 훅(hooks/session-context.sh)이 hooks/session-context.md 를 통째로 additionalContext
# 로 싣고, 플러그인은 CLAUDE.md 도 rules 도 만들지 않는다(그 둘은 플러그인 구성 요소가 아니다 —
# 스토리 harness-lzs3 "현재 상태" 실측). 그래서 손으로 적은 경로 하나가 곧 전수이고, 집합이
# 넓어질 길은 훅이 다른 파일을 싣는 것뿐이다 — 그때는 session-context.sh 와 함께 이 파생을 고친다.
# 대상 단언: 파일이 실재하고 비어 있지 않다(0바이트 블록은 '안 봤음' 이다).
ALWAYS_LOADED=()
ALWAYS_LOADED_STR=""
always_loaded_derive() {
  if [[ ! -s "$BLOCK" ]]; then
    echo "✗ 상시 로드 파생 — 주입 블록 $BLOCK 이 없거나 비었다. 훅이 싣는 파일이 옮겨졌으면 hooks/session-context.sh 와 함께 이 파생을 고쳐라"
    return 1
  fi
  ALWAYS_LOADED=("$BLOCK")
  ALWAYS_LOADED_STR="$BLOCK"
  return 0
}

# ── R-DATE: 항상 로드되는 문서에 YYYY-MM-DD 가 없다 ──────────────────
# 왜: 날짜는 문서를 낡게 만들고 매 세션 토큰을 낸다. 시점이 필요한 기록의 단일 출처는
# 원장이다 — 문서의 것은 사본이고 사본은 원장이 갱신돼도 따라오지 않는다 (harness-dg0.6.30).
#
# 자기참조 회피는 **모집단 정의로** 닫혀 있다: 이 스크립트는 상시 로드 문서가 아니므로
# 여기 적힌 날짜 패턴은 애초에 검사 대상이 아니다. 값(패턴 문자열)을 고쳐 피하지 않는다.
#
# 면제 — 지금 없다. 상시 로드 문서에 날짜가 남아야 하는 자리가 하나도 없다.
RDATE_KEEP=()

check_rdate() {
  local hits n k c scope
  always_loaded_derive || return 1

  hits=$(grep -nE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "${ALWAYS_LOADED[@]}" 2>/dev/null)

  # 역방향 단언 — 면제 키가 실제 후보에 잡히는가. 0건 면제는 낡은 면제다.
  if [[ "${#RDATE_KEEP[@]}" -gt 0 ]]; then
    for k in "${RDATE_KEEP[@]}"; do
      c=$(printf '%s\n' "$hits" | grep -cF -- "$k")
      if [[ "$c" -lt 1 ]]; then
        echo "✗ R-DATE 면제(앵커) '$k' 가 후보에서 0건이다 — 낡은 면제다. 면제표에서 빼라"
        return 1
      fi
      hits=$(printf '%s\n' "$hits" | grep -vF -- "$k")
    done
  fi

  n=$(printf '%s' "$hits" | grep -c .)
  scope="상시 로드 ${#ALWAYS_LOADED[@]}파일[${ALWAYS_LOADED_STR}] · 면제 ${#RDATE_KEEP[@]}앵커"
  if [[ "$n" -ne 0 ]]; then
    printf '%s\n' "$hits" | while IFS= read -r line; do
      [[ -n "$line" ]] && echo "✗ R-DATE $(printf '%s' "$line" | cut -c1-140)"
    done
    echo "✗ R-DATE 날짜 잔존 ${n}건 ($scope). 시점은 원장에 두고 문서에는 bead ID 참조만 남겨라"
    return 1
  fi
  echo "✓ R-DATE 날짜 잔존 0건 ($scope)"
  return 0
}

# ── R-BEAD: 상시 로드 문서가 가리키는 bead ID 가 원장에 실재한다 ─────
# 왜: 근거를 원장 참조로 옮기면 참조가 끊어지는 순간 이유가 통째로 사라진다 — 문서에는
# 요약만 남으므로 죽은 참조는 조용한 손실이다 (harness-dg0.6.30).
#
# 면제 — 패턴이 걷어 오지만 원장 ID 가 아닌 토큰. 파일시스템 이름이라 원장에 없는 것이
# 정상이다. 각 키가 실제 후보에 잡히는지 역방향으로 단언한다.
RBEAD_KEEP=(
  "harness-workspace"  # ~/.harness-workspace — 대상 레포 클론 루트의 디렉토리 이름
)
# 패턴 자기 시험 — 주입 블록은 bead 참조를 하나도 안 가질 수 있다(가리키는 문서다). 그때 후보 0건은
# '위반 없음' 인데, 패턴이 죽어도 같은 0건이라 구분되지 않는다. 합성 문자열로 패턴이 산 것을 먼저 못박는다.
RBEAD_PATTERN='harness-[0-9a-z]+(\.[0-9]+)*'
rbead_pattern_alive() {
  [[ "$(printf 'x harness-ab1.2.3 y' | grep -ohE "$RBEAD_PATTERN")" == "harness-ab1.2.3" ]] \
    && [[ -z "$(printf 'no ids here' | grep -ohE "$RBEAD_PATTERN")" ]]
}

check_rbead() {
  local json rc ids cand_all cand k c id missing n scope
  always_loaded_derive || return 1

  rbead_pattern_alive || { echo "✗ R-BEAD — bead ID 패턴 자기 시험 실패 — 패턴이 죽었다. 후보 0건이 '위반 없음' 으로 보고된다"; return 1; }
  need_hroot R-BEAD || return 1
  json=$(bdl list --all --json -n 0 2>/dev/null); rc=$?
  if [[ "$rc" -ne 0 || -z "$json" ]]; then
    echo "✗ R-BEAD — ledger.sh list 실패 (rc=$rc): 원장 미가용 (하네스 루트 $HROOT)" >&2
    return 1
  fi
  ids=$(printf '%s' "$json" | jq -r '.[] | select(has("id")) | .id')
  if [[ -z "$ids" ]]; then
    echo "✗ R-BEAD — 원장에서 id 를 한 건도 못 뽑았다. 원장의 JSON 스키마가 바뀌었으면 이 파생을 고쳐라 (안 고치면 참조 전부가 '없는 bead' 로 뒤집힌다)"
    return 1
  fi

  cand_all=$(grep -ohE "$RBEAD_PATTERN" "${ALWAYS_LOADED[@]}" 2>/dev/null | sort -u)

  # 역방향 단언 — 면제 키가 실제 후보에 있는가.
  # 개수 가드가 필요하다: bash 3.2 + set -u 에서 빈 배열의 "${A[@]}" 는 unbound 로 즉시 죽는다.
  # 위 메시지가 "면제표에서 빼라"고 지시하므로 전 키가 낡으면 그 지시를 따른 결과가 빈 배열이다.
  cand="$cand_all"
  if [[ "${#RBEAD_KEEP[@]}" -gt 0 ]]; then
    for k in "${RBEAD_KEEP[@]}"; do
      c=$(printf '%s\n' "$cand_all" | grep -cxF -- "$k")
      if [[ "$c" -lt 1 ]]; then
        echo "✗ R-BEAD 면제 '$k' 가 후보에서 0건이다 — 낡은 면제다. 면제표에서 빼라"
        return 1
      fi
      cand=$(printf '%s\n' "$cand" | grep -vxF -- "$k")
    done
  fi
  n=$(printf '%s' "$cand" | grep -c .)
  # 후보 0건은 정상이다 — 주입 블록은 자리를 가리키는 문서라 bead 를 인용하지 않을 수 있다.
  # 패턴이 죽어서 0건인 경우는 위 자기 시험이 먼저 잡는다.

  missing=""
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    printf '%s\n' "$ids" | grep -qxF -- "$id" || missing="${missing}${id}"$'\n'
  done <<< "$cand"

  scope="상시 로드 ${#ALWAYS_LOADED[@]}파일[${ALWAYS_LOADED_STR}] · 참조 ${n}건 · 면제 ${#RBEAD_KEEP[@]}키"
  if [[ -n "$missing" ]]; then
    printf '%s' "$missing" | while IFS= read -r id; do
      [[ -n "$id" ]] && echo "✗ R-BEAD '$id' 가 원장에 없다 — 죽은 참조다. 문서의 근거가 통째로 사라진다"
    done
    echo "✗ R-BEAD 죽은 참조 $(printf '%s' "$missing" | grep -c .)건 ($scope)"
    return 1
  fi
  echo "✓ R-BEAD 죽은 참조 0건 ($scope 전부 원장에 실재)"
  return 0
}

# ── R-WAIT: 사람 대기 신호 목록의 단일 소유 ──────────────────────────
# 왜: 목록이 두 곳에 있으면 서로의 부분집합이 아니게 갈라지고, 어느 쪽을 읽느냐로
# 결론이 달라진다. 실제로 갈라져 있던 상태가 harness-dg0.6.39 의 대상이었고, 한쪽은
# "모든 신호" 라고 적고도 한 신호를 빠뜨린 채였다.
#
# 두 축을 본다. 종전 결함이 정확히 이 둘로 나뉜다.
#  ① 단일 소유 절이 살아 있고 **신호를 전부 들고 있다.** 빠지면 그 신호를 낸 역할의
#     결과가 아무도 정하지 않은 채 사라진다. 단언은 절의 **표 행**에 건다 — 절 전체를
#     보면 산문에 한 번 언급된 것만으로 만족돼, 표에서 신호가 빠져도 통과한다
#     (실측: 표에서 SCOPE_EXCESS 행을 지운 사본이 rc=0 으로 통과했다).
#  ② 그 절 **밖에서 목록을 다시 적은 줄이 없다.** 다시 적히는 순간 갈라짐이 시작된다.
#
# 후보 판정 — 한 줄에 "사람 대기" 가 있고 그 줄이 신호를 **둘 이상** 나열할 때만
# 발동한다. 신호 하나를 처리하는 줄(develop 의 DECISION_NEEDED 처리 등)은 집합을
# 정의하는 것이 아니라 받은 신호를 분배하는 자리라 후보가 아니다.
#
# 한계(확인한 것):
#  · 다른 낱말로 적은 나열("사람에게 간다")과, 표로 쪼개 한 줄에 신호가 하나씩만
#    오는 나열은 못 본다. 종전에 갈라졌던 두 자리가 둘 다 한 줄 나열이라 그 형태를
#    잡는 것이 이 검사의 대상이고, 그 밖의 형태는 잡지 않는다.
#    이 한계는 실물 2건과 겹친다(두 자리는 harness-g88o.3.2 의 영어화 뒤 문면이다):
#    verify-implement/SKILL.md 의 "DEVIATION · DECISION_NEEDED or a value that is not
#    in the list → report to the user and wait" 와 verify-code/SKILL.md 의
#    "DECISION_NEEDED or a value that is not in the list → safe exit" 는
#    신호를 둘 이상 들지만 1단 검색어(WAIT_TRIGGER)가 없어 안 잡힌다. 둘 다
#    자기 역할의 SIGNAL 값을 분배하는 자리라 고칠 대상이 아니고(단일 소유 절이 그
#    사실을 적는다), 면제표에 등재할 수도 없다 — 후보에 오르지 않으므로 역방향 단언이
#    0건으로 죽는다. 낱말을 늘려 잡으면 이 둘이 오탐으로 들어온다.
#  · 면제 앵커는 파일 한정이 아니라 후보 줄 전역의 부분문자열이다(R-REM 과 같다).
#    역방향 단언은 ≥1건만 보므로 과소만 잡고 과폭은 못 잡는다.
#  · WAIT_TOKENS 는 화이트리스트라 *토큰→표* 방향만 단언된다. 표에 행을 더하고 여기
#    등재하지 않으면 그 신호만으로 이뤄진 절 밖 나열이 조용히 통과한다(새 신호의
#    기본값이 "검사 안 됨" — 극성 반전 규율과 어긋나는 방향이다). 그래도 이쪽을 고른
#    것은, 표에서 토큰을 파생하면 ① 단언이 "표가 표를 든다" 가 되어 공허해지기
#    때문이다. 두 방향 중 하나만 살아남으며 지금 것이 의미 있는 쪽이다 — 뒤집지 마라.
#  · **언어 교차**: 이 검사는 스캔 대상의 문면을 낱말로 판다. 대상에 영어 문서가 섞이면
#    한국어 낱말만으로는 그 파일이 후보에 오르지 않고, 그 침묵이 통과로 읽힌다. 그래서
#    1단 검색어와 서술어 토큰 셋에 영어 대안을 함께 든다. 그 영어 낱말을 안 쓰는 번역은
#    다시 안 보이게 되므로 **낱말의 단일 소유는 아래 WAIT_TRIGGER·WAIT_TOKENS 자신이다.**
#    WAIT_OWNER 의 절이 드는 것은 신호 *목록*이고 낱말의 영어 표기까지는 들지 않는다 —
#    한때 그 절에도 같은 목록을 두었으나 두 목록이 곧 어긋났고(문서 셋 vs 여기 넷), 문서
#    쪽을 따른 번역의 줄을 이 검사가 못 보게 된다. 번역하는 쪽은 여기를 읽는다.
#
# 부정 대조군(이 검사가 죽었는지): RWAIT_SCAN_EXTRA 에 파일 경로 하나를 주면 스캔 대상에
#   더해진다(R-DUP 의 RDUP_SCAN_EXTRA 와 같은 규약). 영어 스킬 사본에 신호 둘 이상을 한 줄에
#   나열한 줄을 주입해 그 경로로 주면 그 사본의 경로:줄을 지목하며 rc 1 이어야 한다.
#   트리 안의 skills/ 에 사본을 두지 않아도 되게 하려는 것이 이 통로의 목적이다.
WAIT_OWNER="skills/develop/SKILL.md"
WAIT_ANCHOR="## 사람 대기"
# 1단 검색어. 스캔 대상에 영어 문서가 섞이면 한국어 낱말만으로는 후보가 0건이 되고,
# 그 0건은 "나열이 없다" 가 아니라 "안 봤다" 다. 그래서 영어 표기를 함께 든다 — ERE 이고
# grep -i 로 쓰므로 대소문자는 가리지 않는다. **영어 문서가 이 절을 가리킬 때 쓸 낱말은
# 여기가 단일 소유다** — 문서에 같은 목록을 다시 적지 않는다.
WAIT_TRIGGER='사람 대기|human wait'
# 화이트리스트. 각 항목은 ERE 이고, 단일 소유 절이 **전부** 들고 있어야 한다.
# 영어 대안을 함께 든 항목이 셋 있다 — 신호 이름이 아니라 서술어라 번역에서 낱말이
# 통째로 바뀌는 것들이다. 나머지 넷은 SCREAMING_SNAKE 식별자·고유명사라 번역을 타지
# 않는다. **쓸 영어 표기의 단일 소유가 여기다** — 번역하는 쪽이 읽을 자리이고, 문서에
# 같은 목록을 두면 두 목록이 어긋난다.
# 한계(확인한 것): 역방향 단언은 한국어 대안이 표 행에 걸려 성립하므로 영어 대안이 늘어도
# 흔들리지 않는다 — 뒤집어 말하면 **영어 표기 쪽은 역방향으로 단언되지 않는다.** 오타가
# 나면 그 표기를 쓴 줄을 조용히 못 보게 된다. 실측 근거는 부정 대조군(아래 RWAIT_SCAN_EXTRA)
# 이고, 그것이 이 표기가 실제로 잡는다는 것을 재는 유일한 자리다.
WAIT_TOKENS=(
  'DECISION_NEEDED'
  'DEVIATION'
  'SCOPE_EXCESS'
  '상한 초과|limit exceeded'
  'actor claim'
  '목록에 없는 값|목록 밖 값|unlisted value|not in the list'
  '종결 미완|cycle close incomplete'
)
# 면제 — 앵커 문자열. 고칠 수 없거나 고쳐서는 안 되는 자리만 사유와 함께 등재한다.
# 지금은 없다 — 플러그인 트리에는 docs/ 의 실측 기록이 없다.
WAIT_KEEP=()
# 나열 패턴 자기 시험 — 절 밖 나열이 0건인 것이 정상 상태인데, 패턴이 죽어도 같은 0건이다. 신호 둘을
# 한 줄에 나열한 합성 파일을 스캔 대상에 얹어 그 줄이 후보에 오르는지로 패턴이 산 것을 못박는다
# (RWAIT_SCAN_EXTRA 와 같은 통로). 그 줄은 잔존에서 뺀다 — 검사가 자기 픽스처를 위반으로 세지 않는다.

check_rwait() {
  local files sec rows p t k c cnt line fpath body cand resid n_cand n_res scope f=0
  local -a flist=()

  # 스캔 대상은 글롭에서 파생한다. 새 규칙 문서·새 스킬·새 역할 정의의 기본값이 "검사됨" 이다.
  files=$( { echo "$BLOCK"
             for p in skills/*/SKILL.md agents/*.md; do
               [[ -f "$p" ]] && echo "$p"
             done
           } | sort -u )
  while IFS= read -r p; do [[ -n "$p" ]] && flist+=("$p"); done <<< "$files"
  [[ -n "${RWAIT_SCAN_EXTRA:-}" ]] && flist+=("$RWAIT_SCAN_EXTRA")
  local probe; probe="$(mktemp)"
  printf 'probe line: human wait — DECISION_NEEDED · DEVIATION\n' > "$probe"
  flist+=("$probe")
  if [[ "${#flist[@]}" -lt 2 ]]; then
    echo "✗ R-WAIT — 스캔 대상 파생이 ${#flist[@]}건이다. 글롭이 죽었으면 잔존 0 은 '위반 없음' 이 아니라 '안 봤음' 이다"
    return 1
  fi

  # 대상 단언 — 검사가 무엇을 보는지 못박는다. 파생이 조용히 좁아지는 것을 잡는다.
  for k in "$BLOCK" "$WAIT_OWNER" "agents/implementer.md"; do
    if ! printf '%s\n' "${flist[@]}" | grep -qxF -- "$k"; then
      echo "✗ R-WAIT — 스캔 대상에 '$k' 가 없다 (${#flist[@]}건 파생). 파생이 좁아졌다"
      return 1
    fi
  done

  # ① 단일 소유 절이 살아 있는가 + 신호를 전부 들고 있는가.
  if ! grep -qF -- "$WAIT_ANCHOR" "$WAIT_OWNER"; then
    echo "✗ R-WAIT — 단일 소유 절('$WAIT_ANCHOR')이 $WAIT_OWNER 에 없다. 절을 옮겼으면 이 앵커를 고쳐라 (안 고치면 목록이 어디에도 없는 채로 통과한다)"
    return 1
  fi
  sec=$(awk -v a="$WAIT_ANCHOR" 'index($0,a)==1 {on=1; print; next} on && /^## / {on=0} on {print}' "$WAIT_OWNER")
  if [[ "$(printf '%s' "$sec" | grep -c .)" -lt 2 ]]; then
    echo "✗ R-WAIT — 단일 소유 절이 비어 있다. 앵커만 남고 본문이 사라지면 목록이 없는 것과 같다"
    return 1
  fi
  rows=$(printf '%s\n' "$sec" | grep '^| ' | grep -v '^|---')
  if [[ "$(printf '%s' "$rows" | grep -c .)" -lt 2 ]]; then
    echo "✗ R-WAIT — 단일 소유 절에 신호 표가 없다. 표를 다른 형태로 바꿨으면 이 파생을 고쳐라 (안 고치면 목록이 비어도 통과한다)"
    return 1
  fi
  for t in "${WAIT_TOKENS[@]}"; do
    if ! printf '%s\n' "$rows" | grep -qE -- "$t"; then
      echo "✗ R-WAIT 단일 소유 절의 표가 신호 '$t' 를 들고 있지 않다 — 목록에서 빠지면 그 신호를 낸 역할의 결과가 아무도 정하지 않은 채 사라진다"
      f=1
    fi
  done

  # ② 절 밖의 나열. 후보 = "사람 대기" 가 있고 신호를 둘 이상 나열한 줄.
  cand=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    fpath=${line%%:*}
    body=${line#*:}; body=${body#*:}
    cnt=0
    for t in "${WAIT_TOKENS[@]}"; do
      printf '%s' "$body" | grep -qE -- "$t" && cnt=$((cnt+1))
    done
    [[ "$cnt" -ge 2 ]] || continue
    # 단일 소유 절의 줄은 정의라 후보에서 뺀다 — 그 절이 목록을 드는 유일한 자리다.
    if [[ "$fpath" == "$WAIT_OWNER" ]] && printf '%s\n' "$sec" | grep -qxF -- "$body"; then continue; fi
    cand="${cand}${line}"$'\n'
  done <<< "$(grep -nHiE -- "$WAIT_TRIGGER" "${flist[@]}" 2>/dev/null)"

  # 패턴 자기 시험 — 합성 줄이 후보에 올라야 한다. 그 뒤 잔존에서 뺀다.
  if ! printf '%s' "$cand" | grep -qF -- "$probe:"; then
    echo "✗ R-WAIT 나열 패턴이 죽었다 — 신호 둘을 한 줄에 나열한 합성 줄이 후보에 오르지 않는다. 절 밖 나열 0줄이 '위반 없음' 이 아니라 '안 봤음' 이 된다"
    rm -f "$probe"; return 1
  fi
  cand=$(printf '%s' "$cand" | grep -vF -- "$probe:")
  rm -f "$probe"
  n_cand=$(printf '%s' "$cand" | grep -c .)

  # 역방향 단언 — 면제 키가 실제 후보에 잡히는가. 0건 면제는 낡은 면제다.
  resid="$cand"
  for k in ${WAIT_KEEP[@]+"${WAIT_KEEP[@]}"}; do
    c=$(printf '%s\n' "$cand" | grep -cF -- "$k")
    if [[ "$c" -lt 1 ]]; then
      echo "✗ R-WAIT 면제(앵커) '$k' 가 후보에서 0건이다 — 앵커가 편집으로 사라졌거나 낡은 면제다. 면제표를 고쳐라"
      f=1
    fi
    resid=$(printf '%s\n' "$resid" | grep -vF -- "$k")
  done

  resid=$(printf '%s\n' "$resid" | grep -v '^$')
  n_res=$(printf '%s' "$resid" | grep -c .)
  scope="스캔 $(( ${#flist[@]} - 1 ))파일 · 신호 ${#WAIT_TOKENS[@]}종 · 후보 ${n_cand}줄 · 면제 ${#WAIT_KEEP[@]}앵커 · 패턴 자기 시험 통과"
  if [[ "$n_res" -ne 0 ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "✗ R-WAIT $(printf '%s' "$line" | cut -d: -f1,2) — 사람 대기 목록을 다시 적었다: $(printf '%s' "$line" | cut -d: -f3- | cut -c1-110)"
    done <<< "$resid"
    echo "✗ R-WAIT 절 밖 나열 ${n_res}줄 ($scope). $WAIT_OWNER 의 \"$WAIT_ANCHOR\" 절을 가리키게 고치거나, 고칠 수 없는 자리면 사유와 함께 면제표에 등재하라"
    return 1
  fi

  [[ "$f" -eq 0 ]] && echo "✓ R-WAIT 단일 소유 성립 ($scope · 절 밖 나열 0줄)"
  return "$f"
}


# ── R-DUP: 스킬·역할 문서가 상시 로드 문서의 문장을 그대로 복제한 자리 ─
# 왜: 복제된 문장은 원본이 고쳐져도 따라오지 않는다. 두 곳이 갈라지면 어느 쪽을 읽느냐로
# 결론이 달라지고, 상시 로드 문서는 매 세션 컨텍스트에 실리므로 **사본이 조용히 이긴다.**
# 이 스토리가 문서에 대해 반복해 도달한 결론이 "값을 옮기지 말고 자리를 가리켜라" 이고
# (harness-dg0.6.17 · harness-dg0.6.30 · harness-dg0.6.40), 이 검사는 그 결론의 강제다.
#
# 대상(스캔): 스킬 본문 `skills/*/SKILL.md` 과 역할 정의 `agents/*.md` 전수.
#   글롭에서 판다 — 새 스킬·새 역할의 기본값이 "검사됨" 이다(극성 반전).
# 원천: 상시 로드 문서 집합(always_loaded_derive). R-DATE·R-BEAD 와 **같은 모집단**이고
#   그 파생의 뿌리·근거·한계는 그 함수의 주석이 든다 — 여기에 다시 적지 않는다.
#   두 집합이 겹치면(스킬이 상시 로드가 되면) 자기 자신과의 대조가 되어 전부 적중하므로
#   교집합은 스캔 대상에서 뺀다. 뺀 결과는 scope 줄의 파일 수·목록으로 보인다.
#   **원천에서 헤딩 줄은 뺀다**(`grep -v '^#'`) — 이 검사가 권하는 형태가 "<파일>의
#   '<절 제목>'" 으로 자리를 가리키는 것이라, 절 제목을 원천 단위로 두면 규율을 지킨 줄이
#   곧 위반이 된다. 근거와 실측은 아래 임계값 주석의 정정이 든다.
# 판정: 원천의 **문장 단위**가 대상 줄의 부분문자열이면 복제다. 양쪽을 같은 함수로
#   정규화(목록 기호·번호·헤딩 마커·`*`·백틱 제거, 공백 접기)한 뒤 비교하므로 강조만
#   다른 사본도 잡힌다. 문장 분할은 `다. ` 와 `. ` 다.
#
# **0건의 취급 — 무엇이 0이면 실패인가.** 실패로 읽는 것은 *파생 집합*이 0건인 경우다:
#   ① 원천 문장 단위 0건(정규화·분할이 죽었다) ② 스캔 대상 파일 5건 미만(글롭이 죽었다)
#   ③ 문장 분할이 **한 번도** 일어나지 않았다(분할 정규식이 죽었다). ③ 이 ① 과 따로 있는
#   이유는 분할이 **부분적으로** 죽는 형태를 ① 이 못 잡기 때문이다 — 분할 정규식이 매칭
#   불가가 되면 줄 전체가 한 단위가 되어 단위 수만 줄고(실측: 375→217) 조용히 통과한다.
#   **적중 0줄은 실패가 아니라 통과다** — 그것이 이 검사가 지키려는 정상 상태다.
#
# 임계값 RDUP_MIN=60바이트(≈한글 20자) — 손으로 고른 값이라 근거를 실측으로 적는다.
#   [측정 2026-08-28 · bash 3.2.57(1)-release · macOS Darwin 25.6.0 · BSD sed/awk ·
#    LC_ALL 미설정(단위 길이만 LC_ALL=C) · 문서는 eb421e5(이 커밋의 수정 **전**)를
#    `git archive` 로 편 사본 · 검사 코드는 **이 파일의 최종본**을 그 사본에 얹고
#    RDUP_MIN 만 sed 로 바꿔 돌렸다 · 센 것은 "그대로 옮겼다" 줄의 수]
#   임계값별 적중: 30바이트 11줄 · 40바이트 6줄 · 45바이트 1줄 · 50바이트 1줄 · 60바이트 1줄.
#   **오탐의 정체가 임계값을 정한다.** 45바이트 아래에서 들어오는 적중의 과반은 이 검사가
#   권하는 바로 그 형태 — *가리키기* 다. 30바이트에서 11줄 중 7줄이 **절 제목을 인용한
#   포인터**였다: "위임 메시지의 환경 스냅샷"(36바이트, 3줄) · "사이클 종결 — PR 이
#   종점이다"(40바이트, 3줄) · "원장에 본문을 넘기는 형태"(36바이트, 1줄). 40바이트에서도
#   6줄 중 3줄이 그중 가장 긴 "사이클 종결 — PR 이 종점이다" 다. 관측된 절 제목 인용의
#   최대가 40바이트이므로 45바이트가 첫 청정 구간이고, 60바이트는 그 위로 20바이트를 더
#   둔 값이다. 45~60 의 적중이 동일(1줄)이라 이 구간에서 잃는 것이 없다.
#   60바이트에서 남은 1줄은 오탐이 아니었다 — plan-story 가 계층 매핑 표 "스토리" 행의
#   근거 문장을 그대로 옮긴 자리이고, 이 커밋이 그것을 포인터로 바꿔 **0줄**로 만든다.
#   **임계값을 내리지 마라.** 내리려면 위 포인터 3종을 면제로 등재해야 하는데, 그것은
#   "가리킨 자리를 면제표에 나열" 하는 것이라 자리를 하나 가리킬 때마다 면제가 하나 는다 —
#   면제표가 규율의 준수를 기록하는 이상한 자리가 된다.
#
#   **정정(같은 태스크의 재작업 · 재측정 2026-08-28 · bash 3.2.57(1)-release · macOS Darwin
#   25.6.0 · BSD sed/awk/grep · 트리 a89b5dd · 원천 파생을 검사 코드와 같은 형태로 재현해
#   잼).** 위 문단은 "관측된 절 제목 인용의 최대가 40바이트이므로 45바이트가 첫 청정
#   구간" 이라고 적었다. **그 40바이트는 이미 인용된 제목의 최대(표본)이지 인용 가능한
#   제목의 최대(모집단)가 아니다.** 모집단은 상시 로드 문서의 헤딩 전수 22줄이고, 재보니
#   정규화 후 최대 66바이트("결정 상태 — 안 하기로 한 것은 남은 일이 아니다") · 2위
#   57바이트("사람 대기 — 어떤 신호가 사람에게 가는가") 로 **임계값 60이 그 둘 사이에
#   있다.** 66바이트 제목으로 자리를 정확히 가리키는 줄은 이 검사가 복제로 잡고, 실패
#   메시지의 조치("문면을 지우고 자리를 가리켜라")는 이미 자리를 가리키는 그 줄에 대해
#   수행 불가능하다 — 규칙 A(자리를 가리켜라)와 규칙 B(문장을 옮기지 마라)의 충돌이다.
#   적중이 0이던 것은 설계가 아니라 현존 두 자리가 제목을 줄여 쓴 우연이었다.
#   **해소는 임계값이 아니라 원천이다** — 헤딩 줄을 원천 파생에서 뺀다(아래 units).
#   그러면 충돌이 구조적으로 닫히고, 근거가 표본이 아니라 모집단 위에 선다.
#   [재측정: 원천 376 → 375단위(빠진 1건이 그 66바이트 제목) · 이 트리 적중 0줄 유지 ·
#    그 제목을 온전히 인용한 포인터 줄을 주입한 사본이 헤딩 제외 **전** rc=1(그 줄 지목)
#    → **후** rc=0 · 기점 트리 eb421e5 의 진짜 복제 1건(plan-story:12)은 제외 후에도 잡힘]
#   **임계값 60 은 그대로 둔다.** 위 "내리지 마라" 의 이유는 이 변경으로 바뀌었다 — 포인터
#   3종이 원천에서 사라지므로 면제 등재 없이도 내릴 수 있다. 그래도 내리지 않는 이유는
#   다른 것이다: 내리면 오탐 분포를 다시 재야 하고(그 재측정이 이 재작업의 범위 밖이다),
#   45~60 구간의 적중이 동일해 안 내려서 잃는 것이 없다.
#
# 한계(확인한 것):
#  · **문장의 일부만 옮긴 복제는 못 본다.** 단위가 문장이라 앞뒤를 잘라 60바이트 미만으로
#    만들면 빠져나간다. 재서술(같은 뜻 다른 말)도 못 본다 — 이 검사는 문자열 동일성만 본다.
#  · **방향이 한쪽이다.** 상시 로드 문서 → 스킬·역할 방향만 본다. 스킬끼리의 복제와
#    docs/ 안의 복제는 대상이 아니다(R-REM 이 다른 축으로 docs 를 본다).
#  · 면제 앵커는 파일 한정이 아니라 적중 줄 전역의 부분문자열이다(R-WAIT·R-REM 과 같다).
#    역방향 단언은 ≥1건만 보므로 과소만 잡고 과폭은 못 잡는다.
#  · **헤딩 제외의 대가**: 상시 로드 문서의 절 제목을 산문으로 옮긴 자리는 이제 안 잡힌다.
#    의도한 것이다 — 그 형태가 곧 이 검사가 권하는 *가리키기* 이고, 둘을 문자열로 가를
#    방법이 없다. 제목 아래 **본문**을 옮긴 복제는 그대로 잡힌다.
#  · **분할 단언은 총사만 잡는다.** ③ 은 "분할이 한 번도 일어나지 않았다" 를 본다. 두 대안
#    (`다.` 와 `.`) 중 하나만 죽는 부분사는 나머지 하나가 분할을 일으켜 통과한다.
#
# 부정 대조군(이 검사가 죽었는지): RDUP_SCAN_EXTRA 에 파일 경로 하나를 주면 스캔 대상에
#   더해진다. 역할 정의 사본에 상시 로드 문서의 문장 하나를 주입해 그 경로로 주면 적중이
#   1줄 이상이 되고 그 사본의 경로:줄을 지목해야 한다. **사본이 원본과 같거나 만들어지지
#   않으면 그 자체가 실패다** — 두 파일의 실재를 먼저 단언하고 내용 차이를 봐라(비교 명령의
#   비-0 만으로 판정하지 마라: 부재의 rc=2 와 차이의 rc=1 이 셸 || 에서 같은 분기로 간다).
#   그 둘로 모자란다 — **주입한 문장이 실제 원천 단위 목록에 있는지 함께 단언해라.**
#   임계값 미만의 문장을 주입하면 사본은 원본과 다른데 적중은 0이고, 그러면 대조군이
#   공허한 채로 "검사가 죽었다" 로 오독된다.
#
# 배선: 다른 검사와 같다 — rules-check.sh 자체가 손으로 돌리는 게이트다(위 "배선" 항목).
RDUP_MIN=60
# 면제 — 지금 없다. 상시 로드 문서의 문장이 그대로 남아야 하는 스킬·역할 자리가 없다.
# (0건 면제표는 정상이다. 등재된 키가 0건 적중이면 그것이 낡은 면제라 실패로 읽는다.)
RDUP_KEEP=()

rdup_norm() {  # stdin → 정규화된 줄. 원천과 대상에 **같은 함수**를 쓴다
  sed -e 's/^[[:space:]]*[-*>|][[:space:]]*//' \
      -e 's/^[[:space:]]*[0-9][0-9]*\.[[:space:]]*//' \
      -e 's/^#\{1,6\}[[:space:]]*//' \
      -e 's/[*`]//g' \
      -e 's/[[:space:]][[:space:]]*/ /g' \
      -e 's/^ //' -e 's/ $//'
}

check_rdup() {
  local p k c u line unit units corpus hits resid n_u n_h n_res scope f=0
  # slist/n_skip 은 언어 축소 블록에서 선언한다 (선언 자리에 사유 주석이 붙어 있다).
  local -a tlist=()

  always_loaded_derive || return 1

  # 스캔 대상은 글롭에서 판다. 상시 로드 문서와 겹치는 것은 자기 대조라 뺀다.
  for p in skills/*/SKILL.md agents/*.md; do
    [[ -f "$p" ]] || continue
    printf '%s\n' "${ALWAYS_LOADED[@]}" | grep -qxF -- "$p" && continue
    tlist+=("$p")
  done
  [[ -n "${RDUP_SCAN_EXTRA:-}" ]] && tlist+=("$RDUP_SCAN_EXTRA")

  if [[ "${#tlist[@]}" -lt 5 ]]; then
    echo "✗ R-DUP — 스캔 대상 파생이 ${#tlist[@]}건이다. 글롭이 죽었으면 복제 0줄은 '위반 없음' 이 아니라 '안 봤음' 이다"
    return 1
  fi
  # 대상 단언 — 글롭 파생(tlist)이 무엇을 물고 있는지 못박는다. 개수만으로는 대상 교체를
  # 못 잡는다. 못박는 것은 **글롭 목록이지 아래 언어 축소를 거친 실제 스캔 집합(slist)이
  # 아니다** — 그래야 이 셋 중 하나가 영어로 옮겨져 축소에 빠져도 단언이 안 깨진다.
  # slist 쪽은 개수 하한(0건이면 실패)만 보고, 축소가 실제로 걸리는지는 부정 대조군이 본다.
  for k in "skills/develop/SKILL.md" "agents/implementer.md" "agents/evaluator.md"; do
    if ! printf '%s\n' "${tlist[@]}" | grep -qxF -- "$k"; then
      echo "✗ R-DUP — 스캔 대상에 '$k' 가 없다 (${#tlist[@]}건 파생). 파생이 좁아졌다"
      return 1
    fi
  done

  # ── 언어 축소: 한글이 한 바이트도 없는 파일은 스캔에서 뺀다 ──────────
  # 왜: 이 검사는 문자열 동일성만 본다(위 "한계"). 원천은 한국어 상시 로드 문서이므로
  #   **한글이 없는 파일은 원천 단위를 그대로 옮길 수 없다** — 스캔해도 적중이 구조적으로
  #   0이다. 커버리지 포기가 아니라 대상 집합의 정확한 축소다. 근거는 M0 의 실측
  #   (harness-g88o.1.1): 같은 복제가 한국어면 rc 1, 영어로 옮기면 rc 0 이었다 — 번역된
  #   복제는 축소 **전에도** 잡히지 않았다.
  # 극성 반전은 지킨다 — 글롭은 위에서 그대로 판다. 제외가 파일 목록이 아니라 판정에서
  #   파생하므로 새 스킬의 기본값은 "검사됨" 이고, 한국어가 한 줄이라도 들어오면 그 파일은
  #   즉시 스캔 대상으로 돌아온다(번역본이 한국어 절 제목을 인용하는 자리가 그렇다).
  # **제외 0건은 정상이다** — 영어 문서가 없는 트리에서는 아무것도 빠지지 않는다. 위
  #   "0건 취급" 이 실패로 읽는 것은 *파생 집합*의 0건이지 이 제외 수가 아니다. 이 수는
  #   판정이 아니라 관측값이고, 축소가 실제로 작동하는지는 부정 대조군이 단언한다
  #   (checks/rdup-language-probe.sh).
  # 한계(확인한 것): 판정은 UTF-8 선행 바이트 \xEA-\xED 의 존재다. 그 범위는 한글 음절·
  #   자모 확장 말고도 U+A000–U+DFFF 의 희소 문자를 함께 포함한다 — **과잉 포함** 방향이라
  #   안전하다(덜 빼고 더 스캔한다). 반대로 한글 자모(U+1100–, 선행 바이트 \xE1)만으로 쓴
  #   파일은 한국어인데도 "한글 없음" 으로 갈린다. 실물에 그런 문서가 없어 수용한다.
  local -a slist=()
  local n_skip=0
  for p in "${tlist[@]}"; do
    if LC_ALL=C grep -q $'[\xea-\xed]' "$p" 2>/dev/null; then slist+=("$p"); else n_skip=$((n_skip+1)); fi
  done
  # 언어 판정이 죽어 전부 빠지면 적중 0줄이 "위반 없음" 으로 보고된다. 0건은 실패로 읽는다.
  if [[ "${#slist[@]}" -lt 1 ]]; then
    echo "✗ R-DUP 언어 축소 뒤 스캔 대상이 0건이다 (글롭 ${#tlist[@]}건 전부 제외). 언어 판정이 죽었으면 적중 0줄은 '위반 없음' 이 아니라 '안 봤음' 이다"
    return 1
  fi

  # 원천 문장 단위. 길이는 **바이트**다(LC_ALL=C) — 로케일에 따라 임계값이 흔들리지 않게.
  # 헤딩 줄은 뺀다 — 절 제목은 이 검사가 권하는 *가리키기* 의 재료다(위 주석의 정정).
  # END 의 마커는 분할이 실제로 일어났는지를 못박는다(위 0건 취급 ③).
  units=$(cat "${ALWAYS_LOADED[@]}" | grep -v '^#' | rdup_norm | LC_ALL=C awk -v m="$RDUP_MIN" '
    { n = split($0, a, /(다\.|\.) /)
      if (n > 1) split_seen = 1
      for (i = 1; i <= n; i++) { u = a[i]; gsub(/^ +| +$/, "", u); if (length(u) >= m) print u } }
    END { if (split_seen) print "@@RDUP_SPLIT_OK@@" }' \
    | grep -v '^$' | sort -u)
  if ! printf '%s\n' "$units" | grep -qxF '@@RDUP_SPLIT_OK@@'; then
    echo "✗ R-DUP 문장 분할이 한 번도 일어나지 않았다 — 분할 정규식이 죽었다. 줄 전체가 한 단위가 되어 문장 단위 검출력을 잃는다 (단위 수만 줄고 적중 0줄이 '위반 없음' 으로 보고된다)"
    return 1
  fi
  units=$(printf '%s\n' "$units" | grep -vxF '@@RDUP_SPLIT_OK@@')
  n_u=$(printf '%s' "$units" | grep -c .)
  if [[ "$n_u" -lt 1 ]]; then
    echo "✗ R-DUP 원천 문장 단위가 0건이다 — 정규화나 문장 분할이 죽었다. 0건 파생은 실패로 읽는다 (적중 0줄이 '위반 없음' 으로 보고된다)"
    return 1
  fi

  # 대상 말뭉치: 정규화한 줄에 경로:행 을 붙인다. 빈 줄은 뺀다(빈 패턴은 전부 적중시킨다).
  corpus=$(for p in "${slist[@]}"; do
             rdup_norm < "$p" | awk -v f="$p" '{ if (length($0) > 0) print f ":" NR ":" $0 }'
           done)

  hits=$(printf '%s\n' "$corpus" | grep -F -f <(printf '%s\n' "$units") 2>/dev/null)
  n_h=$(printf '%s' "$hits" | grep -c .)

  # 역방향 단언 — 면제 키가 실제 적중에 잡히는가. 0건 면제는 낡은 면제다.
  resid="$hits"
  for k in ${RDUP_KEEP[@]+"${RDUP_KEEP[@]}"}; do
    [[ -n "$k" ]] || continue
    c=$(printf '%s\n' "$hits" | grep -cF -- "$k")
    if [[ "$c" -lt 1 ]]; then
      echo "✗ R-DUP 면제(앵커) '$k' 가 적중에서 0건이다 — 앵커가 편집으로 사라졌거나 낡은 면제다. 면제표를 고쳐라"
      f=1
    fi
    resid=$(printf '%s\n' "$resid" | grep -vF -- "$k")
  done

  resid=$(printf '%s\n' "$resid" | grep -v '^$')
  n_res=$(printf '%s' "$resid" | grep -c .)
  scope="상시 로드 ${#ALWAYS_LOADED[@]}파일[${ALWAYS_LOADED_STR}] · 원천 ${n_u}단위(≥${RDUP_MIN}바이트) · 스캔 ${#slist[@]}파일(글롭 ${#tlist[@]} − 언어 제외 ${n_skip}) · 적중 ${n_h}줄 · 면제 ${#RDUP_KEEP[@]}앵커"

  if [[ "$n_res" -ne 0 ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      unit=""
      while IFS= read -r u; do
        [[ -n "$u" ]] || continue
        if printf '%s' "${line#*:*:}" | grep -qF -- "$u"; then unit="$u"; break; fi
      done <<< "$units"
      echo "✗ R-DUP $(printf '%s' "$line" | cut -d: -f1,2) — 상시 로드 문서의 문장을 그대로 옮겼다: $(printf '%s' "$unit" | cut -c1-110)"
    done <<< "$resid"
    echo "✗ R-DUP 복제 ${n_res}줄 ($scope). 문면을 지우고 그 문장이 사는 자리(파일 경로 · 절 제목)를 가리켜라"
    return 1
  fi

  [[ "$f" -eq 0 ]] && echo "✓ R-DUP 복제 0줄 ($scope)"
  return "$f"
}

# ── R-BUDGET: 상시 로드 문서의 총 바이트 상한 ────────────────────────
# 왜: 상시 로드는 **매 세션 시작 × 매 서브에이전트 위임**에 곱해지는 유일한 문서 비용이다.
# 그리고 이 레포의 규칙은 회고마다 늘어나는 쪽으로만 힘이 걸려 있다 — 승격 기준(2회 관측)은
# 더하는 규칙이고, 덜어내는 규칙(retrospective 6절의 분기 감사)에는 판정 수단이 없었다.
# 근거는 harness-guau.2.3.
#
# 그래서 총량에 **상한 하나**를 건다. 넘으면 이 게이트가 깨지므로, 규칙을 더하려면 그만큼
# 덜어내거나 상한을 올리는 커밋을 명시적으로 해야 한다 — 후자는 git 에 남고 리뷰 대상이 된다.
# 이것이 "설득으로 안 되는 종류는 게이트로 옮긴다"(retrospective 4절)의 적용이다.
#
# **상한을 올리는 것 자체는 위반이 아니다.** 이 검사가 막는 것은 총량이 아니라 **모르는 사이
# 늘어나는 것**이다. 올릴 때는 무엇을 얻으려고 올리는지 커밋 메시지에 적는다.
#
# 대상 집합은 always_loaded_derive 가 파생한다 — 주입 블록 하나다. 상한 8000 은 종전(CLAUDE.md +
# agile.md 33,000)의 약 1/4 로, 블록을 "절대 금지 + 나머지가 어디 있는지" 로 줄인 결정의 값이다.
RBUDGET_MAX=8000
check_rbudget() {
  local total=0 n b f scope
  always_loaded_derive || return 1
  n=${#ALWAYS_LOADED[@]}
  for f in "${ALWAYS_LOADED[@]}"; do
    b=$(wc -c < "$f" 2>/dev/null | tr -d '[:space:]')
    [[ -n "$b" ]] || { echo "✗ R-BUDGET — $f 의 크기를 재지 못했다"; return 1; }
    total=$((total + b))
  done
  # 0건 통과를 실패로 읽는다 — 집합이 비면 어떤 상한도 참이 된다.
  [[ "$n" -gt 0 && "$total" -gt 0 ]] || { echo "✗ R-BUDGET — 상시 로드 집합이 비었거나 0바이트다. 빈 집합에 대한 상한은 검사가 아니다"; return 1; }
  scope="상시 로드 ${n}파일[${ALWAYS_LOADED_STR}]"
  if [[ "$total" -gt "$RBUDGET_MAX" ]]; then
    for f in "${ALWAYS_LOADED[@]}"; do
      printf '    %8s  %s\n' "$(wc -c < "$f" | tr -d '[:space:]')" "$f"
    done
    echo "✗ R-BUDGET ${total} > 상한 ${RBUDGET_MAX} (바이트 · $scope). 덜어내거나, 올릴 값어치가 있으면 checks/rules-check.sh 의 RBUDGET_MAX 를 올리고 그 사유를 커밋 메시지에 적어라"
    return 1
  fi
  echo "✓ R-BUDGET ${total} / 상한 ${RBUDGET_MAX} (바이트 · 여유 $((RBUDGET_MAX - total)) · $scope)"
  return 0
}

check_r5  || fail=1
check_r18 || fail=1
check_s12 || fail=1
check_racc || fail=1
check_rrem || fail=1
check_c6  || fail=1
check_r40 || fail=1
check_s22 || fail=1
check_s24 || fail=1
check_rdate || fail=1
check_rbead || fail=1
check_rwait || fail=1
check_rdup  || fail=1
check_rbudget || fail=1

exit "$fail"
