import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { delegationCapability } from '../../plugins/harness/lib/runtime/delegation.mjs';
import { diagnoseDelegation, diagnose } from '../../plugins/harness/lib/runtime/doctor.mjs';
import { loadRole, registerRoles, roleCall, roleResult } from '../../plugins/harness/lib/runtime/roles.mjs';
import { inspectDistribution, generateDistribution } from '../../plugins/harness/lib/distribution.mjs';

// Synthetic tool returns exercise integration; live provenance is judged separately.
const root = fileURLToPath(new URL('../../', import.meta.url));
const plugin = path.join(root, 'plugins/harness');
const temp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'delegation-integration-')));
const repo = path.join(temp, 'repo');
const env = { ...process.env, GIT_CONFIG_GLOBAL: os.devNull, GIT_CONFIG_NOSYSTEM: '1' };
for (const key of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR', 'HARNESS_ROOT'])
  delete env[key];
let count = 0, sequence = 0;
const check = (condition, why) => { assert.ok(condition, why); count++; };
const file = (value) => {
  const target = path.join(temp, `input-${sequence++}.json`);
  fs.writeFileSync(target, JSON.stringify(value));
  return target;
};
function run(script, args, expected = 0, target = plugin) {
  const result = spawnSync(process.execPath, [path.join(target, 'scripts', script), ...args], { env, encoding: 'utf8' });
  assert.equal(result.status, expected, `${script} ${args[0]}: ${result.stdout}\n${result.stderr}`);
  count++;
  return JSON.parse(result.stdout);
}
const delegation = (action, value, expected = 0) => run('delegation.mjs', [action, file(value)], expected);
const observe = (tool, value) => ({ source: 'parent-tool-return', tool: `collaboration.${tool}`, value });
const git = (...args) => {
  const result = spawnSync('git', ['-C', repo, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', ...args], { env, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
};
try {
  check(diagnoseDelegation === delegationCapability, 'doctor uses the execution capability function itself');
  fs.mkdirSync(repo);
  git('init', '-qb', 'fixture');
  fs.writeFileSync(path.join(repo, '.harness.json'), '{}\n');
  git('add', '.'); git('commit', '-qm', 'base');
  const base = git('rev-parse', 'HEAD');
  const common = {
    version: 1, runtime: 'codex', provider: 'collaboration', repository: repo,
    data: path.join(temp, 'data'), sessionId: 'fixture-session', parentAgentId: '/root',
  };
  const make = (role, changes = {}) => ({
    ...common, callId: `call-${sequence++}`, role, task: 'fixture#1',
    sourceHash: loadRole(role).sha256,
    commitScope: { mode: 'fixed', base, head: base, branch: 'fixture' },
    implementerIds: [], previousAgentIds: [], permission: 'prompt-only', ...changes,
  });
  for (const request of [
    { runtime: 'codex', provider: 'collaboration', permission: 'prompt-only' },
    { runtime: 'codex', provider: 'collaboration', permission: 'enforced' },
    { runtime: 'codex', provider: 'collaboration' },
    { runtime: 'claude', provider: 'collaboration', permission: 'prompt-only' },
    { runtime: 'codex', provider: 'native', permission: 'prompt-only' },
  ]) {
    const expected = request.runtime === 'codex' && request.provider === 'collaboration' && request.permission === 'prompt-only' ? 0 : 1;
    const capability = delegation('capability', request, expected);
    assert.deepEqual(capability, run('doctor.mjs', ['delegation', file(request)], expected)); count++;
    assert.deepEqual(capability, delegationCapability(request)); count++;
    check(capability.automaticNativeFallback === false && capability.enforcement === 'unavailable', 'availability is explicit and does not imply enforcement');
    const call = make('implementer', { ...request, permission: request.permission ?? 'unspecified' });
    const begin = delegation('begin', call, expected);
    check(begin.status === (expected ? 'REJECTED' : 'PENDING'), 'execution and diagnostics agree');
    if (expected) check(begin.reason === capability.reason, 'execution rejection uses the shared reason');
  }
  const authors = [];
  let head = base;
  for (const [role, signal] of [['implementer', 'IMPLEMENTATION_COMPLETE'], ['reviewer', 'LGTM'], ['evaluator', 'MATCH']]) {
    const call = make(role, {
      sessionId: 'cycle-fixture', implementerIds: [...authors],
      commitScope: role === 'implementer' ? { mode: 'implementation', base, branch: 'fixture' } : { mode: 'fixed', base, head, branch: 'fixture' },
    });
    const pending = delegation('begin', call);
    const child = `/root/${pending.dispatch.task_name}`;
    delegation('bind', { call, observation: observe('spawn_agent', { task_name: child }) });
    if (role === 'implementer') {
      fs.writeFileSync(path.join(repo, 'implementation.txt'), 'substantive fixture change\n');
      git('add', '.'); git('commit', '-qm', 'implementation'); head = git('rev-parse', 'HEAD');
      check(head !== base, 'implementation advances HEAD'); authors.push(child);
    }
    const result = delegation('complete', { call, head, observation: observe('list_agents', { agents: [{ agent_name: child, agent_status: { completed: `SIGNAL: ${signal}\nSynthetic integration response` } }] }) });
    check(result.status === 'OBSERVED' && result.signal === signal && result.head === head, 'selected procedure consumes bound canonical SIGNAL');
    check(result.enforcement === 'unavailable' && result.tools === 'unknown' && result.tokens === 'unknown', 'unknown measurements stay unknown');
  }
  const audit = delegation('audit', { ...common, sessionId: 'cycle-fixture' });
  check(audit.status === 'OBSERVED', 'complete nonempty cycle inventory');
  const interrupted = make('implementer', { sessionId: 'negative-fixture', commitScope: { mode: 'fixed', base, head, branch: 'fixture' } });
  const started = delegation('begin', interrupted);
  const child = `/root/${started.dispatch.task_name}`;
  delegation('bind', { call: interrupted, observation: observe('spawn_agent', { task_name: child }) });
  const stopped = { call: interrupted, head, observation: observe('list_agents', { agents: [{ agent_name: child, agent_status: 'interrupted' }] }) };
  check(delegation('complete', stopped, 1).status === 'REJECTED', 'interruption cannot authorize a procedure');
  stopped.observation.value.agents[0].agent_status = { completed: 'SIGNAL: IMPLEMENTATION_COMPLETE' };
  check(delegation('complete', stopped, 1).status === 'REJECTED', 'follow-up cannot repair a terminal invocation');
  const self = make('reviewer', { sessionId: 'negative-fixture', implementerIds: [child], commitScope: { mode: 'fixed', base, head, branch: 'fixture' } });
  delegation('begin', self);
  check(delegation('bind', { call: self, observation: observe('spawn_agent', { task_name: child }) }, 1).status === 'REJECTED', 'author reuse cannot provide independent judgment');
  check(delegation('audit', { ...common, sessionId: 'negative-fixture' }, 1).status === 'REJECTED', 'failed population stays failed');

  // Native registration/lifecycle keeps its stronger, independent evidence requirement.
  const registration = registerRoles('codex', path.join(temp, 'agents'));
  const nativeCall = roleCall(registration, { role: 'evaluator', task: 'fixture#1', message: 'fixture', sessionId: 'native', parentAgentId: 'parent', implementerIds: ['author'], previousAgentIds: [] });
  const events = ['SubagentStart', 'PreToolUse', 'SubagentStop'].map(hook_event_name => ({ hook_event_name, session_id: 'native', agent_type: nativeCall.identifier, agent_id: 'child', last_assistant_message: 'SIGNAL: MATCH' }));
  const outcome = { state: 'completed', agentId: 'child', events };
  check(roleResult(registration, nativeCall, outcome).status === 'REACHED', 'native fixture still reached');
  for (const changed of [{ ...outcome, events: [] }, { ...outcome, state: 'interrupted' }, { ...outcome, agentId: 'author' }])
    check(roleResult(registration, nativeCall, changed).status === 'UNREACHED', 'native missing hooks/interruption/self judgment never falls back');
  const nativeDoctor = diagnose(plugin);
  check(nativeDoctor.static === 'PASS' && nativeDoctor.loaded === 'UNREACHED' && nativeDoctor.live === 'UNREACHED', 'generic cycle does not certify native doctor');

  for (const name of ['develop', 'verify-code', 'verify-implement']) {
    const body = fs.readFileSync(path.join(plugin, 'skills', name, 'SKILL.md'), 'utf8');
    check(body.includes('docs/roles.md') && body.includes('OBSERVED') && body.includes('prompt-only') && body.includes('REACHED'), `${name} reaches the selected contract`);
  }
  const copy = path.join(temp, 'plugin'); fs.cpSync(plugin, copy, { recursive: true });
  const before = inspectDistribution(plugin);
  check(generateDistribution(copy).hash === before.hash, 'generated metadata and relocated artifact remain consistent');
  check(!Object.keys(before.files).some(name => name.startsWith('tests/')), 'developer fixtures do not ship');
  const module = path.join(copy, 'lib/runtime/delegation.mjs');
  check(fs.statSync(module).size > 0, 'removal negative control has a real target');
  fs.unlinkSync(module);
  check(!fs.existsSync(module), 'removal control actually removed the adapter');
  for (const [script, action] of [['delegation.mjs', 'capability'], ['doctor.mjs', 'delegation']]) {
    const result = spawnSync(process.execPath, [path.join(copy, 'scripts', script), action, file({ runtime: 'codex', provider: 'collaboration', permission: 'prompt-only' })], { env, encoding: 'utf8' });
    check(result.status !== 0 && /ERR_MODULE_NOT_FOUND/.test(result.stderr), 'missing shared capability cannot silently pass diagnostics');
  }
  check(run('roles.mjs', ['result', file(registration), file(nativeCall), file(outcome)], 0, copy).status === 'REACHED', 'adapter removal preserves native role inspector');
  console.log(`PASS delegation integration: ${count} assertions; synthetic Node/Git fixtures on ${process.platform}; live provenance and enforcement unmeasured`);
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
