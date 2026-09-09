#!/usr/bin/env node
import {consumerContext, ledgerIndex, ancestors, labels, registry, cliOptions, isMain, cli} from '../lib/ledger-view.mjs';

// Whole-ledger population; closed/deferred only exempt missing acceptance and
// orphan sprint ancestry. A closed child's mismatching label still corrupts counts.
export function judgeBoard(rows, rails, sprints) {
  const byId = ledgerIndex(rows), errors = [];
  if (!rows.length) throw new Error('원장이 0건이다 — 빈 집합에 대한 검사는 통과가 아니라 검사 안 함이다');
  registry(rails, 'rails'); registry(sprints, 'sprints');
  const sprintIds = new Set(rows.flatMap(row => labels(row, 'sprint:')));
  for (const id of sprintIds) {
    if (!/^\d{4}-S\d{2}$/.test(id)) errors.push(`sprint:${id} — 스프린트 ID 형식 위반 (YYYY-SNN)`);
    if (!sprints.some(row => row.id === id)) errors.push(`sprint:${id} — 스프린트 등록부에 등재되지 않은 스프린트`);
  }
  for (const row of sprints) if (!sprintIds.has(row.id)) errors.push(`스프린트 등록부의 '${row.id}' — 원장에 sprint:${row.id} 라벨이 하나도 없다`);
  for (const id of new Set(rows.flatMap(row => labels(row, 'rail:')))) if (!rails.some(row => row.id === id)) errors.push(`rail:${id} — 레일 등록부에 등재되지 않은 레일`);
  for (const row of rows) {
    const chain = ancestors(row, byId, 8), terminal = ['closed', 'deferred'].includes(row.status);
    const expected = chain.filter(item => item.issue_type === 'epic').map(item => labels(item, 'sprint:')[0]).find(value => value !== undefined);
    const own = labels(row, 'sprint:')[0];
    if (row.issue_type !== 'epic') {
      if (expected !== undefined && own !== expected) errors.push(`${row.id} — MISMATCH: 상위 스토리는 sprint:${expected} 인데 이 이슈의 라벨이 다르다 (${row.title ?? ''})`);
      else if (expected === undefined && own !== undefined && !terminal) errors.push(`${row.id} — ORPHAN: sprint:${own} 라벨이 있는데 조상에 스프린트 epic 이 없다`);
    }
    if (row.issue_type === 'task' && !(row.acceptance_criteria ?? '') && !terminal && chain.some(item => labels(item, 'sprint:').length)) errors.push(`${row.id} — acceptance 가 비어 있다 (${row.title ?? ''}). 착수 전에 채워라`);
  }
  return {code: errors.length ? 1 : 0, stdout: errors.length ? errors.map(line => `✗ ${line}\n`).join('') : '✓ 원장 구조 검사 통과 — 형식·레일 등재·스프린트 등록부·상속·acceptance\n'};
}
export async function checkBoard(options = {}) {
  const context = await consumerContext(options);
  const rows = await context.array(['list', '--all', '--json', '-n', '0']);
  const [rails, sprints] = await Promise.all([context.array(['rails', '--json']), context.array(['sprints', '--json'])]);
  return judgeBoard(rows, rails, sprints);
}
if (isMain(import.meta.url)) await cli(() => { const {args, root} = cliOptions(process.argv.slice(2)); if (args.length) throw new Error('인자를 받지 않는다 (사용법: board-check.mjs [--root <root>])'); return checkBoard({root}); });
