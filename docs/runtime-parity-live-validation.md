# Candidate live validation

The final contract is all four required execution surfaces, not the success of
the adapter fixtures. Official product documentation remains primary; ECC is an
implementation reference. A candidate whose desktop execution has not run does
not meet the contract even when every CLI probe succeeds.

## Reproducible preparation

Run `node tests/harness/runtime-parity-live-prepare.mjs <new-absolute-directory>`.
It creates a disposable Git main checkout, three linked worktrees, a local bare
origin, and isolated bundles through the production installation adapter. The
prepared receipt records the canonical source hash and exact artifact paths.
It does not install into user profiles or grant trust. Antigravity receives the
project-discoverable projection. Codex receives project hooks, roles and skills;
the old `harness@skills` is disabled only in this disposable project to avoid
duplicate policy. Review that exact project and its hooks through the official
UI before claiming activation. Preparation remains static evidence.

For linked Codex worktrees, the
[official app-server hook contract](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)
reads matching root-checkout `.codex` declarations. Worktree-only hooks were
absent in actual discovery even after project trust. The preparation helper
therefore defines the root hook input before Git initialization. Preserve the
failed discovery control and record the new repository as a different baseline.

Use `runtime-parity-live-run.mjs <invocation.json> <new-observation-directory>`
under `tests/harness/` for explicit CLI invocations. The input holds `command`,
string-array `args`, `cwd` and optional `timeoutMs`. It captures stdout, stderr,
invocation, exit code and signal without parsing a successful transport as a
successful canary. It sets an isolated harness data directory and deliberately
does not create an unissued doctor challenge. Ordinary workflow observations
record the executing wrapper source and workspace. Raw artifacts stay local;
they can contain user paths, session identifiers and provider metadata.

## Evidence input

`node tests/harness/runtime-parity-evidence-check.mjs` runs **synthetic integrity
regressions**. Pass a bundle JSON path to check actual coverage. The two invocations
answer different questions; a successful no-argument test is not live acceptance.

The bundle contains `schemaVersion: 1`, the canonical `baseline`, four `reports`
from the shared parity contract, and `observations`. Each observation contains
`id`, actual `surface`, `version`, `sessionId`, `workspace`, `command`, `args`,
`repository`, `sourceSha256`, `configSha256`, `exitCode`, `signal`, `origin: live`,
`kind: provider-execution`, and `files`. Files have a bundle-relative `path`,
`sha256` and `kind`: invocation, stdout, stderr, exit or hook. Copy the relevant
state event snapshot into the bundle and hash it after the execution ends.

Every scenario's evidence contains `observationId`, a file `reference` belonging
to that observation, `assertion`, `expected` and `actual`, alongside the shared
surface/scenario/origin fields. Use provider output and actual effects for the
assertion. A model's assertion that a hook ran is not enough; retain the hook
record and actual tool outcome. A single invocation can cover several scenarios
only when it actually exercised each assertion. A different surface, old source,
missing file, interrupted run or incomplete scenario makes the check fail.

Integrity and normalized comparison are not authenticity. Even a matching bundle
keeps `liveCertified: false` and requires an independent evaluator to compare
the claimed semantic assertions with the raw records and verify independence.
Do not invent outcomes to fill a matrix. Preserve first failures and corrected
attempts separately, with the cause of each correction.

## Required remaining desktop step

The [official local-plugin workflow](https://developers.openai.com/plugins/build/plugins)
requires restarting the desktop app and testing changed plugins in a new chat.
The current desktop session running an older installed artifact cannot supply
the new candidate's live evidence. Prepare the candidate, exact project config,
hook review and handoff first. After the supported restart/new-chat step, capture
the actual desktop version, artifact source, session/workspace, hook output,
native or observed child identity, canary effects and completion. Never relabel
a CLI receipt as desktop, or substitute fixture roles for actual child loading.

## Native permission and ordering limits observed

Antigravity's [permission documentation](https://antigravity.google/docs/cli/permissions)
defaults non-workspace file reads and unconfigured commands to approval. A
headless read of the external candidate script was denied. The separate
operator-owned role API subsequently worked without retrying that read.
Reading a staged script is not the same as provider plugin installation;
this probe does not establish the permissions of a globally installed plugin.
Use an exact, harmless command approval in the supported TUI to measure required
shell tools; do not enable a global bypass to make the probe pass.

Native reviewer reads and result delivery completed under fast operator binding.
An earlier child reached its result before binding and was correctly denied;
fast binding is a positive control, not an ordering guarantee. A pending/ready
handshake must distinguish pre-registration idle from final completion while
retaining actual child identity, source checks and pre-registration write denial.

The reviewer shell `touch` canary passed the harness policy and was denied by
provider permissions. This matches the documented shell-mediated-write limit.
It must not be reported as a harness reviewer-write denial, and a successful
native file-tool denial must not erase that limitation.
