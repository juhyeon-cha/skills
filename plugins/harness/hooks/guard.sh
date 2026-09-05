#!/bin/bash
# PreToolUse 훅 — 하네스 불변식을 지키는 난간(guardrail)의 골격.
#
# 규칙은 등록부(RULES)에 하나씩 얹힌다. 등록부가 비어 있던 골격 시점의 기반선
# (모든 입력이 통과)이 harness-uhy.3.5 note 에 기록돼 있어, 지금의 차단이 규칙 때문임을
# 그 기록과의 대조로 증명한다. 규칙별 실측은 그 규칙을 만든 태스크 bead 의 note 에 있다.
#
# **남은 규칙은 앵커와 무관한 불변식 넷이다** (플러그인 재구조화 — 스토리 harness-lzs3 "결정됨"):
#   작업은 워크트리에서만 …… r_main_write · r_main_shell
#   만든 주체가 채점하지 않는다 … r_grader_write · r_grader_shell · r_impl_bd
#   원격은 사람이 연다 ……………… r_remote
#   원장 하나 …………………………… r_bd_root
# 뺀 것과 그 사유는 태스크 harness-lzs3.3.1 의 note 표가 든다 — 트리 앵커(GUARD_ROOT·.harness-state·
# 앵커 트리의 원장 이름)에 기대던 규칙과 불변식 밖 규칙이다. 앵커·플러그인 루트·실측 형식은 아래 GUARD_ROOT 주석.
#
# 담장이 아니라 난간이다. 명령 문자열 검사는 원리적으로 완전하지 않다 — 스크립트
# 경유 밀수(`bash x.sh` 안의 명령은 훅에 이벤트로 뜨지 않는다)와 인터프리터 간접
# 실행이 실측으로 통과했다 (harness-uhy.1.1 note "막을 수 없는 것").
# 부주의한 사고를 막는 것이 목적이고, 악의적 우회를 막는 보안 경계로 쓰지 마라.
#
# 계약:
#   입력  stdin 의 PreToolUse 이벤트 JSON (tool_name·tool_input·agent_id·agent_type·cwd)
#   차단  종료 코드 2 + stderr 사유 문자열 (deny 함수)
#   통과  종료 코드 0, stdout 무출력
#   부수  호출마다 발화 로그 한 줄 (아래 "발화 로그" 절). 판정에는 영향이 없고, 로그가
#         실패해도 훅은 죽지 않는다
#   (차단은 hookSpecificOutput.permissionDecision=deny JSON 으로도 되지만, 스파이크가
#    실측한 것은 종료 코드 2 쪽이라 그것을 쓴다.)
#
# 규칙을 추가하는 법:
#   ① 함수를 하나 쓴다 — 이름은 `r_` 접두. 차단할 때 deny "<사유>", 그 외에는 return 0.
#   ② RULES 에 "<도구이름 또는 *>:<함수이름>" 한 줄을 등재한다.
#   ③ 규칙 블록은 아래 `RULES=()` **뒤에** 둔다. 앞에 두면 `RULES=()` 가 등재를 지운다.
#   ①의 `r_` 접두와 ③의 배치를 checks/guard-check.sh ⑦ 이 역방향으로 단언한다 —
#   함수를 정의해 놓고 등재를 빠뜨리거나 순서가 뒤집히면 게이트가 비-0 으로 깨진다.
#   규칙 본문에서 **명령 형태를 정규식으로 열거하지 마라.** 그 접근은 스파이크에서
#   세 번 연속 샜고(래퍼 `timeout`, 옵션 위치 `git -C`) 한 번은 경로 속 `.git` 덕에
#   우연히 맞았다. 하위 명령 토큰의 존재만 보는 극성 반전(has_token)이 8건 전부를
#   의도대로 잡았다. 대가는 오탐이며 그 교환은 의도적으로 받아들인 것이다.
# **미도달은 차단이다.** Claude Code 는 rc=2 만 차단으로 읽으므로 훅이 내부 오류(unbound
# 변수·없는 명령)로 rc=1 에 죽으면 그 호출은 **통과**한다 — fail-open [실측 2026-08-28, 리뷰 #7].
# 판정에 도달한 출구(deny·SKIP·마지막 exit 0)만 GUARD_DONE=1 을 세우고, 나머지는 여기서 막는다.
# set -u 보다 **앞**에 둔다 — 그 뒤 첫 줄의 오류부터 덮어야 한다.
GUARD_DONE=0
trap '[ "$GUARD_DONE" = 1 ] || { echo "GUARD-DENY: 훅이 판정에 도달하지 못했다 (내부 오류 rc=$?) — 통과가 아니라 차단으로 넘어진다. hooks/guard.sh 를 고쳐라" >&2; exit 2; }' EXIT
set -uo pipefail

# **플러그인 루트.** hooks.json 이 `${CLAUDE_PLUGIN_ROOT}` 를 주고, 검사가 훅을 직접 부를 때는 그
# 변수가 없으므로 자기 위치의 부모로 떨어진다(사본을 다른 앵커에 두고 돌리는 검사가 그 형태다).
#
# **이 값은 하네스 루트도 프로젝트 루트도 워크트리도 아니다** — 플러그인은 셋 다의 밖에 산다. 규칙은
# 이 값을 트리 판정에 쓰지 않는다. 쓰는 곳은 둘뿐이다: 내부 오류 메시지의 자기 경로, 그리고
# lib/harness-root.sh 의 자리(r_bd_root 의 차단 메시지가 하네스 루트를 제시할 때 부른다).
# 종전에 이 값에 기대던 규칙(파생본 판별 .harness-state · 앵커 트리의 원장 이름)은 뺐다.
#
# 클론 루트를 기준으로 판정하는 규칙(r_main_write·r_main_shell)의 값은
# `${HARNESS_CLONE_ROOT:-$HOME/.harness-workspace}` 다 — scripts/repo.sh·scripts/workspace.sh 가
# 클론 위치를 정할 때 쓰는 바로 그 규약이다.
#
# agent_type 의 실측 형식은 `harness:<에이전트이름>` 이다 (M0 실측 harness-lzs3.1 note —
# 플러그인이름:에이전트이름). 역할별 규칙은 그 형식 하나로만 대조한다 — 접두 없는 값을 함께 받으면
# 플러그인 밖의 동명 에이전트가 이 하네스의 역할로 읽힌다.
GUARD_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# ── 발화 로그 ────────────────────────────────────────────────────────
# **줄 하나를 호출마다 남긴다 — 차단이든 통과든.** 차단만 기록하면 "발화 0" 과
# "훅이 안 돌았다" 가 둘 다 무기록이라 구분되지 않는다. 그 구분이 이 로그의 존재
# 이유다 (harness-pl7 S16 의 전제: "지금은 무기록이라 '발화 0' 과
# '훅이 안 돌았다' 가 구분되지 않는다").
#
# **회차의 정의는 페이로드의 session_id 다.** ADR 이 적은 회차 경계는 스프린트 라벨인데
# 훅은 그것을 볼 수 없다 — 도구 호출마다 원장을 읽어야 하고 그 비용은 이 훅이 감당할
# 수 없다. 페이로드에서 확실히 얻는 것으로 정의하고 나머지는 한계로 남긴다.
#   한계 ①  session_id ↔ 스프린트·담당자 대응은 **미검증 가설**이다 (harness-dg0.3.1 note 9.6-7,
#            harness-dg0.6.17 이 처분 대상으로 등재). 여기서 그 가설에 기대지 않는다 —
#            회차는 세션이고 그 이상을 주장하지 않는다.
#   한계 ②  PreToolUse 페이로드에 session_id 가 없으면 그 열이 `-` 가 되고 계수는 회차
#            구분 없는 총계로 무너진다. **조용히 무너지지는 않는다** — 로그의 그 열이
#            전부 `-` 인 것으로 보인다.
#            **실린다는 것은 실측됐다** [2026-08-29, harness-qih]: 이 로그
#            (~/.claude/harness-guard-log.tsv) 3777줄의 2열이 `-` 1종 + UUID 6종이다.
#            남는 것은 부재의 가능성뿐이다 — 없으면 위와 같이 `-` 로 보인다.
#   한계 ③  회전은 오래된 회차의 계수를 **지운다**. 상한 안의 최근분만 기계값이다.
#
# 위치: `~/.claude/harness-guard-log.tsv`. 어느 레포도 어느 워크트리도 아니라 git·원장을
# 오염시키지 않으면서, 훅 사본이 워크트리마다 배포돼도 계수가 한 파일로 모인다.
# GUARD_ROOT 아래에 두면 워크트리 수만큼 쪼개진다.
# **클론 루트 옆(`~/.harness-workspace/guard-log.tsv`)에는 둘 수 없다** [실측 2026-08-27]:
# 이 훅 자신의 C3(r_main_shell)가 클론 루트 직속 경로를 명령 문자열에서 보면 차단하므로,
# 거기 두면 로그를 들여다보는 명령이 rc=2 로 막힌다 — 초판이 그 자리였고 실제로 막혔다.
# 계수 스크립트는 경로를 명령 문자열에 두지 않아 돌지만, 사람이 원본을 볼 수 없게 된다.
#
# 회전: 줄 수 상한 하나. **새 상태 파일을 만들지 않는다** — harness-dg0.3.1 note 9.3(2) 가
# 재주입 상한을 별도 상태 없이 로그 줄 수로 센 것과 같은 형태다. 넘으면 최근 절반만 남긴다.
GUARD_LOG="${HARNESS_GUARD_LOG:-$HOME/.claude/harness-guard-log.tsv}"
GUARD_LOG_MAX="${HARNESS_GUARD_LOG_MAX:-20000}"

