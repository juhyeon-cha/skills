/** Project bounded visual blockquotes without replacing their readable Markdown tokens. */
export function projectVisuals(tokens, md) {
  const ends = new Map(), stack = [];
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i].nesting === 1) stack.push(i);
    if (tokens[i].nesting === -1) ends.set(stack.pop(), i);
  }
  const children = (start) => {
    const result = [];
    for (let i = start + 1; i < ends.get(start); i = (ends.get(i) ?? i) + 1) result.push(i);
    return result;
  };
  const fail = (token, reason) => {
    throw Error(`VISUAL_BLOCK_INVALID at line ${(token.map?.[0] ?? 0) + 1}: ${reason}`);
  };
  for (let i = 0; i < tokens.length; i++) {
    const quote = tokens[i], marker = tokens[i + 2];
    if (quote.type !== 'blockquote_open' || tokens[i + 1]?.type !== 'paragraph_open'
        || marker?.type !== 'inline' || !/^\[!(FLOW|CARDS)\]/.test(marker.content)) continue;
    const match = /^\[!(FLOW|CARDS)\] ([^\n]+)$/.exec(marker.content);
    if (!match || !match[2].trim()) fail(quote, 'Use a separate marker paragraph with a plain title.');
    const [ , kind, title ] = match;
    const titleTokens = md.parseInline(title, {})[0].children;
    if (titleTokens.some(t => t.type !== 'text')) fail(quote, 'The visual title must be plain text.');
    if (quote.level !== 0) fail(quote, 'Visual blocks must be at document level.');
    const parts = children(i), list = parts[1];
    const expected = kind === 'FLOW' ? 'ordered_list_open' : 'bullet_list_open';
    if (parts.length !== 2 || tokens[list]?.type !== expected)
      fail(quote, `Use one ${kind === 'FLOW' ? 'ordered' : 'unordered'} list after the title.`);
    const items = children(list);
    if (!items.length || items.some(at => tokens[at].type !== 'list_item_open')) fail(quote, 'The visual list needs items.');
    for (const [position, at] of items.entries()) {
      const blocks = children(at);
      if (!blocks.length || tokens[blocks[0]].type !== 'paragraph_open') fail(quote, 'Each item must start with a paragraph.');
      if (kind === 'CARDS') {
        const inline = tokens[blocks[0] + 1].children || [];
        const first = inline.findIndex(t => t.type !== 'text' || t.content.trim());
        const close = inline.findIndex((t, n) => n > first && t.type === 'strong_close');
        if (inline[first]?.type !== 'strong_open' || close < 0
            || !inline.slice(first + 1, close).some(t => t.content?.trim()))
          fail(quote, 'Each card must start with a bold title.');
      } else {
        for (const [n, block] of blocks.entries()) {
          if (tokens[block].type === 'paragraph_open') continue;
          if (tokens[block].type !== 'bullet_list_open' || position !== items.length - 1 || n !== blocks.length - 1)
            fail(quote, 'Only the final flow step may end with an unordered outcome list.');
          for (const outcome of children(block)) {
            if (tokens[outcome].type !== 'list_item_open' || children(outcome).some(p => tokens[p].type !== 'paragraph_open'))
              fail(quote, 'Outcomes support paragraphs only, without deeper branches.');
          }
          tokens[block].attrJoin('class', 'wiki-flow-outcomes');
        }
      }
      tokens[at].attrJoin('class', kind === 'FLOW' ? 'wiki-flow-step' : 'wiki-card');
    }
    quote.tag = tokens[ends.get(i)].tag = 'section';
    quote.attrJoin('class', `wiki-visual wiki-${kind.toLowerCase()}`);
    quote.attrSet('aria-label', titleTokens.map(t => t.content).join(''));
    tokens[i + 1].attrJoin('class', 'wiki-visual-title');
    marker.content = title;
    marker.children = titleTokens;
    tokens[list].attrJoin('class', 'wiki-visual-items');
  }
  return tokens;
}
