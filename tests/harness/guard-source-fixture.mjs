// Developer-only source controls. Mutate a copy of the actual Node owner and
// assert that each requested transformation hit; never a shipped override.
import fs from 'node:fs';
const [action, source, target, value] = process.argv.slice(2);
const original = fs.readFileSync(source, 'utf8');
let text = original;
const replace = (from, to) => { if (!text.includes(from)) throw new Error(`mutation anchor missing: ${from}`); text = text.replace(from, to); };
const removeLines = marker => { const lines = text.split('\n'); if (!lines.some(line => line.includes(marker))) throw new Error(`mutation marker missing: ${marker}`); text = lines.filter(line => !line.includes(marker)).join('\n'); };
if (action === 'registry') {
  const lines = original.split('\n'); const anchor = lines.indexOf('export const RULES = [];');
  const definitions = [...original.matchAll(/^export (?:async )?function (r_\w+)\(/gm)].map(match => match[1]);
  const registrations = [...original.matchAll(/^RULES\.push\(\{matcher: '[^']+', run: (\w+)\}\);/gm)].map(match => match[1]);
  const valid = anchor >= 0 && definitions.length > 0 && definitions.every(name => registrations.includes(name)) && registrations.every(name => /^r_/.test(name) && definitions.includes(name)) && registrations.length === new Set(registrations).size && lines.every((line, index) => !line.startsWith('RULES.push(') || index > anchor);
  if (!valid) console.error('registry definitions/registrations/order differ');
  process.exitCode = valid ? 0 : 1;
} else if (action === 'inventory') {
  const match = new RegExp('^export const ' + target + " = '([^']*)';", 'm').exec(original);
  if (!match) throw new Error('inventory missing: ' + target);
  console.log(match[1]);
} else {
  if (action === 'inject') replace('export const RULES = [];', 'export const RULES = [];\n' + fs.readFileSync(value, 'utf8'));
  else if (action === 'remove-rule') removeLines(`run: ${value}}`);
  else if (action === 'no-registry') removeLines('RULES.push(');
  else if (action === 'before-anchor') { removeLines('run: r_remote}'); replace('export const RULES = [];', "RULES.push({matcher: 'Bash', run: r_remote});\nexport const RULES = [];"); }
  else if (action === 'no-prefix') text = text.replaceAll('r_remote', 'no_remote');
  else if (action === 'internal-error') replace('event = normalizeHookEvent(raw, {env});', 'event = normalizeHookEvent(raw, {env});\n    throw new Error("internal-error-fixture");');
  else if (action === 'no-error-conversion') replace('code: 2, stdout:', 'code: 1, stdout:');
  else if (action === 'no-cwd') replace('const target = norm(ctx, value);', "if (!path.isAbsolute(value)) return null;\n  const target = norm(ctx, value);");
  else if (action === 'no-holder') replace('const holder = holdsTrees(ctx, candidate);', 'continue; const holder = holdsTrees(ctx, candidate);');
  else if (action === 'wide-coordinate') replace("executable === 'bd'", 'true');
  else if (action === 'no-backticks') replace("segments(command.replaceAll('`', '\\n'))", 'segments(command)');
  else if (action === 'no-workspace') removeLines('REGISTERED_WORKSPACE');
  else if (action === 'no-home') removeLines('EXPAND_HOME');
  else if (action === 'no-root-assignment') removeLines('ROOT_ASSIGNMENT');
  else if (action === 'regex-root-assignment') replace("command = command.replaceAll('HARNESS_ROOT=' + root + ' ', '')", "{ try { command = command.replace(new RegExp('HARNESS_ROOT=' + root + ' ', 'g'), ''); } catch { command = ''; } }");
  else if (action === 'no-grader-scope') replace('const found = rootOf(ctx, value); if (!found) return;', "const found = rootOf(ctx, value) || {target: value, repo: 'fixture'};");
  else if (action === 'no-grader-pair') removeLines('GRADER_GIT_PAIR');
  else if (action === 'bd-optonly') removeLines('IMPL_OPTIONS_ONLY');
  else if (action === 'redir') replace("' __REDIR__ '", "' '");
  else if (action === 'gh-word') { replace("for (const segment of execSegments('gh', ctx.command))", 'for (const segment of segments(ctx.command))'); replace('if (!first || member(GH_READ_EXEMPT', 'if (member(GH_READ_EXEMPT'); }
  else if (action === 'bd-joined') replace("execSegments(tool, ctx.command).map(segment =>", "[execSegments(tool, ctx.command).join('\\n')].filter(Boolean).map(segment =>");
  else if (action === 'no-log') replace('await guardLog(event ?? {}, rule, env);', '/* observation removed in developer copy */');
  else if (action === 'byte-length') replace('[...command].length >= 120', 'Buffer.byteLength(command) >= 120');
  else if (action === 'no-log-distinction') replace("if (!fs.readFileSync(hook, 'utf8').includes('await guardLog(event ?? {}, rule, env);'))", 'if (false)');
  else throw new Error('unknown mutation: ' + action);
  if (text === original) throw new Error('mutation did not change source');
  fs.writeFileSync(target, text);
}
