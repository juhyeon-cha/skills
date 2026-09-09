#!/usr/bin/env node
import {inspectWorkspace, gitEnvironment} from '../lib/workspace.mjs';
import {runPreparation} from '../lib/preparation.mjs';
// A vanished waiter does not own the worker's lifetime.
for (const stream of [process.stdout, process.stderr]) stream.on('error', error => { if (error.code !== 'EPIPE') throw error; });
try {
  const identity = await inspectWorkspace(process.argv[2]);
  if (!identity.linked) throw new Error('preparation requires a linked workspace');
  const result = await runPreparation(identity, {env: gitEnvironment(), say: text => { if (text) process.stderr.write(text + '\n'); }});
  process.stdout.write(JSON.stringify(result) + '\n');
} catch (error) { process.stderr.write(error.message + '\n'); process.exitCode = 1; }
