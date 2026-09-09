import fs from 'node:fs/promises';
import path from 'node:path';
import {constants} from 'node:fs';
import {spawn} from 'node:child_process';
import {validateCommand} from './config.mjs';

const failure = (code, message) => Object.assign(new Error(message), {code});
// Match Node's first lexicographic key when Windows env names differ only by case.
const envValue = (env, key, platform) => env[platform === 'win32' ? Object.keys(env).sort().find(k => k.toUpperCase() === key) : key];

// This pure candidate builder supports lexical Windows fixtures on other OSes.
// Only resolveExecutable/runCommand on the host prove actual execution support.
export function executableCandidates(executable, {cwd, env = process.env, platform = process.platform}) {
  if (typeof executable !== 'string' || !executable || executable.includes('\0')) throw failure('EINVAL', 'invalid executable');
  const p = platform === 'win32' ? path.win32 : path.posix;
  if (typeof cwd !== 'string' || !p.isAbsolute(cwd)) throw failure('EINVAL', 'absolute cwd required');
  if (platform === 'win32' && (/^[A-Za-z]:(?![\\/])/.test(executable) || /^[\\/](?![\\/])/.test(executable))) throw failure('EINVAL', 'ambiguous Windows executable path');
  if (platform === 'win32' && /\.(cmd|bat)$/i.test(executable)) throw failure('UNSUPPORTED_EXECUTABLE', 'Windows .cmd/.bat require an explicit adapter; no implicit shell wrapping');
  const explicit = platform === 'win32' ? /[\\/]/.test(executable) : executable.includes('/');
  const searchPath = envValue(env, 'PATH', platform);
  const directories = searchPath === undefined ? [] : searchPath.split(platform === 'win32' ? ';' : ':');
  const bases = explicit ? [p.resolve(cwd, executable)] : directories.filter(dir => platform !== 'win32' || dir !== '').map(dir => p.resolve(cwd, dir, executable));
  if (platform !== 'win32' || p.extname(executable)) return bases;
  const extensions = (envValue(env, 'PATHEXT', platform) ?? '.COM;.EXE;.BAT;.CMD').split(';').filter(ext => /^\.[a-z0-9]+$/i.test(ext));
  return bases.flatMap(base => extensions.map(ext => base + ext));
}

export async function resolveExecutable(executable, options) {
  const platform = options.platform ?? process.platform;
  let accessError;
  for (const candidate of executableCandidates(executable, options)) {
    try {
      if (!(await fs.stat(candidate)).isFile()) continue;
      await fs.access(candidate, platform === 'win32' ? constants.F_OK : constants.X_OK);
    } catch (error) {
      if (!['ENOENT', 'ENOTDIR'].includes(error.code)) accessError = error;
      continue;
    }
    if (platform === 'win32' && !/\.(exe|com)$/i.test(candidate)) throw failure('UNSUPPORTED_EXECUTABLE', 'Windows requires a native .exe/.com; .cmd/.bat and scripts are not implicitly shell-wrapped');
    return candidate;
  }
  throw accessError ?? failure('ENOENT', `executable not found: ${executable}`);
}

// Completion is explicit: an exit code, a terminating signal, or a launch error.
// stdout/stderr remain buffers; no shell quoting or text re-encoding is applied.
export async function runCommand(command, {cwd, env = process.env} = {}) {
  validateCommand(command);
  let executable;
  const argv = typeof command === 'string' ? ['bash', '-c', command] : command.argv;
  try { executable = await resolveExecutable(argv[0], {cwd, env}); }
  catch (error) { return {status: 'spawn_error', code: null, signal: null, error: {code: error.code, message: error.message}, stdout: Buffer.alloc(0), stderr: Buffer.alloc(0)}; }
  return new Promise(resolve => {
    const stdout = [], stderr = []; let error;
    let child;
    try { child = spawn(executable, argv.slice(1), {cwd, env, shell: false, stdio: ['ignore', 'pipe', 'pipe']}); }
    catch (err) { resolve({status: 'spawn_error', code: null, signal: null, error: {code: err.code, message: err.message}, stdout: Buffer.alloc(0), stderr: Buffer.alloc(0)}); return; }
    child.stdout.on('data', data => stdout.push(data));
    child.stderr.on('data', data => stderr.push(data));
    child.on('error', err => { error = {code: err.code, message: err.message}; });
    child.on('close', (code, signal) => resolve({status: error ? 'spawn_error' : signal ? 'signaled' : 'exited', code, signal, ...(error ? {error} : {}), stdout: Buffer.concat(stdout), stderr: Buffer.concat(stderr)}));
  });
}
