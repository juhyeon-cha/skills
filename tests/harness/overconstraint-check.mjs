import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {isReadonlySearch} from '../../plugins/harness/lib/guard/operations.mjs';
import {registerRoles, verifyRegistration} from '../../plugins/harness/lib/runtime/roles.mjs';
import {resolveState} from '../../plugins/harness/lib/runtime/state.mjs';
import {evaluateStop} from '../../plugins/harness/lib/runtime/stop.mjs';

const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'overconstraint-'));
try {
  for (const command of [
    "rg --files -g AGENTS.md -g CLAUDE.md '/clone parent' 2>/dev/null | head -40; cat '/main/x'",
    'rg pattern /repo > /dev/null', 'cat /repo/x 1>/dev/null 2>/dev/null',
  ]) assert.equal(isReadonlySearch(command), true, command);
  for (const command of [
    'rg x /repo >/dev/null-other', 'rg x /repo >>/dev/null', 'rg x /repo >/repo/file',
    'rg x /repo >/dev/null; rm -rf /repo', 'rg --pre=exec /repo 2>/dev/null',
    'rg x $(touch /repo/file) 2>/dev/null', 'cat /repo < /dev/null',
    'cat /repo 2>&1', 'rg x /repo >"/dev/null"',
  ]) assert.equal(isReadonlySearch(command), false, command);

  const directory = path.join(temp, 'agents');
  const registration = registerRoles('codex', directory);
  const foreign = path.join(directory, 'foreign.toml');
  const accepted = [
    'name = "foreign"\ncount = 3\nenabled = true\nvalues = [1,\n2, {key = "value"}]\n[tools]\nname = "harness-reviewer"\n',
    'name = "foreign"\ndeveloper_instructions = """\nname = "harness-reviewer"\n[table]\n"""\n',
    "developer_instructions = '''\nname = 'harness-reviewer'\n'''\nname = 'foreign'\n",
    'values = [\'name = "fake"\', "#", {name = "nested"}]\nname = "foreign"\n',
  ];
  for (const text of accepted) {
    fs.writeFileSync(foreign, text);
    verifyRegistration(registration);
  }
  const collision = registration.roles[0].identifier;
  for (const text of [
    `"name" = "${collision}"\n`,
    `"na\\u006de" = "${collision}"\n`,
    `values = [1,\n 2]\nname = "${collision}"\n`,
    'name = "foreign"\nname = "second"\n',
    'name = "foreign"\nvalue = """unfinished\n',
    'name = "foreign"\nvalue = [1, 2\n',
    `name = "${collision}"\nvalue = true\n`,
  ]) {
    fs.writeFileSync(foreign, text);
    assert.throws(() => verifyRegistration(registration), undefined, text);
  }
  fs.rmSync(foreign);
  fs.appendFileSync(registration.roles[0].file, '# drift\n');
  assert.throws(() => verifyRegistration(registration));

  const repo = path.join(temp, 'repo'); fs.mkdirSync(repo);
  const env = {...process.env, HARNESS_RUNTIME: 'claude', HARNESS_DATA_DIR: path.join(temp, 'data')};
  for (const key of ['PLUGIN_ROOT', 'PLUGIN_DATA', 'CLAUDE_PLUGIN_DATA', 'GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR']) delete env[key];
  const git = (...args) => {
    const result = spawnSync('git', ['-C', repo, ...args], {env, encoding: 'utf8'});
    assert.equal(result.status, 0, result.stderr);
  };
  git('init', '-q');
  const scope = await resolveState({runtime: 'claude', cwd: repo, sessionId: 'owned'}, env);
  fs.mkdirSync(scope.session, {recursive: true});
  const record = {runtime: scope.runtime, repoKey: scope.repoKey, sessionId: scope.sessionId,
    claims: [{task: 't', actor: 'mine', evidence: 'ledger-show'}]};
  const rows = [{id: 't', status: 'in_progress', actor: 'mine', notes: ''}];
  const stop = () => evaluateStop({cwd: repo, session_id: scope.sessionId}, {
    env, rootFinder: async () => repo,
    ledger: async () => ({code: 0, stdout: JSON.stringify(rows)}),
  });
  let result = await stop();
  assert.deepEqual(result.outcomes, ['SCOPE_FAIL']);
  assert.equal(result.stdout, ''); assert.match(result.stderr, /completion not established/);
  fs.writeFileSync(scope.actorRecovery, JSON.stringify(record));
  fs.writeFileSync(scope.actors, '{broken');
  result = await stop();
  assert.deepEqual(result.outcomes, ['SCOPE_RECOVERED', 'BLOCK']);
  assert.equal(JSON.parse(result.stdout).decision, 'block');
  assert.deepEqual(JSON.parse(fs.readFileSync(scope.actors)), record);
  for (const changed of [
    {...record, runtime: 'codex'}, {...record, repoKey: 'other'}, {...record, sessionId: 'other'},
    {...record, claims: [{task: 't', actor: 'other', evidence: 'ledger-show'}]},
    {...record, claims: [{task: 't', actor: 'mine', evidence: 'command-text'}]},
    {...record, claims: [...record.claims, {task: 'missing', actor: 'second', evidence: 'ledger-show'}]},
  ]) {
    fs.rmSync(scope.actors, {force: true});
    fs.writeFileSync(scope.actorRecovery, JSON.stringify(changed));
    result = await stop();
    assert.deepEqual(result.outcomes, ['SCOPE_FAIL']); assert.equal(result.stdout, '');
    assert.equal(fs.existsSync(scope.actors), false);
  }
  fs.writeFileSync(scope.actorRecovery, JSON.stringify(record));
  rows[0].actor = 'reassigned';
  assert.deepEqual((await stop()).outcomes, ['SCOPE_FAIL']);
  assert.match(fs.readFileSync(scope.stopLog, 'utf8'), /SCOPE_FAIL/);
  console.log('PASS overconstraint: read-only boundaries, foreign TOML names, scoped ownership recovery; offline fixtures');
} finally { fs.rmSync(temp, {recursive: true, force: true}); }
