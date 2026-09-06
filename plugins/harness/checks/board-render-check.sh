#!/usr/bin/env bash
# 게이트: scripts/board.sh 의 **0건 판정**을 픽스처로 단언한다.
#
#   닫힌 스프린트 0건 → rc 0 + 빈 표 index.md   ·   닫힌 스프린트 N건 → rc 0
#   활성 스프린트 0건 → rc≠0                    ·   활성 스프린트 N건 → rc 0
#
# 왜 별도 검사인가: board-check.sh 는 **원장의 구조**를 보고 투영을 보지 않는다(그 파일 머리).
# 여기서 보는 것은 렌더러의 판정이라 그 경계를 넘지 않는다.
#
# 왜 픽스처인가: 실 원장은 스프린트마다 항목 수가 계속 바뀌어 네 경우를 동시에 만들 수 없고,
# 네트워크에 기대면 커밋 게이트가 원격 상태에 흔들린다. 가짜 gh 로 이슈 집합을 고정한다 —
# 판정 대상은 board.sh 의 분기이지 gh 의 동작이 아니다(gh 자체는 ledger-adapter-check 가 본다).
#
# set -e 를 쓰지 않는다 — 첫 실패에서 죽으면 나머지 경우의 결과가 보고되지 않는다.
set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BOARD="$PLUGIN_ROOT/scripts/board.sh"
command -v jq >/dev/null 2>&1 || { echo "✗ jq 가 없다 — 이 검사는 jq 없이 판정할 수 없다" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail=0
step() {
  local label="$1"; shift
  if "$@"; then echo "  ✓ ${label}"; else echo "  ✗ FAILED: ${label}"; fail=1; fi
}

# ── 픽스처 루트 ───────────────────────────────────────────────────────
ROOT="$TMP/root"; mkdir -p "$ROOT"
cat > "$ROOT/repos.json" <<'EOF'
{"repos":[{"name":"harness","url":"https://github.com/juhyeon-cha/harness.git","default_branch":"master","check":"true","bootstrap":""}]}
EOF
printf '{"backend":"github","owner":"juhyeon-cha","project":4}\n' > "$ROOT/ledger.json"
# 등록부 파일(rails.json·sprints.json)을 두지 않는다 — board.sh 는 이제 어댑터의 rails·sprints 로
# 읽는다. 파일이 없는 루트에서 아래 다섯 경우가 다 서는 것이 그 전환의 증거다.

# 가짜 gh — 두 질의에 답한다.
#   ① 이슈: 한 건만 낸다. 그 이슈가 어느 스프린트에 붙는지는 FAKE_SPRINT 가 정한다.
#      rail:r1 의 owner 는 이 epic 의 assignee 에서 나온다 (github 백엔드의 rails).
#   ② Projects v2 ITERATION 필드: 2026-S01 닫힘 · 2026-S02 활성 — 이 검사가 가르는 유일한 축이다.
# 두 질의 다 `gh api graphql` 이라 $1 $2 로는 안 갈린다. 스프린트 질의에만 있는 projectV2 로 가른다
# (이슈 질의의 프로젝트 필드는 projectItems 다 — ledger-github.sh 의 PROJECT_FIELD).
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'FAKE'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status") exit 0 ;;
  "api graphql")
    if [[ "$*" == *projectV2* ]]; then
      printf '{"data":{"user":{"projectV2":{"fields":{"nodes":[{},{"configuration":{"iterations":[{"title":"2026-S02"}],"completedIterations":[{"title":"2026-S01"}]}}]}}}}}'
      exit 0
    fi
    printf '[{"data":{"repository":{"issues":{"nodes":[{"id":"NODE_1","databaseId":1001,"number":1,"title":"픽스처 스토리","state":"OPEN","body":"본문","createdAt":"2026-09-06T00:00:00Z","updatedAt":"2026-09-06T00:00:00Z","closedAt":null,"repository":{"name":"harness"},"labels":{"nodes":[{"name":"type:epic"},{"name":"repo:harness"},{"name":"rail:r1"},{"name":"slug:fx-story"},{"name":"sprint:%s"}]},"assignees":{"nodes":[{"login":"juhyeon-cha"}]},"comments":{"nodes":[]},"parent":null,"blockedBy":{"totalCount":0,"nodes":[]},"projectItems":{"nodes":[{"project":{"number":4}}]}}]}}}}]' "$FAKE_SPRINT"
    exit 0 ;;
