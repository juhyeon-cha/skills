import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
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
  // These are policy inputs only: no search, environment dump or destructive command executes.
  const compound = `pwd -P; cat fixture.txt; ls -la ${temp}; cat ${main}/.codex/config.toml; printenv | rg 'HARNESS|CODEX|CLAUDE_PLUGIN'`;
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
      `rg marker ${target} > ${target}`, `printenv > ${target}`,
      `ls ${target}; rm -rf ${target}`, `ls ${target}; mv ${target} /tmp/gone`,
      `python3 -c 'print(1)' ${target}`, `node -e 'console.log(1)' ${target}`,
      `node printenv ${target}`, `bash -c 'rg marker ${target}'`,
      `rg --pr?=cat marker ${target}`,
      `RIPGREP_CONFIG_PATH=/tmp/config rg marker ${target}`,
    ]) await check(command, 2);
    await check(`rg marker ${target}`, 2, {env: {...env, RIPGREP_CONFIG_PATH: '/tmp/config'}});
    await check(`rg --no-config marker ${target}`, 0, {env: {...env, RIPGREP_CONFIG_PATH: '/tmp/config'}});
    await check(`rg -e --no-config ${target}`, 2, {env: {...env, RIPGREP_CONFIG_PATH: '/tmp/config'}});
  }
  // Each omitted inventory entry independently restores the measured false positive.
  for (const word of ['rg', 'printenv']) {
    const mutant = path.join(temp, `without-${word}`);
    fs.cpSync(root, mutant, {recursive: true});
    const source = path.join(mutant, 'lib/guard/guard.mjs');
    const original = fs.readFileSync(source, 'utf8');
    const changed = original.replace(/(export const MC_READ_CMDS =\s*')([^']+)(')/, (_, before, list, after) => before + list.split(' ').filter(x => x !== word).join(' ') + after);
    assert.notEqual(changed, original);
    fs.writeFileSync(source, changed);
    const {evaluateGuard: evaluateMutant} = await import(pathToFileURL(source));
    const result = await evaluateMutant(event(compound), {env, pluginRoot: mutant});
    assert.equal(result.code, 2);
    assert.throws(() => assert.equal(result.code, 0), assert.AssertionError);
    count++;
  }
  console.log(`PASS readonly search guard: ${count} policy assertions (commands never executed)`);
} finally {
  fs.rmSync(temp, {recursive: true, force: true});
}
