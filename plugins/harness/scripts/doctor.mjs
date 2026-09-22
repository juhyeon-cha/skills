import { createChallenge, diagnose } from '../lib/runtime/doctor.mjs';
import { readJson } from '../lib/distribution.mjs';
try {
  const [action, first, second, third, fourth] = process.argv.slice(2);
  if (action === 'challenge')
    console.log(JSON.stringify(createChallenge(first, second, third, readJson(fourth))));
  else if (action === 'check') {
    const result = diagnose(first, second, third);
    console.log(JSON.stringify(result));
    if (result.static !== 'PASS' || result.loaded !== 'PASS' || result.live !== 'PASS')
      process.exitCode = 1;
  } else
    throw new Error(
      'usage: challenge <new state directory> <runtime> <installed root> <registration.json> | check <installed root> [state directory session-id]',
    );
} catch (error) {
  console.log(JSON.stringify({ status: 'UNREACHED', reason: error.message }));
  process.exitCode = 1;
}
