import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const repo = fileURLToPath(new URL('../../', import.meta.url));
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'harness-audit-gate-'));
const write = (relative, body, executable = false) => {
  const file = path.join(temp, relative);
  fs.mkdirSync(path.dirname(file), {recursive: true});
  fs.writeFileSync(file, body, {mode: executable ? 0o755 : 0o644});
};
try {
  write('scripts/check.sh', fs.readFileSync(path.join(repo, 'scripts/check.sh')));
  write('plugins/toolkit/.claude-plugin/plugin.json', JSON.stringify({description: 'fixture'}));
  write('.claude-plugin/marketplace.json', JSON.stringify({plugins: [{name: 'toolkit', description: 'fixture'}]}));
  write('README.md', 'fixture');
  for (const directory of ['tests', 'docs', '.claude/skills']) fs.mkdirSync(path.join(temp, directory), {recursive: true});
  for (const command of ['claude', 'shellcheck']) write('bin/' + command, '#!/bin/sh\nexit 0\n', true);
  const env = {...process.env, PATH: path.join(temp, 'bin') + path.delimiter + process.env.PATH};
  delete env.HARNESS_ROOT;
  const run = extra => spawnSync('bash', [path.join(temp, 'scripts/check.sh')], {cwd: temp, env: {...env, ...extra}, encoding: 'utf8'});
  const audit = 'plugins/toolkit/skills/agent-doc-audit/check.sh';
  write(audit, "#!/bin/sh\nprintf '%s\\n' 'docs/rules.md:1:4-date:2026-01-01'\n", true);
  const advisory = run();
  assert.equal(advisory.status, 0, advisory.stdout + advisory.stderr);
  assert.match(advisory.stdout, /advisory findings/);
  write(audit, '#!/bin/sh\nexit 7\n', true);
  assert.equal(run().status, 1, 'an audit execution failure remains a gate failure');
  write(audit, "#!/bin/sh\nprintf '%s\\n' 'docs/rules.md:1:6-dead-path:missing.md'\n", true);
  assert.equal(run({HARNESS_ROOT: temp}).status, 1, 'path validity is distinct from style advice');
  console.log('PASS audit gate: style advisory, execution failure and broken-path failure');
} finally {
  fs.rmSync(temp, {recursive: true, force: true});
}
