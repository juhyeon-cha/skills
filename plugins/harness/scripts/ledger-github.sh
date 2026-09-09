#!/usr/bin/env bash
# Legacy transport; policy and backend implementations have one Node source.
set -u
: "${LEDGER_ROOT:?call through the ledger frontend}"
exec node "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ledger.mjs" --root "$LEDGER_ROOT" "$@"
