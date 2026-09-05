#!/bin/bash
# 전사를 읽는 자리 — 서브에이전트 전사(agent-*.jsonl)를 읽어 집계하고 A9 을 판정한다.
#
# natural-language(harness-pl7) 6.4 의 "사후 검출" 12건 중 9건이 이 자리 하나에 걸린다(D4). D2 가 사후 검출에
# 붙인 단서가 그 요구다 — "그 기록을 실제로 읽는 자리를 만들지 않으면 0". 기록은 있고
# 없던 것이 읽는 쪽이다. 이 파일이 그 하나이며, **전사를 파싱하는 자리는 여기뿐이다**
# (harness-dg0.6.18 ↔ harness-2a5.1.2 소유 합의: 회고는 이 자리를 호출만 한다).
#
# ── 훅이냐 사후 배치냐 — 실측으로 갈랐다 (2026-08-28, macOS Darwin 25.6.0 · zsh ·
#    Claude Code 2.1.247)
#
#   측정 명령 (스크래치 프로젝트에 SubagentStop 훅을 걸고 페이로드를 파일로 받았다):
#     $ mkdir -p "$SC/.claude"
#     $ cat > "$SC/.claude/dump.sh"        # 내용: cat > "$<프로젝트 디렉토리 변수>/subagentstop-payload.json" (Claude Code 가 훅에 주는 그 변수)
#     $ cat > "$SC/.claude/settings.json"  # hooks.SubagentStop -> dump.sh
#     $ cd "$SC" && claude -p "Launch one general-purpose subagent (Agent tool) …" \
#         --allowedTools "Agent,Task" --max-turns 10     # rc=0
#     $ python3 -c "import json;print(sorted(json.load(open('$SC/subagentstop-payload.json'))))"
#
#   결과 — **전사 경로는 실린다.** 페이로드의 키 14개 중 넷이 이 자리에 직접 쓰인다:
#     agent_transcript_path  … 그 서브에이전트 자신의 agent-*.jsonl 절대 경로
#     transcript_path        … 부모 세션 전사
#     agent_type / agent_id  … 역할과 인스턴스 식별자
#     last_assistant_message … **응답 본문**("probe-ok" 이 그대로 실렸다)
#
#   그래서 훅도 가능하다. 그런데도 사후 배치를 택한 이유는 셋이다.
#     1. 이 자리가 내야 하는 것은 집계다(역할별 신호 계수·도구 분포·인스턴스 재사용).
#        SubagentStop 훅은 한 번에 한 위임만 보므로 집계를 내려면 자기 상태 파일을
#        따로 들어야 한다 — 원천이 이미 파일로 있는데 파생 상태를 하나 더 만드는 꼴이다.
#     2. 회고는 지나간 스토리 구간을 본다. 훅은 그 구간이 지난 뒤에 세워도 소용이 없고,
#        배치는 이미 쌓인 전사를 그대로 읽는다.
#     3. 둘 다 세우면 전사를 파싱하는 자리가 둘이 된다 — 소유 합의가 막으려던 것이다.
#
#   **natural-language(harness-pl7) 의 판정 근거 하나가 이 실측으로 흔들린다(문서는 닫힌 산출물이라 고치지 않는다).**
#   R9·A9·S25 의 Q1✗ 근거는 "서브에이전트 **응답 본문**이 훅에 나타난다는 관측이 없다"
#   였다. last_assistant_message 로 나타난다. 다만 SubagentStop 은 응답이 나온 뒤에
#   불리므로 **차단 시점의 도구 경계**는 여전히 아니다 — 셋의 "불가능" 판정 자체가
#   뒤집히는지는 이 태스크의 범위 밖이고, 관측만 여기 남긴다.
#
# ── 무엇을 판정하는가
#
#   A9 — "역할 응답의 첫 줄은 정확히 `SIGNAL: <VALUE>`". 어휘는 손으로 적지 않고
#   agents/*.md 에서 파생한다(역할 정의가 바뀌면 이 검사도 따라간다).
#   판정 대상은 **완료된** 역할 위임뿐이다 — 모집단을 그렇게 정의하면 감사 자신이
#   띄운(그리고 아직 도는) 전사가 섞이지 않는다. 값을 갱신하는 대신 정의로 닫는 형태다.
#
# ── 판정에 도달하지 못하면 침묵하지 않는다
#
#   모집단 0건 · 전사 파일 부재 · python3 부재 · --since 해석 실패는 전부 stderr 에
#   `UNREACHED: …` 한 줄을 남기고 rc=2 로 끝난다. 0건은 0건이라고 말한다.
#
# 종료 코드: 0 판정 도달·위반 없음 / 1 위반 있음 / 2 판정 미도달
set -euo pipefail

