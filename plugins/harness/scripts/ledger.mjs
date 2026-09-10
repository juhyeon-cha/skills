#!/usr/bin/env node
import { executeLedger } from '../lib/ledger.mjs';
const chunks = [];
if (!process.stdin.isTTY) for await (const chunk of process.stdin) chunks.push(chunk);
const result = await executeLedger(process.argv.slice(2), {
  input: Buffer.concat(chunks),
  inheritStdin: process.stdin.isTTY,
});
process.stdout.write(result.stdout);
process.stderr.write(result.stderr);
process.exitCode = result.code;
