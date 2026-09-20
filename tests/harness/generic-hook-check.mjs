import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { beginDelegation, bindDelegation, completeDelegation } from '../../plugins/harness/lib/runtime/delegation.mjs';
import { loadRole } from '../../plugins/harness/lib/runtime/roles.mjs';
import { evaluateGuard } from '../../plugins/harness/lib/guard/guard.mjs';
import { normalizeHookEvent } from '../../plugins/harness/lib/guard/hook-event.mjs';
import { resolveState } from '../../plugins/harness/lib/runtime/state.mjs';

const plugin = fileURLToPath(new URL('../../plugins/harness/', import.meta.url));
const temp = await fs.promises.realpath(fs.mkdtempSync(path.join(os.tmpdir(), 'generic-hook-')));
const repo = path.join(temp, 'repo');
const env = { ...process.env, HARNESS_RUNTIME: 'codex', HARNESS_DATA_DIR: path.join(temp, 'data'), GIT_CONFIG_GLOBAL: path.join(temp, 'gitconfig'), GIT_CONFIG_NOSYSTEM: '1' };
for (const key of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR', 'HARNESS_ROOT', 'HARNESS_GUARD_LOG']) delete env[key];
const git = (...args) => {
  const result = spawnSync('git', ['-C', repo, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', ...args], { env, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
};
try {
  fs.mkdirSync(repo);
  fs.writeFileSync(env.GIT_CONFIG_GLOBAL, '');
  git('init', '-qb', 'fixture');
  fs.writeFileSync(path.join(repo, '.harness.json'), '{}\n');
  git('add', '.'); git('commit', '-qm', 'base');
  const head = git('rev-parse', 'HEAD');
  const worktree = path.join(temp, 'worktree');
  git('worktree', 'add', '-qb', 'worktree-fixture', worktree);
  // Replay exec_command inputs preserved in generic-child-observation.md.
  // The UUID/default envelope is the preserved Codex shape; metadata is a fixture.
  const ordinary = {cwd: worktree, session_id: 'generic-session',
    agent_id: '01a093ff-1e5b-7302-9ed5-8ba5379852bb', agent_type: 'default',
    tool_name: 'exec_command', tool_input: {cmd: `python3 -c 'print("generic-child-probe")'`}};
  const ordinaryMetadata = {thread: {id: ordinary.agent_id, source: {subAgent: {thread_spawn: {
    parent_thread_id: ordinary.session_id, depth: 1, agent_path: '/root/generic_probe', agent_role: null,
  }}}}};
  const ordinaryGuard = (changes = {}, reply = ordinaryMetadata) => evaluateGuard({...ordinary, ...changes}, {
    pluginRoot: plugin, env, readThread: async () => reply,
  });
  for (const action of [
    {},
    {tool_input: {cmd: `python3 -c 'import tempfile; f = tempfile.NamedTemporaryFile(prefix="generic-child-probe-", dir="/private/tmp", delete=False); print(f.name); f.close()'`}},
    {tool_name: 'Write', tool_input: {file_path: path.join(worktree, 'ordinary.txt'), content: 'allowed'}},
    {tool_name: 'apply_patch', tool_input: {command: `*** Begin Patch\n*** Add File: ${worktree}/ordinary.txt\n+allowed\n*** End Patch`}},
    {tool_name: 'collaborationspawn_agent', tool_input: {task_name: 'nested', message: 'Inspect locally'}},
  ]) assert.equal((await ordinaryGuard(action)).code, 0, JSON.stringify(action));
  assert.equal((await ordinaryGuard({agent_type: 'unknown'})).code, 2);
  assert.equal((await ordinaryGuard({agent_type: 'harness-reviewer', tool_name: 'Write',
    tool_input: {file_path: path.join(worktree, 'blocked.txt')}})).code, 2,
  'a native role claim still selects its restrictions');
  for (const [action, rule] of [
    [{tool_name: 'Write', tool_input: {file_path: path.join(repo, 'blocked.txt')}}, 'r_main_write'],
    [{tool_name: 'Write', tool_input: {file_path: path.join(env.HARNESS_DATA_DIR, 'blocked.txt')}}, 'r_main_write'],
    [{tool_input: {cmd: `touch '${repo}/blocked.txt'`}}, 'r_main_shell'],
    [{tool_input: {cmd: 'git push origin HEAD'}}, 'r_remote'],
    [{tool_input: {cmd: 'gh pr create --title forbidden'}}, 'r_remote'],
    [{tool_input: {cmd: 'ledger.mjs note task forbidden'}}, 'r_bd_root'],
    [{tool_name: 'mcp__codex_app__create_thread', tool_input: {}}, 'r_task_create'],
  ]) {
    const denied = await ordinaryGuard(action);
    assert.equal(denied.code, 2, JSON.stringify(action));
    assert.equal(denied.rule, rule, denied.stderr);
  }
  for (const childPath of ['/root/harness_missing', '/root/harness_missing/nested']) {
    const reply = structuredClone(ordinaryMetadata);
    reply.thread.source.subAgent.thread_spawn.agent_path = childPath;
    assert.equal((await ordinaryGuard({}, reply)).code, 2, 'managed namespace cannot lose its inventory');
  }
  // Prove both sides of the classification gate using changed source copies.
  const classification = "if (!child.split('/').some(part => part.startsWith('harness_'))) return null;";
  for (const [label, replacement, childPath, expected] of [
    ['restore-blanket-denial', '', '/root/generic_probe', 2],
    ['disable-managed-boundary', 'return null;', '/root/harness_missing', 0],
  ]) {
    const copy = path.join(temp, label);
    fs.cpSync(plugin, copy, {recursive: true});
    const source = path.join(copy, 'lib/runtime/delegation.mjs');
    const original = fs.readFileSync(source, 'utf8');
    assert.ok(original.includes(classification));
    fs.writeFileSync(source, original.replace(classification, replacement));
    assert.notEqual(fs.readFileSync(source, 'utf8'), original);
    const mutant = await import(pathToFileURL(path.join(copy, 'lib/guard/guard.mjs')));
    const reply = structuredClone(ordinaryMetadata);
    reply.thread.source.subAgent.thread_spawn.agent_path = childPath;
    const result = await mutant.evaluateGuard(ordinary, {pluginRoot: copy, env, readThread: async () => reply});
    assert.equal(result.code, expected, label + ': ' + result.stderr);
    if (expected === 2) assert.match(result.stderr, /child role is unidentified/);
  }
  const call = { version: 1, runtime: 'codex', provider: 'collaboration', repository: worktree, data: env.HARNESS_DATA_DIR, sessionId: 'generic-session', parentAgentId: '/root', callId: 'read-review', role: 'reviewer', task: 'fixture#1', sourceHash: loadRole('reviewer', plugin).sha256, commitScope: { mode: 'fixed', base: head, head, branch: 'worktree-fixture' }, implementerIds: ['/root/author'], previousAgentIds: [], permission: 'prompt-only' };
  const pending = await beginDelegation(call, { root: plugin, env });
  assert.equal(pending.status, 'PENDING');
  const child = `/root/${pending.dispatch.task_name}`;
  // Hook cwd is the parent session checkout; the call is bound to its linked tree.
  // A command outside the read exemption exercises the role-dependent path.
  // Ordinary reads are covered by child-read-check and need no inventory.
  const event = { tool_name: 'Bash', cwd: repo, session_id: call.sessionId, agent_id: child, tool_input: { command: 'node --version' } };
  const guard = (changes = {}) => evaluateGuard({ ...event, ...changes }, { pluginRoot: plugin, env });
  const beforeBind = await guard();
  const bound = await bindDelegation({ call, observation: { source: 'parent-tool-return', tool: 'collaboration.spawn_agent', value: { task_name: child } } }, { root: plugin, env });
  assert.equal(bound.status, 'PENDING');
  const afterBind = await guard();
  if (process.argv.includes('--baseline')) {
    for (const result of [beforeBind, afterBind]) {
      assert.equal(result.code, 2);
      assert.match(result.stderr, /child role is unidentified/);
    }
    assert.equal((await guard({ agent_type: 'harness-reviewer' })).code, 0);
    console.log('PASS baseline: begin/bind PENDING; generic command rejected before and after bind; native command allowed');
  } else {
    assert.equal(pending.dispatch.model, undefined);
    assert.equal(pending.dispatch.reasoning_effort, undefined);
    assert.equal(pending.dispatch.fork_turns, undefined);
    assert.equal(beforeBind.code, 0, beforeBind.stderr);
    assert.equal(afterBind.code, 0, afterBind.stderr);
    // Codex 0.154.0 actual hook shape: UUID + default profile. The tool path
    // comes from App Server metadata, not from time ordering or child prose.
    const nativeEvent = { ...event, agent_id: '01a093ff-1e5b-7302-9ed5-8ba5379852bb', agent_type: 'default' };
    const metadata = { thread: { id: nativeEvent.agent_id, source: { subAgent: { thread_spawn: {
      parent_thread_id: call.sessionId, depth: 1, agent_path: child, agent_role: null,
    } } } } };
    const nativeGuard = (changes = {}, reply = metadata) => evaluateGuard({ ...nativeEvent, ...changes }, {
      pluginRoot: plugin, env, readThread: async () => reply,
    });
    assert.equal((await nativeGuard()).code, 0, 'UUID/default resolves via authoritative path');
    for (const edit of [
      r => { r.thread.id = 'different'; },
      r => { r.thread.source.subAgent.thread_spawn.parent_thread_id = 'foreign'; },
      r => { delete r.thread.source.subAgent.thread_spawn.agent_path; },
      r => { r.thread.source.subAgent.thread_spawn.agent_role = 'worker'; },
      r => { r.thread.agentRole = 'harness-reviewer'; },
      r => { r.thread.source = 'cli'; },
    ]) {
      const reply = structuredClone(metadata); edit(reply);
      assert.equal((await nativeGuard({}, reply)).code, 2);
    }
    assert.equal((await nativeGuard({ agent_id: child })).code, 2, 'default requires runtime UUID');
    assert.equal((await evaluateGuard(nativeEvent, { pluginRoot: plugin, env, readThread: async () => { throw Error('offline'); } })).code, 2);
    assert.equal((await nativeGuard({ tool_name: 'Write', tool_input: { file_path: path.join(worktree, 'blocked.txt') } })).code, 2);
    assert.equal((await nativeGuard({ tool_name: 'Bash', tool_input: { command: 'git commit -m blocked' } })).code, 2);
    const hook = spawnSync(process.execPath, [path.join(plugin, 'hooks/guard.mjs')], { env: { ...env, CLAUDE_PLUGIN_ROOT: plugin }, input: JSON.stringify(event), encoding: 'utf8' });
    assert.equal(hook.status, 0, hook.stderr);
    assert.equal((await guard({ cwd: worktree })).code, 0);
    for (const changes of [{ session_id: 'foreign' }, { session_id: undefined }, { agent_type: 'unknown' }]) assert.equal((await guard(changes)).code, 2);
    assert.equal((await guard({agent_id: '/root/unregistered'})).code, 0);
    assert.equal((await guard({agent_id: '/root/unregistered', harness_policy_role: 'harness:reviewer'})).code, 0);
    assert.equal((await ordinaryGuard()).code, 0, 'unrelated managed inventory does not enroll ordinary children');
    assert.equal(normalizeHookEvent(event, { delegatedRole: 'harness:reviewer' }).agent_type, '', 'generic policy must not fabricate native identity');
    assert.equal(normalizeHookEvent({ ...event, agent_id: '', harness_policy_role: 'harness:implementer' }).harness_policy_role, '', 'raw policy claims are ignored');
    const scope = await resolveState({ cwd: repo, sessionId: call.sessionId }, env);
    const directory = path.join(scope.session, 'delegation');
    const mutate = async (suffix, edit) => {
      const target = path.join(directory, fs.readdirSync(directory).find(name => name.endsWith(suffix)));
      const original = fs.readFileSync(target, 'utf8');
      try {
        fs.writeFileSync(target, edit(JSON.parse(original)));
        assert.equal((await guard()).code, 2, `${suffix} corruption must fail closed`);
        assert.equal((await ordinaryGuard()).code, 0, 'unrelated corrupt records do not enroll ordinary children');
        assert.equal((await guard({tool_name: 'Read', tool_input: {file_path: path.join(worktree, '.harness.json')}})).code, 0,
          'corrupt role evidence must not block inspection');
      } finally { fs.writeFileSync(target, original); }
      assert.equal((await guard()).code, 0, 'restored record must allow read');
    };
    await mutate('.call.json', record => { record.value.sourceHash = '0'.repeat(64); return JSON.stringify(record); });
    await mutate('.call.json', record => { record.value.sessionId = 'foreign'; return JSON.stringify(record); });
    await mutate('.call.json', record => { record.value.role = 'implementer'; return JSON.stringify(record); });
    await mutate('.call.json', () => '{broken');
    await mutate('.binding.json', record => { record.value.child = '/root/foreign'; return JSON.stringify(record); });
    await mutate('.dispatch.json', record => { record.value.task_name = 'harness_' + '0'.repeat(32); return JSON.stringify(record); });
    const foreign = path.join(temp, 'foreign');
    fs.mkdirSync(foreign);
    const initialized = spawnSync('git', ['init', '-q', foreign], { env, encoding: 'utf8' });
    assert.equal(initialized.status, 0, initialized.stderr);
    assert.equal((await guard({ cwd: foreign })).code, 2, 'other repository cannot borrow inventory');
    assert.equal((await evaluateGuard(event, { pluginRoot: plugin, env: { ...env, HARNESS_DATA_DIR: path.join(temp, 'foreign-data') } })).code, 2);
    assert.equal((await guard({ agent_type: 'harness-reviewer' })).code, 0);
    for (const changes of [
      { tool_name: 'Write', tool_input: { file_path: path.join(worktree, 'blocked.txt'), content: 'no' } },
      { tool_name: 'Bash', tool_input: { command: 'git commit -m forbidden' } },
      { tool_name: 'Bash', tool_input: { command: 'ledger.mjs note fixture#1 forbidden' } },
    ]) {
      assert.equal((await guard(changes)).code, 2);
      assert.equal((await guard({ ...changes, agent_type: 'harness-reviewer' })).code, 2);
    }
    const outcome = await completeDelegation({ call, head, observation: { source: 'parent-tool-return', tool: 'collaboration.list_agents', value: { agents: [{ agent_name: child, agent_status: { completed: 'SIGNAL: UNREACHED' } }] } } }, { root: plugin, env });
    assert.equal(outcome.status, 'REJECTED');
    assert.equal((await guard()).code, 2);
    assert.equal((await guard({tool_name: 'Read', tool_input: {file_path: path.join(worktree, '.harness.json')}})).code, 0,
      'terminal result ends role permission, not inspection');
    assert.equal((await nativeGuard()).code, 2, 'UUID cannot revive a terminal call');
    const successfulCall = { ...call, callId: 'successful-review' };
    const successful = await beginDelegation(successfulCall, { root: plugin, env });
    const successfulChild = `/root/${successful.dispatch.task_name}`;
    await bindDelegation({ call: successfulCall, observation: { source: 'parent-tool-return', tool: 'collaboration.spawn_agent', value: { task_name: successfulChild } } }, { root: plugin, env });
    const accepted = await completeDelegation({ call: successfulCall, head, observation: { source: 'parent-tool-return', tool: 'collaboration.list_agents', value: { agents: [{ agent_name: successfulChild, agent_status: { completed: 'SIGNAL: LGTM' } }] } } }, { root: plugin, env });
    assert.equal(accepted.status, 'OBSERVED');
    assert.equal((await guard({ agent_id: successfulChild })).code, 2, 'successful completion also ends execution');
    const implementation = { ...call, callId: 'implementation', role: 'implementer', sourceHash: loadRole('implementer', plugin).sha256, commitScope: { mode: 'implementation', base: head, branch: 'worktree-fixture' }, implementerIds: [] };
    const impl = await beginDelegation(implementation, { root: plugin, env });
    const implChild = `/root/${impl.dispatch.task_name}`;
    const write = { agent_id: implChild, tool_name: 'Write', tool_input: { file_path: path.join(worktree, 'allowed.txt'), content: 'fixture' } };
    assert.equal((await guard(write)).code, 0, 'implementer can write the linked tree');
    fs.writeFileSync(path.join(worktree, 'dirty.txt'), 'implementation in progress');
    assert.equal((await guard(write)).code, 0, 'implementation dirty tree remains executable');
    assert.equal((await guard({ agent_id: implChild, tool_name: 'Bash', tool_input: { command: 'git push origin HEAD' } })).code, 2);
    console.log('PASS generic hook: ordinary children allowed; managed corrupt/terminal evidence and common protections retained; 2 classification mutations verified');
  }
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
