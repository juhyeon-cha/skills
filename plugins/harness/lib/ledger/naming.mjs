/** Stable issue kinds. Sprint and backlog membership belong in fields/labels. */
const prefixes = Object.freeze({epic: '스토리', feature: '마일스톤', task: '태스크', decision: '결정'});
const knownPrefix = /^\[(?:epic|feature|task|decision|스토리|에픽|마일스톤|태스크|결정)\]\s*/i;

/** Name a newly created issue; preserve unrecognized types and bracketed prose. */
export function namedTitle(title, type) {
  const prefix = Object.hasOwn(prefixes, type) ? prefixes[type] : undefined;
  if (!prefix) return title;
  const body = String(title).trim().replace(knownPrefix, '');
  return `[${prefix}]${body ? ` ${body}` : ''}`;
}
