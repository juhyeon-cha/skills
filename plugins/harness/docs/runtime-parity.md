# Shared runtime configuration

The harness shares repository policy and implementation across Claude, Codex and
Antigravity CLI. Each runtime receives its own configuration format. This is not
a synchronization of every provider setting or a claim of full live equivalence.

## Sources and projections

| Source | Claude | Codex CLI and desktop | Antigravity CLI |
|---|---|---|---|
| Repository `.harness.json` | Same repository file | Same repository file | Same repository file |
| `skills/*/SKILL.md` | Original skill directories | Original skill directories | Flat `skills/*.md` with resolved plugin-root references |
| `agents/*.md` | Original role Markdown | Generated `harness-*.toml` with `developer_instructions` | Generated agent Markdown with tool/model frontmatter |
| Hook handlers | `hooks/hooks.json` | Manifest selects `hooks/codex.json` | Generated root `hooks.json`: PreInvocation, PreToolUse, Stop |

`lib/distribution.mjs` generates Claude/Codex metadata from the common hook
registry. `lib/runtime/parity-install.mjs` prepares owned bundles and uses
`lib/runtime/roles.mjs` for role projections. Antigravity keeps the shared runtime
under the bundle's `.harness/` directory. Hook adapters translate provider events
into the common guard, state and Stop handlers.

## Provider-owned settings

Claude settings, Codex `config.toml`, and Antigravity user/workspace settings
remain provider-owned. Model selection, sandbox/approval policy, plugin enablement
and hook trust are not overwritten or made identical by bundle preparation.
Models inherit runtime settings unless a supported selection is supplied;
there is no cross-provider model-name equivalence.

For Codex, the plugin manifest selects its hook JSON; role registration writes
TOML to the explicitly supplied agents directory. Bundle staging does not generate
or merge a project `config.toml`. Enablement and trust use the provider's supported
installation flow. CLI and desktop share projections but may have different
loaded sessions and settings.

See [installation](installation.md) for activation and ownership, and
[runtime roles](runtime-roles.md) for role execution. Installation diagnostics
report their observed scope; preparing files does not prove session loading.
Keep regression checks focused on configuration projection and observed defects.
