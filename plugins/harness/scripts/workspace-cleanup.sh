#!/usr/bin/env bash
# 스토리 워크트리 정리기 — scripts/workspace.sh 의 대칭.
# 사용법: scripts/workspace-cleanup.sh <story-id> [--force]
#
# 생성이 불변식(브랜치 story/<ID>·기준 origin 최신·exclude 등재·부트스트랩 마커)을
# 소유하듯, 정리도 불변식을 소유한다. develop 스킬 4-4 가 손절차로 적어 두었던 것을
# 이 스크립트가 가져온다:
#   ① 원격 참조 갱신 (fetch --prune)  ② 미커밋·미푸시 검사(있으면 중단)
#   ③ 워크트리 제거 → 로컬 스토리 브랜치 삭제 → 부트스트랩 마커 삭제
# 4-4 는 fetch --prune 을 마지막에 뒀지만 여기서는 **맨 앞**이다 — 미푸시 판정이
# origin 참조에 기대므로, 낡은 참조로 판정하면 검사 자체가 거짓이 된다.
#
# **클론 자체는 지우지 않는다.** 등록 해제는 scripts/repo.sh remove 의 몫이다.
#
# stdout: "<레포이름>\t<제거한 워크트리 절대경로>" 줄 목록 (workspace.sh 와 같은 계약
#   채널). 진단은 전부 stderr. 제거를 거부한 레포는 stdout 에 나오지 않으며, **아무것도
#   제거하지 않은 레포도 나오지 않는다** — 이미 정리된 상태로 다시 불린 경우가 그것이다.
#   반대로 브랜치 삭제만 실패한 레포는 워크트리를 이미 지웠으므로 rc 가 비-0 이어도
#   그 줄이 나온다 (반쯤 정리된 것과 손도 안 댄 것을 호출자가 구분할 수 있어야 한다).
#   제거 직전에는 무시된 파일(.gitignore 등재분) 요약을 stderr 로 흘린다 — 막지는 않지만
#   무엇이 함께 사라지는지는 드러난다.
# 일부 레포가 실패해도 나머지는 정리하고, 실패 사실을 남긴 뒤 비-0으로 끝난다.
#
# --force: **미푸시 검사만** 무시한다. 스쿼시 머지 후 GitHub 이 원격 브랜치를 지우면
#   로컬 커밋이 어느 origin 참조에서도 안 보여 영구히 막히는데, 그 막힘의 실제 대안이
#   `rm -rf <클론>/.claude/worktrees/...`(훅이 못 막고 복구 경로도 없는 조작,
#   harness-uhy.3.3 note 한계 5)라서 탈출구를 둔다.
#   **미커밋 변경은 --force 로도 지우지 않는다** — 유일하게 복구 경로가 없는 상태다.
#
# 머지 확인(develop 4-4 ①)은 이 스크립트가 하지 않는다. gh 를 부르지 않으며, 그 이유는
# 셋이다: (1) 외부 API 호출은 사람 승인 대상이라(CLAUDE.md P3) 자동 경로에 넣지 않는다
# (2) gh 부재·미인증이면 검사가 조용히 건너뛰어져 "머지 확인함"이 거짓이 된다 —
# 침묵이 통과로 읽히는 형태. 결론은 이 둘로 선다. (3) 은 그 자리를 로컬 검사로 메울 수
# 없다는 별개의 근거다 — 스쿼시 머지는 로컬 조상 관계를 남기지 않으므로, gh 를 안 부르는
# 대신 `git merge-base --is-ancestor` 같은 로컬 판정으로 대신하려 해도 머지 여부를 정직하게
# 말할 수 없다. 대신 이 스크립트는 **되돌릴 수 없는 손실**(미커밋·미푸시)만
# 기계로 판정하고, 머지 여부는 호출하는 사람이 판정한다 — develop 4-4 의 "사용자
# 지시로만"이 곧 그 판정의 표현이다.
set -uo pipefail
# 하네스 루트는 lib/harness-root.sh 가 낸다 (workspace.sh·board.sh 와 동일) — 호출자의 CWD 도
# 스크립트 위치도 쓰지 않는다. CWD 를 쓰면 워크트리에서 절대 경로로 불렸을 때 대상 레포의
# repos.json 을 읽고 bare bd 가 대상 원장에 붙는다.
# `$PWD` 가 아니라 `pwd -P` 다. 논리 경로로 잡으면 아래 inside() 가 심볼릭 경로로 들어온
# 호출자를 못 알아보고 **자기 CWD 를 지운다** (macOS 는 /var→/private/var 심링크가 기본이라
# 재현 소재가 늘 있다). 이 파일의 다른 경로 비교도 전부 pwd -P 로 통일돼 있다.
CALLER_PWD="$(pwd -P)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ROOT="$(bash "$PLUGIN_ROOT/lib/harness-root.sh")" || exit 1
cd "$ROOT" || { echo "✗ 하네스 루트로 이동하지 못했다: $ROOT" >&2; exit 1; }

