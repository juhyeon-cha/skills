#!/usr/bin/env bash
set -euo pipefail
node "$(cd "$(dirname "$0")" && pwd)/ledger-record-check.mjs"
node "$(cd "$(dirname "$0")" && pwd)/ledger-naming-check.mjs"
