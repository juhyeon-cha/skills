#!/usr/bin/env bash
# 게이트: **원장을 보는** 규약 검사 — 원장의 상태가 규약대로인가. 대상은 하네스 루트의 원장이고,
# 설치본에서 매번 새로 판정된다(그래서 이 검사는 배포된다). 짝은 트리를 보는 저작 검사
# tests/harness/doc-rules-check.sh 이며 그쪽은 배포되지 않는다 — 판정 대상이 배포 전에만
# 바뀌는 저작물이라 설치본에서 돌릴 값어치가 없다.
#
#   R5  (harness:develop 운영 규율) 태스크의 repo: 라벨은 정확히 1개
#   R-ACC (harness:develop 운영 규율) acceptance 없는 태스크는 착수(in_progress)하지 않는다
#   S22 (harness:develop 3-0) 한 워크트리에 두 태스크를 동시에 위임하지 않는다
#   S24 (harness:develop 4-2) 하위가 전부 종료 상태인데 열려 있는 스토리
#
# 원장은 언제나 lib/harness-root.sh 가 낸 루트 HROOT 의 것이다 — 워크트리에서 부르면 워크트리
# 자신의 `.harness.json` 이 그 루트다. 하네스 루트를 못 찾으면 **조용히 건너뛰지 않고 실패한다**
# (rc≠0) — 원장 없이 통과한 원장 검사는 검사가 아니다.
#
# 극성 반전(harness:develop 운영 규율): 검사 대상을 손으로 나열하지 않는다.
#   R5  대상은 원장의 태스크 전수에서 파생한다 (면제는 아래 사유 참조).
#   R-ACC 대상은 원장에서 파생한다 — 착수의 기계적 표시(status=in_progress)를 가진
#         태스크 전수이며, 손으로 고른 id 목록이 없다.
#   S22 원장 쪽(동시 in_progress)과 파일시스템 쪽(그 스토리의 워크트리 수)에서 각각 파생해
#       비둘기집으로 판정한다 — 손으로 적은 스토리 면제가 없다.
#   S24 대상은 **하위를 가진 epic 전수**이고, 종료 상태 집합(closed·blocked·deferred)만
#       손으로 적힌 목록이다. bd 의 계산이 규율과 반대라 그 집합을 이 검사가 직접 든다.
#
# **0건 파생의 취급.** S22·S24 는 갓 세팅한 트리에서 대상이 0건이라 0건을 실패로 읽을 수
#   없고(setup/SKILL.md 1.5 의 A 검증표가 rc 0 을 요구한다), R5 와 **같은 함수**를 쓴다 —
#   `ledger_fields_ok`(파생이 의존하는 필드를 직접 단언한다). 그 대체가 못 잡는 것까지
#   실측으로 그 함수의 주석에 적혀 있다. 사유는 각 검사의 주석이 든다.
#
# 배선: setup 의 설치 검증표(harness:setup 1.5·2·3)가 부르고, 개발 중에는 tests/run-all.sh 가
#   배포되는 검사 전수로 함께 돌린다.
#
# set -e 를 쓰지 않는다 — 검사 스크립트는 첫 실패에서 죽으면 안 된다. 실패는 fail=1 로
# 모아 전부 보고한다 (board-check.sh 와 같은 관례).
# 종료 코드는 파이프 밖에서 채집한다.
set -uo pipefail

CALLER_PWD="$PWD"   # 호출 CWD — 원장 루트를 여기서 파생한다(아래 cd 뒤에는 잃는다)
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$PLUGIN_ROOT" || { echo "✗ 플러그인 루트로 이동하지 못했다: $PLUGIN_ROOT" >&2; exit 1; }
PLUGIN_ROOT="$PWD"   # 절대 경로로 못박는다 — 아래에서 호출 CWD 로 돌아가 부른다

