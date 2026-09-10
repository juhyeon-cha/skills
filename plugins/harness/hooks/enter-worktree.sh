#!/usr/bin/env bash
# Claude PostToolUse transport; Git membership and lifecycle live in workspace.mjs.
set -uo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
command -v node >/dev/null 2>&1 || { echo "원장 배선 실패 — node 없음" >&2; exit 2; }
exec node "$PLUGIN_ROOT/scripts/workspace.mjs" hook-enter
