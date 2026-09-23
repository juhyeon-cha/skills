# Read the same evidence in an agent and browser

Use this for a live local reading website or an agent answer that must match it. Reuse the
[relation host boundary](multi-repo.md#establish-the-host-boundary): the host selects the state,
principal and goal. This is a single local host session, not multi-user authentication.
It requires the existing Python runtime from [project setup](project.md), with no new dependency.

## Agent result

Run `multi_repo.py --state STATE --host HOST --principal PRINCIPAL read --input INPUT`, where
INPUT contains only `{"goal":"ID"}`. The result is the managed `wiki` projection without the
redundant Markdown, plus:

- `schema_version: 1` identifies this additive reading shape.
- `index` reports the existing query index comparison, independently of publication/completion.
- `projection_id` hashes the authorized result before this ID and read time are added.
- `read_at` records when this request finished deriving its evidence.

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

## Browser result

Start the foreground server using the same state/host/principal and goal:

```sh
"$PYTHON" "$KNOWLEDGE_ROOT/scripts/reader.py" --state /absolute/relations \
  --host /absolute/host.json --principal reader --goal contract --port 8774
```

Open the printed `http://127.0.0.1:PORT` URL. Port 0 selects an available port. The server provides
an overview, permitted repository pages, evidence/publication history, and `/api/read` JSON.
Every page/API request derives the same public read contract; the projection ID allows comparison
with a CLI read while inputs are unchanged. Search filters only the permitted result and leaves
overall completion unchanged. Repository ID, code commit, target, validation and URL are distinct.
Repository local paths and private state files are not served.

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
