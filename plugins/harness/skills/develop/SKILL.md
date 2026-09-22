---
name: develop
description: Story (epic bead) development execution procedure. Use on a "스토리 시작/착수해" or "<스토리ID> 개발해" request, and while running the task implementation cycle. Implement and verify the authorized outcome in an isolated workspace.
---

# Story development

Before executing command notation, read `${CLAUDE_PLUGIN_ROOT}/docs/commands.md`
and resolve the plugin and harness roots.

## 1. Pickup verification

Read the requested story and relevant tasks through the adapter with explicit
`--root`. Confirm the target repository, requested outcome and dependencies.
Clarify an ambiguous outcome before implementing it; a missing procedural marker
or acceptance field alone does not invalidate a clear user request. Record the
agreed completion criteria when authorized to update the ledger.

The session unit is (story, repo). Keep each task's repository unambiguous. An
actual concurrent writer in the same worktree or a task held by another active
actor blocks conflicting work; continue independent work where possible.

## 원장 기록

Use `${CLAUDE_PLUGIN_ROOT}/docs/ledger-records.md` for adapter record formats.
Record the outcome, commit or inspected diff, checks and limitations. Progress,
retry and execution-inventory records are optional resume aids, not prerequisites
for implementation, review or acceptance.

### ACTOR state — `ACTOR: <레포> <값>`

When using ledger claims, use a session actor (`sess-` plus six random characters)
and associate it with the repository. Claim with `ledger update <task ID> --claim
--actor <literal actor>`. Read the claim's own result; on GitHub use its `actor`
field, not the GitHub assignee login. An existing assignee alone is not a claim.
Confirm ownership before resuming; do not reclaim another actor's live work.
An old actor marker without a repository needs investigation only when ownership
is ambiguous. Optional runtime actor binding follows `docs/state.md`.

## 2. Create the workspace

Read `${CLAUDE_PLUGIN_ROOT}/docs/workspace.md` when creating, resuming or cleaning
an assigned linked worktree. Inspect its canonical path, branch and Git common
directory before writing. Preserve the main checkout. Use the repository's
preparation procedure when the changed behavior needs it, and resolve actual
preparation failures before dependent implementation or tests.

## Design premises during implementation

Use the agreed design and any M0 findings as the baseline. When observations
contradict a premise, record the affected input or interface. Resolve a material
scope decision with the user while continuing unaffected work. Select checks for
the changed behavior and the repository's required gate; report untested scope.

## 3. Task cycle

Choose a coherent task or milestone scope, following dependencies. Batch related
single-repository tasks when their changes can be reviewed together; split them
when separate contexts or repository ownership make that clearer. The unit is a
reviewable outcome, not a mandatory sequence of role invocations.

1. Implement locally or delegate a bounded implementation responsibility. Give a
   worker the assigned worktree and relevant requirements. Keep concurrent writers
   out of the same worktree's staging area.
2. Inspect the resulting diff and run checks for the changed behavior. Apply
   `verify-code` to select local or independent verification by risk. Quality and
   acceptance may be checked together; no implementer → reviewer → evaluator
   chain is required by default.
3. Correct concrete failures within scope and verify the correction. Interpret
   an actual response by its findings and inspected scope. Missing SIGNAL text,
   receipts or progress markers do not make a useful review invalid.
4. Apply `verify-implement` to compare the outcome with requirements and close
   accepted tasks when ledger writes are authorized. Preserve unresolved work and
   its reason; a blocked task does not prevent unrelated work.

Ordinary delegation follows `${CLAUDE_PLUGIN_ROOT}/docs/roles.md`. Use the native
audit procedure in `docs/transcripts.md` only when explicitly selected for its
audit purpose. Its strict validators govern claims about native invocation.

## 4. 스토리 마무리

Inspect the final state and verify affected cross-repository contracts where the
story spans repositories. Summarize delivered changes, commits, checks and limits.
Close only outcomes actually achieved; identify approved deferrals and unresolved
work separately. Keep delivery status truthful when a PR or approval remains.

Follow "사이클 종결" for authorized remote delivery. Redraw ledger projections with
`board all` when needed; they remain outside git. Worktree cleanup requires user
instruction after merge confirmation and follows `docs/workspace.md`.

## 위임 메시지의 환경 스냅샷

Give the harness root and assigned worktree, responsibility, task requirements,
applicable instruction paths, and fixed base/head or identified working diff.
Include dirty-tree information and relevant test results when they affect the
work. Distinguish previous reports' claims from observations. Keep enough context
to perform the bounded task without copying unrelated conversation history.

## 장기 실행

Start a recurring loop or enable Stop continuation only on explicit user request.
The session-scoped controls are in `${CLAUDE_PLUGIN_ROOT}/docs/state.md`. Default
Stop performs no ledger polling or Stop-log writing. Open work alone does not
authorize continuation. Resume from actual files and the latest useful record;
phase markers and retry counters may help but are not a required state machine.
Respect user budgets and stop on a decision requiring the user. Do not rearm a
loop while that decision remains unresolved.

