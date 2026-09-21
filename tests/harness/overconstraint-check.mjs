import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {isReadonlySearch} from '../../plugins/harness/lib/guard/operations.mjs';
import {registerRoles, verifyRegistration, projectRole} from '../../plugins/harness/lib/runtime/roles.mjs';
import {inspectDistribution, generateDistribution} from '../../plugins/harness/lib/distribution.mjs';
import {fileURLToPath} from 'node:url';
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

  const root = fileURLToPath(new URL('../../plugins/harness', import.meta.url));
  const fixture = path.join(temp, 'native-source'); fs.cpSync(root, fixture, {recursive: true});
  for (const runtime of ['claude', 'codex', 'antigravity']) {
    const file = path.join(fixture, 'native', runtime, `reviewer.${runtime === 'codex' ? 'toml' : 'md'}`);
    const original = fs.readFileSync(file, 'utf8');
    const marker = runtime === 'codex' ? '# HARNESS_ROLE_INSTRUCTIONS' : '<!-- HARNESS_ROLE_INSTRUCTIONS -->';
    const invalid = [original.replace(marker, ''), original + '\n' + marker,
      runtime === 'codex' ? original.replace(marker, `[nested]\n${marker}`) : original.replace(marker, '').replace('name:', `${marker}\nname:`)];
    if (runtime === 'codex') invalid.push(original.replace(marker, `developer_instructions = "extra"\n${marker}`),
      original.replace(marker, `"developer_\\u0069nstructions" = "extra"\n${marker}`),
      original.replace(marker, `harness_instruction_slot = true\ninstructions = """\n${marker}\n"""`));
    for (const text of invalid) {
      fs.writeFileSync(file, text);
      assert.throws(() => projectRole(runtime, 'reviewer', fixture));
    }
    fs.writeFileSync(file, original.replaceAll('\n', '\r\n'));
    assert.ok(projectRole(runtime, 'reviewer', fixture).text.includes('SIGNAL:'));
    const extra = runtime === 'codex' ? 'experimental_value = [1, 2]\n' : 'custom_native_field: preserved\n';
    fs.writeFileSync(file, original.replace(runtime === 'codex' ? marker : 'name:', runtime === 'codex' ? extra + marker : extra + 'name:'));
    assert.ok(projectRole(runtime, 'reviewer', fixture).text.includes(extra));
    if (runtime === 'antigravity') {
      fs.writeFileSync(file, original.replace('model: inherit', 'model: pro'));
      assert.match(projectRole(runtime, 'reviewer', fixture, fixture, {availableTools: ['view_file', 'run_command', 'send_message']}).text, /model: pro/);
      assert.match(projectRole(runtime, 'reviewer', fixture, fixture, {modelOptions: {model: 'flash'}}).text, /model: flash/);
    }
    fs.writeFileSync(file, original);
  }
  const canonical = path.join(fixture, 'roles/reviewer.md');
  const originalBody = fs.readFileSync(canonical, 'utf8');
  const special = '\nLiteral $& $` $\' quotes " slash \\ and newline\n';
  fs.writeFileSync(canonical, originalBody + special);
  const installedRoot = '/path with spaces/"quoted"/$&';
  for (const runtime of ['claude', 'codex', 'antigravity']) {
    const text = projectRole(runtime, 'reviewer', fixture, installedRoot).text;
    const body = runtime === 'codex' ? JSON.parse(/^developer_instructions = (.+)$/m.exec(text)[1]) : text;
    assert.ok(body.endsWith(special));
    assert.ok(body.includes(runtime === 'claude' ? '${CLAUDE_PLUGIN_ROOT}' : installedRoot));
  }
  assert.throws(() => inspectDistribution(fixture), /generated drift/);
  generateDistribution(fixture);
  const native = path.join(fixture, 'native/claude/reviewer.md');
  fs.appendFileSync(native, '\n');
  assert.throws(() => inspectDistribution(fixture), /generated drift/);
  console.log('PASS native slots reject missing, duplicate, misplaced and assigned instructions; body bytes and stale output');

  const directory = path.join(temp, 'agents');
  const registration = registerRoles('codex', directory);
  const foreign = path.join(directory, 'foreign.toml');
  const accepted = [
    'name = "foreign"\ncount = 3\nenabled = true\nvalues = [1,\n2, {key = "value"}]\n[tools]\nname = "harness-reviewer"\n',
    'name = "foreign"\ndeveloper_instructions = """\nname = "harness-reviewer"\n[table]\n"""\n',
    "developer_instructions = '''\nname = 'harness-reviewer'\n'''\nname = 'foreign'\n",
    'values = [\'name = "fake"\', "#", {name = "nested"}]\nname = "foreign"\n',
    'name = "foreign"\nfoo.bar = 1\n"other" . \'name\' = "harness-reviewer"\n',
    '"foo.bar" = true\nname = "foreign"\n',
    'name = "foreign"\nfoo."bar\\U0001F600" = 1\n',
    '"foo\\U0001F600" = 1\nname = "foreign"\n',
    'name = "literal\\\\U0001F600"\n',
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
    `foo.name = "foreign"\n"name" = "${collision}"\n`,
    `"na\\U0000006de" = "${collision}"\n`,
    `name = "\\U00000068${collision.slice(1)}"\n`,
    'name = "\\U00110000"\n',
    'name = "\\U0000D800"\n',
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
  assert.deepEqual(result.outcomes, ['SCOPE_RECOVERED', 'NOTICE']);
  assert.equal(result.stdout, '');
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
