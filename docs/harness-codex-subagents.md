# Codex subagents: native configuration and ordinary delegation

Read this when changing Codex role registration or diagnosing a mismatch between
native configuration and ordinary subagent behavior. The operating procedure is
[roles.md](../plugins/harness/docs/roles.md).

## Native roles

Harness assembles `roles/<role>.md` with `native/codex/<role>.toml` through
`scripts/roles.mjs register codex`. Registration and its receipt establish generated
files, not runtime discovery or invocation. A native delegation tool must actually
select the registered identifier before execution can establish native loading.
Prompting an ordinary child with a role name is not that evidence.

The shipped Claude and Codex templates omit model declarations and inherit runtime
settings. Runtime-specific settings belong in their native templates. The read-only
`roles.mjs explain` command shows the canonical body and declared native template;
it does not report an observed execution model or dispatch an agent.

## Ordinary subagents

Use the runtime's ordinary delegation tool directly with the responsibility,
repository, requirements and identified review scope. Inspect its actual returned
findings. Model selection belongs to the caller or runtime settings; Harness has
no generic model-preference layer, invocation inventory or begin/bind/complete
protocol. Reuse or create a child according to the task and independence needed.

Ordinary tool execution does not consult provider metadata or a delegation
inventory to establish a role. Known native roles retain their concrete tool
restrictions; common child safeguards still apply to ordinary children. Neither a
prompt nor an allowed tool call proves a read-only permission boundary.

## Verification boundary

Configuration and fixture tests establish source assembly and tested contracts.
They do not establish that an installed runtime discovered a role, used a particular
model, activated hooks or enforced permissions. Claim those only after observing
the corresponding behavior in that runtime. When a native role selector is
unavailable, ordinary delegation remains usable; an explicitly required native
audit remains unverified.
