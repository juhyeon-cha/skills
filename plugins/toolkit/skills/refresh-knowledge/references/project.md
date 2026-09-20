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

`doctor` reports the actual Python, jsonschema, Git and SQLite versions/paths, or fails. It does
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
`status` without `--run` lists runs and the current baseline. Commands return JSON on stdout and
nonzero status with a JSON error on failure. A busy writer fails immediately; retry after that
command exits. Use the [state rules](workflow.md) to distinguish work needed from completion.
