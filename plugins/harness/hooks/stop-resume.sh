#!/bin/bash
# 정지 가드 — 원장에 진행 중인 일이 남았는데 세션이 멈추려 하면 되민다 (Stop 훅).
#
# 왜 Stop 훅 계층인가 (실측 2026-08-27, harness-dg0.6.12 착수 시 확인).
#   이 태스크의 bead note 는 "살아 있는 background 서브에이전트가 있으면 세션이 Stop
#   상태에 도달하지 않아 Stop 훅이 발화하지 않는다"를 가설로 세우고, 맞으면 이 장치가
#   무의미하다고 적었다. 전사를 파싱해 확인한 결과 **가설은 거짓이다.**
#     전사: ~/.claude/projects/-Users-juhyeon-workspace-harness/1bdbd772-…-09805d429bba.jsonl
#     stop_hook_summary 레코드 111건. Agent 위임 87건, 그중 완료 알림(task-notification)과
#     tool-use-id 로 짝지어진 liveness 창 40건. **111건 중 48건이 그 창 안에서 발화했다.**
#   당시 쓰던 루프 플러그인이 9시간 동안 iteration=1 이었던 원인은 발화 실패가 아니라 등록
#   실패다: 111건 전부 hookCount=1 이고 실행된 명령은 당시 이 하네스가 Stop 에 걸어 둔 루프
#   취소 훅 하나뿐이다. 플러그인 Stop 훅은 한 번도 실행되지 않았고, 그 플러그인은
#   installed_plugins.json 에 없으며 캐시에 .orphaned_at 이 있다. 즉 "발화하지 않는
#   계층"이 아니라 "설치되지 않은 플러그인"이었다.
#
# 다섯 경로가 각각 로그를 한 줄 남긴다: BLOCK · IDLE · RECURSE · GAVE_UP · ORACLE_FAIL.
# CANCEL 이 여섯째다 — 전용 마커로 끈 것도 남긴다. 조용히 꺼지는 장치는 있다고 믿게
# 만들어 없는 것보다 나쁘고, 그것이 harness-dg0.3.1 note 가 그 루프 플러그인을 탈락시킨 사유였다.
# VERIFY_PENDING 이 일곱째다 — 배치 모드의 검증 대기 완료분도, 위임 직후 아직 구현이 시작되지
# 않은 구간(DELEGATED)도 하다 만 일이 아니다. 두 표시를 한 경로가 건수를 갈라 적는다 (4b).
# NO_CLAIM 이 여덟째, SCOPE_FAIL 이 아홉째다 — 사거리 좁히기의 두 폴백이다 (3b).
#
# **사거리는 이 세션이 claim 한 actor 다** — 오라클은 여전히 원장을 읽지만 판정은 그중
# 이 세션의 몫으로 좁힌다. 잡지 않은 일로 막지 않는 것이 목적이고, 매핑을 못 읽으면
# 종전대로 원장 전체로 판정한다(SCOPE_FAIL). 천장은 ../docs/guardrail-verification.md 8절이 든다.
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Runtime/session come from an explicit adapter identity and the actual event.
# A missing state contract is UNREACHED, never an idle-work assertion.
payload="$(cat)"
for dependency in node jq; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    echo "STATE UNREACHED: Stop $dependency dependency missing; stop allowed" >&2
    exit 0
  fi
done
SID="$(printf '%s' "$payload" | jq -er '.session_id | select(type == "string" and length > 0)')" || { echo "STATE UNREACHED: Stop session missing" >&2; exit 0; }
PCWD="$(printf '%s' "$payload" | jq -er '.cwd | select(type == "string" and length > 0)')" || { echo "STATE UNREACHED: Stop cwd missing" >&2; exit 0; }
STATE="$(node "$PLUGIN_ROOT/scripts/state.mjs" paths "${HARNESS_RUNTIME:-}" "$PCWD" "$SID")" || { echo "STATE UNREACHED: Stop state resolution failed; stop allowed" >&2; exit 0; }
RUNTIME="$(printf '%s' "$STATE" | jq -er '.runtime')"
LOG="$(printf '%s' "$STATE" | jq -er '.stopLog')"
MAX_BLOCKS=3
log() {
  node "$PLUGIN_ROOT/scripts/state.mjs" stop-log "$RUNTIME" "$PCWD" "$SID" "$1" "$2" || echo "STATE UNREACHED: Stop observation was not persisted" >&2
}
ACTIVE="$(printf '%s' "$payload" | jq -r '.stop_hook_active == true')"

# 1) 재귀 통과 — 이미 이 훅이 되민 턴이다. 다시 막으면 세션이 영영 멈추지 못한다.
if [[ "$ACTIVE" == "true" ]]; then
  log RECURSE "stop_hook_active=true — 이 훅이 되민 턴의 종료다. 다시 막지 않는다"
  exit 0
fi

