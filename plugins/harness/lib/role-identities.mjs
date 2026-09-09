// Runtime identifiers only; bodies and SIGNAL vocabularies belong to agents/*.md.
export const roleNames = Object.freeze(['implementer', 'reviewer', 'evaluator']);
export function roleIdentifier(runtime, role) {
  if (!roleNames.includes(role) || !['claude', 'codex'].includes(runtime)) throw new Error('unidentified runtime/role');
  return `harness${runtime === 'claude' ? ':' : '-'}${role}`;
}
export function canonicalRole(identifier) {
  for (const role of roleNames) for (const runtime of ['claude', 'codex']) {
    if (identifier === roleIdentifier(runtime, role)) return roleIdentifier('claude', role);
  }
  return undefined;
}
