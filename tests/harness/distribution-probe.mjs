// Explicit isolated installation probe; not part of the default test suite.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {pluginRoot, readJson} from '../../plugins/harness/lib/distribution.mjs';
import {registerRoles} from '../../plugins/harness/lib/runtime/roles.mjs';
import {createChallenge, diagnose} from '../../plugins/harness/lib/runtime/doctor.mjs';

const [action, directory, installed] = process.argv.slice(2);
const base = fs.realpathSync(directory);
const json = (file, value) => fs.writeFileSync(path.join(base, file), JSON.stringify(value, null, 2));
if (action === 'prepare') {
  const target = path.join(base, 'market/plugins/harness');
  if (readJson(path.join(target, '.codex-plugin/plugin.json')).name !== 'harness' || fs.existsSync(path.join(base, 'home'))) throw new Error('expected fresh scaffold');
  fs.rmSync(target, {recursive: true}); fs.cpSync(pluginRoot, target, {recursive: true});
  fs.mkdirSync(path.join(base, 'home'), {mode: 0o700});
  const repo = path.join(base, 'repo'); fs.mkdirSync(repo);
  const git = (...args) => execFileSync('git', ['-C', repo, ...args], {encoding: 'utf8'}).trim();
  git('init', '-q'); git('config', 'user.name', 'Fixture'); git('config', 'user.email', 'fixture@example.invalid');
  fs.writeFileSync(path.join(repo, 'README.md'), 'Disposable installation diagnostic. No ledger is configured.\n');
  git('add', '.'); git('commit', '-qm', 'fixture base');
  const workspace = path.join(repo, '.claude/worktrees/fixture'); git('worktree', 'add', '-qb', 'fixture', workspace);
  const commit = git('rev-parse', 'HEAD');
  fs.mkdirSync(path.join(base, 'unconfigured'));
  fs.writeFileSync(path.join(base, 'home/config.toml'), `model = "gpt-5.6-terra"\n[projects.${JSON.stringify(base)}]\ntrust_level = "trusted"\n`);
  const recorder = path.join(base, 'raw-recorder.mjs');
  fs.writeFileSync(recorder, `import fs from 'node:fs';fs.appendFileSync(${JSON.stringify(path.join(base, 'raw-events.jsonl'))},JSON.stringify(JSON.parse(fs.readFileSync(0,'utf8')))+'\\n');\n`);
  json('home/hooks.json', {hooks: {PreToolUse: [{hooks: [{type: 'command', command: `node '${recorder}'`, timeout: 10}]}]}});
  const message = `HARNESS_ROOT=${base}/unconfigured; worktree=${workspace}; task=fixture#1; commits=${commit}. Branch fixture. HEAD ${commit}, working tree clean. This disposable diagnostic has no configured ledger or acceptance. Read the local commit if your role permits it; report the missing contract using your defined first-line SIGNAL when required. Do not edit files, call remote services or create a task. Use your registered production role instructions.`;
  fs.writeFileSync(path.join(base, 'prompt.txt'), `This is an isolated installation capability diagnostic, not story development. Run a single safe pwd shell command with explicit workdir ${base}/unconfigured (different from session cwd), then delegate one child each to native custom harness-implementer, harness-reviewer and harness-evaluator. Send each: ${message}\nWait for all three results, report their SIGNALs. No changes or network/ledger mutations. Do not call setup/status or create a story.`);
  console.log(JSON.stringify({base, workspace}));
} else if (action === 'challenge') {
  const registration = registerRoles('codex', path.join(base, 'home/agents'), installed);
  json('registration.json', registration);
  console.log(JSON.stringify(createChallenge(path.join(base, 'state'), 'codex', installed, registration)));
} else if (action === 'collect') {
  const challenge = readJson(path.join(base, 'state/challenge.json'));
  const lines = fs.readFileSync(path.join(base, 'state/receipts.jsonl'), 'utf8').trim().split('\n').map(JSON.parse);
  const sessionId = lines.find(e => e.receipt.hook === 'context')?.receipt.sessionId;
  const metadata = {installedRoot: challenge.artifact.root, state: path.join(base, 'state'), sessionId};
  json('evidence.json', metadata);
  const result = diagnose(metadata.installedRoot, metadata.state, sessionId); json('diagnosis.json', result);
  console.log(JSON.stringify(result)); process.exitCode = result.live === 'PASS' ? 0 : 1;
} else throw new Error('prepare|challenge|collect <base> [installed root]');
