// Runs directly under Node on macOS/Linux/native Windows; no Bash/jq fixtures.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {runCommand, windowsBatchArguments} from '../../plugins/harness/lib/process.mjs';
import {inspectWorkspace} from '../../plugins/harness/lib/workspace.mjs';
import {prepareWorkspaceIdentity, preparationPaths, preparationStatus} from '../../plugins/harness/lib/preparation.mjs';

assert.equal(process.platform, process.argv[2] || process.platform, 'actual host must match requested evidence');
const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'native-prepare-'));
const repo = path.join(temp, '원본 repo'), wt = path.join(temp, '준비 workspace');
const env = {...process.env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: path.join(temp, 'empty.gitconfig'), GIT_TERMINAL_PROMPT: '0'};
for (const key of Object.keys(env)) if (key.startsWith('GIT_') && !['GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL', 'GIT_TERMINAL_PROMPT'].includes(key)) delete env[key];
let reached = 0;
const check = async (name, fn) => { await fn(); reached++; console.log(`PASS ${name}`); };
const exists = file => fs.stat(file).then(() => true, error => { if (error.code === 'ENOENT') return false; throw error; });
const waitFor = async predicate => { const deadline = Date.now() + 30000; while (!(await predicate())) { if (Date.now() > deadline) throw new Error('fixture judgment UNREACHED'); await new Promise(r => setTimeout(r, 30)); } };
let identity, paths;
try {
  await fs.writeFile(env.GIT_CONFIG_GLOBAL, '');
  await fs.mkdir(repo);
  const git = async args => { const result = await runCommand({argv: ['git', ...args]}, {cwd: repo, env}); assert.equal(result.code, 0, result.stderr.toString()); };
  await git(['init', '--initial-branch=main']);
  await git(['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-m', 'fixture']);
  await git(['worktree', 'add', '-b', 'fixture-preparation', wt]);
  identity = await inspectWorkspace(wt, {env}); paths = preparationPaths(identity);
  const configFile = path.join(wt, '.harness.json'), input = path.join(wt, 'input'), countFile = path.join(wt, 'attempts');
  const script = path.join(wt, 'bootstrap 한글.mjs'), pidFile = path.join(wt, 'child.pid');
  await fs.writeFile(script, `import fs from 'node:fs'; import {spawn} from 'node:child_process';
fs.appendFileSync('attempts','x'); fs.writeFileSync('child.pid',String(process.pid));
const mode=fs.readFileSync('input','utf8');
if(mode==='descendant') {
  const child=spawn(process.execPath,['-e',"require('node:fs').writeFileSync('descendant.ready',String(process.pid));setInterval(()=>{},1000)"],{stdio:'ignore',detached:true});
  fs.writeFileSync('descendant.pid',String(child.pid)); child.unref();
  const deadline=Date.now()+10000;
  while(!fs.existsSync('descendant.ready')) { if(Date.now()>deadline) throw new Error('descendant liveness UNREACHED'); await new Promise(r=>setTimeout(r,20)); }
  if(fs.readFileSync('descendant.ready','utf8')!==String(child.pid)) throw new Error('descendant identity mismatch');
  process.kill(child.pid,0);
}
if(mode==='hold') await new Promise(r=>setTimeout(r,30000));
else await new Promise(r=>setTimeout(r,1000));
process.exitCode=mode==='fail'?9:0;
`);
  const config = {ledger: {backend: 'github'}, bootstrap: {argv: [process.execPath, script]}, preparation: {inputs: ['input', 'bootstrap 한글.mjs'], timeout_ms: 10000}};
  const save = () => fs.writeFile(configFile, JSON.stringify(config));
  const setMode = async value => { await fs.writeFile(input, value); await fs.rm(pidFile, {force: true}); await save(); };
  const count = () => fs.readFile(countFile, 'utf8').then(x => x.length, () => 0);
  const prepare = () => prepareWorkspaceIdentity(identity, {env, say: text => process.stderr.write(text)});
  await setMode('fail');
  await check('failed bootstrap is not ready and is retryable', async () => {
    const before = await count();
    await assert.rejects(prepare(), /부트스트랩 실패: 9/); assert.equal(await count(), before + 1);
    assert.equal((await preparationStatus(identity)).ready, false);
    await setMode('ok'); assert.equal((await prepare()).ready, true);
  });
  await check('unchanged receipt avoids duplicate execution', async () => {
    const before = await count(); assert.equal((await prepare()).ready, true); assert.equal(await count(), before);
  });
  await check('concurrent runtime callers share execution', async () => {
    await setMode('concurrent'); const before = await count();
    const results = await Promise.all([prepare(), prepare()]);
    assert.ok(results.every(result => result.ready)); assert.equal(await count(), before + 1);
  });
  await check('timeout never publishes READY and terminated ownership recovers', async () => {
    config.preparation.timeout_ms = 500; await setMode('hold'); await assert.rejects(prepare());
    assert.equal(await exists(paths.ready), false);
    config.preparation.timeout_ms = 10000; await setMode('retry-timeout'); assert.equal((await prepare()).ready, true);
  });
  await check('input replacement during execution cannot certify old bytes', async () => {
    await setMode('changing'); const pending = prepare(); await waitFor(() => exists(pidFile));
    await fs.writeFile(input, 'replacement'); await assert.rejects(pending); assert.equal(await exists(paths.ready), false);
    assert.equal((await prepare()).ready, true);
  });
  await check('batch adapter rejects unrepresentable argv before any launch', async () => {
    for (const value of ['x&echo unsafe', '%PATH%', '!x!', 'a"b', 'a\nb', '^x', 'C:\\tail\\', '(x)']) assert.throws(() => windowsBatchArguments('C:\\fixture.cmd', [value]), /batch arguments/);
    assert.deepEqual(windowsBatchArguments('C:\\공백\\fixture.cmd', ['space value', '한글', '']), ['/d', '/s', '/v:off', '/c', '""C:\\공백\\fixture.cmd" "space value" "한글" """']);
  });
  if (process.platform === 'win32') {
    await check('native cmd/bat adapter preserves representable argv and exit status', async () => {
      const echo = path.join(wt, 'argv.mjs'); await fs.writeFile(echo, 'process.stdout.write(JSON.stringify(process.argv.slice(2))); process.exitCode=7;');
      for (const suffix of ['cmd', 'bat']) {
        const batch = path.join(wt, `공백 launcher.${suffix}`);
        await fs.writeFile(batch, '@echo off\r\n"%FIXTURE_NODE%" "%FIXTURE_ECHO%" %*\r\n', 'utf8');
        const values = ['한글', 'space value', '', 'C:\\path\\file', "'literal'"];
        const result = await runCommand({argv: [batch, ...values]}, {cwd: wt, env: {...env, FIXTURE_NODE: process.execPath, FIXTURE_ECHO: echo}});
        assert.equal(result.code, 7, result.stderr.toString()); assert.deepEqual(JSON.parse(result.stdout), values);
        const invalid = await runCommand({argv: [batch, 'x&echo unsafe']}, {cwd: wt, env});
        assert.equal(invalid.status, 'spawn_error'); assert.equal(invalid.error.code, 'UNREPRESENTABLE_BATCH_ARGUMENT');
      }
    });
    await check('worker crash terminates its Job descendants before lock recovery', async () => {
      await setMode('hold'); const pending = prepare(); await waitFor(() => exists(pidFile));
      const owner = JSON.parse(await fs.readFile(path.join(paths.lock, 'owner.json'), 'utf8'));
      const childPid = Number(await fs.readFile(pidFile, 'utf8'));
      assert.match(owner.job, /^Local\\HarnessPrepare-/); process.kill(owner.pid, 'SIGKILL');
      await assert.rejects(pending);
      assert.throws(() => process.kill(childPid, 0), {code: 'ESRCH'});
      await setMode('retry-crash'); assert.equal((await prepare()).ready, true);
    });
    await check('surviving descendants prevent READY and are reaped by supervisor', async () => {
      await setMode('descendant'); await assert.rejects(prepare());
      assert.equal(await fs.readFile(path.join(wt, 'descendant.ready'), 'utf8'), await fs.readFile(path.join(wt, 'descendant.pid'), 'utf8'));
      assert.equal(await exists(paths.ready), false);
      const childPid = Number(await fs.readFile(path.join(wt, 'descendant.pid'), 'utf8'));
      assert.throws(() => process.kill(childPid, 0), {code: 'ESRCH'});
      await setMode('retry-descendant'); assert.equal((await prepare()).ready, true);
    });
    await check('supervisor crash closes the owning Job and cannot orphan bootstrap', async () => {
      await setMode('hold'); const pending = prepare(); await waitFor(() => exists(pidFile));
      const owner = JSON.parse(await fs.readFile(path.join(paths.lock, 'owner.json'), 'utf8'));
      const childPid = Number(await fs.readFile(pidFile, 'utf8'));
      process.kill(owner.supervisor, 'SIGKILL'); await assert.rejects(pending);
      await waitFor(() => { try { process.kill(childPid, 0); return false; } catch (error) { if (error.code === 'ESRCH') return true; throw error; } });
      assert.equal(await exists(paths.ready), false);
      await setMode('retry-supervisor'); assert.equal((await prepare()).ready, true);
    });
    await check('launcher crash terminates its attached supervisor and owned worker tree', async () => {
      await setMode('hold'); const pending = prepare(); await waitFor(() => exists(pidFile));
      const owner = JSON.parse(await fs.readFile(path.join(paths.lock, 'owner.json'), 'utf8'));
      const childPid = Number(await fs.readFile(pidFile, 'utf8'));
      process.kill(owner.launcher, 'SIGKILL'); await assert.rejects(pending);
      for (const pid of [owner.supervisor,owner.pid,childPid]) await waitFor(() => {try {process.kill(pid,0);return false;} catch(error) {if(error.code==='ESRCH')return true;throw error;}});
      assert.equal(await exists(paths.ready), false);
      await setMode('retry-launcher'); assert.equal((await prepare()).ready, true);
    });
    await check('Job identity prevents a reused/live unrelated PID from blocking safe recovery', async () => {
      await setMode('pid-reuse'); await fs.mkdir(paths.lock);
      await fs.writeFile(path.join(paths.lock, 'owner.json'), JSON.stringify({pid: process.pid, token: 'old-owner', job: 'Local\\HarnessPrepare-00000000-0000-0000-0000-000000000000'}));
      assert.equal((await prepare()).ready, true); process.kill(process.pid, 0);
    });
    await check('missing PowerShell cannot establish configured readiness', async () => {
      await setMode('missing-helper'); const missing = {...env};
      for (const key of Object.keys(missing)) if (key.toUpperCase() === 'PATH') delete missing[key];
      missing.PATH = temp;
      await assert.rejects(prepareWorkspaceIdentity(identity, {env: missing}), /not found/);
      assert.equal((await preparationStatus(identity)).ready, false);
    });
    await check('killed waiter does not own independent preparation lifetime', async () => {
      await setMode('waiter');
      const module = fileURLToPath(new URL('../../plugins/harness/lib/preparation.mjs', import.meta.url));
      const launcher = path.join(temp, 'caller.mjs');
      await fs.writeFile(launcher, `import {prepareWorkspaceIdentity} from ${JSON.stringify(pathToFileURL(module).href)}; await prepareWorkspaceIdentity(${JSON.stringify(identity)});`);
      const caller = spawn(process.execPath, [launcher], {cwd: wt, env, stdio: 'ignore'});
      const done = new Promise(resolve => caller.on('close', resolve));
      await waitFor(() => exists(pidFile)); caller.kill('SIGKILL'); await done;
      await waitFor(async () => await exists(paths.ready) && !(await exists(paths.lock)));
      assert.equal((await preparationStatus(identity)).ready, true);
    });
  } else console.log('UNREACHED Windows Job/cmd-specific controls: requires native Windows; common preparation executed on ' + process.platform);
  await check('empty and malformed worker responses remain UNREACHED with Unicode diagnostics', async () => {
    const copy = path.join(temp, 'protocol-plugin');
    await fs.cp(fileURLToPath(new URL('../../plugins/harness', import.meta.url)), copy, {recursive: true});
    const module = await import(pathToFileURL(path.join(copy, 'lib/preparation.mjs')));
    for (const response of ['', 'invalid-json']) {
      await setMode('protocol-' + response);
      await fs.writeFile(path.join(copy, 'scripts/prepare-worker.mjs'), `import fs from 'node:fs'; import path from 'node:path';
const response=${JSON.stringify(response)}, diagnostic='한글 진단 protocol';
if(process.platform==='win32') { const ipc=process.env.HARNESS_PREPARE_IPC; fs.writeFileSync(path.join(ipc,'diagnostics.log'),diagnostic); if(response) fs.writeFileSync(path.join(ipc,'result.json'),response); }
else { process.stderr.write(diagnostic); process.stdout.write(response); }
`);
      await assert.rejects(module.prepareWorkspaceIdentity(identity, {env}), error => error.message.includes('PREPARE_PROTOCOL_UNREACHED') && error.message.includes('한글 진단 protocol'));
      assert.equal((await preparationStatus(identity)).canDelegate, false);
    }
  });
  if (!process.argv.includes('--mutation-child')) {
    await check('removing failed-command rejection makes this suite fail', async () => {
      const copy = path.join(temp, 'mutation');
      await fs.cp(fileURLToPath(new URL('../../plugins/harness', import.meta.url)), path.join(copy, 'plugins/harness'), {recursive: true});
      await fs.mkdir(path.join(copy, 'tests/harness'), {recursive: true});
      const test = path.join(copy, 'tests/harness/native-preparation-contract-check.mjs');
      await fs.copyFile(fileURLToPath(import.meta.url), test);
      const module = path.join(copy, 'plugins/harness/lib/preparation.mjs');
      const before = await fs.readFile(module, 'utf8');
      const after = before.replace("if (result.status !== 'exited' || result.code !== 0)", 'if (false)');
      assert.notEqual(after, before); await fs.writeFile(module, after);
      const result = await runCommand({argv: [process.execPath, test, process.platform, '--mutation-child']}, {cwd: copy, env});
      assert.equal(result.code, 1, result.stderr.toString()); assert.match(result.stderr.toString(), /Missing expected rejection/);
    });
  }
  assert.equal(reached, (process.platform === 'win32' ? 15 : 7) + (process.argv.includes('--mutation-child') ? 0 : 1), 'every host-applicable judgment must run');
  console.log(`PASS native preparation/process ${reached}; host=${process.platform}; actual runtime hooks are separate evidence`);
} finally { await fs.rm(temp, {recursive: true, force: true}); }
