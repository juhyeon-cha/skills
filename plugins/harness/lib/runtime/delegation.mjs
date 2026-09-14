import fs from 'node:fs';
import path from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { isDeepStrictEqual } from 'node:util';
import { resolveState, withStateLock } from './state.mjs';
import { loadRole } from './roles.mjs';
import { roleSpawnOptions } from './role-models.mjs';
import { codexThreadId, readCodexThread, codexChildPath } from './codex-identity.mjs';

const hash = (value) => createHash('sha256').update(value).digest('hex');
const assurances = {
  format: 'harness-delegation-v1',
  provenance: 'parent-attested-tool-observation',
  permission: 'prompt-only',
  enforcement: 'unavailable',
  nativeRoleEvidence: 'unavailable',
  tools: 'unknown',
  tokens: 'unknown',
};
function object(value, keys, label) {
  if (
    !value ||
    typeof value !== 'object' ||
    Array.isArray(value) ||
    Object.keys(value).some((key) => !keys.includes(key)) ||
    keys.some((key) => !Object.hasOwn(value, key))
  )
    throw new Error(`${label} schema invalid`);
}
function text(value, label) {
  if (typeof value !== 'string' || !value.trim() || /[\0\r\n]/.test(value))
    throw new Error(`${label} missing/invalid`);
  return value;
}
function agent(value) {
  if (typeof value !== 'string' || !/^\/root(?:\/[a-z0-9_]+)*$/.test(value))
    throw new Error('canonical child/parent identity invalid');
  return value;
}
const callKeys = [
  'version',
  'runtime',
  'provider',
  'repository',
  'data',
  'sessionId',
  'parentAgentId',
  'callId',
  'role',
  'task',
  'sourceHash',
  'commitScope',
  'implementerIds',
  'previousAgentIds',
  'permission',
];
function callShape(call) {
  object(call, [...callKeys, ...['retryOf', 'resumeFrom', 'reuseChild', 'modelOptions'].filter(key => Object.hasOwn(call ?? {}, key))], 'call');
}

/** Execution-policy eligibility; this does not spawn or certify a child. */
export function delegationCapability({ runtime, provider, permission = 'prompt-only' } = {}) {
  const reason =
    runtime !== 'codex' || provider !== 'collaboration'
      ? 'unsupported delegation runtime/provider'
      : permission !== 'prompt-only'
        ? 'unsupported permission policy; enforced permissions unavailable'
        : null;
  return {
    format: 'harness-delegation-capability-v1',
    status: reason ? 'UNAVAILABLE' : 'AVAILABLE',
    runtime: runtime ?? 'unspecified',
    provider: provider ?? 'unspecified',
    permission: permission ?? 'unspecified',
    enforcement: 'unavailable',
    nativeRoleEvidence: 'unavailable',
    automaticNativeFallback: !reason,
    reason,
  };
}

