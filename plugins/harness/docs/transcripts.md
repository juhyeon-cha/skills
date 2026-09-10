# Runtime observations and ordinary outcomes

`lib/transcripts/` owns format-specific decoding. `lib/transcript.mjs` owns A9 and retrospective aggregation; role names and SIGNAL vocabularies come from the existing role modules and `agents/*.md`. `lib/runtime/workflow.mjs` connects the ordinary session store to `roleCall`/`roleResult`. The ledger remains task state and acceptance authority. A retrospective report never closes work.

## Ordinary delegation

Use this path before every required implementation/review/evaluation, including a retry. Save the SessionStart `HARNESS_STATE_JSON` object as `scope.json`: `runtime`, `repository`, `sessionId`, and the observed absolute `data` directory. The workflow resolver passes that directory explicitly; hook environment inheritance is unnecessary. Save the registered role receipt and the request described in [roles.md](roles.md), adding a unique `callId`.

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

## Optional transcript-to-outcome adapters

The native-outcome path does not require a transcript. To consume a captured runtime stream instead, provide a fifth begin argument `capture.json` with an explicit `format` and absolute `file`; then use `complete <scope.json> <registration.json> <call-id> <native-call-id>`. Capture must begin before delegation. Existing bytes are hashed and excluded from the invocation window. Missing capture bytes and unavailable instance/wait association remain UNREACHED.

| Format selector | Accepted evidence | Boundary |
|---|---|---|
| `claude-code-2.1-jsonl` | Agent/Task `tool_use` ID and explicit role; matching `tool_result`/`toolUseResult` child; synchronous completed status or asynchronous task-notification; child attribution and response | `children` is an explicit absolute directory containing `agent-<id>.jsonl`. Unknown/conflicting roles or unsupported records are not skipped |
| `codex-exec-0.153-jsonl` | `thread.started` and completed `collab_tool_call` spawn/wait items with sender/receiver IDs and the selected child's completed state/message | Requires actual spawn and wait instance association. A prompt mentioning a role supplies no identity. Empty receivers/states cannot establish completion |

Selectors describe narrow adapter contracts, not a guarantee that every runtime patch emits every field. [Codex non-interactive documentation](https://learn.chatgpt.com/docs/non-interactive-mode) describes the JSON event stream. It does not make native on-disk rollout JSONL the same format. Rollout records such as `session_meta`/`response_item`/`event_msg` are unsupported here. Recorded Codex probes can contain real role hooks but omit spawn and wait receiver/state details in exec output: the transcript path stays UNREACHED, while the separate native-return path remains available when the orchestrator actually has those returns. Positive decoder fixtures are not proof of a live native task result.

## Retrospective aggregate

`bash <plugin>/checks/transcript-check.sh --scope <scope.json> --json` reads every stored required call, including missing/failed outcomes. The scoped inventory is session-wide; preserve failed attempts in its population. Do not filter them away to obtain a passing aggregate.

The existing Claude directory entry remains: `--projects <directory>` (default `~/.claude/projects`), `--session <id>`, `--since <ISO8601|Nd|Nh>`, `--json`. It derives inventory from actual Agent/Task invocations rather than completions alone. Session and time filters intersect; unfinished invocations remain visible even if they began before the window. Completion-only legacy fragments, malformed tails, missing files and unsupported records are UNREACHED. `--self-check` retains the clean/dirty first-line SIGNAL and asynchronous notification controls.

The report keeps `signals`, `tools`, `reuse`, and `a9.verdicts`, and adds explicit `population`, per-call `observations`, `complete`, and `unreached`. Exit 0 means complete A9 observation without violations; exit 1 means A9 violations; any required UNREACHED makes the whole report exit 2, even alongside valid observations. `complete: false` means signal/tool counts cover only the observed subset and cannot be quoted as the full denominator. A9 failures and token availability are independent: missing token fields yield `tokens.roles.<role>.status: UNKNOWN`, `total: null`, with `observed_partial` separately labelled. Message IDs deduplicate split-record usage. Parent exec turn usage is never attributed to a child.

Ordinary outcome metadata does not carry token usage or per-message tool distribution. Its tool aggregate therefore has `status: UNKNOWN` and null measurements, not zero calls. Historical decoded transcripts can supply those measurements only for the observed population.

Guard firing counts still use the [state resolver](state.md) through `guard-log.sh`. New metadata-only guard rows contain no raw command to classify; report classification as unmeasured instead of reconstructing it from unrelated transcripts. Transcript role evidence and guard false-positive judgments remain separate inputs.
