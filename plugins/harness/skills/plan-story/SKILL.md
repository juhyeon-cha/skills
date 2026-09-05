---
name: plan-story
description: Story → milestone → task breakdown and acceptance writing. Use on a "스토리 만들어" or "이슈를 태스크로 쪼개줘" request, and whenever an issue or a backlog item has to become an executable task tree. Sprint composition is plan-sprint.
---

# Story breakdown

## 1. Define the story

- Write **the problem the story solves in one sentence** first. Until that sentence exists it is not yet a story.
- **Put the five below in the body.** The one-sentence problem opens a story; it is not the body — the breakdown happens **when the owner picks the story up**, not when the author files it, so the body holds enough that the owner skips repeating the same investigation.

  | Item | What to write | What happens when it is empty |
  |---|---|---|
  | **Problem** | One sentence. What hurts right now | It is an idea, not a story |
  | **Current state** | The **paths** of the files involved, and what is there and what is missing. Count before you write a number (section 5) | The owner repeats the whole investigation, and a structure written from memory becomes the evidence |
  | **Done shape** | **One observable thing** once this story ends | Nobody knows where a milestone is supposed to stop |
  | **Decided / open** | Split the choices the user or the planner already nailed down from the **questions the owner has to settle** at breakdown time | The owner reopens a closed discussion, or closes an open question alone |
  | **Out of Scope** | The dropped item + why it was dropped (convention below) | An implementation widens quietly and nothing supports calling it excess |

  - **"Open" is the list the owner takes to the user.** When the owner picks the story up and runs this procedure again, they close those questions first and then break it down — leaving a question open costs less than the planner filling it with a guess.
  - **The body goes into the ledger** (`bd create --body-file`). The reason it stays out of the shell command string, and the form it takes, are held by `harness:develop` "원장에 본문을 넘기는 형태".
- Fix the repos involved and name them with `repo:<name>` labels (more than one allowed). Every one of them lives in `repos.json`.
- **Read each of those repos' own conventions before breaking the story down.** Nothing in a target repo loads on its own — the session stands at the harness root — so a milestone or an acceptance written without them nails the harness's taste into the task tree instead of that repo's. **The places to read are owned by `harness:develop` "대상 레포의 관례".** What they yield goes into the story body's **Current state**, and where it constrains a task, into that task's acceptance.
- **Give the story an English slug as a `slug:<rail ID>-<name>` label** for its documentation directory name (lowercase, digits, hyphens; a short summary of the story). **Prefix it with the rail ID** — the format and the reason are owned by the "스토리" row of the mapping table in the session context block. board.sh refuses to render a story without a slug.
- When the original lives outside (a GitHub issue, say), link it with `--external-ref` and carry a summary over, so the task body alone is enough to work from.
- **Write what the story will not do (Out of Scope) into its body.** An inclusion list alone does not fix scope — with nothing written about what was dropped, "surely that was included" arrives later, and an implementation that widens quietly has nothing to be called excess against.
  - The form is one line each: **the dropped item + why it was dropped.** "Out of scope for now" without a reason sends the next person through the same discussion from the start.
  - Register what is postponed as a backlog bead and write the ID beside it. Leave out what will never happen — something needing no action needs no registration either.
  - An item the user closed explicitly belongs in the `deferred` status rather than here (`harness:develop` "결정 상태"). Out of Scope is **what the planner dropped from this story**; deferred is **what the user decided against**. Different origins, so keep them apart.
