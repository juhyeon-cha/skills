import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawn, spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {decodeClaude} from '../../plugins/harness/lib/transcripts/claude.mjs';
import {decodeCodex, codexOutcome} from '../../plugins/harness/lib/transcripts/codex.mjs';
import {summarize, auditClaude} from '../../plugins/harness/lib/transcript.mjs';
import {registerRoles, loadRole} from '../../plugins/harness/lib/roles.mjs';
import {recordStateEvent} from '../../plugins/harness/lib/state.mjs';
import {workflowScope, beginWorkflow, completeWorkflow, auditWorkflow} from '../../plugins/harness/lib/workflow.mjs';

const root = fileURLToPath(new URL('../../plugins/harness', import.meta.url));
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'transcript-contract-'));
const env = {...process.env, HOME: temp, HARNESS_DATA_DIR: path.join(temp, '상태 data'), GIT_CONFIG_GLOBAL: os.devNull, GIT_CONFIG_NOSYSTEM: '1'};
for (const key of ['CLAUDE_PLUGIN_ROOT', 'CLAUDE_PLUGIN_DATA', 'PLUGIN_ROOT', 'PLUGIN_DATA', 'HARNESS_RUNTIME', 'HARNESS_DOCTOR_DIR']) delete env[key];
const run = (command, args) => spawnSync(command, args, {env, cwd: temp, encoding: 'utf8'});
const jsonl = (file, rows) => { fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, rows.map(row => JSON.stringify(row)).join('\n') + '\n'); };
let n = 0; const check = (value, reason) => { assert.ok(value, reason); n++; };
const invoke = (id = 'call', role = 'evaluator') => ({type: 'assistant', sessionId: 'session', timestamp: '2026-08-28T00:00:00Z', message: {content: [{type: 'tool_use', id, name: 'Agent', input: {subagent_type: role}}]}});
const returned = (id = 'call', agentId = 'child', status = 'completed') => ({type: 'user', sessionId: 'session', timestamp: '2026-08-28T00:01:00Z', message: {content: [{type: 'tool_result', tool_use_id: id}]}, toolUseResult: {agentId, status}});
const child = (text = 'SIGNAL: MATCH', role = 'evaluator', usage) => [{type: 'assistant', attributionAgent: role, message: {id: 'message', usage, content: [{type: 'tool_use', name: 'Bash'}, {type: 'text', text}]}}];
const audit = (parents = [invoke(), returned()], children = child()) => { const decoded = decodeClaude(parents, () => children, 'session'); return summarize(decoded.calls, decoded.errors); };
try {
  check(audit().rc === 0, 'Claude completed A9 reached');
  check(audit().tokens.roles.evaluator.status === 'UNKNOWN' && audit().tokens.roles.evaluator.total === null, 'missing tokens are unknown, independently of SIGNAL');
  for (const role of ['implementer', 'reviewer', 'evaluator']) for (const signal of loadRole(role).signals) check(audit([invoke('call', role), returned()], child(`SIGNAL: ${signal}`, role)).rc === 0, 'source-owned A9 vocabulary ' + role + ':' + signal);
  check(audit(undefined, child('summary\nSIGNAL: MATCH')).rc === 1, 'negative A9 summary before SIGNAL');
  check(audit(undefined, child('\nSIGNAL: MATCH')).rc === 1, 'first line is exact');
  check(audit(undefined, child('SIGNAL: INVENTED')).rc === 1, 'unknown SIGNAL is A9 violation');
  check(audit(undefined, []).a9.verdicts.EMPTY === 1, 'empty response');
  check(audit([invoke(), returned('call', 'child', 'async_launched'), {type: 'user', message: {content: '<task-notification><task-id>child</task-id><status>completed</status></task-notification>'}}], child('summary\nSIGNAL: MATCH')).rc === 1, 'asynchronous A9 negative control');
  check(audit([invoke()]).rc === 2, 'unfinished invocation retained');
  check(audit([returned()]).rc === 2, 'completion alone is not population');
  check(audit([invoke('call', 'unknown'), returned()], child('SIGNAL: MATCH', 'unknown')).rc === 2, 'unknown role');
  check(audit([invoke('call', 'unknown'), returned()], child()).rc === 2, 'unknown invocation is not repaired by a different child role');
  check(audit([invoke(), returned(), invoke('pending')]).rc === 2, 'normal plus pending is not success');
  check(audit(undefined, [...child(), {type: 'future-record'}]).rc === 2, 'unsupported child format retained');
  const usage = {input_tokens: 2, output_tokens: 3, cache_creation_input_tokens: 0, cache_read_input_tokens: 4};
  const split = [...child('SIGNAL: MATCH', 'evaluator', usage), ...child('SIGNAL: MATCH', 'evaluator', usage)];
  const measured = audit(undefined, split);
  check(measured.tokens.roles.evaluator.total.input_tokens === 2 && measured.tools.evaluator.parallel_responses === 1, 'message identity deduplicates tokens and groups parallel calls');
  const project = path.join(temp, 'projects/p'); jsonl(path.join(project, 'session.jsonl'), [invoke(), returned()]);
  const transcript = path.join(project, 'session/subagents/agent-child.jsonl'); jsonl(transcript, child());
  check(auditClaude({projects: path.dirname(project), session: 'session'}).rc === 0, 'legacy directory/session CLI source');
  check(auditClaude({projects: path.dirname(project), session: 'other'}).rc === 2, 'missing session not empty success');
  check(auditClaude({projects: path.dirname(project), since: '2099-01-01'}).rc === 2, 'time filter has no reached calls');
  fs.appendFileSync(transcript, '{partial'); check(auditClaude({projects: path.dirname(project)}).rc === 2, 'malformed JSON tail is unreached');
  fs.rmSync(transcript); check(auditClaude({projects: path.dirname(project)}).rc === 2, 'missing transcript is unreached');
  const codexRows = (agent = 'native-child', signal = 'SIGNAL: LGTM') => [
    {type: 'thread.started', thread_id: 'session'},
    {type: 'item.completed', item: {id: 'spawn', type: 'collab_tool_call', tool: 'spawn_agent', sender_thread_id: 'parent', receiver_thread_ids: [agent], status: 'completed'}},
    {type: 'item.completed', item: {id: 'wait', type: 'collab_tool_call', tool: 'wait', sender_thread_id: 'parent', receiver_thread_ids: [agent], agents_states: {[agent]: {status: 'completed', message: signal}}, status: 'completed'}}
  ];
  const request = {callId: 'required', role: 'reviewer', task: 'fixture', message: 'Read assigned fixture', sessionId: 'session', parentAgentId: 'parent', implementerIds: ['author'], previousAgentIds: []};
  check(codexOutcome(decodeCodex(codexRows(), 'session'), {...request, nativeCallId: 'spawn'}).agentId === 'native-child', 'Codex explicit exec JSONL completion fixture');
  assert.throws(() => codexOutcome(decodeCodex([{type: 'session_meta', payload: {id: 'session'}}], 'session'), request)); n++;
  assert.throws(() => codexOutcome(decodeCodex(codexRows().slice(0, 2), 'session'), {...request, nativeCallId: 'spawn'})); n++;
  const emptyWait = codexRows(); emptyWait[2].item.receiver_thread_ids = []; emptyWait[2].item.agents_states = {};
  assert.throws(() => codexOutcome(decodeCodex(emptyWait, 'session'), {...request, nativeCallId: 'spawn'})); n++;
  const fakePrompt = [{type: 'thread.started', thread_id: 'session'}, {type: 'item.completed', item: {id: 'message', type: 'agent_message', text: 'harness-reviewer SIGNAL: LGTM'}}];
  assert.throws(() => codexOutcome(decodeCodex(fakePrompt, 'session'), {...request, nativeCallId: 'spawn'})); n++;
  const repo = path.join(temp, 'repo'); fs.mkdirSync(repo); check(run('git', ['init', '-q', repo]).status === 0, 'isolated Git fixture');
  fs.writeFileSync(path.join(repo, 'README'), 'fixture'); run('git', ['-C', repo, 'add', '.']); check(run('git', ['-C', repo, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture']).status === 0, 'Git identity ready');
  const registration = registerRoles('codex', path.join(temp, 'agents'), root);
  const metadata = {runtime: 'codex', repository: repo, sessionId: 'session', data: env.HARNESS_DATA_DIR};
  const scope = await workflowScope(metadata, env);
  const event = async (type, agent = 'native-child', text = 'SIGNAL: LGTM', role = 'harness-reviewer') => recordStateEvent({hook_event_name: type, cwd: repo, session_id: 'session', agent_id: agent, agent_type: role, tool_name: 'Bash', last_assistant_message: text}, 0, {...env, HARNESS_RUNTIME: 'codex'});
  const chain = async (agent = 'native-child', text = 'SIGNAL: LGTM') => { await event('SubagentStart', agent); await event('PreToolUse', agent); await event('SubagentStop', agent, text); };
  const native = agentId => ({nativeCallId: 'actual-tool-call-' + agentId, sessionId: 'session', parentAgentId: 'parent', identifier: 'harness-reviewer', agentId, state: 'completed', result: 'SIGNAL: LGTM'});
  check(auditWorkflow(scope).rc === 2, 'no call inventory never means no required delegation');
  beginWorkflow(scope, registration, request);
  check(auditWorkflow(scope).rc === 2, 'persisted call with no events/outcome is visible');
  await chain(); check(completeWorkflow(scope, registration, request.callId, native('native-child')).status === 'REACHED', 'ordinary native outcome uses persisted event chain without transcript');
  check(auditWorkflow(scope).rc === 0 && auditWorkflow(scope).tokens.roles.reviewer.status === 'UNKNOWN', 'ordinary result consumed without token invention');
  check(auditWorkflow(scope).tools.reviewer.status === 'UNKNOWN' && auditWorkflow(scope).tools.reviewer.calls === null, 'native result metadata cannot fabricate zero tool calls');
  beginWorkflow(scope, registration, {...request, callId: 'late'});
  check(completeWorkflow(scope, registration, 'late', native('native-child')).status === 'UNREACHED', 'late inventory cannot reuse historical completed event chain');
  check(auditWorkflow(scope).rc === 2 && auditWorkflow(scope).judged === 1, 'normal plus unreached result preserves both');
  beginWorkflow(scope, registration, {...request, callId: 'self'}); await chain('author');
  check(completeWorkflow(scope, registration, 'self', native('author')).status === 'UNREACHED', 'self judgment rejected by shared roleResult');
  beginWorkflow(scope, registration, {...request, callId: 'interrupted'}); await chain('interrupted');
  check(completeWorkflow(scope, registration, 'interrupted', {...native('interrupted'), state: 'running'}).status === 'UNREACHED', 'native wait not completed');
  const capture = path.join(temp, 'capture.jsonl');
  beginWorkflow(scope, registration, {...request, callId: 'captured'}, {format: 'codex-exec-0.153-jsonl', file: capture});
  jsonl(capture, codexRows('captured')); await chain('captured');
  check(completeWorkflow(scope, registration, 'captured', 'spawn').status === 'REACHED', 'optional exec adapter produces same role outcome contract');
  beginWorkflow(scope, registration, {...request, callId: 'old-capture'}, {format: 'codex-exec-0.153-jsonl', file: capture}); await chain('captured');
  check(completeWorkflow(scope, registration, 'old-capture', 'spawn').status === 'UNREACHED', 'capture boundary rejects preexisting native completion');
  beginWorkflow(scope, registration, {...request, callId: 'changed-history'}, {format: 'codex-exec-0.153-jsonl', file: capture});
  jsonl(capture, codexRows('replacement')); await chain('replacement');
  check(completeWorkflow(scope, registration, 'changed-history', 'spawn').reason.includes('history changed'), 'rewritten capture prefix cannot become new native evidence');
  beginWorkflow(scope, registration, {...request, callId: 'parallel-a'}); beginWorkflow(scope, registration, {...request, callId: 'parallel-b'});
  await chain('parallel');
  check(completeWorkflow(scope, registration, 'parallel-a', native('parallel')).status === 'REACHED', 'first concurrent inventory owns native result');
  check(completeWorkflow(scope, registration, 'parallel-b', native('parallel')).reason.includes('already assigned'), 'same native result cannot satisfy concurrent inventory twice');
  for (const [id, expected] of [['bad-signal', /SIGNAL/], ['missing-stop', /chain/], ['wrong-role', /role identity/], ['reused', /reused/]]) {
    beginWorkflow(scope, registration, {...request, callId: id, previousAgentIds: id === 'reused' ? [id] : []});
    if (id === 'bad-signal') await chain(id, 'SIGNAL: INVENTED');
    else if (id === 'missing-stop') { await event('SubagentStart', id); await event('PreToolUse', id); }
    else if (id === 'wrong-role') { await chain(id); await event('SubagentStop', id, 'SIGNAL: LGTM', 'mystery'); }
    else await chain(id);
    const result = completeWorkflow(scope, registration, id, native(id));
    check(result.status === 'UNREACHED' && expected.test(result.reason), 'shared role result negative control: ' + id);
  }
  const scopeFile = path.join(temp, 'scope.json'); fs.writeFileSync(scopeFile, JSON.stringify(metadata));
  const registrationFile = path.join(temp, 'registration.json'); fs.writeFileSync(registrationFile, JSON.stringify(registration));
  const nativeFile = path.join(temp, 'native.json'); fs.writeFileSync(nativeFile, JSON.stringify(native('racing')));
  beginWorkflow(scope, registration, {...request, callId: 'race-a'}); beginWorkflow(scope, registration, {...request, callId: 'race-b'}); await chain('racing');
  const race = await Promise.all(['race-a', 'race-b'].map(id => new Promise((resolve, reject) => {
    const process = spawn(globalThis.process.execPath, [path.join(root, 'scripts/workflow.mjs'), 'complete-native', scopeFile, registrationFile, id, nativeFile], {env, cwd: temp});
    process.on('error', reject); process.stdout.resume(); process.stderr.resume(); process.on('exit', resolve);
  })));
  check(race.sort().join(',') === '0,2', 'two actual completion processes cannot double-assign one native instance');
  const claudeScope = await workflowScope({...metadata, runtime: 'claude'}, env);
  const claudeRegistration = registerRoles('claude', undefined, root);
  const claudeCapture = path.join(temp, 'claude-capture.jsonl'); const childDirectory = path.join(temp, 'children');
  beginWorkflow(claudeScope, claudeRegistration, {...request, role: 'evaluator', callId: 'claude-capture'}, {format: 'claude-code-2.1-jsonl', file: claudeCapture, children: childDirectory});
  jsonl(claudeCapture, [invoke(), returned()]); jsonl(path.join(childDirectory, 'agent-child.jsonl'), child());
  for (const type of ['SubagentStart', 'PreToolUse', 'SubagentStop']) await recordStateEvent({hook_event_name: type, cwd: repo, session_id: 'session', agent_id: 'child', agent_type: 'harness:evaluator', tool_name: 'Bash', last_assistant_message: 'SIGNAL: MATCH'}, 0, {...env, HARNESS_RUNTIME: 'claude'});
  check(completeWorkflow(claudeScope, claudeRegistration, 'claude-capture', 'call').status === 'REACHED', 'optional Claude capture connects native invocation to common role result');
  check(run('bash', [path.join(root, 'checks/transcript-check.sh'), '--self-check']).status === 0, 'existing self-check entry retains A9 negative controls');
  const cli = run('bash', [path.join(root, 'checks/transcript-check.sh'), '--scope', scopeFile, '--json']);
  check(cli.status === 2 && JSON.parse(cli.stdout).population === 15, 'retrospective CLI consumes complete required inventory including failures');
  console.log(`PASS transcript: ${n} assertions; offline Claude/Codex and common native outcome fixtures; remote writes 0`);
} finally { fs.rmSync(temp, {recursive: true, force: true}); }
