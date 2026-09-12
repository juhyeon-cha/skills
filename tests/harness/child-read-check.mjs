import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {evaluateGuard} from '../../plugins/harness/lib/guard/guard.mjs';

const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'child-read-'));
try {
  const env = {...process.env, HARNESS_RUNTIME: 'codex', HARNESS_DATA_DIR: temp};
  for (const key of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE']) delete env[key];
  assert.equal(spawnSync('git', ['init', '-q', temp], {env}).status, 0);
  const base = {cwd: temp, session_id: 'review', agent_id: '/root/reviewer',
    tool_name: 'Read', tool_input: {file_path: path.join(temp, 'source.md')}};
  let metadataCalls = 0;
  const guard = (changes = {}) => evaluateGuard({...base, ...changes}, {env,
    readThread: async () => { metadataCalls++; throw Error('metadata unavailable'); }});
  for (const identity of [
    {}, {agent_id: '01a093ff-1e5b-7302-9ed5-8ba5379852bb', agent_type: 'default'},
    {session_id: undefined},
  ]) {
    for (const action of [
      {}, {tool_name: 'Grep', tool_input: {pattern: 'role'}},
      {tool_name: 'exec_command', tool_input: {cmd: 'rg --files 2>/dev/null | head -40'}},
      {tool_name: 'exec_command', tool_input: {cmd: 'git diff HEAD~1...HEAD --stat'}},
      {tool_name: 'PowerShell', tool_input: {command: 'git.exe diff HEAD~1...HEAD --stat'}},
      {tool_name: 'PowerShell', tool_input: {command: 'Get-Content source.md'}},
      {tool_name: 'exec_command', tool_input: {cmd: "git -C '/repo path' --no-pager log -3 --oneline"}},
      {tool_name: 'collaboration.send_message', tool_input: {target: '/root', message: 'Review result'}},
      // Actual Codex PreToolUse spells the internal namespace without a dot.
      {tool_name: 'collaborationsend_message', tool_input: {target: '/root', message: 'Review result'}},
    ]) {
      const result = await guard({...identity, ...action});
      assert.equal(result.code, 0, JSON.stringify({...identity, ...action}) + '\n' + result.stderr);
    }
  }
  assert.equal(metadataCalls, 0, 'read/report availability must not depend on metadata');
  for (const action of [
    {tool_name: 'Bash', tool_input: {command: 'git diff HEAD~1...HEAD --stat'}},
    {tool_name: 'collaborationsend_message', tool_input: {target: '/root', message: 'Review result'}},
  ]) {
    const hook = spawnSync(process.execPath,
      [fileURLToPath(new URL('../../plugins/harness/hooks/guard.mjs', import.meta.url))],
      {env, input: JSON.stringify({...base, agent_id: '01a093ff-1e5b-7302-9ed5-8ba5379852bb',
        agent_type: 'default', ...action}), encoding: 'utf8'});
    assert.equal(hook.status, 0, hook.stderr);
  }
  for (const changes of [
    {tool_name: 'Write', tool_input: {file_path: path.join(temp, 'changed')}},
    {tool_name: 'exec_command', tool_input: {cmd: 'git commit -m changed'}},
    {tool_name: 'exec_command', tool_input: {cmd: 'git push origin HEAD'}},
    {tool_name: 'exec_command', tool_input: {cmd: 'git diff --output=/tmp/changed'}},
    {tool_name: 'exec_command', tool_input: {cmd: 'git diff --out=/tmp/changed'}},
    {tool_name: 'PowerShell', tool_input: {command: 'git.exe diff --output=changed'}},
    {tool_name: 'exec_command', tool_input: {cmd: 'git -c alias.inspect=push inspect'}},
    {tool_name: 'exec_command', tool_input: {cmd: 'git diff; rm -rf /tmp/changed'}},
    {tool_name: 'exec_command', tool_input: {cmd: 'git diff > /tmp/changed'}},
    {tool_name: 'exec_command', tool_input: {cmd: 'git diff --ext-diff'}},
    {tool_name: 'exec_command', tool_input: {cmd: 'rg --pre=exec x'}},
    {tool_name: 'unrecognized_tool', tool_input: {}},
    {agent_type: 'unknown'}, {agent_id: 5}, {tool_input: null},
  ]) assert.equal((await guard(changes)).code, 2, JSON.stringify(changes));
  console.log('PASS child reads: role-free reads/reporting; unknown effects and mutations still require identity');
} finally {fs.rmSync(temp, {recursive: true, force: true});}
