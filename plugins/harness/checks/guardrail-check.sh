#!/usr/bin/env bash
# 게이트: 강제 장치(난간)가 조용히 사라지지 않았는가 — 강제 장치 **자체**의 검사. 대상은 이 플러그인 트리다.
#
# 막는 것: **게이트가 없어진 상태와 게이트가 통과한 상태는 둘 다 "아무 일 없음"으로
# 보인다.** 규칙 하나가 등재에서 빠지고, deny 한 줄이 지워지고, 검사 스크립트의 실행
# 비트가 사라지고, hooks.json 의 배선이 훅 파일과 갈라져도 — 전부 rc=0 에 무출력이다.
#
# **표면 5개**를 본다. 각 표면은 **집합을 파생**하고, 항목별로 검사하며, 검사할 수 없는
# 항목만 사유와 함께 면제 목록에 등재한다 (harness:develop 운영 규율 "극성 반전").
# **이 수는 검사가 스스로 대조한다** — 아래 "머리주석 ↔ 실제 표면" 절이 이 파일이 적는
# 표면 수 전부를 본문의 section 라벨에서 파생한 실제 표면 수와 맞춘다.
#
#   S1 훅 규칙   hooks/guard.sh 의 규칙 함수 전수 — 규칙마다 **실제로 막히는지**를
#                합성 stdin 으로 확인하고, 그 차단이 **그 규칙 때문임**을 A/B 대조로 귀속한다
#   S2 훅 배선   hooks/hooks.json ↔ hooks/*.sh (양방향). 배선된 명령이 실재하는 파일을
#                ${CLAUDE_PLUGIN_ROOT} 로 가리키는가 · 훅 파일 전부가 어느 이벤트에든 배선됐는가 ·
#                PreToolUse 가 S1 이 시험한 그 파일을 모든 도구에 대해(matcher 없음) 부르는가 ·
#                Stop 이 정지 가드와 루프 취소를 부르는가
#   S5 스크립트  scripts·checks·hooks·lib 의 *.sh 실물 전수(실행 비트·문법)
#   S6 원장 게이트 checks/ledger-check.sh 의 원장 탐색·자동 반영 — bd·dolt 를
#                스텁으로 갈아끼운 픽스처에서 실제로 돌린다
#   S7 정지 가드 hooks/stop-resume.sh (Stop) — **배선된 그 파일에 Stop 페이로드를
#                직접 먹여 발화를 본다.** 런타임을 기다리지 않는다: 경로 전원이 로그를
#                한 줄씩 남기는가(판정 도달) · 오라클만 흔들면 stdout 이 갈리는가(부정
#                대조군) · hooks.json 의 Stop 등재만 뺀 사본에서 대상 파생이 뒤집히는가
#                (A/B 귀속) · 먹인 파일이 그 등재가 가리키는 경로인가(대상 단언) · 상태
#                파일이 데이터 디렉토리(HARNESS_DATA_DIR)에만 떨어지는가
#
# 종전(하네스 루트의 같은 검사)에 있던 표면 S3(권한 deny)·S4(플러그인 등재)와 install.sh
# 미러링·pre-commit/pre-push/render 블록 대조·docs/guardrails.md 계수 대조·"못 막는 것" rc=0
# 실측은 뺐다 — 그 원본(settings.json·install.sh·.beads/hooks·docs/)이 플러그인에 없다. 문서
# 계수 대조는 하네스 루트 문서가 새 구조로 고쳐진 뒤(M4) 그 문서가 소유할 자리다.
#
# **존재 확인이 아니라 차단 동작을 본다.** S1 이 그 무게를 진다 — 규칙이 등재돼 있고
# 함수가 있어도 판정문에 오타가 나면 아무것도 막지 않는데, 존재 검사는 그것을 통과시킨다.
# S1 은 규칙마다 차단돼야 할 입력을 실제로 먹여 rc=2 를 요구하고, **같은 입력이 그 규칙의
# 등재만 뺀 사본에서는 rc=0** 임을 함께 요구한다. 뒤엣것이 없으면 다른 규칙이 우연히
# 막아 준 것을 "이 규칙이 산다"로 오독한다 — 규칙 7개가 겹치는 판정 지점을 공유하므로
# 실제로 일어나는 오독이다 (guard.sh 의 "등재 순서로 메시지를 고른다" 주석 참조).
#
# checks/guard-check.sh 와의 경계: 그쪽은 guard.sh **안**을 판다 (규칙별 오탐·미탐 경계,
# 면제 목록 전수, 한계의 박제). 이 게이트는 그 위에서 **표면이 사라졌는가**만 본다.
# 규칙 하나에 시험 1건씩이고, 대신 guard-check.sh 가 못 보는 것을 본다: hooks.json 배선·
# 검사 스크립트 실물·정지 가드의 발화.
#
# 한계:
#   - 표면이 **양쪽에서 함께** 지워지면(규칙 함수와 그 시험, hooks.json 과 훅 파일)
#     이 게이트는 잡지 못한다. 막는 것은 **조용한 드리프트**다 — 한쪽만 바뀌는 것.
#   - **jq 가 없으면 경고를 내고 통째로 통과한다(fail-open).** 훅(guard.sh)이 입력을 해석하는
#     데와 hooks.json 을 읽는 데 jq 가 쓰이므로 S5 만 통과시킬 수 있는데, 표면 5 중 1만 본
#     rc=0 은 통과로 오독되므로 함께 건너뛴다. 조용히 넘어가지 않는다 — stderr 에 남긴다.
#   - **파생 앵커가 행두 고정이라 복합문·어순 변형은 샌다.** S7 의 경로 집합은 앵커가 행두의
#     log 한 줄이라 훅이 **분기마다 행두 한 줄**이라는 현재 문체를 지키는 동안만 전수이고,
#     자기 단언의 선언 집합은 "표면" 이 수 앞에 오는 어순만 센다. 앵커를 풀지 않는 것이
#     선택이다 — 풀면 산문 주석에 나온 같은 낱말까지 잡는 오탐이 생긴다.
#
# 하네스 루트는 필요 없다 — 이 검사는 플러그인 트리와 합성 픽스처만 본다(정지 가드의 원장은
# 스텁 bd 이고 하네스 루트는 HARNESS_ROOT 로 물린 합성 루트다. lib/harness-root.sh 는 그 첫
# 출처를 그대로 받는다).
#
# set -e 를 쓰지 않는다 — 검사 스크립트는 첫 실패에서 죽으면 안 된다 (board-check.sh 관례).
# 종료 코드는 파이프 밖에서 채집한다.
set -uo pipefail

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# 자기 단언의 대상. 이름이 같은 파일이 여러 트리에 있고(설치본·워크트리), 그러면 **지금 도는
# 파일이 아닌 것**을 세도 rc 가 같아 아무것도 드러나지 않는다.
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
cd "$ROOT" || { echo "✗ 플러그인 루트로 이동하지 못했다: $ROOT" >&2; exit 1; }
# 훅 사본을 다른 앵커에 두고 돌리는 절이 있다 — 세션이 이 변수를 내보낸 채 돌리면 사본이 전부 그
# 값을 앵커로 읽는다. 아래에서는 명시적으로 넘길 때만 쓴다.
unset CLAUDE_PLUGIN_ROOT

HOOK="hooks/guard.sh"
HOOKSJSON="hooks/hooks.json"
STOPHOOK="hooks/stop-resume.sh"

# 환경 사유의 미가용은 **fail-open + 경고**다 — 코드와 무관한 사유로 게이트를 막지 않는다. 같은
# 판단의 선례: guard.sh 자신이 jq 없으면 통과+경고로 넘어간다. **대신 조용히 넘어가지 않는다.**
if ! command -v jq >/dev/null 2>&1; then
  echo "⚠ 강제 장치 검사: jq 없음 — 훅(guard.sh)이 입력을 해석하는 데와 hooks.json 을 읽는 데 jq 가 쓰이므로 검사를 통째로 건너뛴다 (통과). S5 만은 jq 없이도 판정할 수 있으나, 표면 5 중 1만 본 rc=0 은 통과로 오독되므로 함께 건너뛴다." >&2
  echo "  난간이 사라졌는지 **알 수 없는** 상태다. jq 를 설치하고 checks/guardrail-check.sh 를 다시 돌려라." >&2
  exit 0
fi

for f in "$HOOK" "$HOOKSJSON" "$STOPHOOK"; do
  # 플러그인이 항상 싣는 파일이다 — 없으면 환경 사유가 아니라 강제 장치 자체의 소멸이므로 막는다.
  [[ -f "$f" ]] || { echo "✗ 강제 장치의 파일이 없다: $f" >&2; exit 1; }
done

TMP="$(cd "$(mktemp -d)" && pwd)"   # 심볼릭 링크를 미리 푼다 (macOS /var → /private/var)
trap 'rm -rf "$TMP"' EXIT

# 발화 로그를 임시 경로로 돌린다. S1 은 규칙마다 훅에 합성 stdin 을 먹이므로(규칙 7종 ×
# 프로브·A/B 사본) 기본 경로에 그대로 쓰면 실사용 계수가 합성 발화로 오염된다. "그 규칙이
# 발화한 적 있는가" 를 기계값으로 만드는 것이 그 로그의 존재 이유인데, 게이트 자신이 그 값을
# 위조한다. checks/guard-check.sh 가 같은 이유로 같은 형태를 쓴다.
export HARNESS_GUARD_LOG="$TMP/guard-log.tsv"
# 세션→actor 매핑도 같은 이유로 돌린다. 기본 경로가 `$HOME/.claude/harness-session-actor.tsv`
# 라 돌리지 않으면 이 게이트의 합성 claim 이 **실사용 매핑에 섞이고**, 정지 가드가 그것을
# 읽어 사거리를 정한다 — 게이트가 자기 판정 재료를 위조하는 바로 그 형태다.
export HARNESS_SESSION_ACTOR_LOG="$TMP/session-actor.tsv"

fail=0
pass_n=0

# 통과는 세기만 하고 실패만 낸다. GUARDRAIL_VERBOSE=1 이면 종전처럼 전문을 낸다.
# 통과했다는 사실만 필요한 자리(커밋 게이트)에서 단언 70여 줄이 매번 실렸다.
# **실패는 항상 전문이다** — `.claude/agents/implementer.md` 5("게이트 출력은 전문으로
# 판정한다")와 `reviewer.md` 7("잘라 읽지 않는다")이 지키는 자리이고, 여기서 요약하면
# 이 게이트가 진단 수단을 스스로 없앤다.
VERBOSE="${GUARDRAIL_VERBOSE:-0}"
CUR_SECTION=""      # 실패가 나올 때 그것이 어느 표면인지 함께 내기 위해 들고 있는다
SECTION_SHOWN=0

section() {  # section <제목> — 통과만 있는 실행에서는 제목도 소음이다
  CUR_SECTION="$1"; SECTION_SHOWN=0
  if [[ "$VERBOSE" == 1 ]]; then echo "$1"; SECTION_SHOWN=1; fi
}
# 눌린 제목을 실패 직전에 한 번만 되살린다. 없으면 ✗ 줄만 나와서 그것이 S1~S6 중
# 어디인지 안 보인다 — 요약이 진단 수단을 깎는 자리다.
show_section() {
  if [[ "$SECTION_SHOWN" == 0 && -n "$CUR_SECTION" ]]; then echo "$CUR_SECTION"; SECTION_SHOWN=1; fi
}
# step 을 거치지 않고 성공만 알리는 자리(분기 안에서 실패를 따로 처리하는 곳)가 있다.
# 그 자리도 여기로 모은다 — 아니면 통과 출력이 두 경로로 갈려 한쪽만 눌린다.
pass() {  # pass <라벨>
  pass_n=$((pass_n + 1))
  if [[ "$VERBOSE" == 1 ]]; then echo "  ✓ $1"; fi
}
step() {  # step <라벨> <명령...>
  local label="$1"; shift
  if "$@"; then
    pass_n=$((pass_n + 1))
    if [[ "$VERBOSE" == 1 ]]; then echo "  ✓ ${label}"; fi
  else
    show_section
    echo "  ✗ ${label}"; fail=1
  fi
}
say_fail() { show_section; echo "      $*"; }
# 사본이 원본과 **다르다**를 단언한다. `! cmp -s` 하나로는 안 된다 — 사본이 없거나 비면
# cmp 가 rc=2 로 죽고 그 비-0 이 "다르다"로 읽혀, 사본을 못 만든 A/B·부정 대조군이
# 조용히 통과한다 (harness-erf). 실재·비어있지 않음을 통과해야 내용 차이를 근거로 쓴다.
not_same() { [ -s "$1" ] && [ -s "$2" ] && ! cmp -s "$1" "$2"; }

# ── 면제 목록 ────────────────────────────────────────────────────────
# 극성 반전: 새 항목의 기본값은 "검사됨"이다. 검사할 수 없는 것만 여기 등재하고,
# 각 줄에 사유를 남긴다. 아래 assert_exempt_keys 가 **면제 키가 실제 집합에 있는지**를
# 역방향으로 단언한다 — 사라진 항목을 면제해 두면 그 면제가 곧 침묵이 된다.
#
# 등재 형식은 `<키>${SEP}<사유>` 다. 구분자는 US(0x1f) — **키에 나타날 수 없는 바이트**를
# 골랐다. 인쇄 가능한 구분자는 안전하지 않다: 훅 키는 필드 구분에 탭을 쓰고, 훅 명령에는
# `|` 가 들 수 있다(파이프라인).
SEP=$'\x1f'

