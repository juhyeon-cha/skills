import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { roleNames, roleIdentifier } from './role-contract.mjs';
import { roleSignals, roleChain } from './role-contract.mjs';
import { assembleNativeRole, nativeAgentName } from './native-role.mjs';
export { nativeAgentName } from './native-role.mjs';
import { requiredRoleTools, roleCapabilities } from './role-capabilities.mjs';

const plugin = fileURLToPath(new URL('../../', import.meta.url));
const hash = (bytes) => createHash('sha256').update(bytes).digest('hex');
const required = (value, label) => {
  if (typeof value !== 'string' || !value.trim()) throw new Error(`${label} missing`);
  return value;
};

/**
 * Load a canonical role document and validate its identity and SIGNAL contract.
 * @param {string} role Canonical role name accepted by roleIdentifier.
 * @param {string} [root] Plugin directory containing roles/.
 * @returns {{role: string, source: string, sha256: string,
 *   body: string, signals: string[]}}
 * @throws {Error} If the role is unknown or its document is unreadable or invalid.
 */
export function loadRole(role, root = plugin) {
  roleIdentifier('claude', role);
  const source = path.join(root, 'roles', `${role}.md`);
  const bytes = fs.readFileSync(source, 'utf8');
  const signals = roleSignals(bytes);
  if (!signals.length || new Set(signals).size !== signals.length)
    throw new Error('role SIGNAL contract missing/duplicate');
  return {
    role,
    source,
    sha256: hash(bytes),
    body: bytes,
    signals,
  };
}

export function projectRole(runtime, role, root, installedRoot = root, options = {}) {
  if (runtime !== 'antigravity' && Object.keys(options).length)
    throw new Error('projection options require Antigravity; use native runtime model selection');
  const definition = loadRole(role, root);
  const identifier = roleIdentifier(runtime, role);
  let text = assembleNativeRole(runtime, definition, root, installedRoot);
  if (runtime === 'antigravity' && Object.keys(options).length) {
    const model = roleCapabilities(runtime, role, {availableTools: requiredRoleTools(runtime, role), ...options}).model.model;
    if (options.modelOptions?.model !== undefined) {
      const end = text.indexOf('\n---', 4);
      const header = text.slice(0, end);
      if (!/^model: .+$/m.test(header)) throw new Error('native model field missing');
      text = header.replace(/^model: .+$/m, () => `model: ${model}`) + text.slice(end);
    }
  }
  return { ...definition, identifier, text };
}

// Explicit destination is a native Codex agents directory, never inferred user state.
// Claude's existing plugin agents directory is referenced, not generated again.
export function registerRoles(runtime, destination, root = plugin) {
  root = fs.realpathSync(root);
  roleIdentifier(runtime, roleNames[0]);
  if (runtime === 'codex') {
    if (!path.isAbsolute(destination ?? ''))
      throw new Error('absolute agents destination required');
    fs.mkdirSync(destination, { recursive: true });
    for (const role of roleNames) {
      const entry = projectRole(runtime, role, root);
      const file = path.join(destination, `${entry.identifier}.toml`);
      // Installation updates must be deliberate: never overwrite foreign/drifted files.
      if (fs.existsSync(file) && fs.readFileSync(file, 'utf8') !== entry.text)
        throw new Error(`registration already differs: ${file}`);
    }
  }
  const roles = roleNames.map((role) => {
    const entry = projectRole(runtime, role, root);
    const file =
      runtime === 'claude' ? path.join(root, 'agents', `${role}.md`) : path.join(destination, `${entry.identifier}.toml`);
    if (runtime === 'claude' && fs.readFileSync(file, 'utf8') !== entry.text)
      throw new Error('generated Claude role drift');
    if (runtime === 'codex' && !fs.existsSync(file))
      fs.writeFileSync(file, entry.text, { flag: 'wx' });
    return {
      role,
      identifier: entry.identifier,
      source: entry.source,
      sourceHash: entry.sha256,
      file,
      fileHash: hash(entry.text),
    };
  });
  return { version: 1, runtime, root, roles };
}

export function verifyRegistration(registration) {
  if (
    registration?.version !== 1 ||
    !path.isAbsolute(registration.root ?? '') ||
    !Array.isArray(registration.roles) ||
    registration.roles.length !== roleNames.length
  )
    throw new Error('registration missing');
  const seen = new Set();
  for (const entry of registration.roles) {
    const expected = projectRole(registration.runtime, entry.role, registration.root);
    if (seen.has(entry.role)) throw new Error('duplicate role registration');
    seen.add(entry.role);
    if (
      entry.identifier !== expected.identifier ||
      entry.source !== expected.source ||
      entry.sourceHash !== expected.sha256 ||
      entry.fileHash !== hash(expected.text) ||
      fs.readFileSync(entry.file, 'utf8') !== expected.text
    )
      throw new Error('role registration drift');
    if (registration.runtime === 'claude' && entry.file !== path.join(registration.root, 'agents', `${entry.role}.md`))
      throw new Error('Claude must reference generated role');
    if (registration.runtime === 'codex') {
      const duplicates = fs
        .readdirSync(path.dirname(entry.file))
        .filter((name) => name.endsWith('.toml'))
        .filter((name) => {
          const text = fs.readFileSync(path.join(path.dirname(entry.file), name), 'utf8');
          return nativeAgentName(text) === entry.identifier;
        });
      if (duplicates.length !== 1) throw new Error('duplicate native role name');
    }
  }
  return registration;
}

export function roleCall(registration, request) {
  verifyRegistration(registration);
  const definition = loadRole(request?.role, registration.root);
  for (const field of ['sessionId', 'parentAgentId', 'task', 'message'])
    required(request[field], field);
  if (
    !Array.isArray(request.implementerIds) ||
    !Array.isArray(request.previousAgentIds) ||
    [...request.implementerIds, ...request.previousAgentIds].some(
      (id) => typeof id !== 'string' || !id,
    )
  )
    throw new Error('identity history required');
  if (request.role !== 'implementer' && !request.implementerIds.length)
    throw new Error('implementation identity missing');
  // History is supplied from persisted delegation/RETRY records, never guessed from prose.
  return {
    ...request,
    runtime: registration.runtime,
    identifier: roleIdentifier(registration.runtime, definition.role),
    sourceHash: definition.sha256,
  };
}

export function roleResult(registration, call, outcome) {
  try {
    const expected = roleCall(registration, call);
    if (
      call.identifier !== expected.identifier ||
      call.sourceHash !== expected.sourceHash ||
      call.runtime !== expected.runtime
    )
      throw new Error('call drift');
    const id = required(outcome?.agentId, 'child identity');
    if (
      outcome.state !== 'completed' ||
      id === call.parentAgentId ||
      (call.role !== 'implementer' && call.implementerIds.includes(id)) ||
      call.previousAgentIds.includes(id)
    )
      throw new Error('interrupted, self judgment, or reused instance');
    const events = outcome.events;
    if (!Array.isArray(events)) throw new Error('role events missing');
    const chain = roleChain(events, call.sessionId, call.identifier, id);
    if (!chain.stopped) throw new Error('same-instance role chain missing');
    const result = chain.result;
    const signal = /^SIGNAL: ([A-Z_]+)(?:\r?\n|$)/.exec(result ?? '')?.[1];
    if (!loadRole(call.role, registration.root).signals.includes(signal))
      throw new Error('SIGNAL missing/unregistered');
    return {
      status: 'REACHED',
      signal,
      agentId: id,
      sessionId: call.sessionId,
      task: call.task,
      result,
    };
  } catch (error) {
    return { status: 'UNREACHED', reason: error.message };
  }
}
