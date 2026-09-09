#!/usr/bin/env node
import os from 'node:os';
import path from 'node:path';
import {loadConfig, configCommand} from '../lib/config.mjs';
import {runCommand} from '../lib/process.mjs';

try {
  const [action, root, field, ...extra] = process.argv.slice(2);
  if (!root || extra.length || !['validate', 'run'].includes(action) || (action === 'validate' ? field !== undefined : !field)) throw new Error('usage: node scripts/config.mjs validate <repo> | run <repo> <check|bootstrap>');
  const cwd = path.resolve(root);
  const {config} = await loadConfig(cwd);
  if (action === 'validate') process.stdout.write(JSON.stringify(config) + '\n');
  else {
    const command = configCommand(config, field);
    if (command === null) process.stderr.write('config: bootstrap is not configured; no process started\n');
    else {
      const result = await runCommand(command, {cwd});
      process.stdout.write(result.stdout); process.stderr.write(result.stderr);
      if (result.status === 'exited') process.exitCode = result.code;
      else {
        const {stdout, stderr, ...completion} = result;
        process.stderr.write(JSON.stringify(completion) + '\n');
        process.exitCode = result.status === 'signaled' ? 128 + (os.constants.signals[result.signal] ?? 1) : 1;
      }
    }
  }
} catch (error) {
  process.stderr.write(`config: ${error.message}\n`); process.exitCode = 1;
}
