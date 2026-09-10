import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync, spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { loadRole } from '../../plugins/harness/lib/runtime/roles.mjs';
import { delegationCapability } from '../../plugins/harness/lib/runtime/delegation.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const plugin = path.join(root, 'plugins/harness');
const cli = path.join(plugin, 'scripts/delegation.mjs');
const temp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'delegation-contract-')));
const repo = path.join(temp, 'repo');
const env = { ...process.env, GIT_CONFIG_GLOBAL: path.join(temp, 'empty.gitconfig'), GIT_CONFIG_NOSYSTEM: '1' };
for (const key of [
  'GIT_DIR',
  'GIT_WORK_TREE',
  'GIT_INDEX_FILE',
  'GIT_COMMON_DIR',
  'HARNESS_ROOT',
  'HARNESS_RUNTIME',
])
  delete env[key];
let count = 0,
  sequence = 0;
const check = (value, message) => {
  assert.ok(value, message);
  count++;
};
const hash = (value) => createHash('sha256').update(value).digest('hex');
const copy = (value) => structuredClone(value);
const dispatches = new Map();
function git(...args) {
  const result = spawnSync(
    'git',
    ['-C', repo, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', ...args],
    { env, encoding: 'utf8' },
  );
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}
function inputFile(value) {
  const file = path.join(temp, `input-${sequence++}.json`);
  fs.writeFileSync(file, JSON.stringify(value));
  return file;
}
function run(action, value, expected = 0, entry = cli) {
  const result = spawnSync(process.execPath, [entry, action, inputFile(value)], {
    env,
    encoding: 'utf8',
  });
  assert.equal(result.status, expected, `${action}: ${result.stdout}\n${result.stderr}`);
  count++;
  const output = JSON.parse(result.stdout);
  if (action === 'begin' && expected === 0)
    dispatches.set(`${value.sessionId}:${value.callId}`, output.dispatch.task_name);
  return output;
}
function concurrent(action, values) {
  return Promise.all(
    values.map(
      (value) =>
        new Promise((resolve, reject) => {
          const child = spawn(process.execPath, [cli, action, inputFile(value)], { env });
          let out = '',
            err = '';
          child.stdout.on('data', (data) => {
            out += data;
          });
          child.stderr.on('data', (data) => {
            err += data;
          });
          child.on('error', reject);
          child.on('close', (code) => resolve({ code, out: JSON.parse(out), err }));
        }),
    ),
  );
}
const observation = (tool, value) => ({
  source: 'parent-tool-return',
  tool: `collaboration.${tool}`,
  value,
});
const childName = (call) =>
  `${call.parentAgentId}/${dispatches.get(`${call.sessionId}:${call.callId}`) ?? 'missing_dispatch'}`;
const binding = (call, child = childName(call)) => ({
  call,
  observation: observation('spawn_agent', { task_name: child }),
});
const completion = (
  call,
  head,
  child = childName(call),
  body = `SIGNAL: ${loadRole(call.role).signals[0]}\nfixture response`,
) => ({
  call,
  head,
  observation: observation('list_agents', {
    agents: [{ agent_name: child, agent_status: { completed: body } }],
  }),
});
const context = (call) =>
  Object.fromEntries(
    ['version', 'runtime', 'provider', 'repository', 'data', 'sessionId', 'parentAgentId'].map(
      (key) => [key, call[key]],
    ),
  );
function inventory(call, kind) {
  const repoKey = hash(fs.realpathSync(path.join(repo, '.git')));
  return path.join(
    call.data,
    'v1/codex/repos',
    repoKey,
    'sessions',
    hash(call.sessionId),
    'delegation',
    `${hash(call.callId)}.${kind}.json`,
  );
}
try {
  fs.writeFileSync(env.GIT_CONFIG_GLOBAL, '');
  check(fs.lstatSync(env.GIT_CONFIG_GLOBAL).isFile() && fs.statSync(env.GIT_CONFIG_GLOBAL).size === 0,
    'Git global configuration is an empty regular file');
  const userHome = path.join(temp, 'user-home');
  fs.mkdirSync(userHome);
  fs.writeFileSync(path.join(userHome, '.gitconfig'), '[harness]\nfixtureInherited = ambient\n');
  const ambientEnv = { ...env, HOME: userHome, USERPROFILE: userHome, XDG_CONFIG_HOME: userHome };
  delete ambientEnv.GIT_CONFIG_GLOBAL;
  const ambient = spawnSync('git', ['config', '--global', '--get', 'harness.fixtureInherited'],
    { env: ambientEnv, encoding: 'utf8' });
  check(ambient.status === 0 && ambient.stdout.trim() === 'ambient', 'ambient global configuration control is populated');
  const isolated = spawnSync('git', ['config', '--global', '--list'],
    { env: { ...ambientEnv, GIT_CONFIG_GLOBAL: env.GIT_CONFIG_GLOBAL }, encoding: 'utf8' });
  check(isolated.status === 0 && isolated.stdout === '', 'fixture global file isolates populated user configuration');
  check(
    delegationCapability({ runtime: 'codex', provider: 'collaboration', permission: 'prompt-only' })
      .status === 'AVAILABLE',
    'shared capability supports explicit policy',
  );
  for (const request of [
    {},
    { runtime: 'codex', provider: 'collaboration' },
    { runtime: 'codex', provider: 'collaboration', permission: 'enforced' },
    { runtime: 'codex', provider: 'unknown', permission: 'prompt-only' },
  ])
    check(
      delegationCapability(request).status === 'UNAVAILABLE',
      'shared capability rejects unsupported or implicit policy',
    );
  fs.mkdirSync(repo);
  git('init', '-qb', 'fixture');
  fs.writeFileSync(path.join(repo, '.harness.json'), '{}\n');
  git('add', '.');
  git('commit', '-qm', 'base');
  const base = git('rev-parse', 'HEAD');
  let id = 0;
  const make = (changes = {}) => ({
    version: 1,
    runtime: 'codex',
    provider: 'collaboration',
    repository: repo,
    data: path.join(temp, 'data'),
    sessionId: `session-${id}`,
    parentAgentId: '/root',
    callId: `call_${id++}`,
    role: 'implementer',
    task: 'fixture#1',
    sourceHash: loadRole('implementer').sha256,
    commitScope: { mode: 'fixed', branch: 'fixture', base, head: base },
    implementerIds: [],
    previousAgentIds: [],
    permission: 'prompt-only',
    ...changes,
  });
  const start = (call) => {
    run('begin', call);
    run('bind', binding(call));
    return call;
  };

  const empty = make();
  check(
    run('audit', context(empty), 1).errors.includes('empty invocation inventory'),
    'empty is not success',
  );
  const good = make();
  check(run('begin', good).status === 'PENDING', 'begin inventory pending');
  check(run('audit', context(good), 1).calls[0].status === 'PENDING', 'unbound call retained');
  run('bind', binding(good));
  check(
    run('audit', context(good), 1).calls[0].status === 'PENDING',
    'bound missing outcome retained',
  );
  const passed = run('complete', completion(good, base));
  check(
    passed.status === 'OBSERVED' &&
      passed.permission === 'prompt-only' &&
      passed.nativeRoleEvidence === 'unavailable' &&
      passed.enforcement === 'unavailable' &&
      passed.tools === 'unknown' &&
      passed.tokens === 'unknown',
    'observed result cannot claim native assurance or zero usage',
  );
  check(run('audit', context(good)).calls.length === 1, 'nonempty audit reached');
  run('begin', good, 1);
  run('bind', binding(good), 1);
  run('complete', completion(good, base), 1);

  for (const data of [`${temp}/noncanonical-trailing/`, `${temp}/noncanonical-dot/./inventory`]) {
    const call = make({ data });
    check(!fs.existsSync(path.resolve(data)), 'path regression starts without an inventory');
    check(
      /normalized absolute data path required/.test(run('begin', call, 1).reason),
      'non-normalized data path is rejected before begin persists an unusable call',
    );
    run('audit', context(call), 1);
    check(!fs.existsSync(path.resolve(data)), 'rejected data path creates no state directory');
  }

  for (const key of Object.keys(good)) {
    const bad = make();
    delete bad[key];
    run('begin', bad, 1);
  }
  for (const changes of [
    { version: 2 },
    { runtime: 'claude' },
    { provider: 'unknown' },
    { permission: 'enforced' },
    { permission: 'unavailable' },
    { permission: '' },
    { parentAgentId: 'root' },
    { role: 'unknown' },
    { sourceHash: '0'.repeat(64) },
    { previousAgentIds: ['/root/a', '/root/a'] },
    { implementerIds: null },
    { commitScope: { mode: 'fixed', branch: 'other', base, head: base } },
    { commitScope: { mode: 'fixed', branch: 'fixture', base: 'HEAD', head: base } },
    { commitScope: { mode: 'unknown', branch: 'fixture', base, head: base } },
    { role: 'reviewer', sourceHash: loadRole('reviewer').sha256 },
    { extra: 'unsupported' },
  ])
    run('begin', make(changes), 1);
  for (const args of [
    [],
    ['unknown', inputFile(good)],
    ['begin'],
    ['begin', inputFile(good), 'extra'],
    ['begin', path.join(temp, 'absent')],
  ]) {
    const result = spawnSync(process.execPath, [cli, ...args], { env, encoding: 'utf8' });
    check(
      result.status === 1 && JSON.parse(result.stdout).status === 'REJECTED',
      'CLI count/action/input error closes',
    );
  }
  const malformed = path.join(temp, 'malformed.json');
  fs.writeFileSync(malformed, '{');
  check(
    spawnSync(process.execPath, [cli, 'begin', malformed], { env }).status === 1,
    'malformed JSON refused',
  );

  for (const mutate of [
    (c) => (c.parentAgentId = '/root/other'),
    (c) => (c.sessionId = 'other'),
    (c) => (c.task = 'other#1'),
    (c) => (c.sourceHash = '0'.repeat(64)),
    (c) => (c.commitScope.head = '0'.repeat(40)),
    (c) => (c.provider = 'other'),
    (c) => (c.repository = temp),
    (c) => (c.callId = 'missing'),
  ]) {
    const original = start(make());
    const altered = copy(original);
    mutate(altered);
    run('complete', completion(altered, base), 1);
    check(
      fs.existsSync(inventory(original, 'call')) && fs.existsSync(inventory(original, 'binding')),
      'scope rejection preserves original inventory',
    );
  }
  for (const mutate of [
    (b) => (b.observation.source = 'child-self-report'),
    (b) => (b.observation.value.task_name = '/root'),
    (b) => (b.observation.value.task_name = '/root/foreign/nested'),
    (b) => (b.observation.value.task_name = '/root/../child'),
    (b) => (b.observation.value = {}),
    (b) => (b.observation.value.extra = true),
    (b) => (b.observation.tool = 'collaboration.followup_task'),
  ]) {
    const call = make();
    run('begin', call);
    const bad = binding(call);
    mutate(bad);
    run('bind', bad, 1);
    check(
      run('audit', context(call), 1).calls[0].status === 'REJECTED',
      'binding failure inventory is terminal',
    );
    run('bind', binding(call), 1);
  }
  const boundTwice = make();
  run('begin', boundTwice);
  run('bind', binding(boundTwice));
  run('bind', binding(boundTwice), 1);
  run('complete', completion(boundTwice, base));
  for (const role of ['reviewer', 'evaluator']) {
    const self = make({
      role,
      sourceHash: loadRole(role).sha256,
      implementerIds: ['/root/author'],
    });
    run('begin', self);
    run('bind', binding(self, '/root/author'), 1);
    const independent = make({
      role,
      sourceHash: loadRole(role).sha256,
      implementerIds: ['/root/author'],
    });
    start(independent);
    run('complete', completion(independent, base));
  }
  const retry = make({ previousAgentIds: ['/root/old'] });
  run('begin', retry);
  run('bind', binding(retry, '/root/old'), 1);
  const old = start(make({ sessionId: 'reuse' }));
  const reused = make({ sessionId: 'reuse' });
  run('begin', reused);
  run('bind', binding(reused, childName(old)), 1);
  const notBound = make();
  run('begin', notBound);
  run('complete', completion(notBound, base), 1);

  for (const mutate of [
    (c) => (c.observation.source = 'child-self-report'),
    (c) => (c.observation.value.agents = []),
    (c) => (c.observation.value.agents[0].agent_name = '/root/other'),
    (c) => (c.observation.value.agents[0].agent_status = 'running'),
    (c) => (c.observation.value.agents[0].agent_status = 'interrupted'),
    (c) => (c.observation.value.agents[0].agent_status = { completed: null }),
    (c) => c.observation.value.agents.push(copy(c.observation.value.agents[0])),
    (c) => (c.observation.value.agents[0].agent_status = { completed: 'SIGNAL: UNKNOWN' }),
    (c) =>
      (c.observation.value.agents[0].agent_status = {
        completed: 'prefix\nSIGNAL: IMPLEMENTATION_COMPLETE',
      }),
    (c) => (c.head = '0'.repeat(40)),
    (c) => (c.observation.extra = 'ignored?'),
  ]) {
    const call = start(make());
    const bad = completion(call, base);
    mutate(bad);
    run('complete', bad, 1);
    check(
      run('audit', context(call), 1).calls[0].status === 'REJECTED',
      'invalid completion persisted',
    );
    run('complete', completion(call, base), 1);
  }

  const raceA = make({ sessionId: 'bind-race' }),
    raceB = make({ sessionId: 'bind-race' });
  run('begin', raceA);
  run('begin', raceB);
  const swappedA = binding(raceA, childName(raceB));
  run('bind', swappedA, 1);
  run('bind', binding(raceB, childName(raceA)), 1);
  const unused = make();
  run('begin', unused);
  run('bind', binding(unused, '/root/never_inventoried'), 1);
  const bindSame = make();
  run('begin', bindSame);
  const bindRace = await concurrent('bind', [binding(bindSame), binding(bindSame)]);
  check(
    bindRace.filter((r) => r.code === 0).length === 1 &&
      bindRace.filter((r) => r.code === 1).length === 1,
    'concurrent child reservation has one owner',
  );
  const raceComplete = start(make());
  const completionRace = await concurrent('complete', [
    completion(raceComplete, base),
    completion(raceComplete, base),
  ]);
  check(
    completionRace.filter((r) => r.code === 0).length === 1 &&
      completionRace.filter((r) => r.code === 1).length === 1,
    'concurrent completion consumes once',
  );
  check(
    run('audit', context(raceComplete)).status === 'OBSERVED',
    'losing duplicate cannot corrupt completed result',
  );

  const changed = start(make());
  fs.writeFileSync(path.join(repo, 'dirty'), 'uncommitted');
  run('complete', completion(changed, base), 1);
  fs.rmSync(path.join(repo, 'dirty'));
  const early = make({ commitScope: { mode: 'implementation', branch: 'fixture', base } });
  run('begin', early);
  fs.writeFileSync(path.join(repo, 'early-edit'), 'child edits before binding');
  run('bind', binding(early));
  check(
    run('audit', context(early), 1).calls[0].status === 'PENDING',
    'early child edit binding is not completion',
  );
  run('complete', completion(early, base), 1);
  fs.rmSync(path.join(repo, 'early-edit'));
  const author = make({ commitScope: { mode: 'implementation', branch: 'fixture', base } });
  run('begin', author);
  const fixedBefore = start(make());
  fs.writeFileSync(path.join(repo, 'implemented'), 'actual local implementation commit');
  git('add', '.');
  git('commit', '-qm', 'implementation');
  const implementedHead = git('rev-parse', 'HEAD');
  run('bind', binding(author));
  check(
    run('complete', completion(author, implementedHead)).head === implementedHead,
    'implementation accepts pinned descendant head',
  );
  run('complete', completion(fixedBefore, implementedHead), 1);
  check(
    run('audit', context(good)).status === 'OBSERVED',
    'historical fixed scope audit does not require current HEAD to stay frozen',
  );
  const finalScope = { mode: 'fixed', branch: 'fixture', base, head: implementedHead };
  const branchDrift = start(make({ commitScope: finalScope }));
  git('checkout', '-qb', 'other');
  run('complete', completion(branchDrift, implementedHead), 1);
  git('checkout', '-q', 'fixture');
  const unrelated = make({
    commitScope: { mode: 'implementation', branch: 'fixture', base: implementedHead },
  });
  start(unrelated);
  git('checkout', '--orphan', 'unrelated');
  git('rm', '-rf', '.');
  fs.writeFileSync(path.join(repo, '.harness.json'), '{}');
  git('add', '.');
  git('commit', '-qm', 'unrelated root');
  const unrelatedHead = git('rev-parse', 'HEAD');
  git('checkout', '-q', 'fixture');
  git('reset', '--hard', unrelatedHead);
  run('complete', completion(unrelated, unrelatedHead), 1);
  git('reset', '--hard', implementedHead);

  const orphanA = start(make({ commitScope: finalScope, sessionId: 'orphan' }));
  const orphanB = start(make({ commitScope: finalScope, sessionId: 'orphan' }));
  run('complete', completion(orphanA, implementedHead));
  run('complete', completion(orphanB, implementedHead));
  fs.rmSync(inventory(orphanB, 'call'));
  check(
    run('audit', context(orphanA), 1).errors.includes('orphan/unknown inventory record'),
    'orphan outcomes cannot hide behind another successful call',
  );
  const corrupt = start(make({ commitScope: finalScope }));
  run('complete', completion(corrupt, implementedHead));
  const outcomeFile = inventory(corrupt, 'outcome');
  const savedOutcome = fs.readFileSync(outcomeFile, 'utf8');
  const envelope = JSON.parse(savedOutcome);
  envelope.value.tools = 0;
  fs.writeFileSync(outcomeFile, JSON.stringify(envelope));
  run('audit', context(corrupt), 1);
  fs.writeFileSync(outcomeFile, savedOutcome);
  const callFile = inventory(corrupt, 'call');
  const savedCall = JSON.parse(fs.readFileSync(callFile, 'utf8'));
  savedCall.parentAgentId = '/root/other';
  fs.writeFileSync(callFile, JSON.stringify(savedCall));
  run('audit', context(corrupt), 1);

  // A copy is the target of both source drift and adapter-removal controls.
  const removed = path.join(temp, 'removed');
  fs.mkdirSync(path.join(removed, 'plugins'), { recursive: true });
  fs.cpSync(plugin, path.join(removed, 'plugins/harness'), { recursive: true });
  const copiedCli = path.join(removed, 'plugins/harness/scripts/delegation.mjs');
  const drift = make({ commitScope: finalScope });
  run('begin', drift, 0, copiedCli);
  run('bind', binding(drift), 0, copiedCli);
  const roleFile = path.join(removed, 'plugins/harness/agents/implementer.md');
  const roleBytes = fs.readFileSync(roleFile);
  fs.appendFileSync(roleFile, '\nSource drift fixture.\n');
  run('complete', completion(drift, implementedHead), 1, copiedCli);
  run('audit', context(drift), 1, copiedCli);
  fs.writeFileSync(roleFile, roleBytes);
  const removedAdapter = path.join(removed, 'plugins/harness/lib/runtime/delegation.mjs');
  check(
    fs
      .readFileSync(removedAdapter)
      .equals(fs.readFileSync(path.join(plugin, 'lib/runtime/delegation.mjs'))),
    'negative copy target matches production',
  );
  fs.rmSync(removedAdapter);
  check(
    !fs.existsSync(removedAdapter) &&
      fs.existsSync(path.join(plugin, 'lib/runtime/delegation.mjs')),
    'only copied adapter removed',
  );
  const unavailable = spawnSync(
    process.execPath,
    [copiedCli, 'begin', inputFile(make({ commitScope: finalScope }))],
    { env, encoding: 'utf8' },
  );
  check(
    unavailable.status !== 0 && /ERR_MODULE_NOT_FOUND/.test(unavailable.stderr),
    'removed adapter cannot certify generic execution',
  );
  fs.mkdirSync(path.join(removed, 'tests/harness'), { recursive: true });
  for (const name of ['role-contract-check.mjs', 'runtime-contract-check.mjs']) {
    fs.copyFileSync(
      path.join(root, 'tests/harness', name),
      path.join(removed, 'tests/harness', name),
    );
    const native = spawnSync(process.execPath, [path.join(removed, 'tests/harness', name)], {
      env,
      encoding: 'utf8',
    });
    check(
      native.status === 0 && /PASS/.test(native.stdout),
      `native suite remains populated after adapter removal: ${name}\n${native.stdout}\n${native.stderr}`,
    );
  }
  console.log(
    `PASS delegation contract: ${count} assertions; CLI, temporary Git commits, race and adapter-removal controls; provider observations are offline fixtures, not live evidence`,
  );
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
