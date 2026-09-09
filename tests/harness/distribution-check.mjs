import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {pluginRoot, inspectDistribution, generateDistribution, readJson, hookWiring} from '../../plugins/harness/lib/distribution.mjs';
import {registerRoles, verifyRegistration} from '../../plugins/harness/lib/roles.mjs';

const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'distribution-check-'));
let count = 0;
const check = (value, why) => { assert.ok(value, why); count++; };
try {
  const baseline = inspectDistribution();
  const copy = path.join(temp, 'harness'); fs.cpSync(pluginRoot, copy, {recursive: true});
  check(inspectDistribution(copy).hash === baseline.hash, 'relocation keeps content identity');
  check(generateDistribution(copy).hash === baseline.hash, 'generation has no self-referential drift');
  const claude = readJson(path.join(copy, '.claude-plugin/plugin.json'));
  const codex = readJson(path.join(copy, '.codex-plugin/plugin.json'));
  check(claude.version === codex.version && claude.description === codex.description, 'Claude metadata owns version/description');
  check(!('skills' in codex) && !('hooks' in codex), 'one default skills/hooks registration');
  const wiring = hookWiring(copy);
  check(wiring.length === 6 && wiring.filter(e => e.script).length === 4, 'all transports resolved; four Bash owners and two observers');
  const command = wiring.find(e => e.event === 'PreToolUse').command;
  const missingEnv = {...process.env, PATH: path.join(temp, 'empty-path'), CLAUDE_PLUGIN_ROOT: copy, HARNESS_DOCTOR_DIR: ''};
  const oldCommand = command.replace(' || exit 2', '');
  check(oldCommand !== command && spawnSync('/bin/sh', ['-c', oldCommand], {env: missingEnv}).status === 127, 'negative control: missing Node without transport returns 127');
  check(spawnSync('/bin/sh', ['-c', command], {env: missingEnv}).status === 2, 'actual generated transport maps missing Node to block rc2');
  const nodeOnly = path.join(temp, 'node-only'); fs.mkdirSync(nodeOnly); fs.symlinkSync(process.execPath, path.join(nodeOnly, 'node'));
  check(spawnSync('/bin/sh', ['-c', command], {env: {...missingEnv, PATH: nodeOnly}, input: JSON.stringify({hook_event_name: 'PreToolUse', session_id: 'fixture', cwd: temp, tool_name: 'Bash', tool_input: {command: 'pwd'}})}).status === 2, 'missing Bash transport blocks');
  const legacy = path.join(temp, 'legacy-hooks.json');
  fs.writeFileSync(legacy, JSON.stringify({hooks: Object.fromEntries(wiring.filter(e => e.script).map(e => [e.event, [{...e.matcher ? {matcher: e.matcher} : {}, hooks: [{type: 'command', command: `bash "\${CLAUDE_PLUGIN_ROOT}/${e.script}"`}]}]]))}));
  check(hookWiring(copy, legacy).length === 4, 'existing Claude Bash wiring resolves');
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
