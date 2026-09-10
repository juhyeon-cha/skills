#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { ledgerRoot } from '../lib/ledger.mjs';

try {
  const explicit = process.env.HARNESS_ROOT;
  // Discovery only checks file presence, never backend or configuration contents.
  // Unlike an explicit ledger coordinate, the legacy discovery override must
  // itself contain the marker and must not fall back to an ancestor.
  // Concatenate without path.join/resolve: removing '..' first can make an
  // inaccessible explicit path (missing/..) look like its existing ancestor.
  // Windows APIs can normalize dot segments too. Check every prefix before
  // traversing '..', so a missing directory or ordinary file cannot disappear.
  if (explicit) {
    const offset = path.parse(explicit).root.length;
    const components = process.platform === 'win32' ? /[^\\/]+/g : /[^/]+/g;
    for (const component of explicit.slice(offset).matchAll(components)) {
      if (component[0] !== '..') continue;
      const prefix = explicit.slice(0, offset + component.index) || '.';
      if (
        !(await fs.stat(prefix).then(
          (value) => value.isDirectory(),
          () => false,
        ))
      ) {
        throw new Error(`HARNESS_ROOT='${explicit}' 는 하네스 루트가 아니다 (.harness.json 없음)`);
      }
    }
  }
  if (
    explicit &&
    !(await fs.stat(`${explicit}${path.sep}.harness.json`).then(
      (value) => value.isFile(),
      () => false,
    ))
  ) {
    throw new Error(`HARNESS_ROOT='${explicit}' 는 하네스 루트가 아니다 (.harness.json 없음)`);
  }
  process.stdout.write((explicit || (await ledgerRoot(process.cwd()))) + '\n');
} catch (error) {
  process.stderr.write(`harness-root: ${error.message}\n`);
  process.exitCode = 1;
}
