# Runtime observations and ordinary outcomes

`lib/transcripts/` owns format-specific decoding. `lib/transcript.mjs` owns A9 and retrospective aggregation; role names and SIGNAL vocabularies come from the existing role modules and `agents/*.md`. `lib/runtime/workflow.mjs` connects the ordinary session store to `roleCall`/`roleResult`. The ledger remains task state and acceptance authority. A retrospective report never closes work.

## Ordinary native delegation

For the native contract selected in [roles.md](roles.md), use this path before every required implementation/review/evaluation, including a retry. Save the SessionStart `HARNESS_STATE_JSON` object as `scope.json`: `runtime`, `repository`, `sessionId`, and the observed absolute `data` directory. The workflow resolver passes that directory explicitly; hook environment inheritance is unnecessary. Save the registered role receipt and the request described in [roles.md](roles.md), adding a unique `callId`.

```text
node <plugin>/scripts/workflow.mjs begin <scope.json> <registration.json> <request.json>
```

Require exit 0 before native delegation. Begin validates `roleCall`, persists the required invocation, and records the current event-file byte boundary and prefix hash. A missing outcome stays visible in the inventory. Hook absence, a disabled hook, an unknown role and an unfinished invocation cannot turn into an empty successful population.

Invoke the actual registered native role and wait using the runtime's native tool. The orchestrator records what those tools returned in `native-outcome.json`: `nativeCallId`, `sessionId`, `parentAgentId`, `identifier`, `agentId`, `state` and `result`. The common result's `state` can be `completed` only when native wait actually reports completion. `result` is the returned response, including its first line. These values come from native returns, never from a child's summary, prompt text or a guessed identifier.

```text
node <plugin>/scripts/workflow.mjs complete-native <scope.json> <registration.json> <call-id> <native-outcome.json>
```

Completion loads ordinary hook observations after begin. It rejects changed/truncated history, mismatched session/role/instance, interrupted results and different native/hook SIGNALs, and delegates role discipline to `roleResult`. A session-wide completion lock prevents one native call or child instance from satisfying two inventories. Immutable outcome and result records preserve UNREACHED as well as REACHED; a retry needs a fresh call and child through the existing RETRY procedure. Keep the inventory rather than overwriting a failed attempt. A missing or failed result is exit 2; require REACHED before the calling skill handles its signal.

This is local evidence handling, not authentication of native tool returns. The orchestrator owns their provenance. A manually written completed flag does not prove execution, and stored files do not protect against same-user tampering. The hook chain is an additional necessary observation, not a replacement for that responsibility. Raw response bodies are used for validation and are not copied into the outcome store; only identity, status, format and first-line SIGNAL persist there.

## Generic parent observations

For managed generic prompt-only execution selected under [roles.md](roles.md), use
`scripts/delegation.mjs`. It shares the capability decision with doctor; it does not
call the model tool. Parent-supplied observations are a trust boundary, not an
authenticated provider capture or protection against same-user file edits. Keep
the original tool returns locally so a grader can compare their provenance.

1. Save a begin JSON with `version: 1`, `runtime: "codex"`,
   `provider: "collaboration"`, canonical absolute worktree `repository`, normalized
   absolute parent-owned `data`, actual `sessionId` and `parentAgentId`, a new local
   `callId`, `role`, `task`, `sourceHash`, `commitScope`, `implementerIds`,
   `previousAgentIds`, and optional `permission: "prompt-only"` (the default). Optional `modelOptions` follows roles.md. Obtain sourceHash
   from `loadRole(role, pluginRoot).sha256` in `lib/runtime/roles.mjs`. Use the actual
   parent session identity. For guarded execution, take `data` and `sessionId`
   from the active SessionStart context as [roles.md](roles.md) requires; an
   arbitrary inventory directory cannot be discovered by the hook.
   Implementation scope is `{mode: "implementation", base, branch}` with the clean
   starting HEAD. Grader scope is `{mode: "fixed", base, head, branch}` pinned before
   dispatch. Use full commit SHAs. Populate author and earlier child IDs from records.
