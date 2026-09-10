import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {registerRoles, verifyRegistration, roleCall, roleResult} from '../../plugins/harness/lib/runtime/roles.mjs';

const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'role-ambiguity-'));
let failures = 0;
let count = 0;
const check = (condition, label) => { count++; console.log(`${condition ? 'PASS' : 'FAIL'} ${label}`); if (!condition) failures++; };
try {
  const registration = registerRoles('codex', temp);
  const extra = path.join(temp, 'extra.toml');
  for (const declaration of ['"name" = "harness-reviewer"', "'name' = 'harness-reviewer'", '"na\\u006de" = "harness\\u002dreviewer"', 'name = """harness-reviewer"""', 'name = "other"\n[unsupported]\nvalue = 1']) {
    fs.writeFileSync(extra, `${declaration}\ndescription = "different body"\n`);
    let refused = false;
    try { verifyRegistration(registration); } catch { refused = true; }
    check(refused, `ambiguous registration ${JSON.stringify(declaration)}`);
    fs.unlinkSync(extra);
  }
  fs.writeFileSync(extra, '"name" = "unrelated" # comment\n description = \'other role\'\n');
  check(verifyRegistration(registration) === registration, 'supported quoted unrelated role');
  fs.unlinkSync(extra);
  const call = roleCall(registration, {role: 'reviewer', task: 'fixture#1', sessionId: 'session', parentAgentId: 'parent', implementerIds: ['author'], previousAgentIds: [], message: 'fixture'});
  const event = (hook_event_name, result) => ({hook_event_name, session_id: 'session', agent_id: 'child', agent_type: 'harness-reviewer', last_assistant_message: result});
  const events = [event('SubagentStart'), event('PreToolUse'), event('SubagentStop', 'SIGNAL: LGTM')];
  const outcome = extraEvents => ({state: 'completed', agentId: 'child', events: [...events, ...extraEvents]});
  check(roleResult(registration, call, outcome([])).status === 'REACHED', 'single complete chain');
  for (const suffix of [
    [event('SubagentStop', 'no signal')],
    [event('SubagentStop', 'SIGNAL: CHANGES_REQUESTED')],
    [event('SubagentStart'), event('PreToolUse')],
    [event('PreToolUse')],
    [event('SubagentStart'), event('PreToolUse'), event('SubagentStop', 'SIGNAL: LGTM')],
  ]) check(roleResult(registration, call, outcome(suffix)).status === 'UNREACHED', `mixed execution ${suffix.map(e => e.hook_event_name).join('/')}`);
  assert.equal(failures, 0, `${failures}/${count} ambiguity regressions failed`);
  console.log(`PASS role ambiguity: ${count} assertions`);
} finally { fs.rmSync(temp, {recursive: true, force: true}); }
