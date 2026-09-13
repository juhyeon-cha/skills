import fs from 'node:fs';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {inspectDistribution, digest, readJson, skillName} from '../distribution.mjs';
import {projectRole, nativeAgentName} from './roles.mjs';
import {diagnose} from './doctor.mjs';

const installationSurfaces = ['claude-cli', 'codex-cli', 'codex-desktop', 'antigravity-cli'];

const json = value => JSON.stringify(value, null, 2) + '\n';
const inside = (root, file) => file === root || file.startsWith(root + path.sep);
// Do not follow links even at an ancestor or at an absent final component.
function safePath(value) {
  if (!path.isAbsolute(value ?? '') || path.resolve(value) !== value)
    throw new Error('normalized absolute destination required');
  let current = path.parse(value).root;
  for (const part of value.slice(current.length).split(path.sep).filter(Boolean)) {
    current = path.join(current, part);
    if (!fs.existsSync(current)) {
      try { fs.lstatSync(current); throw new Error('dangling symlink destination'); }
      catch (error) { if (error.code !== 'ENOENT') throw error; }
      continue;
    }
    if (fs.lstatSync(current).isSymbolicLink()) throw new Error('symlink destination');
  }
  return value;
}
const fileHash = file => {
  safePath(file);
  if (!fs.existsSync(file)) return null;
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.nlink !== 1) throw new Error('managed destination is not a single-link file');
  return digest(fs.readFileSync(file));
};

/** Prepare provider-discoverable bytes without editing provider registries or trust.
 * Destination is the explicit bundle path passed to the provider's local installer.
 * Codex agentsDestination is its separately discovered native agents directory.
 */
