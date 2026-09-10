#!/usr/bin/env node
import path from 'node:path';
import {
  consumerContext,
  ledgerIndex,
  ancestors,
  labels,
  lastMarker,
  cliOptions,
  isMain,
  cli,
} from '../lib/ledger-view.mjs';
import { inspectWorkspace } from '../lib/workspace.mjs';
import { worktreeName } from '../lib/worktree-name.mjs';

export function judgeR5(rows, byId = ledgerIndex(rows)) {
  const covered = rows.filter(
    (row) =>
      row.issue_type === 'task' &&
      ancestors(row, byId, 16).some((item) => item.issue_type === 'epic'),
  );
  return {
    covered: covered.length,
    errors: covered
      .filter((row) => labels(row, 'repo:').length !== 1)
      .map(
        (row) =>
          `R5 ${row.id} — repo: 라벨이 ${labels(row, 'repo:').length}개다 (정확히 1개여야 한다)`,
      ),
  };
}
export function judgeAcceptance(rows) {
  const covered = rows.filter((row) => row.issue_type === 'task' && row.status === 'in_progress');
  return {
    covered: covered.length,
    errors: covered
      .filter((row) => !(row.acceptance_criteria ?? '').trim())
      .map((row) => `R-ACC ${row.id} — acceptance 없이 착수됐다 (${row.title ?? ''})`),
  };
}
// The adapter's actor is the session claim, whereas a GitHub assignee is a
// login shared by several sessions. Legacy beads/notion claims use assignee.
const actor = (row) => row.actor || row.assignee || `(미지정)${row.id}`;
export function judgeS22(rows, { repo, worktrees }, byId = ledgerIndex(rows)) {
  const groups = new Map(),
    messages = [],
    errors = [];
  for (const row of rows) {
    if (
      row.issue_type !== 'task' ||
      row.status !== 'in_progress' ||
      lastMarker(row).startsWith('VERIFY_PENDING')
    )
      continue;
    const epic = ancestors(row, byId, 16).find((item) => item.issue_type === 'epic');
    if (!epic) continue;
    const ownRepo = labels(row, 'repo:')[0] ?? '(없음)',
      key = JSON.stringify([epic.id, ownRepo]);
    if (!groups.has(key)) groups.set(key, { story: epic.id, repo: ownRepo, tasks: [] });
    groups.get(key).tasks.push(row);
  }
  for (const group of groups.values()) {
    if (group.tasks.length < 2) continue;
    const ids = group.tasks
        .map((row) => row.id)
        .sort()
        .join(','),
      lanes = new Set(group.tasks.map(actor)).size;
    if (group.repo !== repo) {
      messages.push(
        `S22 ${group.story} (repo:${group.repo}) — 이 레포('${repo}')가 아니라 판정하지 않는다 — 그 레포의 클론에서 게이트를 돌려라: ${ids}`,
      );
      continue;
    }
    const count = worktrees(group.story);
    if (!Number.isSafeInteger(count) || count < 0) throw new Error('S22 작업 트리 계수 미가용');
    const text = `S22 ${group.story} (repo:${repo}) — 동시 in_progress ${group.tasks.length}건 · actor ${lanes}명 / 워크트리 ${count}개: ${ids}`;
    if (lanes >= 2 && lanes > count) errors.push(text);
    else messages.push(text + ' (공유 확정 아님)');
  }
  return {
    errors,
    messages,
    covered: rows.filter((row) => row.issue_type === 'epic').length,
    tasks: rows.filter((row) => row.issue_type === 'task' && row.status === 'in_progress').length,
    pending: rows.filter(
      (row) =>
        row.issue_type === 'task' &&
        row.status === 'in_progress' &&
        lastMarker(row).startsWith('VERIFY_PENDING'),
    ).length,
  };
}
export function judgeS24(rows, byId = ledgerIndex(rows)) {
  const epics = rows.filter((row) => row.issue_type === 'epic'),
    errors = [];
  let covered = 0;
  for (const epic of epics) {
    const descendants = rows.filter(
      (row) => row.id !== epic.id && ancestors(row, byId).some((item) => item.id === epic.id),
    );
    if (!descendants.length) continue;
    covered++;
    if (
      ['open', 'in_progress'].includes(epic.status) &&
      descendants.every((row) => ['closed', 'blocked', 'deferred'].includes(row.status))
    )
      errors.push(
        `S24 ${epic.id} — 하위 ${descendants.length}건이 전부 closed·blocked·deferred 인데 스토리가 ${epic.status} 다`,
      );
  }
  return { covered, errors };
}

