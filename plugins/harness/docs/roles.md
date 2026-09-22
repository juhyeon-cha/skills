# Role guidance and optional runtime contracts

## Ordinary delegation

Use ordinary delegation for implementation, review and acceptance by default.
Supply the repository/worktree, responsibility, relevant requirements and rules,
and fixed commit range or identified working diff. Inspect the actual returned
response against that scope. Keep the outcome, commit/diff, checks and limitations;
the provider-returned child identity is useful for follow-up but no registration,
begin/bind/complete inventory, role receipt, first-line SIGNAL or session audit is
required to use meaningful findings or close verified work.

`roles/*.md` retains responsibility guidance and its existing managed-response
conventions. Those conventions describe role-oriented execution; ordinary
responsibility prompts need not adopt their SIGNAL or ledger-stage format. This
choice does not override user instructions, concrete safety constraints or an
explicit project requirement for a particular role or independent review.
`verify-code` owns risk-driven verification selection and grader independence.

Reuse a reviewer for a bounded correction when useful, supplying the corrected
scope and prior findings. Use a fresh reviewer when scope or authorship requires
it. Missing optional infrastructure is not a reason to halt useful verification.
Never turn an unavailable audit into a successful audit claim.

## Standalone investigation and review

Standalone reviews follow the same ordinary path and finish with findings. They
do not require a story or create authority for ledger writes or task closure.
The parent may run checks unavailable to the child and supply actual results.

## Tool boundaries

Ordinary child execution does not need delegation-inventory or provider-metadata
lookup. A default or unidentified role remains ordinary; child-scoped workspace,
runtime-state, remote-write and ledger-coordinate protections still apply.
Recognized native roles retain their concrete tool restrictions. Prompts and
registration alone do not establish host permission enforcement. Use runtime
permissions when an actual read-only boundary is required and verify that boundary
before claiming it. A passing hook is not proof of safety or user authorization.

## Select an optional managed contract

Choose managed/native auditing when the user or project requires it, or when its
invocation history is useful to a concrete investigation. Its commands remain
strict: invalid identity, stale sources, failed completion and missing observations
cannot be reported as successful managed evidence. Record an attempted audit's
actual status without making it a universal completion prerequisite.

For managed Codex collaboration, follow
[Generic parent observations](transcripts.md#generic-parent-observations).
`delegation.mjs capability` and `doctor.mjs delegation` inspect declared capability;
the default permission is prompt-only and unsupported requested enforcement is
unavailable. `OBSERVED` describes parent-observed execution, not semantic quality,
registered native identity, model usage or enforced role permissions.

For native audit, use Register, Call and Result below and the native observation
procedure in [transcripts.md](transcripts.md). `REACHED` attests the validated
observation contract, not correctness. An explicitly required native or enforced
contract remains required when unavailable; choose another ordinary path only
when the requirement permits it. Cross-session recovery is optional and described
in [transcripts.md](transcripts.md#cross-session-independent-evaluator-recovery).

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
follow [installation.md](installation.md). Managed generic collaboration reads the
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

Run `verify <registration.json>` before claiming verified native registration. Missing files, changed sources, altered generated files and duplicate native names in that directory fail. Also check the runtime's discovered roles for duplicate identifiers from other scopes; the directory check cannot enumerate a runtime's effective configuration. Generated files are projections: after an update, review and remove the old generated files, then regenerate from the new install and replace the receipt. Keep the old install and receipt together for rollback. Never maintain generated role prose by hand.

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
Provider metadata schemas may differ across clients. Ordinary execution does
not require App Server metadata resolution.

## Call (native)

Save a request JSON containing `role`, `task` (the task or batch unit), `message` (the skill's delegation message), `sessionId`, `parentAgentId`, `implementerIds` and `previousAgentIds`. IDs are runtime instance IDs, not role names. Populate implementation authors and previous attempts from persisted delegation records; an empty previous list is valid only on the first attempt. The task/batch and commit range in the message are the scope of this call.

Before native invocation, persist the required call with `workflow.mjs begin` as [Runtime observations](transcripts.md) specifies. It uses `roleCall` and records the observation boundary; standalone `roles.mjs call` validates a request but does not persist that inventory. Invoke the runtime's native delegate tool with the returned call's `identifier` and `message`: Claude uses `harness:<role>`, Codex uses `harness-<role>`. Record the returned child and invocation IDs before waiting. The CLI does not spawn a model or prove runtime loading. A generic child instructed to read a role file is not evidence of custom-role registration.

For a managed retry, create a new call while retaining the earlier result. Native evidence requires a fresh child when the provider cannot isolate a new invocation. Use the generic linked-retry path to reuse a reviewer. Evaluator/reviewer IDs must differ from the parent and every implementation author.

## Result (native)

Use `workflow.mjs complete-native` with the actual native return recorded by the orchestrator, following [Runtime observations](transcripts.md). It loads ordinary events after begin, checks invocation ownership, and calls the existing `roleResult` contract. Require rc 0 and `status: REACHED` before claiming a successful native audit result. The adapter checks ordered Start → tool → Stop events from the same session, role and instance, and the Stop result's first line against the current source role's vocabulary. Upsert call, outcome and result paths with `ledger summary <task ID> execution-<role> --file <file>` so identity and scope survive re-entry. These are evidence records, not an authenticated audit service: only the orchestrator supplies native returns, never a child's summary. `roles.mjs result` remains a direct contract inspector for explicit fixtures/probes; it does not replace managed inventory or its observation boundary.

Supply one invocation per child instance: exactly one Start and one Stop, with all tool starts between them. Repeated Start/Stop or tool starts after Stop make the result UNREACHED, including an unfinished follow-up after an earlier successful verdict. Use a fresh child and call for another judgment instead of combining responses from a reused instance.

Missing identity, missing/unregistered SIGNAL, interrupted execution, stale registration and self-judgment produce `UNREACHED`: the standalone `roles.mjs` inspector returns rc 1; the managed `workflow.mjs` consumer returns rc 2. Preserve failed evidence. A failed optional audit does not invalidate
an ordinary review or authorize a success claim about the native contract.
When the user requires that contract, resolve its failure before claiming that
requirement met. Acceptance and close follow verify-implement's outcome comparison.

Native role prompts and generated registration alone are not enforcement;
verify actual hook activation and permission behavior when making such a claim.
Storage is owned by [Runtime state](state.md); [Runtime observations](transcripts.md)
owns optional audit consumers and transcript decoders. Missing association fails
that audit without becoming a prerequisite for ordinary task completion.

# Runtime parity adapters

The [runtime role execution contract](runtime-roles.md) describes capability
checks, Antigravity native projections and parent-observed child/result binding.
