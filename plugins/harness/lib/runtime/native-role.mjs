import fs from 'node:fs';
import path from 'node:path';
import {roleIdentifier} from './role-contract.mjs';
const required = (value, label) => { if (typeof value !== 'string' || !value.trim()) throw new Error(`${label} missing`); return value; };

// Read top-level statements without treating names inside strings or containers
// as assignments. The runtime validates unrelated TOML values and tables.
function nativeStatements(text) {
  const statements = [];
  const containers = [];
  let statement = '';
  let quote = '';
  let multiline = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quote) {
      statement += c;
      if (quote === '"' && c === '\\') {
        if (++i >= text.length) throw new Error('unfinished native TOML escape');
        statement += text[i];
        continue;
      }
      if (!multiline && /[\r\n]/.test(c)) throw new Error('unfinished native TOML string');
      if (c !== quote) continue;
      if (!multiline) { quote = ''; continue; }
      let n = 1;
      while (text[i + n] === quote) n++;
      if (n < 3) continue;
      if (n > 5) throw new Error('ambiguous native TOML string delimiter');
      statement += quote.repeat(n - 1);
      i += n - 1;
      quote = '';
      multiline = false;
      continue;
    }
    if (c === '#') {
      while (i + 1 < text.length && text[i + 1] !== '\n') i++;
      continue;
    }
    if (c === '"' || c === "'") {
      quote = c;
      multiline = text.slice(i, i + 3) === c.repeat(3);
      statement += multiline ? c.repeat(3) : c;
      if (multiline) i += 2;
      continue;
    }
    if (c === '[' || c === '{') containers.push(c === '[' ? ']' : '}');
    if ((c === ']' || c === '}') && containers.pop() !== c)
      throw new Error('unbalanced native TOML container');
    if (c === '\n' && !containers.length) {
      if (statement.trim()) statements.push(statement.trim());
      statement = '';
    } else statement += c;
  }
  if (quote || containers.length) throw new Error('unfinished native TOML value');
  if (statement.trim()) statements.push(statement.trim());
  return statements;
}

  const basic = '"(?:[^"\\\\\\x00-\\x1f]|\\\\(?:["\\\\btnfr]|u[0-9a-fA-F]{4}|U[0-9a-fA-F]{8}))*"';
  const literal = "'[^'\\x00-\\x1f]*'";
  const string = `(?:${basic}|${literal})`;
  const keyPart = `(?:[A-Za-z0-9_-]+|${string})`;
  const assignment = new RegExp(`^(${keyPart})((?:\\s*\\.\\s*${keyPart})*)\\s*=\\s*([\\s\\S]*)$`);
  const nameValue = new RegExp(`^${string}$`);
  const decode = (value) => {
    if (!value.startsWith('"')) return value.startsWith("'") ? value.slice(1, -1) : value;
    // Consume each escape atomically so a literal backslash followed by U is
    // not confused with a TOML Unicode escape. JSON handles the shared escapes.
    const json = value.replace(/\\(?:["\\btnfr]|u[0-9a-fA-F]{4}|U[0-9a-fA-F]{8})/g, (escape) => {
      if (!escape.startsWith('\\U')) return escape;
      const code = Number.parseInt(escape.slice(2), 16);
      if (code >= 0xd800 && code <= 0xdfff) throw new Error('invalid TOML Unicode scalar');
      return JSON.stringify(String.fromCodePoint(code)).slice(1, -1);
    });
    return JSON.parse(json);
  };

export function nativeAgentName(text) {
  let name;
  for (const line of nativeStatements(text)) {
    if (line.startsWith('[')) break;
    const match = assignment.exec(line);
    if (!match) throw new Error('unreadable top-level native TOML key');
    if (match[2]) continue; // Dotted paths are nested fields, not the scalar name.
    const key = decode(match[1]);
    if (key !== 'name') continue;
    if (name !== undefined) throw new Error('duplicate native agent name');
    if (!nameValue.test(match[3])) throw new Error('native agent name requires a single-line string');
    name = decode(match[3]);
  }
  return required(name, 'native agent name');
}

export function assembleNativeRole(runtime, definition, root, installedRoot = root) {
  const identifier = roleIdentifier(runtime, definition.role);
  const source = path.join(root, 'native', runtime, `${definition.role}.${runtime === 'codex' ? 'toml' : 'md'}`);
  const template = fs.readFileSync(source, 'utf8');
  const marker = runtime === 'codex' ? '# HARNESS_ROLE_INSTRUCTIONS' : '<!-- HARNESS_ROLE_INSTRUCTIONS -->';
  if (template.split(marker).length !== 2) throw new Error('native instruction slot missing/duplicate');
  const body = runtime === 'claude' ? definition.body : definition.body.replaceAll('${CLAUDE_PLUGIN_ROOT}', () => installedRoot);
  if (runtime === 'codex') {
    if (!template.split('\n').includes(marker)) throw new Error('native instruction slot must occupy its own line');
    const probe = template.replace(marker, () => 'harness_instruction_slot = true');
    const statements = nativeStatements(probe);
    const slot = statements.indexOf('harness_instruction_slot = true');
    if (slot < 0 || statements.slice(0, slot).some(line => line.startsWith('[')))
      throw new Error('native instruction slot must be top-level');
    if (statements.some(line => { const match = assignment.exec(line); return match && decode(match[1]) === 'developer_instructions'; }))
      throw new Error('native developer_instructions already assigned');
    if (nativeAgentName(probe) !== identifier) throw new Error('native role name mismatch');
    return template.replace(marker, () => `developer_instructions = ${JSON.stringify(body)}`);
  }
  const frontmatter = /^---\r?\n([\s\S]*?)\r?\n---\r?\n/.exec(template);
  if (!frontmatter || frontmatter[0].includes(marker) || !template.slice(frontmatter[0].length).split('\n').includes(marker))
    throw new Error('native instruction slot must follow frontmatter');
  const names = [...frontmatter[1].matchAll(/^name: (.+)$/gm)];
  if (names.length !== 1 || names[0][1] !== (runtime === 'claude' ? definition.role : identifier)) throw new Error('native role name mismatch');
  if (!/^description: .+/m.test(frontmatter[1])) throw new Error('native description missing');
  return template.replace(marker, () => body);
}
