#!/bin/bash
# ralph 루프 취소 마커: 사람이 루프 밖에서 `touch <데이터 디렉토리>/ralph-cancel` 로 루프를 끊는다.
# 마커가 있으면 루프 상태 파일을 제거해 플러그인 stop-hook 이 종료를 허용하게 만든다.
#
# 마커는 프로젝트 디렉토리가 아니라 **하네스 데이터 디렉토리**에 둔다 (스토리 harness-lzs3 "결정됨" —
# 런타임 상태는 프로젝트 밖). 대상 레포 트리에 하네스 파일이 떨어지지 않는다.
# STATE 는 ralph-loop 플러그인의 내부 상태 파일이라 **프로젝트 디렉토리(payload 의 cwd) 안**이다 —
# 우리 소유가 아닌 계약이므로 플러그인 메이저 업데이트 시 이 경로가 여전히 맞는지 확인하라.
#
# ponytail: 플러그인 훅과의 실행 순서는 보장되지 않는다 — 플러그인 훅이 먼저 돌면
# 그 턴은 재주입되고 다음 턴 종료에서 풀린다(최대 한 반복 지연). 순서 보장이 필요해지면
# 플러그인 훅을 포크해 마커 검사를 내장하는 것이 업그레이드 경로.
set -uo pipefail

DATA="${HARNESS_DATA_DIR:-$HOME/.claude/plugins/data/harness}"
MARKER="$DATA/ralph-cancel"
[[ -f "$MARKER" ]] || exit 0

# 페이로드의 cwd 가 프로젝트 디렉토리다. jq 가 없거나 키가 없으면 CWD 로 짐작하지 않는다 —
# 마커를 남겨 두고 통과한다(다음 Stop 에서 다시 시도). 엉뚱한 트리의 파일을 지우는 것보다 낫다.
payload="$(cat)"
proj="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
if [[ -z "$proj" ]]; then
  echo "ralph 루프 취소: 페이로드에 cwd 가 없다 — 마커를 남기고 통과한다" >&2
  exit 0
fi
STATE="$proj/.claude/ralph-loop.local.md"

rm -f "$MARKER" "$STATE"
echo "🛑 ralph 루프: 취소 마커 감지 — 루프 상태 제거($STATE), 종료 허용"
exit 0