# 플러그인 루트 — 역할 정의(agents/*.md)의 자리. 하네스 루트(lib/harness-root.sh)는 필요 없다:
# 전사는 ~/.claude/projects 아래에 있고 이 검사는 원장을 읽지 않는다.
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROJECTS="${HOME}/.claude/projects"
SINCE=""
SESSION=""
JSON=0
SELF=0

usage() {
  cat <<'USAGE'
사용법: checks/transcript-check.sh [--projects DIR] [--since ISO8601|Nd|Nh] [--session UUID] [--json]
        checks/transcript-check.sh --self-check

  --projects DIR   전사 루트 (기본: ~/.claude/projects — 그 아래 프로젝트 디렉토리
                   전부를 훑는다). --self-check 이 임시 디렉토리에 만든 대조군을 짚으려
                   자기를 재귀 호출할 때 쓰는 옵션이고, 회고는 쓰지 않는다.
  --since          이 시각 이후에 끝난 위임만 본다. 회고가 스토리 구간을 자를 때 쓴다.
  --session UUID   이 세션이 위임한 것만 본다. 세션 UUID 는 전사 경로에 그대로
                   있으므로(<projects>/<프로젝트>/<UUID>/subagents/) 디렉토리 한 겹을
                   고르는 일이다. 기본은 전체 — 스크립트는 자기를 부른 세션을 알 수
                   없으므로 자동 감지하지 않는다. 값은 회고가 넘긴다.
  --json           기계 판독 출력. 회고는 이쪽을 쓴다.
  --self-check     부정 대조군 — 위반을 심은 사본에서 판정이 뒤집히는지 확인한다.

  세 필터는 서로를 무시하지 않고 **교집합**이다: --projects 가 고른 루트 아래에서,
  --session 이 고른 세션의, --since 이후에 끝난 위임. 어느 하나를 주어도 나머지가
  꺼지지 않으므로, 좁힌 결과가 0건이면 통과가 아니라 rc=2(판정 미도달)로 끝난다.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --projects|--since|--session)
      # 빈 값도 "값이 없다"로 읽는다 — 빈 문자열은 필터가 꺼진 것과 구분되지 않아,
      # 좁히려던 호출이 조용히 전체 훑기로 넓어진다.
      [[ $# -ge 2 && -n "$2" ]] || { echo "UNREACHED: $1 에 값이 없다 — 판정에 도달하지 못했다" >&2; exit 2; }
      case "$1" in
        --projects) PROJECTS="$2" ;;
        --since)    SINCE="$2" ;;
        --session)  SESSION="$2" ;;
      esac
      shift 2 ;;
    --json)     JSON=1; shift ;;
    --self-check) SELF=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "UNREACHED: 알 수 없는 인자 '$1' — 판정에 도달하지 못했다" >&2; usage >&2; exit 2 ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "UNREACHED: python3 이 없다 — 전사를 파싱하지 못했다. 조용히 통과하지 않는다" >&2
  exit 2
fi

# ── 부정 대조군 ───────────────────────────────────────────────────────
# 같은 입력에서 위반 한 줄만 흔들어 판정이 rc=0 -> rc=1 로 뒤집히는지 본다.
# 사본이 원본과 같거나 만들어지지 않으면 그 자체를 실패로 읽는다(agile.md).
if [[ "$SELF" -eq 1 ]]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  python3 - "$TMP" <<'FIXTURE'
import json, os, sys
tmp = sys.argv[1]
SID = "00000000-0000-0000-0000-0000000000ff"
AID = "aSELFCHECK0000001"