# Always-on rules owned here

## 운영 규율

- Make completion observable through the resulting files, behavior or relevant
  checks. Failed required tests and unmet requirements block completion.
- Select verification by risk using `verify-code`; record the outcome through
  `verify-implement`. Role identity is not a substitute for review quality.
- Preserve protected paths, actual writer ownership and user approval boundaries.
- Ledger diagnostics describe the records they inspect. Missing phase markers,
  retry counts or unrelated structural findings do not block implementation or PR
  delivery. Resolve a finding when it prevents safe task identification or proves
  a conflict affecting the current work.
- Generated `docs/sprints/`, `docs/backlog/` and `docs/adr/` projections are outside
  git; edit their ledger source and regenerate instead of editing projections.

## 원장에 본문을 넘기는 형태

**A body handed to the ledger (`ledger`) — state·summary·note·description·acceptance·close reason — never sits inside a shell command string.** The shell interprets the body before ledger does and erases identifiers wrapped in backticks or `$` into empty strings, while ledger exits 0.

- **Use the adapter's file options** — `note --file`, `create`/`update --body-file` and `--acceptance-file`, `create`/`init --title-file`, `close --reason-file`, or the stdin forms shown by `ledger --help`. The common frontend reads these files and passes literal values to every backend. Use the runtime's stdin facility for `dep add --file -`; create its JSONL with a file tool first. No shell command substitution is required.
- **A one-line fixed string with no backtick and no `$` may go inline** — `RETRY: <단계> <n>/<상한>`·`ACTOR: <레포> <값>`.
- **Make the body file in a call other than the ledger call.** The file-writing tool (Write·Edit) is simplest — the body leaves the command string, so every rule that looks at command strings loses its material. Made with a heredoc in the same call, the body is inside the command string again.
- **No heredoc as a ledger argument.** Nothing gets damaged, but the whole body is scanned as a command string, other rules fire on the body's words, and passing them means distorting what gets recorded.
- **Getting past a block by editing the body is forbidden at every stage.** What may change is the form (splitting the call) and the tool (file writing). When both are spent and it is still blocked, do not edit the body — **write into the report that it was blocked.**
- Gate: **none — discipline only.** The guard keeps only invariants independent of any tree anchor, and this discipline is outside them. `$VAR` is the same — `$` outside bodies is so common that putting it in the verdict would let false positives drown the discipline.

> Evidence: `harness-xwd` · `harness-dg0.6.36` · `harness-dg0.6.19` · `harness-dg0.6.14`.

## 상태 주장의 근거

Inspect the state that supports each claim. A check establishes only its exercised
boundary; its exit code does not establish runtime loading, permissions or unmet
requirements outside that boundary. Record the command, result, relevant commit
or diff and limitations. Reuse a result when its tested inputs remain unchanged;
rerun when changes or failures make that evidence stale. A copied commit-message
claim alone is not fresh evidence.

Confirm remote and ledger operations from resulting state when claiming they
succeeded. If a result cannot be confirmed, say so. Read-only ledger diagnostics
remain diagnostic; state-changing checks require the same authorization as their
underlying action. `ledger-check` reflects only with explicit `--push` (or its
legacy switch), and an ahead-without-reflection result is not remote equality.

## 결정 상태 — 안 하기로 한 것은 남은 일이 아니다

An item the user explicitly closed with "안 한다 / 지금 말자" is **a third state, neither done nor undone**. In beads it is `deferred` — `ledger update <ID> --status deferred`. In closing conditions it ranks with closed·blocked.

- **Exclude** it from remaining work, completion criteria, and report lists. It does not block a completion verdict.
- When circumstances change and it looks needed again, **ask in one line.** Do not persuade.
- Keep what was passed over in silence apart from what was closed explicitly. When unclear, ask once.
- **The beads backend counts `deferred` as an open child or blocker.** Closing needs a bypass: `ledger close <ID> --force` for the parent, `ledger dep remove` for the dependency. Leave the reason for the bypass in the close reason or a note.

## 진단 가설 규율

Applies when diagnosing a cause and proposing an action. Not to plain observations.

- **Before verification, write "hypothesis".** Not "the cause is X" but "hypothesis: X — verifiable by <this>".
- **Confirm equivalence before using a control.** Confirm that the conditions (settings · cache · path · version) are the same, or state that they were not confirmed.
- **Continue diagnosis while each attempt produces new evidence or eliminates a distinct cause.** Record the hypothesis and result. Stop when the same failure repeats without new evidence, the next step needs a user decision, or an explicit user budget is reached. Repeating the same command is not a new diagnostic attempt.

## 사람 대기 — 어떤 신호가 사람에게 가는가

Wait when a decision or authorization is actually required: ambiguous scope,
accepted scope changes, unavailable explicitly required permissions or runtime,
a conflicting live writer, or retry progress exhausted or explicit user budget reached.
Describe the concrete question and continue independent authorized work if any.

