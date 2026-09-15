---
name: writing-for-humans
description: Write, restructure, or condense human-facing work documents for their audience and purpose. Use for FE/BE engineering documents, UI/UX design explanations, PO decision proposals, service specifications, and cross-functional handoffs. Excludes agent instructions and proofreading-only requests.
---

# Writing for humans

Produce documents that let readers make the required decision or take the required action. Use only the length needed for that outcome.

## 1. Identify the reader and purpose

Establish the **primary reader, action after reading, existing knowledge, and delivery medium** from the request and source material. Job function is a starting point: a BE engineer implementing a change needs different information from one assessing an investment. Distinguish the author's role from the reader's.

Use this context to guide the work; do not output a separate analysis table unless requested. When the purpose is clear and only details are missing, state a brief assumption and proceed. Ask a focused question only when whose decision to support would materially change the content. The user's specified audience, length, and format override defaults.

## 2. Read only the relevant references

Read the reference for the primary reader and the reference for the document's purpose. For multiple functions, center the shared decision and add only the role references needed for the handoff.

| Read when | Reference |
|---|---|
| FE developers implement screens or connect them to servers | [FE: states and screen behavior](references/frontend.md) |
| BE developers design server behavior, data, or operations | [BE: contracts and failure handling](references/backend.md) |
| UI/UX practitioners design or review user flows and interactions | [UI/UX: experience and design rationale](references/uiux.md) |
| Product owners decide priorities, scope, or outcomes | [PO: investment and product decisions](references/product-owner.md) |
| Service planners define policies, workflows, or conditions | [Planning: rules and exceptions](references/planning.md) |
| Choosing a structure for proposals, specifications, handoffs, updates, or instructions | [Document shapes and multiple audiences](references/document-shapes.md) |
| Condensing a draft or replacing abstract language | [Editing criteria and audience-specific examples](references/editing.md) |

For unlisted roles, use the closest **decision task**. Role-specific items are selection criteria, not a form to fill out.

## 3. Select facts, then write

Check the evidence for conclusions in supplied material and relevant files you are authorized to access. Distinguish facts, proposals, hypotheses, and unresolved decisions. Do not invent plausible figures, schedules, owners, API behavior, or policies. Surface conflicts that affect a decision, and write the parts that unresolved questions do not block.

Start with the conclusion or request the reader needs first, then provide the reasoning and execution conditions. Order sentences by how the reader understands the subject, not by the sequence of your investigation. For long source material, retain the necessary evidence in the body and link detailed sources nearby. Cite only sources you have checked.

For cross-functional documents, place role-specific differences beneath the shared conclusion. Define each policy or figure once. Create separate documents only when the user requests them or when audiences, lifetimes, or maintenance responsibilities differ.

When editing, preserve commitments, figures, conditions, and degrees of certainty. Distinguish substantive proposals from wording improvements. Deliver an answer when an answer is requested, and a file when file creation is requested. Permission to write a document does not grant permission to publish externally. If a file format or a PR requires a particular structure, honor it while using this skill to select and express the content.

## 4. Review against the reader's task and trim

Check whether the reader can do the following from the document alone:

- Decision documents: understand what to decide, why, and how remaining uncertainty could change the conclusion.
- Execution documents: identify applicability, actions, observable results, and important exceptions.
- Updates: understand what changed and its impact or request for them.

Remove background, repeated summaries, and empty sections that do not support those outcomes. Restore any decision conditions or exceptions lost through shortening. A short document may need only connected sentences without headings. Deliver the finished document; add process notes or self-checklists only when requested.