def build(name, final_text, asynchronous=False):
    proj = os.path.join(tmp, name, "-fixture-project")
    os.makedirs(os.path.join(proj, SID, "subagents"))
    # 부모 세션 전사 — 끝난 evaluator 위임 하나. 끝을 적는 형태가 둘이라 둘 다 시험한다.
    if asynchronous:
        head = {"type": "user", "sessionId": SID, "timestamp": "2026-08-28T00:00:00.000Z",
                "message": {"content": "<task-notification>\n<task-id>%s</task-id>\n<status>completed</status>\n</task-notification>" % AID}}
    else:
        head = {"type": "user", "sessionId": SID, "timestamp": "2026-08-28T00:00:00.000Z",
                "message": {"content": [{"type": "tool_result", "tool_use_id": "toolu_fixture"}]},
                "toolUseResult": {"agentId": AID, "agentType": "evaluator", "status": "completed",
                                  "content": [{"type": "text", "text": final_text}]}}
    with open(os.path.join(proj, SID + ".jsonl"), "w", encoding="utf-8") as f:
        f.write(json.dumps(head, ensure_ascii=False) + "\n")
    # 서브에이전트 전사 — 도구 호출 한 번과 최종 응답 한 번.
    with open(os.path.join(proj, SID, "subagents", "agent-%s.jsonl" % AID), "w", encoding="utf-8") as f:
        f.write(json.dumps({"type": "assistant", "attributionAgent": "evaluator",
                            "message": {"content": [{"type": "tool_use", "name": "Bash", "input": {}}]}},
                           ensure_ascii=False) + "\n")
        f.write(json.dumps({"type": "assistant", "attributionAgent": "evaluator",
                            "message": {"content": [{"type": "text", "text": final_text}]}},
                           ensure_ascii=False) + "\n")

DIRTY = "판정을 정리한다.\n\nSIGNAL: MATCH\n\n근거: 고정 픽스처.\n"
build("clean", "SIGNAL: MATCH\n\n근거: 고정 픽스처.\n")
# 흔든 곳은 한 줄이다 — SIGNAL 앞에 요약 한 줄을 둔다(A9 이 금지하는 바로 그 형태).
build("dirty", DIRTY)
# 같은 위반을 비동기 형태(task-notification)로 한 번 더. 모집단 경로가 죽으면 이것이 통과한다.
build("async", DIRTY, asynchronous=True)
os.makedirs(os.path.join(tmp, "empty"))
FIXTURE

  CLEAN="$TMP/clean/-fixture-project/00000000-0000-0000-0000-0000000000ff/subagents/agent-aSELFCHECK0000001.jsonl"
  DIRTY="$TMP/dirty/-fixture-project/00000000-0000-0000-0000-0000000000ff/subagents/agent-aSELFCHECK0000001.jsonl"
  if ! { [[ -s "$CLEAN" ]] && [[ -s "$DIRTY" ]] && ! cmp -s "$CLEAN" "$DIRTY"; }; then
    echo "  ✗ 사본 성립 — 두 픽스처가 없거나 서로 같다. 대조군이 공허하다" >&2
    exit 1
  fi
  echo "  ✓ 사본 성립 — 두 픽스처가 실재하고 서로 다르다"

  rc_clean=0; "$0" --projects "$TMP/clean" >/dev/null 2>&1 || rc_clean=$?
  rc_dirty=0; "$0" --projects "$TMP/dirty" >/dev/null 2>&1 || rc_dirty=$?
  rc_async=0; "$0" --projects "$TMP/async" >/dev/null 2>&1 || rc_async=$?
  emsg="$("$0" --projects "$TMP/empty" 2>&1 >/dev/null)" || true
  rc_empty=0; "$0" --projects "$TMP/empty" >/dev/null 2>&1 || rc_empty=$?
  # 새 옵션도 픽스처가 덮는다 — 짚으면 위반이 살아 있고, 없는 세션이면 미도달로 끝난다.
  rc_sess=0; "$0" --projects "$TMP/dirty" --session 00000000-0000-0000-0000-0000000000ff >/dev/null 2>&1 || rc_sess=$?
  nmsg="$("$0" --projects "$TMP/dirty" --session 11111111-1111-1111-1111-111111111111 2>&1 >/dev/null)" || true
  rc_nosess=0; "$0" --projects "$TMP/dirty" --session 11111111-1111-1111-1111-111111111111 >/dev/null 2>&1 || rc_nosess=$?

  ok=0
  [[ "$rc_clean" -eq 0 ]] && echo "  ✓ 정상 사본 rc=0 (판정에 도달했고 위반 없음)" || { echo "  ✗ 정상 사본 rc=$rc_clean (0 이어야 한다)" >&2; ok=1; }
  [[ "$rc_dirty" -eq 1 ]] && echo "  ✓ 위반 사본 rc=1 — 판정이 뒤집혔다" || { echo "  ✗ 위반 사본 rc=$rc_dirty (1 이어야 한다) — 대조군이 공허하다" >&2; ok=1; }
  [[ "$rc_async" -eq 1 ]] && echo "  ✓ 비동기 형태(task-notification)의 같은 위반도 rc=1 — 모집단 경로가 살아 있다" || { echo "  ✗ 비동기 사본 rc=$rc_async (1 이어야 한다) — 비동기 위임이 모집단에서 통째로 빠진다" >&2; ok=1; }
  [[ "$rc_empty" -eq 2 ]] && echo "  ✓ 빈 사본 rc=2 — 판정 미도달" || { echo "  ✗ 빈 사본 rc=$rc_empty (2 이어야 한다)" >&2; ok=1; }
  [[ "$rc_sess" -eq 1 ]] && echo "  ✓ --session 이 픽스처 세션을 짚어도 위반 rc=1 — 세션 한정이 모집단을 잃지 않는다" || { echo "  ✗ --session 지정 rc=$rc_sess (1 이어야 한다) — 세션 한정이 모집단을 통째로 날렸다" >&2; ok=1; }
  { [[ "$rc_nosess" -eq 2 ]] && [[ "$nmsg" == UNREACHED:* ]]; } && echo "  ✓ 없는 세션은 rc=2 + UNREACHED — 조용히 통과하지 않는다" || { echo "  ✗ 없는 세션 rc=$rc_nosess / '${nmsg%%$'\n'*}' (rc=2 와 UNREACHED 여야 한다)" >&2; ok=1; }
  case "$emsg" in
    UNREACHED:*) echo "  ✓ 미도달이 로그 한 줄로 남는다: ${emsg%%$'\n'*}" ;;
    *) echo "  ✗ 미도달인데 UNREACHED 줄이 없다 — 침묵과 구분되지 않는다" >&2; ok=1 ;;
  esac
  exit "$ok"
