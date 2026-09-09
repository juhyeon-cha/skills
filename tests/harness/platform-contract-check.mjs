// The identical native-host suite is run directly by Node on every CI OS.
// No shell, jq, Python, executable script stub or symlink is needed here.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {runCommand, executableCandidates} from '../../plugins/harness/lib/process.mjs';
import {loadConfig, validateConfig} from '../../plugins/harness/lib/config.mjs';
import {patchOperations, normalizePath, isReadonlySearch} from '../../plugins/harness/lib/operations.mjs';
import {inspectWorkspace} from '../../plugins/harness/lib/workspace.mjs';
import {prepareWorkspaceIdentity, preparationStatus} from '../../plugins/harness/lib/preparation.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const expected = process.argv[2] || process.platform;
const reportFile = process.argv[3];
const checks = [];
const report = {schema: 1, host: process.platform, expectedHost: expected, node: process.version,
  scope: 'native Node/Git core fixtures; not runtime hook or backend integration',
  core: 'UNREACHED', fullProduct: 'UNREACHED', checks,
  boundaries: {
    hooksAndGuard: 'native policy and runtime transport suites; actual CLI activation separate and UNREACHED here',
    workspaceLifecycle: 'native ledger and story naming; full lifecycle integration tested separately',
    preparation: 'configured preparation exercised by native-preparation-contract-check.mjs',
    legacyCommands: 'Bash strings retain shell semantics; structured argv uses no shell',
    windowsLaunchers: 'explicit cmd.exe adapter; constrained batch argv; arbitrary argv uses native executable',
    roles: 'native runtime registration/load/result not exercised',
    wslAndGitBash: 'transitional environments; not established by native core fixtures',
  }};
