import {roleIdentifier} from './role-contract.mjs';

// These are minimum executable operations, not an exhaustive security allowlist.
// Shell access supplies Git, the gate and the common ledger commands.
export function requiredRoleTools(runtime, role) {
  roleIdentifier(runtime, role);
  const tools = {claude: ['Read', 'Bash'], codex: ['exec_command'],
    antigravity: ['view_file', 'run_command', 'send_message']}[runtime];
  return [...tools, ...(role === 'implementer' ? {
    claude: ['Write', 'Edit'], codex: ['apply_patch'],
    antigravity: ['write_to_file', 'replace_file_content'],
  }[runtime] : [])];
}

export function roleCapabilities(runtime, role, options) {
  const required = requiredRoleTools(runtime, role);
  if (!options || !Array.isArray(options.availableTools) ||
      options.availableTools.some(tool => typeof tool !== 'string' || !tool))
    throw new Error('observed available tools required');
  const missing = required.filter(tool => !options.availableTools.includes(tool));
  if (missing.length) throw new Error(`required role tools missing: ${missing.join(', ')}`);
  let model;
  if (runtime === 'codex') {
    const request = options.modelOptions ?? {};
    if (typeof request !== 'object' || Array.isArray(request) ||
        Object.keys(request).some(key => !['model', 'reasoning_effort', 'availableModels'].includes(key)))
      throw new Error('model options invalid');
    const {model: selected, reasoning_effort: effort, availableModels: available} = request;
    if (available !== undefined && (!Array.isArray(available) || available.some(value => typeof value !== 'string' || !value)))
      throw new Error('available models invalid');
    if (selected !== undefined && (typeof selected !== 'string' || !selected.trim())) throw new Error('requested model invalid');
    if (effort !== undefined && (typeof effort !== 'string' || !effort.trim() || !selected)) throw new Error('requested effort requires a model');
    if (selected && available && !available.includes(selected)) throw new Error('requested model unavailable');
    model = selected ? {model: selected, ...(effort ? {reasoning_effort: effort} : {})} : {};
  }
  else {
    const selected = options.modelOptions?.model ?? 'inherit';
    const models = runtime === 'antigravity' ? ['inherit', 'flash', 'pro'] : options.availableModels;
    if (typeof selected !== 'string' || !selected ||
        (selected !== 'inherit' && (!Array.isArray(models) || !models.includes(selected))))
      throw new Error('requested model unavailable');
    if (options.modelOptions?.reasoning_effort !== undefined)
      throw new Error('requested effort has no supported runtime mapping');
    model = {model: selected};
  }
  return {runtime, role, requiredTools: required, model, evidence: 'capability-check',
    nativeLoaded: false, enforcement: 'unverified'};
}
