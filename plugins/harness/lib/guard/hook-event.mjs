import {
  normalizePath,
  patchOperations,
  isReadonlySearch,
  shellWriteOperations,
} from './operations.mjs';

import { canonicalRole } from '../runtime/role-contract.mjs';
import { powershellOperations } from './powershell-operations.mjs';
import {additionalToolContract} from './tool-contract.mjs';
import {literalReadEffects} from './shell-effects.mjs';

export function normalizeHookEvent(
  raw,
  { env = process.env, platform = process.platform, delegatedRole, deferDelegatedRole = false } = {},
) {
  if (!raw || Array.isArray(raw) || typeof raw !== 'object')
    throw new Error('hook input must be an object');
  if (
    typeof raw.tool_name !== 'string' ||
    !raw.tool_name ||
    typeof raw.cwd !== 'string' ||
    !raw.cwd ||
    !raw.tool_input ||
    typeof raw.tool_input !== 'object' ||
    Array.isArray(raw.tool_input)
  )
    throw new Error('required hook input missing');
  if (!/^(?:\/|[A-Za-z]:[\\/]|\\\\)/.test(raw.cwd) || /[\0\r\n]/.test(raw.cwd))
    throw new Error('absolute cwd required');
  let contract = additionalToolContract(raw.tool_name);
  if (!contract && !['Bash', 'PowerShell', 'exec_command', 'apply_patch', 'Write', 'Edit', 'NotebookEdit',
    'Read', 'NotebookRead', 'Glob', 'Grep', 'Agent', 'Task', 'SendMessage', 'EnterWorktree', 'ExitWorktree',
    'WebSearch', 'WebFetch', 'AskUserQuestion', 'TodoWrite', 'Skill'].includes(raw.tool_name) &&
    !/^collaboration\.?(?:spawn_agent|send_message|list_agents|wait_agent|followup_task|interrupt_agent)$/.test(raw.tool_name))
    contract = {canonical: 'OTHER', effect: 'host-managed', roleIndependent: true};
  for (const key of ['agent_id', 'agent_type'])
    if (raw[key] != null && typeof raw[key] !== 'string') throw new Error(`invalid ${key}`);
  if (delegatedRole && (!raw.agent_id || (raw.agent_type && raw.agent_type !== 'default') || !canonicalRole(delegatedRole)))
    throw new Error('invalid delegated policy role');
  const pendingRole = deferDelegatedRole && raw.agent_id && (!raw.agent_type || raw.agent_type === 'default');
  // Only the resolver supplies null after classifying an ordinary child.
  const ordinaryChild = delegatedRole === null && raw.agent_id && (!raw.agent_type || raw.agent_type === 'default');
  if (raw.agent_id && !canonicalRole(raw.agent_type) && !delegatedRole && !pendingRole && !ordinaryChild)
    throw new Error('child role is unidentified');
  if (raw.agent_type && !canonicalRole(raw.agent_type) && !delegatedRole && !pendingRole && !ordinaryChild) throw new Error('unknown role');
  const event = {
    ...raw,
    agent_type: canonicalRole(raw.agent_type) ?? '',
    harness_policy_role: delegatedRole || canonicalRole(raw.agent_type) || '',
    harness_operations: [],
    harness_shell_readonly: false,
    harness_tool_contract: contract,
  };
  if (raw.tool_name === 'exec_command' || raw.tool_name === 'PowerShell') event.tool_name = 'Bash';
  if (event.tool_name === 'Bash') {
    const command = raw.tool_input.command ?? raw.tool_input.cmd;
    if (typeof command !== 'string' || !command.trim()) throw new Error('shell command missing');
    event.tool_input = { ...raw.tool_input, command };
    event.harness_shell_dialect =
      raw.tool_name === 'PowerShell' ||
      (platform === 'win32' &&
        (raw.tool_name === 'exec_command' ||
          env.HARNESS_RUNTIME === 'codex' ||
          (!env.HARNESS_RUNTIME && env.CODEX_HOME)))
        ? 'powershell'
        : 'posix';
    if (event.harness_shell_dialect === 'powershell') {
      const parsed = powershellOperations(command, raw.cwd);
      event.harness_shell = parsed;
      event.harness_shell_readonly = parsed.readonly;
      event.harness_operations = parsed.paths.map((path) => ({ kind: 'update', path }));
    } else {
      event.harness_shell_readonly = isReadonlySearch(command, env);
      event.harness_literal_effects = literalReadEffects(command, raw.cwd, env);
      if (event.harness_literal_effects) {
        event.harness_effect_readonly = event.harness_literal_effects.writes.length === 0;
        event.harness_operations = event.harness_literal_effects.writes.map(path => ({kind: 'update', path}));
      } else if (!event.harness_shell_readonly)
        event.harness_operations = shellWriteOperations(command, raw.cwd);
    }
  } else if (event.tool_name === 'apply_patch') {
    event.harness_operations = patchOperations(raw.tool_input.command, raw.cwd);
  } else {
    const value = raw.tool_input.file_path ?? raw.tool_input.notebook_path;
    if (['Write', 'Edit', 'NotebookEdit'].includes(raw.tool_name) && !value)
      throw new Error('file target missing');
    if (value && ['Write', 'Edit', 'NotebookEdit'].includes(raw.tool_name))
      event.harness_operations = [{ kind: 'update', path: normalizePath(value, raw.cwd) }];
  }
  return event;
}