fi

python3 - "$PROJECTS" "$SINCE" "$JSON" "$ROOT" "$SESSION" <<'PY'
import glob, json, os, re, sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

projects, since_raw, as_json, root = sys.argv[1], sys.argv[2], sys.argv[3] == "1", sys.argv[4]
session = sys.argv[5]
# 세 필터는 교집합이다. --session 은 --projects 아래에서 세션 디렉토리 한 겹을 고를 뿐이라
# --projects 를 덮지 않고, 시간 창(--since)은 그렇게 좁혀진 모집단 위에서 그대로 걸린다.
SESSION_GLOB = session or "*"

unreached = []
def unreach(msg):
    """판정에 도달하지 못한 사유. 침묵과 구분되는 유일한 출력이라 반드시 한 줄씩 남긴다."""
    unreached.append(msg)
    print("UNREACHED: " + msg, file=sys.stderr)

# ── 역할별 SIGNAL 어휘는 역할 정의에서 파생한다. 손으로 적으면 정의가 바뀔 때 조용히 낡는다.
VOCAB = {}
for path in sorted(glob.glob(os.path.join(root, "agents/*.md"))):
    role = os.path.basename(path)[:-3]
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except OSError as e:
        unreach("역할 정의를 읽지 못했다: %s (%s)" % (path, e))
        continue
    for line in lines:
        if "`<VALUE>`" in line and "중 하나" in line:
            vals = set(re.findall(r"`([A-Z][A-Z_]+)`", line))
            if vals:
                VOCAB[role] = vals
            break
if not VOCAB:
    unreach("%s/agents/*.md 에서 SIGNAL 어휘를 파생하지 못했다 — 판정 대상 역할이 0개다" % root)
    sys.exit(2)

since = None
if since_raw:
    m = re.fullmatch(r"(\d+)([dh])", since_raw)
    if m:
        n = int(m.group(1))
        since = datetime.now(timezone.utc) - (timedelta(days=n) if m.group(2) == "d" else timedelta(hours=n))
    else:
        try:
            since = datetime.fromisoformat(since_raw.replace("Z", "+00:00"))
            if since.tzinfo is None:
                since = since.replace(tzinfo=timezone.utc)
        except ValueError:
            unreach("--since 값을 해석하지 못했다: %s (ISO8601 또는 Nd/Nh)" % since_raw)
            sys.exit(2)

def parse_ts(s):
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None

def records(path):
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except ValueError:
                continue  # 전사 마지막 줄은 기록 중일 수 있다

def first_text(rec):
    """content 배열의 첫 type=='text' 블록. thinking 블록이 앞에 오면 인덱스로는 어긋난다."""
    content = (rec.get("message") or {}).get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        for b in content:
            if isinstance(b, dict) and b.get("type") == "text":
                return b.get("text", "")
    return None

