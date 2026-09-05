#!/usr/bin/env bash
# SessionStart probe: inject a token the session can quote back.
. "$(dirname "$0")/spike-log.sh"
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"HARNESS_SPIKE_CONTEXT:7c1e — spike token injected by the harness plugin SessionStart hook. Quote it verbatim when asked."}}'
