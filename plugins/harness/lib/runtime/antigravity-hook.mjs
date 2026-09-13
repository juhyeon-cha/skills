import path from 'node:path';

const object = value => value && typeof value === 'object' && !Array.isArray(value);
const text = value => typeof value === 'string' && value.length > 0 && !/[\0\r\n]/.test(value);
const absolute = value => text(value) && path.isAbsolute(value);
const integer = value => Number.isSafeInteger(value) && value >= 0;

// Provider envelope, not a fabricated Claude SubagentStart/Stop event.
// Contract: https://antigravity.google/docs/hooks. Unknown tools fail closed;
// asynchronous execution and child identity need their own observed contracts.
export function antigravityEvent(id, raw) {
  if (!object(raw) || !text(raw.conversationId) || !Array.isArray(raw.workspacePaths) ||
      raw.workspacePaths.length !== 1 || !absolute(raw.workspacePaths[0]))
    throw new Error('Antigravity requires one absolute workspace and conversationId');
  const event = {cwd: path.resolve(raw.workspacePaths[0]), session_id: raw.conversationId,
    harness_runtime: 'antigravity', harness_native_event: {context: 'PreInvocation', guard: 'PreToolUse', stop: 'Stop'}[id],
    model: raw.modelName, transcript_path: raw.transcriptPath};
  if (id === 'context') {
    if (!integer(raw.invocationNum) || !integer(raw.initialNumSteps)) throw new Error('invalid PreInvocation counters');
    event.hook_event_name = 'SessionStart';
    event.invocation_num = raw.invocationNum;
  } else if (id === 'stop') {
    if (!integer(raw.executionNum) || typeof raw.fullyIdle !== 'boolean' || !text(raw.terminationReason) ||
        (raw.error != null && typeof raw.error !== 'string')) throw new Error('invalid Antigravity Stop');
    Object.assign(event, {hook_event_name: 'Stop', fully_idle: raw.fullyIdle,
      execution_num: raw.executionNum, termination_reason: raw.terminationReason, runtime_error: raw.error || ''});
  } else if (id === 'guard') {
    if (!object(raw.toolCall) || !text(raw.toolCall.name) || !object(raw.toolCall.args) || !integer(raw.stepIdx))
      throw new Error('invalid Antigravity toolCall');
    const {name, args} = raw.toolCall;
    Object.assign(event, {hook_event_name: 'PreToolUse', tool_name: name, tool_input: args,
      harness_native_tool: name, agent_id: raw.conversationId, step_idx: raw.stepIdx});
    const files = {view_file: ['Read', 'AbsolutePath'], write_to_file: ['Write', 'TargetFile'],
      replace_file_content: ['Edit', 'TargetFile'], multi_replace_file_content: ['Edit', 'TargetFile'],
      list_dir: ['Glob', 'DirectoryPath'], find_by_name: ['Glob', 'SearchDirectory'], grep_search: ['Grep', 'SearchPath']};
    if (files[name]) {
      const [tool, field] = files[name];
      if (!absolute(args[field])) throw new Error('absolute Antigravity file target required');
      event.tool_name = tool; event.tool_input = {file_path: args[field]};
    } else if (name === 'run_command') {
      if (typeof args.CommandLine !== 'string' || !args.CommandLine.trim() || args.CommandLine.includes('\0') || !absolute(args.Cwd)) throw new Error('Antigravity command/cwd missing');
      // Unlike Codex exec_command, this provider exposes the actual command cwd.
      event.tool_name = 'Bash'; event.tool_input = {command: args.CommandLine};
      event.cwd = path.resolve(args.Cwd);
      event.harness_workspace = path.resolve(raw.workspacePaths[0]);
    } else if (name === 'invoke_subagent') {
      if (!Array.isArray(args.Subagents) || args.Subagents.length !== 1)
        throw new Error('one registered subagent per invocation required');
      event.tool_name = 'Agent';
      event.subagents = args.Subagents;
    } else if (name === 'send_message') {
      if (!text(args.Recipient) || typeof args.Message !== 'string' || !args.Message.trim())
        throw new Error('child result message/recipient required');
      event.tool_name = 'SendMessage';
      event.recipient = args.Recipient;
      event.message = args.Message;
    } else if (name === 'manage_task' && ['list', 'status'].includes(args.Action)) {
      event.tool_name = 'Read'; event.tool_input = {};
    } else if (name === 'list_permissions') {
      event.tool_name = 'Read'; event.tool_input = {};
    } else throw new Error(`Antigravity tool contract UNREACHED: ${name}`);
  } else throw new Error('unsupported Antigravity hook; native child lifecycle is not available');
  return event;
}

export function antigravityOutput(id, run) {
  if (id === 'guard') return JSON.stringify({decision: run.code === 0 ? 'allow' : 'deny', reason: run.stderr || undefined});
  if (id === 'context') {
    const context = JSON.parse(run.stdout).hookSpecificOutput?.additionalContext;
    if (typeof context !== 'string') throw new Error('context output missing');
    return JSON.stringify({injectSteps: [{ephemeralMessage: context}]});
  }
  if (id === 'stop') {
    const output = run.stdout ? JSON.parse(run.stdout) : {};
    return JSON.stringify({decision: output.decision === 'block' ? 'continue' : 'stop',
      reason: output.reason || run.stderr || undefined});
  }
  throw new Error('unsupported Antigravity output');
}
