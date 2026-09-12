import {createHash} from 'node:crypto';

// Required semantics, not product-specific paths, model IDs or native event names.
const definitions = [
  ['C1', 'Canonical source', ['repository', 'config', 'instructions', 'skills', 'roles']],
  ['C2', 'Instructions and skills', ['policy-loaded', 'skills-discovered', 'duplicate-rejected', 'override-omission-rejected']],
  ['C3', 'Roles and tools', ['implementer-tools', 'reviewer-read', 'reviewer-write-denied', 'evaluator-tools', 'author-grader-independent', 'identity-mismatch-rejected']],
  ['C4', 'Permission boundaries', ['worktree-write', 'main-write-denied', 'protected-write-denied', 'remote-canary-denied', 'malformed-payload-rejected', 'ambiguous-workspace-rejected']],
  ['C5', 'Preparation and checks', ['bootstrap-input', 'check-input', 'bootstrap-failure-preserved', 'check-failure-preserved']],
  ['C6', 'Ledger and resume', ['ledger-coordinates', 'actor-ownership', 'explicit-rebind', 'cancel-isolated']],
  ['C7', 'Stop and completion', ['unfinished-continued', 'cancel-respected', 'error-preserved', 'resume-bounded', 'missing-completion-rejected']],
  ['C8', 'Model policy', ['parent-inherited', 'role-selection', 'explicit-override', 'unsupported-override-rejected', 'actual-selection-recorded']],
  ['C9', 'Installation lifecycle', ['clean-install', 'existing-install', 'user-edits-preserved', 'managed-policy-preserved', 'update', 'stale-rejected', 'duplicate-rejected', 'rollback']],
  ['C10', 'Complete scenario coverage', ['new-session', 'resumed-session', 'updated-session', 'unrun-rejected', 'cross-surface-evidence-rejected']],
];
const freeze = value => {
  if (value && typeof value === 'object') { Object.values(value).forEach(freeze); Object.freeze(value); }
  return value;
};
export const parityContract = freeze({
  schemaVersion: 1,
  surfaces: ['claude-cli', 'codex-cli', 'codex-desktop', 'antigravity-cli'],
  contracts: definitions.map(([id, title, scenarios]) => ({id, title, scenarios})),
  // A supported path is a requirement for an adapter, not an installed-support claim.
  capabilityModes: ['native', 'harness'],
});
export const parityContractSha256 = createHash('sha256').update(JSON.stringify(parityContract)).digest('hex');
export const parityScenarioIds = Object.freeze(parityContract.contracts.flatMap(c => c.scenarios.map(s => `${c.id}/${s}`)));

export function renderParitySupportTable() {
  return ['| Contract | Required scenarios | Required surfaces | Permitted implementation path |',
    '|---|---|---|---|', ...parityContract.contracts.map(c =>
      `| ${c.id}: ${c.title} | ${c.scenarios.join(', ')} | ${parityContract.surfaces.join(', ')} | native or harness; observation required |`)].join('\n');
}

const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const text = value => typeof value === 'string' && value.trim().length > 0 &&
  !['UNKNOWN', 'UNAVAILABLE', 'UNREACHED'].includes(value.trim().toUpperCase());
const hash = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const exactKeys = (value, keys) => object(value) && Object.keys(value).length === keys.length && keys.every(k => Object.hasOwn(value, k));

/** Compare normalized reports to an independently obtained canonical baseline.
 * No I/O, provider invocation, authenticity check, ledger close or live certification.
 * A fixture MATCH only proves the supplied fixture agrees with the common contract.
 */
