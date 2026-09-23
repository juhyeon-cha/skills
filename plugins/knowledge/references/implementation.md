# Continue an implementation handoff

Use this procedure after a behavior-change handoff, including when an implementation result
arrives later. It connects repository implementation evidence to the existing document update
flow. Goal completion is the agent's judgment; the CLI records immutable intake and document runs.

## 1. Establish the exact goal and authority

Read the existing caller-owned bundle and [intake](intake.md) record. Reuse the goal ID, content
version, intake ID, original instructions, acceptance criteria and remaining differences from
[bootstrap](bootstrap.md); freeze missing inputs before work. Compare them with the latest
authoritative goal and preserve any successor version separately. Confirm that the actual user
instruction or approved decision authorizes implementation in this repository and scope. Existing
explicit authorization is sufficient; document approval alone is not implementation authorization.

Keep links in the caller's existing task or bundle, without introducing another record format:
exact goal/intake and authority; source commit and document hashes; each acceptance criterion's
command, cwd, exit code and raw result with the source and test revisions/hashes used at that time;
actual independent implementation review input and response; project, document run and completion
receipt. A command against a subsequently edited working directory is not reproducible evidence.

Read public `status` and `intake-status` before deciding the next action. Compare existing results
and receipts against these exact identities before starting work; an identical completed result
needs verification of the existing state, not another implementation or document run.

## 2. Verify implementation against that version

Use the repository's implementation and verification workflow within the established authority.
For returned work, inspect the actual source changes and criterion results at the recorded versions.
Require every mandatory criterion to pass and an independent implementation review covering that
same goal and source. Preserve the reviewer's actual response; document review does not replace it.

If authority or required evidence is missing, or implementation checks/review fail, keep completion
pending, preserve the existing document baseline, and name each remaining difference and the needed
repair or evidence. Recheck the latest goal before accepting a result. A successful older result
belongs only to its reviewed goal version: retain it as historical evidence and assess the successor's
remaining differences; never mark the successor complete from that result. Reconcile an outdated
result with the current authorized source before selecting a document revision; do not roll back a
newer baseline to document it. Continue only with verified, applicable source and resolved authority.

## 3. Connect verified source to the document run

Read [project commands](project.md) and use the existing source-to-document flow in
[knowledge:update](../skills/update/SKILL.md). Inspect the project's settings, baseline and active run against
the actual repository and document bytes. For an existing run inspect `status --run ID` and follow
its next action. For a new verified source revision use `start --rev COMMIT`; keep the link to the
behavior-change intake in the caller-owned record. Do not pass that intake to `start --intake`:
only a current-documentation intake is accepted there. If no reviewed project baseline exists,
use the existing bootstrap procedure first.

Prepare source-backed decisions, obtain the existing independent document-packet review, import
that actual response, and `resume` the same run. Before application, recheck goal/source/document
identity against the reviewed evidence; reconcile changes and renew affected review. Follow
[states and recovery](workflow.md) for failures or interruption, preserving artifacts and the last
completed baseline rather than constructing a replacement result. An unchanged revision or a
previously completed run is checked against its existing documents and receipt, not duplicated.

Inspect final document bytes/hashes, the public baseline and actual completion receipt and link
them to the implementation evidence. Report separately: the exact goal version whose implementation
was verified, the document run's completed boundary, and remaining differences for the latest goal.
A target stated correctly in a document does not prove implemented behavior, and neither result
proves deployment. Historical intake remains immutable `pending_implementation` / `not_verified`;
this procedure adds no command to promote it to implemented or deployed.

## When a goal is deferred, withdrawn or rolled back

Read the latest authoritative decision and preserve the earlier goal, intake and results.
Record changed goal status through a new [intake](intake.md) and keep its relation to the
previous version in the caller-owned bundle. Inspect both current code and documents before
deciding the remaining effects; an older successful result does not revive a withdrawn goal.

Before document application, follow [recovery](workflow.md) to terminate the affected active run while
retaining its last completed baseline. After application or implementation, withdrawal alone
does not undo those changes. Treat an authorized rollback as a new change against the actual
current source and documents, verify its criteria and obtain the affected independent reviews.
Use the existing update route or a reviewed successor for changed structure or conflicts.

Keep deferred and withdrawn goals in historical/target records; describe any effects still
implemented as current behavior until a verified change removes them. A goal status alone is
not evidence that the current code changed.
Record which effects were preserved, which were reversed and which remain pending; do not
report rollback completion from the withdrawal intake or an unchanged historical receipt.
