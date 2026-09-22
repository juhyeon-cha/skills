import fs from 'node:fs';
import path from 'node:path';
import {createHash, randomBytes} from 'node:crypto';
import {isDeepStrictEqual} from 'node:util';
import {fileURLToPath} from 'node:url';
import {inspectDistribution} from '../distribution.mjs';
import {resolveState, withStateLock} from './state.mjs';
import {loadRole} from './roles.mjs';
import {roleIdentifier} from './role-contract.mjs';
import {roleCapabilities} from './role-capabilities.mjs';

const hash = value => createHash('sha256').update(value).digest('hex');
const text = (value, label) => {
  if (typeof value !== 'string' || !value.trim() || /[\0\r\n]/.test(value))
    throw new Error(`${label} missing`);
  return value;
};
const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const save = (file, value) => withStateLock(file, () =>
  fs.writeFileSync(file, JSON.stringify(value), {flag: 'wx', mode: 0o600}));
const callFile = (scope, id) => path.join(scope.session, 'antigravity-calls', hash(text(id, 'callId')) + '.json');
export const antigravityChildFile = scope => path.join(scope.session, 'antigravity-child.json');
function sourceOf(root) {
  const {root: canonical, hash: digest} = inspectDistribution(root);
  return {root: canonical, hash: digest};
}
export function observedAntigravityRows(scope, source) {
  const rows = fs.readFileSync(scope.events, 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse);
  return rows.filter(row => row.runtime === 'antigravity' && row.repoKey === scope.repoKey &&
    row.event?.session_id === scope.sessionId && row.observation?.kind === 'executing-wrapper' &&
    row.observation.workspace === scope.top && isDeepStrictEqual(row.observation.source, source));
}
export function validateAntigravityParent(scope, root) {
  const parent = read(path.join(scope.session, 'antigravity-parent.json'));
  if (parent.version !== 1 || parent.runtime !== scope.runtime ||
      parent.kind !== 'parent' || parent.evidence !== 'operator-attested' ||
      parent.sessionId !== scope.sessionId || parent.repoKey !== scope.repoKey ||
      parent.workspace !== scope.top || !isDeepStrictEqual(parent.source, sourceOf(root)))
    throw new Error('parent scope/source mismatch');
  return parent;
}
async function scoped(input, root, env) {
  if (input.runtime !== 'antigravity') throw new Error('Antigravity runtime required');
  const scope = await resolveState({runtime: input.runtime, cwd: input.workspace, sessionId: input.parentId}, env);
  if (scope.dataSource !== 'explicit' || input.workspace !== scope.top) throw new Error('explicit exact scope required');
  validateAntigravityParent(scope, root);
  return scope;
}

