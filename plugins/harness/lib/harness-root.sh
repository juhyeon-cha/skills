#!/usr/bin/env bash
# 하네스 루트 — ledger.json·repos.json·rails.json·sprints.json 이 사는 디렉토리 — 를 stdout 한 줄로
# 낸다. scripts·checks·hooks 가 전부 여기서 얻는다. 스크립트 자기 위치로 파생하지 않는다 — 이 파일은
# 플러그인 안에 있고 플러그인은 하네스 루트 밖에 산다. **bd 를 부르지 않는다** — github·notion
# 백엔드에는 bd 가 없다(스토리 harness-m8gg 열림 4 · T4.2).
#
# 찾는 순서:
#   1. HARNESS_ROOT 환경 변수 — 있으면 그것만 본다 (검사가 픽스처를 물리는 통로이고, 서브에이전트의
#      `HARNESS_ROOT=<루트> ledger.sh …` 형태가 이 자리다).
#   2. CWD 에서 위로 올라가며 처음 만나는 `.beads/redirect` — beads 백엔드의 워크트리 배선
#      (`ledger.sh wire-worktree` 가 쓴다). 내용은 `<루트>/.beads` 한 줄이라 그 부모가 루트다.
#      bd 자신도 이 파일을 상위로 올라가며 찾으므로 워크트리의 하위 디렉토리에서 불러도 같은 답이다.
#      github·notion 은 워크트리에 아무것도 두지 않는다 — 3 이 그 자리다.
#   3. ${HARNESS_CLONE_ROOT:-$HOME/.harness-workspace}/.harness-root 한 줄 파일 — 대상 레포 클론
#      루트에서 연 세션의 자리. 쓰는 것은 scripts/repo.sh, 여기서는 읽기만 한다.
#
# 판별자는 `<후보>/ledger.json` 의 존재다 — 백엔드를 정하는 파일이 곧 루트의 표지다(종전의
# `.beads/embeddeddolt` 는 beads 에만 있어 다른 백엔드의 루트를 못 알아봤다). 못 찾으면 rc=1 과
# stderr 한 줄. **조용히 CWD 로 폴백하지 않는다** — 엉뚱한 트리를 하네스 루트로 읽으면 등록부·원장을
# 그쪽에서 찾다 조용히 어긋난다.
set -u

is_root() { [ -n "$1" ] && [ -f "$1/ledger.json" ]; }

if [ -n "${HARNESS_ROOT:-}" ]; then
  if is_root "$HARNESS_ROOT"; then printf '%s\n' "$HARNESS_ROOT"; exit 0; fi
  echo "harness-root: HARNESS_ROOT='$HARNESS_ROOT' 는 하네스 루트가 아니다 (ledger.json 없음)" >&2
  exit 1
fi

d="$PWD"
while :; do
  if [ -r "$d/.beads/redirect" ]; then
    target="$(head -1 "$d/.beads/redirect")"
    cand="${target%/}"; cand="${cand%/.beads}"
    if is_root "$cand"; then printf '%s\n' "$cand"; exit 0; fi
    echo "harness-root: $d/.beads/redirect 가 가리키는 '$target' 의 루트 '$cand' 는 하네스 루트가 아니다 (ledger.json 없음)" >&2
    exit 1
  fi
  [ "$d" = "/" ] && break
  d="$(dirname "$d")"
done

f="${HARNESS_CLONE_ROOT:-$HOME/.harness-workspace}/.harness-root"
if [ -r "$f" ]; then
  cand="$(head -1 "$f")"
  if is_root "$cand"; then printf '%s\n' "$cand"; exit 0; fi
  echo "harness-root: $f 가 가리키는 '$cand' 는 하네스 루트가 아니다 (ledger.json 없음)" >&2
  exit 1
fi

echo "harness-root: 하네스 루트를 찾지 못했다 — CWD($PWD) 위로 .beads/redirect 가 없고 $f 도 없다 (판별자는 ledger.json). 스토리 워크트리 안에서 부르거나 HARNESS_ROOT 를 지정하라" >&2
exit 1
