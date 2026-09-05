---
name: plan-sprint
description: Sprint composition procedure. Use when opening a new sprint, assigning stories to a sprint and a rail, or on a "스프린트 계획/시작해" request. Breaking a story down internally is plan-story.
---

# Sprint composition

## 1. Fix the sprint ID

The ID format is `YYYY-SNN` (4-digit year - S + 2-digit sequence). Read the existing IDs with `bd list --label-pattern 'sprint:*' --all --json -n 0` and take the next sequence for that year. When the sprint has dates, hang them on the stories with `--due`.

**Once the ID is fixed, register it in the root `sprints.json` as `"<ID>": {"status": "active"}`.** That registry is the source of truth for whether a sprint is closed, and flipping the value to `closed` at the end belongs to this same procedure — the registry alone decides closure, and a count of closed issues decides nothing (the mapping table in the session context block, sprint row). An unregistered ID gets blocked by `board-check`, which names it.

## 2. Collect story candidates

Sources: user instruction, `bd ready`, the backlog (`bd list`), external issues. A candidate joins the sprint once **the problem it solves fits in one sentence** — until that sentence exists it stays a candidate.

## 3. Assign

- Label the story epic with `sprint:<ID>` and `rail:<rail ID>`. **Use only rail IDs registered in the root `rails.json`** — when you need a rail that is absent, update the registry with the user first.
- Set the story's assignee to the rail owner named in the registry: `bd update <story ID> --assignee <owner>`.
- When the story already has children, confirm the labels were inherited with `bd list -l sprint:<ID> --all`.

## 4. Delegate the breakdown

Break each admitted story down with the plan-story procedure (through milestones → tasks → acceptance).

## 5. Completion criteria

Sprint composition is complete when both hold:

1. Every task in `bd list -l sprint:<ID> --all` has acceptance.
2. `checks/board-check.sh` is rc 0 (registry, labels, acceptance). Redraw the local projection with `scripts/board.sh all` — admitted stories move from the backlog tree to the sprint tree.

## 6. Ship the registry

The body of a plan lives in the ledger and the projection sits outside git. What this channel puts in a
commit is **registry changes only** — `sprints.json` (open/close) and `rails.json` (rails). When the
registry is unchanged there is no commit and no PR, and what remains is the ledger push
(`bd dolt push`) — it rides outside `git push`, so it needs an explicit instruction from the user.

The body of the close procedure is owned by `harness:develop` "사이클 종결 — PR 이 종점이다"
— commit → push the work branch → open the PR. **Restate none of those steps here.** This channel has
two constraints of its own.

1. **The commit carries the registry only.** Mixing code in dissolves the reason this channel exists.
2. **A human does the merge.** Leave the PR open and let a human confirm the plan before merging. A plan
   is the artifact with the highest cost to reverse (the whole task tree) — its gate is **the human
   merge**, and opening a PR spends none of that gate. It puts the plan where a human can see it.
