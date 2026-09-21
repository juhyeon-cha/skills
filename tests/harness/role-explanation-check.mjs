import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import childProcess from 'node:child_process';
import {syncBuiltinESMExports} from 'node:module';
import {explainRole} from '../../plugins/harness/lib/runtime/role-explanation.mjs';
import {projectRole} from '../../plugins/harness/lib/runtime/roles.mjs';

const plugin = fileURLToPath(new URL('../../plugins/harness/', import.meta.url));
const fixture = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'role-explanation-')));
const root = path.join(fixture, 'plugin');
fs.cpSync(plugin, root, {recursive: true});
const snapshot = dir => fs.readdirSync(dir, {withFileTypes: true}).sort((a, b) => a.name.localeCompare(b.name))
  .flatMap(entry => entry.isDirectory() ? snapshot(path.join(dir, entry.name))
    : [[path.relative(fixture, path.join(dir, entry.name)), fs.readFileSync(path.join(dir, entry.name)).toString('base64')]]);
const before = snapshot(fixture);
const originalFetch = globalThis.fetch;
const originals = {};
try {
  for (const name of ['spawn', 'spawnSync', 'exec', 'execSync', 'execFile', 'execFileSync', 'fork']) {
    originals[name] = childProcess[name];
    childProcess[name] = () => { throw new Error(`unexpected subprocess: ${name}`); };
  }
  syncBuiltinESMExports();
  globalThis.fetch = () => { throw new Error('unexpected fetch'); };
  for (const [runtime, execution] of [['codex', 'generic'], ['codex', 'native'], ['claude', 'native'], ['antigravity', 'native']]) {
    const report = explainRole({runtime, role: 'reviewer', execution}, root);
    const expected = projectRole(runtime, 'reviewer', root);
    assert.deepEqual(report.canonical, {file: expected.source, sha256: expected.sha256});
    assert.equal(report.native.rendered, expected.text);
    assert.equal(report.native.applicableToSelectedPath, execution === 'native');
    assert.equal(report.native.loading, 'unverified');
    assert.equal(report.native.artifact, runtime === 'claude' ? path.join(root, 'agents/reviewer.md') : null);
    assert.equal(report.native.source, path.join(root, 'native', runtime, `reviewer.${runtime === 'codex' ? 'toml' : 'md'}`));
    assert.deepEqual(report.observed, {model: 'unknown', reasoningEffort: 'unknown'});
    assert.equal(report.enforcement, execution === 'generic' ? 'unavailable' : 'unverified');
    assert.equal(report.requestProvenance, 'caller-supplied-not-dispatched');
    assert.equal(report.requested, null);
    assert.deepEqual(report.selectedDispatchOptions, execution === 'generic' ? {} : null);
  }
  const modelOptions = {model: 'gpt-5.6-sol', reasoning_effort: 'high', availableModels: ['gpt-5.6-sol']};
  const report = explainRole({runtime: 'codex', role: 'reviewer', execution: 'generic', modelOptions}, root);
  assert.deepEqual(report.requested, modelOptions);
  assert.deepEqual(report.selectedDispatchOptions, {model: 'gpt-5.6-sol', reasoning_effort: 'high', fork_turns: 'none'});
  assert.deepEqual(report.observed, {model: 'unknown', reasoningEffort: 'unknown'});
  assert.deepEqual(snapshot(fixture), before);
} finally {
  Object.assign(childProcess, originals);
  syncBuiltinESMExports();
  globalThis.fetch = originalFetch;
}
const input = path.join(fixture, 'input.json');
fs.writeFileSync(input, JSON.stringify({runtime: 'claude', role: 'implementer', execution: 'native'}));
const cli = childProcess.spawnSync(process.execPath, [path.join(root, 'scripts/roles.mjs'), 'explain', input], {encoding: 'utf8'});
assert.equal(cli.status, 0, cli.stdout + cli.stderr);
assert.equal(JSON.parse(cli.stdout).canonical.file, path.join(root, 'roles/implementer.md'));
console.log('PASS role explanation: source, declaration, request and unknown observation remain distinct; fixture unchanged');
