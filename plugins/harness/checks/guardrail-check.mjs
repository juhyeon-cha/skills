#!/usr/bin/env node
// Five surfaces: S1 policy, S2 wiring, S5 executable sources, S6 ledger sync,
// S7 Stop. All mutation/ledger/state fixtures are temporary and offline. These
// direct-handler judgments do not establish actual runtime loading or firing.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {isMain} from '../lib/ledger-view.mjs';

export const SURFACES = ['S1', 'S2', 'S5', 'S6', 'S7'];
export async function checkGuardrails({pluginRoot = fileURLToPath(new URL('../', import.meta.url)), env = process.env} = {}) {
  const temp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'harness-guardrails-')));
  const outputs = [], errors = []; let checks = 0;
  const check = async (label, fn) => { try { await fn(); checks++; if (env.GUARDRAIL_VERBOSE === '1') outputs.push(`✓ ${label}`); } catch (error) { errors.push(`✗ ${label}: ${error.message}`); } };
  const isolated = {...env, HARNESS_RUNTIME: 'claude', HARNESS_DATA_DIR: path.join(temp, 'data'), HARNESS_GUARD_LOG: path.join(temp, 'guard.tsv'), GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: path.join(temp, 'gitconfig')};
  for (const key of ['PLUGIN_ROOT', 'PLUGIN_DATA', 'CLAUDE_PLUGIN_ROOT', 'CLAUDE_PLUGIN_DATA', 'HARNESS_ROOT', 'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR', 'GIT_OBJECT_DIRECTORY', 'GIT_PREFIX']) delete isolated[key];
  fs.writeFileSync(isolated.GIT_CONFIG_GLOBAL, '');
  const main = path.join(temp, 'repo'), workspace = path.join(temp, 'workspace');
  const native = relative => import(pathToFileURL(path.join(pluginRoot, relative)).href);
  const git = (...args) => { const run = spawnSync('git', args, {env: isolated, encoding: 'utf8'}); assert.equal(run.status, 0, run.stderr); };
  let copyIndex = 0;
  const mutant = async (relative, change) => {
    const copy = path.join(temp, 'copy-' + ++copyIndex); fs.cpSync(pluginRoot, copy, {recursive: true});
    const file = path.join(copy, relative), before = fs.readFileSync(file, 'utf8'), after = change(before);
    assert.notEqual(after, before, 'source mutation did not hit'); fs.writeFileSync(file, after);
    return {root: copy, module: await import(pathToFileURL(file).href)};
  };
  try {
    git('init', '-q', main); fs.writeFileSync(path.join(main, '.harness.json'), JSON.stringify({ledger: {backend: 'beads'}}));
    git('-C', main, 'add', '.harness.json'); git('-C', main, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture');
    git('-C', main, 'worktree', 'add', '-qb', 'worktree-fixture', workspace);
    const guard = await native('lib/guard.mjs'), stop = await native('lib/stop.mjs'), state = await native('lib/state.mjs');
    const distribution = await native('lib/distribution.mjs'), ledger = await native('lib/ledger.mjs'), ledgerCheck = await native('checks/ledger-check.mjs');
    const shell = (command, role = '') => ({hook_event_name: 'PreToolUse', tool_name: 'Bash', cwd: workspace, session_id: 'policy', ...(role ? {agent_id: 'child', agent_type: role} : {}), tool_input: {command}});
    const write = (file, role = '') => ({...shell('', role), tool_name: 'Write', tool_input: {file_path: file}});
    const judge = input => guard.evaluateGuard(input, {env: isolated});
    const probes = {
      r_main_write: write(path.join(main, 'file')),
      r_main_shell: shell('rm -rf ' + path.join(main, 'file').replaceAll('\\', '/')),
      r_remote: shell('git push origin main', 'harness:implementer'),
      r_grader_write: write(path.join(workspace, 'file'), 'harness:reviewer'),
      r_grader_shell: shell('git commit -m fixture', 'harness:reviewer'),
      r_impl_bd: shell('bd -C /fixture close task', 'harness:implementer'),
      r_bd_root: shell('bd note task fixture', 'harness:implementer'),
    };
    await check('surface inventory is nonempty and complete', () => assert.deepEqual(SURFACES, ['S1', 'S2', 'S5', 'S6', 'S7']));
    const guardSource = fs.readFileSync(path.join(pluginRoot, 'lib/guard.mjs'), 'utf8');
    const defined = [...guardSource.matchAll(/^export (?:async )?function (r_\w+)\(/gm)].map(match => match[1]);
    await check('S1 definitions, registrations and probes agree in both directions', () => {
      assert.ok(defined.length >= 7); assert.deepEqual(defined.sort(), guard.RULES.map(row => row.run.name).sort());
      assert.deepEqual(defined.sort(), Object.keys(probes).sort()); assert.equal(new Set(defined).size, defined.length);
    });
    for (const [rule, input] of Object.entries(probes)) await check(`S1 ${rule} blocks and its registration-only mutant permits`, async () => {
      const blocked = await judge(input); assert.equal(blocked.code, 2, blocked.stderr); assert.equal(blocked.rule, rule);
      const copy = await mutant('lib/guard.mjs', text => text.split('\n').filter(line => !(line.startsWith('RULES.push(') && line.includes(`run: ${rule}}`))).join('\n'));
      const allowed = await copy.module.evaluateGuard(input, {env: isolated}); assert.equal(allowed.code, 0, allowed.stderr);
    });
    await check('S2 generated metadata has no drift or duplicate registration', () => distribution.inspectDistribution(pluginRoot));
    for (const runtime of ['claude', 'codex']) await check(`S2 ${runtime} wiring covers every handler and removal is detected`, () => {
      const file = path.join(pluginRoot, runtime === 'claude' ? 'hooks/hooks.json' : 'hooks/codex.json');
      const rows = distribution.hookWiring(pluginRoot, file); assert.equal(rows.length, 6);
      for (const [event, script] of [['PreToolUse', 'hooks/guard.sh'], ['Stop', 'hooks/stop-resume.sh'], ['SessionStart', 'hooks/session-context.sh']]) {
        const matching = rows.filter(row => row.event === event && row.script === script); assert.equal(matching.length, 1); if (event === 'PreToolUse') assert.equal(matching[0].matcher, '');
      }
      const raw = JSON.parse(fs.readFileSync(file, 'utf8')); delete raw.hooks.Stop;
      const removed = path.join(temp, runtime + '-without-stop.json'); fs.writeFileSync(removed, JSON.stringify(raw));
      const changed = distribution.hookWiring(pluginRoot, removed); assert.equal(changed.length, rows.length - 1); assert.ok(!changed.some(row => row.event === 'Stop'));
      const definitions = JSON.parse(fs.readFileSync(path.join(pluginRoot, 'lib/hook-definitions.json'), 'utf8'));
      const declared = definitions.flatMap(entry => entry.script ? [entry.script] : []).sort();
      assert.deepEqual([...new Set(rows.flatMap(row => row.script ? [row.script] : []))].sort(), declared);
    });
    const scripts = [];
    function walk(directory) { for (const entry of fs.readdirSync(directory, {withFileTypes: true})) { const file = path.join(directory, entry.name); if (entry.isDirectory()) walk(file); else if (/\.(mjs|sh)$/.test(entry.name)) scripts.push(file); } }
    for (const directory of ['lib', 'scripts', 'checks', 'hooks']) walk(path.join(pluginRoot, directory));
    await check('S5 executable source population is nonempty', () => { assert.ok(scripts.filter(file => file.endsWith('.mjs')).length >= 20); assert.ok(scripts.filter(file => file.endsWith('.sh')).length >= 10); });
    for (const file of scripts) await check(`S5 ${path.relative(pluginRoot, file)}`, () => {
      if (file.endsWith('.mjs')) { const run = spawnSync(process.execPath, ['--check', file], {encoding: 'utf8'}); assert.equal(run.status, 0, run.stderr); }
      else if (process.platform !== 'win32') { assert.ok(fs.statSync(file).mode & 0o111, 'POSIX wrapper execution bit missing'); const run = spawnSync('bash', ['-n', file], {encoding: 'utf8'}); assert.equal(run.status, 0, run.stderr); }
      else assert.ok(fs.readFileSync(file, 'utf8').startsWith('#!'), 'legacy POSIX wrapper missing shebang');
    });
    if (process.platform === 'win32') outputs.push('S5 POSIX wrappers: source presence only; Bash syntax/execute bits are POSIX compatibility checks, not native runtime dependencies.');
    const database = path.join(temp, 'upstream/.beads/embeddeddolt'); fs.mkdirSync(path.join(database, 'db'), {recursive: true});
    fs.mkdirSync(path.join(main, '.beads')); fs.writeFileSync(path.join(main, '.beads/redirect'), path.dirname(database));
    let ahead = 0, miss = false, pushFails = false, pushes = 0;
    const transport = async ({argv}, options) => {
      const [executable, ...args] = argv; let stdout = '', code = 0;
      if (executable === 'bd' && args[0] === '-C' && args[2] === 'where') { assert.equal(args[1], main); stdout = miss ? '' : `database: ${database}\n`; code = miss ? 1 : 0; }
      else if (executable === 'bd' && args.join(' ') === 'dolt push') { assert.equal(options.cwd, main); pushes++; if (pushFails) code = 1; else ahead = 0; }
      else if (executable === 'dolt') {
        if (args[0] === 'remote') stdout = 'origin https://example.invalid/db\n';
        else if (args[0] === 'branch') stdout = 'remotes/origin/main\n';
        else if (args[0] === 'merge-base') stdout = 'ancestor\n';
        else if (args[0] === 'log') stdout = Array.from({length: ahead}, (_, i) => `commit-${i}\n`).join('');
        else assert.equal(args[0], 'version');
      } else throw new Error('unexpected offline command: ' + argv.join(' '));
      return {status: 'exited', code, stdout: Buffer.from(stdout), stderr: Buffer.alloc(0)};
    };
    const runLedger = (implementation = ledger.executeLedger, push = false) => ledgerCheck.checkLedger({root: main, cwd: workspace, env: isolated, push, ledger: args => implementation(args, {root: main, cwd: workspace, env: isolated, process: transport})});
    await check('S6 redirect location comes from bd where and zero ahead is judged', async () => { const result = await runLedger(); assert.equal(result.code, 0); assert.match(result.stdout, /원격 반영 확인됨/); });
    await check('S6 missing ledger is explicit skipped evidence, never verified', async () => { miss = true; const result = await runLedger(); miss = false; assert.equal(result.code, 0); assert.match(result.stderr, /임베디드 원장 없음/); assert.match(result.stdout, /건너뜀/); assert.doesNotMatch(result.stdout, /확인됨/); });
    await check('S6 read mode does not write or hide ahead state', async () => { ahead = 3; const before = pushes; const result = await runLedger(); assert.equal(result.code, 0); assert.equal(ahead, 3); assert.equal(pushes, before); assert.match(result.stdout, /앞서 있음\(반영하지 않음/); });
    await check('S6 explicit push changes state and confirms the state afterward', async () => { ahead = 3; const result = await runLedger(ledger.executeLedger, true); assert.equal(result.code, 0); assert.equal(ahead, 0); assert.match(result.stdout, /이번에 수행함/); });
    await check('S6 failed push cannot pretend the ahead state resolved', async () => { ahead = 3; pushFails = true; const result = await runLedger(ledger.executeLedger, true); pushFails = false; assert.equal(result.code, 1); assert.equal(ahead, 3); assert.match(result.stderr, /해소하지 못했다/); });
    await check('S6 location and actual push each have independent live mutations', async () => {
      const location = await mutant('lib/ledger/beads.mjs', text => text.replace('const database=/^\\s*database:\\s*(.*)$/m.exec(where.stdout.toString())?.[1]', "const database=path.join(ctx.root,'.beads/embeddeddolt')"));
      const alteredLocation = await import(pathToFileURL(path.join(location.root, 'lib/ledger.mjs')).href); ahead = 0;
      assert.match((await runLedger(alteredLocation.executeLedger)).stdout, /건너뜀/);
      const nopush = await mutant('lib/ledger/beads.mjs', text => text.replace("await ctx.command('bd',['dolt','push'],{cwd:ctx.root,allowFailure:true})", "{stdout:Buffer.alloc(0),stderr:Buffer.alloc(0),code:0}"));
      const alteredPush = await import(pathToFileURL(path.join(nopush.root, 'lib/ledger.mjs')).href); ahead = 3;
      const result = await runLedger(alteredPush.executeLedger, true); assert.equal(result.code, 1); assert.equal(ahead, 3);
    });
    const outcomes = new Set(); let observedLines = 0, expectedLines = 0, runs = 0;
    const scopeFor = sessionId => state.resolveState({runtime: 'claude', cwd: workspace, sessionId}, isolated);
    const bindFixture = async sessionId => { const scope = await scopeFor(sessionId); fs.mkdirSync(path.dirname(scope.actors), {recursive: true}); fs.writeFileSync(scope.actors, JSON.stringify({runtime: scope.runtime, repoKey: scope.repoKey, sessionId, claims: [{actor: 'mine', evidence: 'ledger-show'}]})); };
    const stopCase = async (sessionId, rows, expected, {active = false, binding = true, oracle, rootFinder, implementation = stop.evaluateStop, lines = binding || active || expected === 'ORACLE_FAIL' ? 1 : 2} = {}) => {
      if (binding) await bindFixture(sessionId);
      const scope = await scopeFor(sessionId); const before = fs.existsSync(scope.stopLog) ? fs.readFileSync(scope.stopLog, 'utf8').trimEnd().split('\n').length : 0;
      const result = await implementation({cwd: workspace, session_id: sessionId, stop_hook_active: active}, {env: isolated, ledger: oracle ?? (async args => { assert.deepEqual(args, ['list', '--status', 'in_progress', '--limit', '0', '--json']); return {code: 0, stdout: JSON.stringify(rows)}; }), ...(rootFinder ? {rootFinder} : {})});
      const records = fs.readFileSync(scope.stopLog, 'utf8').trimEnd().split('\n').slice(before); runs++; observedLines += records.length; expectedLines += lines;
      assert.equal(result.code, 0); assert.equal(records.length, lines); assert.equal(records.at(-1).split('\t')[2], expected);
      for (const record of records) outcomes.add(record.split('\t')[2]);
      if (expected === 'BLOCK') assert.equal(JSON.parse(result.stdout).decision, 'block'); else assert.equal(result.stdout, '');
      return result;
    };
    await check('S7 recursion, idle, oracle failure variants and ordinary block each log', async () => {
      await stopCase('recurse', [], 'RECURSE', {active: true}); await stopCase('idle', [], 'IDLE');
      await stopCase('oracle-fail', [], 'ORACLE_FAIL', {oracle: async () => ({code: 1})});
      await stopCase('oracle-shape', [], 'ORACLE_FAIL', {oracle: async () => ({code: 0, stdout: '{}'})});
      await stopCase('root-fail', [], 'ORACLE_FAIL', {rootFinder: async () => { throw new Error('harness-root unavailable'); }});
      await stopCase('block', [{assignee: 'mine'}], 'BLOCK');
    });
    const marked = notes => ({assignee: 'mine', notes});
    await check('S7 both marks, mixed marks, prose, missing marks and rework preserve outcomes', async () => {
      for (const [name, rows, want] of [
        ['vp', [marked('VERIFY_PENDING: a'), marked('VERIFY_PENDING: b')], 'VERIFY_PENDING'],
        ['vp-prose', [marked('VERIFY_PENDING: a\nreview prose')], 'VERIFY_PENDING'],
        ['vp-missing', [marked('VERIFY_PENDING: a'), marked('')], 'BLOCK'],
        ['dg', [marked('DELEGATED: a'), marked('DELEGATED: b')], 'VERIFY_PENDING'],
        ['mixed', [marked('VERIFY_PENDING: a'), marked('DELEGATED: b')], 'VERIFY_PENDING'],
        ['rework', [marked('VERIFY_PENDING: a\nCHANGES_REQUESTED\nDELEGATED: b')], 'VERIFY_PENDING'],
        ['dg-missing', [marked('DELEGATED: a'), marked('prose')], 'BLOCK'],
        ['empty', [marked('')], 'BLOCK'],
      ]) await stopCase(name, rows, want);
    });
    await check('S7 cancellation remains session-owned and the cap is bounded', async () => {
      const scope = await scopeFor('cancel'); state.cancelSession(scope); const legacy = path.join(isolated.HARNESS_DATA_DIR, 'stop-resume-cancel'); fs.writeFileSync(legacy, 'legacy');
      await stopCase('cancel', [marked('')], 'CANCEL'); await stopCase('cancel', [marked('')], 'CANCEL'); await stopCase('other', [marked('')], 'BLOCK');
      assert.ok(fs.existsSync(scope.cancel)); assert.equal(fs.readFileSync(legacy, 'utf8'), 'legacy');
      assert.ok(stop.MAX_BLOCKS > 0); for (let i = 0; i < stop.MAX_BLOCKS; i++) await stopCase('cap', [marked('')], 'BLOCK'); await stopCase('cap', [marked('')], 'GAVE_UP');
    });
    await check('S7 actor/assignee and missing mappings preserve six scope controls', async () => {
      await stopCase('other-actor', [{assignee: 'other'}], 'IDLE'); await stopCase('mine-actor', [{assignee: 'mine'}], 'BLOCK');
      await stopCase('missing-session', [{assignee: 'mine'}], 'BLOCK', {binding: false}); await stopCase('missing-map', [{assignee: 'other'}], 'BLOCK', {binding: false});
      await stopCase('github', [{actor: 'mine', assignee: 'login'}], 'BLOCK'); await stopCase('github-null', [{actor: null, assignee: 'login'}], 'IDLE');
    });
    await check('S7 markers and scope narrowing have independent mutation controls', async () => {
      for (const [marker, replacement, rows] of [['VERIFY_MARK', '  const vp = 0;', [marked('VERIFY_PENDING: a')]], ['DELEGATED_MARK', '  const dg = 0;', [marked('DELEGATED: a')]], ['SCOPE_NARROW', '', [{assignee: 'other'}]]]) {
        const copy = await mutant('lib/stop.mjs', text => text.split('\n').map(line => line.includes('// ' + marker) ? replacement : line).join('\n'));
        await stopCase(marker, rows, 'BLOCK', {implementation: copy.module.evaluateStop});
      }
    });
    await check('S7 oracle count changes block reason; no claim is invented by PreToolUse', async () => {
      const first = await stopCase('count-one', [marked('')], 'BLOCK'), second = await stopCase('count-two', [marked(''), marked('')], 'BLOCK');
      assert.match(first.stdout, /1건/); assert.match(second.stdout, /2건/);
      const input = {...shell('bd -C /fixture update t --claim --actor pretend'), session_id: 'no-claim'}; await judge(input);
      assert.equal(fs.existsSync((await scopeFor('no-claim')).actors), false);
    });
    await check('S7 outcome population, log count and source declarations agree', () => {
      const source = fs.readFileSync(path.join(pluginRoot, 'lib/stop.mjs'), 'utf8');
      const sourceOutcomes = [...new Set([...source.matchAll(/log\('([A-Z_]+)'/g)].map(match => match[1]))];
      assert.deepEqual([...outcomes].sort(), [...stop.STOP_OUTCOMES].sort()); assert.deepEqual(sourceOutcomes.sort(), [...outcomes].sort());
      assert.ok(runs >= 25); assert.equal(observedLines, expectedLines); assert.ok(observedLines >= runs);
    });
    await check('S7 unavailable state is diagnosed without claiming idle or modifying the ledger', async () => {
      const blockedPath = path.join(temp, 'not-a-directory'); fs.writeFileSync(blockedPath, 'fixture');
      let calls = 0;
      const result = await stop.evaluateStop({cwd: workspace, session_id: 'unwritable'}, {env: {...isolated, HARNESS_DATA_DIR: path.join(blockedPath, 'data')}, ledger: async args => { calls++; assert.equal(args[0], 'list'); return {code: 1}; }});
      assert.equal(result.code, 0); assert.equal(result.stdout, ''); assert.match(result.stderr, /UNREACHED/); assert.equal(calls, 1); assert.ok(!result.outcomes.includes('IDLE'));
    });
    await check('S7 default state directory is resolved under the isolated home', async () => {
      const home = path.join(temp, 'home'); fs.mkdirSync(home);
      const fallback = {...isolated, HOME: home, USERPROFILE: home}; delete fallback.HARNESS_DATA_DIR;
      const scope = await state.resolveState({runtime: 'claude', cwd: workspace, sessionId: 'default-state'}, fallback);
      assert.ok(scope.data.startsWith(home + path.sep));
      const result = await stop.evaluateStop({cwd: workspace, session_id: 'default-state', stop_hook_active: true}, {env: fallback});
      assert.equal(result.code, 0); assert.equal(result.stdout, ''); assert.ok(fs.existsSync(scope.stopLog)); assert.match(fs.readFileSync(scope.stopLog, 'utf8'), /RECURSE/);
    });
  } catch (error) { errors.push(`✗ guardrail setup/fixture UNREACHED: ${error.message}`); }
  finally { fs.rmSync(temp, {recursive: true, force: true}); }
  return {code: errors.length ? 1 : 0, stdout: outputs.join('\n') + `\n강제 장치 검사 ${errors.length ? '실패' : '통과'} — 단언 ${checks} · 표면 ${SURFACES.join(', ')}; 직접 handler/metadata 판정, 실제 runtime 발화는 별도\n`, stderr: errors.join('\n') + (errors.length ? '\n' : '')};
}
if (isMain(import.meta.url)) {
  try {
    const args = process.argv.slice(2); if (args.length && (args.length !== 2 || args[0] !== '--root' || !path.isAbsolute(args[1]))) throw new Error('usage: guardrail-check.mjs [--root <repository>]');
    // Root is accepted for the common check command contract. This check only
    // judges its plugin artifact and isolated fixtures, never that live ledger.
    const result = await checkGuardrails(); process.stdout.write(result.stdout); process.stderr.write(result.stderr); process.exitCode = result.code;
  } catch (error) { console.error(`UNREACHED: ${error.message}`); process.exitCode = 1; }
}
