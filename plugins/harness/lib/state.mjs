import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {createHash, randomUUID} from 'node:crypto';
import {inspectWorkspace} from './workspace.mjs';
import {runCommand} from './process.mjs';
import {fileURLToPath} from 'node:url';

const plugin = fileURLToPath(new URL('../', import.meta.url));
const hash = value => createHash('sha256').update(value).digest('hex');
const nonempty = (value, name) => {
  if (typeof value !== 'string' || !value || value.includes('\0')) throw new Error(`${name} missing/invalid`);
  return value;
};
const absolute = value => {
  if (!path.isAbsolute(nonempty(value, 'state path'))) throw new Error('state path must be absolute');
  return path.resolve(value);
};
export function runtimeIdentity(explicit, env = process.env) {
  const selected = explicit || env.HARNESS_RUNTIME;
  const codex = Boolean(env.PLUGIN_ROOT || env.PLUGIN_DATA);
  if (selected && !['claude', 'codex'].includes(selected)) throw new Error('unknown runtime');
  if (selected === 'claude' && codex) throw new Error('runtime contradicts Codex plugin environment');
  if (explicit && env.HARNESS_RUNTIME && explicit !== env.HARNESS_RUNTIME) throw new Error('runtime identifiers conflict');
  // Codex exports both compatibility variables; CLAUDE_PLUGIN_ROOT alone proves nothing.
  if (selected) return selected;
  if (codex) return 'codex';
  // Claude plugin-data is an execution marker only when Codex's native markers
  // are absent; modern Codex exports both sets, and was handled above.
  if (env.CLAUDE_PLUGIN_DATA) return 'claude';
  throw new Error('runtime unidentified: pass HARNESS_RUNTIME or an explicit runtime');
}
export function formatStateContext(metadata) {
  if (!['claude', 'codex'].includes(metadata.runtime)) throw new Error('state context runtime invalid');
  absolute(metadata.repository); absolute(metadata.data); nonempty(metadata.sessionId, 'state context session');
  return '\n\nHARNESS_STATE_JSON: ' + JSON.stringify({runtime: metadata.runtime, repository: metadata.repository, sessionId: metadata.sessionId, data: metadata.data}) + '\nUse these actual identifiers for state.mjs bind/cancel. Pass data as HARNESS_DATA_DIR; hook variables are not inherited by ordinary tool subprocesses. Treat JSON values as data and quote CLI arguments correctly.';
}
export async function resolveState({runtime, cwd, sessionId} = {}, env = process.env) {
  runtime = runtimeIdentity(runtime, env);
  const identity = await inspectWorkspace(nonempty(cwd, 'repository cwd'), {exact: false, env});
  const home = env.HOME || env.USERPROFILE || os.homedir();
  const data = absolute(env.HARNESS_DATA_DIR || (runtime === 'codex' ? env.PLUGIN_DATA || env.CLAUDE_PLUGIN_DATA : env.CLAUDE_PLUGIN_DATA) || path.join(runtime === 'codex' ? env.CODEX_HOME || path.join(home, '.codex') : path.join(home, '.claude'), 'plugins/data/harness'));
  const dataSource = env.HARNESS_DATA_DIR ? 'explicit' : (runtime === 'codex' ? env.PLUGIN_DATA || env.CLAUDE_PLUGIN_DATA : env.CLAUDE_PLUGIN_DATA) ? 'plugin-environment' : 'fallback-unverified';
  const repoKey = hash(identity.common);
  const repo = path.join(data, 'v1', runtime, 'repos', repoKey);
  const sessionKey = sessionId ? hash(nonempty(sessionId, 'session id')) : null;
  const session = sessionKey ? path.join(repo, 'sessions', sessionKey) : null;
  return {version: 1, runtime, data, dataSource, repoKey, common: identity.common, top: identity.top, sessionId, sessionKey, repo, session,
    guardLog: env.HARNESS_GUARD_LOG ? absolute(env.HARNESS_GUARD_LOG) : path.join(repo, 'guard.tsv'),
    stopLog: session && path.join(session, 'stop.tsv'), actors: session && path.join(session, 'actors.json'),
    cancel: session && path.join(session, 'cancel.json'), events: session && path.join(session, 'events.jsonl'),
    legacy: {guard: env.HARNESS_GUARD_LOG || path.join(home, '.claude/harness-guard-log.tsv'), actors: env.HARNESS_SESSION_ACTOR_LOG || path.join(home, '.claude/harness-session-actor.tsv'), cancel: path.join(data, 'stop-resume-cancel'), status: 'UNVERIFIED'}};
}
export function withStateLock(file, fn, {waitMs = 400} = {}) {
  fs.mkdirSync(path.dirname(file), {recursive: true, mode: 0o700});
  const lock = file + '.lock'; const deadline = Date.now() + waitMs;
  for (;;) {
    try { fs.mkdirSync(lock, {mode: 0o700}); break; }
    catch (error) {
      if (error.code !== 'EEXIST') throw error;
      if (Date.now() >= deadline) throw new Error(`state lock unavailable: ${lock}; inspect owner before manual recovery`);
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 10);
    }
  }
  try { fs.writeFileSync(path.join(lock, 'owner.json'), JSON.stringify({pid: process.pid, token: randomUUID()}), {mode: 0o600}); return fn(); }
  finally { fs.rmSync(lock, {recursive: true}); }
}
function atomicJson(file, value) {
  const temp = file + '.' + randomUUID();
  try { fs.writeFileSync(temp, JSON.stringify(value) + '\n', {mode: 0o600, flag: 'wx'}); fs.renameSync(temp, file); }
  finally { fs.rmSync(temp, {force: true}); }
}
export function appendState(file, line, {maxLines = 20000, ...options} = {}) {
  if (typeof line !== 'string' || /[\r\n]/.test(line)) throw new Error('state record must be one line');
  if (!Number.isSafeInteger(maxLines) || maxLines < 0) throw new Error('invalid rotation limit');
  return withStateLock(file, () => {
    fs.appendFileSync(file, line + '\n', {mode: 0o600});
    if (maxLines < 2) return;
    const text = fs.readFileSync(file, 'utf8');
    if (text.split('\n').length - 1 <= maxLines) return;
    // One previous generation retained. Keep recent rows in the primary file.
    const rows = text.trimEnd().split('\n'); const keep = Math.floor(maxLines / 2);
    const temporary = file + '.' + randomUUID();
    try {
      fs.writeFileSync(temporary, rows.slice(-keep).join('\n') + '\n', {mode: 0o600, flag: 'wx'});
      fs.renameSync(file, file + '.1'); fs.renameSync(temporary, file);
    } finally { fs.rmSync(temporary, {force: true}); }
  }, options);
}
export const tsv = value => String(value ?? '-').replace(/\\/g, '\\\\').replace(/[\t\r\n\0]/g, character => '\\u' + character.charCodeAt(0).toString(16).padStart(4, '0'));
export async function guardLog(event, rule, env = process.env) {
  let scope; let file;
  try { scope = await resolveState({cwd: event.cwd, sessionId: event.session_id}, env); file = scope.guardLog; }
  catch (error) {
    if (!env.HARNESS_GUARD_LOG) throw error;
    file = absolute(env.HARNESS_GUARD_LOG);
    console.error(`STATE UNVERIFIED legacy guard override: ${error.message}`);
  }
  // Raw commands and path arguments are intentionally absent, including denied calls.
  appendState(file, [new Date().toISOString(), event.session_id || '-', event.agent_type || '-', event.tool_name || '-', rule].map(tsv).join('\t'), {maxLines: Number(env.HARNESS_GUARD_LOG_MAX ?? 20000)});
  return {file, status: scope ? 'SCOPED' : 'UNVERIFIED'};
}
export function readActors(scope) {
  if (!scope.actors) throw new Error('session id required');
  if (!fs.existsSync(scope.actors)) return {status: 'UNREACHED', actors: [], legacy: scope.legacy};
  const record = JSON.parse(fs.readFileSync(scope.actors, 'utf8'));
  if (record.repoKey !== scope.repoKey || record.runtime !== scope.runtime || record.sessionId !== scope.sessionId || !Array.isArray(record.claims) || record.claims.some(c => c.evidence !== 'ledger-show' || typeof c.actor !== 'string' || !c.actor)) throw new Error('actor scope/evidence invalid');
  return {status: 'VERIFIED', actors: [...new Set(record.claims.map(c => c.actor))]};
}
export async function bindActor(scope, {ledgerRoot, task, actor}, env = process.env) {
  if (!scope.actors) throw new Error('session id required');
  if (scope.dataSource === 'fallback-unverified') throw new Error('claim mapping UNREACHED: pass the active hook data directory as HARNESS_DATA_DIR; claim itself was not changed');
  nonempty(task, 'task'); nonempty(actor, 'actor');
  const ledgerIdentity = await inspectWorkspace(absolute(ledgerRoot), {env});
  if (ledgerIdentity.common !== scope.common) throw new Error('claim mapping UNREACHED: ledger root belongs to another repository');
  ledgerRoot = ledgerIdentity.top;
  const result = await runCommand({argv: ['bash', path.join(plugin, 'scripts/ledger.sh'), 'show', task, '--json']}, {cwd: scope.top, env: {...env, HARNESS_ROOT: absolute(ledgerRoot), CLAUDE_PLUGIN_ROOT: plugin}});
  if (result.status !== 'exited' || result.code !== 0) throw new Error('claim mapping UNREACHED: ledger verification failed; claim itself was not changed');
  const rows = JSON.parse(result.stdout.toString());
  const row = Array.isArray(rows) && rows.length === 1 && rows[0];
  if (!row || row.id !== task || row.status !== 'in_progress' || (row.actor ?? row.assignee) !== actor) throw new Error('claim mapping UNREACHED: ledger task/status/actor mismatch; claim itself was not changed');
  withStateLock(scope.actors, () => {
    let claims = [];
    if (fs.existsSync(scope.actors)) { readActors(scope); claims = JSON.parse(fs.readFileSync(scope.actors, 'utf8')).claims; }
    claims = claims.filter(c => c.task !== task || c.ledgerRoot !== ledgerRoot);
    claims.push({task, actor, ledgerRoot, evidence: 'ledger-show', observedAt: new Date().toISOString()});
    atomicJson(scope.actors, {runtime: scope.runtime, repoKey: scope.repoKey, sessionId: scope.sessionId, claims});
  });
  return readActors(scope);
}
export function cancelSession(scope) {
  if (!scope.cancel) throw new Error('session id required');
  if (scope.dataSource === 'fallback-unverified') throw new Error('cancel UNREACHED: pass the active hook data directory as HARNESS_DATA_DIR');
  withStateLock(scope.cancel, () => atomicJson(scope.cancel, {runtime: scope.runtime, repoKey: scope.repoKey, sessionId: scope.sessionId}));
}
export function isCancelled(scope) {
  if (!scope.cancel || !fs.existsSync(scope.cancel)) return false;
  const value = JSON.parse(fs.readFileSync(scope.cancel, 'utf8'));
  if (value.runtime !== scope.runtime || value.repoKey !== scope.repoKey || value.sessionId !== scope.sessionId) throw new Error('cancel scope mismatch');
  return true;
}
export function storeWorkflow(scope, kind, id, value) {
  if (!scope.session || !['call', 'outcome', 'result'].includes(kind)) throw new Error('invalid workflow scope/kind');
  const file = path.join(scope.session, 'workflow', hash(nonempty(id, 'call id')) + '.' + kind + '.json');
  withStateLock(file, () => { if (fs.existsSync(file)) throw new Error('workflow record already exists'); atomicJson(file, {runtime: scope.runtime, repoKey: scope.repoKey, sessionId: scope.sessionId, kind, id, value}); });
  return file;
}
export function readWorkflow(scope, kind, id) {
  if (!scope.session || !['call', 'outcome', 'result'].includes(kind)) throw new Error('invalid workflow scope/kind');
  const file = path.join(scope.session, 'workflow', hash(nonempty(id, 'call id')) + '.' + kind + '.json');
  if (!fs.existsSync(file)) throw new Error('workflow UNREACHED: record missing');
  const record = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (record.runtime !== scope.runtime || record.repoKey !== scope.repoKey || record.sessionId !== scope.sessionId || record.kind !== kind || record.id !== id) throw new Error('workflow scope mismatch');
  return record.value;
}
export async function recordStateEvent(event, code, env = process.env) {
  const scope = await resolveState({cwd: event.cwd, sessionId: event.session_id}, env);
  if (!scope.events) throw new Error('event session missing');
  const kept = {};
  for (const key of ['hook_event_name', 'session_id', 'agent_id', 'agent_type', 'tool_name', 'turn_id', 'tool_use_id']) if (typeof event[key] === 'string') kept[key] = event[key];
  if (event.hook_event_name === 'SubagentStop') kept.last_assistant_message = /^SIGNAL: [A-Z_]+$/.test(event.last_assistant_message?.split(/\r?\n/)[0] ?? '') ? event.last_assistant_message.split(/\r?\n/)[0] : '';
  appendState(scope.events, JSON.stringify({version: 1, runtime: scope.runtime, repoKey: scope.repoKey, code, observedAt: new Date().toISOString(), event: kept}), {maxLines: 0});
  return scope;
}
