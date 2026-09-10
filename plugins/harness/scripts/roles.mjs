import fs from 'node:fs';
import { registerRoles, verifyRegistration, roleCall, roleResult } from '../lib/roles.mjs';

// JSON files keep delegation text and runtime evidence out of shell quoting.
const read = (file) => JSON.parse(fs.readFileSync(file, 'utf8'));
const [action, first, second, third] = process.argv.slice(2);
try {
  let result;
  if (action === 'register') result = registerRoles(first, second);
  else if (action === 'verify') result = verifyRegistration(read(first));
  else if (action === 'call') result = roleCall(read(first), read(second));
  else if (action === 'result') result = roleResult(read(first), read(second), read(third));
  else
    throw new Error(
      'usage: register <claude|codex> [absolute agents directory] | verify <registration.json> | call <registration.json> <request.json> | result <registration.json> <call.json> <outcome.json>',
    );
  console.log(JSON.stringify(result));
  if (result.status === 'UNREACHED') process.exitCode = 1;
} catch (error) {
  console.log(JSON.stringify({ status: 'UNREACHED', reason: error.message }));
  process.exitCode = 1;
}
