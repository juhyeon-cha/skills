import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import { auditClaude, summarize } from '../lib/transcript.mjs';
import { decodeClaude } from '../lib/transcripts/claude.mjs';
import { workflowScope, auditWorkflow } from '../lib/runtime/workflow.mjs';

function selfCheck() {
  const invocation = {
    type: 'assistant',
    message: {
      content: [
        { type: 'tool_use', id: 'call', name: 'Agent', input: { subagent_type: 'evaluator' } },
      ],
    },
  };
  const result = {
    type: 'user',
    message: { content: [{ type: 'tool_result', tool_use_id: 'call' }] },
    toolUseResult: { agentId: 'child', agentType: 'evaluator', status: 'completed' },
  };
  const audit = (text, async = false) => {
    const parent = [
      invocation,
      {
        ...result,
        toolUseResult: { ...result.toolUseResult, status: async ? 'async_launched' : 'completed' },
      },
    ];
    if (async)
      parent.push({
        type: 'user',
        message: {
          content:
            '<task-notification><task-id>child</task-id><status>completed</status></task-notification>',
        },
      });
    const decoded = decodeClaude(
      parent,
      () => [
        {
          type: 'assistant',
          attributionAgent: 'evaluator',
          message: { content: [{ type: 'text', text }] },
        },
      ],
      'fixture',
    );
    return summarize(decoded.calls, decoded.errors);
  };
  const clean = 'SIGNAL: MATCH\n근거';
  const dirty = '판정을 정리한다.\n' + clean;
  assert.notEqual(clean, dirty);
  assert.equal(audit(clean).rc, 0);
  assert.equal(audit(dirty).rc, 1);
  assert.equal(audit(dirty, true).rc, 1);
  assert.equal(summarize([]).rc, 2);
  const mixed = decodeClaude([invocation], () => [], 'fixture');
  assert.equal(
    summarize([
      ...decodeClaude(
        [invocation, result],
        () => [
          {
            type: 'assistant',
            attributionAgent: 'evaluator',
            message: { content: [{ type: 'text', text: clean }] },
          },
        ],
        'fixture',
      ).calls,
      ...mixed.calls,
    ]).rc,
    2,
  );
  console.log(
    'PASS transcript self-check: clean/dirty A9, async notification, empty and mixed unfinished controls',
  );
}

try {
  const options = { projects: path.join(os.homedir(), '.claude/projects') };
  const args = process.argv.slice(2);
  for (let index = 0; index < args.length; index++) {
    const key = args[index];
    if (['--projects', '--since', '--session', '--scope'].includes(key)) {
      const value = args[++index];
      if (!value || value.startsWith('--')) throw new Error(`${key} value missing`);
      options[key.slice(2)] = value;
    } else if (key === '--json') options.json = true;
    else if (key === '--self-check') options.self = true;
    else if (key === '--help' || key === '-h') options.help = true;
    else throw new Error(`unsupported argument ${key}`);
  }
  if (options.help)
    console.log(
      'transcript-check.sh [--projects DIR] [--session UUID] [--since ISO8601|Nd|Nh] [--json] | --scope scope.json [--json] | --self-check',
    );
  else if (options.self) selfCheck();
  else {
    if (options.scope && (options.session || options.since || args.includes('--projects')))
      throw new Error('scope inventory cannot be combined with Claude directory filters');
    const report = options.scope
      ? auditWorkflow(await workflowScope(JSON.parse(fs.readFileSync(options.scope))))
      : auditClaude(options);
    for (const reason of report.unreached) console.error(`UNREACHED: ${reason}`);
    console.log(
      options.json
        ? JSON.stringify(report, null, 2)
        : `${report.status}: required=${report.population}, judged=${report.judged}, unreached=${report.unreached.length}; aggregates=${report.complete ? 'complete' : 'partial'}\n${JSON.stringify(report)}`,
    );
    process.exitCode = report.rc;
  }
} catch (error) {
  console.error(`UNREACHED: ${error.message}`);
  console.log(
    JSON.stringify({ status: 'UNREACHED', complete: false, unreached: [error.message], rc: 2 }),
  );
  process.exitCode = 2;
}
