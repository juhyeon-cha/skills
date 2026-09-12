import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';

const START = '<!-- harness:managed:start -->';
const END = '<!-- harness:managed:end -->';
const STATE = /<!-- harness:state (.*?) -->/s;
const key = /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$/;
const machine = /^(?:ACTOR|DELEGATED|VERIFY_PENDING|RETRY|PHASE):/;
const error = (message) => { throw new Error(`ledger record: ${message}`); };
const empty = () => ({ version: 1, actor: null, actors: {}, phase: null, retries: {} });

export function isStateMarker(text) {
  return typeof text === 'string' && !/[\r\n]/.test(text.trim()) && machine.test(text.trim());
}
export function applyMarker(execution, marker) {
  const next = structuredClone(execution);
  const text = marker.trim();
  let m;
  if ((m = /^ACTOR: ([^\s]+)(?: ([^\s]+))?$/.exec(text))) {
    if (m[2]) {
      if (!key.test(m[1])) error('invalid actor repository');
      next.actors[m[1]] = m[2];
    }
    next.actor = m[2] ?? m[1];
  } else if ((m = /^(DELEGATED|VERIFY_PENDING): ([^\s]+)$/.exec(text))) {
    next.phase = { kind: m[1], value: m[2] };
  } else if ((m = /^RETRY: ([a-zA-Z0-9][a-zA-Z0-9._-]{0,79}) (\d+)\/(\d+)$/.exec(text))) {
    const count = Number(m[2]), limit = Number(m[3]);
    if (!Number.isSafeInteger(count) || !Number.isSafeInteger(limit) || limit < 1)
      error('invalid retry counter');
    next.retries[m[1]] = { count, limit };
  } else if (text === 'PHASE: idle') next.phase = { kind: 'idle', value: '' };
  else error('expected ACTOR, DELEGATED, VERIFY_PENDING, RETRY or PHASE: idle');
  return next;
}
export function legacyExecution(notes) {
  let execution = empty();
  for (const line of String(notes ?? '').split(/\r?\n/)) {
    if (!machine.test(line)) continue;
    // Legacy prose that happens to start with a reserved word is not executable.
    try { execution = applyMarker(execution, line); } catch { /* retain in notes */ }
  }
  return execution;
}
function validate(record) {
  const e = record?.execution;
  if (record?.version !== 1 || e?.version !== 1 ||
      !(e.actor === null || typeof e.actor === 'string') ||
      !e.actors || Array.isArray(e.actors) || typeof e.actors !== 'object' ||
      !e.retries || Array.isArray(e.retries) || typeof e.retries !== 'object' ||
      !record.summaries || Array.isArray(record.summaries) || typeof record.summaries !== 'object')
    error('malformed or unsupported managed record');
  for (const [repo, actor] of Object.entries(e.actors))
    if (!key.test(repo) || typeof actor !== 'string' || !actor || /\s/.test(actor)) error('invalid actor map');
  if (e.phase !== null && (!e.phase || !['DELEGATED', 'VERIFY_PENDING', 'idle'].includes(e.phase.kind) || typeof e.phase.value !== 'string' ||
      (e.phase.kind !== 'idle' && (!e.phase.value || /\s/.test(e.phase.value))))) error('invalid execution phase');
  for (const [stage, retry] of Object.entries(e.retries))
    if (!key.test(stage) || !Number.isSafeInteger(retry?.count) || retry.count < 0 || !Number.isSafeInteger(retry.limit) || retry.limit < 1) error('invalid retry counter');
  for (const [section, text] of Object.entries(record.summaries))
    if (!key.test(section) || typeof text !== 'string') error('invalid summary');
  return record;
}
export function splitRecord(body = '') {
  const begin = body.indexOf(START), end = body.indexOf(END);
  if (begin < 0 && end < 0) return { body, record: null };
  if (begin < 0 || end < begin || body.indexOf(START, begin + START.length) >= 0 || body.indexOf(END, end + END.length) >= 0)
    error('managed body boundary is malformed or duplicated');
  const block = body.slice(begin + START.length, end);
  const match = STATE.exec(block);
  if (!match || block.match(/<!-- harness:state /g)?.length !== 1) error('managed state missing or duplicated');
  let record;
  try { record = JSON.parse(match[1]); } catch { error('managed state JSON is invalid'); }
  const before = body.slice(0, begin).replace(/\n\n$/, '');
  return { body: before + body.slice(end + END.length), record: validate(record) };
}
export function recordBody(body, record) {
  if (!record) return body;
  validate(record);
  const clean = splitRecord(body).body;
  const serialized = JSON.stringify(record).replace(/</g, '\\u003c').replace(/>/g, '\\u003e');
  const e = record.execution;
  const lines = [
    e.phase && `상태: ${e.phase.kind}${e.phase.value ? ' · ' + e.phase.value : ''}`,
    e.actor && `실행 담당: ${e.actor}`,
    ...Object.entries(e.retries).map(([stage, r]) => `재시도 ${stage}: ${r.count}/${r.limit}`),
  ].filter(Boolean);
  for (const [section, text] of Object.entries(record.summaries)) {
    if (text.includes(START) || text.includes(END) || text.includes('<!-- harness:state ')) error('reserved marker in summary');
    lines.push(`### ${section}\n\n${text}`);
  }
  return `${clean}\n\n${START}\n<details>\n<summary>하네스 실행 상태와 결과</summary>\n\n<!-- harness:state ${serialized} -->\n\n${lines.join('\n\n')}\n\n</details>\n${END}`;
}
export function preserveRecord(previous, replacement) {
  const old = splitRecord(previous), next = splitRecord(replacement);
  return recordBody(next.body, next.record ?? old.record);
}
export function executionLines(e) {
  const lines = [];
  if (e.actor && !Object.keys(e.actors).length) lines.push(`ACTOR: ${e.actor}`);
  for (const [repo, actor] of Object.entries(e.actors)) lines.push(`ACTOR: ${repo} ${actor}`);
  for (const [stage, r] of Object.entries(e.retries)) lines.push(`RETRY: ${stage} ${r.count}/${r.limit}`);
  if (e.phase && e.phase.kind !== 'idle') lines.push(`${e.phase.kind}: ${e.phase.value}`);
  return lines;
}
export function normalizeRecord(row) {
  const { body, record } = splitRecord(row.description ?? '');
  if (!record) return row;
  const prose = String(row.notes ?? '').split(/\r?\n/).filter(line => !machine.test(line)).join('\n');
  return { ...row, description: body, execution: record.execution, summaries: record.summaries,
    events: row.events ?? row.notes ?? null,
    notes: [prose, ...executionLines(record.execution)].filter(Boolean).join('\n') || null,
    actor: record.execution.actor ?? row.actor ?? null };
}
export function rowRecord(row) {
  return { version: 1, execution: row.execution ?? legacyExecution(row.notes), summaries: row.summaries ?? {} };
}
export function lastExecutionMarker(row) {
  if (row.execution) {
    validate({ version: 1, execution: row.execution, summaries: row.summaries ?? {} });
    const phase = row.execution.phase;
    return phase && phase.kind !== 'idle' ? `${phase.kind}: ${phase.value}` : '';
  }
  return String(row.notes ?? '').split(/\r?\n/).filter(line => /^(VERIFY_PENDING|DELEGATED):/.test(line)).at(-1) ?? '';
}

// Serialize writers to the same remote item on this host, even from different
// checkouts. GitHub/Notion offer no atomic compare-and-swap for body updates.
// Remote races are checked before/after a write, not claimed to be prevented.
export async function withRecordLock(identity, operation) {
  const hash = createHash('sha256').update(identity).digest('hex');
  const dir = path.join(os.tmpdir(), 'harness-ledger-record-' + hash);
  try { await fs.mkdir(dir, { mode: 0o700 }); }
  catch (cause) {
    if (cause.code === 'EEXIST') error(`another local write owns ${dir}; retry after it completes; inspect a crashed writer before removing its lock`);
    throw cause;
  }
  try { return await operation(); }
  finally { await fs.rmdir(dir); }
}
