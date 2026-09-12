// Offline release transaction contracts: disposable Git repositories and local bare origins only.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {projections, inspectDistribution} from '../plugins/harness/lib/distribution.mjs';

const source = fileURLToPath(new URL('../', import.meta.url));
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'release-artifact-'));
const env = {...process.env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null'};
let assertions = 0;
const check = (value, message) => { assert.ok(value, message); assertions++; };
function run(cwd, command, args, expected = 0) {
  const result = spawnSync(command, args, {cwd, env, encoding: 'utf8'});
  assert.equal(result.status, expected, `${command} ${args.join(' ')}\n${result.stdout}\n${result.stderr}`);
  return result.stdout.trim();
}
function fixture(name, plugin = 'harness') {
  const base = path.join(temp, name), repo = path.join(base, 'repo'), remote = path.join(base, 'origin.git');
  fs.mkdirSync(repo, {recursive: true});
  fs.mkdirSync(path.join(repo, 'scripts'));
  fs.copyFileSync(path.join(source, 'scripts/release.sh'), path.join(repo, 'scripts/release.sh'));
  fs.mkdirSync(path.join(repo, '.claude-plugin'));
  fs.writeFileSync(path.join(repo, '.claude-plugin/marketplace.json'), '{}\n');
  fs.writeFileSync(path.join(repo, 'README.md'), 'fixture\n');
  const root = path.join(repo, 'plugins', plugin);
  fs.cpSync(path.join(source, 'plugins', plugin), root, {recursive: true});
  // A release test must remain pinned even after the source is released again.
  const manifest = path.join(root, '.claude-plugin/plugin.json');
  const metadata = JSON.parse(fs.readFileSync(manifest, 'utf8'));
  fs.writeFileSync(manifest, JSON.stringify({...metadata, version: '2.1.3'}, null, 2) + '\n');
  if (plugin === 'harness') for (const [relative, text] of Object.entries(projections(root))) fs.writeFileSync(path.join(root, relative), text);
  fs.writeFileSync(path.join(root, 'CHANGELOG.md'), '## 2.2.0 — 2026-09-10\n\nMINOR: fixture\n');
  fs.writeFileSync(path.join(repo, 'scripts/check.sh'), '#!/bin/bash\nexit 0\n');
  const bin = path.join(base, 'bin'); fs.mkdirSync(bin);
  fs.writeFileSync(path.join(bin, 'claude'), '#!/bin/bash\nexit 0\n', {mode: 0o755});
  run(repo, 'git', ['init', '-q', '-b', 'main']);
  run(repo, 'git', ['config', 'user.name', 'Release Fixture']);
  run(repo, 'git', ['config', 'user.email', 'fixture@example.invalid']);
  run(repo, 'git', ['init', '--bare', '-q', remote]);
  run(repo, 'git', ['remote', 'add', 'origin', remote]);
  run(repo, 'git', ['add', '.']); run(repo, 'git', ['commit', '-qm', 'baseline']);
  run(repo, 'git', ['push', '-q', 'origin', 'main']);
  const initial = run(repo, 'git', ['rev-parse', 'HEAD']);
  const files = ['.claude-plugin/plugin.json', ...plugin === 'harness' ? Object.keys(projections(root)) : []];
  const before = files.map(relative => fs.readFileSync(path.join(root, relative)));
  function release(commandPath = `${bin}${path.delimiter}${env.PATH}`) {
    return spawnSync('/bin/bash', ['scripts/release.sh', plugin, 'minor'], {cwd: repo, env: {...env, PATH: commandPath}, encoding: 'utf8'});
  }
  function unchanged(result) {
    check(result.status !== 0, `${name}: failure is nonzero`);
    for (let i = 0; i < files.length; i++) { assert.deepEqual(fs.readFileSync(path.join(root, files[i])), before[i], `${name}: restored ${files[i]}`); assertions++; }
    check(run(repo, 'git', ['rev-parse', 'HEAD']) === initial, `${name}: no commit`);
    check(run(repo, 'git', ['tag', '--list']) === '', `${name}: no tag`);
    check(run(repo, 'git', ['--git-dir', remote, 'rev-parse', 'main']) === initial, `${name}: origin unchanged`);
    check(run(repo, 'git', ['diff', '--cached', '--name-only']) === '', `${name}: index unchanged`);
  }
  return {repo, root, remote, bin, initial, release, unchanged};
}
try {
  for (const plugin of ['harness', 'toolkit']) {
    const f = fixture(`success-${plugin}`, plugin), result = f.release();
    check(result.status === 0, `${plugin}: release succeeds\n${result.stdout}\n${result.stderr}`);
    const tag = `${plugin}-v2.2.0`;
    check(JSON.parse(fs.readFileSync(path.join(f.root, '.claude-plugin/plugin.json'))).version === '2.2.0', `${plugin}: canonical version bumped`);
    if (plugin === 'harness') check(inspectDistribution(f.root).version === '2.2.0', 'generated metadata exactly follows canonical version');
    run(f.repo, 'git', ['merge-base', '--is-ancestor', tag, 'origin/main']); assertions++;
    check(run(f.repo, 'git', ['--git-dir', f.remote, 'rev-parse', tag]) === run(f.repo, 'git', ['--git-dir', f.remote, 'rev-parse', 'main']), `${plugin}: origin tag and branch name same release commit`);
  }
  for (const phase of ['generate', 'check', 'validate', 'gate']) {
    const f = fixture(`failure-${phase}`);
    if (phase === 'generate') {
      // Deliberately corrupt several projections before failing: restoration must include all of them.
      fs.writeFileSync(path.join(f.root, 'scripts/distribution.mjs'), `import fs from 'node:fs'; import {projections} from '../lib/distribution.mjs';\nfor (const relative of Object.keys(projections())) fs.writeFileSync(new URL('../' + relative, import.meta.url), 'partial generation');\nprocess.exitCode = 1;\n`);
    } else if (phase === 'check') {
      fs.appendFileSync(path.join(f.root, 'scripts/distribution.mjs'), '\nif (process.argv[2] === "check") process.exitCode = 1;\n');
    } else if (phase === 'validate') fs.writeFileSync(path.join(f.bin, 'claude'), '#!/bin/bash\nexit 9\n');
    else fs.writeFileSync(path.join(f.repo, 'scripts/check.sh'), '#!/bin/bash\nexit 7\n');
    f.unchanged(f.release());
  }
  const drift = fixture('current-drift');
  fs.appendFileSync(path.join(drift.root, 'hooks/codex.json'), ' ');
  const bytes = fs.readFileSync(path.join(drift.root, 'hooks/codex.json'));
  check(drift.release().status !== 0, 'existing generated drift refuses release');
  assert.deepEqual(fs.readFileSync(path.join(drift.root, 'hooks/codex.json')), bytes); assertions++;
  check(run(drift.repo, 'git', ['rev-parse', 'HEAD']) === drift.initial, 'drift preflight makes no commit');
  const branch = fixture('wrong-branch');
  run(branch.repo, 'git', ['switch', '-qc', 'feature']); branch.unchanged(branch.release());
  const linked = fixture('linked-release');
  const worktree = path.join(path.dirname(linked.repo), 'worktree');
  run(linked.repo, 'git', ['worktree', 'add', '-qb', 'codex/release', worktree]);
  const linkedResult = spawnSync('/bin/bash', ['scripts/release.sh', 'harness', 'minor'], {
    cwd: worktree, env: {...env, PATH: `${linked.bin}${path.delimiter}${env.PATH}`}, encoding: 'utf8',
  });
  check(linkedResult.status === 0, `linked release succeeds: ${linkedResult.stderr}`);
  check(run(linked.repo, 'git', ['rev-parse', 'HEAD']) === linked.initial, 'main checkout HEAD unchanged');
  check(JSON.parse(fs.readFileSync(path.join(linked.root, '.claude-plugin/plugin.json'))).version === '2.1.3', 'main checkout files unchanged');
  check(run(linked.repo, 'git', ['--git-dir', linked.remote, 'rev-parse', 'main']) === run(worktree, 'git', ['rev-parse', 'HEAD']), 'linked release pushes HEAD to default branch');
  const noNode = fixture('missing-node');
  for (const command of ['dirname', 'git', 'sed', 'jq']) {
    const executable = run(source, '/bin/bash', ['-c', 'command -v "$1"', '--', command]);
    fs.symlinkSync(executable, path.join(noNode.bin, command));
  }
  const missing = noNode.release(noNode.bin);
  check(missing.stderr.includes('node 가 없다'), 'missing Node is diagnosed before mutation');
  noNode.unchanged(missing);
  const atomic = fixture('atomic-rejection');
  fs.writeFileSync(path.join(atomic.remote, 'hooks/update'), '#!/bin/bash\ncase "$1" in refs/tags/*) exit 1;; esac\nexit 0\n', {mode: 0o755});
  check(atomic.release().status !== 0, 'rejected remote tag fails publication');
  check(run(atomic.repo, 'git', ['--git-dir', atomic.remote, 'rev-parse', 'main']) === atomic.initial, 'atomic push leaves remote branch unchanged when tag is rejected');
  check(run(atomic.repo, 'git', ['--git-dir', atomic.remote, 'tag', '--list']) === '', 'atomic failure publishes no remote tag');
  run(atomic.repo, 'git', ['merge-base', '--is-ancestor', 'harness-v2.2.0', 'HEAD']); assertions++;
  console.log(`PASS: ${assertions} offline release artifact assertions`);
} finally { fs.rmSync(temp, {recursive: true, force: true}); }
