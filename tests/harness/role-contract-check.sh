#!/usr/bin/env bash
# Offline role and actual guard fixtures; live evidence is an explicit optional argument.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
command -v node >/dev/null 2>&1 || { printf '%s\n' 'UNREACHED: node missing' >&2; exit 1; }
node "$ROOT/tests/harness/role-contract-check.mjs" "$@"
node "$ROOT/tests/harness/role-ambiguity-check.mjs"
