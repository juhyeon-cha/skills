# Connect an installed SAP Harness knowledge screen

Read this when a user asks to prepare “내 지식”, connect the desktop knowledge screen,
or passes a writing/review handoff copied from that screen. Use notebook.md for
record formats, evidence collection, document authoring and real independent review.
This bridge configures the installed-user workflow; keep developer knowledge in Git.

## Prepare the selected source

1. Inspect the user's question and selected tenant. Resolve the installed SAP CLI,
   Python 3.10+, knowledge plugin root and MarkdownIt module directory through the
   host. Resolve filesystem symlinks to their real absolute paths. If a capability
   is absent, report the missing installation; never silently install a plugin.
2. Show the exact SAP objects and readonly connection before first collection.
   Existing authorization covers only its stated source/object set. Register and
   collect through SAP Harness when authorized; source UUIDs come from its output.
3. Resolve paths with `sap-harness knowledge paths --tenant TENANT --source UUID`.
   Initialize the returned notebook with `--audience user --notes PERSONAL_PATH`.
   Import observations and retain useful notes. Existing context files stay intact.
4. Save the notebook.md refresh plan at ROOT/refresh-plan.json, using the installed
   SAP CLI and exact source, tenant, readonly level and object IDs. Validate every
   selection with the local graph export. The screen displays this object list
   before recollecting. Keep credentials out of both JSON files.
5. Save ROOT/desktop.json with this shape (ROOT is the returned source root):

```json
{
  "version": 1,
  "python": "/absolute/real/python3",
  "knowledgeRoot": "/absolute/installed/knowledge",
  "markdownIt": "/absolute/node_modules/markdown-it"
}
```

Preserve existing configuration and make only the requested binding changes.
Use `notebook status --source UUID --publication WIKI_ROOT` to verify runtime
compatibility before reporting the desktop connection ready. The screen runs the
plugin with its own Electron executable as Node; do not require a Node path from
the user. Reopen “내 지식” after preparing a new source.

## Complete a desktop handoff

Read ROOT/desktop-status.json to locate its selected run under ROOT/runs/RUN_ID.
Inspect collection.json and handoff.json; collection failure is not a fresh success.
Follow notebook.md to write or revise explanations against exact observations and
obtain a real independent review. Preserve notes and previous document revisions.
Do not fabricate a review to make the UI advance.

The screen polls read-only status and distinguishes collection, writing, independent
review and publication. After all current explanations pass review, the user can
select “검토한 설명을 위키에 반영”. That local action builds/checks a new snapshot and
switches the stable entry only on success. Old pages remain accessible during
waiting or failure. A completed state means reviewed against imported evidence,
not continuously verified SAP behavior. First-time and writer handoffs are copied
to the clipboard; the application does not send them to an AI service automatically.
