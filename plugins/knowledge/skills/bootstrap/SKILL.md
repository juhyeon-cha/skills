---
name: bootstrap
description: Create the first evidence-linked knowledge or target specification when no reviewed baseline exists. Use for code-to-knowledge initialization or goal-only specifications; existing-baseline changes use knowledge:update.
---

# Bootstrap knowledge

Read [bootstrap](../../references/bootstrap.md) and execute its freeze, generation, independent
evaluation and handoff steps. Resolve the reader, purpose, source scope and caller-owned bundle.
The procedure owns criteria and recovery; keep the exact input and output versions through handoffs.
Read [project setup](../../references/project.md) before commands. Resolve the external
`toolkit:writing-for-humans` capability and an independent `knowledge:review` agent.

Separate current behavior, approved targets and proposals. Code absent is different from required
code inaccessible. A proposal or missing evidence remains pending. For an existing reviewed
baseline use `knowledge:update`; preserve the bundle instead of overwriting it.

Finish only with the independently evaluated bundle and verified project or intake receipt required
by the bootstrap procedure. A target intake can be complete while its implementation is pending;
`init` success alone establishes no semantic review or implementation completion.
