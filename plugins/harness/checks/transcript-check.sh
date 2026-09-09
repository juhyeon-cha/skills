#!/bin/bash
# Runtime transcript adapters own parsing; this keeps the existing command entry.
# Exit: 0 reached, 1 A9 violation, 2 any required observation unreached.
set -euo pipefail
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
command -v node >/dev/null 2>&1 || { echo "UNREACHED: node dependency missing" >&2; exit 2; }
exec node "$ROOT/scripts/transcript.mjs" "$@"
