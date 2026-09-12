import assert from 'node:assert/strict';
import { planProjectSetup, planProjectItem, githubProject, projectViews } from '../../plugins/harness/lib/ledger/github-project.mjs';
const fields = [
  { id: 'sprint', name: 'Sprint', dataType: 'ITERATION', configuration: { iterations: [{ id: 'i1', title: '2026-S01' }], completedIterations: [{ id: 'i0', title: '2026-S00' }] } },
  { id: 'status', name: 'Harness Status', dataType: 'SINGLE_SELECT', options: ['open', 'in_progress', 'blocked', 'deferred', 'closed', 'needs_decision'].map((name) => ({ name, id: name })) },
];
const snapshot = { id: 'project', fields, views: projectViews };
assert.equal(planProjectSetup({ fields: [], views: [] }).fields.length, 2);
assert.equal(planProjectSetup(snapshot).views.length, 0);
assert.equal(planProjectSetup({ ...snapshot, views: [{ ...projectViews[0], filter: 'custom' }] }).viewDrift.length, 1);
assert.throws(() => planProjectSetup({ fields: [{ name: 'Sprint', dataType: 'TEXT' }], views: [] }), /non-iteration/);
assert.throws(() => planProjectSetup({ fields: [...fields, fields[0]], views: [] }), /duplicate/);
const issue = { id: 'repo#1', labels: ['sprint:2026-S01'], status: 'in_progress' };
const item = { id: 'item', fieldValues: [] };
assert.deepEqual(planProjectItem(snapshot, item, issue).map((x) => x.value), [{ iterationId: 'i1' }, { singleSelectOptionId: 'in_progress' }]);
const populated = { ...item, fieldValues: [{ field: { id: 'sprint' }, iterationId: 'i1' }, { field: { id: 'status' }, optionId: 'in_progress' }] };
assert.deepEqual(planProjectItem(snapshot, populated, issue), []);
assert.deepEqual(planProjectItem(snapshot, populated, { ...issue, labels: [] }), [{ itemId: 'item', fieldId: 'sprint', value: null }]);
assert.equal(planProjectItem(snapshot, item, { ...issue, labels: ['sprint:2026-S00'] })[0].value.iterationId, 'i0');
assert.throws(() => planProjectItem(snapshot, item, { ...issue, labels: ['sprint:missing'] }), /registered/);
assert.throws(() => planProjectItem(snapshot, item, { ...issue, labels: ['sprint:a', 'sprint:b'] }), /multiple/);
assert.throws(() => planProjectItem(snapshot, item, { ...issue, status: 'unknown' }), /unsupported/);
// Transport boundary: numeric user ID, paged fields and views, no plan mutations.
const calls = [];
const command = async (_, args, extra = {}) => {
  calls.push({ args, extra });
  let data;
  if (args[1].startsWith('users/')) data = { id: 42, type: 'User' };
  else {
    const { query, variables } = JSON.parse(extra.input);
    assert.ok(!query.startsWith('mutation'));
    if (query.includes('user(login:')) data = { data: { user: { projectV2: { id: 'project' } } } };
    else if (query.includes('fields(first:')) data = { data: { node: { fields: { nodes: variables.after ? [fields[1]] : [fields[0]], pageInfo: { hasNextPage: !variables.after, endCursor: 'next' } } } } };
    else data = { data: { node: { views: { nodes: projectViews, pageInfo: { hasNextPage: false } } } } };
  }
  return { code: 0, stdout: JSON.stringify(data) };
};
const project = githubProject({ command, owner: 'example', number: 1 });
assert.equal((await project.setup()).fields.length, 0);
assert.equal(calls.length, 5);
assert.equal((await project.setup()).views.length, 0);
assert.equal(calls.filter((x) => x.args[1] === 'users/example').length, 1);
console.log('✓ github project setup/projection: offline contracts passed');
// Apply against an in-memory API; repeated setup/sync must issue zero new writes.
const remote = { fields: [], views: [], values: [], writes: [] };
const mutateCommand = async (_, args, extra = {}) => {
  const payload = extra.input ? JSON.parse(extra.input) : null;
  let response;
  if (args[1] === 'users/example') response = { id: 42, type: 'User' };
  else if (args[1].includes('/fields?')) response = [remote.fields.map((field, i) => ({ ...field, id: i + 1 }))];
  else if (args[1].endsWith('/views')) {
    assert.equal(args[1], 'users/example/projectsV2/1/views');
    remote.writes.push(payload); remote.views.push(payload); response = remote.views.length % 2 ? { id: remote.views.length } : { value: { id: remote.views.length } };
  } else {
    const { query, variables } = payload;
    let data;
    const page = (nodes) => ({ nodes, pageInfo: { hasNextPage: false } });
    if (query.includes('user(login:')) data = { user: { projectV2: { id: 'project' } } };
    else if (query.includes('createProjectV2Field(')) {
      remote.writes.push(variables.input);
      remote.fields.push(structuredClone(fields.find((field) => field.name === variables.input.name)));
      data = { createProjectV2Field: { projectV2Field: { id: remote.fields.at(-1).id } } };
    } else if (query.includes('fields(first:')) data = { node: { fields: page(remote.fields) } };
    else if (query.includes('views(first:')) data = { node: { views: page(remote.views) } };
    else if (query.includes('projectItems(first:')) data = { repository: { issue: { projectItems: page([{ id: 'item', project: { id: 'project' } }]) } } };
    else if (query.includes('fieldValues(first:')) data = { node: { fieldValues: page(remote.values) } };
    else if (query.includes('ProjectV2ItemFieldValue(')) {
      const input = variables.input; remote.writes.push(input);
      remote.values = remote.values.filter((value) => value.field.id !== input.fieldId);
      if (input.value) remote.values.push({ field: { id: input.fieldId }, ...(input.value.iterationId ? { iterationId: input.value.iterationId } : { optionId: input.value.singleSelectOptionId }) });
      const operation = input.value ? 'updateProjectV2ItemFieldValue' : 'clearProjectV2ItemFieldValue';
      data = { [operation]: { projectV2Item: { id: 'item' } } };
    } else throw new Error(query);
    response = { data };
  }
  return { code: 0, stdout: JSON.stringify(response) };
};
const writable = githubProject({ command: mutateCommand, owner: 'example', number: 1 });
assert.match((await writable.sync(issue, { apply: true })).skipped, /not initialized/);
await writable.setup({ apply: true });
assert.equal(remote.writes.length, 6);
await writable.setup({ apply: true });
assert.equal(remote.writes.length, 6);
assert.equal(remote.views.find((view) => view.layout === 'board').vertical_group_by.length, 1);
await writable.sync(issue, { apply: true });
assert.equal(remote.writes.length, 8);
await writable.sync(issue, { apply: true });
assert.equal(remote.writes.length, 8);
await writable.sync({ ...issue, labels: [], status: 'closed' }, { apply: true });
assert.equal(remote.values.length, 1);
assert.equal(remote.values[0].optionId, 'closed');
console.log('✓ github project apply: retries, user endpoint, board grouping, label removal and closed status passed');

