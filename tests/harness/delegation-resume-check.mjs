import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {spawn, spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {loadRole} from '../../plugins/harness/lib/runtime/roles.mjs';

const plugin = fileURLToPath(new URL('../../plugins/harness/', import.meta.url));
const temp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'delegation-resume-')));
const repo = path.join(temp, 'repo');
fs.mkdirSync(repo);
const env = {...process.env, GIT_CONFIG_GLOBAL: path.join(temp, 'gitconfig'), GIT_CONFIG_NOSYSTEM: '1'};
fs.writeFileSync(env.GIT_CONFIG_GLOBAL, '');
for (const key of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR', 'HARNESS_RUNTIME']) delete env[key];
const git = (...args) => {
  const result = spawnSync('git', ['-C', repo, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', ...args], {env, encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
};
git('init', '-qb', 'fixture');
fs.writeFileSync(path.join(repo, '.harness.json'), '{}');
git('add', '.'); git('commit', '-qm', 'fixture');
const head = git('rev-parse', 'HEAD');
const digest = value => createHash('sha256').update(value).digest('hex');
let sequence = 0;
const inputFile = value => {
  const file = path.join(temp, `input-${sequence++}.json`);
  fs.writeFileSync(file, JSON.stringify(value));
  return file;
};
const cli = path.join(plugin, 'scripts/delegation.mjs');
const run = (action, value, code = 0, entry = cli) => {
  const result = spawnSync(process.execPath, [entry, action, inputFile(value)], {env, encoding: 'utf8'});
  assert.equal(result.status, code, `${action}: ${result.stdout}\n${result.stderr}`);
  return JSON.parse(result.stdout);
};
const call = (sessionId, callId, extra = {}) => ({version: 1, runtime: 'codex', provider: 'collaboration',
  repository: repo, data: path.join(temp, 'data'), sessionId, parentAgentId: '/root', callId,
  role: 'evaluator', task: 'fixture#436', sourceHash: loadRole('evaluator', plugin).sha256,
  commitScope: {mode: 'fixed', base: head, head, branch: 'fixture'},
  implementerIds: ['/root'], previousAgentIds: [], permission: 'prompt-only', ...extra});
const context = call => Object.fromEntries(['version', 'runtime', 'provider', 'repository', 'data', 'sessionId', 'parentAgentId'].map(key => [key, call[key]]));
const record = (call, kind) => path.join(call.data, 'v1/codex/repos', digest(fs.realpathSync(path.join(repo, '.git'))),
  'sessions', digest(call.sessionId), 'delegation', `${digest(call.callId)}.${kind}.json`);
const observed = value => ({source: 'parent-tool-return', tool: 'collaboration.spawn_agent', value});
const fail = value => {
  run('begin', value);
  return run('bind', {call: value, observation: observed('collab spawn failed: agent thread limit reached')}, 1);
};
const reference = value => run('reference', {context: context(value), callId: value.callId});
const finish = (value, begun) => {
  const child = `${value.parentAgentId}/${begun.dispatch.task_name}`;
  run('bind', {call: value, observation: observed({task_name: child})});
  return run('complete', {call: value, head, observation: {source: 'parent-tool-return',
    tool: 'collaboration.list_agents', value: {agents: [{agent_name: child,
      agent_status: {completed: 'SIGNAL: MATCH\nfixture only'}}]}}});
};

const old = call('old-session', 'datadescr-eval-01');
const failure = fail(old);
assert.equal(failure.reason, 'collab spawn failed: agent thread limit reached');
assert.deepEqual(failure.failure, {layer: 'provider', kind: 'capacity',
  message: failure.reason, childState: 'not-created'});
assert.equal(fs.existsSync(record(old, 'binding')), false);
const before = ['call', 'dispatch', 'outcome'].map(kind => fs.readFileSync(record(old, kind), 'utf8'));
const unsupported = call('new-session', 'datadescr-eval-02', {retryOf: old.callId});
assert.match(run('begin', unsupported, 1).reason, /ENOENT/);
assert.equal(fs.existsSync(record(unsupported, 'call')), false);
const ref = reference(old);
const next = call('new-session', 'datadescr-eval-02', {resumeFrom: ref});
for (const change of [
  {resumeFrom: {...ref, sessionId: 'absent'}},
  {resumeFrom: {...ref, parentAgentId: '/root/other'}},
  {resumeFrom: {...ref, callId: 'absent'}},
  {resumeFrom: {...ref, callHash: '0'.repeat(64)}},
  {resumeFrom: {...ref, outcomeHash: '0'.repeat(64)}},
  {sessionId: old.sessionId}, {retryOf: old.callId}, {reuseChild: true},
  {task: 'fixture#other'}, {implementerIds: ['/root/other']},
  {role: 'reviewer', sourceHash: loadRole('reviewer', plugin).sha256},
]) run('begin', {...next, ...change}, 1);
const begun = run('begin', next);
assert.equal(run('audit', context(next), 1).calls.length, 2);
assert.match(run('begin', {...next, sessionId: 'duplicate-session'}, 1).reason, /already consumed/);
finish(next, begun);
const audit = run('audit', context(next));
assert.equal(audit.calls.length, 2);
const historical = audit.calls.find(row => row.sessionId === old.sessionId);
assert.equal(historical.status, 'REJECTED');
assert.deepEqual(historical.resolvedByRef, {sessionId: next.sessionId, parentAgentId: next.parentAgentId, callId: next.callId});
assert.deepEqual(['call', 'dispatch', 'outcome'].map(kind => fs.readFileSync(record(old, kind), 'utf8')), before);

// Unrelated historical calls do not affect this recovery's evidence.
const unrelated = call(old.sessionId, 'unrelated');
run('begin', unrelated);
const partial = run('audit', context(next));
assert.equal(partial.calls.length, 2);
assert.equal(partial.calls.some(row => row.callId === unrelated.callId), false);
const transcript = spawnSync(process.execPath, [path.join(plugin, 'scripts/transcript.mjs'), '--scope', inputFile(context(next)), '--json'], {env, encoding: 'utf8'});
assert.equal(transcript.status, 2, transcript.stderr);
const aggregate = JSON.parse(transcript.stdout);
assert.equal(aggregate.population, 2);
assert.equal(aggregate.complete, false);
assert.equal(aggregate.signals.evaluator.MATCH, 1);
assert.equal(aggregate.a9.verdicts.OK, 1);
assert.equal(aggregate.tools.evaluator.status, 'UNKNOWN');
assert.equal(aggregate.tokens.roles.evaluator.status, 'UNKNOWN');
assert.equal(aggregate.reuse.multi_signal_transcripts, 0);

// Hashes pin bytes, including failures created by the older schema-only adapter.
const legacy = call('legacy-session', 'legacy-failure');
fail(legacy);
const legacyEnvelope = JSON.parse(fs.readFileSync(record(legacy, 'outcome'), 'utf8'));
delete legacyEnvelope.value.failure;
legacyEnvelope.value.reason = 'spawn return schema invalid';
fs.writeFileSync(record(legacy, 'outcome'), JSON.stringify(legacyEnvelope));
const legacyRef = reference(legacy);
const legacyNext = call('legacy-next-session', 'legacy-next', {resumeFrom: legacyRef});
const legacyBegin = run('begin', legacyNext);
finish(legacyNext, legacyBegin);
assert.equal(run('audit', context(legacyNext)).calls.length, 2);
fs.appendFileSync(record(legacy, 'outcome'), ' ');
assert.match(run('audit', context(legacyNext), 1).calls[0].reason, /digest mismatch/);

// Same-session retry remains supported; cross-session claims serialize.
const same = call('same-session', 'same-01'); fail(same);
const sameNext = call(same.sessionId, 'same-02', {retryOf: same.callId});
finish(sameNext, run('begin', sameNext));
assert.equal(run('audit', context(same)).calls.length, 2);
// Historical same-session retry ancestry is selected, without its neighbours.
const chainOld = call('chain-old', 'chain-first'); fail(chainOld);
const chainRetry = call(chainOld.sessionId, 'chain-retry', {retryOf: chainOld.callId}); fail(chainRetry);
run('begin', call(chainOld.sessionId, 'chain-unrelated'));
const chainNext = call('chain-current', 'chain-next', {resumeFrom: reference(chainRetry)});
finish(chainNext, run('begin', chainNext));
const chainAudit = run('audit', context(chainNext));
assert.equal(chainAudit.calls.length, 3);
assert.equal(chainAudit.calls.filter(x => x.resolvedByRef).length, 2);
const racing = call('race-old', 'race-01'); fail(racing);
const raceRef = reference(racing);
const race = await Promise.all(['race-a', 'race-b'].map(sessionId => new Promise((resolve, reject) => {
  const child = spawn(process.execPath, [cli, 'begin', inputFile(call(sessionId, 'race-02', {resumeFrom: raceRef}))], {env});
  let out = '';
  child.stdout.on('data', data => { out += data; });
  child.on('error', reject);
  child.on('close', code => resolve({code, out: JSON.parse(out)}));
})));
assert.deepEqual(race.map(row => row.code).sort(), [0, 1]);
assert.match(race.find(row => row.code === 1).out.reason, /already consumed|lock unavailable/);

// Remove only the cross-session resolver in an isolated copy. The exact valid
// resume fails again, establishing the positive regression reaches the fix.
const mutant = path.join(temp, 'mutant');
fs.cpSync(plugin, mutant, {recursive: true});
const moduleFile = path.join(mutant, 'lib/runtime/delegation.mjs');
const source = fs.readFileSync(moduleFile, 'utf8');
const needle = "return call.resumeFrom ? sessionScope(scope, call.resumeFrom.sessionId) : scope;";
assert.equal(source.split(needle).length, 2);
const changed = source.replace(needle, 'return scope;');
assert.notEqual(source, changed);
fs.writeFileSync(moduleFile, changed);
const mutationOld = call('mutation-old', 'mutation-01'); fail(mutationOld);
const mutationNext = call('mutation-new', 'mutation-02', {resumeFrom: reference(mutationOld)});
assert.match(run('begin', mutationNext, 1, path.join(mutant, 'scripts/delegation.mjs')).reason, /ENOENT/);
finish(mutationNext, run('begin', mutationNext));
assert.equal(run('audit', context(mutationNext)).status, 'OBSERVED');

const missing = call('missing-session', 'missing-outcome');
run('begin', missing);
assert.match(run('reference', {context: context(missing), callId: missing.callId}, 1).reason, /ENOENT/);
const cycle = call('cycle-session', 'cycle'); fail(cycle);
const cycleEnvelope = JSON.parse(fs.readFileSync(record(cycle, 'call'), 'utf8'));
cycleEnvelope.value.retryOf = cycle.callId;
fs.writeFileSync(record(cycle, 'call'), JSON.stringify(cycleEnvelope));
assert.match(run('reference', {context: context(cycle), callId: cycle.callId}, 1).reason, /itself|cycle/);

const dispatchTamper = call('dispatch-old', 'dispatch'); fail(dispatchTamper);
const dispatchRef = reference(dispatchTamper);
fs.appendFileSync(record(dispatchTamper, 'dispatch'), ' ');
assert.match(run('begin', call('dispatch-new', 'dispatch-next', {resumeFrom: dispatchRef}), 1).reason, /dispatch digest mismatch/);

// Repeated child paths in different sessions are distinct inventory identities.
const repeated = call('repeated-old', 'repeated');
const repeatedBegin = run('begin', repeated);
const repeatedChild = `/root/${repeatedBegin.dispatch.task_name}`;
run('bind', {call: repeated, observation: observed({task_name: repeatedChild})});
run('complete', {call: repeated, head, observation: {source: 'parent-tool-return',
  tool: 'collaboration.list_agents', value: {agents: []}}}, 1);
const repeatedNext = call('repeated-new', 'repeated-next', {resumeFrom: reference(repeated)});
const repeatedNextBegin = run('begin', repeatedNext);
const dispatchEnvelope = JSON.parse(fs.readFileSync(record(repeatedNext, 'dispatch'), 'utf8'));
dispatchEnvelope.value.task_name = repeatedBegin.dispatch.task_name;
fs.writeFileSync(record(repeatedNext, 'dispatch'), JSON.stringify(dispatchEnvelope));
finish(repeatedNext, {...repeatedNextBegin, dispatch: repeatedBegin.dispatch});
assert.equal(run('audit', context(repeatedNext)).status, 'OBSERVED');

// Preserve parent-qualified inventory visits without duplicating a session's
// calls when independent parents each have a resumed failure.
const parentA = call('multi-history', 'parent-a', {parentAgentId: '/root/a'});
const parentB = call('multi-history', 'parent-b', {parentAgentId: '/root/b'});
fail(parentA); fail(parentB);
const successorA = call('multi-current', 'successor-a', {resumeFrom: reference(parentA)});
const successorB = call('multi-current', 'successor-b', {resumeFrom: reference(parentB)});
finish(successorA, run('begin', successorA));
finish(successorB, run('begin', successorB));
const multiAudit = run('audit', context(successorA));
assert.equal(multiAudit.calls.length, 4);
assert.equal(new Set(multiAudit.calls.map(x => `${x.sessionId}:${x.callId}`)).size, 4);
assert.equal(multiAudit.calls.filter(x => x.status === 'REJECTED' && x.resolvedByRef).length, 2);
const unseenParent = call('multi-history', 'unrelated-parent', {parentAgentId: '/root/c'});
run('begin', unseenParent);
const partialParents = run('audit', context(successorA));
assert.equal(partialParents.calls.length, 4);
assert.equal(partialParents.calls.some(x => x.callId === unseenParent.callId), false);
fs.writeFileSync(record(unseenParent, 'outcome'), '{corrupt unrelated outcome');
assert.equal(run('audit', context(successorA)).status, 'OBSERVED');
fs.writeFileSync(record(unseenParent, 'call'), '{corrupt unrelated call');
assert.equal(run('audit', context(successorA)).status, 'OBSERVED');
fs.writeFileSync(record(unseenParent, 'call'), 'null');
assert.equal(run('audit', context(successorA)).status, 'OBSERVED');
const currentPending = call(successorA.sessionId, 'current-pending');
run('begin', currentPending);
assert.equal(run('audit', context(successorA), 1).calls.find(x => x.callId === currentPending.callId).status, 'PENDING');

// One Git common directory/session may contain calls in different worktrees.
// Binding and audit must inspect each recorded owner at its own checkout.
const sibling = path.join(temp, 'sibling');
git('worktree', 'add', '-qb', 'sibling', sibling);
const firstWork = call('worktree-session', 'first-work');
finish(firstWork, run('begin', firstWork));
const otherWork = call('worktree-session', 'other-work', {repository: sibling,
  commitScope: {...firstWork.commitScope, branch: 'sibling'}});
finish(otherWork, run('begin', otherWork));
const multipleWorktrees = run('audit', context(otherWork));
assert.equal(multipleWorktrees.status, 'OBSERVED');
assert.equal(multipleWorktrees.calls.length, 2);
// A source copy restores the exact wrong-top lookup responsible for the live
// reviewer bind failure; the same second-worktree bind must reject there.
const ownerMutant = path.join(temp, 'wrong-owner');
fs.cpSync(plugin, ownerMutant, {recursive: true});
const ownerFile = path.join(ownerMutant, 'lib/runtime/delegation.mjs');
const ownerSource = fs.readFileSync(ownerFile, 'utf8');
assert.ok(ownerSource.includes('const own = {...scope, top: envelope.value?.repository};'));
fs.writeFileSync(ownerFile, ownerSource.replace('const own = {...scope, top: envelope.value?.repository};', 'const own = scope;'));
const mutantWork = call('worktree-session', 'mutant-work', {repository: sibling,
  commitScope: otherWork.commitScope});
const mutantBegin = run('begin', mutantWork);
assert.match(run('bind', {call: mutantWork, observation: observed({task_name: `/root/${mutantBegin.dispatch.task_name}`})},
  1, path.join(ownerMutant, 'scripts/delegation.mjs')).reason, /stored call identity mismatch/);

fs.writeFileSync(path.join(repo, 'advanced'), 'next commit');
git('add', '.'); git('commit', '-qm', 'advance');
const advanced = git('rev-parse', 'HEAD');
const changedScope = call('changed-scope', 'changed', {resumeFrom: ref,
  commitScope: {...old.commitScope, head: advanced}});
assert.match(run('begin', changedScope, 1).reason, /identical commit scope/);
console.log(`PASS delegation resume: historical failure, hashes, scope, once-only race, partial aggregate and resolver-removal control; offline provider fixtures only. Retained fixture: ${temp}`);
