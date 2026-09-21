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
| old-input | Initial code-order checks passed, but goal `2`→`1` failed independent acceptance at `59cee02`. Corrective goal ordering/atomic-intake/terminal-history regression in `acceptance-fixes.json`; Final independent judgment: MET (see the outcome below). |
| new-request | `post-complete-submit-2.json`, distinct execution and unchanged artifacts |
| feedback | Initial actual timer terminated unchanged but lost its originating cause (independent acceptance failure). Corrective receipt-bound poll link before checks, no duplicate work, unrelated-source regression in `acceptance-fixes.json`; Final independent judgment: MET (see the outcome below). |
| lost-response | `test_lost_response_reconciles_real_completed_command`, real public apply with injected lost response |
| failure-classes | Bounded transport/model, unknown outcome, malformed result and permission/service regression cases |
| policy-wait | Actual blocked document review, evidence resolution, same execution retry; independent reader rollback policy decision |
| authority | Authority and guard negative-control regression; reader's explicit local-only authority |
| periodic-gap | `quiet-pending-watch.json`: real timer detects the independently committed source without a supplied code event |
| periodic-drift | Initial single-tick drift evidence was insufficient and baseline drift was unchecked. Corrective four-tick real watch observes external public-CLI baseline change, document drift, missing source and approved pending goal; `acceptance-fixes.json` preserves outputs and hashes. Final independent judgment: MET (see the outcome below). |
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

## Subsequent independent review fixes

Independent review of `0ed49e7f82d2061e6b3c2cc2c700b8b9fe9e2f81` found two additional
supersession failures: replacement of a still-pending implementer and repeated termination
after a successful public terminate lost its response. `review-fixes.json` preserves the
reviewer's reproduction output and subsequent regression/negative-control outputs. These
are local fixtures with synthetic host receipts and real public CLI effects, not new live
model observations. The original `evidence.json` remains unchanged. The later independent outcome is recorded below; this addendum remains implementation evidence.

## Acceptance corrections after `59cee02`

Independent acceptance reported VIOLATION: goal versions could regress by arrival order,
poll feedback lacked its originating execution/cause, and repeated drift evidence was incomplete.
`acceptance-fixes.json` retains that judgment, failing old-source outputs, corrective fixture
commands/effects and regression results. This is implementation evidence awaiting independent
re-evaluation at that point; the later independent outcome is recorded below. Every original case remains mapped above; unaffected cases
retain their previously observed boundary, while old-input, feedback and periodic-drift explicitly
record the initial failure or missing evidence and the corrective observation.

The drift experiment uses an external direct public CLI caller (`start`, `prepare`, `review`,
`resume`) to move the baseline, then external document editing and a tracked-source rename. This
models an external writer outside automation ownership; it performs no database editing/migration.
Four actual timer ticks distinguish baseline/document/source/pending-goal findings. The subsequent
three ticks have no repeated alerts and preserve project/document hashes, the approved goal,
pending task and task/model counts. Receipts and direct review JSON in this experiment are synthetic.
Repeated automation status output is explicitly projected with its raw-output hash; the original
raw command capture remains at the path recorded in the evidence. Original actual-model receipts,
interrupted dispatch and earlier failed observations in `evidence.json` remain unchanged.

## Actual receipt feedback after acceptance repair

Read `final-feedback.json` to verify the final repair against the existing actual
model history at `159ccfd0dd7c405340eb8540640df00fb463a302`. Five watch ticks linked
the exact implementation commit to `live-goal-cause-1` and its goal execution.
The original poll input, eight receipts, five completed executions and document/project
artifact hashes remained unchanged. Only the causal observation was added; no new
model call or implementation verification is claimed. All five ticks emitted no
notifications. This supplements, rather than rewrites, the earlier failed cause-link evidence.

## Independent outcome

At `566d46e83019d1dde4c2808871d4a5e7911aa7c9`, a separate full reviewer returned
LGTM (`s4-review-3`) and an independent evaluator returned MATCH (`s4-evaluation-2`).
All 15 original cases were MET within the documented local boundary. The evaluator
compared original hashes, actual actor/receipt links, repeated timer outputs and
artifact preservation directly. The parent retained the complete responses and
validated OBSERVED results in the managed invocation inventory; [task #374](https://github.com/juhyeon-cha/skills/issues/374)
holds the acceptance and review summaries. This outcome does not replace the
initial failures, synthetic-fixture labels, or unverified service boundaries above.
