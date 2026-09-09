import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {pluginRoot, readJson} from '../lib/distribution.mjs';
import {recordHook} from '../lib/doctor.mjs';
import {recordStateEvent, formatStateContext} from '../lib/state.mjs';

try {
  const id = process.argv[2];
  const definition = readJson(path.join(pluginRoot, 'lib/hook-definitions.json')).find(entry => entry.id === id);
  if (!definition) throw new Error('unknown hook');
  const input = fs.readFileSync(0, 'utf8');
  const event = JSON.parse(input);
  if (event.hook_event_name !== definition.event) throw new Error('hook event mismatch');
  const run = definition.script ? spawnSync('bash', [path.join(pluginRoot, definition.script)], {input, encoding: 'utf8', env: {...process.env, CLAUDE_PLUGIN_ROOT: pluginRoot}}) : {status: 0, stdout: '', stderr: ''};
  const code = run.status ?? 2;
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