# 2) Cancellation is created for an explicit runtime/repository/session only.
# Legacy entrance markers are left untouched: the next observer is not their owner.
if node "$PLUGIN_ROOT/scripts/state.mjs" cancelled "$RUNTIME" "$PCWD" "$SID"; then
  log CANCEL "이 세션의 명시적 취소 — 통과한다 (마커 유지)"
  exit 0
else
  cancel_rc=$?
  if [[ "$cancel_rc" -ne 1 ]]; then
    echo "STATE UNREACHED: cancellation could not be evaluated; stop allowed" >&2
    exit 0
  fi
fi

# 3) 오라클 — 원장의 in_progress 이슈 수.
#    원장은 lib/harness-root.sh 가 낸 하네스 루트를 HARNESS_ROOT 로 물린 어댑터(scripts/ledger.sh)로
#    읽는다 — 백엔드가 무엇이든 같은 JSON 키다. 헬퍼의 CWD 는 페이로드의 cwd 다(워크트리면 배선을
#    따라간다). 못 찾으면 ORACLE_FAIL — 0 으로 폴백하지 않는다.
#    --limit 0 이 없으면 bd 의 기본 상한 50 에서 잘려 51건째부터 조용히 안 세어진다.
#    타입으로 좁히지 않는다: in_progress 인 마일스톤·스토리도 진행 중인 일이다
#    (실측 2026-08-27 이 원장의 in_progress 는 전부 type=task 라 현재는 같은 값이다).
PCWD="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
if ! HROOT="$(cd "${PCWD:-.}" 2>/dev/null; bash "$PLUGIN_ROOT/lib/harness-root.sh" 2>/dev/null)" || [[ -z "$HROOT" ]]; then
  log ORACLE_FAIL "하네스 루트를 찾지 못했다(lib/harness-root.sh, cwd=${PCWD:-?}) — 0 으로 폴백하지 않고 통과한다"
  exit 0
fi
if ! oracle="$(HARNESS_ROOT="$HROOT" bash "$PLUGIN_ROOT/scripts/ledger.sh" list --status in_progress --limit 0 --json 2>/dev/null)"; then
  log ORACLE_FAIL "ledger.sh list 실패 — 0 으로 폴백하지 않고 통과한다"
  exit 0
fi
n="$(printf '%s' "$oracle" | jq 'if type == "array" then length else "NaN" end' 2>/dev/null || echo NaN)"
if ! [[ "$n" =~ ^[0-9]+$ ]]; then
  log ORACLE_FAIL "ledger.sh 출력이 JSON 배열이 아니다 — 0 으로 폴백하지 않고 통과한다"
  exit 0
fi

# 3b) Only ledger-confirmed bindings narrow the scope. Legacy TSV records
# are preserved but cannot prove a successful claim or runtime/repo ownership.
SCOPE="원장 전체(검증된 매핑 없음)"
if actor_state="$(node "$PLUGIN_ROOT/scripts/state.mjs" actors "$RUNTIME" "$PCWD" "$SID")"; then
  actors="$(printf '%s' "$actor_state" | jq -er '.actors | join("\n")')"
  narrowed="$(printf '%s' "$oracle" | jq --arg a "$actors" '($a | split("\n")) as $act | [.[] | . as $i | select($act | index($i.actor // $i.assignee // ""))]' 2>/dev/null)" && oracle="$narrowed"  # SCOPE_NARROW
  n="$(printf '%s' "$oracle" | jq 'length' 2>/dev/null || echo "$n")"
  SCOPE="이 세션의 actor $(printf '%s' "$actors" | tr '\n' ' ')"
else
  log SCOPE_FAIL "검증된 actor 매핑을 읽지 못했다 — legacy 상태는 미검증이고 사거리를 좁히지 않는다"
fi

# 4) 오라클 0 통과 — 막을 이유가 없다.
if [[ "$n" -eq 0 ]]; then
  log IDLE "in_progress 0건(범위: $SCOPE) — 막을 이유가 없다"
  exit 0
fi

