# Read the same evidence in an agent and browser

Use this for a live local reading website or an agent answer that must match it. Reuse the
[relation host boundary](multi-repo.md#establish-the-host-boundary): the host selects the state,
principal and goal. This is a single local host session, not multi-user authentication.
Use the Python runtime from [project setup](project.md). The browser also requires Node 20+
and the prepared pinned Markdown runtime from [wiki setup](knowledge-wiki.md#render-the-reviewed-body).
Reuse a prepared user-owned runtime; the reader never installs dependencies.

## Agent result

Run `multi_repo.py --state STATE --host HOST --principal PRINCIPAL read --input INPUT`, where
INPUT contains only `{"goal":"ID"}`. The result is the managed `wiki` projection without the
redundant Markdown, plus:

- `schema_version: 1` identifies this additive reading shape.
- `index` reports the existing query index comparison, independently of publication/completion.
- `projection_id` hashes the authorized result before this ID and read time are added.
- `read_at` records when this request finished deriving its evidence.
- Each visible member's `validation_detail` and the goal's `integration_detail` report a
  `stage`, `code` and `next_action` from the diagnostic vocabulary below.

Retain all existing current/target/validation and publication distinctions. The stricter wiki
boundary requires source, query and publish rights. Document bodies require a complete current
publication; pending, withdrawn, inaccessible or stale results remain diagnostic views.
A query-only permission may allow the legacy `query` command to return more than `read`; that is
an explicit interface distinction, not permission to add missing bodies to the browser result.

The read command does not publish, refresh an index or rewrite the state file. It uses the
existing exclusive command lock; a busy writer means unavailable, not an empty successful view.
It compares observable overlap between the wiki and query computations and rejects detected
policy/source/evidence changes. Concurrent external file edits are not an atomic Git snapshot;
keep writers coordinated and report the observed revision/time, not continuous freshness.

## Diagnose a blocked read

Read details alongside validation, goal status, completion, index and served state. A detail
reports the first blocker in source → documents → checks → independent review order, not every
root cause. Integration has its own checks/review after members are verified. When any required
member is withheld, integration reports only `withheld`; hidden identifiers and diagnostics are
omitted. Unknown or unreadable evidence becomes `evidence_unavailable` at the observed stage.

| Code | Established fact | Next action |
|---|---|---|
| `verified` | This validation scope has current evidence | `none` |
| `source_dirty` | The source tree has uncommitted changes | `resolve_source_changes` |
| `documents_pending` | Document state is not ready for the current source | `update_and_review_documents` |
| `document_evidence_changed` | Document content or bindings fail their recorded evidence check | `update_and_review_documents` |
| `check_pending` | A required check has no recorded result | `run_checks` |
| `check_stale` | Recorded check inputs no longer match, or changed during execution | `run_checks` |
| `check_failed` | A check with matching inputs returned a nonzero exit | `inspect_check_and_rerun` |
| `review_pending` | No passing independent review matches current evidence | `request_independent_review` |
| `members_pending` | Integration is waiting for member verification | `resolve_member_blockers` |
| `withheld` | Required evidence is outside the reader's scope | `ask_host_to_verify_access` |
| `evidence_unavailable` | This stage's evidence cannot be established | `ask_host_to_inspect_evidence` |

Check freshness covers goal, command, executable/script file hashes, source snapshots and
unchanged inputs during execution. A historical nonzero exit with changed inputs is stale,
not a current failure. Details contain no check names, commands, paths, output or raw exceptions.
The same coarse `pending_or_stale` validation can have different details and projection IDs.

Treat `next_action` as a handoff to the responsible operation, not authorization to execute it.
After a repair, reread: successful checks may still need a new independent review; completion
does not itself refresh an index or create a publication. An inactive goal remains incomplete
even if an individual validation scope reports `verified`.

Legacy `query`/`wiki` and stored view hashes keep their existing shape. Diagnostics are attached
only to `read`, after legacy index/publication comparisons and the permission intersection.
Observable diagnostic changes between the two computations reject the read as `READ_CHANGED`.

## Browser result

Set `WIKI_MARKDOWN_IT_MODULE` to the absolute module directory of the prepared Markdown runtime
(or pass `--markdown-it`). Start the foreground server using the same state/host/principal and goal:

```sh
"$PYTHON" "$KNOWLEDGE_ROOT/scripts/reader.py" --state /absolute/relations \
  --host /absolute/host.json --principal reader --goal contract --port 8774
```

Open the printed `http://127.0.0.1:PORT` URL. Port 0 selects an available port. The server provides
an overview, permitted repository document catalogues, individual document pages,
evidence/publication history, and `/api/read` JSON.
Every page/API request derives the same public read contract; the projection ID allows comparison
with a CLI read while inputs are unchanged. Document search follows the contract below and leaves
overall completion unchanged. Repository ID, code commit, target, validation and URL are distinct.
Repository local paths and private state files are not served.

Document URLs encode repository ID and the entire canonical document path as separate segments:
`/documents/ENCODED_REPOSITORY/ENCODED_PATH/`. Use catalogue links rather than constructing filesystem
paths. Each request resolves the URL against the fresh permitted projection; an unavailable body
returns 404 even when that URL was previously readable. Rendering preserves the canonical text
and the API projection. It does not author, summarize or approve content.

The text-only Markdown bridge shares heading parsing with the static renderer. It receives only
this request's permitted document paths/text and route identities, never repository/state paths.
Document pages render headings, tables and fenced code, with a local heading navigation list.
Relative links resolve only within the same repository's permitted document set; absolute managed
document routes must also exist in that set of permitted pages. Heading targets must exist.
Unresolved references become non-clickable text without looking for or reading the target.
HTML is inert, images become alt text, and protocol-relative/unsafe links are inactive. Explicit
HTTP(S)/mailto links remain links; the reader fetches no external resources. The Node process is
not an OS sandbox; use a trusted runtime. Missing runtime, timeout or rendering failure fails
closed without cached-body fallback. Node startup is paid on document/catalogue requests; no
cross-request rendered body cache is kept. Search also pays this per-request Node startup.

For flowcharts and cards, author the supported [visual blocks](visual-blocks.md).
The shared renderer turns their ordinary Markdown lists into labeled flows or card grids,
while preserving readable list content for agents and section search. Mermaid fences remain
code and raw HTML remains inert. Malformed recognized visual blocks fail the render just
like other rendering failures; they do not bypass the current permitted-body boundary.

### Search documents and evidence sections

Use `/search/?q=QUERY` in the browser or `/api/search?q=QUERY` for the identical search result
as JSON, URL-encoding the query. The overview search form leads to that page; existing `/?q=`
links also show document results. The reader retains its host-selected identity and goal.
An agent can retrieve the JSON from the running local reader. `multi_repo.py read` remains the
unchanged full projection; the legacy `query` command retains its repository JSON filter.

Search uses only bodies present in the fresh authorized read projection. It normalizes text with
Unicode NFKC and casefold, splits the query on whitespace, and requires every term as a substring
in the same section's displayed text or its document title. Sections follow the shared Markdown
headings, including duplicate heading IDs. Displayed table, code and link-label text are included;
link destinations, repository metadata and fallback path titles are not searchable. This is
literal retrieval, not semantic ranking, translation, stemming or generated answers.

Results are ordered by repository ID, document path and section order. Each carries `repository`,
`path`, `title`, `section`, a bounded `excerpt`, and a managed document `url` with its actual anchor.
`current`, `target`, `validation`, `validation_detail` and `review_synthetic` retain their separate
meanings. Follow the URL to read the full section before answering from an incomplete excerpt.
The JSON wrapper has `schema_version: 1`, `query`, `results`, and the original `projection_id`,
`read_at`, goal/version/status, completion, integration, required/withheld counts, index and served
states. The projection ID identifies the source view, not the query or search algorithm.

Empty queries return no matches and an input prompt. No matches means no matching section in the
currently provided documents, not proof that a feature or inaccessible evidence does not exist.
Unavailable/partial bodies yield no matches; a failed read or renderer returns 503, never cached
results. Search reads current permitted text, not the legacy stored query index: an absent/stale
index can coexist with a current verified publication and searchable bodies. Report both states;
search neither refreshes the index nor changes completion. Every new request rechecks permissions.

Completion, membership and first-blocker diagnostics remain visible. Commit/hash/raw review detail
is under disclosure controls; fixture review receipts remain explicitly marked as test responses.
This separation changes presentation, not the evidence or permission boundary.

The server binds only loopback and fixes identity/goal at startup. Browser parameters cannot
select a principal, host file or goal. Host/Origin checks, escaped text, a restrictive content
policy and no-store responses protect this local read boundary. Other local processes able to
use the URL receive that selected principal's view; do not treat loopback as user authentication.
Use a host-controlled reader principal appropriate for that local session.

Inspect the overview, repository links, evidence page, search and denied direct links in the real
browser. Record actual observations separately from HTTP/unit tests and semantic model judgments.
A source failure returns diagnostic or unavailable state; never fall back to an old cached body.
After a permission or source change, request the page again. Previously displayed, copied or
saved bytes cannot be recalled, and an open page is not a live subscription. Stop with Ctrl-C;
stopping the reader does not stop automation or undo publication.

## Completion

Report the exact goal/version, projection ID, read time, visible/withheld required membership,
index/publication/completion states and remaining evidence gaps. Document review and local
checks do not prove operational deployment. Static exports follow [wiki](knowledge-wiki.md)
and must be labeled snapshots; they cannot provide this request-time authorization behavior.