// Parent/operator-owned observations attest native invocation.
// They are not provider signatures or native permission proof.
export async function beginAntigravityRole(input, {root, env = process.env}) {
  const scope = await scoped(input, root, env);
  for (const key of ['callId', 'task', 'parentId']) text(input[key], key);
  if (typeof input.prompt !== 'string' || !input.prompt.trim()) throw new Error('prompt missing');
  const definition = loadRole(input.role, root);
  const capabilities = roleCapabilities('antigravity', input.role, input.capabilities);
  for (const key of ['implementerIds', 'previousAgentIds']) {
    if (!Array.isArray(input[key]) || new Set(input[key]).size !== input[key].length) throw new Error('identity history missing');
    input[key].forEach(id => text(id, 'history identity'));
  }
  if (input.role !== 'implementer' && !input.implementerIds.length) throw new Error('implementation identity missing');
  const args = {Subagents: [{TypeName: roleIdentifier('antigravity', input.role),
    Model: capabilities.model.model, Workspace: 'inherit', Role: input.role,
    Prompt: `Harness call ${input.callId}\nPreparation only. Read the canonical ${input.role} instructions and safe workspace context. Do not execute the task, mutate files, or return a SIGNAL. Wait idle for the parent's HARNESS_READY message; send its exact ACK as instructed, then wait idle for HARNESS_START. Only after acknowledging START may you execute its task. This is a harness handshake, not native lifecycle registration.`} ]};
  const call = {version: 1, runtime: 'antigravity', callId: input.callId, task: input.task,
    parentId: input.parentId, workspace: scope.top, repoKey: scope.repoKey,
    role: input.role, roleHash: definition.sha256, source: sourceOf(root), args,
    phase: 'awaiting-bind', prompt: input.prompt,
    implementerIds: input.implementerIds, previousAgentIds: input.previousAgentIds,
    capabilities, provenance: 'parent-attested-tool-observation'};
  save(callFile(scope, call.callId), call);
  return {status: 'PENDING', call, dispatch: {tool: 'invoke_subagent', args}};
}
function validCall(call, scope, root) {
  if (call.version !== 1 || call.parentId !== scope.sessionId || call.repoKey !== scope.repoKey ||
      call.workspace !== scope.top || !isDeepStrictEqual(call.source, sourceOf(root)) ||
      call.roleHash !== loadRole(call.role, root).sha256) throw new Error('call scope/source drift');
}
export function authorizeAntigravitySpawn(scope, event, root) {
  const directory = path.join(scope.session, 'antigravity-calls');
  const matching = fs.readdirSync(directory).filter(name => name.endsWith('.json')).map(name => read(path.join(directory, name)))
    .filter(call => isDeepStrictEqual(call.args.Subagents, event.tool_input.Subagents));
  if (matching.length !== 1) throw new Error('unregistered or ambiguous Antigravity dispatch');
  const call = matching[0]; validCall(call, scope, root);
  if (fs.existsSync(callFile(scope, call.callId) + '.bound')) throw new Error('call already dispatched');
  return call;
}
export function parseAntigravitySpawnResult(value) {
  // Installed CLI's GENERIC tool result contains one JSON object. Deliberately
  // reject batches and assistant prose; a provider format change is UNREACHED.
  if (typeof value !== 'string') throw new Error('native tool return missing');
  const match = /Created the following subagents:\s*(\{[\s\S]*\})\s*The subagents will send you a message/.exec(value);
  if (!match) throw new Error('unrecognized invoke_subagent return');
  const result = JSON.parse(match[1]);
  text(result.conversationId, 'returned child');
  if (!Array.isArray(result.workspaceUris) || result.workspaceUris.length !== 1)
    throw new Error('ambiguous returned child workspace');
  return {child: result.conversationId, workspace: fileURLToPath(result.workspaceUris[0])};
}
export async function bindAntigravityRole(input, {root, env = process.env}) {
  const scope = await scoped(input, root, env);
  const call = read(callFile(scope, input.callId)); validCall(call, scope, root);
  if (input.observation?.source !== 'parent-tool-return' || input.observation.tool !== 'invoke_subagent')
    throw new Error('parent tool return observation required');
  const result = parseAntigravitySpawnResult(input.observation.value);
  if (result.workspace !== call.workspace || result.child === call.parentId ||
      call.previousAgentIds.includes(result.child) ||
      (call.role !== 'implementer' && call.implementerIds.includes(result.child)))
    throw new Error('child workspace/self/reuse mismatch');
  const rows = observedAntigravityRows(scope, call.source);
  const dispatch = rows.filter(row => row.code === 0 && row.event.harness_native_tool === 'invoke_subagent' &&
    isDeepStrictEqual(row.event.subagents, call.args.Subagents));
  if (dispatch.length !== 1) throw new Error('single observed dispatch required');
  if (!Number.isSafeInteger(input.observation.stepIdx) || input.observation.stepIdx !== dispatch[0].event.step_idx)
    throw new Error('returned tool step differs from dispatch');
  const childScope = await resolveState({runtime: 'antigravity', cwd: call.workspace, sessionId: result.child}, env);
  const binding = {...call, kind: 'child', childId: result.child, dispatchStep: dispatch[0].event.step_idx,
    observationHash: hash(input.observation.value)};
  // A child may already be safely reading. Binding never relies on its claimed
  // role, and absent context keeps mutation denied until the hook is observed.
  save(antigravityChildFile(childScope), binding);
  const nonce = randomBytes(32).toString('hex');
  const ack = `HARNESS_READY_ACK ${call.callId} ${nonce}`;
  const message = `HARNESS_READY ${call.callId} ${nonce}\nSend exactly ${JSON.stringify(ack)} to ${call.parentId}, then wait idle for HARNESS_START. Do not execute the task or return a SIGNAL.`;
  save(callFile(scope, input.callId) + '.bound', {childId: result.child, phase: 'bound-not-ready', nonce, ack, message});
  return {status: 'BOUND_NOT_READY', childId: result.child, nativeLoaded: false,
    dispatch: {tool: 'send_message', args: {Recipient: result.child, Message: message}}};
}
const messageRows = (rows, recipient, message) => rows.filter(row => row.code === 0 &&
  row.event.harness_native_tool === 'send_message' && row.event.recipient === recipient && row.event.message === message);
