import {normalizePath} from './operations.mjs';

// A bounded lexer, not an interpreter. Literal quotes/backslashes are retained
// as data; expansion, script blocks and dynamic calls never receive read status.
export const PS_READ_COMMANDS = 'get-content gc cat type get-childitem gci ls dir get-item gi get-itemproperty get-location gl pwd test-path resolve-path select-string sls write-output echo write-host out-host measure-object compare-object select-object format-list format-table';
export function powershellReadonly([name, ...args]) {
  name = name.toLowerCase();
  if (PS_READ_COMMANDS.split(' ').includes(name)) return true;
  if (['rg', 'rg.exe', 'grep', 'head', 'tail', 'wc'].includes(name)) return !args.some(arg => /^--(?:pre|pre-glob|hostname-bin|search-zip)(?:=|$)|^-[^-]*z/.test(arg));
  return false;
}
export function powershellOperations(command, cwd) {
  const segments = [[]], redirects = []; let word = '', quote = '', active = false, dynamic = false, redirect = false, redirectNext = false;
  const finish = () => { if (active) { segments.at(-1).push(word); if (redirectNext) { redirects.push(word); redirectNext = false; } } word = ''; active = false; };
  for (let i = 0; i < command.length; i++) {
    const c = command[i];
    if (quote === "'") {
      if (c === "'" && command[i + 1] === "'") { word += "'"; i++; }
      else if (c === "'") quote = '';
      else word += c;
      active = true; continue;
    }
    if (c === '`') { dynamic = true; word += command[++i] ?? ''; active = true; continue; }
    if (c === '$') dynamic = true;
    if (quote === '"') { if (c === '"') quote = ''; else word += c; active = true; continue; }
    if (c === "'" || c === '"') { quote = c; active = true; continue; }
    if ('{}()'.includes(c)) dynamic = true;
    if (c === '>' || c === '<') { redirect = true; finish(); redirectNext = true; continue; }
    if (';|\n'.includes(c)) { finish(); if (segments.at(-1).length) segments.push([]); continue; }
    if (c === '&') { finish(); if (segments.at(-1).length) { segments.push([]); dynamic = true; } continue; }
    if (/\s/.test(c)) { finish(); continue; }
    word += c; active = true;
  }
  if (quote) throw new Error('unterminated PowerShell string');
  finish();
  const commands = segments.filter(segment => segment.length);
  const readonly = commands.length > 0 && !dynamic && !redirect && commands.every(powershellReadonly);
  const paths = readonly ? [] : commands.flatMap(words => powershellReadonly(words) ? [] : powershellTargets(words, cwd));
  paths.push(...redirects.filter(value => value !== '$null').map(value => normalizePath(value, cwd)));
  return {commands, readonly, dynamic, redirect, paths};
}

// Literal file cmdlets have positional path operands too. Unknown commands keep
// explicit path candidates; their implementation is not treated as read-only.
export function powershellTargets([name, ...args], cwd) {
  name = name.toLowerCase();
  const positionalCount = /^(?:move-item|mi|move|copy-item|cpi|copy|cp|rename-item|rni|ren)$/.test(name) ? 2
    : /^(?:set-content|sc|add-content|ac|out-file|remove-item|ri|rm|del|erase|new-item|ni|mkdir|md|rmdir|rd|clear-content|clc)$/.test(name) ? 1 : 0;
  const targets = [], explicit = /^(?:[A-Za-z]:[\\/]|\\\\|\/|\.\.?[\\/])/;
  let position = 0, operand = '';
  for (const value of args) {
    if (value.startsWith('-')) { operand = /^-(?:force|recurse|whatif|confirm|append|noclobber|nonewline|passthru|container)$/i.test(value) ? '' : value.toLowerCase(); continue; }
    if (operand) {
      if (['-path', '-literalpath', '-destination', '-newname', '-filepath'].includes(operand)) targets.push(value);
      operand = ''; continue;
    }
    if (position++ < positionalCount || explicit.test(value)) targets.push(value);
  }
  return targets.map(value => normalizePath(value, cwd));
}
