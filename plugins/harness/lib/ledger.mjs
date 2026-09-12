import fs from 'node:fs/promises';
import path from 'node:path';
import { loadConfig } from './config.mjs';
import { runCommand } from './process.mjs';
import {
  commands,
  beadsCommands,
  csv,
  parse,
  writeValues,
  writeFlags,
  fail,
  json,
  fileArguments,
} from './ledger/common.mjs';
import { githubLedger } from './ledger/github.mjs';
import { notionLedger } from './ledger/notion.mjs';
import { beadsLedger } from './ledger/beads.mjs';
import { applyMarker, isStateMarker, recordBody, rowRecord, withRecordLock } from './ledger/record.mjs';
import { namedTitle } from './ledger/naming.mjs';
import { noteBody } from './ledger/common.mjs';

export { commands, beadsCommands };
export const help = `사용: ledger.mjs [--root <절대 경로>] <하위 명령> [인자…] (bd 호환; legacy ledger.sh 동일)
모든 백엔드 (beads · github · notion):
  init [--title <제목>] [--parent-page <id>] [--prefix <p>]
  create <제목> [-t <type>] [-l <라벨,…>] [--parent <id>] [--acceptance <문>] [--body-file <f>|-d <문>] [--stdin] [--silent] [-p <n>]
  show <id> [--json]
  list [-l <라벨,…>] [--label-pattern <glob>] [--status <s,…>] [-t <type>] [--parent <id>] [--all] [-n <N>] [--json]
  ready [-l <라벨,…>] [-t <type>] [-n <N>] [--json]
  children <id> [--json]
  state <id> <실행 표식> | --file <f> | --stdin
  summary <id> <section> <본문> | --file <f> | --stdin
  note <id> <사건 기록> | --file <f> | --stdin
  close <id>… [--reason <문>|--reason-file <f>] [--force]
  update <id> [--status <s>] [--claim --actor <값>] [-a|--assignee <값>] [--parent <id>] [-t <type>] [--acceptance <문>] [--body-file <f>]
  dep add <id> <의존 대상 id> | --file - (JSONL {"from","to"})
  label add|remove <id…> <라벨>
  wire-worktree <워크트리 절대 경로>
  has-ui
  sync-check [--push]
  rails --json
  sprints --json
  sprint-add <YYYY-SNN>
GitHub 전용:
  project-setup [--apply] (기본은 읽기 전용 계획)
  project-sync [--apply] (기본은 읽기 전용 계획)
  help | --help
본문 파일: create --title-file <f> 로 제목을 대신하고 create/update --acceptance-file <f> 로 완료 조건을 읽는다.
init --title-file <f> 도 지원한다. 파일과 같은 값의 인라인 인자를 함께 주면 거부한다.
beads 전용 (github · notion 은 rc≠0):
  ${beadsCommands.join(' · ')}
  --version (beads passthrough)
create 상속은 sprint:·rail:·repo:만이다. 명시한 접두사가 이기고 slug:는 상속하지 않는다.
epic assignee는 rails의 owner다. --assignee와 --claim은 다른 경로다(동시 사용 github/notion 거부).
없는 설정·지원하지 않는 backend는 rc≠0이며 폴백이 없다. --root → HARNESS_ROOT → cwd 상위 .harness.json 순서다.
`;
export async function ledgerRoot(cwd, explicit) {
  if (explicit) {
    if (!path.isAbsolute(explicit)) fail('ledger root: 절대 경로가 필요하다');
    return fs.realpath(explicit);
  }
  let current = await fs.realpath(cwd);
  for (;;) {
    if (
      await fs.stat(path.join(current, '.harness.json')).then(
        (s) => s.isFile(),
        (e) => {
          if (e.code === 'ENOENT') return false;
          throw e;
        },
      )
    )
      return current;
    const parent = path.dirname(current);
    if (parent === current) fail('ledger: .harness.json 을 찾지 못했다');
    current = parent;
  }
}