# S1: 차단 동작을 시험할 수 없는 규칙 함수. 키는 guard.sh 의 규칙 함수 이름.
# 지금은 없다 — 남은 규칙 7종은 전부 합성 stdin 으로 차단·귀속을 잴 수 있다(트리 상태에
# 기대던 r_core_write·r_bead_leak 은 규칙과 함께 뺐다). 0건 면제표는 정상이다.
EXEMPT_RULE=()

# S2: 어느 이벤트에도 배선되지 않아도 되는 hooks/*.sh. 키는 "hooks/<파일명>".
# 지금은 없다 — hooks/ 의 셸은 전부 hooks.json 이 부른다. 헬퍼를 hooks/ 에 두게 되면 여기 사유와 함께 등재한다.
EXEMPT_HOOK=()

# 면제 키가 실제 집합에 존재하는가 (역방향 단언).
#   assert_exempt_keys <이름> <면제배열의 항목들...> -- <집합의 항목들...>
assert_exempt_keys() {
  local name="$1"; shift
  local -a ex=() set_=() ; local seen_sep=0 a
  for a in "$@"; do
    if [[ "$a" == "--" && "$seen_sep" -eq 0 ]]; then seen_sep=1; continue; fi
    if [[ "$seen_sep" -eq 0 ]]; then ex+=("$a"); else set_+=("$a"); fi
  done
  local key found bad=0 e s
  for e in ${ex[@]+"${ex[@]}"}; do
    key="${e%%"$SEP"*}"
    found=0
    for s in ${set_[@]+"${set_[@]}"}; do [[ "$s" == "$key" ]] && { found=1; break; }; done
    if [[ "$found" -eq 0 ]]; then
      say_fail "$name 의 면제 키가 실제 집합에 없다: '$key' — 항목이 사라졌는데 면제만 남았다면 그 면제가 곧 침묵이다. 면제를 지워라"
      bad=1
    fi
  done
  [[ "$bad" -eq 0 ]]
}

# 면제된 키인가.
is_exempt() {  # is_exempt <키> <면제배열 항목들...>
  local key="$1"; shift
  local e
  for e in "$@"; do [[ "${e%%"$SEP"*}" == "$key" ]] && return 0; done
  return 1
}

# ── 머리주석 ↔ 실제 표면 (자기 단언) ─────────────────────────────────
# 이 파일이 **자기 모집단**이다. 머리주석이 적는 표면 수와 본문의 실제 절 수가 갈리면
# 다음 사람이 머리주석을 지도로 쓰고 없는 표면을 있다고 읽는다 — 실제로 갈려 있었다
# (머리주석 "다섯"인 동안 본문에 S6 이 있었다). 수를 손으로 맞추는 대신 검사가 대조한다.
#
# 파생 형태:
#   실제  본문의 `section "S<번호>` 라벨에서 번호를 뽑아 중복을 없앤다. 머리주석의 S 목록은
#         `section "` 가 없어 섞이지 않고, **이 파생식 자신도 섞이지 않는다** — 패턴의 S
#         뒤에 오는 것은 숫자가 아니라 대괄호라 자기매칭이 없다.
#   선언  주석·메시지에 적힌 표면 수. 한 곳만 보면 나머지가 조용히 낡는다 (jq 한계 절의
#         분모가 그 자리였다). 새로 적는 수의 기본값을 "검사됨"으로 만들려는 자리이고,
#         **어순 한 가지만 센다** — 위 경로 집합과 같은 부류의 한계다(머리주석 한계 절).
section "머리주석 ↔ 실제 표면 수 (자기 단언)"

SURF_SET=()
while IFS= read -r s; do [[ -n "$s" ]] && SURF_SET+=("$s"); done < <(
  grep -oE 'section "S[0-9]+' "$SELF" | grep -oE 'S[0-9]+' | sort -u)
step "본문에서 표면 집합을 파생했다 (${#SURF_SET[@]}개: ${SURF_SET[*]:-없음})" \
  [ "${#SURF_SET[@]}" -gt 0 ]

DECLARED=()
while IFS= read -r d; do [[ -n "$d" ]] && DECLARED+=("$d"); done < <(
  grep -oE '표면 [0-9]+' "$SELF" | awk '{print $2}')
step "이 파일이 표면 수를 적는 자리가 있다 (0건이면 대조할 것이 없다)" \
  [ "${#DECLARED[@]}" -gt 0 ]

bad_decl=()
for d in ${DECLARED[@]+"${DECLARED[@]}"}; do
  [[ "$d" == "${#SURF_SET[@]}" ]] || bad_decl+=("$d")
