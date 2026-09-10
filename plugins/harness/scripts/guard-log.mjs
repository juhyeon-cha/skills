#!/usr/bin/env node
import {summarizeGuardLog} from '../lib/guard-log.mjs';
import path from 'node:path';
try {
  const args = process.argv.slice(2), env = {...process.env}; let cwd = process.cwd();
  while (args[0]?.startsWith('--')) {
    const key = args.shift(), value = args.shift();
    if (!value || !['--runtime', '--data', '--repo', '--log'].includes(key)) throw new Error('usage: [--runtime claude|codex] [--data <absolute>] [--repo <absolute>] [--log <legacy TSV>] count|rows [session]');
    if (key !== '--runtime' && !path.isAbsolute(value)) throw new Error(`${key} must be absolute`);
    if (key === '--runtime') { if (!['claude', 'codex'].includes(value)) throw new Error('unknown runtime'); env.HARNESS_RUNTIME = value; }
    else if (key === '--data') env.HARNESS_DATA_DIR = value;
    else if (key === '--log') env.HARNESS_GUARD_LOG = value;
    else cwd = value;
  }
  const result = await summarizeGuardLog(args, {env, cwd});
  process.stdout.write(result.stdout); process.stderr.write(result.stderr); process.exitCode = result.code;
} catch (error) { console.error(`STATE UNREACHED: ${error.message}`); process.exitCode = 2; }
