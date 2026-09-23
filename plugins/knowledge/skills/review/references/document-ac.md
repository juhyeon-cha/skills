# Document acceptance contract

AC means acceptance criterion. Evaluation evidence is separate from the fixed packet/plan review
response. This contract creates no ledger, runtime signal, or automatic evaluator. The caller
retains evidence and hands it to its existing workflow.

## Classify before judging

Classify each relevant claim or section; mixed documents can use multiple rows.

| Class | Authority | Required boundary |
|---|---|---|
| Current behavior | Pinned code, configuration, observed execution | Identify version/environment; static evidence proves no deployment |
| Target specification | Versioned user instruction or approved decision | Separate approval, document quality, implementation verification, deployment; retain unimplemented differences and the implementation handoff |
| Wording-only edit | Before/after text and the same underlying authority | Compare commitments, conditions, exceptions, uncertainty; unchanged meaning can close document work without code work |
| Proposal or procedure | Problem evidence/constraints, or applicable policy/permissions | Label assumptions and open decisions; evaluate the reader's decision or next action |

Missing code is an explicit input state, not proof that an approved target is wrong. Missing
authority, contradictory policy, or unclear scope is indeterminate; retain the conflict and ask
only for decisions evidence cannot resolve. A target's conditions, outcomes, exceptions, and
acceptance must be actionable. Implementation and deployment remain pending without their own evidence.

## Freeze inputs

Before writing or observing responses, freeze AC IDs, applicable classes, reader/context,
questions, required propositions, source/decision versions, scope, exclusions with reasons, and
expected handling of unknown information. Record exact document and role-input bytes with hashes.
Changed sources or criteria get a new version and reason; retain earlier failures rather than
fitting expectations to responses.

Select relevant criteria from factual/intent fidelity, completeness of conditions/exceptions,
cross-document consistency, actionable reader decisions, testable target outcomes, traceability,
uncertainty, and structure/wording. Every mandatory criterion must pass; averages cannot hide a
failure. Explain style defects through a specific reader's mistaken action.

## Separate four observations

1. **Format check:** verify files, IDs, links, versions, hashes, and required evidence links.
   Record command and inspected result. Structural success is not semantic success.
2. **Content review:** an independent reviewer compares full documents with authority and AC,
   including retained claims and exceptions. It may also perform the independent judgment below.
3. **Document-only reader:** a fresh execution receives only frozen document, reader situation,
   and questions. Preserve actual action, expected result, quotes, and missing information. Keep
   source, answer keys, defect names, and earlier judgments out of its input. Record whether
   separation is prompt-only or enforced by tool access. Model inference without documentary
   support is not document-quality evidence; this is not a human usability study.
4. **Independent judgment:** give a non-author the authority, AC, exact document, and actual reader
   response. Return AC-by-AC results with quote and source support. Distinguish document omission
   from a reader's missing quote; a correct quote of a false claim still fails factual fidelity.

Low-risk wording changes may use a local semantic comparison; state why reader evaluation was
excluded. When introducing a criterion, evaluate a normal document and a separate copy with a
corresponding intentional defect. Preserve actual outcomes, including escaped defects. Repair
failures and evaluate changed claims against the new version, with a fresh reader where required.
Never reuse an old response for a changed document.

## Evidence and results

Preserve input/criterion versions and hashes; role IDs and observable tool/model identity (unknown
when unavailable); exact role inputs and raw outputs; format result; AC-level content and reader
judgments with reasons; failure/repair history; document, implementation, deployment completion
separately. A path or hash alone does not prove execution. Missing roles/responses are not-executed.

| Result | Meaning | Next action |
|---|---|---|
| pass | Mandatory criterion and evidence satisfied | Advance only the evaluated boundary |
| fail | Artifact/response contradicts fixed requirement | Identify document, code, or evaluation-input cause; repair and rerun affected criteria |
| indeterminate | Authority conflict, open policy, or unclear scope prevents judgment | Preserve evidence and resolve decision |
| not-executed | Required role/tool/input/response unavailable or not invoked | Restore execution; keep completion pending |

For prepared packets, keep the existing response shape: repairable defects map to `revise` with
failed checks; missing evidence/decisions to `blocked` with unverified checks. Only all four checks
supported and no findings permit `pass`. A missing role has no review response until it runs; the
coordinator records not-executed separately and never manufactures reviewer JSON. AC records
without packet/plan IDs stay separate.