export function installationPlan({source, destination, surface, agentsDestination}) {
  if (!installationSurfaces.includes(surface)) throw new Error('unknown surface');
  source = fs.realpathSync(source);
  safePath(destination);
  if (inside(source, destination) || inside(destination, source))
    throw new Error('source and destination must be disjoint');
  const runtime = surface.split('-')[0];
  if (runtime === 'codex') {
    safePath(agentsDestination);
    if ([source, destination].some(root => inside(root, agentsDestination) || inside(agentsDestination, root)))
      throw new Error('agents destination must be disjoint');
  } else if (agentsDestination !== undefined) throw new Error('unexpected agents destination');
  const artifact = inspectDistribution(source);
  const installedRoot = runtime === 'antigravity' ? path.join(destination, '.harness') : destination;
  const files = {};
  const modes = {};
  for (const relative of Object.keys(artifact.files)) {
    const original = path.join(source, relative);
    const file = path.join(installedRoot, relative);
    files[file] = fs.readFileSync(original);
    if (digest(files[file]) !== artifact.files[relative]) throw new Error('source changed while reading');
    modes[file] = fs.statSync(original).mode & 0o777;
  }
  const components = {skills: [], roles: [], hooks: []};
  if (runtime === 'antigravity') {
    const manifest = readJson(path.join(source, '.claude-plugin/plugin.json'));
    files[path.join(destination, 'plugin.json')] = json({name: manifest.name, description: manifest.description});
    // CLI plugin skills are flat Markdown. Canonical SKILL.md files remain only
    // inside the non-discovered runtime tree, avoiding two discovery registrations.
    for (const skill of artifact.skills) {
      const file = path.join(destination, 'skills', `${skill.name}.md`);
      files[file] = fs.readFileSync(path.join(source, skill.path), 'utf8')
        .replaceAll('${CLAUDE_PLUGIN_ROOT}', installedRoot);
      components.skills.push(file);
    }
    for (const {role} of artifact.roles) {
      const file = path.join(destination, 'agents', `${role}.md`);
      files[file] = projectRole('antigravity', role, source, installedRoot).text;
      components.roles.push(file);
    }
    const hooks = {};
    for (const [id, event] of [['context', 'PreInvocation'], ['guard', 'PreToolUse'], ['stop', 'Stop']]) {
      // Only provider-supported events enter the common Antigravity adapter.
      const handler = {type: 'command', command: `node ${shellQuote(path.join(installedRoot, 'scripts/hook.mjs'))} ${id} --runtime antigravity`, timeout: id === 'stop' ? 30 : 10};
      hooks[event] = event === 'PreToolUse' ? [{matcher: '*', hooks: [handler]}] : [handler];
      components.hooks.push(`${event}:${id}`);
    }
    files[path.join(destination, 'hooks.json')] = json({harness: hooks});
  } else {
    components.skills = artifact.skills.map(skill => path.join(installedRoot, skill.path));
    if (runtime === 'codex') {
      for (const {role} of artifact.roles) {
        const entry = projectRole('codex', role, source, installedRoot);
        const file = path.join(agentsDestination, `${entry.identifier}.toml`);
        files[file] = entry.text;
        components.roles.push(file);
      }
    } else components.roles = artifact.roles.map(({role}) => path.join(installedRoot, 'agents', `${role}.md`));
    components.hooks = readJson(path.join(source, 'lib/hook-definitions.json')).map(hook => `${hook.event}:${hook.id}`);
  }
  return {schemaVersion: 1, surface, runtime, destination, agentsDestination: agentsDestination ?? null,
    installedRoot, sourceHash: artifact.hash, version: artifact.version, contextHash: artifact.contextHash,
    skills: artifact.skills, roles: artifact.roles, components,
    modes: Object.fromEntries(Object.keys(files).map(file => [file, modes[file] ?? 0o644])),
    files: Object.fromEntries(Object.entries(files).map(([file, bytes]) => [file, Buffer.from(bytes)]))};
}
function shellQuote(value) { return "'" + value.replaceAll("'", "'\\''") + "'"; }
function receiptOf(plan) {
  const {files, ...metadata} = plan;
  return {...metadata, files: Object.fromEntries(Object.entries(files).map(([file, bytes]) => [file, digest(bytes)]))};
}
function validateReceipt(receipt, plan) {
  if (receipt?.schemaVersion !== 1 || receipt.destination !== plan.destination ||
      receipt.surface !== plan.surface || receipt.agentsDestination !== plan.agentsDestination ||
      !receipt.files || typeof receipt.files !== 'object' || Array.isArray(receipt.files))
    throw new Error('ownership receipt scope mismatch');
  for (const [file, hash] of Object.entries(receipt.files)) {
    if (!inside(plan.destination, file) && !(plan.agentsDestination &&
      path.dirname(file) === plan.agentsDestination && /^harness-(implementer|reviewer|evaluator)\.toml$/.test(path.basename(file))))
      throw new Error('ownership receipt path escape');
    if (!/^[a-f0-9]{64}$/.test(hash) || fileHash(file) !== hash ||
        (fs.statSync(file).mode & 0o777) !== receipt.modes?.[file])
      throw new Error(`managed file missing or edited: ${path.basename(file)}`);
  }
}

/** Install/update/rollback all use the same owned-file reconciliation.
 * Supply the earlier canonical source for rollback; never trust a version string.
 * No provider activation, trust grant, or loaded/live PASS is manufactured.
 */
