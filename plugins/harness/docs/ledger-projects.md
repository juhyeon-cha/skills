# GitHub Project setup and projection

For a new ledger, `ledger init` creates the Project when needed, ensures the fields and views below, and writes `ledger.project_views: true` only after setup succeeds. Commit that configuration change. For an existing ledger, inspect and apply the structural plan, then backfill issue values:

```bash
ledger project-setup --json
ledger project-setup --apply
ledger project-sync --json
ledger project-sync --apply
ledger project-sync --json
```

Setup is complete when the setup plan has no missing fields or views. Backfill is complete when every issue has an empty `changes` array and none reports `skipped`. Commands without `--apply` only read. Both commands are GitHub-specific. Repeating setup preserves existing views, including a same-name view with custom settings; the plan reports those differences under `viewDrift`. It does not rename, delete, or overwrite an existing view.

## Fields and views

`Sprint` is an iteration field selected by its exact name. Its iteration titles are sprint IDs. A different field type under this name or duplicate names fail explicitly. Setup creates the field without inventing sprint registrations; `ledger sprint-add` registers them. `Harness Status` is a dedicated single-select projection of ledger state. Existing default `Status` settings belong to the user and remain unchanged.

| View | Shows |
|---|---|
| 현재 스프린트 | Story epics in the date-current Sprint iteration |
| 백로그 | Open story epics with no Sprint value |
| 실행 | Tasks in the date-current Sprint iteration, board columns by Harness Status |
| 판단 필요 | Open items projected as blocked or needs_decision |

The table views show title, assignees, Sprint, Harness Status, parent and sub-issue progress when those fields are available. GitHub's public create-view API supports filters and board grouping. Set the initial tab order and nested hierarchy presentation in the GitHub UI; setup reports this limitation instead of claiming those settings were applied. Existing custom views remain alongside these four shared views.

## Source of truth and repairs

Issue state, labels and decision events are authoritative. Project changes never flow back into the issue. `sprint:<ID>` must match exactly one active or completed Sprint iteration title. Removing the label clears the projected Sprint value. Multiple labels or an unknown iteration fail with a diagnostic; register or correct the source and rerun synchronization.

Open, in_progress, blocked, deferred and closed map to the same named Harness Status options. An open decision issue, or one whose last nonempty event line starts with `DECISION_NEEDED`, projects as needs_decision. Closing always projects closed. A later event line resolving the decision releases that projection. Execution-state marker rendering is excluded from this event check.

Once `ledger.project_views` is enabled, create, structural/status update, label, close and event-note writes synchronize the affected issue. Execution state and summary updates do not rescan the Project. The client caches field metadata and locates the specific issue's Project item rather than scanning every Project item. GitHub edits outside the adapter and existing issues are reconciled by `project-sync --apply`. Bulk synchronization reads 100 Project items per page with their field values, follows any truncated nested values, and sends up to 10 field changes per mutation request. It re-reads the Project to verify convergence. A partial mutation failure is reported; rerunning reads actual values and sends only remaining changes.

If a write succeeds on the issue but projection fails, repair the reported Project field or sprint mapping and rerun `project-sync --apply`; the issue remains the source of truth. Existing configurations without `project_views` continue without automatic Project writes until setup is applied. A missing configured projection field produces a diagnostic, not a silent success.

API references: [view creation](https://docs.github.com/en/rest/projects/views), [field enumeration](https://docs.github.com/en/rest/projects/fields), [filter syntax](https://docs.github.com/en/issues/planning-and-tracking-with-projects/customizing-views-in-your-project/filtering-projects). Personal Projects require a token accepted by the personal-project endpoints. Read/API failures are surfaced; setup may have created some fields or views before a later request fails, and a retry reads existing names before creating the remainder.
