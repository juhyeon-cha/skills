import {isReadonlySearch, normalizePath} from './operations.mjs';

// A complete parse of a deliberately small literal grammar. Other commands
// use recognized write-target analysis; this is not a shell interpreter.
export function literalReadEffects(command, cwd, env = process.env) {
  if (typeof command !== 'string' || /[\0\r]/.test(command)) return null;
  const segments = [[]];
  let word = '', active = false, quote = '';
  const finish = () => {
    if (active) segments.at(-1).push({word});
    word = ''; active = false;
  };
  for (let i = 0; i < command.length; i++) {
    const c = command[i];
    if (quote === "'") {
      if (c === "'") quote = ''; else word += c;
      active = true; continue;
    }
    if ('$`\\'.includes(c)) return null;
    if (quote === '"') {
      if (c === '"') quote = ''; else word += c;
      active = true; continue;
    }
    if (c === "'" || c === '"') { quote = c; active = true; continue; }
    if ('<()&{}*?[]~'.includes(c)) return null;
    if (c === '>') {
      // File descriptors and descriptor duplication are outside this grammar.
      if (active && /^\d+$/.test(word)) return null;
      finish();
      segments.at(-1).push({redirect: command[i + 1] === '>' ? '>>' : '>'});
      if (command[i + 1] === '>') i++;
      continue;
    }
    if (';|\n'.includes(c)) {
      finish();
      if (!segments.at(-1).length) return null;
      segments.push([]); continue;
    }
    if (/\s/.test(c)) { finish(); continue; }
    word += c; active = true;
  }
  if (quote) return null;
  finish();
  if (!segments.at(-1).length) segments.pop();
  if (!segments.length) return null;
  const writes = [];
  let dataCommand = false;
  for (const tokens of segments) {
    const words = [];
    for (let i = 0; i < tokens.length; i++) {
      if (!tokens[i].redirect) { words.push(tokens[i].word); continue; }
      const target = tokens[++i]?.word;
      if (!target) return null;
      // /dev/null is the only special device admitted as an output sink.
      if (target !== '/dev/null') writes.push(normalizePath(target, cwd));
    }
    const [name, ...args] = words;
    if (name === 'echo' || name === 'printf') {
      if (name === 'printf' && args[0] === '-v') return null;
      dataCommand = true;
    } else {
      // Re-quote literal argv; the strict existing inventory owns read options.
      const quoted = words.map(value => "'" + value.replaceAll("'", "'\\''") + "'").join(' ');
      if (!isReadonlySearch(quoted, env)) return null;
    }
  }
  // Plain searches retain the existing classification and mutation controls.
  if (!writes.length && !dataCommand) return null;
  return {writes: [...new Set(writes)]};
}
