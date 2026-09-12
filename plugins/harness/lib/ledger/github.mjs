import { githubProject } from './github-project.mjs';
import { splitRecord, recordBody, normalizeRecord, preserveRecord, rowRecord, applyMarker } from './record.mjs';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { loadConfig } from '../config.mjs';
import {
  parse,
  createOptions,
  updateOptions,
  csv,
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

const fields =
  'id databaseId number title state body createdAt updatedAt closedAt repository{name} labels(first:100){nodes{name}} assignees(first:10){nodes{login}} comments(first:100){nodes{body} pageInfo{hasNextPage endCursor}} parent{number repository{name}} blockedBy(first:50){totalCount nodes{number state repository{name}}}';
const projectField = 'projectItems(first:20){nodes{project{number}}}';
export function normalizeGithub(node) {
  if (
    !node?.repository?.name ||
    !Number.isInteger(node.number) ||
    !Array.isArray(node.labels?.nodes) ||
    !Array.isArray(node.comments?.nodes) ||
    !Array.isArray(node.assignees?.nodes) ||
    !Array.isArray(node.blockedBy?.nodes) ||
    !Number.isInteger(node.blockedBy.totalCount) ||
    node.blockedBy.totalCount < 0
  ) {
    fail('GitHub issue 응답 계약에 필수 식별자·라벨·댓글·의존성이 없다');
  }
  const id = `${node.repository.name}#${node.number}`,
    labels = (node.labels?.nodes ?? []).map((row) => row.name);
  const deps = node.blockedBy?.nodes ?? [];
  if ((node.blockedBy?.totalCount ?? 0) > deps.length)
    fail(
      `blockedBy 가 잘렸다: ${id} — totalCount=${node.blockedBy.totalCount} 받은 노드=${deps.length} · FIELDS 의 blockedBy(first:N) 을 늘려라`,
    );
  const managed = splitRecord(node.body ?? '');
  let body = managed.body;
  if (body.startsWith('## Acceptance\n')) body = '\n' + body;
  const parts = body.split('\n## Acceptance\n');
  if (node.comments.pageInfo?.hasNextPage) fail(`comments 가 잘렸다: ${id} — 실행 상태를 추측하지 않는다`);
  const comments = (node.comments?.nodes ?? []).map((row) => row.body);
  const actors = comments
    .map((text) => /^ACTOR:[ \t]*([^\r\n]*)/.exec(text)?.[1]?.split(' ').filter(Boolean).at(-1))
    .filter((value) => value != null);
  return normalizeRecord({
    id,
    title: node.title,
    description: recordBody((parts[0] ?? '').replace(/\n$/, ''), managed.record),
    acceptance_criteria:
      parts.length > 1
        ? parts.slice(1).join('\n## Acceptance\n').replace(/^\n/, '').replace(/\n$/, '')
        : '',
    status:
      node.state === 'CLOSED'
        ? 'closed'
        : (labels.find((x) => x.startsWith('status:')) ?? 'status:open').slice(7),
    issue_type: (labels.find((x) => x.startsWith('type:')) ?? 'type:task').slice(5),
    labels: labels.filter((x) => !x.startsWith('type:') && !x.startsWith('status:')).sort(),
    notes: comments.length ? comments.join('\n') : null,
    assignee: node.assignees?.nodes?.[0]?.login ?? null,
    actor: actors.at(-1) ?? null,
    dependencies: deps.map((dep) => ({
      id: `${dep.repository.name}#${dep.number}`,
      status: dep.state === 'CLOSED' ? 'closed' : 'open',
      dependency_type: 'blocks',
    })),
    parent: node.parent ? `${node.parent.repository.name}#${node.parent.number}` : null,
    priority: 2,
    created_at: node.createdAt ?? null,
    updated_at: node.updatedAt ?? null,
    closed_at: node.closedAt ?? null,
  });
}
const compose = (desc, acceptance) =>
  desc + (acceptance ? '\n\n## Acceptance\n\n' + acceptance : '') + '\n';
export async function githubLedger(argv, ctx) {
  const [cmd, ...args] = argv;
  if (cmd === 'has-ui') {
    ctx.out('GitHub 의 이슈·Projects 화면\n');
    return;
  }
  if (cmd === 'wire-worktree') {
    ctx.out(
      'ledger-github: 워크트리 배선 없음 — 루트는 HARNESS_ROOT 또는 위로 거슬러 찾은 .harness.json 으로 정한다\n',
    );
    return;
  }
  if (cmd === 'sync-check') {
    ctx.out('✓ 원장 게이트 통과 — 원격 반영 대상 없음 (github 백엔드: 이슈가 원격 자체다)\n');
    return;
  }
  const owner = ctx.config.ledger.owner;
  let project = ctx.config.ledger.project;
  if (!owner) fail(`${ctx.file} 에 ledger.owner 가 없다`);
  const gh = async (args, extra = {}) => ctx.command('gh', args, extra);
  const text = async (args, extra) => (await gh(args, extra)).stdout.toString().trimEnd();
  const read = async (args, extra) => JSON.parse(await text(args, extra));
  const auth = await gh(['auth', 'status'], { allowFailure: true });
  if (auth.code !== 0) fail('gh 인증이 없다 — 사람이 gh auth login 을 먼저 한다');
  const split = (id) => {
    const match = /^([^#]+)#([0-9]+)$/.exec(id ?? '');
    if (!match) fail(`id 형식은 <repo>#<번호> 다: '${id}'`);
    return { repo: match[1], num: match[2], slug: `${owner}/${match[1]}` };
  };
  const query = async (q, variables = {}, paginate = false) =>
    read([
      'api',
      'graphql',
      ...(paginate ? ['--paginate', '--slurp'] : []),
      '-f',
      'query=' + q,
      ...Object.entries(variables).flatMap(([key, value]) => [
        typeof value === 'number' ? '-F' : '-f',
        `${key}=${value}`,
      ]),
    ]);
  const issueQuery = async (id, selection) => {
    const { repo, num } = split(id);
    const result = await query(
      `query($o:String!,$r:String!,$n:Int!){ repository(owner:$o,name:$r){ issue(number:$n){ ${selection} } } }`,
      { o: owner, r: repo, n: Number(num) },
    );
    const node = result.data?.repository?.issue;
    if (!node) fail(`없는 id 이거나 읽지 못했다: ${id}`);
    const cursors = new Set();
    while (node.comments?.pageInfo?.hasNextPage) {
      const cursor = node.comments.pageInfo.endCursor;
      if (!cursor || cursors.has(cursor)) fail(`comments pagination: ${id} 의 cursor 가 없거나 반복된다`);
      cursors.add(cursor);
      const next = await query('query($o:String!,$r:String!,$n:Int!,$after:String!){repository(owner:$o,name:$r){issue(number:$n){comments(first:100,after:$after){nodes{body} pageInfo{hasNextPage endCursor}}}}}', {o:owner,r:repo,n:Number(num),after:cursor});
      const page = next.data?.repository?.issue?.comments;
      if (!Array.isArray(page?.nodes) || !page.pageInfo) fail(`comments pagination: ${id} 의 응답이 없다`);
      node.comments.nodes.push(...page.nodes);
      node.comments.pageInfo = page.pageInfo;
    }
    return node;
  };
  const ensure = async (slug, label) => gh(['label', 'create', label, '-R', slug, '--force']);
  const parent = async (parentID, childID) => {
    const p = split(parentID),
      c = split(childID);
    const pn = await text(['api', `repos/${p.slug}/issues/${p.num}`, '--jq', '.node_id']),
      cn = await text(['api', `repos/${c.slug}/issues/${c.num}`, '--jq', '.node_id']);
    await query(
      'mutation($p:ID!,$c:ID!){ addSubIssue(input:{issueId:$p, subIssueId:$c}) { issue { number } subIssue { number } } }',
      { p: pn, c: cn },
    );
  };
  const withBody = async (body, action) => {
    const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'harness-ledger-'));
    const file = path.join(directory, 'body');
    try {
      await fs.writeFile(file, body);
      return await action(file);
    } finally {
      await fs.rm(directory, { recursive: true, force: true });
    }
  };
  const requireProject = () => {
    if (!project) fail(`${ctx.file} 에 ledger.project 가 없다 — ledger.sh init 이 만든다`);
  };
  let projectClient;
  const projects = () => {
    requireProject();
    projectClient ??= githubProject({ command: ctx.command, owner, number: project });
    return projectClient;
  };
  const enableProjection = async () => {
    const { config: current } = await loadConfig(ctx.root);
    current.ledger.project_views = true;
    await replaceJSON(ctx.file, current);
    ctx.config.ledger.project_views = true;
  };
  const syncIssue = async (id) => {
    if (!ctx.config.ledger.project_views) return;
    const result = await projects().sync(normalizeGithub(await issueQuery(id, fields)), { apply: true });
    if (result.skipped) fail(`Project projection: ${result.skipped}`);
  };
  const list = async (options) => {
    requireProject();
    const membership = await query(
      'query($o:String!,$n:Int!,$endCursor:String){ user(login:$o){ projectV2(number:$n){ items(first:100, after:$endCursor){ nodes{ content{ ... on Issue { repository{name} } } } pageInfo{hasNextPage endCursor} } } } }',
      { o: owner, n: Number(project) },
      true,
    ).catch((error) => fail(`Project ${project} 항목 조회 실패 — ${error.message}`));
    const names = [
      ...new Set(
        membership
          .flatMap((page) => page.data?.user?.projectV2?.items?.nodes ?? [])
          .map((item) => item.content?.repository?.name)
          .filter(Boolean),
      ),
    ].sort();
    if (!names.length)
      ctx.err(
        `ledger-github: Project ${project} (owner ${owner}) 에 이슈 항목이 0건이다 — 훑을 레포가 없다. ledger.project 번호를 확인하라.\n`,
      );
    let rows = [],
      seen = 0,
      kept = 0;
    for (const name of names) {
      const states =
        options.all || csv(options.status).includes('closed') ? '[OPEN,CLOSED]' : '[OPEN]';
      const pages = await query(
        `query($o:String!,$r:String!,$endCursor:String){ repository(owner:$o,name:$r){ issues(first:100, after:$endCursor, states:${states}){ nodes{ ${fields} ${projectField} } pageInfo{hasNextPage endCursor} } } }`,
        { o: owner, r: name },
        true,
      );
      const nodes = pages.flatMap((page) => page.data.repository.issues.nodes);
      seen += nodes.length;
      const selected = nodes.filter((node) =>
        (node.projectItems?.nodes ?? []).some(
          (item) => String(item.project.number) === String(project),
        ),
      );
      kept += selected.length;
      for (const node of selected)
        rows.push(normalizeGithub(node.comments?.pageInfo?.hasNextPage ? await issueQuery(`${node.repository.name}#${node.number}`, fields) : node));
    }
    if (!kept && seen)
      ctx.err(
        `ledger-github: Project ${project} 에 든 이슈가 0건이다 — 등재 레포의 이슈 ${seen}건은 전부 프로젝트 밖이다. ledger.project 번호를 확인하라.\n`,
      );
    return filterRows(rows, options);
  };
  const iteration = async () => {
    requireProject();
    const result = await query(
      'query($o:String!,$n:Int!){ user(login:$o){ projectV2(number:$n){ id fields(first:100){ nodes{ ... on ProjectV2IterationField { id name configuration { duration iterations{ title startDate duration } completedIterations{ title startDate duration } } } } } } } }',
      { o: owner, n: Number(project) },
    );
    const p = result.data?.user?.projectV2;
    if (!p)
      fail(
        `sprints: 사용자 ${owner} 의 Projects v2 ${project} 를 읽지 못했다 — 조직 소유 project 에는 이 질의가 닿지 않는다`,
      );
    return { project: p, field: p.fields.nodes.find((field) => field.name === 'Sprint' && field.configuration != null) };
  };
  switch (cmd) {
    case 'init': {
      const options = parse(args, { '--title': 'title' });
      if (options.positional.length) fail('init: 모르는 인자');
      if (!project) {
        const result = await read([
          'project',
          'create',
          '--owner',
          owner,
          '--title',
          options.title ?? 'harness-ledger',
          '--format',
          'json',
        ]);
        project = result.number;
        if (!project) fail('Projects v2 를 만들지 못했다');
        const { config: current } = await loadConfig(ctx.root);
        current.ledger.project = project;
        await replaceJSON(ctx.file, current);
      }
      await gh(['project', 'view', String(project), '--owner', owner, '--format', 'json']);
      const result = await projects().setup({ apply: true });
      await enableProjection();
      for (const limitation of result.limitations) ctx.err(`Project: ${limitation}\n`);
      ctx.out(`✓ github 원장: owner=${owner} project=${project} (${ctx.file})\n`);
      break;
    }
    case 'project-setup': {
      if (args.some((arg) => !['--apply', '--json'].includes(arg))) fail('project-setup: --apply, --json only');
      const result = await projects().setup({ apply: args.includes('--apply') });
      if (args.includes('--apply')) await enableProjection();
      ctx.out(json(result));
      break;
    }
    case 'project-sync': {
      if (args.some((arg) => !['--apply', '--json'].includes(arg))) fail('project-sync: --apply, --json only');
      const results = await projects().syncAll(await list({ all: true, limit: 0 }), { apply: args.includes('--apply') });
      ctx.out(json(results));
      break;
    }
    case 'create': {
      const options = createOptions(args),
        title = options.positional[0];
      if (!title) fail('create: 제목이 필요하다');
      requireProject();
      const labels = csv(options.labels),
        repos = labels.filter((label) => label.startsWith('repo:'));
      if (repos.length !== 1)
        fail(`create: repo: 라벨이 ${repos.length}개다 — 이슈가 살 레포는 정확히 하나여야 한다`);
      const repo = repos[0].slice(5),
        slug = `${owner}/${repo}`,
        all = [`type:${options.type ?? 'task'}`, ...labels];
      for (const label of all) await ensure(slug, label);
      const url = await withBody(
        compose(await description(options, ctx), options.acceptance ?? ''),
        (file) =>
          text(['issue', 'create', '-R', slug, '-t', title, '-F', file, '-l', all.join(',')]),
      );
      const num = url.split('/').at(-1);
      if (!/^\d+$/.test(num)) fail(`gh issue create 실패 (${slug})`);
      const id = `${repo}#${num}`;
      if (options.parent) await parent(options.parent, id);
      const added = await gh(
        ['project', 'item-add', String(project), '--owner', owner, '--url', url],
        { allowFailure: true },
      );
      if (added.code !== 0) {
        let present = false;
        try {
          present = (await issueQuery(id, projectField)).projectItems.nodes.some(
            (item) => String(item.project.number) === String(project),
          );
        } catch {}
        if (!present)
          fail(
            `이슈 ${id} 은 만들었지만 Project ${project} 소속이 아니다 (item-add rc=${added.code}, 소속을 다시 읽어도 없다) — ${added.stderr?.toString() ?? ''}`,
          );
      }
      await syncIssue(id);
      ctx.out(options.silent ? id + '\n' : `✓ Created issue: ${id} — ${title}\n`);
      break;
    }
    case 'show': {
      const row = normalizeGithub(await issueQuery(args[0], fields));
      ctx.out(args.includes('--json') ? json([row]) : showText(row));
      break;
    }
    case 'children': {
      const node = await issueQuery(args[0], `subIssues(first:100){ nodes{ ${fields} } }`);
      const rows = [];
      for (const child of node.subIssues.nodes)
        rows.push(normalizeGithub(child.comments?.pageInfo?.hasNextPage ? await issueQuery(`${child.repository.name}#${child.number}`, fields) : child));
      ctx.out(args.includes('--json') ? json(rows) : rowsText(rows));
      break;
    }
    case 'list': {
      const rows = await list(listOptions(args));
      ctx.out(args.includes('--json') ? json(rows) : rowsText(rows));
      break;
    }
    case 'ready': {
      const options = listOptions(args);
      const rows = (await list({ ...options, status: 'open', limit: 0 })).filter((row) =>
        row.dependencies.every((dep) => dep.status === 'closed'),
      );
      const limited = options.limit ? rows.slice(0, options.limit) : rows;
      ctx.out(options.json ? json(limited) : rowsText(limited));
      break;
    }
    case 'note': {
      const id = args.shift(),
        { slug, num } = split(id);
      await gh(['issue', 'comment', num, '-R', slug, '-b', await noteBody(args, ctx)]);
      await syncIssue(id);
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
        const { slug, num } = split(id);
        const current = await issueQuery(id, 'state');
        if (current.state !== 'CLOSED')
          await gh(['issue', 'close', num, '-R', slug, ...(reason ? ['-c', reason] : [])]);
        await syncIssue(id);
        ctx.out(`✓ Closed ${id}\n`);
      }
      break;
    }
    case 'update': {
      const id = args.shift(),
        { slug, num } = split(id),
        options = updateOptions(args);
      if (options.claim && options.assignee !== undefined)
        fail('update: --claim 과 --assignee 는 같이 쓸 수 없다');
      if (options.claim) {
        await gh(['issue', 'edit', num, '-R', slug, '--add-assignee', '@me']);
        if (options.actor) {
          const raw = await issueQuery(id, fields), row = normalizeGithub(raw), record = rowRecord(row);
          record.execution = applyMarker(record.execution, `ACTOR: ${options.actor}`);
          await withBody(recordBody(raw.body ?? '', record), file => gh(['issue', 'edit', num, '-R', slug, '-F', file]));
        }
        options.status ||= 'in_progress';
      }
      if (options.assignee !== undefined) {
        const result = await read(
          ['api', '-X', 'PATCH', `repos/${slug}/issues/${num}`, '--input', '-'],
          {
            input: Buffer.from(
              JSON.stringify({ assignees: options.assignee ? [options.assignee] : [] }),
            ),
          },
        );
        if ((result.assignees?.[0]?.login ?? '').toLowerCase() !== options.assignee.toLowerCase())
          fail(`assignee 를 '${options.assignee}' 로 바꾸지 못했다: ${id}`);
      }
      if (options.status || options.type) {
        const labels = (
            await text([
              'issue',
              'view',
              num,
              '-R',
              slug,
              '--json',
              'labels',
              '--jq',
              '.labels[].name',
            ])
          )
            .split('\n')
            .filter(Boolean),
          edit = [];
        for (const label of labels)
          if (
            (options.status && label.startsWith('status:')) ||
            (options.type && label.startsWith('type:'))
          )
            edit.push('--remove-label', label);
        const added = [];
        if (options.status && !['open', 'closed'].includes(options.status))
          added.push('status:' + options.status);
        if (options.type) added.push('type:' + options.type);
        for (const label of added) {
          await ensure(slug, label);
          edit.push('--add-label', label);
        }
        if (edit.length) await gh(['issue', 'edit', num, '-R', slug, ...edit]);
        if (options.status === 'closed') await gh(['issue', 'close', num, '-R', slug]);
        else if (['open', 'in_progress', 'blocked', 'deferred'].includes(options.status))
          await gh(['issue', 'reopen', num, '-R', slug], { allowFailure: true });
      }
      if (options.parent) await parent(options.parent, id);
      if (
        options.acceptance !== undefined ||
        options.description !== undefined ||
        options.bodyFile !== undefined
      ) {
        const raw = await issueQuery(id, fields);
        const row = normalizeGithub(raw);
        const desc =
          options.description !== undefined || options.bodyFile !== undefined
            ? await description(options, ctx)
            : row.description;
        await withBody(preserveRecord(raw.body ?? '', compose(desc, options.acceptance ?? row.acceptance_criteria)), (file) =>
          gh(['issue', 'edit', num, '-R', slug, '-F', file]),
        );
      }
      if (options.status || options.type || options.claim || options.parent) await syncIssue(id);
      ctx.out(`✓ Updated issue: ${id}\n`);
      break;
    }
    case 'dep': {
      for (const [a, b] of await dependencyPairs(args, ctx)) {
        const target = split(b),
          source = split(a),
          bid = await text(['api', `repos/${target.slug}/issues/${target.num}`, '--jq', '.id']);
        await gh([
          'api',
          '-X',
          'POST',
          `repos/${source.slug}/issues/${source.num}/dependencies/blocked_by`,
          '-F',
          `issue_id=${bid}`,
        ]);
        ctx.out(`✓ Added dependency: ${a} blocked by ${b}\n`);
      }
      break;
    }
    case 'label': {
      const sub = args.shift(),
        label = args.pop();
      if (!['add', 'remove'].includes(sub) || !args.length || !label)
        fail('label: add|remove <id…> <라벨>');
      for (const id of args) {
        const { slug, num } = split(id);
        if (sub === 'add') await ensure(slug, label);
        await gh([
          'issue',
          'edit',
          num,
          '-R',
          slug,
          sub === 'add' ? '--add-label' : '--remove-label',
          label,
        ]);
        await syncIssue(id);
        ctx.out(
          `✓ ${sub === 'add' ? 'Added' : 'Removed'} label '${label}' ${sub === 'add' ? 'to' : 'from'} ${id}\n`,
        );
      }
      break;
    }
    case 'rails':
    case 'sprints':
    case 'sprint-add': {
      if (cmd !== 'sprint-add' && args.some((arg) => arg !== '--json')) fail(`${cmd}: 모르는 인자`);
      if (cmd === 'rails') {
        ctx.out(
          json(
            railsFrom(await list({ all: true, type: 'epic', pattern: 'rail:*', limit: 0 }), ctx),
          ),
        );
        break;
      }
      const { field } = await iteration();
      if (!field) fail('sprints: 첫 100개 안에 ITERATION 필드가 없다 — ledger.sh init 이 만든다');
      const config = field.configuration;
      if (cmd === 'sprints') {
        const rows = [
          ...(config.iterations ?? []).map((row) => ({ id: row.title, status: 'active' })),
          ...(config.completedIterations ?? []).map((row) => ({ id: row.title, status: 'closed' })),
        ].sort((a, b) => a.id.localeCompare(b.id));
        if (!rows.length)
          ctx.err('ledger-github: sprints: ITERATION 필드는 있는데 iteration 이 하나도 없다\n');
        ctx.out(json(rows));
        break;
      }
      const existing = [...(config.completedIterations ?? []), ...(config.iterations ?? [])]
        .map(({ title, startDate, duration }) => ({ title, startDate, duration }))
        .sort((a, b) => a.startDate.localeCompare(b.startDate));
      const duration =
          Number.isInteger(config.duration) && config.duration > 0 ? config.duration : 14,
        last = existing.at(-1),
        date = last ? new Date(last.startDate + 'T00:00:00Z') : new Date();
      if (last) date.setUTCDate(date.getUTCDate() + last.duration);
      const start = date.toISOString().slice(0, 10);
      const iterations = [...existing, { title: args[0], startDate: start, duration }];
      const q =
        'mutation($f:ID!,$d:Int!,$s:Date!,$it:[ProjectV2Iteration!]!){ updateProjectV2Field(input:{fieldId:$f, iterationConfiguration:{duration:$d, startDate:$s, iterations:$it}}){ projectV2Field { ... on ProjectV2IterationField { name } } } }';
      const result = await read(['api', 'graphql', '--input', '-'], {
        input: Buffer.from(
          JSON.stringify({
            query: q,
            variables: { f: field.id, d: duration, s: iterations[0].startDate, it: iterations },
          }),
        ),
      });
      if (!result.data?.updateProjectV2Field?.projectV2Field)
        fail('sprint-add: 뮤테이션이 200 을 냈지만 응답에 필드가 없다');
      ctx.out(
        `✓ 스프린트 등재: ${args[0]} (github: Projects v2 ${project} 의 ITERATION 필드에 iteration — 시작 ${start} · ${duration}일)\n`,
      );
      break;
    }
    default:
      fail(`'${cmd}' 는 github 백엔드에 없다 (beads 전용이거나 모르는 명령) — ledger.sh --help`);
  }
}
