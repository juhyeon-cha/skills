#!/usr/bin/env node
import { worktreeName } from '../lib/workspace/worktree-name.mjs';
try {
  process.stdout.write(worktreeName(process.argv[2]) + '\n');
} catch (error) {
  process.stderr.write(error.message + '\n');
  process.exitCode = 1;
}
