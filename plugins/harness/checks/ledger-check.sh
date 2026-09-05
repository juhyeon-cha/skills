#!/bin/bash
# 게이트: 원장의 상태가 원격과 어긋난 채로 push 되는 것을 막는다.
#
# 판정은 어댑터의 몫이다 — `ledger.sh sync-check [--push]`. 백엔드가 무엇을 보는지는 그쪽이 든다:
#   beads   Dolt 원장이 원격보다 앞서 있는가(scripts/ledger-beads.sh sync-check — 탐색·계보·ahead·
#           자동 반영의 판정과 문구가 전부 거기 있다)
#   github  이슈가 원격 자체라 반영할 것이 없다 → "원격 반영 대상 없음" rc 0
#   notion  같다
#
# **쓰기 모드: LEDGER_CHECK_PUSH=1. 기본값은 반영하지 않는 것이다.** 이 변수가 있을 때만 어댑터에
# --push 를 넘긴다. 켜는 자리는 하네스 루트의 `pre-push` 훅 블록 하나이며 그 자리가 CLAUDE.md 예외
# 하나가 미리 승인한 자리다 — 손으로 치는 `git push` 가 곧 그 승인이다. 스위치를 빠뜨린 호출이
# 승인 밖의 원격 반영이 되면 안 된다 — 안전한 쪽이 기본값이다(harness-x0i.2.1).
# 켜지 않고 돌렸는데 원장이 앞서 있으면 통과 문구가 "앞서 있음(반영하지 않음 — 쓰기 모드 아님)" 이다 —
# `확인됨` 과 글자로 갈린다. 침묵시키는 것이 아니라 말만 하는 모드다.
#
# 인자로 하네스 루트를 받는다. 생략하면 lib/harness-root.sh 가 내는 하네스 루트다(운영 경로 —
# 못 찾으면 rc=1 로 멈춘다). 인자를 받는 이유는 자기 검사(checks/guardrail-check.sh S6)가 합성
# 픽스처를 물려 실패 경로와 fail-open 경로를 실제로 밟아 보기 위함이다.
set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ROOT="${1:-$(bash "$PLUGIN_ROOT/lib/harness-root.sh")}" || exit 1

if [ -n "${LEDGER_CHECK_PUSH:-}" ]; then
  exec env HARNESS_ROOT="$ROOT" bash "$PLUGIN_ROOT/scripts/ledger.sh" sync-check --push
fi
exec env HARNESS_ROOT="$ROOT" bash "$PLUGIN_ROOT/scripts/ledger.sh" sync-check
