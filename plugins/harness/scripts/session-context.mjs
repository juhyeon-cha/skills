#!/usr/bin/env node
import { pluginRoot } from '../lib/distribution.mjs';
import { sessionContext } from '../lib/session-context.mjs';
try {
  console.log(JSON.stringify(sessionContext(pluginRoot)));
} catch (error) {
  console.error(`UNREACHED: ${error.message}`);
  process.exitCode = 2;
}
