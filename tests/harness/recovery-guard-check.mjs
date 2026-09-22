import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {normalizeHookEvent} from '../../plugins/harness/lib/guard/hook-event.mjs';
import {evaluateGuard} from '../../plugins/harness/lib/guard/guard.mjs';

const root = fileURLToPath(new URL('../../plugins/harness/', import.meta.url));
const temp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'recovery-guard-')));
const main = path.join(temp, 'repo'), work = path.join(temp, 'work');
const env = {...process.env, HARNESS_RUNTIME: 'codex', HARNESS_DATA_DIR: path.join(temp, 'data'),
  GIT_CONFIG_GLOBAL: os.devNull, GIT_CONFIG_NOSYSTEM: '1'};
for (const key of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'HARNESS_ROOT', 'RIPGREP_CONFIG_PATH']) delete env[key];
const git = (...args) => {
  const r = spawnSync('git', args, {env, encoding: 'utf8'});
  assert.equal(r.status, 0, r.stderr);
};
fs.mkdirSync(main);
fs.writeFileSync(path.join(main, '.harness.json'), JSON.stringify({ledger: {backend: 'beads'}}));
git('init', '-q', main); git('-C', main, 'add', '.');
git('-C', main, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture');
git('-C', main, 'worktree', 'add', '-qb', 'fixture', work);
fs.symlinkSync(main, path.join(work, 'main-link'));
const event = (tool_name, tool_input, extra = {}) => ({cwd: work, session_id: 'fixture', tool_name, tool_input, ...extra});
let checks = 0;
async function check(e, code, reason) {
  const result = await evaluateGuard(e, {env, pluginRoot: root});
  assert.equal(result.code, code, JSON.stringify({e, result}));
  if (reason) assert.equal(result.diagnostic.reasonCode, reason);
  checks++;
  return result;
}
const question = {questions: [{title: 'Continue?', options: ['Wait', 'Resume']}]};
const accepted = [
  ['request_user_input_async', question], ['functions.request_user_input_async', question],
  ['clock.sleep', {duration_ms: 1}], ['clocksleep', {duration_ms: 100}],
  ['mcp__codex_app__read_thread', {threadId: 'fixture'}],
  ['mcp__codex_app__list_projects', {}],
  ['mcp__cua_repl__js', {code: 'await cua.getState();'}],
];
for (const [tool, input] of accepted) {
  await check(event(tool, input), 0);
  await check(event(tool, input, {agent_id: '/root/unidentified', agent_type: 'default'}), 0);
}
// The host owns schemas and opaque tool permissions, including future fields.
for (const [tool, input] of [
  ['unknown_read_tool', {file_path: main + '/input'}],
  ['clocksleep', {duration_ms: -1}],
  ['request_user_input_async', {questions: [{title: ''}]}],
  ['mcp__codex_app__list_projects', {futureOption: true}],
  ['mcp__codex_app__read_thread', {threadId: 'fixture', futureOption: true}],
]) {
  await check(event(tool, input), 0);
  await check(event(tool, input, {agent_id: '/root/unidentified', agent_type: 'default'}), 0);
}
for (const code of ['await cua.getState(); await cua.getApp("A");', 'await cua.click(1);', 'await cua["getState"]();'])
  assert.equal((await check(event('mcp__cua_repl__js', {code}), 0)).diagnostic.reasonCode, 'ALLOWED');
const create = {prompt: 'Independent evaluation', target: {type: 'projectless'}};
await check(event('mcp__codex_app__create_thread', create), 0);
await check(event('mcp__codex_app__create_thread', create, {agent_id: '/root/reviewer', agent_type: 'harness:reviewer'}), 2, 'POLICY_DENIED');
await check(event('mcp__codex_app__create_thread', {...create, target: {type: 'project', projectId: 'p'}}), 0);
const bash = command => event('exec_command', {cmd: command});
const allowed = [
  `cat '${main}/.harness.json' > '${work}/report.json'`,
  `cat '${main}/.harness.json' | head -1 >> '${work}/report.json'`,
  `printf '%s' '${main}/.codex/config.toml' > '${work}/report.txt'`,
  `echo '${main}/.codex/config.toml'`,
  `echo '\`touch ${main}/never\`' > '${work}/literal.txt'`,
];
for (const command of allowed) await check(bash(command), 0);
const denied = [
  `cat '${work}/input' > '${main}/output'`, `echo x >> '${main}/.harness.json'`,
  `echo x > '${work}/main-link/output'`,
  `cat '${main}/.harness.json'; touch '${main}/output'`,
  `echo \`touch ${main}/output\``, `echo "\`touch ${main}/output\`"`,
  `echo $(touch ${main}/output)`, `echo "$(touch ${main}/output)"`,
  `git diff --output='${main}/output'`,
];
for (const command of denied) await check(bash(command), 2);
git('-C', main, 'diff', '--output=relative.patch');
assert.equal(fs.existsSync(path.join(main, 'relative.patch')), true, 'Git output follows -C');
await check(bash(`git -C '${main}' diff --output=relative.patch`), 2);
await check(bash(`git -C '${main}' diff -C --output=relative.patch`), 2);
await check(bash(`git -C '${main}' diff -C50 --output=relative.patch`), 2);
await check(bash(`git -C '${work}' -C ../repo diff --output=relative.patch`), 2);
await check(bash(`git -C '${main}' -C ../work diff --output=relative.patch`), 0);
for (const command of [
  `env sh -c 'touch ${main}/output'`,
  `rg --pre=touch x '${main}/input' > '${work}/out'`,
  `node '${work}/.claude/preflight.mjs' --root '${main}'`,
]) await check(bash(command), 0); // Opaque effects remain under host permissions.

// Provider/runtime instructions are not executed: these are policy input fixtures.
assert.equal(fs.existsSync(path.join(main, 'output')), false);
const log = fs.readFileSync(path.join(env.HARNESS_DATA_DIR, 'v1/codex/repos',
  fs.readdirSync(path.join(env.HARNESS_DATA_DIR, 'v1/codex/repos'))[0], 'guard.tsv.diagnostics.jsonl'), 'utf8');
assert.ok(log.includes('host-managed'));
for (const secret of [main, work, 'Continue?', 'Independent evaluation', 'touch']) assert.ok(!log.includes(secret));
checks++;
// Removing each fix must break the corresponding expectation. Copies only.
for (const [label, relative, from, to, input, expected] of [
  ['effects', 'lib/guard/shell-effects.mjs', 'export function literalReadEffects(command, cwd, env = process.env) {',
    'export function literalReadEffects(command, cwd, env = process.env) { return null;', {...bash(allowed[3]), agent_id: '/root/unidentified', agent_type: 'default'}, 0],
  ['substitution', 'lib/guard/operations.mjs', 'nested.push(...shellWriteOperations(command.slice(start, end), cwd));', '', bash(denied[4]), 2],
  ['task-rule', 'lib/guard/guard.mjs', "RULES.push({matcher: '*', run: r_task_create});", '',
    event('mcp__codex_app__create_thread', create, {agent_id: '/root/reviewer', agent_type: 'harness:reviewer'}), 2],
]) {
  const copy = path.join(temp, label); fs.cpSync(root, copy, {recursive: true});
  const file = path.join(copy, relative), original = fs.readFileSync(file, 'utf8');
  assert.ok(original.includes(from)); fs.writeFileSync(file, original.replace(from, to));
  const mutant = await import(pathToFileURL(path.join(copy, 'lib/guard/guard.mjs')));
  if (label === 'effects') {
    // Read classification remains useful even though identity no longer gates execution.
    assert.equal(normalizeHookEvent(input, {env}).harness_effect_readonly, true);
    const changed = await import(pathToFileURL(path.join(copy, 'lib/guard/hook-event.mjs')));
    assert.notEqual(changed.normalizeHookEvent(input, {env}).harness_effect_readonly, true);
  } else {
    assert.equal((await evaluateGuard(input, {env, pluginRoot: root})).code, expected);
    const result = await mutant.evaluateGuard(input, {env, pluginRoot: copy});
    assert.notEqual(result.code, expected, `${label}: removing fix must fail regression`);
  }
  checks++;
}
console.log(`PASS recovery guard: ${checks} assertions, 3 killed mutations; candidate commands not executed`);
