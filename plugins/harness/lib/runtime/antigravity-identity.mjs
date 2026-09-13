import fs from 'node:fs';
import path from 'node:path';
import {inspectDistribution} from '../distribution.mjs';
import {resolveState, withStateLock} from './state.mjs';
import {antigravityChildFile, antigravityChildIdentity, authorizeAntigravitySpawn, authorizeAntigravityMessage, validateAntigravityParent} from './antigravity-roles.mjs';

export async function registerAntigravityParent(scope, sourceHash, root) {
  if (scope.runtime !== 'antigravity' || !scope.session || scope.dataSource !== 'explicit')
    throw new Error('parent registration requires explicit Antigravity session/data');
  const source = inspectDistribution(root);
  if (sourceHash !== source.hash) throw new Error('parent source hash differs from loaded artifact');
  const observed = fs.readFileSync(scope.events, 'utf8').trim().split('\n').map(line => JSON.parse(line));
  if (!observed.some(row => row.runtime === scope.runtime && row.repoKey === scope.repoKey &&
      row.code === 0 && row.event?.session_id === scope.sessionId && row.event?.harness_native_event === 'PreInvocation' &&
      row.observation?.kind === 'executing-wrapper' && row.observation.workspace === scope.top &&
      row.observation.source?.root === source.root && row.observation.source?.hash === source.hash))
    throw new Error('parent context not observed in this scope');
  const record = {version: 1, kind: 'parent', evidence: 'operator-attested', runtime: scope.runtime,
    repoKey: scope.repoKey, sessionId: scope.sessionId, workspace: scope.top,
    source: {root: source.root, hash: source.hash}};
  const file = path.join(scope.session, 'antigravity-parent.json');
  withStateLock(file, () => {
    if (fs.existsSync(file)) {
      if (fs.readFileSync(file, 'utf8') !== JSON.stringify(record)) throw new Error('parent registration conflict');
    } else fs.writeFileSync(file, JSON.stringify(record), {flag: 'wx', mode: 0o600});
  });
  return record;
}

// Operator attestation is a workflow trust boundary, not an OS authentication
// service.
export async function antigravityIdentity(event, {env, pluginRoot}) {
  const workspace = event.harness_workspace || event.cwd;
  const scope = await resolveState({runtime: 'antigravity', cwd: workspace, sessionId: event.session_id}, env);
  if (path.resolve(workspace) !== scope.top || !(event.cwd === scope.top || event.cwd.startsWith(scope.top + path.sep)))
    throw new Error('Antigravity execution workspace mismatch');
  if (fs.existsSync(antigravityChildFile(scope))) {
    const identity = await antigravityChildIdentity(scope, pluginRoot, env);
    if (event.harness_native_tool === 'invoke_subagent') throw new Error('child delegation unavailable');
    if (event.harness_native_tool === 'send_message' && event.tool_input.Recipient !== identity.binding.parentId)
      throw new Error('child result recipient differs from parent');
    if (!identity.active && !(event.harness_native_tool === 'send_message' &&
        event.message === identity.handshakeAck)) throw new Error('child task waits for ready/start handshake');
    if (identity.active && /^HARNESS_(?:READY|START)_ACK /.test(event.message ?? ''))
      throw new Error('repeated handshake acknowledgement');
    return identity;
  }
  validateAntigravityParent(scope, pluginRoot);
  if (event.harness_native_tool === 'invoke_subagent') authorizeAntigravitySpawn(scope, event, pluginRoot);
  if (event.harness_native_tool === 'send_message') authorizeAntigravityMessage(scope, event, pluginRoot);
  return {kind: 'parent'};
}
