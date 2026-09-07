# Usecase catalog — the four value axes

> The harness's four value axes pinned as **the order a person actually walks**. Each usecase has an actor, steps, and pass criteria.
>
> Structure: [architecture.md](architecture.md). Procedure text: [operations.md](operations.md). Limits of the enforcement: [guardrails.md](guardrails.md). **Only scenarios and criteria are written here** — overlapping description is left to those documents.

## How to use this document

- **UC numbers are fixed identifiers.** They are row keys elsewhere (the defect matrix `harness-dg0.2.1`). Never reuse or shift a number — a retired usecase keeps its number with the reason.
- **Pass criteria take two forms only**: ① `command` → expected exit code ② existence of a file or state (a path, a ledger field value, a git ref). "Works well" is not a criterion.
- **Criteria are hypotheses; measurements live in the ledger.** The walk-throughs that produced these criteria are the notes of `harness-dg0.1.2` and later story beads — quote from there, do not copy them here.
- **Every ledger call below is the adapter.** `ledger.sh …` is short for `bash <plugin>/scripts/ledger.sh …`; subcommands, arguments, and JSON keys are `bd`'s. Which backend answers is `ledger.backend` in the repo's `.harness.json` — the criteria below hold on all three unless a step names one.
- Judgment commands run **from the place the actor's session opened** unless stated: the target repo's main checkout for planning and retrospective, that checkout or its worktree for development. Both carry `.harness.json`, so the harness root is found by walking up; where the cwd cannot be counted on (a subagent, a fixture), prefix the call with `HARNESS_ROOT=<harness root>`.
- Placeholders: `<story ID>` · `<task ID>` · `<sprint ID>` (`YYYY-SNN`) · `<repo>` · `<clone>` (= that repo's clone, wherever it lives) · `<worktree name>` (= what `<plugin>/lib/worktree-name.sh <story ID>` prints — **not the story ID**, which a `github` ID's `#` makes unusable as a name) · `<worktree>` (= `<clone>/.claude/worktrees/<worktree name>`) · `<harness root>` · `<plugin>` (= the installed plugin, which skill and agent bodies reach as CLAUDE_PLUGIN_ROOT).

## Index

| Axis | UC | Title |
|---|---|---|
| A. multi-repo | UC-1 | register a new target repo and reach the first worktree |
| | UC-2 | one story touches two repos — one session per repo, integration verification |
| B. multi-worktree · session | UC-3 | two sessions work different stories at the same time |
| | UC-4 | a new session picks up an interrupted cycle |
| | UC-5 | an unattended loop processes tasks in sequence and stops on a signal |
| | UC-6 | clean up the worktree after confirming the merge |
| C. shared ledger | UC-7 | a planning change lands in the ledger and nowhere else |
| | UC-8 | a task close rides out on the development branch |
| | UC-9 | a new machine stands the harness up and restores the target repos |
| D. self-improvement | UC-10 | close a story or sprint and fold the retrospective into the rules |
| | UC-11 | promote a persuasion-only rule to a gate |

**Not covered here**: plugin distribution itself (the marketplace) — it is not one of the four axes and has no open defect. Secret-file handling (deny 10) is outside the axes too. Add as UC-12 onward when needed.

---

## Axis A — multi-repo

### UC-1. Register a new target repo and reach the first worktree

**Actor**: a person (a session opened in the new clone)

**Steps**

1. `git clone <url>` — anywhere. In a worktree of it, write `.harness.json` with the gate command, the default branch and the **same `ledger` object the harness's other repos carry** (`harness:setup` section 5), and commit it. That file is the registration: there is no registry, and its presence is what makes the clone a harness root.
2. `bash <plugin>/lib/harness-root.sh` from inside the clone prints the clone's path, and `ledger.sh list -n 1` from there is rc 0.
3. `harness:plan-story` creates the story epic: `ledger.sh create "<title>" -t epic -l sprint:<sprint ID>,rail:r1,slug:r1-<slug>,repo:<repo>`.
4. Open a session in `<clone>` and run `harness:develop` — section 2 calls `EnterWorktree` with `name=<worktree name>`; the plugin's PostToolUse hook wires the ledger and runs the repo's `bootstrap` if the repo has no EnterWorktree hook of its own.
5. `harness:develop` 3-1 delegates to `harness:implementer` with the worktree path and the harness root absolute path.

**Pass criteria**

