import fs from 'node:fs';
import path from 'node:path';
import {randomBytes, createHmac} from 'node:crypto';
import {inspectDistribution, digest, readJson, pluginRoot} from './distribution.mjs';
import {verifyRegistration, roleCall, roleResult} from './roles.mjs';

const signature = (value, secret) => createHmac('sha256', secret).update(JSON.stringify(value)).digest('hex');

// Explicit state directory seam; central state resolution belongs to the state adapter.
export function createChallenge(directory, runtime, installedRoot, registration, expectedRoot = pluginRoot) {
  if (!path.isAbsolute(directory) || !['claude', 'codex'].includes(runtime)) throw new Error('absolute state directory and runtime required');
  const artifact = inspectDistribution(installedRoot);
  if (artifact.hash !== inspectDistribution(expectedRoot).hash) throw new Error('installed artifact differs from expected source (even if version matches)');
  verifyRegistration(registration);
  if (registration.root !== artifact.root || registration.runtime !== runtime) throw new Error('registration source/runtime mismatch');
  fs.mkdirSync(directory, {mode: 0o700}); // Never replace an existing challenge.
  const challenge = {nonce: randomBytes(24).toString('hex'), secret: randomBytes(32).toString('hex'), runtime, artifact, registration, expires: Date.now() + 30 * 60 * 1000};
  fs.writeFileSync(path.join(directory, 'challenge.json'), JSON.stringify(challenge), {mode: 0o600, flag: 'wx'});
  return {directory, nonce: challenge.nonce};
}

export function recordHook(directory, root, event, hook, execution) {
  if (!directory) return;
  const challenge = readJson(path.join(directory, 'challenge.json'));
  if (Date.now() > challenge.expires || typeof event.session_id !== 'string' || !event.session_id) throw new Error('doctor challenge expired/session missing');
  const artifact = inspectDistribution(root);
  if (artifact.root !== challenge.artifact.root || artifact.hash !== challenge.artifact.hash) throw new Error('executing source differs from challenge');
  const signal = event.hook_event_name === 'SubagentStop' ? /^SIGNAL: [A-Z_]+(?=\r?\n|$)/.exec(event.last_assistant_message ?? '')?.[0] ?? '' : undefined;
  const receipt = {nonce: challenge.nonce, runtime: challenge.runtime, root: artifact.root, hash: artifact.hash, version: artifact.version, sessionId: event.session_id, hook, code: execution.code, event: {hook_event_name: event.hook_event_name, session_id: event.session_id, agent_type: event.agent_type, agent_id: event.agent_id, tool_name: event.tool_name, last_assistant_message: signal}};
  if (hook === 'context' && execution.code === 0) {
    const output = JSON.parse(execution.stdout);
    const context = output.hookSpecificOutput?.additionalContext;
    if (typeof context !== 'string' || !context) throw new Error('context output missing');
    receipt.contextHash = digest(context);
  }
  fs.appendFileSync(path.join(directory, 'receipts.jsonl'), JSON.stringify({receipt, signature: signature(receipt, challenge.secret)}) + '\n', {mode: 0o600});
}

export function diagnose(root, directory, sessionId, expectedRoot = pluginRoot) {
  const report = {static: 'UNREACHED', loaded: 'UNREACHED', live: 'UNREACHED', reasons: []};
  try {
    const artifact = inspectDistribution(root);
    if (artifact.hash !== inspectDistribution(expectedRoot).hash) throw new Error('installed artifact differs from expected source');
    report.static = 'PASS'; report.artifact = {root: artifact.root, version: artifact.version, hash: artifact.hash};
    if (!directory || !sessionId) throw new Error('current session challenge/identity missing; installation list is not load evidence');
    const challenge = readJson(path.join(directory, 'challenge.json'));
    if (Date.now() > challenge.expires || challenge.artifact.root !== artifact.root || challenge.artifact.hash !== artifact.hash) throw new Error('stale challenge or different source');
    verifyRegistration(challenge.registration);
    const lines = fs.readFileSync(path.join(directory, 'receipts.jsonl'), 'utf8').trim().split('\n').filter(Boolean);
    const receipts = lines.map(line => {
      const envelope = JSON.parse(line);
      if (signature(envelope.receipt, challenge.secret) !== envelope.signature) throw new Error('unissued/altered receipt');
      const r = envelope.receipt;
      if (r.nonce !== challenge.nonce || r.hash !== artifact.hash || r.root !== artifact.root || r.runtime !== challenge.runtime || r.version !== artifact.version) throw new Error('receipt source/challenge mismatch');
      return r;
    }).filter(r => r.sessionId === sessionId);
    const contexts = receipts.filter(r => r.hook === 'context' && r.code === 0 && r.contextHash === artifact.contextHash);
    if (contexts.length !== 1) throw new Error('context hook not observed exactly once in this session');
    const events = receipts.filter(r => r.code === 0).map(r => r.event);
    const starts = events.filter(e => e.hook_event_name === 'SubagentStart');
    const identities = new Map();
    for (const start of starts) {
      if (!start.agent_id || identities.has(start.agent_id)) throw new Error('duplicate/reused native child identity');
      identities.set(start.agent_id, start.agent_type);
    }
    for (const entry of challenge.registration.roles) if (!starts.some(e => e.agent_type === entry.identifier && e.agent_id)) throw new Error(`loaded role unobserved: ${entry.identifier}`);
    if (!receipts.some(r => r.hook === 'guard' && r.code === 0)) throw new Error('guard execution unobserved');
    report.loaded = 'PASS';
    if (!receipts.some(r => r.hook === 'stop' && r.code === 0)) throw new Error('Stop hook execution unobserved');
    const implementer = challenge.registration.roles.find(entry => entry.role === 'implementer');
    const implementerIds = starts.filter(e => e.agent_type === implementer.identifier).map(e => e.agent_id);
    for (const entry of challenge.registration.roles) {
      const child = starts.find(e => e.agent_type === entry.identifier);
      const call = roleCall(challenge.registration, {role: entry.role, task: 'doctor-capability', message: 'doctor capability observation', sessionId, parentAgentId: sessionId, implementerIds, previousAgentIds: []});
      const stopped = events.some(e => e.hook_event_name === 'SubagentStop' && e.agent_id === child.agent_id && e.agent_type === entry.identifier);
      const result = roleResult(challenge.registration, call, {state: stopped ? 'completed' : 'interrupted', agentId: child.agent_id, events});
      if (result.status !== 'REACHED') throw new Error(`live role result missing: ${entry.identifier}`);
    }
    report.live = 'PASS';
  } catch (error) { report.reasons.push(error.message); }
  return report;
}
