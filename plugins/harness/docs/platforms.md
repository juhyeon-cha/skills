# Platform boundaries

Choose a runtime and backend using the following boundaries before setup. A Node file extension or a passing core fixture does not establish the complete runtime workflow.

| Execution path | Contract |
|---|---|
| Node structured argv, config, operation normalization, Git workspace inspection | Common code; each host must execute the native core suite to establish its own result. Windows drive/UNC lexical fixtures on another host prove parsing only. |
| Workspace create, enter and cleanup | Common Node orchestration and ledger adapter, using Git registration instead of directory names. Inspection alone does not establish mutation, preparation or cleanup results. |
| Configured workspace preparation | POSIX process-group ownership; Windows Job Object ownership through Windows PowerShell 5.1 and in-memory C# compilation. Windows 10 / Server 2016+ is required; absent/restricted helpers fail UNREACHED. A repository with no preparation command has a separate no-op contract. |
| Hook transport and guard | One Node policy implementation with runtime-specific launch metadata. Direct handler and transport tests are separate from the runtime actually loading, trusting and firing the hook. |
| Ledger backends | One Node frontend and provider adapters. GitHub uses native gh, beads uses native bd and Dolt for its sync contract, and Notion uses Node HTTPS fetch. Provider tools, credentials and services remain prerequisites; their presence is not a successful ledger operation. |
| Operational checks and projections | Node board, rules, ledger, workspace and guardrail commands; legacy shell entrypoints only forward to them. Fixture success does not establish access to a user's live ledger. |
| Legacy command strings | Explicit Bash semantics. Native executable argv bypasses the shell. Windows `.cmd`/`.bat` use a constrained explicit cmd.exe adapter; unrepresentable arguments and other script extensions are refused. |
| Git Bash / WSL | Transitional environments, each requiring its own integration evidence. Neither certifies native Windows behavior. |

Use `UNSUPPORTED` for a path the implementation explicitly refuses, `UNREACHED` for missing execution evidence, and `PASS` only for the measured scope on the reported host. Full native Windows support requires actual hook, role, workspace, configured preparation and ledger results; a green core CI job cannot substitute for them. Installation, load and live execution remain separate doctor judgments. Current implementation and host measurements are recorded in skills#266.

The source repository runs `node tests/harness/platform-contract-check.mjs <darwin|linux|win32> <report.json>` directly on each CI host. The report includes reached judgments, native Node/Git versions, dependency boundaries and a separate full-product verdict. The Bash wrapper is a POSIX convenience only. The suite uses disposable local Git repositories and has no remote ledger operations or credential requirements.

The source also runs `node tests/harness/native-preparation-contract-check.mjs <host>` on each native CI host: shared readiness/retry/concurrency/timeout/fingerprint controls plus actual Windows batch, worker/supervisor crash, descendant, Job identity and missing-helper controls. Local non-Windows runs explicitly leave Windows-specific judgments UNREACHED.

Native ledger, operational-consumer and hook suites use offline fixtures and native
entrypoints. Report their reached populations separately from provider credentials,
CLI registration and live session observations. Bash/jq/Python used by a POSIX
developer regression runner are not hidden product requirements. A repository's
legacy Bash command string remains its explicit compatibility dependency. POSIX
preparation additionally uses the host's `ps` for owned process-group inspection.
The shipped guardrail check also uses `bash -n` on POSIX to validate retained
shell wrappers. This is a declared verification dependency; Windows validates
their source presence without executing Bash, and checks native modules with Node.

Windows Job ownership follows [JOB_LIST process creation](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-updateprocthreadattribute) and [Job Object lifetime](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects). Windows process launch restrictions follow [Node child process documentation](https://nodejs.org/api/child_process.html#spawning-bat-and-cmd-files-on-windows). Host matrix and shell behavior follow [GitHub workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax).
