import { lastExecutionMarker } from '../ledger/record.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { resolveState, readActors, isCancelled, appendState, tsv } from './state.mjs';
import { executeLedger, ledgerRoot } from '../ledger.mjs';

export const STOP_OUTCOMES = [
  'RECURSE',
  'CANCEL',
  'ORACLE_FAIL',
  'SCOPE_FAIL',
  'IDLE',
  'VERIFY_PENDING',
  'GAVE_UP',
  'BLOCK',
];
export const MAX_BLOCKS = 3;
const quote = (value) =>
  "'" + value.replaceAll("'", process.platform === 'win32' ? "''" : "'\\''") + "'";

export async function evaluateStop(
  event,
  {
    env = process.env,
    ledger = executeLedger,
    rootFinder = ledgerRoot,
    pluginRoot = fileURLToPath(new URL('../../', import.meta.url)),
  } = {},
) {
  const result = { code: 0, stdout: '', stderr: '', outcomes: [] };
  let scope;
  try {
    if (
      typeof event.session_id !== 'string' ||
      !event.session_id ||
      typeof event.cwd !== 'string' ||
      !path.isAbsolute(event.cwd)
    )
      throw new Error('Stop session/cwd missing');
    scope = await resolveState({ cwd: event.cwd, sessionId: event.session_id }, env);
  } catch (error) {
    result.stderr = `STATE UNREACHED: ${error.message}; stop allowed\n`;
    return result;
  }
  const log = (outcome, message) => {
    result.outcomes.push(outcome);
    try {
      appendState(
        scope.stopLog,
        [new Date().toISOString(), event.session_id, outcome, message].map(tsv).join('\t'),
        { maxLines: 0 },
      );
    } catch (error) {
      result.stderr += `STATE UNREACHED: Stop observation was not persisted: ${error.message}\n`;
    }
  };
  if (event.stop_hook_active === true) {
    log('RECURSE', 'stop_hook_active=true — 이 훅이 되민 턴의 종료다. 다시 막지 않는다');
    return result;
  }
  try {
    if (isCancelled(scope)) {
      log('CANCEL', '이 세션의 명시적 취소 — 통과한다 (마커 유지)');
      return result;
    }
  } catch (error) {
    result.stderr += `STATE UNREACHED: cancellation could not be evaluated: ${error.message}; stop allowed\n`;
    return result;
  }
  let rows;
  try {
    const root = await rootFinder(event.cwd, env.HARNESS_ROOT);
    const oracle = await ledger(['list', '--status', 'in_progress', '--limit', '0', '--json'], {
      root,
      cwd: event.cwd,
      env,
    });
    if (oracle.code !== 0) throw new Error('ledger list 실패');
    rows = JSON.parse(oracle.stdout);
    if (
      !Array.isArray(rows) ||
      rows.some((row) => !row || typeof row !== 'object' || Array.isArray(row))
    )
      throw new Error('ledger 출력이 JSON 배열이 아니다');
  } catch (error) {
    log('ORACLE_FAIL', `${error.message} — 0 으로 폴백하지 않고 통과한다`);
    return result;
  }
  let range = '원장 전체(검증된 매핑 없음)';
  try {
    const actors = readActors(scope);
    if (actors.status !== 'VERIFIED') throw new Error('검증된 actor 매핑 없음');
    rows = rows.filter((row) => actors.actors.includes(row.actor ?? row.assignee ?? '')); // SCOPE_NARROW
    range = `이 세션의 actor ${actors.actors.join(' ')}`;
  } catch {
    log('SCOPE_FAIL',
      '검증된 actor 매핑을 읽지 못했다 — legacy 상태는 미검증이고 사거리를 좁히지 않는다',
    );
  }
  const n = rows.length;
  if (n === 0) {
    log('IDLE', `in_progress 0건(범위: ${range}) — 막을 이유가 없다`);
    return result;
  }
  const marks = rows.map(lastExecutionMarker);
  const vp = marks.filter((mark) => mark.startsWith('VERIFY_PENDING')).length; // VERIFY_MARK
  const dg = marks.filter((mark) => mark.startsWith('DELEGATED')).length; // DELEGATED_MARK
  const pending = vp + dg;
  if (pending === n) {
    log('VERIFY_PENDING',
      `in_progress ${n}건 전부 표시가 있다(검증 대기 ${vp}건 · 위임 직후 ${dg}건 · 범위: ${range}) — 막을 이유가 없다`,
    );
    return result;
  }
  let blocks = 0;
  try {
    blocks = fs
      .readFileSync(scope.stopLog, 'utf8')
      .split('\n')
      .filter((line) => line.split('\t')[2] === 'BLOCK').length;
  } catch (error) {
    if (error.code !== 'ENOENT') {
      result.stderr += `STATE UNREACHED: Stop count failed: ${error.message}; stop allowed\n`;
      return result;
    }
  }
  if (blocks >= MAX_BLOCKS) {
    log('GAVE_UP',
      `이 세션의 BLOCK ${blocks} 회가 상한 ${MAX_BLOCKS} 에 도달했다 — in_progress ${n}건이 남았지만 막지 않는다`,
    );
    return result;
  }
  log('BLOCK',
    `in_progress ${n}건(표시 없음 ${n - pending}건 · 검증 대기 ${vp}건 · 위임 직후 ${dg}건 · 범위: ${range}) — 재주입 ${blocks + 1}/${MAX_BLOCKS}`,
  );
  const cancel = [
    'node',
    quote(path.join(pluginRoot, 'scripts/state.mjs')),
    '--data',
    quote(scope.data),
    'cancel',
    quote(scope.runtime),
    quote(event.cwd),
    quote(event.session_id),
  ].join(' ');
  result.stdout =
    JSON.stringify({
      decision: 'block',
      reason: `범위 ${range} 안에 in_progress 인 일이 ${n}건 남아 있고 그중 ${n - pending}건은 표시가 없다. 마감했다면 ledger.mjs close 로 닫고, 구현이 끝났다면 VERIFY_PENDING: <커밋 해시>, 위임 직후면 DELEGATED: <마일스톤ID> 를 ledger.mjs state --file 로 남겨라. 사람을 기다리는 중이거나 의도적으로 멈추는 것이면 \`${cancel}\` 로 이 가드를 끈 뒤 종료하라(마커는 이 세션이 끝날 때까지 유효하다). 상한에 닿으면 가드가 스스로 물러난다 — ${scope.stopLog} 참고.`,
    }) + '\n';
  return result;
}