export function compareRuntimeParity(baseline, reports, supportDocument) {
  const issues = [];
  const require = (path, condition, reason) => { if (!condition) issues.push({path, reason}); };
  require('supportDocument', typeof supportDocument === 'string' &&
    supportDocument.split('<!-- parity-contract:start -->').length === 2 &&
    supportDocument.split('<!-- parity-contract:end -->').length === 2 &&
    supportDocument.split('<!-- parity-contract:start -->')[1]?.split('<!-- parity-contract:end -->')[0]?.trim() === renderParitySupportTable(),
  'support documentation does not match required capabilities and scenarios');
  require('baseline.repository', text(baseline?.repository), 'canonical repository identity is required');
  for (const key of ['sourceSha256', 'configSha256']) require(`baseline.${key}`, hash(baseline?.[key]), 'canonical content hash is required');
  require('baseline.contractSha256', baseline?.contractSha256 === parityContractSha256, 'contract schema is stale or unknown');
  require('baseline.inputs', exactKeys(baseline?.inputs, parityScenarioIds) && parityScenarioIds.every(id => hash(baseline?.inputs?.[id])), 'every scenario requires a canonical input digest');
  require('baseline.origin', ['fixture', 'live'].includes(baseline?.origin), 'origin must explicitly distinguish fixture from live');
  const rows = Array.isArray(reports) ? reports : [];
  require('reports', rows.length === parityContract.surfaces.length, 'all four required surfaces must appear exactly once');
  for (const row of rows) require('reports.surface', parityContract.surfaces.includes(row?.surface), 'unknown surface');
  for (const surface of parityContract.surfaces) {
    const matches = rows.filter(r => r?.surface === surface);
    require(surface, matches.length === 1, 'missing or duplicate surface; CLI cannot stand in for desktop');
    const row = matches[0];
    if (!row) continue;
    require(`${surface}.schemaVersion`, row.schemaVersion === parityContract.schemaVersion, 'unknown report schema');
    for (const key of ['repository', 'sourceSha256', 'configSha256', 'contractSha256'])
      require(`${surface}.${key}`, row[key] === baseline?.[key] && text(row[key]), 'missing, stale or different canonical source/repository');
    require(`${surface}.version`, text(row.version), 'actual surface version is required');
    require(`${surface}.platform`, row.platform === 'darwin', 'this contract covers the agreed macOS surfaces only');
    require(`${surface}.origin`, row.origin === baseline?.origin, 'fixture and live reports cannot be combined');
    require(`${surface}.capabilities`, exactKeys(row.capabilities, definitions.map(d => d[0])), 'required capability inventory is missing or unknown');
    for (const {id} of parityContract.contracts) {
      const capability = row.capabilities?.[id];
      require(`${surface}.${id}.status`, capability?.status === 'AVAILABLE', 'required capability is missing, UNKNOWN or UNAVAILABLE');
      require(`${surface}.${id}.mode`, parityContract.capabilityModes.includes(capability?.mode), 'implementation must name an observed native or harness path');
      require(`${surface}.${id}.reference`, text(capability?.reference), 'capability requires an implementation/evidence reference');
    }
    require(`${surface}.scenarios`, exactKeys(row.scenarios, parityScenarioIds), 'required scenario missing or unknown');
    for (const id of parityScenarioIds) {
      const result = row.scenarios?.[id];
      require(`${surface}.${id}.outcome`, result?.outcome === 'MATCH', 'required semantic outcome not reached; transport exit 0 is insufficient');
      require(`${surface}.${id}.inputSha256`, hash(result?.inputSha256) && result.inputSha256 === baseline?.inputs?.[id], 'scenario input differs from canonical input');
      const evidence = result?.evidence;
      require(`${surface}.${id}.evidence`, text(evidence?.reference) && evidence?.surface === surface && evidence?.scenario === id && evidence?.origin === baseline?.origin,
        'missing or misattributed evidence; a different surface/scenario cannot supply this result');
      require(`${surface}.${id}.stages`, exactKeys(result?.stages, ['static', 'loaded', 'live']) &&
        ['static', 'loaded', 'live'].every(stage => result.stages[stage] === 'MATCH'),
      'static, loaded and live semantic checks must each be reached (fixture origin remains synthetic)');
    }
  }
  return {status: issues.length ? 'MISMATCH' : 'MATCH', scope: 'normalized-report-comparison',
    origin: baseline?.origin ?? 'unknown', liveCertified: false, issues};
}
