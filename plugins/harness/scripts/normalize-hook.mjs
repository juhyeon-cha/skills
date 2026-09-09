import fs from 'node:fs';
import {normalizeHookEvent} from '../lib/hook-event.mjs';
try {
  const event = normalizeHookEvent(JSON.parse(fs.readFileSync(0, 'utf8')));
  const paths = event.harness_operations.flatMap(op => op.kind === 'move' ? [op.source, op.destination] : [op.path]);
  if (process.platform !== 'win32' && paths.some(p => /^[A-Za-z]:[\\/]|^\\\\/.test(p))) throw new Error('Windows filesystem policy is unavailable on this host');
  console.log(JSON.stringify(event));
} catch (error) {
  console.error(`GUARD-DENY: UNREACHED — ${error.message}`);
  process.exitCode = 2;
}
