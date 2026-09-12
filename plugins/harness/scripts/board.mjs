#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import {
  consumerContext,
  ledgerIndex,
  ancestors,
  labels,
  registry,
  cliOptions,
  isMain,
  cli,
} from '../lib/ledger-view.mjs';

const glyph = (status) =>
  ({ open: '○', in_progress: '◐', blocked: '●', closed: '✓', deferred: '❄', pinned: '📌' })[
    status
  ] ?? status;
const cell = (value) => String(value ?? '').replaceAll('|', '\\|');
const text = (value) =>
  value == null
    ? ''
    : typeof value === 'string'
      ? value.replace(/\n+$/, '')
      : JSON.stringify(value);
const label = (row, prefix) => labels(row, prefix).join(', ');
const detail = (title, body) =>
  body ? `\n<details><summary>${title}</summary>\n\n${body}\n\n</details>\n` : '';
const notes = (row) => detail('기록 (bd notes)', text(row.notes)) +
  Object.entries(row.summaries ?? {}).map(([section, body]) => detail(`결과 · ${section}`, text(body))).join('');
// Match the previous dotted-ID numeric segment order, without locale-dependent
// collation (so the same snapshot emits identical bytes on every host).
const compare = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
export function naturalId(a, b) {
  const parts = (value) =>
    value.split('.').map((part) => (/^-?\d+(?:e[+-]?\d+)?$/i.test(part) ? Number(part) : part));
  const left = parts(a),
    right = parts(b);
  for (let i = 0; i < Math.min(left.length, right.length); i++) {
    if (typeof left[i] !== typeof right[i]) return typeof left[i] === 'number' ? -1 : 1;
    const order = compare(left[i], right[i]);
    if (order) return order;
  }
  return left.length - right.length;
}
function targetMode(target) {
  if (['all', 'backlog', 'adr'].includes(target)) return target;
  if (/^\d{4}-S\d{2}$/.test(target)) return 'sprint';
  throw new Error(
    `대상 형식 위반: '${target}' (스프린트 ID 는 YYYY-SNN, 백로그는 backlog, 결정 기록은 adr)`,
  );
}

