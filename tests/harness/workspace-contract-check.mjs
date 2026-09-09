import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const self = fileURLToPath(import.meta.url);
if (process.argv[2] === '--adapter') {
  const [, , , operation, target] = process.argv;
  const root = process.env.HARNESS_ROOT;
  const backend = JSON.parse(fs.readFileSync(path.join(root, '.harness.json'))).ledger.backend;
  fs.appendFileSync(process.env.FIXTURE_CALLS, JSON.stringify({operation, target, root, backend}) + '\n');
  if (process.env.FIXTURE_ADAPTER_FAIL === '1') process.exit(23);
  if (operation === 'wire-worktree') {
    console.log(`fixture ${backend} wiring reached`);
  } else if (operation === 'show') {
    console.log(JSON.stringify([{id: target, labels: [`repo:${path.basename(root)}`]}]));
  } else {
    fs.appendFileSync(process.env.FIXTURE_SENTINEL, 'ledger mutation/unknown call\n');
    process.exit(97);
  }
  process.exit(0);
}

const source = fileURLToPath(new URL('../../plugins/harness', import.meta.url));
const fault = process.argv[2];
assert.ok(!fault || ['--missing-target', '--adapter-failure'].includes(fault), 'unknown argument');
const temp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'workspace-contract-')));
let reached = 0;
const check = (condition, message) => { assert.ok(condition, message); reached++; };
const run = (command, args, cwd, env, input) => {
  const result = spawnSync(command, args, {cwd, env, input, encoding: 'utf8', timeout: 30000});
  if (result.error) throw result.error;
  return result;
};
const ok = result => { assert.equal(result.status, 0, result.stderr || result.stdout); return result.stdout.trim(); };
try {
  const plugin = path.join(temp, 'plugin');
  fs.cpSync(source, plugin, {recursive: true});
  const calls = path.join(temp, 'calls.jsonl');
  const sentinel = path.join(temp, 'remote-writes');
  fs.writeFileSync(calls, ''); fs.writeFileSync(sentinel, '');
  const bin = path.join(temp, 'bin'); fs.mkdirSync(bin);
  const home = path.join(temp, 'home'); fs.mkdirSync(home);
  const env = {...process.env, HOME: home, PATH: `${bin}${path.delimiter}${process.env.PATH}`, CLAUDE_PLUGIN_ROOT: plugin, FIXTURE_CALLS: calls, FIXTURE_SENTINEL: sentinel, FIXTURE_RUNNER: self, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: os.devNull, GIT_ALLOW_PROTOCOL: 'file', GIT_TERMINAL_PROMPT: '0'};
  env.FIXTURE_REAL_GIT = process.env.FIXTURE_REAL_GIT || ok(run('which', ['git'], temp, process.env));
  for (const key of Object.keys(env)) if (key.startsWith('GIT_') && !['GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL', 'GIT_ALLOW_PROTOCOL', 'GIT_TERMINAL_PROMPT'].includes(key)) delete env[key];
  delete env.HARNESS_ROOT;
  env.HARNESS_GUARD_LOG = path.join(temp, 'guard.tsv');
  env.HARNESS_SESSION_ACTOR_LOG = path.join(temp, 'actors.tsv');
  for (const command of ['gh', 'bd', 'curl', 'wget', 'ssh']) {
    fs.writeFileSync(path.join(bin, command), '#!/bin/sh\nprintf "remote command\\n" >> "$FIXTURE_SENTINEL"\nexit 97\n', {mode: 0o755});
  }
  fs.writeFileSync(path.join(bin, 'git'), '#!/bin/sh\nfor arg do\n  case "$arg" in push|send-pack) printf "git remote write\\n" >> "$FIXTURE_SENTINEL"; exit 97 ;; esac\ndone\nexec "$FIXTURE_REAL_GIT" "$@"\n', {mode: 0o755});
  check(run('gh', ['api'], temp, env).status === 97, 'remote sentinel reached');
  check(run('git', ['push'], temp, env).status === 97, 'git write sentinel reached');
  check(fs.readFileSync(sentinel, 'utf8').trim().split('\n').length === 2, 'sentinel negative controls counted');
  fs.writeFileSync(sentinel, ''); // Only deliberate sentinel controls are excluded below.
  // Replace only the adapter boundary in a temporary copy, never policy code.
  fs.writeFileSync(path.join(plugin, 'scripts/ledger.sh'), '#!/usr/bin/env bash\nexec node "$FIXTURE_RUNNER" --adapter "$@"\n');
  const targets = ['hooks/enter-worktree.sh', 'scripts/workspace-cleanup.sh', 'hooks/guard.sh'];
  if (fault === '--missing-target') fs.unlinkSync(path.join(plugin, targets[0]));
  for (const target of targets) {
    check(fs.existsSync(path.join(plugin, target)), `missing target ${target}`);
    check(fs.readFileSync(path.join(plugin, target)).equals(fs.readFileSync(path.join(source, target))), `source mismatch ${target}`);
  }
  ok(run('jq', ['--version'], temp, env));
  const git = (cwd, ...args) => run('git', ['-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', ...args], cwd, env);
  for (const backend of ['github', 'beads', 'notion']) {
    const startCount = reached;
    const base = path.join(temp, backend); fs.mkdirSync(base);
    const seed = path.join(base, 'seed'); fs.mkdirSync(seed); ok(git(seed, 'init', '-q'));
    fs.writeFileSync(path.join(seed, '.harness.json'), JSON.stringify({ledger: {backend}, bootstrap: 'mkdir -p node_modules; echo attempt >> node_modules/attempts; test -f node_modules/ready'}));
    fs.writeFileSync(path.join(seed, '.gitignore'), 'node_modules/\n');
    fs.writeFileSync(path.join(seed, 'README.md'), 'needle\n');
    ok(git(seed, 'add', '.')); ok(git(seed, 'commit', '-qm', 'fixture seed'));
    const origin = path.join(base, 'origin.git'); ok(git(base, 'clone', '-q', '--bare', seed, origin));
    const repo = path.join(base, 'fixture'); ok(git(base, 'clone', '-q', origin, repo));
    check(ok(git(repo, 'remote', 'get-url', 'origin')) === origin && origin.startsWith(temp + path.sep), 'origin stays inside fixture');
    const wt = path.join(repo, '.claude/worktrees/story-1');
    ok(git(repo, 'worktree', 'add', '-q', '-b', 'worktree-story-1', wt));
    const fixtureEnv = {...env, HARNESS_ROOT: repo, FIXTURE_ADAPTER_FAIL: fault === '--adapter-failure' ? '1' : '0'};
    const hook = overrides => run('bash', [path.join(plugin, targets[0])], repo, {...fixtureEnv, ...overrides}, JSON.stringify({session_id: 'fixture', tool_name: 'EnterWorktree', cwd: wt}));
    const cleanup = (...args) => run('bash', [path.join(plugin, targets[1]), 'story-1', ...args], repo, fixtureEnv);
    const marker = path.join(repo, '.claude/worktrees/.bootstrapped-story-1');
    let result = hook();
    check(result.status === 2 && result.stderr.includes('부트스트랩 실패'), 'bootstrap failure reached');
    check(fs.existsSync(wt) && !fs.existsSync(marker), 'failure preserves workspace without marker');
    fs.writeFileSync(path.join(wt, 'node_modules/ready'), '');
    check(hook().status === 0 && fs.existsSync(marker), 'retry prepares workspace');
    check(hook().status === 0 && fs.readFileSync(path.join(wt, 'node_modules/attempts'), 'utf8').trim().split('\n').length === 2, 'successful preparation is not repeated');
    fs.unlinkSync(marker); fs.mkdirSync(path.join(wt, '.claude'), {recursive: true});
    fs.writeFileSync(path.join(wt, '.claude/settings.json'), JSON.stringify({hooks: {PostToolUse: [{matcher: 'EnterWorktree', hooks: []}]}}));
    result = hook();
    check(result.status === 0 && result.stderr.includes('EnterWorktree 훅이 소유한다') && !fs.existsSync(marker), 'own-hook baseline skips preparation even with empty handlers');
    check(fs.readFileSync(path.join(wt, 'node_modules/attempts'), 'utf8').trim().split('\n').length === 2, 'own-hook did not execute bootstrap');
    fs.unlinkSync(path.join(wt, '.claude/settings.json'));
    result = hook({FIXTURE_ADAPTER_FAIL: '1'});
    check(result.status === 2 && result.stderr.includes('어댑터'), 'adapter failure is not success');
    result = run('bash', [path.join(plugin, targets[1]), 'story-1'], repo, {...fixtureEnv, FIXTURE_ADAPTER_FAIL: '1'});
    check(result.status === 1 && result.stderr.includes('ledger.sh show 실패') && fs.existsSync(wt), 'cleanup adapter failure preserves workspace');
    result = run('bash', [path.join(plugin, targets[1]), 'story-1'], base, fixtureEnv);
    check(result.status === 1 && result.stderr.includes('대상 레포를 찾지 못했다') && fs.existsSync(wt), 'cleanup without target repository fails');
    fs.writeFileSync(path.join(wt, 'dirty.txt'), 'dirty');
    result = cleanup('--force');
    check(result.status === 1 && result.stderr.includes('미커밋 변경이 있다') && fs.existsSync(wt), 'dirty cleanup rejected even with force');
    ok(git(wt, 'add', 'dirty.txt')); ok(git(wt, 'commit', '-qm', 'unpushed fixture'));
    result = cleanup();
    check(result.status === 1 && result.stderr.includes('미푸시 커밋이 있다') && fs.existsSync(wt), 'unpushed cleanup rejected');
    // Direct-input policy regressions, not native hook-firing evidence.
    const guard = (tool_name, tool_input) => run('bash', [path.join(plugin, targets[2])], repo, fixtureEnv, JSON.stringify({session_id: 'fixture', cwd: wt, tool_name, tool_input}));
    result = guard('Bash', {command: `grep needle '${repo}/README.md'`});
    check(result.status === 0, `ordinary search allowed: ${result.stderr}`);
    check(guard('Write', {file_path: path.join(repo, 'README.md')}).status === 2, 'main checkout file write blocked');
    check(guard('Bash', {command: `rg needle '${repo}/README.md'`}).status === 0, 'read-only search allowed');
    check(guard('apply_patch', {command: `*** Begin Patch\n*** Update File: ${repo}/README.md\n@@\n-needle\n+edited\n*** End Patch`}).status === 2, 'apply_patch main checkout write blocked');
    // Local origin is read by fetch; the fixture never pushes, including cleanup.
    result = cleanup('--force');
    check(result.status === 0 && !fs.existsSync(wt), 'explicit forced cleanup positive control');
    const adapterCalls = fs.readFileSync(calls, 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse).filter(call => call.backend === backend);
    check(adapterCalls.some(call => call.operation === 'wire-worktree') && adapterCalls.some(call => call.operation === 'show'), 'both adapter boundaries reached');
    check(adapterCalls.every(call => call.root === repo), 'adapter root is isolated');
    console.log(`PASS ${backend}: reached=${reached - startCount}; direct-script fixture`);
  }
  check(fs.readFileSync(sentinel, 'utf8') === '', 'remote/ledger write sentinel must be zero');
  console.log(`PASS total: reached=${reached}; actual remote/ledger write sentinel=0; hook firing not tested`);
  if (!fault) {
    for (const control of ['--missing-target', '--adapter-failure']) {
      const result = run(process.execPath, [self, control], temp, env);
      check(result.status !== 0 && result.stderr.includes(control === '--missing-target' ? 'missing target' : 'bootstrap failure reached'), `negative control ${control}`);
      console.log(`PASS negative control ${control}: rc=${result.status}`);
    }
  }
} finally { fs.rmSync(temp, {recursive: true, force: true}); }
