#!/usr/bin/env bash
# beads 백엔드 — 인자를 그대로 bd 에 넘긴다. ledger.sh 가 부른다(직접 부르지 않는다).
# 원장은 언제나 LEDGER_ROOT 의 것이다: `bd -C "$LEDGER_ROOT"` — 루트에 .beads/redirect 가 있으면
# bd 가 그것을 따라간다(워크트리와 같은 배선).
#
# init 만 여기서 처리한다: `bd init --prefix <p>` 뒤 원격 배선은 setup 스킬 1.6 의 몫이다 —
# 원격 반영이라 이 스크립트가 대신 하지 않는다.
set -u
: "${LEDGER_ROOT:?ledger.sh 를 통해 불러라}"

if [ "${1:-}" = "init" ]; then
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
fi

exec bd -C "$LEDGER_ROOT" "$@"
