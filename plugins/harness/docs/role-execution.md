# Executing a role

Read this document before acting as implementer, reviewer or evaluator. It owns
the execution scope shared by ordinary requests and ledger-backed assignments.
Before using command notation, read [commands.md](commands.md).

## Select the assignment

Use the supplied outcome, repository, requirements and change scope. A native
role name selects a responsibility, not a story workflow or permission to write
to a ledger. A missing task ID, acceptance field, SIGNAL or audit receipt alone
does not block a clear request. Ask when the observable outcome, target or a
material scope decision is unclear; continue independent work where possible.

Use ledger-backed steps only when assigned a ledger task. Read its description,
acceptance and relevant notes with the explicitly supplied harness root. Missing
ledger coordinates block those calls, not work already defined by the request.
If a required ledger requirement cannot be read, report that limit and withhold
the dependent judgment. A clear requirement in the request or task description
can supply a missing acceptance field; state that interpretation. Conflicting
requirements or materially different outcomes require a decision.

Before any external API call or ledger write, establish the applicable user
authorization. A task reference or role registration is not that authorization.
Use [ledger-records.md](ledger-records.md) when recording authorized task results.
Task closure and remote delivery belong to the orchestrator.

## Confirm the target

Obtain the actual physical cwd (`pwd -P` on POSIX). From that directory, resolve
the Git top-level with `git rev-parse --show-toplevel`, then run
`workspace inspect <resolved top-level>`. Compare the canonical `top` with the
assigned path and check the Git common directory and expected branch. A nested
cwd is valid only when it resolves to that assigned repository/worktree.
Investigate a mismatch before touching or judging the target.

Implementation uses an assigned linked worktree (`linked: true`) and preserves
the main checkout. A standalone read-only review or evaluation may inspect the
specified main checkout. A ledger-backed development assignment uses its assigned
linked worktree. Filesystem aliases do not replace Git registration checks.

For judgment, identify the exact scope: fixed commits, staged changes, unstaged
changes, named untracked files, or an explicitly supplied combination. A dirty
tree is not itself a reason to stop. Inspect only the identified changes and
preserve unrelated work. If testing a commit requires a clean state but the
working tree differs, obtain evidence from the intended state or report that
verification as unavailable; never attribute dirty-tree test results to a commit.
If the target changes during judgment, recheck affected evidence before reporting.

## Evidence and completion

Read repository conventions using develop's "대상 레포의 관례" and apply the
required gate and relevant checks. Reuse evidence only under develop's
"상태 주장의 근거" in [develop](../skills/develop/SKILL.md). Inspect complete check
output and exit status; truncated output or another agent's assurance is not
proof. Report unexecuted checks and what passing checks do not establish.

Run independent tool calls together; sequence calls that depend on earlier
results. Keep changes and judgments within the authorized outcome. Necessary
supporting changes belong to that outcome; independently useful additions or
reversal of an explicit exclusion require a decision.

Return the outcome/findings, inspected commit or working diff, verification
evidence and limitations. Use the role's SIGNAL format when the caller requests
it or explicitly selects native auditing; ordinary findings need no first-line
marker. Explicit independence, permission and audit requirements remain binding.
When native audit is selected, read [transcripts.md](transcripts.md); an incomplete
audit stays unavailable even if the work has useful independently verified results.