export function renderDocuments(target, rows, rails = [], sprints = []) {
  const mode = targetMode(target),
    byId = ledgerIndex(rows);
  if (mode === 'all') throw new Error('renderDocuments는 개별 대상을 받는다');
  if (mode !== 'adr') registry(rails, 'rails');
  const selected =
    mode === 'adr'
      ? rows.filter((row) => row.issue_type === 'decision')
      : rows.filter(
          (row) =>
            row.issue_type === 'epic' &&
            (mode === 'backlog'
              ? row.status !== 'closed' && !labels(row, 'sprint:').length
              : labels(row, 'sprint:').includes(target)),
        );
  if (mode === 'sprint' && !selected.length) {
    registry(sprints, 'sprints');
    const status = sprints.find((row) => row.id === target)?.status;
    if (status !== 'closed')
      throw new Error(
        `sprint:${target} 라벨이 붙은 스토리(epic)가 없다 (스프린트 등록부의 status: ${status ?? '등재 없음'} — 닫힌 스프린트만 0건이 통과다)`,
      );
  }
  const selectedIds = new Set(selected.map((row) => row.id));
  const population =
    mode === 'adr'
      ? selected
      : rows.filter((row) => ancestors(row, byId, 8).some((item) => selectedIds.has(item.id)));
  const children = (id) =>
    population.filter((row) => row.parent === id).sort((a, b) => naturalId(a.id, b.id));
  const seen = new Set();
  for (const row of selected) {
    const slug = label(row, 'slug:');
    if (!slug)
      throw new Error(
        `${row.issue_type === 'decision' ? '결정' : '스토리'} ${row.id} 에 slug: 라벨이 없다`,
      );
    if (!/^[a-z0-9][a-z0-9-]*$/.test(slug))
      throw new Error(`슬러그 형식 위반: '${slug}' (${row.id})`);
    if (seen.has(slug))
      throw new Error(`슬러그 충돌: ${target} 안에 slug 가 중복된 bead 가 있다 — ${slug}`);
    seen.add(slug);
  }
  const front = mode === 'sprint' ? `sprint: ${target}` : `${mode}: true`;
  const title =
    mode === 'sprint' ? `스프린트 ${target}` : mode === 'backlog' ? '백로그' : '결정 기록 (ADR)';
  // Keep the legacy generated header for byte-stable re-render/rollback.
  const header = `<!-- bd 생성 문서. 직접 수정 금지 — bd 로 수정 후 scripts/board.sh ${target} 재실행 -->`;
  const document = (fields, body) => `---\n${fields.join('\n')}\n---\n${header}\n\n${body}`;
  let index = document(
    [front],
    `# ${title}\n\n${mode === 'adr' ? '| 결정 | bead | 상태 | 대체한 결정 | 제목 |\n|---|---|---|---|---|\n' : '| 스토리 | bead | 레일 | 담당 | 상태 | 레포 | 제목 |\n|---|---|---|---|---|---|---|\n'}`,
  );
  const files = new Map();
  for (const row of selected.sort((a, b) => compare(a.id, b.id))) {
    const slug = label(row, 'slug:'),
      status = text(row.status),
      rowTitle = text(row.title),
      description = text(row.description);
    if (mode === 'adr') {
      if (row.dependencies != null && !Array.isArray(row.dependencies))
        throw new Error(`dependencies 형식: ${row.id}`);
      const sup = (row.dependencies ?? [])
        .filter((dep) => dep.type === 'supersedes')
        .map((dep) => dep.depends_on_id)
        .join(', ');
      index += `| [${slug}](${slug}.md) | ${row.id} | ${glyph(status)} ${status} | ${sup || '-'} | ${cell(rowTitle)} |\n`;
      let body = `# ${glyph(status)} ${rowTitle}\n`;
      if (sup) body += `\n> 대체됨 — 이 결정을 대신하는 bead: ${sup}\n`;
      if (description) body += `\n${description}\n`;
      files.set(
        `${slug}.md`,
        document(
          [
            `decision: ${row.id}`,
            front,
            `status: ${status}`,
            `slug: ${slug}`,
            ...(sup ? [`superseded_by: ${sup}`] : []),
          ],
          body + notes(row),
        ),
      );
      continue;
    }
    const rail = label(row, 'rail:'),
      repos = label(row, 'repo:'),
      owner = rails.find((item) => item.id === rail)?.owner;
    if (!rail) throw new Error(`스토리 ${row.id} 에 rail: 라벨이 없다`);
    if (!owner)
      throw new Error(`레일 '${rail}' 이 등록부에 없거나 owner 를 낼 수 없다 (스토리 ${row.id})`);
    index += `| [${slug}](${slug}/index.md) | ${row.id} | ${cell(rail)} | ${cell(owner)} | ${glyph(status)} ${status} | ${cell(repos)} | ${cell(rowTitle)} |\n`;
    let body = `# ${glyph(status)} ${rowTitle}\n`;
    if (description) body += `\n## 설명\n\n${description}\n`;
    body += '\n## 마일스톤\n\n| 마일스톤 | bead | 상태 | 제목 |\n|---|---|---|---|\n';
    let n = 0;
    for (const milestone of children(row.id)) {
      n++;
      const ms = text(milestone.status),
        mt = text(milestone.title),
        md = text(milestone.description);
      body += `| [M${n}](M${n}.md) | ${milestone.id} | ${glyph(ms)} ${ms} | ${cell(mt)} |\n`;
      let milestoneBody = `# ${glyph(ms)} M${n} — ${mt}\n\n스토리: [${row.id}](index.md)\n`;
      if (md) milestoneBody += `\n${md}\n`;
      milestoneBody += '\n## 태스크\n';
      for (const task of children(milestone.id)) {
        const ts = text(task.status),
          acceptance = text(task.acceptance_criteria),
          reason = text(task.close_reason);
        milestoneBody += `\n### ${glyph(ts)} ${task.id} — ${text(task.title)}\n\n- 상태: ${ts}\n`;
        if (acceptance) milestoneBody += `- acceptance: ${acceptance}\n`;
        if (reason) {
          const [first, ...rest] = reason.split('\n');
          milestoneBody += `- 종료 근거: ${first}\n`;
          if (rest.length) milestoneBody += detail('종료 근거 전문', rest.join('\n'));
        }
        milestoneBody += notes(task);
      }
      files.set(
        `${slug}/M${n}.md`,
        document(
          [`milestone: ${milestone.id}`, `story: ${row.id}`, front, `status: ${ms}`],
          milestoneBody,
        ),
      );
    }
    files.set(
      `${slug}/index.md`,
      document(
        [
          `story: ${row.id}`,
          front,
          `status: ${status}`,
          `rail: ${rail}`,
          `owner: ${owner}`,
          `slug: ${slug}`,
          `repos: [${repos}]`,
        ],
        body + notes(row),
      ),
    );
  }
  files.set('index.md', index);
  return files;
}

