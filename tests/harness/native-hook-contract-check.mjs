import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {executableCandidates} from '../../plugins/harness/lib/process.mjs';
import {patchOperations, normalizePath, isReadonlySearch} from '../../plugins/harness/lib/guard/operations.mjs';
import {evaluateGuard, GR_ROLES, IMPL_ROLES, BD_READ_EXEMPT, LEDGER_READ_EXEMPT, IMPL_BD_WRITE_ALLOW} from '../../plugins/harness/lib/guard/guard.mjs';
import {powershellOperations} from '../../plugins/harness/lib/guard/powershell-operations.mjs';
import {summarizeGuardLog} from '../../plugins/harness/lib/guard/guard-log.mjs';
import {normalizeHookEvent} from '../../plugins/harness/lib/guard/hook-event.mjs';
import {workspaceShellCommand} from '../../plugins/harness/lib/workspace/workspace-command.mjs';
import {windowsCommandOperands} from '../../plugins/harness/lib/guard/common-command.mjs';
import {LEDGER_TOOLS} from '../../plugins/harness/lib/guard/guard.mjs';

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

try {
  if (process.argv[2]) assert.equal(process.platform, process.argv[2], 'actual host must match requested host');
  git('init', '-q', main);
  fs.writeFileSync(path.join(main, '.harness.json'), JSON.stringify({ledger: {backend: 'beads'}}));
  git('-C', main, 'add', '.harness.json');
  git('-C', main, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture');
  git('-C', main, 'worktree', 'add', '-qb', 'worktree-fixture', workspace);
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
  await check('all shared ledger read exemptions and implementer write allowance', async () => {
    assert.ok(BD_READ_EXEMPT.split(' ').length >= 15); assert.deepEqual(IMPL_BD_WRITE_ALLOW.split(' ').sort(), ['note', 'state', 'summary']);
    for (const role of [...GR_ROLES.split(' '), ...IMPL_ROLES.split(' ')]) for (const sub of (BD_READ_EXEMPT + ' ' + LEDGER_READ_EXEMPT).split(' ')) assert.equal((await judge(event(`node /plugin/ledger.mjs --root /fixture ${sub}`, role))).code, 0, `${role} ${sub}`);
    for (const command of ['note task fixture', 'state task "VERIFY_PENDING: abc123"', 'summary task implementation --file /tmp/result.md']) {
      for (const role of GR_ROLES.split(' ')) assert.equal((await judge(event(`node /plugin/ledger.mjs --root /fixture ${command}`, role))).code, 2, `${role} ${command}`);
      assert.equal((await judge(event(`node /plugin/ledger.mjs --root /fixture ${command}`, 'harness:implementer'))).code, 0, command);
      assert.equal((await judge(event(`node /plugin/ledger.mjs ${command}`, 'harness:implementer'))).code, 2, `unscoped ${command}`);
    }
    for (const command of ['update task --claim --actor session', 'close task', 'project-setup --apply'])
      assert.equal((await judge(event(`node /plugin/ledger.mjs --root /fixture ${command}`, 'harness:implementer'))).code, 2, command);
  });
  await check('read-only searches keep protected paths and policy words as data', async () => {
    const discard = `rg --files -g AGENTS.md -g CLAUDE.md ${shellPath(path.dirname(main))} 2>/dev/null | head -40; cat ${shellPath(path.join(main, 'CLAUDE.md'))}`;
    assert.equal((await judge(event(discard))).code, 0, discard);
    for (const suffix of [` >${shellPath(path.join(main, 'output'))}`, ` >/dev/null; rm -rf ${shellPath(main)}`])
      assert.equal((await judge(event(`rg x ${shellPath(main)}${suffix}`))).code, 2, suffix);
    for (const command of [`rg -n 'ledger.sh close' ${shellPath(main)}`, `grep -n 'git push' ${shellPath(main)}`, `cat ${shellPath(path.join(main, '한글 공백.txt'))}`]) assert.equal((await judge(event(command, 'harness:reviewer'))).code, 0, command);
    assert.equal((await judge(event(`rg --pre sh ${shellPath(main)}`))).code, 0);
    assert.equal((await judge(event(`cat ${shellPath(main)}; rm -rf ${shellPath(main)}`))).code, 2);
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
      const gitCommand = `git -C '${main}' status`, gitResult = await judge(event(gitCommand, role, 'PowerShell'));
      assert.equal(gitResult.code, 0, gitCommand + '\n' + gitResult.stderr);
    }
    assert.equal((await judge(event(`node '${path.join(main, 'ledger.mjs')}' --root '${main}' note task fixture`, 'harness:implementer', 'PowerShell'))).code, 0);
    assert.equal((await judge(event(`node '${path.join(main, 'ledger.mjs')}' --root '${main}' close task`, 'harness:implementer', 'PowerShell'))).code, 2);
    assert.equal((await judge(event('Get-Content "$($x)"', '', 'PowerShell'))).code, 0);
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
  await check('PowerShell policy argv keeps short Windows names and Unicode paths in one coordinate', async () => {
    for (const coordinate of [String.raw`C:\Users\RUNNER~1\Temp\한글 공백`, path.join(main, 'RUNNER~1', '한글 공백')]) {
      const command = `git -C '${coordinate}' status`, result = await judge(event(command, 'harness:reviewer', 'PowerShell'));
      assert.equal(result.code, 0, command + '\n' + result.stderr);
      const writeCommand = `git -C '${coordinate}' checkout -- .`, denied = await judge(event(writeCommand, 'harness:reviewer', 'PowerShell'));
      assert.equal(denied.code, 2, writeCommand + '\n' + denied.stderr);
    }
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
  await check('literal Windows ledger operands distinguish coordinates from repeated write operands', () => {
    for (const dialect of ['posix', 'powershell']) for (const repository of [String.raw`C:\repo 한글`, 'C:/repo', String.raw`\\server\share\repo`]) {
      const command = `node 'C:/plugin/scripts/ledger.mjs' --root '${repository}'`;
      for (const sub of ['show task', 'list', 'note task fixture']) {
        const result = windowsCommandOperands(command + ' ' + sub, {dialect, ledgerTools: LEDGER_TOOLS.split(' ')});
        assert.deepEqual(result.operands.map(({path, kind}) => ({path, kind})), [
          {path: 'C:/plugin/scripts/ledger.mjs', kind: 'transport'}, {path: repository, kind: 'ledger-root'},
        ]);
      }
      const repeated = windowsCommandOperands(command + ` note task '${repository}'`, {dialect, ledgerTools: LEDGER_TOOLS.split(' ')});
      assert.deepEqual(repeated.operands.map(operand => operand.kind), ['transport', 'ledger-root', 'target']);
      assert.equal(repeated.operands.at(-1).path, repository);
      for (const tail of [` > '${repository}'`, `; echo fixture > '${repository}'`]) assert.equal(windowsCommandOperands(command + ' show task' + tail, {dialect, ledgerTools: LEDGER_TOOLS.split(' ')}), null);
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
  assert.equal(count, 11); console.log(`PASS hook policy: ${count} judgments`);
} finally { fs.rmSync(temp, {recursive: true, force: true}); }
