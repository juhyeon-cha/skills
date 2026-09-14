import path from 'node:path';

export function normalizePath(value, cwd) {
  if (typeof value !== 'string' || !value || /[\0\r\n]/.test(value))
    throw new Error('invalid file path');
  const windows = /^[A-Za-z]:[\\/]|^\\\\/.test(value) || /^[A-Za-z]:[\\/]|^\\\\/.test(cwd);
  if (/^[A-Za-z]:(?![\\/])/.test(value)) throw new Error('drive-relative path is ambiguous');
  return (windows ? path.win32 : path.posix).resolve(cwd, value);
}

export function patchOperations(command, cwd) {
  if (typeof command !== 'string' || command.includes('\0'))
    throw new Error('invalid patch command');
  const lines = command.replaceAll('\r\n', '\n').split('\n');
  if (lines.at(-1) === '') lines.pop();
  if (lines.shift() !== '*** Begin Patch' || lines.pop() !== '*** End Patch')
    throw new Error('unknown patch envelope');
  const operations = [];
  for (let i = 0; i < lines.length; ) {
    const match = /^\*\*\* (Add|Update|Delete) File: (.+)$/.exec(lines[i++]);
    if (!match) throw new Error('unknown patch file header');
    const source = normalizePath(match[2], cwd);
    const kind = { Add: 'create', Update: 'update', Delete: 'delete' }[match[1]];
    let destination;
    if (lines[i]?.startsWith('*** Move to: ')) {
      if (kind !== 'update') throw new Error('move requires update');
      destination = normalizePath(lines[i++].slice(13), cwd);
    }
    let body = 0;
    while (i < lines.length && !/^\*\*\* (Add|Update|Delete) File: /.test(lines[i])) {
      const line = lines[i++];
      if (
        kind === 'delete' ||
        (kind === 'create'
          ? !line.startsWith('+')
          : !/^(?:[ +\-]|@@(?: |$)|\*\*\* End of File$)/.test(line))
      )
        throw new Error('unknown patch body');
      body++;
    }
    if (kind === 'update' && body === 0 && !destination) throw new Error('empty patch operation');
    operations.push(destination ? { kind: 'move', source, destination } : { kind, path: source });
  }
  if (!operations.length) throw new Error('empty patch');
  return operations;
}

// Inspect literal output redirects and standard file-command operands only.
// Script bodies, option values and arbitrary path arguments are not write evidence.
// Dynamic shell effects belong to the host permission boundary.
export function shellWriteOperations(command, cwd) {
  const segments = [[]], redirects = [];
  let word = '', quote = '', active = false, dynamic = false, output = false;
  const finish = () => {
    if (active) {
      const token = dynamic ? null : word;
      if (output) redirects.push(token);
      else segments.at(-1).push(token);
      output = false;
    }
    word = ''; active = false; dynamic = false;
  };
  for (let i = 0; i < command.length; i++) {
    const c = command[i];
    if (quote === "'") {
      if (c === "'") quote = '';
      else word += c;
      active = true;
      continue;
    }
    if (c === '\\') {
      word += command[++i] ?? ''; active = true; continue;
    }
    if (c === '$' || c === '`') dynamic = true;
    if (quote === '"') {
      if (c === '"') quote = '';
      else word += c;
      active = true;
      continue;
    }
    if (c === '"' || c === "'") { quote = c; active = true; continue; }
    if (c === '#' && !active) {
      while (i < command.length && command[i] !== '\n') i++;
      finish(); segments.push([]); continue;
    }
    // A heredoc body is opaque shell data, not a sequence of tool operations.
    if (c === '<' && command[i + 1] === '<') break;
    if (c === '>') {
      if (/^\d+$/.test(word)) { word = ''; active = false; }
      finish();
      if (command[i + 1] === '>') i++;
      if (command[i + 1] === '&') {
        i++;
        while (/[\d-]/.test(command[i + 1] ?? '')) i++;
      } else output = true;
      continue;
    }
    if (';|&\n()'.includes(c)) { finish(); segments.push([]); continue; }
    if (/\s/.test(c)) { finish(); continue; }
    if ('*?[]{}'.includes(c) || (c === '~' && !active)) dynamic = true;
    word += c; active = true;
  }
  if (!quote) finish();
  const targets = redirects.filter(value => value && value !== '/dev/null');
  const switches = {
    rm: 'dfirRv', rmdir: 'pv', unlink: '', touch: 'acfh', mkdir: 'pv',
    tee: 'ai', cp: 'aDfHLPRfilnprsvxT', mv: 'finvT',
  };
  const values = {
    touch: ['-r', '--reference', '-d', '--date', '-t'],
    mkdir: ['-m', '--mode'],
    cp: ['-S', '--suffix'], mv: ['-S', '--suffix'],
  };
  for (const [executable, ...args] of segments) {
    const name = executable?.split('/').at(-1);
    if (!Object.hasOwn(switches, name)) continue;
    // Expansion can supply options as well as filenames. Preserve redirects,
    // but do not infer operand roles from an incomplete argv.
    if (args.includes(null)) continue;
    const operands = [];
    let literal = false, opaque = false, destination;
    for (let i = 0; i < args.length; i++) {
      const arg = args[i];
      if (arg === '--') { literal = true; continue; }
      if (!literal && arg.startsWith('-') && arg !== '-') {
        const option = arg.split('=')[0];
        const targetOption = ['cp', 'mv'].includes(name) && ['-t', '--target-directory'].includes(option);
        if (targetOption || (values[name] ?? []).includes(option)) {
          const value = arg.includes('=') ? arg.slice(arg.indexOf('=') + 1) : args[++i];
          if (value === undefined || value === '') { opaque = true; break; }
          if (targetOption) destination = value;
          continue;
        }
        if (arg === '--help' || arg === '--version') { opaque = true; break; }
        if (/^-[^-]+$/.test(arg) && [...arg.slice(1)].every(flag => switches[name].includes(flag))) continue;
        // Unknown options may consume the next argument. Do not guess its role.
        opaque = true; break;
      }
      operands.push(arg);
    }
    if (opaque) continue;
    // A copy reads its sources; moving also modifies them.
    targets.push(...(name === 'cp' ? [destination ?? operands.at(-1)] : [...operands, destination]).filter(Boolean));
  }
  return [...new Set(targets)].map(value => ({kind: 'update', path: normalizePath(value, cwd)}));
}

