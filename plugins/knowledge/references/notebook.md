# Accumulate knowledge from non-Git observations

Read this for explicitly exported SAP evidence, source-scoped notes, or knowledge
that must survive recollection outside Git. Git projects keep their existing
bootstrap/update contracts. This notebook is a separate local-owner store, not a
replacement for `multi_repo` permissions or its managed publication.

## Select purpose and authority

Distinguish the product user from its developer, independently of job title. An
ABAP developer using installed sap-harness is a product user when carrying out SAP
work. Select `audience: user|developer`, `area: usage|development|domain`, the actual
reader task (`purpose`) and an explicit `product_version`. Use the inspected
version, or an explicit unknown label; never infer latest compatibility.

Keep product usage, product implementation and tenant-specific domain knowledge
separate. Reuse evidence IDs across explanations, not copied policies. Follow
`toolkit:writing-for-humans` for question-first answers, linked scenarios and visual
forms. SAP structure alone does not establish business intent, runtime behavior,
authorization or transaction results.

Resolve an absolute installed knowledge plugin root and Python 3.10+ through the
host. Notebook operations use Python's standard library and SQLite; they do not
need a Git clone or SAP credentials. Writing and independent semantic review still
require the actual host writer/reviewer capabilities. Missing capabilities leave
drafts unreviewed. The CLI never calls a model or invents a review.

Use a user-owned notebook directory outside plugin caches, legacy knowledge and
SAP databases. Keep each source explicit. A SAP graph source UUID is not the tenant
alias; `observation.source_id` and the exported object ID select its identity.
A database rebuild that assigns new IDs requires an explicit new source; this
notebook does not infer equivalence across rebuilt databases.

## Import inspected evidence

Existing public `sap-harness graph show-id OBJECT_UUID --db DATABASE` exports one
owner graph as JSON without querying SAP. Save its output as UTF-8 JSON and supply
the actual producing sap-harness version. Resolve the installed CLI as documented
by sap-harness; do not require `npm`, a source checkout or extension installation.
Recollection and SAP access remain sap-harness operations needing their own scope.

```sh
python "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project NOTEBOOK notebook import-sap \
  --input OBJECT_EXPORT.json --producer-version INSTALLED_VERSION
```

The adapter checks owner/source identity, preserves the full export, original
observation time and completeness, and hashes the export as its evidence revision.
A retained successful structure under a partial/failed observation is not a new
complete observation. `unsupported`/`reference` map to `partial`; original status
and collector profile remain recorded. Completeness is limited to that profile.
An absent object or a missing export is not evidence of removal.

Other explicit evidence can use `notebook observe --input observation.json`:

```json
{
  "source": "product-release-example",
  "object": "connection-guide",
  "revision": "source-content-sha256-or-other-actual-version",
  "observed_at": "2026-09-24T00:00:00Z",
  "status": "complete",
  "title": "Connection behavior",
  "body": "Exact inspected evidence, with its limitations.",
  "metadata": {"producer": "explicit local export", "locator": "original source locator"}
}
```

Supported states are `complete`, `partial`, `failed`, `removed`. Record removal only
from explicit evidence. Import is atomic and identical records are idempotent.
Older observations remain history and cannot replace the latest observation.
Conflicting bytes at the same source/object/time fail for reconciliation; do not
invent a later time to force replacement. Use the same owner `show-id` selection
on later exports. Export content hashes include all preserved fields.

## Write, revise and review an explanation

Use `notebook document --input document.json`. Every revision has an immutable ID.
First revision uses `previous: null`; an update must name that key's latest ID.
Different audience, area or product version needs its own key. This preserves
version-specific explanations rather than silently relabeling old instructions.

