import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHmac} from 'node:crypto';
import {pluginRoot, readJson, digest} from '../../plugins/harness/lib/distribution.mjs';
import {createChallenge, diagnose} from '../../plugins/harness/lib/runtime/doctor.mjs';
import {registerRoles, loadRole} from '../../plugins/harness/lib/runtime/roles.mjs';

const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'doctor-contract-'));
let count = 0;
const check = (condition, message) => { assert.ok(condition, message); count++; };
try {
  const env = {...process.env, HOME: temp, HARNESS_GUARD_LOG: path.join(temp, 'guard.tsv'), HARNESS_SESSION_ACTOR_LOG: path.join(temp, 'actors.tsv'), HARNESS_DATA_DIR: path.join(temp, 'data')};
  delete env.HARNESS_ROOT;
  for (const key of ['PLUGIN_ROOT', 'PLUGIN_DATA', 'CLAUDE_PLUGIN_DATA', 'HARNESS_RUNTIME']) delete env[key];
  const git = args => { const result = spawnSync('git', ['-C', temp, ...args], {env, encoding: 'utf8'}); assert.equal(result.status, 0, result.stderr); };
  git(['init', '-q']); fs.writeFileSync(path.join(temp, 'README'), 'fixture'); git(['add', 'README']); git(['-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture']);
  for (const runtime of ['claude', 'codex']) {
    const registration = registerRoles(runtime, path.join(temp, runtime, 'agents'));
    const state = path.join(temp, runtime, 'challenge');
    if (runtime === 'claude') fs.mkdirSync(path.join(temp, runtime));
    createChallenge(state, runtime, pluginRoot, registration);
    check(diagnose(pluginRoot, state, 'session').loaded === 'UNREACHED', `${runtime} disabled/untrusted/managed-only: no execution receipt`);
    const invoke = (id, event) => {
      const result = spawnSync(process.execPath, [path.join(pluginRoot, 'scripts/hook.mjs'), id], {cwd: temp, env: {...env, HARNESS_RUNTIME: runtime, HARNESS_DOCTOR_DIR: state}, input: JSON.stringify({session_id: 'session', cwd: temp, ...event}), encoding: 'utf8'});
      assert.equal(result.status, 0, result.stderr); return result;
    };
    invoke('context', {hook_event_name: 'SessionStart'});
    check(diagnose(pluginRoot, state, 'session').loaded === 'UNREACHED', 'context alone is not all roles/hooks');
    for (const entry of registration.roles) {
      const identity = {agent_id: `child-${entry.role}`, agent_type: entry.identifier};
      invoke('role-start', {hook_event_name: 'SubagentStart', ...identity});
      invoke('guard', {hook_event_name: 'PreToolUse', tool_name: 'Bash', tool_input: {command: 'pwd'}, ...identity});
      invoke('role-stop', {hook_event_name: 'SubagentStop', last_assistant_message: `SIGNAL: ${loadRole(entry.role).signals[0]}\nnot retained`, ...identity});
    }
    check(diagnose(pluginRoot, state, 'session').live === 'UNREACHED', 'missing Stop hook');
    invoke('stop', {hook_event_name: 'Stop'});
    const good = diagnose(pluginRoot, state, 'session'); check(good.static === 'PASS' && good.loaded === 'PASS' && good.live === 'PASS', 'direct hook fixture reaches all stages');
    check(diagnose(pluginRoot, state, 'other').loaded === 'UNREACHED', 'wrong session');
    const receipts = path.join(state, 'receipts.jsonl'); const before = fs.readFileSync(receipts, 'utf8');
    for (const mutation of ['body', 'suffix']) {
      const secret = readJson(path.join(state, 'challenge.json')).secret;
      const faulty = before.trim().split('\n').map(line => {
        const envelope = JSON.parse(line);
        if (envelope.receipt.hook === 'context') {
          if (mutation === 'body') envelope.receipt.emittedContextHash = digest('policy body omitted');
          else envelope.receipt.stateContext.data += '/wrong';
          envelope.signature = createHmac('sha256', secret).update(JSON.stringify(envelope.receipt)).digest('hex');
        }
        return JSON.stringify(envelope);
      }).join('\n') + '\n';
      fs.writeFileSync(receipts, faulty);
      check(diagnose(pluginRoot, state, 'session').loaded === 'UNREACHED', `issued context mismatch (${mutation}) cannot certify whole emitted policy and state suffix`);
      fs.writeFileSync(receipts, before);
    }
    check(!before.includes('tool_input') && !before.includes('not retained'), 'no command or role body persisted');
    fs.writeFileSync(receipts, before.split('\n').filter(line => !line || JSON.parse(line).receipt.hook !== 'role-stop').join('\n'));
    check(diagnose(pluginRoot, state, 'session').live === 'UNREACHED', 'observed starts without role completion');
    fs.writeFileSync(receipts, before);
    invoke('role-start', {hook_event_name: 'SubagentStart', agent_id: 'child-implementer', agent_type: registration.roles.find(e => e.role === 'evaluator').identifier});
    check(diagnose(pluginRoot, state, 'session').loaded === 'UNREACHED', 'same child identity across roles');
    fs.writeFileSync(receipts, before);
    fs.writeFileSync(receipts, before.replace('"code":0', '"code":23'));
    check(diagnose(pluginRoot, state, 'session').loaded === 'UNREACHED', 'tampered receipt');
    fs.writeFileSync(receipts, JSON.stringify({loaded: true, live: true}) + '\n');
    check(diagnose(pluginRoot, state, 'session').loaded === 'UNREACHED', 'caller boolean never certifies');
    fs.writeFileSync(receipts, before);
    const challengeFile = path.join(state, 'challenge.json'); const challenge = readJson(challengeFile);
    fs.writeFileSync(challengeFile, JSON.stringify({...challenge, expires: 0}));
    check(diagnose(pluginRoot, state, 'session').loaded === 'UNREACHED', 'expired evidence');
  }
  const copy = path.join(temp, 'wrong-source'); fs.cpSync(pluginRoot, copy, {recursive: true});
  fs.appendFileSync(path.join(copy, 'hooks/session-context.md'), '\nchanged\n');
  check(diagnose(copy).static === 'UNREACHED', 'same version wrong content');
  check(diagnose(pluginRoot).loaded === 'UNREACHED', 'external doctor works without hook receipt');
  if (process.argv[2]) {
    const metadata = readJson(process.argv[2]);
    const actual = diagnose(metadata.installedRoot, metadata.state, metadata.sessionId);
    check(actual.static === 'PASS' && actual.loaded === 'PASS' && actual.live === 'PASS', 'actual isolated Codex installation/load proof');
  }
  console.log(`PASS doctor: ${count} assertions; direct hook fixtures, Claude live UNREACHED (skills#268)`);
} finally { fs.rmSync(temp, {recursive: true, force: true}); }