- `jq -e .ledger.backend <clone>/.harness.json` → rc 0, and its value is the same as the harness's other repos carry
- `bash <plugin>/lib/harness-root.sh` run from `<clone>` prints `<clone>`
- `git -C <worktree> rev-parse --abbrev-ref HEAD` prints `worktree-<worktree name>`
- `grep -qx '.claude/worktrees/' <clone>/.git/info/exclude && grep -qx '.beads' <clone>/.git/info/exclude` → rc 0, and the target repo's `.gitignore` is unchanged: `git -C <clone> status --porcelain .gitignore` prints 0 lines
- on the `beads` backend, `cat <worktree>/.beads/redirect` prints the ledger home's `.beads` and `ledger.sh where` inside the worktree prints that ledger; on `github`·`notion` there is nothing to wire, and the criterion is instead that `ledger.sh list -n 1` from inside the worktree is rc 0
- `bash <plugin>/checks/workspace-check.sh` → rc 0
- inside the worktree, the repo's `check` command from its own `.harness.json` → rc 0 (bootstrap finished)

### UC-2. One story touches two repos — one session per repo, integration verification

**Actor**: two orchestrator sessions (one per repo, each in its own clone) + implementer subagents

**Steps**

1. The story epic carries `repo:<A>,repo:<B>` together.
2. Right after task creation, remove from each task the repo label it does not touch: `ledger.sh label remove <task ID> repo:<B>` (`harness:plan-story` section 2).
3. `ledger.sh children <story ID>` — no task with two or more `repo:` labels.
4. Open one session in `<clone A>` and one in `<clone B>`; each runs `harness:develop`, claims its own tasks, and leaves `ACTOR: <repo> <value>` on the story bead. Each `EnterWorktree` makes that repo's worktree.
5. Each session delegates its tasks to its own worktree and runs that repo's `check`.
6. Before the story closes, integration verification: **at the same final commit state**, run `check` again in every related repo and leave the per-repo exit codes with `ledger.sh note <story ID>` (`harness:develop` 4-1).

**Pass criteria**

- `bash <plugin>/checks/rules-check.sh` → rc 0 (R5: exactly one `repo:` label per task; S22: no more actors than worktrees per (story, repo))
- `ledger.sh show <story ID>` notes carry one `ACTOR: <repo> <value>` line per repo
- both worktrees: `git -C <worktree> rev-parse --abbrev-ref HEAD` == `worktree-<worktree name>`
- every repo's `check` in step 6 → rc 0
- `ledger.sh show <story ID>` notes carry one line per repo with that repo's exit code
- the cycle close is per repo: one PR per repo, and a repo whose own rules ask a person before push stops at step 1 of "사이클 종결" without blocking the other

---

## Axis B — multi-worktree, sessions

### UC-3. Two sessions work different stories at the same time

**Actor**: two people (or two sessions), each opened in the clone of the repo its story touches. Two sessions on the same (story, repo) are forbidden.

**Steps**

1. Each session takes a different ready story `<S1>`·`<S2>` (`ledger.sh ready`).
2. Each reads the last `ACTOR: <repo> …` line of its story's notes, or makes one: `ledger.sh note <story ID> "ACTOR: <repo> sess-<6 chars>"`.
3. Each claims its tasks: `ledger.sh update <task ID> --claim --actor sess-<6 chars>`.
4. Each enters its worktree with `EnterWorktree`.
5. Each implements and commits. After a task closes, `bash <plugin>/scripts/board.sh all` at the harness root redraws the local projections — never committed.

**Pass criteria**

