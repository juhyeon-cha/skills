// Read-only consumer boundary. Fixture transports are ordinary library arguments,
// never environment-selected executables or alternate production ledger files.
import {executeLedger, ledgerRoot} from './ledger.mjs';
import {fileURLToPath} from 'node:url';
import {realpathSync} from 'node:fs';

export async function consumerContext(options = {}) {
  const cwd = options.cwd ?? process.cwd(), env = options.env ?? process.env;
  const root = await ledgerRoot(cwd, options.root ?? env.HARNESS_ROOT);
  const ledger = options.ledger ?? (argv => executeLedger(argv, {root, cwd, env}));
  const text = async argv => {
    const result = await ledger(argv);
    if (result.code !== 0) throw new Error(`ledger ${argv[0]} 실패: ${result.stderr || result.code}`);
    return result.stdout;
  };
  const array = async argv => {
    let value;
    try { value = JSON.parse(await text(argv)); } catch (error) { throw new Error(`ledger ${argv[0]} JSON 미가용: ${error.message}`); }
    if (!Array.isArray(value)) throw new Error(`ledger ${argv[0]}: JSON 배열이 필요하다`);
    return value;
  };
  return {root, cwd, env, text, array, ledger};
}

export function ledgerIndex(rows) {
  if (!Array.isArray(rows)) throw new Error('원장 JSON 배열이 필요하다');
  const byId = new Map();
  for (const row of rows) {
    if (!row || ['id', 'issue_type', 'status'].some(key => typeof row[key] !== 'string' || !row[key])) throw new Error('원장 JSON 에 id/issue_type/status 가 없는 이슈가 있다');
    if (byId.has(row.id)) throw new Error(`원장 id 중복: ${row.id}`);
    if (row.labels != null && (!Array.isArray(row.labels) || row.labels.some(label => typeof label !== 'string'))) throw new Error(`원장 labels 형식: ${row.id}`);
    for (const key of ['notes', 'acceptance_criteria']) if (row[key] != null && typeof row[key] !== 'string') throw new Error(`원장 ${key} 형식: ${row.id}`);
    byId.set(row.id, row);
  }
  for (const row of rows) if (row.parent != null && !byId.has(row.parent)) throw new Error(`parent 가 원장에서 해소되지 않는 이슈: ${row.id}`);
  // Missing parent is a legitimate root. A renamed schema key cannot be
  // distinguished from roots using this snapshot alone; zero hierarchy is shown.
  for (const row of rows) {
    const seen = new Set();
    for (let current = row; current; current = byId.get(current.parent)) {
      if (seen.has(current.id)) throw new Error(`parent 순환: ${row.id}`);
      seen.add(current.id);
    }
  }
  return byId;
}
export function ancestors(row, byId, limit = Infinity) {
  const result = [];
  for (let current = row; current && result.length < limit; current = byId.get(current.parent)) result.push(current);
  return result;
}
export const labels = (row, prefix) => (row.labels ?? []).filter(value => value.startsWith(prefix)).map(value => value.slice(prefix.length));
export const lastMarker = row => (row.notes ?? '').split(/\r?\n/).filter(line => /^(VERIFY_PENDING|DELEGATED)/.test(line)).at(-1) ?? '';
export function registry(rows, kind) {
  const seen = new Set();
  for (const row of rows) {
    if (!row || typeof row.id !== 'string' || !row.id || seen.has(row.id)) throw new Error(`${kind} 등록부 id 누락/중복`);
    seen.add(row.id);
    if (kind === 'sprints' && !['active', 'closed'].includes(row.status)) throw new Error(`스프린트 등록부의 '${row.id}' — status 가 active·closed 가 아니다`);
    if (kind === 'rails' && (typeof row.owner !== 'string' || !row.owner)) throw new Error(`레일 '${row.id}' 의 owner 를 낼 수 없다`);
  }
  return rows;
}
export function cliOptions(argv) {
  const args = [...argv]; let root;
  if (args[0] === '--root') { args.shift(); root = args.shift(); if (!root) throw new Error('--root 값이 필요하다'); }
  return {args, root};
}
export function isMain(url) {
  if (!process.argv[1]) return false;
  // Node resolves an entrypoint's symlinks before setting import.meta.url.
  // Comparing the original spelling would silently skip every CLI action.
  try { return realpathSync(fileURLToPath(url)) === realpathSync(process.argv[1]); }
  catch { return false; }
}
export async function cli(run) {
  try { const result = await run(); process.stdout.write(result.stdout ?? ''); process.stderr.write(result.stderr ?? ''); process.exitCode = result.code; }
  catch (error) { process.stderr.write(`✗ ${error.message}\n`); process.exitCode = 1; }
}
