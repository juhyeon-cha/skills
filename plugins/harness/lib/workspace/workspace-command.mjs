import fs from 'node:fs';
import path from 'node:path';
import { powershellOperations } from '../guard/powershell-operations.mjs';

export function workspaceArguments(args) {
  const [action, cwd, ...rest] = args;
  if (
    !['create', 'inspect', 'enter', 'prepare', 'ready', 'cleanup'].includes(action) ||
    !cwd ||
    !path.isAbsolute(cwd)
  )
    throw new Error('workspace action and absolute repository/workspace path required');
  if (['inspect', 'enter', 'prepare', 'ready'].includes(action)) {
    if (rest.length) throw new Error('unexpected workspace arguments');
    return { action, cwd };
  }
  const story = rest.shift();
  if (!story || story.startsWith('-')) throw new Error('story ID required');
  let destination,
    force = false;
  if (
    action === 'create' &&
    rest[0] === '--destination' &&
    rest.length === 2 &&
    path.isAbsolute(rest[1])
  )
    destination = rest.splice(0)[1];
  if (action === 'cleanup' && rest.length === 1 && rest[0] === '--force') {
    force = true;
    rest.pop();
  }
  if (rest.length) throw new Error('unexpected workspace arguments');
  return { action, cwd, story, destination, force };
}

// Recognize a single literal invocation, never evaluate shell text. The same
// argument contract is used by the CLI before any mutation.
export function literalShellWords(command, { dialect = 'posix', cwd = process.cwd() } = {}) {
  if (dialect === 'powershell') {
    try {
      const parsed = powershellOperations(command, cwd);
      if (parsed.dynamic || parsed.redirect || parsed.commands.length !== 1) return null;
      return parsed.commands[0];
    } catch {
      return null;
    }
  }
  const words = [];
  let word = '',
    quote = '',
    active = false;
  for (const c of command) {
    if (quote === "'") {
      if (c === "'") quote = '';
      else word += c;
      active = true;
      continue;
    }
    if ('$`\\\0\r\n'.includes(c)) return null;
    if (quote === '"') {
      if (c === '"') quote = '';
      else word += c;
      active = true;
      continue;
    }
    if (c === "'" || c === '"') {
      quote = c;
      active = true;
      continue;
    }
    if (';|&<>(){}*?[]~'.includes(c)) return null;
    if (/\s/.test(c)) {
      if (active) words.push(word);
      word = '';
      active = false;
      continue;
    }
    word += c;
    active = true;
  }
  if (quote) return null;
  if (active) words.push(word);
  return words;
}

export function workspaceShellCommand(command, script, { dialect = 'posix' } = {}) {
  const words = literalShellWords(command, { dialect, cwd: path.dirname(script) });
  if (
    !words ||
    !['node', ...(dialect === 'powershell' ? ['node.exe'] : []), process.execPath].includes(
      words[0],
    ) ||
    !words[1] ||
    !path.isAbsolute(words[1])
  )
    return null;
  try {
    if (fs.realpathSync(words[1]) !== fs.realpathSync(script)) return null;
    return workspaceArguments(words.slice(2));
  } catch {
    return null;
  }
}
