import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {requiredRoleTools, roleCapabilities} from '../../plugins/harness/lib/runtime/role-capabilities.mjs';
import {projectRole} from '../../plugins/harness/lib/runtime/roles.mjs';
import {beginAntigravityRole, bindAntigravityRole, activateAntigravityRole, completeAntigravityRole} from '../../plugins/harness/lib/runtime/antigravity-roles.mjs';
import {registerAntigravityParent} from '../../plugins/harness/lib/runtime/antigravity-identity.mjs';
import {resolveState, recordStateEvent} from '../../plugins/harness/lib/runtime/state.mjs';
import {antigravityEvent} from '../../plugins/harness/lib/runtime/antigravity-hook.mjs';
import {inspectDistribution} from '../../plugins/harness/lib/distribution.mjs';

const root = fileURLToPath(new URL('../../plugins/harness/', import.meta.url));
const temp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'parity-role-')));
const main = path.join(temp, 'repo'), work = path.join(temp, 'work');
const env = {...process.env, HARNESS_DATA_DIR: path.join(temp, 'data'), HARNESS_RUNTIME: 'antigravity',
  GIT_CONFIG_GLOBAL: os.devNull, GIT_CONFIG_NOSYSTEM: '1'};
for (const key of ['PLUGIN_ROOT', 'PLUGIN_DATA', 'CLAUDE_PLUGIN_ROOT', 'CLAUDE_PLUGIN_DATA',
  'HARNESS_GUARD_LOG', 'HARNESS_ROOT', 'HARNESS_DOCTOR_DIR', 'GIT_DIR', 'GIT_WORK_TREE']) delete env[key];
const git = (...args) => {const run = spawnSync('git', args, {env, encoding: 'utf8'}); assert.equal(run.status, 0, run.stderr);};
const options = {root, env};
const scope = id => resolveState({runtime: 'antigravity', cwd: work, sessionId: id}, env);
const hook = (id, event) => {
  const run = spawnSync(process.execPath, [path.join(root, 'scripts/hook.mjs'), id, '--runtime', 'antigravity'],
    {env, cwd: work, input: JSON.stringify(event), encoding: 'utf8'});
  assert.equal(run.status, 0, run.stderr); return JSON.parse(run.stdout);
};
const context = id => hook('context', {conversationId: id, workspacePaths: [work], invocationNum: 0, initialNumSteps: 0});
let step = 1;
const dispatchSteps = new Map();
const tool = (id, name, args) => {
  const stepIdx = step++;
  const result = hook('guard', {conversationId: id, workspacePaths: [work], stepIdx, toolCall: {name, args}});
  if (name === 'invoke_subagent' && result.decision === 'allow')
    dispatchSteps.set(args.Subagents[0].Prompt.split('\n')[0].slice('Harness call '.length), stepIdx);
  return result;
};
const stop = (id, extra = {}) => hook('stop', {conversationId: id, workspacePaths: [work], executionNum: 0,
  fullyIdle: true, terminationReason: 'NO_TOOL_CALL', error: '', ...extra});
const coordinate = callId => ({runtime: 'antigravity', workspace: work, parentId: 'parent', callId});
const nativeReturn = child => `Created the following subagents:\n${JSON.stringify({conversationId: child,
  workspaceUris: [pathToFileURL(work).href]})}\nThe subagents will send you a message when completed.`;
const bind = (callId, childId) => bindAntigravityRole({...coordinate(callId), observation: {
  source: 'parent-tool-return', tool: 'invoke_subagent', stepIdx: dispatchSteps.get(callId), value: nativeReturn(childId)}}, options);
const starts = new Map();
const receipt = (child, dispatch, stepIdx) => ({source: 'parent-tool-return', tool: 'send_message', stepIdx,
  recipient: child, message: dispatch.args.Message, success: true,
  value: `Created At: 2026-09-13T10:08:33+09:00\nCompleted At: 2026-09-13T10:08:33+09:00\nMessage sent to "${child}".`});