function validateCall(call, root) {
  callShape(call);
  if (call.resumeFrom !== undefined) {
    object(call.resumeFrom, ['sessionId', 'parentAgentId', 'callId', 'callHash', 'dispatchHash', 'bindingHash', 'outcomeHash'], 'resume reference');
    for (const key of ['sessionId', 'callId']) text(call.resumeFrom[key], `resume ${key}`);
    agent(call.resumeFrom.parentAgentId);
    for (const key of ['callHash', 'dispatchHash', 'outcomeHash', ...(call.resumeFrom.bindingHash === null ? [] : ['bindingHash'])])
      if (!/^[a-f0-9]{64}$/.test(call.resumeFrom[key])) throw new Error('resume digest invalid');
    if (call.resumeFrom.sessionId === call.sessionId || call.retryOf || call.reuseChild)
      throw new Error('cross-session resume requires a fresh child and a distinct session, without retryOf');
    if (call.role !== 'evaluator' || call.commitScope?.mode !== 'fixed')
      throw new Error('cross-session resume supports fixed evaluator calls only');
  }
  if (call.retryOf !== undefined) {
    text(call.retryOf, 'retryOf');
    if (call.retryOf === call.callId) throw new Error('retry cannot reference itself');
  }
  if (call.reuseChild !== undefined && (typeof call.reuseChild !== 'boolean' || !call.retryOf || call.role !== 'reviewer'))
    throw new Error('child reuse requires a reviewer retry');
  if (call.reuseChild && call.modelOptions?.model) throw new Error('requested model change requires a fresh child');
  roleSpawnOptions(call.role, call.modelOptions);
  if (call.version !== 1) throw new Error('unsupported delegation version');
  const capability = delegationCapability(call);
  if (capability.status !== 'AVAILABLE') throw new Error(capability.reason);
  for (const key of ['repository', 'data']) {
    text(call[key], key);
    if (!path.isAbsolute(call[key])) throw new Error(`${key} must be absolute`);
  }
  for (const key of ['sessionId', 'callId', 'task']) text(call[key], key);
  agent(call.parentAgentId);
  for (const key of ['implementerIds', 'previousAgentIds']) {
    if (!Array.isArray(call[key]) || new Set(call[key]).size !== call[key].length)
      throw new Error('identity history missing/duplicate');
    call[key].forEach(agent);
  }
  if (call.role !== 'implementer' && !call.implementerIds.length)
    throw new Error('implementation identity missing');
  const definition = loadRole(call.role, root);
  if (call.sourceHash !== definition.sha256) throw new Error('role source hash drift');
  const commit = call.commitScope;
  object(
    commit,
    commit?.mode === 'implementation'
      ? ['mode', 'base', 'branch']
      : ['mode', 'base', 'head', 'branch'],
    'commit scope',
  );
  if (
    !['implementation', 'fixed'].includes(commit.mode) ||
    (commit.mode === 'implementation' && call.role !== 'implementer')
  )
    throw new Error('commit scope mode invalid for role');
  text(commit.branch, 'branch');
  for (const key of commit.mode === 'fixed' ? ['base', 'head'] : ['base'])
    if (!/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(commit[key]))
      throw new Error('full commit identity required');
  return definition;
}

