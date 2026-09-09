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
const hookCommand = id => `node "\${CLAUDE_PLUGIN_ROOT}/scripts/hook.mjs" ${id} --runtime codex || exit 2`;
// Codex 0.153.4 uses cmd.exe /C with an outer-quoted command on Windows.
// EncodedCommand avoids embedded cmd quotes. This generated shim only locates
// the common executable and preserves streams/status; it contains no policy.
export function windowsHookCommand(id) {
  if (!/^[a-z-]+$/.test(id)) throw new Error('invalid hook identifier');
  const source = `$ErrorActionPreference='Stop'; try { $root=$env:PLUGIN_ROOT; if (-not $root) { $root=$env:CLAUDE_PLUGIN_ROOT }; if (-not $root) { throw 'plugin root missing' }; & node (Join-Path $root 'scripts/hook.mjs') '${id}' --runtime codex; if ($null -eq $LASTEXITCODE) { throw 'Node exit status missing' }; exit $LASTEXITCODE } catch { [Console]::Error.WriteLine('UNREACHED: '+$_.Exception.Message); exit 2 }`;
  return `powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand ${Buffer.from(source, 'utf16le').toString('base64')}`;
}
export function hookTransport(id, runtime) {
  if (runtime === 'claude') return {type: 'command', command: 'node', args: [`\${CLAUDE_PLUGIN_ROOT}/scripts/hook.mjs`, id, '--runtime', 'claude']};
  if (runtime === 'codex') return {type: 'command', command: hookCommand(id), commandWindows: windowsHookCommand(id)};
  throw new Error('unknown hook runtime');
}

// Deliberately limited YAML: flat mappings and a single scalar skill name.
// Reject unsupported structure instead of guessing a registration identity.
function skillName(body) {
  const frontmatter = /^---[ \t]*\r?\n([\s\S]*?)\r?\n---[ \t]*(?:\r?\n|$)/.exec(body)?.[1];
  if (frontmatter === undefined) throw new Error('skill frontmatter missing');
  const fields = new Map();
  for (const line of frontmatter.split(/\r?\n/)) {
    if (/^\s*(?:#.*)?$/.test(line)) continue;
    const field = /^([A-Za-z_][A-Za-z0-9_-]*)[ \t]*:[ \t]*(.*)$/.exec(line);
    if (!field || fields.has(field[1])) throw new Error('unsupported/duplicate skill frontmatter key');
    fields.set(field[1], field[2]);
  }
  const raw = fields.get('name') ?? '';
  const scalar = /^("(?:[^"\\]|\\.)*"|'(?:[^']|'')*'|[a-z0-9]+(?:-[a-z0-9]+)*)(?:[ \t]+#.*|[ \t]*)$/.exec(raw)?.[1];
  if (!scalar) throw new Error('unsupported skill name scalar');
  const name = scalar.startsWith('"') ? JSON.parse(scalar) : scalar.startsWith("'") ? scalar.slice(1, -1).replaceAll("''", "'") : scalar;
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(name)) throw new Error('invalid skill name');
  return name;
}

export function hookWiring(root = pluginRoot, configFile = path.join(root, 'hooks/hooks.json')) {
  const definitions = readJson(path.join(root, 'lib/hook-definitions.json'));
  const rows = [];
  for (const [event, groups] of Object.entries(readJson(configFile).hooks)) for (const group of groups) for (const hook of group.hooks) {
    const definition = definitions.find(entry => entry.event === event && ['claude', 'codex'].some(runtime => {
      const transport = hookTransport(entry.id, runtime);
      return hook.command === transport.command && JSON.stringify(hook.args) === JSON.stringify(transport.args) && hook.commandWindows === transport.commandWindows;
    }));
    if (hook.type !== 'command' || !definition || !fs.existsSync(path.join(root, 'scripts/hook.mjs')) || (definition.script && !fs.existsSync(path.join(root, definition.script)))) throw new Error('unresolved hook transport/target');
    rows.push({event, matcher: group.matcher ?? '', command: hook.command, ...(hook.args ? {args: hook.args} : {}), ...(hook.commandWindows ? {commandWindows: hook.commandWindows} : {}), script: definition.script ?? null});
  }
  return rows;
}

export function projections(root = pluginRoot) {
  const manifest = readJson(path.join(root, '.claude-plugin/plugin.json'));
  const hooks = {}, codexHooks = {};
  const seen = new Set();
  const registrations = new Set();
  for (const entry of readJson(path.join(root, 'lib/hook-definitions.json'))) {
    if (seen.has(entry.id) || !/^[a-z-]+$/.test(entry.id)) throw new Error('duplicate/invalid hook identifier');
    seen.add(entry.id);
    const registration = JSON.stringify([entry.event, entry.matcher ?? '', entry.script ?? '']);
    if (registrations.has(registration)) throw new Error('duplicate hook registration');
    registrations.add(registration);
    const hook = {...hookTransport(entry.id, 'claude'), timeout: entry.timeout};
    (hooks[entry.event] ??= []).push({...entry.matcher ? {matcher: entry.matcher} : {}, hooks: [hook]});
    (codexHooks[entry.event] ??= []).push({...entry.matcher ? {matcher: entry.matcher} : {}, hooks: [{...hookTransport(entry.id, 'codex'), timeout: entry.timeout}]});
  }
  for (const id of ['context', 'guard', 'workspace', 'stop', 'role-start', 'role-stop']) if (!seen.has(id)) throw new Error(`required hook missing: ${id}`);
  return {
    '.codex-plugin/plugin.json': encoded({...manifest, hooks: './hooks/codex.json', interface: {displayName: manifest.name, shortDescription: manifest.description, longDescription: manifest.description, developerName: manifest.author.name, category: 'Productivity', capabilities: ['Write'], defaultPrompt: []}}),
    'hooks/hooks.json': encoded({description: 'Generated Claude exec transport from lib/hook-definitions.json; shared Node handlers.', hooks}),
    'hooks/codex.json': encoded({description: 'Generated Codex transport from lib/hook-definitions.json; replaces default hooks to avoid duplicate registration.', hooks: codexHooks}),
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
    const name = skillName(body);
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
