import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {evaluateGuard} from '../../plugins/harness/lib/guard/guard.mjs';

const root = fileURLToPath(new URL('../../plugins/harness/', import.meta.url));
const temp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'guard-readonly-')));
const main = path.join(temp, 'repo');
const work = path.join(temp, 'work');
const env = {...process.env, HARNESS_RUNTIME: 'codex', HARNESS_DATA_DIR: path.join(temp, 'data'), GIT_CONFIG_GLOBAL: os.devNull, GIT_CONFIG_NOSYSTEM: '1'};
for (const key of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'HARNESS_ROOT', 'RIPGREP_CONFIG_PATH']) delete env[key];
const git = (...args) => {
  const result = spawnSync('git', args, {env, encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
};
const event = command => ({hook_event_name: 'PreToolUse', tool_name: 'Bash', cwd: work, tool_input: {command}});
let count = 0;
const check = async (command, code, options = {}) => {
  const result = await evaluateGuard(event(command), {pluginRoot: root, env, ...options});
  assert.equal(result.code, code, `${command}\n${result.stderr}`);
  if (code === 2) assert.equal(result.rule, 'r_main_shell');
  count++;
};
try {
  fs.mkdirSync(main);
  fs.writeFileSync(path.join(main, '.harness.json'), JSON.stringify({ledger: {backend: 'beads'}}));
  git('init', '-q', main);
  git('-C', main, 'add', '.');
  git('-C', main, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture');
  git('-C', main, 'worktree', 'add', '-qb', 'fixture', work);
  // Guard inputs exercise classification without executing the candidate commands.
  const spacedWork = path.join(temp, 'spaced work');
  git('-C', main, 'worktree', 'add', '-qb', 'spaced-fixture', spacedWork);
  const spacedData = path.join(temp, 'state data');
  const readEnv = {...env, HARNESS_DATA_DIR: spacedData};
  const readTargets = [spacedData, path.join(spacedWork, '.harness.json'),
    path.join(spacedWork, '.codex', 'config.toml'), path.join(main, 'spaced file')];
  for (const target of readTargets) {
    for (const tool_name of ['Bash', 'exec_command']) {
      for (const agent_type of ['', 'harness:implementer', 'harness:reviewer', 'harness:evaluator']) {
        const judge = command => evaluateGuard({...event(command), cwd: spacedWork, tool_name,
          ...(agent_type ? {agent_id: 'child', agent_type} : {})}, {pluginRoot: root, env: readEnv});
        for (const command of [`ls "${target}"`, `cat "${target}"; printenv`,
          `ls "${target}" | head -1`, `printenv HARNESS_RUNTIME; rg marker "${target}"`]) {
          const result = await judge(command);
          assert.equal(result.code, 0, `${command}\n${result.stderr}`);
          count++;
        }
        for (const command of [`ls "${target}" > "${target}"`, `printenv > "${target}"`,
          `cat "${target}"; touch "${target}"`]) {
          const protectedTarget = target === spacedData || target.startsWith(main + path.sep);
          assert.equal((await judge(command)).code, protectedTarget || agent_type.includes('reviewer') || agent_type.includes('evaluator') ? 2 : 0, command);
          count++;
        }
        for (const command of [`rg --pre cat marker "${target}"`, `bash /tmp/read-script.sh "${target}"`]) {
          assert.equal((await judge(command)).code, 0, command);
          count++;
        }
      }
    }
    const direct = await evaluateGuard({cwd: spacedWork, tool_name: 'Write', tool_input: {file_path: target}},
      {pluginRoot: root, env: readEnv});
    assert.equal(direct.code, target === spacedData || target.startsWith(main + path.sep) ? 2 : 0, target);
    count++;
  }
  // These are policy inputs only: no search, environment dump or destructive command executes.
  const compound = `pwd -P; stat fixture.txt; cat fixture.txt; ls -la ${temp}; cat ${main}/.codex/config.toml; printenv | rg 'HARNESS|CODEX|CLAUDE_PLUGIN'`;
  await check(`ls ${temp}`, 0);
  await check(compound, 0);
  await check(`ls ${temp}; printenv`, 0);
  await check(`ls ${temp}; rg marker fixture.txt`, 0);
  for (const target of [temp, main, `${work}/.codex/config.toml`]) {
    await check(`rg -n 'marker|other' ${target}`, 0);
    await check(`rg --files ${target}`, 0);
    for (const command of [
      `rg --pre cat marker ${target}`, `rg '--pre=cat' marker ${target}`,
      `rg --pre-glob '*.txt' --pre cat marker ${target}`,
      `rg --hostname-bin /tmp/program marker ${target}`,
      `rg --no-config --pre=cat marker ${target}`,
      `rg -z marker ${target}`, `rg -niz marker ${target}`, `rg --search-zip marker ${target}`,
      `python3 -c 'print(1)' ${target}`, `node -e 'console.log(1)' ${target}`,
      `node printenv ${target}`, `bash -c 'rg marker ${target}'`,
      `rg --pr?=cat marker ${target}`,
      `RIPGREP_CONFIG_PATH=/tmp/config rg marker ${target}`,
    ]) await check(command, 0);
    await check(`rg marker ${target}`, 0, {env: {...env, RIPGREP_CONFIG_PATH: '/tmp/config'}});
    await check(`rg --no-config marker ${target}`, 0, {env: {...env, RIPGREP_CONFIG_PATH: '/tmp/config'}});
    await check(`rg -e --no-config ${target}`, 0, {env: {...env, RIPGREP_CONFIG_PATH: '/tmp/config'}});
  }
  console.log(`PASS readonly search guard: ${count} policy assertions (commands never executed)`);
} finally {
  fs.rmSync(temp, {recursive: true, force: true});
}
