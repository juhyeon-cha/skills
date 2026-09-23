# Knowledge wiki

Use this procedure when presenting code-linked knowledge as a human-facing web wiki.
It extends the document workflow; it does not add a renderer command to the knowledge CLI.

## Establish the reading task

Name the reader, the decisions they must make, and the source revision. Inspect existing
knowledge and its evidence before choosing page boundaries. Use the writing dependency
in the parent skill to organize pages around reader tasks, with an entry page, contextual
links, and a separate evidence page. Choose the number of pages from those tasks.

Keep three kinds of material distinct:

- Shared knowledge: one canonical document body for human reading and agent retrieval.
- Agent procedures: tool use, permissions, and update instructions in their owning skills.
- Evaluation records: frozen questions, answer keys, raw responses, and execution receipts
  outside the ordinary reading path, linked from the evidence record when appropriate.

Record required propositions and reader questions before authoring. Include expected
answers and source support, especially prerequisites, negative cases, and what a successful
local check does and does not establish. A missing prerequisite can prevent action even
when every sentence on the page is true.

## Render the reviewed body

Follow the parent skill's independent document review before treating knowledge as reviewed.
Derive page bodies and search text from the same canonical input. Preserve relative links
for direct document readers and resolve them to valid routes and heading anchors in HTML.
Keep navigation, summaries, and visible status labels consistent with the body.

Record the source revision separately from document review, build integrity, and live
verification. Put technical provenance behind a clear evidence link or disclosure. State
whether the site is a fixed snapshot. Comparing a supplied revision or checking file hashes
establishes only that comparison; freshness requires observing the actual source and index.

Use the project's renderer if one exists. For a new renderer, verify input boundaries,
missing references, duplicate routes, orphan pages, and unsafe content. Build into a new
output directory, write a completion receipt only after success, and serve only a completed
output. A failed build may leave partial files; inspect them before retrying and follow the
project's deletion policy. A receipt should bind the actual document, manifest, search, and
HTML bytes. A passing hash check is neither semantic review nor atomic publication.

## Evaluate reading and change propagation

For document acceptance and reader evaluation, read and apply the existing
[document acceptance contract](../../review-knowledge/references/document-ac.md).
Use the shared Markdown as the document input and link failed and repaired versions to their
actual responses. That contract owns freezing, role separation, judgment, and rerun requirements.

Exercise the served site in a browser: route navigation, search result and empty state,
unknown route, keyboard access, heading links, and narrow/wide layouts including resize.
Record observations against the exact built output. Source inspection alone does not
establish these interactions.

Replay a real change through the existing project workflow: pin before/after revisions,
freeze expected affected claims, independently review the proposal, apply it, inspect the
completion record, then regenerate HTML and search. Check both the appearance of the new
claim and removal of the superseded claim. Include dependency files needed to explain the
change. Distinguish one replayed document from a complete wiki update, and a historical
replay from a live change subscription.

Finish with the reviewed content version, built output, actual reader/browser observations,
change-propagation result, and remaining unverified scope. Record observed interventions,
cost, and latency only when captured. Decide whether further infrastructure is needed from
observed failures and comparison with the existing approach; a multipage wiki alone does
not require a central database or search service. Remote publication follows the parent
skill's separate authorization boundary.
