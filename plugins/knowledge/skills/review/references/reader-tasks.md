# Knowledge for reader tasks

Read this when freezing, authoring, updating or reviewing knowledge for a reader's
work. This contract owns task coverage; `toolkit:writing-for-humans` owns prose and
role-specific writing guidance. Use its selected role and document-purpose references
when authoring. Reviewers use the frozen tasks and supplied authority directly.

## Freeze the work the reader must do

Select only the requested readers. For each, record the action or decision after
reading, existing knowledge and bounded subject. Job titles are starting points,
not fixed document types: an FE engineer implementing a screen and one assessing
change impact need different knowledge. For an unlisted role, derive questions from
the actual work rather than adding every role below.

| Requested work | Questions to derive from the actual input | Evidence to inspect |
|---|---|---|
| FE implementation | Which conditions change the screen, request or recovery action? | Screen logic, consumed API contract and applicable design decisions |
| BE implementation | What do callers receive on success, repetition and failure, and which data rules hold? | Callers, service logic, schemas, configuration and relevant checks |
| Service planning | Who may do what under which conditions, and what happens in exceptions? | Versioned policy decisions, user flows and implementation differences |
| PO decisions | Which problem and outcome justify the scope, and what uncertainty changes the decision? | Actual problem observations, approved scope and decision records; measured results separately from proposed targets |

Keep a small task-coverage record in the existing caller-owned bundle. For each
question retain a stable ID, reader/action, required answer conditions and exceptions,
authority/version, and expected treatment of unknowns. Mark questions mandatory or
explicitly excluded with a reason before generation. This is review context, not a
new CLI schema, state store or access-control role.

Derive required questions from both the request and inspected sources. Include a
consequential exception or decision boundary when it affects the task. A generic
overview cannot substitute for an unanswered mandatory question. Missing questions
discovered later require a versioned criterion change with a reason, not a silent
reduction in the acceptance bar.

## Compose supported answers

Give each question an answer location, evidence locator and status in that record.
Use current behavior, confirmed target, proposal and unresolved as distinct claim
classes under [document acceptance](document-ac.md#classify-before-judging).
Code establishes observed behavior within its evidence boundary; it cannot establish
why a business priority was approved or a measured product outcome. State a missing
source, the question it leaves open and the action or decision it blocks. An explicit
unknown passes only when the frozen criterion permits that outcome; otherwise the
mandatory question remains pending.

Define a shared rule once at a canonical document section and link reader-specific
explanations to it. Add task-specific conditions and examples where needed; create
separate files only when reader work, authority or maintenance lifetime warrants it.
Do not force four documents for a single-reader request. Every required shared section
must be included in the authorized review and reader inputs; an unavailable dependency
is a gap, not an invitation to copy private content.

Keep bootstrap's separate current/target authority bundles. A multi-reader request
may share a subject and current evidence within one bundle; related target/proposal
bundles retain their own authority and completion. Link their exact versions and
distinguish intended policy from current implementation. Policy intent belongs to its
decision evidence, not a fabricated code binding. Existing source/binding schemas and
handoff routes remain unchanged.

## Preserve coverage during updates

Read the previous task record and compare changed source, policy and shared rules
with every dependent reader explanation and question, including preserved documents.
Record affected answers and justified unaffected ones. For an older baseline without
a record, derive the bounded tasks from its audience, purpose and supplied evidence
before composing changes; obtain a missing reader decision only when it changes scope.

Freeze the revised questions and expected effects before authoring. New readers,
questions or documents are scope changes: use the existing
[structural-change route](../../../references/maintenance.md#2-select-the-supported-update-boundary)
when new bindings or a successor bundle are required. Keep missing policy/goal evidence
pending without replacing it with an inference from code.

## Review the answers, not the headings

Supply the exact task record, shared sections and source/decision versions with the
review input. At project initialization, include the selected tasks and criteria in
the existing `audience`/`purpose` strings so later packets retain that context.
Project settings are immutable: changed tasks or criteria require the reviewed successor
route, not editing settings or a generated packet. For legacy projects, retain derived
coverage and its document-acceptance evaluation in the caller-owned bundle, bound to
the exact packet and document hashes; report the narrower scope carried by the packet.
Do not add unrecognized fields to packet or review JSON. Review only supplied
audience/purpose, with coverage limits stated rather than invented reader requirements.

For each mandatory question, check that the document lets the reader make the correct
decision or action, including relevant conditions, exceptions and evidence limits.
Trace common facts across reader explanations and source classes. A correct BE answer
does not compensate for an FE failure path omission; a matching code statement does
not prove an approved policy or product effect.

Use the [document acceptance observations](document-ac.md#separate-four-observations)
for fresh document-only readers and independent judgment. Give each reader only its
situation, questions and the required document/shared sections, keeping answer criteria
and source material with the judge. Record results by question and reader, preserving
all mandatory failures. For prepared reviews, map reader-task defects to `reader_action`,
authority/content errors to `source_fidelity` or `decision_coverage`, and unsupported
certainty to `uncertainty`; keep the existing response shape.