const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'harness-platform-'));
let exitCode = 0;
async function check(name, fn) { await fn(); checks.push(name); console.log(`PASS ${name}`); }
const emptyPath = {...process.env};
for (const key of Object.keys(emptyPath)) if (key.toUpperCase() === 'PATH') delete emptyPath[key];
emptyPath.PATH = path.join(temp, 'empty executable directory');
await fs.mkdir(emptyPath.PATH);
const run = (argv, cwd = temp, env = process.env) => runCommand({argv}, {cwd, env});
try {
  await check('actual host matches matrix (no platform simulation)', () => {
    assert.equal(process.platform, expected);
    assert.ok(['darwin', 'linux', 'win32'].includes(expected));
    assert.ok(Number(process.versions.node.split('.')[0]) >= 22);
    if (expected === 'win32') assert.equal(process.env.WSL_DISTRO_NAME, undefined);
  });
  const script = path.join(temp, '공백 argv fixture.mjs');
  await fs.writeFile(script, 'process.stdout.write(JSON.stringify(process.argv.slice(2))); process.stderr.write("오류\\r\\n"); process.exitCode = 7;\r\n');
  await check('native executable preserves argv, CRLF, stderr and nonzero without PATH tools', async () => {
    const args = ['space value', '한글', '"quoted"', "'literal'", 'line\nbreak', '$HOME; & | > * {x,y}', ''];
    const result = await run([process.execPath, script, ...args], temp, emptyPath);
    assert.equal(result.status, 'exited'); assert.equal(result.code, 7);
    assert.deepEqual(JSON.parse(result.stdout), args); assert.equal(result.stderr.toString(), '오류\r\n');
  });
  await check('missing shell and backend executables are explicit spawn errors', async () => {
    for (const executable of ['bash', 'jq', 'python3', 'gh', 'bd', 'curl', 'git']) {
      const result = await run([executable, '--version'], temp, emptyPath);
      assert.equal(result.status, 'spawn_error', executable); assert.equal(result.error.code, 'ENOENT', executable);
    }
    const result = await runCommand('printf legacy', {cwd: temp, env: emptyPath});
    assert.equal(result.status, 'spawn_error'); assert.equal(result.error.code, 'ENOENT');
  });
  await check('Windows lexical constraints are not host execution evidence', () => {
    const options = {cwd: 'C:\\공백 repo', platform: 'win32', env: {Path: 'C:\\tools', PATHEXT: '.EXE;.CMD'}};
    assert.deepEqual(executableCandidates('node', options), ['C:\\tools\\node.EXE', 'C:\\tools\\node.CMD']);
    assert.deepEqual(executableCandidates('npm.cmd', options), ['C:\\tools\\npm.cmd']);
    assert.throws(() => executableCandidates('C:relative', options), /ambiguous/);
    assert.equal(normalizePath('..\\새 파일', 'C:\\repo\\src'), 'C:\\repo\\새 파일');
    assert.equal(normalizePath('파일', '\\\\server\\share\\repo'), '\\\\server\\share\\repo\\파일');
  });
  await check('all patch operations and conservative shell classification', () => {
    const patch = '*** Begin Patch\r\n*** Add File: 새 파일\r\n+x\r\n*** Update File: old\r\n*** Move to: moved\r\n@@\r\n-x\r\n+y\r\n*** Delete File: gone\r\n*** End Patch\r\n';
    const ops = patchOperations(patch, temp);
    assert.deepEqual(ops.map(op => op.kind), ['create', 'move', 'delete']);
    assert.equal(ops[1].source, path.join(temp, 'old')); assert.equal(ops[1].destination, path.join(temp, 'moved'));
    assert.throws(() => patchOperations(patch.replace('Add File:', 'Unknown File:'), temp));
    assert.equal(isReadonlySearch('rg "literal --pre=*" file'), true);
    assert.equal(isReadonlySearch('rg --pr?=* needle file'), false);
  });
  await check('single config source retains extensions and rejects invalid backend', async () => {
    for (const backend of ['github', 'beads', 'notion']) {
      const config = {ledger: {backend}, bootstrap: {argv: [process.execPath, script]}, extension: {한글: true}};
      await fs.writeFile(path.join(temp, '.harness.json'), '\uFEFF' + JSON.stringify(config, null, 2).replaceAll('\n', '\r\n'));
      assert.deepEqual((await loadConfig(temp)).config, config);
    }
    assert.throws(() => validateConfig({ledger: {backend: 'unknown'}}), /no fallback/);
    await assert.rejects(loadConfig(path.join(temp, 'absent')), /ENOENT/);
  });
  const repo = path.join(temp, '원본 repo'); const linked = path.join(temp, '외부 linked');
  await fs.mkdir(repo);
  const gitEnv = {...process.env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: path.join(temp, 'empty.gitconfig'),
    GIT_TERMINAL_PROMPT: '0'};
  await fs.writeFile(gitEnv.GIT_CONFIG_GLOBAL, '');
  for (const key of Object.keys(gitEnv)) if (key.startsWith('GIT_') && !['GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL', 'GIT_TERMINAL_PROMPT'].includes(key)) delete gitEnv[key];
  const git = async args => { const r = await run(['git', ...args], repo, gitEnv); assert.equal(r.status, 'exited', r.error?.message); assert.equal(r.code, 0, r.stderr.toString()); return r.stdout.toString(); };
  await check('real Git metadata accepts external worktree and rejects lookalike folder', async () => {
    report.git = (await git(['--version'])).trim();
    await git(['init', '--initial-branch=main']);
    await git(['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-m', 'fixture']);
    await git(['worktree', 'add', '-b', 'fixture-linked', linked]);
    const identity = await inspectWorkspace(linked, {env: gitEnv});
    assert.equal(identity.linked, true); assert.equal(identity.top, await fs.realpath(linked));
    assert.equal(identity.main, await fs.realpath(repo)); assert.equal(identity.branch, 'fixture-linked');
    const fake = path.join(repo, '.claude', 'worktrees', 'fake'); await fs.mkdir(fake, {recursive: true});
    await assert.rejects(inspectWorkspace(fake, {env: gitEnv}), /not a worktree root/);
    await assert.rejects(inspectWorkspace(linked, {env: emptyPath}), /git .*failed/);
  });
  await check('dependency audit exposes native backend executables and shared hook dispatch', async () => {
    const read = name => fs.readFile(path.join(root, 'plugins/harness', name), 'utf8');
    assert.match(await read('scripts/ledger.sh'), /exec node/);
    report.ledgerDependencies = {};
    for (const [backend, executable] of Object.entries({github: 'gh', beads: 'bd', notion: null})) {
      const source = await read(`lib/ledger/${backend}.mjs`);
      assert.doesNotMatch(source, /['"](?:bash|jq|python3|curl)['"]/);
      if (executable) assert.match(source, new RegExp(`\\b${executable}\\b`));
      report.ledgerDependencies[backend] = {required: ['node', ...(executable ? [executable] : [])],
        coverage: 'offline native ledger suite; beads sync additionally uses optional dolt', integration: 'live backend UNREACHED'};
    }
    assert.match(await read('lib/workspace.mjs'), /process.execPath, path.join\(plugin, 'scripts\/ledger.mjs'\), '--root'/);
    assert.match(await read('lib/preparation.mjs'), /spawnWindowsWorker/);
    const hook = await read('scripts/hook.mjs');
    assert.doesNotMatch(hook, /spawn(?:Sync)?\(['"](?:bash|jq|python3)['"]/);
    for (const name of ['guard', 'stop', 'session-context']) {
      assert.match(hook, new RegExp(name));
      assert.doesNotMatch(await read(`lib/${name}.mjs`), /spawn(?:Sync)?\(['"](?:bash|jq|python3)['"]/);
    }
  });
  await check('no-command preparation uses no shell; configured preparation requires an execution result', async () => {
    const identity = await inspectWorkspace(linked, {env: gitEnv});
    const file = path.join(linked, '.harness.json');
    await fs.writeFile(file, JSON.stringify({ledger: {backend: 'github'}}));
    assert.deepEqual(await prepareWorkspaceIdentity(identity, {env: emptyPath}),
      {preparation: 'not-configured', ready: false, canDelegate: true});
    await fs.writeFile(file, JSON.stringify({ledger: {backend: 'github'}, bootstrap: {argv: [process.execPath, script]}}));
    assert.equal((await preparationStatus(identity)).canDelegate, false);
    report.configuredPreparation = 'UNREACHED in core suite: run native-preparation-contract-check.mjs';
  });
  assert.equal(checks.length, 9, 'all judgment points must run');
  report.core = 'PASS';
} catch (error) {
  report.core = 'FAIL'; report.error = error.stack; exitCode = 1; console.error(error);
} finally {
  await fs.rm(temp, {recursive: true, force: true});
  if (reportFile) await fs.writeFile(reportFile, JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report)); process.exitCode = exitCode;
}
