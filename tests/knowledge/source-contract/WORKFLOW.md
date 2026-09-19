# Reviewed workflow handoff

Use [refresh-knowledge](../../../.claude/skills/refresh-knowledge/SKILL.md) to orchestrate
capture, decisions, writing, review and local application. These are repository-local skills,
not an installed toolkit feature. The agent executes the CLI calls; no background scheduler
or model API is embedded in this runner. Source and update formats remain owned by
[README.md](README.md) and [UPDATES.md](UPDATES.md).

## Packet

After `update.py prepare`, bundle the exact plan, original bindings, complete pinned source
snapshots, audience and purpose into a self-contained packet:

```sh
"$PYTHON" tests/knowledge/source-contract/workflow.py packet \
  --plan plan.json --bindings bindings.json --before before.json --after after.json \
  --repo /absolute/source/repo --audience 'Backend callers' \
  --purpose 'Choose the correct retry behavior' --out packet.json
```

Packet creation revalidates the plan against Git. Delegate the packet to an independent
reviewer with [review-knowledge](../../../.claude/skills/review-knowledge/SKILL.md). Preserve
its actual response as `review.json`; do not fabricate or rewrite a passing verdict.
If filesystem access is unavailable, provide all packet contents as text and record that
transport limit. Do not claim that the reviewer ran source verification or application.

## Review record

The record shape is owned by [workflow-schema.json](workflow-schema.json). A reviewer returns:

```json
{
  "packet": "<exact packet ID>",
  "plan": "<exact plan ID>",
  "verdict": "pass",
  "checks": {
    "source_fidelity": "pass",
    "decision_coverage": "pass",
    "reader_action": "pass",
    "uncertainty": "pass"
  },
  "findings": []
}
```

The other verdicts are `revise` and `blocked`; individual checks can be `fail` or `unverified`.
Use findings for concrete defects or missing evidence. A pass requires all four checks to
pass and an empty findings list. An edited plan or reader context produces a different packet
ID and requires a new review. Hashes bind content; they do not authenticate a reviewer or
prove independence. The orchestrating agent must obtain the actual independent response.
This is an ordinary document-review record, not an LLM scoring or evaluation framework.

## Finish and continue

```sh
"$PYTHON" tests/knowledge/source-contract/workflow.py finish \
  --packet packet.json --review review.json --repo /absolute/source/repo \
  --docs-root /absolute/documents --out complete.json
```

Finish rejects a missing, stale, incomplete or negative review before touching documents.
It verifies source/plan again, then calls the existing conditional apply. Use the same
exclusive-workspace and recovery rules as [UPDATES.md](UPDATES.md). Direct `update.py apply`
remains a lower-level developer tool; the review boundary applies to this runner, not every
possible way of editing files.

Only after final document verification does the runner create the completion record with
packet, plan and review content IDs and the next bindings. Repeating finish verifies live
documents even if the same completion already exists, and does not rewrite identical files.
Known receipt conflicts fail before document writes. If receipt storage fails after application,
documents may already be complete: inspect them and retry the same packet/review. An existing
partial or different receipt requires a fresh output path; never treat it as completion.

Consume `complete.json`'s `next_bindings` for the next cycle; null means no tracked claims
remain. This runner publishes no remote changes and advances no external task ledger.