# ── 모집단: 부모 세션 전사가 **끝났다고 기록한** 위임. 진행 중인 위임은 여기 없다 —
#    감사를 돌리는 그 세션 자신의 서브에이전트가 섞이지 않는 것이 이 정의의 값어치다.
#
#    끝을 적는 형태가 둘이다. 하나만 보면 조용히 절반을 잃는다 (실측 2026-08-28,
#    이 세션의 위임 109건: 동기 42건 · 비동기 67건).
#      동기  : tool_result 의 toolUseResult.status == "completed" (agentType 도 함께 실린다)
#      비동기: 그 자리에는 status == "async_launched" 만 있고 agentType 이 없다.
#              끝은 나중에 <task-notification> 의 <status>completed</status> 로 온다.
#    그래서 역할은 결과 레코드가 아니라 **전사 자신의 attributionAgent** 에서 읽는다 —
#    두 형태에 공통이고, 파일당 정확히 하나다.
sessions_glob = os.path.join(projects, "*", SESSION_GLOB + ".jsonl")
sessions = sorted(glob.glob(sessions_glob))

# 전사 파일은 세션 디렉토리 옆이 아니라 **전 프로젝트에서** 찾는다. 같은 위임이 두 세션
# 전사에 실리는 경우가 실재하기 때문이다 — 세션이 다른 프로젝트 디렉토리로 이어지면
# 결과 레코드는 양쪽에 남고 전사 파일은 한쪽에만 있다(실측: a2cb1305e5fb1c0ba 가
# -Users-juhyeon-workspace-harness 와 …-bridge-cse-… 양쪽에 있고 파일은 뒤엣것 아래에만 있다).
# 세션 디렉토리를 기준으로 풀면 그 절반이 "파일 없음" 으로 새어 나간다.
transcripts = {}
for f in glob.glob(os.path.join(projects, "*", SESSION_GLOB, "subagents", "agent-*.jsonl")):
    transcripts[os.path.basename(f)[len("agent-"):-len(".jsonl")]] = f

# ── 토큰 ─────────────────────────────────────────────────────────────
# 이 자리가 재는 값 중 유일하게 **돈으로 환산되는** 것이다. 하네스는 응답 상한·위임 상한·
# 병렬 호출·배치 verify 로 이 값을 줄이려 하는데, 줄었는지를 보는 수단이 없었다 —
# 규율이 자기 효과를 실증하지 않는 자리였다. 근거는 harness-guau.1.1.
#
# **레코드가 아니라 message.id 로 센다.** 한 응답이 도구를 여럿 부르면 전사 기록기가
# 레코드를 쪼개고 쪼갠 레코드가 같은 usage 를 함께 든다 — 그대로 더하면 **병렬 호출을
# 많이 하는 역할일수록 값이 부풀어**, 이 계수가 답해야 할 비교(역할 간 비용)가 뒤집힌다.
# 도구 분포가 per_msg 로 묶는 것과 같은 현상이고 같은 키를 쓴다.
USAGE_KEYS = ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")

def add_usage(acc, seen, rec):
    if rec.get("type") != "assistant":
        return
    msg = rec.get("message") or {}
    u = msg.get("usage")
    if not isinstance(u, dict):
        return
    key = msg.get("id")
    if key is not None:
        if key in seen:
            return
        seen.add(key)
    for k in USAGE_KEYS:
        v = u.get(k)
        acc[k] += v if isinstance(v, int) else 0
    acc["requests"] += 1

tokens_role = defaultdict(Counter)
seen_role = defaultdict(set)
tokens_orch = Counter()
seen_orch = set()
delegations = Counter()

NOTIFY_ID = re.compile(r"<task-id>([0-9a-zA-Z]+)</task-id>")
NOTIFY_ST = re.compile(r"<status>(\w+)</status>")

def in_window(rec):
    """--since 창 안인가. 창이 없으면 전부 안이다."""
    if since is None:
        return True
    rts = parse_ts(rec.get("timestamp"))
    return rts is not None and rts >= since

