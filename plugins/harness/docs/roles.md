# Runtime role contract

Before delegating in develop, verify-code or verify-implement, use this contract. Role discipline and SIGNAL vocabularies come from `roles/*.md`; the skill still owns result handling and RETRY checkpoints and explicit user budgets.

## Standalone investigation and review

Use ordinary delegation for a user-requested investigation or review that does
not close ledger tasks. Supply the repository, fixed commit range (or identified
working diff), responsibilities and relevant rules. Keep the provider-returned
child identity, response and inspected scope with the findings. No story, native
registration, begin/bind/complete inventory or whole-session audit is required.
The same independent reviewer can follow up on its findings. The parent can run
tests that need permissions unavailable to the reviewing child and supply their
actual results. A standalone report does not authorize ledger close.

Ordinary children carry no harness role policy. The guard still applies common
workspace, runtime-state, remote-write and ledger-coordinate protections; host
permissions and user authorization govern execution beyond those recognized
effects. An opaque Python command is not proof of a write or a role claim.
Reserve child path components beginning with `harness_` for managed delegation:
`begin` generates that namespace. A managed child or its descendant must resolve
its inventory; missing, corrupt or terminal evidence cannot become an ordinary
child. Explicit role claims retain their role validation.

The remaining sections govern delegated role execution. Local verification selected
by verify-code requires no delegation inventory or role receipt.

## Select the execution contract

