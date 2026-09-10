#!/usr/bin/env bash
# Legacy transport; policy and backend implementations have one Node source.
set -u
exec node "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ledger.mjs" "$@"
