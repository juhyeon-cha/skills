---
name: verify-implement
description: Compare implementation with acceptance and close verified work. Use on an "acceptance 판정해" or "이 태스크 닫아도 되나" request and during implementation verification. Code-quality review is verify-code.
---

# Acceptance judgment

Before executing command notation, read `${CLAUDE_PLUGIN_ROOT}/docs/commands.md`.
`verify-code` owns verification path selection. Evaluator responsibility guidance
is `${CLAUDE_PLUGIN_ROOT}/roles/evaluator.md`; ordinary delegation follows
`${CLAUDE_PLUGIN_ROOT}/docs/roles.md`.

## 1. Compare the outcome

Compare each applicable requirement with the resulting files and behavior. Run
required checks and relevant tests, or reuse results whose tested inputs remain
unchanged under develop's "상태 주장의 근거". Record what the evidence does and does
not establish. A non-zero required check or unmet requirement keeps affected work
open; fix within scope and retry. Independent review can assess quality and
acceptance together, and does not need duplicate command execution.

When delegating, give the fixed diff, requirements, existing check results and
claims needing scrutiny. Inspect the actual response; meaningful evidence is
usable without a role receipt, inventory, first-line SIGNAL or whole-session audit.
Explicit user/project requirements for independence or managed auditing still apply.

## 2. Resolve findings

Correct unmet requirements and verify the affected behavior. Close independently
satisfied tasks without waiting for unrelated tasks. If acceptance wording is
stale but intent is clear, state the interpretation and evidence; a material
scope change needs the user's decision. Preserve approved deferrals separately.
Retry guidance is in verify-code's "재시도 카운터"; a missing counter does not block
correction. A response-format mismatch alone is not an acceptance failure.

## 3. Close

Close only when the applicable requirements are met. Respect approval boundaries
for external ledger writes. Use a completion file containing outcome, commit or
inspected diff, checks and limitations with `ledger close <ID> --reason-file <file>`.
An existing quality/acceptance summary can be reused or updated when useful; a
separate summary, phase marker or managed receipt is not a prerequisite for close.
Preserve actual decisions and reversals as events under `docs/ledger-records.md`.
Inspect the resulting ledger status before claiming closure. Redraw local
projections with `board all` when needed; they stay outside git.
