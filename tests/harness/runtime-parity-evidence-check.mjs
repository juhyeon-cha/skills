import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {inspectParityEvidence, sha256} from './runtime-parity-evidence.mjs';
import {parityContract, parityContractSha256, parityScenarioIds} from '../../plugins/harness/lib/runtime/parity-contract.mjs';

const support = fs.readFileSync(new URL('../../plugins/harness/docs/runtime-parity.md', import.meta.url), 'utf8');
if (process.argv[2]) {
  const file = path.resolve(process.argv[2]);
  try {
    const result = inspectParityEvidence(JSON.parse(fs.readFileSync(file)), path.dirname(file), support);
    console.log(JSON.stringify(result, null, 2));
    process.exitCode = result.status === 'MATCH' ? 0 : 1;
  } catch (error) { console.error(error.message); process.exitCode = 1; }
} else {
  const directory = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'parity-evidence-check-'));
  try {
    const baseline = {repository: 'synthetic-repository', sourceSha256: 'a'.repeat(64), configSha256: 'b'.repeat(64),
      contractSha256: parityContractSha256, origin: 'live', inputs: Object.fromEntries(parityScenarioIds.map(id => [id, sha256(id)]))};
    // Deliberately synthetic input claiming live exercises the integrity layer;
    // it never sets liveCertified, even when every structural check matches.
    const observations = parityContract.surfaces.map(surface => {
      const files = ['invocation', 'stdout', 'stderr', 'exit', 'hook'].map(kind => {
        const name = `${surface}-${kind}.txt`; fs.writeFileSync(path.join(directory, name), `${surface}/${kind}`);
        return {kind, path: name, sha256: sha256(`${surface}/${kind}`)};
      });
      return {id: surface, surface, version: 'synthetic-version', sessionId: `${surface}-session`, workspace: '/synthetic',
        command: 'synthetic', args: [], repository: baseline.repository, sourceSha256: baseline.sourceSha256,
        configSha256: baseline.configSha256, exitCode: 0, signal: null, origin: 'live', kind: 'provider-execution', files};
    });
    const reports = parityContract.surfaces.map(surface => ({...baseline, schemaVersion: 1, surface, version: 'synthetic-version', platform: 'darwin',
      capabilities: Object.fromEntries(parityContract.contracts.map(({id}) => [id, {status: 'AVAILABLE', mode: 'harness', reference: surface}])),
      scenarios: Object.fromEntries(parityScenarioIds.map(id => [id, {outcome: 'MATCH', inputSha256: baseline.inputs[id], stages: {static: 'MATCH', loaded: 'MATCH', live: 'MATCH'},
        evidence: {surface, scenario: id, origin: 'live', observationId: surface, reference: `${surface}-hook.txt`, assertion: id, expected: 'synthetic-result', actual: 'synthetic-result'}}]))}));
    const bundle = {schemaVersion: 1, baseline, observations, reports};
    assert.equal(inspectParityEvidence(bundle, directory, support).status, 'MATCH');
    assert.equal(inspectParityEvidence(bundle, directory, support).liveCertified, false);
    const rejected = mutate => { const copy = structuredClone(bundle); mutate(copy); assert.equal(inspectParityEvidence(copy, directory, support).status, 'MISMATCH'); };
    for (const mutate of [
      x => x.baseline.origin = 'fixture', x => x.reports.pop(), x => x.observations.pop(),
      x => x.observations.push(x.observations[0]), x => x.observations[0].sourceSha256 = 'c'.repeat(64),
      x => x.observations[0].surface = 'codex-desktop', x => x.observations[0].version = 'UNKNOWN',
      x => x.observations[0].signal = 'SIGTERM', x => delete x.observations[0].sessionId,
      x => x.observations[0].files.pop(), x => x.observations[0].files[0].path = '../escape',
      x => x.observations[0].files[0].sha256 = '0'.repeat(64),
      x => x.reports[0].scenarios[parityScenarioIds[0]].evidence.observationId = 'codex-cli',
      x => x.reports[0].scenarios[parityScenarioIds[0]].evidence.actual = 'UNREACHED',
      x => x.reports[0].scenarios[parityScenarioIds[0]].evidence.reference = 'not-recorded',
    ]) rejected(mutate);
    fs.writeFileSync(path.join(directory, observations[0].files[0].path), 'tampered');
    assert.equal(inspectParityEvidence(bundle, directory, support).status, 'MISMATCH');
    console.log('PASS: synthetic evidence integrity/coverage controls; no live certification. Supply an actual bundle path to judge live coverage.');
  } finally { fs.rmSync(directory, {recursive: true, force: true}); }
}
