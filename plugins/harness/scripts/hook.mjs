import fs from 'node:fs';
import path from 'node:path';
import {pluginRoot, readJson} from '../lib/distribution.mjs';
import {recordHook} from '../lib/doctor.mjs';
import {recordStateEvent, formatStateContext} from '../lib/state.mjs';
import {sessionContext} from '../lib/session-context.mjs';

try {
  const id = process.argv[2];
  const rest = process.argv.slice(3);
  if (rest.length) {
    if (rest.length !== 2 || rest[0] !== '--runtime' || !['claude', 'codex'].includes(rest[1])) throw new Error('invalid hook runtime argument');
    if (process.env.HARNESS_RUNTIME && process.env.HARNESS_RUNTIME !== rest[1]) throw new Error('hook runtime conflicts with environment');
    process.env.HARNESS_RUNTIME = rest[1];
  }
  const definition = readJson(path.join(pluginRoot, 'lib/hook-definitions.json')).find(entry => entry.id === id);
  if (!definition) throw new Error('unknown hook');
  const input = fs.readFileSync(0, 'utf8');
  const event = JSON.parse(input);
  if (event.hook_event_name !== definition.event) throw new Error('hook event mismatch');
  let run = {code: 0, stdout: '', stderr: ''};
  if (id === 'context') run.stdout = JSON.stringify(sessionContext(pluginRoot));
  else if (id === 'guard') run = await (await import('../lib/guard.mjs')).evaluateGuard(event, {pluginRoot});
  else if (id === 'stop') run = await (await import('../lib/stop.mjs')).evaluateStop(event, {pluginRoot});
  else if (id === 'workspace') {
    if (typeof event.cwd !== 'string' || !path.isAbsolute(event.cwd)) throw new Error('payload cwd required');
    try { await (await import('../lib/workspace.mjs')).enterWorkspace(event.cwd, {say: line => { run.stderr += line + '\n'; }}); }
    catch (error) { run.code = 2; run.stderr += `원장 배선 실패 — ${error.message}\n`; }
  }
  else if (!['role-start', 'role-stop'].includes(id)) throw new Error('registered hook has no native handler');
  const code = run.code;
  let stateContext;
  try {
    const scope = await recordStateEvent(event, code);
    if (id === 'context' && code === 0) {
      const output = JSON.parse(run.stdout);
      stateContext = {runtime: scope.runtime, repository: scope.top, sessionId: scope.sessionId, data: scope.data};
      if (typeof output.hookSpecificOutput?.additionalContext !== 'string') throw new Error('session context output missing');
      output.hookSpecificOutput.additionalContext += formatStateContext(stateContext);
      run.stdout = JSON.stringify(output);
    }
  }
  catch (error) { console.error(`STATE UNREACHED: ${error.message}; ordinary workflow evidence unavailable`); }
  recordHook(process.env.HARNESS_DOCTOR_DIR, pluginRoot, event, id, {code, stdout: run.stdout ?? '', stateContext});
  process.stdout.write(run.stdout ?? ''); process.stderr.write(run.stderr ?? '');
  process.exitCode = code;
} catch (error) { console.error(`UNREACHED: ${error.message}`); process.exitCode = 2; }
