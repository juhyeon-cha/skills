# Notebook storage and history transfer

Read this when selecting a SQLite file, adding knowledge to an existing application
DB, choosing artifact locations, or transferring a scoped notebook. The observation
and review contracts remain in [notebook.md](notebook.md).

## Configure locations

The caller owns path selection. Pass an existing JSON configuration file to
`knowledge.py --project CONFIG.json notebook ...`. Use absolute paths outside
plugin caches. All commands use that configuration regardless of cwd.

```json
{
  "version": 1,
  "database": "/absolute/data/application.sqlite",
  "notebook": "product-usage",
  "artifacts": "/absolute/knowledge/artifacts",
  "notes": "/absolute/personal-notes",
  "publication": "/absolute/published-wiki"
}
```

`database`, `notebook` and `artifacts` are required. `notes` and `publication` are
optional. Omit `notes` to keep personal notes in SQLite; supplying it selects
file-owned notes with one original JSON file per note. The notebook's note storage
mode is immutable. A file directory's owner marker binds it to the store identity
and notebook as well as its source and audience. Keep notes and artifacts separate.
The publication directory must be separate from private storage and configuration;
serve only that directory. Symlink paths and parent traversal are rejected.

The DB stores notebook source/audience and a stable store identity; the configuration
stores locations. A notebook ID is caller-chosen and unique within that DB. Multiple
notebooks can share a file; user and developer notebooks can use entirely separate
files. Scope selection is data isolation, not multi-user access control. The owner
of a local DB/configuration can access or replace them; host authentication remains
the caller's responsibility.

## Initialize explicitly

Create a new SQLite file:

```sh
python "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project CONFIG.json notebook init \
  --source SOURCE_ID --audience user
```

Add knowledge tables and a notebook to an **existing** SQLite file:

```sh
python "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project CONFIG.json notebook init \
  --attach --source SOURCE_ID --audience user
```

Creation refuses an existing file. Attach refuses a missing file. Repeating attach
with the same notebook/scope is idempotent; another scope is refused. Ordinary reads
and writes require initialization and never create configured DBs, tables or
notebooks implicitly. Initialization of a new file that fails can retain an empty
file: inspect it, then explicitly attach to it or select a new destination.

Initialization modifies only `knowledge_*` tables/indexes. A matching name is not
sufficient ownership: the schema and its ownership/version record must match.
The knowledge version lives in `knowledge_schema`; DB-wide `user_version`,
`application_id` and journal mode stay under host control. The CLI never changes
host tables or adds dependencies, triggers or foreign keys to them. Unknown schema
versions fail; no automatic schema upgrade is implemented.

Each DB write uses a short transaction; busy writers fail with the public CLI error
contract. Retry the same input after the competing transaction finishes. Record
insertion is idempotent. DDL failure rolls back its DB changes. For file-owned notes,
initialization validates the directory first, commits the DB identity, then publishes
the owner marker. If that publication fails, retain both locations and retry attach;
the committed identity is reused. Reads/writes of personal notes require that marker.
DB commits and filesystem publication are not one atomic transaction. Partial marker
files are preserved and rejected: restore a trusted marker or choose a fresh note
directory after diagnosing the interrupted write.

The host owns whole-file backup, replacement and recovery. A disposable application
cache is unsuitable for durable knowledge unless the host explicitly preserves it.
Sharing a DB file does not combine collection and knowledge writes into a single
transaction. Producers continue to submit the product-neutral observation contract;
knowledge never queries their tables or loads their SQLite extensions.

## Use configured artifacts and publication

Existing observation, document, review, note, read and get commands are unchanged.
`handoff --source SOURCE_ID --save` also writes immutable JSON below the configured
`artifacts/handoffs/` directory and returns `artifact`. Repeated identical packets
reuse the same file; a conflicting or partial file fails and is retained.

`status --source SOURCE_ID` uses configured `publication`. `wiki` uses it as the
stable publish root while still requiring an explicit, new `--output` child for
each build. An explicit publication argument must match the configured location.
Without configured publication, supply the existing command arguments. Wiki build
and agent work occur outside the write transaction. DB snapshot reads are consistent;
external note files are not included in SQLite's transaction.

## Preserve existing stores and transfer history

Directory-valued `--project` retains the existing `scope.json`/`observations.sqlite`
contract, including existing unscoped stores. It does not migrate them. Configure a
new target and use an explicit transfer for a scoped notebook:

```sh
python "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project OLD_DIRECTORY notebook backup \
  --output /absolute/transfer/history.json
python "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project NEW_CONFIG.json notebook init \
  --attach --source SOURCE_ID --audience user
python "$KNOWLEDGE_ROOT/scripts/knowledge.py" --project NEW_CONFIG.json notebook restore \
  --input /absolute/transfer/history.json
```

Use create rather than attach if the target file does not exist. Backup also accepts
a configured notebook and includes all revisions, reviews and external personal
notes. It refuses output overwrite. Quiesce external note writers when exporting;
the SQLite snapshot cannot lock arbitrary file editors. Backup contains private
source bodies and notes: keep it outside the served wiki.

Restore requires an initialized configured notebook with matching source/audience
and **DB-managed notes** (omit `notes` in the target configuration). This makes the
entire history import one DB transaction, without a second filesystem commit.
It preserves record IDs and exact evidence/review links and validates every record
in original insertion order. File-owned notes are appended after DB history in the
backup; their identity and body are preserved. A populated target is accepted only
when its history exactly matches the bundle, making a lost-response retry safe.
Invalid input rolls back every imported row. Original files/DBs are never rewritten
or removed, and the transfer does not retarget the caller's old configuration.
Unscoped/mixed legacy stores require explicit selection into a scoped notebook first;
backup does not silently infer an audience.

Backup digests detect inconsistent bytes, not authenticity or truth. Existing review
records remain caller-attested history; restoring them performs no new review.
Git project and automation databases keep their existing storage contracts.
