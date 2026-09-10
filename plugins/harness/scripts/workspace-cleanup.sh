#!/usr/bin/env bash
# Compatibility CLI. Workspace naming uses lib/worktree-name.sh through the core.
set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
command -v node >/dev/null 2>&1 || { echo "workspace: node 없음" >&2; exit 1; }
exec node "$PLUGIN_ROOT/scripts/workspace.mjs" cleanup "$(pwd -P)" "$@" --legacy-cleanup
