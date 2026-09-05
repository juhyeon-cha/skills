#!/usr/bin/env bash
# beads 백엔드 — 인자를 그대로 bd 에 넘긴다. ledger.sh 가 부른다(직접 부르지 않는다).
# 원장은 언제나 LEDGER_ROOT 의 것이다: `bd -C "$LEDGER_ROOT"` — 루트에 .beads/redirect 가 있으면
# bd 가 그것을 따라간다(워크트리와 같은 배선).
#
# 여기서 직접 처리하는 것은 둘이다:
#   init          `bd init --prefix <p>`. 그 뒤 원격 배선은 setup 스킬 1.6 의 몫이다 — 원격 반영이라
#                 이 스크립트가 대신 하지 않는다.
#   wire-worktree <워크트리>/.beads/redirect 에 <루트>/.beads 절대 경로를 쓴다 (멱등). 이것이 없으면
#                 워크트리의 bare bd 가 "bd init 으로 새 DB 를 만들라" 고 권하고, 따르면 원장이
#                 이원화된다. 부르는 자리는 hooks/enter-worktree.sh 이고, lib/harness-root.sh 가 이
#                 파일을 둘째 출처로 읽는다. **redirect 를 아는 파일은 이것 하나다.**
set -u
: "${LEDGER_ROOT:?ledger.sh 를 통해 불러라}"

case "${1:-}" in
  init)
    shift
    prefix=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --prefix) prefix="${2:-}"; shift 2 ;;
        *) echo "ledger-beads init: 모르는 인자 '$1' (사용: init --prefix <접두사>)" >&2; exit 1 ;;
      esac
    done
    [ -n "$prefix" ] || { echo "ledger-beads init: --prefix <접두사> 가 필요하다" >&2; exit 1; }
    if [ -d "$LEDGER_ROOT/.beads/embeddeddolt" ]; then
      echo "ledger-beads init: $LEDGER_ROOT/.beads/embeddeddolt 가 이미 있다 — 다시 초기화하지 않는다" >&2
      exit 1
    fi
    exec bd -C "$LEDGER_ROOT" init --prefix "$prefix"
    ;;
  wire-worktree)
    wt="${2:-}"
    [ -n "$wt" ] && [ -d "$wt" ] || { echo "ledger-beads wire-worktree: 실재하는 <워크트리 절대 경로> 가 필요하다 ('${wt}')" >&2; exit 1; }
    mkdir -p "$wt/.beads" && printf '%s\n' "$LEDGER_ROOT/.beads" > "$wt/.beads/redirect" \
      || { echo "ledger-beads wire-worktree: $wt/.beads/redirect 를 쓸 수 없다" >&2; exit 1; }
    echo "$wt/.beads/redirect → $LEDGER_ROOT/.beads"
    exit 0
    ;;
esac

exec bd -C "$LEDGER_ROOT" "$@"