# log_guard <발화한 규칙 이름 또는 -> [차단된 입력 — 차단일 때만]
# **로그 실패가 훅을 죽이면 안 된다** — 난간의 판정은 로그와 무관하다. 모든 실패 경로가
# return 0 이다(디스크·권한, 그리고 jq 없는 환경의 PATH 부재로 mkdir 조차 없는 경우까지).
log_guard() {
  # 디렉토리 생성은 없을 때만 — 이 함수는 도구 호출마다 돈다. 매번 mkdir 을 부르면
  # 아무 일도 하지 않는 포크가 호출마다 하나씩 는다. 경로 분리도 셸 확장으로 한다.
  local d="${GUARD_LOG%/*}"
  [ "$d" = "$GUARD_LOG" ] && d=.   # 슬래시 없는 값(상대 파일명)이면 현재 디렉토리
  [ -d "$d" ] || mkdir -p "$d" 2>/dev/null || return 0
  # 6열은 **차단일 때만** 붙는다. 통과 줄에도 달면 계수 명령(scripts/guard-log.sh)이 보는
  # 마지막 필드가 빈 문자열로 바뀌고, 로그 줄이 호출마다 길어진다 — 이 로그는 차단이 아니라
  # **통과가 압도적 다수**라 줄 길이가 거기서 정해진다. 열 수가 줄마다 다른 것은 의도이며,
  # 두 소비자 모두 위치로 읽는다($2·$5).
  local ev="${2-}"
  if [ -n "$ev" ]; then
    # 탭·개행은 열을 쪼갠다. 걷어내고 앞 120자만 남긴다 — 오탐 판정에 필요한 것은
    # 명령의 머리이지 전문이 아니고, 전문을 남기면 이 파일이 명령 사본이 된다.
    ev="$(printf '%s' "$ev" | tr '\n\t' '  ')"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$(date -u +%FT%TZ 2>/dev/null)" "${SESSION_ID:--}" "${AGENT_TYPE:--}" \
      "${TOOL_NAME:--}" "$1" "${ev:0:120}" >> "$GUARD_LOG" 2>/dev/null || return 0
  else
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$(date -u +%FT%TZ 2>/dev/null)" "${SESSION_ID:--}" "${AGENT_TYPE:--}" \
      "${TOOL_NAME:--}" "$1" >> "$GUARD_LOG" 2>/dev/null || return 0
  fi
  # **상한 1 이면 회전하지 않는다.** tail -n 0 이 로그를 통째로 비우고, 그 빈 로그는
  # 계수 명령에서 "훅이 한 번도 돌지 않았다"로 읽힌다 — 이 로그가 없애려는 바로 그
  # 혼동이 상한 값 하나로 되살아난다. 자르지 않고 두는 쪽이 거짓말하지 않는다.
  [ "$GUARD_LOG_MAX" -ge 2 ] 2>/dev/null || return 0
  local n
  n=$(wc -l < "$GUARD_LOG" 2>/dev/null) || return 0
  [ "${n:-0}" -gt "$GUARD_LOG_MAX" ] 2>/dev/null || return 0
  # 한계: 회전 중간 파일 이름이 고정이라 두 훅이 동시에 상한에 닿으면 서로 덮는다.
  # 상한 도달 시점에만 나는 경합이라 빈도가 낮아 그대로 둔다 — 잃는 것은 로그 줄이고
  # 난간 판정은 영향받지 않는다.
  tail -n "$((GUARD_LOG_MAX / 2))" "$GUARD_LOG" > "$GUARD_LOG.tmp" 2>/dev/null \
    && mv "$GUARD_LOG.tmp" "$GUARD_LOG" 2>/dev/null
  return 0
}

INPUT="$(cat)"

# jq 를 요구한다. 없으면 죽지 않고 통과시키되 조용히 넘어가지 않는다 —
# 난간이 꺼진 사실은 보여야 한다. (이 요구는 harness-uhy.3.5 note 에 명시)
if ! command -v jq >/dev/null 2>&1; then
  echo "harness guard: jq 없음 — 훅 입력을 해석할 수 없어 검사를 건너뛴다 (통과)." >&2
  log_guard SKIP-nojq
  GUARD_DONE=1; exit 0
fi
# 객체가 아니면(깨진 JSON·빈 stdin·배열) 건너뛴다. 종전의 `jq empty` 는 빈 입력을 유효로 봤다.
if ! printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
  echo "harness guard: 훅 입력이 JSON 객체가 아니다 — 검사를 건너뛴다 (통과)." >&2
  log_guard SKIP-badjson
  GUARD_DONE=1; exit 0
fi

# JSON 은 printf 로 먹인다 — echo 는 backslash 확장 셸에서 필드 안의 이스케이프를
# 망가뜨려 jq 를 rc=5 로 죽인다 (docs/development.md "셸 함정").
field() { printf '%s' "$INPUT" | jq -r "$1 // \"\"" 2>/dev/null; }

TOOL_NAME="$(field '.tool_name')"
AGENT_ID="$(field '.agent_id')"       # 서브에이전트 호출에만 채워진다
AGENT_TYPE="$(field '.agent_type')"   # 역할별 차등 규칙의 근거 (implementer 등)
# `.cwd` 는 **상대 경로의 기준**으로만 쓴다 — 앵커가 아니다. 워크트리 안에서 `echo x > ../../../f` 는
# 본 체크아웃 쓰기인데 경로 문자열만 보면 판정할 수 없었다. 키가 없으면 상대 경로는 종전대로
# 판정하지 않는다(한계). 명령 안의 `cd` 는 못 따라간다 — 서브에이전트는 호출마다 cd 한다(한계).
CWD="$(field '.cwd')"
SESSION_ID="$(field '.session_id')"   # 발화 로그의 회차 열. 판정에는 쓰지 않는다
COMMAND="$(field '.tool_input.command')"    # Bash
# 판정용 정규화 — 인용부호와 백슬래시를 걷어낸다. 셸은 `git pu\sh`·`git p""ush` 를 push 로
# 실행하는데 낱말 판정(has_token 의 -w)은 그 글자에 막혀 **미탐**이었다 [실측 2026-08-28,
# implementer: 둘 다 rc=0 — 리뷰 #6]. 리터럴 `\n`·`\t` 는 먼저
# 공백으로 되돌린다(걷어내면 `\n/path` 가 `n/path` 로 붙어 경로 추출이 어긋난다).
# 역따옴표는 남긴다(판정 재료로 쓰는 규칙은 지금 없다 — 걷어내면 뒤의 경로 추출이 어긋난다).
COMMAND="$(printf '%s' "$COMMAND" | sed -E -e 's/\\[nrt]/ /g' -e "s/[\\\\\"']//g")"
FILE_PATH="$(field '.tool_input.file_path')" # Write·Edit·Read 계열
NOTEBOOK_PATH="$(field '.tool_input.notebook_path')" # NotebookEdit 은 file_path 를 쓰지 않는다

# 차단. stderr 의 사유가 그대로 에이전트에게 보인다.
# **어느 규칙이 발화했는지는 여기서만 알 수 있다** — 차단 메시지에는 규칙 이름이 없고,
# 겹치는 판정 지점에서 메시지만으로는 귀속이 안 된다(harness-uhy.2.1 note 의 결론). 디스패처가
# CURRENT_RULE 에 지금 도는 규칙을 담아 두므로 그것을 그대로 로그에 남긴다.
# **차단된 입력도 함께 남긴다(6열).** 규칙 이름만으로는 그 발화가 정탐이었는지 오탐이었는지
# 사후에 가릴 수 없고, 이 난간은 오탐을 의도적으로 감수하는 설계라 그 대가의 크기를 재는
# 수단이 있어야 한다 — 없으면 "규칙을 유지할 값어치가 있는가" 가 영영 기억으로만 판정된다.
# 근거는 harness-guau.1.2.
deny() {
  # 명령이 없는 호출(경로만 받는 도구)은 그 경로가 판정 재료였다 — 같은 열에 넣는다.
  local ev="$COMMAND"
  [ -n "$ev" ] || ev="$FILE_PATH"
  [ -n "$ev" ] || ev="$NOTEBOOK_PATH"
  log_guard "${CURRENT_RULE:--}" "$ev"
  echo "GUARD-DENY: $*" >&2
  GUARD_DONE=1; exit 2
}

# 명령 문자열에 토큰이 단어 경계로 존재하는가 (극성 반전 — 위 주석 참조).
# 둘째 인자로 다른 건초더미를 줄 수 있다(기본값은 $COMMAND).
has_token() { printf '%s' "${2-$COMMAND}" | grep -Eqw -- "$1"; }

# ── 하위 명령 추출 ────────────────────────────────────────────────────
# `<도구> <전역옵션…> <하위명령>` 에서 하위 명령을 occurrence 마다 낸다. 값을 받는
# 전역 옵션은 **그 값도 함께** 건너뛴다 — 안 건너뛰면 값이 하위 명령으로 읽혀 진짜
# 하위 명령이 가려진다(미탐). `--opt=값` 은 아래 tr 이 `=` 를 남기므로 한 토큰이라
# 저절로 처리된다.
#
# **목록은 손으로 적되, 게이트가 `<도구> --help` 파생과 대조한다.** 훅에서 직접
# 파생하지 않는 이유는 비용이다 — 이 훅은 **모든 도구 호출마다** 도는데 훅 1회가
# 56ms 이고 `bd --help` 가 32ms, `git --help` 가 5ms 다 [실측 2026-08-22, 각 5회 평균].
# 대신 목록이 낡으면 checks/guard-check.sh 가 실패시킨다: 파생에 있는데 여기 없으면
# 그것이 곧 미탐이므로 **파생 ⊆ 목록**을 단언하고, 파생 집합이 비면(파싱이 깨졌다는
# 뜻이다) 그것도 실패로 읽는다. 새 옵션의 기본값은 "건너뛴다"여야 한다 — 목록에
# 없으면 값이 하위 명령으로 읽히는 쪽이 기본값이 되므로 극성이 뒤집힌다.
#
# 리다이렉션은 하위 명령이 아니다. `bd --help > /dev/null 2>&1` 의 `/dev/null` 이 하위 명령으로
# 읽히던 것이 harness-dj4 의 2번 형태다 [실측 2026-08-28 rc=2]. 아래 sed 가 fd 복제(`2>&1`·`>&2`)는
# 지우고, 대상을 받는 연산자(`>`·`>>`·`<`·`2>`·`&>`)는 표지 토큰 `__REDIR__` 로 바꿔 awk 가
# 표지와 그 대상을 함께 건너뛴다. **옵션만 있는 호출은 빈 줄을 낸다** — `bd --help`·`bd --version`·
# `gh --version` 은 도움말·버전 출력이라 규칙 셋(r_grader_shell·r_impl_bd·r_bd_root)과 r_remote 의
# gh 판정이 전부 읽기로 취급한다(harness-dj4 1·5번 · harness-fz1 의 `gh --version`).
BD_VALUE_OPTS="-C --directory --db --actor --dolt-auto-commit"
# 초과분 사유 — 아래 둘은 이 머신의 `git --help` usage 줄에 없지만 다른 버전에는 있다.
# 목록에 두는 것은 **과차단 방향**이라 미탐을 만들지 않으므로 남긴다.
GIT_VALUE_OPTS="-C -c --git-dir --work-tree --namespace --config-env --exec-path --super-prefix --attr-source"

subcmds_after() {  # subcmds_after <도구> <값-받는 옵션 목록> [건초더미 — 기본값은 $COMMAND]
  printf '%s' "${3-$COMMAND}" | sed -E 's/[0-9]*[<>]&[0-9]+//g; s/&?[0-9]*[<>]{1,2}/ __REDIR__ /g' \
    | tr -c 'A-Za-z0-9_.:/=-' '\n' \
    | awk -v tool="$1" -v vopts="$2" '
        $0 != "" { t[++n] = $0 }
        END {
          split(vopts, vo, " ")
          for (k in vo) val[vo[k]] = 1
          for (i = 1; i <= n; i++) {
            b = t[i]; sub(".*/", "", b)          # 절대 경로 호출(/opt/homebrew/bin/bd)도 그 도구다
            if (b != tool) continue
            j = i + 1
            while (j <= n && (substr(t[j], 1, 1) == "-" || t[j] == "__REDIR__")) {
              if (val[t[j]] || t[j] == "__REDIR__") j++   # 값-받는 옵션과 리다이렉션은 그 대상도 건너뛴다
              j++
            }
            print (j <= n ? t[j] : "")
          }
        }'
}

