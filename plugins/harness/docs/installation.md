# Runtime installation and diagnosis

Use this procedure from setup A, B or C. Repository-owned `.harness.json` remains the configuration source; installing or updating a plugin does not copy it.

## Common prerequisites

Check `node --version`, `git --version`, `bash --version`, `jq --version` and `python3 --version` before setup. The common Node commands require Node 22 or later. Bash, jq and Python remain dependencies of the existing policy/ledger checks; Node wrappers do not remove them. Add the selected backend's tools and credentials as setup specifies. macOS and Linux use the POSIX adapters; WSL is the transitional Windows route. Native Windows support is not established by these wrappers: Bash hooks and process-group preparation still need the later native adapter work.

Run `node <expected plugin source>/scripts/distribution.mjs check` to verify the generated metadata and shared source tree. Development builds regenerate with `generate`; version and description come exclusively from `.claude-plugin/plugin.json`. The Codex compatibility manifest uses the default `skills/` and `hooks/hooks.json` locations, so no second skill/hook tree is registered. A release copies the same plugin artifact; never hand-edit projections in an installed cache.

## Claude

Install at user scope with `claude plugin marketplace add juhyeon-cha/skills`, then `claude plugin install harness@skills`. Update with `claude plugin marketplace update skills` and `claude plugin update harness@skills`. Preserve the existing Claude plugin agents directory and hooks discovery. Check `claude plugin list` and the single user-scope entry in `~/.claude/plugins/installed_plugins.json` for installation inventory only. Setup's Claude scope migration handles older project/local duplicates.

Run `node <installed root>/scripts/roles.mjs register claude` and save the registration JSON. Restart the session after changes. Claude live evidence remains a separately tracked prerequisite (skills#268); fixtures establish compatibility, not current-session activation.

## Codex

Use a marketplace that contains the generated Codex manifest. Configure an explicitly selected local or Git marketplace with `codex plugin marketplace add <source>`, then `codex plugin add harness@<marketplace>`. `codex plugin list --json` gives inventory, not proof that the open session loaded the artifact. For updates, follow the installed CLI's marketplace upgrade/add procedure, then start a new session.

Register native agents explicitly using `node <installed root>/scripts/roles.mjs register codex <absolute CODEX_HOME/agents directory>` and save the JSON receipt. Plugin agent auto-discovery is not assumed. Keep one registration scope; verify other project/user agent directories and effective runtime discovery for duplicate names. The role contract's restricted TOML verifier rejects unsupported files in a shared directory. On update, compare old files against the old receipt first: preserve any differing/foreign file and resolve the conflict; remove only verified owned old projections, regenerate from the new installed root, and replace the receipt. The generator refuses a differing file rather than overwriting it. Roll back the installed artifact and its matching generated roles/receipt together.

Review the plugin's exact hook definitions in Codex `/hooks` and trust them before use. Installation does not grant trust. `features.hooks=false`, individually disabled hooks and managed-only policies may prevent execution. Resolve these through the runtime's supported settings; diagnosis does not enable hooks or change trust. The official hook contract supplies `CLAUDE_PLUGIN_ROOT` compatibility alongside `PLUGIN_ROOT`. See [Codex hooks](https://learn.chatgpt.com/docs/hooks) and [plugin packaging](https://developers.openai.com/plugins/build/plugins).

## Doctor: static, loaded and live

Run the doctor from the **expected source artifact**, passing the installed root: `node <expected source>/scripts/doctor.mjs check <installed root>`. Static PASS requires matching full content hashes and generated metadata, not equal version strings. Without current-session evidence, loaded/live are UNREACHED and the command exits nonzero. An open session using an earlier install remains unverified even when its version number equals the source version.

For an explicit diagnostic session, create a new private directory with `doctor.mjs challenge <new absolute state directory> <claude|codex> <installed root> <role registration.json>`. Launch the runtime with `HARNESS_DOCTOR_DIR` pointing there. The actual shipped wrapper runs each original hook and signs a nonce-bound receipt containing its result, executing root/version/content hash, session and role identity. SessionStart records the hash of the actual emitted context. After the diagnostic session completes, use `doctor.mjs check <installed root> <state directory> <actual session ID>` from the expected source artifact.

Loaded PASS requires the matching SessionStart context, successful guard execution and observed native starts for all registered roles in that session. Live PASS additionally requires successful Stop execution and each role's complete same-instance result contract. A diagnostic delegation may report a source-defined decision signal: that proves role invocation, not task acceptance. Observe all roles in a disposable fixture; normal setup does not mutate a real task merely to satisfy diagnosis. EnterWorktree's matcher is statically verified here; this probe does not prove that lifecycle event fires in Codex.

Codex's Bash hook `cwd` can remain the session directory when `exec_command` actually runs in a different explicit workdir; the observed hook input carries only `command`. Treat that cwd as session context, not verified process cwd. Doctor PASS proves registration and hook/role execution only; it does not establish complete protection of relative shell writes or visibility of execution workdir. Preserve this uncertainty instead of inventing a workdir from the command text. The isolated probe retains a safe cross-directory `pwd` observation separately from product receipts.

Receipts expire after thirty minutes and belong to one challenge and session. Missing, altered, stale, wrong-source or cross-session receipts cannot certify load. Hooks disabled or untrusted cannot emit receipts, so an external doctor still reports UNREACHED. Boolean settings or caller-written success claims are not evidence. These private local records protect against accidental stale/altered observations, not a hostile process with the same user's filesystem access. They retain event/agent IDs, execution status, hashes and the first role-result line; raw commands and result bodies are omitted. Keep them private and remove them after diagnosis. The state directory is explicit pending the central state resolver. Transcript formats are not parsed.
# Skill registration names

Distribution inspection reads names only from the opening YAML frontmatter. It supports flat mappings with bare keys and lower-case hyphenated names written as plain, single-quoted, or JSON-compatible double-quoted scalars, including surrounding spaces and trailing comments. Names are decoded before duplicate detection. Duplicate keys, quoted keys, nested mappings, multiline names, tags, aliases, and unsupported escapes fail inspection; they are not treated as different registrations. A `name:` line in the Markdown body never supplies registration metadata.

## State compatibility

Runtime state paths, explicit claim binding and per-session cancellation follow [Runtime state](state.md). Existing Claude plugin-data execution variables select the Claude path without a new setting; standalone scripts need explicit runtime identity. Preserve old state files during migration or rollback. Ordinary event metadata is distinct from doctor receipts and does not independently prove a completed role contract.
