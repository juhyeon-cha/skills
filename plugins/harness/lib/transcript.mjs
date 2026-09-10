import fs from 'node:fs';
import path from 'node:path';
import { loadRole } from './roles.mjs';
import { roleNames } from './role-identities.mjs';
import { records, tokens } from './transcripts/common.mjs';
import { decodeClaude } from './transcripts/claude.mjs';

export function summarize(calls, errors = [], root) {
  const vocab = Object.fromEntries(roleNames.map((role) => [role, loadRole(role, root).signals]));
  const report = {
    version: 1,
    population: calls.length,
    judged: 0,
    unreached: [...errors],
    observations: [],
    signals: {},
    tools: {},
    tokens: { roles: {} },
    reuse: { multi_signal_transcripts: 0, combos: {} },
    a9: { verdicts: { OK: 0, NO_SIGNAL: 0, BAD_VALUE: 0, EMPTY: 0 }, violations: [] },
    vocab,
  };
  for (const role of roleNames) {
    report.signals[role] = {};
    report.tools[role] = {
      calls: 0,
      responses_with_tools: 0,
      calls_per_response: null,
      parallel_responses: 0,
      max_per_response: 0,
      top: {},
    };
    report.tokens.roles[role] = tokens(
      calls
        .filter((call) => call.role === role)
        .flatMap((call) =>
          (call.messages ?? []).map((message) => ({
            ...message,
            id: message.id && `${call.id}:${message.id}`,
          })),
        ),
    );
    if (
      errors.length ||
      calls.some((call) => call.role === role && (!call.completed || call.reason))
    ) {
      report.tokens.roles[role].status = 'UNKNOWN';
      report.tokens.roles[role].total = null;
    }
  }
  for (const call of calls) {
    const reason =
      call.reason ??
      (!vocab[call.role]
        ? 'role unidentified'
        : !call.completed
          ? 'required invocation unfinished'
          : null);
    if (reason) {
      report.unreached.push(`${call.id}: ${reason}`);
      report.observations.push({ id: call.id, task: call.task, status: 'UNREACHED', reason });
      continue;
    }
    const texts = call.texts ?? [];
    const head = texts.at(-1)?.split(/\r?\n/)[0];
    const signal = /^SIGNAL: ([A-Z_]+)$/.exec(head ?? '')?.[1];
    const verdict = !texts.length
      ? 'EMPTY'
      : !signal
        ? 'NO_SIGNAL'
        : !vocab[call.role].includes(signal)
          ? 'BAD_VALUE'
          : 'OK';
    report.judged++;
    report.a9.verdicts[verdict]++;
    report.observations.push({
      id: call.id,
      task: call.task,
      role: call.role,
      agentId: call.agentId,
      status: verdict === 'OK' ? 'REACHED' : 'VIOLATION',
      verdict,
    });
    if (verdict !== 'OK')
      report.a9.violations.push({ role: call.role, agent_id: call.agentId, kind: verdict });
    const sigs = texts
      .map((text) => /^SIGNAL: ([A-Z_]+)(?:\r?\n|$)/.exec(text)?.[1])
      .filter(Boolean);
    for (const value of sigs)
      report.signals[call.role][value] = (report.signals[call.role][value] ?? 0) + 1;
    if (sigs.length > 1) {
      report.reuse.multi_signal_transcripts++;
      const key = sigs.join(',');
      report.reuse.combos[key] = (report.reuse.combos[key] ?? 0) + 1;
    }
    const grouped = new Map();
    const target = report.tools[call.role];
    for (const message of call.messages ?? []) {
      const tools = message.tools ?? [];
      if (!tools.length) continue;
      const key = message.id ?? message.index;
      grouped.set(key, (grouped.get(key) ?? 0) + tools.length);
      for (const tool of tools) target.top[tool] = (target.top[tool] ?? 0) + 1;
    }
    for (const n of grouped.values()) {
      target.calls += n;
      target.responses_with_tools++;
      target.parallel_responses += Number(n > 1);
      target.max_per_response = Math.max(target.max_per_response, n);
    }
    target.calls_per_response = target.responses_with_tools
      ? target.calls / target.responses_with_tools
      : null;
  }
  for (const role of roleNames) {
    const own = calls.filter((call) => call.role === role);
    const complete =
      !errors.length &&
      own.length > 0 &&
      own.every((call) => call.completed && !call.reason && call.toolsMeasured !== false);
    const observed = report.tools[role];
    report.tools[role] = complete
      ? { status: 'KNOWN', ...observed }
      : {
          status: 'UNKNOWN',
          calls: null,
          responses_with_tools: null,
          calls_per_response: null,
          parallel_responses: null,
          max_per_response: null,
          top: null,
          observed_partial: observed,
        };
  }
  if (!calls.length) report.unreached.push('required invocation inventory empty or missing');
  report.complete = report.unreached.length === 0;
  report.rc = !report.complete ? 2 : report.a9.violations.length ? 1 : 0;
  report.status = report.rc === 2 ? 'UNREACHED' : report.rc === 1 ? 'VIOLATION' : 'REACHED';
  return report;
}

export function sinceTime(raw) {
  if (!raw) return null;
  const relative = /^(\d+)([dh])$/.exec(raw);
  const time = relative
    ? Date.now() - Number(relative[1]) * (relative[2] === 'd' ? 86400000 : 3600000)
    : Date.parse(raw);
  if (!Number.isFinite(time)) throw new Error('invalid --since');
  return time;
}

export function auditClaude({ projects, session, since }, root) {
  const calls = [];
  const errors = [];
  const threshold = sinceTime(since);
  if (session && !/^[A-Za-z0-9_-]+$/.test(session))
    throw new Error('invalid Claude session filter');
  const dirs = fs
    .readdirSync(projects, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => path.join(projects, entry.name));
  for (const directory of dirs) {
    for (const file of fs
      .readdirSync(directory)
      .filter((name) => name.endsWith('.jsonl') && (!session || name === session + '.jsonl'))) {
      const id = file.slice(0, -6);
      try {
        const decoded = decodeClaude(
          records(path.join(directory, file)),
          (agent) => {
            if (!/^[A-Za-z0-9_-]+$/.test(agent))
              throw new Error('unsupported Claude agent identifier');
            const candidates = dirs
              .map((dir) => path.join(dir, id, 'subagents', `agent-${agent}.jsonl`))
              .filter((candidate) => fs.existsSync(candidate));
            if (candidates.length !== 1) throw new Error('child transcript missing/ambiguous');
            return records(candidates[0]);
          },
          id,
        );
        errors.push(...decoded.errors.map((error) => `${id}: ${error}`));
        for (const call of decoded.calls) {
          // Incomplete calls cannot disappear behind an end-time filter.
          if (threshold !== null && call.completed && Date.parse(call.timestamp) < threshold)
            continue;
          if (threshold !== null && !Number.isFinite(Date.parse(call.timestamp)))
            call.reason ??= 'timestamp missing for requested window';
          calls.push({ ...call, id: `${id}:${call.id}` });
        }
      } catch (error) {
        errors.push(`${id}: ${error.message}`);
      }
    }
  }
  return {
    ...summarize(calls, errors, root),
    format: 'claude-code-2.1-jsonl',
    projects,
    session: session ?? null,
    since: since ?? null,
  };
}