2. Run `node <plugin>/scripts/delegation.mjs begin <begin.json>`; require rc 0 and
   PENDING. Pass the returned `dispatch.task_name` unchanged to the actual
   `collaboration.spawn_agent` tool, together with the returned model/effort/fork
   options, role instructions and skill delegation message. Model selection is
   owned by [roles.md](roles.md#model-selection). This generated name correlates the request; it is not a native invocation
   ID. Save the actual tool return before waiting.
3. Run `bind <bind.json>` with `{call, observation}`: `call` is begin's exact returned
   call and observation is `{source: "parent-tool-return", tool:
   "collaboration.spawn_agent", value: <actual tool return>}`. Require rc 0 and
   PENDING. The return shape is `{task_name: "/root/<actual child>"}`. Binding reserves
   the child for this invocation. Unlinked reuse or a mismatched child is rejected.
4. After the actual child finishes, run `complete <complete.json>` with `{call, head,
   observation}`. `head` is the actual clean final HEAD; implementation may advance
   to a descendant of base on the same branch, while grader HEAD is fixed. Observation
   is `{source: "parent-tool-return", tool: "collaboration.list_agents", value:
   <actual tool return>}`. The supported return contains `agents` rows with
   `agent_name` and `agent_status`; a completed status is `{completed: <full response>}`.
   Obtain a new completion snapshot after this invocation finishes; never reuse the
   previous turn's completed snapshot. Use the real returned body, not the child's account of a tool result. Require rc 0
   and OBSERVED before handling its signal. Running/interrupted status, missing body,
   wrong SIGNAL, identity/source/commit mismatch and duplicate completion reject.
5. Run `audit <context.json>` with only version, runtime, provider, repository, data,
   sessionId and parentAgentId from the call. It reads every call in this inventory;
   missing, pending and failed attempts remain visible. An empty inventory cannot
   succeed. Audit succeeds when each call is OBSERVED or a valid rejected call has
   an OBSERVED successor through explicit `retryOf` links. Resolved rows retain
   REJECTED and their reason, with `resolvedBy` pointing to the recovery. Pending,
   corrupt, unrelated and unresolved failed calls still fail audit. Audit is an
   execution-history check, not acceptance; an OBSERVED CHANGES_REQUESTED is not LGTM.

All commands take exactly an action and one JSON file. Failed validation returns
nonzero; PENDING is not completion. A retry needs a new call linked with `retryOf: <prior callId>` under the
existing progress/budget rule. The prior call must be terminal, with the same
task, role, repository and base; a fixed head may advance to a descendant.
Unlinked calls cannot resolve a failure. Failed or interrupted execution uses
a fresh child. A completed reviewer can use `reuseChild: true`: begin returns
`dispatch.tool: "collaboration.followup_task"` and the existing task name. Send
the corrected head and earlier findings to that child, then bind with
`observation.tool: "collaboration.followup_task"` and its actual return value
(which may be null). Only one invocation may own that reviewer at a time.
Complete consumes a new response through the same list_agents observation;
old results are never renamed or overwritten. A native-only requirement keeps
its native observation boundary.

Branch, HEAD and cleanliness are checked at begin and complete. Binding and
tool permission checks retain identity and repository checks without repeating
those mutable-tree checks. A result for the wrong or dirty final tree is rejected. Keep all
request/outcome files and the actual observation source for re-entry and grading.
The immutable outcomes store signal and response hash rather than the full body.

This inventory is separate from native workflow records. The retrospective adapter
selects it when the supplied scope contains `provider: "collaboration"`.
`enforcement` and native role evidence remain unavailable; `tools` and `tokens`
remain unknown. Audit OBSERVED does not measure role restrictions, tool counts or
semantic acceptance and does not satisfy the native doctor's live check.

### Cross-session independent evaluator recovery

`retryOf` names a call in the same session. Use `resumeFrom` to reference a failure
in another session. Recovery supports REJECTED evaluator calls with the same
canonical worktree, task, fixed `commitScope` and `implementerIds`. Use the new
session's actual `sessionId` and `parentAgentId` and create a fresh child. Do not
impersonate the old session or copy its inventory. A changed HEAD cannot resolve
the old failure through this contract.

1. Save the previous audit context and call ID as
   `{context: <previous context>, callId: <failed ID>}` and run
   `node <plugin>/scripts/delegation.mjs reference <reference-input.json>`.
   The result contains `sessionId`, `parentAgentId`, `callId`, `callHash`,
   `dispatchHash`, `bindingHash` and `outcomeHash`. Hashes pin the original envelope
   bytes; an absent binding has a null `bindingHash`. These are not authentication
   signatures and cannot defend against the same OS user rewriting all evidence.
2. Add the returned `resumeFrom` to a new begin JSON with the actual current session
   coordinates, a new call ID and the current role `sourceHash`. Keep `task`,
   `repository`, `commitScope` and `implementerIds` identical to the previous call.
   Omit `retryOf` and `reuseChild`. Give the fresh evaluator the previous evidence,
   role, task, fixed HEAD and failure, then follow begin → actual spawn → bind →
   complete above.
3. `audit` validates every call in the current and referenced historical sessions.
   It retains the previous REJECTED status and reason, adding `resolvedBy` and
   `resolvedByRef: {sessionId, parentAgentId, callId}` only for a valid OBSERVED
   successor. Unrelated failures, unfinished calls and corrupt records still fail
   audit. Hash mismatches, missing records, scope mismatches, cycles and duplicate
   consumption of a failure are rejected. A new PENDING call consumes the reference
   too. If creation fails, record that new call as a terminal failure and reference
   it on the next recovery. Do not skip PENDING to consume the earlier failure again.

Call identity is `(sessionId, parentAgentId, callId)`; child identity is
`(sessionId, child path)`. Files are keyed by call ID within a session, so different
parents must also use distinct call IDs in that session. Calls from worktrees
sharing a Git common directory coexist in one session inventory. Bind and audit
validate each call's worktree and Git common identity. Retry repository equality
and audit's composite session/parent identity remain required. Audit visits other
parents it discovers and counts each parent's calls only in that visit. References
to several parents in one historical session do not duplicate counts or hide
failures and unfinished calls belonging to unreferenced parents.

A recurring `/root` path alone does not identify the same execution.
`implementerIds` and `previousAgentIds` remain conservative path-based exclusion
lists: a grader cannot use a listed path even in a new session. Cross-session
reviewer reuse is unsupported. Same-session reviewer `retryOf` and `reuseChild`
follow the existing procedure.

When spawn returns a `collab spawn failed: ...` string, supply that actual value
as the bind observation. The REJECTED outcome preserves the original message,
`failure.layer: provider`, `failure.kind` and `childState: not-created`. A thread
limit message is classified as capacity, never success or MATCH. Other return
shapes remain contract errors; do not infer provider failure. Preserve historical
`spawn return schema invalid` outcomes unchanged and link the retained original
observation separately as evidence of the original error.

If the same creation limit recurs, wait in VERIFY_PENDING instead of repeatedly
creating calls. Report the failure reference, fixed HEAD, required independent
evaluator and conditions to check before resuming. Resume when new evidence shows
available capacity or in a new evaluation session requested by the user. Maximum
creation counts, concurrent versus cumulative limits and reset conditions remain
UNKNOWN without provider evidence. Parent judgment or changing a reviewer into an
evaluator cannot replace recovery. The repository-wide lock serializes reference
consumption, so audit/reference also need write access to the lock directory.
EPERM indicates a sandbox/state access failure, not a policy denial.

## Optional transcript-to-outcome adapters

The native-outcome path does not require a transcript. To consume a captured runtime stream instead, provide a fifth begin argument `capture.json` with an explicit `format` and absolute `file`; then use `complete <scope.json> <registration.json> <call-id> <native-call-id>`. Capture must begin before delegation. Existing bytes are hashed and excluded from the invocation window. Missing capture bytes and unavailable instance/wait association remain UNREACHED.

| Format selector | Accepted evidence | Boundary |
|---|---|---|
| `claude-code-2.1-jsonl` | Agent/Task `tool_use` ID and explicit role; matching `tool_result`/`toolUseResult` child; synchronous completed status or asynchronous task-notification; child attribution and response | `children` is an explicit absolute directory containing `agent-<id>.jsonl`. Unknown/conflicting roles or unsupported records are not skipped |
| `codex-exec-0.153-jsonl` | `thread.started` and completed `collab_tool_call` spawn/wait items with sender/receiver IDs and the selected child's completed state/message | Requires actual spawn and wait instance association. A prompt mentioning a role supplies no identity. Empty receivers/states cannot establish completion |

Selectors describe narrow adapter contracts, not a guarantee that every runtime patch emits every field. [Codex non-interactive documentation](https://learn.chatgpt.com/docs/non-interactive-mode) describes the JSON event stream. It does not make native on-disk rollout JSONL the same format. Rollout records such as `session_meta`/`response_item`/`event_msg` are unsupported here. Recorded Codex probes can contain real role hooks but omit spawn and wait receiver/state details in exec output: the transcript path stays UNREACHED, while the separate native-return path remains available when the orchestrator actually has those returns. Positive decoder fixtures are not proof of a live native task result.

## Retrospective aggregate

`bash <plugin>/checks/transcript-check.sh --scope <scope.json> --json` reads every stored required call, including missing/failed outcomes. The scoped inventory is session-wide; preserve failed attempts in its population. Do not filter them away to obtain a passing aggregate.

For a generic scope, include the audit context's `version`, `runtime`, `provider`,
`repository`, `data`, `sessionId` and `parentAgentId`. A report with
`format: harness-delegation-v1` aggregates `signals`, `tools`, `reuse` and
`a9.verdicts` alongside `population`, `complete` and `unreached` from the validated
generic inventory, including referenced historical sessions. Execution audit
explains resolved REJECTED calls through `resolvedBy`; A9 still retains those
failed observations, so the aggregate may remain partial. `reuse` counts each
call's first SIGNAL, not actual child reuse. Unmeasured tool and token costs remain
UNKNOWN; native observations are not automatically mixed into this aggregate.

The existing Claude directory entry remains: `--projects <directory>` (default `~/.claude/projects`), `--session <id>`, `--since <ISO8601|Nd|Nh>`, `--json`. It derives inventory from actual Agent/Task invocations rather than completions alone. Session and time filters intersect; unfinished invocations remain visible even if they began before the window. Completion-only legacy fragments, malformed tails, missing files and unsupported records are UNREACHED. `--self-check` retains the clean/dirty first-line SIGNAL and asynchronous notification controls.

The report keeps `signals`, `tools`, `reuse`, and `a9.verdicts`, and adds explicit `population`, per-call `observations`, `complete`, and `unreached`. Exit 0 means complete A9 observation without violations; exit 1 means A9 violations; any required UNREACHED makes the whole report exit 2, even alongside valid observations. `complete: false` means signal/tool counts cover only the observed subset and cannot be quoted as the full denominator. A9 failures and token availability are independent: missing token fields yield `tokens.roles.<role>.status: UNKNOWN`, `total: null`, with `observed_partial` separately labelled. Message IDs deduplicate split-record usage. Parent exec turn usage is never attributed to a child.

Ordinary outcome metadata does not carry token usage or per-message tool distribution. Its tool aggregate therefore has `status: UNKNOWN` and null measurements, not zero calls. Historical decoded transcripts can supply those measurements only for the observed population.

Guard firing counts still use the [state resolver](state.md) through `guard-log.sh`. New metadata-only guard rows contain no raw command to classify; report classification as unmeasured instead of reconstructing it from unrelated transcripts. Transcript role evidence and guard false-positive judgments remain separate inputs.