runs = {}
notify_orphan = set()
for sp in sessions:
    try:
        recs = list(records(sp))
    except OSError as e:
        unreach("세션 전사를 열지 못했다: %s (%s)" % (sp, e))
        continue
    for rec in recs:
        # 오케스트레이터 토큰. 위임 판정과 달리 단위가 **세션 전사의 응답**이라 위임
        # 하나에 귀속되지 않는다 — 상시 로드와 누적된 위임 보고가 여기 실린다.
        if in_window(rec):
            add_usage(tokens_orch, seen_orch, rec)
        done = None
        tur = rec.get("toolUseResult")
        if isinstance(tur, dict) and tur.get("agentId") and tur.get("status") == "completed":
            done = (tur["agentId"], tur.get("agentType"))
        else:
            content = (rec.get("message") or {}).get("content")
            if isinstance(content, str) and "<task-notification>" in content:
                mid, mst = NOTIFY_ID.search(content), NOTIFY_ST.search(content)
                if mid and mst and mst.group(1) == "completed":
                    # 같은 알림 형태를 **서브에이전트가 아닌 작업**(백그라운드 셸 등)도 쓴다.
                    # 그쪽은 전사가 없어 역할을 가릴 수 없으므로 판정에서 빼되, 조용히 빼지
                    # 않고 머리줄에 건수로 남긴다.
                    if mid.group(1) in transcripts:
                        done = (mid.group(1), None)
                    else:
                        notify_orphan.add(mid.group(1))
        if done is None:
            continue
        aid, atype = done
        ts = parse_ts(rec.get("timestamp"))
        if since is not None and (ts is None or ts < since):
            continue
        runs[aid] = {"role": atype, "ts": rec.get("timestamp"), "path": transcripts.get(aid)}

if not sessions:
    unreach("세션 전사가 0개다: %s — 판정에 도달하지 못했다" % sessions_glob)
if not runs:
    unreach("범위 안에서 완료된 위임이 0건이다 (since=%s, session=%s) — 판정에 도달하지 못했다"
            % (since_raw or "전체", session or "전체"))

signals = defaultdict(Counter)
tools = defaultdict(lambda: {"calls": 0, "responses": 0, "parallel": 0, "max_per_response": 0, "top": Counter()})
combos = Counter()
verdicts = Counter()
violations = []
judged = 0

for aid, run in sorted(runs.items(), key=lambda kv: kv[1]["ts"] or ""):
    path = run["path"]
    if not path or not os.path.exists(path):
        # 역할을 아는 건만 미도달로 센다. 비동기 위임은 결과 레코드에 역할이 없어 여기서
        # 가릴 수 없으므로 함께 남긴다 — 판정하지 못한 것을 판정했다고 말하지 않는다.
        if run["role"] is None or run["role"] in VOCAB:
            unreach("위임 %s (%s) 의 전사 파일이 없다 — 이 건은 판정하지 못했다" % (aid, run["role"] or "역할 미상"))
        continue
    try:
        recs = list(records(path))
    except OSError as e:
        unreach("위임 %s 의 전사를 읽지 못했다 (%s)" % (aid, e))
        continue

    # 역할은 전사 자신이 든다 — 동기·비동기 두 형태에 공통인 유일한 출처다.
    role = run["role"]
    for rec in recs:
        if rec.get("attributionAgent"):
            role = rec["attributionAgent"]
            break
    if role is None:
        # 전사가 있는데 역할을 못 가린 건. 조용히 빼면 "역할 에이전트가 아니었다" 와
        # 구분되지 않는다 — 비동기 위임의 역할은 attributionAgent 하나에만 걸려 있어,
        # 그 필드가 사라지면 모집단이 통째로 줄면서 미도달 0건·위반 0건·rc=0 이 된다.
        unreach("위임 %s 의 역할을 가리지 못했다 (attributionAgent·agentType 둘 다 없다) — 이 건은 판정하지 못했다" % aid)
        continue
    if role not in VOCAB:
        continue  # 역할 에이전트가 아니다 (general-purpose · Explore 등). A9 의 대상이 아니다

    texts = []
    # 한 응답이 도구를 여럿 부르면 **전사 기록기가 레코드를 쪼갠다** — 쪼개진 레코드는
    # 같은 message.id 를 공유한다. 레코드로 세면 "응답당 1.00 · 최대 1" 이 입력과 무관한
    # 항등식이 되어, 이 자리가 답해야 할 질문(병렬 호출을 하는가)에 언제나 "안 한다" 고
    # 답한다 (실측 2026-08-28: 레코드 28,111개가 전부 tool_use 1개).
    per_msg = Counter()
    delegations[role] += 1
    for rec in recs:
        if rec.get("type") != "assistant":
            continue
        add_usage(tokens_role[role], seen_role[role], rec)
        msg = rec.get("message") or {}
        content = msg.get("content")
        blocks = content if isinstance(content, list) else []
        n_tool = 0
        for b in blocks:
            if isinstance(b, dict) and b.get("type") == "tool_use":
                n_tool += 1
                tools[role]["top"][b.get("name", "?")] += 1
        if n_tool:
            # id 가 없으면 레코드 자신을 키로 쓴다 — 묶지 못한 것을 묶은 척하지 않는다.
            per_msg[msg.get("id") or rec.get("requestId") or rec.get("uuid") or id(rec)] += n_tool
        t = first_text(rec)
        if t and t.strip():
            texts.append(t)

    for n in per_msg.values():
        tools[role]["calls"] += n
        tools[role]["responses"] += 1
        tools[role]["max_per_response"] = max(tools[role]["max_per_response"], n)
        if n > 1:
            tools[role]["parallel"] += 1

    # 앵커는 텍스트 블록 머리의 SIGNAL 이다. 본문에 인용된 낱말까지 세면 값이 크게 틀린다.
    sigs = [m.group(1) for m in (re.match(r"SIGNAL:\s*([A-Z_]+)", t.lstrip()) for t in texts) if m]
    for s in sigs:
        signals[role][s] += 1
    if len(sigs) > 1:
        combos[",".join(sigs)] += 1

    judged += 1
    if not texts:
        verdicts["EMPTY"] += 1
        violations.append({"role": role, "agent_id": aid, "kind": "EMPTY", "detail": "응답 텍스트가 없다"})
        continue
    # ponytail: lstrip 이라 선행 공백·빈 줄은 눈감아 준다. 잡는 것은 SIGNAL 앞의 **내용**이다.
    head = texts[-1].lstrip().split("\n", 1)[0].strip()
    m = re.fullmatch(r"SIGNAL: ([A-Z_]+)", head)
    if not m:
        verdicts["NO_SIGNAL"] += 1
        violations.append({"role": role, "agent_id": aid, "kind": "NO_SIGNAL", "detail": head[:80]})
    elif m.group(1) not in VOCAB[role]:
        verdicts["BAD_VALUE"] += 1
        violations.append({"role": role, "agent_id": aid, "kind": "BAD_VALUE", "detail": m.group(1)})
    else:
        verdicts["OK"] += 1

