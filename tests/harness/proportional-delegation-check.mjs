import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {beginDelegation, bindDelegation, completeDelegation, auditDelegation, delegationHookRole} from '../../plugins/harness/lib/runtime/delegation.mjs';
import {loadRole} from '../../plugins/harness/lib/runtime/roles.mjs';
import {roleSpawnOptions} from '../../plugins/harness/lib/runtime/role-models.mjs';
import {resolveState} from '../../plugins/harness/lib/runtime/state.mjs';

const temp = await fs.promises.realpath(fs.mkdtempSync(path.join(os.tmpdir(), 'proportional-')));
const root = fileURLToPath(new URL('../../plugins/harness/', import.meta.url));
const repo = path.join(temp, 'repo');
const env = {...process.env, HARNESS_RUNTIME: 'codex', HARNESS_DATA_DIR: path.join(temp, 'data'),
  GIT_CONFIG_GLOBAL: path.join(temp, 'gitconfig'), GIT_CONFIG_NOSYSTEM: '1'};
for (const key of ['GIT_DIR', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR', 'GIT_WORK_TREE']) delete env[key];
const options = {root, env};
const git = (...args) => {
  const r = spawnSync('git', ['-C', repo, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', ...args], {env, encoding: 'utf8'});
  assert.equal(r.status, 0, r.stderr); return r.stdout.trim();
};
const observation = (tool, value) => ({source: 'parent-tool-return', tool: `collaboration.${tool}`, value});
const context = call => Object.fromEntries(['version', 'runtime', 'provider', 'repository', 'data', 'sessionId', 'parentAgentId'].map(k => [k, call[k]]));
let sequence = 0;
try {
  fs.writeFileSync(env.GIT_CONFIG_GLOBAL, ''); fs.mkdirSync(repo); git('init', '-qb', 'fixture');
  fs.writeFileSync(path.join(repo, '.harness.json'), '{}'); git('add', '.'); git('commit', '-qm', 'base');
  const base = git('rev-parse', 'HEAD');
  const make = (extra = {}) => ({version: 1, runtime: 'codex', provider: 'collaboration', repository: repo,
    data: env.HARNESS_DATA_DIR, sessionId: 'session', parentAgentId: '/root', callId: `c${sequence++}`,
    role: 'reviewer', task: 't', sourceHash: loadRole('reviewer', root).sha256,
    commitScope: {mode: 'fixed', base, head: base, branch: 'fixture'}, implementerIds: ['/root/author'],
    previousAgentIds: [], permission: 'prompt-only', ...extra});
  const start = async call => {
    const pending = await beginDelegation(call, options);
    const child = `/root/${pending.dispatch.task_name}`;
    const binding = await bindDelegation({call: pending.call, observation: observation('spawn_agent', {task_name: child})}, options);
    assert.equal(binding.status, 'PENDING'); return {call: pending.call, child};
  };
  const complete = (run, body, head = base) => completeDelegation({call: run.call, head,
    observation: observation('list_agents', {agents: [{agent_name: run.child, agent_status: {completed: body}}]})}, options);

  assert.deepEqual(roleSpawnOptions('reviewer'), {}, 'unknown model availability inherits runtime settings');
  assert.deepEqual(roleSpawnOptions('reviewer', {availableModels: ['other']}), {});
  assert.equal(roleSpawnOptions('reviewer', {availableModels: ['gpt-5.6-sol']}).model, 'gpt-5.6-sol');
  assert.equal(roleSpawnOptions('reviewer', {model: 'chosen', reasoning_effort: 'low'}).model, 'chosen');
  assert.throws(() => roleSpawnOptions('reviewer', {model: 'chosen', availableModels: ['other']}), /requested model/);
  const selected = await beginDelegation(make({sessionId: 'model', modelOptions: {model: 'chosen', reasoning_effort: 'low'}}), options);
  assert.equal(selected.dispatch.model, 'chosen');
  assert.equal(selected.dispatch.reasoning_effort, 'low');

  const first = await start(make());
  await assert.rejects(beginDelegation(make({retryOf: first.call.callId}), options), /ENOENT/);
  fs.writeFileSync(path.join(repo, 'scratch'), 'temporary test artifact');
  const hook = {cwd: repo, session_id: first.call.sessionId, agent_id: first.child};
  assert.equal(await delegationHookRole(hook, options), 'harness:reviewer', 'tool use does not recheck cleanliness');
  assert.equal((await complete(first, 'SIGNAL: LGTM')).status, 'REJECTED', 'result adoption still checks cleanliness');
  fs.rmSync(path.join(repo, 'scratch'));
  const retry = await start(make({retryOf: first.call.callId}));
  assert.equal((await complete(retry, 'SIGNAL: CHANGES_REQUESTED\nFix x')).status, 'OBSERVED');
  const recovered = await auditDelegation(context(retry.call), options);
  assert.equal(recovered.status, 'OBSERVED');
  assert.equal(recovered.calls.find(c => c.callId === first.call.callId).status, 'REJECTED');
  assert.equal(recovered.calls.find(c => c.callId === first.call.callId).resolvedBy, retry.call.callId);

  const followCall = make({retryOf: retry.call.callId, reuseChild: true, previousAgentIds: [retry.child]});
  const follow = await beginDelegation(followCall, options);
  assert.equal(`/root/${follow.dispatch.task_name}`, retry.child, 'same independent reviewer may re-review');
  assert.equal(follow.dispatch.tool, 'collaboration.followup_task');
  await assert.rejects(beginDelegation(make({retryOf: retry.call.callId, reuseChild: true}), options), /active invocation/);
  const bound = await bindDelegation({call: follow.call, observation: observation('followup_task', null)}, options);
  assert.equal(bound.status, 'PENDING');
  assert.equal(await delegationHookRole({...hook, agent_id: retry.child}, options), 'harness:reviewer', 'only the active retry owns role permission');
  const notDone = await auditDelegation(context(follow.call), options);
  assert.equal(notDone.status, 'REJECTED', 'a pending retry is not resolved by the old result');
  assert.equal((await complete({call: follow.call, child: retry.child}, 'SIGNAL: LGTM\nVerified x')).status, 'OBSERVED');
  assert.equal((await auditDelegation(context(follow.call), options)).status, 'OBSERVED');
  await assert.rejects(beginDelegation(make({retryOf: retry.call.callId, reuseChild: true}), options), /reserved/,
    'forking reuse from an older invocation must fail before dispatch');
  await assert.rejects(complete({call: follow.call, child: retry.child}, 'SIGNAL: LGTM'), /terminal/);
  await assert.rejects(beginDelegation(make({retryOf: follow.call.callId, reuseChild: true, implementerIds: [retry.child]}), options));
  await assert.rejects(beginDelegation(make({retryOf: follow.call.callId, task: 'other'}), options));
  await assert.rejects(beginDelegation(make({retryOf: 'missing'}), options));

  const unrelated = await start(make({task: 'different'}));
  assert.equal((await complete(unrelated, 'invalid result')).status, 'REJECTED');
  assert.equal((await auditDelegation(context(unrelated.call), options)).status, 'REJECTED', 'unrelated success cannot hide failure');
  const repaired = await start(make({task: 'different', retryOf: unrelated.call.callId}));
  assert.equal((await complete(repaired, 'SIGNAL: LGTM')).status, 'OBSERVED');
  assert.equal((await auditDelegation(context(repaired.call), options)).status, 'OBSERVED');
  const scope = await resolveState({cwd: repo, sessionId: 'session'}, env);
  const failureFile = path.join(scope.session, 'delegation', createHash('sha256').update(first.call.callId).digest('hex') + '.outcome.json');
  const saved = fs.readFileSync(failureFile, 'utf8'); fs.writeFileSync(failureFile, '{broken');
  assert.equal((await auditDelegation(context(first.call), options)).status, 'REJECTED', 'retry never masks corrupt evidence');
  fs.writeFileSync(failureFile, saved);
  const forged = JSON.parse(saved); forged.value.resolvedBy = 'invented-success';
  fs.writeFileSync(failureFile, JSON.stringify(forged));
  assert.equal((await auditDelegation(context(first.call), options)).status, 'REJECTED', 'resolution is derived, never trusted from a stored outcome');
  fs.writeFileSync(failureFile, saved);
  console.log('PASS proportional delegation: model inheritance, endpoint checks, reviewer reuse, resolved history and retained boundaries');
} finally {fs.rmSync(temp, {recursive: true, force: true});}
