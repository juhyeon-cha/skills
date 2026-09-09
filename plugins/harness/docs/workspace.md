# Workspace commands

Use `node <plugin>/scripts/workspace.mjs` with absolute paths. Replace `<plugin>` with the loaded plugin root. Commands return JSON; diagnostics go to stderr and errors return nonzero.

```text
create <repo> <story> [--destination <external-path>]
inspect <workspace>
enter <workspace>
cleanup <repo-or-current-workspace> <story> [--force]
```

`create` checks the story's `repo:` label through the existing ledger adapter, fetches origin, and creates `worktree-<name>` from `origin/<default_branch>` (or origin's symbolic HEAD when no default is configured). The name comes from `lib/worktree-name.sh`. Default destination remains `<main>/.claude/worktrees/<name>`. An existing path or branch is an error: inspect the existing registration and resume it with `enter`. Creation alone does not establish preparation readiness.

`inspect` verifies Git top-level, git-dir/common-dir, worktree registration and branch agreement. A directory underneath a repository is not a workspace root merely because Git can find its parent. Linked worktrees outside the main checkout are valid; main checkouts return `linked: false`. Filesystem aliases are resolved before comparison. `HARNESS_ROOT` selects the ledger, independently of this Git identity. Git location overrides inherited from hooks are removed from Git child processes.

`enter` requires a registered linked workspace on a `worktree-<name>` branch. It wires the existing ledger adapter and preserves local exclude entries. The transitional preparation path retains the repository's `.harness.json` bootstrap and legacy sibling marker. A repository EnterWorktree hook produces `external-hook-unverified`; it does not prove that the hook succeeded. Without that hook, a failed bootstrap leaves the workspace and no new marker, allowing retry. This compatibility path is not a lock, fingerprint or crash-safe readiness protocol. Read [config-process.md](config-process.md) before changing the bootstrap command format.

Claude's `hooks/enter-worktree.sh` is a PostToolUse transport into `enter`; its errors exit 2 after the native tool has already run. Codex invokes the same CLI. After entry, set subsequent commands' cwd to the returned `top`. Main-checkout guard permission recognizes only a single literal `node '<plugin>/scripts/workspace.mjs' ...` invocation with this argument contract. Variables, compound commands and arbitrary Node scripts receive no workspace exception. Quoted absolute paths support spaces and Unicode. Reviewers and evaluators can inspect but cannot mutate the workspace lifecycle.

`cleanup` selects the registration by expected story branch, so an external linked path does not need a separate setting. It refuses the caller's current directory, dirty worktrees, mismatched identity, locked workspaces and fetch failures. `--force` skips only the unpushed-commit check. Ignored files are reported before removal. Removal targets one registration; it never prunes unrelated absent worktrees. A branch-delete failure after worktree removal reports partial progress with nonzero exit. The compatibility `workspace-cleanup.sh <story> [--force]` retains its tab-separated removed-repository/path output and never reports an untouched target as removed. Neither command verifies PR merge status.

`checks/workspace-check.sh [workspace]` validates repository config and inspects Git identity without ledger writes or remote access on every backend. Development roundtrip tests replace only adapter boundaries in temporary plugin copies and use local bare origins.

Git and Node must be available. Ledger calls and story-name conversion still require Bash, and ledger adapters may require jq and backend clients. This shared core does not establish native Windows support for those adapters. Current native filesystem evidence must be reported separately from lexical Windows path fixtures.
