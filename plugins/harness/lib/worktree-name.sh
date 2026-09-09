#!/usr/bin/env bash
# Legacy transport. Story ID conversion has one Node source.
set -u
exec node "$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/worktree-name.mjs" "$@"
