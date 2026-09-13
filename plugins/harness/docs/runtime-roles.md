# Runtime role execution

Canonical role instructions remain in `agents/`. Claude references those plugin
agents, Codex projects them as native TOML, and Antigravity projects Markdown
with `subagent: true`, `mainAgent: false`, supported tools and `model: inherit`.
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

Use `node <plugin-root>/scripts/antigravity-role.mjs begin|bind|complete <input.json>`
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
- `bind` additionally takes `observation` with `source: "parent-tool-return"`,
  `tool: "invoke_subagent"`, the actual `stepIdx`, and `value` holding the native
  tool's returned text. The parser extracts its single returned `conversationId`
  and `workspaceUris`. The matching successful dispatch hook must already exist.
  Assistant prose and caller-invented lifecycle events are not accepted.
- `complete` additionally takes the bound `childId` and `observation` containing
  `source: "parent-received-message"`, actual `sender`, `recipient`, and `body`.
  This attests the parent received the message; the adapter compares it with that
  child's observed result message, required read and final idle Stop. A successful
  PreToolUse alone does not attest message delivery.

A child can read before registration. Mutation remains denied until the actual
returned ID is bound and its executing-wrapper context was observed at the same
source and workspace. Reviewer/evaluator mutation then follows the shared guard;
the native tools list is not claimed as an exhaustive enforcement boundary.
Unregistered dispatches, duplicate bindings, other calls or workspaces, stale
source, parent self-judgment and author-as-grader all fail. Parent observations
and their source must be retained locally for independent verification.

Each call uses a fresh child. Its observed Stop execution numbers start at zero
and remain contiguous. An intermediate Stop may extend the call only when the
wrapper actually returned `continue`; the final Stop must be normal and idle,
with no later child event. The final result message must follow the last continue,
so an older verdict cannot certify a resumed turn. Busy, killed, error, missing,
duplicate or externally reawakened completions fail. Parent busy Stop events live
in a different session and never join the child's chain. An OBSERVED result still
has `nativeLoaded: false` and `liveCertified: false`; whole-environment certification
belongs to the parity evidence comparison and independent acceptance judgment.

The state directory holds result messages and dispatch prompts for this comparison.
Keep it local; publish sanitized evidence summaries, not raw provider transcripts.
