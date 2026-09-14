import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {evaluateGuard, GR_ROLES, IMPL_ROLES} from '../../plugins/harness/lib/guard/guard.mjs';

import {patchOperations} from '../../plugins/harness/lib/guard/operations.mjs';

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

try {
  if (process.argv[2]) assert.equal(process.platform, process.argv[2], 'actual host must match requested host');
  git('init', '-q', main);
  fs.writeFileSync(path.join(main, '.harness.json'), JSON.stringify({ledger: {backend: 'beads'}}));
  git('-C', main, 'add', '.harness.json');
  git('-C', main, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture');
  git('-C', main, 'worktree', 'add', '-qb', 'worktree-fixture', workspace);
  await check('main versus registered workspace file permissions for all roles', async () => {
    for (const role of ['', ...IMPL_ROLES.split(' '), ...GR_ROLES.split(' ')]) {
      assert.equal((await judge(write(path.join(main, 'a'), role))).code, 2);
      assert.equal((await judge(write(path.join(workspace, 'a'), role))).code, GR_ROLES.split(' ').includes(role) ? 2 : 0);
    }
  });
  await check('configuration edits and path data are allowed while concrete protected writes stay denied', async () => {
    for (const relative of ['.harness.json', '.agents/rules.md', '.claude/settings.json', '.codex/config.toml']) {
      assert.equal((await judge(write(path.join(workspace, relative)))).code, 0, relative);
      assert.equal((await judge(write(path.join(main, relative)))).code, 2, relative);
    }
    for (const target of [path.join(workspace, '.git'), path.join(env.HARNESS_DATA_DIR, 'active.json')]) {
      assert.equal((await judge(write(target))).code, 2, target);
      assert.equal((await judge(event(`echo x > '${target}'`))).code, 2, target);
    }
    for (const command of [
      `python3 -c 'print("${main}")'`,
      `git commit -m 'document ${main}'`,
      `node script.mjs --input '${main}'`,
      `echo '${main}' > '${path.join(workspace, 'note')}'`,
      `cp '${path.join(main, 'source')}' '${path.join(workspace, 'copy')}'`,
      `touch -r '${path.join(main, 'source')}' '${path.join(workspace, 'stamp')}'`,
      `touch --reference='${path.join(main, 'source')}' '${path.join(workspace, 'stamp')}'`,
      `cp -t "$DEST" '${path.join(main, 'source')}'`,
      `cp --target-directory="$DEST" '${path.join(main, 'source')}'`,
    ]) assert.equal((await judge(event(command))).code, 0, command);
    for (const command of [
      `echo x >> '${path.join(main, 'file')}'`,
      `rm -rf '${main}'`,
      `rm -rf '${path.dirname(main)}'`,
      `cp '${path.join(workspace, 'source')}' '${path.join(main, 'copy')}'`,
      `cp -t '${main}' '${path.join(workspace, 'source')}'`,
      `cp --target-directory='${main}' '${path.join(workspace, 'source')}'`,
      `mv '${path.join(main, 'source')}' '${path.join(workspace, 'moved')}'`,
      `cat '${main}'; echo x > '${path.join(main, 'file')}'`,
    ]) assert.equal((await judge(event(command))).code, 2, command);
    const continueCommand = `node '${path.join(root, 'scripts/state.mjs')}' --data '${env.HARNESS_DATA_DIR}' continue claude '${main}' session`;
    assert.equal((await evaluateGuard(event(continueCommand), {env, pluginRoot: root})).code, 0);
    assert.equal((await evaluateGuard(event(continueCommand, 'harness:reviewer'), {env, pluginRoot: root})).code, 2);
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
      assert.equal((await evaluateGuard(event(command, 'harness:reviewer', tool), {env, pluginRoot: root})).code, 0, 'opaque script coordinates are not writes');
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
      assert.equal(target.code, 0, tool + '\n' + target.stderr);
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
      for (const command of [read + ` > '${path.join(main, 'overwrite')}'`, read + `; echo x > '${path.join(main, 'overwrite')}'`, projection + ` > '${path.join(main, 'overwrite')}'`]) assert.equal((await judgeCommand(command, '', tool)).code, 2, command);
      const fake = path.join(temp, 'spoof', 'board-check.mjs'); fs.mkdirSync(path.dirname(fake), {recursive: true}); fs.copyFileSync(path.join(root, 'checks/board-check.mjs'), fake);
      assert.equal((await judgeCommand(`node '${fake}' --root '${main}'`, '', tool)).code, 0, 'unknown scripts remain under host permissions');
    }
  });
  assert.equal(count, 8); console.log(`PASS native guard paths: ${count} judgments on ${process.platform}`);
} finally { fs.rmSync(temp, {recursive: true, force: true}); }
