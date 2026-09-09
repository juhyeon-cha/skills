import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash, randomUUID} from 'node:crypto';
import {spawn, spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {loadConfig, configCommand} from './config.mjs';
import {runCommand} from './process.mjs';

const hash = value => createHash('sha256').update(value).digest('hex');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const read = file => fs.readFile(file, 'utf8').then(JSON.parse).catch(error => { if (error.code === 'ENOENT') return null; throw error; });
const alive = pid => { try { process.kill(pid, 0); return true; } catch (error) { if (error.code === 'ESRCH') return false; throw error; } };
// Git identity, never runtime/session identity. Central state resolution can
// replace this function without changing ownership or receipt contracts.
export function preparationPaths(identity) {
  const root = path.join(identity.gitDir, 'harness', 'prepare', hash(identity.top));
  return {root, lock: path.join(root, 'lock'), ready: path.join(root, 'ready.json')};
}
async function contract(identity) {
  const {config, file} = await loadConfig(identity.top);
  for (const name of ['settings.json', 'settings.local.json']) {
    const settings = await read(path.join(identity.top, '.claude', name));
    if (settings?.hooks?.PostToolUse?.some(hook => !hook.matcher || hook.matcher === '*' || new RegExp(hook.matcher).test('EnterWorktree'))) throw new Error('LEGACY_HOOK_UNVERIFIED: move preparation to .harness.json bootstrap and exclude EnterWorktree from the repository hook; hook existence is not readiness');
  }
  const command = configCommand(config, 'bootstrap');
  const digest = createHash('sha256').update(await fs.readFile(file));
  for (const input of config.preparation?.inputs ?? []) {
    const location = await fs.realpath(path.resolve(identity.top, input));
    if (!location.startsWith(identity.top + path.sep) || !(await fs.stat(location)).isFile()) throw new Error('preparation input must be a regular file inside the workspace');
    digest.update('\0' + input + '\0').update(hash(await fs.readFile(location)));
  }
  return {command, fingerprint: digest.digest('hex'), timeout: config.preparation?.timeout_ms ?? 300000};
}
export async function preparationStatus(identity) {
  const current = await contract(identity);
  const paths = preparationPaths(identity);
  const receipt = await read(paths.ready);
  const lock = await fs.stat(paths.lock).then(() => true, error => { if (error.code === 'ENOENT') return false; throw error; });
  if (!current.command) {
    if (lock) throw new Error('PREPARE_BUSY_OR_UNREACHED: existing preparation lock; no-command config cannot bypass it');
    return {preparation: 'not-configured', ready: false, canDelegate: true};
  }
  const ready = !lock && receipt?.version === 1 && receipt.fingerprint === current.fingerprint && receipt.top === identity.top && receipt.gitDir === identity.gitDir;
  return {preparation: ready ? 'ready' : 'not-ready', ready, canDelegate: ready, fingerprint: current.fingerprint};
}
async function acquire(paths, token, deadline) {
  let joined;
  for (;;) {
    try {
      await fs.mkdir(paths.lock);
      // The worker is already its process-group leader; no bootstrap exists
      // before this immutable owner record has been written.
      const ownerFile = path.join(paths.lock, `owner-${token}.json`);
      await fs.writeFile(ownerFile, JSON.stringify({token, pid: process.pid}), {flag: 'wx'});
      await fs.rename(ownerFile, path.join(paths.lock, 'owner.json'));
      return joined;
    } catch (error) { if (error.code !== 'EEXIST') throw error; }
    const owner = await read(path.join(paths.lock, 'owner.json'));
    if (owner && Number.isSafeInteger(owner.pid) && owner.pid > 1 && typeof owner.token === 'string') {
      if (!alive(owner.pid) && !alive(-owner.pid)) {
        if (joined === owner.token) throw new Error('PREPARE_JOINED_CRASH: shared preparation worker crashed; retry');
        // Only one contender can recover this lock. Others never remove a
        // missing/malformed owner or a recovery claim abandoned by a crash.
        try { await fs.mkdir(path.join(paths.lock, 'recovery')); }
        catch (error) { if (error.code === 'ENOENT') continue; if (error.code !== 'EEXIST') throw error; if (Date.now() >= deadline) throw new Error('PREPARE_LOCK_UNREACHED: abandoned recovery claim'); await pause(50); continue; }
        const recovery = path.join(paths.lock, 'recovery', token);
        try { await fs.writeFile(recovery, '', {flag: 'wx'}); } catch (error) { if (error.code === 'ENOENT') continue; throw error; }
        const claims = await fs.readdir(path.dirname(recovery));
        if (claims.length !== 1 || claims[0] !== token) throw new Error('PREPARE_LOCK_UNREACHED: competing recovery; inspect lock manually');
        const currentOwner = await read(path.join(paths.lock, 'owner.json'));
        if (currentOwner?.token !== owner.token || currentOwner?.pid !== owner.pid || alive(owner.pid) || alive(-owner.pid)) {
          await fs.unlink(recovery); await fs.rmdir(path.dirname(recovery));
          continue;
        }
        // An interrupted publication is not a completed preparation.
        await fs.rm(paths.ready, {force: true});
        await fs.unlink(path.join(paths.lock, 'owner.json'));
        await fs.unlink(recovery); await fs.rmdir(path.dirname(recovery)); await fs.rmdir(paths.lock);
        continue;
      }
      joined ??= owner.token;
    }
    if (Date.now() >= deadline) throw new Error('PREPARE_BUSY_OR_UNREACHED: owner/process group still alive or incomplete lock; no lock stolen');
    await pause(50);
  }
}
// Called only by the detached worker. A POSIX process group lets a dead owner
// retain the lock while any bootstrap descendants are still running.
function groupHasChildren() {
  const result = spawnSync('ps', ['-axo', 'pid=,pgid='], {detached: true, encoding: 'utf8'});
  if (result.error || result.status !== 0) throw new Error('PREPARE_UNREACHED: cannot inspect POSIX process group');
  return result.stdout.trim().split('\n').some(line => { const [pid, group] = line.trim().split(/\s+/).map(Number); return group === process.pid && pid !== process.pid; });
}
export async function runPreparation(identity, {env = process.env, say = () => {}} = {}) {
  const initial = await contract(identity);
  if (!initial.command) return {preparation: 'not-configured', ready: false, canDelegate: true};
  if (process.platform === 'win32') throw new Error('PREPARE_UNSUPPORTED: native Windows process-tree ownership requires an adapter');
  const paths = preparationPaths(identity), token = randomUUID();
  await fs.mkdir(paths.root, {recursive: true});
  const joined = await acquire(paths, token, Date.now() + initial.timeout + 1000);
  let timer;
  try {
    const current = await contract(identity);
    const outcome = joined ? await read(path.join(paths.root, `failure-${joined}.json`)) : null;
    if (joined && outcome?.token === joined && outcome.fingerprint === current.fingerprint) throw new Error('PREPARE_JOINED_FAILURE: shared preparation failed; retry');
    const existing = await read(paths.ready);
    if (existing?.version === 1 && existing.fingerprint === current.fingerprint && existing.top === identity.top && existing.gitDir === identity.gitDir) return {preparation: 'ready', ready: true, canDelegate: true, reused: true};
    await fs.rm(paths.ready, {force: true});
    if (!current.command) return {preparation: 'not-configured', ready: false, canDelegate: true};
    // SIGKILL removes this worker and its non-detached descendants together.
    // Lock remains for a later caller to recover only after the group is gone.
    timer = setTimeout(() => { say('PREPARE_TIMEOUT'); process.kill(-process.pid, 'SIGKILL'); }, current.timeout);
    const result = await runCommand(current.command, {cwd: identity.top, env});
    clearTimeout(timer); timer = undefined;
    if (groupHasChildren()) throw new Error('PREPARE_BUSY: bootstrap descendants still running; lock retained');
    say(result.stdout.toString() + result.stderr.toString());
    if (result.status !== 'exited' || result.code !== 0) throw new Error(`부트스트랩 실패: ${result.error?.message || result.signal || result.code}`);
    if ((await contract(identity)).fingerprint !== current.fingerprint) throw new Error('PREPARE_INPUT_CHANGED: no ready receipt; retry');
    const receipt = {version: 1, fingerprint: current.fingerprint, top: identity.top, gitDir: identity.gitDir, token};
    const temporary = path.join(paths.root, `ready-${token}.json`);
    await fs.writeFile(temporary, JSON.stringify(receipt), {flag: 'wx'});
    await fs.rename(temporary, paths.ready);
    return {preparation: 'ready', ready: true, canDelegate: true, reused: false};
  } catch (error) {
    const file = path.join(paths.root, `failure-${token}.tmp`);
    await fs.writeFile(file, JSON.stringify({token, fingerprint: initial.fingerprint}), {flag: 'wx'});
    await fs.rename(file, path.join(paths.root, `failure-${token}.json`));
    throw error;
  } finally {
    clearTimeout(timer);
    if (groupHasChildren()) throw new Error('PREPARE_BUSY: bootstrap descendants still running; lock retained');
    const owner = await read(path.join(paths.lock, 'owner.json'));
    if (owner?.token !== token) throw new Error('PREPARE_LOCK_UNREACHED: ownership changed');
    await fs.unlink(path.join(paths.lock, 'owner.json')); await fs.rmdir(paths.lock);
  }
}
export async function prepareWorkspaceIdentity(identity, {env = process.env, say = () => {}} = {}) {
  // Preflight also distinguishes a legitimate no-command repo from own hooks.
  const status = await preparationStatus(identity);
  if (status.canDelegate) return status;
  if (process.platform === 'win32') throw new Error('PREPARE_UNSUPPORTED: native Windows process-tree ownership requires an adapter');
  const worker = fileURLToPath(new URL('../scripts/prepare-worker.mjs', import.meta.url));
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [worker, identity.top], {cwd: identity.top, env, detached: true, stdio: ['ignore', 'pipe', 'pipe']});
    let output = '';
    child.stdout.on('data', data => { output += data; }); child.stderr.on('data', data => say(data.toString()));
    child.on('error', reject);
    child.on('close', (code, signal) => {
      if (code !== 0) return reject(new Error(`PREPARE_FAILED_OR_CRASHED: ${signal || code}; workspace preserved; retry after owner/group exits`));
      try { resolve(JSON.parse(output)); } catch (error) { reject(error); }
    });
  });
}
