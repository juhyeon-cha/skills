#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import {ledgerRoot} from '../lib/ledger.mjs';

try {
  const explicit = process.env.HARNESS_ROOT;
  const root = await ledgerRoot(process.cwd(), explicit ? path.resolve(explicit) : undefined);
  // Discovery only checks file presence, never backend or configuration contents.
  // Unlike an explicit ledger coordinate, the legacy discovery override must
  // itself contain the marker and must not fall back to an ancestor.
  if (explicit && !(await fs.stat(path.join(root, '.harness.json')).then(value => value.isFile(), () => false))) {
    throw new Error(`HARNESS_ROOT='${explicit}' 는 하네스 루트가 아니다 (.harness.json 없음)`);
  }
  process.stdout.write((explicit || root) + '\n');
} catch (error) {
  process.stderr.write(`harness-root: ${error.message}\n`);
  process.exitCode = 1;
}
