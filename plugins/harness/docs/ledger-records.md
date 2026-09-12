# Ledger names and records

## Names and hierarchy

The visible hierarchy is **스토리 → 마일스톤 → 태스크**. The stored types remain `epic` → `feature` → `task`; `decision` is a decision record. New issues use `[스토리] <purpose>`, `[마일스톤] <purpose>`, `[태스크] <purpose>` or `[결정] <question>`. The adapter replaces a recognized type prefix idempotently. Other types retain their supplied title because their naming semantics are not defined here. Bracketed domain prose is preserved.

Backlog is an unassigned story, not a type. Register the story body first; create children at pickup or explicit decomposition. Small steps without independent acceptance belong in a task checklist. Sprint IDs remain `YYYY-SNN` and assignment lives in labels/fields, so moving a story does not rename it. An optional sprint objective belongs in sprint documentation.

Existing titles and comments remain intact. For an existing-title migration, first produce an ID / current title / proposed title table for open issues and review it before applying changes; new creation does not trigger a bulk rename. A legacy title containing a sprint or an unfamiliar prefix needs individual review.

## Recording contract

| Information | Write | Behavior |
|---|---|---|
| Actor, delegation, verification phase, retry count | `ledger state <ID> <marker>` or `ledger state <ID> --file <file>` | Update execution state; no progress comment |
| Latest role result, evidence, integration or delivery result | `ledger summary <ID> <section> --file <file>` | Upsert that body section; no progress comment |
| Blocker, human decision request, judgment reversal | `ledger note <ID> --file <file>` | Append a durable event |
| Completion | `ledger close <ID> --reason-file <file>` | Leave the single completion comment |

State markers retain their grammar: `ACTOR: <repo> <actor>`, `DELEGATED: <milestone ID>`, `VERIFY_PENDING: <commit hash>` and `RETRY: <stage> <n>/<limit>`. Persist a retry before re-delegating. Delegation and verification update the same phase; changing a summary never clears it. `ledger show` exposes execution fields and compatible marker lines in notes; existing issues without state still read their last legacy markers. An old `ACTOR: <actor>` without a repo still requires `DECISION_NEEDED`, as specified by develop.

Summary section names are bounded slugs such as `implementation`, `review`, `acceptance`, `integration`, `delivery` and `completion`. Keep the latest result and evidence in the body, with durable links for lengthy logs. A reversal remains an append-only event quoting the superseded judgment and its reason, even when a summary is replaced. Preserve human-authored body text outside the harness sections.

A normal successful task ends with one completion comment containing the outcome, implementation/review/acceptance evidence and limitations. Update the acceptance summary before closing and pass the completion file to `close`; a separate completion `note` duplicates that record. Blockers and decisions may add event comments when they actually occur.

Create a body file before calling the ledger, following develop's “원장에 본문을 넘기는 형태”. Fixed marker strings without shell metacharacters may be passed inline. Implementers may write state, summaries and event notes for their assigned tasks; changing structure, claims and closure remains the orchestrator's responsibility.

## Storage and concurrency

The description contains one versioned managed block with structured execution state and named summaries. GitHub keeps acceptance separate from this block; Notion and beads retain their existing description storage. Malformed or duplicate blocks fail instead of being discarded. Existing exact machine `note` calls are routed to state for interrupted older sessions. JSON reads expose `execution`, `summaries` and original `events`, while `notes` supplies current marker lines for older consumers.

State/summary writes lock the item on the local host, re-read the body before writing and verify the result afterward. Repeating an unchanged record performs no write. GitHub and Notion do not provide an atomic body compare-and-swap here: another host can still race between the checks. A detected conflict fails; inspect the remote body before retrying. A lock left by a crashed process is retained for inspection rather than stolen by age.
