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
  object(call, callKeys, 'call');
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
  const inProgress = phase === 'bind' && scope.mode === 'implementation';
  const head =
    phase === 'complete' || phase === 'audit'
      ? completedHead
      : inProgress
        ? git(call, 'rev-parse', 'HEAD')
        : scope.mode === 'fixed'
          ? scope.head
          : scope.base;
  check(head);
  if (scope.mode === 'fixed' && head !== scope.head) throw new Error('fixed head drift');
  git(call, 'merge-base', '--is-ancestor', scope.base, head);
  if (phase !== 'audit') {
    if (
      git(call, 'symbolic-ref', '--short', 'HEAD') !== scope.branch ||
      git(call, 'rev-parse', 'HEAD') !== head ||
      (!inProgress && git(call, 'status', '--porcelain'))
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
    call.previousAgentIds.includes(child) ||
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

/** The caller attests that observations came from its provider tool calls.
 * Local records prevent accidental drift/reuse, not forgery by the same OS user. */
export async function beginDelegation(call, { root, env = process.env } = {}) {
  // Persist the default so binding and completion consume the selected contract.
  if (call && typeof call === 'object' && !Array.isArray(call) && !Object.hasOwn(call, 'permission'))
    call = { ...call, permission: 'prompt-only' };
  validateCall(call, root);
  const scope = await storage(call, env);
  return withStateLock(path.join(scope.directory, 'inventory'), () => {
    verifyCommits(call, 'begin');
    write(scope, call, 'call', call);
    // This nonce correlates the requested task name with the observed spawn return.
    // It is not a provider-issued invocation ID or proof of role enforcement.
    const dispatch = { task_name: 'harness_' + randomUUID().replaceAll('-', '') };
    write(scope, call, 'dispatch', dispatch);
    return result(call, 'PENDING', { call, dispatch: { ...dispatch, ...roleSpawnOptions(call.role) } });
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
          binding.tool !== 'collaboration.spawn_agent'
        )
          throw new Error('binding identity/provenance mismatch');
      }
      verifyCommits(call, 'bind');
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
  return withStateLock(path.join(scope.directory, 'inventory'), () => {
    savedCall(scope, call);
    terminal(scope, call);
    if (fs.existsSync(file(scope, call.callId, 'binding'))) throw new Error('duplicate binding');
    try {
      const raw = observation(input.observation, 'collaboration.spawn_agent');
      object(raw, ['task_name'], 'spawn return');
      const child = raw.task_name;
      independent(call, child);
      if (child !== expectedChild(scope, call))
        throw new Error('spawn return does not match requested task name');
      for (const name of fs
        .readdirSync(scope.directory)
        .filter((name) => name.endsWith('.binding.json'))) {
        const record = JSON.parse(fs.readFileSync(path.join(scope.directory, name), 'utf8'));
        const owner = read(
          scope,
          { ...call, callId: record.id, parentAgentId: record.parentAgentId },
          'call',
        );
        const binding = read(scope, owner, 'binding');
        if (binding.child === child) throw new Error('child already reserved by an inventory call');
      }
      // Reserve the actual child immediately, including when subsequent commit validation fails.
      write(scope, call, 'binding', {
        child,
        source: 'parent-tool-return',
        tool: 'collaboration.spawn_agent',
      });
      verifyCommits(call, 'bind');
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
  object(call, callKeys, 'call');
  const scope = await storage(call, env);
  return withStateLock(path.join(scope.directory, 'inventory'), () => {
    savedCall(scope, call);
    terminal(scope, call);
    let outcome;
    try {
      const definition = validateCall(call, root);
      const binding = read(scope, call, 'binding');
      object(binding, ['child', 'source', 'tool'], 'binding');
      if (binding.source !== 'parent-tool-return' || binding.tool !== 'collaboration.spawn_agent')
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
  const scope = await storage(context, env);
  return withStateLock(path.join(scope.directory, 'inventory'), () => {
    const calls = [],
      errors = [],
      children = new Set();
    const files = fs.readdirSync(scope.directory).filter((name) => name !== 'inventory.lock');
    const names = files.filter((name) => name.endsWith('.call.json'));
    for (const name of files) {
      const match = /^([a-f0-9]{64})\.(call|dispatch|binding|outcome)\.json$/.exec(name);
      if (!match || !files.includes(`${match[1]}.call.json`))
        errors.push('orphan/unknown inventory record');
    }
    for (const name of names) {
      try {
        const envelope = JSON.parse(fs.readFileSync(path.join(scope.directory, name), 'utf8'));
        const call = read(scope, { ...context, callId: envelope.id }, 'call');
        if (name !== path.basename(file(scope, call.callId, 'call')))
          throw new Error('inventory filename mismatch');
        const item = result(call, 'PENDING');
        calls.push(item);
        try {
          validateCall(call, root);
          const binding = read(scope, call, 'binding');
          object(binding, ['child', 'source', 'tool'], 'binding');
          if (
            binding.source !== 'parent-tool-return' ||
            binding.tool !== 'collaboration.spawn_agent'
          )
            throw new Error('binding provenance invalid');
          independent(call, binding.child);
          if (binding.child !== expectedChild(scope, call))
            throw new Error('binding dispatch mismatch');
          if (children.has(binding.child)) throw new Error('duplicate inventory child');
          children.add(binding.child);
          const outcome = read(scope, call, 'outcome');
          if (outcome.status !== 'OBSERVED')
            throw new Error(outcome.reason ?? 'non-observed outcome');
          if (
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
        } catch (error) {
          item.status = fs.existsSync(file(scope, call.callId, 'outcome')) ? 'REJECTED' : 'PENDING';
          item.reason = error.message;
        }
      } catch (error) {
        errors.push(error.message);
      }
    }
    if (!names.length) errors.push('empty invocation inventory');
    return {
      ...assurances,
      status:
        !errors.length && calls.length && calls.every((call) => call.status === 'OBSERVED')
          ? 'OBSERVED'
          : 'REJECTED',
      sessionId: context.sessionId,
      calls,
      errors,
    };
  });
}