command -v jq >/dev/null 2>&1 || { echo "✗ jq 가 없다 — 이 게이트는 jq 없이는 판정할 수 없다 (없으면 빈 질의 결과가 '위반 없음' 오진이 된다)" >&2; exit 1; }

# 원장 루트 HROOT — lib/harness-root.sh 가 **호출 CWD 에서** 낸다(플러그인 루트에서 부르면 플러그인이
# 사는 트리의 배선을 따라가 검토 대상과 무관한 루트가 나온다). 한 번 찾고, 못 찾으면 그것을 쓰는
# 검사마다 실패한다.
HROOT="$(cd "$CALLER_PWD" && bash "$PLUGIN_ROOT/lib/harness-root.sh" 2>/dev/null)" || HROOT=""
HROOT_ERR=""
[[ -n "$HROOT" ]] || HROOT_ERR="$(cd "$CALLER_PWD" && bash "$PLUGIN_ROOT/lib/harness-root.sh" 2>&1 >/dev/null | head -1)"
need_hroot() {  # need_hroot <검사이름> — 하네스 루트가 없으면 ✗ 를 내고 1
  [[ -n "$HROOT" ]] && return 0
  echo "✗ $1 — 하네스 루트를 찾지 못했다 (${HROOT_ERR:-lib/harness-root.sh rc≠0}). 원장을 보는 검사라 건너뛰지 않고 실패한다 — 스토리 워크트리 안에서 돌리거나 HARNESS_ROOT 를 지정하라"
  return 1
}
bdl() { HARNESS_ROOT="$HROOT" bash scripts/ledger.sh "$@"; }   # 원장은 언제나 하네스 루트의 것이다 — 어댑터로 읽는다(CWD 는 플러그인 루트)