# ── 실행 위치 ───────────────────────────────────────────────────────
# 규칙은 낱말의 **존재**가 아니라 **실행되는 자리**를 본다. 명령 문자열을 조각으로 나누고
# (경계: `;` `&&` `||` `|` `(` `$(` 개행) 조각의 **첫 실행 낱말**을 그 조각이 실행하는 명령으로
# 읽는다. 앞에 붙는 것은 건너뛴다 — `VAR=값` · 옵션(`-x`) · 숫자(`timeout 5` 의 5) · 래퍼
# (timeout env nice sudo bash sh zsh — `bash -c "bd …"` 의 실행은 bd 다). 산문·경로·인용문
# 속 낱말은 조각의 첫 실행 낱말이 아니므로 판정에 들지 않는다 (`git log --grep push` ·
# 커밋 메시지 본문의 `bd create` · 파이썬 문자열 속 `git push`).
# 못 보는 것: 변수 치환(`B=bd; $B …`) · `eval` · 스크립트 파일 경유 — 종전과 같다.
# 첫 실행 낱말은 basename 으로 비교한다 — 경로 **끝**의 도구 이름은 인자 자리라 걸리지 않고
# (`chmod +x /tmp/x/gh` · `bash /tmp/gh-runner.sh`), `/opt/homebrew/bin/gh pr create` 는 걸린다.
EXEC_WRAPPERS="timeout env nice sudo bash sh zsh"
cmd_segments() { printf '%s\n' "${1-$COMMAND}" | sed -E 's/\|\||&&|[;|(]|\$\(/\n/g'; }
seg_exec_word() {  # seg_exec_word <조각> → 첫 실행 낱말 (없으면 빈 줄)
  printf '%s' "$1" | tr -c 'A-Za-z0-9_.:/=-' '\n' \
    | awk -v w="$EXEC_WRAPPERS" '
        BEGIN { split(w, a, " "); for (k in a) wrap[a[k]] = 1 }
        $0 == "" { next }
        wrap[$0] { next }
        /^-/ { next }
        /^[0-9]+[smhd]?$/ { next }
        /=/ { next }
        { sub(".*/", ""); print; exit }'
}
exec_segments() {  # exec_segments <명령이름> → 그 명령을 실행하는 조각들 (한 줄에 하나)
  local seg
  while IFS= read -r seg; do
    [ "$(seg_exec_word "$seg")" = "$1" ] && printf '%s\n' "$seg"
  done < <(cmd_segments)
  return 0
}
bd_exec_present() { [ -n "$(exec_segments bd)" ]; }
# 도구 이름을 변수에 담는 형태(`B=bd; $B …`)는 실행 위치에서 읽히지 않는다 — 대입문을 보고 막는다.
tool_aliased() { printf '%s' "$COMMAND" | grep -Eq "(^|[^A-Za-z0-9_])[A-Za-z_][A-Za-z0-9_]*=$1([^A-Za-z0-9_]|\$)"; }

# ── 세션→actor 매핑 관측 ─────────────────────────────────────────────
# **관측이지 판정이 아니다.** 여기서는 아무것도 막지 않는다 — 하는 일은 claim 명령이
# 지나갈 때 (session_id, actor) 쌍을 파일에 한 줄 적는 것뿐이고, 그 파일을 읽는 것은 정지
# 가드(hooks/stop-resume.sh)다. 그쪽 오라클이 원장 단위라 **자기가 잡지 않은**
# in_progress 로도 막히던 것을, 이 매핑이 세션 사거리로 좁힌다 (docs/guardrail-verification.md 8절).
#
# **파생이 아니라 관측인 이유.** actor 는 `sess-` + 무작위 6자라 session_id 에서 계산될 수
# 없고, 한 actor 가 세션을 넘어 재사용되는 것이 이어받기 규약이다
# (harness:develop 3절 0번). 파생은 그 규약을 깨지만, claim 이
# **일어나는 순간**을 적는 것은 깨지 않는다.
#
# 한계 ①  PreToolUse 는 명령 실행 **전**이라 claim 의 성공 여부를 모른다. 거부된 claim 도 그
#          세션 **자신의** actor 값이라 매핑을 오염시키지 않으므로 대응하지 않는다.
# 한계 ②  매핑 파일이 지워지면 정지 가드는 SCOPE_FAIL 을 남기고 종전(원장 전체) 동작으로
#          돌아간다 — 통과로 폴백하지 않는다. 잃는 것은 사거리이지 가드가 아니다.
# 회전은 두지 않는다 — 줄이 느는 것은 claim 마다 한 번이라 발화 로그와 자릿수가 다르다.
# 위치가 GUARD_LOG 과 같은 자리인 이유도 그쪽 주석과 같다(워크트리마다 배포돼도 한 파일).
SESSION_ACTOR_LOG="${HARNESS_SESSION_ACTOR_LOG:-$HOME/.claude/harness-session-actor.tsv}"

# **로그 실패가 훅을 죽이면 안 된다** — log_guard 와 같은 계약이다(모든 실패 경로가 return 0).
sa_observe() {
  [ "$TOOL_NAME" = "Bash" ] || return 0
  # 귀속할 수 없는 기록은 남기지 않는다 — session_id 없는 줄은 사거리를 좁히지 못하고,
  # 빈 열은 정지 가드 쪽에서 "이 세션의 actor" 로 잘못 읽힐 재료가 된다.
  [ -n "$SESSION_ID" ] || return 0
  local seg actor d
  # **bd 를 실행하는 조각만 본다.** 다른 명령이 인자로 --claim --actor 를 담은 경우
  # (grep · 설명 · 커밋 메시지)는 claim 이 아니다 — 실행 위치 판정을 그대로 쓴다.
  while IFS= read -r seg; do
    actor="$(printf '%s' "$seg" | tr -c 'A-Za-z0-9_.:/=-' '\n' | awk '
        $0 != "" { t[++n] = $0 }
        END {
          for (i = 1; i <= n; i++) if (t[i] == "--claim") c = 1
          if (!c) exit 1
          for (i = 1; i <= n; i++) {
            if (t[i] == "--actor" && i < n && substr(t[i+1], 1, 1) != "-") { print t[i+1]; exit 0 }
            if (index(t[i], "--actor=") == 1 && length(t[i]) > 8) { print substr(t[i], 9); exit 0 }
          }
          exit 1
        }')" || continue
    [ -n "$actor" ] || continue
    d="${SESSION_ACTOR_LOG%/*}"
    [ "$d" = "$SESSION_ACTOR_LOG" ] && d=.
    [ -d "$d" ] || mkdir -p "$d" 2>/dev/null || return 0
    printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ 2>/dev/null)" "$SESSION_ID" "$actor" \
      >> "$SESSION_ACTOR_LOG" 2>/dev/null || return 0
    return 0
  done < <(exec_segments bd)
  return 0
}
sa_observe || :   # SA_OBSERVE_CALL — 관측 호출. 실패해도 판정은 그대로 돈다

# ── 규칙 등록부 ───────────────────────────────────────────────────────
# 형식: "<도구이름 또는 *>:<함수이름>". 비어 있으면 아무것도 차단하지 않는다.
# **이 선언은 모든 `RULES+=` 보다 위에 있어야 한다.** 아래로 내려가면 이미 쌓인 등재를
# 전부 지우고, 규칙이 하나도 안 걸리는 훅이 rc=0 으로 조용히 통과한다. 이 줄은
# checks/guard-check.sh 의 mkhook 이 삽입 앵커(`^RULES=()$`)로도 쓰므로 단독 유지한다.
RULES=()

# ── 규칙 ─────────────────────────────────────────────────────────────

# ── C3 — 대상 레포 본 체크아웃 쓰기 차단 ──────────────────────────────
#
# 경계가 한 단계 차이다. 클론 루트 아래 `<레포>/` 는 전부 금지이고 예외가 딱 하나,
# `<레포>/.claude/worktrees/<스토리ID>/` 다. 워크트리가 본 체크아웃의 **하위 경로**라
# 접두 일치만 보면 워크트리까지 함께 막힌다 — 그것이 harness-uhy.1.1 note ④ 가 실측한 실패다.
# `permissions.deny` 로 부모를 막고 자식(워크트리)을 allow 하면 둘 다 막혔고
# (`main.txt: old  wt.txt: old`), 훅으로 바꾸니 의도대로 갈렸다
# (`main.txt: old  wt.txt: NEWWT`). **그래서 이 강제 지점은 반드시 훅이어야 한다.**
#
# 클론 루트는 GUARD_ROOT 가 아니다 (위 GUARD_ROOT 주석). scripts/repo.sh·
# scripts/workspace.sh 와 **같은 표현**을 쓴다 — 셋이 어긋나면 규칙이 조용히 빗나간다.
CLONE_ROOT="${HARNESS_CLONE_ROOT:-$HOME/.harness-workspace}"

# 경로를 **어휘적으로** 정규화한다. 파일시스템을 보지 않는다 — 아직 없는 파일도
# 판정해야 하고, 훅의 CWD 는 신뢰할 수 없다. `..` 를 접는 것이 핵심이다:
# `<워크트리>/../../../main.txt` 는 접두만 보면 워크트리 안이지만 실제로는 본 체크아웃이다.
# 상대 경로는 payload 의 cwd 를 기준으로 접는다 — cwd 가 없으면 판정하지 않고 1 을 낸다.
# 서브셸 함수인 이유: `set -f` 로 세그먼트 분리 중 glob 확장을 끄고, 그 설정이 훅의
# 나머지로 새지 않게 한다.
mc_norm() (
  set -f
  local p="$1" res="" seg
  # shellcheck disable=SC2088  # 확장이 아니라 **패턴 매칭**이다 — 에이전트가 보낸 경로 문자열이 `~/` 로 시작하는지 보고 여기서 직접 펼친다.
  case "$p" in "~/"*) p="$HOME/${p#\~/}" ;; esac
  case "$p" in /*) ;; *) [ -n "$CWD" ] || return 1; p="$CWD/$p" ;; esac
  IFS=/
  for seg in $p; do
    case "$seg" in
      ''|.) ;;
      ..)   res="${res%/*}" ;;
      *)    res="$res/$seg" ;;
    esac
  done
  printf '%s' "${res:-/}"
)

# 경로가 어느 레포의 본 체크아웃 안인가. 안이면 0 과 함께 MC_PATH(정규화 경로)·
# MC_REPO(레포 이름)·MC_SUB(레포 아래 상대 경로, 레포 루트면 빈 문자열)를 채운다.
# **워크트리 예외 판정은 여기서 하지 않는다** — 도구 경로 규칙과 셸 명령 규칙의 예외
# 폭이 다르기 때문이다(각 규칙 주석 참조). 두 판정을 한 함수에 섞으면 한쪽의 완화가
# 다른 쪽의 구멍이 된다.
MC_PATH=""; MC_REPO=""; MC_SUB=""
mc_locate() {
  local p root rest
  p="$(mc_norm "$1")" || return 1
  root="$(mc_norm "$CLONE_ROOT")" || return 1
  # 비교는 소문자로 접어서 한다 — macOS 기본 파일시스템은 대소문자를 구분하지 않아
  # `~/.Harness-Workspace/…` 가 같은 디렉토리인데 문자열 비교는 통과시켰다 [실측 2026-08-28,
  # implementer rm -rf 그 표기 → rc=0 — 리뷰 #8]. MC_PATH 등 밖으로 내는 값은 원래 표기다.
  # ponytail: 대소문자 구분 FS(Linux)에서는 다른 디렉토리를 같은 것으로 읽는 오탐 방향.
  local lp lr
  lp="$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')"
  lr="$(printf '%s' "$root" | tr '[:upper:]' '[:lower:]')"
  # 클론 루트 **자체**도 잡는다. 여기를 빼면 심각도가 뒤집힌다 — 레포 하나를 지우는
  # `rm -rf <루트>/<레포>` 는 막히는데 전부를 지우는 `rm -rf <루트>` 가 통과한다.
  # MC_REPO 를 비워 두어 호출부(mc_deny_root)가 "루트 자체"와 "루트 직속"을 가른다.
  case "$lp" in
    "$lr")    MC_PATH="$p"; MC_REPO=""; MC_SUB=""; return 0 ;;
    "$lr"/?*) ;;                                   # 우변 인용 — 루트를 glob 으로 읽지 않는다
    *) return 1 ;;
  esac
  rest="${p:$((${#root} + 1))}"
  MC_REPO="${rest%%/*}"
  [ -n "$MC_REPO" ] || return 1
  # 클론 루트 직속 파일(`<루트>/x.txt`)은 레포 체크아웃이 아니다.
  if [ "$MC_REPO" = "$rest" ]; then MC_SUB=""; else MC_SUB="${rest#*/}"; fi
  MC_PATH="$p"
  return 0
}

