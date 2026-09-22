import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
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
  assert.equal((await ordinaryGuard({agent_type: 'unknown'})).code, 0);
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
    assert.equal((await ordinaryGuard({}, reply)).code, 0, 'managed names do not require inventory for ordinary tools');
  }
  // The default guard must not consult metadata, even when the runtime is offline.
  let metadataReads = 0;
  assert.equal((await evaluateGuard(ordinary, {pluginRoot: plugin, env,
    readThread: async () => { metadataReads++; throw Error('offline'); }})).code, 0);
  assert.equal(metadataReads, 0);
  // A restored metadata gate must be detected by the ordinary-child control.
  const copy = path.join(temp, 'metadata-gate-mutant');
  fs.cpSync(plugin, copy, {recursive: true});
  const source = path.join(copy, 'lib/guard/guard.mjs');
  const original = fs.readFileSync(source, 'utf8');
  const anchor = 'event = normalizeHookEvent(raw, { env });';
  assert.ok(original.includes(anchor));
  fs.writeFileSync(source, original.replace(anchor, "throw new Error('restored metadata gate');"));
  const mutant = await import(pathToFileURL(source));
  assert.equal((await mutant.evaluateGuard(ordinary, {pluginRoot: copy, env})).code, 2);
  const event = { tool_name: 'Bash', cwd: repo, session_id: 'generic-session', agent_id: '/root/ordinary', tool_input: { command: 'node --version' } };
  const guard = (changes = {}) => evaluateGuard({...event, ...changes}, {pluginRoot: plugin, env});
    const hook = spawnSync(process.execPath, [path.join(plugin, 'hooks/guard.mjs')], { env: { ...env, CLAUDE_PLUGIN_ROOT: plugin }, input: JSON.stringify(event), encoding: 'utf8' });
    assert.equal(hook.status, 0, hook.stderr);
    const doctor = path.join(temp, 'doctor'); fs.mkdirSync(doctor);
    for (const challenge of ['{broken', JSON.stringify({expires: 0})]) {
      fs.writeFileSync(path.join(doctor, 'challenge.json'), challenge);
      for (const [tool_input, expected] of [[{command: 'node --version'}, 0], [{command: 'git push origin HEAD'}, 2]]) {
        const observed = spawnSync(process.execPath, [path.join(plugin, 'scripts/hook.mjs'), 'guard', '--runtime', 'codex'], {
          env: {...env, CLAUDE_PLUGIN_ROOT: plugin, HARNESS_DOCTOR_DIR: doctor},
          input: JSON.stringify({...event, hook_event_name: 'PreToolUse', tool_input}), encoding: 'utf8',
        });
        assert.equal(observed.status, expected, observed.stderr);
        assert.match(observed.stderr, /diagnostic|doctor/i);
        if (expected === 2) assert.match(observed.stderr, /remote|push/i);
      }
    }

  assert.equal(normalizeHookEvent({...event, harness_policy_role: 'harness:reviewer'}).harness_policy_role, '');
  const scope = await resolveState({cwd: repo, sessionId: event.session_id}, env);
  const directory = path.join(scope.session, 'delegation');
  fs.mkdirSync(directory, {recursive: true});
  const legacy = path.join(directory, 'legacy.call.json');
  fs.writeFileSync(legacy, '{broken');
  assert.equal((await guard()).code, 0);
  assert.equal(fs.readFileSync(legacy, 'utf8'), '{broken');
  const oldScope = path.join(temp, 'old-scope.json');
  fs.writeFileSync(oldScope, JSON.stringify({runtime: 'codex', provider: 'collaboration', repository: repo,
    sessionId: event.session_id, data: env.HARNESS_DATA_DIR}));
  const removedDoctor = spawnSync(process.execPath, [path.join(plugin, 'scripts/doctor.mjs'), 'delegation', oldScope], {env, encoding: 'utf8'});
  assert.equal(removedDoctor.status, 1);
  assert.equal(JSON.parse(removedDoctor.stdout).status, 'UNREACHED');
  const oldAudit = spawnSync(process.execPath, [path.join(plugin, 'scripts/transcript.mjs'), '--scope', oldScope], {env, encoding: 'utf8'});
  assert.notEqual(oldAudit.status, 0);
  assert.match(oldAudit.stdout + oldAudit.stderr, /provider adapter unsupported/);
  assert.equal(fs.readFileSync(legacy, 'utf8'), '{broken');

  for (const changes of [
    {tool_name: 'Write', tool_input: {file_path: path.join(worktree, 'ordinary.txt'), content: 'allowed'}},
    {cwd: worktree, tool_input: {command: 'git commit -m fixture'}},
  ]) {
    assert.equal((await guard(changes)).code, 0);
    assert.equal((await guard({...changes, agent_type: 'harness-reviewer'})).code, 2);
  }
  console.log('PASS ordinary children: direct tools allowed, legacy records ignored and preserved, common/native protections retained, restored gate mutation detected');
} finally {
  fs.rmSync(temp, {recursive: true, force: true});
}
