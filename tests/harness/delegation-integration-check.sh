#!/usr/bin/env bash
set -euo pipefail
exec node "$(dirname "${BASH_SOURCE[0]}")/delegation-integration-check.mjs" "$@"
