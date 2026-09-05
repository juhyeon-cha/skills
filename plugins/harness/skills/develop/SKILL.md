---
name: develop
description: Story (epic bead) development execution procedure. Use on a "스토리 시작/착수해" or "<스토리ID> 개발해" request, and while running the task implementation cycle. Workspace creation → milestone-scoped implement→verify cycle → story wrap-up.
---

# Story development

## 1. Pickup verification

**The session unit is (story, repo).** A development session opens in the clone root of the target repo (`~/.harness-workspace/<repo>`), and the clone directory name is this session's repo — it must be registered in the harness root's `repos.json`. A multi-repo story is worked by **one session per repo**; the sessions coordinate through the ledger (the story bead's notes and the tasks' claims), not through each other. The harness root is what `${CLAUDE_PLUGIN_ROOT}/lib/harness-root.sh` prints from that clone root (it reads `~/.harness-workspace/.harness-root`, which `scripts/repo.sh` writes) — hold it for the whole cycle, every ledger call is `HARNESS_ROOT=<harness root> ledger.sh …` until the worktree is wired (the hook below). `ledger.sh` in this skill is always `${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh` — the ledger adapter; its subcommands, arguments and JSON keys are those of `bd` (`ledger.sh --help`), and the backend is the `backend` of the harness root's `ledger.json`.

