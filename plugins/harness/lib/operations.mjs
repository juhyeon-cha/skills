import path from 'node:path';

export function normalizePath(value, cwd) {
  if (typeof value !== 'string' || !value || /[\0\r\n]/.test(value)) throw new Error('invalid file path');
  const windows = /^[A-Za-z]:[\\/]|^\\\\/.test(value) || /^[A-Za-z]:[\\/]|^\\\\/.test(cwd);
  if (/^[A-Za-z]:(?![\\/])/.test(value)) throw new Error('drive-relative path is ambiguous');
  return (windows ? path.win32 : path.posix).resolve(cwd, value);
}

export function patchOperations(command, cwd) {
  if (typeof command !== 'string' || command.includes('\0')) throw new Error('invalid patch command');
  const lines = command.replaceAll('\r\n', '\n').split('\n');
  if (lines.at(-1) === '') lines.pop();
  if (lines.shift() !== '*** Begin Patch' || lines.pop() !== '*** End Patch') throw new Error('unknown patch envelope');
  const operations = [];
  for (let i = 0; i < lines.length;) {
    const match = /^\*\*\* (Add|Update|Delete) File: (.+)$/.exec(lines[i++]);
    if (!match) throw new Error('unknown patch file header');
    const source = normalizePath(match[2], cwd);
    const kind = {Add: 'create', Update: 'update', Delete: 'delete'}[match[1]];
    let destination;
    if (lines[i]?.startsWith('*** Move to: ')) {
      if (kind !== 'update') throw new Error('move requires update');
      destination = normalizePath(lines[i++].slice(13), cwd);
    }
    let body = 0;
    while (i < lines.length && !/^\*\*\* (Add|Update|Delete) File: /.test(lines[i])) {
      const line = lines[i++];
      if (kind === 'delete' || (kind === 'create' ? !line.startsWith('+') : !/^(?:[ +\-]|@@(?: |$)|\*\*\* End of File$)/.test(line))) throw new Error('unknown patch body');
      body++;
    }
    if (kind === 'update' && body === 0 && !destination) throw new Error('empty patch operation');
    operations.push(destination ? {kind: 'move', source, destination} : {kind, path: source});
  }
  if (!operations.length) throw new Error('empty patch');
  return operations;
}

// Preserve quoted absolute path operands for the conservative legacy shell
// policy, whose whitespace tokenization cannot preserve spaces in filenames.
// These are candidates, not a claim that arbitrary shell effects were parsed.
export function quotedPathCandidates(command, cwd) {
  return [...command.matchAll(/'([^']*)'|"([^"]*)"/g)].map(match => match[1] ?? match[2])
    .filter(value => /\s/.test(value) && /^(?:\/|[A-Za-z]:[\\/]|\\\\)/.test(value))
    .map(value => ({kind: 'update', path: normalizePath(value, cwd)}));
}

// A deliberately narrow POSIX read-only subset, not a shell interpreter.
// Dynamic expansion, redirects and execution-capable options stay conservative.
export function isReadonlySearch(command) {
  if (typeof command !== 'string' || /[\0\r]/.test(command)) return false;
  const segments = [[]]; let word = ''; let quote = ''; let active = false;
  const finish = () => { if (active) segments.at(-1).push(word); word = ''; active = false; };
  for (let i = 0; i < command.length; i++) {
    const c = command[i];
    if (quote === "'") { if (c === "'") quote = ''; else word += c; active = true; continue; }
    if (c === '$' || c === '`' || c === '\\') return false;
    if (quote === '"') { if (c === '"') quote = ''; else word += c; active = true; continue; }
    if (c === '"' || c === "'") { quote = c; active = true; continue; }
    // Unquoted brace, pathname and tilde expansions can manufacture options.
    // Quoted literals have already been consumed above and remain read-only.
    if ('{}*?[]~'.includes(c)) return false;
    if (c === '>' || c === '<' || c === '(' || c === ')' || c === '&') return false;
    if (c === ';' || c === '|' || c === '\n') { finish(); if (!segments.at(-1).length) return false; segments.push([]); continue; }
    if (/\s/.test(c)) { finish(); continue; }
    word += c; active = true;
  }
  if (quote) return false;
  finish();
  if (!segments.at(-1).length) return false;
  return segments.every(([name, ...args]) => {
    if (!['rg', 'grep', 'cat', 'head', 'tail', 'wc', 'pwd'].includes(name)) return false;
    if (name === 'rg' && args.some(arg => /^--(?:pre|pre-glob|hostname-bin|search-zip)(?:=|$)|^-[^-]*z/.test(arg))) return false;
    return true;
  });
}
