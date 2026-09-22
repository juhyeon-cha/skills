import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import childProcess from 'node:child_process';
import {syncBuiltinESMExports} from 'node:module';
import {explainRole} from '../../plugins/harness/lib/runtime/role-explanation.mjs';
import {projectRole, registerRoles} from '../../plugins/harness/lib/runtime/roles.mjs';

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
  for (const [runtime, execution] of [['codex', 'native'], ['claude', 'native'], ['antigravity', 'native']]) {
    const report = explainRole({runtime, role: 'reviewer', execution}, root);
    const expected = projectRole(runtime, 'reviewer', root);
    assert.deepEqual(report.canonical, {file: expected.source, sha256: expected.sha256});
    assert.equal(report.native.rendered, expected.text);
    assert.equal(report.native.applicableToSelectedPath, execution === 'native');
    assert.equal(report.native.loading, 'unverified');
    assert.equal(report.native.artifact, runtime === 'claude' ? path.join(root, 'agents/reviewer.md') : null);
    assert.equal(report.native.source, path.join(root, 'native', runtime, `reviewer.${runtime === 'codex' ? 'toml' : 'md'}`));
    assert.deepEqual(report.observed, {model: 'unknown', reasoningEffort: 'unknown'});
    assert.equal(report.enforcement, 'unverified');
    assert.equal(report.requestProvenance, 'caller-supplied-not-dispatched');
    assert.equal(report.requested, null);
    assert.equal('selectedDispatchOptions' in report, false);
  }
  const modelOptions = {model: 'gpt-5.6-sol', reasoning_effort: 'high', availableModels: ['gpt-5.6-sol']};
  const report = explainRole({runtime: 'codex', role: 'reviewer', execution: 'native', modelOptions}, root);
  assert.deepEqual(report.requested, modelOptions);
  assert.equal('selectedDispatchOptions' in report, false);
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

const run = value => {
  fs.writeFileSync(input, JSON.stringify(value));
  const beforeQuery = snapshot(fixture);
  const result = childProcess.spawnSync(process.execPath, [path.join(root, 'scripts/roles.mjs'), 'explain', input], {encoding: 'utf8'});
  assert.deepEqual(snapshot(fixture), beforeQuery, 'CLI must not modify its input or plugin');
  assert.equal(result.stderr, '');
  return {status: result.status, report: JSON.parse(result.stdout)};
};
const base = {runtime: 'codex', role: 'reviewer', execution: 'native'};
for (const invalid of [null, [], 'codex', {...base, typo: true}, {...base, runtime: 'other'},
  {...base, role: '../reviewer'}, {...base, role: 'other'}, {...base, execution: 'loaded'},
  {...base, execution: 'generic'}, {...base, installedRoot: '.'},
  {...base, installedRoot: null}, ...[null, [], 'sol', {unknown: true}, {model: ''}, {model: 1},
    {availableModels: 'sol'}, {availableModels: [1]}, {reasoning_effort: 'high'},
    {model: 'sol', availableModels: []}, {model: 'sol', reasoning_effort: 1}]
    .map(modelOptions => ({...base, modelOptions})),
  ...['claude', 'antigravity'].flatMap(runtime => [
    {...base, runtime, modelOptions: {availableModels: 'invalid'}},
    {...base, runtime, modelOptions: {model: '   '}},
  ]),
  {...base, execution: 'native', modelOptions: {model: 'sol', availableModels: []}},
  {...base, runtime: 'claude', execution: 'native', modelOptions: {model: 'sol'}},
  {...base, runtime: 'antigravity', execution: 'native', modelOptions: {model: 'sol'}},
  {...base, runtime: 'antigravity', execution: 'native', modelOptions: {model: 'pro', reasoning_effort: 'high'}},
]) {
  const result = run(invalid);
  assert.equal(result.status, 1, JSON.stringify(invalid));
  assert.equal(result.report.status, 'UNREACHED');
  assert.equal(typeof result.report.reason, 'string');
  assert.equal(result.report.observed, undefined);
}
for (const runtime of ['claude', 'codex', 'antigravity']) {
  const modelOptions = runtime === 'antigravity' ? {model: 'pro'} : {model: 'chosen', availableModels: ['chosen']};
  const {status, report} = run({...base, runtime, execution: 'native', modelOptions});
  assert.equal(status, 0);
  assert.deepEqual(report.requested, modelOptions);
  assert.equal('selectedDispatchOptions' in report, false);
  assert.deepEqual(report.observed, {model: 'unknown', reasoningEffort: 'unknown'});
  assert.equal(report.native.loading, 'unverified');
  assert.equal(report.native.rendered, projectRole(runtime, 'reviewer', root).text);
}
const destination = path.join(fixture, 'registered');
const registration = registerRoles('codex', destination, root);
const codexReport = run(base).report;
assert.equal(codexReport.native.rendered, fs.readFileSync(registration.roles.find(role => role.role === 'reviewer').file, 'utf8'));
assert.deepEqual(explainRole(base, `${root}/`), explainRole(base, root));
const installedRoot = path.join(fixture, 'explicit install');
assert.equal(run({...base, installedRoot}).report.native.rendered, projectRole('codex', 'reviewer', root, installedRoot).text);
const template = path.join(root, 'native/codex/reviewer.toml');
const original = fs.readFileSync(template, 'utf8');
const advanced = original.replace('# HARNESS_ROLE_INSTRUCTIONS', 'model = "user-model"\nmodel_reasoning_effort = "high"\n# HARNESS_ROLE_INSTRUCTIONS\n[advanced]\nflag = true');
fs.writeFileSync(template, advanced);
assert.equal(run(base).report.native.rendered, projectRole('codex', 'reviewer', root).text);
assert.match(run(base).report.native.rendered, /\[advanced\]\nflag = true/);
for (const corrupted of [original.replace('# HARNESS_ROLE_INSTRUCTIONS', ''), `${original}\n# HARNESS_ROLE_INSTRUCTIONS\n`]) {
  fs.writeFileSync(template, corrupted);
  assert.equal(run(base).status, 1);
}
fs.renameSync(template, `${template}.absent`);
assert.equal(run(base).status, 1);
fs.renameSync(`${template}.absent`, template);
fs.writeFileSync(template, original);
const canonical = path.join(root, 'roles/reviewer.md');
fs.renameSync(canonical, `${canonical}.absent`);
assert.equal(run(base).status, 1);
fs.renameSync(`${canonical}.absent`, canonical);
fs.writeFileSync(input, '{');
assert.equal(childProcess.spawnSync(process.execPath, [path.join(root, 'scripts/roles.mjs'), 'explain', input]).status, 1);
assert.equal(childProcess.spawnSync(process.execPath, [path.join(root, 'scripts/roles.mjs'), 'explain']).status, 1);
console.log('PASS role explanation: invalid requests/source fail, native requests remain unobserved, CLI is read-only and matches registration');
