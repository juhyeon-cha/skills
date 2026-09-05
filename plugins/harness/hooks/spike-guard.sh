#!/usr/bin/env bash
# PreToolUse probe: deny (rc=2) when the command carries HARNESS_SPIKE_DENY.
. "$(dirname "$0")/spike-log.sh"
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null)
case "$cmd" in
  *HARNESS_SPIKE_DENY*)
    echo "SPIKE-DENY: command carries HARNESS_SPIKE_DENY" >&2
    exit 2
    ;;
esac
exit 0
