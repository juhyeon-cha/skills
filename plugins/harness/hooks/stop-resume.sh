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
#   ralph-loop 이 9시간 동안 iteration=1 이었던 원인은 발화 실패가 아니라 등록 실패다:
#   111건 전부 hookCount=1 이고 실행된 명령은 ralph-cancel.sh 하나뿐이다. 플러그인 Stop
#   훅은 한 번도 실행되지 않았고, ralph-loop 은 installed_plugins.json 에 없으며 캐시에
#   .orphaned_at 이 있다. 즉 "발화하지 않는 계층"이 아니라 "설치되지 않은 플러그인"이었다.
#
# 다섯 경로가 각각 로그를 한 줄 남긴다: BLOCK · IDLE · RECURSE · GAVE_UP · ORACLE_FAIL.
# CANCEL 이 여섯째다 — 전용 마커로 끈 것도 남긴다. 조용히 꺼지는 장치는 있다고 믿게
# 만들어 없는 것보다 나쁘고, 그것이 harness-dg0.3.1 note 가 ralph-loop 을 탈락시킨 사유였다.
# VERIFY_PENDING 이 일곱째다 — 배치 모드의 검증 대기 완료분도, 위임 직후 아직 구현이 시작되지
# 않은 구간(DELEGATED)도 하다 만 일이 아니다. 두 표시를 한 경로가 건수를 갈라 적는다 (4b).
# NO_CLAIM 이 여덟째, SCOPE_FAIL 이 아홉째다 — 사거리 좁히기의 두 폴백이다 (3b).
#
# **사거리는 이 세션이 claim 한 actor 다** — 오라클은 여전히 원장을 읽지만 판정은 그중
# 이 세션의 몫으로 좁힌다. 잡지 않은 일로 막지 않는 것이 목적이고, 매핑을 못 읽으면
# 종전대로 원장 전체로 판정한다(SCOPE_FAIL). 천장은 docs/guardrail-verification.md 8절이 든다.
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# 상태 파일은 전부 **하네스 데이터 디렉토리** 아래다 (스토리 harness-lzs3 "결정됨" — 런타임 상태는
# 프로젝트 디렉토리 밖). 종전의 자리(본 체크아웃의 .claude/stop-resume.log · CWD 의 취소 마커)는
# 대상 레포 트리에 하네스 파일을 떨어뜨렸고, 워크트리가 지워지면 기록도 함께 사라졌다.
# 세션이 어느 레포·워크트리에서 열리든 한 자리에 모이므로 git 앵커도 CWD 폴백도 없다.
# **디렉토리를 만들 수 없으면 판정하지 않고 통과한다** — 정지 가드가 사람을 가두면 가드가 아니다.
# 그 사실은 stderr 한 줄로 남긴다(조용히 꺼지지 않는다).
DATA="${HARNESS_DATA_DIR:-$HOME/.claude/plugins/data/harness}"
if ! mkdir -p "$DATA" 2>/dev/null; then
  echo "정지 가드: 데이터 디렉토리를 만들 수 없다 ($DATA) — 판정하지 않고 통과한다" >&2
  exit 0
fi
LOG="$DATA/stop-resume.log"
# 세션→actor 매핑. hooks/guard.sh 가 claim 을 관측해 적는 파일이고(그쪽의
# "세션→actor 매핑 관측" 절) 여기서는 읽기만 한다. 경로 규약을 그쪽과 같게 둔다.
SESSION_ACTOR_LOG="${HARNESS_SESSION_ACTOR_LOG:-$HOME/.claude/harness-session-actor.tsv}"
# 전용 취소 마커. 루프 취소 마커($DATA/ralph-cancel)는 **읽지 않는다** —
# 소유가 다르고, 한 마커로 두 장치를 끄면 무엇을 껐는지 기록이 구분하지 못한다.
# **소유자는 파일 내용이 아니라 이름에 있다** (harness-o59). 이 경로는 사람이 touch 하는
# 입구이고, 처음 본 세션이 자기 자리($CANCEL.<session_id>)로 mv 한다 — 어느 경로도 남의
# 마커를 rm 하지 않으므로 동시에 도는 세션이 서로의 마커를 뺏지 못한다. 죽은 세션의 잔존은
# 소비 대상이 아니라 무해한 빈 파일이다.
CANCEL="$DATA/stop-resume-cancel"
# ponytail: 세션당 재주입 상한. 넘으면 막지 않고 GAVE_UP 을 남긴 뒤 통과한다 —
# 사람이 못 빠져나가는 가드는 가드가 아니다. 상한 계산에 새 상태 파일을 쓰지 않고
# 아래 log 가 남긴 BLOCK 줄을 센다(상태의 출처를 둘로 늘리지 않는다).
MAX_BLOCKS=3

