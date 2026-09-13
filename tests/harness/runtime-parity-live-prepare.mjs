import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {installDistribution} from '../../plugins/harness/lib/runtime/parity-install.mjs';
import {inspectDistribution} from '../../plugins/harness/lib/distribution.mjs';

// Preparation only: never installs into a user profile or grants provider trust.
const root = path.resolve(process.argv[2] ?? '');
if (!process.argv[2] || fs.existsSync(root)) throw new Error('supply a new absolute evidence directory');
const source = fileURLToPath(new URL('../../plugins/harness', import.meta.url));
fs.mkdirSync(root, {recursive: true, mode: 0o700});
const json = (file, value) => fs.writeFileSync(file, JSON.stringify(value, null, 2) + '\n', {mode: 0o600});
const git = (args, cwd) => { const run = spawnSync('git', args, {cwd, encoding: 'utf8'}); if (run.status !== 0) throw new Error(run.stderr); };
const main = path.join(root, 'main'); fs.mkdirSync(main);
git(['init', '-b', 'main'], main);
json(path.join(main, '.harness.json'), {default_branch: 'main', check: ['node', '-e', 'process.exit(0)'], ledger: {backend: 'github', owner: 'local-probe', project: 1}});
fs.writeFileSync(path.join(main, 'fixture.txt'), 'PARITY_M5_READ_MARKER\n');
fs.writeFileSync(path.join(main, 'CLAUDE.md'), 'Disposable parity probe. Do not contact a ledger or remote service through tools. Only execute the explicitly requested canary once; never work around denial.\n');
fs.copyFileSync(path.join(main, 'CLAUDE.md'), path.join(main, 'AGENTS.md'));
git(['add', '.'], main);
git(['-c', 'user.name=Parity Probe', '-c', 'user.email=parity@example.invalid', 'commit', '-m', 'fixture: parity workspace'], main);
git(['init', '--bare', path.join(root, 'remote.git')], root);
git(['remote', 'add', 'origin', path.join(root, 'remote.git')], main);
const artifacts = {};
for (const surface of ['claude-cli', 'codex-cli', 'antigravity-cli']) {
  const workspace = path.join(root, surface);
  git(['worktree', 'add', '-b', `probe-${surface}`, workspace], main);
  const destination = path.join(root, 'bundles', surface);
  const options = {source, surface, destination, ...(surface === 'codex-cli' ? {agentsDestination: path.join(workspace, '.codex/agents')} : {})};
  const staged = installDistribution(options);
  json(path.join(root, `${surface}-install.json`), options);
  if (surface === 'antigravity-cli') {
    fs.mkdirSync(path.join(workspace, '.agents'), {recursive: true});
    // Official workspace discovery of projected components, without global link.
    for (const name of ['hooks.json', 'skills', 'agents']) fs.cpSync(path.join(destination, name), path.join(workspace, '.agents', name), {recursive: true});
  }
  if (surface === 'codex-cli') {
    const hooks = JSON.parse(fs.readFileSync(path.join(destination, 'hooks/codex.json'), 'utf8').replaceAll('${CLAUDE_PLUGIN_ROOT}', destination)).hooks;
    let config = '[features]\nhooks = true\n[plugins."harness@skills"]\nenabled = false\n';
    for (const [event, groups] of Object.entries(hooks)) for (const group of groups) {
      config += `\n[[hooks.${event}]]\n${group.matcher ? `matcher = ${JSON.stringify(group.matcher)}\n` : ''}`;
      for (const hook of group.hooks) config += `[[hooks.${event}.hooks]]\ntype = "command"\ncommand = ${JSON.stringify(hook.command)}\ntimeout = ${hook.timeout}\n`;
    }
    fs.writeFileSync(path.join(workspace, '.codex/config.toml'), config);
    fs.mkdirSync(path.join(workspace, '.agents/skills'), {recursive: true});
    for (const skill of staged.receipt.skills) fs.cpSync(path.join(destination, path.dirname(skill.path)), path.join(workspace, '.agents/skills', skill.name), {recursive: true});
  }
  artifacts[surface] = {workspace, bundle: destination, installedRoot: staged.receipt.installedRoot, static: staged.static, loaded: 'UNREACHED', live: 'UNREACHED'};
}
json(path.join(root, 'prepared.json'), {schemaVersion: 1, source: inspectDistribution(source), main, artifacts});
console.log(JSON.stringify({root, sourceHash: inspectDistribution(source).hash, artifacts}));