function git(call, ...args) {
  const env = { ...process.env };
  for (const key of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR'])
    delete env[key];
  const result = spawnSync('git', ['-C', call.repository, ...args], { env, encoding: 'utf8' });
  if (result.error || result.status !== 0)
    throw new Error(`commit scope verification failed: ${args[0]}`);
  return result.stdout.trim();
}
function verifyCommits(call, phase, completedHead) {
  const scope = call.commitScope;
  const check = (sha) => {
    if (
      !/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(sha ?? '') ||
      git(call, 'rev-parse', '--verify', `${sha}^{commit}`) !== sha
    )
      throw new Error('commit identity invalid');
  };
  check(scope.base);
  const head = phase === 'begin'
    ? scope.mode === 'fixed' ? scope.head : scope.base
    : completedHead;
  check(head);
  if (scope.mode === 'fixed' && head !== scope.head) throw new Error('fixed head drift');
  git(call, 'merge-base', '--is-ancestor', scope.base, head);
  if (phase !== 'audit') {
    if (
      git(call, 'symbolic-ref', '--short', 'HEAD') !== scope.branch ||
      git(call, 'rev-parse', 'HEAD') !== head ||
      git(call, 'status', '--porcelain')
    )
      throw new Error('repository branch/head/cleanliness drift');
  }
  return head;
}

async function storage(call, env) {
  if (
    typeof call.data !== 'string' ||
    !path.isAbsolute(call.data) ||
    path.resolve(call.data) !== call.data
  )
    throw new Error('normalized absolute data path required');
  // Explicit data is a local parent-owned inventory, not a hook-delivered directory.
  const scope = await resolveState(
    { runtime: call.runtime, cwd: call.repository, sessionId: call.sessionId },
    { ...env, HARNESS_DATA_DIR: call.data },
  );
  if (scope.top !== call.repository) throw new Error('canonical repository root required');
  return { ...scope, directory: path.join(scope.session, 'delegation') };
}
function file(scope, id, kind) {
  return path.join(scope.directory, `${hash(id)}.${kind}.json`);
}
function write(scope, call, kind, value) {
  const destination = file(scope, call.callId, kind);
  if (fs.existsSync(destination)) throw new Error(`duplicate ${kind}`);
  const temporary = destination + '.' + randomUUID();
  const envelope = {
    version: 1,
    runtime: scope.runtime,
    repoKey: scope.repoKey,
    sessionId: scope.sessionId,
    parentAgentId: call.parentAgentId,
    id: call.callId,
    kind,
    value,
  };
  try {
    fs.writeFileSync(temporary, JSON.stringify(envelope) + '\n', { flag: 'wx', mode: 0o600 });
    fs.renameSync(temporary, destination);
  } finally {
    fs.rmSync(temporary, { force: true });
  }
}
function read(scope, call, kind) {
  const envelope = JSON.parse(fs.readFileSync(file(scope, call.callId, kind), 'utf8'));
  object(
    envelope,
    ['version', 'runtime', 'repoKey', 'sessionId', 'parentAgentId', 'id', 'kind', 'value'],
    'inventory',
  );
  if (
    envelope.version !== 1 ||
    envelope.runtime !== scope.runtime ||
    envelope.repoKey !== scope.repoKey ||
    envelope.sessionId !== scope.sessionId ||
    envelope.parentAgentId !== call.parentAgentId ||
    envelope.id !== call.callId ||
    envelope.kind !== kind
  )
    throw new Error('inventory scope/parent mismatch');
  if (
    kind === 'call' &&
    (envelope.value.callId !== call.callId ||
      envelope.value.parentAgentId !== call.parentAgentId ||
      envelope.value.runtime !== scope.runtime ||
      envelope.value.sessionId !== scope.sessionId ||
      envelope.value.repository !== scope.top ||
      envelope.value.data !== scope.data)
  )
    throw new Error('stored call identity mismatch');
  return envelope.value;
}
function savedCall(scope, call) {
  const saved = read(scope, call, 'call');
  if (!isDeepStrictEqual(saved, call)) throw new Error('stored call scope drift');
  return saved;
}
function observation(value, tool) {
  object(value, ['source', 'tool', 'value'], 'observation');
  if (value.source !== 'parent-tool-return' || value.tool !== tool)
    throw new Error('parent tool observation required; child report is insufficient');
  return value.value;
}
function independent(call, child) {
  agent(child);
  if (
    path.posix.dirname(child) !== call.parentAgentId ||
    (call.previousAgentIds.includes(child) && !call.reuseChild) ||
    (call.role !== 'implementer' && call.implementerIds.includes(child))
  )
    throw new Error('foreign child, self judgment, or reused child');
}
function expectedChild(scope, call) {
  const dispatch = read(scope, call, 'dispatch');
  object(dispatch, ['task_name'], 'dispatch');
  if (!/^harness_[a-f0-9]{32}$/.test(dispatch.task_name))
    throw new Error('dispatch identity invalid');
  return `${call.parentAgentId}/${dispatch.task_name}`;
}
function terminal(scope, call) {
  if (fs.existsSync(file(scope, call.callId, 'outcome'))) throw new Error('call already terminal');
}
const result = (call, status, extra = {}) => ({
  ...assurances,
  status,
  callId: call.callId,
  sessionId: call.sessionId,
  task: call.task,
  role: call.role,
  ...extra,
});

function outcomeIdentity(call, outcome) {
  object(outcome, [...Object.keys(assurances), 'status', 'callId', 'sessionId', 'task', 'role',
    ...(outcome?.status === 'REJECTED' ? ['reason', ...(Object.hasOwn(outcome, 'failure') ? ['failure'] : [])] : ['child', 'head', 'signal', 'result', 'bodyHash'])], 'outcome');
  if (!outcome || outcome.callId !== call.callId || outcome.sessionId !== call.sessionId ||
      outcome.task !== call.task || outcome.role !== call.role ||
      Object.entries(assurances).some(([key, value]) => outcome[key] !== value) ||
      !['OBSERVED', 'REJECTED'].includes(outcome.status)) throw new Error('outcome association invalid');
  if (outcome.status === 'REJECTED') text(outcome.reason, 'rejection reason');
  if (outcome.failure) {
    object(outcome.failure, ['layer', 'kind', 'message', 'childState'], 'provider failure');
    if (outcome.failure.layer !== 'provider' || outcome.failure.childState !== 'not-created' ||
        !['capacity', 'spawn-failed'].includes(outcome.failure.kind) ||
        outcome.failure.message !== outcome.reason || !outcome.reason.startsWith('collab spawn failed: '))
      throw new Error('provider failure association invalid');
  }
}
const identityKey = call => JSON.stringify([call.sessionId, call.parentAgentId, call.callId]);
function sessionScope(scope, sessionId) {
  const session = path.join(scope.repo, 'sessions', hash(sessionId));
  return {...scope, sessionId, sessionKey: hash(sessionId), session,
    directory: path.join(session, 'delegation')};
}
function priorScope(scope, call) {
  return call.resumeFrom ? sessionScope(scope, call.resumeFrom.sessionId) : scope;
}
function previousCall(scope, call) {
  const own = priorScope(scope, call);
  const ref = call.resumeFrom ?? {callId: call.retryOf};
  const prior = read(own, {...call, ...ref}, 'call');
  if (call.resumeFrom) {
    for (const kind of ['call', 'dispatch', 'binding', 'outcome']) {
      const filename = file(own, prior.callId, kind);
      const actual = kind === 'binding' && !fs.existsSync(filename) ? null : hash(fs.readFileSync(filename));
      if (actual !== ref[`${kind}Hash`])
        throw new Error(`resume ${kind} digest mismatch`);
    }
  }
  return prior;
}
// A session inventory belongs to the Git common directory, not one checkout.
// Read each unrelated owner at its recorded checkout while proving it still
// belongs to this repository. Retry scope equality remains in validateRetry.
function inventoryOwner(scope, name) {
  const envelope = JSON.parse(fs.readFileSync(path.join(scope.directory, name), 'utf8'));
  const own = {...scope, top: envelope.value?.repository};
  const owner = read(own, {callId: envelope.id, parentAgentId: envelope.parentAgentId}, 'call');
  if (name !== path.basename(file(own, owner.callId, 'call')))
    throw new Error('inventory filename mismatch');
  if (fs.realpathSync(git(owner, 'rev-parse', '--show-toplevel')) !== owner.repository ||
      fs.realpathSync(git(owner, 'rev-parse', '--path-format=absolute', '--git-common-dir')) !== fs.realpathSync(scope.common))
    throw new Error('inventory repository mismatch');
  return {scope: own, call: owner};
}
function retryIds(scope, call) {
  const ids = new Set([identityKey(call)]);
  while (call.retryOf || call.resumeFrom) {
    const prior = previousCall(scope, call);
    scope = priorScope(scope, call);
    if (ids.has(identityKey(prior))) throw new Error('retry cycle');
    ids.add(identityKey(prior));
    call = prior;
  }
  return ids;
}
function validateRetry(scope, call, root) {
  if (!call.retryOf && !call.resumeFrom) return null;
  const prior = previousCall(scope, call);
  validateCall(prior, root);
  if (prior.task !== call.task || prior.role !== call.role || prior.repository !== call.repository ||
      prior.commitScope.base !== call.commitScope.base || prior.commitScope.mode !== call.commitScope.mode)
    throw new Error('retry scope mismatch');
  const outcome = read(priorScope(scope, call), prior, 'outcome');
  outcomeIdentity(prior, outcome);
  if (call.resumeFrom && (outcome.status !== 'REJECTED' ||
      !isDeepStrictEqual(prior.commitScope, call.commitScope) ||
      !isDeepStrictEqual(prior.implementerIds, call.implementerIds)))
    throw new Error('resume requires rejected evaluator, identical commit scope and implementation identities');
  if (call.resumeFrom) {
    const own = priorScope(scope, call);
    const child = expectedChild(own, prior);
    if (fs.existsSync(file(own, prior.callId, 'binding'))) {
      const binding = read(own, prior, 'binding');
      object(binding, ['child', 'source', 'tool'], 'binding');
      independent(prior, binding.child);
      if (binding.child !== child || binding.source !== 'parent-tool-return' || binding.tool !== bindingTool(prior) || outcome.failure)
        throw new Error('historical binding association invalid');
    }
  }
  if (call.commitScope.mode === 'fixed')
    git(call, 'merge-base', '--is-ancestor', prior.commitScope.head, call.commitScope.head);
  retryIds(scope, call);
  if (prior.retryOf || prior.resumeFrom) validateRetry(priorScope(scope, call), prior, root);
  validateResumeConsumption(scope, call);
  if (call.reuseChild && (outcome.status !== 'OBSERVED' || !['CHANGES_REQUESTED', 'LGTM'].includes(outcome.signal)))
    throw new Error('reuse requires a completed reviewer result');
  return prior;
}
function availableChild(scope, call, child) {
  const ancestors = call.reuseChild ? retryIds(scope, call) : new Set();
  for (const name of fs.readdirSync(scope.directory).filter(name => name.endsWith('.binding.json'))) {
    const recorded = inventoryOwner(scope, name.replace(/\.binding\.json$/, '.call.json'));
    const owner = recorded.call;
    const binding = read(recorded.scope, owner, 'binding');
    if (binding.child === child && !(ancestors.has(identityKey(owner)) &&
        fs.existsSync(file(scope, owner.callId, 'outcome'))))
      throw new Error('child already reserved by an inventory call');
  }
}
const bindingTool = call => call.reuseChild ? 'collaboration.followup_task' : 'collaboration.spawn_agent';

// One repository-wide writer lock makes cross-session consumption atomic. It
// encloses the existing session lock; historical records are never rewritten.
function inventoryLock(scope, fn) {
  return withStateLock(path.join(scope.repo, 'delegation-retries'), () =>
    withStateLock(path.join(scope.directory, 'inventory'), fn));
}
function validateResumeConsumption(scope, call) {
  if (!call.resumeFrom && !call.retryOf) return;
  const target = identityKey(call.resumeFrom ?? {...call, callId: call.retryOf});
  const sessions = path.join(scope.repo, 'sessions');
  for (const name of fs.readdirSync(sessions)) {
    const directory = path.join(sessions, name, 'delegation');
    if (!fs.existsSync(directory)) continue;
    for (const filename of fs.readdirSync(directory).filter(name => name.endsWith('.call.json'))) {
      const envelope = JSON.parse(fs.readFileSync(path.join(directory, filename), 'utf8'));
      const owner = envelope.value;
      if (!owner || identityKey(owner) === identityKey(call)) continue;
      const ref = owner.resumeFrom ?? (owner.retryOf ? {...owner, callId: owner.retryOf} : null);
      if (ref && (call.resumeFrom || owner.resumeFrom) && identityKey(ref) === target)
        throw new Error('resume reference already consumed; inspect successor before another retry');
    }
  }
}

/** Produce an explicit immutable reference without rewriting the old session. */
export async function delegationResumeReference(input, {root, env = process.env} = {}) {
  object(input, ['context', 'callId'], 'reference input');
  object(input.context, ['version', 'runtime', 'provider', 'repository', 'data', 'sessionId', 'parentAgentId'], 'audit context');
  if (input.context.version !== 1 || input.context.runtime !== 'codex' || input.context.provider !== 'collaboration')
    throw new Error('unsupported reference version/runtime/provider');
  agent(input.context.parentAgentId);
  text(input.context.sessionId, 'sessionId');
  const scope = await storage(input.context, env);
  return inventoryLock(scope, () => {
    const call = read(scope, {...input.context, callId: text(input.callId, 'callId')}, 'call');
    validateCall(call, root);
    validateRetry(scope, call, root);
    const outcome = read(scope, call, 'outcome');
    outcomeIdentity(call, outcome);
    if (call.role !== 'evaluator' || call.commitScope.mode !== 'fixed' || outcome.status !== 'REJECTED')
      throw new Error('resume reference requires a rejected fixed evaluator');
    expectedChild(scope, call);
    return {sessionId: call.sessionId, parentAgentId: call.parentAgentId, callId: call.callId,
      callHash: hash(fs.readFileSync(file(scope, call.callId, 'call'))),
      dispatchHash: hash(fs.readFileSync(file(scope, call.callId, 'dispatch'))),
      bindingHash: fs.existsSync(file(scope, call.callId, 'binding')) ? hash(fs.readFileSync(file(scope, call.callId, 'binding'))) : null,
      outcomeHash: hash(fs.readFileSync(file(scope, call.callId, 'outcome')))};
  });
}

/** The caller attests that observations came from its provider tool calls.
 * Local records prevent accidental drift/reuse, not forgery by the same OS user. */
export async function beginDelegation(call, { root, env = process.env } = {}) {
  // Persist the default so binding and completion consume the selected contract.
  if (call && typeof call === 'object' && !Array.isArray(call) && !Object.hasOwn(call, 'permission'))
    call = { ...call, permission: 'prompt-only' };
  validateCall(call, root);
  const scope = await storage(call, env);
  return inventoryLock(scope, () => {
    verifyCommits(call, 'begin');
    const prior = validateRetry(scope, call, root);
    validateResumeConsumption(scope, call);
    // This nonce correlates the requested task name with the observed spawn return.
    // It is not a provider-issued invocation ID or proof of role enforcement.
    const dispatch = { task_name: 'harness_' + randomUUID().replaceAll('-', '') };
    if (call.reuseChild) {
      const binding = read(scope, prior, 'binding');
      independent(call, binding.child);
      if (binding.child !== expectedChild(scope, prior)) throw new Error('retry binding mismatch');
      availableChild(scope, call, binding.child);
      dispatch.task_name = path.posix.basename(binding.child);
      for (const name of fs.readdirSync(scope.directory).filter(name => name.endsWith('.call.json'))) {
        const recorded = inventoryOwner(scope, name);
        const owner = recorded.call;
        if (!fs.existsSync(file(recorded.scope, owner.callId, 'outcome')) && expectedChild(recorded.scope, owner) === binding.child)
          throw new Error('reviewer already has an active invocation');
      }
    }
    write(scope, call, 'call', call);
    write(scope, call, 'dispatch', dispatch);
    return result(call, 'PENDING', { call, dispatch: { ...dispatch,
      ...(call.reuseChild ? {tool: 'collaboration.followup_task'} : roleSpawnOptions(call.role, call.modelOptions)) } });
  });
}

/** Resolve a generic hook child against the parent's session inventory.
 * Dispatch is persisted before spawn, so a first tool need not race binding.
 * This selects guard policy only; it is never native role/lifecycle evidence. */
export async function delegationHookRole(raw, { root, env = process.env, readThread = readCodexThread } = {}) {
  text(raw.session_id, 'hook session');
  const scope = await resolveState({ cwd: raw.cwd, sessionId: raw.session_id }, env);
  if (scope.runtime !== 'codex' || scope.dataSource === 'fallback-unverified')
    throw new Error('generic hook requires explicit Codex state coordinates');
  scope.directory = path.join(scope.session, 'delegation');
  if (!fs.existsSync(scope.directory)) throw new Error('child role is unidentified');
  if (raw.agent_type === 'default' && !codexThreadId(raw.agent_id))
    throw new Error('Codex generic hook requires a thread UUID');
  const child = raw.agent_type === 'default'
    ? codexChildPath(raw, await readThread(raw.agent_id, { env }))
    : agent(raw.agent_id);
  return withStateLock(path.join(scope.directory, 'inventory'), () => {
    const matches = [];
    for (const name of fs
      .readdirSync(scope.directory)
      .filter((name) => name.endsWith('.call.json'))) {
      const envelope = JSON.parse(fs.readFileSync(path.join(scope.directory, name), 'utf8'));
      const call = envelope.value;
      const own = { ...scope, top: call?.repository };
      read(own, call, 'call');
      if (name !== path.basename(file(own, call.callId, 'call')))
        throw new Error('inventory filename mismatch');
      if (expectedChild(own, call) !== child) continue;
      if (fs.existsSync(file(own, call.callId, 'outcome'))) continue;
      validateCall(call, root);
      independent(call, child);
      terminal(own, call);
      if (
        fs.realpathSync(git(call, 'rev-parse', '--show-toplevel')) !==
          fs.realpathSync(call.repository) ||
        fs.realpathSync(git(call, 'rev-parse', '--path-format=absolute', '--git-common-dir')) !==
          fs.realpathSync(scope.common)
      )
        throw new Error('hook repository mismatch');
      if (fs.existsSync(file(own, call.callId, 'binding'))) {
        const binding = read(own, call, 'binding');
        object(binding, ['child', 'source', 'tool'], 'binding');
        if (
          binding.child !== child ||
          binding.source !== 'parent-tool-return' ||
          binding.tool !== bindingTool(call)
        )
          throw new Error('binding identity/provenance mismatch');
      }
      matches.push(call.role);
    }
    if (matches.length !== 1) throw new Error('child role is unidentified or ambiguous');
    return `harness:${matches[0]}`;
  });
}
export async function bindDelegation(input, { root, env = process.env } = {}) {
  object(input, ['call', 'observation'], 'bind');
  const { call } = input;
  validateCall(call, root);
  const scope = await storage(call, env);
  return inventoryLock(scope, () => {
    savedCall(scope, call);
    terminal(scope, call);
    if (fs.existsSync(file(scope, call.callId, 'binding'))) throw new Error('duplicate binding');
    try {
      validateRetry(scope, call, root);
      const raw = observation(input.observation, bindingTool(call));
      if (!call.reuseChild && typeof raw === 'string' && raw.startsWith('collab spawn failed: ')) {
        text(raw, 'provider spawn error');
        const failure = result(call, 'REJECTED', {reason: raw, failure: {
          layer: 'provider', kind: raw === 'collab spawn failed: agent thread limit reached' ? 'capacity' : 'spawn-failed',
          message: raw, childState: 'not-created',
        }});
        write(scope, call, 'outcome', failure);
        return failure;
      }
      if (!call.reuseChild) object(raw, ['task_name'], 'spawn return');
      const child = call.reuseChild ? expectedChild(scope, call) : raw.task_name;
      independent(call, child);
      if (child !== expectedChild(scope, call))
        throw new Error('spawn return does not match requested task name');
      availableChild(scope, call, child);
      // Reserve the observed child for this invocation.
      write(scope, call, 'binding', {
        child,
        source: 'parent-tool-return',
        tool: bindingTool(call),
      });
      return result(call, 'PENDING', { child });
    } catch (error) {
      const failure = result(call, 'REJECTED', { reason: error.message });
      write(scope, call, 'outcome', failure);
      return failure;
    }
  });
}
export async function completeDelegation(input, { root, env = process.env } = {}) {
  object(input, ['call', 'observation', 'head'], 'complete');
  const { call } = input;
  // Validate source inside the terminal section so drift leaves a failed inventory.
  callShape(call);
  const scope = await storage(call, env);
  return inventoryLock(scope, () => {
    savedCall(scope, call);
    terminal(scope, call);
    let outcome;
    try {
      const definition = validateCall(call, root);
      validateRetry(scope, call, root);
      const binding = read(scope, call, 'binding');
      object(binding, ['child', 'source', 'tool'], 'binding');
      if (binding.source !== 'parent-tool-return' || binding.tool !== bindingTool(call))
        throw new Error('binding provenance invalid');
      independent(call, binding.child);
      if (binding.child !== expectedChild(scope, call))
        throw new Error('binding dispatch mismatch');
      const raw = observation(input.observation, 'collaboration.list_agents');
      object(raw, ['agents'], 'list_agents return');
      if (!Array.isArray(raw.agents)) throw new Error('agent inventory missing');
      const seen = new Set();
      for (const row of raw.agents) {
        object(row, ['agent_name', 'agent_status'], 'agent snapshot');
        agent(row.agent_name);
        if (seen.has(row.agent_name)) throw new Error('duplicate snapshot child');
        seen.add(row.agent_name);
      }
      const row = raw.agents.find((row) => row.agent_name === binding.child);
      object(row?.agent_status, ['completed'], 'completed child status');
      const body = row.agent_status.completed;
      if (typeof body !== 'string') throw new Error('completed body missing');
      const signal = /^SIGNAL: ([A-Z_]+)(?:\r?\n|$)/.exec(body)?.[1];
      if (!definition.signals.includes(signal)) throw new Error('SIGNAL missing/unregistered');
      const head = verifyCommits(call, 'complete', input.head);
      outcome = result(call, 'OBSERVED', {
        child: binding.child,
        head,
        signal,
        result: body.split(/\r?\n/)[0],
        bodyHash: hash(body),
      });
    } catch (error) {
      outcome = result(call, 'REJECTED', { reason: error.message });
    }
    write(scope, call, 'outcome', outcome);
    return outcome;
  });
}
export async function auditDelegation(context, { root, env = process.env } = {}) {
  object(
    context,
    ['version', 'runtime', 'provider', 'repository', 'data', 'sessionId', 'parentAgentId'],
    'audit context',
  );
  if (context.version !== 1 || context.runtime !== 'codex' || context.provider !== 'collaboration')
    throw new Error('unsupported audit version/runtime/provider');
  agent(context.parentAgentId);
  text(context.sessionId, 'sessionId');
  for (const key of ['repository', 'data'])
    if (typeof context[key] !== 'string' || !path.isAbsolute(context[key]))
      throw new Error('absolute audit paths required');
  let scope = await storage(context, env);
  return inventoryLock(scope, () => {
    const calls = [],
      errors = [],
      children = new Map(),
      validCalls = new Map();
    const initialSession = context.sessionId;
    const scopes = new Map([[JSON.stringify([context.sessionId, context.parentAgentId]), {scope, context}]]);
    for (const entry of scopes.values()) {
    scope = entry.scope;
    context = entry.context;
    if (!fs.existsSync(scope.directory)) {
      errors.push(`${context.sessionId}: missing invocation inventory`);
      continue;
    }
    const files = fs.readdirSync(scope.directory).filter((name) => name !== 'inventory.lock');
    const names = files.filter((name) => name.endsWith('.call.json'));
    for (const name of files) {
      const match = /^([a-f0-9]{64})\.(call|dispatch|binding|outcome)\.json$/.exec(name);
      if (!match || !files.includes(`${match[1]}.call.json`))
        errors.push('orphan/unknown inventory record');
    }
    for (const name of names) {
      try {
        const recorded = inventoryOwner(scope, name);
        const call = recorded.call;
        scope = recorded.scope;
        const item = result(call, 'PENDING');
        calls.push(item);
        try {
          validateCall(call, root);
          validateRetry(scope, call, root);
          validateResumeConsumption(scope, call);
          if (call.resumeFrom) {
            const ref = call.resumeFrom;
            const key = JSON.stringify([ref.sessionId, ref.parentAgentId]);
            if (!scopes.has(key)) scopes.set(key, {scope: priorScope(scope, call),
              context: {...context, sessionId: ref.sessionId, parentAgentId: ref.parentAgentId}});
          }
          expectedChild(scope, call);
          const outcome = read(scope, call, 'outcome');
          outcomeIdentity(call, outcome);
          const binding = fs.existsSync(file(scope, call.callId, 'binding')) ? read(scope, call, 'binding') : null;
          if (binding) {
            object(binding, ['child', 'source', 'tool'], 'binding');
            if (binding.source !== 'parent-tool-return' || binding.tool !== bindingTool(call))
              throw new Error('binding provenance invalid');
            independent(call, binding.child);
            if (binding.child !== expectedChild(scope, call)) throw new Error('binding dispatch mismatch');
            const childKey = JSON.stringify([call.sessionId, binding.child]);
            if (children.has(childKey)) {
              const owner = children.get(childKey);
              if (!(call.reuseChild && retryIds(scope, call).has(identityKey(owner))) &&
                  !(owner.reuseChild && retryIds(scope, owner).has(identityKey(call))))
                throw new Error('duplicate inventory child');
            }
            children.set(childKey, call);
          }
          if (outcome.status === 'REJECTED') {
            Object.assign(item, outcome);
            validCalls.set(identityKey(call), {call, scope});
            continue;
          }
          if (
            !binding ||
            outcome.child !== binding.child ||
            outcome.callId !== call.callId ||
            outcome.sessionId !== call.sessionId ||
            outcome.task !== call.task ||
            outcome.role !== call.role ||
            Object.entries(assurances).some(([key, value]) => outcome[key] !== value) ||
            !loadRole(call.role, root).signals.includes(outcome.signal) ||
            outcome.result !== `SIGNAL: ${outcome.signal}` ||
            !/^[a-f0-9]{64}$/.test(outcome.bodyHash)
          )
            throw new Error('outcome association invalid');
          verifyCommits(call, 'audit', outcome.head);
          Object.assign(item, outcome);
          validCalls.set(identityKey(call), {call, scope});
        } catch (error) {
          item.status = fs.existsSync(file(scope, call.callId, 'outcome')) ? 'REJECTED' : 'PENDING';
          item.reason = error.message;
        }
      } catch (error) {
        errors.push(error.message);
      }
    }
    if (!names.length) errors.push('empty invocation inventory');
    }
    // Resolve execution failures only through explicit, validated retry links.
    // The original rows retain their status and reason; pending/corrupt calls
    // never disappear behind a later success.
    for (const item of calls.filter(item => item.status === 'OBSERVED')) {
      let current = [...validCalls.values()].find(({call}) =>
        call.sessionId === item.sessionId && call.callId === item.callId);
      const successor = current?.call;
      while (current && (current.call.retryOf || current.call.resumeFrom)) {
        const previous = previousCall(current.scope, current.call);
        const key = identityKey(previous);
        if (!validCalls.has(key)) break;
        const prior = calls.find(row => row.callId === previous.callId && row.sessionId === previous.sessionId);
        if (prior.status === 'REJECTED') {
          prior.resolvedBy = item.callId;
          prior.resolvedByRef = {sessionId: item.sessionId,
            parentAgentId: successor.parentAgentId,
            callId: item.callId};
        }
        current = validCalls.get(key);
      }
    }
    return {
      ...assurances,
      status:
        !errors.length && calls.length && calls.every((call) => call.status === 'OBSERVED' || call.resolvedBy)
          ? 'OBSERVED'
          : 'REJECTED',
      sessionId: initialSession,
      calls,
      errors,
    };
  });
}
