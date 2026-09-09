import fs from 'node:fs';
import path from 'node:path';
import {literalShellWords} from './workspace-command.mjs';
import {resolveState} from './state.mjs';

// Only a single literal invocation of the loaded artifact receives coordinate
// semantics. Shell composition, arbitrary Node scripts and unknown argv receive
// no exception. This classifier never runs a CLI, repository gate or backend.
export async function commonCommand(command, {pluginRoot, cwd, dialect, env}) {
  const words = literalShellWords(command, {dialect, cwd});
  if (!words || !['node', 'node.exe', process.execPath].includes(words[0]) || !path.isAbsolute(words[1] ?? '')) return null;
  let relative;
  try {
    relative = path.relative(fs.realpathSync(pluginRoot), fs.realpathSync(words[1])).split(path.sep).join('/');
  } catch { return null; }
  const args = words.slice(2), result = {entry: relative, effect: 'read', paths: [], writes: [], remote: false};
  const absolute = value => typeof value === 'string' && path.isAbsolute(value) && !/[\0\r\n]/.test(value);
  const rootArgs = () => args.length >= 2 && args[0] === '--root' && absolute(args[1]);
  if (['checks/board-check.mjs', 'checks/rules-check.mjs', 'checks/guardrail-check.mjs'].includes(relative)) {
    return rootArgs() && args.length === 2 ? result : null;
  }
  if (relative === 'checks/ledger-check.mjs') {
    const root = rootArgs() ? args[1] : args[0];
    const rest = args.slice(rootArgs() ? 2 : 1);
    if (!absolute(root) || rest.some(value => value !== '--push') || rest.length > 1) return null;
    result.remote = rest.length > 0 || Boolean(env.LEDGER_CHECK_PUSH);
    result.effect = result.remote ? 'remote' : 'read'; return result;
  }
  if (relative === 'checks/workspace-check.mjs') return args.length === 1 && absolute(args[0]) ? result : null;
  if (relative === 'scripts/board.mjs') {
    if (!rootArgs() || args.length !== 3 || !/^(?:all|backlog|adr|\d{4}-S\d{2})$/.test(args[2])) return null;
    result.effect = 'projection'; result.writes = [path.join(args[1], 'docs')]; return result;
  }
  if (relative === 'scripts/config.mjs') {
    if (!absolute(args[1])) return null;
    if (args[0] === 'validate' && args.length === 2) return result;
    if (args[0] !== 'run' || args.length !== 3 || !['check', 'bootstrap'].includes(args[2])) return null;
    // A configured check is a grader's gate, but can execute arbitrary repository
    // code. Its repository stays a protected write candidate on main.
    result.effect = args[2] === 'check' ? 'gate' : 'prepare'; result.paths = [args[1]]; return result;
  }
  if (relative === 'scripts/guard-log.mjs') {
    while (args[0]?.startsWith('--')) {
      const option = args.shift(), value = args.shift();
      if (!['--runtime', '--repo', '--data', '--log'].includes(option) || (option === '--runtime' ? !['claude', 'codex'].includes(value) : !absolute(value))) return null;
    }
    return args.length <= 2 && (!args.length || ['count', 'rows'].includes(args[0])) ? result : null;
  }
  if (relative === 'scripts/transcript.mjs') {
    while (args.length) {
      const option = args.shift();
      if (['--json', '--self-check', '--help', '-h'].includes(option)) continue;
      if (!['--projects', '--scope', '--session', '--since'].includes(option)) return null;
      const value = args.shift(); if (!value || value.startsWith('--') || (['--projects', '--scope'].includes(option) && !absolute(value))) return null;
    }
    return result;
  }
  if (relative === 'scripts/state.mjs') {
    const stateEnv = {...env};
    if (args[0] === '--data') { args.shift(); const value = args.shift(); if (!absolute(value)) return null; stateEnv.HARNESS_DATA_DIR = value; }
    const [action, runtime, repository, session, ledgerRoot, task, actor] = args;
    const reading = ['paths', 'actors', 'cancelled'].includes(action), writing = ['bind', 'cancel'].includes(action);
    if (!reading && !writing) return null;
    if (!['claude', 'codex'].includes(runtime) || !absolute(repository) || !session) return null;
    if (action === 'bind' ? args.length !== 7 || !absolute(ledgerRoot) || !task || !actor : args.length !== 4) return null;
    if (writing) {
      const scope = await resolveState({runtime, cwd: repository, sessionId: session}, stateEnv);
      result.effect = 'state'; result.writes = [action === 'bind' ? scope.actors : scope.cancel];
    }
    return result;
  }
  return null;
}