- **Run a question round right before the approval gate — 2 rounds at most.** Once the five in the table are filled, ask what is still unanswered with the `AskUserQuestion` **tool** (rather than in output text — the tool imposes the restraint of 4 questions per round and 4 options per question). The point is to enrich the design, not to interrogate.
  - **Ask only questions whose answer changes the shape of the milestone/task tree.** When either answer yields the same tree, the planner decides it.
  - **Ship a recommended answer with every question.** A bare list of options leaves the user unable to answer in one word.
  - **The planner investigates facts directly — the user gets asked about choices.** Files, counts, and current behavior are read and confirmed; what goes to the user is choice and priority.
  - **Stop at the end of round 2.** Write the remaining questions into the story body's "open" and move to the approval gate — the owner closes them at pickup.
  - **This is the only design question round.** From section 2 on, the round stays closed — once approved, run to the end. The approval taken in section 2 for exceeding the milestone ceiling is **the confirmation of one decision** rather than a reopened design round, so it sits outside this constraint.
- **Approval gate.** After creating the story bead, show the user **the five in the table plus the repos**, take approval, and then go to section 2. Milestone and task creation come after approval. When the entry point is "break down a story that already exists", showing that story's body stands in for the gate — and **close the questions left in "open" first**, since breaking down around an open question nails its answer into the task tree as an assumption.

## 2. Break it down

Build epic (story) → feature (milestone) → task per the session context block "애자일 계층 ↔ beads 매핑 규약". Express ordering constraints as `blocks` dependencies. A story headed for an unattended loop carries **only tasks with no external wait** (a live system, a human approval).

**Story size ceiling: one story = one PR = 5 milestones.** Size a milestone to the batch condition (single repo · task count) — that condition is written in `develop` section 3 and stays there.

- **5 is not the planner's to exceed.** When it looks like it has to be, ask the user **on the spot** and take approval — this is **the confirmation of one decision** rather than the design question round of section 1, so it sits outside that round's ceiling and its "only one round" constraint (section 1). **With no approval the breakdown stops** — a sixth milestone waits for the answer.
- **Splitting a story is a proposal and the user judges it.** Two conditions produce the proposal: the milestones' `repo:` labels diverge, or the planner sees a reason to split. Once the split is decided, split the story and join the parts with `blocks`.

### M0 — the milestone that proves the premise first

**M0 is an ordinary milestone that happens to be numbered 0** — it runs the develop cycle like any other. Only its character differs: its job is proving the premise the later milestones stand on, and **when the proof comes out different from the expectation, it stops there** (rather than going on to the later milestones). **M0 stays out of the milestone ceiling above.**

**A trigger list decides whether to attach one.** Attach M0 when the story leans on any of these.

| Trigger | What is uncertain |
|---|---|
| **Actual behavior of an external system or library** | What can differ from the docs — response shape, exit codes, failure modes |
| **Data schema or storage format** | Whether the existing data really has that shape |
| **The shape of a public interface other code will bite into** | What has to be fixed here for the later milestones to stay converged |
| **Performance or capacity premises** | Whether "this should be enough" is a measurement |

- Promoting something outside the list to M0 on the planner's own judgment stays allowed.
- **When a trigger fires and the decision is to skip M0, leave one line of reasoning in the story body's "decided".** Silence there is indistinguishable from never having judged.

**Nail the expected result into an M0 task's acceptance** — "what counts as a pass" rather than "confirm it". That is what makes a divergence judgeable. On a divergence the evaluator's `NO_MATCH` / `DEVIATION` stops through the existing human-wait path (`harness:develop` "사람 대기"). **Invent no new signal.**

**Task size rule: one task = one acceptance = one or more commits.** When an acceptance is one passage in one file, merge the task into its neighbor.

**In a multi-repo story, narrow every task to a single repo.** bd hands a task every parent label at creation, so a task ends up with several `repo:` labels — left that way, develop cannot judge which worktree to delegate to and refuses to start. Right after creating the tasks, drop the labels for repos the task does not actually touch: `bd label remove <task ID> repo:<untouched repo>`. A task that genuinely has to change two repos is two tasks — split it on the repo boundary and join with `blocks`.

**Registering several at once means the ids stay unpredicted.** The procedure is held by "여러 개를 한 번에 등재할 때" below.

## 3. Acceptance writing discipline

