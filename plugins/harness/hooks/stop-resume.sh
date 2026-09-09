#!/usr/bin/env bash
# POSIX compatibility transport; the common Node handler owns behavior.
set -uo pipefail
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
command -v node >/dev/null 2>&1 || { echo "UNREACHED: node executable missing" >&2; exit 2; }
exec node "$ROOT/scripts/stop.mjs" "$@"
