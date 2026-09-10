import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {resolveState} from './state.mjs';

export async function summarizeGuardLog(args, {env = process.env, cwd = process.cwd(), pluginRoot = env.CLAUDE_PLUGIN_ROOT || fileURLToPath(new URL('../', import.meta.url))} = {}) {
  const [command = 'count', session = ''] = args;
  if (!['count', 'rows'].includes(command) || args.length > (command === 'count' ? 1 : 2)) return {code: 2, stdout: '', stderr: `모르는 하위 명령 또는 인자: ${args.join(' ')} — count | rows [<회차>]\n`};
  const log = env.HARNESS_GUARD_LOG || (await resolveState({cwd}, env)).guardLog;
  let stderr = env.HARNESS_GUARD_LOG ? 'STATE UNVERIFIED: explicit legacy TSV; counts are historical observations\n' : '';
  let text = '';
  try { text = fs.readFileSync(log, 'utf8'); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  if (!text) {
    const hook = path.join(pluginRoot, 'lib/guard.mjs'); let why = '검사한 훅에는 로깅 호출이 있다';
    try {
      if (!fs.readFileSync(hook, 'utf8').includes('await guardLog(event ?? {}, rule, env);')) { // LOGGING_PRESENCE
        return {code: 3, stdout: '', stderr: stderr + `로깅 없는 guard.mjs 가 발화 중이다 — 훅은 돌아도 로그를 남기지 않는다. 이 빈 로그는 '훅 미실행' 도 '발화 0' 도 아니다. 훅=${hook} 로그=${log}\n`};
      }
    } catch { why = '훅 파일을 읽지 못해 로깅 유무를 확인하지 못했다'; }
    return {code: 1, stdout: '', stderr: stderr + `발화 로그가 없거나 비었다 — 관측 미도달: 훅 실행과 로그 쓰기를 확인해야 하며 '발화 0' 이 아니다 (${why}: ${hook}): ${log}\n`};
  }
  const rows = text.trimEnd().split(/\r?\n/).map(line => line.split('\t'));
  if (command === 'count') {
    const counts = new Map();
    for (const row of rows) { const key = `${row[1] ?? ''}\t${row[4] ?? ''}`; counts.set(key, (counts.get(key) ?? 0) + 1); }
    return {code: 0, stdout: [...counts].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(([key, count]) => `${key}\t${count}\n`).join(''), stderr};
  }
  const selected = rows.filter(row => !session || row[1] === session);
  if (session && !selected.length) return {code: 5, stdout: '', stderr: stderr + `회차 ${session} 의 행이 로그에 없다 — 차단 0건이 아니라 그 회차를 못 찾았다 (회전으로 사라졌거나 회차 이름이 다르다): ${log}\n`};
  const blocked = selected.filter(row => row[4] !== '-' && !row[4]?.startsWith('SKIP-'));
  if (!blocked.length) return {code: 4, stdout: '', stderr: stderr + `차단 0건 — 이 범위의 ${selected.length}줄이 전부 통과·SKIP 이다. 못 센 것이 아니라 차단이 실제로 0 이다: ${log}\n`};
  const counts = {ok: 0, truncated: 0, nocmd: 0};
  const stdout = blocked.map(row => {
    const command = row[5] ?? '';
    const state = !command ? 'nocmd' : [...command].length >= 120 ? 'truncated' : 'ok'; // UNICODE_LENGTH
    counts[state]++;
    return [...row.slice(0, 5), state, command].join('\t') + '\n';
  }).join('');
  stderr += `차단 ${blocked.length}건: 분류 가능 ${counts.ok} · 절단(120자 상한) ${counts.truncated} · 명령 없음(옛 5열 행) ${counts.nocmd}\n`;
  if (!counts.ok) stderr += `차단 ${blocked.length}건이 전부 분류 불가다 — 이 범위로는 오탐률을 낼 수 없다. 오탐 0 이 아니라 못 셌다.\n`;
  return {code: counts.ok ? 0 : 6, stdout, stderr};
}