# Stop 페이로드만 입력이다. 인자도 환경 변수도 상태의 출처로 쓰지 않는다.
payload="$(cat)"

SID="unknown"
log() {  # log <경로> <사유>
  printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SID" "$1" "$2" >> "$LOG"
}

# jq 가 없으면 페이로드도 원장 출력도 읽을 수 없다. 0 으로 폴백하지 않는다 —
# 읽지 못한 것을 "진행 중인 일 없음"으로 읽으면 가드가 조용히 꺼진다.
if ! command -v jq >/dev/null 2>&1; then
  log ORACLE_FAIL "jq 없음 — 페이로드와 원장을 읽을 수 없다. 0 으로 폴백하지 않고 통과한다"
  exit 0
fi

SID="$(printf '%s' "$payload" | jq -r '.session_id // "unknown"' 2>/dev/null || echo unknown)"
ACTIVE="$(printf '%s' "$payload" | jq -r 'if .stop_hook_active == true then "true" else "false" end' 2>/dev/null || echo false)"

# 1) 재귀 통과 — 이미 이 훅이 되민 턴이다. 다시 막으면 세션이 영영 멈추지 못한다.
if [[ "$ACTIVE" == "true" ]]; then
  log RECURSE "stop_hook_active=true — 이 훅이 되민 턴의 종료다. 다시 막지 않는다"
  exit 0
fi

# 2) 전용 취소 마커 — **세션 지속형이고 소유자는 파일 이름에 있다**. 빈 입구 마커(`touch`)를
#    처음 보면 이 세션의 자리로 mv 해 귀속시키고, 그 뒤로는 자기 자리만 보고 통과한다 —
#    무관한 태스크 하나가 in_progress 로 남아 있는 동안 턴마다 다시 켜야 하는 일을 없앤다.
#    **남의 자리는 읽지도 지우지도 않는다** — 옛 형태(소유자를 내용에 적고 남의 것이면 rm)는
#    실사용 귀속 8건이 전부 다른 세션에 소비되는 결과를 냈다(harness-o59 본문의 실측).
#    session_id 를 모르는 호출은 귀속시킬 자리가 없으므로 입구를 1회 소비하고, 그 사실을
#    로그가 다른 문면으로 구분해 남긴다.
CANCEL_MINE="$CANCEL.$SID"
if [[ -f "$CANCEL_MINE" ]]; then
  log CANCEL "전용 취소 마커($CANCEL_MINE)가 이 세션의 것이다 — 통과한다 (마커 유지)"
  exit 0
fi
if [[ -f "$CANCEL" ]]; then
  if [[ "$SID" == "unknown" ]]; then
    rm -f "$CANCEL" 2>/dev/null || true
    log CANCEL "입구 마커($CANCEL)를 소비했다 — session_id 를 몰라 귀속시킬 자리가 없다"
  elif mv "$CANCEL" "$CANCEL_MINE" 2>/dev/null; then  # CANCEL_OWN
    log CANCEL "입구 마커($CANCEL)를 이 세션의 자리($CANCEL_MINE)로 옮겼다 — 이 세션이 끝날 때까지 통과한다"
  else
    log CANCEL "입구 마커($CANCEL)를 이 세션의 자리로 옮기지 못했다(쓸 수 없다) — 귀속 없이 이번 정지를 허용한다"
  fi
  exit 0
fi

# 3) 오라클 — 원장의 in_progress 이슈 수.
#    원장은 lib/harness-root.sh 가 낸 하네스 루트에 `bd -C` 로 붙는다 — 세션이 대상 레포 클론
#    루트(redirect 없음)에서 열려도 bare bd 처럼 "원장 없음" 으로 꺼지지 않는다. 헬퍼의 CWD 는
#    페이로드의 cwd 다(워크트리면 redirect 를 따라간다). 못 찾으면 ORACLE_FAIL — 0 으로 폴백하지 않는다.
#    --limit 0 이 없으면 bd 의 기본 상한 50 에서 잘려 51건째부터 조용히 안 세어진다.
#    타입으로 좁히지 않는다: in_progress 인 마일스톤·스토리도 진행 중인 일이다
#    (실측 2026-08-27 이 원장의 in_progress 는 전부 type=task 라 현재는 같은 값이다).
PCWD="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
if ! HROOT="$(cd "${PCWD:-.}" 2>/dev/null; bash "$PLUGIN_ROOT/lib/harness-root.sh" 2>/dev/null)" || [[ -z "$HROOT" ]]; then
  log ORACLE_FAIL "하네스 루트를 찾지 못했다(lib/harness-root.sh, cwd=${PCWD:-?}) — 0 으로 폴백하지 않고 통과한다"
  exit 0