STORY=""
FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    -*) echo "오류: 알 수 없는 옵션: $1 (사용법: workspace-cleanup.sh <story-id> [--force])" >&2; exit 1 ;;
    *) [[ -z "$STORY" ]] || { echo "오류: 스토리 ID 는 하나만 받는다" >&2; exit 1; }; STORY="$1"; shift ;;
  esac
done
[[ -n "$STORY" ]] || { echo "사용법: workspace-cleanup.sh <story-id> [--force]" >&2; exit 1; }

MANIFEST="${REPOS_MANIFEST:-repos.json}"   # 재정의는 검사 스크립트용
CLONE_ROOT="${HARNESS_CLONE_ROOT:-$HOME/.harness-workspace}"
command -v jq >/dev/null 2>&1 || { echo "오류: jq 가 없다 — 라벨·등록부 해석에 필수 (없으면 '라벨 없음' 오진이 난다)" >&2; exit 1; }
[[ -f "$MANIFEST" ]] || { echo "오류: $MANIFEST 없음" >&2; exit 1; }

# bd 실패와 "라벨 없음"을 구분한다. stderr 는 stdout 에 섞지 않는다 — bd 가 경고만 내도
# JSON 이 오염돼 jq 가 죽고 "라벨 없음" 오진이 난다 (workspace.sh 와 같은 실측).
BD_ERR=$(mktemp)
SHOW_JSON=$(bd show "$STORY" --json 2>"$BD_ERR")
if [[ $? -ne 0 ]]; then
  echo "오류: bd show 실패 — $(cat "$BD_ERR")" >&2; rm -f "$BD_ERR"; exit 1
fi
rm -f "$BD_ERR"
REPOS=$(printf '%s' "$SHOW_JSON" | jq -r '.[0].labels[]? | select(startswith("repo:")) | sub("^repo:"; "")')
[[ -n "$REPOS" ]] || { echo "오류: ${STORY} 에 repo:* 라벨이 없다" >&2; exit 1; }

BRANCH="story/$STORY"
fail=0

