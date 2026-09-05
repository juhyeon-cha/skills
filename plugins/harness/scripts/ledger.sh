#!/usr/bin/env bash
# 원장 어댑터의 경계. 하위 명령·인자·JSON 키는 bd 와 같다 — 스킬·검사·훅은 `bd -C <루트> …` 를
# `ledger.sh …` 로 바꾸는 것으로 끝난다. 백엔드는 `<하네스루트>/ledger.json` 의 `backend` 하나로
# 정하고, 없으면 rc≠0 이다. **폴백 없음** — 파일이 없다고 조용히 beads 로 가면 원장을 잘못 짚은
# 채로 쓰기가 성공한다.
#
# 사용: ledger.sh <하위 명령> [인자…]      ledger.sh --help
#
# 하네스 루트는 HARNESS_ROOT → lib/harness-root.sh 순서로 찾는다. HARNESS_ROOT 가 있으면 bd 를
# 부르지 않는다(검사가 픽스처를 물리는 통로이고, github·notion 백엔드에는 bd 가 없다).
#
# 백엔드 파일은 같은 디렉토리의 ledger-<backend>.sh 이고 아래 환경 변수로 받는다:
#   LEDGER_ROOT   하네스 루트 절대 경로
#   LEDGER_CONFIG ledger.json 절대 경로
#
# 하위 명령 집합의 출처: 플러그인이 실제 부르는 bd 하위 명령 전수(측정 명령과 결과는 원장
# harness-m8gg.4.1 의 note). 모든 백엔드가 받는 것과 beads 에만 있는 것으로 가른다 — beads 전용
# 명령을 github·notion 에 주면 rc≠0 이다(bd 의 dolt·where 같은 것은 다른 백엔드에 대응물이 없다).
set -u

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BACKENDS="beads github notion"

usage() {
  cat <<'EOF'
사용: ledger.sh <하위 명령> [인자…]   (인자 규약은 bd 와 같다)

모든 백엔드 (beads · github · notion):
  init                       백엔드별 원장 초기화 (setup 이 부른다)
  create <제목> [-t <type>] [-l <라벨,…>] [--parent <id>] [--acceptance <문>] [--body-file <f>|-d <문>] [--silent] [-p <n>]
  show <id> [--json]
  list [-l <라벨,…>] [--label-pattern <glob>] [--status <s,…>] [-t <type>] [--parent <id>] [--all] [-n <N>] [--json]
  ready [-l <라벨,…>] [-t <type>] [-n <N>] [--json]
  children <id> [--json]
  note <id> <본문> | --file <f> | --stdin
  close <id>… [--reason <문>|--reason-file <f>] [--force]
  update <id> [--status <s>] [--claim --actor <값>] [--parent <id>] [-t <type>] [--acceptance <문>]
  dep add <id> <의존 대상 id> | --file - (JSONL {"from","to"})
  label add|remove <id> <라벨>
  wire-worktree <워크트리 절대 경로>   워크트리에 원장을 배선한다 — hooks/enter-worktree.sh 가 부른다
                             (beads: <워크트리>/.beads/redirect · github·notion: 배선할 것이 없다, rc 0)
  sync-check [--push]        원장이 원격과 어긋났는가 — checks/ledger-check.sh 가 부른다
                             (beads: Dolt 원격 대조, --push 면 앞선 커밋 반영 · github·notion: "원격 반영 대상 없음" rc 0)
  help | --help

beads 전용 (github · notion 은 rc≠0):
  delete · edit · tag · search · supersede · remember · notes · counts · batch ·
  export · import · bootstrap · root · sql · dolt · where

이 목록은 플러그인의 bd 호출 전수(grep)에서 파생했다. 그 측정에 섞인 하위 명령 아닌 토큰
(- · --actor · --db · --directory · --dolt-auto-commit · --help · --json · --version · bd · call · do · hands · has · role)은 뺐다.
EOF
}

case "${1:-}" in
  --help|-h|help) usage; exit 0 ;;
  "") usage >&2; exit 1 ;;
esac

if [ -n "${HARNESS_ROOT:-}" ]; then
  ROOT="$HARNESS_ROOT"
else
  ROOT="$(bash "$PLUGIN_ROOT/lib/harness-root.sh")" || exit 1
fi

CFG="$ROOT/ledger.json"
[ -f "$CFG" ] || { echo "ledger: $CFG 이 없다 — 하네스 루트에 ledger.json 을 두어라 ({\"backend\": \"beads|github|notion\"})" >&2; exit 1; }
backend="$(jq -r '.backend // empty' "$CFG" 2>/dev/null)"
case " $BACKENDS " in
  *" $backend "*) ;;
  *) echo "ledger: $CFG 의 backend '$backend' 는 허용값($BACKENDS) 밖이다" >&2; exit 1 ;;
esac

LEDGER_ROOT="$ROOT" LEDGER_CONFIG="$CFG" exec bash "$PLUGIN_ROOT/scripts/ledger-$backend.sh" "$@"
