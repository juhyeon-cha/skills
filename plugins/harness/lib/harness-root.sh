#!/usr/bin/env bash
# 하네스 루트 — 원장(.beads/embeddeddolt)·repos.json·rails.json·sprints.json 이 사는 디렉토리 — 를
# stdout 한 줄로 낸다. scripts·checks·hooks 가 전부 여기서 얻는다. 스크립트 자기 위치로 파생하지
# 않는다 — 이 파일은 플러그인 안에 있고 플러그인은 하네스 루트 밖에 산다.
#
# 찾는 순서 (스토리 harness-lzs3 열림 ① 의 답):
#   1. HARNESS_ROOT 환경 변수 — 있으면 그것만 본다 (검사가 픽스처를 물리는 통로).
#   2. `bd where` 의 database 줄 — 워크트리에서는 .beads/redirect 를 따라간 원장이고, 하네스 루트
#      자신에서는 그 자리의 원장이다. 원장 디렉토리(<루트>/.beads/embeddeddolt)의 두 단계 위가 루트다.
#      실측 2026-09-05 (bd 1.2.2): 워크트리(redirect 있음) → database: <루트>/.beads/embeddeddolt ·
#      하네스 레포 클론 루트(추적된 .beads 뼈대, dolt 없음) → 첫 줄만 있고 database 줄 없음 ·
#      원장이 없는 디렉토리 → rc=1.
#   3. ${HARNESS_CLONE_ROOT:-$HOME/.harness-workspace}/.harness-root 한 줄 파일 — redirect 가 없는
#      대상 레포 클론 루트에서 연 세션의 자리. 쓰는 것은 scripts/repo.sh (M4 4.4), 여기서는 읽기만 한다.
#
# 판별자는 `<후보>/.beads/embeddeddolt` 디렉토리의 존재다 — 스토리 description 의 결정. 못 찾으면
# rc=1 과 stderr 한 줄. **조용히 CWD 로 폴백하지 않는다** — 엉뚱한 트리를 하네스 루트로 읽으면
# 등록부·원장을 그쪽에서 찾다 조용히 어긋난다.
set -u

is_root() { [ -n "$1" ] && [ -d "$1/.beads/embeddeddolt" ]; }

if [ -n "${HARNESS_ROOT:-}" ]; then
  if is_root "$HARNESS_ROOT"; then printf '%s\n' "$HARNESS_ROOT"; exit 0; fi
  echo "harness-root: HARNESS_ROOT='$HARNESS_ROOT' 는 하네스 루트가 아니다 (.beads/embeddeddolt 없음)" >&2
  exit 1
fi

db="$(bd where 2>/dev/null | sed -n 's/^[[:space:]]*database:[[:space:]]*//p' | head -1)"
if [ -n "$db" ]; then
  cand="${db%/.beads/embeddeddolt}"
  if [ "$cand" != "$db" ] && is_root "$cand"; then printf '%s\n' "$cand"; exit 0; fi
fi

f="${HARNESS_CLONE_ROOT:-$HOME/.harness-workspace}/.harness-root"
if [ -r "$f" ]; then
  cand="$(head -1 "$f")"
  if is_root "$cand"; then printf '%s\n' "$cand"; exit 0; fi
  echo "harness-root: $f 가 가리키는 '$cand' 는 하네스 루트가 아니다 (.beads/embeddeddolt 없음)" >&2
  exit 1
fi

echo "harness-root: 하네스 루트를 찾지 못했다 — CWD($PWD)에서 bd where 가 원장을 내지 않고 $f 도 없다. 스토리 워크트리 안에서 부르거나 HARNESS_ROOT 를 지정하라" >&2
exit 1
