# Accumulate knowledge from explicit evidence

Read this for source-scoped evidence, notes or knowledge outside a Git checkout.
Git projects retain their bootstrap/update contracts; this local-owner notebook
is not a multi-user authorization service or a replacement for managed project permissions.

## Responsibilities

The producing application owns collection, authentication, source-specific parsing,
collection authorization and storage-location selection. It translates its output
into the observation contract below and invokes the public notebook CLI. Knowledge
never executes a producer's collector or interprets its domain-specific payload.

Knowledge owns evidence history, explanations, personal notes, dependency impact,
writing handoffs, independent review records and static wiki publication. Use
`toolkit:writing-for-humans` for question-led explanations and reader actions.
Distinguish product usage from product development independently of job title.
For example, an engineer using an installed product may need usage knowledge;
a developer changing that product needs implementation knowledge.

## Initialize one source and audience

The host supplies absolute notebook, personal-note and wiki paths in user-owned
storage outside plugin caches. For an explicit SQLite file, a shared application DB,
configured artifact/publication locations, or history transfer, read
[notebook storage](notebook-storage.md). Preserve existing files. A product may keep user knowledge in a vault and
its own developer documentation in Git; knowledge does not choose those paths.

```sh
python "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project NOTEBOOK notebook init \
  --source SOURCE_ID --audience user --notes PERSONAL_DIRECTORY
```

Use `developer` for a separate developer notebook. Source and audience are immutable;
reads and writes reject a different scope. A source identifier is not a display
label or inferred tenant name. Existing unscoped or mixed notebooks are retained;
explicitly select records for a new scoped notebook instead of relabeling them.
Personal notes have their own matching scope marker and one original JSON file.
Back up notebook and personal notes together. Without `--notes`, notes stay in the DB.

## Observation input contract

The public `notebook observe --input OBSERVATION.json` command accepts exactly:

```json
{
  "source": "producer:environment",
  "object": "stable-object-id",
  "revision": "producer-revision-or-content-hash",
  "observed_at": "2026-09-24T08:00:00Z",
  "status": "complete",
  "title": "Order API contract",
  "body": "Explicitly exported evidence, including its limitations.",
  "metadata": {
    "producer": "api-schema-exporter",
    "producer_version": "1.0",
    "locator": "object:stable-object-id",
    "evidence_scope": "documented schema only; runtime behavior not observed"
  }
}
```

All scalar fields are nonempty strings. `observed_at` includes a timezone.
`metadata` contains only string keys and values; the example keys are useful producer
context, not product-specific requirements. Preserve provenance and collection scope.
Use `complete`, `partial`, `failed` or `removed`. The producer maps its own states to
these meanings: complete covers its stated collection scope, never all possible facts.
Failed/partial evidence is not silently replaced with an earlier successful capture.
A repeated identical record is idempotent. Different evidence at the same source,
object and observation time is a conflict; reconcile it rather than overwrite history.

Store producer-specific details as opaque body/metadata. The producer owns canonical
hashing and identity translation. A content hash establishes byte identity, not truth.
Knowledge adds its own immutable record ID and returns it for document dependencies.

## Write and independently review explanations

Use `notebook document --input DOCUMENT.json` with exactly these fields:
`key`, `source`, `title`, `audience`, `area`, `purpose`, `product_version`, `author`,
`body`, `evidence`, `previous`. Text fields are nonempty; `audience` is `user` or
`developer`; `area` is `usage`, `development` or `domain`. `evidence` is a nonempty
list of distinct observation record IDs from the same source. `previous` is null
for a new key or the latest document ID for a revision. Use a new key to change
audience, area or product version. Existing explanations and reviews remain history.

Write the answer to the reader's question, the action or judgment it supports,
its exceptions and what the evidence does not establish. Keep code-derived facts,
observed behavior and interpretation distinguishable. Field lists alone are not
an explanation. Use [visual blocks](visual-blocks.md) when sequence or comparison
is easier to read visually. Preserve the reader's language.

Use `notebook review --input REVIEW.json` with `document`, `reviewer`, `verdict`
and `reason`. The document is an exact revision ID; verdict is `pass`, `revise`
or `blocked`. Register a real independent judgment, not an invented review record.
The reviewer must differ from the author. Identities are caller-attested, not
authenticated. A pass requires current complete bound observations.

`current` means reviewed against the latest imported complete evidence. It does
not guarantee the live source is unchanged. A changed observation makes dependent
explanations `stale`; incomplete/removed evidence makes them `evidence_pending`.
An unreviewed revision remains `unreviewed`. Review requests remain `revise` or `blocked`.

