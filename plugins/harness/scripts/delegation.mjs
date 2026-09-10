import fs from 'node:fs';
import {
  beginDelegation,
  bindDelegation,
  completeDelegation,
  auditDelegation,
} from '../lib/runtime/delegation.mjs';

try {
  const [action, input, ...extra] = process.argv.slice(2);
  const actions = {
    begin: beginDelegation,
    bind: bindDelegation,
    complete: completeDelegation,
    audit: auditDelegation,
  };
  if (!Object.hasOwn(actions, action) || !input || extra.length)
    throw new Error('usage: delegation.mjs begin|bind|complete|audit <input.json>');
  const result = await actions[action](JSON.parse(fs.readFileSync(input, 'utf8')));
  console.log(JSON.stringify(result));
  if (result.status === 'REJECTED') process.exitCode = 1;
} catch (error) {
  console.log(
    JSON.stringify({ format: 'harness-delegation-v1', status: 'REJECTED', reason: error.message }),
  );
  process.exitCode = 1;
}
