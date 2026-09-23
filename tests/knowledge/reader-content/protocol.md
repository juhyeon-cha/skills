# Reader-task content observation

Use this development fixture to evaluate knowledge content for FE, BE, planning and
PO work. All policy decisions, reports and code are synthetic local inputs. This is
not a user study, an operational service or evidence of generalized improvement.

Freeze `fixture/*`, `questions.json` and `expectations.json` hashes in `frozen.json`
before authoring. All twelve questions are mandatory; unknowns explicitly required
by expectations are correct answers, not missing evidence to invent. The writer
receives source, questions and the candidate procedures, but not expectations.
The observation is document generation/review only; no `init`, intake, publication
or implementation-complete receipt is required or implied.

The writer uses the candidate bootstrap/reader-task and installed writing-for-humans
procedures to produce Korean knowledge and a caller-owned coverage record. Keep
current behavior separate from fictional policy/decision authority even if using one
human reading document with labeled sections. Link shared facts instead of copying
different policies for each role. Pin outputs before reader evaluation.

A fresh reader receives only the Korean document, situations and questions. It must
answer all questions with supporting excerpts and identify missing information.
Keep source, answer keys, variant labels and previous results out of its prompt.
One fresh model may answer all four situations; report that this is not four human
participants. Dispatch without conversation history; file transport may read only
the supplied opaque packet before answering. Isolation is prompt-level, not a tool
access sandbox. Save the exact dispatch, returned identity and unedited response.

An independent non-author judge receives the exact source, criteria, document and
actual reader responses. It reviews both content and question-level answers. Every
required proposition must be supported by the document and source; a correct guess
does not count. Any mandatory failure keeps that variant from passing.

After the normal document is frozen, create a separate defect copy with two
intentional substitutions: response loss becomes cancellation failure with immediate
retry, and a proposed/unknown product metric becomes a claimed achieved result.
Preserve original bytes and each exact substitution. Use a separate fresh reader
with the same questions and no variant label. The judge must identify the FE2/PL2
and PO1/PO3 defects. Record an escaped control as a failed observation, not a pass.

The normal document must pass all twelve questions and both defect families must be
detected. Cite exact passages. Preserve failed versions and rerun affected reader
observations after any correction. The repository gate and dependency tests establish
packaging/regression behavior separately from these actual semantic observations.
Record elapsed time if observable; unavailable model cost/token counts remain unknown.

For updates, inspect the procedure's path from source changes to dependent reader
answers and the existing immutable-settings/successor boundary. This observation
does not execute a changed-policy update or certify runtime loading of installed skills.
