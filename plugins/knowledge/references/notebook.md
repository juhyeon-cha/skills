# Accumulate knowledge from non-Git observations

Read this for explicitly exported SAP evidence, source-scoped notes, or knowledge
that must survive recollection outside Git. Git projects keep their existing
bootstrap/update contracts. This notebook is a separate local-owner store, not a
replacement for `multi_repo` permissions or its managed publication.

For the installed SAP Harness “내 지식” screen or its copied handoff, read
[desktop connection](desktop.md).

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

Use a user-owned notebook directory outside plugin caches and separate from SAP
DB files and existing generated pages. For SAP, obtain the canonical notebook,
wiki and personal-note paths from `sap-harness knowledge paths --tenant TENANT
--source SOURCE_UUID`; its existing vault knowledge base is the storage owner.
Initialize each new notebook with one immutable purpose and source before import:

```sh
python "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project NOTEBOOK notebook init \
  --source SOURCE_UUID --audience user --notes ABSOLUTE_PERSONAL_DIRECTORY
```

`--notes` makes that directory the canonical store for append-only note JSON files;
the notebook DB does not duplicate their bodies. Wiki builds read those files.
Back up both locations together. Preserve unrelated files there. Without `--notes`,
notes stay in the notebook DB. Use separate directories for every purpose/source.
Product-development knowledge belongs in the developer repository's managed Git
knowledge workflow. A separate `developer` notebook can hold explicitly selected
local evidence, but must never publish into the user wiki.

Existing unscoped notebooks remain readable; they cannot be relabeled or published.
Select records explicitly into a new scoped notebook, including note selection;
never infer the audience of a legacy note. Keep each source explicit. A SAP graph source UUID is not the tenant
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

Filters select explanations within the notebook purpose; notes and observations
stay visible for that source. A scoped notebook rejects other sources/audiences
on reads, writes and refreshes. Search is literal text matching, not semantic retrieval. Omit
filters deliberately to see all purposes/versions for that source. No match does
not establish missing SAP behavior. History IDs can be retrieved with `get`.

Export requires a scoped notebook and creates only its audience entry page, document
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

Imports handle explicit local exports. The authorized recollection branch below
uses the SAP CLI to connect. It does not schedule collection, install the plugin, migrate existing DBs,
or add a server-side multi-user service. Keep runtime availability, successful local
import, independent document judgment and real SAP completeness separate.

## Recollect and close a SAP knowledge task

Use this branch when the user authorizes SAP recollection. Keep that authorization
scoped to a named source and object list. A saved plan is configuration, not new
permission. Use `toolkit:writing-for-humans` to turn findings into reader actions;
job title alone does not choose between product usage and product development.

Create a private plan outside plugin caches with this exact shape:

```json
{
  "version": 1,
  "cli": ["/absolute/node", "/absolute/installed/sap-harness.js"],
  "producer_version": "ACTUAL_INSTALLED_BUILD",
  "db": "/absolute/existing/graph.sqlite",
  "source": "REGISTERED_SOURCE_UUID",
  "tenant": "SELECTED_TENANT",
  "level": "SELECTED_READONLY_LEVEL",
  "objects": [{"id": "OBJECT_UUID", "type": "DDLS", "name": "I_PLANT"}]
}
```

A directly executable installed CLI uses a one-element `cli` array. No shell
fragments or credentials belong in this plan. Source registration and initial
collection use SAP Harness's installed `graph` commands. New builds can resolve
an object export by `graph show-id --name I_PLANT --type DDLS --source SOURCE_UUID
--db DATABASE`; use the returned owner ID. Older builds require an existing ID.
Read-only target levels are configured names, not the literal word `readonly`.
SAP Harness selects the readonly target for `graph source` and `graph collect`.

```sh
python "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project NOTEBOOK notebook refresh-sap \
  --plan PLAN.json --output NEW_RUN_DIRECTORY
```

This runs one bounded refresh (1–20 selected objects), imports newer complete or
partial observations and writes `collection.json` plus `handoff.json`. It never
registers a new source implicitly. When only the exporting product version changes,
it preserves an otherwise identical old observation with its original producer
attribution; a new collection records the new version. It validates all local identities before
collection; SAP Harness validates the observed server/client and connection before
its DB writer opens. Commands use argument arrays. SAP owns SSO and may open its
login browser; a 180-second command timeout stops the run for human attention.
There is no background scheduler. Repeating the command is an explicit new run.
For a recurring request, use the host's scheduler with the same approved plan,
failures stopping for attention, and the authorization's requested interval.

Read both the exit code and report. Exit 1 with `ok: false` can still include a
successfully imported partial observation. A failed connection with no newer
observation is `collection_unverified`; the prior complete evidence remains only
the last imported evidence. Do not report it as a successful live refresh. Do not
retry authentication automatically. Preserve interrupted output directories and
use a new one. The notebook's `sap-refresh.lock` prevents another refresh writer;
after a crash, confirm no process is active before explicitly removing that lock.

For each completed SAP investigation or implementation task within this authorized
knowledge workflow:

1. Retain the useful finding as a source/object note, including unresolved meaning.
2. Run the configured refresh when its selected evidence may have changed. Inspect
   `collection.json` before the writer handoff; an incomplete run remains visible.
3. Compare each handoff document's exact old/new evidence. Inspect field labels,
   deprecation/successor annotations, uncollected targets and limits before writing
   an explanation. A stable structure hash is not proof of unchanged business data.
4. Revise only relevant document keys with the latest evidence and `previous` ID.
   Keep product versions distinct. Obtain a real independent review of the exact
   revision; register that actual response. Keep notes and previous revisions.
5. Rebuild the wiki with the following command, and verify the selected audience entry
   page, important states and evidence links. Report incomplete work separately.

## Build from an installed plugin

The notebook CLI needs Python 3.10+ with SQLite. Wiki rendering also needs Node and
MarkdownIt available as a module directory; resolve them through the host runtime
or install the documented wiki dependencies with the user's approved package setup.
No repository checkout, npm workspace or Git is needed at execution time.

```sh
python "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project NOTEBOOK notebook wiki \
  --source SOURCE_UUID --output WIKI_ROOT/snapshots/NEW_BUILD --publish WIKI_ROOT --require-current \
  --node /absolute/node --markdown-it /absolute/node_modules/markdown-it
python -m http.server 8777 --bind 127.0.0.1 --directory WIKI_ROOT
```

`wiki` exports, builds and checks local bytes before returning `site` and `index`.
Use a new output directory on every build; an existing snapshot is never replaced.
`--require-current` checks the exact exported snapshot and rejects empty, unreviewed,
stale or blocked documents before creating output. Use it for reviewed publication;
omit it only when deliberately building a labelled draft for inspection.

Optional `--publish` creates a scope-bound stable entry at WIKI_ROOT/index.html.
The new output must be inside that root. Only a successful build/check atomically
updates the entry; a failed build retains the last success. Keep the failed run
visible in the task report; the retained page is not evidence that refresh passed.
Serve only this wiki root, never a parent containing another audience's files.
The root starts empty or carries the same scope; unrelated existing sites are refused.
Serve on loopback for browser search, then stop that foreground server when done.
This does not publish remotely, install dependencies or approve document semantics.
