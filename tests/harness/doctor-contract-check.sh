#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
node "$ROOT/tests/harness/doctor-contract-check.mjs" "$@"
