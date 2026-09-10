import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadConfig } from './config.mjs';
import { prepareWorkspaceIdentity, preparationStatus, preparationPaths } from './preparation.mjs';
import { runCommand } from './process.mjs';
import { worktreeName } from './worktree-name.mjs';

const plugin = fileURLToPath(new URL('../', import.meta.url));
const exists = async (p) =>
  fs.stat(p).then(
    () => true,
    (error) => {
      if (error.code === 'ENOENT') return false;
      throw error;
    },
  );
const inside = (child, parent) => child === parent || child.startsWith(parent + path.sep);
export function gitEnvironment(env = process.env) {
  return Object.fromEntries(
    Object.entries(env).filter(
      ([key]) =>
        !key.startsWith('GIT_') ||
        [
          'GIT_CONFIG_GLOBAL',
          'GIT_CONFIG_NOSYSTEM',
          'GIT_ALLOW_PROTOCOL',
          'GIT_TERMINAL_PROMPT',
        ].includes(key),
    ),
  );
}
async function git(cwd, args, env = process.env) {
  const result = await runCommand(
    { argv: ['git', '-C', cwd, ...args] },
    { cwd, env: gitEnvironment(env) },
  );
  if (result.status !== 'exited' || result.code !== 0)
    throw Object.assign(
      new Error(
        `git ${args[0]} failed: ${result.stderr.toString() || result.error?.message || result.signal}`,
      ),
      { completion: result },
    );
  return result.stdout.toString();
}
export function parseWorktrees(text) {
  return text
    .split('\0\0')
    .filter(Boolean)
    .map((record) =>
      Object.fromEntries(
        record
          .split('\0')
          .filter(Boolean)
          .map((line) => {
            const at = line.indexOf(' ');
            return at < 0 ? [line, true] : [line.slice(0, at), line.slice(at + 1)];
          }),
      ),
    );
}
// exact=true rejects a normal directory whose Git lookup falls through to a parent.
export async function inspectWorkspace(location, { exact = true, env = process.env } = {}) {
  const cwd = await fs.realpath(location);
  const top = await fs.realpath((await git(cwd, ['rev-parse', '--show-toplevel'], env)).trim());
  if (exact && top !== cwd) throw new Error(`not a worktree root: ${location} (toplevel=${top})`);
  const common = await fs.realpath(
    path.resolve(top, (await git(top, ['rev-parse', '--git-common-dir'], env)).trim()),
  );
  const gitDir = await fs.realpath(
    path.resolve(top, (await git(top, ['rev-parse', '--git-dir'], env)).trim()),
  );
  const registrations = parseWorktrees(
    await git(top, ['worktree', 'list', '--porcelain', '-z'], env),
  );
  const canonical = await Promise.all(
    registrations.map(async (row) => ({
      ...row,
      worktree: await fs.realpath(row.worktree).catch(() => path.resolve(row.worktree)),
    })),
  );
  const registration = canonical.find((row) => row.worktree === top);
  if (!registration || registration.bare) throw new Error(`Git registration missing: ${top}`);
  const branch = (
    await git(top, ['symbolic-ref', '--quiet', '--short', 'HEAD'], env).catch(() => '')
  ).trim();
  if ((registration.branch ?? '') !== (branch ? `refs/heads/${branch}` : ''))
    throw new Error('Git branch and registration disagree');
  const main = canonical[0].worktree;
  const mainCommon = await fs.realpath(
    path.resolve(main, (await git(main, ['rev-parse', '--git-common-dir'], env)).trim()),
  );
  if (mainCommon !== common) throw new Error('Git common directory differs from main registration');
  return {
    top,
    main,
    common,
    gitDir,
    branch,
    linked: gitDir !== common && top !== main,
    registrations: canonical,
  };
}
export async function storyName(story) {
  const name = worktreeName(story);
  if (!name || !/^[A-Za-z0-9._-]+$/.test(name) || ['.', '..'].includes(name))
    throw new Error('invalid story workspace name');
  return name;
}
async function ledger(root, cwd, args, env) {
  await loadConfig(root); // Root identity and ledger coordinates are separate from Git.
  const result = await runCommand(
    { argv: [process.execPath, path.join(plugin, 'scripts/ledger.mjs'), '--root', root, ...args] },
    { cwd, env: { ...gitEnvironment(env), CLAUDE_PLUGIN_ROOT: plugin, HARNESS_ROOT: root } },
  );
  if (result.status !== 'exited' || result.code !== 0)
    throw new Error(
      `ledger.sh ${args[0]} 실패 — 어댑터: ${result.stderr.toString() || result.error?.message || result.signal}`,
    );
  return result.stdout.toString();
}
async function storyContext(cwd, story, env) {
  let identity;
  try {
    identity = await inspectWorkspace(cwd, { exact: false, env });
    await loadConfig(identity.top);
  } catch (error) {
    throw new Error(`대상 레포를 찾지 못했다 — ${error.message}`);
  }
  const root = env.HARNESS_ROOT || identity.top;
  const rows = JSON.parse(await ledger(root, identity.top, ['show', story, '--json'], env));
  if (
    !Array.isArray(rows) ||
    !Array.isArray(rows[0]?.labels) ||
    !rows[0].labels.includes(`repo:${path.basename(identity.main)}`)
  )
    throw new Error('story repo: label does not match target repository');
  const name = await storyName(story, { cwd: identity.top, env });
  return { ...identity, name, expectedBranch: `worktree-${name}`, root };
}
export async function createWorkspace(cwd, story, { destination, env = process.env } = {}) {
  const context = await storyContext(cwd, story, env);
  const { config } = await loadConfig(context.top);
  const target = destination
    ? path.resolve(cwd, destination)
    : path.join(context.main, '.claude/worktrees', context.name);
  if (
    (await exists(target)) ||
    context.registrations.some((row) => row.branch === `refs/heads/${context.expectedBranch}`)
  )
    throw new Error('workspace path or branch already exists; inspect and enter it');
  await git(context.main, ['fetch', '--prune', '--quiet', 'origin'], env);
  const base = config.default_branch
    ? `origin/${config.default_branch}`
    : (
        await git(context.main, ['symbolic-ref', '--short', 'refs/remotes/origin/HEAD'], env)
      ).trim();
  await git(context.main, ['worktree', 'add', '-b', context.expectedBranch, target, base], env);
  return inspectWorkspace(target, { env });
}
function linked(identity) {
  if (!identity.linked || !/^worktree-[A-Za-z0-9._-]+$/.test(identity.branch))
    throw new Error('not a registered story workspace (expected worktree-<name> branch)');
}
export async function enterWorkspace(location, { env = process.env, say = () => {} } = {}) {
  const identity = await inspectWorkspace(location, { env });
  linked(identity);
  await loadConfig(identity.top);
  const root = env.HARNESS_ROOT || identity.top;
  say(
    '원장 배선: ' + (await ledger(root, identity.top, ['wire-worktree', identity.top], env)).trim(),
  );
  const exclude = path.join(identity.common, 'info/exclude');
  await fs.mkdir(path.dirname(exclude), { recursive: true });
  const lines = (
    await fs.readFile(exclude, 'utf8').catch((error) => {
      if (error.code === 'ENOENT') return '';
      throw error;
    })
  ).split('\n');
  for (const line of ['.beads', '.claude/worktrees/']) if (!lines.includes(line)) lines.push(line);
  await fs.writeFile(exclude, lines.join('\n') + '\n');
  return {
    ...identity,
    ...(await prepareWorkspaceIdentity(identity, { env: gitEnvironment(env), say })),
  };
}
export async function prepareWorkspace(location, options = {}) {
  const identity = await inspectWorkspace(location, options);
  linked(identity);
  return { ...identity, ...(await prepareWorkspaceIdentity(identity, options)) };
}
export async function readyWorkspace(location, options = {}) {
  const identity = await inspectWorkspace(location, options);
  linked(identity);
  const status = await preparationStatus(identity);
  if (!status.canDelegate)
    throw new Error('PREPARE_NOT_READY: run workspace prepare; implementation delegation blocked');
  return { ...identity, ...status };
}
export async function cleanupWorkspace(
  cwd,
  story,
  { force = false, env = process.env, say = () => {} } = {},
) {
  const context = await storyContext(cwd, story, env);
  const record = context.registrations.find(
    (row) => row.branch === `refs/heads/${context.expectedBranch}`,
  );
  const target = record?.worktree || path.join(context.main, '.claude/worktrees', context.name);
  const caller = await fs.realpath(process.cwd());
  const selected = await fs.realpath(cwd);
  if (inside(caller, target) || inside(selected, target))
    throw new Error('호출자가 정리 대상 워크트리 안에 서 있다 — 밖에서 실행하라');
  if (record?.locked || target === context.main)
    throw new Error('locked or main workspace cannot be removed');
  const present = await exists(target);
  if (present) {
    const actual = await inspectWorkspace(target, { env });
    linked(actual);
    if (actual.common !== context.common || actual.branch !== context.expectedBranch)
      throw new Error('workspace belongs to another repository or branch');
    if (await exists(preparationPaths(actual).lock))
      throw new Error('PREPARE_BUSY_OR_UNREACHED: resolve preparation lock before cleanup');
    const dirty = await git(target, ['status', '--porcelain'], env);
    if (dirty) throw new Error(`미커밋 변경이 있다 — --force 로도 보존한다\n${dirty}`);
  }
  try {
    await git(context.main, ['fetch', '--prune', '--quiet', 'origin'], env);
  } catch (error) {
    throw new Error(`fetch --prune 실패 — ${error.message}`);
  }
  const branchExists = await git(
    context.main,
    ['show-ref', '--verify', '--quiet', `refs/heads/${context.expectedBranch}`],
    env,
  )
    .then(() => true)
    .catch((error) => {
      if (error.completion?.code === 1) return false;
      throw error;
    });
  if (branchExists) {
    const unpushed = await git(
      context.main,
      ['log', '--oneline', context.expectedBranch, '--not', '--remotes=origin'],
      env,
    );
    if (unpushed && !force) throw new Error(`미푸시 커밋이 있다\n${unpushed}`);
    if (unpushed) say(`--force: 미푸시 커밋\n${unpushed}`);
  }
  const result = { main: context.main, target, removed: [], branch: context.expectedBranch };
  if (present || record) {
    if (present) say(await git(target, ['status', '--short', '--ignored'], env));
    // Targeted remove handles absent registrations without global worktree prune.
    await git(context.main, ['worktree', 'remove', target], env);
    result.removed.push('workspace');
  }
  if (branchExists) {
    try {
      await git(context.main, ['branch', '-D', context.expectedBranch], env);
      result.removed.push('branch');
    } catch (error) {
      error.partial = result;
      throw error;
    }
  }
  const marker = path.join(context.main, '.claude/worktrees', `.bootstrapped-${context.name}`);
  if (await exists(marker)) {
    await fs.unlink(marker);
    result.removed.push('marker');
  }
  return result;
}
