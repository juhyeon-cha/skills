---
name: status
description: One-screen harness status, read-only — the active sprint, open/closed task counts per story, in-progress tasks with their actor, blocked tasks, unresolved decisions, and stories whose tasks are all closed but which are still open. Use on a "현황" or "지금 어디까지 했어" request, and at the start of a session before picking up a story. It changes nothing in the ledger.
---

# Harness status

Six items, always the same six, always in this order, each as a table. **This procedure only
reads** — the ledger calls are `list` and `show`, and the registry read is `sprints.json`. When one
item has nothing to show, its table has one row saying so; the item is never dropped, so a missing
item means the report was cut short.

## 0. The active sprint — and the two ways it is absent

```bash
jq -r '.sprints | to_entries[] | select(.value.status == "active") | .key' <harness root>/sprints.json
```

**When `sprints.json` is missing, or that command prints nothing, that fact is the first line of the
output** — `sprints.json not found at <path>` or `no active sprint in sprints.json` — followed by
items 3 and 4 only (they do not depend on a sprint). Do not guess a sprint from labels: the registry
is the only source of sprint state (session context block, mapping table).

One read covers items 1, 2, and 5 and 6 — hold it as a file:

```bash
HARNESS_ROOT=<harness root> ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list -l sprint:<ID> --all --json -n 0 > sprint.json
```

The adapter's rc≠0 is reported as it is, with its stderr, and the report stops there.

## 1. Active sprint

| Sprint | Stories (open epics) |
|---|---|
| `<ID>` | `jq '[.[] | select(.issue_type == "epic" and .status != "closed")] | length' sprint.json` |

## 2. Open / closed tasks per story

A task's story is its milestone's parent; a task hanging directly under the epic counts too.

```bash
jq -r '
  (map(select(.issue_type == "feature")) | map({key: .id, value: (.parent // "")}) | from_entries) as $m2s
  | (map(select(.issue_type == "task" or .issue_type == "bug"))
     | map(. + {story: ((.parent // "") as $p | ($m2s[$p] // $p))})) as $tasks
  | .[] | select(.issue_type == "epic" and .status != "closed") | .id as $sid
  | ($tasks | map(select(.story == $sid))) as $t
  | [$sid, .status, ($t | map(select(.status != "closed")) | length), ($t | map(select(.status == "closed")) | length), .title]
  | @tsv' sprint.json
```

| Story | Status | Open | Closed | Title |
|---|---|---|---|---|

## 3. In progress — and who holds it

```bash
HARNESS_ROOT=<harness root> ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list --status in_progress --json -n 0 \
  | jq -r '.[] | [.id, (.assignee // "-"), .title] | @tsv'
```

| Task | Actor (`assignee`) | Title |
|---|---|---|

On the `github` backend the assignee is a GitHub login, not the actor value — say so in the column
header when `ledger.json` says `github` (`harness:develop` 3-0 holds the reason).

## 4. Blocked

Same call with `--status blocked`.

| Task | Title |
|---|---|

## 5. Unresolved decisions

A task is waiting on a human when the **last non-empty line of its notes** starts with
`DECISION_NEEDED` — the same reading the stop guard uses for `VERIFY_PENDING`.

```bash
jq -r '.[] | select(.status != "closed")
  | select(((.notes // "") | split("\n") | map(select(length > 0)) | last // "") | startswith("DECISION_NEEDED"))
  | [.id, .title] | @tsv' sprint.json
```

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