export function gitReadonly(input) {
  const args = [...input];
  while (args[0] === '-C' || args[0] === '--no-pager') {
    if (args.shift() === '-C' && !args.shift()) return false;
  }
  if (!['diff', 'show', 'log', 'status', 'ls-files', 'rev-parse'].includes(args.shift()))
    return false;
  // Git accepts abbreviated long options. Output files and external
  // diff/textconv commands are effects, even on a read subcommand.
  return !args.some((arg) => {
    const option = arg.split('=')[0];
    return option.startsWith('--') && option.length > 2 &&
      ['--output', '--ext-diff', '--textconv'].some((effect) => effect.startsWith(option));
  });
}

// A deliberately narrow POSIX read-only subset, not a shell interpreter.
// Dynamic expansion, redirects and execution-capable options stay conservative.
export function ripgrepReadonly(args, command, env = process.env) {
  // Preprocessors, hostname discovery and decompression can run external programs.
  // Config can supply these flags too. Only a leading --no-config is an
  // unambiguous option: after -e the same token could instead be a pattern.
  if ((env.RIPGREP_CONFIG_PATH || command.includes('RIPGREP_CONFIG_PATH')) &&
      args[0] !== '--no-config') return false;
  return !args.some(arg => /^--(?:pre|pre-glob|hostname-bin|search-zip)(?:=|$)|^-[^-]*z/.test(arg));
}

export function isReadonlySearch(command, env = process.env) {
  if (typeof command !== 'string' || /[\0\r]/.test(command)) return false;
  const segments = [[]];
  let word = '';
  let quote = '';
  let active = false;
  const finish = () => {
    if (active) segments.at(-1).push(word);
    word = '';
    active = false;
  };
  for (let i = 0; i < command.length; i++) {
    const c = command[i];
    if (quote === "'") {
      if (c === "'") quote = '';
      else word += c;
      active = true;
      continue;
    }
    if (c === '$' || c === '`' || c === '\\') return false;
    if (quote === '"') {
      if (c === '"') quote = '';
      else word += c;
      active = true;
      continue;
    }
    if (c === '"' || c === "'") {
      quote = c;
      active = true;
      continue;
    }
    // Unquoted brace, pathname and tilde expansions can manufacture options.
    // Quoted literals have already been consumed above and remain read-only.
    if ('{}*?[]'.includes(c) || (c === '~' && !active)) return false;
    if (c === '>') {
      const discard = /^>\s*\/dev\/null(?=[\s;|]|$)/.exec(command.slice(i));
      if (!discard) return false;
      if (active && /^[12]$/.test(word)) {
        word = '';
        active = false;
      } else finish();
      i += discard[0].length - 1;
      continue;
    }
    if (c === '<' || c === '(' || c === ')' || c === '&') return false;
    if (c === ';' || c === '|' || c === '\n') {
      finish();
      if (!segments.at(-1).length) return false;
      segments.push([]);
      continue;
    }
    if (/\s/.test(c)) {
      finish();
      continue;
    }
    word += c;
    active = true;
  }
  if (quote) return false;
  finish();
  if (!segments.at(-1).length) return false;
  return segments.every(([name, ...args]) => {
    if (name === 'git') return gitReadonly(args);
    if (!['rg', 'grep', 'cat', 'head', 'tail', 'wc', 'pwd', 'ls', 'printenv'].includes(name)) return false;
    if (name === 'rg' && !ripgrepReadonly(args, command, env)) return false;
    return true;
  });
}
