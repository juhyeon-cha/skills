import { spawn } from 'node:child_process';
import readline from 'node:readline';

export const codexThreadId = (value) =>
  typeof value === 'string' && /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(value);

/** Read metadata through the versioned App Server protocol, never rollout parsing.
 * No thread/start, resume, turn, or model request is made. */
export function readCodexThread(threadId, { env = process.env, spawnProcess = spawn } = {}) {
  if (!codexThreadId(threadId)) throw new Error('Codex thread ID invalid');
  return new Promise((resolve, reject) => {
    const proc = spawnProcess('codex', ['app-server'], { env, stdio: ['pipe', 'pipe', 'pipe'] });
    let settled = false;
    let bytes = 0;
    let initialized = false;
    const finish = (error, result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      proc.kill();
      if (error) reject(error); else resolve(result);
    };
    const timer = setTimeout(() => finish(new Error('Codex thread/read timed out')), 8000);
    const send = (value) => proc.stdin.write(JSON.stringify(value) + '\n');
    proc.on('error', () => finish(new Error('Codex App Server unavailable')));
    proc.on('exit', () => finish(new Error('Codex thread/read ended without response')));
    proc.stdin.on('error', () => finish(new Error('Codex App Server input closed')));
    proc.stderr.resume();
    proc.stdout.on('data', (chunk) => {
      bytes += chunk.length;
      if (bytes > 1024 * 1024) finish(new Error('Codex thread/read response too large'));
    });
    readline.createInterface({ input: proc.stdout }).on('line', (line) => {
      if (settled) return;
      try {
        const message = JSON.parse(line);
        if (message.id === 1) {
          if (initialized || message.error || !message.result)
            throw new Error('Codex App Server initialization rejected');
          initialized = true;
          send({ method: 'initialized', params: {} });
          send({ id: 2, method: 'thread/read', params: { threadId, includeTurns: false } });
        } else if (message.id === 2) {
          if (!initialized || message.error || !message.result?.thread)
            throw new Error('Codex thread/read unavailable');
          finish(null, message.result);
        }
      } catch (error) { finish(error); }
    });
    send({ id: 1, method: 'initialize', params: {
      clientInfo: { name: 'harness_identity', version: '1' },
      capabilities: { experimentalApi: true },
    } });
  });
}

export function codexChildPath(raw, response) {
  const thread = response?.thread;
  const source = thread?.source?.subAgent?.thread_spawn;
  if (
    !codexThreadId(raw.agent_id) || raw.agent_type !== 'default' ||
    thread?.id !== raw.agent_id || source?.parent_thread_id !== raw.session_id ||
    !Number.isInteger(source?.depth) || source.depth < 1 ||
    ![null, undefined, 'default'].includes(source?.agent_role) ||
    ![null, undefined, 'default'].includes(thread?.agentRole) ||
    typeof source?.agent_path !== 'string' ||
    !/^\/root(?:\/[a-z0-9_]+)+$/.test(source.agent_path)
  ) throw new Error('Codex hook/thread identity mismatch');
  return source.agent_path;
}
