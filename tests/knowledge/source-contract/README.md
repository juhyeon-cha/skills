# Pinned source contracts

Use this repository-local CLI to capture and compare Git text evidence before implementing
knowledge updates. It does not generate documents, evaluate LLMs, or publish anything.
`schema.json` owns the version-1 snapshot and change shapes. Bump the contract version when
changing their meaning. This development CLI is not part of an installed plugin.

## Setup and run

Use Python 3.10+ with Git and an isolated environment. Install `requirements.txt` there;
the CLI fails when jsonschema is unavailable instead of skipping contract validation.
From the repository root (replace PYTHON and all example coordinates):

```sh
PYTHON=/absolute/path/to/venv/bin/python
"$PYTHON" -m pip install -r tests/knowledge/source-contract/requirements.txt
"$PYTHON" tests/knowledge/source-contract/cli.py capture \
  --repo /absolute/path/to/repository --repository owner/repository \
  --rev COMMIT --path src --out /absolute/new/snapshot.json
"$PYTHON" tests/knowledge/source-contract/cli.py check /absolute/new/snapshot.json \
  --repo /absolute/path/to/repository
"$PYTHON" tests/knowledge/source-contract/cli.py diff before.json after.json --out change.json
"$PYTHON" tests/knowledge/source-contract/cli.py check change.json \
  --before before.json --after after.json --repo /absolute/path/to/repository
KNOWLEDGE_PYTHON="$PYTHON" bash tests/knowledge/source-contract-check.sh
```

## Interpretation

- `--path` is a literal repository-relative file or directory; repeat it for multiple scopes.
  Paths must have no leading/trailing slash, backslash, dot or parent segments. No glob expansion
  is performed. An unmatched scope produces a valid empty file set to represent complete deletion;
  inspect the printed file count when capturing a new scope. Compare only identical scopes and
  stable repository identities. The identity is caller-supplied, not authenticated against a remote.
- Capture reads committed Git blobs, ignoring working edits and Git replacement objects. It supports
  UTF-8 regular files and executable mode. Symlinks, submodules, NUL-containing or non-UTF-8 data
  within the selected scope fail. No fetch, checkout, repository hooks, or source changes occur.
- The snapshot ID hashes canonical JSON excluding its own ID. File hashes cover UTF-8 bytes.
  Repeating a capture at the same resolved commit and scope gives identical output bytes.
  Output parents must exist; outputs use exclusive creation. Existing files are refused.
  A process interruption may leave a partial output; inspect it and use a new output path.
- `check` without `--repo` establishes internal structure/hash consistency only. It cannot detect
  a coherently rewritten snapshot or certify source completeness. With `--repo`, it rebuilds the
  selected scope from the pinned Git tree and compares the full record, including omissions.
- Changes require both snapshots for checking. The checker recomputes the change set, not merely
  the result hash. Add `--repo` to establish both snapshots against Git. A rename candidate is a
  unique removed/added pair with identical content and mode, not proof of semantic identity.
  Ambiguous pairs stay removed/added; a move with edits also stays removed/added.
- No symbol extraction, caller graph, policy impact, current-branch freshness, atomic multi-file
  knowledge update, or recovery scheduler is implemented. Those are subsequent contracts, not
  implied by a passing source check. No runtime observation is inferred from static source.

The shell test is discovered by `tests/run-all.sh`. Set `KNOWLEDGE_PYTHON` to an environment with
the dependency installed when using that runner; missing dependencies fail rather than skip.
For initiative scope and the deferred evaluation work, read the
[initiative index](../../../docs/initiatives/code-driven-knowledge/README.md).

## Bind claims and find affected documents

When connecting source changes to document review, use `impact.py` and the definitions in
`impact-schema.json`. Supply a spec containing exact document excerpts and their source paths:

```json
{"documents":[{"path":"guide.md","claims":[{"id":"retry-rule","text":"Exact existing sentence.","evidence":["src/retry.py"]}]}]}
```

Paths in this spec have two roots: document paths use `--docs-root`; evidence paths use the
snapshot's Git repository root. Claim IDs are unique within each document. Both commands
require a local source repository and verify pinned snapshots against Git before writing.

```sh
"$PYTHON" tests/knowledge/source-contract/impact.py bind spec.json \
  --snapshot before.json --repo /absolute/source/repo \
  --docs-root /absolute/documents --out bindings.json
"$PYTHON" tests/knowledge/source-contract/impact.py impact bindings.json \
  --before before.json --after after.json --repo /absolute/source/repo \
  --docs-root /absolute/documents --out impact.json
```

`bind` records the exact snapshot ID and hashes of the complete document bytes. An excerpt
must occur literally in its document, and every evidence path must exist in the snapshot.
Document paths are relative and symlinks below the supplied document root are rejected.
`impact` rejects changed or missing documents, a different baseline, malformed bindings, and
source mismatches. After legitimate edits, review the links and bind again; never carry a
binding forward merely by replacing its hash or snapshot ID.

Read `candidates` as documents and claims requiring review, with the concrete file changes
that selected them. Read `unlinked_changes` as changes with no declared dependent claim;
this always includes additions, since a baseline cannot link a file that did not exist.
A changed file selects all claims linked to that file, including mode-only changes. A rename
candidate selects the old path's claims and does not rewrite their links. Shared evidence
can select multiple documents. Unchanged input yields two empty lists; an empty candidate
list alone does not mean the change is irrelevant.

Links are supplied by the author or agent. Literal excerpt presence is not semantic truth,
and the CLI cannot prove the completeness of those links or discover indirect dependencies.
The output is a deterministic review queue, not approval to edit or publish documents.
It does not assert current-branch freshness, lock concurrently edited documents, evaluate
model output, or apply updates. Re-run against stable inputs before consuming an old queue.
The source test wrapper also runs the impact regression cases.

## Prepare and apply updates

After deriving candidates, follow [document updates](UPDATES.md) to author decisions,
prepare a reviewable plan, and apply it with stale-document checks and partial retry.
