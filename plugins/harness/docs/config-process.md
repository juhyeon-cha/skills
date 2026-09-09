# Repository configuration and command execution

The repository owns `.harness.json`. `lib/config.mjs` reads that exact file in the supplied repository directory; it does not search parents, write a projection or choose a default ledger. The `validate` command prints the validated object, including extension keys. Do not print this output where repository extensions may contain secrets.

```sh
node "${CLAUDE_PLUGIN_ROOT}/scripts/config.mjs" validate <repo>
node "${CLAUDE_PLUGIN_ROOT}/scripts/config.mjs" run <repo> bootstrap
node "${CLAUDE_PLUGIN_ROOT}/scripts/config.mjs" run <repo> check
```

`schema_version` is the repository configuration format, independent of the plugin's release version. Omission accepts the legacy format; the only explicit supported value is the integer `1`. Unsupported values, malformed JSON, a missing file, or an invalid known field fail before execution. UTF-8 with optional BOM and CRLF is accepted. Additional top-level and ledger keys remain intact.

`ledger.backend` must explicitly name `github`, `beads` or `notion`. Coordinates remain owned and consumed by the existing ledger adapters. Optional `owner` and `database_id` fields must be nonempty strings when present; `project` must be a positive integer. Missing coordinates can be supplied by adapter initialization and are not fabricated here. `default_branch`, when present, is a nonempty string. A missing `check` cannot be executed.

`check` and `bootstrap` accept a nonempty string or an object with exactly one `argv` array. Its first item is a nonempty executable name or path; remaining items are strings, including empty strings. NUL is rejected. For example:

```json
{
  "schema_version": 1,
  "ledger": {"backend": "beads"},
  "default_branch": "main",
  "check": {"argv": ["node", "scripts/check.mjs", "argument with spaces"]},
  "bootstrap": "npm ci"
}
```

A string runs as `bash -c <unchanged string>`, in the supplied repository directory and environment. It never changes silently to PowerShell, cmd or `/bin/sh`. If Bash is unavailable, launch fails. Missing, null or empty-string `bootstrap` means no preparation command; `configCommand` returns `null`, and the CLI explicitly reports that no process started. The caller owns preparation state and retry decisions.

A structured command passes its arguments separately with `shell: false`. Spaces, Unicode, quotes, newlines and shell metacharacters in arguments are literal. The runner inherits the supplied environment and closes stdin; it captures stdout/stderr as buffers. It does not install dependencies or alter environment variables. Use the API for finite commands whose output can be buffered; streaming, cancellation and preparation lifecycle belong to the consuming workspace command.

`runCommand` returns `status` (`exited`, `signaled`, `spawn_error`), `code`, `signal`, output buffers and an error code/message on launch failure. A nonzero child exit is distinct from a missing executable. The CLI preserves child exit codes and both output streams. For signals it appends structured completion metadata to stderr and exits with `128 + signal number`; it does not claim that the CLI itself received that signal. Configuration errors and launch errors return nonzero.

Executable discovery is centralized in `lib/process.mjs`. Explicit relative executable paths resolve against the supplied cwd. POSIX PATH entries retain order, including empty entries meaning cwd; an absent PATH has no implicit fallback. Windows candidates use case-insensitive PATH/PATHEXT names, semicolon separation, drive and UNC paths. No implicit Windows current-directory search is added. Drive-relative and current-drive-rooted executable paths are rejected as ambiguous. `.cmd`/`.bat` files are unsupported instead of being joined into a cmd command string; use a native executable such as Node with a script argument. Other Windows script extensions are also refused. Windows candidate fixtures on another OS establish lexical behavior only; native Windows execution support requires a Windows run.

This CLI/API is an incremental consumer of the shared configuration. Existing Bash hooks and ledger adapters keep their current readers and execution paths. Do not migrate a repository's preparation or check field to structured argv until the entry point consuming that field uses this contract. Workspace preparation integration is a separate step; this layer does not infer whether an EnterWorktree hook ran.
