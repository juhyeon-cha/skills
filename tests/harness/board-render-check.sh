#!/usr/bin/env bash
# 게이트: scripts/board.sh 의 두 갈래를 픽스처로 단언한다.
#
#   ① UI 를 갖는 백엔드(github·notion) → 아무 파일도 만들지 않고 rc 0 이며, 무엇을 하지 않았는지 말한다
#   ② UI 가 없는 백엔드(beads) → 종전의 **0건 판정** 그대로다:
#        닫힌 스프린트 0건 → rc 0 + 빈 표 index.md   ·   닫힌 스프린트 N건 → rc 0
#        활성 스프린트 0건 → rc≠0                    ·   활성 스프린트 N건 → rc 0
#        등재 없는 스프린트 0건 → rc≠0
#
# ② 를 beads 픽스처로 도는 이유: 0건 판정은 **렌더에 들어간 뒤**의 분기라, UI 를 갖는 백엔드에서는
# 도달 자체가 불가능해졌다(①). 종전 이 검사는 github 픽스처로 그 분기를 봤고, 그대로 두면 검사가
# 통째로 ① 만 보게 된다 — 판정이 사라진 것을 통과로 읽지 않으려고 렌더가 실제로 도는 백엔드로 옮긴다.
#
# 왜 별도 검사인가: board-check.sh 는 **원장의 구조**를 보고 투영을 보지 않는다(그 파일 머리).
# 여기서 보는 것은 렌더러의 판정이라 그 경계를 넘지 않는다.
#
# 왜 픽스처인가: 실 원장은 스프린트마다 항목 수가 계속 바뀌어 다섯 경우를 동시에 만들 수 없고,
# 네트워크·설치본에 기대면 커밋 게이트가 그 상태에 흔들린다. 가짜 gh·가짜 bd 로 이슈 집합을
# 고정한다 — 판정 대상은 board.sh 의 분기이지 gh·bd 의 동작이 아니다(그 둘은 ledger-adapter-check 가 본다).
#
# set -e 를 쓰지 않는다 — 첫 실패에서 죽으면 나머지 경우의 결과가 보고되지 않는다.
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../plugins/harness" && pwd)"
BOARD="$PLUGIN_ROOT/scripts/board.sh"
command -v jq >/dev/null 2>&1 || { echo "✗ jq 가 없다 — 이 검사는 jq 없이 판정할 수 없다" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail=0
step() {
  local label="$1"; shift
  if "$@"; then echo "  ✓ ${label}"; else echo "  ✗ FAILED: ${label}"; fail=1; fi
}

# ── ① UI 를 갖는 백엔드 — 렌더하지 않는다 ────────────────────────────
# 백엔드에 닿지 않는다: 어댑터의 has-ui 는 gh 검사·토큰 검사 앞에 있는 상수라, PATH 에 gh 가
# 없고 NOTION_TOKEN 이 없어도 답한다. 그래서 이 절은 가짜 명령을 하나도 두지 않는다 —
# **원장에 닿지 않고 끝난다는 것 자체가 단언의 일부다.**
echo "── ① UI 를 갖는 백엔드 — board.sh 가 그리지 않는다 ──"

noop_case() { # noop_case <이름> <.harness.json 본문>
  local name="$1" cfg="$2" root="$TMP/ui-$1" rc
  mkdir -p "$root"
  printf '%s\n' "$cfg" > "$root/.harness.json"
  HARNESS_ROOT="$root" bash "$BOARD" all >"$TMP/out" 2>"$TMP/err"
  rc=$?
  step "$name: rc 0" [ "$rc" -eq 0 ]
  step "$name: docs/ 아래에 아무것도 만들지 않았다" [ ! -e "$root/docs" ]
  step "$name: 무엇을 하지 않았는지 말한다 (조용한 통과가 아니다)" \
    bash -c 'grep -q "그리지 않았다" "$1" && grep -q "docs/sprints/" "$1"' _ "$TMP/out"
}

noop_case github '{"ledger":{"backend":"github","owner":"juhyeon-cha","project":4}}'
noop_case notion '{"ledger":{"backend":"notion","database_id":"fx"}}'

# 대상이 all 만이 아니다 — 개별 대상도 같이 no-op 이어야 docs/ 가 부분적으로 서지 않는다.
UIROOT="$TMP/ui-github"
for t in 2026-S01 backlog adr; do
  HARNESS_ROOT="$UIROOT" bash "$BOARD" "$t" >"$TMP/out" 2>"$TMP/err"; RC=$?
  step "github: '$t' 도 rc 0 · 산출물 없음" \
    bash -c '[ "$1" -eq 0 ] && [ ! -e "$2/docs" ]' _ "$RC" "$UIROOT"
done

# 대상 형식 위반은 여전히 실패다 — no-op 이 인자 검증까지 삼키면 오타가 성공으로 읽힌다.
HARNESS_ROOT="$UIROOT" bash "$BOARD" 2026-XX >/dev/null 2>&1; RC=$?
step "github: 대상 형식 위반은 no-op 이 삼키지 않는다 (rc≠0)" [ "$RC" -ne 0 ]

# ── ② UI 가 없는 백엔드 — 0건 판정 ───────────────────────────────────
echo "── ② board.sh 0건 판정 (beads) — 닫힌 스프린트 예외 ──"

ROOT="$TMP/root"; mkdir -p "$ROOT"
printf '{"ledger":{"backend":"beads"}}\n' > "$ROOT/.harness.json"
# beads 백엔드에서 등록부의 원본은 이 두 파일이다(어댑터가 그렇게 답한다 — ledger-beads.sh).
# 2026-S01 닫힘 · 2026-S02 활성 — 이 검사가 가르는 유일한 축이다.
printf '{"rails":{"r1":{"owner":"juhyeon-cha"}}}\n' > "$ROOT/rails.json"
printf '{"sprints":{"2026-S01":{"status":"closed"},"2026-S02":{"status":"active"}}}\n' > "$ROOT/sprints.json"

# 가짜 bd — 이슈 한 건만 낸다. 그 이슈가 어느 스프린트에 붙는지는 FAKE_SPRINT 가 정한다.
# 출력 형태는 `bd list --all --json` 의 것(어댑터가 그 위에 actor 한 겹만 얹는다).
mkdir -p "$TMP/bin"
cat > "$TMP/bin/bd" <<'FAKE'
#!/usr/bin/env bash
# -C <루트> 를 건너뛰고 하위 명령만 본다.
[ "${1:-}" = "-C" ] && shift 2
case "${1:-}" in
  list)
    printf '[{"id":"fx-1","issue_type":"epic","status":"open","title":"픽스처 스토리","description":"본문","notes":null,"acceptance_criteria":null,"close_reason":null,"parent":null,"assignee":"juhyeon-cha","labels":["type:epic","repo:harness","rail:r1","slug:fx-story","sprint:%s"],"dependencies":[]}]' "$FAKE_SPRINT"
    exit 0 ;;
