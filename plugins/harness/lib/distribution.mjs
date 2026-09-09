import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {loadRole} from './roles.mjs';
import {roleNames} from './role-identities.mjs';

export const pluginRoot = fs.realpathSync(fileURLToPath(new URL('../', import.meta.url)));
export const digest = bytes => createHash('sha256').update(bytes).digest('hex');
export const readJson = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const encoded = value => JSON.stringify(value, null, 2) + '\n';
const hookCommand = id => `node "\${CLAUDE_PLUGIN_ROOT}/scripts/hook.mjs" ${id} || exit 2`;

export function hookWiring(root = pluginRoot, configFile = path.join(root, 'hooks/hooks.json')) {
  const definitions = readJson(path.join(root, 'lib/hook-definitions.json'));
  const rows = [];
  for (const [event, groups] of Object.entries(readJson(configFile).hooks)) for (const group of groups) for (const hook of group.hooks) {
    const definition = definitions.find(entry => entry.event === event && (hook.command === hookCommand(entry.id) || (entry.script && hook.command === `bash "\${CLAUDE_PLUGIN_ROOT}/${entry.script}"`)));
    if (hook.type !== 'command' || !definition || !fs.existsSync(path.join(root, 'scripts/hook.mjs')) || (definition.script && !fs.existsSync(path.join(root, definition.script)))) throw new Error('unresolved hook transport/target');
    rows.push({event, matcher: group.matcher ?? '', command: hook.command, script: definition.script ?? null});
  }
  return rows;
}

export function projections(root = pluginRoot) {
  const manifest = readJson(path.join(root, '.claude-plugin/plugin.json'));
  const hooks = {};
  const seen = new Set();
  const registrations = new Set();
  for (const entry of readJson(path.join(root, 'lib/hook-definitions.json'))) {
    if (seen.has(entry.id) || !/^[a-z-]+$/.test(entry.id)) throw new Error('duplicate/invalid hook identifier');
    seen.add(entry.id);
    const registration = JSON.stringify([entry.event, entry.matcher ?? '', entry.script ?? '']);
    if (registrations.has(registration)) throw new Error('duplicate hook registration');
    registrations.add(registration);
    const hook = {type: 'command', command: hookCommand(entry.id), timeout: entry.timeout};
    (hooks[entry.event] ??= []).push({...entry.matcher ? {matcher: entry.matcher} : {}, hooks: [hook]});
  }
  for (const id of ['context', 'guard', 'workspace', 'stop', 'role-start', 'role-stop']) if (!seen.has(id)) throw new Error(`required hook missing: ${id}`);
  return {
    '.codex-plugin/plugin.json': encoded({...manifest, interface: {displayName: manifest.name, shortDescription: manifest.description, longDescription: manifest.description, developerName: manifest.author.name, category: 'Productivity', capabilities: ['Write'], defaultPrompt: []}}),
    'hooks/hooks.json': encoded({description: 'Generated from lib/hook-definitions.json; shared runtime hooks, Node prerequisite.', hooks}),
  };
}

export function generateDistribution(root = pluginRoot) {
  for (const [relative, text] of Object.entries(projections(root))) {
    const file = path.join(root, relative); fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, text);
  }
  return inspectDistribution(root);
}

export function inspectDistribution(root = pluginRoot) {
  root = fs.realpathSync(root);
  for (const [relative, text] of Object.entries(projections(root))) if (fs.readFileSync(path.join(root, relative), 'utf8') !== text) throw new Error(`generated drift: ${relative}`);
  const names = new Set();
  const skills = fs.readdirSync(path.join(root, 'skills')).sort().map(directory => {
    const relative = `skills/${directory}/SKILL.md`;
    const body = fs.readFileSync(path.join(root, relative), 'utf8');
    const name = /^name: (.+)$/m.exec(body)?.[1];
    if (!name || names.has(name)) throw new Error('missing/duplicate skill name');
    names.add(name); return {name, path: relative, hash: digest(body)};
  });
  if (!skills.length) throw new Error('skills missing');
  const roles = roleNames.map(role => { const entry = loadRole(role, root); return {role, hash: entry.sha256}; });
  if (fs.readdirSync(path.join(root, 'agents')).filter(name => name.endsWith('.md')).length !== roles.length) throw new Error('unexpected role registration');
  const files = {};
  function walk(directory, prefix = '') {
    for (const name of fs.readdirSync(directory).sort()) {
      const file = path.join(directory, name); const relative = prefix + name; const stat = fs.lstatSync(file);
      if (stat.isSymbolicLink()) throw new Error(`symlink artifact unsupported: ${relative}`);
      if (stat.isDirectory()) walk(file, relative + '/');
      else if (stat.isFile()) files[relative] = digest(fs.readFileSync(file));
      else throw new Error(`unsupported artifact: ${relative}`);
    }
  }
  walk(root);
  const manifest = readJson(path.join(root, '.claude-plugin/plugin.json'));
  const contextHash = files['hooks/session-context.md'];
  if (!contextHash) throw new Error('context missing');
  for (const hook of readJson(path.join(root, 'lib/hook-definitions.json'))) if (hook.script && !files[hook.script]) throw new Error('hook implementation missing');
  return {root, version: manifest.version, hash: digest(encoded(files)), files, skills, roles, contextHash};
}
