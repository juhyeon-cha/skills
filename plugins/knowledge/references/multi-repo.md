# Relate evidence across repositories

Use `scripts/multi_repo.py` for a shared goal spanning existing local knowledge projects,
cross-repository impact records, or managed search/wiki reads. It adds file-backed relations;
Git captures and the existing project document baseline remain authoritative. It neither
migrates project/automation SQLite schemas nor writes code, documents, or a remote wiki.

## Establish the host boundary

Run the CLI with the Python environment from [project setup](project.md). Supply an exclusive,
host-private state directory, a host-controlled configuration file, and the principal selected
by that host on **every** call:

```sh
"$PYTHON" "$KNOWLEDGE_ROOT/scripts/multi_repo.py" --state /absolute/relations \
  --host /absolute/host.json --principal operator init
```

The executable's `HOST`, `GOAL`, `ATTEST`, `PREDICT`, and `COMPARE` schemas are the authoritative
input shapes. `--input` names a JSON file for every action other than `init`. Host configuration:

```json
{
  "version": 1,
  "repositories": {
    "producer": {"path": "/source/producer", "url": "https://example.invalid/producer",
                 "scope": ["app.py"], "project": "/knowledge/producer"},
    "consumer": {"path": "/source/consumer", "url": "https://example.invalid/consumer",
                 "scope": ["app.py"], "project": "/knowledge/consumer"}
  },
  "principals": {
    "operator": {"manage": true, "goals": ["contract"], "repositories": {
      "producer": ["source", "query", "publish"], "consumer": ["source", "query", "publish"]}},
    "reader": {"manage": false, "goals": ["contract"], "repositories": {
      "producer": ["source", "query", "publish"], "consumer": []}}
  },
  "checks": {
    "producer-check": {"repositories": ["producer"], "cwd_repository": "producer",
                       "argv": ["/absolute/python", "-B", "check.py"]},
    "consumer-check": {"repositories": ["consumer"], "cwd_repository": "consumer",
                       "argv": ["/absolute/python", "-B", "check.py"]},
    "exchange": {"repositories": ["producer", "consumer"], "cwd_repository": "producer",
                 "argv": ["/absolute/python", "-B", "/absolute/exchange-check.py"]}
  }
}
```

These are trusted **host declarations**, not provider authentication, an OS sandbox, or a
multi-user authorization server. A caller able to edit host/state files or choose any principal
already controls this boundary. Keep those files and private artifacts outside published roots.
`manage` permits relation/check/review/publication writes; source access is additionally checked.
Checks execute only host-approved argv and are not a security sandbox. Declare every repository
that a check reads. Full clean Git commits pin repository files; existing absolute file arguments
(including external scripts) are hashed. The host owns undeclared runtime dependencies, installed
packages, environment and network behavior; those are outside reproducibility guarantees.

`source` permits reading the original; public queries additionally require `query`, publication
requires `publish`, and wiki reads require all three. The host's `goals` list explicitly grants
goal ID/version/status and required/withheld member **counts**. Hidden member IDs, targets,
content, locations and links are omitted. Mixed-scope origin/impact text is withheld as a unit.
Permission changes are read from the host file on each invocation; requests cannot provide grants.

`init` captures an identity anchor per logical repository ID. To relocate or clone a repository,
change its host `path`, retaining ID and scope. The new location must reproduce the original
anchor and current capture; an unrelated repository fails closed. URL is a host-declared display
locator, not identity evidence. Existing project settings may retain their old source location;
the adapter validates its current baseline against the newly bound source and its document bytes.
Keep prior projects/artifacts for history; register a reviewed successor through existing project
setup when that project itself needs different settings.

## Record the target; verify actual behavior

1. Register an intake through the [existing intake contract](intake.md). A reference is
   `{ "path": "/absolute/intake-record.json", "sha256": "RAW_FILE_SHA256" }`. The adapter
   revalidates the classified record and its original input; an arbitrary caller note is not an
   intake. `origin` carries its `kind` (`user`, `document`, or `code`), stable request/cause IDs,
   and this reference. Retain actual authorization separately from any document approval.
2. Use `goal` with ID, monotonically increasing integer-family version (for example `v1`, `v2`),
   status (`active`, `deferred`, `withdrawn`), `members`, `integration`, and `origin`.
   Each member maps a logical repository ID to a target **string** and required criterion check
   IDs. Each member check names exactly that repository; each integration check names the whole
   required member set. Every member stays required when evidence is inaccessible. Changing the
   target or status requires a new version and matching confirmed/deferred/withdrawn intake.
3. Use `check` with `{ "goal": "contract", "checks": ["producer-check"] }` to execute mandatory
   checks. Raw results, exact source captures, command input hashes and timing are immutable
   evidence objects. A failed command is recorded with its exit code; it cannot certify completion.
   Timeout/launch failure records exit 124. Source trees must be clean before and after execution.