# 판정이 0건인데 사유가 한 줄도 없으면 침묵과 구분되지 않는다. 남길 사유가 없어도 그 사실을 남긴다.
if judged == 0 and not unreached:
    unreach("범위 안에 판정할 역할 위임이 0건이다 (끝난 위임 %d건, since=%s, session=%s)"
            % (len(runs), since_raw or "전체", session or "전체"))

def tok(acc, n):
    """토큰 집계 한 덩어리. `billed_input` 은 세 입력 열의 합이다 — 단가가 서로 달라
    더한 값 자체가 요금은 아니지만, 열을 따로 낸 채로도 '입력이 얼마나 컸나' 를 한 수로
    비교할 수 있게 둔다. 요금 환산은 여기서 하지 않는다 — 단가가 트리 밖에 있다."""
    d = dict((k, acc[k]) for k in USAGE_KEYS)
    d["requests"] = acc["requests"]
    d["billed_input"] = acc["input_tokens"] + acc["cache_creation_input_tokens"] + acc["cache_read_input_tokens"]
    d["delegations"] = n
    d["per_delegation"] = (dict((k, round(acc[k] / float(n), 1)) for k in USAGE_KEYS) if n else None)
    return d

report = {
    "projects": projects,
    "since": since_raw or None,
    "session": session or None,
    "sessions": len(sessions),
    "completed_delegations": len(runs),
    "notifications_without_transcript": len(notify_orphan),
    "judged": judged,
    "unreached": unreached,
    "vocab": {r: sorted(v) for r, v in sorted(VOCAB.items())},
    "signals": {r: dict(signals[r]) for r in sorted(VOCAB)},
    "tools": {r: {"calls": tools[r]["calls"], "responses_with_tools": tools[r]["responses"],
                  "calls_per_response": round(tools[r]["calls"] / tools[r]["responses"], 2) if tools[r]["responses"] else 0,
                  "parallel_responses": tools[r]["parallel"],
                  "max_per_response": tools[r]["max_per_response"],
                  "top": dict(tools[r]["top"].most_common(5))} for r in sorted(VOCAB)},
    "tokens": {"roles": {r: tok(tokens_role[r], delegations[r]) for r in sorted(VOCAB)},
               "orchestrator": tok(tokens_orch, 0)},
    "reuse": {"multi_signal_transcripts": sum(combos.values()), "combos": dict(combos.most_common(5))},
    "a9": {"verdicts": {k: verdicts[k] for k in ("OK", "NO_SIGNAL", "BAD_VALUE", "EMPTY")},
           "violations": violations},
}

