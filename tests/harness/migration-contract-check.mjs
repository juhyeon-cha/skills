import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {loadConfig} from '../../plugins/harness/lib/config.mjs';
import {inspectDistribution} from '../../plugins/harness/lib/distribution.mjs';
import {registerRoles, verifyRegistration} from '../../plugins/harness/lib/roles.mjs';
import {createChallenge, diagnose} from '../../plugins/harness/lib/doctor.mjs';

assert.notEqual(process.platform, 'win32', 'UNREACHED: migration fixture uses existing POSIX adapters');
assert.ok(!process.argv[2] || process.argv[2] === '--missing-artifact', 'unknown fixture argument');
const source = fileURLToPath(new URL('../../plugins/harness', import.meta.url));
const temp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'harness-migration-')));
const repo = path.join(temp, 'repo'), wt = path.join(repo, '.claude/worktrees/기존 story');
const previous = path.join(temp, 'previous'), candidate = path.join(temp, 'candidate');
let reached = 0;
const check = (value, message) => { assert.ok(value, message); reached++; console.log(`PASS ${message}`); };
const env = {...process.env, HOME: path.join(temp, 'home'), HARNESS_ROOT: repo,
  HARNESS_DATA_DIR: path.join(temp, '공유 data'), GIT_CONFIG_GLOBAL: os.devNull,
  GIT_CONFIG_NOSYSTEM: '1', GIT_ALLOW_PROTOCOL: 'file', GIT_TERMINAL_PROMPT: '0'};
