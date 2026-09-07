#!/usr/bin/env bash
# 릴리스의 기계 부분. 사용: bash scripts/release.sh <플러그인> <patch|minor|major>
#
# 판단은 사람(또는 /release 스킬)이 하고 이 스크립트는 그 뒤만 한다.
#   사람 — 이전 태그부터 훑기 · 폭 결정 · CHANGELOG 항목 본문 작성
#   여기 — 다음 버전 계산 → 전제 확인 → plugin.json 버전 갱신 → validate → 커밋 → 로컬 태그
#
# **CHANGELOG 항목은 미리 쓰여 있어야 한다.** 최상단 헤딩이 `## <다음 버전> — YYYY-MM-DD` 가
# 아니면 아무것도 바꾸지 않고 죽는다 — 버전만 오르고 항목이 없는 릴리스를 막는 자리다.
#
# 되돌리기: 상태를 바꾸는 단계는 셋이고 순서가 곧 롤백 설계다.
#   (1) plugin.json 버전 갱신 → validate 가 실패하면 **원본으로 되돌리고** rc 1. 남는 변경이 없다.
#   (2) 커밋 → 실패하면 스테이징이 남는다. 무엇이 스테이징됐는지 출력하고 rc 1.
#   (3) 태그 → 실패하면 커밋은 남아 있다. 그 사실과 수동 태그 명령을 출력하고 rc 1.
# 전제 확인은 전부 (1) 앞에 모아 둔다 — 그래야 흔한 실패가 아무것도 남기지 않는다.
#
# 태그 push 와 GitHub 릴리스 발행은 하지 않는다. 명시 지시가 있을 때 손으로 한다.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || { echo "✗ 레포 루트로 이동하지 못했다" >&2; exit 1; }

NAME="${1:-}"
BUMP="${2:-}"
usage() { echo "사용: bash scripts/release.sh <플러그인> <patch|minor|major>" >&2; }

# ── 전제 확인 (여기서는 아무것도 바꾸지 않는다) ────────────────────────
[ -n "$NAME" ] && [ -n "$BUMP" ] || { usage; exit 1; }

case "$BUMP" in
  patch|minor|major) ;;
  *) echo "✗ 폭은 patch·minor·major 중 하나다 — 받은 값: $BUMP" >&2; usage; exit 1 ;;
esac

MANIFEST="plugins/$NAME/.claude-plugin/plugin.json"
CHANGELOG="plugins/$NAME/CHANGELOG.md"
[ -f "$MANIFEST" ] || { echo "✗ $MANIFEST 이 없다 — 플러그인 이름이 맞는가" >&2; exit 1; }
[ -f "$CHANGELOG" ] || { echo "✗ $CHANGELOG 이 없다" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || { echo "✗ jq 가 없다 (brew install jq)" >&2; exit 1; }
command -v claude >/dev/null 2>&1 || { echo "✗ claude 가 없다 — validate 를 돌릴 수 없다" >&2; exit 1; }

CUR=$(jq -r '.version // empty' "$MANIFEST")
case "$CUR" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "✗ $MANIFEST 의 version 이 semver 가 아니다 — 읽은 값: '$CUR'" >&2; exit 1 ;;
esac

IFS=. read -r MA MI PA <<EOF
$CUR
EOF
case "$BUMP" in
  major) NEXT="$((MA + 1)).0.0" ;;
  minor) NEXT="$MA.$((MI + 1)).0" ;;
  patch) NEXT="$MA.$MI.$((PA + 1))" ;;
esac
TAG="$NAME-v$NEXT"

# CHANGELOG 최상단 헤딩 — 버전과 날짜 형식을 함께 본다. 항목 본문은 사람이 쓴 것을 믿는다.
HEAD_LINE=$(grep -m1 '^## ' "$CHANGELOG" || true)
WANT="## $NEXT — "
case "$HEAD_LINE" in
  "$WANT"[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *)
    echo "✗ $CHANGELOG 의 첫 항목 헤딩이 이번 릴리스의 것이 아니다" >&2
    echo "  기대: '## $NEXT — YYYY-MM-DD'" >&2
    echo "  실제: '${HEAD_LINE:-(## 로 시작하는 줄이 없다)}'" >&2
    echo "  항목을 먼저 쓴다 — 폭 판단을 첫 줄에, 설치본이 받는 것을 본문에." >&2
    exit 1 ;;
esac

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "✗ 태그 $TAG 가 이미 있다 — 폭을 잘못 골랐거나 이미 릴리스했다" >&2
  exit 1
fi

if ! git diff --cached --quiet; then
  echo "✗ 스테이징된 변경이 있다 — 릴리스 커밋에 섞인다. 먼저 커밋하거나 되돌려라" >&2
  git diff --cached --name-only >&2
  exit 1
fi

echo "· $NAME $CUR → $NEXT ($BUMP), 태그 $TAG"

# ── (1) 버전 갱신 · validate ──────────────────────────────────────────
BACKUP=$(mktemp) || { echo "✗ 임시 파일을 만들지 못했다" >&2; exit 1; }
cp "$MANIFEST" "$BACKUP"
restore() { cp "$BACKUP" "$MANIFEST"; rm -f "$BACKUP"; }

if ! jq --arg v "$NEXT" '.version = $v' "$BACKUP" > "$MANIFEST"; then
  restore
  echo "✗ plugin.json 버전 갱신에 실패했다 — 원본으로 되돌렸다" >&2
  exit 1
fi

vfail=0
for t in . "./plugins/$NAME"; do
  if out=$(claude plugin validate "$t" --strict 2>&1); then
    echo "✓ validate $t"
  else
    printf '%s\n' "$out" >&2
    echo "✗ validate $t 실패" >&2
    vfail=1
  fi
done
if [ "$vfail" -ne 0 ]; then
  restore
  echo "✗ validate 가 실패해 plugin.json 을 원본($CUR)으로 되돌렸다 — 커밋도 태그도 하지 않았다" >&2
  exit 1
fi
rm -f "$BACKUP"

# ── (2) 커밋 ──────────────────────────────────────────────────────────
# README 와 marketplace.json 은 description 이 바뀐 릴리스에서만 실제로 변한다 — 안 변했으면 무해하다.
git add "plugins/$NAME" README.md .claude-plugin/marketplace.json || {
  echo "✗ git add 에 실패했다" >&2; exit 1; }

if ! git commit -m "chore($NAME): release $NEXT"; then
  echo "✗ 커밋에 실패했다. 스테이징이 남아 있다:" >&2
  git diff --cached --name-only >&2
  exit 1
fi
COMMIT=$(git rev-parse --short HEAD)

# ── (3) 로컬 태그 ─────────────────────────────────────────────────────
if ! git tag "$TAG"; then
  echo "✗ 태그 $TAG 를 붙이지 못했다. 커밋 $COMMIT 은 남아 있다 — 고친 뒤 'git tag $TAG' 를 손으로 붙여라" >&2
  exit 1
fi

echo "✓ $NAME $NEXT — 커밋 $COMMIT · 로컬 태그 $TAG"
echo "  태그 push 와 GitHub 릴리스 발행은 하지 않았다. 명시 지시가 있을 때 손으로 한다."
