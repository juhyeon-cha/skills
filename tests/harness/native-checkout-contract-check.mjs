import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {inspectDistribution} from '../../plugins/harness/lib/distribution.mjs';

const source = fileURLToPath(new URL('../../', import.meta.url));
const temp = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'harness-checkout-')));
const plugin = path.join(temp, 'plugins/harness');
const git = (...args) => {
  const result = spawnSync('git', args, {cwd: temp, encoding: 'utf8'});
  assert.equal(result.status, 0, `${args.join(' ')}: ${result.stderr}`);
};
try {
  fs.cpSync(path.join(source, 'plugins/harness'), plugin, {recursive: true});
  fs.copyFileSync(path.join(source, '.gitattributes'), path.join(temp, '.gitattributes'));
  git('init', '--quiet');
  git('config', 'core.autocrlf', 'true');
  git('config', 'core.safecrlf', 'false');
  git('add', '.gitattributes', 'plugins/harness');
  fs.rmSync(plugin, {recursive: true});
  git('checkout-index', '--all', '--force');
  assert.doesNotThrow(() => inspectDistribution(plugin));
  assert.equal(fs.readFileSync(path.join(plugin, '.codex-plugin/plugin.json'), 'utf8').includes('\r'), false);
  console.log('PASS: autocrlf checkout preserves canonical generated plugin bytes');

  fs.rmSync(path.join(temp, '.gitattributes'));
  git('update-index', '--force-remove', '.gitattributes');
  fs.rmSync(plugin, {recursive: true});
  git('checkout-index', '--all', '--force');
  assert.equal(fs.readFileSync(path.join(plugin, '.codex-plugin/plugin.json'), 'utf8').includes('\r\n'), true);
  assert.throws(() => inspectDistribution(plugin), /generated drift/);
  console.log('PASS: removing LF contract produces detected generated drift');
} finally {
  fs.rmSync(temp, {recursive: true, force: true});
}