Roles define responsibilities and permission boundaries; native role registration
is an optional execution mechanism. On `codex` / `collaboration`, use ordinary
children with canonical role instructions through the generic protocol in
[Runtime observations](transcripts.md#generic-parent-observations). The orchestrator
selects this path without a separate user decision; its default policy is
`permission: prompt-only`. Use native roles when available and useful, or when
the user explicitly requires native execution. Record the selected path in the
task execution-<role> summary before delegation.

When native execution is unavailable, the orchestrator may select the generic
path automatically unless the user requires native execution or enforced role
permissions. Preserve a failed native attempt as failed; finish or interrupt its
child before starting a fresh generic call. Never relabel a failed native result
as OBSERVED. An explicit enforcement requirement remains unavailable on this
provider and follows develop's human wait.

`delegation.mjs capability <capability.json>` and `doctor.mjs delegation
<capability.json>` consume the same capability function as generic begin. The JSON
contains `runtime`, `provider`, and `permission`; require exit 0 and AVAILABLE.
Omitting permission selects prompt-only; explicit unsupported values are rejected.
`automaticNativeFallback` reports policy eligibility, not an executed fallback or
authorization to override a user's native requirement. This diagnoses availability,
not execution, hook activation or role loading.
Doctor's native `check` retains its separate static/loaded/live judgments.

Ordinary file reads, recognized read-only shell commands and internal collaboration
reporting do not require role registration, a delegation inventory or metadata
lookup. A passing read is permission to inspect, not role or completion evidence.
For managed writes and commands outside that read subset, use the active
SessionStart `data` and `sessionId` in the call, and the assigned canonical
worktree as `repository`. Codex can deliver a
thread UUID as `agent_id` and the built-in `default` profile as `agent_type`.
For that shape, the guard uses the local CLI's App Server `initialize` →
`initialized` → metadata-only `thread/read` protocol. It requires the exact UUID,
matching `source.subAgent.thread_spawn.parent_thread_id` and canonical
`agent_path`, and no custom role claim. It does not parse rollout files, resume a
thread, request a model turn, or correlate children by timing. Missing metadata,
an unavailable CLI, timeout or schema mismatch denies the tool. The CLI must read
the same local Codex state as the active session; remote-only state is unavailable.
The legacy canonical-path hook shape without `agent_type` remains supported.
An ordinary canonical child path requires no inventory or state coordinates.
UUID/default hooks use the metadata path to distinguish ordinary children from
the reserved managed namespace; metadata failure remains UNREACHED, rather than
guessing that a possibly managed child is ordinary.
For managed children, the guard resolves the active dispatch in that session's inventory, checks
role source, repository identity and any binding, and applies its assigned policy
without filling in native identity. Persisted dispatch permits the
first tool before bind returns; bind is still mandatory for result consumption.
Unknown, mismatched, corrupt or terminal records deny role-dependent execution. Hook cwd may be
the main checkout or a linked tree of the same Git repository. Missing hook
identity or different state coordinates remain UNREACHED; do not search other
sessions or copy inventories to make them match.

An outcome written by complete ends the role-dependent permission window, including REJECTED.
The parent must complete interrupted calls as rejected. A completed reviewer can
be reused through a linked retry below; an interrupted child uses a fresh call and child.
The guard cannot observe provider termination before the parent records it.
These local checks do not establish provider permission enforcement: the same OS
user can alter local records, and unobserved tools are outside the guard's reach.

For the selected generic path, require exit 0 and `status: OBSERVED` from complete
before handling the canonical role's SIGNAL. It attests parent-observed child
identity and completion with `permission: prompt-only`, `enforcement: unavailable`
and `nativeRoleEvidence: unavailable`; tool and token measurements are unknown.
Supply the canonical role file by path as the child's instructions. Those prompts
remain role discipline, but their prohibitions have no verified enforcement here.
An OBSERVED evaluator MATCH can ground close in this generic path.
It is not native REACHED, registered-role evidence or proof of semantic acceptance.

Both paths preserve the calling skill's SIGNAL handling and persisted RETRY checkpoints and explicit user budgets.
Each grader is independent of the parent and all implementation authors. When
separate reviewer and evaluator calls are required, their children are distinct.
Combined verification uses one evaluator as defined by `verify-code` "Verification path".
For a fix review, reuse the independent reviewer when its earlier invocation
completed and its context remains useful. Preserve the original review scope,
earlier findings and a new result for the corrected head. Generic managed calls
use `retryOf` and `reuseChild: true` as `transcripts.md` describes; a fresh child
remains available. Keep earlier IDs as history, not a blanket ban on reuse.
Native protocols that cannot isolate a new invocation use a fresh child or the
generic path unless the user explicitly requires native execution.

When an evaluator cannot start, reassess the verification path first. To link
a fresh independent attempt to a failure in another session, consult
[Cross-session independent evaluator recovery](transcripts.md#cross-session-independent-evaluator-recovery)
for the supported scope, verified failure reference and capacity-wait procedure.

Upsert the call and validated outcome with `ledger summary <task ID> execution-<role> --file <file>`, keeping private runtime
identities and response evidence in the parent-owned local inventory when needed.
PENDING, REJECTED, UNAVAILABLE and native UNREACHED never authorize signal handling
or close. Preserve the task and failed evidence. For native unavailability, apply
the execution-path selection above; otherwise use develop's human-wait procedure.

## Edit and inspect role settings

Edit plugin source in an assigned worktree. `roles/<role>.md` owns shared
instructions and SIGNAL vocabularies. Each runtime owns its native declarations:
`native/claude/<role>.md`, `native/codex/<role>.toml`, or
`native/antigravity/<role>.md`. There is no cross-provider settings schema.
The assembler inserts the shared body at the single instruction marker and
preserves provider-specific fields. It validates role identity and assembly
boundaries; the provider validates supported settings and values.

For a Codex-only declaration, the following is an example template, not a
shipped default or evidence that permissions are enforced:

```toml
name = "harness-reviewer"
description = "Supervisor that reviews the code quality of a task's changes. Does not compare against completion criteria."
sandbox_mode = "read-only"
# HARNESS_ROLE_INSTRUCTIONS
```

Keep the Codex marker on its own top-level line, with no existing
`developer_instructions` assignment. Claude and Antigravity use
`<!-- HARNESS_ROLE_INSTRUCTIONS -->` on its own line after frontmatter.
Build Claude `agents/<role>.md` with `distribution.mjs generate` and check the
artifact with `distribution.mjs check`; those files are generated discovery
artifacts. For deployment and re-registration after either source changes,
follow [installation.md](installation.md). Generic collaboration reads the
canonical role body and uses its dispatch options; native templates, including
sandbox settings, do not configure that path.

Before diagnosing declared role configuration, run the read-only command:

```sh
node <plugin-root>/scripts/roles.mjs explain <input.json>
```

For example, `input.json` can contain:

```json
{"runtime":"codex","role":"reviewer","execution":"generic"}
```

The result has `canonical.file` and `canonical.sha256`, `native.source` and
`native.rendered`, plus `native.artifact` (the Claude discovery path, otherwise
null). This example returns `requested: null`, `selectedDispatchOptions: {}`,
`native.applicableToSelectedPath: false`, `native.loading: "unverified"`,
`observed: {"model":"unknown","reasoningEffort":"unknown"}` and
`enforcement: "unavailable"`. With `execution: "native"`, applicability is true,
selected dispatch options are null and enforcement is `"unverified"`.
Native execution supports all three runtimes; generic supports Codex only.

Optional `modelOptions` uses the Model selection contract below; optional
`installedRoot` is an absolute path used when rendering root references.
`requestProvenance: "caller-supplied-not-dispatched"` applies even to an explicit
request. Requests do not override `native.rendered`; generic
`selectedDispatchOptions` describes the selection that a dispatch would use.
Explain neither dispatches nor registers, writes receipts or detects the loaded
model. A rendered template is declared configuration only. Use registration
verification and current-session observations for those separate questions.

## Register (native)

Run `node ${CLAUDE_PLUGIN_ROOT}/scripts/roles.mjs register claude` to describe the existing Claude plugin roles. It validates and references the generated Claude files without rewriting them; Claude plugin registration is unchanged. For Codex, run `register codex <absolute native agents directory>` and save its JSON output as a registration receipt. Use one discovery scope: `<repo>/.codex/agents` or `<CODEX_HOME>/agents`. The generator assembles the selected native template with the role body and resolves its plugin-root pointers. Native declarations and generic Model selection below remain separate.

Run `verify <registration.json>` before use. Missing files, changed sources, altered generated files and duplicate native names in that directory fail. Also check the runtime's discovered roles for duplicate identifiers from other scopes; the directory check cannot enumerate a runtime's effective configuration. Generated files are projections: after an update, review and remove the old generated files, then regenerate from the new install and replace the receipt. Keep the old install and receipt together for rollback. Never maintain generated role prose by hand.

Owned projections still require exact bytes and source hashes. For other TOML files, the directory verifier reads the top-level name for collisions; the runtime validates unrelated fields. It distinguishes comments, quoted and multiline strings, arrays and inline tables so their contents cannot supply a false name. Dotted paths and fields after the first table header are not top-level scalar names. Names use single-line basic/literal strings, with bare or quoted keys and TOML escapes including `\uXXXX` and `\UXXXXXXXX`. Duplicate names, unreadable name values and unfinished strings or containers produce UNREACHED. Unrelated numeric, boolean, array, multiline instruction and table values do not prevent registration.

Registration proves files, not runtime loading or hook activation. Start a new runtime session after registration. Its native delegation capability must expose the requested identifier and deliver role identity in hooks. If it cannot, record UNREACHED and apply execution-path selection above. Claude live verification is tracked separately in skills#268; a fixture is not a live claim.

## Model selection

`lib/runtime/role-models.mjs` holds preferences, not runtime requirements.
Codex roles inherit the runtime's model and effort when availability is unknown
or the preferred model is unavailable. Native projections omit fixed defaults.
For generic begin, optional `modelOptions.availableModels` supplies a current
provider-supported list; a listed preference can be selected. If that default
fails at dispatch, retry with inherited settings and record the actual choice.
Do not add a model-discovery gate just to use a preference.

An explicit user selection travels as `modelOptions.model` and optional
`reasoning_effort`. Keep it unchanged; known unavailability is an error, and a
provider rejection follows human wait. A model change needs a fresh child;
reviewer follow-ups retain their existing runtime settings. Requested options
are not observed model evidence. Record an observed choice when available and
leave missing usage unknown. Claude retains its runtime-owned model settings.

Sources: [OpenAI subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents),
[models](https://learn.chatgpt.com/docs/models),
[hooks](https://learn.chatgpt.com/docs/hooks), and
[App Server](https://learn.chatgpt.com/docs/app-server).
Generate the protocol schema with the installed CLI as the App Server guide
describes; optional `agent_path` may be absent in another client version, which
leaves generic hook identity UNREACHED.

## Call (native)

Save a request JSON containing `role`, `task` (the task or batch unit), `message` (the skill's delegation message), `sessionId`, `parentAgentId`, `implementerIds` and `previousAgentIds`. IDs are runtime instance IDs, not role names. Populate implementation authors and previous attempts from persisted delegation records; an empty previous list is valid only on the first attempt. The task/batch and commit range in the message are the scope of this call.

Before native invocation, persist the required call with `workflow.mjs begin` as [Runtime observations](transcripts.md) specifies. It uses `roleCall` and records the observation boundary; standalone `roles.mjs call` validates a request but does not persist that inventory. Invoke the runtime's native delegate tool with the returned call's `identifier` and `message`: Claude uses `harness:<role>`, Codex uses `harness-<role>`. Record the returned child and invocation IDs before waiting. The CLI does not spawn a model or prove runtime loading. A generic child instructed to read a role file is not evidence of custom-role registration.

For a retry, follow verify-code's persisted RETRY procedure before creating a new call. Native evidence requires a fresh child when the provider cannot isolate a new invocation. Use the generic linked-retry path to reuse a reviewer. Evaluator/reviewer IDs must differ from the parent and every implementation author.

## Result (native)

Use `workflow.mjs complete-native` with the actual native return recorded by the orchestrator, following [Runtime observations](transcripts.md). It loads ordinary events after begin, checks invocation ownership, and calls the existing `roleResult` contract. Require rc 0 and `status: REACHED` before handling its `signal` through the calling skill. The adapter checks ordered Start → tool → Stop events from the same session, role and instance, and the Stop result's first line against the current source role's vocabulary. Upsert call, outcome and result paths with `ledger summary <task ID> execution-<role> --file <file>` so identity and scope survive re-entry. These are evidence records, not an authenticated audit service: only the orchestrator supplies native returns, never a child's summary. `roles.mjs result` remains a direct contract inspector for explicit fixtures/probes; it does not replace ordinary inventory or its observation boundary.

Supply one invocation per child instance: exactly one Start and one Stop, with all tool starts between them. Repeated Start/Stop or tool starts after Stop make the result UNREACHED, including an unfinished follow-up after an earlier successful verdict. Use a fresh child and call for another judgment instead of combining responses from a reused instance.

Missing identity, missing/unregistered SIGNAL, interrupted execution, stale registration and self-judgment produce `UNREACHED`: the standalone `roles.mjs` inspector returns rc 1; the ordinary `workflow.mjs` consumer returns rc 2. Preserve the task and failed evidence; native unavailability follows execution-path selection above, while identity or result-integrity failures follow develop's human-wait procedure. For independent verification, an independently reached evaluator MATCH grounds close; the explicit human scope-excess decision in verify-implement remains its own branch. A parent-written SIGNAL cannot replace required delegated judgment. The local
verification path records checks and acceptance directly, without a role SIGNAL.

The existing guard owns file/Git/ledger permissions through the common identity mapping. Role prompts and generated registration alone are not enforcement: disabled or unidentified hooks invalidate the runtime capability prerequisite. Transcript layouts are not used by this contract.

Ordinary paths and immutable storage are owned by [Runtime state](state.md); [Runtime observations](transcripts.md) owns their workflow consumer and optional transcript decoders. Missing ordinary call/outcome association is UNREACHED. Doctor evidence remains diagnostic.
# Runtime parity adapters

The [runtime role execution contract](runtime-roles.md) describes capability
checks, Antigravity native projections and parent-observed child/result binding.
