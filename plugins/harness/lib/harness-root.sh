#!/usr/bin/env bash
# 하네스 루트 — 대상 레포의 설정 파일 `.harness.json` 이 사는 디렉토리 — 를 stdout 한 줄로 낸다.
# scripts·checks·hooks 가 전부 여기서 얻는다. 스크립트 자기 위치로 파생하지 않는다 — 이 파일은
# 플러그인 안에 있고 플러그인은 하네스 루트 밖에 산다. **bd 를 부르지 않는다** — github·notion
# 백엔드에는 bd 가 없다.
#
# 찾는 순서는 둘뿐이다:
#   1. HARNESS_ROOT 환경 변수 — 있으면 그것만 본다 (검사가 픽스처를 물리는 통로이고, 서브에이전트의
#      `HARNESS_ROOT=<루트> ledger.sh …` 형태가 이 자리다).
#   2. CWD 에서 위로 거슬러 올라가며 처음 만나는 `.harness.json` 의 디렉토리.
#
# 판별자는 `<후보>/.harness.json` 의 존재다. 그 파일은 **대상 레포 자신이 소유하고 커밋한다** —
# 게이트 명령·기본 브랜치·부트스트랩과 원장 좌표가 거기 함께 산다. 그래서 레포를 클론하는 것만으로
# 하네스가 붙고, 클론을 어디에 두든 답이 같다.
#
# 워크트리(`<레포>/.claude/worktrees/<이름>/`)도 자기 체크아웃에 `.harness.json` 을 갖는다 —
# 거슬러 올라가면 워크트리 자신이 답이고, 원장 좌표는 본 체크아웃과 같은 값이다.
#
# 못 찾으면 rc=1 과 stderr 한 줄. **조용히 CWD 로 폴백하지 않는다** — 엉뚱한 트리를 하네스 루트로
# 읽으면 원장을 그쪽에서 찾다 조용히 어긋난다.
set -u

is_root() { [ -n "$1" ] && [ -f "$1/.harness.json" ]; }

if [ -n "${HARNESS_ROOT:-}" ]; then
  if is_root "$HARNESS_ROOT"; then printf '%s\n' "$HARNESS_ROOT"; exit 0; fi
  echo "harness-root: HARNESS_ROOT='$HARNESS_ROOT' 는 하네스 루트가 아니다 (.harness.json 없음)" >&2
  exit 1
fi

dir="$(pwd -P 2>/dev/null)" || dir=""
while [ -n "$dir" ]; do
  if is_root "$dir"; then printf '%s\n' "$dir"; exit 0; fi
  [ "$dir" = / ] && break
  dir="$(dirname "$dir")"
done

echo "harness-root: 하네스 루트를 찾지 못했다 — $(pwd) 에서 위로 .harness.json 이 없다 (판별자는 .harness.json). 대상 레포 안에서 부르거나 HARNESS_ROOT 를 지정하라" >&2
exit 1
