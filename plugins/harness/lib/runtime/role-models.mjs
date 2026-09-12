import { roleIdentifier } from './role-contract.mjs';

// Codex model policy; Claude keeps each role's own frontmatter.
// Rationale and override procedure: docs/roles.md, Model selection.
export function roleModel(role) {
  roleIdentifier('codex', role);
  if (role === 'reviewer') return { model: 'gpt-5.6-sol', reasoning_effort: 'high' };
  if (role === 'evaluator') return { model: 'gpt-5.6-terra', reasoning_effort: 'medium' };
  return {};
}

export function roleSpawnOptions(role) {
  const selected = roleModel(role);
  return selected.model ? { ...selected, fork_turns: 'none' } : {};
}
