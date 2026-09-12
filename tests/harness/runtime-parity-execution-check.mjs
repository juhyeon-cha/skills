import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {evaluateGuard} from '../../plugins/harness/lib/guard/guard.mjs';
import {antigravityEvent, antigravityOutput} from '../../plugins/harness/lib/runtime/antigravity-hook.mjs';
import {resolveState, recordStateEvent, cancelSession, isCancelled, readActors} from '../../plugins/harness/lib/runtime/state.mjs';
import {registerAntigravityParent} from '../../plugins/harness/lib/runtime/antigravity-identity.mjs';
import {inspectDistribution} from '../../plugins/harness/lib/distribution.mjs';
import {evaluateStop, MAX_BLOCKS} from '../../plugins/harness/lib/runtime/stop.mjs';

const root = fileURLToPath(new URL('../../plugins/harness/', import.meta.url));
const temp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'parity-execution-')));
const main = path.join(temp, 'repo'), work = path.join(temp, 'work'), bare = path.join(temp, 'remote.git');
const base = {...process.env, HOME: temp, HARNESS_DATA_DIR: path.join(temp, 'data'), HARNESS_ROOT: main,
  GIT_CONFIG_GLOBAL: os.devNull, GIT_CONFIG_NOSYSTEM: '1', GIT_TERMINAL_PROMPT: '0'};
for (const key of ['PLUGIN_ROOT','PLUGIN_DATA','CLAUDE_PLUGIN_ROOT','CLAUDE_PLUGIN_DATA','HARNESS_RUNTIME',
  'HARNESS_GUARD_LOG','HARNESS_DOCTOR_DIR','GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR','GIT_INDEX_FILE']) delete base[key];