export function installDistribution(options) {
  const plan = installationPlan(options);
  const receiptFile = plan.destination + '.harness-receipt.json';
  const lock = plan.destination + '.harness-lock';
  safePath(receiptFile); safePath(lock);
  fs.mkdirSync(path.dirname(plan.destination), {recursive: true});
  const lockFd = fs.openSync(lock, 'wx', 0o600);
  const originals = new Map();
  const written = [];
  try {
    const previous = fs.existsSync(receiptFile) ? readJson(receiptFile) : null;
    if (previous) validateReceipt(previous, plan);
    const wanted = receiptOf(plan);
    const names = new Set([...Object.keys(previous?.files ?? {}), ...Object.keys(plan.files)]);
    for (const file of names) {
      const actual = fileHash(file);
      if (!Object.hasOwn(previous?.files ?? {}, file) && actual !== null)
        throw new Error(`unowned destination collision: ${path.basename(file)}`);
      originals.set(file, actual === null ? null : {bytes: fs.readFileSync(file), mode: fs.statSync(file).mode & 0o777});
    }
    originals.set(receiptFile, fs.existsSync(receiptFile) ? fs.readFileSync(receiptFile) : null);
    // Fail before changing the destination when the source changed during planning.
    if (inspectDistribution(options.source).hash !== plan.sourceHash) throw new Error('source changed during planning');
    for (const file of names) {
      written.push(file);
      if (plan.files[file]) {
        fs.mkdirSync(path.dirname(file), {recursive: true});
        fs.writeFileSync(file, plan.files[file]);
        fs.chmodSync(file, plan.modes[file]);
      } else fs.unlinkSync(file);
    }
    const temporary = receiptFile + '.' + randomUUID();
    try {
      fs.writeFileSync(temporary, json(wanted), {flag: 'wx', mode: 0o600});
      fs.renameSync(temporary, receiptFile);
    } finally { if (fs.existsSync(temporary)) fs.unlinkSync(temporary); }
    return {status: 'STAGED', static: 'PASS', loaded: 'UNREACHED', live: 'UNREACHED', receipt: wanted};
  } catch (error) {
    // Try all recoverable files; persistent I/O errors or interruption can leave
    // drift which the next invocation rejects. No crash-atomic update claim.
    const recoveryErrors = [];
    for (const file of written.reverse()) {
      try {
        const before = originals.get(file);
        if (before === null) { if (fs.existsSync(file)) fs.unlinkSync(file); }
        else { fs.writeFileSync(file, before.bytes); fs.chmodSync(file, before.mode); }
      } catch (recoveryError) {
        recoveryErrors.push(new Error(`restore failed: ${file}: ${recoveryError.message}`, {cause: recoveryError}));
      }
    }
    if (recoveryErrors.length)
      throw new AggregateError([error, ...recoveryErrors],
        `installation failed: ${error.message}; ${recoveryErrors.map(item => item.message).join('; ')}`, {cause: error});
    throw error;
  } finally { fs.closeSync(lockFd); fs.unlinkSync(lock); }
}

export function diagnoseInstallation(options) {
  const report = {static: 'UNREACHED', loaded: 'UNREACHED', live: 'UNREACHED', reasons: []};
  try {
    const plan = installationPlan(options);
    const receipt = readJson(plan.destination + '.harness-receipt.json');
    validateReceipt(receipt, plan);
    if (JSON.stringify(receipt) !== JSON.stringify(receiptOf(plan))) throw new Error('stale source or projection receipt');
    // Unknown files are preserved, but another discoverable registration is a
    // diagnostic failure; preserving ownership never means silently activating it.
    const folders = [path.join(plan.destination, 'skills'),
      plan.agentsDestination ?? path.join(plan.destination, 'agents')];
    const names = new Set();
    function discover(folder, category) {
      safePath(folder);
      for (const entry of fs.readdirSync(folder)) {
        const file = path.join(folder, entry);
        safePath(file);
        if (fs.lstatSync(file).isDirectory()) { discover(file, category); continue; }
        if (!/\.(md|toml)$/.test(entry)) continue;
        const body = fs.readFileSync(file, 'utf8');
        const name = entry.endsWith('.toml') ? nativeAgentName(body) : skillName(body);
        const key = `${category}:${name}`;
        if (names.has(key)) throw new Error('duplicate discoverable skill or role');
        names.add(key);
      }
    }
    folders.forEach((folder, index) => discover(folder, index));
    report.static = 'PASS';
    report.artifact = {hash: plan.sourceHash, version: plan.version, root: plan.installedRoot};
    if (plan.runtime !== 'antigravity') {
      const observed = diagnose(plan.installedRoot, options.doctorDirectory, options.sessionId, options.source);
      report.reasons.push(...observed.reasons);
      if (observed.runtime !== plan.runtime) {
        report.reasons.push('observed runtime missing or differs from installation runtime');
      } else if (plan.runtime === 'codex') {
        // The current doctor binds runtime, source and session but has no
        // independently observed CLI/desktop identity. A caller/challenge label
        // cannot supply it. Later execution adapters must provide that evidence.
        report.reasons.push('surface identity unobserved; runtime receipt does not distinguish CLI from desktop');
      } else {
        report.loaded = observed.loaded;
        report.live = observed.live;
      }
    } else report.reasons.push('Antigravity execution/observation adapter pending; static projection is not loaded evidence');
  } catch (error) { report.reasons.push(error.message); }
  return report;
}
