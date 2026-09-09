import {roleName, textOf} from './common.mjs';

// Claude Code 2.1 JSONL: Agent/Task tool_use inventory, toolUseResult and
// task-notification completion, explicit child attributionAgent identity.
export function decodeClaude(parent, childRecords, sessionId) {
  const calls = new Map(); const errors = []; const children = new Map();
  for (const record of parent) {
    if (!['assistant', 'user', 'system', 'progress', 'file-history-snapshot', 'queue-operation', 'summary'].includes(record.type)) errors.push('unsupported Claude record type');
    if (record.sessionId && record.sessionId !== sessionId) errors.push('Claude session mismatch');
    for (const block of Array.isArray(record.message?.content) ? record.message.content : []) {
      if (record.type === 'assistant' && block.type === 'tool_use' && ['Agent', 'Task'].includes(block.name)) {
        if (!block.id || calls.has(block.id)) { errors.push('ambiguous Claude invocation'); continue; }
        calls.set(block.id, {id: block.id, role: roleName(block.input?.subagent_type), reason: block.input?.subagent_type && !roleName(block.input.subagent_type) ? 'unknown invocation role' : undefined, timestamp: record.timestamp, completed: false});
      }
    }
    const result = record.toolUseResult;
    if (result?.agentId) {
      const toolId = record.message?.content?.find?.(block => block.type === 'tool_result')?.tool_use_id;
      const call = calls.get(toolId);
      if (!call) { errors.push(`completion/launch without invocation inventory: ${result.agentId}`); continue; }
      if (call.agentId && call.agentId !== result.agentId) { errors.push('Claude child identity changed'); continue; }
      call.agentId = result.agentId;
      const explicitRole = roleName(result.agentType);
      if (result.agentType && (!explicitRole || (call.role && call.role !== explicitRole))) call.reason = 'Claude role mismatch';
      call.role ??= explicitRole;
      if (children.has(result.agentId) && children.get(result.agentId) !== call.id) call.reason = 'reused Claude instance';
      children.set(result.agentId, call.id);
      call.completed = result.status === 'completed'; call.timestamp = record.timestamp ?? call.timestamp;
    }
    const content = record.message?.content;
    if (typeof content === 'string' && content.includes('<task-notification>')) {
      const id = /<task-id>([^<]+)<\/task-id>/.exec(content)?.[1];
      const status = /<status>([^<]+)<\/status>/.exec(content)?.[1];
      const call = calls.get(children.get(id));
      if (!call) errors.push(`notification without invocation inventory: ${id ?? 'unknown'}`);
      else { call.completed = status === 'completed'; call.timestamp = record.timestamp ?? call.timestamp; }
    }
  }
  for (const call of calls.values()) {
    try {
      if (!call.agentId) throw new Error('child identity missing');
      const child = childRecords(call.agentId);
      if (child.some(record => !['assistant', 'user', 'system', 'progress', 'queue-operation', 'summary'].includes(record.type))) throw new Error('unsupported child transcript record');
      const identities = new Set(child.filter(record => record.attributionAgent).map(record => roleName(record.attributionAgent)));
      if (identities.has(undefined) || identities.size > 1) throw new Error('unknown/conflicting child role');
      const attribution = [...identities][0];
      if (attribution && call.role && attribution !== call.role) throw new Error('child role differs from invocation');
      call.role ??= attribution;
      if (!call.role) throw new Error('role unidentified');
      call.texts = child.filter(record => record.type === 'assistant').map(textOf).filter(text => typeof text === 'string' && text.trim());
      call.messages = child.filter(record => record.type === 'assistant').map((record, index) => ({id: record.message?.id, usage: record.message?.usage, index, tools: (Array.isArray(record.message?.content) ? record.message.content : []).filter(block => block.type === 'tool_use').map(block => block.name)}));
    } catch (error) { call.reason = error.message; }
    if (!call.completed) call.reason ??= 'required invocation unfinished';
  }
  if (!calls.size) errors.push('invocation inventory empty; completion records are not the population');
  return {format: 'claude-code-2.1-jsonl', calls: [...calls.values()], errors};
}