4. Bring each member's existing project baseline and document bindings to the checked commit with
   the existing refresh procedure. `review-packet` takes `{ "goal": "contract" }`, or additionally
   `"repositories": ["producer"]` for a partial review. It returns a private packet path, ID and
   canonical packet SHA-256. Give the complete packet, including raw check evidence, source files,
   targets and document text to an independent reviewer. Preserve the actual prompt/response in
   host records; `prompt_sha256` binds the packet bytes, not undisclosed wrapper instructions.
5. Import the actual receipt with `attest`, using the executable's `ATTEST` shape. Author and
   reviewer identities must differ. The response names the packet and records verdict, findings,
   and separate implementation/document judgments. Use `synthetic: true` for test doubles and
   visibly synthetic actor/tool/call IDs; only real host observations support model quality claims.
   `synthetic: false` is still a host attestation, not cryptographic proof of a provider call.

The adapter derives member verification from current source, goal, check, document and review
identities; it accepts no `verified` input flag. A producer-only passing packet verifies only
that member. Whole completion additionally needs all required members and a passing review of
the whole integration packet. Goal-first and already implemented code-first behavior use the same
verification path; no invented implementation event is required. Document initialization alone
does not establish semantic review. The final packet's independent document judgment covers the
current baseline, and existing completed-run artifacts are also checked when present.

## Predict, compare, and feed back

Before execution, call `predict` with the goal, an `origin`, the predicted `affected` member IDs,
and rationale. It freezes current source and document bindings for **every** goal member while
preserving the predicted set, including an incorrect set. Request/cause IDs must match the goal.
Predictions from code, document and user intakes share this contract. Semantic impact remains an
independent agent judgment; the adapter cannot infer an undeclared consumer from program meaning.

After source/document updates, `compare` takes the goal, prediction ID, and `feedback` entries.
Each entry names `kind` (`omission` or `decision`), repositories, a validated intake reference,
and description. The comparison retains exact before/after source changes, document binding
changes, current validation, original prediction and request/cause. Actual changed members absent
from the prediction become omissions; those without omission feedback remain `unresolved`.
Creating feedback records routes knowledge maintenance; it does not prove the downstream intake
was implemented. Preserve subsequent project/automation evidence in their existing records.

## Search and managed wiki

`refresh` builds a disposable index from `{ "goal": "contract" }`. `query` uses that input with
optional `text` for literal case-insensitive matching. It rebuilds authorized current evidence
on access and reports index `absent`, `current`, or `stale`; cached content never bypasses access
checks. Results separate current pinned source, target and validation, with evidence IDs and
authorized prediction/comparison/feedback relations. Dirty source, missing artifacts, document
drift, changed goals or failed checks keep completion incomplete.

`publish` records a managed local publication for the same goal input. Optional `audience` names
a host-configured principal, defaulting to the caller; a manager can publish for a read-only
audience without granting permissions. The publisher must also have publication access to every
exposed audience member. Per-member outcomes and overall `published`, `partial`, `failed`,
`deferred` or `withdrawn` outcomes are retained, including earlier successes. A later member
failure is neither an atomic rollback nor a whole success.

`wiki` returns the freshly authorized projection plus a Markdown rendering and publication
history for the current audience. It serves document bodies only when the latest successful
publication matches the current projection and the goal remains complete. Otherwise it returns
diagnostic current/target/status information with `served: unavailable_or_partial` and omits
document bodies. Access withdrawal never shrinks required membership. Goal withdrawal records
status and history; it does not undo Git commits or document edits.

This managed read boundary can stop serving revoked or stale content. **An already copied static
JSON/Markdown export cannot revoke itself or be recalled.** Consumers needing current access
checks must invoke `query`/`wiki` through the trusted host rather than read private objects/indexes.

## Failure and verification boundary

Commands serialize local access with a nonblocking file lock. Immutable objects precede an atomic
state-file replacement; an interrupted write may leave an unreferenced private object, which is
not a committed publication. Preserve it and inspect state before retrying. This adapter performs
no automatic deletion or repair. Source/publication failures preserve earlier observations and
publication history. Storage failure returns nonzero and cannot promise a persisted failure log
on that failed storage. Public CLI errors omit underlying paths, URLs and exception text.

The regression tests use local Git projects and visibly synthetic review receipts; they exercise
contract validation, not semantic accuracy or real reviewer identity. Actual independent model
quality, live host permissions, operational wiki services, distributed concurrency and scale need
separate observations. The adapter is a foreground local boundary, not a central database,
search engine or scheduler; connect existing automation receipts and project runs through their
existing files instead of duplicating their authoritative status here.
