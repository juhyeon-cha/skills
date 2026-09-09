---
name: develop
description: Story (epic bead) development execution procedure. Use on a "스토리 시작/착수해" or "<스토리ID> 개발해" request, and while running the task implementation cycle. Workspace creation → milestone-scoped implement→verify cycle → story wrap-up.
---

# Story development

## 1. Pickup verification

**The session unit is (story, repo).** A development session opens in the target repo's main checkout — wherever that clone lives — and the clone directory name is this session's repo, which must match one of the story's `repo:` labels. A multi-repo story is worked by **one session per repo**; the sessions coordinate through the ledger (the story bead's notes and the tasks' claims), not through each other. The harness root is what `${CLAUDE_PLUGIN_ROOT}/lib/harness-root.sh` prints — the repo itself, recognized by the `.harness.json` committed at its root — hold it for the whole cycle, every ledger call is `HARNESS_ROOT=<harness root> ledger.sh …`. `ledger.sh` in this skill is always `${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh` — the ledger adapter; its subcommands, arguments and JSON keys are those of `bd` (`ledger.sh --help`), and the backend is `ledger.backend` in that `.harness.json`.

- `ledger.sh show <story ID>` — check that its type is epic, that it carries a `repo:*` label, and that **one of those labels is this session's repo**. Otherwise stop and report what is missing.
- Read the story's `ACTOR:` notes in the form below. The last `ACTOR: <this session's repo> <값>` line is this cycle's claim actor (3-0 creates one when it is absent). When the story is already `in_progress` under another actor **for this repo** and that ACTOR note is not yours, that is a **concurrent-work collision** — do not pick it up; report to the human.
- `ledger.sh children <story ID>` shows the milestone→task tree. If even one task has no acceptance, do not pick it up; go back to the plan-story procedure.

### ACTOR note — `ACTOR: <레포> <값>`

- **Format**: `ACTOR: <레포> <값>` — the repo is this session's repo (the clone directory name), the value is `sess-` + 6 random characters. One live line per (story, repo); a multi-repo story carries one line per repo, left by the session of that repo.
- **Reading**: take the last `ACTOR:` line whose repo is this session's repo. Lines for other repos belong to the other sessions of the same story — they are not collisions and are not reused.
- **Old format — `ACTOR: <값>` with no repo → `DECISION_NEEDED`.** A value without a repo cannot be attributed to a session, so it is neither reused nor overwritten by guess; ask the human whether to re-claim this (story, repo) under the new format. The human-wait handling is "사람 대기" (this skill).
- **Only `<값>` goes into `--actor`** at claim time. After successful claim, confirm the actor mapping with `state.mjs bind` as `${CLAUDE_PLUGIN_ROOT}/docs/state.md` specifies. Pass actual runtime/repository/session identifiers explicitly; PreToolUse cannot prove claim success. On resume bind the ledger actor again for the resumed session, without inventing a new actor.

## 2. Create the workspace

Read `${CLAUDE_PLUGIN_ROOT}/docs/workspace.md` when creating, resuming or cleaning a workspace. Both runtimes use `node <plugin>/scripts/workspace.mjs create <repo> <story>` for creation and `enter <workspace>` for ledger wiring and verified preparation. The command preserves the default `.claude/worktrees/<name>` layout and `worktree-<name>` branch; `lib/worktree-name.sh` owns story-to-name conversion. Resume an existing workspace through `inspect` then `enter`, using the Git registration's path even when it is outside the clone.

Claude's native `EnterWorktree` remains a supported creation/entry transport: its PostToolUse wrapper calls the same common entry command. Do not also create the same workspace through the CLI. Codex uses the CLI and sets subsequent command cwd to the returned `top`; a subprocess cannot change the parent session's cwd.

Before delegation, require a successful entry, `linked: true`, the expected branch and a matching Git common directory. Run `node <plugin>/scripts/workspace.mjs ready <workspace>` and require exit 0 with `canDelegate: true`. A verified bootstrap gives `ready: true`; `not-configured` permits delegation only when preparation is unnecessary and there is no repository EnterWorktree hook. Preparation failure, timeout, unknown lock ownership or `LEGACY_HOOK_UNVERIFIED` blocks implementation delegation and preserves the workspace. Resolve the diagnostic, then retry `prepare` and check `ready` again. Never promote an old marker or hook existence to success. Retain the returned workspace path and the explicit harness root for every delegation and ledger call. The workspace path is Git-owned; `HARNESS_ROOT` selects ledger coordinates and never changes which repository is inspected or cleaned.

## 3. Task cycle

Start from the first task whose dependencies are clear and go **milestone by milestone**. The batch condition fixes the unit of verification:

- **Batch mode is the default flow.** The condition is that **the milestone is single-repo** (every child task carries the same `repo:` label) and that **the task count is around 4**. Delegate every task of the milestone **to one implementer as a list**, implemented in dependency order (the implementer commits and leaves a `VERIFY_PENDING` note per task, then moves to the next — the discipline is `${CLAUDE_PLUGIN_ROOT}/agents/implementer.md` "When the task ID is a list"), and at the end of the milestone run **verify-code once → verify-implement once → close the tasks together**. A task that is implemented but not yet closed stays `in_progress`, marked with a `VERIFY_PENDING` note.
- **Outside the condition the per-task flow holds** — when the milestone crosses repos or the task count exceeds that width, delegate implementation → verify-code → verify-implement → close **per task**.
- **This condition is written here.** Other documents (`verify-code`·`verify-implement`·`plan-story`·`implementer`·`${CLAUDE_PLUGIN_ROOT}/docs/operations.md`) point at this section and do not restate the condition.

The steps below apply, **in batch mode, 0 once to the whole list and 1 once to the milestone**, with 2~5 applied whenever a signal arrives. Outside the condition, run 0~5 per task.

0. **Two checks before pickup.**
   - **Repo decision**: check that the task carries exactly one `repo:` label — that label fixes the worktree to delegate into. With two or more, do not pick it up; go back to plan-story's narrowing (section 2).
   - **Atomic claim**: take it with `ledger.sh update <task ID> --claim --actor <actor value>`. **In batch mode, claim every task of the list under the same actor before delegating** — drop a rejected task from the list. That leaves as many unmarked `in_progress` tasks as the list holds until the implementer leaves its marks, and `checks/rules-check.sh` S22 counts **the tasks of one actor within one story as a single lane**, so that state is not a violation — do not defer the claim to one per task.
     - **Right before delegating, leave `ledger.sh note <task ID> "DELEGATED: <마일스톤ID>"` on every claimed task.** 4b of the stop guard (`${CLAUDE_PLUGIN_ROOT}/hooks/stop-resume.sh`) exempts that stretch on this mark — without it there are as many unmarked `in_progress` tasks as the list holds, from the claim until the implementer's first commit, and a stop inside that window is blocked while matching none of the guard's three exits (observed in `harness-0uw`). The mark sits in **the same place under the same rule** as the `VERIFY_PENDING` of step 2 (the last non-empty line of notes), so the mark the implementer leaves after committing replaces it naturally. It is a one-line fixed string with no backtick and no `$`, so it falls under the inline allowance of "원장에 본문을 넘기는 형태" (this skill).
     - **The actor's origin is a note on the story bead.** Pickup verification (section 1, "ACTOR note") reads the last `ACTOR: <this session's repo> <값>` line of the story's notes — use that value as is when it exists (picking up an interrupted cycle — the same actor passes claim idempotently, so resumption happens by itself), and when it does not, make `sess-` + 6 random characters and leave it with `ledger.sh note <story ID> "ACTOR: <레포> <값>"`. An old-format line (no repo) is `DECISION_NEEDED` — section 1 holds the rule.
     - **Inline the value as a literal in every ledger call.** Holding it in a shell variable (`$HARNESS_ACTOR`) and referencing that is forbidden — the Bash tool gets a new shell per call, so the variable evaporates, and an empty value falls back to the default actor (git user.name), which makes **two sessions on one machine the same actor and lets claim pass idempotently**.
     - **Judge claim state from the claim attempt's rc, or from `status` and `assignee` read together.** A rejection is rc=1 with its message on stderr — in full, `Error claiming <task ID>: issue already claimed by <value>`, and the `already claimed` called below is a substring of it. **Read that rc without a pipe**: `$?` after a pipe belongs to the last command, so a rejection reads as 0.
       - To look at the state again later, read **both together** with `ledger.sh show <task ID> --json | jq -r '.[0] | .status, .assignee'` (this query's pipe does not read an rc, so the prohibition above does not touch it). Held means `in_progress` + an `assignee` equal to that actor **on the `beads`·`notion` backends**; on `github` the `assignee` is the GitHub login of whoever ran the claim (an issue assignee has to be a real account — `ledger-github.sh` header), so there judge held by `status` plus the claim's own rc, never by comparing `assignee` with the actor value.
       - **Do not judge from `assignee` alone.** `ledger.sh update --assignee` puts a value in without a claim — `plan-sprint` section 3 assigns story owners that way, so issues whose `status` is `open` while an `assignee` exists are common in the ledger. Reading those as "held" is the misjudgment this passage blocks.
       - **Do not look at `owner`** — it is a git identity unrelated to claim (the measured value is an email), so it is the same value whoever holds it — judging from it is the misjudgment this passage exists to block (`harness-dfd.1.1`).
       - `assignee` is omitempty, so **when the value is empty** the key itself is absent and it comes back `null` — do not generalize that into "this backend has no such field".
     - When rejected with `already claimed`, another actor's session is working on it — skip it and go to the next ready task. **When every ready task is claimed by another actor, break the loop and go to human wait** — an orphan claim from a dead session is the suspicion, and reclaiming (`ledger.sh update <ID> --status open`, then claim again) is what a human confirms and directs.
     - Never set `--status in_progress` directly. **Two sessions do not hold the same (story, repo) at once** — split parallelism by story, or by repo within a multi-repo story (the ACTOR-note reuse convention is for "picking up", not for concurrent work).
     - **Do not delegate two tasks into one worktree at the same time.** The git staging area is a per-worktree shared resource, so even an `add` with explicit paths mixes with the other's `add` and `commit`. Split by story when parallelism is needed. The target is **two agents in one worktree** — one actor walking a list in sequence is not that target, and S22 counts it that way too.
1. **Implementation**: delegate to implementer. **Delegate thin** — the per-role discipline is held by the `${CLAUDE_PLUGIN_ROOT}/agents/` definitions, so the delegation message carries only ① first line: harness root absolute path + the absolute worktree path of the repo that task touches + the task ID (**in batch mode, the milestone's task ID list in dependency order** — the single-repo condition makes the worktree one) ② what "위임 메시지의 환경 스냅샷" below requires (the values to carry + the verbatim-quotation discipline) ③ task-specific context (background issue link, design hints).
2. `IMPLEMENTATION_COMPLETE` → secure the `VERIFY_PENDING` mark first. The mark is `ledger.sh note <task ID> "VERIFY_PENDING: <커밋 해시>"`, and the stop guard (`${CLAUDE_PLUGIN_ROOT}/hooks/stop-resume.sh`) and `checks/rules-check.sh` S22 use it to separate "finished, awaiting verification" from "left half-done" (what counts is the last **marker** line — a `DELEGATED:` or `VERIFY_PENDING:` line — so prose notes written after it leave the mark standing, and a re-delegation's new `DELEGATED:` supersedes it). It is a one-line fixed string with no backtick and no `$`, so it falls under the inline allowance of "원장에 본문을 넘기는 형태" (this skill). What follows splits by the unit of verification:
   - **Batch mode**: the implementer should have left the mark per task — check the last note of every task in the list with `ledger.sh show`, and fill a missing one in from the commit hash in the report. Once every task of the milestone is one of `VERIFY_PENDING`·`blocked`·`deferred`, run **the verify-code procedure** once over every task awaiting verification as a single list.
   - **Outside the condition**: the orchestrator leaves the mark and goes to **the verify-code procedure** for that one task.
3. `LGTM` → judge acceptance with **the verify-implement procedure** and close the tasks — in batch mode carry the same list and close the tasks that came back `MATCH` together.
4. **Handling of the remaining defined signals** — every signal needs an action, or each session improvises its own:
   - `IMPLEMENTATION_BLOCKED` → leave the reported root cause and attempt history as a `ledger.sh note`, then `ledger.sh update <task ID> --status blocked`. Move on to the next ready task (this does not stop the whole story). **`blocked` is not a human wait** — it is a state you walk past, not one you stop and wait in. **In batch mode**, only the report's "the stuck task's ID" goes `blocked`, "the list of tasks completed (committed) so far" gets its `VERIFY_PENDING` checked per step 2, and the remaining tasks (minus those depending on the blocked one) go through step 1 again as a new list.
   - `DECISION_NEEDED` (from any role) → leave the question as a `ledger.sh note` and go to **human wait** — when a loop is running, break it per the discipline of the long-running section.
   - A value not in the list → safe exit: record the situation and report to the human.
5. The orchestrator leaves each role's core result as a `ledger.sh note` — in batch mode, not on a task before it is closed but on the milestone bead (a task's last note has to be `VERIFY_PENDING`).

## 4. 스토리 마무리

1. **A multi-repo story runs one integration verification before it is closed.** The per-task gates ran only inside their own repo — a broken cross-repo contract (an API schema, say) still leaves every task closed as MATCH. In the worktrees of every repo involved, run each repo's `check` once more **at the same final commit state**, and leave the result (exit code per repo) on the story bead as a `ledger.sh note`. When a divergence shows, do not close the story; report to the human. A single-repo story has no such step.
2. Once every task is one of closed, blocked, or **deferred** (deferred is the third state the user explicitly closed — "결정 상태" (this skill). When the user says "안 한다", transition it with `ledger.sh update <ID> --status deferred`), leave a result summary (commit list, items not run) on the story bead as a `ledger.sh note` and close the milestones and the story. **With a `deferred` child, the `beads` backend counts it as an open child and refuses to close** — pass the parent with `ledger.sh close <ID> --force` and the dependency with `ledger.sh dep remove`, and leave the reason for the bypass in the close reason ("결정 상태" (this skill)). After closing, redraw the local projection with `scripts/board.sh all` (outside git — not a commit target).
3. **Close the cycle.** The procedure body, its scope, and its failure handling are single-owned by "사이클 종결 — PR 이 종점이다" (this skill) — **do not restate the steps here.** This channel has one constraint of its own: the commit carries **everything that branch did** (the opposite of the planning channel). The redraw in step 2 is itself stage 1 of that closing, so when no change is left, go straight to stage 2.
4. **Worktree cleanup happens after a merge is confirmed, and only on user instruction.** Judging whether it merged and directing the cleanup is the human's part, and **everything downstream of that is owned by `scripts/workspace-cleanup.sh <story ID>`** — do not run `git worktree remove` by hand (no gate — the script alone owns the removal order). What that script does is refresh remote refs · check for uncommitted and unpushed work · refuse unresolved preparation locks · remove the worktree and its Git-owned preparation state → delete the local story branch → remove any legacy bootstrap marker. It handles the selected repository; each repository session performs its own cleanup. stdout is a list of `<repo name>\t<absolute path of the removed worktree>` lines.

   - When uncommitted or unpushed changes remain, the script **leaves them alone and exits non-zero**, printing what remains. Report that output as is; whether to drop or keep it is the human's decision. Only when a squash merge deleted the remote branch and that reads as unpushed do you add `--force` on the human's instruction (uncommitted changes are not removed even by `--force`).
   - **The script does not check PR merge state** — a `gh` call is an external API call and thus subject to human approval, and when `gh` is missing or unauthenticated the check is skipped silently. When it is needed, the human checks directly with `gh pr view --json state,mergeCommit`.
   - **The clone itself is never deleted.** It gets reused by the next story.

## 위임 메시지의 환경 스냅샷

**What the delegating side already knows is not left for the receiving side to find out again.** The three delegation procedures (3-1 of this skill · `verify-code` 1 · `verify-implement` 1) carry the two below right after the paths on the first line.

| Item | Form |
|---|---|
| **The HEAD hash at that moment** | the value of `git rev-parse --short HEAD` |
| **Working tree state** | the result of `git status --porcelain`. **When it is empty, write "비어 있다"** |

- **A role that receives these two does not check them again.** When they did not arrive, or diverge from reality, check directly and write that fact into the report.
- **The ledger is not carried.** The role reads the ledger itself — the ledger is the single source of acceptance.
- **Paths are not exempt — all three roles confirm them themselves.** A worktree's parent is the main checkout, so one level off writes into another tree or judges another tree.
- **Point at the place instead of carrying the wording over.** Do not quote the content of documents in the tree (rules, role definitions, skills, ADRs) into a delegation message — name the place alone, as the `"<section title>"` of `<file path>`. A delegation message is the one artifact nobody verifies, so wording written from memory becomes the evidence as it stands. **The same holds for a command's form and what its options mean.** Do not put one in a delegation as an instruction unless you read it there and then — name the file and let the role read it. A form recalled wrong arrives wearing the same clothes as a verified one, and the receiving role has no way to tell them apart.
- **Carry only what cannot be read from the tree** — HEAD and working tree, task-specific context (background links, design hints), and claims in the previous stage's **report** that need fact-checking.
- **A delegation message does not exceed 25 lines.** Count the lines the delegator wrote — quotations from the previous stage's report do not count. **What the limit must not cut**: HEAD and working tree, claims in the previous stage's report that need fact-checking, batch mode's **task ID list** line (common to all three procedures — the condition is `develop` section 3), and what `verify-implement` 1 carries to evaluator: **the items already judged by command and their exit codes** · **the items with no command**. What to cut is what can be read from the tree.
- This list is single-owned here. The other two procedures only point at this section.

> Evidence: `harness-2a5.2.4` · `harness-dg0.6.42`.

## 장기 실행

When there are enough tasks that unattended repetition is needed, propose `/loop` (built into Claude Code) to the user with 3~4 as the prompt. **Never start a loop on your own initiative.** The loop prompt carries pointers only — the procedure body is held by this file.

How `/loop` relates to this pipeline. `/loop` is a wake-up that re-enters the session on an interval; the cycle's state is not in the session but in the ledger (the claim · the `VERIFY_PENDING` mark · the `RETRY:` notes), so a wake-up that arrives after a turn ended picks the cycle up where the ledger says it is. **A wake-up does not stand in for the completion notification of a background delegation** — that notification arrives on its own while the delegation runs, and the two do not collide. The wake-up is the safety net for the other state: nothing is running and the turn has ended with work still open, so the session is reopened to continue.

Loop-exit discipline. The stop guard (`${CLAUDE_PLUGIN_ROOT}/hooks/stop-resume.sh`) is an always-on hook rather than a loop, so it is not the target of the rules below; where its marker enters, it is named.

- **`/loop` takes `[interval] [prompt]` and nothing else.** There is no completion sentence and no iteration ceiling to pass — an option appended to it is not parsed and rides along as part of the prompt string. What produces the exit is the model's per-turn rearm decision, not any string in the prompt. **So do not write options onto a `/loop` and read that as a ceiling being in place** — passing then becomes a false signal of rule compliance.
- **Stopping from inside**: when a signal leading to human wait appears, break the loop and leave the reason for waiting as a `ledger.sh note`. **The list of those signals is single-owned by the "사람 대기" section below — it is not restated here.** Breaking the loop means ending that turn without rearming — rearming is a per-turn choice, not a default.
- **Stopping from outside**: use the explicit runtime/repository/session cancellation command in `${CLAUDE_PLUGIN_ROOT}/docs/state.md`. A shared legacy marker cannot identify which session to stop.
- **The re-review ceiling is counted with `ledger.sh note` rather than memory.** A loop replaces sessions, so the orchestrator's memory disappears every iteration — without the counter left in a note, **limit exceeded never arrives.** The format and the ceiling value are single-owned by the "재시도 카운터" of the `verify-code` skill — **no number is written here.**


# Always-on rules owned here

This skill owns the sections below; the other skills, the role definitions, and the session context block point at them by section title and do not restate them.

## 운영 규율

- **Acceptance must be machine-judgeable.** ① what exists ② what output follows what input ③ which test passes — one of the three forms. "Works well" is forbidden.
- A task without acceptance is not started even when it shows in `ledger.sh ready`. Fill the acceptance first.
- Completion flow: implementer (implementation) → reviewer (quality) → evaluator (acceptance comparison) → `ledger.sh close`. **The unit of verify is the milestone by default** — when the batch condition holds, implement every task of the milestone, then run reviewer and evaluator once each and close together. The condition, and what happens outside it (per-task verify), is section 3 of this skill (`harness-2a5.4`). Whoever built it does not grade it.
- **No task is closed without the evaluator's MATCH record.** Leave the grounds (commit, gate exit code) in `ledger.sh close --reason`.
- **Apply `${CLAUDE_PLUGIN_ROOT}/docs/roles.md` before every delegation and result judgment.** It owns runtime registration, native identity and result validation. Unavailable delegation is UNREACHED: record the missing capability and enter human wait with the task open.
- **There are three projection trees and all three are outside git.** An epic goes to `docs/sprints/<ID>/` when it has a `sprint:` label, and to `docs/backlog/<slug>/` when it has none and is not `closed` — the label splits the output path only, never whether it is rendered. `decision` beads go **in full** to `docs/adr/<slug>.md` (no narrowing by status — a superseded decision stays, with its lineage). The one thing that redraws them is `scripts/board.sh all`, and **no git hook calls it** — this step or a person does. **On a backend with its own UI it draws nothing at all** (rc 0 and one line saying so), because the ledger's own screen is already what people read. When a backlog story closes, its directory disappearing is the correct result.
- **`docs/sprints/`·`docs/backlog/`·`docs/adr/` are never edited by hand.** The next render overwrites them — what gets fixed is the ledger.
- **A gate's verdict is its exit code.** A role verdict requires a REACHED result from the role contract before its first-line SIGNAL is handled. Keep the validated response bound to its call and child instance; a follow-up or earlier attempt cannot supply a missing result.
- **A count in a commit message or a code comment is measured when it is written, not carried over.** The discipline is single-owned by `harness:plan-story` section 5; this line only binds it to the commit path, which never loads that skill. Two shapes recur — a number measured before the change and quoted after it, and a total standing beside sub-counts that do not sum to it. **Add the sub-counts up before committing**: a line whose own arithmetic fails is a defect every reader sees and no gate does.
- **Correction preservation**: when reversing a judgment in the ledger, do not delete the earlier decision. Quote the original with `ledger.sh note <id>` and leave what was wrong and why.
- When a story is stuck, record the story alone and move on to the next. Do not halt the whole sprint.
- **Gates are written in exemption-list form (inverted polarity).** Do not hand-pick what gets checked — derive it from the whole set, and register only what cannot be checked in an exemption list, with a reason. A new item's default is "checked", and a reverse assertion confirms that the exemption key exists in the real set — **but that assertion holds only where the exemption key is a static artifact (a file path, a check name).** When the key is a value of runtime data (a ledger status, a label), a count of 0 is legitimate — the data legitimately holds none — so it is not asserted; an exemption matching 0 exempts nothing and leaves the check on the stronger side (`plugins/harness/checks/board-check.sh` `TERMINAL_STATUS`). An allowlist check stays silent on a violation not in the list, and that silence reads as a pass.

## 원장에 본문을 넘기는 형태

**A body handed to the ledger (`ledger.sh`) — note·description·acceptance·close reason — never sits inside a shell command string.** The shell interprets the body before ledger.sh does and erases identifiers wrapped in backticks or `$` into empty strings, while ledger.sh exits 0.

- **When a file option exists, use it** — `note --file`·`--stdin`, `create`/`update --body-file` (`create` also takes `--stdin`), `close --reason-file`, `dep add --file -`. That is the whole set of file options the adapter takes on every backend (`ledger.sh --help` · the argument contract of `harness-m8gg.4.1` acceptance 6 — there is no `--design-file`). Values without one (`--acceptance`·`--title`) are passed as `"$(cat <path>)"` — the substitution's output is not rescanned.
- **A one-line fixed string with no backtick and no `$` may go inline** — `RETRY: <단계> <n>/<상한>`·`ACTOR: <레포> <값>`.
- **Make the body file in a call other than the ledger.sh call.** The file-writing tool (Write·Edit) is simplest — the body leaves the command string, so every rule that looks at command strings loses its material. Made with a heredoc in the same call, the body is inside the command string again.
- **No heredoc as a ledger.sh argument.** Nothing gets damaged, but the whole body is scanned as a command string, other rules fire on the body's words, and passing them means distorting what gets recorded.
- **Getting past a block by editing the body is forbidden at every stage.** What may change is the form (splitting the call) and the tool (file writing). When both are spent and it is still blocked, do not edit the body — **write into the report that it was blocked.**
- Gate: **none — discipline only.** The guard keeps only invariants independent of any tree anchor, and this discipline is outside them. `$VAR` is the same — `$` outside bodies is so common that putting it in the verdict would let false positives drown the discipline.

> Evidence: `harness-xwd` · `harness-dg0.6.36` · `harness-dg0.6.19` · `harness-dg0.6.14`.

## 상태 주장의 근거

**"The gate passed" and "the work is done" are different.** When reporting a state you brought about, confirm **what actually decides that state** in the same turn, and leave the evidence with it.

| Claim | Not evidence | What to actually confirm |
|---|---|---|
| Gate passed | the rc of a partial run (a single test · some modules) | the rc of running that whole scope |
| Documents current | `board.sh`'s rc | the paths on stdout exist and the status symbol in their `index.md` equals the status of `ledger.sh show` |
| Worktree created | workspace command or native EnterWorktree result | common `inspect` confirms Git registration and linked identity, the branch is `worktree-<the worktree name>` (`lib/worktree-name.sh <story ID>` prints that name — section 2; it is not the ID itself), and inside it `${CLAUDE_PLUGIN_ROOT}/lib/harness-root.sh` prints the harness root |
| Pushed | the push command's rc | the tip of `git ls-remote` is my commit SHA |
| Merged | the PR state being `MERGED` · the remote tip compared at push time (a squash merge makes **a new commit object**, so both can diverge from the original commit) | the merge commit's `--stat` equals that of the whole branch diff (`git diff --stat <default branch>...<branch>`). For a commit with deletions or renames, confirm the path's absence in the remote tree with `git ls-tree --name-only origin/<default branch> <path>` |
| Task closed | having called `ledger.sh close` | the status·close_reason of `ledger.sh show` |
| PR opened | the rc of `gh pr create` | the url and state of `gh pr view --json url,state` |
| Saved to a file | having printed the content in the response body | that turn's write result, or re-checking the path |
| Work continues | knowing what to do next | whether a running piece of work actually exists (a background task · a loop · a schedule) |

When it cannot be confirmed, do not write optimistically — **write that it was not confirmed.**

**When nothing is running and the actor is you, do not end the turn.** Ending the turn is itself waiting for the user. If you would announce, do not — just do it. When there is a reason to stop (approval needed · a judgment requested), write that reason and stop.

**Whether a gate's rc can be taken from a record depends on what decides that gate.**

| Class | Example | Rerun |
|---|---|---|
| **Decided in the tree** | the repo's own `.harness.json` `check` | **No.** The rc is bound to the commit. Use the command and rc the worker left in the commit message, but confirm **that the record belongs to the target commit itself** — when its wording is letter for letter the same as the parent commit's (`<commit>^`) gate record, do not take it; run it directly |
| **Compared against the world outside the tree** | `board-check` (the ledger) | **Run it where it is used.** With the tree unchanged, another session changing the ledger flips it. No record — commit message, hook pass, or the previous stage's report — stands in for it |

This distinction is single-owned here. Role definitions and skills write only *who runs it when* and point at this section.

**When running a gate is itself a side effect, make the side effect opt-in.** `checks/ledger-check.sh` is that spot — remote reflection happens only when `LEDGER_CHECK_PUSH=1` turns it on, and **the one place that turns it on is the `pre-push` hook block**. Called for a verdict, a comparison, or a document check, it reflects nothing, so there is no discipline to memorize before calling this check.

- **Ahead-but-not-reflected is told apart by the pass phrase** — `원격 반영 앞서 있음(반영하지 않음 — 쓰기 모드 아님)`. It differs letter by letter from `확인됨` (it was never ahead). Do not read rc 0 alone as "the ledger equals the remote".
- **When another check that changes state in exchange for an rc appears, write it here.** Such a check defaults to the safe side and puts the side effect behind a switch — the same demand as "gates are written in exemption-list form" above. Evidence: `harness-x0i.2`.

**Write the measurement environment with it.** When using a measurement as evidence, write the shell and version, environment variables (`BEADS_DIR` and the like), CWD, and tool versions with it. When using a count, write the scope, population, aggregation filter, and input too. Do not use a child session's or agent's response summary as a measurement transcript — the raw tool result is the evidence.

**"Why" demands evidence too.** When giving a reason, write whether it was confirmed; when not, write it as a "hypothesis". Name evidence artifacts (screenshots · logs · hashes) with the file name and how they were made. Passing a tool means passing only what that tool sees.

> Evidence: `harness-fnv` · `harness-dg0.6.7` · `harness-1e7` · `harness-8xe`.

## 결정 상태 — 안 하기로 한 것은 남은 일이 아니다

An item the user explicitly closed with "안 한다 / 지금 말자" is **a third state, neither done nor undone**. In beads it is `deferred` — `ledger.sh update <ID> --status deferred`. In closing conditions it ranks with closed·blocked.

- **Exclude** it from remaining work, completion criteria, and report lists. It does not block a completion verdict.
- When circumstances change and it looks needed again, **ask in one line.** Do not persuade.
- Keep what was passed over in silence apart from what was closed explicitly. When unclear, ask once.
- **The beads backend counts `deferred` as an open child or blocker.** Closing needs a bypass: `ledger.sh close <ID> --force` for the parent, `ledger.sh dep remove` for the dependency. Leave the reason for the bypass in the close reason or a note.

## 진단 가설 규율

Applies when diagnosing a cause and proposing an action. Not to plain observations.

- **Before verification, write "hypothesis".** Not "the cause is X" but "hypothesis: X — verifiable by <this>".
- **Confirm equivalence before using a control.** Confirm that the conditions (settings · cache · path · version) are the same, or state that they were not confirmed.
- **Two diagnostic attempts at most.** Beyond that, summarize the confirmed facts and the remaining uncertainty and hand them to a human. Counted separately from the retry counter (the rework ceiling).

## 사람 대기 — 어떤 신호가 사람에게 가는가

**The list of signals that lead to human wait is single-owned here.** The "unresolved decision" of the session context block "절대 금지" and the long-running section of `develop` only point at this section (`harness-dg0.6.39`). The signal handling of `verify-code`·`verify-implement` distributes their own roles' SIGNAL values and does not define this list.

| Signal | Raised by | What the human decides |
|---|---|---|
| `DECISION_NEEDED` | any role | the answer to the question asked |
| `DEVIATION` | evaluator | what to fix when the plan diverges from reality |
| `SCOPE_EXCESS` | evaluator | whether to split the excess off or accept it |
| retry counter **limit exceeded** | verify-code · verify-implement | whether to keep going on the same finding |
| a SIGNAL value **not in the list** | any role | disposition after the safe exit |
| **UNREACHED**, including missing first-line SIGNAL, unidentified role or interrupted delegation | role contract | how to restore a verifiable native delegation before retrying |
| every ready task under another **actor claim** | develop pickup | whether to reclaim the orphan claims |
| **cycle close incomplete** | the failure table of "사이클 종결" | whether to retry or finish by hand |

- **Handling is the same for every signal**: leave the reason for waiting with `ledger.sh note` and stop. In a loop, break the loop — the means is `develop` "장기 실행".
- **None of these signals shows in a ledger query.** All of them stay only in `ledger.sh note` bodies, with no status transition.
- **`SCOPE_EXCESS` is not counted by the counter, but it is a human wait.** The counter decides how many more reworks to order; this list decides who chooses the next action.
- **`blocked` is not a human wait.** On `IMPLEMENTATION_BLOCKED`, `develop` moves the task to `blocked` and walks past it to the next ready task. "절대 금지" counts `blocked` as an "unresolved decision" because it is a criterion for whether remote reflection is automatic.

## 대상 레포의 관례 — 어디에 적혀 있는가

**The list of places where a target repo's rules are written is single-owned here.** Roles run as subagents in the story worktree, each with its own context — **do not count on the target repo's `CLAUDE.md`, rules, or skills being loaded for them.** The only way is to read them directly where they are needed.

**Four places**, relative to that repo's worktree:

| Place | What is there |
|---|---|
| root `CLAUDE.md` | rules that apply to the whole repo |
| `CLAUDE.md` inside the `.claude` directory | the same — which of the two a repo uses varies |
| **every** `.md` under the `.claude/rules` directory (recursively, subdirectories included) | rules by topic — code style · PR procedure · domain conventions |
| **every** `SKILL.md` under the `.claude/skills` directory | that repo's procedures. A convention that applies to design or implementation may be written here rather than in a rule |

- **Do not name file names** — they differ per repo. Fix the places only; learn the names by reading.
- **Rules written anywhere else are treated as absent.** An open list never finishes the search.
- **Do not substitute recall.** Even when the same repo was read in an earlier session, read it again.
- **When none of the places exists, there is no convention.** Silence is not a prohibition.
- **Read per repo.** When a story involves several repos, each one.
- **No gate — persuasion only.** Neither whether it was read nor whether it was followed can be seen by a machine.

**Who reads it when is not decided here.** The owners hold it — `plan-story` (before breakdown) · `implementer`·`reviewer` (before work and review) · "사이클 종결" below (before push, limited to the sentences that deal with push·PR).

## 사이클 종결 — PR 이 종점이다

**The end point of a cycle is PR creation.** Up to there, proceed on your own **when no decision is left unresolved in that cycle** — when one is, and there is no user instruction or approval, do stage 1 only and stop (exception two of the session context block "절대 금지"). The list of irreversible things is **single-owned by the first item of the session context block "절대 금지"** — all of it is subject to explicit instruction. Evidence: `harness-dmy`.

**Three stages, and the order is the discipline.** No harness git hook is planted anywhere (story `harness-lzs3` decision; the harness root is not a git repo either), so neither commit nor push runs the ledger checks for you — **the orchestrator runs the ledger check and the ledger reflection as explicit stages.**

1. **Commit, then the ledger check.** Commit that branch's work — the commit gate is the target repo's. Projections are not commit targets: align the local ones with `scripts/board.sh all` only. After the commit the orchestrator runs two checks in the worktree: `bash "${CLAUDE_PLUGIN_ROOT}/checks/board-check.sh"` (ledger structure) and `bash "${CLAUDE_PLUGIN_ROOT}/checks/ledger-check.sh"` (ledger reflection — **read mode**; do not turn on `LEDGER_CHECK_PUSH`. A pass phrase of `앞서 있음(반영하지 않음 — 쓰기 모드 아님)` means stage 2 has something to raise; `확인됨` means nothing; on `github`·`notion` it is `원격 반영 대상 없음` and stage 2's ledger half is empty from the start). Either one rc≠0 is close incomplete (the failure table).
2. **Remote reflection — the working-branch push, then the ledger's. What the second one is, the backend decides.** Only after stage 1's `board-check`·`ledger-check` passed. Push the working branch first (`git push -u origin worktree-<the worktree name>` — section 2, not the raw story ID; the evidence is the tip of `git ls-remote`). Then the ledger, read off `ledger.backend` in the repo's `.harness.json` — the adapter owns the shape, this section only says when:
   - **`beads`** — run `HARNESS_ROOT=<harness root> bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh sync-check --push` explicitly. This is exactly the scope that exception one of the session context block "절대 금지" approves: the moment the target-repo push is the instruction, the ledger goes up inside that approval. With no pre-push hook anywhere, leaving this command out leaves the ledger as the sole local copy. After reflecting, run `ledger-check` once more in read mode and see `확인됨`.
   - **`github`·`notion`** — **nothing to reflect, and that is not a step being skipped.** The ledger is the remote itself: the issue or the page was already written the moment the note was left, so no local copy exists that could lag behind. `ledger-check` says so in stage 1 (`원격 반영 대상 없음`), and stage 2 is the working-branch push alone.

   **When either fails, do not go to 3.**
3. **PR creation and state check.** After `gh pr create`, confirm the state with `gh pr view --json url,state` and leave the url on the story bead with `ledger.sh note`.

**When a target repo has its own push·PR rules, they come before this section's automatic progression.** So **after finishing 1 and before going to 2, read that repo worktree's conventions directly** — the list of places is single-owned by "대상 레포의 관례" above, and what this section looks for is only **the sentences that deal with push·PR**.

- When what was read makes push or PR something to ask a human about, **do 1 only and stop** — the `1→2 gate` row of the failure table below.
- **When none of the places exists**, or they were read and hold no sentence about push·PR, **proceed with the automatic close as it stands.** Silence is not a prohibition — this is the default.
- **Judge per repo.** One repo asking does not stop another repo's close (the same unit as "a multi-repo story is one PR per repo" below).
- **No gate — persuasion only.** The judgment is natural-language reading, so no machine sees it, and the orchestrator session is not reached by `guard.sh`'s subagent rules either. Evidence: `harness-wym.1`.

| Channel | What the commit carries |
|---|---|
| **Planning** (`plan-sprint` 6 · `plan-story` 7) | **nothing.** The body of a plan is the ledger, the registries are behind the adapter, and the harness root's own files are machine-local — so there is no file to commit anywhere. This channel's remote reflection is the ledger's alone (`beads`: `ledger.sh sync-check --push` · `github`·`notion`: nothing — the ledger is already remote); it is not tied to `git push`, so it is outside exception one and subject to explicit instruction |
| **Development** (`develop` 4) | everything that branch did |

**The scope is every repo carrying a committed `.harness.json` — that file is the approval surface.** Out of scope: when the worktree's `origin` is not the repo you were asked to work in, stop and report · everything subject to explicit instruction (the place the paragraph above points at). **Subagents are out of scope — up to the local commit**; the close is the orchestrator's.

**The PR body is minimal.** The title is the story title, the body is the story id and the list of closed tasks. Do not imitate the target repo's PR rules.

**Failure is judged by state, not by rc.**

| Stage | Failure | Verdict | Action |
|---|---|---|---|
| 1 commit | commit gate rc≠0 | close **incomplete** | `ledger.sh note` the gate output in full. In a loop, break it and wait for the human |
| 1 ledger check | `board-check`·`ledger-check` (read mode) rc≠0 | close **incomplete** | `ledger.sh note` the check output in full on the story bead. Do not go to 2 — raising a ledger that has diverged from the remote (a forked lineage · never reflected) fails the automatic reflection too |
| 1→2 gate | the target repo's rules make push·PR something to ask a human about | close **incomplete** | `ledger.sh note` on the story bead which repo's which file says so. Do not go to 2 |
| 2 working-branch push | rc≠0 (no auth · no remote · the target repo's hook) | close **incomplete** | note the command, rc, and the gist of stderr. Go neither to the ledger reflection nor to 3 — on `beads` the ledger is still local |
| 2 ledger reflection | the reflection rc≠0, or rc=0 while `ledger-check` is not `확인됨`. **`beads` only** — on `github`·`notion` there is nothing to reflect, so this row cannot occur | close **incomplete**. **The working branch is already out** | `ledger.sh note` the command, rc, and the gist of stderr on the story bead. Do not go to 3 — a PR opened now is a PR without its ledger, and if this machine dies the judgment evidence goes with it. Wait for the human |
| 3 PR | `create` rc≠0 **but** `view` prints a url | **complete** | leave the url in a note |
| 3 PR | `create` rc≠0 **and** `view` prints no url | close **incomplete** | note the command, rc, and the gist of stderr. Wait for the human |

- **Do not reopen closed tasks.** The PR is the output of the story close. Instead, **do not close the story** — the incomplete close stays as story state and the next session picks it up.
- **A multi-repo story is one PR per repo.** When some repos fail, write only those as incomplete.
- **Invent no new signal.** An incomplete close is treated as a human-wait signal of `develop` "장기 실행" and breaks the loop.
- **This section is the single owner of the close procedure.** The three skills and `${CLAUDE_PLUGIN_ROOT}/docs/operations.md` put only channel-specific constraints and point here.

## 멀티 레포

- **There is no repo registry.** A story's `repo:<name>` labels name the repos; each of them carries its own `.harness.json` with the same `ledger` object, and **that file also owns the gate command, the default branch and the bootstrap** — language and build-tool knowledge lives nowhere else. The harness does not know where those clones are, so **a person opens the session in the one they work on.**
- At story pickup, each repository session creates or resumes its workspace through section 2. Retain the returned Git-registered path and branch. The session unit is (story, repo), so each repository runs that same procedure independently.
- **The worktree is outside the harness.** State the harness root absolute path in the delegation message — it is the only source of `HARNESS_ROOT=<harness root>`.
- An agent inside a worktree confirms the current path as the first action of every turn. When asked to write while on a main-checkout path, it stops and checks with a human.
