# Public CLI contract

Read this contract when invoking `scripts/knowledge.py` programmatically or interpreting its failures. Independent `cli.py`, `impact.py`, `update.py` and `workflow.py` commands retain their own contracts.

Use `knowledge.py` for project-managed documents. Direct application through the lower-level CLIs does not advance the project baseline or run state; do not mix it with the project workflow on the same documents.

`doctor`, `init`, `start` and `prepare` check the runtime and explicit external writer and knowledge-owned review skill files. `review` and `resume` check only the runtime prerequisites: Python, jsonschema, Git and SQLite JSON functions. They still validate the registered review and application inputs.

## Responses and versions

Success writes one JSON object to stdout, empty stderr, exit 0. Existing fields remain at the top level; `_meta.cli_contract` is 1. Consumers ignore unknown additive fields. Removing fields/codes or changing their type or meaning requires a new compatibility contract. Metadata is output-only: it is not persisted or included in artifact hashes. Output without `_meta` predates this contract.

`--version` used alone returns `plugin_name`, `plugin_version` from the knowledge manifest,
`implementation_id`, and the deprecated `toolkit_version` alias of `plugin_version`.
The alias retains the old string field for consumers; it no longer identifies a toolkit release.
Use `plugin_name` and `plugin_version` for package identity. It needs only Python's standard library, without Git, jsonschema, or a project. Missing or invalid manifests fail instead of supplying an inferred version. `--help` and subcommand help return usage text with exit 0.

`implementation_id` is SHA-256 over sorted relative names and bytes of `.py`, `.json`, `.mjs`, `.js`, `.css` files and `requirements.txt`
under plugin-root scripts and contracts, each part prefixed by its 8-byte big-endian length. Names are relative to the plugin root. Install paths, timestamps and pycache do not affect it. It identifies that source set, not a signature or integrity proof for the entire package. Plugin release version, CLI contract version, DB user_version and artifact versions are separate; this contract performs no migration.

## Failures

Usage errors write one JSON object to stderr with exit 2. Runtime failures do so with exit 1. Stdout is empty. Fields are `error` (human explanation), `command` (parsed command, or null before parsing completes), `code` (machine classification), and `_meta`. Parse stdout and stderr separately. OS termination, failure to start Python and a lost output pipe are outside this response guarantee.

Branch on `code`, not the explanatory text. Known program-owned legacy ValueError prefixes retain their codes; the explicit registry is `DOMAIN_CODES` in `scripts/cli_contract.py`. External messages and user-supplied prefixes do not create codes. Error type takes precedence over prefix:

| Code | Meaning |
|---|---|
| `USAGE_ERROR` | Argument parsing rejected the request |
| `DEPENDENCY`, `DEPENDENCY_UNREACHED` | Required runtime or installed dependency is unavailable |
| `VALIDATION_ERROR` | JSON Schema validation failed |
| `INPUT_ERROR` | Other input ValueError |
| `NOT_FOUND`, `PERMISSION_DENIED`, `IO_ERROR` | File exception type |
| `SQLITE_BUSY` | SQLite BUSY or LOCKED numeric error code |
| `DATABASE_ERROR` | Other SQLite failure; also lock failures on Python 3.10, which lacks sqlite_errorcode |
| `INTERNAL_ERROR` | Unexpected unclassified exception |

Codes do not grant retry permission. After a busy writer exits, inspect current run state before deciding the next command. For partial application follow [workflow recovery](workflow.md); no automatic retry is performed.

## Compatibility boundary

For notebook SQLite location selection, explicit attach and scoped history transfer,
read [notebook storage](notebook-storage.md). These commands retain this JSON transport
and standard-library-only notebook runtime.

The CLI continues existing v1 projects without migration. Unsupported DB versions fail before writes. The development regression preserves a real v1 interrupted application and checks completion, repeated resume, and immutable evidence. This is a specific supported state, not a promise to read every historical version. For runtime prerequisites use `doctor`; for run integrity use [project status](project.md).
