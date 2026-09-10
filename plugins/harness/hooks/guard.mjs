#!/usr/bin/env node
import fs from 'node:fs';
try {
  const { evaluateGuard } = await import('../lib/guard/guard.mjs');
  const result = await evaluateGuard(JSON.parse(fs.readFileSync(0, 'utf8')));
  process.stdout.write(result.stdout);
  process.stderr.write(result.stderr);
  process.exitCode = result.code;
} catch (error) {
  console.error(`GUARD-DENY: UNREACHED — ${error.message}`);
  process.exitCode = 2;
}
