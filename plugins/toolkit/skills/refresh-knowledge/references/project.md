# Project setup and public commands

Resolve the absolute installed skill directory as `SKILL_DIR`. Python 3.10+, Git, SQLite support
in Python, and the pinned [requirements](../scripts/requirements.txt) are required. Prepare an
isolated virtual environment outside the plugin cache once, using an authorized dependency
installation. Use its Python for every command; changing cwd must not change the selected project.

```sh
python3 -m venv /absolute/user-owned/knowledge-venv
/absolute/user-owned/knowledge-venv/bin/python -m pip install -r "$SKILL_DIR/scripts/requirements.txt"
PYTHON=/absolute/user-owned/knowledge-venv/bin/python
"$PYTHON" "$SKILL_DIR/scripts/knowledge.py" doctor
```

`doctor` checks Python 3.10+, the pinned jsonschema version, runnable Git, SQLite, and bundled
writing/review files before mutation. It reports actual versions/paths or fails. Host-level skill
resolution and independent-agent availability must be verified by the orchestrator; file presence
does not prove those capabilities. It does
not install dependencies silently. Artifacts and the project database belong outside the installed
skill. Use an exclusive document workspace: SQLite serializes this project's commands, but cannot
coordinate a different project or arbitrary editor targeting the same documents.

Create a baseline spec as described in [source-contract.md](source-contract.md). Then initialize:

```sh
"$PYTHON" "$SKILL_DIR/scripts/knowledge.py" --project /absolute/project-state init \
  --repo /absolute/source-repo --docs /absolute/document-root --repository owner/repository \
  --baseline COMMIT --path src --spec /absolute/baseline-spec.json \
  --audience 'Backend callers' --purpose 'Use the documented behavior correctly'
```

Initialization validates committed source and baseline documents before publishing a new database.
It never overwrites an existing project. Settings include repository/document roots, scope, audience,
purpose and the initial bindings. Changing those settings is not implemented: initialize a separate
project with a reviewed baseline rather than modifying the SQLite file manually. Schema versions
other than 1 fail; no automatic migration is performed.

Subsequent commands share only `--project`; paths below are returned in their JSON results:

```sh
"$PYTHON" "$SKILL_DIR/scripts/knowledge.py" --project /absolute/project-state start --rev NEXT_COMMIT
"$PYTHON" "$SKILL_DIR/scripts/knowledge.py" --project /absolute/project-state status --run RUN_ID
"$PYTHON" "$SKILL_DIR/scripts/knowledge.py" --project /absolute/project-state prepare --run RUN_ID --decisions /absolute/decisions.json
"$PYTHON" "$SKILL_DIR/scripts/knowledge.py" --project /absolute/project-state review --run RUN_ID --review /absolute/review.json
"$PYTHON" "$SKILL_DIR/scripts/knowledge.py" --project /absolute/project-state resume --run RUN_ID
```

`start` returns the source/document context path; `prepare` returns the exact review packet path.
Both forms of `status` return `project` and `settings`: the persisted absolute `repo` and `docs`
roots, repository label, source scope, audience and purpose. Use these with the returned context
and completion paths to inspect results after a handoff; reading database internals is unnecessary.
`status` without `--run` lists recorded phases and the current baseline without loading historical
source/document/packet bodies into Python or opening their context/review files. Each returned
`context_integrity` and, when a review exists, `review_integrity` is `unchecked`; a recorded
completed phase does not certify the exported artifacts. SQLite still reads the v1 JSON records.
Use `status --deep` to inspect every context and current review: each run reports `verified` or
`invalid` plus the corresponding error, without repairing artifacts or aborting on another run's
damage. This checks exported handoff files, not live Git or document correctness.

Before continuing one run, use `status --run RUN_ID`. It strictly checks its context and current
review, failing on malformed, changed, missing or symlink files. `review.id` and `review.path`
identify the currently registered review, including its findings; `next_action` names the phase's
next operation (`resolve_review` means resolving evidence or a policy decision first;
`review_new_baseline` means a reviewed successor for a terminated change).
Preparing a packet clears the current review even if the packet ID is unchanged. Old review files
remain evidence but are not returned as the current review.

For programmatic invocation, version identification, exit codes and failure handling, read the
[public CLI contract](cli-contract.md). A busy writer fails immediately; inspect current state
after that command exits before choosing the next operation. Use the [state rules](workflow.md) to distinguish work needed from completion.

## Supported observation boundary

The integrated observation is macOS with Codex orchestration, local Git/SQLite, Python 3.14 and
jsonschema 4.26.0. Other hosts are not certified by that observation. A host must support local
Python/Git commands, toolkit skill reads, and an independent reviewer; otherwise stop before
application and report the unavailable capability. Source inputs remain pinned UTF-8 regular Git
files. Use a user-owned virtual environment and an exclusive document workspace. No model API,
remote publication, dependency download, database migration, or automatic skill installation is
performed by this CLI.
