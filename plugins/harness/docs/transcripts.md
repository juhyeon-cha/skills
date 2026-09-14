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

### 세션 간 독립 evaluator 재개

`retryOf`는 같은 세션의 호출 ID다. 다른 세션의 실패는 `resumeFrom`으로 명시한다.
지원 범위는 같은 canonical worktree·task·evaluator 역할·고정 commitScope·
implementerIds를 유지하는 REJECTED 호출이다. 새 세션의 실제 sessionId와 parentAgentId를
사용하고 새 child를 생성한다. 과거 세션으로 위장하거나 inventory를 복사하지 않는다.
HEAD가 바뀌었다면 이 재개 계약으로 과거 실패를 해결할 수 없다.

1. 이전 audit context와 callId를 `{context: <이전 context>, callId: <실패 ID>}`로 저장하고
   `node <plugin>/scripts/delegation.mjs reference <reference-input.json>`을 실행한다.
   반환값은 sessionId·parentAgentId·callId와 callHash·dispatchHash·bindingHash·outcomeHash다.
   해시는 envelope 파일의 원래 바이트를 고정하며 binding이 없으면 bindingHash는 null이다.
   이 값은 인증 서명이 아니다. 같은 OS 사용자의 모든 근거 파일 재작성은 방어하지 못한다.
2. 새 begin JSON에 실제 현재 세션 좌표, 새 callId, 현재 역할 sourceHash와 반환된
   `resumeFrom`을 넣는다. task·repository·commitScope·implementerIds는 이전 호출과 같다.
   `retryOf`와 `reuseChild`를 함께 넣지 않는다. 과거 자료·역할·task·고정 HEAD·이전 실패를
   새 evaluator 메시지에 연결하고, 위의 begin → 실제 spawn → bind → complete를 수행한다.
3. `audit`은 현재 세션과 참조된 과거 세션의 전체 호출을 검증한다. 이전 REJECTED와 이유를
   유지하고 유효한 OBSERVED 후속 호출에만 `resolvedBy`와 `{sessionId,parentAgentId,callId}`인
   `resolvedByRef`를 붙인다. 관련 없는 실패·미완료·손상 기록은 계속 audit 실패 원인이다.
   해시 불일치·누락·scope 불일치·순환·같은 실패의 중복 소비는 거부한다. 새 PENDING도
   참조를 소비한다. 생성에 실패하면 그 새 호출을 terminal 실패로 기록하고, 다음 재개는
   그 실패를 참조한다. PENDING을 건너뛰어 이전 실패를 다시 소비하지 않는다.

호출 식별은 `(sessionId, parentAgentId, callId)`, child 식별은 `(sessionId, child 경로)`다.
세션마다 반복되는 `/root` 자체는 동일 실행의 증거가 아니다. 기존 implementerIds와
previousAgentIds는 경로 기반의 보수적 배제 목록으로 유지한다. 새 세션에서도 그 목록에
있는 경로를 grader로 허용하지 않는다. cross-session reviewer 재사용은 지원하지 않는다.
같은 세션의 reviewer `retryOf`·`reuseChild`는 기존 절차를 따른다.

spawn이 `collab spawn failed: ...` 문자열을 반환하면 그 실제 값을 bind 관측에 넣는다.
REJECTED outcome은 원래 메시지와 `failure.layer: provider`, `failure.kind`,
`childState: not-created`를 보존한다. thread limit 메시지는 capacity로 분류하며 성공이나
MATCH로 승격하지 않는다. 다른 반환 모양은 계약 오류로 남고 추측으로 provider 실패라
분류하지 않는다. 과거의 `spawn return schema invalid`는 불변으로 보존하며 원래 오류는
보관된 실제 관측을 별도 근거로 연결한다.

같은 생성 한도가 재발하면 반복 생성 대신 VERIFY_PENDING으로 대기하고 실패 참조·고정
HEAD·필요한 독립 evaluator·확인할 재개 조건을 보고한다. 용량이 사용 가능하다는 새 근거나
사용자가 요청한 새 평가 세션에서 재개한다. 최대 생성 수, 동시/누적 구분과 리셋 조건은
provider가 확인한 근거 없이는 UNKNOWN이다. 부모의 대리 판정이나 reviewer의 evaluator
전환은 복구가 아니다. 저장소 공통 lock은 동시 참조 소비를 직렬화하므로 audit/reference도
lock 디렉터리 쓰기 권한이 필요하다. EPERM은 sandbox/state 접근 실패이지 정책 차단이 아니다.

