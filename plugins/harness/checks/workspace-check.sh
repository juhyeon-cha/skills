#!/usr/bin/env bash
# Read-only workspace identity check on every backend. No ledger or remote access.
set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
command -v node >/dev/null 2>&1 || { echo "workspace: node 없음" >&2; exit 1; }
TARGET="${1:-$(pwd -P)}"
node "$PLUGIN_ROOT/scripts/config.mjs" validate "$TARGET" >/dev/null || exit 1
exec node "$PLUGIN_ROOT/scripts/workspace.mjs" inspect "$TARGET"
