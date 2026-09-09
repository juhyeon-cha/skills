import fs from 'node:fs';
import {normalizeHookEvent} from '../lib/hook-event.mjs';
import {fileURLToPath} from 'node:url';
import {workspaceShellCommand} from '../lib/workspace-command.mjs';
try {
  const event = normalizeHookEvent(JSON.parse(fs.readFileSync(0, 'utf8')));
  event.harness_workspace_action = '';
  if (event.tool_name === 'Bash') {
    const workspace = workspaceShellCommand(event.tool_input.command, fileURLToPath(new URL('./workspace.mjs', import.meta.url)));
    if (workspace) {
      if (['harness:reviewer', 'harness:evaluator'].includes(event.agent_type) && workspace.action !== 'inspect') throw new Error('grader cannot mutate workspace lifecycle');
      event.harness_workspace_action = workspace.action;
      event.harness_operations = [];
    }
  }
  const paths = event.harness_operations.flatMap(op => op.kind === 'move' ? [op.source, op.destination] : [op.path]);
  if (process.platform !== 'win32' && paths.some(p => /^[A-Za-z]:[\\/]|^\\\\/.test(p))) throw new Error('Windows filesystem policy is unavailable on this host');
  console.log(JSON.stringify(event));
} catch (error) {
  console.error(`GUARD-DENY: UNREACHED — ${error.message}`);
  process.exitCode = 2;
}