const run = (cmd, args, options = {}) => spawnSync(cmd, args, {env: base, encoding: 'utf8', ...options});
const git = (...args) => {const r = run('git', args); assert.equal(r.status, 0, r.stderr);};
const envelope = (name, args, extra = {}) => ({conversationId: 'parent', workspacePaths: [work], toolCall: {name, args}, stepIdx: 0, ...extra});
const invocation = {conversationId: 'parent', workspacePaths: [work], invocationNum: 0, initialNumSteps: 0};
const envFor = runtime => ({...base, HARNESS_RUNTIME: runtime});
const hook = (id, input, runtime = 'antigravity') => run(process.execPath, [path.join(root, 'scripts/hook.mjs'), id, '--runtime', runtime], {input: JSON.stringify(input), env: envFor(runtime), cwd: work});
const guardCode = input => {
  const result = hook('guard', input); assert.equal(result.status, 0, result.stderr);
  const decision = JSON.parse(result.stdout).decision;
  assert.ok(['allow', 'deny'].includes(decision)); return decision === 'allow' ? 0 : 2;
};
const scopeFor = (runtime, sessionId = 'parent', cwd = work) => resolveState({runtime, cwd, sessionId}, envFor(runtime));
let checks = 0;
const check = async (label, fn) => {await fn(); checks++; console.log('PASS ' + label);};
try {
  git('init', '-q', main);
  fs.writeFileSync(path.join(main, '.harness.json'), JSON.stringify({ledger: {backend: 'beads'}}));
  git('-C', main, 'add', '.'); git('-C', main, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture');
  git('-C', main, 'worktree', 'add', '-qb', 'fixture-work', work); git('init', '--bare', '-q', bare);
  git('-C', work, 'remote', 'add', 'origin', bare);
  const agEnv = envFor('antigravity');
  await check('actual wrapper context/read before external parent registration; mutation denied', async () => {
    const context = hook('context', invocation); assert.equal(context.status, 0, context.stderr);
    const injected = JSON.parse(context.stdout).injectSteps[0].ephemeralMessage;
    assert.match(injected, /HARNESS_STATE_JSON/); assert.match(injected, /antigravity/);
    assert.equal(hook('guard', envelope('view_file', {AbsolutePath: path.join(work, '.harness.json')})).status, 0);
    const denied = hook('guard', envelope('write_to_file', {TargetFile: path.join(work, 'allowed.txt')}));
    assert.equal(denied.status, 0); assert.equal(JSON.parse(denied.stdout).decision, 'deny');
    const state = await scopeFor('antigravity');
    const rows = fs.readFileSync(state.events, 'utf8').trim().split('\n').map(line => JSON.parse(line));
    assert.equal(rows.at(-1).code, 2, 'transport zero cannot promote the denied policy receipt');
    await assert.rejects(registerAntigravityParent(state, 'wrong', root), /source hash/);
    const registered = run(process.execPath, [path.join(root, 'scripts/state.mjs'), '--data', base.HARNESS_DATA_DIR,
      'parent-register', 'antigravity', work, 'parent', inspectDistribution(root).hash], {env: agEnv});
    assert.equal(registered.status, 0, registered.stderr);
    const allowed = hook('guard', envelope('write_to_file', {TargetFile: path.join(work, 'allowed.txt')}));
    assert.equal(allowed.status, 0, allowed.stderr); assert.equal(JSON.parse(allowed.stdout).decision, 'allow');
    for (const target of [path.join(main, 'denied.txt'), path.join(work, '.harness.json'), path.join(state.session, 'antigravity-parent.json')])
      assert.equal(guardCode(envelope('write_to_file', {TargetFile: target})), 2);
    assert.equal(guardCode(envelope('run_command', {CommandLine: 'node state.mjs parent-register', Cwd: work})), 2);
  });
  await check('parent registration scope/source/child negative controls cannot promote actors', async () => {
    const state = await scopeFor('antigravity');
    const file = path.join(state.session, 'antigravity-parent.json'), original = fs.readFileSync(file, 'utf8');
    for (const mutate of [r => r.sessionId = 'other', r => r.workspace = main, r => r.source.hash = 'stale', r => r.kind = 'child']) {
      const record = JSON.parse(original); mutate(record); fs.writeFileSync(file, JSON.stringify(record));
      assert.equal(guardCode(envelope('write_to_file', {TargetFile: path.join(work, 'allowed.txt')})), 2);
    }
    fs.writeFileSync(file, '{');
    assert.equal(guardCode(envelope('write_to_file', {TargetFile: path.join(work, 'allowed.txt')})), 2, 'internal identity read error delivers native deny');
    fs.writeFileSync(file, original);
    const child = await scopeFor('antigravity', 'child'); fs.mkdirSync(child.session, {recursive: true});
    fs.writeFileSync(child.actors, JSON.stringify({runtime: 'antigravity', repoKey: child.repoKey, sessionId: 'child',
      claims: [{actor: 'mine', evidence: 'ledger-show'}]}));
    assert.equal(readActors(child).status, 'VERIFIED');
    assert.equal(guardCode(envelope('write_to_file', {TargetFile: path.join(work, 'allowed.txt')}, {conversationId: 'child'})), 2);
    assert.equal(guardCode(envelope('run_command', {CommandLine: 'echo fixture', Cwd: main})), 2);
  });
  await check('registration requires wrapper-observed current source and exact worktree', async () => {
    const state = await scopeFor('antigravity', 'provenance');
    const actual = hook('context', {...invocation, conversationId: 'provenance', source: {root: 'forged', hash: 'forged'}});
    assert.equal(actual.status, 0, actual.stderr);
    const original = fs.readFileSync(state.events, 'utf8');
    const row = JSON.parse(original.trim());
    assert.deepEqual(row.observation.source, {root: inspectDistribution(root).root, hash: inspectDistribution(root).hash});
    for (const mutate of [r => delete r.observation, r => r.observation.source.hash = 'old-artifact',
      r => r.observation.source.root = main, r => r.observation.workspace = main,
      r => r.observation.kind = 'operator-attested']) {
      const changed = JSON.parse(original); mutate(changed);
      fs.writeFileSync(state.events, JSON.stringify(changed) + '\n');
      await assert.rejects(registerAntigravityParent(state, inspectDistribution(root).hash, root), /context not observed/);
    }
    fs.writeFileSync(state.events, '');
    await recordStateEvent({...antigravityEvent('context', {...invocation, conversationId: 'provenance'}),
      source: row.observation.source, observation: row.observation}, 0, agEnv);
    await assert.rejects(registerAntigravityParent(state, inspectDistribution(root).hash, root), /context not observed/);
    fs.writeFileSync(state.events, original);
    await registerAntigravityParent(state, inspectDistribution(root).hash, root);
    const other = await scopeFor('antigravity', 'other-workspace');
    assert.equal(hook('context', {...invocation, conversationId: 'other-workspace', workspacePaths: [main]}).status, 0);
    await assert.rejects(registerAntigravityParent(other, inspectDistribution(root).hash, root), /context not observed/);
    const copy = path.join(temp, 'artifact-copy'); fs.cpSync(root, copy, {recursive: true});
    const copiedState = await scopeFor('antigravity', 'copied-source');
    const copied = run(process.execPath, [path.join(copy, 'scripts/hook.mjs'), 'context', '--runtime', 'antigravity'], {
      input: JSON.stringify({...invocation, conversationId: 'copied-source'}), env: agEnv, cwd: work});
    assert.equal(copied.status, 0, copied.stderr);
    await assert.rejects(registerAntigravityParent(copiedState, inspectDistribution(root).hash, root), /context not observed/);
    fs.appendFileSync(path.join(copy, 'hooks/session-context.md'), '\nChanged fixture source.\n');
    await assert.rejects(registerAntigravityParent(copiedState, inspectDistribution(copy).hash, copy), /context not observed/);
  });
  await check('malformed/ambiguous/unsupported provider envelopes fail closed with native deny', () => {
    for (const input of [null, {}, envelope('unknown', {}), envelope('run_command', {CommandLine: 'pwd'}),
      envelope('write_to_file', {TargetFile: 'relative'}), envelope('view_file', {AbsolutePath: main}, {workspacePaths: [work, main]}),
      envelope('manage_task', {Action: 'send_input', Input: 'rm -rf canary'}), envelope('invoke_subagent', {})]) {
      assert.equal(guardCode(input), 2);
    }
    assert.throws(() => antigravityEvent('role-start', invocation));
  });
  // M4's child identity resolver is synthetic here, never native role evidence.
  const childResolver = async () => ({kind: 'child', role: 'harness:implementer'});
  const eventFor = (runtime, kind, target) => {
    if (runtime === 'antigravity') return antigravityEvent('guard', envelope(kind === 'shell' ? 'run_command' : 'write_to_file',
      kind === 'shell' ? {CommandLine: target, Cwd: work} : {TargetFile: target}));
    return {hook_event_name: 'PreToolUse', cwd: work, session_id: 'parent', agent_id: 'fixture-child', agent_type: 'harness:implementer',
      tool_name: kind === 'shell' ? (runtime === 'codex' ? 'exec_command' : 'Bash') : 'Write',
      tool_input: kind === 'shell' ? {command: target} : {file_path: target}};
  };
  const judge = (runtime, event) => evaluateGuard(event, {env: envFor(runtime), pluginRoot: root, resolveAntigravityIdentity: childResolver});
  await check('canonical state aliases deny direct writes and preserve common state commands', async () => {
    fs.mkdirSync(base.HARNESS_DATA_DIR, {recursive: true});
    const alias = path.join(temp, 'data-alias'); fs.symlinkSync(base.HARNESS_DATA_DIR, alias);
    const aliases = [alias, base.HARNESS_DATA_DIR];
    if (process.platform === 'darwin' && temp.startsWith('/private/tmp/')) aliases.push(base.HARNESS_DATA_DIR.replace('/private/tmp/', '/tmp/'));
    for (const data of aliases) {
      const env = {...envFor('claude'), HARNESS_DATA_DIR: data};
      const evaluate = event => evaluateGuard(event, {env, pluginRoot: root});
      for (const target of [path.join(data, 'actors.json'), path.join(base.HARNESS_DATA_DIR, 'actors.json')])
        assert.equal((await evaluate(eventFor('claude', 'file', target))).code, 2);
      for (const action of [`cancel claude ${work} parent`, `bind claude ${work} parent ${main} fixture-task fixture-actor`, `paths claude ${work} parent`, `actors claude ${work} parent`, `cancelled claude ${work} parent`]) {
        const result = await evaluate(eventFor('claude', 'shell', `node ${path.join(root, 'scripts/state.mjs')} --data ${data} ${action}`));
        assert.equal(result.code, 0, result.stderr);
      }
    }
    const invalid = await evaluateGuard(eventFor('claude', 'file', path.join(work, 'a')), {
      env: {...envFor('claude'), HARNESS_DATA_DIR: 'relative-state'}, pluginRoot: root});
    assert.equal(invalid.code, 2);
    const missing = path.join(temp, 'not-created', 'state');
    const missingResult = await evaluateGuard(eventFor('claude', 'file', path.join(missing, 'actors.json')), {
      env: {...envFor('claude'), HARNESS_DATA_DIR: missing}, pluginRoot: root});
    assert.equal(missingResult.code, 2, 'new state roots remain protected before creation');
  });
  await check('shared verified-role seam allows worktree writes and denies main/protected/remote canaries', async () => {
    fs.symlinkSync(main, path.join(work, 'main-alias'));
    for (const runtime of ['claude', 'codex', 'antigravity']) {
      const allowed = await judge(runtime, eventFor(runtime, 'file', path.join(work, 'allowed.txt'))); assert.equal(allowed.code, 0, allowed.stderr);
      for (const target of [path.join(main, 'denied.txt'), path.join(work, 'main-alias', 'denied.txt'), ...['.git', '.harness.json', '.agents/hooks.json', '.codex/config.toml'].map(p => path.join(work, p))])
        assert.equal((await judge(runtime, eventFor(runtime, 'file', target))).code, 2, runtime + ' ' + target);
      const denied = await judge(runtime, eventFor(runtime, 'shell', 'git push origin HEAD:refs/heads/canary'));
      assert.equal(denied.code, 2); assert.equal(denied.rule, 'r_remote');
      const status = await judge(runtime, eventFor(runtime, 'shell', 'git status --porcelain')); assert.equal(status.code, 0, status.stderr);
      assert.equal((await judge(runtime, {...eventFor(runtime, 'file', path.join(work, 'a')), tool_name: 'future_unclassified_tool'})).code, 2);
    }
    assert.equal(run('git', ['--git-dir', bare, 'show-ref']).status, 1, 'no remote ref was written');
  });
  await check('bootstrap/check configured input, stdout and failing exit survive each runtime', () => {
    for (const runtime of ['claude', 'codex', 'antigravity']) for (const [field, code] of [['bootstrap', 13], ['check', 17]]) {
      fs.writeFileSync(path.join(work, '.harness.json'), JSON.stringify({ledger: {backend: 'beads'},
        [field]: {argv: [process.execPath, '-e', `process.stdout.write(process.argv[1]);process.exit(${code})`, 'literal $HOME 한글']}}));
      const result = run(process.execPath, [path.join(root, 'scripts/config.mjs'), 'run', work, field], {env: envFor(runtime)});
      assert.equal(result.status, code, result.stderr); assert.equal(result.stdout, 'literal $HOME 한글');
    }
    fs.writeFileSync(path.join(work, '.harness.json'), JSON.stringify({ledger: {backend: 'beads'}}));
  });
  const bindFixture = async (runtime, session) => {
    const scope = await scopeFor(runtime, session); fs.mkdirSync(scope.session, {recursive: true});
    fs.writeFileSync(scope.actors, JSON.stringify({runtime, repoKey: scope.repoKey, sessionId: session,
      claims: [{task: 'fixture-task', actor: 'mine', evidence: 'ledger-show'}]}));
    return scope;
  };
  await check('runtime/session actor and cancellation isolation; common bounded Stop decisions', async () => {
    const sessions = [];
    for (const runtime of ['claude', 'codex', 'antigravity']) {
      const scope = await bindFixture(runtime, 'stop'); sessions.push(scope.session);
      const event = runtime === 'antigravity' ? antigravityEvent('stop', {...invocation, conversationId: 'stop', fullyIdle: true, executionNum: 0, terminationReason: 'NO_TOOL_CALL'}) : {cwd: work, session_id: 'stop'};
      const options = {env: envFor(runtime), rootFinder: async () => main,
        ledger: async (_args, coordinates) => {assert.equal(coordinates.root, main); return {code: 0, stdout: JSON.stringify([{actor: 'mine', notes: ''}, {actor: 'other', notes: ''}])};}};
      for (let i = 0; i < MAX_BLOCKS; i++) {
        const result = await evaluateStop(event, options); assert.deepEqual(result.outcomes, ['BLOCK']);
        const output = runtime === 'antigravity' ? antigravityOutput('stop', result) : result.stdout;
        assert.equal(JSON.parse(output).decision, runtime === 'antigravity' ? 'continue' : 'block');
      }
      assert.deepEqual((await evaluateStop(event, options)).outcomes, ['GAVE_UP']);
      cancelSession(scope); assert.deepEqual((await evaluateStop(event, options)).outcomes, ['CANCEL']);
      assert.equal(isCancelled(await scopeFor(runtime, 'another')), false);
      const oracleEvent = {...event, session_id: 'oracle'};
      assert.deepEqual((await evaluateStop(oracleEvent, {...options, ledger: async () => ({code: 19})})).outcomes, ['ORACLE_FAIL']);
      const corrupted = JSON.parse(fs.readFileSync(scope.actors, 'utf8')); corrupted.runtime = 'wrong'; fs.writeFileSync(scope.actors, JSON.stringify(corrupted));
      assert.throws(() => readActors(scope));
    }
    assert.equal(new Set(sessions).size, 3);
    const common = antigravityEvent('stop', {...invocation, fullyIdle: false, executionNum: 1, terminationReason: 'NO_TOOL_CALL'});
    assert.deepEqual((await evaluateStop(common, {env: agEnv})).outcomes, ['RUNTIME_BUSY']);
    assert.deepEqual((await evaluateStop({...common, runtime_error: 'fixture failure'}, {env: agEnv})).outcomes, ['RUNTIME_ERROR']);
  });
  await check('allow control rejects a copied all-blocked guard mutation', async () => {
    const copy = path.join(temp, 'mutant'); fs.cpSync(root, copy, {recursive: true});
    const file = path.join(copy, 'lib/guard/guard.mjs'), before = fs.readFileSync(file, 'utf8');
    const after = before.replace("result = { code: 0, stdout: '', stderr: '', rule };", "result = { code: 2, stdout: '', stderr: 'all blocked mutant', rule };");
    assert.notEqual(before, after); fs.writeFileSync(file, after);
    const mutant = await import(pathToFileURL(file));
    const result = await mutant.evaluateGuard(eventFor('claude', 'file', path.join(work, 'allowed.txt')), {env: envFor('claude')});
    assert.throws(() => assert.equal(result.code, 0));
  });
  console.log(`PASS ${checks} execution fixture groups; no CLI/desktop live certification; AG child resolver synthetic`);
} finally {fs.rmSync(temp, {recursive: true, force: true});}
