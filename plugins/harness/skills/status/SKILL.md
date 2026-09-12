---
name: status
description: One-screen harness status, read-only — the active sprint, open/closed task counts per story, in-progress tasks with their actor, blocked tasks, unresolved decisions, and stories whose tasks are all closed but which are still open. Use on a "현황" or "지금 어디까지 했어" request, and at the start of a session before picking up a story. It changes nothing in the ledger.
---

# Harness status

Before executing command notation in this procedure, read `${CLAUDE_PLUGIN_ROOT}/docs/commands.md` and resolve the plugin and harness roots.

Six items, always the same six, always in this order, each as a table. **This procedure only
reads** — the ledger calls are `list`, `show`, and the registry query `sprints`. When one
item has nothing to show, its table has one row saying so; the item is never dropped, so a missing
item means the report was cut short.

## 0. The active sprint — and the two ways it is absent

```text
node "<plugin-root>/scripts/ledger.mjs" --root "<harness-root>" sprints --json
```

Replace the path placeholders with this session's absolute plugin and harness roots.
Read the returned JSON and select rows whose `status` is `active`.

**When the adapter fails, or no active row exists, that fact is the first line of the
output** — the adapter's stderr as it stands, or `no active sprint` — followed by
items 3 and 4 only (they do not depend on a sprint). Do not guess a sprint from labels: the registry
the adapter answers is the only source of sprint state (session context block, mapping table), and
what backs it — a Projects v2 Iteration, a Notion page of its own, `sprints.json` on `beads` — is the
backend's business, not this procedure's.

One read covers items 1, 2, 5 and 6 — retain the complete returned snapshot:

```text
node "<plugin-root>/scripts/ledger.mjs" --root "<harness-root>" list -l sprint:<ID> --all --json -n 0
```

The adapter's rc≠0 is reported as it is, with its stderr, and the report stops there.

## 1. Active sprint

| Sprint | Stories (open epics) |
|---|---|
| `<ID>` | Count rows with `issue_type == "epic"` and `status != "closed"` in the snapshot |

## 2. Open / closed tasks per story

A task's story is its milestone's parent; a task hanging directly under the epic counts too.

For each epic whose status is not `closed`, group its `task` and `bug` rows using that
parent mapping. Count `status == "closed"` as closed and every other status as open.

| Story | Status | Open | Closed | Title |
|---|---|---|---|---|

## 3. In progress — and who holds it

```text
node "<plugin-root>/scripts/ledger.mjs" --root "<harness-root>" list --status in_progress --json -n 0
```

| Task | Actor | Assignee | Title |
|---|---|---|---|

Display the adapter's explicit `actor` separately from `assignee`. On the `github`
backend the latter is a GitHub login and cannot identify a session. If no explicit
actor is available, report it as unknown; do not infer one from the login
(`harness:develop` 3-0 holds the claim procedure).

## 4. Blocked

Same call with `--status blocked`.

| Task | Title |
|---|---|

## 5. Unresolved decisions

A task is waiting on a human when the **last non-empty line of its `events` (or legacy `notes` when `events` is absent)** starts with
`DECISION_NEEDED`; execution phase is read separately by the stop guard.

Read `id` and `title` from matching rows whose status is not `closed` in the snapshot.

| Task | Title |
|---|---|

## 6. Wrap-up incomplete

A story whose tasks are all closed but which is itself still open — the cycle close
(`harness:develop` "사이클 종결") has not run. Same grouping as item 2, filtered to
`open == 0 and total > 0`.

| Story | Status | Title |
|---|---|---|

## Completion criterion

Six tables printed (or the absent-sprint first line plus tables 3 and 4), every count taken from the
commands above in this session — no number carried over from an earlier report.
