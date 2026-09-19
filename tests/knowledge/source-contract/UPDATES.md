# Prepare and apply document updates

Use this development workflow after [impact extraction](README.md#bind-claims-and-find-affected-documents).
Run it in an exclusively owned document workspace. Another CLI or editor must not write
those documents during application. The original source snapshots, bindings, decisions,
and prepared plan are immutable inputs; store them outside the document files being edited.

## Author decisions

Read the before/after source evidence for each candidate. Use `writing-for-humans` when
composing replacement prose for the document's reader. Supply one decision per candidate
claim, keyed by document path and claim ID. The CLI checks structural consistency; the
agent owns semantic correctness and the relevance/completeness of evidence.

```json
{
  "impact": "<impact record ID>",
  "claims": [
    {
      "path": "guide.md",
      "id": "retry-rule",
      "action": "replace",
      "reason": "The retry limit changed from two to three in src/retry.py.",
      "text": "A failed request is retried up to three times.",
      "evidence": ["src/retry.py"]
    }
  ],
  "unlinked": [
    {
      "change": {"type": "added", "after": "src/diagnostics.py"},
      "action": "no-document-change",
      "reason": "This diagnostic entry point does not change the guide's retry contract."
    }
  ]
}
```

Copy the exact unlinked change objects from the queue. A reason alone is not a deferred
work item: `no-document-change` is an explicit semantic decision. New claims/documents and
unlinked changes requiring edits are outside this CLI's current scope; resolve that work
before preparing a plan rather than labeling it no-document-change.

- `keep`: preserve the original excerpt exactly and provide valid evidence in the after
  snapshot. This can update a renamed evidence path without rewriting the document.
- `replace`: supply a different, nonblank excerpt and nonempty after-snapshot evidence.
- `remove`: supply empty `text` and `evidence`. Only the bound excerpt is removed; the file
  remains, including surrounding whitespace and Markdown structure.

Every candidate needs exactly one decision; every unlinked change needs exactly one
explicit disposition. All reasons must be nonblank. Edits must target unique, nonoverlapping
excerpts. Unaffected claims remain, and every surviving claim is checked against the revised
document and after snapshot. These checks do not establish that the source proves the prose.

## Prepare, review, apply

The JSON definitions live in [update-schema.json](update-schema.json). With `PYTHON` from the
[environment setup](README.md#setup-and-run), prepare a new file:

```sh
"$PYTHON" tests/knowledge/source-contract/update.py prepare decisions.json \
  --bindings bindings.json --before before.json --after after.json \
  --repo /absolute/source/repo --docs-root /absolute/documents --out plan.json
```

Inspect `documents` in the plan: each entry contains exact before/after text and hashes.
Preparation verifies Git evidence and the current document baseline without editing originals.
Review the prose and decisions against source before applying; an internally valid plan is
not semantic approval. A plan hash is an integrity identifier, not an author signature.

```sh
"$PYTHON" tests/knowledge/source-contract/update.py apply plan.json \
  --bindings bindings.json --before before.json --after after.json \
  --repo /absolute/source/repo --docs-root /absolute/documents
```

Application recomputes the entire plan from stored original documents, decisions, bindings,
and pinned Git sources. Before the first write, every bound document must have either its
expected original bytes or its exact planned result. Symlinks and multiply linked or special
files are rejected. Existing output files are never overwritten during preparation.

The CLI replaces changed documents one at a time using a sibling temporary file and rename,
then checks all final bytes. It preserves permission bits but not ownership, ACLs, extended
attributes, inode identity, or modification times. Use ordinary workspace text files. It
prints `status: applied` only after final verification, including on an unchanged retry.

## Failure and continuation

A conflict found during preflight changes no document. A later I/O failure or interruption
can leave a prefix applied. Inspect the error and current files, resolve the cause, then
retry the same plan: exact target files are skipped. A file with any third content is refused.
Do not automatically roll back or overwrite independent edits. An abrupt kill can leave a
`.knowledge-update-*` temporary file; it is not completion evidence.

After a successful apply, use the plan's `next_bindings` as the bindings record for the next
cycle, with this after snapshot becoming the next before snapshot. Do not advance that
record after a partial failure. Claims removed from a document disappear from the next
record; documents with no surviving claims are omitted. `next_bindings: null` means there
are no tracked claims left, so there is no next binding record to consume. This is not a
claim of complete knowledge coverage.

This workflow does not provide a multi-file transaction, arbitrary concurrent-writer safety,
filesystem crash durability, current-branch freshness, automatic semantic decisions, remote
publishing, or LLM evaluation. The final pre-replace check narrows accidental races but is
not an atomic compare-and-swap against another editor. Preserve exclusive workspace access.
