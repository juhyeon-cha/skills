import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {pluginRoot, inspectDistribution, generateDistribution, readJson, hookWiring} from '../../plugins/harness/lib/distribution.mjs';
import {registerRoles, verifyRegistration} from '../../plugins/harness/lib/runtime/roles.mjs';
import {installationPlan} from '../../plugins/harness/lib/runtime/parity-install.mjs';

const temp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'distribution-check-')));
let count = 0;
const check = (value, why) => { assert.ok(value, why); count++; };
try {
  const baseline = inspectDistribution();
  const copy = path.join(temp, 'harness'); fs.cpSync(pluginRoot, copy, {recursive: true});
  check(inspectDistribution(copy).hash === baseline.hash, 'relocation keeps content identity');
  check(generateDistribution(copy).hash === baseline.hash, 'generation has no self-referential drift');
  const validRegistration = registerRoles('claude', undefined, copy);
  const rejectedArtifact = () => {
    for (const action of [() => inspectDistribution(copy), () => registerRoles('claude', undefined, copy),
      () => verifyRegistration(validRegistration),
      () => installationPlan({source: copy, destination: path.join(temp, 'stage'), surface: 'claude-cli'})]) {
      assert.throws(action); count++;
    }
  };
  for (const relative of ['roles/reviewer.md', 'agents/reviewer.md',
    'native/claude/reviewer.md', 'native/codex/reviewer.toml', 'native/antigravity/reviewer.md']) {
    const file = path.join(copy, relative), before = fs.readFileSync(file);
    fs.unlinkSync(file); rejectedArtifact();
    check(!fs.existsSync(file), `validation does not regenerate missing ${relative}`);
    fs.writeFileSync(file, before);
    const unexpected = path.join(path.dirname(file), 'unexpected' + path.extname(file));
    fs.writeFileSync(unexpected, before); rejectedArtifact(); fs.unlinkSync(unexpected);
  }
  for (const relative of ['roles/reviewer.md', 'agents/reviewer.md', 'native/claude/reviewer.md']) {
    const file = path.join(copy, relative), before = fs.readFileSync(file);
    fs.appendFileSync(file, '\nchanged\n'); rejectedArtifact();
    check(fs.readFileSync(file, 'utf8').endsWith('\nchanged\n'), 'validation leaves stale input/output untouched');
    fs.writeFileSync(file, before);
  }
  for (const runtime of ['claude', 'codex', 'antigravity']) {
    const file = path.join(copy, 'native', runtime, `reviewer.${runtime === 'codex' ? 'toml' : 'md'}`);
    const before = fs.readFileSync(file, 'utf8');
    fs.writeFileSync(file, before.replace(/reviewer/g, 'implementer')); rejectedArtifact();
    fs.writeFileSync(file, before);
    fs.appendFileSync(file, '\n# Native-only setting comment\n');
    if (runtime === 'claude') generateDistribution(copy);
    check(inspectDistribution(copy).hash !== baseline.hash, `${runtime} native bytes enter artifact hash`);
    fs.writeFileSync(file, before);
    if (runtime === 'claude') generateDistribution(copy);
  }
  const markers = path.join(copy, '.in_use');
  const marker = path.join(markers, '12345');
  const samePayload = () => {
    const actual = inspectDistribution(copy);
    assert.deepEqual(actual.files, baseline.files);
    check(actual.hash === baseline.hash, 'runtime markers do not change payload identity');
  };
  fs.mkdirSync(markers); samePayload();
  for (const body of ['', '{"pid":12345,', '{"pid":12345,"procStart":"fixture"}']) {
    fs.writeFileSync(marker, body); samePayload();
  }
  fs.unlinkSync(marker); samePayload();
  for (const name of ['0', '01', '-1', 'notes', '.hidden']) {
    const file = path.join(markers, name); fs.writeFileSync(file, 'unexpected');
    assert.throws(() => inspectDistribution(copy), /unsupported runtime metadata/); count++;
    fs.unlinkSync(file);
  }
  fs.mkdirSync(marker);
  assert.throws(() => inspectDistribution(copy), /unsupported runtime metadata/); count++;
  fs.rmdirSync(marker);
  fs.symlinkSync(path.join(copy, 'hooks/session-context.md'), marker);
  assert.throws(() => inspectDistribution(copy), /unsupported runtime metadata/); count++;
  fs.unlinkSync(marker);
  fs.linkSync(path.join(copy, 'hooks/session-context.md'), marker);
  assert.throws(() => inspectDistribution(copy), /unsupported runtime metadata/); count++;
  fs.unlinkSync(marker);
  fs.rmdirSync(markers);
  for (const target of [copy, path.join(temp, 'missing')]) {
    fs.symlinkSync(target, markers);
    assert.throws(() => inspectDistribution(copy), /unsupported runtime metadata/); count++;
    fs.unlinkSync(markers);
  }
  fs.writeFileSync(markers, 'not a directory');
  assert.throws(() => inspectDistribution(copy), /unsupported runtime metadata/); count++;
  fs.unlinkSync(markers);
  fs.mkdirSync(markers); fs.writeFileSync(marker, 'fixture');
  // Deterministic disappearance at each runtime I/O boundary; payload I/O and
  // unrelated errors must remain failures. Restore the actual fs API each time.
  for (const [method, target, code, allowed] of [
    ['lstatSync', markers, 'ENOENT', true],
    ['readdirSync', markers, 'ENOENT', true],
    ['lstatSync', marker, 'ENOENT', true],
    ['lstatSync', marker, 'EACCES', false],
    ['lstatSync', path.join(copy, 'lib/distribution.mjs'), 'ENOENT', false],
    ['readFileSync', path.join(copy, 'lib/distribution.mjs'), 'ENOENT', false],
  ]) {
    const original = fs[method]; let reached = false;
    fs[method] = (file, ...args) => {
      if (file === target) { reached = true; throw Object.assign(new Error(code), {code}); }
      return original(file, ...args);
    };
    try {
      if (allowed) samePayload();
      else { assert.throws(() => inspectDistribution(copy), {code}); count++; }
      check(reached, `fault reached: ${method} ${target}`);
    } finally { fs[method] = original; }
  }
  fs.rmSync(markers, {recursive: true}); samePayload();
  for (const relative of ['ordinary.txt', '.hidden', 'lib/.in_use/12345', 'lib/distribution.mjs', 'roles/reviewer.md', 'hooks/session-context.md', '.claude-plugin/plugin.json']) {
    const file = path.join(copy, relative);
    const before = fs.existsSync(file) ? fs.readFileSync(file) : null;
    fs.mkdirSync(path.dirname(file), {recursive: true}); fs.appendFileSync(file, '\n');
    if (relative.startsWith('roles/')) generateDistribution(copy);
    check(inspectDistribution(copy).hash !== baseline.hash, `payload change detected: ${relative}`);
    if (before === null) fs.unlinkSync(file); else fs.writeFileSync(file, before);
    if (relative.startsWith('roles/')) generateDistribution(copy);
  }
  const claude = readJson(path.join(copy, '.claude-plugin/plugin.json'));
  const codex = readJson(path.join(copy, '.codex-plugin/plugin.json'));
  check(claude.version === codex.version && claude.description === codex.description, 'Claude metadata owns version/description');
  check(!('skills' in codex) && codex.hooks === './hooks/codex.json', 'one default skills registration and one Codex hook override');
  const wiring = hookWiring(copy);
  check(wiring.length === 6 && wiring.filter(e => e.script).length === 4, 'all transports resolved; four common handlers and two observers');
  const command = hookWiring(copy, path.join(copy, 'hooks/codex.json')).find(e => e.event === 'PreToolUse').command;
  const missingEnv = {...process.env, PATH: path.join(temp, 'empty-path'), CLAUDE_PLUGIN_ROOT: copy, HARNESS_DOCTOR_DIR: ''};
  const oldCommand = command.replace(' || exit 2', '');
  check(oldCommand !== command && spawnSync('/bin/sh', ['-c', oldCommand], {env: missingEnv}).status === 127, 'negative control: missing Node without transport returns 127');
  check(spawnSync('/bin/sh', ['-c', command], {env: missingEnv}).status === 2, 'actual generated transport maps missing Node to block rc2');
  const nodeOnly = path.join(temp, 'node-only'); fs.mkdirSync(nodeOnly); fs.symlinkSync(process.execPath, path.join(nodeOnly, 'node'));
  check(spawnSync('/bin/sh', ['-c', command], {env: {...missingEnv, HARNESS_RUNTIME: 'codex', PATH: nodeOnly}, input: JSON.stringify({hook_event_name: 'PreToolUse', session_id: 'fixture', cwd: temp, tool_name: 'Bash', tool_input: {command: 'pwd'}})}).status === 0, 'native policy works without Bash or jq');
  const legacy = path.join(temp, 'legacy-hooks.json');
  fs.writeFileSync(legacy, JSON.stringify({hooks: Object.fromEntries(wiring.filter(e => e.script).map(e => [e.event, [{...e.matcher ? {matcher: e.matcher} : {}, hooks: [{type: 'command', command: `bash "\${CLAUDE_PLUGIN_ROOT}/${e.script}"`}]}]]))}));
  assert.throws(() => hookWiring(copy, legacy)); count++; // Old metadata is not evidence that the new native artifact loaded.
  for (const file of ['.codex-plugin/plugin.json', 'hooks/hooks.json', 'agents/reviewer.md', 'hooks/session-context.md']) {
    const full = path.join(copy, file); const before = fs.readFileSync(full);
    fs.unlinkSync(full); assert.throws(() => inspectDistribution(copy)); count++;
    fs.writeFileSync(full, before);
  }
  const manifest = path.join(copy, '.codex-plugin/plugin.json');
  fs.writeFileSync(manifest, JSON.stringify({...codex, skills: ['./skills', './skills']}));
  assert.throws(() => inspectDistribution(copy)); count++; generateDistribution(copy);
  const registry = path.join(copy, 'lib/hook-definitions.json'); const definitions = readJson(registry);
  fs.writeFileSync(registry, JSON.stringify([...definitions, definitions[0]]));
  assert.throws(() => inspectDistribution(copy)); count++; fs.copyFileSync(path.join(pluginRoot, 'lib/hook-definitions.json'), registry);
  fs.writeFileSync(registry, JSON.stringify([...definitions, {...definitions[0], id: 'duplicate-context'}]));
  assert.throws(() => generateDistribution(copy)); count++; fs.copyFileSync(path.join(pluginRoot, 'lib/hook-definitions.json'), registry);
  fs.writeFileSync(registry, '[]'); assert.throws(() => generateDistribution(copy)); count++; fs.copyFileSync(path.join(pluginRoot, 'lib/hook-definitions.json'), registry);
  const skill = baseline.skills[0].path;
  const duplicateDir = path.join(copy, 'skills/name-variant'); fs.mkdirSync(duplicateDir);
  const develop = fs.readFileSync(path.join(copy, 'skills/develop/SKILL.md'), 'utf8');
  for (const declaration of ['name: "develop"', "name: 'develop'", 'name: develop # comment', 'name :    develop   ', 'name: "\\u0064evelop"', '"name": develop']) {
    fs.writeFileSync(path.join(duplicateDir, 'SKILL.md'), develop.replace(/^name: develop$/m, declaration));
    assert.throws(() => inspectDistribution(copy), undefined, `duplicate or unsupported YAML: ${declaration}`); count++;
  }
  fs.writeFileSync(path.join(duplicateDir, 'SKILL.md'), '---\ndescription: fixture\n---\nname: body-only\n');
  assert.throws(() => inspectDistribution(copy), undefined, 'body name cannot replace missing frontmatter name'); count++;
  fs.writeFileSync(path.join(duplicateDir, 'SKILL.md'), '---\nname: "unique-fixture" # comment\ndescription: fixture\n---\nname: develop\n');
  check(inspectDistribution(copy).skills.some(s => s.name === 'unique-fixture'), 'quoted unique name normalized; body ignored');
  fs.rmSync(duplicateDir, {recursive: true});
  fs.mkdirSync(path.join(copy, 'skills/duplicate')); fs.copyFileSync(path.join(copy, skill), path.join(copy, 'skills/duplicate/SKILL.md'));
  assert.throws(() => inspectDistribution(copy)); count++; fs.rmSync(path.join(copy, 'skills/duplicate'), {recursive: true});
  const registration = registerRoles('codex', path.join(temp, 'agents'), copy);
  fs.copyFileSync(registration.roles[0].file, path.join(temp, 'agents/duplicate.toml'));
  assert.throws(() => verifyRegistration(registration)); count++;
  fs.appendFileSync(path.join(copy, 'hooks/session-context.md'), '\nchanged context\n');
  check(inspectDistribution(copy).version === baseline.version && inspectDistribution(copy).hash !== baseline.hash, 'same version different source distinguished');
  console.log(`PASS distribution: ${count} assertions; Claude original metadata retained`);
} finally { fs.rmSync(temp, {recursive: true, force: true}); }
