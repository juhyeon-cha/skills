import { loadConfig } from '../config.mjs';
import {
  parse,
  createOptions,
  updateOptions,
  csv,
  unique,
  json,
  fail,
  listOptions,
  filterRows,
  rowsText,
  showText,
  description,
  noteBody,
  bodyFile,
  dependencyPairs,
  railsFrom,
  replaceJSON,
} from './common.mjs';

export const richText = (value) => {
  const chars = [...value],
    parts = [];
  for (let i = 0; i < chars.length; i += 2000)
    parts.push({ type: 'text', text: { content: chars.slice(i, i + 2000).join('') } });
  return parts;
};
const txt = (value) => (value ?? []).map((part) => part.plain_text ?? '').join('');
export function normalizeNotion(page) {
  const p = page.properties,
    assignee = txt(p.Assignee?.rich_text) || null;
  return {
    id: page.id,
    title: txt(p.Name?.title),
    description: txt(p.Description?.rich_text),
    acceptance_criteria: txt(p.Acceptance?.rich_text),
    status: p.Status?.select?.name ?? 'open',
    issue_type: p.Type?.select?.name ?? 'task',
    labels: (p.Labels?.multi_select ?? []).map((label) => label.name).sort(),
    notes: null,
    assignee,
    actor: assignee,
    parent: p.Parent?.relation?.[0]?.id ?? null,
    priority: 2,
    created_at: page.created_time ?? null,
    updated_at: page.last_edited_time ?? null,
  };
}
export async function notionLedger(argv, ctx) {
  const [cmd, ...args] = argv;
  if (cmd === 'has-ui') {
    ctx.out('Notion 의 데이터베이스 화면\n');
    return;
  }
  if (cmd === 'wire-worktree') {
    ctx.out(
      'ledger-notion: 워크트리 배선 없음 — 루트는 HARNESS_ROOT 또는 위로 거슬러 찾은 .harness.json 으로 정한다\n',
    );
    return;
  }
  if (cmd === 'sync-check') {
    ctx.out('✓ 원장 게이트 통과 — 원격 반영 대상 없음 (notion 백엔드: 페이지가 원격 자체다)\n');
    return;
  }
  if (!ctx.env.NOTION_TOKEN) fail('NOTION_TOKEN 환경 변수가 없다 — 통합 토큰을 환경 변수로만 준다');
  let database = ctx.config.ledger.database_id;
  const request = ctx.request;
  const need = () => {
    if (!database)
      fail(
        `${ctx.file} 에 ledger.database_id 가 없다 — ledger.sh init --parent-page <페이지 id> 가 만든다`,
      );
  };
  const page = (id) => request('GET', `pages/${id}`);
  const props = (id, properties) => request('PATCH', `pages/${id}`, { properties });
  const append = (id, text) =>
    request('PATCH', `blocks/${id}/children`, {
      children: [{ object: 'block', type: 'paragraph', paragraph: { rich_text: richText(text) } }],
    });
  const notes = async (id) => {
    const result = await request('GET', `blocks/${id}/children?page_size=100`);
    const paragraphs = result.results
      .filter((row) => row.type === 'paragraph')
      .map((row) => txt(row.paragraph.rich_text));
    return paragraphs.length ? paragraphs.join('\n') : null;
  };
  const query = async (filter) => {
    let cursor,
      rows = [];
    const seen = new Set();
    do {
      const result = await request('POST', `databases/${database}/query`, {
        page_size: 100,
        ...(filter ? { filter } : {}),
        ...(cursor ? { start_cursor: cursor } : {}),
      });
      if (!Array.isArray(result.results)) fail('query 응답을 정규화하지 못했다');
      rows.push(...result.results.map(normalizeNotion));
      if (!result.has_more) break;
      cursor = result.next_cursor;
      if (!cursor || seen.has(cursor))
        fail('query pagination UNREACHED: missing/repeated next_cursor');
      seen.add(cursor);
    } while (cursor);
    return rows;
  };
  const list = async (options) => {
    need();
    const filters = csv(options.labels).map((label) => ({
      property: 'Labels',
      multi_select: { contains: label },
    }));
    if (options.type) filters.push({ property: 'Type', select: { equals: options.type } });
    if (options.parent)
      filters.push({ property: 'Parent', relation: { contains: options.parent } });
    if (options.status)
      filters.push({
        or: csv(options.status).map((status) => ({
          property: 'Status',
          select: { equals: status },
        })),
      });
    else if (!options.all)
      filters.push({ property: 'Status', select: { does_not_equal: 'closed' } });
    const rows = filterRows(await query(filters.length ? { and: filters } : null), options);
    for (const row of rows) row.notes = await notes(row.id);
    return rows;
  };
  switch (cmd) {
    case 'init': {
      const options = parse(args, { '--parent-page': 'parent', '--title': 'title' });
      if (options.positional.length) fail('init: 모르는 인자');
      const base = {
        Name: { title: {} },
        Type: {
          select: {
            options: ['epic', 'feature', 'task', 'bug', 'chore', 'decision'].map((name) => ({
              name,
            })),
          },
        },
        Status: {
          select: {
            options: ['open', 'in_progress', 'blocked', 'deferred', 'closed'].map((name) => ({
              name,
            })),
          },
        },
        Acceptance: { rich_text: {} },
        Labels: { multi_select: {} },
        Description: { rich_text: {} },
        Assignee: { rich_text: {} },
      };
      if (!database) {
        if (!options.parent) fail('새로 만들려면 init --parent-page <통합이 공유된 페이지 id>');
        const result = await request('POST', 'databases', {
          parent: { type: 'page_id', page_id: options.parent },
          title: richText(options.title ?? 'harness-ledger'),
          properties: base,
        });
        database = result.id;
        if (!database) fail('DB 생성 응답에 id 가 없다');
        const { config } = await loadConfig(ctx.root);
        config.ledger.database_id = database;
        await replaceJSON(ctx.file, config);
      }
      await request('PATCH', `databases/${database}`, {
        properties: {
          Parent: { relation: { database_id: database, single_property: {} } },
          'Blocked by': { relation: { database_id: database, single_property: {} } },
          Description: { rich_text: {} },
          Assignee: { rich_text: {} },
        },
      });
      ctx.out(`✓ notion 원장: database_id=${database} (${ctx.file})\n`);
      break;
    }
    case 'create': {
      need();
      const options = createOptions(args),
        title = options.positional[0];
      if (!title) fail('create: 제목이 필요하다');
      const properties = {
        Name: { title: richText(title) },
        Type: { select: { name: options.type ?? 'task' } },
        Status: { select: { name: 'open' } },
        Labels: { multi_select: csv(options.labels).map((name) => ({ name })) },
        Acceptance: { rich_text: richText(options.acceptance ?? '') },
        Description: { rich_text: richText(await description(options, ctx)) },
      };
      if (options.parent) properties.Parent = { relation: [{ id: options.parent }] };
      const result = await request('POST', 'pages', {
        parent: { database_id: database },
        properties,
      });
      if (!result.id) fail('페이지 생성 응답에 id 가 없다');
      ctx.out(options.silent ? result.id + '\n' : `✓ Created issue: ${result.id} — ${title}\n`);
      break;
    }
    case 'show': {
      if (!args[0]) fail('show: id 가 필요하다');
      const raw = await page(args[0]),
        row = normalizeNotion(raw);
      row.notes = await notes(row.id);
      row.dependencies = [];
      for (const dep of raw.properties['Blocked by']?.relation ?? []) {
        const rawDep = await page(dep.id);
        row.dependencies.push({
          id: dep.id,
          status: rawDep.properties.Status?.select?.name ?? 'open',
          dependency_type: 'blocks',
        });
      }
      ctx.out(args.includes('--json') ? json([row]) : showText(row));
      break;
    }
    case 'list':
    case 'children': {
      if (cmd === 'children' && !args[0]) fail('children: id 가 필요하다');
      const options =
        cmd === 'children' ? { parent: args[0], all: true, limit: 0 } : listOptions(args);
      const rows = await list(options);
      ctx.out(args.includes('--json') ? json(rows) : rowsText(rows));
      break;
    }
    case 'ready': {
      const options = listOptions(args),
        rows = await list({ ...options, status: 'open', limit: 0 }),
        ready = [];
      for (const row of rows) {
        const raw = await page(row.id);
        let open = false;
        for (const dep of raw.properties['Blocked by']?.relation ?? []) {
          const rawDep = await page(dep.id);
          if ((rawDep.properties.Status?.select?.name ?? 'open') !== 'closed') {
            open = true;
            break;
          }
        }
        if (!open) ready.push(row);
      }
      const limited = options.limit ? ready.slice(0, options.limit) : ready;
      ctx.out(options.json ? json(limited) : rowsText(limited));
      break;
    }
    case 'note': {
      const id = args.shift();
      if (!id) fail('note: id 가 필요하다');
      await append(id, await noteBody(args, ctx));
      ctx.out(`✓ Note added to ${id}\n`);
      break;
    }
    case 'close': {
      const options = parse(
        args,
        { '-r': 'reason', '--reason': 'reason', '--reason-file': 'reasonFile' },
        { '--force': 'force', '--json': 'json' },
      );
      if (!options.positional.length) fail('close: id 가 필요하다');
      const reason = options.reasonFile ? await bodyFile(options.reasonFile, ctx) : options.reason;
      for (const id of options.positional) {
        await props(id, { Status: { select: { name: 'closed' } } });
        if (reason) await append(id, reason);
        ctx.out(`✓ Closed ${id}\n`);
      }
      break;
    }
    case 'update': {
      const id = args.shift();
      if (!id) fail('update: id 가 필요하다');
      const options = updateOptions(args);
      if (options.claim && options.assignee !== undefined)
        fail('update: --claim 과 --assignee 는 같이 쓸 수 없다');
      if (options.claim) options.status ||= 'in_progress';
      const properties = {};
      if (options.status) properties.Status = { select: { name: options.status } };
      if (options.claim) properties.Assignee = { rich_text: richText(options.actor ?? '') };
      if (options.assignee !== undefined)
        properties.Assignee = { rich_text: richText(options.assignee) };
      if (options.parent) properties.Parent = { relation: [{ id: options.parent }] };
      if (options.type) properties.Type = { select: { name: options.type } };
      if (options.acceptance !== undefined)
        properties.Acceptance = { rich_text: richText(options.acceptance) };
      if (options.bodyFile !== undefined || options.description !== undefined)
        properties.Description = { rich_text: richText(await description(options, ctx)) };
      if (Object.keys(properties).length) await props(id, properties);
      if (options.claim && options.actor) await append(id, `ACTOR: ${options.actor}`);
      ctx.out(`✓ Updated issue: ${id}\n`);
      break;
    }
    case 'dep': {
      for (const [from, to] of await dependencyPairs(args, ctx)) {
        const raw = await page(from),
          ids = unique([
            ...(raw.properties['Blocked by']?.relation ?? []).map((row) => row.id),
            to,
          ]);
        await props(from, { 'Blocked by': { relation: ids.map((id) => ({ id })) } });
        ctx.out(`✓ Added dependency: ${from} blocked by ${to}\n`);
      }
      break;
    }
    case 'label': {
      const sub = args.shift(),
        label = args.pop();
      if (!['add', 'remove'].includes(sub) || !args.length || !label)
        fail('label: add|remove <id…> <라벨>');
      for (const id of args) {
        const raw = await page(id),
          labels = (raw.properties.Labels?.multi_select ?? []).map((row) => row.name);
        await props(id, {
          Labels: {
            multi_select: (sub === 'add'
              ? unique([...labels, label])
              : labels.filter((value) => value !== label)
            ).map((name) => ({ name })),
          },
        });
        ctx.out(
          `✓ ${sub === 'add' ? 'Added' : 'Removed'} label '${label}' ${sub === 'add' ? 'to' : 'from'} ${id}\n`,
        );
      }
      break;
    }
    case 'sprint-add': {
      need();
      const result = await request('POST', 'pages', {
        parent: { database_id: database },
        properties: {
          Name: { title: richText(args[0]) },
          Type: { select: { name: 'sprint' } },
          Status: { select: { name: 'open' } },
        },
      });
      if (!result.id) fail('sprint-add: 페이지 생성 응답에 id 가 없다');
      ctx.out(
        `✓ 스프린트 등재: ${args[0]} (notion: Type=sprint 페이지 ${result.id} · Status=open → sprints 의 active)\n`,
      );
      break;
    }
    case 'rails':
    case 'sprints': {
      if (args.some((arg) => arg !== '--json')) fail(`${cmd}: 모르는 인자`);
      const rows = await list({
        all: true,
        type: cmd === 'rails' ? 'epic' : 'sprint',
        ...(cmd === 'rails' ? { pattern: 'rail:*' } : {}),
        limit: 0,
      });
      if (cmd === 'rails') ctx.out(json(railsFrom(rows, ctx)));
      else {
        if (!rows.length)
          ctx.err('ledger-notion: sprints: Type 이 sprint 인 페이지가 원장에 하나도 없다\n');
        ctx.out(
          json(
            rows
              .map((row) => ({
                id: row.title,
                status: row.status === 'closed' ? 'closed' : 'active',
              }))
              .sort((a, b) => a.id.localeCompare(b.id)),
          ),
        );
      }
      break;
    }
    default:
      fail(`'${cmd}' 는 notion 백엔드에 없다 (beads 전용이거나 모르는 명령) — ledger.sh --help`);
  }
}
