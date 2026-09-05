#!/bin/bash
# 게이트: 셸 스크립트의 정적 분석 (shellcheck).
#
# 왜: 이 플러그인은 셸이 본체다 — scripts·checks·hooks·lib 를 합치면 수천 줄인데, 커밋
# 게이트가 보던 것은 `bash -n`(문법)뿐이었다. docs/development.md "셸 함정" 에 실측으로
# 쌓인 세 항목 — 파이프 밖에서 종료 코드 채집 · `[[ ]]` 우변 glob · JSON 을 echo 로 먹이기
# — 은 전부 shellcheck 가 이름으로 부르는 부류다. 세 번 데고 규율로 적은 자리를 도구가
# 사전에 잡는다. 규율은 남는다 — 도구가 보는 것만 통과했다는 뜻이기 때문이다.
#
# 극성: 대상은 **실물 전수**에서 파생한다(SCAN 아래의 *.sh 전부). 검사에서 뺄 것만 사유와
# 함께 EXEMPT_FILE 에 등재하고, 면제 키가 실재하지 않으면 그 자체를 실패로 읽는다 —
# 사라진 파일의 면제는 검사를 조용히 지운다.
#
# fail-open 경계: **shellcheck 미설치는 통과시키되 통과 문구가 검사하지 못했음을 말한다.**
# 이 도구를 필수 의존으로 올리면 파생 하네스 전부가 설치해야 하는데, 그 부담이 이 검사가
# 잡는 것보다 크다. jq 와 다른 자리다 — 그쪽은 없으면 판정 자체가 불가능해서 필수다.
#
# set -e 를 쓰지 않는다 — 첫 실패에서 죽으면 나머지 파일의 위반이 보고되지 않는다.
set -uo pipefail

# 대상은 플러그인 트리 자신이다 — 하네스 루트는 필요 없고, lib/harness-root.sh 도 검사 대상에 든다.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$PLUGIN_ROOT" || { echo "✗ 플러그인 루트로 이동하지 못했다: $PLUGIN_ROOT" >&2; exit 1; }

[ $# -eq 0 ] || { echo "✗ 인자를 받지 않는다 (사용법: shell-lint.sh)" >&2; exit 1; }

# 검사 대상 트리. 이 플러그인이 소유한 셸이 사는 곳 전부다.
SCAN="scripts checks hooks lib"

# ── 파일 면제 ────────────────────────────────────────────────────────
# 형식: "<경로>|<사유>". 지금은 비어 있다 — 비어 있는 것이 정상이고, 채울 일이 생기면
# 사유를 함께 적는다. 아래 역방향 단언이 실재하지 않는 키를 실패로 읽는다.
EXEMPT_FILE=""

# ── 규칙 면제 ────────────────────────────────────────────────────────
# 형식: "<코드>|<사유>". **코드마다 사유를 적는다** — 사유 없는 면제는 다음 사람이
# 지울 수도 되살릴 수도 없다.
EXEMPT_RULE="
SC2317|이 레포의 검사 스크립트는 함수를 정의해 두고 step 에 이름으로 넘긴다 — shellcheck 는 그 호출을 보지 못해 도달 불가로 읽는다.
"

command -v shellcheck >/dev/null 2>&1 || {
  echo "⚠ 셸 정적 분석: shellcheck 가 없다 — **검사하지 못했다**. 설치하면 그때부터 판정한다 (brew install shellcheck)" >&2
  echo "✓ 셸 정적 분석 건너뜀 — shellcheck 미설치라 판정하지 않았다 (통과가 아니라 미판정이다)"
  exit 0
}

# 대상 전수. 이름을 손으로 적지 않는다.
FILES=$(find $SCAN -type f -name '*.sh' 2>/dev/null | sort)
[ -n "$FILES" ] || { echo "✗ 검사 대상이 0개다 — 빈 집합에 대한 검사는 통과가 아니라 검사 안 함이다 ($SCAN)"; exit 1; }

fail=0

# 역방향 단언 — 면제 키가 실재하는가. 사라진 파일의 면제는 아무것도 안 하면서 참이 된다.
exempt_paths=""
while IFS='|' read -r p why; do
  [ -n "${p:-}" ] || continue
  if [ ! -f "$p" ]; then
    echo "✗ 면제 목록의 '$p' 가 실재하지 않는다 — 실재하지 않는 키의 면제는 검사를 조용히 지운다"
    fail=1
    continue
  fi
  [ -n "${why:-}" ] || { echo "✗ 면제 '$p' 에 사유가 없다"; fail=1; }
  exempt_paths="$exempt_paths$p
"
done <<EOF
$EXEMPT_FILE
EOF

# 규칙 면제도 사유를 요구한다.
codes=""
while IFS='|' read -r c why; do
  [ -n "${c:-}" ] || continue
  case "$c" in SC[0-9]*) ;; *) echo "✗ 규칙 면제 '$c' 가 SC<번호> 형태가 아니다"; fail=1; continue ;; esac
  [ -n "${why:-}" ] || { echo "✗ 규칙 면제 '$c' 에 사유가 없다"; fail=1; }
  codes="${codes:+$codes,}$c"
done <<EOF
$EXEMPT_RULE
EOF

targets=""
n=0
for f in $FILES; do
  case "$exempt_paths" in *"$f"$'\n'*) continue ;; esac
  targets="$targets $f"
  n=$((n + 1))
done
[ "$n" -gt 0 ] || { echo "✗ 면제를 뺀 검사 대상이 0개다 — 면제가 집합을 통째로 지웠다"; exit 1; }

# rc 는 파이프 밖에서 채집한다 (docs/development.md "셸 함정").
# 기준선 셸을 인자로 못박는다 — 이 레포의 파일은 shebang 이 `env bash` 인 것과 `bash` 인
# 것이 섞여 있어 자동 판별에 맡기면 판정이 파일마다 갈린다.
# (주석 첫 낱말을 도구 이름으로 시작하지 않는다 — 그 형태는 지시어로 파싱된다: SC1073.)
OUT=$(shellcheck --shell=bash --severity=warning ${codes:+--exclude="$codes"} $targets 2>&1)
rc=$?

if [ "$rc" -ne 0 ]; then
  printf '%s\n' "$OUT"
  echo "✗ 셸 정적 분석 실패 — 위 지적을 고치거나, 고칠 수 없으면 사유와 함께 이 파일의 면제 목록에 등재하라 (대상 ${n}개)"
  fail=1
fi

[ "$fail" -eq 0 ] || exit 1
echo "✓ 셸 정적 분석 통과 — 대상 ${n}개 · severity=warning 이상 0건 (규칙 면제: ${codes:-없음})"
