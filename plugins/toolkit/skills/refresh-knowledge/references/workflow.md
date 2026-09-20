# States and recovery

Project metadata lives in `project.sqlite3`, with immutable JSON handoff artifacts under `runs/`.
The run ID identifies its baseline, after snapshot and bindings. SQLite transactions serialize
commands and advance the completed baseline plus run state together; a second writer fails busy.
Agent/model calls happen between commands, outside database locks. Never edit database rows manually.

| Phase | Next action |
|---|---|
| awaiting_decisions | Read context, author decisions, then prepare |
| awaiting_review | Delegate the returned packet to toolkit:review-knowledge |
| revise | Repair concrete findings, prepare a new packet, review again |
| blocked | Resolve missing evidence or the actual policy decision |
| ready | Passing review is stored; resume applies it |
| applying | Previous apply may have been interrupted; resume the same run |
| completed | Completion is recorded; start the next source revision |

Starting the same active revision returns that run instead of duplicating it. A different revision
is rejected until the active run is completed. Starting the current completed commit validates
current evidence/documents and reports unchanged. No second run or model call is needed.

The applying phase and review are committed before document writes. If interrupted after some
files change, the transaction advancing the project baseline does not commit; another process
can resume with the stored packet/review. Exact target files are skipped; a third content is refused.
A completion-artifact write failure is recoverable with the same run. A conflicting or partial
artifact is preserved and reported, not overwritten. Resolve the corrupt artifact from its original
record before retrying; the CLI never interprets its existence alone as completion.

After all document checks and completion storage succeed, the project adopts the after snapshot
and next bindings atomically with the completed status. The next `start` obtains these automatically.
A historical completed run is a record, not permission to roll back a newer completed baseline.

The database protects commands sharing this project; arbitrary editors and other project databases
are outside that coordination. Document changes are file-wise, not one all-file transaction. Process
interruption recovery is supported; power-loss durability and metadata preservation beyond mode bits
are not promised. Remote publication is not part of any command. Review IDs bind content, not reviewer
authenticity: preserve the actual independent agent response rather than self-authoring approval.

## End an unrecoverable run or change scope

`terminate --run ID --reason-file FILE` ends an active run before application, preserves its
artifacts and baseline, and releases the active slot. The same baseline/change/intake identity remains terminated;
use a reviewed successor project to reconsider it. A later revision may start only if the original
baseline documents still match. A terminated run cannot resume or prepare.

For partial application, corrupt exported artifacts without a trusted original, persistent document
conflicts, or scope changes, use `retire --reason-file FILE --successor /separate/new-project`.
This preserves all files and the database and writes a retirement marker. It never rolls back
partially written documents or advances the old baseline. Status validates exported context and reports corruption when present; execution
writes and intake registration are refused. Repeating retirement requires the same reason and
successor. This is logical quarantine, not a filesystem security boundary.

Inspect each current document and source revision, resolve conflicting edits using evidence,
and initialize the separate successor with a freshly reviewed baseline spec and scope. The
successor path is a handoff, not proof it was initialized. Keep the old project for diagnosis.
If the database itself is unreadable, preserve the whole directory and use this same successor
procedure without attempting a migration or claiming retirement succeeded. Never reinitialize
an existing project or reconstruct state by editing database rows.

## Intake-bound review and handoff integrity

Packets without intake retain version 1 and their original content identities. Version 2 requires
an entire validated immutable intake record, including source text, declared authority, versions,
acceptance criteria and remaining differences. Its content hash binds that record with the plan.
A changed intake therefore needs a new independent response even when the document plan is identical.
Review and resume refuse an intake run whose stored packet omits or differs from its intake.
Prepare a fresh packet and review before application; retire an already-applying legacy run to a
reviewed successor. This is a packet contract change, not a database migration. Historical v1
review replay establishes only its original no-intake review scope.

Before status, repeated start, prepare, review or resume exposes or changes a run, the exported
context must equal the immutable fields stored in the database. Missing, malformed, changed and
symlink context files fail with their path and recovery guidance. Preserve damaged artifacts;
restore only a trusted original before retrying. The CLI never recreates a missing context during
reentry. Terminate before application or retire after partial application remains available even
when context is corrupt. Keep the old directory and inspect documents before initializing a successor.