# 4b) 검증 대기 통과 — 배치 모드(develop 3절)는 구현이 끝난 태스크를 닫지 않고 마지막 note 로
#     `VERIFY_PENDING: <커밋>` 을 남긴 채 in_progress 로 둔다. 그것은 하다 만 일이 아니라 배치
#     verify 를 기다리는 완료분이라, in_progress **전부**가 그 표시를 달고 있으면 막을 이유가
#     없다. 하나라도 없으면 종전대로 막는다. 표시는 notes 의 **마지막 비어 있지 않은 줄**이다 —
#     뒤에 note 가 하나라도 더 붙으면(재검토 지적 등) 표시가 풀려 다시 막힌다.
#     list --json 은 notes 를 이슈당 문자열 하나로 싣는다 (실측 2026-08-28, bd 1.2.2:
#     `bd show --json` 의 notes 와 md5 가 같다 — github·notion 어댑터도 같은 키로 맞췄다). 그래서
#     이슈별 재조회가 없다.
#     **표시는 둘이고 자리·규칙이 같다** (harness-o59 / harness-0uw). `DELEGATED: <마일스톤ID>` 는
#     오케스트레이터가 배치 위임 **직전**에 태스크마다 남기는 것이다 — 그 구간은 claim 은 됐지만
#     implementer 의 첫 커밋이 아직 없어 표시가 하나도 없고, 그래서 배치 위임 직후의 정지가
#     출구 셋 어디에도 해당하지 않은 채 막혔다(harness-0uw 의 관측). 둘 다 마지막 note 줄이므로
#     커밋 뒤의 VERIFY_PENDING 이 DELEGATED 를 자연히 교체한다.
#     아래 jq 두 줄이 판정이고 guardrail-check S7 의 A/B 가 **각각** 그 줄만 뺀 사본을 돌린다 —
#     빠지면 그 표시의 건수가 0 이라 통과가 아니라 막힘으로 기운다 (jq 오류도 같은 방향).
# 판정 대상은 notes 의 마지막 줄이 아니라 마지막 **표시 줄**이다. 같은 절차가 LGTM 수령·판정
# 근거를 note 로 남기라 요구하므로, 마지막 줄로 읽으면 그 산문이 표시를 덮어 매번 손으로
# 보충하게 된다(harness-k4wg). 표시 줄만 골라 그중 마지막을 보면 DELEGATED → VERIFY_PENDING →
# 재작업의 DELEGATED 순서는 그대로 살고 사이의 산문은 무해하다.
vp=0; dg=0
vp="$(printf '%s' "$oracle" | jq '[.[] | select((((.notes // "") | split("\n") | map(select(test("^(VERIFY_PENDING|DELEGATED)"))) | last) // "") | startswith("VERIFY_PENDING"))] | length' 2>/dev/null || echo 0)"
dg="$(printf '%s' "$oracle" | jq '[.[] | select((((.notes // "") | split("\n") | map(select(test("^(VERIFY_PENDING|DELEGATED)"))) | last) // "") | startswith("DELEGATED"))] | length' 2>/dev/null || echo 0)"
pending=$(( ${vp:-0} + ${dg:-0} ))
if [[ "$pending" -eq "$n" ]]; then
  log VERIFY_PENDING "in_progress ${n}건 전부 표시가 있다(검증 대기 ${vp}건 · 위임 직후 ${dg}건 · 범위: $SCOPE) — 막을 이유가 없다"
  exit 0
fi

# 5) 상한 포기 — 이 세션이 이미 상한만큼 되밀렸다. 막지 않는다.
blocks=0
if [[ -f "$LOG" ]]; then
  blocks="$(awk -F'\t' -v s="$SID" '$3 == "BLOCK"' "$LOG" | wc -l | tr -d ' ')"
fi
if [[ "$blocks" -ge "$MAX_BLOCKS" ]]; then
  # ${n} 의 중괄호는 장식이 아니다 — 뒤에 한글이 붙으면 bash 가 그것을 변수 이름의
  # 일부로 읽어 set -u 아래에서 unbound 로 죽는다 (실측: `$n건` → `n건: unbound variable`).
  log GAVE_UP "이 세션의 BLOCK $blocks 회가 상한 $MAX_BLOCKS 에 도달했다 — in_progress ${n}건이 남았지만 막지 않는다"
  exit 0
fi

# 6) 막음.
log BLOCK "in_progress ${n}건(표시 없음 $((n - ${pending:-0}))건 · 검증 대기 ${vp}건 · 위임 직후 ${dg}건 · 범위: $SCOPE) — 재주입 $((blocks + 1))/$MAX_BLOCKS"
jq -n --argjson n "$n" --argjson m "$((n - ${pending:-0}))" --arg runtime "$RUNTIME" --arg cwd "$PCWD" --arg sid "$SID" --arg state "$PLUGIN_ROOT/scripts/state.mjs" --arg scope "$SCOPE" --arg log "$LOG" \
  '{decision: "block", reason: ("범위 \($scope) 안에 in_progress 인 일이 \($n)건 남아 있고 그중 \($m)건은 표시가 없다. 마감했다면 ledger.sh close 로 닫고, 배치 모드로 구현만 끝난 것이면 ledger.sh note <ID> \"VERIFY_PENDING: <커밋 해시>\" 를, 배치 위임 직후라 아직 구현이 시작되지 않은 것이면 ledger.sh note <ID> \"DELEGATED: <마일스톤ID>\" 를 남기고, 사람을 기다리는 중이거나 의도적으로 멈추는 것이면 `node \($state | @sh) cancel \($runtime | @sh) \($cwd | @sh) \($sid | @sh)` 로 이 가드를 끈 뒤 종료하라(마커는 이 세션이 끝날 때까지 유효하다). 상한에 닿으면 가드가 스스로 물러난다 — " + $log + " 참고.")}'
exit 0
