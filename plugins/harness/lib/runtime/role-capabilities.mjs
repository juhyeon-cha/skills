import {roleIdentifier} from './role-contract.mjs';
import {roleSpawnOptions} from './role-models.mjs';

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
  if (runtime === 'codex') model = roleSpawnOptions(role, options.modelOptions);
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