## Optional transcript-to-outcome adapters

The native-outcome path does not require a transcript. To consume a captured runtime stream instead, provide a fifth begin argument `capture.json` with an explicit `format` and absolute `file`; then use `complete <scope.json> <registration.json> <call-id> <native-call-id>`. Capture must begin before delegation. Existing bytes are hashed and excluded from the invocation window. Missing capture bytes and unavailable instance/wait association remain UNREACHED.

| Format selector | Accepted evidence | Boundary |
|---|---|---|
| `claude-code-2.1-jsonl` | Agent/Task `tool_use` ID and explicit role; matching `tool_result`/`toolUseResult` child; synchronous completed status or asynchronous task-notification; child attribution and response | `children` is an explicit absolute directory containing `agent-<id>.jsonl`. Unknown/conflicting roles or unsupported records are not skipped |
| `codex-exec-0.153-jsonl` | `thread.started` and completed `collab_tool_call` spawn/wait items with sender/receiver IDs and the selected child's completed state/message | Requires actual spawn and wait instance association. A prompt mentioning a role supplies no identity. Empty receivers/states cannot establish completion |

Selectors describe narrow adapter contracts, not a guarantee that every runtime patch emits every field. [Codex non-interactive documentation](https://learn.chatgpt.com/docs/non-interactive-mode) describes the JSON event stream. It does not make native on-disk rollout JSONL the same format. Rollout records such as `session_meta`/`response_item`/`event_msg` are unsupported here. Recorded Codex probes can contain real role hooks but omit spawn and wait receiver/state details in exec output: the transcript path stays UNREACHED, while the separate native-return path remains available when the orchestrator actually has those returns. Positive decoder fixtures are not proof of a live native task result.

## Retrospective aggregate

`bash <plugin>/checks/transcript-check.sh --scope <scope.json> --json` reads every stored required call, including missing/failed outcomes. The scoped inventory is session-wide; preserve failed attempts in its population. Do not filter them away to obtain a passing aggregate.

generic scope에는 audit context의 version·runtime·provider·repository·data·sessionId·
parentAgentId를 모두 넣는다. `format: harness-delegation-v1` 보고서는 검증된 generic
inventory에서 signals·tools·reuse·a9.verdicts와 population·complete·unreached를 함께
집계한다. 참조된 과거 세션도 포함한다. 해결된 REJECTED는 실행 audit의 resolvedBy로
설명하지만 A9 관측의 실패 행을 지우지 않으므로 aggregate는 partial일 수 있다.
reuse는 호출별 첫 SIGNAL의 집계이며 실제 child 재사용 수를 뜻하지 않는다. 미측정
도구·토큰 비용은 UNKNOWN이고 native 집계와 자동으로 섞지 않는다.

The existing Claude directory entry remains: `--projects <directory>` (default `~/.claude/projects`), `--session <id>`, `--since <ISO8601|Nd|Nh>`, `--json`. It derives inventory from actual Agent/Task invocations rather than completions alone. Session and time filters intersect; unfinished invocations remain visible even if they began before the window. Completion-only legacy fragments, malformed tails, missing files and unsupported records are UNREACHED. `--self-check` retains the clean/dirty first-line SIGNAL and asynchronous notification controls.

The report keeps `signals`, `tools`, `reuse`, and `a9.verdicts`, and adds explicit `population`, per-call `observations`, `complete`, and `unreached`. Exit 0 means complete A9 observation without violations; exit 1 means A9 violations; any required UNREACHED makes the whole report exit 2, even alongside valid observations. `complete: false` means signal/tool counts cover only the observed subset and cannot be quoted as the full denominator. A9 failures and token availability are independent: missing token fields yield `tokens.roles.<role>.status: UNKNOWN`, `total: null`, with `observed_partial` separately labelled. Message IDs deduplicate split-record usage. Parent exec turn usage is never attributed to a child.

Ordinary outcome metadata does not carry token usage or per-message tool distribution. Its tool aggregate therefore has `status: UNKNOWN` and null measurements, not zero calls. Historical decoded transcripts can supply those measurements only for the observed population.

Guard firing counts still use the [state resolver](state.md) through `guard-log.sh`. New metadata-only guard rows contain no raw command to classify; report classification as unmeasured instead of reconstructing it from unrelated transcripts. Transcript role evidence and guard false-positive judgments remain separate inputs.
