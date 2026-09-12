#!/usr/bin/env node
import fs from 'node:fs';
import {compareRuntimeParity} from '../lib/runtime/parity-contract.mjs';

try {
  if (process.argv.length !== 4) throw new Error('usage: runtime-parity.mjs <canonical-baseline.json> <reports.json>');
  const baseline = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const reports = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
  const support = fs.readFileSync(new URL('../docs/runtime-parity.md', import.meta.url), 'utf8');
  const result = compareRuntimeParity(baseline, reports, support);
  console.log(JSON.stringify(result));
  process.exitCode = result.status === 'MATCH' ? 0 : 1;
} catch (error) {
  console.error(JSON.stringify({status: 'MISMATCH', liveCertified: false, reason: error.message}));
  process.exitCode = 1;
}