done
[[ ${#bad_decl[@]} -gt 0 ]] && say_fail "이 파일이 적는 표면 수가 실제와 다르다: 적힌 값 ${bad_decl[*]} · 실제 ${#SURF_SET[@]}개(${SURF_SET[*]}) — 표면을 더하거나 지웠으면 머리주석과 jq 한계 절의 분모를 **함께** 고쳐라"
step "적힌 표면 수 ${#DECLARED[@]}곳이 전부 실제와 같다" [ "${#bad_decl[@]}" -eq 0 ]

# 수만 맞고 항목이 빠지면 지도는 여전히 틀린다 — 목록 줄도 함께 센다.
listed_n="$(grep -cE '^#   S[0-9]+ ' "$SELF" | tr -d ' ')"
[[ "$listed_n" -eq "${#SURF_SET[@]}" ]] || say_fail "머리주석의 S 목록이 ${listed_n}줄인데 실제 표면은 ${#SURF_SET[@]}개다 (${SURF_SET[*]}) — 목록에서 빠진 표면은 없는 것처럼 읽힌다"
step "머리주석의 S 목록 줄 수가 실제 표면 수와 같다 (${listed_n})" \
  [ "$listed_n" -eq "${#SURF_SET[@]}" ]

# ── S1: 훅 규칙 — 실제로 막히는가, 그리고 그 규칙 때문인가 ────────────
section "S1 훅 규칙 (${HOOK})"

# 집합 파생. guard.sh 가 "규칙 함수는 r_ 접두" 를 계약으로 선언하고
# checks/guard-check.sh ⑦ 이 그 계약(전원 등재·접두 준수)을 단언한다. 여기서는 그
# 집합을 그대로 받아 **차단 동작**을 본다.
RULE_SET=()
while IFS= read -r fn; do [[ -n "$fn" ]] && RULE_SET+=("$fn"); done < <(
  grep -Eo '^r_[A-Za-z0-9_]+\(\)' "$HOOK" | sed 's/()$//' | sort -u)
step "규칙 집합이 파생됐다 (${#RULE_SET[@]}개)" [ "${#RULE_SET[@]}" -gt 0 ]

CLONE_ROOT="${HARNESS_CLONE_ROOT:-$HOME/.harness-workspace}"   # guard.sh 와 같은 표현
IMPL_T="harness:implementer"; GR_R="harness:reviewer"                     # agent_type 의 실측 형식 (M0)
MAIN_PATH="$CLONE_ROOT/_probe-repo/README.md"                  # 어휘 판정이라 실재하지 않아도 된다

# 규칙마다 **차단돼야 하는** 입력 하나. 형식: "<규칙>|<PreToolUse 이벤트 JSON>".
# 이 표는 손으로 적지만 **집합이 아니라 시험 데이터**다 — 어느 규칙을 검사할지는
# 위 RULE_SET 이 정하고, 아래 두 단언이 이 표와 집합을 양방향으로 맞춘다.
PROBES=(
  "r_main_write|{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$MAIN_PATH\"}}"
  "r_main_shell|{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo x > $MAIN_PATH\"}}"
  "r_remote|{\"tool_name\":\"Bash\",\"agent_type\":\"$IMPL_T\",\"tool_input\":{\"command\":\"git push origin master\"}}"
  "r_grader_write|{\"tool_name\":\"Write\",\"agent_type\":\"$GR_R\",\"tool_input\":{\"file_path\":\"$TMP/probe.txt\"}}"
  "r_grader_shell|{\"tool_name\":\"Bash\",\"agent_type\":\"$GR_R\",\"tool_input\":{\"command\":\"git commit -m probe\"}}"
  "r_impl_bd|{\"tool_name\":\"Bash\",\"agent_type\":\"$IMPL_T\",\"tool_input\":{\"command\":\"bd -C $TMP close probe-1\"}}"
  "r_bd_root|{\"tool_name\":\"Bash\",\"agent_id\":\"sess-probe\",\"tool_input\":{\"command\":\"bd close probe-1\"}}"
)

probe_keys() { local p; for p in "${PROBES[@]}"; do echo "${p%%|*}"; done; }

# 정방향: 집합의 모든 규칙이 시험되거나 면제됐는가. 새 규칙의 기본값이 "검사됨"이 되는 자리.
uncovered=()
for fn in ${RULE_SET[@]+"${RULE_SET[@]}"}; do
  probe_keys | grep -qx -- "$fn" && continue
  is_exempt "$fn" ${EXEMPT_RULE[@]+"${EXEMPT_RULE[@]}"} && continue
  uncovered+=("$fn")
done
if [[ ${#uncovered[@]} -gt 0 ]]; then
  say_fail "차단 시험도 면제도 없는 규칙: ${uncovered[*]} — PROBES 에 차단돼야 할 입력을 더하거나, 시험할 수 없다면 EXEMPT_RULE 에 사유와 함께 등재하라"
fi
step "규칙 전원이 차단 시험 또는 면제로 덮인다" [ "${#uncovered[@]}" -eq 0 ]

# 역방향: 시험·면제의 키가 실제 규칙 집합에 있는가. 규칙이 사라졌는데 시험만 남으면
# 그 시험은 이후 절에서 "차단 안 됨"으로 시끄럽게 죽고, 면제만 남으면 조용하다.
stale=()
while IFS= read -r k; do
  printf '%s\n' ${RULE_SET[@]+"${RULE_SET[@]}"} | grep -qx -- "$k" || stale+=("$k")
done < <(probe_keys)
[[ ${#stale[@]} -gt 0 ]] && say_fail "PROBES 의 키가 실제 규칙 집합에 없다: ${stale[*]} — 규칙이 사라졌다면 시험도 지워라"
step "PROBES 의 키가 전부 실재하는 규칙이다" [ "${#stale[@]}" -eq 0 ]
step "EXEMPT_RULE 의 면제 키가 실재한다" \
  assert_exempt_keys EXEMPT_RULE ${EXEMPT_RULE[@]+"${EXEMPT_RULE[@]}"} -- ${RULE_SET[@]+"${RULE_SET[@]}"}

# 훅 실행 — rc 는 파이프 밖에서 채집한다.
# **`bash <경로>` 로 부른다.** hooks.json 이 배선한 명령도 `bash "${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh"`
# 이므로 실행 비트는 실제 발화 경로의 조건이 아니다. 직접 실행(`./guard.sh`)하면 이 절이
# 실행 비트를 요구하게 되어, 발화에는 아무 영향이 없는 변화에 "규칙이 안 막힌다"고 시끄러운
# 오탐을 낸다. 검사 스크립트의 실행 비트는 S5 가 따로 본다 (그쪽은 실제로 필요하다).
GUARD_RC=0; GUARD_OUT=""
runh() { GUARD_OUT="$(printf '%s' "$2" | bash "$1" 2>&1)"; GUARD_RC=$?; }

# 규칙 **등재만** 뺀 사본을 만든다. 함수 정의는 남기므로 등록부 무결성(guard-check ⑦)의
# 관심사와 섞이지 않고, 오직 "이 규칙이 디스패치되지 않는" 상태만 만든다.
mk_without() {  # mk_without <규칙> → 사본 경로를 stdout 으로
  local fn="$1"
  local dir="$TMP/wo-$fn" copy
  copy="$dir/hooks/guard.sh"   # GUARD_ROOT 파생이 플러그인 배치와 같은 형태가 되게
  mkdir -p "$dir/hooks"
  # 주소를 RULES+= 줄로 한정한다 — 파일 전체에 걸면 규칙 이름을 담은 주석·차단
  # 메시지까지 건드려 A/B 대조가 "등재를 뺐기 때문"이 아닌 이유로 갈릴 수 있다.
  sed -E "/^RULES\+=/ s/\"[^\"]*:${fn}\"//g" "$HOOK" > "$copy"
  printf '%s' "$copy"
}

for entry in "${PROBES[@]}"; do
  fn="${entry%%|*}"; json="${entry#*|}"
  printf '%s\n' ${RULE_SET[@]+"${RULE_SET[@]}"} | grep -qx -- "$fn" || continue

  runh "$HOOK" "$json"
  if [[ "$GUARD_RC" -ne 2 ]]; then
    say_fail "입력: $json"
    say_fail "출력(rc=$GUARD_RC): ${GUARD_OUT:-<없음>}"
  fi
  step "$fn — 차단돼야 할 입력이 실제로 막힌다 (rc=2)" [ "$GUARD_RC" -eq 2 ]
  # 차단 자체가 안 되면 귀속을 따질 것이 없다. 여기서 멈추지 않으면 "등재를 빼도
  # 결과가 같다"는 참인 관측이 "sed 가 고장 났다"는 틀린 진단으로 출력된다 [실측].
  [[ "$GUARD_RC" -eq 2 ]] || continue

  copy="$(mk_without "$fn")"
  if ! not_same "$HOOK" "$copy"; then
    say_fail "$fn 의 등재를 뺀 사본이 원본과 같거나 만들어지지 않았다 — 등재 형태가 바뀌어 sed 가 아무것도 못 지웠다. 이 절의 귀속 단언이 공허해진다"
    fail=1
  else
    runh "$copy" "$json"
    if [[ "$GUARD_RC" -ne 0 ]]; then
      say_fail "$fn 등재를 뺐는데도 rc=$GUARD_RC — 다른 규칙이 이 입력을 막고 있다. 위 rc=2 는 $fn 의 근거가 되지 못하므로 PROBES 의 입력을 그 규칙만 걸리도록 좁혀라"
      say_fail "출력: ${GUARD_OUT:-<없음>}"
    fi
    step "$fn — 그 차단이 이 규칙 때문이다 (등재를 빼면 rc=0)" [ "$GUARD_RC" -eq 0 ]
  fi
done

# 면제된 규칙도 **등재**는 있어야 한다. 면제가 면제하는 것은 *차단 동작*이지 *등재*가
# 아니다 — 규칙 집합을 함수 정의(`^r_…()`)에서 파므로, 등재 줄만 지운 사본에서도 그 규칙은
# 집합에 남고 면제로 통과한다. 시험이 있는 규칙은 그 상태가 위 A/B 에서 rc=0 으로 시끄럽게
# 죽는데, 면제된 규칙만 그 검출을 잃는다 [실측 2026-08-23: RULES+= 줄만 지운 사본이 이
# 게이트를 rc=0 으로 통과했다 — guard-check.sh 는 check-all 의 면제라 아무도 못 본다].
# 그래서 면제 키마다 등재의 실재를 **정적으로** 단언한다. 앞으로 생길 면제도 함께 덮는다.
registered_in() {  # registered_in <규칙함수> <훅파일>
  grep -E '^RULES\+=' "$2" | grep -q "\"[^\"]*:$1\""
}
unregistered=()
for e in ${EXEMPT_RULE[@]+"${EXEMPT_RULE[@]}"}; do
  key="${e%%"$SEP"*}"
  registered_in "$key" "$HOOK" || unregistered+=("$key")
done
[[ ${#unregistered[@]} -gt 0 ]] && say_fail "면제된 규칙이 RULES 등록부에 없다: ${unregistered[*]} — 면제는 차단 동작의 면제이지 등재의 면제가 아니다. 등재가 빠지면 그 규칙은 디스패치되지 않는데, 면제 때문에 위 차단 시험도 돌지 않아 조용히 꺼진 채 남는다"
step "EXEMPT_RULE 의 규칙이 RULES 등록부에 등재돼 있다" [ "${#unregistered[@]}" -eq 0 ]

# 그 단언이 죽으면 실패하는가 — 등재 줄만 뺀 사본에서 반드시 "미등재"로 읽혀야 한다.
# 이 대조가 없으면 위 단언은 grep 이 무엇을 찾든 참이 되는 형태로 조용히 망가질 수 있다.
_reg_probe="${RULE_SET[0]:-}"   # 집합이 비면 위 파생 단언이 이미 ✗ 다 — 여기서 set -u 로 죽지만 않게 한다
_reg_copy="$(mk_without "$_reg_probe")"
if cmp -s "$HOOK" "$_reg_copy"; then
  say_fail "등재 단언의 대조군 사본이 원본과 같다 — sed 가 아무것도 못 지웠고 아래 판정이 공허하다"; fail=1
elif registered_in "$_reg_probe" "$HOOK" && ! registered_in "$_reg_probe" "$_reg_copy"; then
  pass "등재 단언 자체가 작동한다 ($_reg_probe 의 등재를 뺀 사본에서 미등재로 읽힌다)"
else
  say_fail "등재 단언이 등재를 뺀 사본을 통과시켰다 — 등재 검출 기구가 고장 났다"; fail=1
fi

# 면제 역방향 단언이 실제로 작동하는지 — 있지도 않은 키를 면제해 보고 검출되는지 본다.
# 면제 목록이 비어 있으면 위 단언들은 공허하게 참이 된다. 이 자리가 그 공허를 메운다.
if assert_exempt_keys _selftest "r_없는규칙${SEP}사유" -- ${RULE_SET[@]+"${RULE_SET[@]}"} >/dev/null 2>&1; then
  say_fail "면제 역방향 단언이 없는 키를 통과시켰다 — 면제 기구가 고장 났다"
  fail=1
else
  pass "면제 역방향 단언 자체가 작동한다 (없는 키를 면제하면 검출)"
fi

# ── S2: 훅 배선 (hooks.json ↔ hooks/*.sh) ─────────────────────────────
# 플러그인의 훅은 hooks/hooks.json 이 배선한다 — 이벤트마다 `bash "${CLAUDE_PLUGIN_ROOT}/hooks/<파일>"`.
# 파일이 있는데 배선이 없으면 훅은 한 번도 돌지 않고, 배선이 있는데 파일이 없으면 이벤트마다
# 조용히 실패한다 — 둘 다 rc=0 에 무출력이라 여기서 양방향으로 맞춘다.
#
# **matcher 를 본다.** PreToolUse 배선의 matcher 가 "" 이 아니면(예: "WebFetch") guard.sh 는 그
# 도구에만 발화하고 Bash·Write·Edit 에는 한 번도 발화하지 않는데, S1 은 훅을 직접 불러 rc=2 를
# 보므로 규칙 7개가 전부 무력인 채로 이 게이트가 통과한다 [실측 2026-08-22, 종전 settings.json 배선에서].
# 플러그인 hooks.json 은 matcher 를 생략하면 전 도구다 — 생략 또는 "" 만 정답으로 읽는다.
section "S2 훅 배선 (${HOOKSJSON} ↔ hooks/*.sh)"

jq -e '.hooks | type == "object"' "$HOOKSJSON" >/dev/null 2>&1 || { say_fail "$HOOKSJSON 의 .hooks 가 객체가 아니다 — 배선 파생이 공허해진다"; fail=1; }
# 파생: "<이벤트>\t<matcher>\t<명령>". matcher 가 없으면 빈 문자열이다.
wired="$(jq -r '(.hooks // {}) | to_entries[] | .key as $e | .value[]? | (.matcher // "") as $m | (.hooks // [])[] | select(.type == "command") | "\($e)\t\($m)\t\(.command)"' "$HOOKSJSON" 2>/dev/null)"
wired_arr=()
while IFS= read -r _l; do [[ -n "$_l" ]] && wired_arr+=("$_l"); done < <(printf '%s\n' "$wired")
step "hooks.json 에서 배선 집합을 파생했다 (${#wired_arr[@]}개)" [ "${#wired_arr[@]}" -gt 0 ]

# 정방향: 배선된 명령이 전부 ${CLAUDE_PLUGIN_ROOT} 로 실재하는 hooks/*.sh 를 부른다.
HOOK_FILES=()
while IFS= read -r f; do [[ -n "$f" ]] && HOOK_FILES+=("$f"); done < <(find hooks -maxdepth 1 -type f -name '*.sh' | sort)
step "hooks/*.sh 실물 집합을 파생했다 (${#HOOK_FILES[@]}개)" [ "${#HOOK_FILES[@]}" -gt 0 ]
bad_cmd=(); wired_files=()
for line in ${wired_arr[@]+"${wired_arr[@]}"}; do
  ev="${line%%$'\t'*}"; rest="${line#*$'\t'}"; matcher="${rest%%$'\t'*}"; cmd="${rest#*$'\t'}"
  target="$(printf '%s' "$cmd" | grep -oE 'hooks/[A-Za-z0-9_.-]+\.sh' | head -1)"
  if [[ -z "$target" ]]; then bad_cmd+=("$ev :: $cmd (hooks/*.sh 를 부르지 않는다)"); continue; fi
  case "$cmd" in *'${CLAUDE_PLUGIN_ROOT}'*) ;; *) bad_cmd+=("$ev :: $cmd (\${CLAUDE_PLUGIN_ROOT} 로 앵커되지 않았다 — 훅의 CWD 는 신뢰할 수 없다)") ;; esac
  [[ -f "$target" ]] || bad_cmd+=("$ev :: $cmd (파일이 없다: $target)")
  wired_files+=("$target")
done
[[ ${#bad_cmd[@]} -gt 0 ]] && { say_fail "배선이 가리키는 명령이 온전하지 않다:"; for m in "${bad_cmd[@]}"; do say_fail "  - $m"; done; }
step "정방향: 배선된 명령이 전부 \${CLAUDE_PLUGIN_ROOT}/hooks/<실재 파일>.sh 를 부른다" [ "${#bad_cmd[@]}" -eq 0 ]

# 역방향: hooks/*.sh 전부가 어느 이벤트에든 배선됐다 (면제는 EXEMPT_HOOK).
unwired=()
for f in ${HOOK_FILES[@]+"${HOOK_FILES[@]}"}; do
  printf '%s\n' ${wired_files[@]+"${wired_files[@]}"} | grep -qx -- "$f" && continue
  is_exempt "$f" ${EXEMPT_HOOK[@]+"${EXEMPT_HOOK[@]}"} && continue
  unwired+=("$f")
done
[[ ${#unwired[@]} -gt 0 ]] && say_fail "hooks/ 에 있는데 hooks.json 이 부르지 않는 훅 — 한 번도 돌지 않는 난간이다: ${unwired[*]}. 배선하거나, 훅이 아니면 EXEMPT_HOOK 에 사유와 함께 등재하라"
step "역방향: hooks/*.sh 전부가 hooks.json 에 배선됐다" [ "${#unwired[@]}" -eq 0 ]
step "EXEMPT_HOOK 의 면제 키가 실재한다" \
  assert_exempt_keys EXEMPT_HOOK ${EXEMPT_HOOK[@]+"${EXEMPT_HOOK[@]}"} -- ${HOOK_FILES[@]+"${HOOK_FILES[@]}"}

# PreToolUse: S1 이 시험한 그 파일을 모든 도구에 대해 부른다.
pre_n=0; pre_matcher_bad=()
for line in ${wired_arr[@]+"${wired_arr[@]}"}; do
  ev="${line%%$'\t'*}"; rest="${line#*$'\t'}"; matcher="${rest%%$'\t'*}"; cmd="${rest#*$'\t'}"
  [[ "$ev" == "PreToolUse" ]] || continue
  case "$cmd" in *"$HOOK"*) pre_n=$((pre_n + 1)); [[ -z "$matcher" ]] || pre_matcher_bad+=("$matcher") ;; esac
done
[[ "$pre_n" -eq 0 ]] && say_fail "hooks.json 의 PreToolUse 가 $HOOK 를 부르지 않는다 — S1 이 시험한 규칙 ${#RULE_SET[@]}개가 세션에서는 한 번도 안 돈다"
step "PreToolUse 배선이 S1 이 시험한 파일($HOOK)을 가리킨다 (${pre_n}건)" [ "$pre_n" -ge 1 ]
[[ ${#pre_matcher_bad[@]} -gt 0 ]] && say_fail "PreToolUse 훅의 matcher 가 비어 있지 않다: '${pre_matcher_bad[*]}' — 그 도구에만 발화하므로 나머지 도구에서는 규칙 ${#RULE_SET[@]}개가 전부 무력이다. matcher 를 지우거나 \"\" 로 두라"
step "PreToolUse 배선의 matcher 가 없거나 \"\" 다 (모든 도구에 발화)" [ "${#pre_matcher_bad[@]}" -eq 0 ]

# Stop: 정지 가드와 루프 취소가 둘 다 배선됐다. 정지 가드의 발화 자체는 S7 이 본다.
stop_files="$(printf '%s\n' ${wired_arr[@]+"${wired_arr[@]}"} | awk -F'\t' '$1 == "Stop" { print $3 }' | grep -oE 'hooks/[A-Za-z0-9_.-]+\.sh' | sort -u)"
step "Stop 이 정지 가드($STOPHOOK)를 부른다" bash -c 'printf "%s\n" "$1" | grep -qx -- "$2"' _ "$stop_files" "$STOPHOOK"
step "Stop 이 루프 취소(hooks/ralph-cancel.sh)를 부른다" bash -c 'printf "%s\n" "$1" | grep -qx -- "$2"' _ "$stop_files" "hooks/ralph-cancel.sh"
step "SessionStart 가 주입 블록 훅(hooks/session-context.sh)을 부른다" \
  bash -c 'printf "%s\n" "$1" | awk -F"\t" "\$1 == \"SessionStart\" { print \$3 }" | grep -q "hooks/session-context.sh"' _ "$wired"

# 부정 대조군 — 배선 파생이 죽으면 위 단언이 공허해진다. PreToolUse 항목을 뺀 사본에서 pre_n 이 0 이 되는가.
jq -S 'del(.hooks.PreToolUse)' "$HOOKSJSON" > "$TMP/hooks-wo-pre.json" 2>/dev/null
jq -S . "$HOOKSJSON" > "$TMP/hooks-base.json" 2>/dev/null
if ! not_same "$TMP/hooks-base.json" "$TMP/hooks-wo-pre.json"; then
  say_fail "PreToolUse 를 뺀 사본이 원본과 같거나 만들어지지 않았다 — 배선 형태가 바뀌어 jq 가 아무것도 못 지웠다. 이 절의 A/B 가 공허해진다"; fail=1
else
  wo_pre="$(jq -r '(.hooks // {}) | to_entries[] | select(.key == "PreToolUse") | .value[]? | (.hooks // [])[] | .command' "$TMP/hooks-wo-pre.json" | grep -c "$HOOK" || true)"
  step "A/B 귀속: PreToolUse 등재를 빼면 파생이 그 파일을 더는 찾지 못한다 (${wo_pre}건)" [ "${wo_pre:-1}" -eq 0 ]
fi

# ── S5: 스크립트 실물 (scripts·checks·hooks·lib) ─────────────────────
section "S5 스크립트 실물 — 실행 비트 · 문법"

# 집합은 실물에서 파생한다 — 목록을 스크립트에 적으면 파일이 지워질 때 조용해진다.
CHECK_SET=()
while IFS= read -r f; do [[ -n "$f" ]] && CHECK_SET+=("$f"); done < <(find checks -maxdepth 1 -type f -name '*.sh' | sort)
step "검사 스크립트 집합이 파생됐다 (${#CHECK_SET[@]}개)" [ "${#CHECK_SET[@]}" -gt 0 ]
SH_SET=()
while IFS= read -r f; do [[ -n "$f" ]] && SH_SET+=("$f"); done < <(find scripts checks hooks lib -maxdepth 1 -type f -name '*.sh' | sort)
step "플러그인 셸 집합이 파생됐다 (${#SH_SET[@]}개)" [ "${#SH_SET[@]}" -gt "${#CHECK_SET[@]}" ]

bad_x=(); bad_n=()
for f in ${SH_SET[@]+"${SH_SET[@]}"}; do
  # 실행 비트 — 실제로 사라진 적이 있다. 게이트가 있어도 못 부르면 없는 것과 같다.
  [[ -x "$f" ]] || bad_x+=("$f")
  bash -n "$f" 2>/dev/null || bad_n+=("$f")
done
[[ ${#bad_x[@]} -gt 0 ]] && say_fail "실행 비트가 없다: ${bad_x[*]} — chmod +x 하라"
[[ ${#bad_n[@]} -gt 0 ]] && say_fail "문법 오류: ${bad_n[*]}"
step "플러그인 셸 전원이 실행 가능하다" [ "${#bad_x[@]}" -eq 0 ]
step "플러그인 셸 전원이 문법상 온전하다" [ "${#bad_n[@]}" -eq 0 ]

section "S6 원장 게이트 (checks/ledger-check.sh) — 탐색 · 자동 반영"
# 이 게이트가 **어느 원장을 보는지**와 **앞선 원장을 어떻게 다루는지**를 본다.
#   탐색  — 원장이 상위 체크아웃에 있는 격리 작업 공간에서 원장을 놓치고 **건너뜀으로
#           통과**하면, 자동 반영이 실행되지 않아 문서만 원격에 올라간다 (harness-js9)
#   반영  — 앞서 있으면 막지 않고 반영하되, **반영됐음을 상태로 재판정**한다. push 의
#           종료 코드로 통과시키면 자동화가 새로운 조용한 누락을 만든다 (harness-2f1)
# 감사 로그 사이드카 검사는 2026-08-29 에 그 게이트에서 사라졌다(harness-x0i) — 여기 있던
# 픽스처 ⑤·⑤-B·⑤-B2·⑤-C 도 함께 걷어냈다. 근거는 그 스크립트 앞머리 주석과 스토리 본문이다.
# ahead 상태는 $LTMP/ahead 파일이 들고, `bd dolt push` 스텁이 그 파일을 0 으로 만든다 —
# 그래야 "반영이 상태를 실제로 바꿨는가"를 종료 코드가 아닌 것으로 볼 수 있다.
#
# bd·dolt 를 스텁으로 갈아끼운다. 이 절이 주장하는 것은 "원장 위치를 어디서 파생하는가"
# 하나이지 dolt 판정 로직이 아니다. 진짜 원장을 물리면 검사가 실제 `bd dolt push` 를
# 일으켜 **게이트가 원격에 부작용을 낸다.**
LEDGER="checks/ledger-check.sh"
if [[ ! -f "$LEDGER" ]]; then
  say_fail "$LEDGER 이 없다 — push 게이트가 부르는 검사인데 실재하지 않는다"
  fail=1
else
  LTMP="$TMP/ledger"
  # 픽스처 루트 둘 — 판별자 ledger.json(backend beads)을 갖춘다. `root` 는 .beads/redirect 로 `up` 의 원장을
  # 가리키는 사본 루트(워크트리·검사 사본과 같은 배선)라 자기 아래에는 embeddeddolt 가 없다 — 원장 위치를
  # bd 에게 묻지 않고 루트 아래 경로를 조립하면 여기서 원장을 놓친다(harness-js9 의 형태). `norepo` 는
  # 원장이 정말 없는 트리다. ledger-check.sh 는 인자 루트를 HARNESS_ROOT 로 어댑터에 넘긴다.
  mkdir -p "$LTMP/bin" "$LTMP/up/.beads/embeddeddolt/db" "$LTMP/root/.beads" "$LTMP/norepo"
  printf '{"backend":"beads"}\n' > "$LTMP/root/ledger.json"
  printf '{"backend":"beads"}\n' > "$LTMP/norepo/ledger.json"
  printf '%s\n' "$LTMP/up/.beads" > "$LTMP/root/.beads/redirect"

  # dolt 스텁 — 원격 있음 · 계보 공유 · ahead 는 $LTMP/ahead 파일이 정한다.
  # ahead 를 파일로 두는 이유: 자동 반영이 **실제로 상태를 바꿨는지**를 봐야 하기 때문이다.
  # push 의 종료 코드로 통과시키면 ledger-check 이 재판정하는 그 지점을 시험하지 못한다.
  cat > "$LTMP/bin/dolt" <<'STUB'
#!/bin/sh
case "$1" in
  remote) echo "origin https://example.invalid/db" ;;
  branch) echo "  remotes/origin/main" ;;
  merge-base) echo "0000000000000000" ;;
  log) n=$(cat "$AHEAD_FILE" 2>/dev/null || echo 0); i=0
       while [ "$i" -lt "$n" ]; do echo "abc$i 커밋 $i"; i=$((i+1)); done ;;
  *) : ;;
esac
STUB
  # bd 스텁 — where 가 redirect 너머(up)의 원장을 낸다. BD_STUB_MISS=1 이면 원장 없음(rc=1).
  # `bd dolt push` 는 ahead 를 0 으로 만든다(반영 성공). BD_PUSH_FAIL=1 이면 상태를 그대로
  # 두고 rc=1 — 자동 반영이 **해소하지 못한** 경우이며 그때는 막아야 한다.
  # 어댑터는 `bd -C <루트> …` 로 부른다 — 원장 지정을 건너뛰고 하위 명령을 본다.
  cat > "$LTMP/bin/bd" <<STUB
#!/bin/sh
if [ "\$1" = "-C" ]; then shift 2; fi
if [ "\$1" = "where" ]; then
  [ -n "\${BD_STUB_MISS:-}" ] && { echo "Error: No active beads workspace found." >&2; exit 1; }
  b="$LTMP/up/.beads"
  echo "\$b"
  echo "  prefix: fx"
  echo "  database: \$b/embeddeddolt"
  exit 0
fi
if [ "\$1" = "dolt" ] && [ "\$2" = "push" ]; then
  [ -n "\${BD_PUSH_FAIL:-}" ] && { echo "push failed (stub)" >&2; exit 1; }
  echo 0 > "\$AHEAD_FILE"
  echo "Push complete. (stub)"
  exit 0
fi
exit 0
STUB
  chmod +x "$LTMP/bin/dolt" "$LTMP/bin/bd"

  # **상속된 git 환경을 끊고 부른다.** 이 게이트는 pre-commit 안에서도 도는데, 그때
  # GIT_DIR·GIT_INDEX_FILE 등이 환경에 실려 있어 픽스처 레포를 겨냥한 호출이 하네스
  # 레포로 돌아간다 — "이 작업은 작업 폴더에서 실행해야 합니다"로 죽고 이 절만 ✗ 가 된다.
  # 손으로 돌릴 때는 그 변수가 없어 통과하므로, **커밋 시점에만 깨지는** 형태였다
  # [실측 2026-08-22: 직접 실행 rc=0, pre-commit rc=1].
  fxgit() { env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_PREFIX \
                -u GIT_OBJECT_DIRECTORY -u GIT_COMMON_DIR git "$@"; }

  has_text()   { case "$2" in *"$1"*) return 0;; *) return 1;; esac; }
  lacks_text() { ! has_text "$1" "$2"; }
  AHEAD_FILE="$LTMP/ahead"
  set_ahead() { echo "$1" > "$AHEAD_FILE"; }
  get_ahead() { cat "$AHEAD_FILE" 2>/dev/null || echo "?"; }
  run_ledger() {  # run_ledger <스크립트> <ROOT> → LOUT/LRC
    LOUT=$(env PATH="$LTMP/bin:/usr/bin:/bin" AHEAD_FILE="$AHEAD_FILE" "$@" 2>&1); LRC=$?
  }
  # 추가 env 는 개수를 세지 않는다 — env 가 앞의 VAR=VAL 들을 소비하고 나머지를 명령으로
  # 실행하므로, 하나든 둘이든 같은 함수로 간다.
  run_ledger_env() {  # run_ledger_env <VAR=VAL…> <스크립트> <ROOT> → LOUT/LRC
    LOUT=$(env PATH="$LTMP/bin:/usr/bin:/bin" AHEAD_FILE="$AHEAD_FILE" "$@" 2>&1); LRC=$?
  }
  set_ahead 0

  # ① 배선된 사본 루트 — ROOT 아래에 embeddeddolt 가 없고 원장은 redirect 너머에 있다.
  run_ledger bash "$LEDGER" "$LTMP/root"
  step "배선 루트: 원장을 놓치지 않는다 (건너뜀으로 통과하지 않는다)" lacks_text "임베디드 원장 없음" "$LOUT"
  step "배선 루트: redirect 너머의 원장을 대상으로 판정에 도달한다 (rc=0)" [ "$LRC" -eq 0 ]
  step "배선 루트: 반영 여부를 실제로 판정했다고 말한다" has_text "원격 반영 확인됨" "$LOUT"

  # ② 원장이 정말 없는 **클론**(ledger.json 은 있으나 bd 가 원장을 못 낸다) — 건너뛰고 rc=0.
  #    ①의 수정이 이것을 깨지 않는다. 진짜 git 저장소로 만든다 — "저장소이긴 한데 원장이 없다"를 밟는다.
  fxgit init -q "$LTMP/norepo" 2>/dev/null
  LOUT=$(env PATH="$LTMP/bin:/usr/bin:/bin" BD_STUB_MISS=1 bash "$LEDGER" "$LTMP/norepo" 2>&1); LRC=$?
  step "원장 없는 클론: 건너뛴다"        has_text "임베디드 원장 없음" "$LOUT"
  step "원장 없는 클론: rc=0 (fail-open)" [ "$LRC" -eq 0 ]
  # fail-open 이되 **판정했다고 말하지 않는다.** 건너뛴 검사를 "확인됨"으로 적으면
  # 게이트가 꺼진 상태와 통과한 상태가 같은 문장으로 보인다.
  step "원장 없는 클론: '확인됨' 이라고 말하지 않는다" lacks_text "확인됨" "$LOUT"
  # 종전에는 감사 로그 검사의 '대상 미확정' 을 여기서 봤다. 그 검사가 사라져(harness-x0i)
  # 같은 성질 — **건너뛴 것을 건너뛰었다고 말한다** — 을 남은 판정에서 본다.
  step "원장 없는 클론: 건너뛰었다고 말한다"           has_text "원격 반영 건너뜀" "$LOUT"

  # ③ 쓰기 모드에서 원장이 앞서 있으면 **막지 않고 반영한다** — 그리고 반영됐음을 상태로
  #    확인한다. push 의 종료 코드가 아니라 재판정 결과가 근거다 (harness-2f1 acceptance ①).
  #    스위치를 여기서 켜는 것은 **pre-push 훅 블록이 켜는 그 자리를 재현**하는 것이다 —
  #    S5-push 가 그 블록에 이 변수가 실제로 있는지를 따로 단언한다.
  set_ahead 3
  run_ledger_env LEDGER_CHECK_PUSH=1 bash "$LEDGER" "$LTMP/root"
  step "ahead(쓰기 모드): 막지 않고 자동 반영한다 (rc=0)" [ "$LRC" -eq 0 ]
  step "ahead(쓰기 모드): 반영을 예고한다"                has_text "bd dolt push 로 함께 반영한다" "$LOUT"
  step "ahead(쓰기 모드): 통과 문구가 '이번에 수행함' 이다" has_text "원격 반영 이번에 수행함" "$LOUT"
  step "ahead(쓰기 모드): 상태가 실제로 해소됐다 (ahead=0)" [ "$(get_ahead)" = "0" ]

  # ④ 자동 반영이 **실패하면** 막는다 (acceptance ②). 자동화가 새로운 조용한 누락을
  #    만들면 안 된다 — push 가 실패했는데 통과시키면 종전보다 나빠진다.
  set_ahead 3
  run_ledger_env LEDGER_CHECK_PUSH=1 BD_PUSH_FAIL=1 bash "$LEDGER" "$LTMP/root"
  step "push 실패: 막는다 (rc=1)"                      [ "$LRC" -eq 1 ]
  step "push 실패: 해소하지 못했음을 말한다"            has_text "자동 반영이 해소하지 못했다" "$LOUT"
  step "push 실패: 상태를 꾸며내지 않는다 (ahead 유지)" [ "$(get_ahead)" = "3" ]

  # ⑤ **기본값** — 스위치 없이 부르면 앞서 있어도 원격에 쓰지 않는다. 빠뜨림의 기본값이
  #    안전 쪽이라는 것이 이 검사가 지키는 것이고, 근거는 harness-x0i.2.1 이다.
  #    **③ 이 이 절의 대조군이다** — 입력(ahead=3)과 스텁이 같고 다른 것은 환경 변수 하나뿐인데,
  #    ③ 은 ahead 를 0 으로 만들고 여기는 3 으로 남긴다. `bd dolt push` 스텁이 ahead 파일을
  #    0 으로 쓰므로 그 값이 곧 "원격 쓰기가 일어났는가"이고, 종료 코드가 아닌 것으로 본다.
  set_ahead 3
  run_ledger bash "$LEDGER" "$LTMP/root"
  step "기본값(스위치 없음): 막지 않는다 (rc=0)"        [ "$LRC" -eq 0 ]
  step "기본값: 원격에 쓰지 않는다 (ahead 유지)"        [ "$(get_ahead)" = "3" ]
  step "기본값: 반영했다고 말하지 않는다"               lacks_text "원격 반영 이번에 수행함" "$LOUT"
  step "기본값: 앞섬을 침묵시키지 않는다"               has_text "앞서 있음(반영하지 않음" "$LOUT"
  step "기본값: '확인됨' 과 갈린다"                     lacks_text "원격 반영 확인됨" "$LOUT"

  # ⑥ A/B 귀속 둘. 각 수정만 뺀 사본에서 그 단언이 실제로 뒤집히는가.
  #    안 뒤집히면 위 단언들은 "다른 이유로 통과한 것"과 구분되지 않는다.
  #    판정은 ledger-check.sh 가 아니라 어댑터의 beads 백엔드(scripts/ledger-beads.sh sync-check)에 있으므로
  #    사본도 그 파일에서 뜨고, LEDGER_ROOT 를 직접 물려 돌린다(ledger.sh 가 그 백엔드를 부를 때와 같은 계약).
  BEADS_BE="scripts/ledger-beads.sh"
  run_be() {  # run_be <사본> <루트> <인자…> → LOUT/LRC
    local be="$1" root="$2"; shift 2
    LOUT=$(env PATH="$LTMP/bin:/usr/bin:/bin" AHEAD_FILE="$AHEAD_FILE" LEDGER_ROOT="$root" bash "$be" sync-check "$@" 2>&1); LRC=$?
  }
  sed 's#^  elif dolt_root="\$db"; #  elif dolt_root="$LEDGER_ROOT/.beads/embeddeddolt"; #' \
    "$BEADS_BE" > "$LTMP/ledger-old.sh"
  if ! not_same "$BEADS_BE" "$LTMP/ledger-old.sh"; then
    say_fail "원장 탐색 줄을 옛 형태로 되돌린 사본이 원본과 같거나 만들어지지 않았다 — 파생 형태가 바뀌어 sed 가 아무것도 못 지웠다. 이 절의 귀속 단언이 공허해진다"
    fail=1
  else
    set_ahead 0
    run_be "$BEADS_BE" "$LTMP/root"
    step "A/B 대조군: 원본 백엔드를 직접 돌려도 배선 루트에서 판정에 도달한다" has_text "원격 반영 확인됨" "$LOUT"
    run_be "$LTMP/ledger-old.sh" "$LTMP/root"
    step "A/B 귀속: 탐색 한 줄을 되돌리면 배선 루트에서 다시 원장을 놓친다" has_text "임베디드 원장 없음" "$LOUT"
  fi

  # 자동 반영 호출만 뺀 사본 (acceptance ④). ahead 가 그대로 남으므로 재판정이 막아야 한다 —
  # 즉 이 사본에서는 ③ 의 입력이 rc=1 이 된다. 같으면 ③ 은 자동 반영과 무관하게 통과한 것이다.
  sed 's#^            (cd "\$LEDGER_ROOT" && bd dolt push).*#            :#' "$BEADS_BE" > "$LTMP/ledger-nopush.sh"
  if ! not_same "$BEADS_BE" "$LTMP/ledger-nopush.sh"; then
    say_fail "자동 반영 호출을 뺀 사본이 원본과 같거나 만들어지지 않았다 — 호출 형태가 바뀌어 sed 가 아무것도 못 지웠다. acceptance ④ 의 귀속이 공허해진다"
    fail=1
  else
    set_ahead 3
    run_be "$LTMP/ledger-nopush.sh" "$LTMP/root" --push
    step "A/B 귀속: 자동 반영 호출을 빼면 같은 입력이 막힌다 (rc=1)" [ "$LRC" -eq 1 ]
    step "A/B 귀속: 그때 상태는 해소되지 않는다 (ahead 유지)"        [ "$(get_ahead)" = "3" ]
  fi
fi

# ── S7: 정지 가드 — 등재가 아니라 발화를 본다 ──────────────────────────
# Stop 훅은 런타임이 부르는 것이라 세션 없이는 재현할 수 없다. 그래서 이 게이트가 가진
# 유일한 커버가 S2 의 문자열 배선 대조였고, docs/guardrail-verification.md 8절 천장 2 가 "발화는
# 아무도 검사하지 않는다"로 그 상태를 못박았다. 여기서는 런타임을 기다리지 않고 **훅을
# 직접 실행**한다 — Stop 페이로드를 stdin 으로 먹이고, 가짜 오라클을 PATH 앞에 두고,
# 로그와 stdout 을 본다. 등재 통과를 동작 보증으로 읽는 자리를 하나 지운다.
#
# **격리 — 실사용 로그·원장·살아 있는 세션에 붙지 않는다.** 훅의 상태 파일은 데이터 디렉토리
# (HARNESS_DATA_DIR) 아래라 그 변수를 샌드박스로 돌리지 않으면 **실사용 로그에 위조 발화가
# 쌓인다.** "그 경로가 발화한 적 있는가"를 기계값으로 만드는 것이 그 로그의 존재 이유인데
# 게이트가 그 값을 스스로 망친다 (S1·S6 이 같은 이유로 같은 형태를 쓴다). 원장 조회는 PATH
# 앞의 스텁이 받고, 하네스 루트는 HARNESS_ROOT 로 물린 합성 루트다(lib/harness-root.sh 의 첫
# 출처 — 판별자 ledger.json 만 갖춘다) — 진짜 bd·원장을 물리면 판정이 그 머신의 원장
# 상태에 흔들려 재현되지 않는다.
section "S7 정지 가드 (${STOPHOOK}) — 배선된 그 파일이 실제로 발화하는가"
if [[ ! -f "$STOPHOOK" ]]; then
  say_fail "$STOPHOOK 이 없다 — hooks.json 의 Stop 이 부르는 훅인데 실재하지 않는다"
  fail=1
else
  PTMP="$TMP/stopguard"
  mkdir -p "$PTMP/bin" "$PTMP/proj" "$PTMP/data" "$PTMP/hroot"
  printf '{"backend":"beads"}\n' > "$PTMP/hroot/ledger.json"   # 판별자 — 훅의 오라클은 어댑터(ledger.sh)를 거쳐 PATH 앞의 스텁 bd 에 닿는다
  SDATA="$PTMP/data"
  SLOG="$SDATA/stop-resume.log"
  SORACLE="$PTMP/oracle"
  STOPABS="$ROOT/$STOPHOOK"
  SHROOT="$PTMP/hroot"     # HARNESS_ROOT 로 물리는 합성 하네스 루트. 한 시험만 없는 경로로 바꾼다

  # 오라클 스텁. 값은 $ORACLE_FILE 이 정한다 — 숫자면 그 길이의 JSON 배열, FAIL 이면
  # 조회 자체가 실패(rc=1), GARBAGE 면 배열이 아닌 JSON, `[` 로 시작하면 그 JSON 을 그대로
  # (notes·assignee 를 실은 합성 픽스처 — VERIFY_PENDING·사거리 시험). 가운데 둘은
  # ORACLE_FAIL 의 두 갈래(조회 실패 · 형태 불량)를 각각 밟는다.
  # **숫자 모드의 assignee 는 $SCOPE_ACTOR 다** — 훅이 사거리를 이 세션의 actor 로 좁히므로,
  # assignee 를 비우면 숫자 모드 픽스처가 전부 좁히기에 걸러져 IDLE 로 무너진다.
  cat > "$PTMP/bin/bd" <<'STUB'
#!/bin/sh
# 훅은 어댑터를 거쳐 `bd -C <하네스루트> list …` 로 부른다 — 원장 지정을 건너뛰고 하위 명령을 본다.
if [ "$1" = "-C" ]; then shift 2; fi
if [ "$1" = "list" ]; then
  v=$(cat "$ORACLE_FILE" 2>/dev/null || echo 0)
  if [ "$v" = "FAIL" ]; then echo "Error: no beads database found" >&2; exit 1; fi
  if [ "$v" = "GARBAGE" ]; then echo '{"not":"an array"}'; exit 0; fi
  case "$v" in \[*) printf '%s\n' "$v"; exit 0;; esac
  i=0; out=""
  while [ "$i" -lt "$v" ]; do
    out="$out{\"id\":\"probe-$i\",\"assignee\":\"${SCOPE_ACTOR:-probe-actor}\"},"; i=$((i+1))
  done
  printf '[%s]\n' "${out%,}"
  exit 0
fi
exit 0
STUB
  chmod +x "$PTMP/bin/bd"
  SPATH="$PTMP/bin:$(dirname "$(command -v jq)"):/usr/bin:/bin"

  # 사거리 재료. 훅은 세션→actor 매핑(guard.sh 가 claim 을 관측해 적는 파일)을 읽어
  # 이 세션이 잡은 것만 센다. 실사용 매핑을 읽으면 판정이 그 머신의 세션 이력에 흔들리므로
  # 오라클과 같은 이유로 합성 파일을 물린다.
  SACTOR="$PTMP/session-actor.tsv"
  SCOPE_ACTOR="probe-actor"
  SCOPE_MODE=mine   # mine=이 세션의 actor 등재 · other=남의 세션만 등재 · none=매핑 없음

  # 훅 실행. rc 는 명령 치환 밖에서 채집한다. 격리는 환경 변수 셋이다 — HARNESS_DATA_DIR(상태
  # 파일의 자리) · HARNESS_ROOT(헬퍼가 그대로 받는 합성 루트) · HARNESS_SESSION_ACTOR_LOG(사거리
  # 재료). CWD 는 샌드박스 디렉토리다 — 훅은 더 이상 CWD 에 아무것도 쓰지 않는다. CLAUDE_PLUGIN_ROOT
  # 는 이 트리로 못박는다 — A/B 사본은 $PTMP 에 놓이는데 훅이 자기 위치로 플러그인 루트를 잡으면
  # lib/harness-root.sh 를 못 찾아 ORACLE_FAIL 로 통과하고, 그러면 "판정 줄을 뺐다" 가 공허해진다.
  SCWD="$PTMP/proj"
  SOUT=""; SRC=0
  runstop() {  # runstop <훅경로> <session_id> <stop_hook_active> → SOUT/SRC
    case "$SCOPE_MODE" in
      none)  rm -f "$SACTOR" ;;
      other) printf '%s\t%s\t%s\n' 2026-01-01T00:00:00Z "다른-세션" "$SCOPE_ACTOR" > "$SACTOR" ;;
      *)     printf '%s\t%s\t%s\n' 2026-01-01T00:00:00Z "$2" "$SCOPE_ACTOR" > "$SACTOR" ;;
    esac
    SOUT="$(cd "$SCWD" && printf '{"session_id":"%s","stop_hook_active":%s,"cwd":"%s"}' "$2" "$3" "$SCWD" \
      | env PATH="$SPATH" ORACLE_FILE="$SORACLE" SCOPE_ACTOR="$SCOPE_ACTOR" \
            HARNESS_SESSION_ACTOR_LOG="$SACTOR" HARNESS_DATA_DIR="$SDATA" HARNESS_ROOT="$SHROOT" \
            CLAUDE_PLUGIN_ROOT="$ROOT" bash "$1" 2>"$PTMP/err")"
    SRC=$?
  }
  slog_lines() { if [[ -f "$SLOG" ]]; then wc -l < "$SLOG" | tr -d ' '; else echo 0; fi; }
  is_block() { jq -e '.decision == "block"' "$1" >/dev/null 2>&1; }

  # 경로 집합을 훅 소스에서 파생한다. 표를 손으로 적지 않는다 — 새 경로의 기본값을
  # "시험됨"으로 만들려는 것이다 (극성 반전). 함수 정의(log() {)와 본문 주석은 앵커에
  # 걸리지 않는다. **그 기본값은 앵커가 행두 고정이라 훅이 현재 문체를 지키는 동안만
  # 성립한다** — 앞에 판정이 붙은 복합문으로 넣은 경로는 샌다. 실측·사유는 머리주석 한계.
  PATH_SET=()
  while IFS= read -r t; do [[ -n "$t" ]] && PATH_SET+=("$t"); done < <(
    grep -oE '^[[:space:]]*log [A-Z_]+' "$STOPHOOK" | awk '{print $2}' | sort -u)
  step "정지 가드의 경로 집합이 파생됐다 (${#PATH_SET[@]}개: ${PATH_SET[*]:-없음})" \
    [ "${#PATH_SET[@]}" -gt 0 ]

  # 상한도 소스에서 읽는다. 못 읽으면 GAVE_UP 을 밟을 수 없고, 그 사실은 아래 경로
  # 커버리지에서 시끄럽게 남는다 — 조용한 생략으로 만들지 않는다.
  SMAX="$(sed -n 's/^MAX_BLOCKS=\([0-9][0-9]*\).*/\1/p' "$STOPHOOK" | sed -n 1p)"
  step "재주입 상한을 훅 소스에서 읽었다 (MAX_BLOCKS=${SMAX:-못 읽음})" [ -n "$SMAX" ]

  # ① 판정 도달 단언 — **모든 실행 경로가 로그를 한 줄 남긴다.**
  # 이것이 "가드가 안 돌았다"와 "돌았는데 개입할 일이 없었다"를 가르는 유일한 값이다.
  # 조용한 통과 경로가 하나라도 생기면 무기록이 통과와 같은 모습이 되고, 그 순간 이 절의
  # 나머지가 전부 공허해진다 (하네스 루트 docs/guardrail-verification.md 8절이 일곱 경로 전부에 한 줄씩을
  # 요구한 이유가 그것이다). 그래서 경로별 판정과 **합계**를 함께 단언한다.
  # **기대 줄 수를 받는다.** 대부분의 경로는 판정을 끝내며 한 줄을 남기지만 SCOPE_FAIL 은
  # 아니다 — 사거리를 좁히지 못했다는 사실을 남기고 **원장 전체로 판정을 계속**하므로 그
  # 턴은 두 줄이다. 합계 단언을 "실행 회수" 가 아니라 "기대 줄 수의 합" 과 맞추는 이유가
  # 그것이고, 판정 도달의 뜻(무기록은 통과가 아니라 미실행)은 그대로다.
  runs=0; logged=0; wantlines=0; exercised=(); badrc=()
  stop_case() {  # stop_case <마지막 줄의 기대 경로> <session_id> <stop_hook_active> <오라클값> [기대 줄 수=1]
    local want="$1" sid="$2" active="$3" oracle="$4" want_n="${5:-1}" before after added got t
    printf '%s' "$oracle" > "$SORACLE"
    before="$(slog_lines)"
    runstop "$STOPABS" "$sid" "$active"
    after="$(slog_lines)"
    added=$((after - before))
    runs=$((runs + 1))
    logged=$((logged + added))
    wantlines=$((wantlines + want_n))
    [[ "$SRC" -eq 0 ]] || badrc+=("${want}:rc=${SRC}")
    got=""
    [[ "$added" -eq "$want_n" ]] && got="$(sed -n "${after}p" "$SLOG" | awk -F'\t' '{print $3}')"
    step "경로 ${want}: 로그를 정확히 ${want_n}줄 남긴다 (받은 줄: ${added})" [ "$added" -eq "$want_n" ]
    step "경로 ${want}: 마지막 줄의 경로가 ${want} 다 (받은 값: ${got:-없음})" [ "$got" = "$want" ]
    # 남긴 줄 **전부**를 밟은 경로로 센다. 마지막 줄만 세면 판정을 끝내지 않는 경로
    # (SCOPE_FAIL)가 아무리 밟혀도 커버리지에서 영영 빠진다.
    if [[ "$added" -eq "$want_n" ]]; then
      while IFS= read -r t; do [[ -n "$t" ]] && exercised+=("$t"); done < <(
        sed -n "$((before + 1)),${after}p" "$SLOG" | awk -F'\t' '{print $3}')
    fi
    return 0
  }

  stop_case RECURSE     s-recurse true  1
  stop_case IDLE        s-idle    false 0
  stop_case ORACLE_FAIL s-ofail   false FAIL
  stop_case ORACLE_FAIL s-ogarb   false GARBAGE
  # 셋째 갈래 — 하네스 루트를 못 찾는다(헬퍼 rc≠0). 0 으로 폴백하지 않고 통과한다.
  SHROOT="$PTMP/no-such-root"; stop_case ORACLE_FAIL s-noroot false 2; SHROOT="$PTMP/hroot"
  step "경로 ORACLE_FAIL(루트 없음): stdout 이 비어 있다 (막지 않는다)" [ -z "$SOUT" ]
  step "경로 ORACLE_FAIL(루트 없음): 사유가 헬퍼를 가리킨다" bash -c 'tail -1 "$1" | grep -q "harness-root"' _ "$SLOG"
  stop_case BLOCK       s-block   false 2

  # VERIFY_PENDING — 배치 모드의 검증 대기. in_progress **전부**의 마지막 note 줄이
  # VERIFY_PENDING 으로 시작하면 통과, 하나라도 아니면 종전대로 BLOCK. 픽스처는 합성 JSON 이다
  # — 실원장의 표본(마지막 note 가 그 표시인 in_progress 태스크)은 배치가 끝나면 사라지므로
  # 그것에 기대면 시험이 원장 상태에 흔들린다. 셋째 픽스처는 표시 **뒤에** note 가 더 붙은
  # 경우다 — "마지막 줄"이 판정이지 "어딘가 있음"이 아님을 못박는다.
  # assignee 는 **이 세션의 actor** 여야 한다 — 아니면 사거리 좁히기가 먼저 걸러내
  # 이 픽스처들이 VERIFY_PENDING·BLOCK 이 아니라 IDLE 로 무너진다. 값이 어긋나는 것을
  # 아래 한 줄이 잡는다 (SCOPE_ACTOR 를 바꾸고 픽스처를 안 고치면 시끄럽게 죽는다).
  FX_VP_PASS='[{"id":"fx-0","assignee":"probe-actor","notes":"구현 기록\n\nVERIFY_PENDING: 062e13c"},{"id":"fx-1","assignee":"probe-actor","notes":"VERIFY_PENDING: 19b3ae5"}]'
  FX_VP_MISS='[{"id":"fx-0","assignee":"probe-actor","notes":"구현 기록\n\nVERIFY_PENDING: 062e13c"},{"id":"fx-1","assignee":"probe-actor"}]'
  FX_VP_LATER='[{"id":"fx-0","assignee":"probe-actor","notes":"VERIFY_PENDING: 062e13c\n\n재검토 지적 1건"}]'
  printf '%s' "$FX_VP_PASS" > "$PTMP/fx-vp-pass.json"; printf '%s' "$FX_VP_MISS" > "$PTMP/fx-vp-miss.json"
  step "VERIFY_PENDING 픽스처: 통과·차단 픽스처가 둘 다 실재하고 서로 다르다" not_same "$PTMP/fx-vp-pass.json" "$PTMP/fx-vp-miss.json"
  step "VERIFY_PENDING 픽스처의 assignee 가 전부 이 세션의 actor(${SCOPE_ACTOR}) 다 — 아니면 사거리가 먼저 걸러낸다" \
    [ "$(printf '%s%s%s' "$FX_VP_PASS" "$FX_VP_MISS" "$FX_VP_LATER" | jq -rs '[.[][].assignee] | unique | join(",")')" = "$SCOPE_ACTOR" ]
  stop_case VERIFY_PENDING s-vp-pass  false "$FX_VP_PASS"
  step "경로 VERIFY_PENDING: stdout 이 비어 있다 (막지 않는다)" [ -z "$SOUT" ]
  stop_case BLOCK          s-vp-miss  false "$FX_VP_MISS"
  stop_case BLOCK          s-vp-later false "$FX_VP_LATER"
  # A/B 귀속 — 훅에서 **그 판정 줄만** 뺀 사본은 통과 픽스처를 막아야 한다. 판정 줄은 jq 로
  # 표시를 세는 한 줄이고, 빠지면 훅의 ${pending:-0} 이 0 으로 기울어 막힘이 된다. 사본이
  # 정확히 한 줄 짧음을 먼저 단언한다 — 문면이 바뀌어 grep 이 아무것도 못 빼면 이 A/B 는
  # 원본을 다시 돌리는 것이 되어 공허하게 실패하지 않는다.
  HOOK_WO="$PTMP/stop-resume-wo.sh"
  grep -v 'startswith("VERIFY_PENDING")' "$STOPHOOK" > "$HOOK_WO"
  step "A/B 사본: 판정 줄 하나만 빠졌다 ($(wc -l < "$STOPHOOK" | tr -d ' ') → $(wc -l < "$HOOK_WO" | tr -d ' '))" \
    [ "$(wc -l < "$HOOK_WO" | tr -d ' ')" -eq "$(( $(wc -l < "$STOPHOOK" | tr -d ' ') - 1 ))" ]
  printf '%s' "$FX_VP_PASS" > "$SORACLE"; runstop "$HOOK_WO" s-vp-ab false; printf '%s' "$SOUT" > "$PTMP/vp-ab.json"
  step "A/B 귀속: 판정 줄을 뺀 사본에서 통과 픽스처가 block 이 된다" is_block "$PTMP/vp-ab.json"
  step "A/B 사본도 비-0 으로 죽지 않는다 (rc=${SRC})" [ "$SRC" -eq 0 ]

  # DELEGATED — 배치 위임 **직전**에 태스크마다 남기는 표시 (harness-o59 / harness-0uw). 자리와
  # 규칙은 VERIFY_PENDING 과 같다: notes 의 마지막 비어 있지 않은 줄이고, 하나라도 표시가 없으면
  # 종전대로 막는다. 섞인 상태(일부 VERIFY_PENDING · 나머지 DELEGATED)도 면제 대상이다 — 배치
  # 사이클에서 앞 태스크가 커밋되고 뒤 태스크는 아직인 상태가 그 모습이라 그것이 실제 형상이다.
  FX_DG_PASS='[{"id":"fx-d0","assignee":"probe-actor","notes":"DELEGATED: fx-milestone"},{"id":"fx-d1","assignee":"probe-actor","notes":"ACTOR: sess-fx\n\nDELEGATED: fx-milestone"}]'
  FX_DG_MIX='[{"id":"fx-m0","assignee":"probe-actor","notes":"VERIFY_PENDING: 062e13c"},{"id":"fx-m1","assignee":"probe-actor","notes":"DELEGATED: fx-milestone"}]'
  FX_DG_MISS='[{"id":"fx-x0","assignee":"probe-actor","notes":"DELEGATED: fx-milestone"},{"id":"fx-x1","assignee":"probe-actor","notes":"구현 기록"}]'
  FX_DG_EMPTY='[{"id":"fx-e0","assignee":"probe-actor","notes":""}]'
  printf '%s' "$FX_DG_PASS" > "$PTMP/fx-dg-pass.json"; printf '%s' "$FX_DG_MISS" > "$PTMP/fx-dg-miss.json"
  step "DELEGATED 픽스처: 통과·차단 픽스처가 둘 다 실재하고 서로 다르다" not_same "$PTMP/fx-dg-pass.json" "$PTMP/fx-dg-miss.json"
  step "DELEGATED 픽스처의 assignee 가 전부 이 세션의 actor(${SCOPE_ACTOR}) 다 — 아니면 사거리가 먼저 걸러낸다" \
    [ "$(printf '%s%s%s%s' "$FX_DG_PASS" "$FX_DG_MIX" "$FX_DG_MISS" "$FX_DG_EMPTY" | jq -rs '[.[][].assignee] | unique | join(",")')" = "$SCOPE_ACTOR" ]
  stop_case VERIFY_PENDING s-dg-pass  false "$FX_DG_PASS"
  step "DELEGATED: 전부 위임 직후 표시면 stdout 이 비어 있다 (막지 않는다)" [ -z "$SOUT" ]
  dg_log=0; tail -1 "$SLOG" | cut -f4 | grep -q '검증 대기 0건 · 위임 직후 2건' && dg_log=1
  step "DELEGATED: 그 로그 한 줄이 두 표시의 건수를 구분해 든다" [ "$dg_log" -eq 1 ]
  stop_case VERIFY_PENDING s-dg-mix   false "$FX_DG_MIX"
  step "DELEGATED: 섞인 표시도 면제된다 (stdout 이 비어 있다)" [ -z "$SOUT" ]
  stop_case BLOCK          s-dg-miss  false "$FX_DG_MISS"
  stop_case BLOCK          s-dg-empty false "$FX_DG_EMPTY"
  # A/B 귀속 — **DELEGATED 판정 줄만** 뺀 사본은 통과 픽스처를 막아야 한다. VERIFY_PENDING 쪽의
  # A/B 와 줄이 다르므로 둘을 각각 건다 — 한 줄로 합치면 어느 표시가 판정을 낸 것인지 안 갈린다.
  HOOK_DG="$PTMP/stop-resume-dg.sh"
  grep -v 'startswith("DELEGATED")' "$STOPHOOK" > "$HOOK_DG"
  step "A/B 사본: DELEGATED 판정 줄 하나만 빠졌다 ($(wc -l < "$STOPHOOK" | tr -d ' ') → $(wc -l < "$HOOK_DG" | tr -d ' '))" \
    [ "$(wc -l < "$HOOK_DG" | tr -d ' ')" -eq "$(( $(wc -l < "$STOPHOOK" | tr -d ' ') - 1 ))" ]
  step "A/B 사본이 실재하고 원본과 다르다" not_same "$STOPHOOK" "$HOOK_DG"
  printf '%s' "$FX_DG_PASS" > "$SORACLE"; runstop "$HOOK_DG" s-dg-ab false; printf '%s' "$SOUT" > "$PTMP/dg-ab.json"
  step "A/B 귀속: DELEGATED 판정 줄을 뺀 사본에서 통과 픽스처가 block 이 된다" is_block "$PTMP/dg-ab.json"
  step "A/B 사본도 비-0 으로 죽지 않는다 (rc=${SRC})" [ "$SRC" -eq 0 ]
  # 출구 안내 — 차단 메시지가 두 표시를 다 든다. 막기만 하고 나가는 길을 안 적으면 헛턴이 상한까지 간다.
  step "출구 안내: 차단 메시지가 DELEGATED 를 든다" grep -q 'DELEGATED' "$PTMP/dg-ab.json"
  step "출구 안내: 차단 메시지가 VERIFY_PENDING 도 든다" grep -q 'VERIFY_PENDING' "$PTMP/dg-ab.json"

  # CANCEL — **소유자는 파일 이름에 있다** (harness-o59). 빈 입구 마커를 처음 본 세션이 자기
  # 자리로 mv 하고, 그 뒤로는 자기 자리만 보고 통과한다. 다른 세션의 Stop 이 지나가도 남의
  # 자리를 읽지도 지우지도 않는다 — 옛 형태는 여기서 rm 했고 실사용 귀속 8건이 전부 그렇게
  # 뺏겼다. 그래서 "B 가 지나가도 A 의 파일이 실재한다"가 판정 대상이다.
  SRC_MARK="$SDATA/stop-resume-cancel"
  MARK_A="$SRC_MARK.s-cancel"
  : > "$SRC_MARK"
  stop_case CANCEL      s-cancel  false 2
  mk=0; [[ -f "$MARK_A" && ! -f "$SRC_MARK" ]] && mk=1
  step "경로 CANCEL: 사람 입구를 이 세션의 자리로 옮긴다 (입구는 사라지고 자기 자리에 생긴다)" [ "$mk" -eq 1 ]
  stop_case CANCEL      s-cancel  false 2
  step "경로 CANCEL: 같은 세션이면 자기 자리의 마커를 소비하지 않는다" [ -f "$MARK_A" ]
  # 소유자 보존 — B 의 Stop 은 A 의 마커에 손대지 않는다. B 자신은 마커가 없으니 종전대로 막힌다.
  stop_case BLOCK       s-other   false 2
  step "경로 CANCEL: 남의 세션 Stop 이 지나가도 A 의 마커가 그대로 있다" [ -f "$MARK_A" ]
  stop_case CANCEL      s-cancel  false 2
  step "경로 CANCEL: 그 뒤에도 A 는 CANCEL 로 통과하고 마커를 유지한다" [ -f "$MARK_A" ]
  # A/B 귀속 — 귀속 mv 줄만 뺀 사본은 입구를 옮기지 못한다(그 세션의 자리가 생기지 않는다).
  HOOK_OWN="$PTMP/stop-resume-own.sh"
  grep -v 'CANCEL_OWN' "$STOPHOOK" > "$HOOK_OWN"
  step "A/B 사본: 귀속 줄 하나만 빠졌다 ($(wc -l < "$STOPHOOK" | tr -d ' ') → $(wc -l < "$HOOK_OWN" | tr -d ' '))" \
    [ "$(wc -l < "$HOOK_OWN" | tr -d ' ')" -eq "$(( $(wc -l < "$STOPHOOK" | tr -d ' ') - 1 ))" ]
  step "A/B 사본이 실재하고 원본과 다르다" not_same "$STOPHOOK" "$HOOK_OWN"
  : > "$SRC_MARK"; printf '2' > "$SORACLE"; runstop "$HOOK_OWN" s-own-ab false
  ab_own=0; [[ ! -f "$SRC_MARK.s-own-ab" && -f "$SRC_MARK" ]] && ab_own=1
  step "A/B 귀속: 귀속 줄을 뺀 사본에서는 입구가 그 세션의 자리로 옮겨지지 않는다" [ "$ab_own" -eq 1 ]
  step "A/B 사본도 비-0 으로 죽지 않는다 (rc=${SRC})" [ "$SRC" -eq 0 ]
  # 실패 경로 — 마커 자리에 쓸 수 없어도 죽지 않는다. 로그는 **이미 있는 파일에 append** 라
  # 디렉토리 쓰기 권한 없이도 남는다(그것이 이 시험이 성립하는 조건이고, 그래서 mv 만 죽는다).
  chmod a-w "$SDATA"
  stop_case CANCEL      s-nowrite false 2
  chmod u+w "$SDATA"
  nw=0; [[ -f "$SRC_MARK" && ! -f "$SRC_MARK.s-nowrite" ]] && nw=1
  step "경로 CANCEL: 마커를 옮기지 못하면 입구가 남고 로그 한 줄로 그 사실이 구분된다" [ "$nw" -eq 1 ]
  rm -f "$SRC_MARK"

  # ── 데이터 디렉토리 — 상태 파일이 프로젝트 밖의 한 자리에만 떨어진다 ────────────
  # 종전에는 로그가 본 체크아웃의 .claude/ 에, 마커가 CWD 에 떨어졌다(harness-o59 의 로그 앵커).
  # 이제 둘 다 HARNESS_DATA_DIR 아래다 — 기본값은 $HOME/.claude/plugins/data/harness. 위 시험은
  # 전부 그 변수를 샌드박스로 돌려 돌았으므로, **기본값 경로**와 **만들 수 없는 경로**를 따로 본다.
  DHOME="$PTMP/home"; mkdir -p "$DHOME"
  printf '0' > "$SORACLE"
  DOUT="$(cd "$SCWD" && printf '{"session_id":"s-default","stop_hook_active":true}' \
    | env -u HARNESS_DATA_DIR PATH="$SPATH" HOME="$DHOME" HARNESS_ROOT="$SHROOT" CLAUDE_PLUGIN_ROOT="$ROOT" bash "$STOPABS" 2>"$PTMP/derr")"; DRC=$?
  step "데이터 디렉토리 기본값: HOME 아래 .claude/plugins/data/harness/stop-resume.log 에 한 줄이 남는다" \
    [ "$(wc -l < "$DHOME/.claude/plugins/data/harness/stop-resume.log" 2>/dev/null | tr -d ' ')" = "1" ]
  step "데이터 디렉토리 기본값: 실행 디렉토리에는 아무것도 떨어지지 않는다" [ -z "$(ls -A "$SCWD")" ]
  step "데이터 디렉토리 기본값: rc=0 (실제 ${DRC})" [ "$DRC" -eq 0 ]
  : > "$PTMP/notadir"    # 일반 파일 — 그 아래에는 디렉토리를 만들 수 없다 (없는 경로는 mkdir -p 가 만들어 버린다)
  DOUT="$(cd "$SCWD" && printf '{"session_id":"s-nodir","stop_hook_active":false}' \
    | env -u HARNESS_DATA_DIR PATH="$SPATH" HOME="$PTMP/notadir" HARNESS_ROOT="$SHROOT" bash "$STOPABS" 2>"$PTMP/derr")"; DRC=$?
  step "데이터 디렉토리를 만들 수 없으면 막지 않는다 (rc=0, 실제 ${DRC})" [ "$DRC" -eq 0 ]
  step "그때 stdout 은 비어 있다 (판정하지 않는다)" [ -z "$DOUT" ]
  step "그 사실이 stderr 한 줄로 남는다" grep -q '데이터 디렉토리' "$PTMP/derr"
  # 기존 루프 마커는 **읽지 않는다.** 한 마커로 두 장치를 끄면 무엇을 껐는지 기록이
  # 구분하지 못한다 — 그 마커만 있으면 그대로 막혀야 한다.
  : > "$SDATA/ralph-cancel"
  stop_case BLOCK       s-notralph false 2
  step "경로 CANCEL: 루프 취소 마커를 읽지도 소비하지도 않는다" \
    [ -f "$SDATA/ralph-cancel" ]

  # GAVE_UP — 같은 세션이 상한만큼 막힌 뒤에는 막지 않는다. 상한 계산의 출처가 로그
  # 자신이므로, 이 시험은 위 BLOCK 줄들이 실제로 쌓였다는 것까지 함께 확인한다.
  if [[ -n "$SMAX" ]]; then
    i=0
    while [[ "$i" -lt "$SMAX" ]]; do stop_case BLOCK s-cap false 2; i=$((i + 1)); done
    stop_case GAVE_UP s-cap false 2
  fi

  # ── 사거리 — 오라클이 세는 것이 **이 세션이 잡은 일**인가 ───────────────
  # 좁히기 전에는 남의 세션이 잡은 in_progress 로도 막혔다(그것이 이 훅이 실효보다
  # 꺼져 있는 턴이 훨씬 많았던 이유다 — docs/guardrail-verification.md 8절 천장 1). 픽스처는 **폴백의
  # 두 방향**을 각각 밟는다: 매핑을 읽지 못하면 종전대로 원장 전체(SCOPE_FAIL), 읽었는데
  # 이 세션의 actor 가 없으면 통과(NO_CLAIM). 하나로 합치면 가드가 조용히 꺼지거나
  # 아무것도 안 고쳐지므로, 둘이 서로 다른 경로를 낸다는 것 자체가 판정 대상이다.
  SCOPE_FX=()
  FX_SC_OTHER='[{"id":"fx-o","assignee":"다른-actor"}]'
  FX_SC_MINE='[{"id":"fx-m","assignee":"probe-actor"}]'
  printf '%s' "$FX_SC_OTHER" > "$PTMP/fx-sc-other.json"; printf '%s' "$FX_SC_MINE" > "$PTMP/fx-sc-mine.json"
  step "사거리 픽스처: 남의 actor·이 세션 actor 픽스처가 둘 다 실재하고 서로 다르다" \
    not_same "$PTMP/fx-sc-other.json" "$PTMP/fx-sc-mine.json"

  # ① 남의 actor 만 표시 없이 in_progress → 막지 않는다. **변경 전에는 BLOCK 이었다.**
  stop_case IDLE s-sc-other false "$FX_SC_OTHER"; SCOPE_FX+=("남의 actor→통과")
  step "사거리 ①: 남의 actor 만 있으면 stdout 이 비어 있다 (막지 않는다)" [ -z "$SOUT" ]
  # ② 이 세션의 actor 가 표시 없이 in_progress → 종전대로 막는다.
  stop_case BLOCK s-sc-mine false "$FX_SC_MINE"; SCOPE_FX+=("이 세션 actor→block")
  printf '%s' "$SOUT" > "$PTMP/sc-mine.json"
  step "사거리 ②: 이 세션이 잡은 일은 종전대로 막힌다" is_block "$PTMP/sc-mine.json"
  sc_scoped=0
  tail -1 "$SLOG" | cut -f4 | grep -q -- "$SCOPE_ACTOR" && sc_scoped=1
  step "사거리 ②: 차단 로그의 4열이 좁힌 범위(${SCOPE_ACTOR})를 든다" [ "$sc_scoped" -eq 1 ]
  # ③ 매핑은 읽혔는데 이 세션의 actor 가 한 줄도 없다 → NO_CLAIM 으로 통과.
  SCOPE_MODE=other; stop_case NO_CLAIM s-sc-noclaim false "$FX_SC_MINE"; SCOPE_MODE=mine
  SCOPE_FX+=("매핑에 이 세션 없음→NO_CLAIM")
  step "사거리 ③: NO_CLAIM 은 막지 않는다" [ -z "$SOUT" ]
  # ④ 매핑 파일이 없다 → SCOPE_FAIL 을 남기고 **원장 전체**로 판정한다. 통과로 폴백하면
  #    가드가 조용히 꺼지므로, 남의 actor 픽스처가 여기서는 막혀야 한다.
  SCOPE_MODE=none; stop_case BLOCK s-sc-nomap false "$FX_SC_OTHER" 2; SCOPE_MODE=mine
  SCOPE_FX+=("매핑 없음→SCOPE_FAIL 후 원장 전체")
  printf '%s' "$SOUT" > "$PTMP/sc-nomap.json"
  step "사거리 ④: 매핑이 없으면 남의 actor 로도 막는다 (통과로 폴백하지 않는다)" is_block "$PTMP/sc-nomap.json"
  step "사거리 ④: 그 두 줄의 앞 줄이 SCOPE_FAIL 이다" \
    [ "$(tail -2 "$SLOG" | head -1 | cut -f3)" = "SCOPE_FAIL" ]
  # 집합이 빈 채로 참이 되는 것을 막는다 (docs/development.md "검사가 죽었는지 검사한다").
  step "사거리 픽스처 집합이 비지 않았다 (${#SCOPE_FX[@]}종: ${SCOPE_FX[*]:-없음})" \
    [ "${#SCOPE_FX[@]}" -ge 4 ]

  # A/B 귀속 — 훅에서 **좁히기 판정 줄만** 뺀 사본은 픽스처 ① 을 막아야 한다. 사본이
  # 정확히 한 줄 짧음을 먼저 단언한다: 표지가 사라져 grep 이 아무것도 못 빼면 이 A/B 는
  # 원본을 다시 돌리는 것이 되어 공허하게 통과한다 (harness-erf).
  HOOK_SC="$PTMP/stop-resume-sc.sh"
  grep -v 'SCOPE_NARROW' "$STOPHOOK" > "$HOOK_SC"
  step "A/B 사본: 좁히기 판정 줄 하나만 빠졌다 ($(wc -l < "$STOPHOOK" | tr -d ' ') → $(wc -l < "$HOOK_SC" | tr -d ' '))" \
    [ "$(wc -l < "$HOOK_SC" | tr -d ' ')" -eq "$(( $(wc -l < "$STOPHOOK" | tr -d ' ') - 1 ))" ]
  step "A/B 사본이 실재하고 원본과 다르다" not_same "$STOPHOOK" "$HOOK_SC"
  printf '%s' "$FX_SC_OTHER" > "$SORACLE"; runstop "$HOOK_SC" s-sc-ab false
  printf '%s' "$SOUT" > "$PTMP/sc-ab.json"
  step "A/B 귀속: 좁히기 판정 줄을 뺀 사본에서 남의 actor 가 block 이 된다" is_block "$PTMP/sc-ab.json"
  step "A/B 사본도 비-0 으로 죽지 않는다 (rc=${SRC})" [ "$SRC" -eq 0 ]

  # 부정 대조군 — 매핑을 **쓰는** 쪽(guard.sh 의 관측 호출)만 뺀 사본은 같은 claim 입력에서
  # 줄을 남기지 않는다. 여기가 없으면 위 픽스처들은 "훅이 매핑을 읽는다"만 세우고
  # "그 매핑이 실제로 claim 관측으로 채워진다"는 아무도 안 본다.
  GHOOK_SC="$PTMP/guard-noobserve.sh"
  grep -v 'SA_OBSERVE_CALL' "$HOOK" > "$GHOOK_SC"
  step "부정 대조군 사본: 관측 호출 한 줄만 빠졌다 ($(wc -l < "$HOOK" | tr -d ' ') → $(wc -l < "$GHOOK_SC" | tr -d ' '))" \
    [ "$(wc -l < "$GHOOK_SC" | tr -d ' ')" -eq "$(( $(wc -l < "$HOOK" | tr -d ' ') - 1 ))" ]
  step "부정 대조군 사본이 실재하고 원본과 다르다" not_same "$HOOK" "$GHOOK_SC"
  SA_MAP="$PTMP/sa-map.tsv"; : > "$SA_MAP"
  SA_PROBE='{"tool_name":"Bash","session_id":"sa-1","cwd":"/tmp","tool_input":{"command":"bd -C /h update t-1 --claim --actor probe-actor"}}'
  sa_run() { printf '%s' "$SA_PROBE" | env HARNESS_SESSION_ACTOR_LOG="$SA_MAP" bash "$1" >/dev/null 2>&1 || true; }
  sa_run "$HOOK";      sa_n1="$(wc -l < "$SA_MAP" | tr -d ' ')"
  sa_run "$GHOOK_SC";  sa_n2="$(wc -l < "$SA_MAP" | tr -d ' ')"
  step "관측 양성: claim 명령 하나가 매핑에 정확히 한 줄을 남긴다 (${sa_n1}줄)" [ "$sa_n1" -eq 1 ]
  sa_shape=0
  awk -F'\t' 'NF == 3 && $1 ~ /T.*Z$/ && $2 == "sa-1" && $3 == "probe-actor" { ok = 1 } END { exit !ok }' \
    "$SA_MAP" && sa_shape=1
  step "관측 양성: 그 줄이 <UTC 시각>\\t<session_id>\\t<actor> 다" [ "$sa_shape" -eq 1 ]
  step "부정 대조군: 관측 호출을 뺀 사본은 같은 입력에 줄을 남기지 않는다 (${sa_n1} → ${sa_n2})" \
    [ "$sa_n2" -eq "$sa_n1" ]

  step "시험이 0건이 아니다 (훅을 ${runs}회 실행했다)" [ "$runs" -gt 0 ]
  step "판정 도달: 실행 ${runs}회의 기록이 기대 줄 수와 같다 (기록 ${logged}줄 / 기대 ${wantlines}줄) — 무기록은 통과가 아니라 미실행이다" \
    [ "$logged" -eq "$wantlines" ]
  step "기대 줄 수가 실행 회수보다 적지 않다 (${wantlines} ≥ ${runs}) — 어느 실행도 무기록으로 기대되지 않는다" \
    [ "$wantlines" -ge "$runs" ]
  [[ ${#badrc[@]} -gt 0 ]] && say_fail "정지 가드가 비-0 으로 끝난 경로: ${badrc[*]} — 이 훅은 어느 경로에서도 세션을 죽이면 안 된다"
  step "어느 경로에서도 비-0 으로 죽지 않는다" [ "${#badrc[@]}" -eq 0 ]

  # 정방향: 파생한 경로 전원이 실제 실행으로 밟혔는가.
  uncov_s=()
  for t in ${PATH_SET[@]+"${PATH_SET[@]}"}; do
    printf '%s\n' ${exercised[@]+"${exercised[@]}"} | grep -qx -- "$t" || uncov_s+=("$t")
  done
  [[ ${#uncov_s[@]} -gt 0 ]] && say_fail "밟지 않은 정지 가드 경로: ${uncov_s[*]} — 경로가 새로 생겼으면 stop_case 를 더해라. 시험하지 않은 경로는 죽어도 아무도 모른다"
  step "경로 전원이 실제 실행으로 시험됐다 (${#PATH_SET[@]}개)" [ "${#uncov_s[@]}" -eq 0 ]

  # 역방향: 시험한 토큰이 전부 실재하는 경로인가. 경로가 사라졌는데 시험만 남으면
  # 그 시험은 "로그가 안 남는다"로 시끄럽게 죽지만, 무엇이 사라졌는지는 안 말한다.
  stale_s=()
  for t in ${exercised[@]+"${exercised[@]}"}; do
    printf '%s\n' ${PATH_SET[@]+"${PATH_SET[@]}"} | grep -qx -- "$t" || stale_s+=("$t")
  done
  [[ ${#stale_s[@]} -gt 0 ]] && say_fail "시험한 경로 토큰이 훅에 없다: ${stale_s[*]} — 경로가 사라졌다면 시험도 지워라"
  step "시험한 경로 토큰이 전부 실재한다" [ "${#stale_s[@]}" -eq 0 ]

  # ② 부정 대조군 — **오라클만** 흔든 두 실행의 stdout 이 서로 달라야 한다.
  # 재료가 단독으로 무엇을 내는지 먼저 단언한다: 둘 다 block 결정이어야 하고, 그 다음에야
  # "달라졌다"를 오라클 때문이라고 읽을 수 있다. 차단 메시지가 오라클 값을 잃어버리면
  # (하드코딩·문자열 유실) 두 stdout 이 같아지고 여기서 잡힌다.
  printf '1' > "$SORACLE"; runstop "$STOPABS" s-nc1 false; printf '%s' "$SOUT" > "$PTMP/nc1.json"
  printf '2' > "$SORACLE"; runstop "$STOPABS" s-nc2 false; printf '%s' "$SOUT" > "$PTMP/nc2.json"
  step "부정 대조군 재료 ①: 오라클 1 에서 block 결정을 낸다" is_block "$PTMP/nc1.json"
  step "부정 대조군 재료 ②: 오라클 2 에서도 block 결정을 낸다" is_block "$PTMP/nc2.json"
  step "부정 대조군: 오라클만 흔들면 두 stdout 이 갈린다" not_same "$PTMP/nc1.json" "$PTMP/nc2.json"
  # 그리고 막지 않는 경로에서는 stdout 이 **비어 있다**. 이것이 없으면 "달랐다"가
  # "한쪽이 아무것도 안 냈다"와 구분되지 않는다.
  printf '0' > "$SORACLE"; runstop "$STOPABS" s-nc0 false
  step "오라클 0 에서는 stdout 이 비어 있다 (막지 않는다)" [ -z "$SOUT" ]

  # ③④ 대상 단언과 A/B 귀속은 둘 다 **배선**이 출처다 — hooks.json 이다.
  if true; then
    stop_wired() {  # stop_wired <hooks.json> → Stop 에 배선된 훅 파일 경로들
      jq -r '(.hooks.Stop // [])[] | (.hooks // [])[] | select(.type == "command") | .command' "$1" \
        | grep -oE 'hooks/[A-Za-z0-9_.-]+\.sh' | sort -u
    }
    WIRED=()
    while IFS= read -r p; do [[ -n "$p" ]] && WIRED+=("$p"); done < <(stop_wired "$HOOKSJSON")
    step "Stop 에 배선된 훅을 파생했다 (${#WIRED[@]}개: ${WIRED[*]:-없음})" [ "${#WIRED[@]}" -gt 0 ]

    # ④ 대상 단언 — 위에서 **먹인 파일**이 그 배선이 가리키는 경로인가.
    # rc 만 보면 무엇을 시험했는지 드러나지 않는다: Stop 에는 훅이 둘 배선돼 있어
    # ("이 가드"와 ralph-cancel.sh), "Stop 훅이 배선돼 있다"는 단언은 다른 하나만으로도
    # 참이 된다. 이 절이 먹인 것은 $STOPABS 이고 그것이 이 경로에서 나왔음을 못박는다.
    hits=0
    for p in ${WIRED[@]+"${WIRED[@]}"}; do [[ "$p" == "$STOPHOOK" ]] && hits=$((hits + 1)); done
    [[ "$hits" -eq 1 ]] || say_fail "시험한 파일이 Stop 배선과 맞지 않는다: ${STOPHOOK} 을 가리키는 배선 ${hits}건 (배선된 것: ${WIRED[*]:-없음}) — 배선되지 않은 파일을 시험하면 통과가 아무것도 뜻하지 않는다"
    step "대상 단언: 시험한 파일이 ${HOOKSJSON} 의 Stop 에 배선된 그 경로다 (${STOPHOOK})" \
      [ "$hits" -eq 1 ]

    # ③ A/B 귀속 — 그 **등재만** 뺀 사본에서 위 대상 파생이 뒤집힌다. 사본이 원본과
    # 다름을 먼저 단언한다: 배선 형태가 바뀌어 jq 가 아무것도 못 지우면 "뒤집혔다"가
    # 조용히 공허해진다 (harness-erf).
    # 원본도 **같은 jq 로 정규화해** 둔다. 사본을 디스크 원본과 그대로 비교하면 들여쓰기·키
    # 순서 차이만으로 not_same 이 참이 되어, 등재를 하나도 못 지운 사본이 "다르다"로 읽힌다
    # — 선단언이 조용히 공허해지는 자리다 (실측: 대조군 f 에서 그렇게 통과했다).
    jq -S . "$HOOKSJSON" > "$PTMP/settings-base.json" 2>/dev/null
    jq -S --arg f "$STOPHOOK" \
      '(.hooks.Stop) |= [ .[] | .hooks |= [ .[] | select((.command // "") | contains($f) | not) ] ]' \
      "$HOOKSJSON" > "$PTMP/settings-wo.json" 2>/dev/null
    if ! not_same "$PTMP/settings-base.json" "$PTMP/settings-wo.json"; then
      say_fail "Stop 등재만 뺀 사본이 원본과 같거나 만들어지지 않았다 — 배선 형태가 바뀌어 jq 가 아무것도 못 지웠다. 이 절의 A/B 귀속이 공허해진다"
      fail=1
    else
      WO=()
      while IFS= read -r p; do [[ -n "$p" ]] && WO+=("$p"); done < <(stop_wired "$PTMP/settings-wo.json")
      wo_hits=0
      for p in ${WO[@]+"${WO[@]}"}; do [[ "$p" == "$STOPHOOK" ]] && wo_hits=$((wo_hits + 1)); done
      step "A/B 귀속: 등재를 빼면 대상 파생이 그 경로를 더는 찾지 못한다 (${wo_hits}건)" \
        [ "$wo_hits" -eq 0 ]
      # 파생 자체가 죽어서 0 이 된 것과 구분한다 — 사라진 것이 그 한 항목뿐이어야 한다.
      step "A/B 귀속: 사본에서 사라진 배선이 그 하나뿐이다 (${#WIRED[@]} → ${#WO[@]})" \
        [ "${#WO[@]}" -eq "$((${#WIRED[@]} - 1))" ]
    fi
  fi
fi

echo
if [[ "$fail" -eq 0 ]]; then
  echo "강제 장치 검사 통과 — 단언 ${pass_n} · 규칙 ${#RULE_SET[@]} · 훅 배선 ${#wired_arr[@]}(hooks.json) · 셸 ${#SH_SET[@]} · 검사 ${#CHECK_SET[@]}"
  if [[ "$VERBOSE" != 1 ]]; then
    echo "  (단언 전문은 GUARDRAIL_VERBOSE=1)"
  fi
else
  echo "강제 장치 검사 실패 — 위의 ✗ 항목을 고쳐라. 난간이 조용히 사라진 상태일 수 있다" >&2
  echo "  통과한 단언 ${pass_n} 개는 생략됐다. 전문은 GUARDRAIL_VERBOSE=1 로 다시 돌려라" >&2
fi
exit "$fail"
