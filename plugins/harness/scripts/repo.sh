#!/usr/bin/env bash
# 대상 레포 등록부 관리 — 클론과 repos.json 등재를 한 번에 한다.
#
# 사용:
#   scripts/repo.sh add <url> [--name <이름>] [--branch <기본브랜치>] [--check <게이트명령>] [--bootstrap <명령>]
#   scripts/repo.sh check <이름>         그 레포의 게이트 명령을 한 줄로 낸다 (.harness.json 에서)
#   scripts/repo.sh restore [<이름>]     등록부에 있는데 클론이 없는 레포를 다시 클론 (새 머신)
#   scripts/repo.sh apply <이름>         add 없이 클론 루트 층의 하네스 루트 기록(아래)만 다시 돌린다 (기존 클론용)
#   scripts/repo.sh list
#   scripts/repo.sh remove <이름>
#
# **게이트 명령·기본 브랜치·부트스트랩은 대상 레포 자신이 소유한다** — 클론 루트의 `.harness.json`
# 이 그 자리다. 하네스의 등록부에 두면 레포를 아는 사람이 고칠 수 없는 자리에 그 레포의 지식이
# 앉고, 하네스가 둘이면 값도 둘로 갈린다. add 는 클론에 그 파일이 없을 때만 만들어 준다 —
# 이미 있으면 손대지 않는다(그 레포의 추적 파일이다).
#
# 클론 위치는 ~/.harness-workspace/<이름> 으로 고정한다. 손으로 적은 경로는 썩는다 —
# 등록만 남고 클론이 사라진 repos.json 을 실측으로 겪었다. 위치를 도구가 정하면
# "등재됐다"와 "클론이 있다"가 갈라지지 않는다.
#
# 스토리 워크트리는 클론 안(<클론>/.claude/worktrees/<story-id>)에 생긴다.
# 그 경로를 대상 레포의 .gitignore 가 아니라 .git/info/exclude 에 넣는다 —
# .gitignore 는 대상 레포가 소유한 추적 파일이므로 하네스가 고치지 않는다.
#
# 클론 루트 층의 하네스 루트 기록 (add·restore·apply 가 공통으로 돈다 — 이 스크립트가 그 층을 소유한다):
#   <클론루트>/.harness-root 에 하네스 루트 절대 경로 한 줄 — lib/harness-root.sh 가 읽는 형식 그대로.
#   이미 다른 경로가 적혀 있으면 덮어쓰지 않고 rc≠0 — 하네스가 둘이면 어느 원장인지 사람이 정한다.
#
# 플러그인은 클론마다 등록하지 않는다 — harness@skills 는 user scope 로 한 번 설치되고(skills/setup/SKILL.md),
# 이 스크립트는 클론의 .claude/ 아래에 아무것도 쓰지 않는다. 클론별 등록(local scope 설치·직접 병합)은
# 같은 플러그인이 scope 마다 따로 잡힌다 — 실측 근거는 harness-m8gg.2.1 의 note.
set -uo pipefail
# 하네스 루트는 lib/harness-root.sh 가 낸다 — 호출자의 CWD 도 스크립트 위치도 쓰지 않는다
# (플러그인은 하네스 루트 밖에 산다. CWD 를 쓰면 워크트리에서 대상 레포에 repos.json 을 만들어 버린다).
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ROOT="$(bash "$PLUGIN_ROOT/lib/harness-root.sh")" || exit 1
cd "$ROOT" || { echo "✗ 하네스 루트로 이동하지 못했다: $ROOT" >&2; exit 1; }

MANIFEST="${REPOS_MANIFEST:-repos.json}"   # 재정의는 검사 스크립트용
CLONE_ROOT="${HARNESS_CLONE_ROOT:-$HOME/.harness-workspace}"
EXCLUDE_LINE=".claude/worktrees/"
ROOT_FILE="$CLONE_ROOT/.harness-root"        # lib/harness-root.sh 의 3순위 — 읽기는 거기, 쓰기는 여기

