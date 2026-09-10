# Native ledger boundary

`scripts/ledger.mjs` is the Node entry point. `scripts/ledger*.sh` remain legacy
transports; backend policy lives only in `lib/ledger/`. Node 22 or newer is the
common runtime. GitHub requires `gh`, beads requires `bd` (optional `dolt` for
sync inspection), and Notion uses Node HTTPS fetch. Bash, jq, Python and curl are
not dependencies of these native backend paths. Legacy Bash preparation strings
retain their separate Bash requirement.

The entry point accepts `--root <absolute directory>` before the command. Without
it, `HARNESS_ROOT`, then the nearest ancestor `.harness.json`, resolve the root.
Repository configuration remains in that file; no backend copy is generated.
`--commands` returns the shared command inventory without loading configuration
or contacting a provider. Existing commands and beads passthrough remain.

`executeLedger(argv, {root, cwd, env, input, inheritStdin})` returns
`{code, stdout, stderr}`. Input is a Buffer; output fields are strings. A failed
provider call is not an empty successful result. The library also accepts process
and request functions for dependency injection. The production CLI exposes no
environment variable for replacing policy modules, API hosts or fixture tools.

`create --title-file <file>` replaces its positional title;
`init --title-file <file>` replaces `--title`. `create` and `update` accept
`--acceptance-file <file>`. These options read files relative to the caller's cwd
and pass content as argument data; duplicate inline/file values fail before a
provider mutation. A trailing newline is removed as with existing body-file
handling. `--title-file` on update is unsupported because the existing common
update contract does not change titles.

Workspace and session actor verification invoke the native entry point using an
explicit root. `worktree-name.mjs` owns story-name conversion, with the existing
default workspace paths unchanged. Session cancellation can receive
`scripts/state.mjs --data <absolute directory>` outside a hook environment.

The identical native ledger fixture runs on macOS, Linux and native Windows CI,
with function transports and no live writes. The legacy POSIX adapter corpus
retains its backend response cases and membership mutation control. Its Notion
preload rejects unconfigured network access. Passing fixtures establish these
contracts, not installed CLI credentials, provider write permissions, real hook
firing or whole-product native support. Existing provider query ceilings remain
(for example GitHub blockedBy truncation is an error, and Notion note reads retain
the first 100 blocks); this port does not invent completeness beyond them.
