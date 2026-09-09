# Platform boundaries

Choose a runtime and backend using the following boundaries before setup. A Node file extension or a passing core fixture does not establish the complete runtime workflow.

| Execution path | Contract |
|---|---|
| Node structured argv, config, operation normalization, Git workspace inspection | Common code; each host must execute the native core suite to establish its own result. Windows drive/UNC lexical fixtures on another host prove parsing only. |
| Workspace create, enter and cleanup | Node orchestration still calls the Bash ledger adapter. Inspection alone does not establish these lifecycle paths. |
| Configured workspace preparation | POSIX process-group ownership; native Windows returns `PREPARE_UNSUPPORTED`. A repository with no preparation command has a separate no-op contract. |
| Hook transport and guard | Bash/jq policy consumers remain. Native Windows hook execution and enforcement are unestablished. |
| Ledger backends | Shared Bash/jq frontend; GitHub additionally uses gh, beads uses bd, Notion uses curl. POSIX utilities and backend-specific credentials/services remain prerequisites. Presence of these tools does not prove a ledger operation succeeded. |
| Legacy command strings | Explicit Bash semantics. Structured argv bypasses the shell; Windows implicit `.cmd`/`.bat` and shebang launch are unsupported. |
| Git Bash / WSL | Transitional environments, each requiring its own integration evidence. Neither certifies native Windows behavior. |

Use `UNSUPPORTED` for a path the implementation explicitly refuses, `UNREACHED` for missing execution evidence, and `PASS` only for the measured scope on the reported host. Full native Windows support requires actual hook, role, workspace, configured preparation and ledger results; a green core CI job cannot substitute for them. Installation, load and live execution remain separate doctor judgments. Current implementation and host measurements are recorded in skills#266.

The source repository runs `node tests/harness/platform-contract-check.mjs <darwin|linux|win32> <report.json>` directly on each CI host. The report includes reached judgments, native Node/Git versions, dependency boundaries and a separate full-product verdict. The Bash wrapper is a POSIX convenience only. The suite uses disposable local Git repositories and has no remote ledger operations or credential requirements.

Windows process launch restrictions follow [Node child process documentation](https://nodejs.org/api/child_process.html#spawning-bat-and-cmd-files-on-windows). Host matrix and shell behavior follow [GitHub workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax).
