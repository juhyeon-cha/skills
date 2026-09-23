# Visual explanations

Use a visual form to expose a relationship the reader needs: order, a decision,
a comparison, or a small set of independently useful facts. First name what the
reader should learn from it. A short sentence may already be the clearest form.

## Select a form for the content

| Relationship to explain | Useful form | Keep visible |
|---|---|---|
| Ordered work with consequential decisions or handoffs | Flowchart | Entry, named actors when needed, branch conditions, resulting states and important failure/unknown exits |
| Allowed changes between states | State diagram or transition table | From/to states, triggering event and guard condition; distinguish a workflow step from a persisted state |
| Alternatives, response mappings or policy combinations | Table | Comparable columns, units/conditions and meaningful differences; split a table when unrelated facts make rows unreadable |
| A few independent concepts, decisions or next actions | Cards or titled callouts | A meaningful title, the point and its consequence; put status/limits beside the claim when they change its meaning |
| A short sequence without important branches | Numbered steps or a labeled arrow sequence | Order, action and expected outcome |
| Rationale, nuance or an unfamiliar concept | Connected prose with an example | Reasoning, context and the condition that could change the conclusion |

Cards are useful when each item makes sense on its own and the reader benefits from
scanning the set. Use a table when readers must compare the same properties across
items; use a flow when item order or dependencies matter. Do not split a causal
explanation into disconnected tiles. Do not invent metrics or status badges to fill cards.

## Match the delivery medium

Inspect the actual output target's supported subset before choosing syntax. A fenced
`mermaid` block is a diagram only where Mermaid rendering is available; elsewhere it
is source text. Use Mermaid for a small diagram in a compatible Markdown target.
For an existing webpage or document template, use its supported components and layout.
Raw HTML, SVG and images require target support and the applicable publication policy.
Do not enable a renderer, fetch a library or change sanitization merely to decorate prose.

For a text-only Markdown target, use a decision table or numbered branches in place
of an unrendered flowchart. Use bold-titled blockquotes or subsections as card-like
callouts; these are linear reading blocks, not a responsive card grid. State the
capability limit when the user specifically requested the unavailable visual format.
Rendering support is separate from the correctness of the explanation.

When a diagram is supported, keep its source editable and provide a short adjacent
text explanation of the key path and exceptions. For cards, preserve a meaningful
linear reading order. Label meaning directly; color or icon alone must not carry
status, branch identity or priority. Keep labels readable on narrow screens. Split a
dense diagram at a meaningful boundary with explicit continuation instead of shrinking
all its text. These choices should also leave the explanation usable without graphics.

## Preserve the meaning across forms

Draw only relationships established by the input. An arrow can claim causation,
ordering or responsibility: label what it means. A dashed edge or differently colored
card alone does not establish that a step is proposed or unknown; say so in text.
Distinguish an attempted action from its successful outcome and a confirmed business
decision from a suggestion. Include the failure or uncertain branch when omitting it
would lead to the wrong action.

Use the same terms and conditions as the canonical rule and place a nearby source or
section link. A visual may summarize a rule but must not become a conflicting policy.
Keep decision-changing exceptions near the summary; link lengthy detail rather than
copying every paragraph into a diagram and back into prose. When the source changes,
update every affected label, branch, card and explanatory sentence together.