# MC_SUB 가 빈 경우 — 클론 루트 바로 아래의 한 칸. 레포 체크아웃 **루트 자체**이거나
# 그 옆에 놓인 파일이며, 경로 문자열만으로는 둘을 가를 수 없다(디렉토리 실재 여부를
# 보는 것은 아직 없는 파일 앞에서 무의미하다). 어느 쪽이든 금지 대상이라 판정은
# 같지만, "레포 <x.txt> 의 본 체크아웃" 같은 헛소리 메시지를 내지 않으려고 갈라 둔다.
mc_deny_root() {
  [ -n "$MC_SUB" ] && return 0
  [ -n "$MC_REPO" ] || deny "클론 루트 자체 금지 — $1 은 클론 루트($CLONE_ROOT) 그 자체다. 지우거나 옮기면 모든 레포의 클론·워크트리·미커밋 변경이 한 번에 사라진다 — 레포 하나를 겨냥한 조작보다 크다. 이 층은 scripts/repo.sh 가 소유한다."
  deny "클론 루트 직속 금지 — $1 은 클론 루트($CLONE_ROOT) 바로 아래다. 레포 체크아웃 루트이거나 그 옆의 파일이며, 이 층은 scripts/repo.sh 가 소유한다. 작업은 스토리 워크트리 안에서 한다: $CLONE_ROOT/<레포>/.claude/worktrees/<스토리ID>/ — 없으면 scripts/workspace.sh <스토리ID> 로 만든다."
}

# 이 호출이 **파일 쓰기**인가 — 아래 두 규칙(r_main_write·r_grader_write)의 공통 판정.
#
# 도구 **이름 목록**으로 판정하지 않는다. 이름 목록은 허용 목록 극성이라 목록에 없는
# 도구의 기본값이 "검사 안 됨"이 되고, 새 쓰기 도구(MultiEdit 복귀·플러그인·MCP)가 붙는
# 순간 난간이 **게이트 실패 없이 조용히 커버를 잃는다** (harness:develop 극성 반전,
# 실측 2026-08-22: MultiEdit 으로 본 체크아웃 쓰기가 rc=0 으로 통과했다).
#
# 그래서 극성을 뒤집는다: **대상 경로를 받는 도구는 전부 쓰기로 본다.** 읽기 전용임이
# 확인된 것만 아래 면제 목록에 이름으로 적으며, 새 도구의 기본값은 "검사됨"이다. 대가는
# 미지의 읽기 도구가 과차단될 수 있다는 것인데, 그 방향의 오류는 차단 메시지로 즉시
# 드러나고 반대 방향은 침묵한다. 드러나는 쪽을 고른다.
#
# 한계: 경로를 `file_path`·`notebook_path` 가 아닌 키로 받는 도구는 여전히 안 걸린다.
# 그것은 이름 목록이 아니라 **입력 스키마**의 문제라 여기서 풀 수 없다 — docs/guardrails.md
# "못 막는 것"에 등재돼 있고 guard-check 가 그 rc=0 을 한계로 못박는다.
w_readonly() { case "$TOOL_NAME" in Read|NotebookRead|Glob|Grep) return 0 ;; *) return 1 ;; esac; }
w_path() {
  w_readonly && return 0
  [ -n "$FILE_PATH" ] && { printf '%s' "$FILE_PATH"; return 0; }
  [ -n "$NOTEBOOK_PATH" ] && printf '%s' "$NOTEBOOK_PATH"
  return 0
}

