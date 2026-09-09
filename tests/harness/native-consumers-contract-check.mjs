// Offline native Node/Git fixtures. No Bash/jq/Python or remote ledger calls.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {runCommand} from '../../plugins/harness/lib/process.mjs';
import {renderBoard, renderDocuments, naturalId} from '../../plugins/harness/scripts/board.mjs';
import {judgeBoard, checkBoard} from '../../plugins/harness/checks/board-check.mjs';
import {checkLedger} from '../../plugins/harness/checks/ledger-check.mjs';
import {checkWorkspace} from '../../plugins/harness/checks/workspace-check.mjs';
import {judgeR5, judgeAcceptance, judgeS22, judgeS24, checkRules, selfControls, registeredStoryWorktrees} from '../../plugins/harness/checks/rules-check.mjs';
import {ledgerIndex} from '../../plugins/harness/lib/ledger-view.mjs';

assert.equal(process.platform, process.argv[2] || process.platform, 'actual native host must match requested evidence');
const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'harness-consumers-'));
const root = path.join(temp, '원장 repo space');
const gitConfig = path.join(temp, 'empty.gitconfig');
await fs.writeFile(gitConfig, '');
const env = {...process.env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: gitConfig, GIT_TERMINAL_PROMPT: '0'};
for (const key of Object.keys(env)) if (key.startsWith('GIT_') && !['GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL', 'GIT_TERMINAL_PROMPT'].includes(key)) delete env[key];
delete env.LEDGER_CHECK_PUSH;
let reached = 0;
const check = async (name, fn) => { await fn(); reached++; console.log(`PASS ${name}`); };
const exists = file => fs.stat(file).then(() => true, error => { if (error.code === 'ENOENT') return false; throw error; });
const epic = {id: 'repo#42', issue_type: 'epic', status: 'in_progress', title: '스토리 | 한글', labels: ['sprint:2026-S01', 'rail:r1', 'slug:r1-story', 'repo:원장 repo space'], description: '설명\\n문자\n실제 개행', notes: 'story note'};
const milestone = {id: 'repo#42.2', parent: epic.id, issue_type: 'feature', status: 'in_progress', title: '둘째', labels: ['sprint:2026-S01']};
const task = {id: 'repo#42.2.1', parent: milestone.id, issue_type: 'task', status: 'in_progress', title: '-n', labels: ['sprint:2026-S01', 'repo:원장 repo space'], acceptance_criteria: 'run check', notes: '검토 기록\n한글'};
const rows = [epic, milestone, task];
const rails = [{id: 'r1', owner: '담당 | 사람'}], sprints = [{id: '2026-S01', status: 'active'}];
const changed = (id, patch, source = rows) => structuredClone(source).map(row => row.id === id ? {...row, ...patch} : row);
const fixture = ({data = rows, ui = '', railRows = rails, sprintRows = sprints, failures = {}} = {}) => {
  const calls = [];
  const ledger = async argv => { calls.push(argv); if (failures[argv[0]]) return failures[argv[0]];
    return {code: 0, stderr: '', stdout: argv[0] === 'has-ui' ? ui : JSON.stringify({list: data, rails: railRows, sprints: sprintRows}[argv[0]])}; };
  return {root, env, ledger, calls};
};
try {
  await fs.mkdir(root);
  const git = async argv => { const result = await runCommand({argv: ['git', ...argv]}, {cwd: root, env}); assert.equal(result.code, 0, result.stderr.toString()); };
  await git(['init', '--initial-branch=main']);
  await fs.writeFile(path.join(root, '.harness.json'), JSON.stringify({ledger: {backend: 'github'}}));
  await git(['add', '.harness.json']);
  await git(['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '-m', 'fixture']);

  await check('board reads one whole-ledger snapshot and both registries', async () => {
    const options = fixture(); assert.equal((await checkBoard(options)).code, 0);
    assert.deepEqual(options.calls, [['list', '--all', '--json', '-n', '0'], ['rails', '--json'], ['sprints', '--json']]);
  });
  await check('board rejects missing/empty/malformed snapshots and malformed registries', async () => {
    for (const data of [[], null, {}, [null], [{id: 'x'}], [...rows, task], changed(task.id, {parent: 'absent'}), changed(task.id, {parent: task.id})]) await assert.rejects(checkBoard(fixture({data})));
    for (const command of ['list', 'rails', 'sprints']) {
      for (const result of [{code: 1, stdout: '', stderr: 'offline unavailable'}, {code: 0, stdout: '', stderr: ''}, {code: 0, stdout: '{}', stderr: ''}]) await assert.rejects(checkBoard(fixture({failures: {[command]: result}})));
    }
    assert.throws(() => judgeBoard(rows, [{id: 'r1'}], sprints), /owner/);
    assert.throws(() => judgeBoard(rows, rails, [{id: '2026-S01', status: 'typo'}]), /status/);
  });
  await check('board registry checks are bidirectional and include backlog rails', () => {
    assert.equal(judgeBoard(rows, [], sprints).code, 1);
    assert.equal(judgeBoard(rows, rails, []).code, 1);
    assert.equal(judgeBoard(rows, rails, [...sprints, {id: '2026-S02', status: 'closed'}]).code, 1);
    assert.equal(judgeBoard([...rows, {...epic, id: 'backlog', labels: ['rail:missing']}], rails, sprints).code, 1);
    const invalid = rows.map(row => ({...row, labels: (row.labels ?? []).map(value => value.replace('2026-S01', 'bad'))}));
    assert.equal(judgeBoard(invalid, rails, [{id: 'bad', status: 'active'}]).code, 1);
  });
  await check('board inheritance, orphan and acceptance polarities retain terminal boundaries', () => {
    assert.equal(judgeBoard(changed(task.id, {labels: ['repo:x']}), rails, sprints).code, 1);
    assert.equal(judgeBoard(changed(task.id, {labels: ['repo:x'], status: 'closed'}), rails, sprints).code, 1);
    for (const status of ['open', 'blocked', 'in_progress']) assert.equal(judgeBoard(changed(task.id, {status, acceptance_criteria: ''}), rails, sprints).code, 1);
    for (const status of ['closed', 'deferred']) assert.equal(judgeBoard(changed(task.id, {status, acceptance_criteria: ''}), rails, sprints).code, 0);
    const orphan = {...task, parent: null, id: 'orphan'};
    assert.equal(judgeBoard([...rows, orphan], rails, sprints).code, 1);
    assert.equal(judgeBoard([...rows, {...orphan, status: 'closed'}], rails, sprints).code, 0);
  });
  await check('rules self-controls and R5/R-ACC opposite populations', () => {
    assert.equal(selfControls(), 8);
    assert.equal(judgeR5(rows).errors.length, 0);
    assert.equal(judgeR5(changed(task.id, {labels: []})).errors.length, 1);
    assert.equal(judgeR5(changed(task.id, {labels: ['repo:a', 'repo:b']})).errors.length, 1);
    assert.equal(judgeR5([{...task, parent: null, labels: []}]).covered, 0);
    assert.equal(judgeAcceptance(changed(task.id, {acceptance_criteria: ' \r\n'})).errors.length, 1);
    assert.equal(judgeAcceptance(changed(task.id, {acceptance_criteria: '', status: 'open'})).errors.length, 0);
    assert.throws(() => ledgerIndex(changed(task.id, {status: null})), /status/);
  });
  await check('S22 preserves last marker, actor separation, unknown actors and cross-repo scope', () => {
    const two = [...rows, {...task, id: 'other'}], scope = {repo: '원장 repo space', worktrees: () => 0};
    assert.equal(judgeS22(two, scope).errors.length, 1);
    assert.equal(judgeS22(two.map(row => ({...row, assignee: 'same'})), scope).errors.length, 0);
    assert.equal(judgeS22(two.map(row => ({...row, assignee: 'same-login', actor: row.id})), scope).errors.length, 1);
    const marked = two.map(row => ({...row, notes: 'VERIFY_PENDING: a\r\n산문 기록'}));
    assert.equal(judgeS22(marked, scope).errors.length, 0); assert.equal(judgeS22(marked, scope).pending, 2);
    assert.equal(judgeS22(marked.map(row => ({...row, notes: row.notes + '\nDELEGATED: again'})), scope).errors.length, 1);
    assert.equal(judgeS22(two, {...scope, repo: 'other-repo'}).errors.length, 0);
    assert.match(judgeS22(two, {...scope, repo: 'other-repo'}).messages[0], /판정하지 않는다/);
  });
  await check('S24 includes every descendant and terminal kind, excludes childless/closed stories', () => {
    assert.equal(judgeS24(rows).errors.length, 0);
    for (const status of ['closed', 'blocked', 'deferred']) {
      const terminal = rows.map(row => row.issue_type === 'epic' ? row : {...row, status});
      assert.equal(judgeS24(terminal).errors.length, 1);
      assert.equal(judgeS24(changed(epic.id, {status: 'closed'}, terminal)).errors.length, 0);
    }
    assert.equal(judgeS24([epic]).covered, 0);
  });
  await check('S22 counts registered external worktrees and excludes fake directories', async () => {
    await fs.mkdir(path.join(root, '.claude/worktrees/repo-42-fake'), {recursive: true});
    let scope = await registeredStoryWorktrees(root, {env}); assert.equal(scope.worktrees(epic.id), 0);
    const external = path.join(temp, '외부 workspace');
    await git(['worktree', 'add', '-b', 'worktree-repo-42', external]);
    scope = await registeredStoryWorktrees(root, {env}); assert.equal(scope.repo, '원장 repo space'); assert.equal(scope.worktrees(epic.id), 1);
    await git(['worktree', 'add', '-b', 'worktree-repo-42-parallel', path.join(temp, '병렬 workspace')]);
    assert.equal((await registeredStoryWorktrees(external, {env})).worktrees(epic.id), 2);
    assert.equal((await checkRules(fixture({data: [...rows, {...task, id: 'other'}]}))).code, 0);
    await fs.rm(external, {recursive: true, force: true});
    assert.equal((await registeredStoryWorktrees(root, {env})).worktrees(epic.id), 1);
    assert.equal((await checkRules(fixture({data: [...rows, {...task, id: 'other'}]}))).code, 1);
  });
  await check('valid empty rules population reports zero; missing data never becomes zero', async () => {
    const result = await checkRules(fixture({data: []})); assert.equal(result.code, 0); assert.match(result.stdout, /대상 0건/); assert.match(result.stdout, /스토리 0건/);
    await assert.rejects(checkRules(fixture({data: null})));
    await assert.rejects(checkRules(fixture({failures: {list: {code: 1, stdout: '[]', stderr: 'failure'}}})));
  });
  await check('workspace check validates config and Git registration on every backend without ledger', async () => {
    const file = path.join(root, '.harness.json');
    for (const backend of ['github', 'notion', 'beads']) {
      await fs.writeFile(file, JSON.stringify({ledger: {backend}}));
      const result = await checkWorkspace(root, {env}); assert.equal(result.code, 0); assert.equal(JSON.parse(result.stdout).top, await fs.realpath(root));
    }
    await fs.writeFile(file, '{}'); await assert.rejects(checkWorkspace(root, {env}));
    await fs.writeFile(file, JSON.stringify({ledger: {backend: 'github'}}));
    const fake = path.join(root, 'fake directory'); await fs.mkdir(fake); await fs.copyFile(file, path.join(fake, '.harness.json'));
    await assert.rejects(checkWorkspace(fake, {env}), /not a worktree root/);
  });
  await check('renderer UI response makes no writes and has-ui failure cannot imply no UI', async () => {
    for (const ui of ['github', 'notion']) {
      const options = fixture({ui}); const result = await renderBoard('all', options);
      assert.equal(result.code, 0); assert.match(result.stdout, /만들지도 지우지도 않았다/); assert.deepEqual(options.calls, [['has-ui']]);
      assert.equal(await exists(path.join(root, 'docs')), false);
    }
    await assert.rejects(renderBoard('all', fixture({failures: {'has-ui': {code: 1, stdout: '', stderr: 'unavailable'}}})));
  });
  await check('renderer is deterministic and retains metadata, natural ordering, notes and close reasons', () => {
    const fixtureRows = [...changed(task.id, {status: 'closed', close_reason: 'MATCH abc\nfull detail'}), {...milestone, id: 'repo#42.10', title: '열째'}];
    const files = renderDocuments('2026-S01', fixtureRows, rails, sprints);
    assert.deepEqual(files, renderDocuments('2026-S01', fixtureRows, rails, sprints));
    assert.match(files.get('index.md'), /스토리 \\\| 한글/);
    assert.match(files.get('r1-story/index.md'), /owner: 담당 \| 사람/);
    assert.match(files.get('r1-story/index.md'), /\[M1\].*repo#42\.2/); assert.match(files.get('r1-story/index.md'), /\[M2\].*repo#42\.10/);
    assert.match(files.get('r1-story/M1.md'), /### ✓ repo#42\.2\.1 — -n/);
    assert.match(files.get('r1-story/M1.md'), /종료 근거: MATCH abc/); assert.match(files.get('r1-story/M1.md'), /종료 근거 전문/); assert.match(files.get('r1-story/M1.md'), /검토 기록\n한글/);
    assert.equal(naturalId('x.2', 'x.10'), -1);
  });
  await check('renderer empty backlog/ADR and closed sprint succeed; active/unknown empty sprint fail', () => {
    for (const target of ['backlog', 'adr']) assert.equal(renderDocuments(target, [], [], []).size, 1);
    assert.equal(renderDocuments('2026-S02', [], [], [{id: '2026-S02', status: 'closed'}]).size, 1);
    assert.throws(() => renderDocuments('2026-S01', [], [], sprints), /닫힌 스프린트만/);
    assert.throws(() => renderDocuments('2026-S03', [], [], []), /닫힌 스프린트만/);
    assert.throws(() => renderDocuments('../escaped', rows, rails, sprints), /형식/);
  });
  await check('renderer validates slug uniqueness/paths and rail ownership before publishing', () => {
    for (const slug of ['../escaped', 'C:\\escaped', '/root', '한글', 'a/b', '']) assert.throws(() => renderDocuments('2026-S01', changed(epic.id, {labels: ['sprint:2026-S01', 'rail:r1', ...(slug ? ['slug:' + slug] : [])]}), rails, sprints), /슬러그|slug/);
    assert.throws(() => renderDocuments('2026-S01', [...rows, {...epic, id: 'duplicate'}], rails, sprints), /충돌/);
    assert.throws(() => renderDocuments('2026-S01', rows, [], sprints), /레일/);
  });
  await check('ADR retains closed decisions and supersession lineage without reading rails', async () => {
    const decisions = [{id: 'd1', issue_type: 'decision', status: 'closed', title: '옛 결정', labels: ['slug:old'], dependencies: [{type: 'supersedes', depends_on_id: 'd2'}]}, {id: 'd2', issue_type: 'decision', status: 'pinned', title: '현재 결정', labels: ['slug:new']}];
    const files = renderDocuments('adr', decisions);
    assert.match(files.get('old.md'), /superseded_by: d2/); assert.match(files.get('index.md'), /✓ closed \| d2/);
    const options = fixture({data: decisions}); await renderBoard('adr', options); assert.equal(options.calls.some(argv => argv[0] === 'rails'), false);
  });
  await check('projection replacement, stale-output removal and locks preserve completed trees', async () => {
    const options = fixture(); await renderBoard('2026-S01', options);
    const index = path.join(root, 'docs/sprints/2026-S01/index.md'), before = await fs.readFile(index, 'utf8');
    await fs.writeFile(path.join(root, 'docs/sprints/2026-S01/stale.md'), 'stale'); await renderBoard('2026-S01', options);
    assert.equal(await fs.readFile(index, 'utf8'), before); assert.equal(await exists(path.join(root, 'docs/sprints/2026-S01/stale.md')), false);
    const lock = path.join(root, 'docs/sprints/.render-lock-2026-S01'); await fs.mkdir(lock);
    await assert.rejects(renderBoard('2026-S01', options), /이미 진행/); assert.equal(await fs.readFile(index, 'utf8'), before); await fs.rmdir(lock);
    await assert.rejects(renderBoard('2026-S01', fixture({data: changed(epic.id, {labels: []})})), /닫힌 스프린트만/);
    assert.equal(await fs.readFile(index, 'utf8'), before);
  });
  await check('outside docs symlink/junction is rejected before creating any external directory', async () => {
    for (const depth of ['docs','sprints']) {
      const guardedRoot=path.join(temp,'guarded '+depth),outside=path.join(temp,'outside '+depth);
      await fs.mkdir(guardedRoot);await fs.mkdir(outside);await fs.writeFile(path.join(outside,'sentinel'),'preserve');
      if(depth==='sprints')await fs.mkdir(path.join(guardedRoot,'docs'));
      const link=path.join(guardedRoot,'docs',...(depth==='sprints'?['sprints']:[]));
      await fs.symlink(outside,link,process.platform==='win32'?'junction':'dir');
      await assert.rejects(renderBoard('2026-S02',{...fixture({data:[],sprintRows:[{id:'2026-S02',status:'closed'}]}),root:guardedRoot}),/루트 밖/);
      assert.deepEqual(await fs.readdir(outside),['sentinel'],'rejection must leave outside directory unchanged');
      assert.equal(await fs.readFile(path.join(outside,'sentinel'),'utf8'),'preserve');
    }
  });
  await check('ledger sync remains read-only by default and preserves adapter rc/output', async () => {
    const calls = [], ledger = async argv => { calls.push(argv); return {code: 7, stdout: 'ahead', stderr: 'detail'}; };
    assert.deepEqual(await checkLedger({root, env, ledger}), {code: 7, stdout: 'ahead', stderr: 'detail'});
    assert.deepEqual(calls.pop(), ['sync-check']);
    await checkLedger({root, env, ledger, push: true}); assert.deepEqual(calls.pop(), ['sync-check', '--push']);
    await checkLedger({root, env: {...env, LEDGER_CHECK_PUSH: '1'}, ledger}); assert.deepEqual(calls.pop(), ['sync-check', '--push']);
  });
  await check('native CLI works with no Bash/jq/Python in PATH and explicit space/Unicode root', async () => {
    const script = fileURLToPath(new URL('../../plugins/harness/scripts/board.mjs', import.meta.url));
    const clean = {...env}; for (const key of Object.keys(clean)) if (key.toUpperCase() === 'PATH') delete clean[key]; clean.PATH = temp;
    const result = await runCommand({argv: [process.execPath, script, '--root', root, 'all']}, {cwd: temp, env: clean});
    assert.equal(result.code, 0, result.stderr.toString()); assert.match(result.stdout.toString(), /자기 UI/);
    const alias = path.join(temp, 'plugin alias');
    await fs.symlink(path.dirname(path.dirname(script)), alias, process.platform === 'win32' ? 'junction' : 'dir');
    const linked = await runCommand({argv: [process.execPath, path.join(alias, 'scripts/board.mjs'), '--root', root, 'all']}, {cwd: temp, env: clean});
    assert.equal(linked.code, 0, linked.stderr.toString()); assert.match(linked.stdout.toString(), /자기 UI/);
    const bad = await runCommand({argv: [process.execPath, script, '--root', path.join(temp, 'absent'), 'all']}, {cwd: temp, env: clean}); assert.notEqual(bad.code, 0);
  });
  if (!process.argv.includes('--mutation-child')) {
    await check('removing each rules judgment is caught by self-controls', async () => {
      const plugin = fileURLToPath(new URL('../../plugins/harness', import.meta.url));
      const copy = path.join(temp, 'mutated plugin'); await fs.cp(plugin, copy, {recursive: true});
      const file = path.join(copy, 'checks/rules-check.mjs'), original = await fs.readFile(file, 'utf8');
      for (const name of ['judgeR5', 'judgeAcceptance', 'judgeS22', 'judgeS24']) {
        const at = original.indexOf(`export function ${name}(`), brace = original.indexOf(') {', at);
        assert.ok(at >= 0 && brace > at);
        const mutated = original.slice(0, brace + 3) + '\nreturn {errors: [], covered: 0, messages: []};\n' + original.slice(brace + 3);
        assert.notEqual(mutated, original); await fs.writeFile(file, mutated);
        const result = await runCommand({argv: [process.execPath, '--input-type=module', '-e', `import {selfControls} from ${JSON.stringify(pathToFileURL(file).href)}; selfControls();`]}, {cwd: temp, env});
        assert.notEqual(result.code, 0); assert.match(result.stderr.toString(), /自己|자기 시험 실패/);
      }
    });
  }
  assert.equal(reached, process.argv.includes('--mutation-child') ? 19 : 20, 'every native consumer judgment must execute');
  console.log(`PASS native consumers ${reached}; host=${process.platform}; live backend/runtime integration is separate evidence`);
} finally { await fs.rm(temp, {recursive: true, force: true}); }
