import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {registerRoles, verifyRegistration, roleCall, roleResult, loadRole} from '../../plugins/harness/lib/roles.mjs';
import {roleNames, roleIdentifier, canonicalRole} from '../../plugins/harness/lib/role-identities.mjs';

const root = fileURLToPath(new URL('../../plugins/harness', import.meta.url));
const temp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'role-contract-')));
let count = 0;
const check = (condition, message) => { assert.ok(condition, message); count++; };
const rejected = (fn, message) => { assert.throws(fn, undefined, message); count++; };
const clone = value => structuredClone(value);
try {
  for (const runtime of ['claude', 'codex']) {
    const registration = registerRoles(runtime, path.join(temp, runtime));
    check(verifyRegistration(registration) === registration, `${runtime} source registration`);
    for (const role of roleNames) {
      const entry = registration.roles.find(e => e.role === role);
      check(canonicalRole(entry.identifier) === `harness:${role}`, 'shared runtime identity');
      check(entry.source === loadRole(role).source, 'source target pinned');
      if (runtime === 'codex') {
        const text = fs.readFileSync(entry.file, 'utf8');
        check(!/^model\s*=/m.test(text), 'Codex inherits model');
        check(JSON.parse(/^developer_instructions = (.+)$/m.exec(text)[1]) === loadRole(role).body.replaceAll('${CLAUDE_PLUGIN_ROOT}', fs.realpathSync(root)), 'generated body single source');
      } else check(entry.file === entry.source, 'Claude source reference');
      const request = {role, task: 'fixture#1', sessionId: 'session', parentAgentId: 'parent', implementerIds: ['author'], previousAgentIds: [], message: 'fixture delegation'};
      const call = roleCall(registration, request);
      const events = ['SubagentStart', 'PreToolUse', 'SubagentStop'].map(hook_event_name => ({hook_event_name, session_id: call.sessionId, agent_type: call.identifier, agent_id: 'child', last_assistant_message: `SIGNAL: ${loadRole(role).signals[0]}\nresult`}));
      const outcome = {agentId: 'child', state: 'completed', events};
      check(roleResult(registration, call, outcome).status === 'REACHED', `${runtime}/${role} result reached`);
      for (const signal of loadRole(role).signals) {
        const altered = clone(outcome); altered.events[2].last_assistant_message = `SIGNAL: ${signal}\nresult`;
        check(roleResult(registration, call, altered).signal === signal, 'source-defined SIGNAL accepted');
      }
      for (const text of ['', 'text\nSIGNAL: MATCH', 'SIGNAL: UNKNOWN', ' SIGNAL: MATCH']) {
        const altered = clone(outcome); altered.events[2].last_assistant_message = text;
        check(roleResult(registration, call, altered).status === 'UNREACHED', 'missing/unknown first-line result');
      }
      for (const field of ['session_id', 'agent_type', 'agent_id']) {
        const altered = clone(outcome); altered.events[1][field] = 'other';
        check(roleResult(registration, call, altered).status === 'UNREACHED', 'split child/session/role chain');
      }
      check(roleResult(registration, call, {...outcome, state: 'interrupted'}).status === 'UNREACHED', 'interruption');
      check(roleResult(registration, call, {...outcome, events: []}).status === 'UNREACHED', 'disabled hooks never reach judgment');
      check(roleResult(registration, call, {...outcome, agentId: 'parent'}).status === 'UNREACHED', 'self judgment');
      check(roleResult(registration, {...call, previousAgentIds: ['child']}, outcome).status === 'UNREACHED', 'fresh retry required');
      if (role !== 'implementer') {
        check(roleResult(registration, {...call, implementerIds: ['child']}, outcome).status === 'UNREACHED', 'author cannot grade own changes');
        rejected(() => roleCall(registration, {...request, implementerIds: []}), 'unknown implementation author');
      }
      check(roleResult(registration, call, {...outcome, events: events.toReversed()}).status === 'UNREACHED', 'ordered lifecycle');
      check(roleResult(registration, {...call, role: 'unknown'}, outcome).status === 'UNREACHED', 'unknown role');
      const missing = clone(registration); missing.roles.pop();
      check(roleResult(missing, call, outcome).status === 'UNREACHED', 'registration absent');
    }
  }
  const reg = registerRoles('codex', path.join(temp, 'codex'));
  const entry = reg.roles[0];
  const original = fs.readFileSync(entry.file, 'utf8');
  fs.writeFileSync(entry.file, original + '# altered\n');
  rejected(() => verifyRegistration(reg), 'negative control: generated drift');
  rejected(() => registerRoles('codex', path.dirname(entry.file)), 'foreign content not overwritten');
  fs.writeFileSync(entry.file, original);
  fs.copyFileSync(entry.file, path.join(path.dirname(entry.file), 'duplicate.toml'));
  rejected(() => verifyRegistration(reg), 'native duplicate name');
  const cli = spawnSync(process.execPath, [path.join(root, 'scripts/roles.mjs'), 'verify', path.join(temp, 'missing.json')], {encoding: 'utf8'});
  check(cli.status === 1 && JSON.parse(cli.stdout).status === 'UNREACHED', 'CLI absent registration nonzero');

  // Exercise shipped guard, not a second permission implementation.
  const repo = path.join(temp, 'repo'); fs.mkdirSync(repo);
  const env = {...process.env, HOME: temp, CLAUDE_PLUGIN_ROOT: root, GIT_CONFIG_GLOBAL: os.devNull, GIT_CONFIG_NOSYSTEM: '1', HARNESS_GUARD_LOG: path.join(temp, 'guard.tsv'), HARNESS_SESSION_ACTOR_LOG: path.join(temp, 'actors.tsv')};
  for (const key of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'HARNESS_ROOT']) delete env[key];
  const git = (...args) => { const r = spawnSync('git', ['-C', repo, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', ...args], {env, encoding: 'utf8'}); assert.equal(r.status, 0, r.stderr); };
  git('init', '-q'); fs.writeFileSync(path.join(repo, '.harness.json'), '{"ledger":{"backend":"github"}}'); git('add', '.'); git('commit', '-qm', 'fixture');
  const wt = path.join(repo, '.claude/worktrees/fixture'); git('worktree', 'add', '-qb', 'fixture', wt);
  for (const runtime of ['claude', 'codex']) for (const role of roleNames) {
    const event = {cwd: wt, agent_id: 'child', agent_type: roleIdentifier(runtime, role)};
    const guard = (tool_name, tool_input) => spawnSync('/bin/bash', [path.join(root, 'hooks/guard.sh')], {cwd: wt, env, encoding: 'utf8', input: JSON.stringify({...event, tool_name, tool_input})}).status;
    check(guard('Bash', {command: 'pwd'}) === 0, `${role} read`);
    check(guard('apply_patch', {command: '*** Begin Patch\n*** Add File: file\n+x\n*** End Patch'}) === (role === 'implementer' ? 0 : 2), `${role} file write`);
    check(guard('Bash', {command: 'git commit -m fixture'}) === (role === 'implementer' ? 0 : 2), `${role} local commit`);
    check(guard('Bash', {command: 'git push origin main'}) === 2, `${role} remote write denied`);
    check(guard('Bash', {command: 'ledger.sh close fixture#1'}) === 2, `${role} ledger close denied`);
    check(guard('Bash', {command: `HARNESS_ROOT=${repo} ledger.sh note fixture#1 receipt`}) === (role === 'implementer' ? 0 : 2), `${role} ledger note permission`);
  }
  const develop = fs.readFileSync(path.join(root, 'skills/develop/SKILL.md'), 'utf8');
  const verify = fs.readFileSync(path.join(root, 'skills/verify-implement/SKILL.md'), 'utf8');
  check(!develop.includes('Self-judgment is not a violation') && !verify.includes('cannot delegate judges for itself'), 'self-close fallback removed');
  const retry = fs.readFileSync(path.join(root, 'skills/verify-code/SKILL.md'), 'utf8');
  check(retry.includes('RETRY:') && retry.includes('fresh') && retry.includes('docs/roles.md'), 'fresh reviewer and persisted RETRY consumer preserved');
  if (process.argv[2]) {
    const evidence = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
    check(evidence.origin === 'live' && evidence.version && evidence.registration.runtime === 'codex', 'explicit actual Codex evidence');
    check(roleResult(evidence.registration, evidence.call, evidence.outcome).status === 'REACHED', 'actual generated role chain/result');
  }
  console.log(`PASS role contract: ${count} assertions; offline guard fixtures; Claude live UNREACHED (skills#268)`);
} finally { fs.rmSync(temp, {recursive: true, force: true}); }
