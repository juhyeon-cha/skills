# Knowledge wiki

Use this procedure when presenting code-linked knowledge as a human-facing web wiki.
The bundled wiki scripts render reviewed documents; the existing knowledge CLI still owns
source intake, proposal review, and document updates. Keep shared rendering code in this
plugin and repository-specific documents and manifests in the target repository.

## Establish the reading task

Name the reader, the decisions they must make, and the source revision. Inspect existing
knowledge and its evidence before choosing page boundaries. If authoring is needed, use `knowledge:bootstrap` for first documents or `knowledge:update`
for existing documents. Their writing workflow owns page organization and independent review.
Resume rendering from reviewed canonical input.

Keep three kinds of material distinct:

- Shared knowledge: one canonical document body for human reading and agent retrieval.
- Agent procedures: tool use, permissions, and update instructions in their owning skills.
- Evaluation records: frozen questions, answer keys, raw responses, and execution receipts
  outside the ordinary reading path, linked from the evidence record when appropriate.

Record required propositions and reader questions before authoring. Include expected
answers and source support, especially prerequisites, negative cases, and what a successful
local check does and does not establish. A missing prerequisite can prevent action even
when every sentence on the page is true.

## Render the reviewed body

Confirm independent document review through `knowledge:review` before treating knowledge as reviewed.
Derive page bodies and search text from the same canonical input. Preserve relative links
for direct document readers and resolve them to valid routes and heading anchors in HTML.
Keep navigation, summaries, and visible status labels consistent with the body.

Record the source revision separately from document review, build integrity, and live
verification. Put technical provenance behind a clear evidence link or disclosure. State
whether the site is a fixed snapshot. Comparing a supplied revision or checking file hashes
establishes only that comparison; freshness requires observing the actual source and index.

Use the bundled renderer when a local multipage wiki is requested. Its commands take explicit
paths and never write dependencies or output into the installed plugin. Node.js 20+ and the
pinned Markdown runtime are required. Resolve `KNOWLEDGE_ROOT` to this installed knowledge plugin directory;
for source development, use the assigned linked worktree's knowledge plugin directory instead.

Prepare a fresh user-owned runtime outside the plugin cache:

```sh
WIKI_RUNTIME=/absolute/user-owned/wiki-runtime
mkdir -p "$WIKI_RUNTIME"
WIKI_RUNTIME=$(cd "$WIKI_RUNTIME" && pwd -P)
cp "$KNOWLEDGE_ROOT/scripts/wiki/runtime/package.json" "$WIKI_RUNTIME/package.json"
cp "$KNOWLEDGE_ROOT/scripts/wiki/runtime/package-lock.json" "$WIKI_RUNTIME/package-lock.json"
npm ci --prefix "$WIKI_RUNTIME" --ignore-scripts
```

Choose an unused runtime directory so existing dependency manifests are preserved. Run the
approved dependency setup once and reuse it while its pinned manifests remain unchanged.
The target repository needs no npm scripts, renderer copies, or rendering dependency.

```sh
node "$KNOWLEDGE_ROOT/scripts/wiki/build.mjs" /absolute/content /absolute/new-site "$WIKI_RUNTIME/node_modules/markdown-it"
node "$KNOWLEDGE_ROOT/scripts/wiki/check.mjs" /absolute/content/manifest.json /absolute/new-site
node "$KNOWLEDGE_ROOT/scripts/wiki/server.mjs" /absolute/new-site 8769
```

Open the printed loopback URL. Serve only an output whose build and check completed. To compare
against an independently observed revision, append `--observed-revision REV` to the check.
A mismatch returns nonzero and reports stale; the caller remains responsible for obtaining
that revision. Serving is a local preview, not remote publication or a source-change watcher.

### Content manifest

Place `manifest.json` beside the canonical Markdown files:

```json
{
  "title": "Project knowledge",
  "revision": "PINNED_SOURCE_REVISION",
  "home": "overview",
  "evidencePage": "sources",
  "pages": [
    {"id": "overview", "path": "overview.md", "title": "Overview", "summary": "Choose the next action."},
    {"id": "sources", "path": "sources.md", "title": "Evidence", "summary": "Scope and verification.", "kind": "evidence"}
  ]
}
```

`home` names a listed page and maps to `/`; other IDs map to `/ID/`. `evidencePage` is optional
and, when present, names a listed page. Page paths use canonical relative paths (for example `guide.md` or `guides/setup.md`,
without `./`, `..`, backslashes or absolute paths). Page IDs and paths are unique; page IDs use lowercase
letters, digits and hyphens starting with a letter. Page counts and names come from this manifest.
Optional per-page `evidence.reviewStatus` and `evidence.liveStatus` are human-readable recorded
states, never attestations manufactured by the renderer. Missing states display as unverified.

Use local Markdown links and existing heading anchors. Raw HTML is rendered inert; images are
outside the supported subset. Broken references, missing inputs, duplicate IDs, path escapes,
symlinks and unlisted Markdown files fail the build. Build into a new output directory; existing
output is refused. A failed build can leave partial files, so inspect them and choose a new
output before retrying. Follow the user's deletion boundary for cleanup.

The completion receipt binds document, manifest, search and HTML bytes and is written last.
The checker detects changed bytes and missing outputs. This is local integrity evidence,
not semantic review, atomic publication, live verification or currentness.

## Evaluate reading and change propagation

For document acceptance and reader evaluation, read and apply the existing
[document acceptance contract](../skills/review/references/document-ac.md).
Use the shared Markdown as the document input and link failed and repaired versions to their
actual responses. That contract owns freezing, role separation, judgment, and rerun requirements.

Exercise the served site in a browser: route navigation, search result and empty state,
unknown route, keyboard access, heading links, and narrow/wide layouts including resize.
Record observations against the exact built output. Source inspection alone does not
establish these interactions.

Replay a real change through the existing project workflow: pin before/after revisions,
freeze expected affected claims, independently review the proposal, apply it, inspect the
completion record, then regenerate HTML and search. Check both the appearance of the new
claim and removal of the superseded claim. Include dependency files needed to explain the
change. Distinguish one replayed document from a complete wiki update, and a historical
replay from a live change subscription.

Finish with the reviewed content version, built output, actual reader/browser observations,
change-propagation result, and remaining unverified scope. Record observed interventions,
cost, and latency only when captured. Decide whether further infrastructure is needed from
observed failures and comparison with the existing approach; a multipage wiki alone does
not require a central database or search service. Remote publication follows the parent
skill's separate authorization boundary.
