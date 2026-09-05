---
name: verify-code
description: Code-quality review procedure for a task's changes — reviewer delegation and the re-review loop. Use on a "이 커밋 리뷰해" request, and right after implementation lands in a develop cycle. Acceptance judgment is verify-implement.
---

# Code review

The reviewer role definition (`${CLAUDE_PLUGIN_ROOT}/agents/reviewer.md`) holds the review discipline. This procedure holds delegation and signal handling only.

## 1. Delegate

Delegate to reviewer. The message carries ① first line: harness root absolute path + worktree absolute path + the commit range under review + **the task ID list** — in batch mode (`develop` section 3 holds the condition) every task in that milestone awaiting verification, outside it one ② what the `develop` skill's "위임 메시지의 환경 스냅샷" requires (the values to carry + the verbatim-quotation discipline) ③ claims in the implementer's report that reviewer must fact-check. That is the whole message — the discipline for receiving a list (one SIGNAL · attributing each finding to a task · relationships between changes across tasks) is held by `${CLAUDE_PLUGIN_ROOT}/agents/reviewer.md`, so leave it out of the delegation message.

## 2. Signal handling

- `LGTM` → record the receipt and the NIT list with `ledger.sh note` and move on to the verify-implement procedure. **In batch mode write it once on the milestone bead** and **leave the task notes untouched** — the stop guard passes a task only while its last note is `VERIFY_PENDING`, and a NIT appended per task releases that marker, so the guard blocks when the turn ends before close. Outside batch mode write it on that task. Promoting a NIT into a task goes through the convention gate in `plan-story` section 4.
- `CHANGES_REQUESTED` → record the findings with `ledger.sh note` → **read and raise the counter before re-delegating** → delegate the fix to implementer → reviewer re-reviews (**whether the earlier findings are resolved, and nothing else**). When the implementer signal returned from the fix delegation is something other than `IMPLEMENTATION_COMPLETE` (`IMPLEMENTATION_BLOCKED` · `DECISION_NEEDED` · outside the list), handle it through the branches in `develop` 3-4 instead of re-review.
  - **Re-review runs on a fresh reviewer instance.** The instance that raised the findings is done.
  - **In exchange the re-review delegation message is written thick — this is the explicit exception to the thin-delegation discipline (`develop` section 3).** A fresh instance regathers its context, and the delegation message pays that rediscovery cost in its place. Carry three things:
    1. **The earlier findings verbatim** — leave them unsummarised. What was asked for is the control the re-review compares against
    2. **The commit range** — where the fix starts and where it ends
    3. **The implementer's resolution claims** — which finding they say they resolved and how. Those claims are what the re-review checks
  - The procedure for reading and raising the counter, the limits, and the unit in batch mode are held by "재시도 카운터" below. This stage's name is `verify-code`, and the line it leaves is `RETRY: verify-code <n+1>/<상한>`.
- `DECISION_NEEDED` or a value that is not in the list → safe exit: record the situation and report to the user.

## 재시도 카운터

The re-review / re-fix limit **counts only once it is recorded with `ledger.sh note`.** Kept in memory it returns to 0 across session compaction and loop restarts.

- The format is one fixed line: `RETRY: <단계> <n>/<상한>`. Put the values below in the `<상한>` slot verbatim.
- **The unit is the target of one verify pass** — the milestone in batch mode (`develop` section 3), the task outside it. Leave `RETRY:` on that unit's bead and read it from that bead. One batch re-review is one count, whatever the number of tasks (`harness-2a5.4`).
- **Immediately before re-delegating**, read the last `RETRY:` line for that stage from the notes of `ledger.sh show <unit ID>` to get `n`. Absent, it is 0.
- Once `n+1` puts the counter at **limit exceeded**, stop re-delegating — switch to human wait and leave the reason with `ledger.sh note`.
- Limits: `verify-code` re-review **2**, `verify-implement` re-judgment **1**. The implementer's own gate retries (up to 3) stay out of this record. Raising a limit takes a case where a third round was actually needed (`harness-yty`).
- **`SCOPE_EXCESS` sits outside the counter.** It is a decision request about scope rather than a rework demand. What gets counted is rework caused by unmet acceptance.
- The counter ends when the unit (task or milestone) closes.

## Completion criteria

The state where the orchestrator has left the LGTM receipt and the NIT list with `ledger.sh note` — in batch mode once on the milestone bead (with the task list in the body), outside it on that task. Reach this state before moving on to verify-implement.
