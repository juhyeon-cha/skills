# Transition from toolkit

Read this when changing an executable locator or skill name from a toolkit knowledge install.
The source marketplace supplies six direct entrypoints: `knowledge:bootstrap` for first
baselines, `knowledge:update` for existing knowledge changes, `knowledge:review` for independent
judgment, `knowledge:query` for reads, `knowledge:wiki` for presentation, and `knowledge:operate`
for automation and relation operations. The former `refresh-knowledge` entrypoint maps by task;
`review-knowledge` maps to `knowledge:review`. Toolkit retains `writing-for-humans`; it contains
no forwarding knowledge runtime. Existing released caches remain untouched until a separately authorized update.

## Select the package and capabilities

Resolve the installed knowledge plugin root as `KNOWLEDGE_ROOT` through the host. Replace
old skill-local executable locators with `$KNOWLEDGE_ROOT/scripts/knowledge.py`,
`automation.py`, `multi_repo.py`, or `wiki/…` as appropriate. JSON contracts are in
`$KNOWLEDGE_ROOT/contracts`; shared procedures are in `$KNOWLEDGE_ROOT/references`.
For authoring, resolve toolkit's writing skill independently and set `KNOWLEDGE_WRITER_SKILL`
to its absolute directory. Follow [project setup](project.md) and verify actual host dispatch
of the writer and independent reviewer; files alone do not establish invocation capability.
A missing dependency is a named failure, not a reason to load a developer checkout.

## Continue existing work

Keep the existing project, repository, documents, automation state and relations directories.
Select the same external Python runtime and use the new executable locator to inspect
`status --run ID` before resuming. This extraction changes no project SQLite schema, source
identities, packet formats or evidence files. A running old process may still own a task:
stop at its documented boundary and reconcile its actual result before another host writes.
Saved pending prompts retain their old paths and hashes; do not rewrite them or fabricate
new receipts. Finish that task with its still-available original resources first. If resources
are missing, preserve the task and resolve the missing capability before continuation.

Use [public CLI compatibility](cli-contract.md) for identity and error fields. Source-layout
changes produce a new implementation ID and do not retrospectively change older receipts.
The known v1 interrupted-run regression is a tested boundary, not universal historical support.

## Distribution boundary

A source PR is not an installed upgrade. Removing the old toolkit skill names requires a
major toolkit release under this repository's release policy; this extraction does not bump
or publish that release. The new knowledge source starts at 0.1.0. Release/install work must
explicitly communicate the new plugin and executable locations to existing callers.
