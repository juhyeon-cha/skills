---
name: verify-implement
description: Acceptance judgment and closing procedure for a task — evaluator delegation and ledger close. Use on a "acceptance 판정해" or "이 태스크 닫아도 되나" request, and right after review passes in a develop cycle. Code-quality review is verify-code.
---

# Acceptance judgment

The evaluator role definition (`${CLAUDE_PLUGIN_ROOT}/agents/evaluator.md`) holds the judgment discipline. This procedure holds delegation, signal handling, and closing only.

## 1. Delegate

**Run the acceptance items that carry a judging command first, before delegating.** When an acceptance item names a command (`plan-story` section 3 requires it), the orchestrator runs that command and judges by its exit code — per task when given a list. Commands that do not reference each other go out in one response.

- **Except when that command and its rc are already in the target commit message** (`implementer.md` 7 leaves them). Acceptance items often match the repo gate command — running it again here makes it implementer 1× plus here 1×, restoring the double execution that `evaluator.md` 4 removed.
  - **Which gates that skip covers is decided by the two-class table in `harness:develop` "상태 주장의 근거"** — it stays unrestated here. The ones compared against the world outside the tree (`board-check`) **run at this spot, immediately before delegating.**

Then delegate to evaluator. The message carries ① first line: harness root absolute path + worktree absolute path + **the task ID list** — in batch mode (`develop` section 3 holds the condition) every verify-code-passed task awaiting judgment, outside it one ② what the `develop` skill's "위임 메시지의 환경 스냅샷" requires (the values to carry + the verbatim-quotation discipline) ③ **the items already judged by command and their exit codes** (per task) ④ the items with no command — these are what evaluator judges ⑤ claims from the previous stage's report that evaluator must re-verify. The discipline for receiving a list (one SIGNAL · evaluator writes MATCH/unmet per task in the body) is held by `${CLAUDE_PLUGIN_ROOT}/agents/evaluator.md`, so leave it out of the delegation message.

- **Always delegate to evaluator when a session can delegate.** That holds even when commands cover every item — **a single verification signal cannot tell apart what lies outside what that signal sees.** Hunk attribution in the diff (whether anything unasked-for was done) and whether the acceptance wording has gone stale are invisible to every command, and those two are why `evaluator.md` exists. A session that cannot delegate judges for itself, and writes that fact into the grounds — the discipline is `harness:develop` "운영 규율".
- A non-zero command judgment is unmet on its own. Handle it as `VIOLATION` without delegating — evaluator would return the same answer.

## 2. Signal handling

- `MATCH` → go to 3 below. **When the acceptance wording has gone stale, judge by its intent and leave that substitution in `close_reason`.** A sibling task closing first can change the premise, at which point holding to the wording means writing a false sentence. Recording what you judged against in place of the wording is what keeps "why did this close when what it asked for is missing" from recurring.
- `VIOLATION` → **read and raise the counter before re-delegating** → delegate the fix to implementer → re-enter verify-code. Given a list, close the `MATCH` tasks through 3 below as the per-task judgments in the body say, and send only the unmet tasks back for a fix. When the implementer signal returned from the fix delegation is something other than `IMPLEMENTATION_COMPLETE` (`IMPLEMENTATION_BLOCKED` · `DECISION_NEEDED` · outside the list), handle it through the branches in `develop` 3-4 instead of re-entering.
  - Read the number on the last `RETRY: verify-implement` line from the notes of `ledger.sh show <task ID>` (0 when absent).
  - Once `n+1` puts the counter at **limit exceeded** (single-owned by the "재시도 카운터" section of the `verify-code` skill), switch to human wait in place of re-delegating.
  - On re-delegation leave `ledger.sh note <task ID> "RETRY: verify-implement <n+1>/<상한>"`.
  - **In batch mode put the milestone ID in the `<task ID>` slot of the two lines above** — re-judgment happens once per batch, so the counter is one per batch too. The unit is defined in the "재시도 카운터" section of the `verify-code` skill.
- `SCOPE_EXCESS` → report to the user and wait. **It spends no re-judgment count** — the "재시도 카운터" section of the `verify-code` skill holds the reason.
  - The report carries evaluator's **hunk list and classification** (excess / intrusion), and for an intrusion the `deferred` item or Out of Scope sentence it rests on, copied verbatim. Leave it unsummarised — that original text is what the human judges.
  - When the user directs **separate then accept**: register the excess as its own bead, revert those changes, and judge again. This re-judgment is also outside the counter.
  - When the user directs **accept as is**, go to 3 below. Write the accepted excess into `close_reason` — without it the next person reads that code as something that was asked for.
- `DEVIATION` · `DECISION_NEEDED` or a value that is not in the list → report to the user and wait.

## 3. Close

**`ledger.sh close` runs on evaluator's MATCH record alone.** Given a list, do 1–2 per MATCH task and 3 once.

1. Leave the grounds for the MATCH judgment with `ledger.sh note <task ID>`.
2. `ledger.sh close <task ID> --reason "<commit hash, gate exit code>"`.
3. Redraw the local projection with `scripts/board.sh all` — **after** `ledger.sh close`. The projection lives outside git, so it stays out of the commit.
