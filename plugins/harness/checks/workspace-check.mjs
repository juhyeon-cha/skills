#!/usr/bin/env node
// Read-only config + actual Git identity on every backend, without ledger calls.
import path from 'node:path';
import { loadConfig } from '../lib/config.mjs';
import { inspectWorkspace } from '../lib/workspace.mjs';
import { isMain, cli } from '../lib/ledger-view.mjs';

export async function checkWorkspace(target = process.cwd(), { env = process.env } = {}) {
  const root = path.resolve(target);
  await loadConfig(root);
  const identity = await inspectWorkspace(root, { env });
  return { code: 0, stdout: JSON.stringify(identity) + '\n' };
}
if (isMain(import.meta.url))
  await cli(() => {
    const args = process.argv.slice(2);
    if (args.length > 1) throw new Error('사용법: workspace-check.mjs [repo]');
    return checkWorkspace(args[0]);
  });
