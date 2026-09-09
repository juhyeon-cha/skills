#!/usr/bin/env node
import fs from 'node:fs';
try {
  const {evaluateStop} = await import('../lib/stop.mjs');
  const result = await evaluateStop(JSON.parse(fs.readFileSync(0, 'utf8')));
  process.stdout.write(result.stdout); process.stderr.write(result.stderr); process.exitCode = result.code;
} catch (error) { console.error(`STATE UNREACHED: ${error.message}; stop allowed`); process.exitCode = 0; }
