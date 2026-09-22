# Recorded multi-repository observations

Read this archive when judging original S5-01 through S5-06 or checking claims in
the [human report](../../../../docs/initiatives/code-driven-knowledge/experiments/multi-repo-observation.md).
`original-stage5.md`, `frozen-plan.json`, `freeze-hashes.json`, and
`comparison-protocol.json` retain the M0 requirements and prospective criteria.
M0 remains historical evidence; `live/` records the subsequent full experiment.

Run `bash tests/knowledge/multi-repo-observation-check.sh` from the repository root.
It validates recorded bytes, content-addressed objects, script identities,
checkpoint correspondence, actual host receipt relationships and observed state
invariants. It does not replay provider calls or establish new semantic judgments.
The development suite discovers the wrapper under `tests/` automatically.

`live/manifest.json` lists every archived file, its original observed path, byte
size and SHA-256. Original bytes were copied without path rewriting. Absolute paths
describe the observed machine; they are not portable setup instructions. SQLite
databases, Git internals, locks and bytecode are omitted. Public state outputs,
intakes, packets, immutable relation objects, source bundles and snapshots preserve
the evidence used here. A fresh project should follow the shipped setup contract;
do not relocate these state files and treat them as a new execution.

| Claim | Recorded evidence under `live/` |
|---|---|
| Frozen questions and same checkpoints | `comparison-checkpoints.json`, its digest, `checkpoints/Q1` through `Q6` |
| Code-first and document-first completion | Each flow's `*-checks-output.json`, `*-attest-input.json`, `complete-query-output.json`, `complete-wiki-output.json` |
| Actual document and implementation semantics | `producer-doc-review-*`, `consumer-doc-review-*`, `partial-review-*`, `full-review-*` |
| Code/document/user origin and correction | `origins.json`, each flow's `prediction-*-input.json`, `comparison-*-input.json`, project intake records |
| Partial permission, missing source, stale index, withdrawal | `checkpoints/Q4` through `Q6`, code-first `source-unavailable-*`, `source-restored-*`, `withdrawal-*` |
| Independent comparison | `comparison-{baseline,candidate}-reader-*`, `comparison-grader-*` |
| Local invocation, timing, observed runtime | `commands.jsonl`, setup/init/origin traces, `environment.json`, `runtime-source/identity.json`, `validation-scope.json` |
| Source history and displayed wiki | `source-bundles/`, `rendered/` |
| Rejected output and preparation recovery | `baseline-review-raw-1.json`, `baseline-review-result-1.json`, retry records, `reader-preparation-recovery.json` |

Actual tool returns identify the actors; receipts are host declarations, not
provider-authenticated signatures. Comparison readers and grader are distinct
actors. Their reading boundaries were prompt instructions, not tool isolation.
Grader JSON values preserve the actual response; its completion record discloses
whitespace compaction. Missing provider model identifiers, token usage, cost and
latency remain unavailable. Intent-to-preservation intervals include coordination,
waiting, preparation repair and transcription; they are not pure model latency.

The 12 experimental dispatches exclude M0 and harness implementation/review/
acceptance agents. A rejected baseline revision response and actual retry are
included. Additional user policy/scope/authorization interventions were zero;
automated repairs are separate events. Synthetic regression receipts in
`../test_multi_repo.py` are not evidence of actual model calls.

Managed query/wiki enforce the trusted host's current declared access. Copied
static bytes cannot be revoked. The complete checkpoint precedes later failure
experiments, so final disk state is not claimed to be complete. Original intake
registration demonstrates feedback routing, not downstream automatic execution.
Production service accounts, installed activation, distributed coordination,
scale and general semantic accuracy remain unverified. The final delivery head's
independent LGTM/MATCH and CI are tracked in task #395, avoiding a self-referential
commit hash in this archive.