Legacy role responses may label such conditions `DECISION_NEEDED`, `DEVIATION` or
`SCOPE_EXCESS`; examine the substance. A missing or unfamiliar SIGNAL, failed
optional audit, unavailable optional role or absent ledger marker alone is not a
reason to ask the user. Preserve an unsuccessful managed attempt as unsuccessful;
ordinary verification may still proceed unless the user required that contract.
A blocked item remains unresolved without forcing all other work to stop.

## 대상 레포의 관례 — 어디에 적혀 있는가

**The list of places where a target repo's rules are written is single-owned here.** Roles run as subagents in the story worktree, each with its own context — **read the applicable repository instructions directly**, including when the runtime did not inject them.

These entrypoints are relative to that repo's worktree:

| Place | What is there |
|---|---|
| root `AGENTS.md`, and `AGENTS.md` in ancestors of the files being worked on | shared and path-scoped repository rules; follow their explicit references to shared policy documents |
| root `CLAUDE.md` | rules that apply to the whole repo |
| `CLAUDE.md` inside the `.claude` directory | the same — which of the two a repo uses varies |
| **every** `.md` under the `.claude/rules` directory (recursively, subdirectories included) | rules by topic — code style · PR procedure · domain conventions |
| applicable `SKILL.md` under `.claude/skills` | use the skill catalog or frontmatter to select procedures matching this task or an explicit instruction; read those bodies |
| applicable `SKILL.md` under `.agents/skills` | select by task or explicit instruction; read a shared canonical body once |

- **Do not name file names** — they differ per repo. Fix the places only; learn the names by reading.
- **Follow explicit policy references from these entrypoints**, preserving their scope; stop cycles by canonical path. A directory named `.agents` or a `skills.json` file by itself is not proof that either runtime loaded its contents.
- **Keep shared bodies in their repository-owned location.** References may reach the same policy or skill from both runtimes; inspect the canonical source once and do not register it twice. A missing entrypoint is reported, not repaired by silently copying policy.
- **Use current rules.** Reuse a source already read in this session while it is unchanged; read it again after a relevant edit or when resuming without its contents.
- **When none of the places exists, there is no convention.** Silence is not a prohibition.
- **Read per repo.** When a story involves several repos, each one.
- **No gate — persuasion only.** Neither whether it was read nor whether it was followed can be seen by a machine.

**Who reads it when is not decided here.** The owners hold it — `plan-story` (before breakdown) · `implementer`·`reviewer` (before work and review) · "사이클 종결" below (before push, limited to the sentences that deal with push·PR).

## 사이클 종결 — PR 이 종점이다

For an authorized development cycle, prepare the implementation and verification
for review before remote delivery. Standalone investigation ends at its findings.
The session context's remote-approval boundary and the target repository's own
push/PR rules apply; read those rules before delivery. Missing procedural records
do not create a new approval requirement or remove an existing one.

1. Inspect and commit the authorized changes after the required repository gate
   passes. Report actual unresolved requirements. Ledger/board diagnostics can
   identify follow-up maintenance; their unrelated failures do not block the PR.
2. When authorized under the applicable rules, push the working branch to this
   repository's origin and verify the remote tip. Reflect the ledger through the
   adapter where applicable (`beads`: `ledger sync-check --push`; GitHub/Notion
   already store writes remotely). Record a failed ledger reflection separately;
   it does not invalidate verified code or prevent a useful PR unless that
   reflection is an explicit delivery requirement.
3. Create (`gh pr create`) or update the PR with the concrete change, verification and limitations,
   following the repository's PR conventions. Verify its URL and state. Record
   delivery in the ledger when authorized.

These are delivery dependencies, not mandatory ceremonial stages. A failed test
needs correction; a failed push needs recovery before claiming remote delivery;
a missing approval needs the user's decision. Fix recoverable failures within
scope and report unresolved ones. Keep completed task results; do not reopen them
merely because delivery remains pending. A multi-repository story can deliver
verified repositories while reporting another repository's unresolved delivery.

Planning-only changes live in the ledger and require no code PR. Their remote
writes remain subject to the session context's approval rules.
Subagents are out of scope — up to the local commit; remote delivery belongs to
the orchestrator or human. Cleanup follows section 4 and requires user instruction.

## 멀티 레포

- **There is no repo registry.** A story's `repo:<name>` labels name the repos; each of them carries its own `.harness.json` with the same `ledger` object, and **that file also owns the gate command, the default branch and the bootstrap** — language and build-tool knowledge lives nowhere else. The harness does not know where those clones are, so **a person opens the session in the one they work on.**
- At story pickup, each repository session creates or resumes its workspace through section 2. Retain the returned Git-registered path and branch. The session unit is (story, repo), so each repository runs that same procedure independently.
- **Carry the harness root explicitly.** State its absolute path in the delegation message and use it for every ledger `--root`, independently of the worker's cwd.
- An agent inside a worktree confirms the current path as the first action of every turn. When asked to write while on a main-checkout path, it stops and checks with a human.
