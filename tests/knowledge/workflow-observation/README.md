# Recorded agent handoff

This is one observed static-source update, not a model benchmark or a guarantee of autonomous
operation. The parent ran deterministic CLI steps in a disposable repository. Separate agents
authored decisions and reviewed the resulting packet from supplied text. Existing agents were
reused because the session could not create another thread; no cold-start behavior is claimed.
Relevant skill instructions were supplied as text, not loaded through installed skill discovery.

- `source-history.fi`: the fixture Git history, reproducible with `git fast-import`.
- `decisions.json`: the author's returned JSON, preserved before normalization.
- `packet.json`: exact prepared plan, source snapshots, bindings and reader context.
- `review.json`: the independent reviewer's actual JSON response.
- `complete.json`: observed successful completion, identical on repeat.

The reviewer explicitly limited its observation to supplied text and did not independently
verify hashes, Git state or execution. The parent performed those checks. The author changed
the retry limit and retained exception behavior. The reviewer returned pass with no findings.
Read the [human experiment report](../../../docs/initiatives/code-driven-knowledge/experiments/agent-refresh.md)
for the scope and limitations.

`test_workflow.py` reimports this history into a disposable repository, rebuilds the plan from
the preserved decisions, applies the recorded review and compares final bytes and completion.
This is a deterministic replay of an observed handoff; it does not rerun the agents or prove
that a different model/session will produce the same decisions. Run it through the existing
source-contract shell test, using the documented Python environment.
