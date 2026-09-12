import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {compareRuntimeParity, parityContract, parityContractSha256, parityScenarioIds} from '../../plugins/harness/lib/runtime/parity-contract.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const support = fs.readFileSync(new URL('../../plugins/harness/docs/runtime-parity.md', import.meta.url), 'utf8');
const baseline = {repository: 'fixture:canonical-repo', sourceSha256: 'a'.repeat(64), configSha256: 'b'.repeat(64),
  contractSha256: parityContractSha256, origin: 'fixture', inputs: Object.fromEntries(parityScenarioIds.map(id => [id, 'c'.repeat(64)]))};
const reports = parityContract.surfaces.map(surface => ({
  schemaVersion: 1, surface, version: 'fixture-version', platform: 'darwin', ...baseline,
  capabilities: Object.fromEntries(parityContract.contracts.map(({id}) => [id, {status: 'AVAILABLE', mode: surface === 'codex-desktop' ? 'harness' : 'native', reference: `fixture:${surface}/${id}`} ])),
  scenarios: Object.fromEntries(parityScenarioIds.map(id => [id, {outcome: 'MATCH', inputSha256: baseline.inputs[id],
    stages: {static: 'MATCH', loaded: 'MATCH', live: 'MATCH'}, evidence: {reference: `fixture:${surface}/${id}`, surface, scenario: id, origin: 'fixture'}}])),
}));
assert.equal(compareRuntimeParity(baseline, reports, support).status, 'MATCH');
assert.equal(compareRuntimeParity(baseline, reports, support).liveCertified, false);
const reject = (base, rows, doc = support, message = '') => {
  const result = compareRuntimeParity(base, rows, doc);
  assert.equal(result.status, 'MISMATCH', message);
  assert.ok(result.issues.length > 0, message);
  assert.ok(result.issues.every(issue => issue.path && issue.reason));
};
for (const value of [null, [], {}, 'invalid']) reject(value, reports);
for (const key of Object.keys(baseline)) { const bad = structuredClone(baseline); delete bad[key]; reject(bad, reports, support, `baseline ${key}`); }
reject(baseline, null);
reject(baseline, [...reports, reports[0]]);
reject(baseline, reports, support.replace('| native or harness;', '| native only;'));
reject(baseline, reports, support + '\n<!-- parity-contract:start -->');
for (let index = 0; index < reports.length; index++) {
  reject(baseline, reports.filter((_, i) => i !== index));
  for (const key of ['schemaVersion', 'repository', 'sourceSha256', 'configSha256', 'contractSha256', 'version', 'platform', 'origin', 'capabilities', 'scenarios']) {
    const bad = structuredClone(reports); delete bad[index][key]; reject(baseline, bad, support, `missing ${key}`);
  }
  for (const [key, value] of [['repository', 'fixture:other'], ['sourceSha256', 'd'.repeat(64)], ['configSha256', 'e'.repeat(64)], ['contractSha256', 'f'.repeat(64)], ['origin', 'live'], ['platform', 'linux'], ['version', 'UNKNOWN']]) {
    const bad = structuredClone(reports); bad[index][key] = value; reject(baseline, bad, support, key);
  }
  for (const {id} of parityContract.contracts) {
    for (const state of ['UNKNOWN', 'UNAVAILABLE', 'UNREACHED', undefined]) {
      const bad = structuredClone(reports); bad[index].capabilities[id].status = state; reject(baseline, bad, support, `${id} ${state}`);
    }
    const bad = structuredClone(reports); bad[index].capabilities[id].mode = 'prompt-only'; reject(baseline, bad);
  }
  for (const id of parityScenarioIds) {
    for (const mutate of [
      row => delete row.scenarios[id],
      row => row.scenarios[id].outcome = 'UNKNOWN',
      row => row.scenarios[id].outcome = 0,
      row => row.scenarios[id].inputSha256 = 'd'.repeat(64),
      row => row.scenarios[id].evidence.surface = 'other',
      row => row.scenarios[id].evidence.scenario = 'other',
      row => row.scenarios[id].evidence.origin = 'live',
      row => row.scenarios[id].evidence.reference = '',
      ...['static', 'loaded', 'live'].map(stage => row => row.scenarios[id].stages[stage] = 'UNREACHED'),
    ]) { const bad = structuredClone(reports); mutate(bad[index]); reject(baseline, bad, support, id); }
  }
}

const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'parity-contract-'));
try {
  const canonicalFile = path.join(temp, 'canonical.json');
  const reportFile = path.join(temp, 'reports.json');
  fs.writeFileSync(canonicalFile, JSON.stringify(baseline));
  fs.writeFileSync(reportFile, JSON.stringify(reports));
  const cli = path.join(root, 'plugins/harness/scripts/runtime-parity.mjs');
  let run = spawnSync(process.execPath, [cli, canonicalFile, reportFile], {encoding: 'utf8'});
  assert.equal(run.status, 0, run.stderr);
  assert.equal(JSON.parse(run.stdout).status, 'MATCH');
  fs.writeFileSync(reportFile, JSON.stringify(reports.slice(1)));
  run = spawnSync(process.execPath, [cli, canonicalFile, reportFile], {encoding: 'utf8'});
  assert.equal(run.status, 1, run.stderr); assert.match(run.stdout, /missing or duplicate surface/);
  fs.writeFileSync(reportFile, '{');
  run = spawnSync(process.execPath, [cli, canonicalFile, reportFile], {encoding: 'utf8'});
  assert.equal(run.status, 1); assert.match(run.stderr, /MISMATCH/);
  if (!process.argv.includes('--mutation-child')) {
    // Mutate a disposable copy, including this same regression test. A failure
    // accepting comparator must make the existing negative assertions fail.
    for (const file of ['plugins/harness/lib/runtime/parity-contract.mjs', 'plugins/harness/docs/runtime-parity.md', 'tests/harness/runtime-parity-contract-check.mjs']) {
      const target = path.join(temp, file); fs.mkdirSync(path.dirname(target), {recursive: true}); fs.copyFileSync(path.join(root, file), target);
    }
    const module = path.join(temp, 'plugins/harness/lib/runtime/parity-contract.mjs');
    const original = fs.readFileSync(module, 'utf8');
    const mutated = original.replace("issues.length ? 'MISMATCH' : 'MATCH'", "'MATCH'");
    assert.notEqual(mutated, original); fs.writeFileSync(module, mutated);
    run = spawnSync(process.execPath, [path.join(temp, 'tests/harness/runtime-parity-contract-check.mjs'), '--mutation-child'], {encoding: 'utf8'});
    assert.equal(run.status, 1, run.stderr);
    assert.match(run.stderr, /AssertionError/);
    console.log('PASS: temporary accept-failures mutation rejected by the same regression (child rc 1)');
  }
} finally { fs.rmSync(temp, {recursive: true, force: true}); }
console.log('PASS: four-surface normalized fixture comparison and required-field/scenario/document negative controls; no live certification');
