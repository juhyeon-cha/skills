# Bounded local automation

Use this procedure for explicit local code/goal requests and foreground polling of one Git ref.
First create an idle reviewed project with [project setup](project.md). Use the same Python with
the pinned dependencies. `automation.py` is adjacent to `knowledge.py`; it calls the public project
CLI and stores separate state without migrating the project's SQLite database.

This is a local POSIX host workflow. A live agent host must dispatch the returned prompts to real
models, preserve their raw responses, and continue the loop. Python does not invoke a model API,
install a scheduler, receive webhooks, publish remotely or enforce host tool permissions. Check the
host's independent-agent and filesystem/command permissions before initialization. Unavailable
capability remains pending; a synthetic receipt is test evidence only.

## Establish authority and exclusive ownership

Freeze an authority JSON file from the actual user instruction, separate from event configuration:

```json
{
  "reference": "Conversation or decision identifier and the actual approved scope",
  "document_updates": true,
  "implementation": false,
  "checks": []
}
```

For authorized implementation set `implementation` to true and supply the approved mandatory
check argument arrays, for example `[["/absolute/venv/bin/python", "-B", "test_service.py"]]`.
Checks run in the source repository, without shell interpolation, with a 60-second limit each.
Choose commands with safe, repeatable local effects. The host must verify their scope and authority;
the JSON is its attestation, not proof of user identity or a sandbox. Model prompts and event
payloads cannot grant authority. Remote operations have no automation route and require a separate
user-authorized workflow outside this product. Neither a configured check nor model instructions
override host permission checks.

```sh
"$PYTHON" "$SKILL_DIR/scripts/automation.py" --state /absolute/automation init \
  --project /absolute/project-state --authority /absolute/authority.json --ref HEAD
```

Initialization creates an exclusive `.knowledge-automation-owner.json` in the canonical document
root. Every participating automation must honor that permanent claim. A second state/project
targeting the same root is refused, including a symlink alias. The per-state command lock serializes
cooperating processes. Direct `knowledge.py` callers, arbitrary editors, nested document roots,
network filesystems and malicious same-user processes are outside this ownership boundary.
Use disjoint document roots and stop other writers. Reviewed document byte conflicts still fail
without overwriting third-party content. An interrupted initialization preserves its reservation;
inspect it and recover deliberately rather than deleting it to take ownership. State relocation
and migration are unsupported. Keep the original state, project and document paths.

## Submit pinned requests

Write JSON, then run `submit --input /absolute/event.json` with the same `--state`:

```json
{
  "event_id": "delivery-1",
  "request_id": "user-request-1",
  "cause_id": "originating-request-1",
  "kind": "code",
  "revision": "FULL_COMMIT_ID"
}
```

The CLI resolves a revision to an immutable commit at intake. Repeating an event ID requires the
same original bytes semantically; a new delivery with the same request ID must resolve to the same
input. A new user request gets a new request ID even for identical content. Its execution is recorded
separately; already-current effects are checked through the project CLI without another model call.
Use immutable commit IDs rather than moving refs for replayable explicit events.

A goal event uses `kind: "goal"` and adds:

```json
{
  "goal": {
    "id": "retry-behavior",
    "version": "2",
    "text": "Describe the authorized target behavior.",
    "acceptance": ["Describe each required observable result."]
  }
}
```

Keep current `revision` distinct from the target goal. Goal text, version and acceptance are hashed
together. A successor of the same goal ID supersedes pending older work; preserve the earlier
request and results as history. Same-content requests may reuse an implementation only when its
verified revision is still the current baseline and equals the new request's source. Preserve the
cause ID through goal → verified code → document events; repeated current effects then terminate
without repeating implementation or authoring. A cause ID alone never suppresses unrelated work.

Older ancestor code deliveries are historical (`stale`). An intentional rollback sets `rollback:
true` and waits for an actual policy decision; divergence also waits. The question names the source
versions, effect and options. Do not turn a delayed event into rollback by changing its ID or flag.

## Run the host loop

1. Call `next`. It performs supported local project transitions or returns `pending` with the exact
   prompt, its SHA-256, task ID, role and attempt. Persisted tasks make response loss recoverable.
2. For a newly dispatched task invoke the host's actual independent-agent capability with that
   exact prompt. Author, document reviewer, implementer and implementation reviewer must have
   the required separation. Repeated `next` returns the same pending task: query the original host
   call before dispatching again. Task identity is not a lease permitting parallel duplicate calls.
3. Preserve the tool's real actor/call identity, timestamps and raw JSON response in a receipt:

```json
{
  "task_id": "RETURNED_TASK_ID",
  "prompt_sha256": "RETURNED_PROMPT_SHA256",
  "actor": "ACTUAL_RETURNED_ACTOR",
  "host_tool": "ACTUAL_TOOL_NAME",
  "call_id": "ACTUAL_CALL_ID",
  "started_at": "2026-01-01T00:00:00+00:00",
  "finished_at": "2026-01-01T00:00:01+00:00",
  "raw_response": "{\"revision\":\"FULL_COMMIT_ID\"}",
  "response": {"revision": "FULL_COMMIT_ID"}
}
```

4. Call `accept --input /absolute/receipt.json`, then `next` again. The raw response must parse to
   exactly `response`. Preserve surrounding provider output separately if the host extracts JSON;
   do not invent a successful actor or rewrite a failing answer. Receipt fields are host declarations,
   not authenticated provider audit records. Actor inequality checks cannot prove actual independence.
5. Continue until `idle`, `stopped`, or a named wait requiring evidence/authority. Ordinary review
   revisions generate another bounded author/reviewer attempt without a new draft approval.

Author returns the existing [decisions](source-contract.md) object; document reviewer returns the
existing [review response](workflow.md). Implementer commits locally and returns
`{"revision":"FULL_COMMIT_ID"}`. The CLI checks a clean checkout at that revision, ancestry from
the pinned source and actual approved checks. Independent implementation reviewer receives the
goal hash, revisions and raw checks and returns:

```json
{"verdict":"pass","goal_hash":"EXACT_HASH","revision":"EXACT_COMMIT","findings":[]}
```

`revise` requires repair; `blocked` requires evidence or policy. Only a passing exact review after
successful checks makes `implementation_status` verified. `document_status` remains separate:
not_started → draft → applied, or unchanged after public validation. A verified goal does not prove
document application or deployment. A result older than the current baseline never rolls it back.

## Recover, decide and stop

Read `status` and the linked project `status --run` after a lost command response. `next` reconciles
the same public run, including `applying`/`completed`, before another effect. Completion requires
the project's actual document, receipt and baseline checks. Preserve conflicting artifacts.

Report a failed host call using `fail --input` with `task_id`, `class` (model, transport, permission,
or service), concrete `evidence`, and `outcome` (`not_executed` or `unknown`). Preserve malformed
responses and actual host errors outside the successful receipt path. Known-unexecuted model or
transport attempts allow retry up to three attempts per role. Permission/service failures wait for
repair. Unknown outcomes retain the exact pending task: query that call and accept its real result;
do not start a replacement implementation. After repair use `resume --execution EXECUTION_ID`,
then `next`; retries retain the earlier failure evidence and the same execution. Exhausted attempts
remain pending for a new deliberate request or diagnosis, not an unbounded retry loop.

For `policy_wait`/`authority_wait`, inspect `question`, then use
`decision --execution ID --input /absolute/decision.json`. Record `reference` to actual evidence or
the user decision, `choice` from the offered options and, for `provide_evidence_or_decision`, an
`answer`. An ordinary missing-evidence repair can reference existing observed implementation checks
and independent review without asking the user to decide a policy. Only an unresolved policy or new
authorization requires the user. The renewed document review receives this resolution and the
separate implementation evidence; its pass still certifies only the document packet.
The same execution resumes; a policy answer does not count as a passing independent review.
`keep_pending` preserves the target. Implementation authorization is recorded only after the host
checks the real grant. Event payload booleans cannot supply it.
`keep_current` ends that proposed revision as `stale`: it remains in history and does not alter
the current baseline. `superseded` means a newer input displaced work before application;
`completed` reports this execution's separate document/implementation boundaries, not deployment.

`stop` writes an operator control marker independently of the command lock. An already-running
bounded operation may finish; further operations stop at the next boundary. Preserve in-flight
host receipts. `resume` clears the marker; `next` reconciles the same task/run. Killing a model call
or rolling back source/document changes is not part of stop.

## Repeated checks and evidence

Run a real foreground timer with `watch --ticks 12 --interval 5`. Each tick inspects the configured
ref and queues missed revisions, identifies document/baseline drift, missing tracked source files
and pending goals. The live host loop above drains queued work. Watch alone does not execute models
or claim implementation completion. `tick` is a one-shot diagnostic, not evidence of scheduling.
Unchanged findings emit no repeated notification; unchanged sources start no model or document work.
Watch records tick evidence even while quiet. Stop ends the next tick and leaves requests intact.

`status` links events, request/cause/goal identities, tasks, receipts, command intents/results,
actual check output, retries, intervention questions, timings and completion paths. Keep the
automation directory with the project evidence. Use raw host tool records alongside these local
attestations when evaluating actual models; regression fixtures cannot establish service operation.
