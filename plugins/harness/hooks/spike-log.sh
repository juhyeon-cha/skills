#!/usr/bin/env bash
# Sourced by the spike hooks. Reads the hook payload from stdin into $payload
# and appends it as one line to the spike log. Logging failure never changes
# the hook's verdict.
payload=$(cat)
log_dir="$HOME/.claude/plugins/data/harness"
{ mkdir -p "$log_dir" && printf '%s\n' "$payload" | jq -c . >>"$log_dir/spike.log"; } 2>/dev/null || true
