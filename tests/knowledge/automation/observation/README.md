# S4 local observation

Read this evidence when judging the bounded local automation introduced at
`618de47ecb140123a2e4b72c5e6fd53949774867`. `evidence.json` preserves actual host
dispatches and raw receipts, project packets/completion records, source Git export,
public final state, timer/transition outputs, independent reader commands and checks.
Absolute paths identify the observed machine; they are not portable setup instructions.
Use the shipped automation reference to create a new project instead of relocating
these state files or editing SQLite paths.

The original S4 requirements and 15 scenarios were frozen before implementation.
`frozen.json` hashes `original-stage4.md` and `original-scenarios.json` (the latter
was originally named `scenarios.json`). The mapping below preserves every case.

| Original case | Evidence |
|---|---|
| normal-code | Actual code author/reviewer receipts, first completed document run |
| normal-goal | Actual implementer commit, mandatory check, independent implementation reviewer, author/document reviewer and second completion |
| duplicate | `post-complete-submit-0.json`; `test_code_duplicate_new_request_and_unchanged_effect`; concurrent duplicate regression |
| old-input | `test_out_of_order_and_late_response_preserve_newer_source`; `test_verified_goal_older_than_new_frontier_is_retained_without_apply` |
| new-request | `post-complete-submit-2.json`, distinct execution and unchanged artifacts |
| feedback | Actual timer-created code execution and explicit same-cause code request terminate unchanged; goal feedback regression |
| lost-response | `test_lost_response_reconciles_real_completed_command`, real public apply with injected lost response |
| failure-classes | Bounded transport/model, unknown outcome, malformed result and permission/service regression cases |
| policy-wait | Actual blocked document review, evidence resolution, same execution retry; independent reader rollback policy decision |
| authority | Authority and guard negative-control regression; reader's explicit local-only authority |
| periodic-gap | `quiet-pending-watch.json`: real timer detects the independently committed source without a supplied code event |
| periodic-drift | `test_drift_source_loss_and_pending_goal_are_distinct`; actual timer preserves pending goal |
| quiet | `quiet-stable-watch.json`, `final-quiet-watch.json`, exact artifact comparisons in `verification` |
| stop-resume | Actual `stop-resume.json` and reader commands; a pending actual model call was preserved across stop/resume |
| ownership | `test_ownership_external_edit_and_concurrent_duplicate`: competing state and concurrent processes; third-party bytes preserved |

Regression receipts explicitly identify `synthetic-fixture`. They establish local
state/CLI effects and injected failure behavior, not actual provider failures.
Actual host work produced eight accepted receipts (including one blocked review)
from independent actors. Nine provider child dispatches occurred: one additional
dispatch had a host prompt-copy error, was interrupted, and was never accepted.
Its exact incorrect prompt remains in `host_records`. This failure is not relabeled
as a successful call. Provider call IDs are not exposed by this tool; receipt
`call_id` values are coordinator correlation labels, while canonical returned
actor IDs and tool names preserve the available provider identity.

Receipt timestamps describe the coordinator's observed dispatch/result interval;
they are not provider execution latency or token accounting. The host recorded
dispatch observation immediately after tool return. Early commands precede source
hash instrumentation; later command records pin script hashes. The experiment ran
while the candidate evolved, preserving the original blocked result. Final public
state was inspected at the commit above, and its exact source passed the recorded
17 automation and 67 source-contract regression checks. The live claim is this
observed candidate sequence, not a clean first-attempt run of every final prompt.

The first attempted quiet window coincided with a real new source commit and its
no-notification assertion failed. The original output is retained. Subsequent
stable five-tick windows verify no model task, document rewrite or repeated alert.
The document review initially confused goal acceptance with document scope; the
candidate was repaired, actual implementation evidence was supplied, and a fresh
independent document review passed. No user policy choice was invented for that
ordinary evidence repair.

The independent reader used only shipped documentation and CLI help. Its raw
commands and report are embedded. It exercised initialization, unchanged input,
rollback question/keep-current, stop and resume; it did not author fake model data.

Observation boundary: macOS, local Git/SQLite/Python, live Codex host orchestration
and a bounded foreground timer. No installed-plugin activation, persistent service,
webhook, production schedule, remote publication, provider authentication outage,
database migration or deployment is established. Ownership covers cooperating
automation states on the same canonical document root, not arbitrary editors or
nested/network roots. The original source/runtime evidence remains under
`/private/tmp/stage4-work/s4-current/`; this file is not a managed final verdict.
