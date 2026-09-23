import path from 'node:path';
import fs from 'node:fs';
import {fileURLToPath} from 'node:url';
import {projectRole} from './roles.mjs';
import {roleCapabilities, requiredRoleTools} from './role-capabilities.mjs';

const plugin = fileURLToPath(new URL('../../', import.meta.url));

// Caller-supplied requests describe a hypothetical call, never host observations.
export function explainRole(input, root = plugin) {
  root = fs.realpathSync(root);
  if (!input || typeof input !== 'object' || Array.isArray(input) ||
      Object.keys(input).some(key => !['runtime', 'role', 'execution', 'modelOptions', 'installedRoot'].includes(key)))
    throw new Error('explain input invalid');
  const {runtime, role, execution, modelOptions, installedRoot = root} = input;
  if (!['claude', 'codex', 'antigravity'].includes(runtime) ||
      execution !== 'native')
    throw new Error('unsupported runtime/execution');
  if (typeof installedRoot !== 'string' || !path.isAbsolute(installedRoot))
    throw new Error('absolute installedRoot required');
  if (modelOptions !== undefined)
    roleCapabilities(runtime, role, {availableTools: requiredRoleTools(runtime, role), modelOptions});
  const projection = projectRole(runtime, role, root, installedRoot);
  return {
    runtime, role, execution,
    canonical: {file: projection.source, sha256: projection.sha256},
    native: {
      source: path.join(root, 'native', runtime, `${role}.${runtime === 'codex' ? 'toml' : 'md'}`),
      artifact: runtime === 'claude' ? path.join(root, 'agents', `${role}.md`) : null,
      applicableToSelectedPath: true,
      rendered: projection.text,
      loading: 'unverified',
    },
    requested: modelOptions ?? null,
    requestProvenance: 'caller-supplied-not-dispatched',
    observed: {model: 'unknown', reasoningEffort: 'unknown'},
    enforcement: 'unverified',
  };
}
