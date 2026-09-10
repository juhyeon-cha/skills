// Runtime identifiers only; bodies and SIGNAL vocabularies belong to agents/*.md.
export const roleNames = Object.freeze(['implementer', 'reviewer', 'evaluator']);
export function roleIdentifier(runtime, role) {
  if (!roleNames.includes(role) || !['claude', 'codex'].includes(runtime))
    throw new Error('unidentified runtime/role');
  return `harness${runtime === 'claude' ? ':' : '-'}${role}`;
}
export function canonicalRole(identifier) {
  for (const role of roleNames)
    for (const runtime of ['claude', 'codex']) {
      if (identifier === roleIdentifier(runtime, role)) return roleIdentifier('claude', role);
    }
  return undefined;
}

// Evidence inspection shared by runtime probes and doctor. No runtime execution.
export function roleSignals(body) {
  const line = body.split('\n').find((line) => line.includes('`<VALUE>` is one of')) ?? '';
  return [...line.matchAll(/`([A-Z_]+)`/g)].map((match) => match[1]);
}

/**
 * Inspect one role instance within a session; partial instances never combine.
 * An unambiguous start/stop lifecycle can expose a result without a tool event.
 * @param {object[]} events Hook records in observation order.
 * @param {string} session Session identifier.
 * @param {string} role Runtime role identifier.
 * @param {string} agentId Child instance identifier.
 * @returns {{started: boolean, invoked: boolean, stopped: boolean, result: unknown}}
 */
export function roleChain(events, session, role, agentId) {
  const own = events.filter(
    (e) => e?.session_id === session && e.agent_type === role && e.agent_id === agentId,
  );
  // One invocation per instance. A later response or unfinished follow-up must
  // not borrow the verdict from an earlier Stop. Other diagnostic events may
  // follow Stop, but lifecycle/tool events may not.
  const lifecycle = own.filter((e) =>
    ['SubagentStart', 'PreToolUse', 'SubagentStop'].includes(e.hook_event_name),
  );
  const unambiguous =
    lifecycle.filter((e) => e.hook_event_name === 'SubagentStart').length === 1 &&
    lifecycle.filter((e) => e.hook_event_name === 'SubagentStop').length === 1 &&
    lifecycle[0]?.hook_event_name === 'SubagentStart' &&
    lifecycle.at(-1)?.hook_event_name === 'SubagentStop';
  const start = own.findIndex((e) => e.hook_event_name === 'SubagentStart');
  const tool = own.findIndex((e, i) => i > start && e.hook_event_name === 'PreToolUse');
  const stop = own.findIndex((e, i) => i > tool && e.hook_event_name === 'SubagentStop');
  return {
    started: start >= 0,
    invoked: start >= 0 && tool >= 0,
    stopped: unambiguous && start >= 0 && tool >= 0 && stop >= 0,
    result: unambiguous ? own[stop]?.last_assistant_message : undefined,
  };
}

export function inspectRuntimeContract(evidence) {
  const missing = [];
  const require = (name, condition) => {
    if (!condition) missing.push(name);
  };
  const known = evidence && ['claude', 'codex'].includes(evidence.runtime);
  require('runtime', known);
  require('version', typeof evidence?.version === 'string' && evidence.version.length > 0);
  require('source', typeof evidence?.source?.path === 'string' &&
    /^[a-f0-9]{64}$/.test(evidence?.source?.sha256 ?? ''));
  require('config', typeof evidence?.config?.path === 'string' &&
    /^[a-f0-9]{64}$/.test(evidence?.config?.sha256 ?? ''));
  require('origin', ['fixture', 'live'].includes(evidence?.origin));
  const events = Array.isArray(evidence?.events) ? evidence.events : [];
  const session = evidence?.sessionId;
  require('session', typeof session === 'string' && session.length > 0);
  const own = events.filter((e) => e && e.session_id === session);
  require('SessionStart', own.some((e) => e.hook_event_name === 'SessionStart'));
  require('PreToolUse:Bash', own.some(
    (e) =>
      e.hook_event_name === 'PreToolUse' &&
      e.tool_name === 'Bash' &&
      typeof e.tool_input?.command === 'string',
  ));
  const fileTool = evidence?.runtime === 'codex' ? ['apply_patch'] : ['Write', 'Edit'];
  require('PreToolUse:file', own.some(
    (e) =>
      e.hook_event_name === 'PreToolUse' &&
      fileTool.includes(e.tool_name) &&
      typeof e.tool_input?.[e.tool_name === 'apply_patch' ? 'command' : 'file_path'] === 'string',
  ));
  const role = evidence?.role;
  require('role', typeof role === 'string' && role.length > 0);
  const signals = Array.isArray(evidence?.signals) ? evidence.signals : [];
  require('signals', signals.length > 0 &&
    signals.every((s) => typeof s === 'string' && /^[A-Z_]+$/.test(s)));
  const starts = own.filter(
    (e) =>
      e.hook_event_name === 'SubagentStart' &&
      e.agent_type === role &&
      typeof e.agent_id === 'string' &&
      e.agent_id.length > 0,
  );
  require('SubagentStart:role', starts.length > 0);
  const invoked = starts.filter((start) => roleChain(own, session, role, start.agent_id).invoked);
  require('PreToolUse:role', invoked.length > 0);
  // Carry the same instance through each stage; partial children cannot combine.
  const stopped = invoked
    .map((start) => roleChain(own, session, role, start.agent_id))
    .filter((chain) => chain.stopped);
  require('SubagentStop:role', stopped.length > 0);
  require('role:result', stopped.some((e) =>
    signals.includes(/^SIGNAL: ([A-Z_]+)(?:\r?\n|$)/.exec(e.result ?? '')?.[1]),
  ));
  return {
    status: missing.length ? 'UNREACHED' : 'PASS',
    origin: evidence?.origin ?? 'unknown',
    missing,
  };
}
