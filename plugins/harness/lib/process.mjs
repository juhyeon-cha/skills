import fs from 'node:fs/promises';
import path from 'node:path';
import { constants } from 'node:fs';
import { spawn } from 'node:child_process';
import { validateCommand } from './config.mjs';

const failure = (code, message) => Object.assign(new Error(message), { code });
// Match Node's first lexicographic key when Windows env names differ only by case.
const envValue = (env, key, platform) =>
  env[
    platform === 'win32'
      ? Object.keys(env)
          .sort()
          .find((k) => k.toUpperCase() === key)
      : key
  ];

// This pure candidate builder supports lexical Windows fixtures on other OSes.
// Only resolveExecutable/runCommand on the host prove actual execution support.
export function executableCandidates(
  executable,
  { cwd, env = process.env, platform = process.platform },
) {
  if (typeof executable !== 'string' || !executable || executable.includes('\0'))
    throw failure('EINVAL', 'invalid executable');
  const p = platform === 'win32' ? path.win32 : path.posix;
  if (typeof cwd !== 'string' || !p.isAbsolute(cwd))
    throw failure('EINVAL', 'absolute cwd required');
  if (
    platform === 'win32' &&
    (/^[A-Za-z]:(?![\\/])/.test(executable) || /^[\\/](?![\\/])/.test(executable))
  )
    throw failure('EINVAL', 'ambiguous Windows executable path');
  const explicit = platform === 'win32' ? /[\\/]/.test(executable) : executable.includes('/');
  const searchPath = envValue(env, 'PATH', platform);
  const directories =
    searchPath === undefined ? [] : searchPath.split(platform === 'win32' ? ';' : ':');
  const bases = explicit
    ? [p.resolve(cwd, executable)]
    : directories
        .filter((dir) => platform !== 'win32' || dir !== '')
        .map((dir) => p.resolve(cwd, dir, executable));
  if (platform !== 'win32' || p.extname(executable)) return bases;
  const extensions = (envValue(env, 'PATHEXT', platform) ?? '.COM;.EXE;.BAT;.CMD')
    .split(';')
    .filter((ext) => /^\.[a-z0-9]+$/i.test(ext));
  return bases.flatMap((base) => extensions.map((ext) => base + ext));
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
    if (platform === 'win32' && !/\.(exe|com|cmd|bat)$/i.test(candidate))
      throw failure(
        'UNSUPPORTED_EXECUTABLE',
        'Windows requires .exe/.com or the explicit .cmd/.bat adapter',
      );
    return candidate;
  }
  throw accessError ?? failure('ENOENT', `executable not found: ${executable}`);
}

// cmd.exe performs expansion even inside quotes. Refuse expansion/control
// characters, rather than pretend a general argv-to-batch conversion is lossless.
// Native executable argv retains the full Node contract, including these bytes.
export function windowsBatchArguments(executable, args) {
  for (const value of [executable, ...args]) {
    if (
      typeof value !== 'string' ||
      /[\x00-\x1f\x7f"%!^&|<>()]/.test(value) ||
      value.endsWith('\\')
    )
      throw failure(
        'UNREPRESENTABLE_BATCH_ARGUMENT',
        'batch arguments cannot contain control characters, quotes, trailing backslash or cmd expansion/operator characters; invoke the native executable for arbitrary argv',
      );
  }
  return [
    '/d',
    '/s',
    '/v:off',
    '/c',
    '"' + [executable, ...args].map((value) => '"' + value + '"').join(' ') + '"',
  ];
}

export async function commandLaunch(argv, { cwd, env = process.env, platform = process.platform }) {
  const executable = await resolveExecutable(argv[0], { cwd, env, platform });
  if (platform !== 'win32' || !/\.(cmd|bat)$/i.test(executable))
    return { executable, args: argv.slice(1), windowsVerbatimArguments: false };
  const args = windowsBatchArguments(executable, argv.slice(1));
  // Resolve a native interpreter explicitly. Never turn on Node's shell option.
  const interpreter = envValue(env, 'COMSPEC', platform) || 'cmd.exe';
  const cmd = await resolveExecutable(interpreter, { cwd, env, platform });
  if (path.win32.basename(cmd).toLowerCase() !== 'cmd.exe')
    throw failure('UNSUPPORTED_EXECUTABLE', 'batch interpreter must be cmd.exe');
  return { executable: cmd, args, windowsVerbatimArguments: true };
}

// Completion is explicit: an exit code, a terminating signal, or a launch error.
// stdout/stderr remain buffers; no shell quoting or text re-encoding is applied.
/**
 * Execute a validated argv command or a legacy Bash command string.
 * Validation errors reject; executable lookup and launch errors become results.
 * @param {string | {argv: string[]}} command
 * @param {{cwd: string, env?: NodeJS.ProcessEnv, input?: string | Buffer,
 *   inheritStdin?: boolean}} options
 * @returns {Promise<{status: 'exited' | 'signaled' | 'spawn_error',
 *   code: number | null, signal: string | null,
 *   error?: {code: string | undefined, message: string}, stdout: Buffer, stderr: Buffer}>}
 */
export async function runCommand(
  command,
  { cwd, env = process.env, input, inheritStdin = false } = {},
) {
  validateCommand(command);
  let launch;
  const argv = typeof command === 'string' ? ['bash', '-c', command] : command.argv;
  try {
    launch = await commandLaunch(argv, { cwd, env });
  } catch (error) {
    return {
      status: 'spawn_error',
      code: null,
      signal: null,
      error: { code: error.code, message: error.message },
      stdout: Buffer.alloc(0),
      stderr: Buffer.alloc(0),
    };
  }
  return new Promise((resolve) => {
    const stdout = [],
      stderr = [];
    let error;
    let child;
    try {
      child = spawn(launch.executable, launch.args, {
        cwd,
        env,
        windowsVerbatimArguments: launch.windowsVerbatimArguments,
        shell: false,
        stdio: [input !== undefined ? 'pipe' : inheritStdin ? 'inherit' : 'ignore', 'pipe', 'pipe'],
      });
    } catch (err) {
      resolve({
        status: 'spawn_error',
        code: null,
        signal: null,
        error: { code: err.code, message: err.message },
        stdout: Buffer.alloc(0),
        stderr: Buffer.alloc(0),
      });
      return;
    }
    child.stdout.on('data', (data) => stdout.push(data));
    child.stderr.on('data', (data) => stderr.push(data));
    if (child.stdin) {
      child.stdin.on('error', (err) => {
        if (err.code !== 'EPIPE') error = { code: err.code, message: err.message };
      });
      child.stdin.end(input);
    }
    child.on('error', (err) => {
      error = { code: err.code, message: err.message };
    });
    child.on('close', (code, signal) =>
      resolve({
        status: error ? 'spawn_error' : signal ? 'signaled' : 'exited',
        code,
        signal,
        ...(error ? { error } : {}),
        stdout: Buffer.concat(stdout),
        stderr: Buffer.concat(stderr),
      }),
    );
  });
}