- `ledger.sh show <story ID>` — check that its type is epic, that it carries a `repo:*` label, and that **one of those labels is this session's repo**. Otherwise stop and report what is missing.
- Read the story's `ACTOR:` notes in the form below. The last `ACTOR: <this session's repo> <값>` line is this cycle's claim actor (3-0 creates one when it is absent). When the story is already `in_progress` under another actor **for this repo** and that ACTOR note is not yours, that is a **concurrent-work collision** — do not pick it up; report to the human.
- `ledger.sh children <story ID>` shows the milestone→task tree. If even one task has no acceptance, do not pick it up; go back to the plan-story procedure.

### ACTOR note — `ACTOR: <레포> <값>`

- **Format**: `ACTOR: <레포> <값>` — the repo is this session's repo (the clone directory name), the value is `sess-` + 6 random characters. One live line per (story, repo); a multi-repo story carries one line per repo, left by the session of that repo.
- **Reading**: take the last `ACTOR:` line whose repo is this session's repo. Lines for other repos belong to the other sessions of the same story — they are not collisions and are not reused.
- **Old format — `ACTOR: <값>` with no repo → `DECISION_NEEDED`.** A value without a repo cannot be attributed to a session, so it is neither reused nor overwritten by guess; ask the human whether to re-claim this (story, repo) under the new format. The human-wait handling is "사람 대기" (this skill).
- **Only `<값>` goes into `--actor`** at claim time. The guard's session→actor mapping and the stop guard (`${CLAUDE_PLUGIN_ROOT}/hooks/stop-resume.sh`) read that value alone; the repo lives in the note only.

## 2. Create the workspace

Enter the story worktree with the native **`EnterWorktree`** tool, `name` = `<story ID>`. Measured 2026-09-05 (`claude -p`, scratch clone): the worktree is `<clone>/.claude/worktrees/<story ID>` on branch **`worktree-<story ID>`**, cut from `origin/<default branch>` (the `worktree.baseRef` default, `fresh`); the tool does not take a branch name. When `git worktree list` already shows that path (picking up an interrupted cycle), enter it with `path` instead of `name`. Do not run `git worktree add` by hand — the tool and its hook own creation.

The plugin's PostToolUse hook (`${CLAUDE_PLUGIN_ROOT}/hooks/enter-worktree.sh`) wires the ledger (`ledger.sh wire-worktree` — for `beads` a `.beads/redirect` to the harness ledger — plus the clone's `.git/info/exclude`) and, when the target repo has no EnterWorktree hook of its own, runs the `bootstrap` of repos.json once (a sibling marker under `.claude/worktrees/` skips the rerun). **A hook failure does not block the tool** — it exits 2, so its stderr lands in your response (PostToolUse feeds only exit-2 stderr back to Claude): `원장 배선 실패` means the harness root (`ledger.json`) was not found. Before delegating, `${CLAUDE_PLUGIN_ROOT}/lib/harness-root.sh` run inside the worktree must print the harness root. Do not bootstrap (install dependencies) by hand.

**Hold the worktree path and the harness root absolute path for the whole cycle.** The worktree sits outside the harness (`~/.harness-workspace/<repo>/.claude/worktrees/<story ID>/`), so a subagent cannot derive the harness root from its path — state it in every delegation, or `HARNESS_ROOT=<harness root> ledger.sh …` does not work. When the clone is missing, register and clone first with `scripts/repo.sh add <url>` and open the session there.

## 3. Task cycle

Start from the first task whose dependencies are clear and go **milestone by milestone**. The batch condition fixes the unit of verification:

- **Batch mode is the default flow.** The condition is that **the milestone is single-repo** (every child task carries the same `repo:` label) and that **the task count is around 4**. Delegate every task of the milestone **to one implementer as a list**, implemented in dependency order (the implementer commits and leaves a `VERIFY_PENDING` note per task, then moves to the next — the discipline is `${CLAUDE_PLUGIN_ROOT}/agents/implementer.md` "목록을 받았을 때"), and at the end of the milestone run **verify-code once → verify-implement once → close the tasks together**. A task that is implemented but not yet closed stays `in_progress`, marked with a `VERIFY_PENDING` note.
- **Outside the condition the former flow holds** — when the milestone crosses repos or the task count exceeds that width, delegate implementation → verify-code → verify-implement → close **per task**.
- **This condition is written here.** Other documents (`verify-code`·`verify-implement`·`plan-story`·`implementer`·`docs/operations.md`) point at this section and do not restate the condition.

The steps below apply, **in batch mode, 0 once to the whole list and 1 once to the milestone**, with 2~5 applied whenever a signal arrives. Outside the condition, run 0~5 per task.

0. **Two checks before pickup.**
   - **Repo decision**: check that the task carries exactly one `repo:` label — that label fixes the worktree to delegate into. With two or more, do not pick it up; go back to plan-story's narrowing (section 2).
   - **Atomic claim**: take it with `ledger.sh update <task ID> --claim --actor <actor value>`. **In batch mode, claim every task of the list under the same actor before delegating** — drop a rejected task from the list. That leaves as many unmarked `in_progress` tasks as the list holds until the implementer leaves its marks, and `checks/rules-check.sh` S22 counts **the tasks of one actor within one story as a single lane**, so that state is not a violation — do not defer the claim to one per task.
     - **Right before delegating, leave `ledger.sh note <task ID> "DELEGATED: <마일스톤ID>"` on every claimed task.** 4b of the stop guard (`${CLAUDE_PLUGIN_ROOT}/hooks/stop-resume.sh`) exempts that stretch on this mark — without it there are as many unmarked `in_progress` tasks as the list holds, from the claim until the implementer's first commit, and a stop inside that window is blocked while matching none of the guard's three exits (observed in `harness-0uw`). The mark sits in **the same place under the same rule** as the `VERIFY_PENDING` of step 2 (the last non-empty line of notes), so the mark the implementer leaves after committing replaces it naturally. It is a one-line fixed string with no backtick and no `$`, so it falls under the inline allowance of "원장에 본문을 넘기는 형태" (this skill).
     - **The actor's origin is a note on the story bead.** Pickup verification (section 1, "ACTOR note") reads the last `ACTOR: <this session's repo> <값>` line of the story's notes — use that value as is when it exists (picking up an interrupted cycle — the same actor passes claim idempotently, so resumption happens by itself), and when it does not, make `sess-` + 6 random characters and leave it with `ledger.sh note <story ID> "ACTOR: <레포> <값>"`. An old-format line (no repo) is `DECISION_NEEDED` — section 1 holds the rule.
     - **Inline the value as a literal in every ledger call.** Holding it in a shell variable (`$HARNESS_ACTOR`) and referencing that is forbidden — the Bash tool gets a new shell per call, so the variable evaporates, and an empty value falls back to the default actor (git user.name), which makes **two sessions on one machine the same actor and lets claim pass idempotently**.
     - **Judge claim state from the claim attempt's rc, or from `status` and `assignee` read together.** A rejection is rc=1 with its message on stderr — in full, `Error claiming <task ID>: issue already claimed by <value>`, and the `already claimed` called below is a substring of it. **Read that rc without a pipe**: `$?` after a pipe belongs to the last command, so a rejection reads as 0.
       - To look at the state again later, read **both together** with `ledger.sh show <task ID> --json | jq -r '.[0] | .status, .assignee'` (this query's pipe does not read an rc, so the prohibition above does not touch it). Held means `in_progress` + an `assignee` equal to that actor **on the `beads`·`notion` backends**; on `github` the `assignee` is the GitHub login of whoever ran the claim (an issue assignee has to be a real account — `ledger-github.sh` header), so there judge held by `status` plus the claim's own rc, never by comparing `assignee` with the actor value.
       - **Do not judge from `assignee` alone.** `ledger.sh update --assignee` puts a value in without a claim — `plan-sprint` section 3 assigns story owners that way, so issues whose `status` is `open` while an `assignee` exists are common in the ledger (measured on the harness ledger 2026-08-31: 28 tasks). Reading those as "held" is the misjudgment this passage blocks.
       - **Do not look at `owner`** — it is a git identity unrelated to claim (the measured value is an email), so it is the same value whoever holds it, and judging from it produced the misjudgment "isolation does not work" that this passage came from (`harness-dfd.1.1` proof).
       - `assignee` is omitempty, so **when the value is empty** the key itself is absent and it comes back `null` — do not generalize that into "this backend has no such field".
     - When rejected with `already claimed`, another actor's session is working on it — skip it and go to the next ready task. **When every ready task is claimed by another actor, break the loop and go to human wait** — an orphan claim from a dead session is the suspicion, and reclaiming (`ledger.sh update <ID> --status open`, then claim again) is what a human confirms and directs.
     - Never set `--status in_progress` directly. **Two sessions do not hold the same (story, repo) at once** — split parallelism by story, or by repo within a multi-repo story (the ACTOR-note reuse convention is for "picking up", not for concurrent work).
     - **Do not delegate two tasks into one worktree at the same time.** The git staging area is a per-worktree shared resource, so even an `add` with explicit paths mixes with the other's `add` and `commit`. Split by story when parallelism is needed. The target is **two agents in one worktree** — one actor walking a list in sequence is not that target, and S22 counts it that way too.
1. **Implementation**: delegate to implementer. **Delegate thin** — the per-role discipline is held by the `${CLAUDE_PLUGIN_ROOT}/agents/` definitions, so the delegation message carries only ① first line: harness root absolute path + the absolute worktree path of the repo that task touches + the task ID (**in batch mode, the milestone's task ID list in dependency order** — the single-repo condition makes the worktree one) ② what "위임 메시지의 환경 스냅샷" below requires (the values to carry + the verbatim-quotation discipline) ③ task-specific context (background issue link, design hints).
2. `IMPLEMENTATION_COMPLETE` → secure the `VERIFY_PENDING` mark first. The mark is `ledger.sh note <task ID> "VERIFY_PENDING: <커밋 해시>"`, and the stop guard (`${CLAUDE_PLUGIN_ROOT}/hooks/stop-resume.sh`) and `checks/rules-check.sh` S22 use it to separate "finished, awaiting verification" from "left half-done" (the mark is the last line of notes, so a note appended after it undoes it). It is a one-line fixed string with no backtick and no `$`, so it falls under the inline allowance of "원장에 본문을 넘기는 형태" (this skill). What follows splits by the unit of verification:
   - **Batch mode**: the implementer should have left the mark per task — check the last note of every task in the list with `ledger.sh show`, and fill a missing one in from the commit hash in the report. Once every task of the milestone is one of `VERIFY_PENDING`·`blocked`·`deferred`, run **the verify-code procedure** once over every task awaiting verification as a single list.
   - **Outside the condition**: the orchestrator leaves the mark and goes to **the verify-code procedure** for that one task.
3. `LGTM` → judge acceptance with **the verify-implement procedure** and close the tasks — in batch mode carry the same list and close the tasks that came back `MATCH` together.
4. **Handling of the remaining defined signals** — every signal needs an action, or each session improvises its own:
   - `IMPLEMENTATION_BLOCKED` → leave the reported root cause and attempt history as a `ledger.sh note`, then `ledger.sh update <task ID> --status blocked`. Move on to the next ready task (this does not stop the whole story). **`blocked` is not a human wait** — it is a state you walk past, not one you stop and wait in. **In batch mode**, only the report's "막힌 태스크 ID" goes `blocked`, the "그때까지 완료(커밋)된 태스크 목록" gets its `VERIFY_PENDING` checked per step 2, and the remaining tasks (minus those depending on the blocked one) go through step 1 again as a new list.
   - `DECISION_NEEDED` (from any role) → leave the question as a `ledger.sh note` and go to **human wait** — when a loop is running, break it per the discipline of the long-running section.
   - A value not in the list → safe exit: record the situation and report to the human.
5. The orchestrator leaves each role's core result as a `ledger.sh note` — in batch mode, not on a task before it is closed but on the milestone bead (a task's last note has to be `VERIFY_PENDING`).

## 4. 스토리 마무리

1. **A multi-repo story runs one integration verification before it is closed.** The per-task gates ran only inside their own repo — a broken cross-repo contract (an API schema, say) still leaves every task closed as MATCH. In the worktrees of every repo involved, run each repo's `check` once more **at the same final commit state**, and leave the result (exit code per repo) on the story bead as a `ledger.sh note`. When a divergence shows, do not close the story; report to the human. A single-repo story has no such step.
2. Once every task is one of closed, blocked, or **deferred** (deferred is the third state the user explicitly closed — "결정 상태" (this skill). When the user says "안 한다", transition it with `ledger.sh update <ID> --status deferred`), leave a result summary (commit list, items not run) on the story bead as a `ledger.sh note` and close the milestones and the story. **With a `deferred` child, the `beads` backend counts it as an open child and refuses to close** — pass the parent with `ledger.sh close <ID> --force` and the dependency with `ledger.sh dep remove`, and leave the reason for the bypass in the close reason ("결정 상태" (this skill)). After closing, redraw the local projection with `scripts/board.sh all` (outside git — not a commit target).
3. **Close the cycle.** The procedure body, its scope, and its failure handling are single-owned by "사이클 종결 — PR 이 종점이다" (this skill) — **do not restate the steps here.** This channel has one constraint of its own: the commit carries **everything that branch did** (the opposite of the planning channel). The redraw in step 2 is itself stage 1 of that closing, so when no change is left, go straight to stage 2.
4. **Worktree cleanup happens after a merge is confirmed, and only on user instruction.** Judging whether it merged and directing the cleanup is the human's part, and **everything downstream of that is owned by `scripts/workspace-cleanup.sh <story ID>`** — do not run `git worktree remove` by hand (no gate — the script alone owns the removal order). What that script does is refresh remote refs · check for uncommitted and unpushed work · remove the worktree → delete the local story branch → delete the bootstrap marker, and it repeats per repo named by the `repo:` labels. stdout is a list of `<repo name>\t<absolute path of the removed worktree>` lines.

   - When uncommitted or unpushed changes remain, the script **leaves them alone and exits non-zero**, printing what remains. Report that output as is; whether to drop or keep it is the human's decision. Only when a squash merge deleted the remote branch and that reads as unpushed do you add `--force` on the human's instruction (uncommitted changes are not removed even by `--force`).
   - **The script does not check PR merge state** — a `gh` call is an external API call and thus subject to human approval, and when `gh` is missing or unauthenticated the check is skipped silently. When it is needed, the human checks directly with `gh pr view --json state,mergeCommit`.
   - **The clone itself is never deleted.** A registered repo's clone gets reused by the next story — `scripts/repo.sh remove <name>` is for deregistering only, and even that leaves the directory.

## 위임 메시지의 환경 스냅샷

**What the delegating side already knows is not left for the receiving side to find out again.** The three delegation procedures (3-1 of this skill · `verify-code` 1 · `verify-implement` 1) carry the two below right after the paths on the first line.

| Item | Form |
|---|---|
| **The HEAD hash at that moment** | the value of `git rev-parse --short HEAD` |
| **Working tree state** | the result of `git status --porcelain`. **When it is empty, write "비어 있다"** |

- **A role that receives these two does not check them again.** When they did not arrive, or diverge from reality, check directly and write that fact into the report.
- **The ledger is not carried.** The role reads the ledger itself — the ledger is the single source of acceptance.
- **Paths are not exempt — all three roles confirm them themselves.** A worktree's parent is the main checkout, so one level off writes into another tree or judges another tree.
- **Point at the place instead of carrying the wording over.** Do not quote the content of documents in the tree (rules, role definitions, skills, ADRs) into a delegation message — name the place alone, as the `"<section title>"` of `<file path>`. A delegation message is the one artifact nobody verifies, so wording written from memory becomes the evidence as it stands.
- **Carry only what cannot be read from the tree** — HEAD and working tree, task-specific context (background links, design hints), and claims in the previous stage's **report** that need fact-checking.
- **A delegation message does not exceed 25 lines.** Count the lines the delegator wrote — quotations from the previous stage's report do not count. **What the limit must not cut**: HEAD and working tree, claims in the previous stage's report that need fact-checking, batch mode's **task ID list** line (common to all three procedures — the condition is `develop` section 3), and what `verify-implement` 1 carries to evaluator: **the items already judged by command and their exit codes** · **the items with no command**. What to cut is what can be read from the tree.
- This list is single-owned here. The other two procedures only point at this section.

> Evidence: `harness-2a5.2.4` · `harness-dg0.6.42`.
## 장기 실행

When there are enough tasks that unattended repetition is needed, propose a loop (`/ralph-loop` or `/loop`) to the user with 3~4 as the prompt. **[both] Never start a loop on your own initiative.** The loop prompt carries pointers only — the procedure body is held by this file.

Loop-exit discipline. **Each rule names its target loop at the head** — the two loops differ in mechanism, so some rules hold for only one of them, and without a named target the reader attempts combinations that do not hold. The stop guard (`${CLAUDE_PLUGIN_ROOT}/hooks/stop-resume.sh`) is an always-on hook rather than a loop, so it is the target of none of the rules below.

- **[`/ralph-loop` only] A loop always starts with `--completion-promise` (the exact completion sentence) and `--max-iterations` (a ceiling).** An open-ended loop with neither is never started.
  - **This rule does not hold for `/loop` — it has neither option.** `/loop` takes `[interval] [prompt]` and nothing else, so a `--completion-promise` or `--max-iterations` appended to it is not parsed and rides along as part of the prompt string. What produces the exit is the model's per-turn rearm decision, not that string. **So do not write the two options onto a `/loop` and read that as a ceiling being in place** — passing then becomes a false signal of rule compliance.
- **[both] Stopping from inside**: when a signal leading to human wait appears, break the loop and leave the reason for waiting as a `ledger.sh note`. **The list of those signals is single-owned by the "사람 대기" section below — it is not restated here.** The means of breaking differs by target: `/ralph-loop` takes the `cancel-ralph` skill, `/loop` takes ending that turn without rearming — rearming is a per-turn choice, not a default.
- **[`/ralph-loop` only] One loop per machine at a time.** The loop state file (`.claude/ralph-loop.local.md`) and the cancel marker are singletons, so a second loop overwrites the first's state and a cancel cannot name which one it means. When parallel sessions are needed, run the loop in one session and work interactively in the rest. **This rule does not hold for `/loop`** — those two singletons are artifacts of the `ralph-loop` plugin, which `/loop` does not have. That does not mean running `/loop` concurrently is safe.
- **[`/ralph-loop` only] Stopping from outside**: `touch "${HARNESS_DATA_DIR:-$HOME/.claude/plugins/data/harness}/ralph-cancel"` — the Stop hook (`${CLAUDE_PLUGIN_ROOT}/hooks/ralph-cancel.sh`) detects the marker and removes the loop state. Depending on hook ordering it can stop up to one iteration late. Both hooks keep their state under that data directory, outside every project tree.
  - **[stop guard] Its marker differs: `touch "${HARNESS_DATA_DIR:-$HOME/.claude/plugins/data/harness}/stop-resume-cancel"`.** `${CLAUDE_PLUGIN_ROOT}/hooks/stop-resume.sh` **does not read the `ralph-cancel` marker.** That path is the **entrance** a human touches, and **the owner is in the file name** — when the guard first finds the entrance it `mv`s it to `stop-resume-cancel.<session_id>` in the same directory, binding it to that session, and from then on it **reads only its own place** and passes until the session ends (the `CANCEL` line of `stop-resume.log` there). **It neither reads nor deletes another's place** — concurrent sessions cannot steal each other's markers, and a dead session's leftover is a harmless empty file rather than something to be consumed. So **touch the entrance again every time you switch it off**: a past session's place cannot switch this session off.
  - **The two markers do not switch each other off.** When a loop and the guard are both engaged, **both markers** have to be touched (the "[both]" in the brackets above means the two *loops*; the two here are the two *markers*).
- **[both] The re-review ceiling is counted with `ledger.sh note` rather than memory.** A loop replaces sessions, so the orchestrator's memory disappears every iteration — without the counter left in a note, **limit exceeded never arrives.** The format and the ceiling value are single-owned by the "재시도 카운터" of the `verify-code` skill — **no number is written here.**


# Always-on rules owned here

The sections below came down from the always-on ruleset (the harness repo's agile.md rules file, before the plugin). This skill owns them; the other skills, the role definitions, and the session context block point at them by section title and do not restate them.

## 운영 규율

- **acceptance 는 기계 판정 가능해야 한다.** ①무엇이 존재하는가 ②어떤 입력에 어떤 출력인가 ③어떤 테스트가 통과하는가 — 셋 중 하나의 형태. "잘 동작한다"는 금지.
- acceptance 없는 태스크는 `ledger.sh ready` 에 떠도 착수 금지. 먼저 acceptance 를 채운다.
- 완료 흐름: implementer(구현) → reviewer(품질) → evaluator(acceptance 대조) → `ledger.sh close`. **verify 의 단위는 마일스톤이 기본이다** — 배치 조건을 채우면 마일스톤의 태스크 전부를 구현한 뒤 reviewer·evaluator 를 1회씩 돌리고 일괄로 닫는다. 조건과 조건 밖(태스크별 verify)의 원문은 `develop` 3절이다(`harness-2a5.4`). 만든 주체가 채점하지 않는다.
- **evaluator 의 MATCH 기록 없이 태스크를 닫지 않는다.** `ledger.sh close --reason` 에 판정 근거(커밋, 게이트 종료 코드)를 남긴다.
- **위임할 수 없는 세션이면 그 사실을 판정 근거에 적는다** — `close --reason` 에 "evaluator 미위임(사유)". 자기 판정은 위반이 아니라 **약한 근거**이고, 적지 않으면 위임한 판정과 구분되지 않는다.
- **투영 트리는 셋이고 셋 다 git 밖이다.** epic 은 `sprint:` 라벨이 있으면 `docs/sprints/<ID>/`, 없으면서 `closed` 가 아니면 `docs/backlog/<슬러그>/` 다 — 라벨은 출력 경로만 가르고 렌더 여부를 가르지 않는다. `decision` 은 **전수**가 `docs/adr/<슬러그>.md` 다(status 로 좁히지 않는다 — 대체된 결정도 계보와 함께 남는다). 다시 그리는 것은 `scripts/board.sh all` 하나이고 `post-merge`·`post-checkout` 훅이 그것을 부른다. 백로그 스토리가 닫히면 그 디렉토리는 사라지는 것이 정답이다.
- **`docs/sprints/`·`docs/backlog/`·`docs/adr/` 를 손으로 고치지 않는다.** 다음 렌더가 덮어쓴다 — 고칠 것은 원장이다.
- **게이트의 판정은 종료 코드다.** 역할 응답은 기계가 아니라 **네가** 첫 줄 `SIGNAL:` 로 읽는다 — 강제 장치가 없고 `transcript-check` A9 이 사후에 셀 뿐이다. 목록에 없는 값은 안전 종료.
- **정정 보존**: 원장에서 판단을 뒤집을 때 이전 결정을 지우지 않는다. `ledger.sh note <id>` 로 원문을 인용하고 무엇이 왜 틀렸는지 남긴다.
- 스토리가 막히면 스토리만 기록하고 다음으로 진행한다. 스프린트 전체를 중단하지 않는다.
- **게이트는 예외 목록 방식으로 쓴다 (극성 반전).** 검사 대상을 손으로 고르지 않는다 — 전체 집합에서 파생하고, 검사할 수 없는 항목만 사유와 함께 면제 목록에 등재한다. 새 항목의 기본값은 "검사됨"이고, 면제 키가 실제 집합에 존재하는지 역방향 단언을 함께 둔다. 허용 목록 검사는 목록에 없는 위반에 침묵하고 그 침묵이 통과로 읽힌다.

## 원장에 본문을 넘기는 형태

**원장(`ledger.sh`)에 넘기는 본문(note·description·acceptance·close reason)을 셸 명령 문자열 안에 두지 않는다.** 셸이 ledger.sh 보다 먼저 본문을 해석해 역따옴표·`$` 로 감싼 식별자를 빈 문자열로 지우는데 ledger.sh 의 종료 코드는 0 이다.

- **파일 옵션이 있으면 그것을 쓴다** — `note --file`·`--stdin`, `create`/`update --body-file`(`create` 는 `--stdin` 도), `close --reason-file`, `dep add --file -`. 이것이 어댑터가 모든 백엔드에서 받는 파일 옵션 전부다(`ledger.sh --help` · `harness-m8gg.4.1` acceptance 6 의 인자 규약 — `--design-file` 은 없다). 없는 값(`--acceptance`·`--title`)은 `"$(cat <경로>)"` 로 넘긴다 — 치환의 출력은 재스캔되지 않는다.
- **역따옴표·`$` 가 없는 한 줄 고정 문자열은 인라인으로 넘겨도 된다** — `RETRY: <단계> <n>/<상한>`·`ACTOR: <레포> <값>`.
- **본문 파일은 ledger.sh 호출과 다른 호출에서 만든다.** 파일 쓰기 도구(Write·Edit)가 가장 단순하다 — 본문이 명령 문자열을 떠나므로 명령 문자열을 보는 규칙 전부가 재료를 잃는다. 같은 호출의 heredoc 으로 만들면 본문이 다시 명령 문자열 안이다.
- **ledger.sh 의 인자로는 heredoc 을 쓰지 않는다.** 손상은 없지만 본문 전체가 명령 문자열로 스캔되어 다른 규칙이 본문의 낱말에 발화하고, 통과시키려면 기록할 내용을 왜곡해야 한다.
- **막힌 것을 본문 수정으로 푸는 것은 어느 단계에서도 금지다.** 손댈 것은 형태(호출 분리)와 도구(파일 쓰기)뿐이다. 두 수를 다 쓰고도 막히면 본문을 고치지 말고 **막혔다는 사실을 보고에 적는다.**
- 게이트: **없다 — 규율뿐이다.** 종전에 역따옴표와 `bd` 뒤의 heredoc 을 막던 훅 규칙(`r_bd_body`)은 플러그인 재구조화에서 뺐다(가드는 앵커와 무관한 불변식 넷만 남긴다 — 이 규율은 그 넷 밖이다). `$VAR` 도 같다 — 본문 밖의 `$` 가 흔해 판정에 넣으면 오탐이 규율을 압도한다.

> 근거: `harness-xwd` · `harness-dg0.6.36` · `harness-dg0.6.19` · `harness-dg0.6.14`.

## 상태 주장의 근거

**"게이트가 통과했다"와 "일이 됐다"는 다르다.** 자신이 일으킨 상태를 보고할 때는 **그 상태를 실제로 결정하는 것**을 같은 턴에 확인하고, 근거를 함께 남긴다.

| 주장 | 근거로 쓰면 안 되는 것 | 실제로 확인할 것 |
|---|---|---|
| 게이트 통과 | 부분 실행(단일 테스트·일부 모듈)의 rc | 그 범위 전체를 돌린 rc |
| 문서 최신 | `board.sh` 의 rc | stdout 의 경로가 실재하고 그 `index.md` 의 상태 기호가 `ledger.sh show` 의 status 와 같다 |
| 워크트리 생성됨 | `EnterWorktree` 의 성공 메시지 · 훅의 rc | 경로가 실재하고 브랜치가 `worktree-<id>` 이며 그 안에서 `${CLAUDE_PLUGIN_ROOT}/lib/harness-root.sh` 가 하네스 루트를 낸다 |
| push 됐다 | push 명령의 rc | `git ls-remote` 의 tip 이 내 커밋 SHA |
| 머지됐다 | PR 상태가 `MERGED` 인 것 · push 시점에 대조한 원격 tip (스쿼시 머지는 **새 커밋 객체**를 만들어 그 둘이 원본 커밋과 갈릴 수 있다) | 머지 커밋의 `--stat` 이 브랜치 전체 diff(`git diff --stat <기본브랜치>...<브랜치>`)의 것과 같다. 삭제·rename 이 든 커밋은 `git ls-tree --name-only origin/<기본브랜치> <경로>` 로 원격 트리에서 그 경로의 부재를 확인한다 |
| 태스크 닫혔다 | `ledger.sh close` 를 호출한 것 | `ledger.sh show` 의 status·close_reason |
| PR 이 열렸다 | `gh pr create` 의 rc | `gh pr view --json url,state` 의 url 과 state |
| 파일로 남겼다 | 응답 본문에 내용을 출력한 것 | 그 턴의 쓰기 결과, 또는 경로 재확인 |
| 계속 진행된다 | 다음에 할 일을 알고 있다는 것 | 지금 돌고 있는 작업이 실재하는가 (백그라운드 태스크·루프·예약) |

확인할 수 없으면 낙관적으로 쓰지 말고 **확인하지 못했다고 쓴다.**

**돌고 있는 것이 없는데 주체가 나라면 턴을 끝내면 안 된다.** 턴 종료는 그 자체로 사용자 대기 상태다. 예고할 거면 하지 말고 그냥 해라. 멈춰야 할 이유가 있으면(승인 필요·판단 요청) 그것을 이유로 적고 멈춘다.

**게이트의 rc 를 기록으로 갈음할 수 있는가는 그 게이트가 무엇으로 결정되는가에 달렸다.**

| 부류 | 예 | 재실행 |
|---|---|---|
| **트리에서 결정된다** | `repos.json` 의 `check` | **하지 않는다.** rc 가 커밋에 묶여 있다. 작업자가 커밋 메시지에 남긴 명령과 rc 를 근거로 쓰되, **그 기록이 대상 커밋 자신의 것인지** 확인한다 — 부모 커밋(`<커밋>^`)의 게이트 기록과 문면이 글자 그대로 같으면 갈음하지 않고 직접 돌린다 |
| **트리 밖과 대조한다** | `board-check`(원장) | **쓰는 자리에서 직접 돌린다.** 트리가 그대로여도 다른 세션이 원장을 바꾸면 뒤집힌다. 커밋 메시지·훅 통과·앞 단계 보고 어느 기록으로도 갈음하지 않는다 |

이 구분은 여기가 단일 소유다. 역할 정의와 스킬은 *누가 언제 돌리는지*만 적고 이 절을 가리킨다.

**게이트를 돌리는 것 자체가 부작용이면, 부작용을 opt-in 으로 둔다.** `checks/ledger-check.sh` 가 그 자리다 — 원격 반영은 `LEDGER_CHECK_PUSH=1` 이 켤 때만 일어나고 **켜는 자리는 `pre-push` 훅 블록 하나**다. 판정·대조·문서 확인으로 부르면 아무것도 반영되지 않으므로, 이 검사를 부르기 전에 외울 규율은 없다.

- **앞서 있는데 반영하지 않은 상태는 통과 문구로 갈린다** — `원격 반영 앞서 있음(반영하지 않음 — 쓰기 모드 아님)`. `확인됨`(원래 앞서 있지 않았다)과 글자가 다르다. rc 0 만 보고 "원장이 원격과 같다"로 읽지 마라.
- **rc 를 얻는 대가로 상태가 바뀌는 검사가 또 생기면 여기 적는다.** 그런 검사는 안전한 쪽을 기본값으로 두고 부작용을 스위치 뒤에 둔다 — 위 "게이트는 예외 목록 방식으로 쓴다" 와 같은 요구다. 근거는 `harness-x0i.2`.

**측정 환경을 함께 적는다.** 실측을 근거로 쓸 때 셸과 버전, 환경 변수(`BEADS_DIR` 등), CWD, 도구 버전을 같이 적는다. 수를 근거로 쓸 때는 범위·모집단·집계 필터 조건·입력도 적는다. 하위 세션·에이전트의 응답 요약을 실측 전사로 쓰지 않는다 — 도구 결과 원문을 근거로 삼는다.

**"왜 그런가"도 근거를 요구한다.** 이유를 적을 때 그것을 확인했는지 함께 적고, 확인하지 않았으면 "가설"로 쓴다. 근거물(스크린샷·로그·해시)은 파일명과 만든 방법을 함께 적는다. 도구를 통과했다는 것은 그 도구가 보는 것만 통과했다는 뜻이다.

> 근거: `harness-fnv` · `harness-dg0.6.7` · `harness-1e7` · `harness-8xe`.

## 결정 상태 — 안 하기로 한 것은 남은 일이 아니다

사용자가 "안 한다 / 지금 말자" 로 명시적으로 닫은 항목은 **완료도 미완도 아닌 제3의 상태**다. beads 에서는 `deferred` 다 — `ledger.sh update <ID> --status deferred`. 마감 조건에서 closed·blocked 와 동급이다.

- 남은 작업·완료 조건·보고 목록에서 **제외**한다. 완료 판정을 막지 않는다.
- 상황이 바뀌어 다시 필요해 보이면 **한 줄로 묻는다.** 설득하지 않는다.
- 침묵으로 넘어간 것과 명시적으로 닫은 것을 구분한다. 애매하면 한 번 묻는다.
- **beads 백엔드는 `deferred` 를 열린 하위·블로커로 계산한다.** 마감에는 우회가 필요하다: 부모는 `ledger.sh close <ID> --force`, 의존은 `ledger.sh dep remove`. 우회 사유를 close reason 이나 note 에 남긴다.

## 진단 가설 규율

원인을 진단하고 조치를 제안할 때 적용한다. 단순 관찰에는 적용하지 않는다.

- **검증 전에는 "가설"로 쓴다.** "원인은 X" 대신 "가설: X — <이렇게> 검증 가능".
- **대조군을 쓰기 전에 동등성을 확인한다.** 조건(설정·캐시·경로·버전)이 같은지 확인하거나, 확인하지 못했음을 명시한다.
- **진단 시도는 2회까지.** 초과하면 확인된 사실과 남은 불확실성을 정리해 사람에게 넘긴다. 아래 재시도 카운터(재작업 상한)와 별개로 센다.

## 사람 대기 — 어떤 신호가 사람에게 가는가

**사람 대기로 이어지는 신호의 목록은 여기가 단일 소유다.** 세션 컨텍스트 블록 "절대 금지" 의 "미해결 결정"과 `develop` 의 장기 실행은 이 절을 가리키기만 한다(`harness-dg0.6.39`). `verify-code`·`verify-implement` 의 신호 처리는 자기 역할의 SIGNAL 값을 분배하는 자리라 이 목록을 정의하지 않는다.

| 신호 | 내는 자리 | 사람이 정할 것 |
|---|---|---|
| `DECISION_NEEDED` | 어느 역할에서든 | 물어 온 질문의 답 |
| `DEVIATION` | evaluator | 계획이 현실과 어긋났을 때 무엇을 고칠지 |
| `SCOPE_EXCESS` | evaluator | 초과분을 분리할지 그대로 받을지 |
| 재시도 카운터 **상한 초과** | verify-code · verify-implement | 같은 지적으로 더 돌릴지 |
| SIGNAL **목록에 없는 값** | 어느 역할에서든 | 안전 종료 뒤의 처분 |
| 준비된 태스크 전부가 타 **actor claim** | develop 착수 | 고아 claim 을 회수할지 |
| 사이클 **종결 미완** | "사이클 종결" 절의 실패표 | 재시도할지 손으로 마칠지 |

- **처리는 어느 신호든 같다**: 대기 사유를 `ledger.sh note` 로 남기고 멈춘다. 루프 중이면 루프를 끊는다 — 수단은 `develop` "장기 실행" 이 든다.
- **여기 든 신호는 원장 조회로 안 보인다.** 전부 status 전이 없이 `ledger.sh note` 본문에만 남는다.
- **`SCOPE_EXCESS` 는 카운터 대상이 아니지만 사람 대기다.** 카운터는 재작업을 몇 번 더 시킬지, 이 목록은 다음 행동을 누가 정하는지를 가른다.
- **`blocked` 은 사람 대기가 아니다.** `develop` 은 `IMPLEMENTATION_BLOCKED` 를 받으면 태스크를 `blocked` 로 전이시키고 다음 준비된 태스크로 지나간다. "절대 금지" 가 `blocked` 를 "미해결 결정"에 드는 것은 원격 반영 자동 여부의 판정 대상이기 때문이다.

## 대상 레포의 관례 — 어디에 적혀 있는가

**대상 레포의 규칙이 적힌 자리 목록은 여기가 단일 소유다.** 세션은 하네스 루트에 서고 서브에이전트도 그 CWD 를 물려받으므로, 대상 레포의 `CLAUDE.md`·규칙·스킬은 **어느 것도 자동으로 로드되지 않는다.** 필요한 자리에서 직접 읽는 수밖에 없다.

**네 자리다.** 그 레포의 워크트리 기준:

| 자리 | 무엇이 있나 |
|---|---|
| 루트 `CLAUDE.md` | 레포 전체에 걸리는 규율 |
| `.claude/CLAUDE.md` | 같음 — 레포마다 둘 중 어느 쪽에 두는지 다르다 |
| `.claude/rules` 디렉토리 아래의 `.md` **전부** (하위 디렉토리까지 재귀로) | 주제별 규칙 — 코드 스타일 · PR 절차 · 도메인 관례 |
| `.claude/skills` 디렉토리 아래의 `SKILL.md` **전부** | 그 레포의 절차. 설계·구현에 걸리는 관례가 규칙이 아니라 여기 적혀 있을 수 있다 |

- **파일 이름을 지목하지 않는다** — 레포마다 다르다. 자리만 정하고 이름은 읽어서 안다.
- **그 밖에 적힌 규칙은 없는 것으로 본다.** 목록을 닫지 않으면 탐색이 끝나지 않는다.
- **회상으로 대신하지 않는다.** 같은 레포를 앞 세션에서 읽었어도 다시 읽는다.
- **자리가 하나도 실재하지 않으면 관례가 없는 것이다.** 침묵은 금지가 아니다.
- **레포마다 따로 읽는다.** 스토리가 여러 레포를 물면 각각이다.
- **게이트 없음 — 설득뿐이다.** 읽었는지도, 읽고 따랐는지도 기계가 볼 수 없다.

**누가 언제 읽는지는 여기가 정하지 않는다.** 소유자가 든다 — `plan-story`(분해 전) · `implementer`·`reviewer`(작업·검토 전) · 아래 "사이클 종결"(push 전, 그중 push·PR 을 다루는 문장에 한해).

## 사이클 종결 — PR 이 종점이다

**사이클의 종점은 PR 생성이다.** 여기까지는 **그 사이클에 미해결 결정이 남지 않았을 때** 스스로 진행한다 — 남았는데 사용자 지시·승인이 없으면 1 까지만 하고 멈춘다(세션 컨텍스트 블록 "절대 금지" 의 예외 둘). 되돌릴 수 없는 것의 목록은 **세션 컨텍스트 블록 "절대 금지" 첫 항목이 단일 소유한다** — 전부 명시 지시 대상이다. 근거는 `harness-dmy`.

**세 단계이고 순서가 규율이다.** 대상 레포에는 하네스 git 훅을 심지 않으므로(스토리 `harness-lzs3` 결정) 커밋도 push 도 원장 검사를 대신 돌려 주지 않는다 — **원장 검사와 원장 반영은 오케스트레이터가 명시 단계로 돈다.**

1. **커밋, 그리고 원장 검사.** 그 브랜치의 작업을 커밋한다 — 커밋 게이트는 대상 레포의 것이다. 투영은 커밋 대상이 아니다: `scripts/board.sh all` 로 로컬만 맞춘다. 커밋 뒤 오케스트레이터가 워크트리에서 두 검사를 돌린다: `bash "${CLAUDE_PLUGIN_ROOT}/checks/board-check.sh"`(원장 구조) 와 `bash "${CLAUDE_PLUGIN_ROOT}/checks/ledger-check.sh"`(원장 반영 — **읽기 모드**, `LEDGER_CHECK_PUSH` 를 켜지 않는다. 통과 문구가 `앞서 있음(반영하지 않음 — 쓰기 모드 아님)` 이면 2 에서 올릴 것이 있다는 뜻이고 `확인됨` 이면 없다). 둘 중 하나라도 rc≠0 이면 종결 미완이다(실패표).
2. **원격 반영 — 둘이다. 작업 브랜치 push, 그 다음 `bd dolt push`.** 1 의 `board-check`·`ledger-check` 가 통과한 뒤에만 온다. 먼저 작업 브랜치를 push 하고(`git push -u origin worktree-<스토리ID>`, 근거는 `git ls-remote` 의 tip), 이어서 **`HARNESS_ROOT=<하네스루트> ledger.sh dolt push` 를 명시 실행한다** — 세션 컨텍스트 블록 "절대 금지" 의 예외 하나가 승인한 범위가 정확히 이 자리다: 대상 레포 push 가 지시인 순간, 그 승인 안에서 원장을 함께 올린다. 대상 레포에 pre-push 훅이 없으므로 이 명령을 빼면 원장은 로컬 유일본으로 남는다. 반영 뒤 `ledger-check` 를 읽기 모드로 한 번 더 돌려 `확인됨` 을 본다. **어느 쪽이 실패해도 3 으로 가지 않는다.**
3. **PR 생성과 상태 확인.** `gh pr create` 뒤에 `gh pr view --json url,state` 로 상태를 확인하고, url 을 스토리 bead 에 `ledger.sh note` 로 남긴다.

**대상 레포가 자기 push·PR 규칙을 가지면 그 규칙이 이 절의 자동 진행보다 앞선다.** 그래서 **1 을 마치고 2 로 가기 전에, 그 레포 워크트리의 관례를 직접 읽는다** — 자리 목록은 위 "대상 레포의 관례" 가 단일 소유하고, 이 절이 찾는 것은 그중 **push·PR 을 다루는 문장**뿐이다.

- 읽은 것이 push 나 PR 을 사람에게 묻게 하면 **1 까지만 하고 멈춘다** — 아래 실패표의 `1→2 관문` 행이다.
- **자리가 하나도 실재하지 않거나** 읽었는데 push·PR 을 다루는 문장이 없으면 **자동 종결을 그대로 진행한다.** 침묵은 금지가 아니다 — 이것이 기본값이다.
- **레포마다 따로 판정한다.** 한 레포가 묻게 해도 다른 레포의 종결은 간다(아래 "멀티 레포는 레포마다 PR 하나다" 와 같은 단위다).
- **게이트 없음 — 설득뿐이다.** 판정이 자연어 독해라 기계가 볼 수 없고, 오케스트레이터 세션에는 `guard.sh` 의 서브에이전트 규칙도 닿지 않는다. 근거는 `harness-wym.1`.

| 채널 | 커밋에 담는 것 |
|---|---|
| **계획** (`plan-sprint` 6 · `plan-story` 7) | 등록부(`sprints.json`·`rails.json`)의 변경만. 계획의 본체는 원장이라 커밋할 것이 없을 때가 정상이고, 그때 이 채널의 원격 반영은 `bd dolt push` 하나다 — `git push` 에 묶이지 않으므로 예외 하나 밖이고 명시 지시 대상이다 |
| **개발** (`develop` 4) | 그 브랜치의 작업 전부 |

**범위는 `repos.json` 등재 레포 전부다 — 등재가 곧 승인 표면이다.** 범위 밖: 워크트리의 `origin` 이 등재부의 `url` 과 다르면 멈추고 보고한다 · 명시 지시 대상 전부(위 문단이 가리킨 자리). **서브에이전트는 범위 밖이다** — 로컬 커밋까지이고, 종결은 오케스트레이터가 한다.

**PR 본문은 최소형이다.** 제목은 스토리 제목, 본문은 스토리 id 와 닫힌 태스크 목록. 대상 레포의 PR 규칙은 흉내 내지 않는다.

**실패는 rc 가 아니라 상태로 판정한다.**

| 단계 | 실패 | 판정 | 행동 |
|---|---|---|---|
| 1 커밋 | 커밋 게이트 rc≠0 | 종결 **미완** | 게이트 출력 전문을 `ledger.sh note`. 루프면 끊고 사람 대기 |
| 1 원장 검사 | `board-check`·`ledger-check`(읽기 모드) rc≠0 | 종결 **미완** | 검사 출력 전문을 스토리 bead 에 `ledger.sh note`. 2 로 가지 않는다 — 원장이 원격과 갈라진 채(계보 분기·한 번도 반영 안 됨) 올리면 자동 반영도 실패한다 |
| 1→2 관문 | 대상 레포의 규칙이 push·PR 을 사람에게 묻게 한다 | 종결 **미완** | 어느 레포의 어느 파일이 그렇게 적었는지를 스토리 bead 에 `ledger.sh note`. 2 로 가지 않는다 |
| 2 작업 브랜치 push | rc≠0 (인증 없음·원격 없음·대상 레포의 훅) | 종결 **미완** | 명령·rc·stderr 요지를 note. `bd dolt push` 로도 3 으로도 가지 않는다 — 원장은 아직 로컬이다 |
| 2 원장 push | `bd dolt push` rc≠0, 또는 rc=0 인데 `ledger-check` 가 `확인됨` 이 아니다 | 종결 **미완**. **작업 브랜치는 이미 나갔다** | 명령·rc·stderr 요지를 스토리 bead 에 `ledger.sh note`. 3 으로 가지 않는다 — PR 이 열리면 원장 없는 PR 이 되고, 이 머신이 죽으면 판정 근거가 사라진다. 사람 대기 |
| 3 PR | `create` rc≠0 **이지만** `view` 가 url 을 냄 | **완료** | url 을 note 에 남긴다 |
| 3 PR | `create` rc≠0 **이고** `view` 도 url 없음 | 종결 **미완** | 명령·rc·stderr 요지를 note. 사람 대기 |

- **닫힌 태스크를 다시 열지 않는다.** PR 은 스토리 종결의 산출물이다. 대신 **스토리를 닫지 않는다** — 종결 미완이 스토리 상태로 남아 다음 세션이 이어받는다.
- **멀티 레포는 레포마다 PR 하나다.** 일부 레포가 실패하면 그 레포만 미완으로 적는다.
- **새 신호를 만들지 않는다.** 종결 미완은 `develop` "장기 실행" 의 사람 대기 신호로 취급해 루프를 끊는다.
- **이 절이 종결 절차의 단일 소유다.** 세 스킬과 `docs/operations.md` 는 채널 고유 제약만 두고 이 절을 가리킨다.

## 멀티 레포

- 레포 목록과 각 레포의 게이트 명령은 루트 `repos.json` 이 원본이다. 언어·빌드 도구 정보는 이 파일 밖에 두지 않는다.
- **레포 등록과 클론은 `scripts/repo.sh add <url>` 이 함께 한다.** 클론 위치는 `~/.harness-workspace/<이름>` 으로 고정이며 `repos.json` 에 경로를 적지 않는다.
- 스토리 착수 시 그 레포의 클론에서 연 세션이 `EnterWorktree`(name=`<story-id>`)로 워크트리를 만든다: `~/.harness-workspace/<레포이름>/.claude/worktrees/<story-id>/`. 브랜치는 `worktree-<story-id>`(도구가 정한다 — 2절). 세션 단위는 (스토리, 레포)이므로 멀티 레포 스토리는 레포마다 세션 하나가 자기 클론에서 같은 절차를 돈다.
- **워크트리는 하네스 밖에 있다.** 위임 메시지에 하네스 루트 절대 경로를 명시한다 — `HARNESS_ROOT=<하네스루트>` 의 유일한 출처다.
- 워크트리 안의 에이전트는 매 턴 첫 행동으로 현재 경로를 확인한다. 본 체크아웃 경로인데 쓰기를 요구받으면 정지하고 사람에게 확인한다.