## Preserve personal findings

Use `notebook note --input NOTE.json` with nonempty `source`, `object`, `author`,
`body` and `origin`. The source/object must already exist. Notes remain personal
records; neither collection nor publication promotes them to reviewed facts.

For one explicitly selected old Markdown file, use:

```sh
python "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project NOTEBOOK notebook import-note \
  --source SOURCE_ID --object OBJECT_ID --author ACTUAL_AUTHOR --file OLD_PAGE.md
```

This preserves the full UTF-8 text and original byte hash, without deleting or
rewriting the original. Identical imports are idempotent; changes add history.
Old links stay literal. Capture only the selected useful finding, not arbitrary
workspace files or conversation history. Bulk migration/pruning is not performed.

## Compare changes and hand off writing

After the producer imports evidence, request:

```sh
python "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project NOTEBOOK notebook handoff \
  --source SOURCE_ID --collection COLLECTION.json
```

`--collection` is optional. When supplied, the producer report must contain the
matching `source` and boolean `ok`; additional producer diagnostics stay opaque.
A missing report means collection success is unknown, not true. A false report
remains false even when previously imported evidence is still complete.

The version-1 response contains pending `documents`, latest `observations`, personal
`notes`, `history` references (`id`, `kind`) and `evidence_changes`. Resolve a historical
record through public `get --source SOURCE --id ID`. Each changed dependency identifies its document,
object, exact bound/latest records and reason (`new_observation` or `incomplete_evidence`).
Current unrelated documents are excluded from the writing queue. An empty initialized
notebook returns an empty packet. Use that packet to:

1. Compare exact evidence and decide which claims need changing. A new capture is
   a recheck trigger, not proof that every business claim changed.
2. Revise relevant explanations with their `previous` IDs, preserving notes and history.
3. Obtain independent review of the exact new revisions; register the actual result.
4. Publish reviewed explanations. Collection success alone does not complete the task.

The producer owns retry, authentication prompts, scheduling and collection progress.
The host dispatches writing and review through actual agent capabilities; the CLI
only returns data and never calls an AI service or approves its own output.

## Read, inspect status and publish

```sh
python "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project NOTEBOOK notebook read \
  --source SOURCE_ID --audience user --area domain --product-version VERSION --query TERMS
python "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project NOTEBOOK notebook get --source SOURCE_ID --id RECORD_ID
python "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project NOTEBOOK notebook status \
  --source SOURCE_ID --publication WIKI_ROOT --collection COLLECTION.json
```

Read filters select explanations; notes and observations remain visible for the
selected source. Query is literal text matching. No match does not establish missing
product behavior. History IDs can be retrieved with `get`.
Status distinguishes empty, writing, review, publish, complete and collection_failed.
The host adds its own active collection/publication progress. Complete means the
published entry matches the reviewed notebook revision, not live source freshness.

Python 3.10+ with SQLite is sufficient for notebook commands. Wiki rendering also
requires Node and MarkdownIt, resolved by the host. Install dependencies only with
the applicable authorization. No repository checkout is needed at execution time.

```sh
python "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project NOTEBOOK notebook wiki \
  --source SOURCE_ID --output WIKI_ROOT/snapshots/NEW_BUILD --publish WIKI_ROOT --require-current \
  --node /absolute/node --markdown-it /absolute/node_modules/markdown-it
```

`--require-current` validates the exact exported snapshot, rejecting an empty
notebook or any unreviewed/stale/incomplete/blocked explanation before writing output.
Omit it only for a deliberately labelled draft. `notebook export --source SOURCE_ID
--output NEW_CONTENT` produces inputs for the same [wiki renderer](knowledge-wiki.md).

Each build uses a new output directory. The stable publication root must be empty
or belong to the same source/audience; output must be its child. Build/check failure
preserves the last successful entry. Only a checked snapshot replaces the entry,
with a publication receipt. Keep failed attempts visible separately. Serve only
this wiki root on loopback for search, never a parent containing private stores.
This is local publication, not external sharing or semantic approval.

## Recovery

The CLI appends records; semantic write failures roll back. A busy writer fails
immediately: wait and retry the idempotent input. Readers do not create a missing
store. Unknown DB versions or symlink paths fail rather than migrate or overwrite.
Configured-store initialization and history transfer follow [storage recovery](notebook-storage.md).
Preserve interrupted initialization/export output and diagnose it before retrying
with a new destination. Existing data is never rewritten to change producer ownership.
