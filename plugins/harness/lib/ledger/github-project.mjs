// One-way projection: issue labels/state remain authoritative. No issue writes here.
const STATUS = ['open', 'in_progress', 'blocked', 'deferred', 'closed', 'needs_decision'];
const STATUS_FIELD = 'Harness Status';
const FIELD_SELECTION = `__typename ... on ProjectV2FieldCommon { id name dataType }
  ... on ProjectV2SingleSelectField { options { id name } }
  ... on ProjectV2IterationField { configuration { iterations { id title } completedIterations { id title } } }`;
export const projectViews = [
  { name: '현재 스프린트', layout: 'table', filter: 'is:issue label:"type:epic" Sprint:@current' },
  { name: '백로그', layout: 'table', filter: 'is:issue is:open label:"type:epic" no:Sprint' },
  { name: '실행', layout: 'board', filter: 'is:issue label:"type:task" Sprint:@current' },
  { name: '판단 필요', layout: 'table', filter: 'is:issue is:open harness-status:blocked,needs_decision' },
];
const check = (condition, message) => { if (!condition) throw new Error(`github project: ${message}`); };
function oneNamed(rows, name) {
  const matches = rows.filter((row) => row.name === name);
  check(matches.length < 2, `duplicate field '${name}' — resolve ambiguity first`);
  return matches[0];
}
export function planProjectSetup(snapshot) {
  const fields = [];
  const sprint = oneNamed(snapshot.fields, 'Sprint');
  check(!sprint || sprint.dataType === 'ITERATION', "'Sprint' exists with a non-iteration type");
  if (!sprint) fields.push({ name: 'Sprint', dataType: 'ITERATION' });
  const status = oneNamed(snapshot.fields, STATUS_FIELD);
  check(!status || status.dataType === 'SINGLE_SELECT', `'${STATUS_FIELD}' must be SINGLE_SELECT`);
  if (status) for (const name of STATUS)
    check(status.options?.some((option) => option.name === name), `'${STATUS_FIELD}' lacks '${name}' — existing options preserved`);
  else fields.push({ name: STATUS_FIELD, dataType: 'SINGLE_SELECT', singleSelectOptions: STATUS.map((name) => ({ name, color: 'GRAY', description: `Ledger status: ${name}` })) });
  return {
    fields,
    views: projectViews.filter((view) => !snapshot.views.some((existing) => existing.name === view.name)),
    preservedViews: snapshot.views.map((view) => view.name),
    viewDrift: projectViews.flatMap((view) => snapshot.views.filter((existing) => existing.name === view.name && (existing.filter !== view.filter || existing.layout.toLowerCase().replace(/_layout$/, '') !== view.layout)).map((existing) => ({ name: view.name, existing, suggested: view }))),
    limitations: ['Existing views are preserved, including same-name custom filters.', 'Default tab order and nested hierarchy presentation require the GitHub UI.', 'Sprint:@current follows iteration dates; a sprint label must match an existing iteration title.'],
  };
}
export function planProjectItem(snapshot, item, issue) {
  const sprint = oneNamed(snapshot.fields, 'Sprint'), status = oneNamed(snapshot.fields, STATUS_FIELD);
  check(sprint?.dataType === 'ITERATION' && status?.dataType === 'SINGLE_SELECT', 'run project setup before synchronization');
  const labels = issue.labels.map((label) => typeof label === 'string' ? label : label.name);
  const sprints = labels.filter((label) => label.startsWith('sprint:')).map((label) => label.slice(7));
  check(sprints.length <= 1, `${issue.id}: multiple sprint labels`);
  const iterations = [...(sprint.configuration?.iterations ?? []), ...(sprint.configuration?.completedIterations ?? [])];
  const matches = iterations.filter((iteration) => iteration.title === sprints[0]);
  check(!sprints.length || matches.length === 1, `${issue.id}: sprint '${sprints[0]}' must match exactly one registered iteration`);
  const lastNote = (issue.events ?? issue.notes ?? '').split('\n').map((line) => line.trim()).filter(Boolean).at(-1) ?? '';
  const projectedStatus = issue.status !== 'closed' && (issue.issue_type === 'decision' || labels.includes('type:decision') || lastNote.startsWith('DECISION_NEEDED')) ? 'needs_decision' : issue.status;
  const option = status.options.find((entry) => entry.name === projectedStatus);
  check(option, `${issue.id}: unsupported status '${issue.status}'`);
  const desired = [
    { fieldId: sprint.id, value: sprints.length ? { iterationId: matches[0].id } : null },
    { fieldId: status.id, value: { singleSelectOptionId: option.id } },
  ];
  return desired.filter(({ fieldId, value }) => {
    const current = item.fieldValues.find((field) => field.field?.id === fieldId);
    return value === null ? Boolean(current) : Object.entries(value).some(([key, val]) => (key === 'singleSelectOptionId' ? current?.optionId : current?.[key]) !== val);
  }).map((change) => ({ ...change, itemId: item.id }));
}
export function githubProject({ command, owner, number }) {
  check(owner && Number.isInteger(Number(number)) && Number(number) > 0, 'owner and project number required');
  const request = async (args, body) => {
    const response = await command('gh', args, body === undefined ? {} : { input: Buffer.from(JSON.stringify(body)) });
    check(response.code === 0, response.stderr?.toString() || 'gh request failed');
    return JSON.parse(response.stdout.toString());
  };
  const graphql = async (query, variables) => {
    const response = await request(['api', 'graphql', '--input', '-'], { query, variables });
    check(!response.errors?.length, JSON.stringify(response.errors));
    check(response.data, 'GraphQL response has no data');
    return response.data;
  };
  let identity;
  const identify = async () => {
    if (!identity) {
      const account = await request(['api', `users/${encodeURIComponent(owner)}`]);
      check(['User', 'Organization'].includes(account.type) && account.id, 'unsupported owner response');
      const kind = account.type === 'Organization' ? 'organization' : 'user';
      const data = await graphql(`query($owner:String!,$number:Int!){ ${kind}(login:$owner){ projectV2(number:$number){id} } }`, { owner, number: Number(number) });
      const id = data[kind]?.projectV2?.id;
      check(id, 'project not found');
      identity = { id, rest: account.type === 'Organization' ? `orgs/${encodeURIComponent(owner)}/projectsV2/${number}` : `users/${encodeURIComponent(owner)}/projectsV2/${number}` };
    }
    return identity;
  };
  const connection = async (id, field, selection) => {
    let after = null; const rows = [], seen = new Set();
    do {
      const data = await graphql(`query($id:ID!,$after:String){node(id:$id){... on ProjectV2{${field}(first:100,after:$after){nodes{${selection}} pageInfo{hasNextPage endCursor}}}}}`, { id, after });
      const page = data.node?.[field];
      check(Array.isArray(page?.nodes) && page.pageInfo, `invalid ${field} page`);
      rows.push(...page.nodes.filter(Boolean));
      if (!page.pageInfo.hasNextPage) break;
      after = page.pageInfo.endCursor;
      check(after && !seen.has(after), `invalid ${field} pagination cursor`);
      seen.add(after);
    } while (true);
    return rows;
  };
  let cachedSnapshot;
  const inspect = async () => {
    const { id } = await identify();
    cachedSnapshot = { id, fields: await connection(id, 'fields', FIELD_SELECTION), views: await connection(id, 'views', 'id name layout filter') };
    return cachedSnapshot;
  };
  const setup = async ({ apply = false } = {}) => {
    const snapshot = await inspect(), plan = planProjectSetup(snapshot);
    if (!apply) return plan;
    // Re-read before each operation so interrupted/repeated setup is safe.
    for (const field of plan.fields) {
      if (oneNamed((await inspect()).fields, field.name)) continue;
      await graphql('mutation($input:CreateProjectV2FieldInput!){createProjectV2Field(input:$input){projectV2Field{... on ProjectV2FieldCommon{id}}}}', { input: { projectId: snapshot.id, ...field } });
    }
    const { rest } = await identify();
    for (const view of plan.views) {
      if ((await inspect()).views.some((existing) => existing.name === view.name)) continue;
      const pages = await request(['api', `${rest}/fields?per_page=100`, '--paginate', '--slurp', '-H', 'X-GitHub-Api-Version: 2026-03-10']);
      check(Array.isArray(pages) && pages.every(Array.isArray), 'invalid REST fields pages');
      const fields = pages.flat(), status = fields.find((field) => field.name === STATUS_FIELD);
      check(Number.isInteger(status?.id), 'REST status field ID unavailable');
      const visible = fields.filter((field) => ['Title', 'Assignees', 'Sprint', STATUS_FIELD, 'Parent issue', 'Sub-issues progress'].includes(field.name)).map((field) => field.id);
      const response = await request(['api', `${rest}/views`, '-X', 'POST', '-H', 'X-GitHub-Api-Version: 2026-03-10', '--input', '-'], { ...view, visible_fields: visible, ...(view.layout === 'board' ? { vertical_group_by: [status.id] } : {}) });
      check(response.value?.id ?? response.id, 'view creation returned no ID; inspect permissions/API support before retrying');
    }
    const remaining = planProjectSetup(await inspect());
    check(!remaining.fields.length && !remaining.views.length, 'setup did not converge');
    return { ...plan, applied: true };
  };
  const sync = async (issue, { apply = false } = {}) => {
    const snapshot = cachedSnapshot ?? await inspect();
    if (!snapshot.fields.some((field) => field.name === STATUS_FIELD) || !snapshot.fields.some((field) => field.name === 'Sprint'))
      return { issue: issue.id, changes: [], applied: false, skipped: 'Project projection is not initialized; run project-setup --apply.' };
    const match = /^([^#]+)#([0-9]+)$/.exec(issue.id);
    check(match, 'issue id must be repo#number');
    let item, membershipAfter = null; const membershipCursors = new Set();
    do {
      const data = await graphql('query($owner:String!,$repo:String!,$number:Int!,$after:String){repository(owner:$owner,name:$repo){issue(number:$number){projectItems(first:100,after:$after){nodes{id project{id}} pageInfo{hasNextPage endCursor}}}}}', { owner, repo: match[1], number: Number(match[2]), after: membershipAfter });
      const page = data.repository?.issue?.projectItems;
      check(Array.isArray(page?.nodes) && page.pageInfo, 'invalid issue project membership');
      item = page.nodes.find((entry) => entry?.project?.id === snapshot.id);
      if (item || !page.pageInfo.hasNextPage) break;
      membershipAfter = page.pageInfo.endCursor;
      check(membershipAfter && !membershipCursors.has(membershipAfter), 'invalid membership cursor'); membershipCursors.add(membershipAfter);
    } while (true);
    check(item, `${issue.id}: not in configured project`);
    // Read all values independently: nested pagination must not silently truncate.
    let after = null; const values = [], cursors = new Set();
    do {
      const data = await graphql('query($id:ID!,$after:String){node(id:$id){... on ProjectV2Item{fieldValues(first:100,after:$after){nodes{... on ProjectV2ItemFieldSingleSelectValue{optionId field{... on ProjectV2FieldCommon{id}}} ... on ProjectV2ItemFieldIterationValue{iterationId field{... on ProjectV2FieldCommon{id}}}} pageInfo{hasNextPage endCursor}}}}}', { id: item.id, after });
      const page = data.node?.fieldValues;
      check(Array.isArray(page?.nodes) && page.pageInfo, 'invalid item field values');
      values.push(...page.nodes.filter(Boolean));
      if (!page.pageInfo.hasNextPage) break;
      after = page.pageInfo.endCursor; check(after && !cursors.has(after), 'invalid field value cursor'); cursors.add(after);
    } while (true);
    const changes = planProjectItem(snapshot, { ...item, fieldValues: values }, issue);
    if (apply) for (const change of changes) {
      const { value, ...ids } = change;
      const mutation = value ? 'updateProjectV2ItemFieldValue' : 'clearProjectV2ItemFieldValue';
      const inputType = value ? 'UpdateProjectV2ItemFieldValueInput' : 'ClearProjectV2ItemFieldValueInput';
      const data = await graphql(`mutation($input:${inputType}!){${mutation}(input:$input){projectV2Item{id}}}`, { input: { projectId: snapshot.id, ...ids, ...(value ? { value } : {}) } });
      check(data[mutation]?.projectV2Item?.id === item.id, 'field mutation returned no matching item');
    }
    return { issue: issue.id, changes, applied: apply };
  };
  const valueSelection = '... on ProjectV2ItemFieldSingleSelectValue{optionId field{... on ProjectV2FieldCommon{id}}} ... on ProjectV2ItemFieldIterationValue{iterationId field{... on ProjectV2FieldCommon{id}}}';
  const bulkItems = async (projectId) => {
    const items = await connection(projectId, 'items', `id content{... on Issue{number repository{name owner{login}}}} fieldValues(first:20){nodes{${valueSelection}} pageInfo{hasNextPage endCursor}}`);
    const byIssue = new Map();
    for (const item of items) {
      if (!item.content?.repository || item.content.repository.owner.login.toLowerCase() !== owner.toLowerCase()) continue;
      const id = `${item.content.repository.name}#${item.content.number}`;
      check(!byIssue.has(id), `${id}: duplicate project membership`);
      let page = item.fieldValues;
      check(Array.isArray(page?.nodes) && page.pageInfo, 'invalid nested field values');
      const values = page.nodes.filter(Boolean), cursors = new Set();
      while (page.pageInfo.hasNextPage) {
        const after = page.pageInfo.endCursor;
        check(after && !cursors.has(after), 'invalid nested field cursor'); cursors.add(after);
        const data = await graphql(`query($id:ID!,$after:String){node(id:$id){... on ProjectV2Item{fieldValues(first:100,after:$after){nodes{${valueSelection}} pageInfo{hasNextPage endCursor}}}}}`, { id: item.id, after });
        page = data.node?.fieldValues;
        check(Array.isArray(page?.nodes) && page.pageInfo, 'invalid nested field values continuation');
        values.push(...page.nodes.filter(Boolean));
      }
      byIssue.set(id, { id: item.id, fieldValues: values });
    }
    return byIssue;
  };
  const syncAll = async (issues, { apply = false } = {}) => {
    const snapshot = cachedSnapshot ?? await inspect();
    if (!snapshot.fields.some((field) => field.name === STATUS_FIELD) || !snapshot.fields.some((field) => field.name === 'Sprint'))
      return issues.map((issue) => ({ issue: issue.id, changes: [], applied: false, skipped: 'Project projection is not initialized; run project-setup --apply.' }));
    const plan = (items) => issues.map((issue) => {
      const item = items.get(issue.id);
      check(item, `${issue.id}: not in configured project`);
      return { issue: issue.id, changes: planProjectItem(snapshot, item, issue), applied: apply };
    });
    const results = plan(await bulkItems(snapshot.id));
    if (!apply) return results;
    const changes = results.flatMap((result) => result.changes);
    for (let start = 0; start < changes.length; start += 10) {
      const batch = changes.slice(start, start + 10), variables = {};
      const definitions = [], selections = [];
      batch.forEach(({ value, ...ids }, i) => {
        const type = value ? 'UpdateProjectV2ItemFieldValueInput' : 'ClearProjectV2ItemFieldValueInput';
        const mutation = value ? 'updateProjectV2ItemFieldValue' : 'clearProjectV2ItemFieldValue';
        definitions.push(`$v${i}:${type}!`);
        selections.push(`m${i}:${mutation}(input:$v${i}){projectV2Item{id}}`);
        variables[`v${i}`] = { projectId: snapshot.id, ...ids, ...(value ? { value } : {}) };
      });
      // An error may follow earlier successful aliases. Surface it and let a rerun
      // re-read actual values; never replay an assumed all-or-nothing batch.
      const data = await graphql(`mutation(${definitions.join(',')}){${selections.join(' ')}}`, variables);
      batch.forEach((change, i) => check(data[`m${i}`]?.projectV2Item?.id === change.itemId, `batch field mutation m${i} returned no matching item`));
    }
    if (changes.length) {
      const remaining = plan(await bulkItems(snapshot.id));
      check(remaining.every((result) => !result.changes.length), 'bulk projection did not converge; re-read and retry synchronization');
    }
    return results;
  };
  return { inspect, setup, sync, syncAll };
}
