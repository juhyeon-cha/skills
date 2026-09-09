import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {inspectRuntimeContract, roleSignals} from '../../plugins/harness/lib/runtime-contract.mjs';

if (process.argv[2]) {
  try {
    const result = inspectRuntimeContract(JSON.parse(fs.readFileSync(process.argv[2], 'utf8')));
    console.log(JSON.stringify(result));
    process.exitCode = result.status === 'PASS' ? 0 : 1;
  } catch (error) {
    console.error(`UNREACHED: ${error.message}`);
    process.exitCode = 1;
  }
} else {
  const make = runtime => ({
    runtime, version: 'fixture-version', origin: 'fixture', sessionId: 'parent', role: 'harness-reviewer',
    signals: roleSignals(fs.readFileSync(new URL('../../plugins/harness/agents/reviewer.md', import.meta.url), 'utf8')),
    source: {path: 'fixture/source', sha256: 'a'.repeat(64)}, config: {path: 'fixture/config', sha256: 'b'.repeat(64)},
    events: [
      {hook_event_name: 'SessionStart', session_id: 'parent'},
      {hook_event_name: 'PreToolUse', session_id: 'parent', tool_name: 'Bash', tool_input: {command: 'pwd'}},
      {hook_event_name: 'PreToolUse', session_id: 'parent', tool_name: runtime === 'codex' ? 'apply_patch' : 'Write', tool_input: runtime === 'codex' ? {command: '*** Begin Patch\n*** Add File: a\n+x\n*** End Patch'} : {file_path: 'a'}},
      {hook_event_name: 'SubagentStart', session_id: 'parent', agent_id: 'child', agent_type: 'harness-reviewer'},
      {hook_event_name: 'PreToolUse', session_id: 'parent', agent_id: 'child', agent_type: 'harness-reviewer'},
      {hook_event_name: 'SubagentStop', session_id: 'parent', agent_id: 'child', agent_type: 'harness-reviewer', last_assistant_message: 'SIGNAL: LGTM\nfixture'},
    ],
  });
  const splitChildren = runtime => {
    const evidence = make(runtime);
    evidence.events.splice(5, 0, {...evidence.events[3], agent_id: 'other-child'});
    evidence.events[6].agent_id = 'other-child';
    return evidence;
  };
  for (const runtime of ['claude', 'codex']) {
    const good = make(runtime);
    assert.equal(inspectRuntimeContract(good).status, 'PASS');
    assert.equal(inspectRuntimeContract(splitChildren(runtime)).status, 'UNREACHED', 'partial child chains cannot combine');
    const completeChild = splitChildren(runtime);
    completeChild.events.splice(6, 0, {...completeChild.events[4], agent_id: 'other-child'});
    assert.equal(inspectRuntimeContract(completeChild).status, 'PASS', 'one complete child supplies capability evidence');
    for (let i = 0; i < good.events.length; i++) {
      const bad = structuredClone(good); bad.events.splice(i, 1);
      assert.notDeepEqual(bad, good);
      assert.equal(inspectRuntimeContract(bad).status, 'UNREACHED', `missing event ${i}`);
    }
    for (const key of Object.keys(good)) {
      const bad = structuredClone(good); delete bad[key];
      assert.equal(inspectRuntimeContract(bad).status, 'UNREACHED', `missing ${key}`);
    }
    for (const mutate of [b => b.runtime = 'unknown', b => b.events = [], b => b.events[5].agent_id = 'other', b => b.events[4].agent_id = 'other', b => b.events[4].agent_type = 'unknown', b => b.events[5].last_assistant_message = 'SIGNAL: UNKNOWN', b => b.source.sha256 = 'unknown', b => b.events[4].session_id = 'other']) {
      const bad = structuredClone(good); mutate(bad);
      assert.equal(inspectRuntimeContract(bad).status, 'UNREACHED');
    }
  }
  assert.equal(inspectRuntimeContract(null).status, 'UNREACHED');
  assert.deepEqual(roleSignals('unknown format'), []);
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'runtime-contract-check-'));
  try {
    for (const evidence of [null, {...make('codex'), runtime: 'unknown'}, {...make('claude'), events: []}, splitChildren('codex'), splitChildren('claude')]) {
      const file = path.join(temp, 'negative.json');
      fs.writeFileSync(file, JSON.stringify(evidence));
      const run = spawnSync(process.execPath, [process.argv[1], file], {encoding: 'utf8'});
      assert.equal(run.status, 1, run.stderr);
      assert.match(run.stdout, /UNREACHED/);
    }
  } finally { fs.rmSync(temp, {recursive: true, force: true}); }
  console.log('PASS: fixture contracts and missing/unknown evidence negative controls (not live runtime evidence)');
}
