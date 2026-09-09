import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {evaluateGuard, RULES, GR_ROLES, IMPL_ROLES, BD_READ_EXEMPT, LEDGER_READ_EXEMPT, IMPL_BD_WRITE_ALLOW} from '../../plugins/harness/lib/guard.mjs';
import {evaluateStop, STOP_OUTCOMES, MAX_BLOCKS} from '../../plugins/harness/lib/stop.mjs';
import {resolveState, cancelSession} from '../../plugins/harness/lib/state.mjs';
import {powershellOperations} from '../../plugins/harness/lib/powershell-operations.mjs';
import {patchOperations} from '../../plugins/harness/lib/operations.mjs';
import {summarizeGuardLog} from '../../plugins/harness/lib/guard-log.mjs';
import {normalizeHookEvent} from '../../plugins/harness/lib/hook-event.mjs';
import {workspaceShellCommand} from '../../plugins/harness/lib/workspace-command.mjs';

const root = fileURLToPath(new URL('../../plugins/harness/', import.meta.url));
const temp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'harness-native-hooks-')));
const main = path.join(temp, 'repo'), workspace = path.join(temp, 'workspace');
const env = {...process.env, HARNESS_RUNTIME: 'claude', HARNESS_DATA_DIR: path.join(temp, 'data'), HARNESS_GUARD_LOG: path.join(temp, 'guard.tsv'), HARNESS_ROOT: main, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: path.join(temp, 'gitconfig'), GIT_TERMINAL_PROMPT: '0'};
for (const key of ['CLAUDE_PLUGIN_ROOT', 'CLAUDE_PLUGIN_DATA', 'PLUGIN_ROOT', 'PLUGIN_DATA', 'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR']) delete env[key];
fs.writeFileSync(env.GIT_CONFIG_GLOBAL, '');
let count = 0;
const check = async (label, fn) => { await fn(); count++; console.log('PASS ' + label); };
const git = (...args) => { const result = spawnSync('git', args, {env, encoding: 'utf8'}); assert.equal(result.status, 0, result.stderr); };
const event = (command, role = '', tool = 'Bash') => ({hook_event_name: 'PreToolUse', tool_name: tool, cwd: workspace, session_id: 'guard-session', ...(role ? {agent_id: 'child', agent_type: role} : {}), tool_input: {command}});
const write = (file, role = '') => ({...event('', role), tool_name: 'Write', tool_input: {file_path: file, content: 'fixture'}});
const judge = value => evaluateGuard(value, {env});
const posix = value => value.replaceAll('\\', '/');
const shellPath = value => `'${posix(value).replaceAll("'", "'\\''")}'`;
const scoped = session => resolveState({runtime: 'claude', cwd: main, sessionId: session}, env);
const stop = (session, rows, extra = {}, options = {}) => evaluateStop({cwd: main, session_id: session, ...extra}, {env, ledger: async () => ({code: 0, stdout: JSON.stringify(rows), stderr: ''}), ...options});

