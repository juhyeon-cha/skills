#!/usr/bin/env node
import {consumerContext, cliOptions, isMain, cli} from '../lib/ledger-view.mjs';

// The ledger adapter owns sync policy and wording. A verdict is read-only by
// default; retain the explicit legacy write switch and provide native --push.
export async function checkLedger(options = {}) {
  const context = await consumerContext(options);
  const push = options.push ?? Boolean(context.env.LEDGER_CHECK_PUSH);
  return context.ledger(['sync-check', ...(push ? ['--push'] : [])]);
}
if (isMain(import.meta.url)) await cli(() => {
  const {args, root} = cliOptions(process.argv.slice(2));
  const push = args.includes('--push'), positional = args.filter(arg => arg !== '--push');
  if (positional.length > 1 || (root && positional.length)) throw new Error('사용법: ledger-check.mjs [--root <root>|<root>] [--push]');
  return checkLedger({root: root ?? positional[0], ...(push ? {push: true} : {})});
});