function received(observation, sender, recipient, body) {
  if (observation?.source !== 'parent-received-message' || observation.sender !== sender ||
      observation.recipient !== recipient || observation.body !== body) throw new Error('parent received message differs');
}
function normalStops(rows) {
  const stops = rows.filter(row => row.event.harness_native_event === 'Stop');
  if (stops.some(row => row.code !== 0 ||
      !row.event.fully_idle || row.event.termination_reason !== 'NO_TOOL_CALL' || row.event.runtime_error))
    throw new Error('interrupted/repeated child completion');
  return stops;
}
function phaseStops(rows) {
  const stops = normalStops(rows);
  if (stops.some((row, i) => row.event.execution_num !== i ||
      (i < stops.length - 1 && row.observation.stopDecision !== 'continue')))
    throw new Error('interrupted/repeated child completion phase');
  return stops;
}
function beforeAck(rows, ack) {
  const before = rows.slice(0, rows.indexOf(ack));
  const stops = phaseStops(before);
  const lastStop = stops.at(-1);
  if (lastStop && !before.slice(before.indexOf(lastStop) + 1).some(row =>
      row.code === 0 && row.event.harness_native_event === 'PreInvocation'))
    throw new Error('message resume context missing');
}
function delivered(observation, rows, child, message) {
  const matches = messageRows(rows, child, message);
  const returned = typeof observation?.value === 'string' &&
    /^Created At: [^\r\n]+\r?\nCompleted At: [^\r\n]+\r?\nMessage sent to "([^"\r\n]+)"\.\s*$/.exec(observation.value);
  if (matches.length !== 1 || observation?.source !== 'parent-tool-return' || observation.tool !== 'send_message' ||
      observation.stepIdx !== matches[0].event.step_idx || observation.recipient !== child ||
      observation.message !== message || observation.success !== true ||
      !returned || returned[1] !== child)
    throw new Error('exact successful native message delivery observation required');
  // The parent attests the native success and retains its raw return. A hook
  // allow is not delivery and no assistant-authored success is accepted here.
}
export function authorizeAntigravityMessage(scope, event, root) {
  const directory = path.join(scope.session, 'antigravity-calls');
  const calls = fs.readdirSync(directory).filter(name => name.endsWith('.json')).map(name => read(path.join(directory, name)));
  const matches = [];
  for (const call of calls) {
    validCall(call, scope, root);
    const file = callFile(scope, call.callId);
    if (!fs.existsSync(file + '.bound') || fs.existsSync(file + '.result')) continue;
    const bound = read(file + '.bound');
    const active = fs.existsSync(file + '.active') ? read(file + '.active') : null;
    const message = active ? active.message : bound.message;
    if (event.recipient === bound.childId && event.message === message &&
        messageRows(observedAntigravityRows(scope, call.source), bound.childId, message).length === 0) matches.push(call);
  }
  if (matches.length !== 1) throw new Error('unregistered/repeated parent handshake message');
  return matches[0];
}
export async function activateAntigravityRole(input, {root, env = process.env}) {
  const scope = await scoped(input, root, env);
  const file = callFile(scope, input.callId);
  const call = read(file); validCall(call, scope, root);
  const bound = read(file + '.bound');
  if (input.childId !== bound.childId) throw new Error('activation child differs');
  const childScope = await resolveState({runtime: 'antigravity', cwd: scope.top, sessionId: bound.childId}, env);
  await antigravityChildIdentity(childScope, root, env);
  const rows = observedAntigravityRows(childScope, call.source);
  normalStops(rows);
  delivered(input.delivery, observedAntigravityRows(scope, call.source), bound.childId, bound.message);
  const acks = messageRows(rows, call.parentId, bound.ack);
  if (acks.length !== 1) throw new Error('child ready acknowledgement missing');
  beforeAck(rows, acks[0]);
  phaseStops(rows.slice(rows.indexOf(acks[0]) + 1));
  received(input.observation, bound.childId, call.parentId, bound.ack);
  const nonce = randomBytes(32).toString('hex');
  const ack = `HARNESS_START_ACK ${call.callId} ${nonce}`;
  const message = `HARNESS_START ${call.callId} ${nonce}\nSend exactly ${JSON.stringify(ack)} to ${call.parentId} before any task operation, then execute:\n${call.prompt}`;
  const activation = {phase: 'awaiting-start-ack', childId: bound.childId, ack, message,
    prefixLength: rows.length, prefixHash: hash(JSON.stringify(rows)),
    readyDelivery: input.delivery, readyReceived: input.observation};
  save(file + '.active', activation);
  return {status: 'AWAITING_START_ACK', childId: bound.childId,
    dispatch: {tool: 'send_message', args: {Recipient: bound.childId, Message: message}}};
}
export async function antigravityChildIdentity(scope, root, env) {
  const binding = read(antigravityChildFile(scope));
  if (binding.kind !== 'child' || binding.childId !== scope.sessionId || binding.workspace !== scope.top ||
      binding.repoKey !== scope.repoKey || !isDeepStrictEqual(binding.source, sourceOf(root)))
    throw new Error('child scope/source mismatch');
  const parentScope = await resolveState({runtime: 'antigravity', cwd: scope.top, sessionId: binding.parentId}, env);
  validateAntigravityParent(parentScope, root);
  const call = read(callFile(parentScope, binding.callId)); validCall(call, parentScope, root);
  if (read(callFile(parentScope, binding.callId) + '.bound').childId !== scope.sessionId ||
      !isDeepStrictEqual({...binding, kind: undefined, childId: undefined, dispatchStep: undefined, observationHash: undefined},
        {...call, kind: undefined, childId: undefined, dispatchStep: undefined, observationHash: undefined}))
    throw new Error('child call binding mismatch');
  if (fs.existsSync(callFile(parentScope, binding.callId) + '.result')) throw new Error('child call is complete');
  if (!observedAntigravityRows(scope, binding.source).some(row => row.code === 0 && row.event.harness_native_event === 'PreInvocation'))
    throw new Error('child context not observed');
  const file = callFile(parentScope, binding.callId);
  const bound = read(file + '.bound');
  const activation = fs.existsSync(file + '.active') ? read(file + '.active') : null;
  const rows = observedAntigravityRows(scope, binding.source);
  const parentRows = observedAntigravityRows(parentScope, binding.source);
  const message = activation ? activation.message : bound.message;
  const ack = activation ? activation.ack : bound.ack;
  const parentSent = messageRows(parentRows, binding.childId, message).length === 1;
  const acknowledgements = messageRows(rows, binding.parentId, ack);
  if (activation && hash(JSON.stringify(rows.slice(0, activation.prefixLength))) !== activation.prefixHash)
    throw new Error('activation evidence prefix drift');
  const active = !!activation && parentSent && acknowledgements.length === 1 &&
    rows.indexOf(acknowledgements[0]) >= activation.prefixLength;
  return {kind: 'child', role: roleIdentifier('antigravity', binding.role), binding, parentScope,
    active, activation, handshakeAck: parentSent && !acknowledgements.length ? ack : null};
}
export async function completeAntigravityRole(input, {root, env = process.env}) {
  const scope = await scoped(input, root, env);
  const call = read(callFile(scope, input.callId)); validCall(call, scope, root);
  const bound = read(callFile(scope, input.callId) + '.bound');
  if (input.childId !== bound.childId) throw new Error('completion child differs');
  const childScope = await resolveState({runtime: 'antigravity', cwd: scope.top, sessionId: input.childId}, env);
  const identity = await antigravityChildIdentity(childScope, root, env);
  if (!identity.active) throw new Error('child handshake is not active');
  const rows = observedAntigravityRows(childScope, call.source);
  const activation = identity.activation;
  delivered(input.startDelivery, observedAntigravityRows(scope, call.source), bound.childId, activation.message);
  received(input.startObservation, bound.childId, call.parentId, activation.ack);
  const ack = messageRows(rows, call.parentId, activation.ack)[0];
  const readyAck = messageRows(rows, call.parentId, bound.ack)[0];
  beforeAck(rows, readyAck);
  beforeAck(rows.slice(rows.indexOf(readyAck) + 1), ack);
  const execution = rows.slice(rows.indexOf(ack) + 1);
  const stops = phaseStops(execution);
  const stop = stops.at(-1);
  // Continue is recorded from the actual wrapper's output, never a caller's
  // event field. Only that continuation may extend this fresh child's call.
  if (!stops.length || stop !== rows.at(-1) || stops.some((row, i) => row.code !== 0 ||
      !row.event.fully_idle ||
      row.event.termination_reason !== 'NO_TOOL_CALL' || row.event.runtime_error ||
      row.observation.stopDecision !== (i === stops.length - 1 ? 'stop' : 'continue')))
    throw new Error('missing/interrupted/repeated child completion');
  const turn = execution.slice(stops.length > 1 ? execution.indexOf(stops.at(-2)) + 1 : 0);
  const messages = turn.filter(row => row.code === 0 && row.event.harness_native_tool === 'send_message' &&
    row.event.recipient === call.parentId);
  if (messages.length !== 1 || !execution.some(row => row.code === 0 && row.event.harness_native_tool === 'view_file'))
    throw new Error('child read/result chain missing');
  const message = messages[0].event.message;
  if (input.observation?.source !== 'parent-received-message' ||
      input.observation.sender !== bound.childId || input.observation.recipient !== call.parentId ||
      input.observation.body !== message)
    throw new Error('parent received message differs from child result');
  const signal = /^SIGNAL: ([A-Z_]+)(?:\r?\n|$)/.exec(message ?? '')?.[1];
  if (!loadRole(call.role, root).signals.includes(signal)) throw new Error('unregistered result signal');
  const result = {status: 'OBSERVED', signal, callId: call.callId, task: call.task,
    childId: bound.childId, result: message, nativeLoaded: false, liveCertified: false,
    provenance: call.provenance, executionNum: stop.event.execution_num};
  save(callFile(scope, input.callId) + '.result', result);
  return result;
}
