import {
  normalizePath,
  patchOperations,
  isReadonlySearch,
  quotedPathCandidates,
} from './operations.mjs';

import { canonicalRole } from '../runtime/role-contract.mjs';
import { powershellOperations } from './powershell-operations.mjs';

export function normalizeHookEvent(
  raw,
  { env = process.env, platform = process.platform, delegatedRole } = {},
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
  for (const key of ['agent_id', 'agent_type'])
    if (raw[key] != null && typeof raw[key] !== 'string') throw new Error(`invalid ${key}`);
  if (delegatedRole && (!raw.agent_id || (raw.agent_type && raw.agent_type !== 'default') || !canonicalRole(delegatedRole)))
    throw new Error('invalid delegated policy role');
  if (raw.agent_id && !canonicalRole(raw.agent_type) && !delegatedRole)
    throw new Error('child role is unidentified');
  if (raw.agent_type && !canonicalRole(raw.agent_type) && !delegatedRole) throw new Error('unknown role');
  const event = {
    ...raw,
    agent_type: canonicalRole(raw.agent_type) ?? '',
    harness_policy_role: delegatedRole || canonicalRole(raw.agent_type) || '',
    harness_operations: [],
    harness_shell_readonly: false,
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
      event.harness_shell_readonly = isReadonlySearch(command);
      if (!event.harness_shell_readonly)
        event.harness_operations = quotedPathCandidates(command, raw.cwd);
    }
  } else if (event.tool_name === 'apply_patch') {
    event.harness_operations = patchOperations(raw.tool_input.command, raw.cwd);
  } else {
    const value = raw.tool_input.file_path ?? raw.tool_input.notebook_path;
    if (['Write', 'Edit', 'NotebookEdit'].includes(raw.tool_name) && !value)
      throw new Error('file target missing');
    if (value && !['Read', 'NotebookRead', 'Glob', 'Grep'].includes(raw.tool_name))
      event.harness_operations = [{ kind: 'update', path: normalizePath(value, raw.cwd) }];
  }
  return event;
}
