# Flowcharts and cards in wiki documents

Read this when authoring a visual explanation for the static or managed knowledge
wiki. The writing skill owns when a visual form helps; this file owns the supported
Markdown representation. Both renderers use the same document tokens. The original
Markdown remains the agent/API body and the source for document review.

## Flowcharts

Use a document-level blockquote whose first paragraph is `[!FLOW]` followed by a
single-line plain-text title, without inline formatting.
Leave a quoted blank line before one ordered list of steps. Steps contain paragraphs;
the final step may end with one unordered list of labeled alternative outcomes, each
containing paragraphs only. Deeper lists are outside this subset. This represents a linear
flow with a final branch, not an arbitrary graph language. For loops, earlier branches
or several interleaved actors, split the explanation into linked bounded flows or use
a decision/transition table; do not imply a missing connection.

Fictional syntax example; use the actual subject's supported conditions and wording:

```markdown
> [!FLOW] 요청 결과에 따른 다음 행동
>
> 1. 요청을 전송한다.
> 2. 결과를 확인한다.
>    - **성공 응답** — 완료된 결과를 보여준다.
>    - **응답 유실 · 결과 미확정** — 상태를 다시 조회하도록 안내한다.
```

Put entry conditions before the diagram when they apply to the whole flow. Name
each branch's condition and result in its visible text. Use an adjacent explanation
for the mechanism or exception that the diagram alone cannot convey. State the scope
of a partial flow rather than making a small diagram look like the entire service.

## Cards

Use `[!CARDS]` and a single-line plain-text title as the first paragraph of a
document-level blockquote, followed
by a blank line and one unordered list. Start each item with a bold title and include
the point and its consequence. Put confirmed, proposed or unresolved status in the
text where it changes interpretation; styling does not assign a status.

```markdown
> [!CARDS] 범위 판단
>
> - **확정 범위** — 현재 승인된 변경 범위와 그 근거를 설명한다.
> - **미정 사항** — 추가로 필요한 결정과 그 결정이 막는 일을 설명한다.
```

Cards adapt to the available width and retain their list order when stacked. Choose
a table instead when the reader needs to compare identical properties across items.
Use ordinary paragraphs for a long argument; a card grid is not a required page layout.

## Text, links and unsupported syntax

Keep visual blocks at document level; a visual block nested inside a quote, list or
another visual block is unsupported. Escape the opening bracket when a marker is
intended as literal text, or show the source in a code fence.

List contents use the existing safe Markdown subset and link resolution. Raw HTML
remains inert; arbitrary styles, scripts and external diagram engines are not enabled.
Mermaid fences remain code examples. Unsupported or malformed recognized visual
blocks fail rendering; fix the canonical source rather than serving an old visual.

In a Markdown viewer without this extension, the same source remains a titled quote
and readable lists, with the marker visible. In the managed reader, the marker selects
presentation and is excluded from section search. Labels, conditions and card contents
remain searchable under their document section, and links retain the same permission
and anchor checks. Static wiki search retains its existing canonical-Markdown index,
including source markup; it is not the managed reader's section-search contract.
Use document heading links near a visual for citations rather than invented node IDs.
