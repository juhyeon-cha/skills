---
name: plan-sprint
description: Sprint composition procedure. Use when opening a new sprint, assigning stories to a sprint and a rail, or on a "스프린트 계획/시작해" request. Breaking a story down internally is plan-story.
---

# Sprint composition

Before executing command notation in this procedure, read `${CLAUDE_PLUGIN_ROOT}/docs/commands.md` and resolve the plugin and harness roots.

## 1. Fix the sprint ID

The ID format is `YYYY-SNN` (4-digit year - S + 2-digit sequence). Keep that ID unchanged; an optional human objective belongs in sprint documentation, not issue titles. Read the existing IDs with `ledger list --label-pattern 'sprint:*' --all --json -n 0` and take the next sequence for that year. When the sprint has dates, hang them on the stories with `--due`.

**Once the ID is fixed, register it: `ledger sprint-add <ID>`.** One command with the same argument on every backend — where the registration actually lands (a Projects v2 iteration, a Notion page, a key in a file) is the adapter's business, so this procedure does not split by backend. Then confirm the round trip: `ledger sprints --json` has to answer `{"id": "<ID>", "status": "active"}`. An unregistered ID gets blocked by `board-check`, which names it.

- **Registering an ID that is already there fails** (rc≠0, naming the ID) instead of overwriting. A typo cannot quietly replace a live sprint.
- **On `github` the registration needs the project's ITERATION field**, and `ledger init` is what creates it (idempotent — it leaves an existing field alone). With the field missing, `sprint-add` stops and says so; run `ledger init` and register again.

**Closing a sprint is not this command's job, and it is not symmetric across backends.** `sprint-add` only registers, and `ledger sprints` only reads — there is no `sprint-close`, because `github` has no operation that closes an iteration at all. Flipping `active` → `closed` is the backend's:

| Backend | How `closed` happens |
|---|---|
| `github` | By date, on its own — GitHub moves an iteration into `completedIterations` once its end date has passed, so there is nothing to run. To end one early, shorten that iteration in the GitHub UI |
| `notion` | `ledger update <sprint page ID> --status closed` — the sprint is a page, so its own Status carries the state |
| `beads` | Change the `status` value for that key in the root's `sprints.json` |

**On no backend does the state come from a count of closed issues.** That misreading was reverted once already (commit `f88d779`, recorded in the `doc` of `sprints.json`), and it holds on `github` too: the adapter derives `active`/`closed` from the two iteration lists GitHub itself keeps, and reads no issue to do it.

## 2. Collect story candidates

Sources: user instruction, `ledger ready`, the backlog (`ledger list`), external issues. A candidate joins the sprint once **the problem it solves fits in one sentence** — until that sentence exists it stays a candidate.

## 3. Assign

- Label the story epic with `sprint:<ID>` and `rail:<rail ID>`. **Use only rail IDs that `ledger rails --json` answers** — when you need a rail that is absent, settle it with the user first.
- Set the story's assignee to that rail's `owner`: `ledger update <story ID> --assignee <owner>`. **A rail is one person**, so on `github`·`notion` the assignee *is* what makes the rail exist — the adapter derives the pair from the ledger, and two different assignees under one `rail:` label is what `board-check` names. **A story epic created with its `rail:` label already carries the assignee** — the adapter fills it from `ledger rails` at creation, so this step is for a story that already existed (a backlog item being admitted) and for the first epic of a brand-new rail, which has no owner to read yet.
- When the story already has children, confirm the labels reached them with `ledger list -l sprint:<ID> --all`. **Inheritance happens at creation and never again**, so a story broken down before it was admitted has children without the `sprint:` label — add it to each of them (`ledger label add <child ID> sprint:<ID>`). `board-check` names the ones that are missing it.

## 4. Delegate the breakdown

Break each admitted story down with the plan-story procedure (through milestones → tasks → acceptance).

## 5. Completion criteria

Sprint composition is complete when both hold:

1. Every task in `ledger list -l sprint:<ID> --all` has acceptance.
2. `board-check` is rc 0 (registry, labels, acceptance). Redraw the local projection with `board all` — admitted stories move from the backlog tree to the sprint tree.

## 6. Ship the registry

The body of a plan lives in the ledger and the projection sits outside git. **This channel puts nothing
in a commit** — the registries are behind the adapter, so registering a sprint or a rail is a ledger
write, not a file diff. There is no commit and no PR, and what remains is the ledger's own remote
reflection — which is backend-shaped: on `beads` it is `ledger sync-check --push`, and on
`github`·`notion` there is nothing to reflect (the ledger is already remote). Where it exists it rides
outside `git push`, so it needs an explicit instruction from the user.

**There is no PR on this channel** — nothing changed in any repo, so `harness:develop` "사이클 종결" has
no branch to push. What replaces the human merge as the gate on a plan is the ledger itself: a plan is
the artifact with the highest cost to reverse (the whole task tree), so **show the finished tree to the
user and get their confirmation before the develop procedure picks it up** — `ledger list -l
sprint:<ID> --all` is what you put in front of them.
