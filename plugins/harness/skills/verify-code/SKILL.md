---
name: verify-code
description: Code-quality review procedure for a task's changes — reviewer delegation and the re-review loop. Use on a "이 커밋 리뷰해" request, and right after implementation lands in a develop cycle. Acceptance judgment is verify-implement.
---

# Code review

Before executing command notation in this procedure, read `${CLAUDE_PLUGIN_ROOT}/docs/commands.md` and resolve the plugin and harness roots.

The reviewer role definition (`${CLAUDE_PLUGIN_ROOT}/agents/reviewer.md`) holds the review discipline. This procedure holds delegation and signal handling only.

Standalone user-requested reviews use `docs/roles.md` "Standalone investigation
and review" and end with findings. The managed task procedure below is for
reviews whose result feeds task completion.

Before delegation and before reading its result, apply `${CLAUDE_PLUGIN_ROOT}/docs/roles.md` for execution-contract selection, independent child identity and result validation. Require native REACHED or generic OBSERVED under that contract before the branches below apply. That contract owns execution-path selection and explicit enforcement requirements; the SIGNAL and retry rules below hold in both paths.

## Verification path

Use combined verification for behavior-neutral edits and small, localized bug
fixes with a clear regression test and a reviewable diff, when the repository
does not require separate reviews. Use separate reviewer and evaluator calls for
permission or enforcement changes, data-loss or migration risks, incompatible
public contracts, broad dependency/runtime changes, and uncertain impact.
Record the risk grounds for the selected path; changing runtime behavior alone
does not require two graders.

For the combined path, call `verify-implement` with `combined verification` in the
delegation context instead of spawning a reviewer. The independent evaluator
applies its acceptance procedure and the reviewer checklist, returning MATCH only
when both pass. Record both quality and acceptance grounds; the evaluator's
validated MATCH is the combined review receipt. No separate reviewer result is
invented. A quality defect returns VIOLATION with its evidence. Rework repeats
this selected path and uses the verify-implement retry counter.

## 1. Delegate

Delegate to reviewer. The message carries ① first line: harness root absolute path + worktree absolute path + the commit range under review + **the task ID list** — in batch mode (`develop` section 3 holds the condition) every task in that milestone awaiting verification, outside it one ② what the `develop` skill's "위임 메시지의 환경 스냅샷" requires (the values to carry + the verbatim-quotation discipline) ③ claims in the implementer's report that reviewer must fact-check. That is the whole message — the discipline for receiving a list (one SIGNAL · attributing each finding to a task · relationships between changes across tasks) is held by `${CLAUDE_PLUGIN_ROOT}/agents/reviewer.md`, so leave it out of the delegation message.

## 2. Signal handling

- `LGTM` → upsert the receipt and NIT list with `ledger summary <unit ID> review --file <file>` and move on to verify-implement. In batch mode use the milestone and identify the tasks; outside batch mode use the task. The summary leaves `VERIFY_PENDING` standing. Promoting a NIT into a task goes through the convention gate in `plan-story` section 4.
- `CHANGES_REQUESTED` → upsert the findings with `ledger summary <unit ID> review --file <file>` → **read and raise the counter before re-delegating** → delegate the fix to implementer → reviewer re-reviews (**whether the earlier findings are resolved, and nothing else**). When the implementer signal returned from the fix delegation is something other than `IMPLEMENTATION_COMPLETE` (`IMPLEMENTATION_BLOCKED` · `DECISION_NEEDED` · outside the list), handle it through the branches in `develop` 3-4 instead of re-review.
  - **Reuse the independent reviewer for a bounded fix review**, following `docs/roles.md` for a new invocation and result. Use a fresh reviewer when the previous context is unavailable, the scope materially changes, or the reviewer contributed implementation changes.
  - Carry the corrected head and earlier finding references on a follow-up. A fresh reviewer needs the full context below:
    1. **The earlier findings verbatim** — leave them unsummarised. What was asked for is the control the re-review compares against
    2. **The commit range** — where the fix starts and where it ends
    3. **The implementer's resolution claims** — which finding they say they resolved and how. Those claims are what the re-review checks
  - The procedure for reading and raising the counter, the limits, and the unit in batch mode are held by "재시도 카운터" below. This stage's name is `verify-code`, and the line it leaves is `RETRY: verify-code <n+1>/<상한>`.
- `DECISION_NEEDED` or a value that is not in the list → safe exit: record the situation and report to the user.

## 재시도 카운터

The re-review / re-fix limit **counts only once it is recorded with `ledger state`.** Kept in memory it returns to 0 across session compaction and loop restarts.

- The stored format is `RETRY: <stage> <count>/<checkpoint>`. Use the initial checkpoints below for a new unit and retain any recorded extension when resuming.
- **The unit is the target of one verify pass** — the milestone in batch mode (`develop` section 3), the task outside it. Write `ledger state <unit ID> "RETRY: <단계> <n>/<상한>"` on that unit's bead and read it from that bead. One batch re-review is one count, whatever the number of tasks (`harness-2a5.4`).
- **Immediately before re-delegating**, read the last `RETRY:` line for that stage from the notes of `ledger show <unit ID>` to get `n`. Absent, it is 0.
- At the recorded checkpoint, compare the remaining failure with the previous attempt. If new evidence identifies a distinct correction, record that evidence and the next bounded attempt, advance the stored checkpoint, and continue. If the failure repeats without progress, a user decision is needed, or an explicit user budget is exhausted, record the reason and use human wait.
- Initial checkpoints: `verify-code` **2**, `verify-implement` **1**. These trigger a progress review, not automatic human escalation. An extension advances the checkpoint by one attempt and preserves the cumulative count. Explicit user limits override these defaults and are never extended without approval. Implementation gate retries use the same progress rule, recorded in the implementation summary.
- **`SCOPE_EXCESS` sits outside the counter.** It is a decision request about scope rather than a rework demand. What gets counted is rework caused by unmet acceptance.
- The counter ends when the unit (task or milestone) closes.

## Completion criteria

For separate verification, the state where the orchestrator has upserted the LGTM receipt and the NIT list with `ledger summary <unit ID> review --file <file>` — in batch mode once on the milestone bead (with the task list in the body), outside it on that task. Reach this state before moving on to verify-implement.

For combined verification, completion is the validated evaluator MATCH and both grounds recorded by verify-implement.
