import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { readCodexThread, codexChildPath } from '../../plugins/harness/lib/runtime/codex-identity.mjs';
import { roleSpawnOptions } from '../../plugins/harness/lib/runtime/role-models.mjs';

const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-identity-'));
const id = '01a093ff-1e5b-7302-9ed5-8ba5379852bb';
const raw = { agent_id: id, agent_type: 'default', session_id: 'parent' };
const metadata = { thread: { id, model: 'gpt-5.6-terra', source: { subAgent: {
  thread_spawn: { parent_thread_id: 'parent', depth: 1, agent_path: '/root/child', agent_role: null },
} } } };
try {
  const fixture = path.join(temp, 'server.mjs');
  fs.writeFileSync(fixture, `import readline from 'node:readline';
const mode=process.env.FIXTURE_MODE;
let state=0;
readline.createInterface({input:process.stdin}).on('line',line=>{
 const r=JSON.parse(line);
 const expected=['initialize','initialized','thread/read'][state++];
 if(r.method!==expected) process.exit(3);
 if(r.method==='initialize') {
  if(mode==='malformed') return console.log('not-json');
  if(mode==='exit') return process.exit(4);
  console.log(JSON.stringify({id:1,result:{userAgent:'fixture'}}));
 }
 if(r.method==='thread/read') {
  if(r.params.threadId!==${JSON.stringify(id)} || r.params.includeTurns!==false) process.exit(5);
  console.log(JSON.stringify(mode==='error'?{id:2,error:{code:-1}}:{id:2,result:${JSON.stringify(metadata)}}));
 }
});`);
  const read = mode => readCodexThread(id, { env: { ...process.env, FIXTURE_MODE: mode },
    spawnProcess: (command, args, options) => {
      assert.equal(command, 'codex');
      assert.deepEqual(args, ['app-server']);
      return spawn(process.execPath, [fixture], options);
    },
  });
  assert.deepEqual(await read('success'), metadata);
  assert.equal(codexChildPath(raw, metadata), '/root/child');
  for (const mode of ['error', 'malformed', 'exit']) await assert.rejects(read(mode));
  assert.throws(() => readCodexThread('/root/child'), /thread ID invalid/);
  assert.throws(() => codexChildPath({ ...raw, session_id: 'foreign' }, metadata));
  assert.deepEqual(roleSpawnOptions('evaluator'), { model: 'gpt-5.6-terra', reasoning_effort: 'medium', fork_turns: 'none' });
  assert.deepEqual(roleSpawnOptions('reviewer'), { model: 'gpt-5.6-sol', reasoning_effort: 'high', fork_turns: 'none' });
  assert.deepEqual(roleSpawnOptions('implementer'), {});
  assert.throws(() => roleSpawnOptions('unknown'));
  console.log('PASS Codex identity: metadata-only handshake, protocol failure denial, session mapping and role model options');
} finally { fs.rmSync(temp, { recursive: true, force: true }); }
