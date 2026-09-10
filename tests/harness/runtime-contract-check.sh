#!/usr/bin/env bash
# Offline fixtures only. Real sessions are an explicit, separate probe.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
command -v node >/dev/null 2>&1 || { printf '%s\n' 'UNREACHED: node missing' >&2; exit 1; }
node "$ROOT/tests/harness/runtime-contract-check.mjs" "$@"
