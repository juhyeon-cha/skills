import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { executeLedger } from '../../plugins/harness/lib/ledger.mjs';
import { applyMarker, legacyExecution, splitRecord, recordBody, preserveRecord, normalizeRecord, lastExecutionMarker, withRecordLock } from '../../plugins/harness/lib/ledger/record.mjs';

const legacy = 'ACTOR: repo sess-1\nDELEGATED: m0\nVERIFY_PENDING: hash1\nRETRY: verify-code 2/2\nhuman event';
const record = { version: 1, execution: legacyExecution(legacy), summaries: { review: 'LGTM\n\nliteral </details> & unicode 한글' } };
const human = '# Problem\n\nHuman body with trailing lines\n';
const rendered = recordBody(human, record);
assert.deepEqual(splitRecord(rendered), { body: human, record });
assert.equal(recordBody(rendered, record), rendered);
assert.deepEqual(splitRecord(preserveRecord(rendered, 'replacement')).record, record);
assert.equal(splitRecord(preserveRecord(rendered, 'replacement')).body, 'replacement');
assert.throws(() => splitRecord(rendered + rendered), /duplicated/);
assert.throws(() => splitRecord(rendered.replace('"version":1', '"version":2')), /unsupported/);
assert.throws(() => recordBody('body', {...record, summaries: {bad: '<!-- harness:managed:start -->'}}), /reserved/);
const row = normalizeRecord({ description: rendered, notes: legacy, actor: 'old' });
assert.equal(row.actor, 'sess-1');
assert.equal(lastExecutionMarker(row), 'VERIFY_PENDING: hash1');
row.execution = applyMarker(row.execution, 'DELEGATED: m1');
assert.equal(lastExecutionMarker(row), 'DELEGATED: m1');
row.execution = applyMarker(row.execution, 'PHASE: idle');
assert.equal(lastExecutionMarker(row), ''); // stale legacy notes cannot revive phase
assert.equal(row.execution.retries['verify-code'].count, 2);
assert.throws(() => applyMarker(row.execution, 'RETRY: verify-code -1/2'));
assert.throws(() => applyMarker(row.execution, 'RETRY: verify-code 1/0'));
assert.throws(() => applyMarker(row.execution, 'ACTOR: __proto__ actor'));

const root = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), 'ledger-record-test-')));
try {
  await fs.writeFile(path.join(root, '.harness.json'), JSON.stringify({ledger:{backend:'beads'}}));
  let current = {id:'task',description:human,notes:legacy,acceptance_criteria:'criteria',assignee:'sess-1',status:'in_progress',issue_type:'task',labels:[]};
  let writes=0, reads=0, race=false, lost=false;
  const result = value => ({status:'exited',code:0,stdout:Buffer.from(JSON.stringify(value)),stderr:Buffer.alloc(0)});
  const process = async command => {
    const args=command.argv.slice(3);
    if(args[0]==='show') {
      reads++;
      if(race && reads===2) current.description='other writer changed body';
      return result([current]);
    }
    if(args[0]==='update') {
      writes++;
      if (args.includes('--claim')) current.assignee=args[args.indexOf('--actor')+1];
      current.description=lost ? 'remote writer won' : args[args.indexOf('--description')+1];
      return result('updated');
    }
    throw new Error('unexpected backend mutation '+args.join(' '));
  };
  const run=args=>executeLedger(args,{root,cwd:root,process});
  let r=await run(['summary','task','review','LGTM']);assert.equal(r.code,0,r.stderr);
  assert.equal(writes,1);
  r=await run(['summary','task','review','LGTM']);assert.equal(r.code,0,r.stderr);assert.equal(writes,1);
  r=await run(['state','task','RETRY: verify-code 3/2']);assert.equal(r.code,0,r.stderr);
  let view=JSON.parse((await run(['show','task','--json'])).stdout)[0];
  assert.equal(view.execution.retries['verify-code'].count,3);
  assert.equal(view.summaries.review,'LGTM');assert.equal(view.description,human);
  r=await run(['update','task','--claim','--actor','sess-new']);assert.equal(r.code,0,r.stderr);
  view=JSON.parse((await run(['show','task','--json'])).stdout)[0];
  assert.equal(view.actor,'sess-new');assert.equal(view.execution.actor,'sess-new');
  assert.equal(view.summaries.review,'LGTM');
  const phaseFile=path.join(root,'phase.txt'), summaryFile=path.join(root,'summary.txt');
  await fs.writeFile(phaseFile,'VERIFY_PENDING: committed-head\n');
  await fs.writeFile(summaryFile,'implementation evidence');
  const combinedBefore=writes;
  const combined=['summary','task','implementation','--file',summaryFile,'--state-file',phaseFile];
  r=await run(combined);assert.equal(r.code,0,r.stderr);assert.equal(writes,combinedBefore+1);
  view=JSON.parse((await run(['show','task','--json'])).stdout)[0];
  assert.equal(lastExecutionMarker(view),'VERIFY_PENDING: committed-head');
  assert.equal(view.summaries.implementation,'implementation evidence');
  r=await run(combined);assert.equal(r.code,0,r.stderr);assert.equal(writes,combinedBefore+1);
  await fs.writeFile(phaseFile,'invalid marker');
  r=await run(combined);assert.equal(r.code,1);assert.equal(writes,combinedBefore+1);
  r=await run([...combined,'--state-file',phaseFile]);assert.equal(r.code,1);assert.equal(writes,combinedBefore+1);
  const before=writes;race=true;reads=0;
  r=await run(['summary','task','implementation','done']);assert.equal(r.code,1);assert.match(r.stderr,/conflict/);assert.equal(writes,before);
  race=false;lost=true;
  r=await run(['summary','task','implementation','done']);assert.equal(r.code,1);assert.match(r.stderr,/conflict/);
  await withRecordLock(root,async()=>{await assert.rejects(withRecordLock(root,async()=>{}),/another local write/);});
  await withRecordLock(root,async()=>{}); // lock released on prior completion
  console.log('PASS managed record roundtrip, legacy/resume/redelegation, retries, idempotence, beads transport, conflict and locks');
} finally { await fs.rm(root,{recursive:true,force:true}); }