fi
if ! oracle="$(bd -C "$HROOT" list --status in_progress --limit 0 --json 2>/dev/null)"; then
  log ORACLE_FAIL "bd list 실패 — 0 으로 폴백하지 않고 통과한다"
  exit 0
fi
n="$(printf '%s' "$oracle" | jq 'if type == "array" then length else "NaN" end' 2>/dev/null || echo NaN)"
if ! [[ "$n" =~ ^[0-9]+$ ]]; then
  log ORACLE_FAIL "bd 출력이 JSON 배열이 아니다 — 0 으로 폴백하지 않고 통과한다"
  exit 0
fi

# 3b) 사거리 — 이 세션이 claim 한 actor 로 좁힌다.
#     매핑은 파생이 아니라 관측이다: actor 는 무작위 6자라 session_id 에서 계산될 수 없고
#     세션을 넘어 재사용되는 것이 이어받기 규약이라(harness:develop 3절 0번),
#     guard.sh 가 claim 이 지나가는 순간에 (session_id, actor) 를 적어 둔 것을 여기서 읽는다.
#     actor 의 원천은 스토리 bead 의 note `ACTOR: <레포> <값>` 이다(harness:develop 1절 "ACTOR
#     note" — 세션 단위가 (스토리, 레포)라 레포가 앞에 붙는다). **여기 오는 것은 `<값>` 뿐이다** —
#     claim 의 `--actor <값>` 을 guard.sh 가 관측하고, 원장의 assignee 도 그 값이다. 이 훅은
#     note 를 읽지 않으므로 레포 접두는 판정에 들어오지 않는다.
#
#     **폴백의 방향이 둘로 갈린다 — 하나로 합치면 가드가 조용히 꺼지거나 아무것도 안 고쳐진다.**
#       · 매핑을 **읽지 못했다**(없다·읽기 실패) → 종전대로 **원장 전체**로 판정한다(SCOPE_FAIL).
#         0 으로도 통과로도 폴백하지 않는다 — 읽지 못한 것은 "잡은 것이 없다"가 아니다.
#       · 읽었는데 이 세션의 actor 가 **하나도 없다** → 통과한다(NO_CLAIM). 잡은 것이 없는
#         세션은 하다 만 일도 없다. 이것이 이 좁히기가 실제로 고치는 자리다.
#     아래 표지가 달린 한 줄이 좁히기의 판정이고 guardrail-check S7 의 A/B 가 그 줄만 뺀
#     사본을 돌린다 — 빠지면 남의 actor 로도 다시 막힌다(좁히기 전의 동작).
SCOPE="원장 전체(매핑 없음)"
if actors="$(awk -F'\t' -v s="$SID" '$2 == s && $3 != "" { print $3 }' "$SESSION_ACTOR_LOG" 2>/dev/null | sort -u)"; then
  if [[ -z "$actors" ]]; then
    log NO_CLAIM "매핑($SESSION_ACTOR_LOG)에 이 세션의 actor 가 없다 — 잡은 것이 없는 세션은 하다 만 일도 없다. in_progress ${n}건은 남의 것이다"
    exit 0
  fi
  narrowed="$(printf '%s' "$oracle" | jq --arg a "$actors" '($a | split("\n")) as $act | [.[] | . as $i | select($act | index($i.assignee // ""))]' 2>/dev/null)" && oracle="$narrowed"  # SCOPE_NARROW
  # 좁힌 결과를 셀 수 없으면 좁히기 **전** 값을 쓴다 — 0 으로 폴백하지 않는다.
  n="$(printf '%s' "$oracle" | jq 'length' 2>/dev/null || echo "$n")"
  SCOPE="이 세션의 actor $(printf '%s' "$actors" | tr '\n' ' ')"
