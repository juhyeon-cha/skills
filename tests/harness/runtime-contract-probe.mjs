// Explicit live-probe preparation/collection; never called by run-all.sh.
// prepare <claude|codex> <new-directory>: creates isolated settings and a Git fixture.
// collect <directory> <session-id> <observed-cli-version>: inspects recorded raw hooks.
// CLI invocation and authentication remain explicit; no user config is changed here.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {inspectRuntimeContract, roleSignals} from '../../plugins/harness/lib/runtime/role-contract.mjs';

const source = fileURLToPath(new URL('../../plugins/harness/agents/reviewer.md', import.meta.url));
const digest = file => ({path: file, sha256: createHash('sha256').update(fs.readFileSync(file)).digest('hex')});
const [action, arg, arg2, version] = process.argv.slice(2);
try {
  if (action === 'prepare' && ['claude', 'codex'].includes(arg) && arg2) {
    const base = path.resolve(arg2);
    fs.mkdirSync(base, {mode: 0o700}); // Refuse existing directories, including user homes.
    const repo = path.join(base, 'repo');
    const home = path.join(base, 'home');
    fs.mkdirSync(repo); fs.mkdirSync(home, {mode: 0o700});
    execFileSync('git', ['init', '-q', repo]);
    const recorder = path.join(base, 'record.mjs');
    fs.writeFileSync(recorder, `import fs from 'node:fs'; const raw=JSON.parse(fs.readFileSync(0,'utf8')); fs.appendFileSync(${JSON.stringify(path.join(base, 'events.jsonl'))},JSON.stringify(raw)+'\\n');\n`);
    const command = `node '${recorder.replaceAll("'", "'\\''")}'`;
    const hooks = {hooks: Object.fromEntries(['SessionStart', 'PreToolUse', 'PostToolUse', 'SubagentStart', 'SubagentStop'].map(event => [event, [{hooks: [{type: 'command', command, timeout: 10}]}]]))};
    const config = path.join(base, 'settings.json');
    fs.writeFileSync(config, JSON.stringify(hooks, null, 2));
    const roleBody = fs.readFileSync(source, 'utf8').replace(/^---[\s\S]*?---\s*/, '');
    const canary = '\nThis invocation is a runtime capability canary, not a task review. Run pwd once and return SIGNAL: LGTM followed by PROBE_ROLE_RETURN. Do not access ledger or edit files.\n';
    if (arg === 'codex') {
      fs.writeFileSync(path.join(home, 'config.toml'), '');
      fs.writeFileSync(path.join(home, 'hooks.json'), JSON.stringify(hooks, null, 2));
      fs.mkdirSync(path.join(home, 'agents'));
      fs.writeFileSync(path.join(home, 'agents/harness-reviewer.toml'), `name = "harness-reviewer"\ndescription = "Harness reviewer capability canary"\ndeveloper_instructions = ${JSON.stringify(roleBody + canary)}\n`);
    } else {
      fs.writeFileSync(path.join(base, 'agents.json'), JSON.stringify({'harness-reviewer': {description: 'Harness reviewer capability canary', prompt: roleBody + canary}}));
    }
    fs.writeFileSync(path.join(base, 'prompt.txt'), 'Runtime capability test in this disposable Git repository. Run pwd using the shell tool, create probe.txt with content PROBE_EDIT using the file editing tool, then delegate to custom agent harness-reviewer to run pwd and return its SIGNAL and PROBE_ROLE_RETURN. Wait for the agent result and repeat it in your final response. Do not access any ledger, credentials, network, or files outside this fixture.');
    fs.writeFileSync(path.join(base, 'metadata.json'), JSON.stringify({runtime: arg, origin: 'live', role: 'harness-reviewer', source: digest(source), config: digest(arg === 'codex' ? path.join(home, 'hooks.json') : config)}, null, 2));
    console.log(`Prepared ${base}; no model session has run. Authenticate explicitly and run the CLI with these isolated settings. Windows invocation is not established by this POSIX hook command.`);
  } else if (action === 'collect' && arg && arg2 && version) {
    const base = path.resolve(arg);
    const metadata = JSON.parse(fs.readFileSync(path.join(base, 'metadata.json'), 'utf8'));
    for (const item of [metadata.source, metadata.config]) {
      if (digest(item.path).sha256 !== item.sha256) throw new Error(`source/config changed: ${item.path}`);
    }
    const events = fs.readFileSync(path.join(base, 'events.jsonl'), 'utf8').trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
    const evidence = {...metadata, signals: roleSignals(fs.readFileSync(metadata.source.path, 'utf8')), sessionId: arg2, version, events};
    fs.writeFileSync(path.join(base, 'evidence.json'), JSON.stringify(evidence, null, 2));
    const result = inspectRuntimeContract(evidence);
    console.log(JSON.stringify(result));
    process.exitCode = result.status === 'PASS' ? 0 : 1;
  } else throw new Error('usage: prepare <claude|codex> <new-directory> | collect <directory> <session-id> <observed-cli-version>');
} catch (error) {
  console.error(`UNREACHED: ${error.message}`);
  process.exitCode = 1;
}
