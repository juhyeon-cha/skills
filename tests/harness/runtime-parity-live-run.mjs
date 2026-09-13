import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {sha256} from './runtime-parity-evidence.mjs';

// Explicit structured invocation only. Retains raw evidence locally; never
// interprets transport success as semantic success or publishes raw output.
const specification = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const output = path.resolve(process.argv[3]);
if (fs.existsSync(output)) throw new Error('new observation directory required');
fs.mkdirSync(output, {recursive: true, mode: 0o700});
const json = (name, value) => fs.writeFileSync(path.join(output, name), JSON.stringify(value, null, 2) + '\n', {mode: 0o600});
if (!['claude', 'codex', 'agy'].includes(specification.command) || !Array.isArray(specification.args) || !specification.args.every(s => typeof s === 'string')) throw new Error('explicit supported command and argv required');
json('invocation.json', {...specification, startedAt: new Date().toISOString()});
const stdout = fs.openSync(path.join(output, 'stdout.log'), 'wx', 0o600);
const stderr = fs.openSync(path.join(output, 'stderr.log'), 'wx', 0o600);
const environment = {...process.env, HARNESS_DATA_DIR: path.join(path.dirname(output), 'state')};
// Doctor requires a separately issued challenge (and currently only Claude /
// Codex). Ordinary workflow events already capture the actual wrapper source.
delete environment.HARNESS_DOCTOR_DIR;
const child = spawn(specification.command, specification.args, {cwd: specification.cwd,
  env: environment, stdio: ['ignore', stdout, stderr]});
const timer = setTimeout(() => child.kill('SIGTERM'), specification.timeoutMs ?? 90000);
child.on('error', error => { json('spawn-error.json', {message: error.message}); });
child.on('close', (code, signal) => {
  clearTimeout(timer); fs.closeSync(stdout); fs.closeSync(stderr);
  json('exit.json', {code, signal, finishedAt: new Date().toISOString()});
  const files = fs.readdirSync(output).filter(name => fs.statSync(path.join(output, name)).isFile()).map(name => ({path: name, sha256: sha256(fs.readFileSync(path.join(output, name)))}));
  json('raw-receipt.json', {files});
  console.log(JSON.stringify({output, code, signal})); process.exitCode = code ?? 1;
});
