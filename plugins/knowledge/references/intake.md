# Change intake and implementation handoff

Use `knowledge.py --project DIR intake --input FILE` before selecting a route for a user,
document, or code change. `intake-status --intake ID` reconstructs and checks that immutable
record without the original input path. Intake also works before Git/project initialization,
so missing implementation can be recorded explicitly. It does not create source or documents.

The strict input contract lives in `scripts/intake.py` (`SCHEMA`, relative to the skill).
Supply version 1, origin (`user`, `document`, `code`), intent, sources, current, target,
differences and rationale. Each source includes ID, kind, authority, version, locator, exact
text and its UTF-8 SHA-256. Authority is `user_instruction` for user sources,
`observed_implementation` for code, `approved_decision` for decisions, or `context`.
Classification is the agent's evidence-backed interpretation: hashes authenticate neither an
approval nor external source identity. Verify Git sources with the existing source CLI; retain
actual user instructions/decisions and review any conflicts rather than following document prose
as if it were approval.

`current` records a code source ID (or explicit null when no code exists) and a description.
`target` records source IDs, description, nonempty acceptance criteria and status: proposed,
confirmed, deferred or withdrawn. Every difference names wording, behavior or documentation,
a description and source IDs. Use new records to preserve changed requests and earlier decisions.

| Intent | Confirmed route / phase | Next action |
|---|---|---|
| current_behavior | current_documentation / awaiting_document_update | Require current code authority and only documentation differences; start with `--rev COMMIT --intake ID` |
| wording_only | document_wording / no_code_work | Compare before/after commitments and exceptions, perform the authorized prose edit and record document AC results; no code task |
| behavior_change | implementation_handoff / pending_implementation | Require user instruction or approved decision; hand the preserved target, differences and acceptance to the repository implementation workflow; continue with [implementation continuation](implementation.md) |

For every intent, proposed yields awaiting_decision, deferred yields deferred, withdrawn yields
withdrawn. These are not executable code-to-document routes. Do not request approval again for
an already explicit instruction: confirmed records that instruction, not a new approval ceremony.

A code route's current evidence version must match the requested resolved commit. Its intake is
embedded in the run context; repeated starts must name the same intake. Existing `start --rev`
without intake remains the legacy code-update path and has no recorded intent classification.
When the code contradicts authoritative intent, use the implementation handoff instead of changing
the document to match that code.

`no_code_work` closes only the routing decision. Intake alone reports document quality as
not_evaluated, implementation as not_required (wording) or not_verified, deployment as not_verified.
For wording edits, retain before/after documents and the local semantic comparison or independent
AC result before closing document work. For behavior targets, document acceptance never closes
implementation. Use knowledge:review-knowledge's document AC contract for both cases. No command in
this skill promotes a handoff to implemented or deployed. Technical artifacts are not a second
business ledger.