# 쓰기 도구의 경로. 이 호출들은 **쓰기임이 확정**이라 예외를 최소로 둔다:
# 스토리 워크트리 **안**(`.claude/worktrees/<스토리ID>/<무언가>`)만 통과시키고,
# 워크트리 디렉토리 직속(`.claude/worktrees/x`)은 워크트리가 아니므로 막는다.
r_main_write() {
  local p
  p="$(w_path)"
  [ -n "$p" ] || return 0
  mc_locate "$p" || return 0
  case "$MC_SUB" in .claude/worktrees/*/*) return 0 ;; esac
  mc_deny_root "$p"
  deny "본 체크아웃 쓰기 금지 — $MC_PATH 는 대상 레포 '$MC_REPO' 의 본 체크아웃 안이다. 쓰기는 스토리 워크트리 안에서만 한다: $CLONE_ROOT/$MC_REPO/.claude/worktrees/<스토리ID>/ — 없으면 scripts/workspace.sh <스토리ID> 로 만든다."
}
# 매처가 `*` 인 이유는 위 w_path 주석에 있다 — 도구 이름을 여기 나열하면 그 목록이 곧
# 허용 목록이 되어, 나열되지 않은 쓰기 도구가 기본값 "검사 안 됨"으로 샌다.
RULES+=("*:r_main_write")

# 셸 경로(리다이렉션·`sed -i`·`tee`). 판정은 **명령 문자열 안에 본 체크아웃 경로가
# 존재하는가** 하나다 — 쓰기 명령의 형태를 열거하지 않는다(harness:develop 극성 반전,
# harness-uhy.1.1 note ② 의 3연속 누출). 대가로 **읽기 명령도 함께 막힌다**: 명령 문자열만 보고
# 읽기와 쓰기를 가를 방법이 없고, 가르려면 다시 형태 열거로 돌아가야 한다.
#
# 그래서 예외 폭이 위 도구 규칙보다 **넓다**. `.claude/worktrees` 아래면(스토리
# 디렉토리가 없어도) 통과시킨다 — 워크트리 목록 조회(`ls <클론>/.claude/worktrees/`)와
# 워크트리 안의 모든 명령이 그 자리다. 좁히면 `cd <워크트리> && git status` 가 막힌다.
# 그 대가로 `.claude/worktrees` 계층 **자체**에 대한 셸 조작이 전부 통과한다 — 직속 쓰기
# (`echo x > …/worktrees/f`)뿐 아니라 `rm -rf …/worktrees`·`mv …/worktrees/story-a` 까지다.
# 워크트리 삭제는 미커밋 변경에 복구 경로가 없으므로 이것은 무해해서가 아니라 **가를 수단이
# 없어서** 감수하는 것이다. 정리의 정규 경로는 scripts/workspace-cleanup.sh 다.
# harness-uhy.3.3 note "한계" 5번, 게이트 ⑨ 의 rc=0 단언 4건.
# **상대 경로**는 payload 의 cwd 로 접어 후보에 넣는다(`./`·`../` 로 시작하는 토큰) — 워크트리에서
# `echo x > ../../../f` 가 본 체크아웃 쓰기인 자리다. cwd 가 없으면 mc_norm 이 판정하지 않는다.
# 읽기 전용 명령만으로 된 명령은 본 체크아웃 경로가 있어도 통과한다. 조각(`;` `&&` `||` `|`)
# **전부**의 첫 실행 낱말이 아래 목록이거나 git 의 읽기 하위 명령이고, 어느 조각에도 파일
# 리다이렉션(`>` — `2>&1`·`>/dev/null` 은 제외)이 없을 때다. 하나라도 어긋나면 종전대로 막는다.
# find 는 면제하지 않는다 — -delete·-exec 가 쓰기다.
MC_READ_CMDS="ls cat head tail wc stat file grep diff du tree readlink realpath test [ cd pwd echo printf"
# **모든 형태가 읽기인 하위 명령만 든다.** `branch`(-D)·`tag`(-d)·`config`(값 쓰기)·
# `remote`(add·remove)·`stash`(bare 형태)는 읽기 형태가 있어도 쓰기 형태가 있어 뺀다 —
# 목록은 옵션을 보지 않으므로 등재하면 그 쓰기까지 함께 통과한다. 채점자 쪽 목록
# (GR_GIT_READ)이 `branch` 를 들고 있는 것과 갈리는 지점이고, 그쪽을 따라가지 않는다.
MC_GIT_READ="status log diff show ls-files rev-parse blame describe cat-file ls-remote grep for-each-ref merge-base ls-tree rev-list shortlog diff-tree name-rev check-ignore var count-objects whatchanged"
mc_all_readonly() {
  local seg w sub any=0
  while IFS= read -r seg; do
    [ -n "$(printf '%s' "$seg" | tr -d '[:space:]')" ] || continue
    any=1
    case "$(printf '%s' "$seg" | sed -E 's#[0-9]?>&[0-9]##g; s#[0-9]?>/dev/null##g')" in *'>'*) return 1 ;; esac
    w="$(seg_exec_word "$seg")"
    # 실행 낱말이 없는 조각은 **명령이 아니므로** 읽기·쓰기를 가를 대상이 아니다 —
    # 변수 대입만 있는 조각(`P=<경로>; …`)이 그렇다. 판정은 명령을 실행하는 조각이 든다.
    # 대입 접두형(`P=<경로> cat …`)과 같은 결론이 되는 것이 옳다 — 그쪽은 seg_exec_word 가
    # `=` 토큰을 건너뛰어 뒤의 `cat` 을 낸다. 쓰기는 그대로 막힌다: 그 조각의 실행 낱말은
    # 쓰기 명령이지 빈 문자열이 아니다 (게이트 ⑨ 의 MC_SH_READ_MIX 가 못박는다).
    [ -n "$w" ] || continue
    case " $MC_READ_CMDS " in *" $w "*) continue ;; esac
    if [ "$w" = "git" ]; then
      sub="$(subcmds_after git "$GIT_VALUE_OPTS" "$seg")"
      case " $MC_GIT_READ " in *" $sub "*) continue ;; esac
    fi
    return 1
  done < <(cmd_segments)
  [ "$any" -eq 1 ]
}

r_main_shell() {
  local cand cmd
  # `$HOME`·`${HOME}` 을 먼저 펼친다. mc_norm 은 `~/` 만 확장하는데 후보 추출 grep 은
  # `$HOME` 뒤의 슬래시부터 잡아 `/.harness-workspace/...` 라는 엉뚱한 절대 경로를
  # 만든다 — 그래서 틸드는 막히고 `$HOME` 은 새는 비대칭이 생겼다. 셸이 실제로 펼칠
  # 값을 훅도 같은 값으로 펼쳐야 판정이 명령의 의미를 따라간다.
  cmd="$COMMAND"
  cmd="${cmd//\$\{HOME\}/$HOME}"
  cmd="${cmd//\$HOME/$HOME}"
  while IFS= read -r cand; do
    [ -n "$cand" ] || continue
    mc_locate "$cand" || continue
    case "$MC_SUB" in .claude/worktrees|.claude/worktrees/*) continue ;; esac
    mc_all_readonly && return 0
    mc_deny_root "$cand"
    deny "본 체크아웃 경로 금지 — 명령에 $MC_PATH 가 들어 있다. 대상 레포 '$MC_REPO' 의 본 체크아웃은 직접 건드리지 않는다(읽기 전용 명령만으로 된 명령 — ls·cat·grep·git status 등 — 은 통과한다. 파일 리다이렉션이나 그 밖의 명령이 하나라도 섞이면 막힌다). 작업은 스토리 워크트리 안에서 한다: $CLONE_ROOT/$MC_REPO/.claude/worktrees/<스토리ID>/ — 없으면 scripts/workspace.sh <스토리ID> 로 만든다."
  done < <(printf '%s' "$cmd" | grep -oE "[~/][^[:space:]\"'\`;|&()<>]*"
           printf '%s' "$cmd" | grep -oE "(^|[[:space:]])\.\.?/[^[:space:]\"'\`;|&()<>]*" | sed 's/^[[:space:]]//')
}
RULES+=("Bash:r_main_shell")

# ── A3/C2 — 서브에이전트의 원격 반영·GitHub 조작 차단 ─────────────────
#
# 우회 시 빠지는 불변식: **원격 상태의 승인 경로**. push·PR·이슈는 성공하면 로컬에
# 흔적이 거의 남지 않고 원격만 조용히 바뀐다. 되돌리기 비용이 이 훅이 다루는 것 중
# 가장 크고, 되돌림 자체가 또 한 번의 원격 반영이라 승인 없이 시작할 수 없다.
# 근거 문서(전부 설득이고 강제는 없었다): agents/implementer.md:27(=A3) ·
# 세션 블록 "절대 금지"(=C2) · docs/operations.md:36 · docs/development.md "원격".
#
# **적용 대상은 서브에이전트 호출뿐이다.** 오케스트레이터는 사용자 지시를 받으면 실제로
# push·PR 을 해야 한다. 판정 근거는 r_bd_root 와 같은 `agent_id`·`agent_type` 의 존재이고
# 근거도 같다(harness-uhy.1.1 note (b) 실측). C2 는 문면상 오케스트레이터까지 덮지만 훅은 "사용자가
# 지시했는가"를 볼 수 없어 그 절반은 강제 대상이 아니다 — harness-uhy.3.4 note "무엇을 안 막나".
# 판정 두 줄이 r_bd_root 와 같지만 헬퍼로 빼지 않았다. 2번째 중복이고, 레포 규율은
# 3번째에만 추출하라고 한다 (CLAUDE.md P7 — 잘못된 추상화의 비용 > 중복의 비용).
#
# ① push — 판정은 **`push` 토큰의 존재 하나**다. 형태를 열거하지 않으므로 `git push`·
# `git -C <경로> push`·`timeout 5 git push`·`bd dolt push`·`dolt push` 가 한 자리에서
# 걸린다(harness-uhy.1.1 note ② 가 래퍼·옵션 위치로 3연속 샌 그 지점이다). 함께 걸리는 것은 세 갈래다 —
# (1) `push` 라는 **낱말**이 든 무해한 명령(`git log --grep push`), (2) `push` 를 하위 명령으로
# 쓰는 **실행형 로컬 명령**(`git stash push`), (3) `push` 를 하위 명령으로 쓰면서 **진짜로 원격에
# 반영하는** 명령(`git subtree push`). **대가(오탐)는 (1)(2) 뿐이고 (3) 은 차단이 옳은 정탐이다.**
# (2)(3) 은 (1) 과 달리 권할 명령이 있으므로(`git stash -m` · `git subtree split`) deny 메시지가
# 셋을 통째로 "고칠 명령이 없다"로 뭉뚱그리면 안 된다 (harness-uhy.3.4 note "오탐" 의 실행형 갈래).
#
# ② gh — 여기서는 토큰 하나로 부족하다. `gh` 존재만 보면 `gh pr view`·`gh pr list` 같은
# **읽기가 함께 막혀 정상 작업이 멈춘다**(리뷰어가 PR 을 못 읽는다). 그래서 극성 반전을
# 한 층 안으로 옮긴다 — gh 다음 **두 토큰**을 보고 **읽기 면제 목록에 없으면 전부 차단**.
# 하위 명령을 열거하지 않으므로 gh 에 새 명령이 생기면 기본값이 "차단됨"이다.
# 두 토큰을 보는 이유는 gh 의 구조가 `gh <그룹> <동사>` 이기 때문이다 — 읽기/쓰기는
# 동사(둘째)에서 갈리고(`gh pr view` vs `gh pr create`), 그룹 자체가 동사인 것도 있다
# (`gh browse`·`gh search`·`gh status`). 둘 중 하나가 면제어면 통과다.
# `gh api` 는 면제하지 않는다 — `-X POST` 를 이 층에서 읽기와 가를 수단이 없다.
# `download` 는 **받기만 하는 동사**라 면제다(2026-08-23, harness-u9n.3.2). 이 낱말이 첫·둘째
# 토큰에 오는 gh 명령은 셋뿐이고 — `gh release download`·`gh run download`·`gh attestation
# download` — 전부 원격에서 파일을 내려받기만 한다. 짝인 쓰기 동사(`gh release upload`·
# `create`)는 낱말이 달라 그대로 차단이다. 넣은 이유: 지금 릴리스 아티팩트를 받는 곳은
# `scripts/install.sh` 의 `check`(*.state)와 `update`(*.tar.gz) 두 줄이고(그 위의
# `gh release view` 는 종전부터 면제), 그 동작을 서브에이전트가 직접 확인할 수 없었다.
# 면제를 넣을 때는 `check` 하나가 근거였고 `update` 는 계획이었다 — harness-u9n.2.5 가
# 그 하위 명령을 만들면서 둘이 됐다 (2026-08-23).
GH_READ_EXEMPT="view list status diff checks browse search download"

# `gh` 가 **실행되는 조각**마다 선행 옵션을 건너뛴 뒤 두 토큰을 한 줄로 낸다. 판정 축이 실행
# 위치라 URL·경로·인용문 속 `gh`(`curl …/gh/…` · `chmod +x /tmp/x/gh` · `echo "gh pr create"`)는
# 조각의 첫 실행 낱말이 아니므로 여기 오지 않는다 — 종전의 URL 걷어내기(strip_urls, harness-bmu)는
# 그래서 없어졌다. 토큰이 모자라면 그 자리는 빈 문자열이다 (`gh pr` → "pr " · `gh --version` → " ").
# 둘째 토큰은 첫째를 도구 이름 삼아 같은 추출을 한 번 더 한 것이다(`gh pr view` → pr 뒤의 view).
gh_next_pairs() {
  local seg t1 t2
  while IFS= read -r seg; do
    t1="$(subcmds_after gh "" "$seg")"; t1="${t1%%$'\n'*}"
    t2=""; [ -n "$t1" ] && { t2="$(subcmds_after "$t1" "" "$seg")"; t2="${t2%%$'\n'*}"; }
    printf '%s %s\n' "$t1" "$t2"
  done < <(exec_segments gh)
}

gh_is_read() {
  [ -n "$1" ] || return 1
  case " $GH_READ_EXEMPT " in *" $1 "*) return 0 ;; esac
  return 1
}

r_remote() {
  # 오케스트레이터(부모 세션)는 판정 대상이 아니다.
  [ -n "$AGENT_ID" ] || [ -n "$AGENT_TYPE" ] || return 0

  tool_aliased git && deny "git 을 변수에 담아 부르는 형태('G=git; \$G …')는 하위 명령을 읽을 수 없어 차단한다 — git 을 직접 불러라. 원격 반영은 오케스트레이터·사람의 몫이다."
  local seg sub
  while IFS= read -r seg; do
    sub="$(subcmds_after git "$GIT_VALUE_OPTS" "$seg")"
    if [ "$sub" = "push" ] || { [ "$sub" = "subtree" ] && has_token 'push' "$seg"; }; then
      deny "원격 반영 금지 — git 이 push 를 실행한다. git push·bd dolt push 등 **원격 반영은 오케스트레이터·사람의 몫**이다(agents/implementer.md 의 금지 목록, 세션 블록 '원격 반영은 사용자 명시 지시 시에만'). **그 항목에는 예외가 둘 붙어 있지만 둘 다 오케스트레이터의 것이다** — harness:develop '사이클 종결' 이 '서브에이전트는 범위 밖이다 — 로컬 커밋까지' 로 경계를 못박는다. 네가 막힌 이유는 지시가 없어서가 아니라 **액터가 다르기 때문**이고, 그래서 '사용자가 지시했다'는 전언으로는 풀리지 않는다. 서브에이전트는 로컬 커밋까지만 하고 멈춘다 — 구현이 끝났으면 첫 줄에 'SIGNAL: IMPLEMENTATION_COMPLETE' 를 내고 커밋 해시를 보고하라. 원격 반영이 필요하면 그 사실을 보고에 적어 오케스트레이터가 사용자 승인을 받게 하라. 판정은 git·dolt·bd 가 실행하는 하위 명령이라 낱말 인용(git log --grep push)과 로컬 명령(git stash push)은 걸리지 않는다. git subtree push 는 진짜로 원격에 반영하므로 차단이 옳다 — 로컬까지만 하고('git subtree split --prefix <경로> -b <브랜치>') 멈춰 보고하라. 그래도 원격 반영이 아닌데 막혔으면 오탐이다 — 사람에게 확인받아라."
    fi
  done < <(exec_segments git)
  while IFS= read -r seg; do
    [ "$(subcmds_after dolt "" "$seg")" = "push" ] || continue
    deny "원격 반영 금지 — dolt 가 push 를 실행한다. 원장 반영(bd dolt push·dolt push)은 **오케스트레이터·사람의 몫**이다(세션 블록 '원격 반영은 사용자 명시 지시 시에만' — 그 항목의 예외 둘은 오케스트레이터의 것이고 harness:develop '사이클 종결' 이 '서브에이전트는 범위 밖이다 — 로컬 커밋까지' 로 경계를 못박는다). 서브에이전트는 'SIGNAL: IMPLEMENTATION_COMPLETE' 를 내고 멈춘다. 원격 반영이 아닌데 막혔으면 오탐이다 — 사람에게 확인받아라."
  done < <(exec_segments dolt)
  while IFS= read -r seg; do
    [ "$(subcmds_after bd "$BD_VALUE_OPTS" "$seg")" = "dolt" ] && has_token 'push' "$seg" || continue
    deny "원격 반영 금지 — bd dolt push 는 원장을 원격에 반영한다. 그것은 **오케스트레이터·사람의 몫**이다(agents/implementer.md 의 금지 목록, 세션 블록 '원격 반영은 사용자 명시 지시 시에만' — 그 항목의 예외 둘은 오케스트레이터의 것이고 harness:develop '사이클 종결' 이 '서브에이전트는 범위 밖이다 — 로컬 커밋까지' 로 경계를 못박는다). 서브에이전트는 'SIGNAL: IMPLEMENTATION_COMPLETE' 를 내고 멈춘다. 원격 반영이 아닌데 막혔으면 오탐이다 — 사람에게 확인받아라."
  done < <(exec_segments bd)

  tool_aliased gh && deny "gh 를 변수에 담아 부르는 형태('G=gh; \$G …')는 하위 명령을 읽을 수 없어 차단한다 — gh 를 'gh <그룹> <하위명령>' 형태로 직접 불러라. **PR 생성·머지와 이슈 조작은 오케스트레이터·사람의 몫**이고(세션 블록 '원격 반영은 사용자 명시 지시 시에만' — 그 항목의 예외 둘은 오케스트레이터의 것이고 harness:develop '사이클 종결' 이 '서브에이전트는 범위 밖이다 — 로컬 커밋까지' 로 경계를 못박는다), 서브에이전트는 구현 완료 신호를 내고 멈춘다."
  local t1 t2 shown
  while IFS=' ' read -r t1 t2; do
    [ -n "$t1" ] || continue     # 옵션만 있는 호출(gh --version · gh --help) — 읽기다
    gh_is_read "$t1" && continue
    gh_is_read "$t2" && continue
    shown="gh${t1:+ $t1}${t2:+ $t2}"
    deny "GitHub 조작 금지 — '$shown' 은 읽기 면제 목록에 없다. PR 생성·머지, 이슈 조작 등 **GitHub 반영은 오케스트레이터·사람의 몫**이다(agents/implementer.md 의 금지 목록, 세션 블록 '원격 반영은 사용자 명시 지시 시에만'). **그 항목의 예외 둘(사이클 종결의 작업 브랜치 push·PR 생성 포함)은 오케스트레이터의 것이다** — harness:develop '사이클 종결' 이 '서브에이전트는 범위 밖이다 — 로컬 커밋까지' 로 경계를 못박는다. 바뀐 것은 오케스트레이터가 **언제** 해도 되는가이지 **누가** 하는가가 아니다. 읽기는 면제다 — gh 다음 두 토큰 중 하나가 [$GH_READ_EXEMPT] 이면 통과한다(gh pr view · gh pr list · gh issue view · gh run view · gh auth status). 서브에이전트는 구현 완료 신호('SIGNAL: IMPLEMENTATION_COMPLETE')를 내고 멈춘다 — PR·이슈가 필요하면 무엇이 왜 필요한지 보고에 적어 오케스트레이터가 사용자 승인을 받게 하라."
  done < <(gh_next_pairs)
  return 0
}
# **등재 위치가 r_bd_root 보다 앞이다.** `bd dolt push` 는 두 규칙에 함께 걸리는데
# (`dolt` 는 bd 읽기 면제 목록에 없다), 그 명령의 진짜 문제는 -C 누락이 아니라 원격
# 반영이다. 중복 차단은 그대로 두고 **순서로 메시지를 고른다** — 겹침을 없애려고 한쪽을
# 좁히면 `bd -C <하네스루트> dolt push`(A4 는 통과시킨다)가 새거나 A4 가 `bd note` 를 놓친다.
# harness-uhy.3.4 note "r_bd_root 와의 겹침" · 게이트 ⑪ 의 메시지 단언 2건.
RULES+=("Bash:r_remote")

# ── A1/A2 — 채점자(reviewer·evaluator)의 쓰기 차단 ────────────────────
#
# 우회 시 빠지는 불변식: **채점과 답안의 분리**. reviewer·evaluator 가 파일을 고치면
# 그 수정이 곧 다음 판정의 대상이 되어, 만든 주체가 채점하지 않는다는 규율
# (harness:develop "운영 규율" 의 "만든 주체가 채점하지 않는다")이 조용히 무너진다. bd 쓰기도
# 같다 — 지적·판정의 기록은 오케스트레이터의 몫이고, 채점자가 원장을 직접 고치면
# 재시도 카운터와 close 근거가 채점자 자신의 손에 들어간다.
# 근거 문서(전부 설득이고 강제는 없었다): agents/reviewer.md(=후보 A1·A2) ·
# agents/evaluator.md(=후보 A1·A2).
#
# **적용 대상은 agent_type 이 harness:reviewer·harness:evaluator 인 호출뿐이다.** implementer 는 파일을
# 고치고 커밋하고 `bd note` 를 쓴다 — 막으면 구현이 통째로 멈춘다. 오케스트레이터도
# 아니다(원장 기록이 그 몫이다). 그래서 이 규칙의 판정은 앞선 두 규칙의
# `[ -n "$AGENT_ID" ] || [ -n "$AGENT_TYPE" ]`(= 서브에이전트인가)와 **다른 술어**다.
#
# P7 판단(중복 추출 시점): 그 두 줄짜리 판정은 r_bd_root·r_remote 두 곳에 있고
# harness-uhy.3.4 note 가 "3번째가 오면 헬퍼로 뺀다"고 적어 두었다. **이 규칙은 그 3번째가
# 아니다** — 조건이 "서브에이전트인가"가 아니라 "agent_type 이 특정 두 값인가"이고,
# reviewer·evaluator 는 정의상 agent_type 이 비지 않으므로 그 줄을 앞에 두면 죽은
# 코드가 된다. 그래서 중복 수는 여전히 2이고, 추출하지 않는다.
# (판정 술어가 다르므로 그대로 재사용할 수도 없다 — 재사용하면 implementer 까지 막힌다.)
#
# 차단 범위는 셋이다. ①도구 이름(Write·Edit·NotebookEdit) — 정확 일치라 오탐이 없다.
# ②`commit` 토큰 — 명령 문자열 판정이라 오탐이 있다(아래). ③bd 의 비-읽기 하위 명령.
#
# **③ 은 r_bd_root 와 겹친다.** 그쪽은 `-C` 누락만 막고 붙이면 통과시키는데, 채점자에게는
# **`-C` 를 붙여도 쓰기가 금지**다. r_remote 선례대로 **중복 차단을 두고 등재 순서로
# 메시지를 고른다** — 이 규칙을 r_bd_root **앞에** 둔다. 뒤에 두면 `bd note x`(무-C)로
# 막힌 채점자가 "-C 를 붙여라"는 메시지를 받고 `bd -C <하네스루트> note x` 로 고치는데
# 그것도 막히므로, 메시지가 에이전트를 한 번 더 헛걸음시킨다. 반대로 r_remote 보다는
# **뒤**다 — `bd dolt push` 의 진짜 문제는 bd 쓰기가 아니라 원격 반영이다.
# 읽기 면제 목록은 r_bd_root 의 BD_READ_EXEMPT 를 그대로 쓴다(같은 "bd 읽기" 개념이고,
# 목록을 둘로 두면 한쪽만 늘어났을 때 두 규칙의 판정이 어긋난다).
GR_ROLES="harness:reviewer harness:evaluator"

# 헬퍼 이름은 `gr_` 접두다. `r_` 를 쓰면 게이트 ⑦-역의 파생 집합(`^r_…()`)에 섞여
# "등재되지 않은 규칙"으로 오검출된다 (mc_·bd_·gh_ 선례와 같은 이유).
gr_is_grader() {
  [ -n "$AGENT_TYPE" ] || return 1
  case " $GR_ROLES " in *" $AGENT_TYPE "*) return 0 ;; esac
  return 1
}

# 차단 메시지 꼬리 — **그 역할이 무엇만 할 수 있는지**를 역할별로 적는다. 두 역할 정의가
# "검증용 명령 실행은 허용된다"를 명시하므로, 무엇이 막혔는지만 말하고 무엇이 열려
# 있는지를 말하지 않으면 받은 에이전트가 리뷰·판정 자체를 포기한다.
gr_can() {
  local common="검증용 명령 실행은 허용된다 — 게이트·테스트 재실행, git status·git diff·git show, bd -C <하네스루트> show·list 가 그것이다."
  case "$AGENT_TYPE" in
    harness:reviewer)
      printf '%s' "reviewer 가 할 수 있는 것: $common 지적은 파일이 아니라 응답에 쓴다 — 첫 줄 'SIGNAL: CHANGES_REQUESTED'(또는 LGTM) 뒤에 MUST FIX·NIT 를 파일:라인과 함께 적어라. 지적의 기록은 오케스트레이터가 남긴다 (agents/reviewer.md)." ;;
    harness:evaluator)
      printf '%s' "evaluator 가 할 수 있는 것: $common 판정은 파일이 아니라 응답에 쓴다 — 첫 줄 'SIGNAL: MATCH'·'VIOLATION'·'DEVIATION' 뒤에 acceptance 항목별로 인용→근거→MET/NOT_MET 을 적어라. bd close 와 판정의 기록은 오케스트레이터가 남긴다 (agents/evaluator.md)." ;;
  esac
}

# ① 파일 쓰기 판정. **경로를 보지 않으므로** 워크트리 안이든 밖이든 똑같이 막힌다.
# 경로로 완화하지 않는 이유: 채점 대상 트리를 경로로 특정할 수단이 훅 입력에 없고,
# 있다 해도 답안 사본을 다른 자리에 만들어 고치는 경로가 열린다.
# 판정을 도구 이름이 아니라 w_path 로 하는 이유는 그 함수의 주석에 있다 — 이름 목록은
# 허용 목록 극성이라 새 쓰기 도구가 기본값 "검사 안 됨"으로 샌다.
r_grader_write() {
  gr_is_grader || return 0
  [ -n "$(w_path)" ] || return 0
  deny "채점자의 파일 수정 금지 — $TOOL_NAME 도구는 agent_type=$AGENT_TYPE 에게 금지다(파일 수정·커밋 금지, 리뷰·평가만). 채점자가 고친 파일이 곧 다음 판정의 대상이 되어 만든 주체가 채점하는 상태가 된다. $(gr_can)"
}
RULES+=("*:r_grader_write")

# `bd` 뒤의 **하위 명령**을 occurrence 마다 낸다. 원장 지정 표기를 건너뛰고 그 다음을 본다 —
# 채점자에게는 `-C` 가 면죄부가 아니라서 `bd -C <하네스루트> note …` 의 하위 명령이 `note` 임을
# 읽어내야 한다. 옵션 토큰(`-` 로 시작)은 건너뛰고, 값을 받는 표기(-C·--directory·--db)는 그
# 값도 함께 건너뛴다. r_bd_root 도 같은 추출을 쓰되 원장 지정 표기가 하위 명령 **앞에** 있었는지를
# 따로 본다.
#
# **값-받는 옵션의 집합은 BD_VALUE_OPTS 가 든다** — `bd --help` 가 내는 실재 옵션(--actor 등)과
# 맞춰져 있고, 그 대조는 guard-check.sh ⑧-값옵션 절이 매번 한다(파생 ⊆ 훅 목록). 그래서
# `bd -C <H> --actor note create x` 는 하위 명령을 create 로 읽고 막는다 [실측 2026-08-28,
# implementer rc=2 — VO_DENY_LABEL 이 단언]. **목록에 없는 값-받는 옵션이 오면 그 값을 하위
# 명령으로 읽는다** — 값이 허용·면제 목록의 낱말이면 진짜 하위 명령을 못 보고 통과시키므로,
# 실패 방향이 항상 안전한 쪽이 아니다. 남는 구멍은 그 도구 버전의 --help 가 내지 않는 옵션뿐이다
# (⑧ 의 `git --unknown-value-opt` rc=0 고정). **이 주석을 근거로 허용 목록을 더 열지 마라** —
# 낱말을 올릴 때마다 그 구멍이 그만큼 넓어진다.
#
# **A4(r_bd_root)도 같은 구멍을 공유한다** — 같은 subcmds_after 로 하위 명령을 읽으므로 목록에
# 없는 값-받는 옵션의 값이 면제어면 세 규칙이 함께 속는다. `-C` 를 붙인 명령이 A4 단독에서 rc=0
# 인 것은 A4 가 `-C` 만 있으면 어떤 쓰기든 통과시키기 때문이다(harness-uhy.3.2 note 한계 3).
#
# 하위 명령이 없으면(옵션만 있는 호출) 빈 줄을 낸다 — 세 규칙 모두 읽기로 본다.
# 채점자에게 허용되는 git 하위 명령 — 읽기뿐이다. 목록 밖은 전부 차단(극성 반전).
# 한계: branch 는 면제어라 `git branch -D` 가 통과한다 — 채점자가 브랜치를 지울 유인이 없어 감수한다.
GR_GIT_READ="status log diff show ls-files rev-parse blame describe cat-file ls-remote branch grep"

# bd 가 실행 위치인 **조각마다 따로** 읽는다. 조각을 한 문자열로 이어 넘기면 옵션만 있는 조각
# (`bd --version`)의 하위 명령 자리에 다음 조각의 `bd` 가 들어와 'bd bd' 로 막힌다 [실측
# 2026-08-28 배치 reviewer: `bd --version; bd list --status in_progress …` 가 rc=2]. r_bd_root 는
# 자기 루프에서 같은 형태로 돈다. 게이트 ⑬-2 의 A/B(d) 가 이어 붙인 형태로 되돌려 귀속한다.
gr_bd_subcmds() {
  local seg
  while IFS= read -r seg; do subcmds_after bd "$BD_VALUE_OPTS" "$seg"; done < <(exec_segments bd)
}

# ②③ 셸 판정.
# ② `commit` — 판정은 토큰의 존재 하나다. 형태를 열거하지 않으므로 `git commit`·
# `git -C <경로> commit`·`timeout 5 git commit`·`git commit-tree` 가 한 자리에서 걸린다
# (harness-uhy.1.1 note ② 가 래퍼·옵션 위치로 3연속 샌 지점). 대가인 **오탐**의 갈래는 하나뿐이다 —
# **실행이 아닌 문자열**(`git log --grep commit`·`cat /tmp/commit-notes.md`). push 와 달리
# `commit` 을 하위 명령으로 쓰는 실행형 로컬 명령이 따로 없어 갈래를 셋으로 나눌 필요가 없다.
#
# **미탐은 그 옆에 따로 있고, 그것이 이 판정의 진짜 구멍이다.** `git revert`·`cherry-pick`·
# `merge --no-ff`·`am`·`rebase` 는 **커밋을 만드는데**(`git revert --help`: "record some new
# commits") 명령 문자열에 `commit` 토큰이 없어 통과한다 [실측 rc=0]. 즉 이 규칙이 선언한
# "채점자는 커밋을 만들지 않는다"가 토큰 판정만으로는 완결되지 않는다. 넓히려면 어떤 토큰
# 집합을 쓸지가 새 설계라 이 태스크의 acceptance 밖으로 두고, 사실을 harness-uhy.5.1 note 한계
# 2b 와 게이트 ⑫ 의 rc=0 고정으로 남긴다. **차단 메시지도 그 폭을 말해야 한다** — 막는 것이
# `commit` 토큰이 있는 형태뿐임을 적지 않으면 받은 에이전트가 "커밋 전반이 막혔다"로 읽는다.
r_grader_shell() {
  gr_is_grader || return 0

  tool_aliased git && deny "git 을 변수에 담아 부르는 형태('G=git; \$G …')는 하위 명령을 읽을 수 없어 차단한다 — git 을 직접 불러라. $(gr_can)"
  local seg gsub
  while IFS= read -r seg; do
    gsub="$(subcmds_after git "$GIT_VALUE_OPTS" "$seg")"
    if [ -n "$gsub" ]; then case " $GR_GIT_READ " in *" $gsub "*) continue ;; esac; fi
    deny "채점자의 git 쓰기 금지 — 'git ${gsub:-<하위 명령 없음>}' 은 읽기 면제 목록 밖이다. agent_type=$AGENT_TYPE 은 파일 수정·커밋이 금지다(리뷰·평가만) — 채점자가 만든 커밋이 곧 다음 판정의 대상이 된다. 판정은 git 이 실행하는 하위 명령이라 commit 뿐 아니라 revert·cherry-pick·merge·am·rebase·reset·clean·stash·checkout 도 막힌다. 읽기 면제: $GR_GIT_READ. 실행이 아닌 문자열(git log --grep commit)은 걸리지 않는다 — 그래도 막혔으면 오탐이니 사람에게 확인받아라. $(gr_can)"
  done < <(exec_segments git)

  tool_aliased bd && deny "bd 를 변수에 담아 부르는 형태('B=bd; \$B …')는 하위 명령을 읽을 수 없어 차단한다 — bd 를 'bd -C <하네스루트> <하위명령>' 형태로 직접 불러라. 채점자는 읽기만 가능하다. $(gr_can)"
  bd_exec_present || return 0
  local sub
  while IFS= read -r sub; do
    [ -n "$sub" ] || continue     # 옵션만 있는 호출(bd --help · bd --version) — 읽기다
    bd_is_read "$sub" && continue
    deny "채점자의 bd 쓰기 금지 — 'bd $sub' 는 읽기 면제 목록에 없다. agent_type=$AGENT_TYPE 의 bd 는 **읽기만**이고, **-C <하네스루트> 를 붙여도 쓰기는 금지**다 — 그 점이 r_bd_root 와 다르다(그쪽은 원장 지정만 요구한다). 읽기 면제: $BD_READ_EXEMPT. 원장 기록(note·update·close·label)은 오케스트레이터의 몫이다. $(gr_can)"
  done < <(gr_bd_subcmds)
  # bd 가 실행 위치인 조각마다 위 루프가 한 줄씩 받으므로 "bd 는 있는데 하위 명령을 하나도 못
  # 읽은" 자리는 없다 — 치환 우회는 위 tool_aliased 가, 경로·문자열 속 bd 는 exec_segments 가 가른다.
  return 0
}
# **등재 위치가 r_remote 뒤, r_bd_root 앞이다.** 위 "겹침" 주석 참조 —
# `bd dolt push` 는 원격 반영 메시지로, `bd note x`(무-C)는 채점자 메시지로 간다.
RULES+=("Bash:r_grader_shell")

# ── A5 — implementer 의 bd 쓰기 범위 제한 (note 하나만 허용) ──────────
#
# 우회 시 빠지는 불변식: **원장 구조는 오케스트레이터가 소유한다.** implementer 가
# create·update·label·close·dep 를 부르면 계층(스프린트→레일→스토리→마일스톤→태스크)·
# 의존성·상태·재시도 카운터가 구현자의 손에서 바뀐다. "계획을 바꾸지 않는다"
# (agents/implementer.md "역할")와 "evaluator 의 MATCH 기록 없이 태스크를 닫지 않는다"
# (harness:develop)가 함께 무너지는데, 실측상 그 실패는 조용하다 — r_bd_root 주석의
# 임시 원장 실측에서 create·remember·label 이 rc=0 으로 끝났다.
# `note` 만 예외인 이유는 절차 8 이 그것을 **요구**하기 때문이다(`알게 된 중요한 사실은
# bd note 로 남긴다`). 구현자가 원장에 쓸 수 있는 통로는 그 하나뿐이고, 그것까지 막으면
# 스토리의 학습이 응답 본문에만 남아 사라진다.
# 근거 문서(설득만 있고 강제는 없었다): agents/implementer.md(=후보 A5).
#
# **A1/A2(채점자)와 같은 판정 지점, 다른 허용 목록이다.** 채점자는 bd 쓰기가 **전부**
# 금지고 implementer 는 **note 만** 허용이다. 하위 명령을 뽑는 부분(gr_bd_subcmds)은
# 그대로 재사용하고 그 뒤의 판정만 갈린다 — 그것이 이 규칙과 A1/A2 의 유일한 차이다.
#
# **r_grader_shell 에 분기를 더하지 않고 규칙 함수를 따로 둔 이유.** 두 판정 술어
# (gr_is_grader / impl_is_implementer)는 서로소라 합쳐도 본문이 갈라질 뿐이고, 합치면
# 구조 단언이 이 규율을 놓친다: 게이트 ⑦-역은 소스에서 `^r_…()` 를 파생해 등재를
# 확인하므로 **규칙 함수 하나 = 규율 하나**일 때만 새 규율의 기본값이 "검사됨"이 된다.
# 합쳤다면 implementer 분기를 통째로 지워도 r_grader_shell 은 여전히 정의·등재돼 있어
# ⑦-역이 rc=0 으로 통과한다. 5.1 의 변조 (f)가 **FAILED 0 으로 통과**한 것도 같은 층의
# 사고였다 — 옆 규칙이 대신 답했는데 단언이 그것을 구별하지 못했다. 함수를 나누고
# 메시지에 역할 이름을 박아 "어느 규칙이 답했는가"를 단언 가능하게 만든다.
#
# **r_bd_root 와의 겹침: 이 규칙이 앞이다.** 그쪽은 `-C` 누락만 막고 붙이면 통과시키는데,
# implementer 에게는 **-C 를 붙여도 note 외의 쓰기가 금지**다. 순서를 뒤집으면 무-C
# `bd create x` 에 대해 r_bd_root 가 먼저 답해 "`bd -C <하네스루트> create …` 로 부르라"고
# **금지된 행동을 지시**한다. 받은 에이전트는 그대로 고쳐 다시 막히므로 헛걸음이 한 번
# 늘 뿐 아니라, 훅의 메시지가 역할 정의와 모순되는 것이 더 나쁘다. 이 규칙이 앞이면
# `bd create x` 는 "note 만 허용" 이라는 종착 메시지를 한 번에 받는다.
# 반대로 무-C `bd note x` 는 이 규칙이 **통과**시켜 r_bd_root 의 "-C 를 붙여라"로 가는데,
# 그것이 implementer 에게 옳은 지시다. 즉 앞에 두어도 A4 의 메시지가 죽지 않는다.
# r_remote 보다는 **뒤**다 — `bd dolt push` 의 진짜 문제는 bd 쓰기가 아니라 원격 반영이다.
#
# 읽기 면제 목록은 r_bd_root 의 BD_READ_EXEMPT 를 그대로 쓴다(A1/A2 와 같은 이유 —
# 목록을 둘로 두면 한쪽만 늘어났을 때 판정이 어긋난다).
IMPL_ROLES="harness:implementer"
# 쓰기 중 허용되는 하위 명령. **극성 반전이다** — 금지 계열을 열거하지 않으므로 bd 에 새
# 하위 명령이 생기면 기본값이 "차단됨"이다. 이 키가 실제 bd 하위 명령인지, 그리고 이
# 목록과 BD_READ_EXEMPT 를 뺀 나머지가 전부 막히는지는 게이트 ⑬ 이 `bd --help` 에서
# 파생한 집합으로 역방향 단언한다.
IMPL_BD_WRITE_ALLOW="note"

# 헬퍼 이름은 `impl_` 접두다. `r_` 를 쓰면 게이트 ⑦-역의 파생 집합(`^r_…()`)에 섞여
# "등재되지 않은 규칙"으로 오검출된다 (gr_·mc_·bd_·gh_ 선례와 같은 이유).
impl_is_implementer() {
  [ -n "$AGENT_TYPE" ] || return 1
  case " $IMPL_ROLES " in *" $AGENT_TYPE "*) return 0 ;; esac
  return 1
}

impl_bd_write_allowed() {
  case " $IMPL_BD_WRITE_ALLOW " in *" $1 "*) return 0 ;; esac
  return 1
}

r_impl_bd() {
  impl_is_implementer || return 0
  tool_aliased bd && deny "bd 를 변수에 담아 부르는 형태('B=bd; \$B …')는 하위 명령을 읽을 수 없어 차단한다 — bd 를 'bd -C <하네스루트> <하위명령>' 형태로 직접 불러라."
  bd_exec_present || return 0
  local sub
  while IFS= read -r sub; do
    # 옵션만 있는 호출(`bd --help`·`bd --version`·`bd -C <하네스루트>`)과 맨 `bd` 는 도움말·버전
    # 출력이라 읽기다 — harness-dj4 의 1·2·5번 형태가 여기서 막히던 것이다.
    [ -n "$sub" ] || continue
    bd_is_read "$sub" && continue
    impl_bd_write_allowed "$sub" && continue
    deny "implementer 의 bd 쓰기 금지 — 'bd $sub' 는 허용 목록 밖이다. agent_type=$AGENT_TYPE 에게 허용된 bd **쓰기**는 '$IMPL_BD_WRITE_ALLOW' 뿐이고, **-C <하네스루트> 를 붙여도 그 밖의 쓰기는 금지**다 — 그 점이 r_bd_root 와 다르다(그쪽은 원장 지정만 요구한다). 읽기 면제: $BD_READ_EXEMPT. 원장 구조(계층·의존성·상태·라벨)의 변경은 오케스트레이터의 몫이다 — 필요하면 무엇을 왜 바꿔야 하는지 **응답에** 적어 올려라(태스크 범위 밖이면 첫 줄 'SIGNAL: DECISION_NEEDED'). 알게 된 사실은 'bd -C <하네스루트> note <태스크ID> \"…\"' 로 남길 수 있다. note 와 같은 일을 하는 'bd update <id> --append-notes' 도 여기서 막히니 note 를 써라 (bd note --help: \"Shorthand for 'bd update <id> --append-notes'\"). (agents/implementer.md)"
  done < <(gr_bd_subcmds)
  # bd 가 실행 위치인 조각마다 위 루프가 한 줄씩 받으므로 "bd 는 있는데 하위 명령을 하나도 못
  # 읽은" 자리는 없다 — 치환 우회는 위 tool_aliased 가, 경로·문자열 속 bd 는 exec_segments 가 가른다.
  # 이 규칙이 통과시킨 것(읽기·note·옵션만 있는 호출) 중 -C 가 빠진 note 는 다음 등재인 r_bd_root 가 막는다.
  return 0
}
# **등재 위치가 r_grader_shell 뒤, r_bd_root 앞이다.** 위 "겹침" 주석 참조.
RULES+=("Bash:r_impl_bd")

# ── A4 — bd 쓰기의 하네스 루트 지정 누락 차단 ─────────────────────────
#
# 우회 시 빠지는 불변식: **업무 원장의 단일성**. `-C` 없는 bd 는 CWD 에서 `.beads` 를
# 탐색하므로, 워크트리 자신이나 그 부모(대상 레포)가 자체 `.beads` 를 가지면 그쪽에 붙는다.
# 이 워크트리에서 `bd where` 는 이미 하네스 루트가 아니라 워크트리의 .beads 를 낸다
# (실측 2026-08-21) — **탐색이 그쪽으로 간다**는 것까지가 이 관측이 보이는 전부다.
# 다른 원장에 실제로 **쓰였다**는 것은 아래 임시 원장 사본 실측이 보인 것이다.
#
# 조용한 실패가 이 규칙의 존재 이유다 (실측, 임시 원장 사본):
#   bd create "..."                → rc=0, 엉뚱한 원장에 이슈 생성 (아무도 모른다)
#   bd remember "..."              → rc=0, 엉뚱한 원장에 기억 저장
#   bd label add harness-uhy.3.2 x → rc=0, 오류 문구는 나오지만 **종료 코드가 0**
#   bd note/update/close <하네스ID> → rc=1, id 불일치로 시끄럽게 죽는다
# id 인자가 없는 명령(create·remember)과 label 이 특히 위험하다.
#
# **적용 대상은 서브에이전트 호출뿐이다.** 오케스트레이터 세션은 하네스 루트에서 열려
# 옵션 없는 bd 가 정상이고, 스킬 문서가 전부 그 형태로 쓰여 있다. 판정 근거로 훅 입력의
# `agent_id`·`agent_type` **존재**를 쓴다 — 스파이크가 실측한 성질이다: 부모의 Agent
# 도구 호출에는 둘 다 비어 있고 서브에이전트의 개별 호출에만 채워진다 (harness-uhy.1.1 note (b)).
# 둘 중 **하나라도** 있으면 서브에이전트로 본다. agent_type 은 값이라 유형 없는 위임에서
# 빌 수 있고, agent_id 는 호출마다 발급되는 식별자라 더 안정적이다.
#
# `cwd` 를 쓰지 않은 이유: (1) 서브에이전트 호출에서 그 필드가 세션의 프로젝트 디렉토리인지
# 위임된 워크트리인지 **실측된 바 없다**. 전자면 클론 루트 아래로 판정되는 입력이 하나도
# 없어 규칙이 통째로 꺼지는데 rc 는 0 이라 침묵으로 통과한다 — harness:develop 이 금지하는 형태다.
# (2) 명령 안의 `cd` 를 반영하지 못한다. agent_id 오판의 대가는 "-C 를 한 번 더 붙여라"
# 라는 오탐뿐이라 실패 방향이 안전한 쪽이다.
#
# 판정은 **`bd` 바로 다음 토큰**을 occurrence 마다 본다. 셋 중 하나여야 통과다:
# 원장 지정 표기(-C·--directory·--db) / 읽기 면제 목록 / 그 외는 전부 차단.
# 극성 반전이다 — 쓰기 계열을 열거하지 않으므로 bd 에 새 하위 명령이 생기면 기본값이
# "차단됨"이다. 면제 목록의 항목이 실제 bd 하위 명령인지는 게이트 ⑩ 이 `bd --help` 에서
# 파생한 집합으로 역방향 단언한다.
#
# 읽기를 면제한 근거: 잘못된 원장을 읽으면 대개 즉시 드러난다 (실측: 임시 원장에서
# `bd show harness-uhy.3.2` rc=1 "no issue found", `bd list` 는 하네스 이슈가 하나도 없는
# 목록). 쓰기와 달리 조용히 상태를 바꾸지 않는다. 다만 `bd ready` 는 rc=0 에 그 원장의
# 항목을 내므로 무해하지 않다 — 그래서 이것은 "안전해서"가 아니라 **작업을 멈추지 않으려고**
# 연 구멍이며, 목록을 늘리는 것은 그만큼 구멍을 넓히는 일이다.
BD_READ_EXEMPT="show list ready blocked children search query count graph history status prime where context info version help"

bd_is_read() {
  case " $BD_READ_EXEMPT " in *" $1 "*) return 0 ;; esac
  return 1
}

# 차단 메시지에 실을 하네스 루트 값. 훅은 자기 위치(플러그인)에서 아무것도 알 수 없으므로
# lib/harness-root.sh 를 **이 호출의 cwd** 에서 부른다 — 워크트리면 .beads/redirect 를 따라 원장을
# 찾고, 못 찾으면 값을 제시하지 않는다. 틀린 경로를 자신 있게 지시하는 것이 침묵보다 나쁘다.
# 차단 시점에만 도는 호출이라 도구 호출마다의 비용은 없다.
bd_root_hint() {
  local r
  # cwd 로 못 들어가도(합성 페이로드·사라진 디렉토리) 헬퍼는 돈다 — HARNESS_ROOT·.harness-root 파일은 cwd 와 무관하다.
  if r="$(cd "${CWD:-.}" 2>/dev/null; bash "$GUARD_ROOT/lib/harness-root.sh" 2>/dev/null)" && [ -n "$r" ]; then
    printf '%s' "이 호출의 cwd 에서 찾은 하네스 루트는 $r 다 — 위임 메시지가 다른 값을 주지 않았다면 그것이다."
  else
    printf '%s' "훅은 이 호출의 cwd 에서 하네스 루트를 찾지 못했다(lib/harness-root.sh). 위임 메시지가 준 하네스 루트 절대 경로를 쓰고, 받지 못했으면 멈추고 사람에게 물어라(DECISION_NEEDED)."
  fi
}

r_bd_root() {
  # 오케스트레이터(부모 세션)는 판정 대상이 아니다.
  [ -n "$AGENT_ID" ] || [ -n "$AGENT_TYPE" ] || return 0
  tool_aliased bd && deny "bd 를 변수에 담아 부르는 형태('B=bd; \$B …')는 하위 명령을 읽을 수 없어 차단한다 — bd 를 'bd -C <하네스루트> <하위명령>' 형태로 직접 불러라."
  bd_exec_present || return 0
  # 조각마다 하위 명령을 읽고(옵션은 건너뛴다 — `bd --json create x` 는 create 다), 원장 지정
  # 표기는 **하위 명령 앞**에서만 인정한다(`bd note x -C /h` 는 누락이다 — 게이트 BD_FALSEPOS).
  local seg sub
  while IFS= read -r seg; do
    sub="$(subcmds_after bd "$BD_VALUE_OPTS" "$seg")"
    [ -n "$sub" ] || continue     # 옵션만 있는 호출(bd --help · bd --version · bd -C <루트>) — 읽기다
    bd_is_read "$sub" && continue
    has_token '-C|--directory|--db' "${seg%%$sub*}" && continue
    deny "bd 원장 지정 누락 — 서브에이전트의 bd 쓰기는 'bd -C <하네스루트> $sub …' 로 부른다(--directory·--db 도 같은 자리에서 인정된다). -C 없이 부르면 워크트리의 부모 레포가 가진 .beads 에 붙어 **조용히 성공**한다(실측: create·remember·label 이 rc=0). 읽기($BD_READ_EXEMPT)는 면제다. $(bd_root_hint)"
  done < <(exec_segments bd)
  return 0
}
RULES+=("Bash:r_bd_root")

for rule in ${RULES[@]+"${RULES[@]}"}; do
  matcher="${rule%%:*}"; fn="${rule#*:}"
  CURRENT_RULE="$fn"   # deny 가 로그에 남길 발화 규칙 이름. 등록부 파손 차단도 이 이름으로 남는다
  # 등록부 키에 함수가 없으면 **차단한다.** 그냥 부르면 `command not found` 가 stderr 로
  # 나갈 뿐 종료 코드는 0 이라 PreToolUse 가 통과로 읽고, 규칙 하나가 아무 신호 없이
  # 꺼진다 (실측: RULES+=("Bash:r_pusk") → rc=0). 침묵을 통과로 읽는 이 형태를
  # harness:develop 의 극성 반전이 금지한다 — 면제 키의 역방향 단언에 해당한다.
  # 매처 대조보다 **먼저** 둔다: 이번 호출에 디스패치되지 않는 항목의 오타도 잡아야
  # 규칙이 영영 꺼진 채 남지 않는다.
  declare -F "$fn" >/dev/null || deny "규칙 등록부가 깨졌다 — '$rule' 이 가리키는 함수 $fn 이 없다"
  # 우변 인용 — 미인용이면 bash 가 glob 패턴으로 해석한다 (docs/development.md).
  [[ "$matcher" = "*" || "$matcher" = "$TOOL_NAME" ]] || continue
  "$fn"
done

# 통과도 남긴다. 이 줄이 없으면 무기록이 "훅 미실행" 과 구분되지 않는다 (위 발화 로그 주석).
log_guard -
GUARD_DONE=1; exit 0
