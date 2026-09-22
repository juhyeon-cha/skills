---
name: verify-code
description: Review a task's code quality and select verification by risk. Use on a "이 커밋 리뷰해" request and while verifying implementation. Acceptance and task closure use verify-implement.
---

# Code review

Before executing command notation, read `${CLAUDE_PLUGIN_ROOT}/docs/commands.md`.
The reviewer responsibility guidance is `${CLAUDE_PLUGIN_ROOT}/roles/reviewer.md`.
Ordinary delegation and optional managed execution are owned by `docs/roles.md`.

## Verification path

Select checks by the changed behavior, impact and explicit project/user rules.
Use local inspection and relevant tests when they can assess the change reliably.
Use an independent reviewer when a fresh assessment would reduce a concrete risk,
such as permission changes, data-loss risk, migration or uncertain interactions.
One independent assessment can cover both quality and acceptance. Separate review
and evaluation only when explicitly required or when their distinct perspectives
address a concrete gap; explain that reason in the result.

A required independent reviewer must not be an implementation author. If a chosen
optional mechanism is unavailable, choose another adequate path. Preserve an
explicit independence or permission requirement rather than silently weakening it.

## Review and correction

Inspect a fixed commit range or an identified working diff and its affected
callers. Run the required repository gate and relevant checks, reusing unchanged
results under develop's "상태 주장의 근거". For delegation, provide responsibility,
requirements, scope and applicable rules using develop's environment snapshot.
Use the actual returned findings and inspected scope; a SIGNAL, receipt, execution
inventory or audit result is not a default prerequisite for accepting the review.

Fix actionable findings within scope and inspect the correction. Reuse a reviewer
for a bounded follow-up when its context remains useful; use a fresh reviewer
when the scope changes materially or the reviewer contributed implementation.
A follow-up covers the fix and affected behavior, including any new regressions.

## 재시도 카운터

Optional `RETRY: <stage> <count>/<checkpoint>` records help resume long work.
Their absence or a checkpoint is not a stop condition. Continue while an attempt
produces new evidence or a distinct correction; reassess when the same failure
repeats without progress. Explicit user budgets remain binding. When recording
retries, keep the cumulative count on the reviewed task or milestone and retain
prior failure evidence. No record write is required before the next useful fix.

## Completion criteria

Finish with actionable findings or the grounds for finding none, the inspected
commit/diff, checks and limitations. A standalone review ends there. For task
completion, apply verify-implement to the same evidence; a combined quality and
acceptance assessment does not require a second grader or duplicate tests.