echo "원장 루트: ${HROOT:-(없음)}"

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
#     setup/SKILL.md 1.5 의 A 검증표가 그 트리에서 rc 0 을 요구한다. 데이터만 보고
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
# 프로젝트가 무조건 막히므로(setup/SKILL.md 1.5 의 A 검증표가 검사 대상 0건 통과를 전제한다), 대신
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
#   **가변 집합**에 거는 관례라 낡은 면제 키가 실패한다).
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
#   그것을 실패로 만들면 skills/setup/SKILL.md 1.5 의 A 검증표(`rules-check.sh` rc 0)가
#   무조건 막힌다. 대신 **파생이 의존하는 필드를 직접 단언하고**(위 ledger_fields_ok — R5 와
#   같은 함수를 쓴다) 대상 건수를 항상 출력한다. **그 단언이 무엇을 못 잡는지는 그 함수의
#   주석이 실측으로 든다** — 요약하면 `parent` 키 이름 자체가 바뀌는 스키마 변경은 못 잡고,
#   그것은 R5 도 마찬가지다(세 검사가 공유하는 구멍이지 이 검사가 R5 보다 약한 것이 아니다).
#
# 부정 대조군: RULES_LEDGER_JSON 으로 원장 JSON 을 갈아끼운다 — 워크트리가 없는 스토리에
#   in_progress 2건을 넣은 사본은 비-0 이어야 한다. 사본의 실재와 원본과의 차이를 먼저
#   단언하고, **넣은 줄이 실제로 파생 집합에 들어오는지**도 함께 봐라(실재·차이는 대조군
#   성립의 필요조건이지 충분조건이 아니다 — 실측 참조는 tests/harness/doc-rules-check.sh 의
#   R-REM 부정 대조군 항목이 든다).
# **판정 범위는 이 레포 하나다.** 하네스는 다른 레포의 클론이 어디 있는지 알지 못하므로
# (고정 클론 루트를 없앴다) 다른 repo: 라벨의 칸은 워크트리를 셀 수 없다 — 0 으로 세면
# 없는 위반을 만들어 낸다. 그래서 그 칸은 판정하지 않고 `.` 줄로 드러낸다. 멀티 레포
# 스토리는 레포마다 게이트를 돌리므로(harness:develop "멀티 레포") 합치면 전수가 덮인다.
S22_ROOT="${HROOT%%/.claude/worktrees/*}"     # 워크트리에서 돌려도 본 체크아웃을 본다
S22_REPO="${S22_ROOT##*/}"
# 스토리 ID 로 만들어진 워크트리 수. 이름은 ID 가 아니라 **ID 를 변환한 것**이라 lib/worktree-name.sh
# 로 파생한다 — ID 를 그대로 쓰면 github 백엔드(`<repo>#<번호>`)에서 실재하는 워크트리를 0개로
# 세어 검출이 통째로 꺼진다 (harness#79 의 세 번째 사례가 여기였다). 병렬 진행은
# `<그 이름>-<접미>` 를 함께 쓴다 — 둘 다 같은 스토리의 워크트리다.
# 한계 — **`git worktree list` 가 아니라 디렉토리 실재를 센다.** 정리되지 않은 잔여
#   디렉토리(git 은 모르는데 파일시스템에는 남은 것)가 분모를 부풀려 **검출을 약화**시킨다.
#   미탐 쪽이라 안전한 방향이라 그대로 두지만, 이 레포에 정리 스크립트가 둘 있다는 것
#   (scripts/workspace-cleanup.sh)은 잔여가 실재하는 상태라는 뜻이다.
#   좁히려면 각 레포 클론에서 `git worktree list` 를 파생으로 써야 하는데, 그러면 이 검사가
#   클론마다 git 을 실행하게 된다(지금은 파일시스템만 본다).
s22_wt_count() {  # s22_wt_count <스토리ID>
  local d="$S22_ROOT/.claude/worktrees" n=0 p wtname
  [[ -d "$d" ]] || { echo 0; return 0; }
  wtname="$(bash "$PLUGIN_ROOT/lib/worktree-name.sh" "$1")" || { echo 0; return 0; }
  for p in "$d/$wtname" "$d/$wtname"-*; do [[ -d "$p" ]] && n=$((n + 1)); done
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
        # 마지막 줄이 아니라 마지막 **표시 줄**을 본다 — 뒤따르는 산문 note 가 표시를
        # 덮지 않는다(harness-k4wg). stop-resume.sh 의 판정과 같은 규칙이다.
        ((.notes // "") | split("\n") | map(select(test("^(VERIFY_PENDING|DELEGATED)"))) | last // "") | startswith("VERIFY_PENDING");
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
    if [[ "$repo" != "$S22_REPO" ]]; then
      echo "  · S22 $story (repo:$repo) — 이 레포('$S22_REPO')가 아니라 워크트리를 셀 수 없다. 판정하지 않는다 — 그 레포의 클론에서 게이트를 돌려라: $ids"
      continue
    fi
    wt=$(s22_wt_count "$story")
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
  # 자기 판정 시험 — 실원장과 무관한 합성 원장. 레포는 **이 레포**여야 판정에 들어오고
  # (다른 레포는 위에서 건너뛴다), 스토리 fx-s 의 워크트리는 실재하지 않으므로 계수는 0 이다.
  local fx_s='{"id":"fx-s","issue_type":"epic","status":"in_progress"}'
  local fx_plain fx_marked
  fx_plain="[$fx_s,{\"id\":\"fx-a\",\"issue_type\":\"task\",\"status\":\"in_progress\",\"parent\":\"fx-s\",\"labels\":[\"repo:$S22_REPO\"]},{\"id\":\"fx-b\",\"issue_type\":\"task\",\"status\":\"in_progress\",\"parent\":\"fx-s\",\"labels\":[\"repo:$S22_REPO\"]}]"
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
#   (setup/SKILL.md 1.5 의 A 검증표 · 공유 단언 ledger_fields_ok). **그 단언이 `parent` 키
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

check_r5  || fail=1
check_racc || fail=1
check_s22 || fail=1
check_s24 || fail=1

exit "$fail"