```json
{
  "key": "object-reading-user-v1",
  "source": "SOURCE_ID",
  "title": "What can this collected object tell me?",
  "audience": "user",
  "area": "domain",
  "purpose": "Decide what is known and what needs another observation",
  "product_version": "EXACT_INSTALLED_VERSION",
  "author": "ACTUAL_AUTHOR",
  "body": "Supported Markdown explanation, including important unknowns.",
  "evidence": ["OBSERVATION_ID_RETURNED_BY_IMPORT"],
  "previous": null
}
```

One explanation binds observations from one source. Cross-source material uses
separate explanations; this boundary is not an authorization system. All supplied
IDs must exist. A hash proves identity, not source truth or semantic correctness.
Give an independent reviewer the exact document and evidence (`notebook get --source
SOURCE_ID --id ID`), the reader task and actual input authority. Preserve their real
response. Register their judgment with `notebook review --input review.json`:

```json
{"document":"DOCUMENT_ID","reviewer":"ACTUAL_NON_AUTHOR","verdict":"pass","reason":"Actual judgment with scope and limits."}
```

Verdicts are `pass`, `revise`, `blocked`. An author cannot review their own document;
identities are caller-attested, not authenticated by this CLI. The orchestrator
must not impersonate an independent reviewer. A pass requires current complete
bound observations. A later collection makes explanations `stale` or
`evidence_pending` as appropriate; their text and earlier reviews remain history.
Read results mark drafts `unreviewed`, rather than publishing them as facts.
`current` means reviewed against latest imported complete evidence, not live SAP.

## Preserve discoveries and earlier knowledge

Use `notebook note --input note.json` with the exact fields `source`, `object`,
`author`, `body`, `origin`, all nonempty strings. A note needs a known source/object.
Notes remain labeled personal records and never become verified facts automatically.
Only capture material requested or relevant to the user's knowledge task; this is
not conversation recording or automatic ingestion of arbitrary workspace files.

For an explicitly selected old synthesis Markdown page:

```sh
python "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project NOTEBOOK notebook import-note \
  --source SOURCE_ID --object OBJECT_ID --author ACTUAL_AUTHOR --file LEGACY_PAGE.md
```

Import preserves its complete UTF-8 text and original byte hash as an unreviewed
note, without rewriting or deleting the file. Repeating identical text for the
same scope/author is idempotent. Changed text creates another record. Review its
source and applicability before turning it into a document. Broken legacy links
are retained as literal text, not followed. Bulk automatic migration and pruning
are not performed. Keep the old generator from writing into notebook directories.

## Read and show the knowledge

```sh
python "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project NOTEBOOK notebook read \
  --source SOURCE_ID --audience user --area domain --product-version VERSION --query QUESTION_TERMS
python "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project NOTEBOOK notebook get --source SOURCE_ID --id RECORD_ID
python "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project NOTEBOOK notebook export --source SOURCE_ID --output NEW_CONTENT
```

Filters select explanations; notes and observations stay visible for the explicitly
selected source. Search is literal text matching, not semantic retrieval. Omit
filters deliberately to see all purposes/versions for that source. No match does
not establish missing SAP behavior. History IDs can be retrieved with `get`.

Export creates new static-wiki inputs with user/developer entry pages, document
status/version, evidence and literal notes. Build and serve them using
[static wiki](knowledge-wiki.md#render-the-reviewed-body). The existing safe renderer
supports flows/cards. This export is a dated snapshot, not the permission-aware
managed reader; rebuild after importing or revising. Export never uploads data.

## Recovery and limits

`observations.sqlite` is append-only through the CLI. A busy writer fails immediately;
wait for it to finish and retry the original request, which is idempotent. Failed
semantic operations roll back. Readers never create a missing store. Unknown DB
versions or symlink paths fail rather than migrate or overwrite. Preserve an
interrupted first initialization and choose a new directory after diagnosis.
An interrupted export has no final manifest; retain it and retry a new output path.

This first path handles explicit local exports and user-triggered updates. It does
not schedule collection, connect to SAP, install the plugin, migrate existing DBs,
or add a server-side multi-user service. Keep runtime availability, successful local
import, independent document judgment and real SAP completeness separate.