- both worktrees exist and differ: `[ -d <clone>/.claude/worktrees/<S1's worktree name> ] && [ -d <clone>/.claude/worktrees/<S2's worktree name> ]` → rc 0 (or two clones, if the stories touch different repos)
- session 2 claiming session 1's task under another actor is refused: `ledger.sh update <S1's task ID> --claim --actor sess-<session 2>` → non-zero, output contains `already claimed`
- `ledger.sh show <task ID>` assignee equals that session's actor value
- **both** sides: `bash <plugin>/checks/board-check.sh` → rc 0 from their worktrees (the ledger change of one does not break the other's check)
- `git -C <worktree> log --oneline -1` of each points at a commit on a different `worktree-<worktree name>` branch
- the stop guard scopes to each session's own actor: a session that closed its own work stops without pushback while the other's tasks are still `in_progress`

### UC-4. A new session picks up an interrupted cycle

**Actor**: a new session (after the previous one vanished by compaction or exit)

**Steps**

1. Open a session in the same clone (the plugin's SessionStart block loads; the target repo's own rules load too).
2. `ledger.sh -C <harness root> list --status in_progress --all` finds the in-progress tasks.
3. `ledger.sh show <story ID>` — read the last `ACTOR: <repo> …` line for this repo.
4. **With that value as is**, `ledger.sh update <task ID> --claim --actor <read value>` — the same actor passes idempotently.
5. `EnterWorktree` with `name=<worktree name>` — enters the existing worktree, does not create a second one; the hook is idempotent.
6. `git -C <worktree> log --oneline -5` and the last `RETRY:` line of `ledger.sh show <task ID>` restore the stop point and the remaining retries.

**Pass criteria**

- 4 → rc 0 (re-claiming under the same actor is not refused)
- 5 → the session's cwd is the same path as before, string-equal
- `ls -a <clone>/.claude/worktrees/` lists `<worktree name>` exactly once (no duplicate creation)
- the last `RETRY:` line of `ledger.sh show <task ID>` notes is the same before and after the session change (the counter does not reset)
- the picked-up session's first report names who acts next; in a human-wait state the reason exists in `ledger.sh show <task ID>` notes

### UC-5. An unattended loop processes tasks in sequence and stops on a signal

**Actor**: a person starts it; unattended afterwards

**Steps**

1. Drain permission prompts before the loop ([operations.md](operations.md) "Unattended loop").
2. Start `/loop [interval]` with `harness:develop` sections 3–4 as the prompt. It takes nothing else — no completion sentence and no iteration ceiling; the exit is the model's per-turn rearm decision (`harness:develop` "장기 실행").
3. Per task the loop runs implementer → verify-code → verify-implement → `ledger.sh close` (or per milestone in batch mode).
4. Stop: from inside, end the turn without rearming; from outside, `touch "${HARNESS_DATA_DIR:-~/.claude/plugins/data/harness}/stop-resume-cancel"` — the stop guard's marker. The loop itself has no marker; what keeps a session from ending after the loop is broken is the guard, so that is the one to switch off.

**Pass criteria**

- after one iteration the task has transitioned: `ledger.sh show <task ID>` status == `closed` with a non-empty `close_reason`
- at the end of an iteration **the product of the declared next action exists**: the closed-task count grew, or a human-wait reason note appeared — neither is failure
- on a human-wait signal (the list is `harness:develop` "사람 대기"), the reason exists in `ledger.sh show <task ID>` notes and the loop has stopped
- after the stop the guard is not pushing back: the session's last path in the log is not `BLOCK`:

  ```
  awk -F'\t' -v s=<session ID> '$2==s{last=$3} END{if(last=="")exit 2; exit (last=="BLOCK")}' "${HARNESS_DATA_DIR:-$HOME/.claude/plugins/data/harness}/stop-resume.log"
  ```

  rc 0 = a pass path (`CANCEL`·`IDLE`·`RECURSE`·`GAVE_UP`·`ORACLE_FAIL`·`VERIFY_PENDING`·`NO_CLAIM`) · rc 1 = `BLOCK`, still pushing back · **rc 2 = no line for that session** — the guard never fired, and a zero-item pass is read as failure

### UC-6. Clean up the worktree after confirming the merge

**Actor**: a person (the merge judgment and the cleanup instruction are a person's)

**Steps**

1. Confirm the PR state: `gh pr view <number> --json state,mergeCommit`.
2. **Before** cleanup, look for a merge omission: `git -C <clone> fetch --prune` then `git -C <clone> diff --stat origin/<default branch> worktree-<worktree name>` (run from inside the worktree without the clone path in the command string — `r_main_shell`).
3. `bash <plugin>/scripts/workspace-cleanup.sh <story ID>` — fetch --prune → uncommitted/unpushed check → remove the worktree → delete the local `worktree-<worktree name>` branch → delete the bootstrap marker. No hand-typed removal commands (no gate — the script alone owns the order).
4. Read the stdout `<repo>\t<removed path>` lines.

**Pass criteria**

- step 2 prints 0 lines (the merge commit carried every change of the story branch — the squash merge did not swallow a rename's deletion half)
- 3 → rc 0
- `[ ! -d <worktree> ]` → rc 0
- `ls -a <clone>/.claude/worktrees/` does not list `<worktree name>`
- `git -C <clone> branch --list 'worktree-<worktree name>'` prints 0 lines
- the reverse path: with uncommitted changes in the worktree, 3 → non-zero and `[ -d <worktree> ]` → rc 0 (not removed, `--force` included)

---

## Axis C — shared ledger

### UC-7. A planning change lands in the ledger and nowhere else

**Actor**: a person + an orchestrator session at the harness root. **The ledger is global, the registries are behind the adapter, and the projections are outside git** — so planning produces **no diff in any repo** ([operations.md](operations.md) "Documents go nowhere — projections are outside git").

**Steps**

1. `harness:plan-sprint` / `harness:plan-story` build the ledger tree.
2. `ledger.sh list -l sprint:<sprint ID> --all` — no task without acceptance.
3. `bash <plugin>/scripts/board.sh all` redraws the local projections (outside git) — a no-op on a backend that has its own UI.
4. **Nothing to commit.** No file in any repo changed, so this channel has no branch, no push, and no PR.
5. Reflect the ledger — `beads` only, and only on explicit user instruction: `ledger.sh sync-check --push` (that is `bd dolt push`). On `github`·`notion` the writes were already remote and there is nothing to send.

**Pass criteria**

- `bash <plugin>/checks/board-check.sh` → rc 0
- no repo gained a diff from the planning: in every registered clone, `git status --porcelain` prints 0 lines
- judge `bash <plugin>/checks/ledger-check.sh` by its **pass phrase**, not its rc: `… | grep -q '원격 반영 확인됨'` → rc 0 (check the script's own rc with `$pipestatus[1]` in zsh). `확인됨` and `이번에 수행함` judged "not ahead"; `건너뜀` and `앞서 있음(반영하지 않음 — 쓰기 모드 아님)` did not — both also rc 0
- the tree the planning built is readable from the ledger alone: `ledger.sh list -l sprint:<sprint ID> --all` lists it

### UC-8. A task close rides out on the development branch

**Actor**: an orchestrator session in the target clone (inside the story worktree)

**Steps**

1. When the evaluator returns `MATCH`, leave the evidence with `ledger.sh note <task ID>` and `ledger.sh close <task ID> --reason "<commit hash, gate exit code>"`.
2. `bash <plugin>/scripts/board.sh all` at the harness root redraws the local projections (outside git).
3. Commit the code on **this branch**. No documents.
4. **Ledger checks by hand** — no harness hook exists to run them: `bash <plugin>/checks/board-check.sh` and `bash <plugin>/checks/ledger-check.sh` (read mode) from the worktree.
5. **With no unresolved decision, without instruction**: `git push -u origin worktree-<worktree name>`, then **the backend's ledger reflection as an explicit step** (`beads`: `bd -C <harness root> dolt push`; `github`·`notion`: nothing to do), then `ledger-check` again. With an unresolved decision and no approval, stop after 4. The PR after this push and **the merge a person does** follow the same boundary as UC-7 (`harness:develop` "사이클 종결").

**Pass criteria**

- `ledger.sh show <task ID>` status == `closed`, and `close_reason` contains the commit hash and the gate exit code
- `bash <plugin>/checks/board-check.sh` → rc 0
- the commit of step 3 carries no projection: `git show --name-only --format= HEAD | grep -c '^docs/'` prints 0
- 5 → the tip of `git ls-remote origin refs/heads/worktree-<worktree name>` == `git rev-parse HEAD`
- after the explicit ledger reflection, `ledger-check` prints `원격 반영 확인됨` (or, where the backend has nothing to send, `원격 반영 대상 없음`) — the same criterion as UC-7; rc 0 alone proves nothing
- **must not be blocked**: another story's branch in progress in the same sprint does not make step 5 non-zero

### UC-9. A new machine stands the harness up and restores the target repos

**Actor**: a person (another machine, empty)

**Steps**

1. Install the plugin, once per machine at user scope: `claude plugin marketplace add juhyeon-cha/skills` then `claude plugin install harness@skills`; `claude plugin list` shows it. Before the marketplace carries it, `claude --plugin-dir <skills clone>/plugins/harness` and `HARNESS_PLUGIN_ROOT` for the hooks.
2. `git clone <url>` each repo the work touches, anywhere. Each already carries `.harness.json`, so the ledger coordinates come with the clone — **there is nothing else to write.** Steps 1 and 2 are the whole setup.
3. Make the ledger answer, per backend. **`beads`**: `ledger.sh bootstrap --dry-run`, then `ledger.sh bootstrap` (the Dolt data is not carried by anything else). **`github`**: `gh auth status` rc 0 with the `project` scope. **`notion`**: export `NOTION_TOKEN` on this machine.
4. `ledger.sh list` from inside a clone confirms the ledger answers. Until it is rc 0, every skill and gate is powerless.
5. Resume an interrupted story: open a session in its clone and `harness:develop` → `EnterWorktree`.

**Pass criteria**

- `ledger.sh list -n 0` → rc 0 with more than 0 issues
- `claude plugin list` names `harness@skills`, and `[ -f <plugin>/.claude-plugin/plugin.json ]` → rc 0
- `bash <plugin>/lib/harness-root.sh` run from each clone prints that clone — its committed `.harness.json` is the marker, and no other file was created on this machine
- `bash <plugin>/checks/board-check.sh` → rc 0 (the ledger's structure matches the registries the adapter derives)
- 5 → `git -C <worktree> rev-parse --abbrev-ref HEAD` == `worktree-<worktree name>`, and from inside it `ledger.sh list -n 1` is rc 0 (on `beads`, `ledger.sh where` prints that ledger)
- the failure path is judged too: on `beads`, if the ledger was never pushed, 3 fails with `remote at that url contains no Dolt data` (non-zero), and `ledger.sh list` being non-zero in that state is normal

---

## Axis D — self-improvement

### UC-10. Close a story or sprint and fold the retrospective into the rules

**Actor**: a person + an orchestrator session at the harness root

**Steps**

1. `ledger.sh children <story ID>` — every task must be closed, blocked, or deferred.
2. Sprint end is judged by **an open-issue query**: `ledger.sh list -l sprint:<sprint ID> --status open --all -n 0`. Never by eyeballing child statuses.
3. Close the story and milestones. With a deferred child left, `ledger.sh close <ID> --force` with the bypass reason in `--reason`.
4. `bash <plugin>/scripts/board.sh all` (no commit).
5. `harness:retrospective`: sweep the story's notes and the transcript aggregate (`bash <plugin>/checks/transcript-check.sh --since <story start> --session <UUID> --json` — it reads every project directory under `~/.claude/projects`, so sessions opened in target clones are included), raise **only what was observed twice or more** as proposed edits to the plugin's skills, agents, or session block, present them as per-file diffs, and apply **after user approval** — in the skills repo, as a story on `skills`.
6. On the source bead: `ledger.sh note <ID> "반영됨 → <commit hash>"`.

**Pass criteria**

- step 2 prints 0 issues; whatever remains is confirmed `deferred` with `ledger.sh list -l sprint:<sprint ID> --all`
- `ledger.sh show <story ID>` status == `closed` with a non-empty `close_reason`
- `bash <plugin>/checks/board-check.sh` → rc 0
- the applying commit (in the skills repo) names the source story ID: `git log -1 --format=%B | grep -q '<story ID>'` → rc 0
- the source bead's `ledger.sh show <ID>` notes carry a `반영됨 →` line
- a `ledger.sh note` body survives verbatim — a quotation with backticks and `$(...)`, passed through `--file`, reads back from `ledger.sh show` character-identical

### UC-11. Promote a persuasion-only rule to a gate

**Actor**: a person (approval) + an implementer subagent (implementation), in a story on the `skills` repo

**Steps**

1. Pick a candidate (the fit list of `harness-uhy.1.2 note`, or an item the retrospective diagnosed as "Loaded, and it still repeats").
2. Add a rule function to the plugin's `hooks/guard.sh`, or an assertion to `checks/`.
3. **A/B attribution**: a copy with only that rule's registration removed — the same input is blocked by the original and passes in the copy.
4. `bash checks/guardrail-check.sh` — the whole guardrail is alive.
5. A new hook event goes into `hooks/hooks.json` in the same change (S2 compares it with the files both ways).
6. Commit; the plugin gate (`claude plugin validate --strict`) and `tests/run-all.sh` pass.

**Pass criteria**

- for the blocked input, the original `guard.sh` → rc 2; the copy with only that registration removed → rc 0
- **the copy actually differs**: `diff <original> <copy>` prints more than 0 lines
- for the input that must pass (the false-positive boundary), the original `guard.sh` → rc 0
- `bash checks/guardrail-check.sh` → rc 0, and non-zero for a copy with the registration removed
- `bash tests/harness/guard-check.sh` → rc 0
- `hooks/hooks.json` and `hooks/*.sh` agree both ways at the `<event>\t<matcher>\t<command>` grain (guardrail-check S2)
- the new rule's checked set is non-empty — no path passes on 0 items
- the rows for the new rule in [guardrails.md](guardrails.md) section 1 (what it blocks · what it cannot) land in the same story, and the limits that stay rc=0 get a pinned fixture in `guard-check.sh`
