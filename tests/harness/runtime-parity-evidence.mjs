import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {compareRuntimeParity, parityContract, parityScenarioIds} from '../../plugins/harness/lib/runtime/parity-contract.mjs';

export const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const hash = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const present = value => typeof value === 'string' && value.trim() && !/^(UNKNOWN|UNREACHED|UNAVAILABLE)$/i.test(value);

// Developer-side integrity checks. Local files and operator observations are not
// signed provider attestations: independent evaluation must still inspect them.
export function inspectParityEvidence(bundle, directory, support) {
  const normalized = compareRuntimeParity(bundle?.baseline, bundle?.reports, support);
  const issues = [...normalized.issues];
  const require = (at, condition, reason) => { if (!condition) issues.push({path: at, reason}); };
  require('bundle.schemaVersion', bundle?.schemaVersion === 1, 'unknown evidence schema');
  require('bundle.origin', bundle?.baseline?.origin === 'live', 'fixtures cannot certify live execution');
  const observations = Array.isArray(bundle?.observations) ? bundle.observations : [];
  const ids = new Set();
  for (const observation of observations) {
    const at = `observations.${observation?.id}`;
    require(at, present(observation?.id) && !ids.has(observation.id), 'missing or duplicate observation ID');
    ids.add(observation?.id);
    require(at, parityContract.surfaces.includes(observation?.surface), 'unrecognized actual surface');
    require(at, observation?.origin === 'live' && observation?.kind === 'provider-execution', 'actual provider execution required');
    for (const key of ['version', 'sessionId', 'workspace', 'command']) require(`${at}.${key}`, present(observation?.[key]), 'execution coordinate missing');
    require(at, observation?.repository === bundle?.baseline?.repository && observation?.sourceSha256 === bundle?.baseline?.sourceSha256,
      'observation repository/source mismatch');
    require(at, observation?.configSha256 === bundle?.baseline?.configSha256, 'observation config mismatch');
    require(at, Array.isArray(observation?.args) && observation.args.every(v => typeof v === 'string'), 'structured execution argv required');
    require(at, Number.isInteger(observation?.exitCode) && observation?.signal === null, 'execution must finish with recorded exit and no signal');
    require(at, Array.isArray(observation?.files) && observation.files.length > 0, 'raw execution files missing');
    const files = new Set();
    for (const file of observation?.files ?? []) {
      try {
        require(at, ['invocation', 'stdout', 'stderr', 'exit', 'hook'].includes(file?.kind), 'unknown raw evidence kind');
        if (!present(file?.path) || path.isAbsolute(file.path) || file.path.split(/[\\/]/).some(p => p === '..' || !p)) throw new Error('relative evidence path required');
        const root = fs.realpathSync(directory);
        const resolved = fs.realpathSync(path.join(root, file.path));
        if (!resolved.startsWith(root + path.sep) || !fs.statSync(resolved).isFile()) throw new Error('evidence escapes bundle or is not a file');
        require(at, hash(file.sha256) && sha256(fs.readFileSync(resolved)) === file.sha256, 'missing, changed or stale raw evidence');
        require(at, !files.has(file.path), 'duplicate raw evidence path');
        files.add(file.path);
      } catch (error) { issues.push({path: at, reason: error.message}); }
    }
    for (const kind of ['invocation', 'stdout', 'stderr', 'exit', 'hook'])
      require(at, observation?.files?.some(file => file.kind === kind), `missing ${kind} evidence`);
  }
  for (const row of bundle?.reports ?? []) {
    for (const scenario of parityScenarioIds) {
      const evidence = row?.scenarios?.[scenario]?.evidence;
      const observation = observations.find(item => item.id === evidence?.observationId);
      require(`${row?.surface}.${scenario}`, observation && observation.surface === row.surface && observation.version === row.version,
        'scenario lacks its own surface/version execution');
      require(`${row?.surface}.${scenario}`, present(evidence?.assertion) && present(evidence?.expected) && present(evidence?.actual) && evidence?.actual === evidence?.expected,
        'concrete expected/observed semantic assertion required');
      require(`${row?.surface}.${scenario}`, observation?.files?.some(file => file.path === evidence?.reference), 'scenario reference not in hashed execution files');
    }
  }
  return {status: issues.length ? 'MISMATCH' : 'MATCH', liveCertified: false,
    scope: 'local-evidence-integrity-and-coverage', independentEvaluationRequired: true, issues};
}
