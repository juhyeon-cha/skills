# Runtime role contract

Before delegating in develop, verify-code or verify-implement, use this contract. Role discipline and SIGNAL vocabularies come from `agents/*.md`; the skill still owns result handling and RETRY limits.

## Select the execution contract

The default is the native path below. An explicitly selected `codex` / `collaboration`
cycle may use `permission: prompt-only` through the generic protocol in
[Runtime observations](transcripts.md#generic-parent-observations). Record that
selection in the task execution-<role> summary before delegation. Native failure never selects this
path automatically. A request requiring enforced role permissions is unavailable
on this provider: reject it before spawning a child and follow develop's human wait.

`delegation.mjs capability <capability.json>` and `doctor.mjs delegation
<capability.json>` consume the same capability function as generic begin. The JSON
contains `runtime`, `provider`, and `permission`; require exit 0 and AVAILABLE.
This diagnoses contract availability, not execution, hook activation or role loading.
Doctor's native `check` retains its separate static/loaded/live judgments.

For the selected generic path, require exit 0 and `status: OBSERVED` from complete
before handling the canonical role's SIGNAL. It attests parent-observed child
identity and completion with `permission: prompt-only`, `enforcement: unavailable`
and `nativeRoleEvidence: unavailable`; tool and token measurements are unknown.
Supply the canonical role file by path as the child's instructions. Those prompts
remain role discipline, but their prohibitions have no verified enforcement here.
An OBSERVED evaluator MATCH can ground close only in this explicitly selected path.
It is not native REACHED, registered-role evidence or proof of semantic acceptance.

Both paths preserve the calling skill's SIGNAL handling and persisted RETRY limits.
Use independent reviewer and evaluator children, distinct from each other, the
parent and all implementation authors. On a retry use a fresh child and include
all earlier attempts in `previousAgentIds`; a follow-up cannot stand in for it.
Upsert the call and validated outcome with `ledger summary <task ID> execution-<role> --file <file>`, keeping private runtime
identities and response evidence in the parent-owned local inventory when needed.
PENDING, REJECTED, UNAVAILABLE and native UNREACHED never authorize signal handling
or close: preserve the task and use develop's human-wait procedure.

## Register (native)

Run `node ${CLAUDE_PLUGIN_ROOT}/scripts/roles.mjs register claude` to describe the existing Claude plugin roles. It references their original files; Claude plugin registration is unchanged. For Codex, run `register codex <absolute native agents directory>` and save its JSON output as a registration receipt. Use one discovery scope: `<repo>/.codex/agents` or `<CODEX_HOME>/agents`. The generator inserts the role body and resolves its plugin-root pointers. Codex inherits its parent's model; Claude-only frontmatter is not passed as Codex configuration.

Run `verify <registration.json>` before use. Missing files, changed sources, altered generated files and duplicate native names in that directory fail. Also check the runtime's discovered roles for duplicate identifiers from other scopes; the directory check cannot enumerate a runtime's effective configuration. Generated files are projections: after an update, review and remove the old generated files, then regenerate from the new install and replace the receipt. Keep the old install and receipt together for rollback. Never maintain generated role prose by hand.

The directory verifier accepts a restricted TOML subset: flat string assignments, bare or quoted keys, single-line basic strings with JSON-compatible TOML escapes (including `\uXXXX`), single-line literal strings, blank lines and comments. Quoted or escaped `name` keys are decoded before duplicate detection. Every `.toml` file in that directory must be interpretable; tables, arrays, multiline strings, non-string values and other unsupported syntax produce UNREACHED. Use a compatible discovery directory or extend the parser with tests before sharing it with agents that need wider TOML syntax. Unsupported files are never skipped.

Registration proves files, not runtime loading or hook activation. Start a new runtime session after registration. Its native delegation capability must expose the requested identifier and deliver role identity in hooks. If it cannot, record UNREACHED and follow develop's human-wait procedure. Claude live verification is tracked separately in skills#268; a fixture is not a live claim.

## Call (native)

Save a request JSON containing `role`, `task` (the task or batch unit), `message` (the skill's delegation message), `sessionId`, `parentAgentId`, `implementerIds` and `previousAgentIds`. IDs are runtime instance IDs, not role names. Populate implementation authors and previous attempts from persisted delegation records; an empty previous list is valid only on the first attempt. The task/batch and commit range in the message are the scope of this call.

Before native invocation, persist the required call with `workflow.mjs begin` as [Runtime observations](transcripts.md) specifies. It uses `roleCall` and records the observation boundary; standalone `roles.mjs call` validates a request but does not persist that inventory. Invoke the runtime's native delegate tool with the returned call's `identifier` and `message`: Claude uses `harness:<role>`, Codex uses `harness-<role>`. Record the returned child and invocation IDs before waiting. The CLI does not spawn a model or prove runtime loading. A generic child instructed to read a role file is not evidence of custom-role registration.

For a retry, follow verify-code's persisted RETRY procedure before creating a new call. Include every earlier attempt's ID in `previousAgentIds` and use a fresh native child. Evaluator/reviewer IDs must differ from the parent and every implementation author. Same-role follow-ups do not become fresh reviews.

## Result (native)

Use `workflow.mjs complete-native` with the actual native return recorded by the orchestrator, following [Runtime observations](transcripts.md). It loads ordinary events after begin, checks invocation ownership, and calls the existing `roleResult` contract. Require rc 0 and `status: REACHED` before handling its `signal` through the calling skill. The adapter checks ordered Start → tool → Stop events from the same session, role and instance, and the Stop result's first line against the current source role's vocabulary. Upsert call, outcome and result paths with `ledger summary <task ID> execution-<role> --file <file>` so identity and scope survive re-entry. These are evidence records, not an authenticated audit service: only the orchestrator supplies native returns, never a child's summary. `roles.mjs result` remains a direct contract inspector for explicit fixtures/probes; it does not replace ordinary inventory or its observation boundary.

Supply one invocation per child instance: exactly one Start and one Stop, with all tool starts between them. Repeated Start/Stop or tool starts after Stop make the result UNREACHED, including an unfinished follow-up after an earlier successful verdict. Use a fresh child and call for another judgment instead of combining responses from a reused instance.

Missing identity, missing/unregistered SIGNAL, interrupted execution, stale registration and self-judgment produce `UNREACHED`: the standalone `roles.mjs` inspector returns rc 1; the ordinary `workflow.mjs` consumer returns rc 2. Preserve the task and wait for a human under develop's procedure. Only an independently reached evaluator MATCH can ground ordinary close; the explicit human scope-excess decision in verify-implement remains its own branch. A passing test or parent-written SIGNAL cannot replace delegated judgment.

The existing guard owns file/Git/ledger permissions through the common identity mapping. Role prompts and generated registration alone are not enforcement: disabled or unidentified hooks invalidate the runtime capability prerequisite. Transcript layouts are not used by this contract.

Ordinary paths and immutable storage are owned by [Runtime state](state.md); [Runtime observations](transcripts.md) owns their workflow consumer and optional transcript decoders. Missing ordinary call/outcome association is UNREACHED. Doctor evidence remains diagnostic.
