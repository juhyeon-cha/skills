/** Shared Markdown parsing and deterministic heading IDs for static and managed readers. */
export function parseDocument(md, body) {
  const tokens = md.parse(body, {}), headings = [], anchors = new Set();
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    if (token.type !== "heading_open") continue;
    const title = tokens[i + 1].content;
    const base = title.toLowerCase().replace(/[^\p{L}\p{N}\s-]/gu, "")
      .trim().replace(/\s+/g, "-") || "section";
    let id = base, n = 1;
    while (anchors.has(id)) id = base + "-" + ++n;
    anchors.add(id);
    token.attrSet("id", id);
    headings.push({title, id, level: Number(token.tag.slice(1))});
  }
  return {tokens, headings, anchors};
}
