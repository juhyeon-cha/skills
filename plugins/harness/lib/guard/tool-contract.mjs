const aliases = new Map([
  ['request_user_input_async', 'request_user_input_async'],
  ['functions.request_user_input_async', 'request_user_input_async'],
  ['clock.sleep', 'clock.sleep'], ['clocksleep', 'clock.sleep'],
  ...['read_thread', 'list_projects', 'create_thread'].flatMap(name => [
    [`mcp__codex_app__${name}`, `codex_app.${name}`],
    [`mcp__codex_app.${name}`, `codex_app.${name}`],
  ]),
  ['mcp__cua_repl__js', 'cua.js'], ['mcp__cua_repl.js', 'cua.js'],
]);

// Classify only effects used by harness policy. The host owns tool schemas
// and permission checks; opaque tools do not acquire a read-only claim here.
export function additionalToolContract(name) {
  const canonical = aliases.get(name);
  if (!canonical) return null;
  const effect = {
    request_user_input_async: 'question',
    'clock.sleep': 'wait',
    'codex_app.read_thread': 'read',
    'codex_app.list_projects': 'read',
    'codex_app.create_thread': 'task-create',
    'cua.js': 'host-managed',
  }[canonical];
  return {canonical, effect, roleIndependent: effect !== 'task-create'};
}