else
  log SCOPE_FAIL "매핑($SESSION_ACTOR_LOG)을 읽지 못했다 — 사거리를 좁히지 않고 종전대로 원장 전체로 판정한다(통과로 폴백하지 않는다)"
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
#     bd list --json 은 notes 를 이슈당 문자열 하나로 싣는다 (실측 2026-08-28, bd 1.2.2:
#     `bd show --json` 의 notes 와 md5 가 같다). 그래서 이슈별 재조회가 없다.
#     **표시는 둘이고 자리·규칙이 같다** (harness-o59 / harness-0uw). `DELEGATED: <마일스톤ID>` 는
#     오케스트레이터가 배치 위임 **직전**에 태스크마다 남기는 것이다 — 그 구간은 claim 은 됐지만
#     implementer 의 첫 커밋이 아직 없어 표시가 하나도 없고, 그래서 배치 위임 직후의 정지가
#     출구 셋 어디에도 해당하지 않은 채 막혔다(harness-0uw 의 관측). 둘 다 마지막 note 줄이므로
#     커밋 뒤의 VERIFY_PENDING 이 DELEGATED 를 자연히 교체한다.
#     아래 jq 두 줄이 판정이고 guardrail-check S7 의 A/B 가 **각각** 그 줄만 뺀 사본을 돌린다 —
#     빠지면 그 표시의 건수가 0 이라 통과가 아니라 막힘으로 기운다 (jq 오류도 같은 방향).
vp=0; dg=0
vp="$(printf '%s' "$oracle" | jq '[.[] | select(((.notes // "") | split("\n") | map(select(test("\\S"))) | last // "") | startswith("VERIFY_PENDING"))] | length' 2>/dev/null || echo 0)"
dg="$(printf '%s' "$oracle" | jq '[.[] | select(((.notes // "") | split("\n") | map(select(test("\\S"))) | last // "") | startswith("DELEGATED"))] | length' 2>/dev/null || echo 0)"
pending=$(( ${vp:-0} + ${dg:-0} ))
if [[ "$pending" -eq "$n" ]]; then
  log VERIFY_PENDING "in_progress ${n}건 전부 표시가 있다(검증 대기 ${vp}건 · 위임 직후 ${dg}건 · 범위: $SCOPE) — 막을 이유가 없다"
  exit 0
fi

# 5) 상한 포기 — 이 세션이 이미 상한만큼 되밀렸다. 막지 않는다.
blocks=0
if [[ -f "$LOG" ]]; then
  blocks="$(awk -F'\t' -v s="$SID" '$2 == s && $3 == "BLOCK"' "$LOG" | wc -l | tr -d ' ')"
fi
if [[ "$blocks" -ge "$MAX_BLOCKS" ]]; then
  # ${n} 의 중괄호는 장식이 아니다 — 뒤에 한글이 붙으면 bash 가 그것을 변수 이름의
  # 일부로 읽어 set -u 아래에서 unbound 로 죽는다 (실측: `$n건` → `n건: unbound variable`).
  log GAVE_UP "이 세션의 BLOCK $blocks 회가 상한 $MAX_BLOCKS 에 도달했다 — in_progress ${n}건이 남았지만 막지 않는다"
  exit 0
fi

# 6) 막음.
log BLOCK "in_progress ${n}건(표시 없음 $((n - ${pending:-0}))건 · 검증 대기 ${vp}건 · 위임 직후 ${dg}건 · 범위: $SCOPE) — 재주입 $((blocks + 1))/$MAX_BLOCKS"
jq -n --argjson n "$n" --argjson m "$((n - ${pending:-0}))" --arg cancel "$CANCEL" --arg scope "$SCOPE" --arg log "$LOG" \
  '{decision: "block", reason: ("범위 \($scope) 안에 in_progress 인 일이 \($n)건 남아 있고 그중 \($m)건은 표시가 없다. 마감했다면 bd close 로 닫고, 배치 모드로 구현만 끝난 것이면 bd note <ID> \"VERIFY_PENDING: <커밋 해시>\" 를, 배치 위임 직후라 아직 구현이 시작되지 않은 것이면 bd note <ID> \"DELEGATED: <마일스톤ID>\" 를 남기고, 사람을 기다리는 중이거나 의도적으로 멈추는 것이면 `touch \($cancel)` 로 이 가드를 끈 뒤 종료하라(마커는 이 세션이 끝날 때까지 유효하다). 상한에 닿으면 가드가 스스로 물러난다 — " + $log + " 참고.")}'
exit 0
