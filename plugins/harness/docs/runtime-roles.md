# Runtime role execution

Canonical role instructions live in `roles/`; runtime settings live in
`native/claude/`, `native/codex/` and `native/antigravity/`. Claude discovers
generated `agents/` Markdown. Codex assembles native TOML and Antigravity
assembles Markdown with its declared tools, model and execution settings.
The [official CLI discovery documentation](https://antigravity.google/docs/cli/subagents/)
and [official subagent schema](https://antigravity.google/docs/subagents) are the
primary contracts. The CLI's observed tool result parser is intentionally narrow:
a changed format returns UNREACHED instead of guessing an identity.

Before dispatch, run `node <plugin-root>/scripts/roles.mjs capabilities <input.json>`
with `runtime`, `role`, the provider's observed `availableTools` and optional
`modelOptions`. This tests required operations, including shell access for Git,
the gate and ledger, plus file mutation tools for implementers. Missing tools
fail explicitly. A declared list is not proof that a runtime loaded or enforced
it; live role evidence still needs actual allowed reads and denied grader writes.
Claude/Codex native and collaboration evidence continue through the existing
[role procedures](roles.md). No capability result is a close reason.

Antigravity accepts only its documented `inherit`, `flash` and `pro` model tiers.
A different explicit model or unmapped reasoning effort fails without substitution.
Codex uses its existing exact explicit-model contract. Claude explicit model names
require `availableModels`; omission inherits. The capability check never translates
a user's requested model into another provider's model.

## Antigravity parent observations

Use `node <plugin-root>/scripts/antigravity-role.mjs begin|bind|activate|complete <input.json>`
from the registered parent or external operator. Child shell tools cannot enroll
identities through this command. The guard checks normalized literal argv,
including quoted paths and composed literal commands. Dynamic child shell
arguments and inline `sh`/`bash`/`zsh -c` commands are denied because their
enrollment effects cannot be classified; ordinary script-file invocations remain
available. All inputs carry `runtime:
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
  task mutation. READY/ACK/START is a harness protocol over native messaging,
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

A child can read before registration. Mutation remains denied until the actual
returned ID is bound, context was observed at the same source and workspace, READY
delivery and acknowledgement were attested, and START's exact nonce acknowledgement
was observed from that child. Reviewer/evaluator mutation then follows the shared guard;
the native tools list is not claimed as an exhaustive enforcement boundary.
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
