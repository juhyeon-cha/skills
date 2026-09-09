import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {pluginRoot, readJson} from '../lib/distribution.mjs';
import {recordHook} from '../lib/doctor.mjs';

try {
  const id = process.argv[2];
  const definition = readJson(path.join(pluginRoot, 'lib/hook-definitions.json')).find(entry => entry.id === id);
  if (!definition) throw new Error('unknown hook');
  const input = fs.readFileSync(0, 'utf8');
  const event = JSON.parse(input);
  if (event.hook_event_name !== definition.event) throw new Error('hook event mismatch');
  const run = definition.script ? spawnSync('bash', [path.join(pluginRoot, definition.script)], {input, encoding: 'utf8', env: {...process.env, CLAUDE_PLUGIN_ROOT: pluginRoot}}) : {status: 0, stdout: '', stderr: ''};
  const code = run.status ?? 2;
  recordHook(process.env.HARNESS_DOCTOR_DIR, pluginRoot, event, id, {code, stdout: run.stdout ?? ''});
  process.stdout.write(run.stdout ?? ''); process.stderr.write(run.stderr ?? '');
  process.exitCode = code;
} catch (error) { console.error(`UNREACHED: ${error.message}`); process.exitCode = 2; }
