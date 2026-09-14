const object = value => value && typeof value === 'object' && !Array.isArray(value);
const text = value => typeof value === 'string' && value.trim().length > 0;
const keys = (value, allowed) => object(value) && Object.keys(value).every(key => allowed.includes(key));
const optional = (value, name, check) => value[name] === undefined || check(value[name]);
const integer = value => Number.isSafeInteger(value) && value >= 0;

export class ToolContractError extends Error {
  constructor(reasonCode) {
    super(reasonCode === 'TOOL_CONTRACT_UNSUPPORTED' ? 'unknown tool contract (TOOL_CONTRACT_UNSUPPORTED)' : reasonCode);
    this.reasonCode = reasonCode;
  }
}

const aliases = new Map([
  ['request_user_input_async', 'request_user_input_async'],
  ['functions.request_user_input_async', 'request_user_input_async'],
  ['clock.sleep', 'clock.sleep'], ['clocksleep', 'clock.sleep'],
  ...['read_thread', 'list_projects', 'create_thread'].flatMap(name => [
    [`mcp__codex_app__${name}`, `codex_app.${name}`],
    [`mcp__codex_app.${name}`, `codex_app.${name}`],
  ]),
  ['mcp__cua_repl__js', 'cua.js'], ['mcp__cua_repl.js', 'cua.js'],
]);

function validTarget(value) {
  if (!object(value)) return false;
  if (value.type === 'projectless') return keys(value, ['type', 'directoryName']) && optional(value, 'directoryName', text);
  if (value.type === 'chatgptWorkCloud') return keys(value, ['type', 'projectId']) && optional(value, 'projectId', text);
  if (value.type !== 'project' || !keys(value, ['type', 'projectId', 'environment']) || !text(value.projectId)) return false;
  const e = value.environment;
  if (!object(e)) return false;
  if (e.type === 'local') return keys(e, ['type']);
  if (e.type !== 'worktree' || !keys(e, ['type', 'startingState'])) return false;
  if (e.startingState === undefined) return true;
  const s = e.startingState;
  return object(s) && (s.type === 'working-tree' ? keys(s, ['type']) :
    s.type === 'branch' && keys(s, ['type', 'branchName', 'onMissing']) && text(s.branchName) &&
    optional(s, 'onMissing', x => ['error', 'create-branch'].includes(x)));
}

// Exact aliases and per-effect contracts. An unlisted tool never inherits a
// read exemption from its name. Payload values are not used as diagnostics.
export function additionalToolContract(name, input) {
  const canonical = aliases.get(name);
  if (!canonical) return null;
  let valid = false, effect;
  switch (canonical) {
    case 'request_user_input_async':
      effect = 'question';
      valid = keys(input, ['questions']) && Array.isArray(input.questions) && input.questions.length > 0 &&
        input.questions.every(q => keys(q, ['title', 'options']) && text(q.title) &&
          optional(q, 'options', x => Array.isArray(x) && x.length > 0 && x.every(text)));
      break;
    case 'clock.sleep':
      effect = 'wait';
      valid = keys(input, ['duration_ms']) && integer(input.duration_ms) && input.duration_ms >= 1 && input.duration_ms <= 43200000;
      break;
    case 'codex_app.list_projects':
      effect = 'read'; valid = keys(input, []); break;
    case 'codex_app.read_thread':
      effect = 'read';
      valid = keys(input, ['threadId', 'hostId', 'cursor', 'includeOutputs', 'maxOutputCharsPerItem', 'turnLimit']) && text(input.threadId) &&
        ['hostId', 'cursor'].every(k => optional(input, k, text)) &&
        optional(input, 'includeOutputs', x => typeof x === 'boolean') &&
        ['maxOutputCharsPerItem', 'turnLimit'].every(k => optional(input, k, integer));
      break;
    case 'codex_app.create_thread':
      effect = 'task-create';
      valid = keys(input, ['target', 'prompt', 'title', 'model', 'thinking']) && text(input.prompt) && validTarget(input.target) &&
        ['title', 'model'].every(k => optional(input, k, text)) &&
        optional(input, 'thinking', x => ['none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max', 'ultra'].includes(x));
      break;
    case 'cua.js':
      effect = 'read';
      valid = keys(input, ['code', 'title', 'timeout_ms']) && typeof input.code === 'string' &&
        /^\s*await\s+cua\.getState\(\s*\)\s*;?\s*$/.test(input.code) &&
        optional(input, 'title', text) && optional(input, 'timeout_ms', integer);
      if (!valid) throw new ToolContractError('TOOL_EFFECT_UNSUPPORTED');
      break;
  }
  if (!valid) throw new ToolContractError('TOOL_INPUT_INVALID');
  return {canonical, effect, roleIndependent: ['read', 'question', 'wait'].includes(effect)};
}
