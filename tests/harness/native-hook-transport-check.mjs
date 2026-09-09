import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {hookTransport, projections, hookWiring} from '../../plugins/harness/lib/distribution.mjs';

const source = fileURLToPath(new URL('../../plugins/harness/', import.meta.url));
const temp = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'harness-hook-launch-')));
const root = path.join(temp, '플러그인 공백'), repo = path.join(temp, '저장소 공백');
const baseEnv = {...process.env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: path.join(temp, 'gitconfig'), HARNESS_DATA_DIR: path.join(temp, '상태 공백')};
for (const key of ['HARNESS_RUNTIME', 'HARNESS_ROOT', 'PLUGIN_ROOT', 'PLUGIN_DATA', 'CLAUDE_PLUGIN_ROOT', 'CLAUDE_PLUGIN_DATA', 'HARNESS_GUARD_LOG', 'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR']) delete baseEnv[key];
fs.writeFileSync(baseEnv.GIT_CONFIG_GLOBAL, '');
let count = 0;
function check(label, fn) { fn(); count++; console.log('PASS ' + label); }
function copyInventory(directory) {
  try { return fs.readdirSync(directory, {recursive: true}).map(String).sort().slice(0, 80); }
  catch (error) { return {code: error.code}; }
}
function launch(runtime, id, input, extraEnv = {}) {
  const transport = hookTransport(id, runtime);
  const env = {...baseEnv, CLAUDE_PLUGIN_ROOT: root, ...(runtime === 'codex' ? {PLUGIN_ROOT: root} : {}), ...extraEnv};
  const options = {cwd: repo, env, input: JSON.stringify(input), encoding: 'utf8', timeout: 20000};
  if (runtime === 'claude') return spawnSync(transport.command, transport.args.map(arg => arg.replace('${CLAUDE_PLUGIN_ROOT}', root)), options);
  if (process.platform === 'win32') return spawnSync(env.COMSPEC || path.join(env.SystemRoot, 'System32/cmd.exe'), ['/C', `"${transport.commandWindows}"`], {...options, windowsVerbatimArguments: true});
  return spawnSync('/bin/sh', ['-c', transport.command], options);
}
try {
  if (process.argv[2]) assert.equal(process.platform, process.argv[2], 'actual host must match expected host');
  const manifest = path.join('.claude-plugin', 'plugin.json');
  const originalManifest = fs.readFileSync(path.join(source, manifest));
  fs.cpSync(source, root, {recursive: true});
  check('fixture copy preserves the source manifest before projection generation', () => {
    try { assert.deepEqual(fs.readFileSync(path.join(root, manifest)), originalManifest); }
    catch (error) {
      throw new Error('fixture copy incomplete: ' + JSON.stringify({node: process.version, source, root, sourceInventory: copyInventory(source), destinationInventory: copyInventory(root), cause: error.message}));
    }
  });
  for (const [relative, text] of Object.entries(projections(root))) fs.writeFileSync(path.join(root, relative), text);
  const initialized = spawnSync('git', ['init', '-q', repo], {env: baseEnv, encoding: 'utf8'}); assert.equal(initialized.status, 0, initialized.stderr);
  fs.writeFileSync(path.join(repo, '.harness.json'), JSON.stringify({ledger: {backend: 'beads'}}));
  check('both generated runtime wiring sets have six unique hooks and one policy source', () => {
    const claude = hookWiring(root), codex = hookWiring(root, path.join(root, 'hooks/codex.json'));
    assert.equal(claude.length, 6); assert.equal(codex.length, 6);
    assert.equal(JSON.parse(fs.readFileSync(path.join(root, '.codex-plugin/plugin.json'), 'utf8')).hooks, './hooks/codex.json');
    assert.deepEqual(claude.map(row => row.script), codex.map(row => row.script));
  });
  for (const runtime of ['claude', 'codex']) {
    const event = {cwd: repo, session_id: runtime + '-launch'};
    check(`${runtime}: literal Unicode/space root, stdin JSON and UTF-8 stdout reach SessionStart`, () => {
      const run = launch(runtime, 'context', {...event, hook_event_name: 'SessionStart'});
      assert.equal(run.status, 0, run.stderr + String(run.error ?? ''));
      const output = JSON.parse(run.stdout); assert.equal(output.hookSpecificOutput.hookEventName, 'SessionStart');
      assert.ok(output.hookSpecificOutput.additionalContext.startsWith(fs.readFileSync(path.join(root, 'hooks/session-context.md'), 'utf8')));
      assert.match(output.hookSpecificOutput.additionalContext, /HARNESS_STATE_JSON/);
    });
    check(`${runtime}: protected patch denial preserves exit 2 and stderr`, () => {
      const patch = `*** Begin Patch\n*** Add File: ${path.join(repo, '보호 파일.txt')}\n+x\n*** End Patch`;
      const run = launch(runtime, 'guard', {...event, hook_event_name: 'PreToolUse', tool_name: 'apply_patch', tool_input: {command: patch}});
      assert.equal(run.status, 2, run.stderr); assert.match(run.stderr, /GUARD-DENY/);
    });
    check(`${runtime}: Stop recursion uses native handler and clean exit`, () => {
      const run = launch(runtime, 'stop', {...event, hook_event_name: 'Stop', stop_hook_active: true});
      assert.equal(run.status, 0, run.stderr); assert.equal(run.stdout, '');
    });
    check(`${runtime}: missing Node is launch UNREACHED, never a successful handler`, () => {
      const noNode = path.join(temp, 'no-node'); fs.mkdirSync(noNode, {recursive: true});
      const search = process.platform === 'win32' ? path.join(baseEnv.SystemRoot, 'System32/WindowsPowerShell/v1.0') : noNode;
      const run = launch(runtime, 'context', {...event, hook_event_name: 'SessionStart'}, {PATH: search});
      if (runtime === 'claude') { assert.equal(run.error?.code, 'ENOENT'); assert.notEqual(run.status, 0); }
      else { assert.equal(run.status, 2, run.stderr); assert.ok(run.stderr); }
    });
  }
  check('invalid runtime cannot silently select another handler', () => assert.throws(() => hookTransport('guard', 'unknown'), /unknown/));
  console.log(`PASS hook transports: ${count} judgments on ${process.platform}; exact configured launch only, runtime trust/load/fire not established`);
} finally { fs.rmSync(temp, {recursive: true, force: true}); }
