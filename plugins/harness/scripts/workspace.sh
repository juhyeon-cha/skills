#!/usr/bin/env bash
# 스토리 워크트리 생성기
# 사용법: scripts/workspace.sh <story-id>
#
# 스토리 bead의 repo:<이름> 라벨마다 repos.json 에서 레포를 찾아, 그 레포의 클론
# (~/.harness-workspace/<이름>) 안에 워크트리를 만든다:
#   ~/.harness-workspace/<이름>/.claude/worktrees/<story-id>   브랜치 story/<story-id>
#
# stdout: "<레포이름>\t<워크트리 절대경로>" 줄 목록 (계약 채널) — 진단은 전부 stderr.
#   멀티 레포 스토리는 워크트리가 레포별로 흩어지므로 경로가 하나가 아니다.
#   위임할 때는 이 목록과 **하네스 루트 절대 경로**를 함께 준다 — 워크트리 위치에서
#   하네스 루트를 파생할 수 없다.
# 일부 레포가 실패해도 나머지는 만들고, 실패 사실을 남긴 뒤 비-0으로 끝난다.
set -uo pipefail
# 하네스 루트는 lib/harness-root.sh 가 낸다 — 호출자의 CWD(git toplevel)도 스크립트 위치도
# 쓰지 않는다 (플러그인은 하네스 루트 밖에 산다. CWD 를 쓰면 워크트리에서 엉뚱한 repos.json 을
# 찾고 bare bd 가 대상 원장에 붙는다).
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ROOT="$(bash "$PLUGIN_ROOT/lib/harness-root.sh")" || exit 1
cd "$ROOT" || { echo "✗ 하네스 루트로 이동하지 못했다: $ROOT" >&2; exit 1; }

STORY="${1:?사용법: workspace.sh <story-id>}"
MANIFEST="${REPOS_MANIFEST:-repos.json}"   # 재정의는 검사 스크립트용
CLONE_ROOT="${HARNESS_CLONE_ROOT:-$HOME/.harness-workspace}"
command -v jq >/dev/null 2>&1 || { echo "오류: jq 가 없다 — 라벨·등록부 해석에 필수 (없으면 '라벨 없음' 오진이 난다)" >&2; exit 1; }
[[ -f "$MANIFEST" ]] || { echo "오류: $MANIFEST 없음" >&2; exit 1; }
# 워크트리에 배선할 원장. 없으면 배선 없는 워크트리를 남기지 않고 여기서 멈춘다 —
# 그 안의 bare bd 는 "bd init 으로 새 DB 를 만들라"고 권하고, 따르면 원장이 이원화된다.
LEDGER="$ROOT/.beads"
[[ -d "$LEDGER" ]] || { echo "오류: 하네스 원장 $LEDGER 이 없다 — 워크트리에 배선할 대상이 없다" >&2; exit 1; }
# $ROOT 자신이 배선된 워크트리면(하네스를 워크트리에서 개발하는 경우) 그 .beads 는 원장이
# 아니라 배선이다 — 추적되는 뼈대(metadata.json·hooks)만 있고 dolt 데이터가 없다. 배선을
# 배선에 걸면 bd 가 붙지 못하므로(실측 2026-08-30: rc=4) 여기서 한 번 따라간다.
[[ -f "$LEDGER/redirect" ]] && LEDGER="$(cat "$LEDGER/redirect")"

# bd 실패와 "라벨 없음"을 구분한다 — 합쳐 읽으면 DB 미가용을 라벨 문제로 오진한다.
# stderr 는 stdout 에 섞지 않는다: bd 가 성공하면서 경고만 내도 JSON 이 오염돼
# jq 가 죽고 같은 오진이 재발한다 (실측 2026-08-20).
BD_ERR=$(mktemp)
SHOW_JSON=$(bd show "$STORY" --json 2>"$BD_ERR")
if [[ $? -ne 0 ]]; then
  echo "오류: bd show 실패 — $(cat "$BD_ERR")" >&2; rm -f "$BD_ERR"; exit 1
fi
rm -f "$BD_ERR"
REPOS=$(printf '%s' "$SHOW_JSON" | jq -r '.[0].labels[]? | select(startswith("repo:")) | sub("^repo:"; "")')
[[ -n "$REPOS" ]] || { echo "오류: ${STORY} 에 repo:* 라벨이 없다" >&2; exit 1; }

