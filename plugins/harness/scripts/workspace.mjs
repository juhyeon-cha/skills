#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {workspaceArguments} from '../lib/workspace-command.mjs';
import {inspectWorkspace, createWorkspace, enterWorkspace, cleanupWorkspace} from '../lib/workspace.mjs';

const say = text => { if (text) process.stderr.write(text + '\n'); };
const legacyCleanup = process.argv.includes('--legacy-cleanup');
const report = result => {
  if (!legacyCleanup) process.stdout.write(JSON.stringify(result) + '\n');
  else if (result.removed.length) process.stdout.write(`${path.basename(result.main)}\t${result.target}\n`);
};
let action;
try {
  let args = process.argv.slice(2); action = args.shift();
  if (action === 'hook-enter') {
    if (args.length) throw new Error('hook-enter accepts stdin only');
    const input = JSON.parse(fs.readFileSync(0, 'utf8'));
    if (typeof input.cwd !== 'string' || !path.isAbsolute(input.cwd)) throw new Error('payload cwd required');
    await enterWorkspace(input.cwd, {say});
  } else {
    args = args.filter(arg => arg !== '--legacy-cleanup');
    const parsed = workspaceArguments([action, ...args]);
    const {cwd, story, destination, force} = parsed;
    if (legacyCleanup && action !== 'cleanup') throw new Error('legacy output is cleanup-only');
    if (action === 'inspect') report(await inspectWorkspace(cwd));
    else if (action === 'enter') report(await enterWorkspace(cwd, {say}));
    else if (action === 'create') report(await createWorkspace(cwd, story, {destination}));
    else report(await cleanupWorkspace(cwd, story, {force, say}));
  }
} catch (error) {
  if (error.partial) report(error.partial);
  say(`${action === 'hook-enter' ? '원장 배선 실패 — ' : 'workspace: '}${error.message}`);
  process.exitCode = action === 'hook-enter' ? 2 : 1;
}
