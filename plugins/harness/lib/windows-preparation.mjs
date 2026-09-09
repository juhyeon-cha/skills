import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {resolveExecutable, runCommand} from './process.mjs';

const adapter = fileURLToPath(new URL('./windows-job.ps1', import.meta.url));
const validJob = name => typeof name === 'string' && /^Local\\HarnessPrepare-[0-9a-f-]{36}$/.test(name);
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
// Windows PowerShell 5.1 ships with supported Windows versions. A missing or
// administratively restricted PowerShell/Add-Type fails before bootstrap starts.
const powershell = async (cwd, env) => resolveExecutable('powershell.exe', {cwd, env});
const args = (mode, request) => ['-NoLogo', '-NoProfile', '-NonInteractive', '-File', adapter, '-Mode', mode, '-Request', request];

export function windowsOwner(env = process.env) {
  if (!validJob(env.HARNESS_PREPARE_JOB) || !path.isAbsolute(env.HARNESS_PREPARE_IPC || '')) throw new Error('PREPARE_JOB_UNREACHED: worker must be launched by the owning Job supervisor');
  const supervisor = Number(env.HARNESS_PREPARE_SUPERVISOR);
  if (!Number.isSafeInteger(supervisor) || supervisor <= 1) throw new Error('PREPARE_JOB_UNREACHED: missing supervisor identity');
  return {job: env.HARNESS_PREPARE_JOB, supervisor};
}

export async function windowsOwnerGone(owner, {cwd, env = process.env}) {
  if (!validJob(owner.job)) return false; // unknown/legacy ownership is never stolen
  const result = await runCommand({argv: [await powershell(cwd, env), ...args('exists', owner.job)]}, {cwd, env});
  if (result.status !== 'exited' || result.code !== 0 || !['ACTIVE', 'GONE'].includes(result.stdout.toString())) throw new Error('PREPARE_JOB_UNREACHED: cannot determine previous Job lifetime');
  return result.stdout.toString() === 'GONE';
}

export async function windowsHasChildren(env = process.env) {
  windowsOwner(env);
  const nonce = randomUUID(), directory = env.HARNESS_PREPARE_IPC;
  const temporary = path.join(directory, `query-${nonce}`), query = path.join(directory, 'query'), reply = path.join(directory, `reply-${nonce}`);
  await fs.writeFile(temporary, nonce, {flag: 'wx'});
  await fs.rename(temporary, query);
  const deadline = Date.now() + 5000;
  for (;;) {
    try {
      const value = JSON.parse(await fs.readFile(reply, 'utf8'));
      if (value.nonce !== nonce || !Number.isSafeInteger(value.active) || value.active < 1) throw new Error('PREPARE_JOB_UNREACHED: invalid Job accounting');
      await fs.unlink(reply);
      return value.active > 1; // exactly one process, this worker, is expected
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
    if (Date.now() >= deadline) throw new Error('PREPARE_JOB_UNREACHED: supervisor did not reach accounting');
    await pause(20);
  }
}

export async function spawnWindowsWorker(worker, identity, env) {
  const executable = await powershell(identity.top, env);
  const ipc = await fs.mkdtemp(path.join(os.tmpdir(), 'harness-prepare-job-'));
  const request = path.join(ipc, 'launch.json');
  try {
    await fs.writeFile(request, JSON.stringify({executable: process.execPath, worker, cwd: identity.top, job: `Local\\HarnessPrepare-${randomUUID()}`, ipc}), {flag: 'wx'});
    const child = spawn(executable, args('supervise', request), {cwd: identity.top, env, detached: true, stdio: ['ignore', 'pipe', 'pipe']});
    // A killed waiter must not own this directory or the supervisor lifetime.
    child.on('close', () => { fs.rm(ipc, {recursive: true, force: true}).catch(() => {}); });
    await new Promise((resolve, reject) => { child.once('spawn', resolve); child.once('error', reject); });
    return child;
  } catch (error) { await fs.rm(ipc, {recursive: true, force: true}); throw error; }
}
