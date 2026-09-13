// Offline native Node/Git fixtures. No Bash/jq/Python or remote ledger calls.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {runCommand} from '../../plugins/harness/lib/process.mjs';
import {renderBoard, renderDocuments} from '../../plugins/harness/scripts/board.mjs';

import {checkWorkspace} from '../../plugins/harness/checks/workspace-check.mjs';
import {checkRules, registeredStoryWorktrees} from '../../plugins/harness/checks/rules-check.mjs';

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
  assert.equal(reached,7); console.log(`PASS native consumer I/O ${reached}; host=${process.platform}`);
} finally { await fs.rm(temp, {recursive: true, force: true}); }
