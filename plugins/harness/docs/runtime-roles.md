# Optional native role execution

For source ownership, native assembly and read-only configuration diagnosis,
follow [Edit and inspect role settings](roles.md#edit-and-inspect-role-settings).
Runtime declarations retain their own syntax and semantics: Claude frontmatter,
Codex TOML and Antigravity frontmatter are not mutually interchangeable.
Preserving a provider-specific field does not establish that the selected
runtime version supports or enforces it. Ordinary subagents do not load
those declarations; use runtime tools directly as described in [roles.md](roles.md).
The [official CLI discovery documentation](https://antigravity.google/docs/cli/subagents/)
and [official subagent schema](https://antigravity.google/docs/subagents) are the
primary contracts. The CLI's observed tool result parser is intentionally narrow:
a changed format returns UNREACHED instead of guessing an identity.

When explicitly using this native capability contract, run `node <plugin-root>/scripts/roles.mjs capabilities <input.json>`
with `runtime`, `role`, the provider's observed `availableTools` and optional
`modelOptions`. This tests required operations, including shell access for Git,
the gate and ledger, plus file mutation tools for implementers. Missing tools
fail explicitly. A declared list is not proof that a runtime loaded or enforced
it; live role evidence still needs actual allowed reads and denied grader writes.
Claude/Codex native evidence follows the
[role procedures](roles.md). No capability result is a close reason.

Antigravity accepts only its documented `inherit`, `flash` and `pro` model tiers.
A different explicit model or unmapped reasoning effort fails without substitution.
Codex uses its existing exact explicit-model contract. Claude explicit model names
require `modelOptions.availableModels`; omitting `modelOptions.model` inherits.
The capability check never translates a requested model into another model.

Both `explain` and `capabilities` accept the same `modelOptions` object:

```json
{"model":"chosen-model","availableModels":["chosen-model"]}
```

Place it beside `runtime` and `role`. `explain` additionally requires
`execution: "native"`; `capabilities` requires observed `availableTools`.
For Codex, an explicit effort uses `modelOptions.reasoning_effort` and requires
`modelOptions.model`. The `explain` output's `observed.reasoningEffort` is an
observation field, not an input key, and remains `unknown` without runtime evidence.
Codex checks an explicit model against `availableModels` when supplied; that
optional list is required for explicit Claude models. Antigravity uses its fixed
tiers and accepts no reasoning-effort mapping.

Existing Claude `capabilities` callers may supply top-level `availableModels`.
Use the nested form for new inputs. If both locations are present, their model
sets must agree. Missing observations, malformed input and a model absent from
the observed list produce distinct diagnostics. These commands inspect requests;
they neither dispatch a model nor establish runtime availability or enforcement.

## Antigravity parent observations

For the opt-in managed Antigravity protocol, use `node <plugin-root>/scripts/antigravity-role.mjs begin|bind|activate|complete <input.json>`
from the registered parent or external operator. Only the parent or operator may
enroll identities; children must leave enrollment to them. The enrollment-specific guard checks the literal
`parent-register` token in the command string; it does not resolve shell expansion
or attest arbitrary script effects. Common workspace, state and remote protections
still apply. This token check is not proof of enrollment integrity. All inputs carry `runtime:
"antigravity"`, exact `workspace`, actual `parentId`, `callId`, and explicit `data`.
The registry is scoped by the actual repository, session, source root and hash.
It is parent-attested workflow evidence, not an authenticated provider API.

- `begin` additionally takes canonical `role`, `task`, `prompt`, `implementerIds`,
  `previousAgentIds`, and `capabilities.availableTools` with optional
  `capabilities.modelOptions`. It returns exact `invoke_subagent` arguments.
  Invoke that one registered custom role with the returned arguments; workspace
  inheritance keeps the already assigned linked worktree. No new worktree is created.
  The dispatch contains preparation instructions only: read the canonical role and
  safe context, then wait idle. The task prompt is retained locally until START.
- `bind` additionally takes `observation` with `source: "parent-tool-return"`,
  `tool: "invoke_subagent"`, the actual `stepIdx`, and `value` holding the native
  tool's returned text. The parser extracts its single returned `conversationId`
  and `workspaceUris`. The matching successful dispatch hook must already exist.
  Assistant prose and caller-invented lifecycle events are not accepted.
  The return is `BOUND_NOT_READY` with exact `send_message` dispatch arguments
  for READY, containing a fresh call nonce. Send these arguments unchanged.
- The child sends the exact READY_ACK requested by READY and waits idle again.
  `activate` takes the bound `childId`, `delivery` and `observation`. The delivery
  is a parent tool return: `source: "parent-tool-return"`, `tool: "send_message"`,
  actual hook `stepIdx`, exact `recipient` and `message`, `success: true`, and raw
  native `value`. Its narrowly recognized return has `Created At`, `Completed At`
  and `Message sent to "<child>".` lines. Failures and unknown formats fail closed.
  The observation has `source: "parent-received-message"`, actual `sender`,
  `recipient`, and READY_ACK `body`. Both observations must match wrapper evidence.
  Activation returns `AWAITING_START_ACK` and exact START dispatch arguments with
  a second nonce and the task prompt. Send that message unchanged. The child must
  send its exact START_ACK before executing the task; activation alone permits no
  successful managed execution evidence. READY/ACK/START is a harness protocol over native messaging,
  **not** an Antigravity native registration or lifecycle feature.
- `complete` additionally takes the bound `childId` and `observation` containing
  `source: "parent-received-message"`, actual `sender`, `recipient`, and `body`.
  This attests the parent received the message; the adapter compares it with that
  child's observed result message, required read and final idle Stop. A successful
  PreToolUse alone does not attest message delivery.
  It also requires `startDelivery` (the actual START tool return in the delivery
  shape above) and `startObservation` (the parent's received START_ACK). A failed,
  missing or mismatched START delivery cannot certify completion. Parent message
  dispatch and both child acknowledgements are single-use; retrying a failed
  delivery requires a fresh call, rather than replaying an uncertain send.

The managed audit accepts execution only after the returned ID is bound, context
matches source/workspace, and READY/START acknowledgements are observed. This is
an audit condition, not a prerequisite for ordinary local tool execution.
Recognized native reviewer/evaluator roles retain concrete guard restrictions;
unidentified agents use common child protections, including remote restrictions.
The native tools list is not an exhaustive enforcement boundary.
Unregistered dispatches, duplicate bindings, other calls or workspaces, stale
source, parent self-judgment and author-as-grader all fail. Parent observations
and their source must be retained locally for independent verification.

Each call uses a fresh child. Stop execution numbers start at zero and remain
contiguous within each preparation, READY wait, or task execution phase; they are
not a lifetime counter. A resume after an idle handshake Stop needs an observed
PreInvocation before the next acknowledgement. Normal idle Stops during handshake preparation are allowed
and cannot supply a result or required execution read. Execution starts after the
START_ACK; only reads and results after it count. An intermediate execution Stop may extend the call only when the
wrapper actually returned `continue`; the final Stop must be normal and idle,
with no later child event. The final result message must follow the last continue,
so an older verdict cannot certify a resumed turn. Busy, killed, error, missing,
duplicate or externally reawakened execution completions fail. Parent busy Stop events live
in a different session and never join the child's chain. An OBSERVED result still
has `nativeLoaded: false` and `liveCertified: false`.

The state directory holds result messages and dispatch prompts for this comparison.
Keep it local; publish sanitized evidence summaries, not raw provider transcripts.

The message-return parser derives from an observed CLI child-to-parent return;
parent-to-child delivery of this handshake still needs a fresh live probe against
the candidate artifact. Fixture success does not establish that provider path.