die() { echo "오류: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

have git || die "git 이 필요하다"
have jq || die "jq 가 필요하다"

# repos.json 이 없으면 빈 등록부를 만든다 (add 일 때만 — list/remove 는 없으면 오류).
DOC_TEXT="대상 레포 manifest. name: repo:<name> 라벨과 대응. url: 클론 소스. 클론 위치는 ~/.harness-workspace/<name> 으로 고정(scripts/repo.sh 가 관리). 게이트 명령·기본 브랜치·부트스트랩은 여기 없다 — 대상 레포 자신의 .harness.json 이 소유한다."
HARNESS_JSON_DOC="하네스가 이 레포를 다루는 방법. 이 레포가 소유한다 — 하네스 루트가 아니라 여기 있어야 클론마다 갈리지 않는다. check: 게이트 명령(레포 루트 기준) — 하네스는 종료 코드만 본다. default_branch: 워크트리를 자르는 기준 브랜치. bootstrap: 워크트리 생성 직후 그 안에서 1회 실행할 준비 명령(선택, 없으면 키를 두지 않는다)."

clone_path() { echo "$CLONE_ROOT/$1"; }
harness_json() { echo "$(clone_path "$1")/.harness.json"; }

# repos.json 에서 한 레포의 필드를 읽는다.
field_of() {
  jq -r --arg n "$1" --arg f "$2" '.repos[] | select(.name == $n) | .[$f] // ""' "$MANIFEST"
}

# 대상 레포가 소유한 .harness.json 에서 한 필드를 읽는다. 파일이 없으면 그 경로를 들고 죽는다 —
# 폴백으로 덮으면 "게이트가 없는 레포" 가 "게이트가 true 인 레포" 로 조용히 읽힌다.
hfield_of() {
  local f; f="$(harness_json "$1")"
  [[ -f "$f" ]] || die "$f 이 없다 — 게이트 명령·기본 브랜치는 대상 레포가 소유한다. 그 레포 루트에 {\"check\": …, \"default_branch\": …} 로 만들어 커밋하라"
  jq -r --arg k "$2" '.[$k] // ""' "$f" 2>/dev/null \
    || die "$f 이 유효한 JSON 이 아니다"
}
# 죽지 않는 판(list 표시용) — 없으면 빈 값이다.
hfield_soft() {
  local f; f="$(harness_json "$1")"
  [[ -f "$f" ]] || return 0
  jq -r --arg k "$2" '.[$k] // ""' "$f" 2>/dev/null || true
}

has_repo() {
  [[ -f "$MANIFEST" ]] || return 1
  [[ "$(jq -r --arg n "$1" '[.repos[] | select(.name == $n)] | length' "$MANIFEST")" -gt 0 ]]
}

# 한 행을 대상 레포의 로컬 제외 목록에 넣는다 (멱등). $1=클론 경로 $2=행.
# .git/info/exclude 는 커밋되지 않으므로 대상 레포의 이력을 오염시키지 않는다.
add_local_exclude() {
  local repo_dir="$1" line="$2"
  local exclude_file
  exclude_file="$(git -C "$repo_dir" rev-parse --git-path info/exclude 2>/dev/null)" || return 0
  [[ -n "$exclude_file" ]] || return 0
  # rev-parse 는 레포 기준 상대 경로를 낼 수 있다.
  [[ "$exclude_file" = /* ]] || exclude_file="$repo_dir/$exclude_file"
  mkdir -p "$(dirname "$exclude_file")"
  touch "$exclude_file"
  if grep -qxF "$line" "$exclude_file" 2>/dev/null; then
    echo "  제외 목록: 이미 등재됨 ($line)"
  else
    printf '%s\n' "$line" >> "$exclude_file"
    echo "  제외 목록: $line → .git/info/exclude"
  fi
}

# 클론 루트 층의 하네스 루트 기록 (파일 머리 주석). $1=name. 실패는 die — restore 처럼
# 여러 건을 돌리는 자리는 서브셸로 격리한다.
apply_root() {
  local name="$1"
  local dest; dest="$(clone_path "$name")"
  git -C "$dest" rev-parse --git-dir >/dev/null 2>&1 || die "$dest 이 git 레포가 아니다 — 먼저 'restore $name'"

  # .harness-root — 이미 다른 값이면 덮어쓰지 않는다.
  if [[ -f "$ROOT_FILE" ]]; then
    local existing; existing="$(head -1 "$ROOT_FILE")"
    [[ "$existing" == "$ROOT" ]] \
      || die "$ROOT_FILE 이 이미 다른 하네스 루트를 가리킨다: '$existing' (지금 루트: '$ROOT') — 덮어쓰지 않는다. 하나로 정한 뒤 그 파일을 손으로 고쳐라"
    echo "  하네스 루트: 이미 같음 ($ROOT_FILE)"
  else
    mkdir -p "$CLONE_ROOT"
    printf '%s\n' "$ROOT" > "$ROOT_FILE"
    echo "  하네스 루트: $ROOT → $ROOT_FILE"
  fi
}

# 클론 확보 공통부 — add 와 restore 가 같이 쓴다.
# $1=name $2=url $3=branch(빈 값이면 origin/HEAD 탐지) → 전역 DETECTED_BRANCH 에 결과.
ensure_clone() {
  local name="$1" url="$2" branch="$3"
  local dest; dest="$(clone_path "$name")"

  if [[ -e "$dest" ]]; then
    git -C "$dest" rev-parse --git-dir >/dev/null 2>&1 \
      || die "$dest 이 이미 있는데 git 레포가 아니다 — 치우고 다시 실행하라"
    local existing; existing="$(git -C "$dest" remote get-url origin 2>/dev/null || echo "")"
    [[ "$existing" == "$url" ]] \
      || die "$dest 은 다른 원격을 가리킨다 ($existing) — 다른 --name 을 쓰거나 그 디렉토리를 치워라"
    echo "  클론: 이미 있음 — 재사용 ($dest)"
  else
    mkdir -p "$CLONE_ROOT"
    echo "  클론: $url → $dest"
    git clone "$url" "$dest" || die "클론 실패: $url"
  fi

  if [[ -z "$branch" ]]; then
    git -C "$dest" remote set-head origin --auto >/dev/null 2>&1 \
      || echo "경고: origin/HEAD 갱신 실패(오프라인?) — 클론 시점의 값으로 탐지한다. 낡았을 수 있으니 확인하라" >&2
    branch="$(git -C "$dest" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
    [[ -n "$branch" ]] || die "기본 브랜치를 탐지하지 못했다 — --branch 로 지정하라"
    echo "  기본 브랜치: $branch (origin/HEAD 에서 탐지)"
  else
    git -C "$dest" show-ref --verify --quiet "refs/remotes/origin/$branch" \
      || die "origin/$branch 이 없다 — --branch 값을 확인하라"
    echo "  기본 브랜치: $branch"
  fi

  add_local_exclude "$dest" "$EXCLUDE_LINE"
  apply_root "$name"

  # 커밋 신원을 하네스 레포의 로컬 설정에서 복사한다 — 전역 신원은 레포마다 다를 수
  # 있어, 하네스와 대상 클론의 저자를 일치시킨다. 하네스에 로컬 설정이 없으면 건드리지 않는다.
  local id_name id_email
  id_name=$(git -C "$ROOT" config --local user.name 2>/dev/null || echo "")
  id_email=$(git -C "$ROOT" config --local user.email 2>/dev/null || echo "")
  if [[ -n "$id_name" && -n "$id_email" ]]; then
    git -C "$dest" config user.name "$id_name"
    git -C "$dest" config user.email "$id_email"
    echo "  커밋 신원: $id_name <$id_email> (하네스 레포에서 복사)"
  fi

  DETECTED_BRANCH="$branch"
}

cmd_add() {
  local url="" name="" branch="" check="" bootstrap=""
  url="${1:-}"; shift || true
  [[ -n "$url" ]] || die "사용법: scripts/repo.sh add <url> [--name <이름>] [--branch <기본브랜치>] [--check <게이트명령>] [--bootstrap <명령>]"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)      name="${2:?--name 값이 없다}"; shift 2 ;;
      --branch)    branch="${2:?--branch 값이 없다}"; shift 2 ;;
      --check)     check="${2:?--check 값이 없다}"; shift 2 ;;
      --bootstrap) bootstrap="${2:?--bootstrap 값이 없다}"; shift 2 ;;
      *) die "알 수 없는 옵션: $1" ;;
    esac
  done

  # 이름 기본값: url 의 마지막 경로 조각에서 .git 을 뗀다.
  if [[ -z "$name" ]]; then
    name="${url##*/}"
    name="${name%.git}"
  fi
  [[ -n "$name" ]] || die "레포 이름을 정할 수 없다 — --name 으로 지정하라"
  # 이름은 클론 경로가 된다 — 검증 없으면 --name ../x 가 CLONE_ROOT 밖에 클론된다.
  [[ "$name" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "레포 이름 형식 위반: '$name' (소문자·숫자·점·밑줄·하이픈, 첫 글자는 영숫자)"

  has_repo "$name" && die "'$name' 은 이미 $MANIFEST 에 등록돼 있다 (클론만 복구하려면 'restore $name', 재등록은 remove 후 add)"

  echo "add: $name"
  ensure_clone "$name" "$url" "$branch"
  branch="$DETECTED_BRANCH"

  [[ -f "$MANIFEST" ]] || jq -n --arg doc "$DOC_TEXT" '{doc: $doc, repos: []}' > "$MANIFEST"

  # 등록부 쓰기는 잠금으로 직렬화한다 — 동시 add 2건이 read-modify-write 를 겹치면
  # 나중 mv 가 먼저 등록을 소리 없이 덮는다. tmp 는 같은 디렉토리에 둬 mv 를 원자로.
  local lock="$MANIFEST.lock"
  mkdir "$lock" 2>/dev/null || die "$MANIFEST 갱신이 이미 진행 중이다 ($lock). 잔존물이면 지우고 재실행하라"
  # 잠금 밖의 첫 검사(위)와 여기 사이에 긴 clone 이 낀다 — 동시 add 두 건이 둘 다
  # 첫 검사를 통과할 수 있으므로 잠금 안에서 재검사한다.
  if has_repo "$name"; then rmdir "$lock"; die "'$name' 은 이미 $MANIFEST 에 등록돼 있다 (동시 등록 감지)"; fi
  local tmp="$MANIFEST.tmp.$$"
  if jq --arg n "$name" --arg u "$url" '.repos += [{name: $n, url: $u}]' "$MANIFEST" > "$tmp"; then
    mv "$tmp" "$MANIFEST"; rmdir "$lock"
  else
    rm -f "$tmp"; rmdir "$lock"; die "$MANIFEST 갱신 실패 (jq 오류) — 등록부가 유효한 JSON 인지 확인하라"
  fi
  echo "  등록: $MANIFEST"

  # 게이트 명령·기본 브랜치·부트스트랩은 대상 레포가 소유한다. 클론에 이미 있으면 손대지 않는다 —
  # 그 레포의 추적 파일이고, 하네스가 남의 레포 파일을 덮을 자리가 아니다.
  local hj; hj="$(harness_json "$name")"
  if [[ -f "$hj" ]]; then
    echo "  게이트: 대상 레포가 이미 소유한다 ($hj) — 손대지 않는다"
    check="$(hfield_soft "$name" check)"
  else
    jq -n --arg doc "$HARNESS_JSON_DOC" --arg c "$check" --arg b "$branch" --arg bs "$bootstrap" \
      '{doc: $doc, check: $c, default_branch: $b} + (if $bs == "" then {} else {bootstrap: $bs} end)' > "$hj" \
      || die "$hj 을 만들지 못했다"
    echo "  게이트: $hj 을 만들었다 — **대상 레포에 커밋하라** (하네스가 아니라 그 레포가 소유한다)"
  fi

  if [[ -z "$check" ]]; then
    echo
    echo "경고: '$name' 의 check 가 비어 있다. 게이트 명령을 채우기 전까지" >&2
    echo "      implementer 는 이 레포에서 게이트를 돌릴 수 없고 evaluator 는 재실행할 수 없다." >&2
    echo "      $hj 의 check 를 채워라." >&2
  fi
}

# 게이트 명령 한 줄. 소비자는 implementer·evaluator 다 — 없으면 조용히 통과시키지 않는다.
cmd_check() {
  local name="${1:-}" c
  [[ -n "$name" ]] || die "사용법: scripts/repo.sh check <이름>"
  has_repo "$name" || die "'$name' 이 $MANIFEST 에 없다"
  c="$(hfield_of "$name" check)" || exit 1
  [[ -n "$c" ]] || die "$(harness_json "$name") 의 check 가 비어 있다 — 게이트 명령이 없는 레포는 통과를 판정할 수 없다"
  printf '%s\n' "$c"
}

cmd_list() {
  [[ -f "$MANIFEST" ]] || die "$MANIFEST 이 없다"
  local n
  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    local dest state wt
    dest="$(clone_path "$n")"
    if git -C "$dest" rev-parse --git-dir >/dev/null 2>&1; then
      wt=$(git -C "$dest" worktree list --porcelain 2>/dev/null | grep -c '^worktree ')
      state="클론 있음 (워크트리 $((wt > 0 ? wt - 1 : 0))개)"
    elif [[ -e "$dest" ]]; then
      state="✗ 경로가 있으나 git 레포가 아니다"
    else
      state="✗ 클론 없음 — 'scripts/repo.sh restore $n' 으로 복구하라"
    fi
    local hroot="없음 — 'scripts/repo.sh apply $n' 이 쓴다"
    [[ -f "$ROOT_FILE" ]] && hroot="$(head -1 "$ROOT_FILE")"
    local br chk
    br="$(hfield_soft "$n" default_branch)"; chk="$(hfield_soft "$n" check)"
    [[ -f "$(harness_json "$n")" ]] || { br="✗ $(harness_json "$n") 없음"; chk="$br"; }
    printf '%s\n  url:   %s\n  브랜치: %s\n  check: %s\n  경로:  %s — %s\n  하네스 루트: %s\n' \
      "$n" "$(field_of "$n" url)" "$br" "$chk" "$dest" "$state" "$hroot"
  done < <(jq -r '.repos[].name' "$MANIFEST")
}

cmd_apply() {
  local name="${1:-}"
  [[ -n "$name" ]] || die "사용법: scripts/repo.sh apply <이름>"
  has_repo "$name" || die "'$name' 이 $MANIFEST 에 없다"
  echo "apply: $name"
  apply_root "$name"
}

# 등록만 해제한다. 클론은 지우지 않는다 — 커밋되지 않은 작업이 남아 있을 수 있고,
# 디렉토리 삭제는 사람이 내용을 보고 판단할 일이다.
cmd_remove() {
  local name="${1:-}"
  [[ -n "$name" ]] || die "사용법: scripts/repo.sh remove <이름>"
  [[ -f "$MANIFEST" ]] || die "$MANIFEST 이 없다"
  has_repo "$name" || die "'$name' 이 $MANIFEST 에 없다"

  # 지우기 전에 url 을 보여준다 — 재등록에 필요한 것은 그것뿐이다(게이트 명령은 대상 레포가 소유하므로
  # 등록 해제로 유실되지 않는다).
  echo "해제 전 값 (재등록에 필요하면 복사하라):"
  echo "  url:       $(field_of "$name" url)"
  echo "  게이트:    $(harness_json "$name") — 대상 레포가 소유한다 (해제해도 남는다)"

  local lock="$MANIFEST.lock"
  mkdir "$lock" 2>/dev/null || die "$MANIFEST 갱신이 이미 진행 중이다 ($lock). 잔존물이면 지우고 재실행하라"
  local tmp="$MANIFEST.tmp.$$"
  if jq --arg n "$name" '.repos |= map(select(.name != $n))' "$MANIFEST" > "$tmp"; then
    mv "$tmp" "$MANIFEST"; rmdir "$lock"
  else
    rm -f "$tmp"; rmdir "$lock"; die "$MANIFEST 갱신 실패 (jq 오류)"
  fi
  echo "등록 해제: $name ($MANIFEST)"
  local dest; dest="$(clone_path "$name")"
  [[ -e "$dest" ]] && echo "클론은 남겨둔다: $dest  (필요하면 직접 지워라)"
  return 0
}

# 등록부는 있는데 클론이 없는 레포를 다시 클론한다 — 새 머신에서 하네스를 이어받는 경로.
# 기본 브랜치는 등록부에서 읽지 않는다: 그 값은 클론 안의 .harness.json 에 있고 클론하기 전에는
# 읽을 자리가 없다. origin/HEAD 에서 탐지한다 — 실물이 원본이다.
# 인자 없이 부르면 클론 없는 레포 전부를 복구한다.
cmd_restore() {
  local only="${1:-}"
  [[ -f "$MANIFEST" ]] || die "$MANIFEST 이 없다"

  local n url dest restored=0 skipped=0 fail=0
  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    [[ -n "$only" && "$n" != "$only" ]] && continue
    dest="$(clone_path "$n")"
    if git -C "$dest" rev-parse --git-dir >/dev/null 2>&1; then
      skipped=$((skipped + 1)); continue
    fi
    url="$(field_of "$n" url)"
    [[ -n "$url" ]] || { echo "오류: '$n' 의 url 이 등록부에 없다" >&2; fail=1; continue; }
    echo "restore: $n"
    # ensure_clone 의 die 는 exit 1 이라 그대로 부르면 스크립트 전체가 죽어
    # "일부 실패해도 나머지 진행" 이 무효가 된다 — 서브셸로 exit 을 격리한다.
    if ! ( ensure_clone "$n" "$url" "" ); then fail=1; continue; fi
    restored=$((restored + 1))
  done < <(jq -r '.repos[].name' "$MANIFEST")

  [[ -n "$only" ]] && ! has_repo "$only" && die "'$only' 이 $MANIFEST 에 없다"
  echo "복구 $restored · 이미 있음 $skipped"
  [[ "$fail" -eq 0 ]] || exit 1
}

case "${1:-help}" in
  add)     shift; cmd_add "$@" ;;
  check)   shift; cmd_check "${1:-}" ;;
  restore) shift; cmd_restore "${1:-}" ;;
  apply)   shift; cmd_apply "${1:-}" ;;
  list)    shift; cmd_list ;;
  remove)  shift; cmd_remove "${1:-}" ;;
  help|-h|--help) sed -n '4,11p' "$PLUGIN_ROOT/scripts/repo.sh" | sed 's/^# \{0,1\}//' ;;
  *) die "알 수 없는 명령: ${1:-} (add | check | restore | apply | list | remove | help)" ;;
esac
