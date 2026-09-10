// Explicit exec --json adapter observed with Codex 0.153.4. Native rollout
// records (timestamp/type/payload) are a different, unsupported format.
export function decodeCodex(rows, sessionId) {
  const errors = []; const items = new Map(); let thread = 0;
  for (const [index, row] of rows.entries()) {
    if (!['thread.started', 'turn.started', 'turn.completed', 'turn.failed', 'error', 'item.started', 'item.updated', 'item.completed'].includes(row.type) || row.payload) { errors.push('unsupported Codex exec record'); continue; }
    if (row.type === 'thread.started') { thread++; if (row.thread_id !== sessionId) errors.push('Codex thread mismatch'); }
    if (row.type === 'turn.failed' || row.type === 'error') errors.push('Codex execution failed');
    if (row.type.startsWith('item.')) {
      const item = row.item;
      if (!item?.id || !['collab_tool_call', 'agent_message', 'command_execution', 'file_change', 'mcp_tool_call', 'web_search', 'todo_list', 'reasoning', 'error'].includes(item.type)) { errors.push('Codex item missing/unsupported'); continue; }
      const previous = items.get(item.id);
      if (previous?.event === 'item.completed') errors.push('Codex item repeated after completion');
      items.set(item.id, {...item, event: row.type, index});
    }
  }
  if (thread !== 1) errors.push('Codex thread inventory missing/ambiguous');
  const tools = [...items.values()].filter(item => item.type === 'collab_tool_call');
  return {format: 'codex-exec-0.153-jsonl', tools, errors};
}

export function codexOutcome(decoded, call, boundary = 0) {
  if (decoded.errors.length) throw new Error(decoded.errors.join('; '));
  const spawn = decoded.tools.find(item => item.id === call.nativeCallId && item.tool === 'spawn_agent' && item.index >= boundary);
  if (!spawn || spawn.event !== 'item.completed' || spawn.status !== 'completed' || spawn.sender_thread_id !== call.parentAgentId || spawn.receiver_thread_ids?.length !== 1) throw new Error('native spawn identity/completion missing');
  const agentId = spawn.receiver_thread_ids[0];
  const later = decoded.tools.filter(item => item.index > spawn.index && item.receiver_thread_ids?.includes(agentId));
  if (later.some(item => item.tool !== 'wait')) throw new Error('child has follow-up/reuse or unsupported operation');
  const wait = later.at(-1);
  const state = wait?.agents_states?.[agentId];
  if (!wait || wait.event !== 'item.completed' || wait.status !== 'completed' || wait.sender_thread_id !== call.parentAgentId || state?.status !== 'completed' || typeof state.message !== 'string') throw new Error('native wait/instance completion missing');
  return {agentId, state: 'completed', nativeText: state.message};
}
