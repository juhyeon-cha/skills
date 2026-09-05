#!/usr/bin/env bash
# guard.sh 발화 로그의 회차별 계수. 규칙이 실제로 몇 번 발화했는지를 기계값으로 낸다.
#
# 왜: 신규 게이트의 값어치를 판정하려면 "그 규칙이 최근 회차에서 발화한 적이 있는가" 가
# 기계값이어야 한다. 지금까지 그 수는 사람의 세션 기억뿐이었다
# (harness-pl7 S16).
#
# 출력: TSV 세 열 — <회차(session_id)> <규칙 또는 -> <횟수>. 정렬은 사전순.
#   r_worktree 처럼 규칙 이름이 든 행  = 그 규칙이 그 회차에서 그만큼 발화(차단)했다
#   `-` 행                              = 훅이 돌았고 아무 규칙도 발화하지 않은 호출 수
#   SKIP-nojq · SKIP-badjson 행         = 훅이 돌았지만 검사를 건너뛴 호출 수
#
# **발화 0 과 훅 미실행의 구분이 이 명령의 요점이다.** 그리고 부재에는 원인이 둘이다 —
# 그 둘이 같은 문구로 나오면 계수가 그 자리에서 거짓 근거가 된다 (harness-dg0.6.33).
#   발화 0        그 회차의 행이 있고 규칙 열이 `-` 뿐이다 (훅은 돌았다)
#   훅 미실행     rc=1. 로그가 없고, **배선된 guard.sh 에는 로깅 호출이 있다** —
#                 그러니 비어 있다는 것은 훅이 안 돌았다는 뜻이다
#   로깅 없는 판  rc=3. 로그가 없는데 **배선된 guard.sh 에 로깅 호출이 없다.** 훅은
#                 돌아도 아무것도 안 남는다. 이 상태의 빈 로그는 미실행도 발화 0 도
#                 아니다 — 전역 원장과 달리 **훅 코드는 트리 안에 있어 브랜치를 탄다**
#
# 어느 guard.sh 를 보는가: hooks.json 이 `${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh` 를 부르므로
# (그 배선은 checks/guardrail-check.sh S2 가 단언한다) 같은 변수로 정한다. 변수가 없으면 이
# 스크립트 자신의 플러그인 트리로 떨어지는데 **그 트리가 세션이 배선한 트리와 다를 수 있다**
# — 그래서 검사한 훅 경로를 문구에 함께 낸다. 하네스 루트는 필요 없다 — 로그도 훅도 하네스 루트
# 밖($HOME·플러그인)에 있어 lib/harness-root.sh 를 부르지 않는다. 계수를 근거로
# 쓸 수 있는 조건과 이 셋의 천장은 docs/guardrail-verification.md 11절이 든다.
#
# 나머지 한계는 guard.sh 의 "발화 로그" 주석이 든다 (회차 정의·session_id 부재·회전 소실).
set -uo pipefail

# 기본 경로는 guard.sh 의 GUARD_LOG 와 **같은 표현이어야 한다** — 갈라지면 이 명령이 빈
# 로그를 보고 "훅 미실행" 이라고 거짓말한다. checks/guard-check.sh ⑮ 가 두 파일에서
# 기본값을 각각 파생해 대조한다 (한쪽만 고치면 게이트가 비-0).
LOG="${HARNESS_GUARD_LOG:-$HOME/.claude/harness-guard-log.tsv}"

if [ ! -s "${LOG}" ]; then
  HOOK="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/hooks/guard.sh"
  WHY="검사한 훅에는 로깅 호출이 있다"
  # 아래 if…fi 가 두 부재를 가르는 로직이다. 통째로 빼면 두 상태가 같은 문구로 돌아간다 —
  # checks/guard-check.sh ⑰ 이 이 범위만 지운 사본으로 그 귀속을 든다.
  if [ ! -r "${HOOK}" ]; then
    WHY="훅 파일을 읽지 못해 로깅 유무를 확인하지 못했다"
  elif ! grep -q '^[[:space:]]*log_guard ' "${HOOK}"; then
    printf '%s\n' "로깅 없는 guard.sh 가 발화 중이다 — 훅은 돌아도 로그를 남기지 않는다. 이 빈 로그는 '훅 미실행' 도 '발화 0' 도 아니다. 훅=${HOOK} 로그=${LOG}" >&2
    exit 3
  fi
  printf '%s\n' "발화 로그가 없거나 비었다 — 훅이 한 번도 돌지 않았다는 뜻이지 '발화 0' 이 아니다 (${WHY}: ${HOOK}): ${LOG}" >&2
  exit 1
fi

awk -F'\t' '{ c[$2 "\t" $5]++ } END { for (k in c) print k "\t" c[k] }' "${LOG}" | sort
