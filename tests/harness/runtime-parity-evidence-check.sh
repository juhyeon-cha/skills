#!/usr/bin/env bash
set -euo pipefail
node "$(dirname "$0")/runtime-parity-evidence-check.mjs" "$@"