BRANCH="story/$STORY"
# 클론의 로컬 제외 목록에 넣을 줄. `.beads` 는 아래 ensure_ledger_link 가 만드는 원장
# 배선이다 — 대상 레포는 그 이름을 gitignore 하지 않으므로 등재하지 않으면 워크트리
# git status 에 뜬다. 통짜 `.beads` 라서 이미 추적 중인 파일(하네스 자신의 원장 뼈대)에는
# 닿지 않고, 그 아래 새로 생기는 파일만 가린다 — 가리려는 것이 정확히 그것이다.
EXCLUDE_LINES=(".claude/worktrees/" ".beads")
fail=0

# 워크트리 디렉토리를 클론의 로컬 제외 목록에 멱등 재보장한다 — repo.sh add 가
# 1회 등재하지만, exclude 소실·수동 클론 상태에서 워크트리를 만들면 본 체크아웃
# git status 에 .claude/ 가 통째로 떠 "본 체크아웃 오염 금지" 신호를 흐린다.
ensure_exclude() {
  local repo_dir="$1" exclude_file
  exclude_file="$(git -C "$repo_dir" rev-parse --git-path info/exclude 2>/dev/null)" || return 0
  [[ "$exclude_file" = /* ]] || exclude_file="$repo_dir/$exclude_file"
  mkdir -p "$(dirname "$exclude_file")"; touch "$exclude_file"
  local line
  for line in "${EXCLUDE_LINES[@]}"; do
    grep -qxF "$line" "$exclude_file" 2>/dev/null || printf '%s\n' "$line" >> "$exclude_file"
  done
}

# 워크트리의 bare bd 를 하네스 원장에 붙인다. 배선이 없으면 bd 가 "no beads database
# found / bd init 으로 새 DB 를 만들라"고 권하고, 에이전트가 힌트를 따르면 원장이
# 이원화된다 (실측 2026-08-30: sap-harness 워크트리의 bd list, 그리고 하네스 자신의
# 워크트리도 같다 — 원장의 dolt 디렉토리는 추적 대상이 아니라 워크트리에 오지 않는다).
#
# 수단은 bd 자신의 워크트리 장치다: `.beads/redirect` 에 원장 디렉토리 경로를 적으면
# 그리로 붙는다(그 파일명은 bd 가 만드는 `.beads/.gitignore` 가 이미 든다). 환경 변수는
# 세션마다 다시 필요하고 복사는 원장을 복제하므로 둘 다 쓰지 않는다. 절대 경로를 적는다 —
# bd 가 만드는 그 .gitignore 는 이 파일을 "relative path" 라 적지만 절대 경로도 먹는다
# (실측 2026-08-30, bd 1.2.2 Homebrew). 커밋되지 않는 파일이라 다른 클론으로 옮겨갈 일이
# 없고, 워크트리 깊이에도 의존하지 않는다.
ensure_ledger_link() {
  mkdir -p "$1/.beads" && printf '%s\n' "$LEDGER" > "$1/.beads/redirect" && return 0
  echo "오류: 원장 배선 실패 — $1/.beads/redirect 를 쓸 수 없다" >&2
  return 1
}

# 부트스트랩 실행 + 완료 마커. 마커는 워크트리 밖(형제 파일)에 둔다 — 워크트리 안에
# 두면 대상 레포 체크아웃에 untracked 로 뜬다. 마커가 없으면 재실행 경로에서도
# 부트스트랩을 다시 시도한다 (실측 2026-08-20: 마커 없이는 "수동 확인 후 재실행하라"
# 안내를 따른 재실행이 부트스트랩을 건너뛰고 rc=0 을 냈다).
run_bootstrap() {
  local name="$1" dest="$2" marker="$3"
  local cmd
  cmd=$(jq -r --arg n "$name" '.repos[] | select(.name == $n) | .bootstrap // ""' "$MANIFEST")
  [[ -z "$cmd" ]] && { touch "$marker"; return 0; }
  if [[ -f "$marker" ]]; then return 0; fi
  echo "부트스트랩: $name — $cmd" >&2
  if (cd "$dest" && bash -c "$cmd") >&2; then
    touch "$marker"; return 0
  fi
  echo "오류: '$name' 부트스트랩 실패 — 워크트리는 남긴다. 원인 해결 후 재실행하면 부트스트랩부터 재시도한다" >&2
  return 1
}

while IFS= read -r name; do
  [[ -z "$name" ]] && continue

  if [[ "$(jq -r --arg n "$name" '[.repos[] | select(.name == $n)] | length' "$MANIFEST")" -eq 0 ]]; then
    echo "오류: $MANIFEST 에 '$name' 항목이 없다 (scripts/repo.sh add <url> --name $name)" >&2; fail=1; continue
  fi

  # 클론 위치는 등록부가 아니라 이름에서 파생한다 — scripts/repo.sh 가 거기에 클론한다.
  repo="$CLONE_ROOT/$name"
  if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    echo "오류: '$name' 의 클론이 없다: $repo (scripts/repo.sh restore 또는 add 로 확보하라)" >&2; fail=1; continue
  fi

  dest="$repo/.claude/worktrees/$STORY"
  marker="$repo/.claude/worktrees/.bootstrapped-$STORY"
  if [[ -e "$dest" ]]; then
    # 재사용 전 검증 — 무검증 재사용은 세 실패를 통과시킨다:
    #   깨진 잔존 디렉토리면 git -C 가 부모(=본 체크아웃)로 폴스루해 워크트리인 척하고,
    #   브랜치가 다르면 엉뚱한 작업 위에 이어 쓰고,
    #   클론과 무관한 독립 레포(브랜치명만 일치)면 고아 트리에 커밋이 쌓인다.
    # 물리 경로끼리 비교한다 (macOS /var→/private/var, 실측 2026-08-19).
    actual_top=$(git -C "$dest" rev-parse --show-toplevel 2>/dev/null || echo "")
    dest_phys=$(cd "$dest" 2>/dev/null && pwd -P || echo "")
    if [[ -z "$actual_top" || "$actual_top" != "$dest_phys" ]]; then
      echo "오류: $dest 이 있지만 git 워크트리가 아니다 (toplevel=${actual_top:-없음}) — 치우고 재실행하라" >&2
      fail=1; continue
    fi
    actual_branch=$(git -C "$dest" branch --show-current 2>/dev/null || echo "")
    if [[ "$actual_branch" != "$BRANCH" ]]; then
      echo "오류: $dest 의 브랜치가 '$actual_branch' 다 (기대: $BRANCH) — 다른 작업의 잔존. 확인 후 치워라" >&2
      fail=1; continue
    fi
    # 클론과의 연결 — 워크트리의 공용 git 디렉토리가 이 클론의 .git 인지 (실측 2026-08-20:
    # git init + 브랜치명만 맞춘 독립 레포가 위 두 검사를 통과했다).
    common=$(git -C "$dest" rev-parse --git-common-dir 2>/dev/null || echo "")
    [[ "$common" = /* ]] || common="$dest/$common"
    common_phys=$(cd "$common" 2>/dev/null && pwd -P || echo "")
    clone_git_phys=$(cd "$repo/.git" 2>/dev/null && pwd -P || echo "")
    if [[ -z "$common_phys" || "$common_phys" != "$clone_git_phys" ]]; then
      echo "오류: $dest 은 이 클론($repo)의 워크트리가 아니다 (git-common-dir=$common_phys) — 치우고 재실행하라" >&2
      fail=1; continue
    fi
    # 체크아웃이 끝나지 않은 빈 워크트리 — 위 세 검사를 전부 통과한다(worktree add
    # --no-checkout 이 만드는 상태 그대로다). 생성 중 checkout 이 실패하거나 add 와
    # checkout 사이에 중단되면 남고, 검증이 이것을 통과시키면 재실행이 "재사용: 검증
    # 통과" 를 찍고 빈 트리를 정상으로 돌려준다.
    if [[ -z "$(git -C "$dest" ls-files | head -n 1)" ]]; then
      echo "오류: $dest 의 인덱스가 비었다 — 체크아웃이 끝나지 않은 잔존. 치우고 재실행하라" >&2
      fail=1; continue
    fi
    ensure_exclude "$repo"
    ensure_ledger_link "$dest" || { fail=1; continue; }
    run_bootstrap "$name" "$dest" "$marker" || { fail=1; continue; }
    echo "재사용: 기존 워크트리 검증 통과 — $dest" >&2
    printf '%s\t%s\n' "$name" "$dest"
    continue
  fi

  # 기준 커밋은 원격의 기본 브랜치다. 클론의 HEAD 는 PR 이 머지돼도
  # 자동으로 따라오지 않아, HEAD 에서 분기하면 낡은 트리 위에서 작업하게 된다.
  base=$(jq -r --arg n "$name" '.repos[] | select(.name == $n) | .default_branch // ""' "$MANIFEST")
  if [[ -z "$base" ]]; then
    echo "오류: $MANIFEST 의 '$name' 에 default_branch 가 없다" >&2; fail=1; continue
  fi
  if [[ "$base" == *$'\n'* ]]; then
    echo "오류: $MANIFEST 에 '$name' 이 중복 등록돼 있다 (default_branch 가 여러 값) — 등록부를 정리하라" >&2; fail=1; continue
  fi
  if ! git -C "$repo" fetch --quiet origin "$base" 2>/dev/null; then
    echo "오류: '$name' 의 origin/$base fetch 실패 — 기준 커밋을 확정할 수 없다 (브랜치가 개명됐다면 repos.json 의 default_branch 를 갱신하라)" >&2; fail=1; continue
  fi

  mkdir -p "$repo/.claude/worktrees"
  # 이전 워크트리의 부트스트랩 마커가 남아 있으면(worktree remove 는 마커를 안 지운다)
  # 새 워크트리가 부트스트랩을 건너뛴다 — 신규 생성은 항상 마커 없이 시작한다.
  rm -f "$marker"
  ensure_exclude "$repo"
  # 체크아웃을 `--no-checkout` 으로 미룬다. worktree add 는 체크아웃을 그 자리에서 하면서
  # post-checkout 훅을 부르는데, 그 훅의 투영 렌더(플러그인은 훅을 심지 않는다 — 하네스 레포
  # 자신처럼 .beads/hooks 에 board.sh 를 배선한 레포에서만 돈다)는 bd 로
  # 원장을 읽는다 — 아래 ensure_ledger_link 보다 먼저 도니 .beads/redirect 가 없고, bd 가
  # 원장을 못 찾아 렌더가 실패해 거짓 경고가 난다. 순서만이 원인이다 (실측 2026-08-31:
  # 갓 만든 워크트리에서 redirect 유무만 바꿔 board.sh all 을 돌리면 있을 때 rc=0,
  # 없을 때 rc=1 "no beads database found"). 배선 뒤에 git 에게 체크아웃을 시키면 훅도
  # 그때 돌고, 부르는 주체가 여전히 git 이라 훅의 인자 규약을 흉내 낼 필요가 없다.
  if git -C "$repo" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git -C "$repo" worktree add --no-checkout "$dest" "$BRANCH" >&2 || { fail=1; continue; }
    # 기존 브랜치 재개 — 기준을 갱신하지 않으므로 "origin 최신" 을 찍으면 거짓 로그가 된다
    # (실측 2026-08-20: 옛 커밋의 브랜치를 체크아웃하며 최신 sha 를 보고했다).
    echo "재개: 기존 브랜치 $BRANCH @ $(git -C "$dest" rev-parse --short HEAD) — 기준 갱신 안 함 (origin/$base 최신: $(git -C "$repo" rev-parse --short "origin/$base"))" >&2
  else
    git -C "$repo" worktree add --no-checkout -b "$BRANCH" "$dest" "origin/$base" >&2 || { fail=1; continue; }
    echo "기준: $name @ origin/$base ($(git -C "$repo" rev-parse --short "origin/$base"))" >&2
  fi

  ensure_ledger_link "$dest" || { fail=1; continue; }
  # 미뤄 둔 체크아웃 — 트리를 채우고 post-checkout 훅을 돌린다. 배선 뒤라 훅의 렌더가
  # 원장을 찾는다. 실패하면 빈 워크트리가 남으므로 여기서 끊는다.
  git -C "$dest" checkout --force "$BRANCH" >&2 || { fail=1; continue; }
  run_bootstrap "$name" "$dest" "$marker" || { fail=1; continue; }

  printf '%s\t%s\n' "$name" "$dest"
done <<< "$REPOS"

if [[ "$fail" -ne 0 ]]; then
  echo "오류: 일부 레포 실패 — 위 stderr 확인. 성공한 워크트리는 유지된다" >&2
  exit 1
fi
