#!/usr/bin/env bash
# M0 spike (harness-lzs3.1.2): open nested `claude -p` sessions with the plugin
# loaded and measure three premises.
#   (a) PreToolUse hook rc=2 blocks a Bash command carrying HARNESS_SPIKE_DENY
#   (b) SessionStart additionalContext is quotable by the session
#   (c) agent_type carried by the PreToolUse payload for a plugin agent (printed, not judged)
# rc=0 when (a) and (b) hold, rc=1 otherwise, rc=3 when claude or auth is missing.
set -u
plugin=$(cd "$(dirname "$0")/.." && pwd)
log="$HOME/.claude/plugins/data/harness/spike.log"
work=$(mktemp -d)

command -v claude >/dev/null 2>&1 || { echo "rc=3: claude not on PATH"; exit 3; }
claude auth status 2>/dev/null | jq -e '.loggedIn == true' >/dev/null 2>&1 || { echo "rc=3: claude not authenticated (claude auth status)"; exit 3; }

rm -f "$log"

# $1 label, $2 allowed tools, $3 prompt → stream-json in $work/$1.jsonl, digest on stdout
run() {
  echo "=== $1"
  claude -p --plugin-dir "$plugin" --allowedTools "$2" --max-turns 6 \
    --output-format stream-json --verbose "$3" </dev/null >"$work/$1.jsonl" 2>"$work/$1.err"
  echo "claude rc=$?"
  jq -r '
    select(.type=="assistant" or .type=="user") | .message.content[]? |
    if .type=="text" then "text: \(.text)"
    elif .type=="tool_use" then "tool_use: \(.input|tostring)"
    elif .type=="tool_result" then "tool_result: \(.content|tostring)"
    else empty end' "$work/$1.jsonl"
  [ -s "$work/$1.err" ] && { echo "stderr:"; cat "$work/$1.err"; }
  return 0
}

fail=0
run a Bash 'Run this exact Bash command and report the tool result verbatim: echo HARNESS_SPIKE_DENY | rev'
# Judge on tool_result blocks only: the model may mention the expected output in
# prose (observed 2026-09-05), but it can appear in a tool_result only if the command ran.
jq -r 'select(.type=="user") | .message.content[]? | select(.type=="tool_result") | .content|tostring' "$work/a.jsonl" >"$work/a.results"
if grep -q 'SPIKE-DENY' "$work/a.results" && ! grep -q 'YNED_EKIPS_SSENRAH' "$work/a.results"; then
  echo "(a) PASS: tool_result carries SPIKE-DENY and no echo output"
else
  echo "(a) FAIL"; fail=1
fi

run b '' 'Your context contains a token that begins with HARNESS_SPIKE_CONTEXT. Reply with that token verbatim, nothing else.'
if grep -q 'HARNESS_SPIKE_CONTEXT:7c1e' "$work/b.jsonl"; then
  echo "(b) PASS: session quoted HARNESS_SPIKE_CONTEXT:7c1e"
else
  echo "(b) FAIL"; fail=1
fi

run c 'Agent,Bash' 'Use the Agent tool with subagent_type "harness:spike-implementer" (fall back to "spike-implementer" if that name is rejected). Reply with the path it reports, nothing else.'
echo "=== (c) PreToolUse payloads with agent_type, from $log"
jq -c 'select(.hook_event_name=="PreToolUse" and .agent_type != null and .agent_type != "") | {agent_type, agent_id, tool_name, cwd}' "$log" 2>/dev/null || echo "(no agent_type lines)"

echo "raw outputs: $work"
exit $fail