// Process/HTTPS transport injection is a library dependency boundary. The CLI
// has no environment-driven replacement executable, API host or policy module.
export async function executeLedger(argv, options = {}) {
  const env = options.env ?? process.env,
    cwd = options.cwd ?? process.cwd();
  const args = [...argv];
  let root = options.root;
  if (args[0] === '--root') {
    args.shift();
    root = args.shift();
    if (!root) return { code: 1, stdout: '', stderr: 'ledger: --root 값이 필요하다\n' };
  }
  if (['help', '--help', '-h'].includes(args[0])) return { code: 0, stdout: help, stderr: '' };
  if (args[0] === '--commands')
    return { code: 0, stdout: json([...commands, ...beadsCommands]), stderr: '' };
  if (!args.length) return { code: 1, stdout: '', stderr: help };
  let stdout = '',
    stderr = '';
  const ctx = {
    env,
    cwd,
    input: options.input ?? Buffer.alloc(0),
    inheritStdin: options.inheritStdin,
    out: (value) => {
      stdout += value;
    },
    err: (value) => {
      stderr += value;
    },
  };
  try {
    ctx.root = await ledgerRoot(cwd, root ?? env.HARNESS_ROOT);
    const loaded = await loadConfig(ctx.root);
    ctx.config = loaded.config;
    ctx.file = loaded.file;
    ctx.backend = ctx.config.ledger.backend;
    args.splice(0, args.length, ...(await fileArguments(args, ctx)));
    ctx.command = async (executable, commandArgs, extra = {}) => {
      const result = await (options.process ?? runCommand)(
        { argv: [executable, ...commandArgs] },
        {
          cwd: extra.cwd ?? ctx.cwd,
          env,
          input: extra.input,
          inheritStdin: options.inheritStdin,
          ...extra,
        },
      );
      if (!extra.allowFailure && (result.status !== 'exited' || result.code !== 0))
        fail(
          `${executable} 실패: ${result.stderr?.toString() || result.error?.message || result.signal || result.code}`,
        );
      return result;
    };
    ctx.request =
      options.request ??
      (async (method, endpoint, body) => {
        const response = await fetch('https://api.notion.com/v1/' + endpoint, {
          method,
          headers: {
            Authorization: `Bearer ${env.NOTION_TOKEN}`,
            'Notion-Version': '2022-06-28',
            'Content-Type': 'application/json',
          },
          ...(body === undefined ? {} : { body: JSON.stringify(body) }),
        });
        const payload = await response.json();
        if (!response.ok)
          fail(
            `HTTP ${response.status} ${payload.code ?? '?'} — ${method} /v1/${endpoint}: ${(payload.message ?? '').slice(0, 200)}`,
          );
        return payload;
      });
    const backend = { github: githubLedger, notion: notionLedger, beads: beadsLedger }[ctx.backend];
    const invoke = async (callArgs) => {
      let captured = '';
      const result = await backend(callArgs, {
        ...ctx,
        out: (value) => {
          captured += value;
        },
      });
      if (result?.code) fail(`ledger-${ctx.backend}: ${result.stderr || 'backend failed'}`);
      if (result?.stderr) ctx.err(result.stderr);
      return captured + (result?.stdout ?? '');
    };
    // Legacy exact machine notes are routed to mutable state as well, so an
    // interrupted session running an older prompt does not resume comment spam.
    if (args[0] === 'note' && isStateMarker(await noteBody(args.slice(2), ctx))) args[0] = 'state';
    if (['state', 'summary'].includes(args[0])) {
      const [command, id, ...rest] = args;
      if (!id) fail(`${command}: id 가 필요하다`);
      const section = command === 'summary' ? rest.shift() : null;
      if (section !== null && !/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$/.test(section ?? '')) fail('summary: 유효한 section 이 필요하다');
      const value = await noteBody(rest, ctx);
      const identity = JSON.stringify([ctx.backend, ctx.config.ledger.owner ?? ctx.config.ledger.database_id ?? ctx.root, id]);
      await withRecordLock(identity, async () => {
        const readRow = async () => {
          const row = JSON.parse(await invoke(['show', id, '--json']))[0];
          if (!row?.id) fail(`${command}: 이슈를 읽지 못했다`);
          return row;
        };
        const before = await readRow(), record = structuredClone(rowRecord(before));
        if (command === 'state') record.execution = applyMarker(record.execution, value);
        else record.summaries[section] = value;
        if (JSON.stringify(record) === JSON.stringify(rowRecord(before)) && before.execution) return;
        const fingerprint = row => JSON.stringify([row.description, row.acceptance_criteria, rowRecord(row)]);
        if (fingerprint(before) !== fingerprint(await readRow())) fail('record conflict: 본문이 변경됐다 — 다시 읽고 재시도하라');
        await invoke(['update', id, '--description', recordBody(before.description, record)]);
        const after = await readRow();
        if (after.description !== before.description || after.acceptance_criteria !== before.acceptance_criteria || JSON.stringify(rowRecord(after)) !== JSON.stringify(record))
          fail('record conflict: 쓰기 후 결과가 다르다 — 덮어쓰지 말고 원장을 확인하라');
      });
      ctx.out(`✓ ${command} updated: ${id}\n`);
    } else if (args[0] === 'create') {
      // Keep backend-specific argv intact; only shared label flags are replaced.
      const parsed = parse(args.slice(1), writeValues, writeFlags, true),
        labels = csv(parsed.labels);
      if (parsed.parent) {
        let parent;
        try {
          parent = JSON.parse(await invoke(['show', parsed.parent, '--json']))[0];
        } catch (error) {
          fail(`create: 부모 '${parsed.parent}' 를 읽지 못했다 — ${error.message}`);
        }
        if (ctx.backend === 'beads' && parent?.id && parent.labels == null) parent.labels = [];
        if (!Array.isArray(parent?.labels))
          fail(`create: 부모 '${parsed.parent}' 의 labels 를 읽지 못했다`);
        const explicit = new Set(labels.map((label) => label.split(':')[0]));
        for (const label of parent.labels)
          if (
            /^(sprint|rail|repo):/.test(label) &&
            !explicit.has(label.split(':')[0]) &&
            !labels.includes(label)
          )
            labels.push(label);
      }
      const final = ['create'];
      for (let i = 1; i < args.length; i++) {
        const arg = args[i];
        if (['-l', '--label', '--labels'].includes(arg)) i++;
        else {
          final.push(arg);
          if (Object.hasOwn(writeValues, arg)) final.push(args[++i]);
        }
      }
      for (let i = 1; i < final.length; i++) {
        if (Object.hasOwn(writeValues, final[i])) { i++; continue; }
        if (!final[i].startsWith('-')) { final[i] = namedTitle(final[i], parsed.type ?? 'task'); break; }
      }
      if (labels.length) final.push('-l', labels.join(','));
      let owner;
      if (parsed.type === 'epic' && labels.some((label) => label.startsWith('rail:'))) {
        const rail = labels.find((label) => label.startsWith('rail:')).slice(5);
        try {
          owner = JSON.parse(await invoke(['rails', '--json'])).find(
            (row) => row.id === rail,
          )?.owner;
        } catch (error) {
          ctx.err(`ledger: create: 레일 등록부를 읽지 못했다 — ${error.message}\n`);
        }
        if (!owner)
          ctx.err(
            `ledger: create: 레일 '${rail}' 의 owner 를 찾지 못했다 — 첫 epic 이면 정상이다. assignee 없이 만든다\n`,
          );
      }
      const strip = ctx.backend === 'beads' && parsed.parent;
      if (owner || strip) {
        if (!parsed.silent) final.push('--silent');
        const id = (await invoke(final)).trim();
        if (!id) fail('create: 백엔드가 새 id 를 내지 않았다');
        try {
          if (owner) await invoke(['update', id, '--assignee', owner]);
          if (strip) {
            const created = JSON.parse(await invoke(['show', id, '--json']))[0];
            if (created?.id && created.labels == null) created.labels = [];
            if (!Array.isArray(created?.labels)) fail('실제 labels 를 읽지 못했다');
            for (const label of created.labels)
              if (!labels.includes(label)) await invoke(['label', 'remove', id, label]);
          }
        } catch (error) {
          fail(`create: ${id} 는 만들었지만 후속 계약을 적용하지 못했다 — ${error.message}`);
        }
        ctx.out(
          parsed.silent ? id + '\n' : `✓ Created issue: ${id} — ${parsed.positional[0] ?? ''}\n`,
        );
      } else ctx.out(await invoke(final));
    } else {
      if (args[0] === 'sprint-add') {
        if (args.length !== 2 || !/^\d{4}-S\d{2}$/.test(args[1]))
          fail('sprint-add: 스프린트 ID 형식은 YYYY-SNN 이다');
        const rows = JSON.parse(await invoke(['sprints', '--json']));
        if (!Array.isArray(rows)) fail('sprint-add: 지금 등재를 읽지 못했다');
        if (rows.some((row) => row.id === args[1]))
          fail(`sprint-add: '${args[1]}' 는 이미 등재돼 있다 — 덮어쓰지 않는다`);
      }
      const result = args[0] === 'update'
        ? await withRecordLock(JSON.stringify([ctx.backend, ctx.config.ledger.owner ?? ctx.config.ledger.database_id ?? ctx.root, args[1]]), () => backend(args, ctx))
        : await backend(args, ctx);
      if (result)
        return {
          ...result,
          stdout: stdout + (result.stdout ?? ''),
          stderr: stderr + (result.stderr ?? ''),
        };
    }
    return { code: 0, stdout, stderr };
  } catch (error) {
    return { code: 1, stdout, stderr: stderr + `ledger: ${error.message}\n` };
  }
}
