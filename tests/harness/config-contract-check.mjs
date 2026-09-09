import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {validateConfig, loadConfig, loadConfigSnapshot, configCommand} from '../../plugins/harness/lib/config.mjs';
import {runCommand, executableCandidates, resolveExecutable} from '../../plugins/harness/lib/process.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const temp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'config-contract-')));
let reached = 0;
const check = (value, message) => { assert.ok(value, message); reached++; };
const rejects = async (fn, pattern, message) => { await assert.rejects(fn, pattern, message); reached++; };
const env = {...process.env, HOME: temp};
const cli = (action, cwd, field) => spawnSync(process.execPath, [path.join(root, 'plugins/harness/scripts/config.mjs'), action, cwd, ...(field ? [field] : [])], {env, encoding: 'utf8'});
try {
  const cwd = path.join(temp, '한글 repo with spaces'); fs.mkdirSync(cwd);
  const legacy = {ledger: {backend: 'github', owner: 'fixture', project: 5, custom: ['keep']}, check: 'bash scripts/check.sh', default_branch: 'main', bootstrap: 'printf "%s" "$FIXTURE_TEXT"', custom: {nested: ['추가 키']}};
  const file = path.join(cwd, '.harness.json');
  fs.writeFileSync(file, JSON.stringify(legacy));
  const loaded = await loadConfig(cwd);
  check(loaded.file === file && JSON.stringify(loaded.config) === JSON.stringify(legacy), 'legacy keys/extensions preserved exactly');
  const bytes = fs.readFileSync(file);
  const snapshot = await loadConfigSnapshot(cwd);
  check(snapshot.bytes.equals(bytes) && JSON.stringify(snapshot.config) === JSON.stringify(legacy), 'snapshot bytes and validated config describe the same read');
  check(Object.keys(loaded).sort().join(',') === 'config,file', 'existing loader return shape remains compatible');
  check(JSON.stringify(JSON.parse(cli('validate', cwd).stdout)) === JSON.stringify(legacy), 'validate CLI preserves source config');
  check(fs.readFileSync(file).equals(bytes), 'reading never rewrites repo config');
  const legacyString = {...legacy, ledger: {...legacy.ledger, project: '5'}, check: 'printf legacy', bootstrap: 'printf legacy'};
  fs.writeFileSync(file, JSON.stringify(legacyString));
  const validation = cli('validate', cwd);
  check(validation.status === 0 && JSON.parse(validation.stdout).ledger.project === '5', 'legacy numeric project string preserved');
  for (const field of ['check', 'bootstrap']) {
    const result = cli('run', cwd, field);
    check(result.status === 0 && result.stdout === 'legacy', `legacy string project does not block ${field}`);
  }
  // Exercise the existing adapter, with only gh replaced by an offline fixture.
  const fakeBin = path.join(temp, 'fake-gh'); fs.mkdirSync(fakeBin);
  const issue = {number: 1, title: 'fixture', state: 'OPEN', repository: {name: 'fixture'}, labels: {nodes: []}, comments: {nodes: []}, assignees: {nodes: []}, blockedBy: {totalCount: 0, nodes: []}, projectItems: {nodes: [{project: {number: 5}}]}};
  const projectResponse = [{data: {user: {projectV2: {items: {nodes: [{content: {repository: {name: 'fixture'}}}]}}}}}];
  const issuesResponse = [{data: {repository: {issues: {nodes: [issue]}}}}];
  fs.writeFileSync(path.join(fakeBin, 'gh'), `#!/usr/bin/env node\nconst args = process.argv.slice(2);\nif (args.join(' ') === 'auth status') process.exit(0);\nconst q = args.find(a => a.startsWith('query=')) || '';\nif (args[0] !== 'api' || args[1] !== 'graphql' || !q.startsWith('query=query(')) process.exit(99);\nif (q.includes('projectV2(')) { if (!args.includes('n=5')) process.exit(98); console.log(${JSON.stringify(JSON.stringify(projectResponse))}); }\nelse if (q.includes('repository(owner:')) console.log(${JSON.stringify(JSON.stringify(issuesResponse))});\nelse process.exit(97);\n`, {mode: 0o755});
  const adapterEnv = {...env, PATH: `${fakeBin}:${env.PATH}`, HARNESS_ROOT: cwd, CLAUDE_PLUGIN_ROOT: path.join(root, 'plugins/harness')};
  const adapterRead = () => spawnSync('bash', [path.join(root, 'plugins/harness/scripts/ledger.sh'), 'list', '--json'], {env: adapterEnv, encoding: 'utf8'});
  const stringRead = adapterRead();
  fs.writeFileSync(file, JSON.stringify(legacy));
  const numberRead = adapterRead();
  check(stringRead.status === 0 && numberRead.status === 0 && stringRead.stdout === numberRead.stdout && JSON.parse(stringRead.stdout)[0].id === 'fixture#1', 'actual adapter project string and number select the same nonempty issue');
  for (const backend of ['github', 'beads', 'notion']) check(validateConfig({ledger: {backend}}).ledger.backend === backend, `explicit backend ${backend}`);
  for (const config of [[], null, {}, {ledger: {}}, {ledger: {backend: 'other'}}, {...legacy, schema_version: 2}, {...legacy, schema_version: '1'}, {...legacy, check: {argv: []}}, {...legacy, bootstrap: {argv: ['node', 2]}}, {...legacy, check: {argv: ['node'], shell: true}}, {...legacy, default_branch: ''}, {...legacyString, schema_version: 1}, ...['', 'abc', '0', '-5', '5.1', '05', ' 5', '5e0'].map(project => ({...legacy, ledger: {...legacy.ledger, project}}))]) {
    fs.writeFileSync(file, JSON.stringify(config));
    check(cli('validate', cwd).status !== 0, 'invalid config must fail; unsupported versions never fall back');
  }
  fs.writeFileSync(file, '{broken'); check(cli('validate', cwd).status !== 0, 'malformed JSON fails');
  fs.unlinkSync(file); check(cli('validate', cwd).status !== 0, 'missing file fails');
  await rejects(() => loadConfig(cwd), /ENOENT/, 'missing file throws');
  fs.writeFileSync(file, '\uFEFF' + JSON.stringify({...legacy, schema_version: 1}, null, 2).replaceAll('\n', '\r\n'));
  check((await loadConfig(cwd)).config.schema_version === 1, 'UTF8 BOM and CRLF config');
  for (const bootstrap of [undefined, null, '']) {
    const config = {...legacy, bootstrap}; if (bootstrap === undefined) delete config.bootstrap;
    check(configCommand(config, 'bootstrap') === null, 'legacy absent/empty bootstrap is explicit no-command');
  }
  const script = path.join(cwd, 'echo argv 한글.mjs');
  fs.writeFileSync(script, 'process.stdout.write(JSON.stringify(process.argv.slice(2))); process.stderr.write("오류\\n");');
  const args = ['', '공백 한글', 'line1\nline2', 'a"b', "a'b", '$HOME; $(touch NEVER)', 'C:\\space dir\\한글', '&|<>*?'];
  const command = {argv: [process.execPath, script, ...args]};
  const direct = await runCommand(command, {cwd, env});
  check(direct.status === 'exited' && direct.code === 0 && direct.signal === null, 'direct argv completion');
  check(JSON.stringify(JSON.parse(direct.stdout)) === JSON.stringify(args), 'arguments preserve Unicode, spaces, newlines and metacharacters');
  check(direct.stderr.toString() === '오류\n' && !fs.existsSync(path.join(cwd, 'NEVER')), 'stderr exact and no shell interpretation');
  fs.writeFileSync(file, JSON.stringify({...legacy, schema_version: 1, bootstrap: command}));
  const directCli = cli('run', cwd, 'bootstrap');
  check(directCli.status === 0 && directCli.stdout === direct.stdout.toString() && directCli.stderr === direct.stderr.toString(), 'CLI argv output exact');
  const shellEnv = {...env, FIXTURE_TEXT: '한글 공백\nline2'};
  const shell = 'values=("$FIXTURE_TEXT" "space arg"); printf "%s\\n" "${values[@]}"; printf stderr >&2';
  const reference = spawnSync('bash', ['-c', shell], {cwd, env: shellEnv});
  const actual = await runCommand(shell, {cwd, env: shellEnv});
  check(reference.status === 0 && actual.code === reference.status && actual.stdout.equals(reference.stdout) && actual.stderr.equals(reference.stderr), 'legacy matches existing bash -c environment and quoting');
  const nonzero = {argv: [process.execPath, '-e', 'process.stdout.write("out"); process.stderr.write("err"); process.exit(23)']};
  const failed = await runCommand(nonzero, {cwd, env});
  check(failed.status === 'exited' && failed.code === 23 && failed.stdout.toString() === 'out' && failed.stderr.toString() === 'err', 'nonzero code and streams preserved');
  fs.writeFileSync(file, JSON.stringify({...legacy, check: nonzero}));
  check(cli('run', cwd, 'check').status === 23, 'CLI nonzero preserved');
  const absent = await runCommand({argv: ['harness-nonexistent-executable']}, {cwd, env: {...env, PATH: temp}});
  check(absent.status === 'spawn_error' && absent.code === null && absent.error.code === 'ENOENT', 'missing executable differs from child exit');
  const noCwd = await runCommand({argv: [process.execPath]}, {cwd: path.join(temp, 'absent'), env});
  check(noCwd.status === 'spawn_error' && noCwd.error.code === 'ENOENT', 'spawn cwd failure preserved');
  if (process.platform !== 'win32') {
    const signaled = await runCommand({argv: [process.execPath, '-e', 'process.kill(process.pid, "SIGTERM")']}, {cwd, env});
    check(signaled.status === 'signaled' && signaled.signal === 'SIGTERM' && signaled.code === null, 'signal completion distinct from exit');
    fs.writeFileSync(file, JSON.stringify({...legacy, check: {argv: [process.execPath, '-e', 'process.kill(process.pid, "SIGTERM")']}}));
    const signalCli = cli('run', cwd, 'check');
    check(signalCli.status === 143 && JSON.parse(signalCli.stderr).signal === 'SIGTERM', 'CLI signal code plus original signal diagnostic');
    const bin = path.join(temp, 'bin space'); fs.mkdirSync(bin);
    fs.symlinkSync(process.execPath, path.join(bin, 'node-fixture'));
    check(await resolveExecutable('node-fixture', {cwd, env: {PATH: bin}}) === path.join(bin, 'node-fixture'), 'PATH discovery preserves spaces');
    check(await resolveExecutable('./node-fixture', {cwd: bin, env: {PATH: ''}}) === path.join(bin, 'node-fixture'), 'relative executable resolves against explicit cwd');
    check(await resolveExecutable('node-fixture', {cwd: bin, env: {PATH: ':' + temp}}) === path.join(bin, 'node-fixture'), 'POSIX empty PATH component means cwd');
    const denied = path.join(bin, 'not-executable'); fs.writeFileSync(denied, 'no', {mode: 0o644});
    const permission = await runCommand({argv: [denied]}, {cwd, env});
    check(permission.status === 'spawn_error' && permission.error.code === 'EACCES', 'permission error not flattened to missing executable');
    const noBash = await runCommand('printf ok', {cwd, env: {PATH: temp}});
    check(noBash.status === 'spawn_error' && noBash.error.code === 'ENOENT', 'legacy Bash absence never substitutes another shell');
  }
  const win = {cwd: 'C:\\repo space', platform: 'win32', env: {Path: 'C:\\Program Files\\bin;\\\\server\\share\\bin', PATHEXT: '.EXE;.CMD'}};
  check(JSON.stringify(executableCandidates('node', win)) === JSON.stringify(['C:\\Program Files\\bin\\node.EXE', 'C:\\Program Files\\bin\\node.CMD', '\\\\server\\share\\bin\\node.EXE', '\\\\server\\share\\bin\\node.CMD']), 'Windows PATH/PATHEXT lexical candidates');
  for (const name of ['npm.cmd', 'C:\\bin\\npm.BAT']) { check(executableCandidates(name, win).length > 0, 'Windows script launcher reaches explicit adapter discovery'); }
  await rejects(() => resolveExecutable('C:relative.exe', win), /ambiguous/, 'Windows drive-relative executable denied');
  // Run this same suite against a source copy with version validation removed.
  // Its invalid-version assertion must fail, establishing a live negative gate.
  if (!process.argv.includes('--mutation-child')) {
    const copy = path.join(temp, 'mutated');
    for (const relative of ['plugins/harness/lib/config.mjs', 'plugins/harness/lib/process.mjs', 'plugins/harness/scripts/config.mjs', 'plugins/harness/scripts/ledger.sh', 'plugins/harness/scripts/ledger-github.sh', 'tests/harness/config-contract-check.mjs']) {
      const target = path.join(copy, relative); fs.mkdirSync(path.dirname(target), {recursive: true}); fs.copyFileSync(path.join(root, relative), target);
    }
    const target = path.join(copy, 'plugins/harness/lib/config.mjs');
    const before = fs.readFileSync(target, 'utf8');
    const after = before.split('\n').filter(line => !line.includes("if ('schema_version' in config")).join('\n');
    check(after !== before, 'negative source mutation actually changed version validation'); fs.writeFileSync(target, after);
    const negative = spawnSync(process.execPath, [path.join(copy, 'tests/harness/config-contract-check.mjs'), '--mutation-child'], {env, encoding: 'utf8'});
    check(negative.status === 1 && negative.stderr.includes('unsupported versions never fall back'), 'mutated validation suite fails at intended assertion');
    console.log('negative control: removed version validation, suite exit 1');
  }
  check(reached >= 40, 'nonempty reached contract set');
  console.log(`PASS config/process contract: ${reached} assertions; host=${process.platform}; Windows candidates lexical only`);
} finally { fs.rmSync(temp, {recursive: true, force: true}); }
