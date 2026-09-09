# Common command notation

Resolve `<plugin-root>` to the loaded harness artifact's absolute directory and
`<harness-root>` to the repository root given in the session or delegation. The
runtime adapter supplies the plugin location; `.harness.json` identifies the
repository-owned configuration. A worktree path is not a substitute for the
delegated harness root.

Procedure bodies use the following notation. Expand it before running a command;
these names do not require installing shell aliases or adding scripts to PATH.
Quote each path argument, including paths with spaces or Korean characters.

| Notation | Invocation |
|---|---|
| `ledger <arguments>` | `node "<plugin-root>/scripts/ledger.mjs" --root "<harness-root>" <arguments>` |
| `workspace <arguments>` | `node "<plugin-root>/scripts/workspace.mjs" <arguments>` |
| `board <arguments>` | `node "<plugin-root>/scripts/board.mjs" --root "<harness-root>" <arguments>` |
| `board-check` | `node "<plugin-root>/checks/board-check.mjs" --root "<harness-root>"` |
| `rules-check` | `node "<plugin-root>/checks/rules-check.mjs" --root "<harness-root>"` |
| `ledger-check` | `node "<plugin-root>/checks/ledger-check.mjs" --root "<harness-root>"` |
| `workspace-check <repo>` | `node "<plugin-root>/checks/workspace-check.mjs" <repo>` |
| `guardrail-check` | `node "<plugin-root>/checks/guardrail-check.mjs" --root "<harness-root>"` |
| `guard-log <arguments>` | `node "<plugin-root>/scripts/guard-log.mjs" <arguments>` |
| `transcript <arguments>` | `node "<plugin-root>/scripts/transcript.mjs" <arguments>` |

Use `ledger --help` for supported commands and flags. Write bodies with the file
tool first, then pass `--file`, `--body-file`, `--reason-file`, `--acceptance-file`
or `--title-file` as supported by that command. This preserves literal content
without shell command substitution. Read JSON results directly or use a native
JSON consumer; a jq pipeline is not an installation requirement.

`guardrail-check` checks the plugin and temporary offline fixtures; supplying the
repository root does not turn it into a live ledger or runtime activation check.

Run the repository's gate with
`node "<plugin-root>/scripts/config.mjs" run "<worktree>" check`. The common runner
preserves its exit status and output. Structured argv is the native command
contract; a repository's existing string command retains explicit Bash semantics.
Changing that repository-owned command is a separate migration, not something
the plugin silently rewrites.

The old `.sh` entrypoints remain POSIX convenience wrappers. Windows native
procedures use the Node entrypoints above. Read [platforms.md](platforms.md) for
host and backend requirements and [installation.md](installation.md) before
claiming that an installed artifact or its hooks and roles are actually loaded.