esac
echo "fake bd: 모르는 호출 $*" >&2; exit 1
FAKE
chmod +x "$TMP/bin/bd"

# render <스토리가 붙은 스프린트> <그릴 스프린트> — RC 와 OUT_DIR 을 채운다.
render() {
  FAKE_SPRINT="$1" PATH="$TMP/bin:$PATH" HARNESS_ROOT="$ROOT" bash "$BOARD" "$2" >"$TMP/out" 2>"$TMP/err"
  RC=$?
  OUT_DIR="$ROOT/docs/sprints/$2"
}

# ⓐ 닫힌 스프린트 · 0건 — 스토리는 활성 쪽에 있다. 이전이 열린 항목만 옮기므로 실제로 나는 모양이다.
render 2026-S02 2026-S01
step "닫힌 스프린트 0건 → rc 0" [ "$RC" -eq 0 ]
step "닫힌 스프린트 0건 → 빈 표 index.md 를 낸다 (표 머리는 있고 스토리 행은 0)" \
  bash -c '[ -f "$1/index.md" ] && grep -q "^| 스토리 | bead |" "$1/index.md" && [ "$(grep -c "^| \[" "$1/index.md")" -eq 0 ]' _ "$OUT_DIR"

# ⓑ 닫힌 스프린트 · N건 — 완화가 닫힌 스프린트의 정상 렌더까지 망가뜨리지 않았는가.
render 2026-S01 2026-S01
step "닫힌 스프린트 N건 → rc 0 이고 스토리 행이 있다" \
  bash -c '[ "$1" -eq 0 ] && [ "$(grep -c "^| \[" "$2/index.md")" -eq 1 ]' _ "$RC" "$OUT_DIR"

# ⓒ 활성 스프린트 · 0건 — 완화가 여기까지 새면 안 된다. 진행 중인 스프린트가 비어 보이는 것은
#    라벨 누락이나 질의 어긋남이고, 그것이 이 규칙이 애초에 잡으려던 오진이다.
render 2026-S01 2026-S02
step "활성 스프린트 0건 → rc≠0 (완화가 여기로 새지 않는다)" [ "$RC" -ne 0 ]
step "활성 스프린트 0건의 stderr 가 등록부의 status 를 든다" \
  bash -c 'grep -q "스프린트 등록부의 status" "$1"' _ "$TMP/err"

# ⓓ 활성 스프린트 · N건 — 평시 경로.
render 2026-S02 2026-S02
step "활성 스프린트 N건 → rc 0 이고 스토리 행이 있다" \
  bash -c '[ "$1" -eq 0 ] && [ "$(grep -c "^| \[" "$2/index.md")" -eq 1 ]' _ "$RC" "$OUT_DIR"

# ⓔ 등재 없는 스프린트 — "모르면 닫힌 것으로 친다" 가 아니다. 예외가 규칙을 삼키지 않는지 본다.
render 2026-S02 2026-S09
step "등록부에 없는 스프린트 0건 → rc≠0 (모르는 것을 닫힌 것으로 치지 않는다)" [ "$RC" -ne 0 ]

if [ "$fail" -ne 0 ]; then
  echo "✗ board 렌더 검사 실패 — 위 ✗ 항목" >&2
  exit 1
fi
echo "✓ board 렌더 검사 통과 — ① github·notion 무동작(산출물 0 · 사유 한 줄 · 형식 위반은 여전히 실패) · ② beads 0건 판정(닫힘 통과 · 활성 실패 · 미등재 실패)"