- **Write observable results only. Leave out the means of implementation.**
  The form is one of three: ① what exists ② what output follows what input ③ which check passes.
- Write a gate item as a command and an exit code (e.g. "npm test exit code 0").
- Apply this to every item: "reading this sentence alone, can pass/fail be called without disagreement?" Reject anything of the "works well" kind.
- **Attach a judging command to every item that can carry one.** All three forms above are shapes a single shell line can judge — existence is `test` / `grep`, input-output is that command plus the expected value, a check is that check's exit code. **An item carrying a command is judged by the machine**, not by a human or an agent (`verify-implement` section 1).
  - **When an item cannot carry a command, leave one line saying why.** Silence is indistinguishable from "could have carried one and did not". Examples that cannot: which item a diff hunk belongs to, whether a passage has gone stale — both are natural-language judgments, so the evaluator sees them.
  - **Confirm the role that runs the command can actually run it.** `guard.sh` narrowly blocks subagent writes — the implementer's `bd` writes are `note` alone, and reviewer and evaluator are barred from `bd` and `git` writes entirely. An unrunnable command leaves the item unjudged and the worker blocked on return (twice in `harness-dfd`). When only the orchestrator can do it, write that fact into the item.
- **Write the failure path alongside.** All three forms above describe the happy path only. Make **what is observed** on bad input, a missing target, and denied permission into items of their own.

## 4. Promoting a review NIT into a task — the convention gate

Ask before promoting: **does this change follow the repo's convention, or leave it?**

- **Count directly** how many places in the repo hold the same pattern. Promote when the target alone is the exception (the change moves toward the convention).
- When the target *is* the convention (the change moves away), skip the task — or, if it is made anyway, write "do not spread to the other N places" into the task body.

## 5. Number discipline

Counts quoted in a plan or a body are **counted before they are written**. Carrying a number out of someone else's report means remeasuring it or naming the source.

## 6. Ready-to-start verification

Check the finished tree with `bd children <story ID>`: 0 tasks without acceptance, no dependency cycles, **0 tasks with 2 or more `repo:` labels** (the narrowing from section 2 was skipped). Passing all three means the tree can go to the develop procedure.

## 7. Document rendering

Redraw the local projection with `scripts/board.sh all`. **A backlog breakdown gets redrawn too** — the `sprint:` label splits the output path (`docs/backlog/<slug>/`) and nothing else. The projection sits outside git — leave it unedited and out of the commit.

When the breakdown changed a registry (`sprints.json` · `rails.json`), ship it through the channel in plan-sprint 6. When it did not, this procedure has no commit, and the ledger push (`bd dolt push`) waits for an explicit instruction from the user.

## 여러 개를 한 번에 등재할 때 — id 를 예측하지 않는다

- **Derive no id from creation order.** There is no way to confirm whether the rule is `max+1` or `count+1`, and one failure that shifts the numbering makes a dependency edge **join the wrong pair with no error**. Take the **actual id** from `bd create --silent` output and use that.
- **Hang the dependencies in one shot with `bd dep add --file -`** — it takes `{"from":…,"to":…}` JSONL on stdin and runs one whole-graph cycle check before committing. `from` is the dependent side, `to` the prerequisite.
- **Assert positively at the end** — child count · that every acceptance is filled · one `repo:` label · dependency edge count. Leave out negative forms like "0 empty ones": one wrong field name yields 0 and reads as a pass (measured — writing `acceptance_criteria` as `acceptance` gives 0 on this ledger).
- **A failure leaves a partial registration — scripts like this are not idempotent.** Rerunning as-is piles up duplicates, and the child-count assertion fails **only after the cleanup target has grown**. Print the actual id to stdout at every creation, and make the failure path emit its own recovery instructions (`bd -C <harness root> delete <id> … --force`).

> Evidence: `harness-dg0.6.1`. `bd create --graph` went unused because its help does not state the format — that trades an unverified id prediction for an unverified format guess, which is the same class of failure.
