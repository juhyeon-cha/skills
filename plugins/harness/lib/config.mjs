import fs from 'node:fs/promises';
import path from 'node:path';

const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const string = value => typeof value === 'string' && value.length > 0 && !value.includes('\0');
const invalid = message => { throw new Error(`CONFIG_INVALID: ${message}`); };

export function validateCommand(command) {
  if (string(command)) return command; // Legacy strings retain Bash semantics.
  if (!object(command) || Object.keys(command).some(key => key !== 'argv') ||
      !Array.isArray(command.argv) || !string(command.argv[0]) ||
      !command.argv.every(arg => typeof arg === 'string' && !arg.includes('\0'))) {
    invalid('command must be a nonempty Bash string or {argv: [executable, ...strings]}');
  }
  return command;
}

export function validateConfig(config) {
  if (!object(config)) invalid('root must be an object');
  if ('schema_version' in config && config.schema_version !== 1) invalid('unsupported schema_version (supported: 1)');
  if (!object(config.ledger) || !['github', 'beads', 'notion'].includes(config.ledger.backend)) invalid('ledger.backend must be github, beads or notion; no fallback');
  for (const key of ['owner', 'database_id']) {
    if (key in config.ledger && !string(config.ledger[key])) invalid(`ledger.${key} must be a nonempty string`);
  }
  if ('project' in config.ledger && (!Number.isSafeInteger(config.ledger.project) || config.ledger.project < 1)) invalid('ledger.project must be a positive integer');
  if ('default_branch' in config && !string(config.default_branch)) invalid('default_branch must be a nonempty string');
  if ('check' in config) validateCommand(config.check);
  if ('bootstrap' in config && config.bootstrap !== null && config.bootstrap !== '') validateCommand(config.bootstrap);
  // Preserve repository-owned extensions without projecting a second config.
  return config;
}

export async function loadConfig(repoRoot) {
  const file = path.resolve(repoRoot, '.harness.json');
  const config = validateConfig(JSON.parse((await fs.readFile(file, 'utf8')).replace(/^\uFEFF/, '')));
  return {file, config};
}

export function configCommand(config, field) {
  validateConfig(config);
  if (!['check', 'bootstrap'].includes(field)) invalid('command field must be check or bootstrap');
  const command = config[field];
  if (field === 'bootstrap' && (command === undefined || command === null || command === '')) return null;
  return validateCommand(command);
}
