import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {resolveState, storeWorkflow, readWorkflow, withStateLock} from './state.mjs';
import {roleCall, roleResult, loadRole} from './roles.mjs';
import {records, parseRecords} from './transcripts/common.mjs';
import {decodeCodex, codexOutcome} from './transcripts/codex.mjs';
import {decodeClaude} from './transcripts/claude.mjs';
import {summarize} from './transcript.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const bytes = file => fs.existsSync(file) ? fs.readFileSync(file) : Buffer.alloc(0);
function boundary(file) {
  const value = bytes(file);
  if (value.length && value.at(-1) !== 10) throw new Error('incomplete observation boundary');
  return {file, size: value.length, hash: hash(value), records: value.toString('utf8').split('\n').filter(line => line.trim()).length};
}
function snapshot(saved) {
  const value = bytes(saved.file);
  if (value.length < saved.size || hash(value.subarray(0, saved.size)) !== saved.hash) throw new Error('observation history changed/truncated');
  return parseRecords(value);
}
const after = saved => snapshot(saved).slice(saved.records);
export async function workflowScope(metadata, env = process.env) {
  if (!metadata?.data || !path.isAbsolute(metadata.data)) throw new Error('observed hook data required');
  return resolveState({runtime: metadata.runtime, cwd: metadata.repository, sessionId: metadata.sessionId}, {...env, HARNESS_DATA_DIR: metadata.data});
}
export function beginWorkflow(scope, registration, request, capture) {
  const call = roleCall(registration, request);
  if (call.runtime !== scope.runtime || call.sessionId !== scope.sessionId || !request.callId) throw new Error('workflow call scope missing');
  const expectedFormat = scope.runtime === 'codex' ? 'codex-exec-0.153-jsonl' : 'claude-code-2.1-jsonl';
  capture ??= {format: 'native-outcome-v1'};
  if (![expectedFormat, 'native-outcome-v1'].includes(capture.format)) throw new Error('unsupported capture format');
  if (capture.format !== 'native-outcome-v1' && !path.isAbsolute(capture.file ?? '')) throw new Error('absolute capture path required');
  const record = {version: 1, call, createdAt: new Date().toISOString(), capture: capture.format === 'native-outcome-v1' ? {format: capture.format} : {...capture, ...boundary(capture.file)}, events: boundary(scope.events)};
  storeWorkflow(scope, 'call', request.callId, record);
  return record;
}
export function completeWorkflow(scope, registration, callId, native) {
  return withStateLock(path.join(scope.session, 'workflow-completion'), () => completeLocked(scope, registration, callId, native));
}
function completeLocked(scope, registration, callId, native) {
  const saved = readWorkflow(scope, 'call', callId);
  const nativeCallId = typeof native === 'string' ? native : native?.nativeCallId;
  let result; let outcome;
  try {
    if (saved.version !== 1 || !Number.isFinite(Date.parse(saved.createdAt)) || saved.call.sessionId !== scope.sessionId || saved.call.runtime !== scope.runtime || typeof nativeCallId !== 'string' || !nativeCallId) throw new Error('workflow call identity invalid');
    if (!['native-outcome-v1', scope.runtime === 'codex' ? 'codex-exec-0.153-jsonl' : 'claude-code-2.1-jsonl'].includes(saved.capture.format)) throw new Error('unsupported saved capture format');
    const call = {...saved.call, nativeCallId};
    if (saved.capture.format === 'native-outcome-v1') {
      if (native.sessionId !== call.sessionId || native.parentAgentId !== call.parentAgentId || native.identifier !== call.identifier || native.state !== 'completed' || typeof native.result !== 'string') throw new Error('native return identity/completion missing');
      outcome = {agentId: native.agentId, state: native.state, nativeText: native.result};
    } else if (scope.runtime === 'codex') {
      outcome = codexOutcome(decodeCodex(snapshot(saved.capture), scope.sessionId), call, saved.capture.records);
    }
    else {
      const decoded = decodeClaude(after(saved.capture), agent => {
        if (!/^[A-Za-z0-9_-]+$/.test(agent) || !path.isAbsolute(saved.capture.children ?? '')) throw new Error('Claude child transcript location missing');
        return records(path.join(saved.capture.children, `agent-${agent}.jsonl`));
      }, scope.sessionId);
      const native = decoded.calls.find(item => item.id === nativeCallId);
      if (decoded.errors.length || !native?.completed || native.reason || native.role !== call.role) throw new Error('Claude native invocation/completion missing');
      outcome = {agentId: native.agentId, state: 'completed', nativeText: native.texts?.at(-1)};
    }
    const envelopes = after(saved.events);
    if (envelopes.some(row => row.version !== 1 || row.runtime !== scope.runtime || row.repoKey !== scope.repoKey || row.event?.session_id !== scope.sessionId || !Number.isFinite(Date.parse(row.observedAt)) || Date.parse(row.observedAt) < Date.parse(saved.createdAt))) throw new Error('ordinary event scope/version/boundary mismatch');
    const events = envelopes.map(row => row.event);
    const directory = path.join(scope.session, 'workflow');
    for (const file of fs.readdirSync(directory).filter(name => name.endsWith('.outcome.json'))) {
      const envelope = JSON.parse(fs.readFileSync(path.join(directory, file), 'utf8'));
      const previous = readWorkflow(scope, 'outcome', envelope.id);
      if (previous.nativeCallId === nativeCallId || (outcome.agentId && previous.agentId === outcome.agentId)) throw new Error('native invocation/instance already assigned to another inventory call');
    }
    if (envelopes.some(row => row.event.agent_id === outcome.agentId && row.code !== 0)) throw new Error('role hook observation failed');
    if (events.some(event => event.agent_id === outcome.agentId && event.agent_type !== call.identifier)) throw new Error('child role identity changed or unknown');
    result = roleResult(registration, call, {...outcome, events});
    if (result.status !== 'REACHED') throw new Error(result.reason);
    if (outcome.nativeText?.split(/\r?\n/)[0] !== result.result?.split(/\r?\n/)[0]) throw new Error('native wait and hook SIGNAL differ');
    // Persist minimal evidence; raw capture and response bodies stay at their source.
    outcome = {agentId: outcome.agentId, state: outcome.state, nativeCallId, captureFormat: saved.capture.format, eventCount: events.length};
    result = {...result, result: result.result.split(/\r?\n/)[0]};
  } catch (error) { result = {status: 'UNREACHED', reason: error.message}; outcome = {status: 'UNREACHED', agentId: outcome?.agentId, nativeCallId, reason: error.message}; }
  storeWorkflow(scope, 'outcome', callId, outcome);
  storeWorkflow(scope, 'result', callId, result);
  return result;
}
export function auditWorkflow(scope, root) {
  const directory = path.join(scope.session, 'workflow'); const errors = []; const calls = [];
  const files = fs.existsSync(directory) ? fs.readdirSync(directory).filter(name => name.endsWith('.call.json')) : [];
  for (const file of files) {
    try {
      const envelope = JSON.parse(fs.readFileSync(path.join(directory, file), 'utf8'));
      const saved = readWorkflow(scope, 'call', envelope.id);
      const call = {id: envelope.id, task: saved.call.task, role: saved.call.role, completed: false, texts: [], messages: [], toolsMeasured: false};
      calls.push(call);
      try {
        if (saved.call.sourceHash !== loadRole(saved.call.role, root).sha256) throw new Error('stored role source changed');
        const outcome = readWorkflow(scope, 'outcome', envelope.id); const result = readWorkflow(scope, 'result', envelope.id);
        if (result.status !== 'REACHED' || outcome.state !== 'completed' || result.agentId !== outcome.agentId || result.sessionId !== scope.sessionId || result.task !== saved.call.task) throw new Error(result.reason ?? 'workflow outcome association missing');
        call.completed = true; call.agentId = result.agentId; call.texts = [result.result];
      } catch (error) { call.reason = error.message; }
    } catch (error) { errors.push(error.message); }
  }
  return {...summarize(calls, errors, root), format: 'harness-workflow-v1', runtime: scope.runtime, session: scope.sessionId};
}