for (const key of Object.keys(env)) if ((key.startsWith('GIT_') && !['GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM', 'GIT_ALLOW_PROTOCOL', 'GIT_TERMINAL_PROMPT'].includes(key)) || /^(?:CLAUDE_PLUGIN|PLUGIN_|HARNESS_RUNTIME|HARNESS_SESSION)/.test(key)) delete env[key];
const run = (argv, cwd = repo) => {
  const r = spawnSync(argv[0], argv.slice(1), {cwd, env, encoding: 'utf8', timeout: 30000});
  if (r.error) throw r.error; return r;
};
const ok = r => { assert.equal(r.status, 0, r.stderr || r.stdout); return r.stdout.trim(); };
const json = r => JSON.parse(ok(r));
const write = (file, value) => { fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, value); };
const bytes = file => fs.readFileSync(file, 'utf8');
try {
  fs.cpSync(source, previous, {recursive: true}); fs.cpSync(source, candidate, {recursive: true});
  if (process.argv[2]) fs.unlinkSync(path.join(candidate, 'agents/evaluator.md'));
  const initial = inspectDistribution(candidate);
  check(initial.hash === inspectDistribution(previous).hash, 'fixture starts from exact source artifacts');
  // These are candidate snapshots of the current APIs, not the released legacy runtime.
  fs.appendFileSync(path.join(candidate, 'docs/workspace.md'), '\nFixture candidate artifact difference.\n');
  const next = inspectDistribution(candidate), old = inspectDistribution(previous);
  check(next.version === old.version && next.hash !== old.hash, 'same plugin version cannot stand for equal artifacts');
  const oldRoles = registerRoles('codex', path.join(temp, 'old-agents'), previous);
  const nextRoles = registerRoles('codex', path.join(temp, 'new-agents'), candidate);
  check(verifyRegistration(oldRoles) && verifyRegistration(nextRoles), 'each immutable root has matching role projections');
  const mixed = {...oldRoles, root: candidate};
  assert.throws(() => verifyRegistration(mixed), /drift/); reached++;
  const oldRoleFile = oldRoles.roles[0].file, oldRoleBytes = bytes(oldRoleFile);
  assert.throws(() => registerRoles('codex', path.dirname(oldRoleFile), candidate), /already differs/); reached++;
  check(bytes(oldRoleFile) === oldRoleBytes, 'upgrade refuses to overwrite previous projections');
  const foreign = path.join(temp, 'foreign-agents'); fs.mkdirSync(foreign);
  const foreignFile = path.join(foreign, path.basename(oldRoleFile)); write(foreignFile, 'name = "foreign"\n');
  assert.throws(() => registerRoles('codex', foreign, candidate), /already differs/); reached++;
  check(bytes(foreignFile) === 'name = "foreign"\n', 'foreign modified generated filename is preserved');
  const challenge = path.join(temp, 'challenge');
  createChallenge(challenge, 'codex', previous, oldRoles, previous);
  const mismatch = diagnose(previous, challenge, 'session', candidate);
  check(mismatch.static === 'UNREACHED' && mismatch.live === 'UNREACHED', 'same-version old install cannot certify candidate source');
  const missing = diagnose(candidate, undefined, undefined, candidate);
  check(missing.static === 'PASS' && missing.loaded === 'UNREACHED' && missing.live === 'UNREACHED', 'static artifact never certifies current-session activation');
  assert.throws(() => verifyRegistration({...nextRoles, version: 99}), /registration missing/); reached++;
  check(verifyRegistration(oldRoles).root === previous, 'rollback retains original root and matching receipt');

  fs.mkdirSync(repo); fs.mkdirSync(env.HOME);
  const git = (...args) => ok(run(['git', '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false', ...args]));
  git('init', '-q'); git('commit', '--allow-empty', '-qm', 'fixture'); git('worktree', 'add', '-qb', 'worktree-migration', wt);
  const legacyConfig = {ledger: {backend: 'github', project: '5'}, default_branch: 'main',
    check: 'printf gate', bootstrap: 'printf "legacy\\n" >> attempts', custom: {preserve: true}};
  const configFile = path.join(wt, '.harness.json'), legacyBytes = JSON.stringify(legacyConfig);
  write(configFile, legacyBytes); write(path.join(repo, '.harness.json'), legacyBytes);
  check((await loadConfig(wt)).config.ledger.project === '5', 'unversioned numeric-string coordinates retain legacy shape');
  // Only the adapter is substituted. No real ledger backend command is reachable.
  const sentinel = path.join(temp, 'unexpected-adapter'); env.MIGRATION_SENTINEL = sentinel;
  write(path.join(candidate, 'scripts/ledger.mjs'), `import fs from 'node:fs';
const args=process.argv.slice(2);if(args[0]==='--root')args.splice(0,2);
if(args[0]==='wire-worktree')process.exit(0);
if(args[0]==='show')console.log('[{"id":"migration-1","status":"in_progress","actor":"actor-original"}]');
else {fs.appendFileSync(process.env.MIGRATION_SENTINEL,'unexpected\\n');process.exit(97);}
`);
  const forbidden = run([process.execPath, path.join(candidate, 'scripts/ledger.mjs'), 'create']);
  check(forbidden.status === 97 && bytes(sentinel) === 'unexpected\n', 'fake adapter rejects and records mutation attempts');
  fs.unlinkSync(sentinel); // Exclude only this deliberate negative control.
  const workspace = (action, runtime = 'codex') => {
    env.HARNESS_RUNTIME = runtime;
    return run([process.execPath, path.join(candidate, 'scripts/workspace.mjs'), action, wt]);
  };
  const initialIdentity = json(workspace('inspect'));
  const settings = path.join(wt, '.claude/settings.json');
  const oldSettings = JSON.stringify({hooks: {PostToolUse: [{matcher: 'EnterWorktree', hooks: [{type: 'command', command: 'repository-owned-setup'}]}]}});
  write(settings, oldSettings);
  const marker = path.join(repo, '.claude/worktrees/.bootstrapped-migration'); write(marker, 'old-marker');
  const dirty = path.join(wt, 'uncommitted.txt'); write(dirty, 'retain my work');
  const credential = path.join(wt, 'config.yaml'); write(credential, 'fixture-only opaque bytes');
  const rejected = workspace('enter');
  check(rejected.status !== 0 && rejected.stderr.includes('LEGACY_HOOK_UNVERIFIED'), 'legacy own hook and marker do not create readiness');
  check(!fs.existsSync(path.join(wt, 'attempts')) && bytes(marker) === 'old-marker', 'legacy detection avoids duplicate preparation and preserves marker');
  // Target-owned cutover; the source installer never performs this edit itself.
  write(settings, JSON.stringify({hooks: {}}));
  check(json(workspace('enter', 'claude')).top === wt, 'existing legacy-layout workspace reenters without recreation');
  check(json(workspace('ready')).canDelegate === true && bytes(path.join(wt, 'attempts')) === 'legacy\n', 'legacy bootstrap retains Bash semantics');
  ok(workspace('enter')); check(bytes(path.join(wt, 'attempts')) === 'legacy\n', 'other runtime reuses prepared workspace');
  const modern = {...legacyConfig, schema_version: 1, ledger: {...legacyConfig.ledger, project: 5},
    bootstrap: {argv: [process.execPath, '-e', 'require("node:fs").appendFileSync("attempts", "modern\\n")']}, preparation: {inputs: ['input.txt']}};
  write(path.join(wt, 'input.txt'), 'v1'); write(configFile, JSON.stringify(modern));
  check(workspace('ready').status !== 0, 'changed config cannot reuse previous readiness');
  ok(workspace('enter')); ok(workspace('enter', 'claude'));
  check(bytes(path.join(wt, 'attempts')) === 'legacy\nmodern\n', 'schema 1 argv cutover runs once across reentry');
  check((await loadConfig(wt)).config.custom.preserve, 'modern configuration preserves repository extension');
  write(configFile, legacyBytes); write(settings, oldSettings);
  check(workspace('ready').status !== 0, 'restored legacy hook remains unverified by new runtime');
  check(bytes(configFile) === legacyBytes && bytes(settings) === oldSettings, 'repository rollback restores exact config and hook bytes');
  const finalIdentity = json(workspace('inspect'));
  check(finalIdentity.gitDir === initialIdentity.gitDir && finalIdentity.branch === initialIdentity.branch, 'upgrade and rollback preserve Git registration identity');
  check(bytes(dirty) === 'retain my work' && bytes(credential) === 'fixture-only opaque bytes' && bytes(marker) === 'old-marker', 'dirty work, credential sentinel and old marker survive');

  const state = await import(pathToFileURL(path.join(candidate, 'lib/state.mjs')));
  const olderState = await import(pathToFileURL(path.join(previous, 'lib/state.mjs')));
  const actors = path.join(temp, 'legacy-actors.tsv'), guard = path.join(temp, 'legacy-guard.tsv');
  env.HARNESS_SESSION_ACTOR_LOG = actors; env.HARNESS_GUARD_LOG = guard;
  write(actors, 'legacy actor\n'); write(guard, 'legacy guard\n'); write(path.join(env.HARNESS_DATA_DIR, 'stop-resume-cancel'), 'legacy cancel');
  const scope = await state.resolveState({runtime: 'codex', cwd: wt, sessionId: 'session-old'}, env);
  check(scope.legacy.status === 'UNVERIFIED' && state.readActors(scope).status === 'UNREACHED' && !state.isCancelled(scope), 'legacy data is preserved without becoming verified binding/cancellation');
  await state.bindActor(scope, {ledgerRoot: repo, task: 'migration-1', actor: 'actor-original'}, env);
  const resumed = await state.resolveState({runtime: 'codex', cwd: wt, sessionId: 'session-new'}, env);
  await state.bindActor(resumed, {ledgerRoot: repo, task: 'migration-1', actor: 'actor-original'}, env);
  check(state.readActors(resumed).actors[0] === 'actor-original' && resumed.session !== scope.session, 'resumed session explicitly retains ledger-confirmed actor');
  state.cancelSession(scope);
  check(state.isCancelled(scope) && !state.isCancelled(resumed), 'cancellation remains session scoped after resume');
  const restored = await olderState.resolveState({runtime: 'codex', cwd: wt, sessionId: 'session-old'}, env);
  check(restored.session === scope.session && olderState.readActors(restored).actors[0] === 'actor-original', 'same state-schema candidate rollback retains scoped observations');
  check(bytes(actors) === 'legacy actor\n' && bytes(guard) === 'legacy guard\n' && bytes(scope.legacy.cancel) === 'legacy cancel', 'legacy rollback files stay byte-identical');
  check(bytes(configFile) === legacyBytes && !fs.existsSync(sentinel), 'state operations leave config unchanged; only fixture show/wire reached');
  check(reached === 32, 'all migration phases reached');
  console.log(`Migration contract: ${reached} assertions; host=${process.platform}; actual legacy runtime load, live workflow and native Windows UNREACHED`);
} finally { fs.rmSync(temp, {recursive: true, force: true}); }
