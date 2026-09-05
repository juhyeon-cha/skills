#!/usr/bin/env bash
# SessionStart: inject session-context.md (the always-on harness block) as additionalContext.
# JSON escaping is done with sed/awk only — the hook must emit valid JSON without jq.
set -u
md="$(dirname "$0")/session-context.md"
tab=$(printf '\t')
body=$(sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$tab/\\\\t/g" -e 's/\r$//' "$md" | awk '{printf "%s\\n", $0}')
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$body"