// The production check exercises both polarities before considering real data.
// Removing a rule or marker/actor derivation must not turn it into a green check.
export function selfControls() {
  const base = [
    { id: 'fx-s', issue_type: 'epic', status: 'in_progress' },
    ...['a', 'b'].map((id) => ({
      id,
      issue_type: 'task',
      status: 'in_progress',
      parent: 'fx-s',
      labels: ['repo:fixture'],
      acceptance_criteria: 'run fixture',
    })),
  ];
  const modify = (fn) =>
    structuredClone(base).map((row) => (row.issue_type === 'task' ? fn(row) : row));
  const scope = { repo: 'fixture', worktrees: () => 0 };
  const expect = (value, message) => {
    if (!value) throw new Error(`자기 시험 실패: ${message}`);
  };
  expect(
    judgeR5(base).errors.length === 0 &&
      judgeR5(modify((row) => ({ ...row, labels: [] }))).errors.length === 2,
    'R5 대상/라벨 파생',
  );
  expect(
    judgeAcceptance(base).errors.length === 0 &&
      judgeAcceptance(modify((row) => ({ ...row, acceptance_criteria: ' \r\n' }))).errors.length ===
        2,
    'R-ACC 착수/acceptance 파생',
  );
  expect(judgeS22(base, scope).errors.length === 1, 'S22 부정 대조군');
  expect(
    judgeS22(
      modify((row) => ({ ...row, notes: 'VERIFY_PENDING: 0000000\n산문 기록' })),
      scope,
    ).errors.length === 0,
    'S22 표시 도달',
  );
  expect(
    judgeS22(
      modify((row) => ({ ...row, assignee: 'same' })),
      scope,
    ).errors.length === 0,
    'S22 같은 actor 한 레인',
  );
  expect(
    judgeS22(
      modify((row) => ({ ...row, assignee: 'same-login', actor: row.id })),
      scope,
    ).errors.length === 1,
    'S22 GitHub 서로 다른 actor',
  );
  expect(
    judgeS22(
      modify((row) => ({ ...row, labels: [`repo:${row.id}`] })),
      scope,
    ).errors.length === 0,
    'S22 레포 분리',
  );
  expect(
    judgeS24(base).errors.length === 0 &&
      judgeS24(modify((row) => ({ ...row, status: 'deferred' }))).errors.length === 1,
    'S24 종료 하위 도달',
  );
  return 8;
}

export async function registeredStoryWorktrees(root, { env = process.env } = {}) {
  const identity = await inspectWorkspace(root, { env }),
    usable = [];
  for (const registration of identity.registrations) {
    if (registration.worktree === identity.main || registration.bare || registration.prunable)
      continue;
    // A stale registration or a directory falling through to its parent does
    // not count. Confirm the exact registered tree, including external paths.
    try {
      const actual = await inspectWorkspace(registration.worktree, { env });
      if (actual.linked && actual.common === identity.common) usable.push(actual);
    } catch {
      /* absent/unusable worktrees provide no independent index */
    }
  }
  return {
    repo: path.basename(identity.main),
    worktrees: (story) => {
      const name = worktreeName(story),
        branch = `worktree-${name}`;
      return usable.filter((row) => row.branch === branch || row.branch.startsWith(branch + '-'))
        .length;
    },
  };
}
export async function checkRules(options = {}) {
  selfControls();
  const context = await consumerContext(options),
    rows = await context.array(['list', '--all', '--json', '-n', '0']);
  const byId = ledgerIndex(rows),
    scope = await registeredStoryWorktrees(context.root, { env: context.env });
  const r5 = judgeR5(rows, byId),
    acc = judgeAcceptance(rows),
    s22 = judgeS22(rows, scope, byId),
    s24 = judgeS24(rows, byId);
  const errors = [...r5.errors, ...acc.errors, ...s22.errors, ...s24.errors];
  const output = [
    `원장 루트: ${context.root}`,
    ...errors.map((line) => `✗ ${line}`),
    ...s22.messages.map((line) => `  · ${line}`),
  ];
  if (!r5.errors.length) output.push(`✓ R5 태스크 repo: 라벨 정확히 1개 (대상 ${r5.covered}건)`);
  if (!acc.errors.length)
    output.push(`✓ R-ACC 착수된 태스크 ${acc.covered}건 전부 acceptance 있음`);
  if (!s22.errors.length)
    output.push(
      `✓ S22 동시 actor 수가 워크트리 수를 넘는 (스토리, 레포) 없음 (스토리 ${s22.covered}건 · in_progress 태스크 ${s22.tasks}건, 그중 검증 대기 ${s22.pending}건은 세지 않음 · 같은 actor 는 한 레인)`,
    );
  if (!s24.errors.length)
    output.push(
      `✓ S24 하위가 전부 종료 상태인데 열려 있는 스토리 없음 (하위를 가진 스토리 ${s24.covered}건)`,
    );
  return { code: errors.length ? 1 : 0, stdout: output.join('\n') + '\n' };
}
if (isMain(import.meta.url))
  await cli(() => {
    const { args, root } = cliOptions(process.argv.slice(2));
    if (args.length) throw new Error('사용법: rules-check.mjs [--root <root>]');
    return checkRules({ root });
  });
