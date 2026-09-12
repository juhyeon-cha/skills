import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {evaluateGuard, RULES, GR_ROLES, IMPL_ROLES, BD_READ_EXEMPT, LEDGER_READ_EXEMPT, IMPL_BD_WRITE_ALLOW} from '../../plugins/harness/lib/guard/guard.mjs';
import {evaluateStop, STOP_OUTCOMES, MAX_BLOCKS} from '../../plugins/harness/lib/runtime/stop.mjs';
import {resolveState, cancelSession} from '../../plugins/harness/lib/runtime/state.mjs';
import {powershellOperations} from '../../plugins/harness/lib/guard/powershell-operations.mjs';
import {patchOperations} from '../../plugins/harness/lib/guard/operations.mjs';
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
const scoped = session => resolveState({runtime: 'claude', cwd: main, sessionId: session}, env);
const stop = (session, rows, extra = {}, options = {}) => evaluateStop({cwd: main, session_id: session, ...extra}, {env, ledger: async () => ({code: 0, stdout: JSON.stringify(rows), stderr: ''}), ...options});
const bindStopFixture = async (session, actor = '') => {
  const scope = await scoped(session);
  fs.mkdirSync(path.dirname(scope.actors), {recursive: true});
  fs.writeFileSync(scope.actors, JSON.stringify({runtime: scope.runtime, repoKey: scope.repoKey, sessionId: session, claims: [{actor: actor || 'mine', evidence: 'ledger-show'}]}));
};

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
    const file = path.join(copy, 'lib/guard/guard.mjs'); const before = fs.readFileSync(file, 'utf8');
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
    for (const suffix of [' >/dev/null-other', ' >>/dev/null', ` >${shellPath(path.join(main, 'output'))}`, ` >/dev/null; rm -rf ${shellPath(main)}`])
      assert.equal((await judge(event(`rg x ${shellPath(main)}${suffix}`))).code, 2, suffix);
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
      const gitCommand = `git -C '${main}' status`, gitResult = await judge(event(gitCommand, role, 'PowerShell'));
      assert.equal(gitResult.code, 0, gitCommand + '\n' + gitResult.stderr);
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
  await check('exact loaded native check commands accept protected repository coordinates', async () => {
    for (const tool of ['Bash', 'PowerShell']) for (const name of ['board-check', 'rules-check', 'ledger-check', 'guardrail-check']) {
      const command = `node '${path.join(root, `checks/${name}.mjs`)}' --root '${main}'`;
      const result = await evaluateGuard(event(command, 'harness:reviewer', tool), {env, pluginRoot: root});
      assert.equal(result.code, 0, command + '\n' + result.stderr);
    }
    const loaded = path.join(main, 'loaded plugin 공백'); fs.cpSync(root, loaded, {recursive: true});
    for (const tool of ['Bash', 'PowerShell']) {
      const command = `node '${path.join(loaded, 'checks/board-check.mjs')}' --root '${main}'`;
      const result = await evaluateGuard(event(command, 'harness:reviewer', tool), {env, pluginRoot: loaded});
      assert.equal(result.code, 0, 'loaded script path inside main is transport: ' + tool + '\n' + command + '\n' + result.stderr);
      assert.equal((await evaluateGuard(event(command, 'harness:reviewer', tool), {env, pluginRoot: root})).code, 2, 'another identical artifact is not the loaded entrypoint');
    }
  });
  await check('loaded root and entrypoint aliases share native filesystem identity', async () => {
    const loaded = path.join(main, 'loaded plugin 공백'), script = path.join(loaded, 'checks/board-check.mjs');
    const roots = [...new Set([loaded, fs.realpathSync(loaded), fs.realpathSync.native(loaded)])];
    const scripts = [...new Set([script, fs.realpathSync(script), fs.realpathSync.native(script)])];
    if (process.platform === 'win32') console.log('Windows loaded aliases: ' + JSON.stringify({roots, scripts}));
    for (const pluginRoot of roots) for (const entry of scripts) for (const tool of ['Bash', 'PowerShell']) {
      const command = `node '${entry}' --root '${main}'`;
      const result = await evaluateGuard(event(command, 'harness:reviewer', tool), {env, pluginRoot});
      assert.equal(result.code, 0, JSON.stringify({pluginRoot, command, tool}) + '\n' + result.stderr);
    }
  });
  await check('Bash drive and UNC operands remain protected write candidates without whitespace', async () => {
    const targets = process.platform === 'win32' ? [path.join(main, 'overwrite')] : [String.raw`C:\Users\RUNNER~1\repo\overwrite`, String.raw`\\server\share\repo\overwrite`];
    for (const target of targets) {
      // Bash consumes unquoted backslashes as escapes. Its quoted native path
      // and unquoted forward-slash drive form are actual path operands.
      for (const operand of [`'${target}'`, ...(/^[A-Za-z]:/.test(target) && !/\s/.test(target) ? [target.replaceAll('\\', '/')] : [])]) {
        const command = `echo fixture > ${operand}`, result = await judge(event(command));
        assert.equal(result.code, 2, command + '\n' + result.stderr);
      }
      assert.equal((await judge(event(`cat '${target}'`, 'harness:reviewer'))).code, 0);
    }
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
  await check('native ledger coordinates preserve reads and note permissions in both shell dialects', async () => {
    for (const tool of ['Bash', 'PowerShell']) {
      const command = `node '${path.join(main, 'plugins/harness/scripts/ledger.mjs')}' --root '${main}'`;
      for (const role of ['', 'harness:implementer', 'harness:reviewer', 'harness:evaluator']) {
        for (const sub of ['show task', 'list']) {
          const result = await judge(event(command + ' ' + sub, role, tool));
          assert.equal(result.code, 0, tool + ' ' + role + '\n' + command + ' ' + sub + '\n' + result.stderr);
        }
        const note = await judge(event(command + ' note task fixture', role, tool));
        assert.equal(note.code, ['', 'harness:implementer'].includes(role) ? 0 : 2, tool + ' ' + role + '\n' + note.stderr);
      }
      for (const tail of [` > '${path.join(main, 'overwrite')}'`, `; echo fixture > '${path.join(main, 'overwrite')}'`]) {
        const result = await judge(event(command + ' show task' + tail, '', tool));
        assert.equal(result.code, 2, tool + '\n' + command + tail + '\n' + result.stderr);
      }
      const target = await judge(event(`node '${path.join(main, 'writer.mjs')}' --output '${path.join(main, 'overwrite')}'`, '', tool));
      assert.equal(target.code, 2, tool + '\n' + target.stderr);
      const search = tool === 'PowerShell' ? `Select-String -Path '${main}' -Pattern 'ledger.mjs close'` : `rg -n 'ledger.mjs close' '${main}'`;
      const reading = await judge(event(search, 'harness:reviewer', tool));
      assert.equal(reading.code, 0, tool + '\n' + search + '\n' + reading.stderr);
    }
  });
  await check('common CLI coordinate exceptions preserve mutations, roles, redirects and loaded source identity', async () => {
    const invoke = (relative, args) => `node '${path.join(root, relative)}' ${args}`;
    const judgeCommand = (command, role = '', tool = 'Bash', extra = {}) => evaluateGuard(event(command, role, tool), {env: {...env, ...extra}, pluginRoot: root});
    for (const tool of ['Bash', 'PowerShell']) {
      for (const command of [
        invoke('checks/workspace-check.mjs', `'${main}'`),
        invoke('scripts/config.mjs', `validate '${main}'`),
        invoke('scripts/guard-log.mjs', `--runtime claude --data '${main}' --repo '${main}' rows session`),
        invoke('scripts/transcript.mjs', `--scope '${path.join(main, 'scope.json')}' --json`),
        invoke('scripts/state.mjs', `--data '${main}' paths claude '${main}' session`),
      ]) assert.equal((await judgeCommand(command, 'harness:reviewer', tool)).code, 0, command);
      const projection = invoke('scripts/board.mjs', `--root '${main}' all`);
      assert.equal((await judgeCommand(projection, '', tool)).code, 0, projection);
      for (const role of ['harness:implementer', 'harness:reviewer', 'harness:evaluator']) assert.equal((await judgeCommand(projection, role, tool)).code, 2, role);
      const remote = invoke('checks/ledger-check.mjs', `--root '${main}' --push`);
      assert.equal((await judgeCommand(remote, '', tool)).code, 0);
      assert.equal((await judgeCommand(remote, 'harness:implementer', tool)).code, 2);
      assert.equal((await judgeCommand(invoke('checks/ledger-check.mjs', `--root '${main}'`), 'harness:implementer', tool, {LEDGER_CHECK_PUSH: '1'})).code, 2);
      for (const repository of [main, workspace]) {
        const gate = invoke('scripts/config.mjs', `run '${repository}' check`);
        assert.equal((await judgeCommand(gate, 'harness:reviewer', tool)).code, repository === main ? 2 : 0, gate);
      }
      assert.equal((await judgeCommand(invoke('scripts/config.mjs', `run '${workspace}' bootstrap`), 'harness:reviewer', tool)).code, 2);
      for (const action of [`bind claude '${main}' session '${main}' task actor`, `cancel claude '${main}' session`]) {
        const safe = invoke('scripts/state.mjs', `--data '${env.HARNESS_DATA_DIR}' ${action}`);
        assert.equal((await judgeCommand(safe, '', tool)).code, 0, safe);
        assert.equal((await judgeCommand(safe, 'harness:reviewer', tool)).code, 2, safe);
        assert.equal((await judgeCommand(invoke('scripts/state.mjs', `--data '${main}' ${action}`), '', tool)).code, 2);
      }
      const read = invoke('checks/board-check.mjs', `--root '${main}'`);
      for (const command of [read + ` > '${path.join(main, 'overwrite')}'`, read + `; Set-Content '${path.join(main, 'overwrite')}' x`, projection + ` > '${path.join(main, 'overwrite')}'`, read + ' --unknown']) assert.equal((await judgeCommand(command, '', tool)).code, 2, command);
      const fake = path.join(temp, 'spoof', 'board-check.mjs'); fs.mkdirSync(path.dirname(fake), {recursive: true}); fs.copyFileSync(path.join(root, 'checks/board-check.mjs'), fake);
      assert.equal((await judgeCommand(`node '${fake}' --root '${main}'`, '', tool)).code, 2, 'same basename/content is not loaded identity');
    }
  });
  const outcomes = new Set();
  const capture = result => { result.outcomes.forEach(outcome => outcomes.add(outcome)); return result; };
  await check('Stop recursion, cancellation and legacy marker ownership', async () => {
    assert.equal(capture(await stop('recursive', [], {stop_hook_active: true})).stdout, '');
    const scope = await scoped('cancelled'); cancelSession(scope);
    assert.equal(capture(await stop('cancelled', [{id: 't'}])).stdout, '');
    fs.writeFileSync(path.join(env.HARNESS_DATA_DIR, 'stop-resume-cancel'), 'legacy');
    const unknown = capture(await stop('other', [{id: 't'}]));
    assert.equal(unknown.stdout, ''); assert.deepEqual(unknown.outcomes, ['SCOPE_FAIL']); assert.match(unknown.stderr, /completion not established/);
    assert.equal(fs.readFileSync(path.join(env.HARNESS_DATA_DIR, 'stop-resume-cancel'), 'utf8'), 'legacy');
  });
  await check('Stop oracle failure never becomes idle and zero work is explicit', async () => {
    const failed = capture(await stop('oracle', [], {}, {ledger: async () => ({code: 1, stdout: ''})})); assert.deepEqual(failed.outcomes, ['ORACLE_FAIL']);
    const malformed = capture(await stop('malformed', [], {}, {ledger: async () => ({code: 0, stdout: '{}'})})); assert.deepEqual(malformed.outcomes, ['ORACLE_FAIL']);
    await bindStopFixture('idle');
    const idle = capture(await stop('idle', [])); assert.ok(idle.outcomes.includes('IDLE')); assert.equal(idle.stdout, '');
  });
  await check('Stop verified actor narrows only matching runtime/repository/session', async () => {
    const scope = await scoped('actor'); fs.mkdirSync(path.dirname(scope.actors), {recursive: true});
    fs.writeFileSync(scope.actors, JSON.stringify({runtime: scope.runtime, repoKey: scope.repoKey, sessionId: scope.sessionId, claims: [{actor: 'mine', evidence: 'ledger-show'}]}));
    const result = capture(await stop('actor', [{actor: 'other', notes: ''}])); assert.deepEqual(result.outcomes, ['IDLE']);
    fs.writeFileSync(scope.actors, JSON.stringify({runtime: 'codex', repoKey: scope.repoKey, sessionId: scope.sessionId, claims: [{actor: 'mine', evidence: 'ledger-show'}]}));
    const foreign = capture(await stop('actor', [{actor: 'other', notes: ''}])); assert.deepEqual(foreign.outcomes, ['SCOPE_FAIL']); assert.equal(foreign.stdout, '');
    fs.writeFileSync(scope.actorRecovery, JSON.stringify({runtime: scope.runtime, repoKey: scope.repoKey, sessionId: scope.sessionId, claims: [{task: 't', actor: 'mine', evidence: 'ledger-show'}]}));
    const recovered = capture(await stop('actor', [{id: 't', status: 'in_progress', actor: 'mine', notes: ''}]));
    assert.deepEqual(recovered.outcomes, ['SCOPE_RECOVERED', 'BLOCK']);
  });
  await check('Stop last marker survives prose, mixed marks pass, unmarked work blocks and cap terminates', async () => {
    for (const session of ['pending', 'bounded']) await bindStopFixture(session, 'mine');
    const pending = capture(await stop('pending', [{actor: 'mine', notes: 'DELEGATED: m\nVERIFY_PENDING: abc\nreview evidence'}, {actor: 'mine', notes: 'VERIFY_PENDING: old\nDELEGATED: m\nprose'}])); assert.ok(pending.outcomes.includes('VERIFY_PENDING')); assert.equal(pending.stdout, '');
    for (let i = 0; i < MAX_BLOCKS; i++) assert.equal(JSON.parse(capture(await stop('bounded', [{actor: 'mine', notes: ''}, {actor: 'mine', notes: 'VERIFY_PENDING: a'}])).stdout).decision, 'block');
    const done = capture(await stop('bounded', [{actor: 'mine', notes: ''}])); assert.ok(done.outcomes.includes('GAVE_UP')); assert.equal(done.stdout, '');
    assert.deepEqual([...outcomes].sort(), [...STOP_OUTCOMES].sort());
  });
  await check('Stop both marker checks have live independent negative controls', async () => {
    for (const [marker, line, notes] of [['VERIFY_MARK', 'const vp = 0;', 'VERIFY_PENDING: abc'], ['DELEGATED_MARK', 'const dg = 0;', 'DELEGATED: milestone']]) {
      const copy = path.join(temp, marker); fs.cpSync(root, copy, {recursive: true}); const file = path.join(copy, 'lib/runtime/stop.mjs');
      const before = fs.readFileSync(file, 'utf8'); const after = before.split('\n').map(value => value.includes('// ' + marker) ? '  ' + line : value).join('\n'); assert.notEqual(after, before); fs.writeFileSync(file, after);
      const mutant = await import(pathToFileURL(file).href);
      await bindStopFixture(marker); await bindStopFixture(marker + '-control');
      const result = await mutant.evaluateStop({cwd: main, session_id: marker}, {env, ledger: async () => ({code: 0, stdout: JSON.stringify([{actor: 'mine', notes}])})}); assert.equal(JSON.parse(result.stdout).decision, 'block');
      assert.equal((await stop(marker + '-control', [{actor: 'mine', notes}])).stdout, '');
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
