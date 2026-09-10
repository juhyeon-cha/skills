#!/usr/bin/env node
import { inspectWorkspace, gitEnvironment } from '../lib/workspace/workspace.mjs';
import { runPreparation } from '../lib/workspace/preparation.mjs';
import fs from 'node:fs/promises';
import { appendFileSync } from 'node:fs';
import path from 'node:path';
// A vanished waiter does not own the worker's lifetime.
for (const stream of [process.stdout, process.stderr])
  stream.on('error', (error) => {
    if (error.code !== 'EPIPE') throw error;
  });
const ipc = process.platform === 'win32' ? process.env.HARNESS_PREPARE_IPC : null;
const diagnostic = (text) => {
  if (!text) return;
  if (ipc) appendFileSync(path.join(ipc, 'diagnostics.log'), text + '\n');
  else process.stderr.write(text + '\n');
};
try {
  const identity = await inspectWorkspace(process.argv[2]);
  if (!identity.linked) throw new Error('preparation requires a linked workspace');
  const result = await runPreparation(identity, { env: gitEnvironment(), say: diagnostic });
  const text = JSON.stringify(result) + '\n';
  if (ipc) {
    await fs.writeFile(path.join(ipc, 'result.tmp'), text, { flag: 'wx' });
    await fs.rename(path.join(ipc, 'result.tmp'), path.join(ipc, 'result.json'));
  } else process.stdout.write(text);
} catch (error) {
  diagnostic(error.message);
  process.exitCode = 1;
}
