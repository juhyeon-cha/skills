# Pinned documentation experiment

Use this case when checking the document-acceptance stage of the code-driven knowledge
workflow or reproducing skills#323. `writing-for-humans` was the writer used in this case.
This is development material, not a shipped skill or a general evaluation platform.
Run commands from the repository root. Python 3 standard library is sufficient.

## Inputs and roles

- `sources.json` contains verbatim excerpts, source file hashes and an immutable Git commit.
- `questions.json` supplies the reader's tasks. `expectations.json` contains source-derived
  required propositions for the judge. These inputs were written before the writer call;
  `frozen.json` records their hashes. Update an expectation only for a source-grounded reason,
  record that reason, and retain the earlier result rather than accepting the writer's answer.
- `documents/` holds the Korean common policy and role-specific views. The parent condensed
  an independent skill-generated draft before the full reader evaluation.
- `observations/` holds parent-recorded actual returns and judgments, not invented test responses.

The writer receives the source excerpts, the writing skill and reader purpose. A fresh
reader receives only one `reader-prompt.txt`, with no conversation history, source, expected
answers, mutation name or prior verdict. In Codex collaboration use `fork_turns: "none"`;
do not use follow-up turns across different cases. Supply the harness root as the first line,
then the exact packet. If the dispatch cannot embed the packet, allow one initial literal read
of an opaque packet path and no subsequent tool use; record that transport exception. This is prompt-level
input separation, not proof of a provider-enforced sandbox or absence of pretrained knowledge.

A separate judge receives source, expectations, the exact document and the actual reader return.
Compare meaning and all required propositions, not matching keywords. Check the quotes against
the document. Every required proposition needs a returned supporting excerpt, including limits;
a correct answer with incomplete citations fails evidence completeness. Record that separately
from a missing or incorrect document. A faithful quote from a wrong document is still a factual failure. Missing content
is a document failure; a missing return or inaccessible input is UNREACHED. Neither passes.
The author is not the sole judge. Preserve actual child identities and raw returns.

## Run

```sh
python3 tests/knowledge/document-ac/check.py
python3 tests/knowledge/document-ac/check.py --source-repo /absolute/path/to/sap-harness
python3 tests/knowledge/document-ac/packets.py /absolute/new/run-directory
```

The optional source check reads the pinned local Git objects; it never fetches or contacts SAP.
Missing objects fail with SOURCE_UNREACHED. The default check verifies frozen bytes, question
coverage, excerpt hashes, local file/heading links and this case's chat-route literals. It cannot
decide prose correctness or remote link availability. Nonzero means a failed or unavailable check.

Prepare into a fresh path. Existing run directories are refused and partial outputs are preserved
on failure. The manifest records document/prompt hashes and structural results. Run fresh readers
for `normal`, `missing-exception` and `resend`, without revealing those labels to the readers.
`broken-link` and `bad-identifier` must fail the structural check for the corresponding reason.
An empty/absent document set or changed frozen evidence must also fail. Do not interpret a
successful packet-preparation command as a successful document evaluation.

The normal reader must satisfy every expected proposition with document support. Missing-exception
must fail q5 (500 handling); resend must fail q3 (no duplicate request). A reader may faithfully
report contradictory/insufficient material; that still fails the document AC. Record the judge's
reason rather than coercing an expected negative outcome. If a mutant passes, inspect whether the
defect remained recoverable from other passages and revise the experiment with its history intact.

Send failed ACs and their evidence to the writer. Correct documents and rerun affected checks and
a fresh reader on the corrected packet; never relabel an old response with a new document hash.
Skill changes require an observed skill failure. A successful draft justifies no extra universal
rule. Stop for an actual policy conflict or scope/approval boundary; normal wording and repair
decisions stay internal. Existing harness retry and completion procedures remain the owner of
execution state; these case labels are not new harness SIGNALs.

For the final report include commit/input hashes, actual child identities, document versions,
answers, per-question judgments, deterministic check results, repair history and limitations.
All required normal ACs must pass and all intended defect controls must fail. This demonstrates
this case on the observed surface, not human comprehension, general skill improvement or live SAP.

## Initiative and historical records

For goals, scope and the sequence of experiments, read the
[initiative index](../../../docs/initiatives/code-driven-knowledge/README.md).
This directory owns executable evaluation inputs and checks; the initiative owns planning.

The case moved from `tests/toolkit/writing-for-humans/` after the original experiment.
Files under `observations/` retain their original bytes, including historical command paths.
Those commands describe past runs; use the current commands above for a new run.
