import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {normalizePath, patchOperations, isReadonlySearch} from '../../plugins/harness/lib/operations.mjs';
import {normalizeHookEvent} from '../../plugins/harness/lib/hook-event.mjs';

const root = fileURLToPath(new URL('../../plugins/harness', import.meta.url));
const temp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'operation-policy-')));
let count = 0;
const check = (value, why) => { assert.ok(value, why); count++; };
const run = (cmd, args, options = {}) => spawnSync(cmd, args, {encoding: 'utf8', ...options});
try {
  const repo = path.join(temp, '공백 repo'); fs.mkdirSync(repo);
  const env = {...process.env, HOME: temp, CLAUDE_PLUGIN_ROOT: root, GIT_CONFIG_GLOBAL: os.devNull, GIT_CONFIG_NOSYSTEM: '1'};
  env.HARNESS_GUARD_LOG = path.join(temp, 'guard.tsv');
  env.HARNESS_SESSION_ACTOR_LOG = path.join(temp, 'actors.tsv');
  for (const key of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'HARNESS_ROOT']) delete env[key];
  const git = (...args) => { const r = run('git', ['-C', repo, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', ...args], {env}); assert.equal(r.status, 0, r.stderr); };
  git('init', '-q'); fs.writeFileSync(path.join(repo, '.harness.json'), '{"ledger":{"backend":"github"}}'); git('add', '.'); git('commit', '-qm', 'fixture');
  const wt = path.join(repo, '.claude/worktrees/story'); git('worktree', 'add', '-q', '-b', 'worktree-story', wt);
  const event = (tool_name, tool_input, extra = {}) => ({tool_name, tool_input, cwd: wt, ...extra});
  const guard = (e, overrides = {}) => run('/bin/bash', [path.join(root, 'hooks/guard.sh')], {cwd: wt, env: {...env, ...overrides}, input: JSON.stringify(e)});
  const patch = text => `*** Begin Patch\n${text}\n*** End Patch`;
  const multi = patch('*** Add File: 한글 새 파일\n+one\n*** Update File: old\n*** Move to: moved file\n@@\n-old\n+new\n*** Delete File: obsolete');
  const ops = patchOperations(multi.replaceAll('\n', '\r\n'), wt);
  check(ops.length === 3 && ops[0].kind === 'create' && ops[1].kind === 'move' && ops[2].kind === 'delete', 'CRLF multi-file operations');
  check(ops[1].source === path.join(wt, 'old') && ops[1].destination === path.join(wt, 'moved file'), 'move has both endpoints');
  check(guard(event('apply_patch', {command: multi})).status === 0, 'allowed multi-file patch');
  check(guard(event('apply_patch', {command: patch('*** Add File: empty')})).status === 0, 'empty added file is supported by apply_patch');
  for (const text of [
    `*** Add File: ${repo}/blocked\n+x`,
    `*** Delete File: ${repo}/blocked`,
    `*** Update File: ${repo}/blocked\n@@\n-a\n+b`,
    `*** Update File: ${repo}/blocked\n*** Move to: ${wt}/ok\n@@\n-a\n+b`,
    `*** Update File: ${wt}/ok\n*** Move to: ${repo}/blocked\n@@\n-a\n+b`,
    `*** Add File: ${wt}/ok\n+x\n*** Delete File: ${repo}/blocked`,
  ]) check(guard(event('apply_patch', {command: patch(text)})).status === 2, `protected/mixed operation ${text}`);
  for (const role of ['harness:reviewer', 'harness-evaluator']) check(guard(event('apply_patch', {command: multi}, {agent_id: 'child', agent_type: role})).status === 2, `grader ${role}`);
  check(guard(event('apply_patch', {command: multi}, {agent_id: 'child', agent_type: 'harness-implementer'})).status === 0, 'canonical implementer mapping');
  for (const command of [`rg 'git push; rm -rf ${repo}' '${repo}/x'`, `grep '$(git push)' '${repo}/x'`, `rg needle '${repo}/x' | head -1`]) {
    check(isReadonlySearch(command), 'literal search identified');
    check(guard(event('Bash', {command})).status === 0, 'literal search allowed');
  }
  for (const command of [`rg x '${repo}/x' > '${repo}/out'`, `rg --pre='rm' '${repo}/x'`, `rg "$(touch '${repo}/x')" '${repo}/x'`, `rg x '${repo}/x'; touch '${repo}/x'`, `rg --search-zip '${repo}/x'`, `rg --hostname-bin=touch '${repo}/x'`]) {
    check(!isReadonlySearch(command), 'execution/redirect is not readonly');
    check(guard(event('Bash', {command})).status === 2, `write or indirect command remains conservative: ${command}`);
  }
  // Execute only disposable preprocessing canaries: prove that shell expansion
  // can turn apparently harmless options into rg's executable --pre option.
  const preBin = path.join(temp, 'pre-bin'); fs.mkdirSync(preBin);
  fs.writeFileSync(path.join(preBin, 'pre'), '#!/bin/sh\nprintf invoked > "$PRE_CANARY"\ncat "$1"\n', {mode: 0o755});
  fs.writeFileSync(path.join(wt, '--pre=pre'), '');
  fs.writeFileSync(path.join(repo, 'input'), 'needle\n');
  const expansions = ['--pre{,}=pre', '--pr?=*', '--pr[e]=pre'];
  const observations = expansions.map(option => {
    const command = `rg ${option} needle '${repo}/input'`;
    const canary = path.join(temp, `canary-${expansions.indexOf(option)}`);
    const probeEnv = {...env, PATH: `${preBin}:${env.PATH}`, PRE_CANARY: canary};
    delete probeEnv.RIPGREP_CONFIG_PATH;
    const actual = run('/bin/bash', ['-c', command], {cwd: wt, env: probeEnv});
    check(actual.status === 0 && fs.existsSync(canary), `actual preprocessor canary: ${option}`);
    const guarded = guard(event('Bash', {command}), probeEnv);
    console.log(`expansion canary ${option}: execution=${actual.status}, canary=${fs.existsSync(canary)}, guard=${guarded.status}`);
    return {command, guarded};
  });
  for (const {command, guarded} of observations) {
    check(!isReadonlySearch(command), `expanded option is not readonly: ${command}`);
    check(guarded.status === 2, `expanded executable option denies: ${command}`);
  }
  for (const syntax of ['{a,b}', '*', '?', '[ab]', '~', '$HOME', '$(pwd)', '`pwd`', '<(pwd)', '>(cat)', '$((1+1))']) {
    check(!isReadonlySearch(`rg ${syntax} file`), `unquoted expansion excluded: ${syntax}`);
  }
  for (const literal of ["'{a,b} * ? [ab] ~ $HOME $(pwd) `pwd`'", '"{a,b} * ? [ab] ~"']) {
    const command = `rg ${literal} '${repo}/input'`;
    check(isReadonlySearch(command), 'quoted expansion characters remain literal');
    check(guard(event('Bash', {command})).status === 0, 'quoted literal search allowed');
  }
  check(normalizeHookEvent(event('exec_command', {cmd: 'pwd'})).tool_name === 'Bash', 'exec_command maps to Bash');
  for (const extra of [{agent_type: false}, {agent_id: 0}, {cwd: '.'}]) check(guard(event('Bash', {command: 'pwd'}, extra)).status === 2, 'malformed identity/cwd fails closed');
  for (const e of [event('apply_patch', {command: 'unknown'}), event('apply_patch', {command: patch('')}), event('apply_patch', {command: patch('*** Unknown File: x')}), event('Write', {}), event('Bash', {}), event('Bash', {command: 'pwd'}, {agent_id: 'child'}), event('Bash', {command: 'pwd'}, {agent_type: 'unknown'}), {...event('Bash', {command: 'pwd'}), cwd: ''}]) check(guard(e).status === 2, 'unknown/missing input fails closed');
  check(normalizePath('..\\한글 file', 'C:\\work\\story') === 'C:\\work\\한글 file', 'drive lexical path');
  check(normalizePath('..\\한글 file', '\\\\server\\share\\story') === '\\\\server\\share\\한글 file', 'UNC lexical path');
  check(patchOperations(patch('*** Add File: C:\\work\\한글 file\n+x'), 'C:\\work')[0].path === 'C:\\work\\한글 file', 'Windows patch path');
  assert.throws(() => normalizePath('C:relative', 'C:\\work'));
  for (const missing of ['node', 'jq']) {
    const bin = path.join(temp, `no-${missing}`); fs.mkdirSync(bin);
    for (const name of ['cat', 'dirname', 'grep', 'env', ...(missing === 'node' ? ['jq'] : ['node'])]) {
      const located = run('which', [name]); assert.equal(located.status, 0); fs.symlinkSync(located.stdout.trim(), path.join(bin, name));
    }
    const result = guard(event('Bash', {command: 'pwd'}), {PATH: bin});
    check(missing === 'node' ? result.status === 2 && result.stderr.includes(missing) : result.status === 0, missing === 'node' ? 'missing node denies' : 'missing jq does not affect native policy');
  }
  const badJq = path.join(temp, 'bad-jq'); fs.mkdirSync(badJq);
  const canary = path.join(badJq, 'executed');
  for (const predicate of ['*harness_operations*', '*tool_name*']) {
    fs.writeFileSync(path.join(badJq, 'jq'), `#!/bin/sh\necho called > '${canary}'\nexit 23\n`, {mode: 0o755});
    check(guard(event('apply_patch', {command: patch(`*** Add File: ${repo}/blocked\n+x`)}), {PATH: `${badJq}:${env.PATH}`}).status === 2, `protected patch denies independently of unavailable jq ${predicate}`);
    check(guard(event('apply_patch', {command: multi}), {PATH: `${badJq}:${env.PATH}`}).status === 0, 'allowed patch works independently of unavailable jq');
    check(guard(event('Bash', {command: 'pwd'}), {PATH: `${badJq}:${env.PATH}`}).status === 0 && !fs.existsSync(canary), 'read policy does not invoke jq');
  }
  console.log(`PASS operation policy: ${count} assertions; direct script and lexical Windows fixtures only`);
} finally { fs.rmSync(temp, {recursive: true, force: true}); }
