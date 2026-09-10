#!/usr/bin/env node
// Lifecycle transport only. The preparation contract remains in the worker.
import fs from 'node:fs/promises';
import { spawn } from 'node:child_process';
for (const stream of [process.stdout, process.stderr])
  stream.on('error', (error) => {
    if (error.code !== 'EPIPE') throw error;
  });
try {
  const request = JSON.parse(await fs.readFile(process.argv[2], 'utf8'));
  const child = spawn(request.powershell, request.supervisorArgs, {
    cwd: request.cwd,
    env: { ...process.env, HARNESS_PREPARE_LAUNCHER: String(process.pid) },
    detached: false,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  child.stdout.on('data', (data) => process.stdout.write(data));
  child.stderr.on('data', (data) => process.stderr.write(data));
  child.on('error', (error) => {
    process.stderr.write(`PREPARE_LAUNCH_UNREACHED: ${error.message}\n`);
    process.exitCode = 1;
  });
  child.on('close', (code) => {
    process.exitCode = code ?? 1;
  });
} catch (error) {
  process.stderr.write(`PREPARE_LAUNCH_UNREACHED: ${error.message}\n`);
  process.exitCode = 1;
}
