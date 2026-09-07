#!/usr/bin/env bash
# 하네스 루트 — 원장 지정 파일 `ledger.json` 이 사는 디렉토리 — 를 stdout 한 줄로 낸다.
# scripts·checks·hooks 가 전부 여기서 얻는다. 스크립트 자기 위치로 파생하지 않는다 — 이 파일은
# 플러그인 안에 있고 플러그인은 하네스 루트 밖에 산다. **bd 를 부르지 않는다** — github·notion
# 백엔드에는 bd 가 없다(스토리 harness-m8gg 열림 4 · T4.2).
#
# 찾는 순서는 둘뿐이다:
#   1. HARNESS_ROOT 환경 변수 — 있으면 그것만 본다 (검사가 픽스처를 물리는 통로이고, 서브에이전트의
#      `HARNESS_ROOT=<루트> ledger.sh …` 형태가 이 자리다).
#   2. ${HARNESS_CLONE_ROOT:-$HOME/.harness-workspace} — **클론 루트 직속의 `ledger.json`.**
#      원장 지정은 머신의 사실(어느 원장에 붙어 일하는가)이지 어떤 트리의 내용이 아니다. 그래서
#      트리를 거슬러 올라가지 않고 머신에 하나뿐인 그 자리만 본다 — CWD 가 어디든 답이 같다.
#
# **CWD 를 거슬러 올라가지 않는다.** 종전에는 `.beads/redirect` 를 상위로 찾아 워크트리마다 다른
# 답이 나올 수 있었다. 그 배선은 이제 **beads 백엔드 안에서만 산다** — `ledger.sh wire-worktree`
# 가 쓰고 `bd` 자신이 읽는다(scripts/ledger-beads.sh). 루트 판별에는 쓰이지 않는다: 백엔드를
# 모르는 채로 백엔드 전용 파일을 판별자로 삼으면 github·notion 트리에서 답이 갈린다.
#
# 판별자는 `<후보>/ledger.json` 의 존재다. 못 찾으면 rc=1 과 stderr 한 줄. **조용히 CWD 로
# 폴백하지 않는다** — 엉뚱한 트리를 하네스 루트로 읽으면 등록부·원장을 그쪽에서 찾다 조용히 어긋난다.
set -u

is_root() { [ -n "$1" ] && [ -f "$1/ledger.json" ]; }

if [ -n "${HARNESS_ROOT:-}" ]; then
  if is_root "$HARNESS_ROOT"; then printf '%s\n' "$HARNESS_ROOT"; exit 0; fi
  echo "harness-root: HARNESS_ROOT='$HARNESS_ROOT' 는 하네스 루트가 아니다 (ledger.json 없음)" >&2
  exit 1
fi

cand="${HARNESS_CLONE_ROOT:-$HOME/.harness-workspace}"
if is_root "$cand"; then printf '%s\n' "$cand"; exit 0; fi

echo "harness-root: 하네스 루트를 찾지 못했다 — $cand/ledger.json 이 없다 (판별자는 ledger.json). 'repo.sh root --backend <백엔드> --owner <소유자>' 로 만들거나 HARNESS_ROOT 를 지정하라" >&2
exit 1
