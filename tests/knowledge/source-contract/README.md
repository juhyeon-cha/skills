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
