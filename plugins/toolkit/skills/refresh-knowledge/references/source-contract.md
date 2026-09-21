# Source, baseline and decisions

Source capture reads pinned committed Git blobs, not working edits or deployment behavior.
Scope paths are literal repository-relative files/directories; repeat `--path` for multiple
scopes. UTF-8 regular text files are supported; selected symlinks, submodules, binary data and
invalid paths fail. An empty capture can represent deleted files; inspect a new scope's file count.
The [source schema](../scripts/schema.json) owns snapshot/change shapes.

## Initial baseline

Read existing documentation and actual baseline source. List the important behavioral claims
and their evidence, including unchanged behavior. Document paths use `--docs`; evidence paths
use the source repository root. This input is project data, never a plugin-file dependency.

```json
{"documents":[{"path":"guide.md","claims":[{"id":"retry-limit","text":"A connection error is retried twice.","evidence":["src/retry.py"]}]}]}
```

The [binding schema](../scripts/impact-schema.json) requires exact document excerpts, unique
claim IDs within each document and nonempty evidence paths. Binding verifies excerpt presence
and records the whole document hash. File-level evidence can overselect claims after an unrelated
line change and cannot discover undeclared dependencies. Record coverage limits honestly.

## Decisions for a run

Read every source file and document in `context.json` relevant to a candidate or unlinked change.
The impact ID and candidate IDs are machine-generated; copy them exactly. The
[decision schema](../scripts/update-schema.json) owns the input consumed by `prepare`:

```json
{
  "impact": "<impact ID from context>",
  "claims": [{"path":"guide.md","id":"retry-limit","action":"replace",
    "reason":"The configured retry budget increased.",
    "text":"A connection error is retried three times.","evidence":["src/retry.py"]}],
  "unlinked": [{"change":{"type":"added","after":"src/version.py"},
    "action":"no-document-change","reason":"This isolated version label does not affect the guide's contract."}]
}
```

Every candidate requires exactly one decision, even when kept. Every unlinked change requires
one justified `no-document-change` disposition. `prepare` supports only existing claims; for new
claims/documents or indirect impact, read [impact and structural changes](maintenance.md) to
select a reviewed successor or resolve the missing evidence. An unresolved addition cannot be
classified as `no-document-change`. Inspect [editing rules](updates.md)
for keep/replace/remove, renamed evidence and ambiguous excerpts. Claims about deployment or
policy intent need additional evidence; source structure and hashes do not prove semantic truth.