const ackOf = dispatch => JSON.parse(/Send exactly ("[^"\n]+")/.exec(dispatch.args.Message)[1]);
const receivedAck = (child, dispatch) => ({source: 'parent-received-message', sender: child, recipient: 'parent', body: ackOf(dispatch)});
const finish = (callId, childId, body = 'SIGNAL: LGTM\nfixture') => completeAntigravityRole({...coordinate(callId), childId,
  ...starts.get(callId),
  observation: {source: 'parent-received-message', sender: childId, recipient: 'parent', body}}, options);
let checks = 0;
const check = async (label, fn) => {await fn(); checks++; console.log('PASS ' + label);};
try {
  git('init', '-q', main);
  fs.writeFileSync(path.join(main, '.harness.json'), JSON.stringify({ledger: {backend: 'beads'}}));
  git('-C', main, 'add', '.'); git('-C', main, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture');
  git('-C', main, 'worktree', 'add', '-qb', 'fixture', work);
  await check('three runtimes reject every missing required tool and preserve explicit model', () => {
    for (const runtime of ['claude', 'codex', 'antigravity']) for (const role of ['implementer', 'reviewer', 'evaluator']) {
      const availableTools = requiredRoleTools(runtime, role);
      const model = runtime === 'antigravity' ? 'pro' : 'explicit-model';
      const input = {availableTools, availableModels: [model], modelOptions: {model, ...(runtime === 'codex' ? {availableModels: [model]} : {})}};
      assert.equal(roleCapabilities(runtime, role, input).model.model, model);
      for (const absent of availableTools)
        assert.throws(() => roleCapabilities(runtime, role, {...input, availableTools: availableTools.filter(tool => tool !== absent)}), /tools missing/);
      assert.throws(() => roleCapabilities(runtime, role, {...input, modelOptions: {model: 'unavailable', availableModels: []}}), /unavailable/);
      assert.throws(() => roleCapabilities(runtime, role), /available tools/);
      if (runtime === 'antigravity') {
        const projection = projectRole(runtime, role, root);
        assert.match(projection.text, /subagent: true/); assert.match(projection.text, /model: inherit/);
        for (const tool of availableTools) assert.ok(projection.text.includes(JSON.stringify(tool)));
      } else assert.throws(() => projectRole(runtime, role, root, root, {modelOptions: {model}}), /native runtime model selection/);
    }
  });
  context('parent'); await registerAntigravityParent(await scope('parent'), inspectDistribution(root).hash, root);
  async function begin(callId, role = 'reviewer') {
    return beginAntigravityRole({...coordinate(callId), task: 'fixture-task', role, prompt: 'Read and return canonical SIGNAL.',
      implementerIds: ['author'], previousAgentIds: [], capabilities: {availableTools: requiredRoleTools('antigravity', role)}}, options);
  }
  await check('identity records remain strict for enrollment but do not gate ordinary writes', async () => {
    const parent = await scope('parent');
    const file = path.join(parent.session, 'antigravity-parent.json');
    const original = fs.readFileSync(file, 'utf8');
    try {
      for (const [field, value] of [['version', 2], ['runtime', 'codex'], ['kind', 'child'],
        ['evidence', 'invented'], ['sessionId', 'other'], ['repoKey', 'other'],
        ['workspace', main], ['source', {root, hash: 'stale'}]]) {
        fs.writeFileSync(file, JSON.stringify({...JSON.parse(original), [field]: value}));
        assert.equal(tool('parent', 'write_to_file', {TargetFile: path.join(work, 'invalid-parent')}).decision, 'allow', field);
        await assert.rejects(begin('invalid-' + field), /parent scope\/source mismatch/, field);
      }
    } finally { fs.writeFileSync(file, original); }
    assert.equal(tool('parent', 'write_to_file', {TargetFile: path.join(work, 'valid-parent')}).decision, 'allow');
  });
  async function active(callId, role = 'reviewer') {
    const request = await begin(callId, role);
    assert.equal(tool('parent', 'invoke_subagent', request.dispatch.args).decision, 'allow');
    const child = callId + '-child';
    const bound = await bind(callId, child); context(child);
    await ready(callId, child, bound); return child;
  }
  async function ready(callId, child, bound, idle = false) {
    const readyStep = step;
    assert.equal(tool('parent', 'send_message', bound.dispatch.args).decision, 'allow');
    assert.equal(tool(child, 'send_message', {Recipient: 'parent', Message: ackOf(bound.dispatch)}).decision, 'allow');
    if (idle) stop(child);
    const activation = await activateAntigravityRole({...coordinate(callId), childId: child,
      delivery: receipt(child, bound.dispatch, readyStep), observation: receivedAck(child, bound.dispatch)}, options);
    assert.equal(tool(child, 'write_to_file', {TargetFile: path.join(work, 'premature')}).decision, 'allow');
    const startStep = step;
    assert.equal(tool('parent', 'send_message', activation.dispatch.args).decision, 'allow');
    if (idle) context(child);
    assert.equal(tool(child, 'send_message', {Recipient: 'parent', Message: ackOf(activation.dispatch)}).decision, 'allow');
    starts.set(callId, {startDelivery: receipt(child, activation.dispatch, startStep), startObservation: receivedAck(child, activation.dispatch)});
    return activation;
  }
  await check('native returned child binds without fabrication; ordinary tools do not require enrollment', async () => {
    const call = await begin('race');
    assert.equal(tool('parent', 'invoke_subagent', call.dispatch.args).decision, 'allow');
    assert.equal(tool('race-child', 'view_file', {AbsolutePath: path.join(work, '.harness.json')}).decision, 'allow');
    assert.equal(tool('race-child', 'write_to_file', {TargetFile: path.join(work, 'canary')}).decision, 'allow');
    const bound = await bind('race', 'race-child');
    assert.equal(tool('race-child', 'write_to_file', {TargetFile: path.join(work, 'canary')}).decision, 'allow');
    context('race-child');
    await ready('race', 'race-child', bound);
    assert.equal(tool('race-child', 'write_to_file', {TargetFile: path.join(work, 'canary')}).decision, 'deny');
    const state = await scope('race-child');
    assert.match(fs.readFileSync(state.guardLog, 'utf8'), /r_grader_write/);
    const implementer = await active('implement', 'implementer');
    const spacedRoot = path.join(temp, 'plugin with spaces');
    fs.symlinkSync(root, spacedRoot, 'dir');
    for (const action of ['begin', 'bind', 'activate', 'complete']) {
      for (const [plugin, quote] of [[root, ''], [root, "'"], [root, '"'],
        [spacedRoot, "'"], [spacedRoot, '"']]) {
        const registrationCommand = {CommandLine: `node ${quote}${path.join(plugin, 'scripts/antigravity-role.mjs')}${quote} ${action} ${path.join(temp, 'input.json')}`, Cwd: work};
        assert.equal(tool('parent', 'run_command', registrationCommand).decision, 'allow');
        assert.equal(tool(implementer, 'run_command', registrationCommand).decision, 'allow');
      }
    }
    for (const id of ['parent', implementer])
      assert.equal(tool(id, 'run_command', {CommandLine: `node "${path.join(root, 'scripts/state.mjs')}" parent-register`, Cwd: work}).decision, 'deny');
    assert.equal(tool(implementer, 'run_command', {CommandLine: 'git status --short', Cwd: work}).decision, 'allow');
    assert.equal(tool(implementer, 'run_command', {CommandLine: 'git status --short && git diff --stat', Cwd: work}).decision, 'allow');
    assert.equal(tool(implementer, 'run_command', {CommandLine: `git status; node "${path.join(root, 'scripts/antigravity-role.mjs')}" begin input.json`, Cwd: work}).decision, 'allow');
    assert.equal(tool(implementer, 'run_command', {CommandLine: 'node "$ENROLLMENT" begin input.json', Cwd: work}).decision, 'allow');
    assert.equal(tool(implementer, 'run_command', {CommandLine: `bash -c 'node "${path.join(root, 'scripts/antigravity-role.mjs')}" begin input.json'`, Cwd: work}).decision, 'allow');
    assert.equal(tool(implementer, 'run_command', {CommandLine: 'bash tests/check.sh && node tests/check.mjs', Cwd: work}).decision, 'allow');
    assert.equal(tool(implementer, 'write_to_file', {TargetFile: path.join(work, 'canary')}).decision, 'allow');
    assert.equal(tool(implementer, 'write_to_file', {TargetFile: path.join(main, 'canary')}).decision, 'deny');
    assert.equal(tool(implementer, 'run_command', {CommandLine: 'git push origin HEAD', Cwd: work}).decision, 'deny');
  });
  await check('missing/cross-call/self identities and modified dispatch cannot bind', async () => {
    const call = await begin('badbind');
    assert.equal(tool('parent', 'invoke_subagent', {Subagents: [{...call.dispatch.args.Subagents[0], Model: 'flash'}]}).decision, 'allow');
    await assert.rejects(bind('badbind', 'other'), /dispatch/);
    assert.equal(tool('parent', 'invoke_subagent', call.dispatch.args).decision, 'allow');
    for (const child of ['parent', 'author']) await assert.rejects(bind('badbind', child), /self/);
    await assert.rejects(bindAntigravityRole({...coordinate('badbind'), observation: {source: 'child-report', tool: 'invoke_subagent', value: nativeReturn('bad')}}, options), /observation/);
    await assert.rejects(bindAntigravityRole({...coordinate('badbind'), observation: {source: 'parent-tool-return', tool: 'invoke_subagent', value: 'assistant says child is bad'}}, options), /unrecognized/);
    await bind('badbind', 'badbind-child');
    assert.equal(tool('parent', 'invoke_subagent', call.dispatch.args).decision, 'allow');
    await assert.rejects(bind('badbind', 'badbind-child'));
  });
  await check('explicit audit requires exact ready, ack and start while ordinary tools remain executable', async () => {
    const callId = 'delayed', child = 'delayed-child';
    const call = await begin(callId, 'implementer');
    assert.ok(!call.dispatch.args.Subagents[0].Prompt.includes(call.call.prompt));
    assert.equal(tool('parent', 'invoke_subagent', call.dispatch.args).decision, 'allow');
    context(child);
    tool(child, 'view_file', {AbsolutePath: path.join(work, '.harness.json')});
    assert.equal(tool(child, 'send_message', {Recipient: 'parent', Message: 'SIGNAL: IMPLEMENTATION_COMPLETE\nold'}).decision, 'allow');
    stop(child);
    const bound = await bind(callId, child);
    assert.equal(tool(child, 'write_to_file', {TargetFile: path.join(work, 'before-ready')}).decision, 'allow');
    const readyStep = step;
    assert.equal(tool('parent', 'send_message', {...bound.dispatch.args, Message: 'forged'}).decision, 'allow');
    const actualReadyStep = step;
    assert.equal(tool('parent', 'send_message', bound.dispatch.args).decision, 'allow');
    const input = {...coordinate(callId), childId: child,
      delivery: receipt(child, bound.dispatch, actualReadyStep), observation: receivedAck(child, bound.dispatch)};
    await assert.rejects(activateAntigravityRole(input, options), /acknowledgement/);
    context(child);
    assert.equal(tool(child, 'send_message', {Recipient: 'parent', Message: ackOf(bound.dispatch) + '-wrong'}).decision, 'allow');
    assert.equal(tool(child, 'send_message', {Recipient: 'parent', Message: ackOf(bound.dispatch)}).decision, 'allow');
    stop(child, {executionNum: 0});
    for (const change of [{childId: 'wrong'}, {delivery: {...input.delivery, success: false}},
      {callId: 'missing-call'}, {workspace: main},
      {delivery: {...input.delivery, stepIdx: readyStep}},
      {delivery: {...input.delivery, value: 'Message failed'}},
      {delivery: {...input.delivery, value: input.delivery.value.replace(child, 'wrong')}},
      {observation: {...input.observation, sender: 'wrong'}}, {observation: {...input.observation, body: 'old'}}])
      await assert.rejects(activateAntigravityRole({...input, ...change}, options));
    const otherSource = path.join(temp, 'other-source');
    fs.cpSync(root, otherSource, {recursive: true});
    await assert.rejects(activateAntigravityRole(input, {...options, root: otherSource}), /source mismatch/);
    const activation = await activateAntigravityRole(input, options);
    await assert.rejects(activateAntigravityRole(input, options));
    assert.equal(tool(child, 'write_to_file', {TargetFile: path.join(work, 'before-start')}).decision, 'allow');
    await assert.rejects(finish(callId, child), /not active/);
    const startStep = step;
    assert.equal(tool('parent', 'send_message', activation.dispatch.args).decision, 'allow');
    context(child);
    assert.equal(tool(child, 'write_to_file', {TargetFile: path.join(work, 'before-start-ack')}).decision, 'allow');
    assert.equal(tool(child, 'send_message', {Recipient: 'parent', Message: ackOf(activation.dispatch)}).decision, 'allow');
    starts.set(callId, {startDelivery: receipt(child, activation.dispatch, startStep), startObservation: receivedAck(child, activation.dispatch)});
    assert.equal(tool(child, 'write_to_file', {TargetFile: path.join(work, 'after-start')}).decision, 'allow');
    tool(child, 'send_message', {Recipient: 'parent', Message: 'SIGNAL: IMPLEMENTATION_COMPLETE\nfixture'});
    stop(child, {executionNum: 0});
    await assert.rejects(finish(callId, child, 'SIGNAL: IMPLEMENTATION_COMPLETE\nfixture'), /read\/result/);
    // The old preparation read cannot supply the required execution read.
  });
  await check('ordinary duplicate delivery stays allowed but invalidates only its explicit audit', async () => {
    const callId = 'duplicate-delivery', child = 'duplicate-delivery-child';
    const call = await begin(callId, 'implementer');
    tool('parent', 'invoke_subagent', call.dispatch.args); context(child);
    const bound = await bind(callId, child);
    const deliveryStep = step;
    assert.equal(tool('parent', 'send_message', bound.dispatch.args).decision, 'allow');
    assert.equal(tool('parent', 'send_message', bound.dispatch.args).decision, 'allow');
    assert.equal(tool(child, 'send_message', {Recipient: 'parent', Message: ackOf(bound.dispatch)}).decision, 'allow');
    await assert.rejects(activateAntigravityRole({...coordinate(callId), childId: child,
      delivery: receipt(child, bound.dispatch, deliveryStep), observation: receivedAck(child, bound.dispatch)}, options), /exact successful native message delivery/);
  });
  await check('idle preparation resumes into a fresh accepted execution with successful start delivery', async () => {
    const callId = 'delayed-success', child = 'delayed-success-child';
    const call = await begin(callId, 'implementer');
    tool('parent', 'invoke_subagent', call.dispatch.args); context(child); stop(child);
    const bound = await bind(callId, child); context(child);
    await ready(callId, child, bound, true);
    tool(child, 'view_file', {AbsolutePath: path.join(work, '.harness.json')});
    assert.equal(tool(child, 'write_to_file', {TargetFile: path.join(work, 'after-ready')}).decision, 'allow');
    const body = 'SIGNAL: IMPLEMENTATION_COMPLETE\nfixture';
    tool(child, 'send_message', {Recipient: 'parent', Message: body}); stop(child, {executionNum: 0});
    const evidence = starts.get(callId);
    starts.set(callId, {...evidence, startDelivery: {...evidence.startDelivery, success: false}});
    await assert.rejects(finish(callId, child, body), /delivery/);
    starts.set(callId, {...evidence, startObservation: {...evidence.startObservation, sender: 'wrong'}});
    await assert.rejects(finish(callId, child, body), /received/);
    starts.set(callId, evidence);
    assert.equal((await finish(callId, child, body)).signal, 'IMPLEMENTATION_COMPLETE');
  });
  await check('fresh child read, result and single successful idle close one exact call', async () => {
    const child = await active('success');
    assert.equal(tool(child, 'view_file', {AbsolutePath: path.join(work, '.harness.json')}).decision, 'allow');
    assert.equal(tool(child, 'send_message', {Recipient: 'other', Message: 'SIGNAL: LGTM\nfixture'}).decision, 'allow');
    assert.equal(tool(child, 'send_message', {Recipient: 'parent', Message: 'SIGNAL: LGTM\nfixture'}).decision, 'allow');
    stop(child);
    await assert.rejects(finish('success', 'another-child'), /child differs/);
    const result = await finish('success', child);
    assert.equal(result.signal, 'LGTM'); assert.equal(result.liveCertified, false); assert.equal(result.nativeLoaded, false);
    await assert.rejects(finish('success', child), /complete/);
  });
  await check('missing, interrupted, killed, repeated or reawakened Stop never supplies completion', async () => {
    for (const [name, override] of [['missing', null], ['busy', {fullyIdle: false}], ['error', {error: 'failure'}],
      ['killed', {terminationReason: 'CANCELLED'}], ['later-turn', {executionNum: 1}], ['repeat', {}], ['reawakened', {}]]) {
      const child = await active(name);
      tool(child, 'view_file', {AbsolutePath: path.join(work, '.harness.json')});
      tool(child, 'send_message', {Recipient: 'parent', Message: 'SIGNAL: LGTM\nfixture'});
      if (override) stop(child, override);
      if (name === 'repeat') stop(child);
      if (name === 'reawakened') context(child);
      await assert.rejects(finish(name, child), /completion/);
    }
  });
  await check('wrapper-requested continuation accepts only refreshed result after continuous Stop0 to Stop1', async () => {
    const child = await active('continue');
    tool(child, 'view_file', {AbsolutePath: path.join(work, '.harness.json')});
    tool(child, 'send_message', {Recipient: 'parent', Message: 'SIGNAL: CHANGES_REQUESTED\nold fixture result'});
    await recordStateEvent(antigravityEvent('stop', {conversationId: child, workspacePaths: [work],
      executionNum: 0, fullyIdle: true, terminationReason: 'NO_TOOL_CALL', error: ''}), 0, env, root,
      {stdout: JSON.stringify({decision: 'block'})});
    context(child);
    stop(child, {executionNum: 1});
    await assert.rejects(finish('continue', child), /result chain/);
    // Separate fresh child proves the legitimate continued path without editing
    // the earlier native observations to make its failed result appear valid.
    const fresh = await active('continued-success');
    tool(fresh, 'view_file', {AbsolutePath: path.join(work, '.harness.json')});
    await recordStateEvent(antigravityEvent('stop', {conversationId: fresh, workspacePaths: [work],
      executionNum: 0, fullyIdle: true, terminationReason: 'NO_TOOL_CALL', error: ''}), 0, env, root,
      {stdout: JSON.stringify({decision: 'block'})});
    context(fresh);
    tool(fresh, 'send_message', {Recipient: 'parent', Message: 'SIGNAL: LGTM\nnew fixture result'});
    stop(fresh, {executionNum: 1});
    assert.equal((await finish('continued-success', fresh, 'SIGNAL: LGTM\nnew fixture result')).executionNum, 1);
  });
  console.log(JSON.stringify({origin: 'fixture', checks, liveCertified: false}));
} finally {fs.rmSync(temp, {recursive: true, force: true});}
