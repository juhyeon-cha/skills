import fs from 'node:fs';
import {resolveState, guardLog, readActors, bindActor, cancelSession, isCancelled, appendState, tsv} from '../lib/state.mjs';
try {
  const [action, ...args] = process.argv.slice(2);
  if (action === 'guard') {
    await guardLog(JSON.parse(fs.readFileSync(0, 'utf8')), args[0]);
  } else if (action === 'guard-path') {
    if (process.env.HARNESS_GUARD_LOG) console.log(process.env.HARNESS_GUARD_LOG);
    else console.log((await resolveState({cwd: process.cwd()})).guardLog);
  } else {
    const [runtime, cwd, sessionId] = args;
    const scope = await resolveState({runtime: runtime || undefined, cwd, sessionId});
    if (action === 'paths') console.log(JSON.stringify(scope));
    else if (action === 'actors') { const result = readActors(scope); console.log(JSON.stringify(result)); if (result.status !== 'VERIFIED') process.exitCode = 1; }
    else if (action === 'bind') console.log(JSON.stringify(await bindActor(scope, {ledgerRoot: args[3], task: args[4], actor: args[5]})));
    else if (action === 'cancel') { cancelSession(scope); console.log(JSON.stringify({cancelled: true, sessionId})); }
    else if (action === 'cancelled') process.exitCode = isCancelled(scope) ? 0 : 1;
    else if (action === 'stop-log') appendState(scope.stopLog, [new Date().toISOString(), sessionId, args[3], args[4]].map(tsv).join('\t'), {maxLines: 0});
    else throw new Error('usage: paths|actors|cancel|cancelled <runtime> <repo> <session> | bind <runtime> <repo> <session> <ledger-root> <task> <actor> | guard <rule> (stdin event) | guard-path');
  }
} catch (error) { console.error(`STATE UNREACHED: ${error.message}`); process.exitCode = 2; }
