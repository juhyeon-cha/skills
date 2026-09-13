import fs from 'node:fs';
import {pluginRoot} from '../lib/distribution.mjs';
import {beginAntigravityRole, bindAntigravityRole, completeAntigravityRole} from '../lib/runtime/antigravity-roles.mjs';
try {
  const [action, file] = process.argv.slice(2);
  const fn = {begin: beginAntigravityRole, bind: bindAntigravityRole, complete: completeAntigravityRole}[action];
  if (!fn || !file || process.argv.length !== 4) throw new Error('usage: begin|bind|complete <input.json>');
  const input = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (typeof input.data !== 'string') throw new Error('explicit data required');
  console.log(JSON.stringify(await fn(input, {root: pluginRoot, env: {...process.env, HARNESS_DATA_DIR: input.data}})));
} catch (error) {
  console.error(`ANTIGRAVITY ROLE UNREACHED: ${error.message}`);
  process.exitCode = 2;
}