esac
echo "fake gh: 모르는 호출 $*" >&2; exit 1
FAKE
chmod +x "$TMP/bin/gh"

# render <스토리가 붙은 스프린트> <그릴 스프린트> — RC 와 OUT_DIR 을 채운다.
render() {
  FAKE_SPRINT="$1" PATH="$TMP/bin:$PATH" HARNESS_ROOT="$ROOT" bash "$BOARD" "$2" >"$TMP/out" 2>"$TMP/err"
  RC=$?
  OUT_DIR="$ROOT/docs/sprints/$2"
}
rows() { # 렌더된 index.md 의 스토리 행 수 (표 머리 2줄 제외)
  grep -c '^| \[' "$1/index.md" 2>/dev/null || true
}

echo "── board.sh 0건 판정 — 닫힌 스프린트 예외 ──"

# ① 닫힌 스프린트 · 0건 — 스토리는 활성 쪽에 있다. 이전이 열린 항목만 옮기므로 실제로 나는 모양이다.
render 2026-S02 2026-S01
step "닫힌 스프린트 0건 → rc 0" [ "$RC" -eq 0 ]
step "닫힌 스프린트 0건 → 빈 표 index.md 를 낸다 (표 머리는 있고 스토리 행은 0)" \
  bash -c '[ -f "$1/index.md" ] && grep -q "^| 스토리 | bead |" "$1/index.md" && [ "$(grep -c "^| \[" "$1/index.md")" -eq 0 ]' _ "$OUT_DIR"

# ② 닫힌 스프린트 · N건 — 완화가 닫힌 스프린트의 정상 렌더까지 망가뜨리지 않았는가.
render 2026-S01 2026-S01
step "닫힌 스프린트 N건 → rc 0 이고 스토리 행이 있다" \
  bash -c '[ "$1" -eq 0 ] && [ "$(grep -c "^| \[" "$2/index.md")" -eq 1 ]' _ "$RC" "$OUT_DIR"

# ③ 활성 스프린트 · 0건 — 완화가 여기까지 새면 안 된다. 진행 중인 스프린트가 비어 보이는 것은
#    라벨 누락이나 질의 어긋남이고, 그것이 이 규칙이 애초에 잡으려던 오진이다.
render 2026-S01 2026-S02
step "활성 스프린트 0건 → rc≠0 (완화가 여기로 새지 않는다)" [ "$RC" -ne 0 ]
step "활성 스프린트 0건의 stderr 가 등록부의 status 를 든다" \
  bash -c 'grep -q "스프린트 등록부의 status" "$1"' _ "$TMP/err"

# ④ 활성 스프린트 · N건 — 평시 경로.
render 2026-S02 2026-S02
step "활성 스프린트 N건 → rc 0 이고 스토리 행이 있다" \
  bash -c '[ "$1" -eq 0 ] && [ "$(grep -c "^| \[" "$2/index.md")" -eq 1 ]' _ "$RC" "$OUT_DIR"

# ⑤ 등재 없는 스프린트 — "모르면 닫힌 것으로 친다" 가 아니다. 예외가 규칙을 삼키지 않는지 본다.
render 2026-S02 2026-S09
step "등록부에 없는 스프린트 0건 → rc≠0 (모르는 것을 닫힌 것으로 치지 않는다)" [ "$RC" -ne 0 ]

if [ "$fail" -ne 0 ]; then
  echo "✗ board 렌더 검사 실패 — 위 ✗ 항목" >&2
  exit 1
fi
echo "✓ board 렌더 검사 통과 — 닫힌 스프린트 0건 통과 · 활성 스프린트 0건 실패 · 등재 없는 스프린트 실패"