# 판정에 한 건도 도달하지 못했으면 rc=2. 위반 0건과 검사 미실행이 같은 값을 내지 않게 한다.
rc = 2 if judged == 0 else (1 if (verdicts["NO_SIGNAL"] + verdicts["BAD_VALUE"] + verdicts["EMPTY"]) else 0)
report["rc"] = rc

if as_json:
    print(json.dumps(report, ensure_ascii=False, indent=2))
    sys.exit(rc)

print("전사 감사 — %s (since=%s · session=%s)" % (projects, since_raw or "전체", session or "전체"))
print("  세션 전사 %d개 · 끝난 위임 %d건 · 그중 역할 위임을 판정한 것 %d건 · 미도달 %d건"
      % (len(sessions), len(runs), judged, len(unreached)))
print("  전사가 없는 완료 알림 %d건은 뺐다 — 서브에이전트가 아닌 작업(백그라운드 셸 등)이 같은 형태로 온다."
      % len(notify_orphan))
print("  총계는 살아 있는 디렉토리라 세션마다 는다 — 근거로 쓸 것은 비율이다.")

print("\n  [역할별 신호 계수]")
for r in sorted(VOCAB):
    c = signals[r]
    body = " · ".join("%s %d" % (k, v) for k, v in c.most_common()) if c else "0건"
    print("    %-12s %s" % (r, body))

print("\n  [역할별 도구 사용]")
for r in sorted(VOCAB):
    t = tools[r]
    if not t["responses"]:
        print("    %-12s 0건" % r)
        continue
    print("    %-12s 호출 %d · 도구를 쓴 응답 %d · 응답당 %.2f · 최대 %d · 병렬(2개 이상) %d (%.1f%%) · 상위 %s"
          % (r, t["calls"], t["responses"], t["calls"] / t["responses"], t["max_per_response"],
             t["parallel"], 100.0 * t["parallel"] / t["responses"],
             ", ".join("%s %d" % kv for kv in t["top"].most_common(3))))

print("\n  [토큰]  message.id 로 센다 — 쪼개진 레코드의 중복을 뺀 값이다")
def n_(v):
    return "{:,}".format(v)
for r in sorted(VOCAB):
    a, n = tokens_role[r], delegations[r]
    if not a["requests"]:
        print("    %-12s 0건" % r)
        continue
    print("    %-12s 요청 %s · 캐시읽기 %s · 캐시쓰기 %s · 출력 %s · 위임 %d건"
          % (r, n_(a["requests"]), n_(a["cache_read_input_tokens"]),
             n_(a["cache_creation_input_tokens"]), n_(a["output_tokens"]), n))
    print("    %-12s   위임당 캐시읽기 %s · 출력 %s"
          % ("", n_(int(a["cache_read_input_tokens"] / n)), n_(int(a["output_tokens"] / n))))
o = tokens_orch
if o["requests"]:
    print("    %-12s 요청 %s · 캐시읽기 %s · 캐시쓰기 %s · 출력 %s"
          % ("오케스트레이터", n_(o["requests"]), n_(o["cache_read_input_tokens"]),
             n_(o["cache_creation_input_tokens"]), n_(o["output_tokens"])))
    print("    %-12s   세션 전사 단위다 — 위임에 귀속되지 않고, 상시 로드와 누적된 위임 보고가 여기 실린다" % "")
else:
    print("    %-12s 0건 — 세션 전사에 usage 가 없다" % "오케스트레이터")

print("\n  [인스턴스 재사용]")
n_reuse = sum(combos.values())
if n_reuse == 0:
    print("    SIGNAL 이 둘 이상인 전사 0건 / 판정 %d건 — 재사용 관측 없음" % judged)
else:
    print("    SIGNAL 이 둘 이상인 전사 %d건 / 판정 %d건" % (n_reuse, judged))
    for combo, n in combos.most_common(5):
        print("      %s : %d" % (combo, n))

print("\n  [A9 판정 — 역할 응답의 첫 줄은 정확히 SIGNAL: <VALUE>]")
print("    OK %d · NO_SIGNAL %d · BAD_VALUE %d · EMPTY %d"
      % (verdicts["OK"], verdicts["NO_SIGNAL"], verdicts["BAD_VALUE"], verdicts["EMPTY"]))
if violations:
    for v in violations:
        print("    ✗ %s %s [%s] %s" % (v["role"], v["agent_id"], v["kind"], v["detail"]))
else:
    print("    위반 0건")

print("\n  rc=%d (0 위반 없음 / 1 위반 있음 / 2 판정 미도달)" % rc)
sys.exit(rc)
PY
