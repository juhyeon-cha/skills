---
name: triage
description: Backlog triage — sweep the open items that belong to no sprint, put duplicate pairs, items that no longer stand, and ranked sprint candidates in one proposal table, and apply only the rows the user confirms. Use on a "백로그 정리해줘" or "triage" request, and before plan-sprint. Composing the sprint itself is plan-sprint.
---

# Backlog triage

The backlog is every open item without a `sprint:` label. It grows by one line per retrospective and
shrinks only when someone reads it whole — this procedure is that read. It ends in a table; **nothing
is written to the ledger until the user confirms a row.**

## 1. Collect

```bash
HARNESS_ROOT=<harness root> ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list --status open --json -n 0 \
  | jq '[.[] | select(((.labels // []) | map(startswith("sprint:")) | any) | not)]'
```

- The adapter's rc is the gate. **rc≠0: report the adapter's stderr as it is and stop — no table.** A
  table built on a partial read proposes closing items it never saw.
- 0 items: report "nothing to triage" and stop.
- Otherwise read every item's `title`, `description`, `issue_type`, `priority`, `created_at`, and
  `parent` from that JSON; a child of an unlabeled epic is triaged through its epic, not alone.

## 2. Propose

One table, three sections, every row with its reason. The reason is what the user judges; a row
without one is not a proposal.

### Duplicate pairs

Two items are duplicates when **their titles are identical**, or when **the first sentence of their
"문제" (problem) section is identical** after trimming whitespace. Anything looser is a similarity,
not a duplicate — list it under sprint candidates with a note if it matters, never here. Per pair:
both IDs, which one stays (the older `created_at`, unless the newer one carries the notes), and the
criterion that matched.

### Items that no longer stand

An item no longer stands when what it names is gone or already decided: the file, rule, hook, or
command in its title or problem statement no longer exists in the tree it points at; the story it
belongs to closed with that scope decided out; or a later item already solved it. Per row: the ID
and the observation that shows it — a `grep` count, a missing path, the closing decision's ID. An
item whose *wording* is stale but whose *ask* still holds is a rewrite proposal, not a removal.

### Sprint candidates

The remaining items, ranked. Order: priority first (`priority` ascending); at equal priority a bug
before a task; at equal type, the item that unblocks others (`dependent_count`) before the one that
blocks nothing. Per row: the ID, the rank, and one line on why it is worth a sprint now — a tool it
needs that now exists, a repeat observation, a gate it keeps failing.

## 3. Confirm, then apply

Show the table and wait for the user's answer per row. **Only a confirmed row is applied**; a row
left undecided stays as it is, and silence confirms nothing.

| Confirmed row | What to run |
|---|---|
| duplicate pair | write `duplicate of <kept ID>` to a file, then `ledger.sh close <dropped ID> --reason-file <file>` |
| no longer stands — hold | `ledger.sh update <ID> --status deferred` |
| no longer stands — rewrite | leave the new wording with `ledger.sh note <ID> --file <file>`; the rewrite itself is the user's or plan-story's |
| sprint candidate | hand the ID to `plan-sprint`; triage does not label sprints |

Bodies (the close reason, the note) go through a file, never inline in the command string — the form
is `harness:develop` "원장에 본문을 넘기는 형태". After applying, rerun step 1 and confirm the closed
IDs are no longer in the list. Report the table with an "applied" column.
