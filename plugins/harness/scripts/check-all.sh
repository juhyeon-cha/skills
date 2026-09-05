#!/usr/bin/env bash
# 이 플러그인의 자기 게이트. 대상은 플러그인 트리 자신(scripts·checks·hooks·lib·hooks.json)이다.
#
# **극성 반전** (harness:develop "운영 규율" — 게이트는 예외 목록 방식으로 쓴다): 돌릴 검사를
# 손으로 고르지 않는다. `checks/*.sh` **실물 전수**에서 파생하고, 여기서 돌릴 수 없는 것만
# 사유와 함께 SKIP 에 등재한다. 새 검사의 기본값은 "돈다" 이고, 면제 키가 실재하지 않으면
# 그 자체를 실패로 읽는다.
#
# 검사를 이름으로 고르면 새로 만든 검사가 아무 데도 배선되지 않은 채 남는데, **배선되지 않은
# 검사는 없는 것과 같다** — 실패하고 있어도 아무도 모른다. 근거는 harness-guau.2.1.
#
# 하네스 루트: 이 게이트 자신은 필요 없지만 원장을 보는 검사(board-check · rules-check 의
# 원장 절 · workspace-check)는 lib/harness-root.sh 로 찾고 못 찾으면 rc≠0 이다 — 여기서 그
# 값을 먼저 찍어 실패의 원인이 코드인지 자리인지 읽는 사람이 가를 수 있게 한다.
#
# set -e 를 쓰지 않는다 — 첫 실패에서 죽으면 나머지 검사의 결과가 보고되지 않는다. 실패는
# 모아서 전부 보고하고 마지막에 비-0 으로 끝난다.
set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$PLUGIN_ROOT" || { echo "✗ 플러그인 루트로 이동하지 못했다: $PLUGIN_ROOT" >&2; exit 1; }

# ── 면제 ─────────────────────────────────────────────────────────────
# 형식: "<파일명>|<사유>". **사유 없는 면제는 등재로 치지 않는다.**
# 면제한 검사는 사라지지 않는다 — 부르는 자리가 여기가 아닐 뿐이고, 그 자리를 사유에 적는다.
SKIP="
guard-check.sh|이 게이트에 넣기엔 느리다 — 다른 검사 전부를 합친 것보다 오래 걸린다(재려면 직접 돌려라). 게이트 하나가 그만큼 붙으면 구현 사이클이 그 값을 태스크마다 치른다. hooks/guard.sh 를 고치는 커밋에서 손으로 돌린다.
transcript-check.sh|판정 대상이 트리 밖(~/.claude/projects 의 전사)이라 이 커밋과 무관하게 rc 가 흔들린다. 다른 세션이 남긴 위반으로 이 트리의 게이트가 깨지면 게이트가 거짓말을 한다. 부르는 자리는 harness:retrospective 1-2 다.
ledger-check.sh|원격·원장 상태에 의존한다. 부르는 자리는 사이클 종결 단계(harness:develop 사이클 종결)다 — 여기서 부르면 네트워크 실패를 커밋 게이트의 실패로 만든다.
"

fail=0
ran=0
skipped=0

# 대상 전수. 이름을 손으로 적지 않는다.
FILES=$(find checks -maxdepth 1 -type f -name '*.sh' 2>/dev/null | sort)
[ -n "$FILES" ] || { echo "✗ checks/*.sh 가 0개다 — 빈 집합에 대한 검사는 통과가 아니라 검사 안 함이다"; exit 1; }

# 역방향 단언 — 면제 키가 실재하는가. 사라진 파일의 면제는 아무것도 안 하면서 참이 된다.
skip_names=""
while IFS='|' read -r name why; do
  [ -n "${name:-}" ] || continue
  if [ ! -f "checks/$name" ]; then
    echo "✗ 면제 목록의 'checks/$name' 이 실재하지 않는다 — 실재하지 않는 키의 면제는 검사를 조용히 지운다"
    fail=1
    continue
  fi
  if [ -z "${why:-}" ]; then
    echo "✗ 면제 'checks/$name' 에 사유가 없다"
    fail=1
  fi
  skip_names="$skip_names$name
"
done <<EOF
$SKIP
EOF

echo "── 플러그인 트리 검사 ($PLUGIN_ROOT) ──"

# ⓪ 하네스 루트 — 원장 검사의 자리. 못 찾으면 **여기서 첫 실패**를 낸다 — 원장을 보는 검사가 아래에서
# 저마다의 문구로 죽기 전에, 원인(판별자 ledger.json 이 없는 자리)이 첫 줄에 오게 한다. 나머지 검사는
# 그래도 돌린다(set -e 를 쓰지 않는 이유와 같다 — 실패를 모아 전부 보고한다).
hroot_err=$(mktemp)
if hroot=$(bash lib/harness-root.sh 2>"$hroot_err"); then
  echo "  · 하네스 루트: $hroot"
else
  echo "✗ 하네스 루트를 찾지 못했다 — $(head -1 "$hroot_err") (스토리 워크트리 안에서 돌리거나 HARNESS_ROOT 를 지정하라; 원장을 보는 검사는 아래에서도 실패한다)"
  fail=1
fi
rm -f "$hroot_err"

# ① 문법 — shellcheck 가 없는 환경에서도 이것만은 돈다(shell-lint 는 그때 건너뛴다).
for f in scripts/*.sh checks/*.sh hooks/*.sh lib/*.sh; do
  bash -n "$f" || { echo "✗ 문법 오류: $f"; fail=1; }
done
echo "  ✓ 문법 (bash -n) — scripts·checks·hooks·lib"

# ② 플러그인 JSON 의 유효성 — 훅 배선과 매니페스트.
if jq empty hooks/hooks.json .claude-plugin/plugin.json 2>&1; then
  echo "  ✓ hooks/hooks.json · .claude-plugin/plugin.json 유효"
else
  echo "✗ hooks.json 또는 plugin.json 이 유효한 JSON 이 아니다"
  fail=1
fi

echo "── checks/*.sh 전수 ──"
for f in $FILES; do
  base="$(basename "$f")"
  case "$skip_names" in
    *"$base"$'\n'*)
      skipped=$((skipped + 1))
      echo "  · 면제: $base"
      continue
      ;;
  esac
  ran=$((ran + 1))
  if bash "$f"; then
    :
  else
    echo "✗ $base 실패 (rc=$?)"
    fail=1
  fi
done

[ "$ran" -gt 0 ] || { echo "✗ 실제로 돌린 검사가 0개다 — 면제가 집합을 통째로 지웠다"; exit 1; }

if [ "$fail" -ne 0 ]; then
  echo "✗ 게이트 실패 — 위 항목을 고쳐라 (돌린 검사 ${ran}개 · 면제 ${skipped}개)"
  exit 1
fi
echo "✓ 게이트 통과 — 돌린 검사 ${ran}개 · 면제 ${skipped}개 (면제 사유는 이 파일의 SKIP)"