async function publish(root, target, files) {
  // Projections must remain inside the target root, including when a docs
  // ancestor is a symlink/junction. Validate each existing ancestor before
  // creating its child, then use canonical paths for publication.
  const canonicalRoot = await fs.realpath(root);
  let parent = canonicalRoot;
  for (const component of ['docs', ...(targetMode(target) === 'sprint' ? ['sprints'] : [])]) {
    const next = path.join(parent, component);
    try {
      parent = await fs.realpath(next);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      try {
        await fs.mkdir(next);
      } catch (createError) {
        if (createError.code !== 'EEXIST') throw createError;
      }
      parent = await fs.realpath(next);
    }
    if (!parent.startsWith(canonicalRoot + path.sep))
      throw new Error('투영 경로가 하네스 루트 밖이다');
  }
  const lock = path.join(parent, `.render-lock-${target}`),
    destination = path.join(parent, target);
  try {
    await fs.mkdir(lock);
  } catch (error) {
    if (error.code === 'EEXIST')
      throw new Error(
        `오류: ${target} 렌더가 이미 진행 중이다 (${lock} 존재). 비정상 종료 잔존물이면 확인 후 정리하라`,
      );
    throw error;
  }
  let temporary;
  try {
    for (const name of await fs.readdir(parent))
      if (name.startsWith(`.render-${target}.`))
        await fs.rm(path.join(parent, name), { recursive: true, force: true });
    temporary = await fs.mkdtemp(path.join(parent, `.render-${target}.`));
    for (const [relative, contents] of files) {
      const file = path.join(temporary, relative);
      await fs.mkdir(path.dirname(file), { recursive: true });
      await fs.writeFile(file, contents);
    }
    // As in the legacy renderer, readers may see a brief absent destination,
    // never a partially rendered tree. Lock prevents concurrent publishers.
    await fs.rm(destination, { recursive: true, force: true });
    await fs.rename(temporary, destination);
    temporary = undefined;
    return destination;
  } finally {
    if (temporary) await fs.rm(temporary, { recursive: true, force: true });
    await fs.rmdir(lock);
  }
}
export async function renderBoard(target, options = {}) {
  const mode = targetMode(target),
    context = await consumerContext(options);
  const ui = (await context.text(['has-ui'])).trim();
  if (ui)
    return {
      code: 0,
      stdout: `board.sh: '${target}' 를 그리지 않았다 — 이 백엔드는 자기 UI(${ui})를 갖는다. docs/sprints/·docs/backlog/·docs/adr/ 아래 파일을 만들지도 지우지도 않았다 (원장이 SSOT 이고 이 트리는 그 투영이라, UI 가 있으면 중복이다)\n`,
    };
  const rows = await context.array(['list', '--all', '--json', '-n', '0']);
  const sprints =
    mode === 'all' || mode === 'sprint'
      ? registry(await context.array(['sprints', '--json']), 'sprints')
      : [];
  const rails = mode === 'adr' ? [] : registry(await context.array(['rails', '--json']), 'rails');
  const targets = mode === 'all' ? [...sprints.map((row) => row.id), 'backlog', 'adr'] : [target];
  // Validate all requested documents before replacing any existing projection.
  const renders = targets.map((name) => [name, renderDocuments(name, rows, rails, sprints)]),
    locations = [];
  for (const [name, files] of renders) locations.push(await publish(context.root, name, files));
  return { code: 0, stdout: locations.join('\n') + '\n' };
}
if (isMain(import.meta.url))
  await cli(() => {
    const { args, root } = cliOptions(process.argv.slice(2));
    if (args.length !== 1)
      throw new Error('사용법: board.mjs [--root <root>] <YYYY-SNN|backlog|adr|all>');
    return renderBoard(args[0], { root });
  });
