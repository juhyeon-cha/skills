# Working in skills

This repository owns the plugin marketplace source.

## Documentation

Before writing or editing agent-facing documentation, read and apply
`mattpocock-skills:writing-for-agents` and `toolkit:agent-doc-audit`.
Use the former for authoring and the latter for auditing existing text,
including its proposal and confirmation procedure.

Write agent-facing documentation in English. Preserve quoted user
utterances, referenced section titles, and required output strings.
Follow the requested language for user-facing deliverables.

Keep each rule in one authoritative location. Point to that location
with an explicit condition for reading it. Keep always-loaded context
short; place task-specific procedures in the document that owns them.

## Source and file placement

Change plugin source under `plugins/<name>/` in an assigned linked
worktree. Preserve the main checkout and update installed copies through
the marketplace update procedure.

Before adding or moving a file, read `docs/development.md`,
“What belongs in the plugin, and what belongs in this repo”.

## Development and verification

Before changing harness internals, read `docs/development.md`.
When executing a harness development cycle, also read
`plugins/harness/docs/engineering.md`.

Run `bash scripts/check.sh` from the worktree root before committing.
Inspect its output and report any checks that did not run.

For plugin code changes, run the relevant development checks against
the changed source. Consult `tests/run-all.sh` for the development suite
and its exclusions. Report the tested boundary and what remains
unverified.

## Marketplace metadata

Treat each plugin manifest's `description` as authoritative. Keep its
marketplace entry and README description identical.

## Commits and releases

Follow README.md, “커밋”, for commit conventions.

Before changing versions or preparing a release, read
`.claude/skills/release/SKILL.md` and README.md, “버전”.
Keep release-authoring policy in this repository's development files;
installation and update instructions belong in the shipped plugin.
