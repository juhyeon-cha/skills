# Run development measurements

Use this procedure when measuring an unreleased toolkit candidate. Read
[README.md](README.md) for prerequisites and measurement boundaries. This is a
repository development tool, not a shipped plugin entry point.

1. Run `runner.py prepare` for the requested case with a new output directory
   outside the checkout. Preserve its returned manifest and frozen runner path.
   Run every remaining command with that frozen runner and the same Python.
2. Run `next --run <absolute directory>`. If it returns `awaiting_agent`, invoke
   the host's actual independent child tool with the exact `prompt` and fresh
   context (`fork_turns: "none"` in Codex). Use a new actor for every task. Keep
   the actual dispatch result and raw final response. When it returns a terminal
   status, proceed to step 5.
3. Write a UTF-8 JSON receipt from the observed tool call. Preserve these fields:

   ```json
   {
     "task": "returned task id",
     "prompt_sha256": "returned prompt hash",
     "actual_prompt": "exact prompt sent",
     "actor": "actual provider-returned canonical child identity",
     "dispatch": {"task_name": "same canonical child identity"},
     "origin": "host-agent-tool",
     "outcome": "completed",
     "response": "raw final response, including any formatting"
   }
   ```

   The current bridge targets Codex collaboration's `task_name` return shape.
   A different provider needs an explicit adapter before its result can be used.
   These are parent-observed declarations, not authenticated provider evidence.
   Do not populate them with fixture responses or a response from another run.
   The document-only readers receive only their returned prompt: do not add
   sources, expected answers, other readers' answers, or conversation history.
   On an actual access/tool failure, use `outcome: "not-executed"` and preserve
   the observed failure in `response`. Never weaken host guards to obtain a pass.
4. Run `accept --run <directory> --receipt <file>`, then return to step 2.
   On validation failure, keep the raw response and inspect the retained command
   logs. Retry identical input after a transient process failure. For a malformed
   model response, preserve the attempt and report it; do not silently rewrite
   its content into a passing result. Source changes require a new prepared run.
5. Run `status --run <directory>` and report its status, actual actors, failures,
   evidence directory, and unverified boundaries. `pass` is case-specific:
   the document case expects negative controls to fail. Keep the full directory
   for reentry and audit. Do not infer host plugin loading, new-session handoff,
   service behavior, or deployment from these results.

If the coordinator stops with an agent task pending, `next` returns that same
work. Recover an already returned response from the host transcript before
launching another actor. Apply steps run after review acceptance is durably
recorded; rerunning `next` resumes the plugin transaction. A failed command can
have committed local side effects, so inspect its logs before retrying.
