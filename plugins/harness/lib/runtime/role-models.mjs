import { roleIdentifier } from './role-contract.mjs';

// Optional Codex preferences; native roles inherit runtime settings.
// Rationale and override procedure: docs/roles.md, Model selection.
export function roleModel(role) {
  roleIdentifier('codex', role);
  if (role === 'reviewer') return { model: 'gpt-5.6-sol', reasoning_effort: 'high' };
  if (role === 'evaluator') return { model: 'gpt-5.6-terra', reasoning_effort: 'medium' };
  return {};
}

export function roleSpawnOptions(role, options = {}) {
  const preferred = roleModel(role);
  if (!options || typeof options !== 'object' || Array.isArray(options) ||
      Object.keys(options).some(key => !['availableModels', 'model', 'reasoning_effort'].includes(key)))
    throw new Error('model options invalid');
  const {availableModels, model, reasoning_effort} = options;
  if (availableModels !== undefined && (!Array.isArray(availableModels) || availableModels.some(value => typeof value !== 'string' || !value)))
    throw new Error('available models invalid');
  if (model !== undefined && (typeof model !== 'string' || !model.trim())) throw new Error('requested model invalid');
  if (reasoning_effort !== undefined && (typeof reasoning_effort !== 'string' || !reasoning_effort.trim())) throw new Error('requested effort invalid');
  if (model && availableModels && !availableModels.includes(model)) throw new Error('requested model unavailable');
  if (!model && reasoning_effort) throw new Error('requested effort requires a model');
  const selected = model ? {model, ...(reasoning_effort ? {reasoning_effort} : {})}
    : availableModels?.includes(preferred.model) ? preferred : {};
  return selected.model ? { ...selected, fork_turns: 'none' } : {};
}
