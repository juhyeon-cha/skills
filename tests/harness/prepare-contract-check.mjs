import assert from 'node:assert/strict';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawn, spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {inspectWorkspace} from '../../plugins/harness/lib/workspace.mjs';
import {preparationPaths, runPreparation} from '../../plugins/harness/lib/preparation.mjs';
import {validateConfig} from '../../plugins/harness/lib/config.mjs';

assert.notEqual(process.platform, 'win32', 'UNREACHED: this suite proves POSIX groups only');
const temp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'prepare-contract-')));
const repo = path.join(temp, 'repo'), wt = path.join(temp, '공백 workspace');
const plugin = path.join(temp, 'plugin'); fs.cpSync(fileURLToPath(new URL('../../plugins/harness', import.meta.url)), plugin, {recursive: true});
const cli = path.join(plugin, 'scripts/workspace.mjs');
const env = {...process.env, GIT_CONFIG_GLOBAL: os.devNull, GIT_CONFIG_NOSYSTEM: '1', GIT_ALLOW_PROTOCOL: 'file', HARNESS_ROOT: repo};
for (const key of Object.keys(env)) if (key.startsWith('GIT_') && !['GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM', 'GIT_ALLOW_PROTOCOL'].includes(key)) delete env[key];
let count = 0;
const check = (value, message) => { assert.ok(value, message); count++; console.log(`PASS ${message}`); };
const git = (...args) => { const r = spawnSync('git', ['-C', repo, ...args], {env, encoding: 'utf8'}); assert.equal(r.status, 0, r.stderr); };
const start = (action = 'prepare', runtime = 'codex') => {
  const child = spawn(process.execPath, [cli, action, wt], {cwd: repo, env: {...env, HARNESS_RUNTIME: runtime}, stdio: ['ignore', 'pipe', 'pipe']});
  let stdout = '', stderr = ''; child.stdout.on('data', d => stdout += d); child.stderr.on('data', d => stderr += d);
  return {child, done: new Promise(resolve => child.on('close', (code, signal) => resolve({code, signal, stdout, stderr})))};
};
const run = async action => start(action).done;
const until = async predicate => { const deadline = Date.now() + 10000; while (!predicate()) { if (Date.now() > deadline) throw new Error('fixture wait UNREACHED'); await new Promise(r => setTimeout(r, 20)); } };
let state;
try {
  fs.mkdirSync(repo); git('init', '-q'); git('-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--allow-empty', '-qm', 'seed');
  git('worktree', 'add', '-qb', 'worktree-fixture', wt);
  fs.writeFileSync(path.join(repo, '.harness.json'), JSON.stringify({ledger: {backend: 'github'}}));
  fs.writeFileSync(path.join(plugin, 'scripts/ledger.sh'), '#!/usr/bin/env bash\n[ "$1" = wire-worktree ] || exit 97\nprintf "fixture wiring\\n"\n');
  state = preparationPaths(await inspectWorkspace(wt, {env}));
  const snapshotConfig = {ledger: {backend: 'github'}, bootstrap: {argv: [process.execPath, '-e', "require('node:fs').writeFileSync('executed', process.argv[1])", 'old']}};
  fs.writeFileSync(path.join(wt, '.harness.json'), JSON.stringify(snapshotConfig));
  const race = spawnSync(process.execPath, [fileURLToPath(new URL('./prepare-snapshot-fixture.mjs', import.meta.url)), plugin, wt], {cwd: repo, env, detached: true, encoding: 'utf8'});
  assert.equal(race.status, 0, race.stderr);
  const observation = JSON.parse(race.stdout); console.log('snapshot interleave: ' + race.stdout.trim());
  check(observation.injected && observation.executed === 'old' && !observation.ready && !observation.canDelegate && observation.error?.includes('PREPARE_INPUT_CHANGED'), 'old command cannot receive readiness for replacement config');
  check((await run()).code === 0 && fs.readFileSync(path.join(wt, 'executed'), 'utf8') === 'new' && (await run('ready')).code === 0, 'retry executes replacement command before granting readiness');
  const commandFile = path.join(wt, 'bootstrap.mjs'), modeFile = path.join(wt, 'input.txt'), attempts = path.join(wt, 'attempts'), pidFile = path.join(wt, 'child.pid');
  fs.writeFileSync(commandFile, `import fs from 'node:fs';\nfs.appendFileSync('attempts', 'attempt\\n'); fs.writeFileSync('child.pid', String(process.pid));\nconst mode=fs.readFileSync('input.txt','utf8');\nif(mode==='fail') { await new Promise(r=>setTimeout(r,300)); process.exit(9); }\nif(mode==='crash') process.kill(process.pid,'SIGKILL');\nawait new Promise(r=>setTimeout(r, mode==='hold'?5000:300)); console.log('fixture prepared');\n`);
  let config = {ledger: {backend: 'github'}, bootstrap: {argv: [process.execPath, commandFile]}, preparation: {inputs: ['input.txt', 'bootstrap.mjs'], timeout_ms: 2000}};
  const save = () => fs.writeFileSync(path.join(wt, '.harness.json'), JSON.stringify(config));
  const mode = value => { fs.writeFileSync(modeFile, value); fs.rmSync(pidFile, {force: true}); };
  const n = () => fs.existsSync(attempts) ? fs.readFileSync(attempts, 'utf8').trim().split('\n').length : 0;
  save(); mode('fail');
  check((await run()).code !== 0 && !fs.existsSync(state.ready) && fs.existsSync(wt), 'failure leaves workspace and no ready');
  check((await run('ready')).code !== 0, 'failure blocks delegation');
  const failedBefore = n(), failedPair = await Promise.all([start('prepare', 'claude').done, start('prepare', 'codex').done]);
  check(failedPair.every(r => r.code !== 0) && n() === failedBefore + 1, 'concurrent failure is shared without implicit duplicate execution');
  mode('ok'); check((await run()).code === 0 && (await run('ready')).code === 0, 'retry yields verified readiness');
  const before = n(); check((await run()).code === 0 && n() === before, 'unchanged command and inputs reuse receipt');
  mode('new input'); const a = start('prepare', 'claude'), b = start('prepare', 'codex');
  const pair = await Promise.all([a.done, b.done]);
  if (!pair.every(r => r.code === 0)) console.log(JSON.stringify(pair.map(({code, signal, stderr}) => ({code, signal, stderr}))));
  check(pair.every(r => r.code === 0) && n() === before + 1, 'two runtime processes share one execution');
  mode('duplicate hook'); const hookBefore = n();
  const hooks = [1, 2].map(() => {
    const child = spawn('bash', [path.join(plugin, 'hooks/enter-worktree.sh')], {cwd: repo, env: {...env, CLAUDE_PLUGIN_ROOT: plugin}, stdio: ['pipe', 'ignore', 'pipe']});
    child.stderr.resume(); child.stdin.end(JSON.stringify({cwd: wt}));
    return new Promise(resolve => child.on('close', code => resolve(code)));
  });
  check((await Promise.all(hooks)).every(code => code === 0) && n() === hookBefore + 1, 'duplicate hook wrappers share the same preparation lock');
  config.bootstrap.argv.push('new-argument'); save(); check((await run('ready')).code !== 0 && (await run()).code === 0 && n() === before + 3, 'command fingerprint invalidates readiness');
  mode('hold'); config.preparation.timeout_ms = 100; save();
  const timed = await run(); check(timed.code !== 0 && !fs.existsSync(state.ready) && timed.stderr.includes('PREPARE_TIMEOUT'), 'timeout kills group without ready');
  mode('ok'); config.preparation.timeout_ms = 2000; save(); check((await run()).code === 0, 'retry recovers terminated timeout owner');
  mode('crash'); check((await run()).code !== 0 && !fs.existsSync(state.ready), 'bootstrap signal crash creates no ready');
  mode('ok'); check((await run()).code === 0, 'bootstrap crash retry works');
  mode('hold'); const crashing = start(); await until(() => fs.existsSync(pidFile));
  const owner = JSON.parse(fs.readFileSync(path.join(state.lock, 'owner.json')));
  process.kill(owner.pid, 'SIGKILL');
  config.preparation.timeout_ms = 50; save();
  const busy = await run(); check(busy.code !== 0 && busy.stderr.includes('no lock stolen') && !fs.existsSync(state.ready), 'dead worker with live child group cannot be stolen');
  process.kill(-owner.pid, 'SIGKILL'); await crashing.done;
  mode('ok'); config.preparation.timeout_ms = 2000; save(); check((await run()).code === 0, 'dead worker and terminated group allow retry');
  mode('before concurrent change'); const changing = start(); await until(() => fs.existsSync(pidFile));
  fs.writeFileSync(modeFile, 'changed while running');
  const changed = await changing.done;
  check(changed.code !== 0 && changed.stderr.includes('PREPARE_INPUT_CHANGED') && !fs.existsSync(state.ready) && (await run('ready')).code !== 0, 'input changed during successful command never grants old readiness');
  mode('ok'); const caller = start(); await until(() => fs.existsSync(pidFile)); caller.child.kill('SIGKILL'); await caller.done;
  await until(() => fs.existsSync(state.ready) && !fs.existsSync(state.lock));
  check((await run('ready')).code === 0, 'waiter termination does not abort independent successful worker');
  config.bootstrap = `${process.execPath} '${commandFile}'`; save(); mode('legacy string');
  check((await run()).code === 0, 'legacy bootstrap string retains Bash execution in workspace');
  config.bootstrap = {argv: ['fixture-executable-does-not-exist']}; save();
  check((await run()).code !== 0 && !fs.existsSync(state.ready), 'missing executable cannot establish readiness');
  config.bootstrap = {argv: [process.execPath, commandFile]}; save();
  fs.unlinkSync(modeFile); check((await run()).code !== 0, 'missing declared input fails before bootstrap');
  mode('restored'); check((await run()).code === 0, 'restored executable and input permit retry');
  fs.mkdirSync(state.lock); fs.writeFileSync(path.join(state.lock, 'owner.json'), '{');
  check((await run()).code !== 0 && (await run('ready')).code !== 0, 'malformed lock cannot be stolen or treated as ready');
  fs.rmSync(state.lock, {recursive: true});
  fs.mkdirSync(path.join(wt, '.claude'), {recursive: true});
  fs.writeFileSync(path.join(wt, '.claude/settings.json'), JSON.stringify({hooks: {PostToolUse: [{matcher: 'EnterWorktree', hooks: []}]}}));
  const own = await run(); check(own.code !== 0 && own.stderr.includes('LEGACY_HOOK_UNVERIFIED'), 'own hook is diagnostic and cannot launch duplicate bootstrap');
  fs.writeFileSync(path.join(wt, '.claude/settings.json'), JSON.stringify({hooks: {PostToolUse: [{matcher: 'Write|EnterWorktree', hooks: []}]}}));
  check((await run()).code !== 0, 'regex repository hook cannot bypass legacy diagnostics');
  delete config.bootstrap; save(); check((await run()).code !== 0, 'own hook cannot use no-command exemption');
  fs.unlinkSync(path.join(wt, '.claude/settings.json'));
  const none = await run(); check(none.code === 0 && JSON.parse(none.stdout).canDelegate && !JSON.parse(none.stdout).ready, 'no preparation command is legitimate no-op without fabricated ready');
  for (const preparation of [{timeout_ms: 0}, {inputs: ['../secret']}, {inputs: ['C:\\secret']}, {inputs: 'wrong'}, {unknown: true}]) {
    assert.throws(() => validateConfig({...config, preparation})); count++;
  }
  config.bootstrap = {argv: [process.execPath, commandFile]}; save(); mode('legacy');
  fs.mkdirSync(path.join(repo, '.claude/worktrees'), {recursive: true}); fs.writeFileSync(path.join(repo, '.claude/worktrees/.bootstrapped-fixture'), '');
  check((await run('ready')).code !== 0 && (await run()).code === 0, 'legacy marker never substitutes for verified execution');
  // Interleave at the filesystem boundary: a contender observed dead owner A,
  // but encounters replacement B when it gets the exclusive recovery claim.
  const exited = spawnSync(process.execPath, ['-e', ''], {detached: true});
  config.preparation.timeout_ms = 1; save(); fs.mkdirSync(state.lock);
  fs.writeFileSync(path.join(state.lock, 'owner.json'), JSON.stringify({pid: exited.pid, token: 'old'}));
  const mkdir = fsp.mkdir; let injected = false;
  fsp.mkdir = async function(location, ...args) {
    const result = await mkdir.call(this, location, ...args);
    if (location === path.join(state.lock, 'recovery') && !injected) {
      injected = true; fs.writeFileSync(path.join(state.lock, 'owner.json'), JSON.stringify({pid: process.pid, token: 'replacement'}));
    }
    return result;
  };
  try { await assert.rejects(runPreparation(await inspectWorkspace(wt, {env}), {env}), /no lock stolen/); }
  finally { fsp.mkdir = mkdir; }
  check(injected && JSON.parse(fs.readFileSync(path.join(state.lock, 'owner.json'))).token === 'replacement', 'stale observation cannot delete replacement lock owner');
  fs.rmSync(state.lock, {recursive: true});
  config.preparation.timeout_ms = 2000; save(); check((await run()).code === 0, 'recovery fixture cleanup leaves preparation reusable');
  const restoredFiles = ['.harness.json', 'bootstrap.mjs', 'input.txt'].map(name => [name, fs.readFileSync(path.join(wt, name))]);
  const oldState = state.root; git('worktree', 'remove', '--force', wt); git('worktree', 'add', wt, 'worktree-fixture');
  for (const [name, data] of restoredFiles) fs.writeFileSync(path.join(wt, name), data);
  check(!fs.existsSync(oldState) && (await run('ready')).code !== 0, 'same path/branch/config recreation cannot reuse removed preparation state');
  console.log(`PASS total ${count}; POSIX fixture processes, not live Claude/Codex hook firing`);
} finally {
  if (state && fs.existsSync(path.join(state.lock, 'owner.json'))) { try { process.kill(-JSON.parse(fs.readFileSync(path.join(state.lock, 'owner.json'))).pid, 'SIGKILL'); } catch {} }
  fs.rmSync(temp, {recursive: true, force: true});
}