# 호출자가 서 있는 디렉토리를 지우지 않는다 — 지운 뒤 그 셸의 CWD 는 존재하지 않는
# inode 가 되어 이후 명령이 알 수 없는 이유로 죽는다.
# 비교는 **양쪽 다 물리 경로**로 한다. 한쪽만 논리 경로면 같은 디렉토리가 다른 문자열이 되어
# 가드가 통째로 헛돈다 (`/tmp/...` 로 cd 한 뒤 실행 → 안 걸리고 자기 CWD 삭제, 리뷰 실측).
inside() {  # inside <디렉토리> — CALLER_PWD 가 그 아래인가
  local dir="$1" dir_phys
  dir_phys=$(cd "$dir" 2>/dev/null && pwd -P || echo "")
  [[ -n "$dir_phys" ]] || return 1   # 없는 디렉토리 안에는 아무도 서 있을 수 없다
  [[ "$CALLER_PWD" == "$dir_phys" || "$CALLER_PWD" == "$dir_phys"/* ]]
}

while IFS= read -r name; do
  [[ -z "$name" ]] && continue

  if [[ "$(jq -r --arg n "$name" '[.repos[] | select(.name == $n)] | length' "$MANIFEST")" -eq 0 ]]; then
    echo "오류: $MANIFEST 에 '$name' 항목이 없다 (scripts/repo.sh add <url> --name $name)" >&2; fail=1; continue
  fi

  # 클론 위치는 등록부가 아니라 이름에서 파생한다 (workspace.sh 와 동일한 규약).
  repo="$CLONE_ROOT/$name"
  if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    echo "오류: '$name' 의 클론이 없다: $repo — 정리할 대상이 없다" >&2; fail=1; continue
  fi

  dest="$repo/.claude/worktrees/$STORY"
  marker="$repo/.claude/worktrees/.bootstrapped-$STORY"

  if inside "$dest"; then
    echo "오류: 호출자가 '$name' 의 정리 대상 워크트리 안에 서 있다 ($CALLER_PWD) — 밖에서 실행하라" >&2
    fail=1; continue
  fi

  # ── ① 원격 참조 갱신. 미푸시 판정의 근거이므로 실패하면 그 레포는 손대지 않는다.
  # 낡은 참조로 통과시키면 "푸시됐다"가 거짓이 될 수 있고, 정리는 급한 일이 아니다.
  if ! git -C "$repo" fetch --prune --quiet origin 2>/dev/null; then
    echo "오류: '$name' 의 fetch --prune 실패 — origin 참조를 갱신하지 못했다. 미푸시 판정의 근거가 없으므로 정리하지 않는다" >&2
    fail=1; continue
  fi

  # ── ② 검사 (워크트리가 있으면 실체 검증부터)
  wt_present=0
  if [[ -e "$dest" ]]; then
    # 무검증 제거는 세 실패를 통과시킨다: 깨진 잔존 디렉토리면 git -C 가 부모(=본
    # 체크아웃)로 폴스루하고, 브랜치가 다르면 남의 작업을 지우고, 클론과 무관한
    # 독립 레포면 이 클론이 모르는 트리를 지운다. workspace.sh 의 재사용 검증과 같은 셋.
    actual_top=$(git -C "$dest" rev-parse --show-toplevel 2>/dev/null || echo "")
    dest_phys=$(cd "$dest" 2>/dev/null && pwd -P || echo "")
    if [[ -z "$actual_top" || "$actual_top" != "$dest_phys" ]]; then
      echo "오류: $dest 이 있지만 git 워크트리가 아니다 (toplevel=${actual_top:-없음}) — 내용을 사람이 확인하라. 지우지 않는다" >&2
      fail=1; continue
    fi
    actual_branch=$(git -C "$dest" branch --show-current 2>/dev/null || echo "")
    if [[ "$actual_branch" != "$BRANCH" ]]; then
      echo "오류: $dest 의 브랜치가 '$actual_branch' 다 (기대: $BRANCH) — 다른 작업이다. 지우지 않는다" >&2
      fail=1; continue
    fi
    common=$(git -C "$dest" rev-parse --git-common-dir 2>/dev/null || echo "")
    [[ "$common" = /* ]] || common="$dest/$common"
    common_phys=$(cd "$common" 2>/dev/null && pwd -P || echo "")
    clone_git_phys=$(cd "$repo/.git" 2>/dev/null && pwd -P || echo "")
    if [[ -z "$common_phys" || "$common_phys" != "$clone_git_phys" ]]; then
      echo "오류: $dest 은 이 클론($repo)의 워크트리가 아니다 (git-common-dir=$common_phys) — 지우지 않는다" >&2
      fail=1; continue
    fi
    wt_present=1

    # 미커밋 — 추적 변경과 untracked 를 함께 본다(무시된 파일은 status 가 제외한다:
    # 부트스트랩 산출물 node_modules/ 로 정리가 막히지 않는다). **--force 로도 뚫리지 않는다.**
    dirty=$(git -C "$dest" status --short 2>/dev/null)
    if [[ -n "$dirty" ]]; then
      echo "중단: '$name' 워크트리에 미커밋 변경이 있다 — $dest" >&2
      printf '%s\n' "$dirty" >&2
      echo "  복구 경로가 없는 유일한 상태다. 커밋하거나 버릴지 사람이 정한 뒤 다시 실행하라 (--force 로도 무시되지 않는다)" >&2
      fail=1; continue
    fi
  else
    echo "알림: '$name' 의 워크트리 디렉토리가 이미 없다 ($dest) — 브랜치·마커 정리만 이어서 한다" >&2
  fi

  # 미푸시 — origin 의 **어느** 참조에서도 보이지 않는 커밋. 브랜치가 이미 없으면 건너뛴다.
  branch_present=0
  if git -C "$repo" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    branch_present=1
    unpushed=$(git -C "$repo" log --oneline "$BRANCH" --not --remotes=origin 2>/dev/null)
    if [[ -n "$unpushed" ]]; then
      if [[ "$FORCE" -eq 1 ]]; then
        echo "경고: '$name' 에 미푸시 커밋이 있으나 --force 로 진행한다 — 아래 커밋은 origin 어디에도 없다" >&2
        printf '%s\n' "$unpushed" >&2
      else
        echo "중단: '$name' 의 $BRANCH 에 미푸시 커밋이 있다 (origin 의 어느 참조에서도 안 보인다)" >&2
        printf '%s\n' "$unpushed" >&2
        echo "  push 하거나, 스쿼시 머지로 원격 브랜치가 지워진 경우라면 --force 로 다시 실행하라" >&2
        fail=1; continue
      fi
    fi
  fi

  # ── ③ 제거: 워크트리 → 로컬 브랜치 → 부트스트랩 마커
  removed=""
  if [[ "$wt_present" -eq 1 ]]; then
    # 남은 유일한 무성 손실 경로를 드러낸다. 무시된 파일은 위 미커밋 검사(`status --short`)에도
    # 안 잡히고 git 자신의 `worktree remove` 도 거부하지 않아 **그대로 사라진다** — 워크트리의
    # `.env` 가 정확히 이 경우다. 막지는 않는다(부트스트랩 산출물 node_modules/ 로 정리가
    # 막히면 안 된다). 막지 못하는 것을 드러내는 것이 이 줄의 일이다.
    ignored=$(git -C "$dest" status --short --ignored 2>/dev/null | sed -n 's/^!! //p')
    if [[ -n "$ignored" ]]; then
      ign_n=$(printf '%s\n' "$ignored" | wc -l | tr -d ' ')
      ign_head=$(printf '%s\n' "$ignored" | head -3 | tr '\n' ' ')
      ign_more=""
      [[ "$ign_n" -gt 3 ]] && ign_more="…"
      echo "알림: '$name' 워크트리의 무시된 파일 ${ign_n}건도 함께 사라진다 (검사도 git 도 이것을 막지 않는다): ${ign_head}${ign_more}" >&2
    fi
    if ! git -C "$repo" worktree remove "$dest" >&2; then
      echo "오류: '$name' 워크트리 제거 실패 — $dest (수동으로 지우지 마라. 원인을 확인하라)" >&2
      fail=1; continue
    fi
    removed="워크트리"
  fi
  # 등록부의 잔존 항목 정리 — 디렉토리가 이미 손으로 지워진 경우 remove 는 없었고
  # 관리 항목만 남아 있다. prune 은 실체 없는 항목만 건드리지만 **레포 전역**이다:
  # 이 스토리 밖의 워크트리도 실체가 일시적으로 안 보이면(외부·네트워크 볼륨 언마운트)
  # 그 등록까지 함께 사라지고, 볼륨이 돌아오면 그 디렉토리는 고아가 된다. 스크립트의
  # 나머지는 전부 $STORY 로 좁혀져 있으므로 여기도 좁힌다 — 고아 등록이 **우리 것뿐일
  # 때만** 돌리고, 남의 것이 섞여 있으면 손대지 않고 알린다 (정리는 급한 일이 아니다).
  repo_phys=$(cd "$repo" && pwd -P)
  orphans=$(git -C "$repo" worktree list --porcelain | sed -n 's/^worktree //p' \
            | while IFS= read -r w; do [[ -e "$w" ]] || printf '%s\n' "$w"; done)
  others=$(printf '%s\n' "$orphans" | grep -vxF -e "$dest" -e "$repo_phys/.claude/worktrees/$STORY")
  if [[ -z "$others" ]]; then
    git -C "$repo" worktree prune >&2
  else
    echo "알림: '$name' 의 워크트리 등록부를 정리하지 않았다 — 이 스토리 밖의 등록도 실체가 안 보인다. 전역 정리는 그것들까지 지운다 (언마운트된 볼륨이면 되돌아왔을 때 고아가 된다):" >&2
    printf '  %s\n' $others >&2
    echo "  의도한 것이면 손으로 정리하라 (git -C $repo 의 worktree 하위 명령)" >&2
  fi

  if [[ "$branch_present" -eq 1 ]]; then
    # -d 가 아니라 -D 다. -d 는 "현재 HEAD 에 머지됐는가"를 묻는데, 클론의 HEAD 는 기본
    # 브랜치의 낡은 로컬 사본이라 머지된 브랜치도 거부한다. 손실 판정은 위 미푸시 검사가
    # 이미 했고 그쪽이 더 정확하다 (origin 전체 참조 대조).
    if git -C "$repo" branch -D "$BRANCH" >&2; then
      removed="${removed:+${removed}·}브랜치 $BRANCH"
    else
      # continue 하지 않는다. 워크트리를 이미 지웠다면 그 사실이 stdout 계약에 실려야
      # 한다 — 건너뛰면 **반쯤 정리된 레포와 손도 안 댄 레포가 구분되지 않는다.**
      # fail=1 로 rc 는 비-0 이 되고, 무엇이 남았는지는 아래 "정리:" 줄이 밝힌다.
      echo "오류: '$name' 의 로컬 브랜치 $BRANCH 삭제 실패 — 브랜치는 남는다" >&2
      fail=1
    fi
  fi
  [[ -e "$marker" ]] && removed="${removed:+${removed}·}부트스트랩 마커"
  rm -f "$marker"

  # stdout 은 "제거했다"는 계약이다. 제거한 것이 없으면 찍지 않는다 — 찍으면 파싱하는
  # 호출자가 이미 정리된 상태를 방금 제거한 것으로 읽는다. 헤더의 "제거를 거부한 레포는
  # stdout 에 나오지 않는다"가 실제로 성립하는 지점이 여기다.
  [[ -n "$removed" ]] && printf '%s\t%s\n' "$name" "$dest"
  # 무엇을 실제로 지웠는지만 적는다 — 이미 정리된 상태로 다시 불리면 "없음"이 된다.
  echo "정리: $name — 제거: ${removed:-없음 (이미 정리된 상태)} (클론은 남긴다: $repo)" >&2
done <<< "$REPOS"

if [[ "$fail" -ne 0 ]]; then
  echo "오류: 일부 레포를 정리하지 못했다 — 위 stderr 확인. 정리된 레포는 그대로다" >&2
  exit 1
fi
