# Runtime state

`lib/state.mjs` owns state paths and writes. Runtime state is observation and coordination data; repository `.harness.json` and the ledger remain the configuration and work sources. Preparation ownership remains in Git worktree metadata and is shared by both runtimes.

## Identity and paths

Commands accept an explicit runtime, repository cwd and session ID. Hooks use the event's session ID/cwd and the plugin execution environment. `HARNESS_RUNTIME=claude|codex` is an explicit selection; a conflicting Codex plugin marker is rejected. Codex's native `PLUGIN_ROOT`/`PLUGIN_DATA` identify Codex before considering its Claude compatibility variables. With those native markers absent, `CLAUDE_PLUGIN_DATA` identifies Claude plugin execution. `CLAUDE_PLUGIN_ROOT` alone identifies neither runtime. A standalone Bash hook without sufficient identity reports UNREACHED; it does not silently select Claude. This environment contract follows [Codex plugin hooks](https://learn.chatgpt.com/docs/hooks) and [Claude hook variables](https://code.claude.com/docs/en/hooks), not transcript-path guessing.

The base priority is `HARNESS_DATA_DIR`, selected runtime plugin data (`PLUGIN_DATA`, then compatibility `CLAUDE_PLUGIN_DATA` for Codex; `CLAUDE_PLUGIN_DATA` for Claude), then the selected runtime's home plugin-data directory. Paths must be absolute. The resolver appends `v1/<runtime>/repos/<sha256 canonical Git common-dir>/sessions/<sha256 session-id>`. Main and linked worktrees share repository identity; unrelated clones and runtimes do not. Session strings never become path components. The repo-level guard TSV aggregates sessions; cancellation, actor bindings, Stop logs and workflow records stay session scoped.

`node <plugin>/scripts/state.mjs paths <runtime> <repo> <session>` prints the resolved paths. `guard-log.sh` uses the same resolver; set `HARNESS_RUNTIME` and the active hook data directory when calling it outside a plugin hook. Its cwd selects the repository. Hook cwd is session context, not verified shell execution cwd.

## Confirming an actor and resuming

After `ledger.sh update <task> --claim --actor <actor>` succeeds, run:

```text
node <plugin>/scripts/state.mjs bind <runtime> <repo> <session> <ledger-root> <task> <actor>
```

Use the actual session ID supplied by the runtime event/context, or a runtime-specific session identifier you have verified. SessionStart supplies runtime, repository, session ID and actual data directory in additionalContext. Pass that directory as `HARNESS_DATA_DIR` on ordinary bind/cancel calls. Hook environment variables are not assumed to propagate into ordinary tool subprocesses. A home-directory fallback is only an unverified lookup: bind/cancel refuse it because a marketplace-scoped runtime data directory may differ. Bind requires explicit arguments; it does not infer success from a command string or a PreToolUse event. The command re-reads the task through the configured ledger adapter and checks ID, `in_progress` and actor. The ledger root must belong to the same canonical Git repository as the session; use that repository's own `.harness.json` to select shared ledger coordinates. A new resumed session may explicitly bind the existing ledger actor. The actor is never derived from the session ID.

A bind failure does not undo or re-run a successful claim. Diagnose the state/read failure and retry bind; report claim success and mapping UNREACHED separately. The Stop guard scopes work only through confirmed bindings. Missing or unverified mappings retain the whole-ledger fallback, with SCOPE_FAIL; they do not mean no work exists.

## Cancellation and compatibility

```text
node <plugin>/scripts/state.mjs cancel <runtime> <repo> <session>
```

Cancellation persists for exactly that scope. Another session never acquires it by observing it first. Legacy `stop-resume-cancel` markers and actor TSVs are preserved as UNVERIFIED, without moving, deleting or treating them as successful bindings. Create an explicit scoped cancellation or re-bind through the ledger to migrate. Rollback can still read the untouched legacy files.

`HARNESS_GUARD_LOG` continues to select an explicit legacy TSV for reads and minimal metadata writes; missing runtime/repository identity is diagnosed as UNVERIFIED. `HARNESS_SESSION_ACTOR_LOG` remains a legacy read location and is never overwritten or promoted automatically. Historical TSV rows can still be counted/classified by `guard-log.sh`, but their runtime/repository identity and claim success are not established. New guard rows contain only time, escaped session, role, tool and rule; raw commands and targets are not retained. Rows without commands cannot certify an old false-positive classification.

## Persistence and evidence

Append and rotation share a per-file directory lock, with a PID/token owner and bounded wait. Lock failure produces an explicit diagnostic. No lock is stolen by age or dead-PID guesses: after a crash, inspect the owner and stop conflicting writers before manually recovering the lock. Guard logging failure does not change the policy decision; Stop failure does not trap the user. Neither failure becomes a successful observation. Guard rotation retains recent rows and one previous generation; counts cover retained rows only. Stop/event logs are not rotated, preserving session limits and event chains. Writes use restrictive permissions and atomic JSON replacement; this is local coordination, not protection from another process with the same user's filesystem access.

The shipped wrapper records ordinary native event metadata even without doctor configuration: session/agent/tool/event IDs, hook rc, timestamp and only the first SIGNAL line. It omits commands, payload bodies and transcript contents. `storeWorkflow`/`readWorkflow` in the state module provide immutable scoped call/outcome/result storage for the runtime adapter. Storage alone validates no role result: missing call/outcome association remains UNREACHED until the role contract validates the matching observed instance. Doctor receipts stay a separate diagnostic contract and cannot substitute for ordinary task evidence. Transcript parsing belongs to the runtime adapter.
