# Workspace commands

Use `node <plugin>/scripts/workspace.mjs` with absolute paths. Replace `<plugin>` with the loaded plugin root. Commands return JSON; diagnostics go to stderr and errors return nonzero.

```text
create <repo> <story> [--destination <external-path>]
inspect <workspace>
enter <workspace>
prepare <workspace>
ready <workspace>
cleanup <repo-or-current-workspace> <story> [--force]
```

`create` checks the story's `repo:` label through the existing ledger adapter, fetches origin, and creates `worktree-<name>` from `origin/<default_branch>` (or origin's symbolic HEAD when no default is configured). The name comes from `lib/worktree-name.sh`. Default destination remains `<main>/.claude/worktrees/<name>`. An existing path or branch is an error: inspect the existing registration and resume it with `enter`. Creation alone does not establish preparation readiness.

`inspect` verifies Git top-level, git-dir/common-dir, worktree registration and branch agreement. A directory underneath a repository is not a workspace root merely because Git can find its parent. Linked worktrees outside the main checkout are valid; main checkouts return `linked: false`. Filesystem aliases are resolved before comparison. `HARNESS_ROOT` selects the ledger, independently of this Git identity. Git location overrides inherited from hooks are removed from Git child processes.

`enter` requires a registered linked workspace on a `worktree-<name>` branch. It wires the existing ledger adapter, preserves local exclude entries and calls common preparation. `prepare` runs only preparation; `ready` checks whether implementation may be delegated and returns nonzero otherwise. Both Claude and Codex consume the same `.harness.json` bootstrap. Read [config-process.md](config-process.md) before changing its command format.

Preparation hashes the exact config bytes and the contents of explicitly declared `preparation.inputs` files. A matching receipt from a successful command, with no active lock, gives `ready: true` and `canDelegate: true`. Changed commands or inputs require another preparation. Changes during execution invalidate its result. Environment changes and undeclared files are not fingerprinted: declare every preparation input the repository needs. Commands must be finite and must not daemonize or escape the worker's process group.

Optional `preparation` settings are `timeout_ms` (positive integer, default 300000) and `inputs` (relative regular-file paths inside the workspace). No language-specific lockfile names are inferred. A missing/null/empty bootstrap and no repository EnterWorktree hook gives `not-configured`, `ready: false`, `canDelegate: true`: preparation is unnecessary, so delegation may proceed. A repository-owned EnterWorktree hook instead fails with `LEGACY_HOOK_UNVERIFIED`, even if a bootstrap or old marker exists. To migrate, move its preparation command to `.harness.json` and remove that hook's duplicate execution in the same repository change. Keep a previous config/hook revision for rollback. Old `.bootstrapped-*` markers never establish readiness.

State lives under the linked workspace's actual Git directory through `preparationPaths`, shared across runtimes and removed with Git's worktree metadata. An independent POSIX worker owns a PID/token lock and process group. Duplicate callers wait for that group and reuse its completed receipt. Ending a waiter leaves the worker running. A failed command leaves no new ready receipt and preserves the workspace. Timeout kills the worker group; a crashed worker's lock is recoverable only when both owner and group are gone. A live descendant, malformed owner record, or abandoned recovery claim fails closed; age alone never steals a lock. Diagnose these states before manual intervention. Do not delete a lock while its worker or descendants run. A crash before lock-owner publication can require manual recovery because ownership could not be established.

Repository hook detection conservatively includes regex or catch-all PostToolUse matchers covering EnterWorktree. A generic hook can narrow its matcher to exclude that event. Only the workspace's settings.json/settings.local.json are inspected here; runtime-loaded global hooks belong to runtime diagnostics and are not discovered by this preparation module.

Preparation requires POSIX process groups and `ps`; native Windows command preparation reports unsupported until a process-tree adapter is verified. WSL evidence is Linux evidence, not Windows-native support. Background processes that deliberately escape the group cannot be supervised by this contract.

Claude's `hooks/enter-worktree.sh` is a PostToolUse transport into `enter`; its errors exit 2 after the native tool has already run. Codex invokes the same CLI. After entry, set subsequent commands' cwd to the returned `top`, then require `ready` success before implementation delegation. Main-checkout guard permission recognizes only a single literal `node '<plugin>/scripts/workspace.mjs' ...` invocation with this argument contract. Variables, compound commands and arbitrary Node scripts receive no workspace exception. Quoted absolute paths support spaces and Unicode. Reviewers and evaluators can inspect and check readiness but cannot mutate the workspace lifecycle.

`cleanup` selects the registration by expected story branch, so an external linked path does not need a separate setting. It refuses the caller's current directory, dirty worktrees, mismatched identity, locked workspaces and fetch failures. `--force` skips only the unpushed-commit check. Ignored files are reported before removal. Removal targets one registration; it never prunes unrelated absent worktrees. A branch-delete failure after worktree removal reports partial progress with nonzero exit. The compatibility `workspace-cleanup.sh <story> [--force]` retains its tab-separated removed-repository/path output and never reports an untouched target as removed. Neither command verifies PR merge status.

`checks/workspace-check.sh [workspace]` validates repository config and inspects Git identity without ledger writes or remote access on every backend. Development roundtrip tests replace only adapter boundaries in temporary plugin copies and use local bare origins.

Git and Node must be available. Ledger calls and story-name conversion still require Bash, and ledger adapters may require jq and backend clients. This shared core does not establish native Windows support for those adapters. Current native filesystem evidence must be reported separately from lexical Windows path fixtures.