try {
  if (process.argv[2]) assert.equal(process.platform, process.argv[2], 'actual host must match requested host');
  git('init', '-q', main);
  fs.writeFileSync(path.join(main, '.harness.json'), JSON.stringify({ledger: {backend: 'beads'}}));
  git('-C', main, 'add', '.harness.json');
  git('-C', main, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture');
  git('-C', main, 'worktree', 'add', '-qb', 'worktree-fixture', workspace);
  const probes = {
    r_main_write: write(path.join(main, 'a')),
    r_main_shell: event(`rm -rf ${posix(path.join(main, 'a'))}`),
    r_remote: event('git push origin main', 'harness:implementer'),
    r_grader_write: write(path.join(workspace, 'a'), 'harness:reviewer'),
    r_grader_shell: event('git commit -m fixture', 'harness:reviewer'),
    r_impl_bd: event('bd -C /fixture close task', 'harness:implementer'),
    r_bd_root: event('bd note task fixture', 'harness:implementer'),
  };
  await check('every registered rule has a probe and no stale probe exists', () => assert.deepEqual(Object.keys(probes).sort(), RULES.map(rule => rule.run.name).sort()));
  for (const [rule, input] of Object.entries(probes)) await check(`rule ${rule}: deny, remove only registration, then allow`, async () => {
    const normal = await judge(input); assert.equal(normal.code, 2, normal.stderr); assert.equal(normal.rule, rule);
    const copy = path.join(temp, rule); fs.cpSync(root, copy, {recursive: true});
    const file = path.join(copy, 'lib/guard.mjs'); const before = fs.readFileSync(file, 'utf8');
    const after = before.split('\n').filter(line => !(line.startsWith('RULES.push(') && line.includes(`run: ${rule}}`))).join('\n');
    assert.notEqual(after, before); fs.writeFileSync(file, after);
    const mutant = await import(pathToFileURL(file).href);
    const result = await mutant.evaluateGuard(input, {env}); assert.equal(result.code, 0, result.stderr);
  });
  await check('main versus registered workspace file permissions for all roles', async () => {
    for (const role of ['', ...IMPL_ROLES.split(' '), ...GR_ROLES.split(' ')]) {
      assert.equal((await judge(write(path.join(main, 'a'), role))).code, 2);
      assert.equal((await judge(write(path.join(workspace, 'a'), role))).code, GR_ROLES.split(' ').includes(role) ? 2 : 0);
    }
  });
  await check('all shared ledger read exemptions and implementer write allowance', async () => {
    assert.ok(BD_READ_EXEMPT.split(' ').length >= 15); assert.equal(IMPL_BD_WRITE_ALLOW, 'note');
    for (const role of [...GR_ROLES.split(' '), ...IMPL_ROLES.split(' ')]) for (const sub of (BD_READ_EXEMPT + ' ' + LEDGER_READ_EXEMPT).split(' ')) assert.equal((await judge(event(`node /plugin/ledger.mjs --root /fixture ${sub}`, role))).code, 0, `${role} ${sub}`);
    for (const role of GR_ROLES.split(' ')) assert.equal((await judge(event('node /plugin/ledger.mjs --root /fixture note task fixture', role))).code, 2);
    assert.equal((await judge(event('node /plugin/ledger.mjs --root /fixture note task fixture', 'harness:implementer'))).code, 0);
    assert.equal((await judge(event('node /plugin/ledger.mjs note task fixture', 'harness:implementer'))).code, 2);
  });
  await check('read-only searches keep protected paths and policy words as data', async () => {
    for (const command of [`rg -n 'ledger.sh close' ${shellPath(main)}`, `grep -n 'git push' ${shellPath(main)}`, `cat ${shellPath(path.join(main, '한글 공백.txt'))}`]) assert.equal((await judge(event(command, 'harness:reviewer'))).code, 0, command);
    assert.equal((await judge(event(`rg --pre sh ${shellPath(main)}`))).code, 2);
    assert.equal((await judge(event(`cat ${shellPath(main)}; rm -rf ${shellPath(main)}`))).code, 2);
  });
  await check('apply_patch normalizes all multi-file add/update/delete/move endpoints atomically', async () => {
    const patch = `*** Begin Patch\n*** Add File: new.txt\n+hi\n*** Update File: src.txt\n*** Move to: moved.txt\n@@\n-old\n+new\n*** Delete File: gone.txt\n*** End Patch\n`;
    const parsed = patchOperations(patch, workspace); assert.equal(parsed.length, 3); assert.equal(parsed[1].kind, 'move');
    assert.equal((await judge({...event(patch), tool_name: 'apply_patch'})).code, 0);
    for (const header of [`*** Add File: ${posix(path.join(main, 'a'))}\n+x`, `*** Update File: ${posix(path.join(main, 'a'))}\n*** Move to: safe.txt`, `*** Update File: safe.txt\n*** Move to: ${posix(path.join(main, 'a'))}`, `*** Delete File: ${posix(path.join(main, 'a'))}`]) {
      const result = await judge({...event(`*** Begin Patch\n*** Add File: allowed.txt\n+x\n${header}\n*** End Patch`), tool_name: 'apply_patch'});
      assert.equal(result.code, 2, result.stderr);
    }
  });
  await check('unknown role, invalid event and malformed patch are UNREACHED', async () => {
    for (const input of [null, [], {}, {...event('echo ok'), agent_id: 'unidentified'}, event('echo ok', 'unknown'), {...event('not a patch'), tool_name: 'apply_patch'}]) { const result = await judge(input); assert.equal(result.code, 2); assert.match(result.stderr, /UNREACHED/); }
  });
  await check('PowerShell lexer preserves drive/UNC/Korean spaces and denies dynamic read exemption', () => {
    const drive = String.raw`C:\한글 폴더\a.txt`, unc = String.raw`\\server\share\공백 경로.txt`;
    assert.equal(powershellOperations(`Get-Content '${drive}' | Select-String 'git push'`, 'C:\\repo').readonly, true);
    assert.equal(powershellOperations(`Select-String -Path '${unc}' -Pattern 'ledger.sh close'`, 'C:\\repo').readonly, true);
    assert.deepEqual(powershellOperations(`Move-Item '${drive}' '${unc}'`, 'C:\\repo').paths, [drive, unc]);
    assert.equal(powershellOperations('Get-Content "$($x)"', 'C:\\repo').readonly, false);
    assert.equal(powershellOperations('Get-Content a; Set-Content b x', 'C:\\repo').readonly, false);
  });
  await check('PowerShell tool uses common role and file policies', async () => {
    assert.equal((await judge(event(`Get-Content '${main}' | Select-String 'git push'`, 'harness:reviewer', 'PowerShell'))).code, 0);
    assert.equal((await judge(event(`Get-Content '${main}' > scratch.txt`, '', 'PowerShell'))).code, 0);
    assert.equal((await judge(event(`Get-Content '${main}'; Set-Content scratch.txt x`, '', 'PowerShell'))).code, 0);
    assert.equal((await judge(event(`Set-Content '${path.join(main, '한글 공백.txt')}' x`, '', 'PowerShell'))).code, 2);
    assert.equal((await judge(event('git push origin main', 'harness:implementer', 'PowerShell'))).code, 2);
    assert.equal((await judge(event('git.exe push origin main', 'harness:implementer', 'PowerShell'))).code, 2);
    assert.equal((await judge(event('Git.EXE push origin main', 'harness:implementer', 'PowerShell'))).code, 2);
    for (const command of ['Set-Content a.txt x', 'Remove-Item -Force a.txt', 'Move-Item a.txt b.txt', 'echo x > a.txt']) {
      assert.equal((await judge({...event(command, '', 'PowerShell'), cwd: main})).code, 2, command);
      assert.equal((await judge(event(command, '', 'PowerShell'))).code, 0, command);
      assert.equal((await judge(event(command, 'harness:reviewer', 'PowerShell'))).code, 2, command);
    }
    for (const role of ['', 'harness:implementer', 'harness:reviewer']) {
      const command = `node '${path.join(main, 'plugins/harness/scripts/ledger.mjs')}' --root '${main}' show task`;
      assert.equal((await judge(event(command, role, 'PowerShell'))).code, 0, command);
      assert.equal((await judge(event(`git -C '${main}' status`, role, 'PowerShell'))).code, 0);
    }
    assert.equal((await judge(event(`node '${path.join(main, 'ledger.mjs')}' --root '${main}' note task fixture`, 'harness:implementer', 'PowerShell'))).code, 0);
    assert.equal((await judge(event(`node '${path.join(main, 'ledger.mjs')}' --root '${main}' close task`, 'harness:implementer', 'PowerShell'))).code, 2);
    assert.match((await judge(event('Get-Content "$($x)"', '', 'PowerShell'))).stderr, /UNREACHED/);
    const normalized = normalizeHookEvent(event('Get-Content a'), {platform: 'win32', env: {HARNESS_RUNTIME: 'codex'}});
    assert.equal(normalized.harness_shell_dialect, 'powershell');
    assert.equal(normalized.harness_shell_readonly, true);
    assert.equal(normalizeHookEvent(event('cat a'), {platform: 'win32', env: {HARNESS_RUNTIME: 'claude', CODEX_HOME: 'C:\\codex'}}).harness_shell_dialect, 'posix');
    const script = path.join(root, 'scripts/workspace.mjs');
    const workspaceCommand = `node '${script}' inspect '${main}'`;
    assert.equal(workspaceShellCommand(workspaceCommand, script, {dialect: 'powershell'}).action, 'inspect');
    assert.equal(workspaceShellCommand(workspaceCommand + '; echo x', script, {dialect: 'powershell'}), null);
    assert.equal(workspaceShellCommand(workspaceCommand + ' > out', script, {dialect: 'powershell'}), null);
    assert.equal((await judge(event(workspaceCommand, 'harness:reviewer', 'PowerShell'))).code, 0);
  });
  await check('PowerShell write path parameters preserve full, colon and abbreviated targets', async () => {
    for (const target of [path.join(main, '보호 파일.txt'), path.join(workspace, '허용 파일.txt')]) {
      for (const parameter of [`-Path '${target}'`, `-Path:'${target}'`, `-Pat '${target}'`, `-Pat:'${target}'`, `-LiteralPath:'${target}'`]) {
        const command = `Set-Content ${parameter} -Value '${main}'`;
        const result = await judge(event(command, '', 'PowerShell'));
        assert.equal(result.code, target.startsWith(main + path.sep) ? 2 : 0, command + '\n' + result.stderr);
      }
    }
    assert.equal((await judge(event(`Set-Content -Pat:'${path.join(workspace, 'allowed')}' -Value:'${main}'`, '', 'PowerShell'))).code, 0);
    for (const parameter of ['-P', '-UnknownWriteParameter']) {
      const result = await judge(event(`Set-Content ${parameter} '${path.join(main, 'file')}' -Value literal`, '', 'PowerShell'));
      assert.equal(result.code, 2); assert.match(result.stderr, /UNREACHED/);
    }
    assert.equal((await judge(event(`Select-String -Path:'${main}' -Pattern 'Set-Content -Pat protected'`, 'harness:reviewer', 'PowerShell'))).code, 0);
  });
  const outcomes = new Set();
  const capture = result => { result.outcomes.forEach(outcome => outcomes.add(outcome)); return result; };
  await check('Stop recursion, cancellation and legacy marker ownership', async () => {
    assert.equal(capture(await stop('recursive', [], {stop_hook_active: true})).stdout, '');
    const scope = await scoped('cancelled'); cancelSession(scope);
    assert.equal(capture(await stop('cancelled', [{id: 't'}])).stdout, '');
    fs.writeFileSync(path.join(env.HARNESS_DATA_DIR, 'stop-resume-cancel'), 'legacy');
    assert.equal(JSON.parse(capture(await stop('other', [{id: 't'}])).stdout).decision, 'block');
    assert.equal(fs.readFileSync(path.join(env.HARNESS_DATA_DIR, 'stop-resume-cancel'), 'utf8'), 'legacy');
  });
  await check('Stop oracle failure never becomes idle and zero work is explicit', async () => {
    const failed = capture(await stop('oracle', [], {}, {ledger: async () => ({code: 1, stdout: ''})})); assert.deepEqual(failed.outcomes, ['ORACLE_FAIL']);
    const malformed = capture(await stop('malformed', [], {}, {ledger: async () => ({code: 0, stdout: '{}'})})); assert.deepEqual(malformed.outcomes, ['ORACLE_FAIL']);
    const idle = capture(await stop('idle', [])); assert.ok(idle.outcomes.includes('IDLE')); assert.equal(idle.stdout, '');
  });
  await check('Stop verified actor narrows only matching runtime/repository/session', async () => {
    const scope = await scoped('actor'); fs.mkdirSync(path.dirname(scope.actors), {recursive: true});
    fs.writeFileSync(scope.actors, JSON.stringify({runtime: scope.runtime, repoKey: scope.repoKey, sessionId: scope.sessionId, claims: [{actor: 'mine', evidence: 'ledger-show'}]}));
    const result = capture(await stop('actor', [{actor: 'other', notes: ''}])); assert.deepEqual(result.outcomes, ['IDLE']);
    fs.writeFileSync(scope.actors, JSON.stringify({runtime: 'codex', repoKey: scope.repoKey, sessionId: scope.sessionId, claims: [{actor: 'mine', evidence: 'ledger-show'}]}));
    const foreign = capture(await stop('actor', [{actor: 'other', notes: ''}])); assert.ok(foreign.outcomes.includes('SCOPE_FAIL')); assert.equal(JSON.parse(foreign.stdout).decision, 'block');
  });
  await check('Stop last marker survives prose, mixed marks pass, unmarked work blocks and cap terminates', async () => {
    const pending = capture(await stop('pending', [{notes: 'DELEGATED: m\nVERIFY_PENDING: abc\nreview evidence'}, {notes: 'VERIFY_PENDING: old\nDELEGATED: m\nprose'}])); assert.ok(pending.outcomes.includes('VERIFY_PENDING')); assert.equal(pending.stdout, '');
    for (let i = 0; i < MAX_BLOCKS; i++) assert.equal(JSON.parse(capture(await stop('bounded', [{notes: ''}, {notes: 'VERIFY_PENDING: a'}])).stdout).decision, 'block');
    const done = capture(await stop('bounded', [{notes: ''}])); assert.ok(done.outcomes.includes('GAVE_UP')); assert.equal(done.stdout, '');
    assert.deepEqual([...outcomes].sort(), [...STOP_OUTCOMES].sort());
  });
  await check('Stop both marker checks have live independent negative controls', async () => {
    for (const [marker, line, notes] of [['VERIFY_MARK', 'const vp = 0;', 'VERIFY_PENDING: abc'], ['DELEGATED_MARK', 'const dg = 0;', 'DELEGATED: milestone']]) {
      const copy = path.join(temp, marker); fs.cpSync(root, copy, {recursive: true}); const file = path.join(copy, 'lib/stop.mjs');
      const before = fs.readFileSync(file, 'utf8'); const after = before.split('\n').map(value => value.includes('// ' + marker) ? '  ' + line : value).join('\n'); assert.notEqual(after, before); fs.writeFileSync(file, after);
      const mutant = await import(pathToFileURL(file).href);
      const result = await mutant.evaluateStop({cwd: main, session_id: marker}, {env, ledger: async () => ({code: 0, stdout: JSON.stringify([{notes}])})}); assert.equal(JSON.parse(result.stdout).decision, 'block');
      assert.equal((await stop(marker + '-control', [{notes}])).stdout, '');
    }
  });
  await check('guard log preserves count and Unicode legacy row outcomes', async () => {
    const file = path.join(temp, 'legacy.tsv'); const logEnv = {...env, HARNESS_GUARD_LOG: file};
    assert.equal((await summarizeGuardLog([], {env: logEnv, pluginRoot: root})).code, 1);
    fs.writeFileSync(file, 't1\ts\ta\tBash\t-\nt2\ts\ta\tBash\tr_x\t' + '한'.repeat(50) + '\nt3\tx\ta\tBash\tr_x\n');
    assert.equal((await summarizeGuardLog([], {env: logEnv})).code, 0);
    const rows = await summarizeGuardLog(['rows', 's'], {env: logEnv}); assert.equal(rows.code, 0); assert.match(rows.stdout, /\tok\t/);
    assert.equal((await summarizeGuardLog(['rows', 'absent'], {env: logEnv})).code, 5);
    assert.equal((await summarizeGuardLog(['rows', 'x'], {env: logEnv})).code, 6);
    assert.equal((await summarizeGuardLog(['unknown'], {env: logEnv})).code, 2);
  });
  console.log(`PASS native hooks: ${count} judgments on ${process.platform}; direct fixtures, actual runtime hook firing remains separate`);
} finally { fs.rmSync(temp, {recursive: true, force: true}); }
