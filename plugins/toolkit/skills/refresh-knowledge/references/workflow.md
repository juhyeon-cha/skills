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