assert.equal(planProjectItem(snapshot, item, { ...issue, notes: 'progress\nDECISION_NEEDED: choose\n' }).at(-1).value.singleSelectOptionId, 'needs_decision');
assert.equal(planProjectItem(snapshot, item, { ...issue, notes: 'DECISION_NEEDED: choose\nresolved' }).at(-1).value.singleSelectOptionId, 'in_progress');
assert.equal(planProjectItem(snapshot, item, { ...issue, events: 'DECISION_NEEDED: choose', notes: 'DECISION_NEEDED: choose\nVERIFY_PENDING: abc' }).at(-1).value.singleSelectOptionId, 'needs_decision');
function bulkFixture() {
  const rows = Array.from({ length: 101 }, (_, i) => ({ id: `repo#${i + 1}`, labels: [], status: 'open' }));
  const stored = rows.map((_, i) => ({ id: `item${i}`, content: { number: i + 1, repository: { name: 'repo', owner: { login: 'example' } } }, values: [] }));
  const stats = { mutations: 0, itemPages: 0, continuations: 0, partialError: false, missingAlias: false };
  const page = (nodes, more = false, cursor = null) => ({ nodes, pageInfo: { hasNextPage: more, endCursor: cursor } });
  const run = async (_, args, extra = {}) => {
    if (args[1] === 'users/example') return { code: 0, stdout: JSON.stringify({ id: 42, type: 'User' }) };
    const { query, variables } = JSON.parse(extra.input);
    let data;
    if (query.includes('user(login:')) data = { user: { projectV2: { id: 'project' } } };
    else if (query.includes('fields(first:')) data = { node: { fields: page(fields) } };
    else if (query.includes('views(first:')) data = { node: { views: page(projectViews) } };
    else if (query.includes('items(first:')) {
      stats.itemPages++;
      const selected = variables.after ? stored.slice(100) : stored.slice(0, 100);
      data = { node: { items: page(selected.map((item) => ({ ...item, fieldValues: item.id === 'item0' ? page([], true, 'field-next') : page(item.values) })), !variables.after, variables.after ? null : 'next') } };
    } else if (query.includes('fieldValues(first:100')) {
      stats.continuations++;
      assert.equal(variables.after, 'field-next');
      data = { node: { fieldValues: page(stored[0].values) } };
    } else if (query.startsWith('mutation(')) {
      stats.mutations++; data = {};
      const entries = Object.entries(variables);
      assert.ok(entries.length <= 10);
      for (const [key, input] of entries) {
        const item = stored.find((item) => item.id === input.itemId);
        item.values = item.values.filter((value) => value.field.id !== input.fieldId);
        if (input.value) item.values.push({ field: { id: input.fieldId }, optionId: input.value.singleSelectOptionId });
        data[key.replace('v', 'm')] = { projectV2Item: { id: item.id } };
        if (stats.partialError) {
          stats.partialError = false;
          return { code: 0, stdout: JSON.stringify({ data, errors: [{ message: 'partial write failure' }] }) };
        }
      }
      if (stats.missingAlias) { stats.missingAlias = false; delete data.m0; }
    } else throw new Error(query);
    return { code: 0, stdout: JSON.stringify({ data }) };
  };
  return { client: githubProject({ command: run, owner: 'example', number: 1 }), rows, stats };
}
const bulk = bulkFixture();
assert.equal((await bulk.client.syncAll(bulk.rows)).flatMap((r) => r.changes).length, 101);
assert.equal(bulk.stats.mutations, 0);
assert.equal(bulk.stats.itemPages, 2);
assert.equal(bulk.stats.continuations, 1);
await bulk.client.syncAll(bulk.rows, { apply: true });
assert.equal(bulk.stats.mutations, 11);
assert.equal((await bulk.client.syncAll(bulk.rows, { apply: true })).flatMap((r) => r.changes).length, 0);
assert.equal(bulk.stats.mutations, 11);
const partial = bulkFixture(); partial.stats.partialError = true;
await assert.rejects(partial.client.syncAll(partial.rows, { apply: true }), /partial write failure/);
await partial.client.syncAll(partial.rows, { apply: true });
assert.equal((await partial.client.syncAll(partial.rows)).flatMap((r) => r.changes).length, 0);
const omitted = bulkFixture(); omitted.stats.missingAlias = true;
await assert.rejects(omitted.client.syncAll(omitted.rows, { apply: true }), /no matching item/);
console.log('✓ github project bulk: pagination, nested continuation, batches, convergence, no-op and partial failures passed');
