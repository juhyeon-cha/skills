import fs from 'node:fs/promises';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
export const commands = ['init','create','show','list','ready','children','note','close','update','dep','label','wire-worktree','has-ui','sync-check','rails','sprints','sprint-add','help'];
export const beadsCommands = ['delete','edit','tag','search','supersede','remember','notes','counts','batch','export','import','bootstrap','root','sql','dolt','where','blocked','query'];
export const csv = value => value ? value.split(',') : [];
export const unique = values => [...new Set(values)].sort();
export const json = value => JSON.stringify(value, null, 2) + '\n';
export const fail = message => { throw new Error(message); };
export function parse(args, values = {}, flags = {}, permissive = false) {
  const result = {positional: []};
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (Object.hasOwn(values, arg)) {
      if (++i >= args.length) fail(`${arg}: 값이 필요하다`);
      const key = values[arg]; result[key] = key === 'labels' && result[key] ? result[key] + ',' + args[i] : args[i];
    } else if (Object.hasOwn(flags, arg)) result[flags[arg]] = true;
    else if (arg.startsWith('-')) { if(!permissive) fail(`모르는 인자 '${arg}'`); }
    else result.positional.push(arg);
  }
  return result;
}
export const writeValues = {'-t':'type','--type':'type','-l':'labels','--label':'labels','--labels':'labels','--parent':'parent','--acceptance':'acceptance','--body-file':'bodyFile','-d':'description','--description':'description','-p':'priority','--priority':'priority','-s':'status','--status':'status','--actor':'actor','-a':'assignee','--assignee':'assignee'};
export const writeFlags = {'--silent':'silent','--stdin':'stdin','--json':'json','--claim':'claim'};
export const createOptions = args => parse(args,Object.fromEntries(Object.entries(writeValues).filter(([,key])=>!['status','actor','assignee'].includes(key))),{'--silent':'silent','--stdin':'stdin','--json':'json'});
export const updateOptions = args => parse(args,Object.fromEntries(Object.entries(writeValues).filter(([,key])=>!['labels','priority'].includes(key))),{'--claim':'claim','--json':'json'});
export const listValues = {'-l':'labels','--label':'labels','--labels':'labels','--label-pattern':'pattern','-s':'status','--status':'status','-t':'type','--type':'type','--parent':'parent','-n':'limit','--limit':'limit'};
export function listOptions(args) {
  const options = parse(args, listValues, {'--all':'all','--json':'json'});
  if (options.positional.length) fail(`list: 모르는 인자 '${options.positional[0]}'`);
  const limit = Number(options.limit ?? 50);
  if (!Number.isSafeInteger(limit) || limit < 0) fail('limit: 0 이상의 정수가 필요하다');
  return {...options, limit};
}
export function filterRows(rows, options) {
  const need = csv(options.labels), statuses = csv(options.status);
  const pattern = options.pattern ? new RegExp('^' + options.pattern.replace(/[.*+?^${}()|[\]\\]/g, c => c === '*' ? '.*' : '\\' + c) + '$') : null;
  const filtered = rows.filter(row => (options.all || options.status || row.status !== 'closed') && (!statuses.length || statuses.includes(row.status)) && (!options.type || row.issue_type === options.type) && (!options.parent || row.parent === options.parent) && need.every(label => row.labels.includes(label)) && (!pattern || row.labels.some(label => pattern.test(label))));
  return options.limit > 0 ? filtered.slice(0, options.limit) : filtered;
}
export const rowsText = rows => rows.map(row => `${row.id}\t${row.status}\t${row.issue_type}\t${row.title}\n`).join('');
export const showText = row => `${row.id} [${row.issue_type} · ${row.status}] ${row.title}\nlabels: ${row.labels.join(', ')}\nparent: ${row.parent ?? '-'}  assignee: ${row.assignee ?? '-'}\n\n${row.description}\n\nACCEPTANCE\n${row.acceptance_criteria}\n\nNOTES\n${row.notes ?? ''}\n`;
export const bodyFile = async (file, ctx) => (file === '-' ? ctx.input.toString() : await fs.readFile(path.resolve(ctx.cwd, file), 'utf8')).replace(/\n+$/, '');
// File values are transported as argv data, never evaluated by a shell.
export async function fileArguments(argv, ctx) {
  const [command, ...args] = argv;
  if (!['create', 'update', 'init'].includes(command)) return argv;
  const output = [], files = {}, inline = new Set(), positional = [];
  const valued = new Set([...Object.keys(writeValues), '--title', '--parent-page', '--prefix']);
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--acceptance-file' || arg === '--title-file') {
      if (Object.hasOwn(files, arg) || i + 1 >= args.length) fail(`${arg}: 중복 또는 값 누락`);
      files[arg] = args[++i];
    } else if (valued.has(arg)) {
      inline.add(arg); output.push(arg);
      if (i + 1 >= args.length) fail(`${arg}: 값이 필요하다`);
      output.push(args[++i]);
    } else { output.push(arg); if (!arg.startsWith('-')) positional.push(arg); }
  }
  if (Object.hasOwn(files, '--acceptance-file')) {
    if (command === 'init' || inline.has('--acceptance')) fail('--acceptance-file: 지원하지 않는 명령 또는 --acceptance 중복');
    output.push('--acceptance', await bodyFile(files['--acceptance-file'], ctx));
  }
  if (Object.hasOwn(files, '--title-file')) {
    if (command === 'update' || inline.has('--title') || (command === 'create' && positional.length)) fail('--title-file: 지원하지 않는 명령 또는 제목 중복');
    const title = await bodyFile(files['--title-file'], ctx);
    if (!title || title.startsWith('-') || title.includes('\0')) fail('--title-file: 제목이 비었거나 인자로 표현할 수 없다');
    if (command === 'create') output.unshift(title); else output.push('--title', title);
  }
  return [command, ...output];
}
export async function description(options, ctx) { return options.bodyFile !== undefined ? bodyFile(options.bodyFile, ctx) : options.stdin ? ctx.input.toString().replace(/\n+$/, '') : options.description ?? ''; }
export async function noteBody(args, ctx) {
  if (!args.length) fail('note: 본문이 필요하다');
  return args[0] === '--file' ? bodyFile(args[1], ctx) : args[0] === '--stdin' ? ctx.input.toString().replace(/\n+$/, '') : args[0];
}
export async function dependencyPairs(args, ctx) {
  if (args.shift() !== 'add') fail("dep: 'add' 만 지원한다");
  if (args[0] === '--file') return (await bodyFile(args[1], ctx)).split(/\r?\n/).filter(x => x.trim()).map(line => JSON.parse(line)).filter(Boolean).map(item => [item.from ?? item.issue_id, item.to ?? item.depends_on_id]);
  if (args.length < 2) fail('dep add: <id> <의존 대상 id> 또는 --file -');
  return [[args[0], args[1]]];
}
export function railsFrom(rows, ctx) {
  const groups = new Map();
  const blank = rows.filter(row => row.assignee == null).map(row => row.id);
  if (blank.length) ctx.err(`rails: assignee (Notion Assignee) 가 없는 epic — ${blank.join(' ')}\n`);
  for (const row of rows.filter(row => row.assignee != null)) for (const label of row.labels.filter(label => label.startsWith('rail:'))) {
    const id = label.slice(5); if (!groups.has(id)) groups.set(id, new Set()); groups.get(id).add(row.assignee);
  }
  for (const [id, owners] of groups) if (owners.size > 1) fail(`rails: 한 레일의 epic 들이 서로 다른 assignee 를 가리킨다 — ${id}=${[...owners].sort().join('/')}`);
  return [...groups].sort(([a],[b]) => a.localeCompare(b)).map(([id, owners]) => ({id, owner: [...owners][0]}));
}
export async function replaceJSON(file, value) {
  const temporary = path.join(path.dirname(file), '.' + path.basename(file) + '-' + randomUUID());
  try { await fs.writeFile(temporary, json(value), {flag:'wx'}); await fs.rename(temporary, file); }
  finally { await fs.rm(temporary, {force:true}); }
}
