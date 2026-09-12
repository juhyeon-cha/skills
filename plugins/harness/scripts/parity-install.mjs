import fs from 'node:fs';
import {installDistribution, diagnoseInstallation} from '../lib/runtime/parity-install.mjs';
try {
  const [action, file, ...extra] = process.argv.slice(2);
  if (!['stage', 'diagnose'].includes(action) || !file || extra.length)
    throw new Error('usage: parity-install.mjs stage|diagnose <options.json>');
  const options = JSON.parse(fs.readFileSync(file, 'utf8'));
  const result = action === 'stage' ? installDistribution(options) : diagnoseInstallation(options);
  console.log(JSON.stringify(result));
  if (action === 'diagnose' && result.loaded !== 'PASS') process.exitCode = 1;
} catch (error) {
  console.log(JSON.stringify({status: 'UNREACHED', reason: error.message}));
  process.exitCode = 1;
}
