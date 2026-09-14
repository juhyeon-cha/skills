import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { normalizeHookEvent } from './hook-event.mjs';
import { normalizePath } from './operations.mjs';
import { workspaceShellCommand, literalShellWords } from '../workspace/workspace-command.mjs';
import { inspectWorkspace } from '../workspace/workspace.mjs';
import { guardLog, resolveState } from '../runtime/state.mjs';
import { commonCommand, windowsCommandOperands } from './common-command.mjs';
import { antigravityIdentity } from '../runtime/antigravity-identity.mjs';
import { canonicalRole } from '../runtime/role-contract.mjs';

// Policy inventories have one owner. Developer tests derive their populations
// from these exports and mutate copies, never an environment injection point.
export const BD_VALUE_OPTS = '-C --directory --db --actor --dolt-auto-commit';
export const GIT_VALUE_OPTS =
  '-C -c --git-dir --work-tree --namespace --config-env --exec-path --super-prefix --attr-source';
export const EXEC_WRAPPERS =
  'timeout env nice sudo bash sh zsh if then else elif while until do node node.exe';
export const LEDGER_TOOLS = 'ledger.sh ledger.mjs bd';
export const MC_GIT_READ_OPT =
  'worktree:list config:--get config:--get-regexp config:--list config:-l branch:--show-current branch:--list branch:-a branch:-r branch:-v branch:-vv remote:-v remote:show remote:get-url stash:list stash:show tag:-l tag:--list';
export const GH_READ_EXEMPT =
  'view list status diff checks browse search download item-list field-list';
export const GR_ROLES = 'harness:reviewer harness:evaluator';
export const GR_GIT_READ =
  'status log diff show ls-files rev-parse blame describe cat-file ls-remote branch grep';
export const IMPL_ROLES = 'harness:implementer';
export const IMPL_BD_WRITE_ALLOW = 'note state summary';
export const BD_READ_EXEMPT =
  'show list ready blocked children search query count graph history status prime where context info version help';
export const LEDGER_READ_EXEMPT = 'rails sprints';

const member = (list, item) => Boolean(item) && list.split(' ').includes(item);
const basename = (value) => value.split(/[\\/]/).at(-1);
const stripQuotes = (text) => text.replace(/\\[nrt]/g, ' ').replace(/[\\"']/g, '');
// A word is cut at its first parameter expansion. Splitting through one turned
// `x="${m%.mjs}.sh"` into a bare `m` that execWord read as a command, while making its
// punctuation into word characters instead let `git${IFS}commit` survive as one token that
// matches no tool, so no rule for git, gh or the ledger fired at all -- a fail-open.
// Cutting keeps `x=` an assignment (skipped, as intended) and keeps `git` the command word
// (its rule still fires). What the expansion would have expanded to is never guessed.
const tokens = (text) =>
  text
    .replace(/\$\{[^}]*}\S*/g, '')
    .split(/[^A-Za-z0-9_.:/=\[\-]+/)
    .filter(Boolean);
const segments = (text) => text.split(/\|\||&&|[;|(]|\$\(|\n/);
const valueOptions = (tool) => (tool === 'bd' ? BD_VALUE_OPTS : '--root');
const isLedgerRead = (sub) => member(BD_READ_EXEMPT + ' ' + LEDGER_READ_EXEMPT, sub);
const hasToken = (text, token) =>
  new RegExp('(?:^|[^A-Za-z0-9_])(?:' + token + ')(?:$|[^A-Za-z0-9_])').test(text);
function execWord(segment) {
  return basename(
    tokens(segment).find(
      (word) =>
        !member(EXEC_WRAPPERS, word) &&
        !word.startsWith('-') &&
        !/^\d+[smhd]?$/.test(word) &&
        !word.includes('='),
    ) ?? '',
  );
}
function subcommands(tool, options, text) {
  const words = text
    .replace(/[0-9]*[<>]&[0-9]+/g, '')
    .replace(/&?[0-9]*[<>]{1,2}/g, ' __REDIR__ ')
    .split(/[^A-Za-z0-9_.:/=\-]+/)
    .filter(Boolean);
  const result = [];
  for (let i = 0; i < words.length; i++) {
    if (basename(words[i]) !== tool) continue;
    let j = i + 1;
    while (j < words.length && (words[j].startsWith('-') || words[j] === '__REDIR__')) {
      if (member(options, words[j]) || words[j] === '__REDIR__') j++;
      j++;
    }
    result.push(words[j] ?? '');
  }
  return result;
}
function nextToken(sub, text) {
  const words = tokens(text);
  return words[words.indexOf(sub) + 1] ?? '';
}
const execSegments = (tool, command) =>
  segments(command).filter((segment) => execWord(segment) === tool);
const toolAliased = (tool, command) =>
  new RegExp(
    '(^|[^A-Za-z0-9_])[A-Za-z_][A-Za-z0-9_]*=([^\\s;&|]*/)?' +
      tool.replaceAll('.', '\\.') +
      '([^A-Za-z0-9_/.]|$)',
  ).test(command);

function quotedSegments(command) {
  let quote = '',
    previous = '',
    out = '';
  for (const original of command) {
    let c = original;
    if (!quote) {
      if (c === '"' || c === "'") quote = c;
    } else if (c === quote) quote = '';
    else if (';|&()'.includes(c) && !(c === '(' && quote === '"' && previous === '$'))
      c = c === '|' ? '\x01' : ' ';
    previous = original;
    out += c;
  }
  return segments(out);
}

class Denial extends Error {
  constructor(rule, message) {
    super(message);
    this.rule = rule;
  }
}
const deny = (ctx, message) => {
  throw new Denial(ctx.rule, message);
};
function norm(ctx, value) {
  if (value.startsWith('~/'))
    value = (ctx.env.HOME || ctx.env.USERPROFILE || os.homedir()) + value.slice(1);
  const target = normalizePath(value, ctx.event.cwd);
  if (process.platform !== 'win32' && /^[A-Za-z]:[\\/]|^\\\\/.test(target)) return target;
  let existing = target;
  const missing = [];
  for (;;) {
    try { return path.join(fs.realpathSync(existing), ...missing); }
    catch (error) {
      if (!['ENOENT', 'ENOTDIR'].includes(error.code)) throw error;
      const parent = path.dirname(existing);
      if (parent === existing) return target;
      missing.unshift(path.basename(existing)); existing = parent;
    }
  }
}
function rootOf(ctx, value) {
  const target = norm(ctx, value);
  let directory = target;
  for (;;) {
    if (fs.existsSync(path.join(directory, '.harness.json')))
      return { target, root: directory, repo: path.basename(directory) };
    const parent = path.dirname(directory);
    if (parent === directory) return null;
    directory = parent;
  }
}
async function locate(ctx, value) {
  const found = rootOf(ctx, value);
  if (!found) return null;
  if (!ctx.workspaces.has(found.root)) {
    let linked = false;
    try {
      const identity = await inspectWorkspace(found.root, { env: ctx.env });
      linked = identity.linked && Boolean(identity.branch);
    } catch {
      /* An unverified identity grants no exception. */
    }
    ctx.workspaces.set(found.root, linked);
  }
  if (ctx.workspaces.get(found.root)) return null; // REGISTERED_WORKSPACE
  return found;
}
function holdsTrees(ctx, value) {
  const holder = norm(ctx, value);
  let children;
  try {
    children = fs.readdirSync(holder);
  } catch {
    return null;
  }
  const trees = children.filter(
    (name) => !name.startsWith('.') && fs.existsSync(path.join(holder, name, '.harness.json')),
  );
  return trees.length ? { holder, trees } : null;
}
function pathCandidates(ctx) {
  if (ctx.common) return [...ctx.common.paths, ...ctx.common.writes];
  return ctx.event.harness_operations.map(operation => operation.path);
}

const filePath = (ctx) =>
  member('Read NotebookRead Glob Grep', ctx.event.tool_name)
    ? ''
    : ctx.event.tool_input.file_path || ctx.event.tool_input.notebook_path || '';
const policyRole = (ctx) => ctx.event.harness_policy_role || ctx.event.agent_type;
const grader = (ctx) => member(GR_ROLES, policyRole(ctx));
const child = (ctx) => Boolean(ctx.event.agent_id || ctx.event.agent_type);
const rootForm = (tool) =>
  tool === 'bd'
    ? 'bd -C <하네스루트>'
    : tool === 'ledger.mjs'
      ? 'node ledger.mjs --root <하네스루트>'
      : 'HARNESS_ROOT=<하네스루트> ledger.sh';
const graderCan = (ctx) =>
  `${policyRole(ctx).split(':').at(-1)} 가 할 수 있는 것: 검증용 명령 실행은 허용된다 — 게이트·테스트 재실행, git status·git diff·git show, ledger.mjs show·list. 지적·판정은 파일이 아니라 응답에 쓴다. ${policyRole(ctx) === 'harness:reviewer' ? 'SIGNAL: CHANGES_REQUESTED(또는 LGTM) 뒤에 MUST FIX·NIT 를 파일:라인과 함께 적어라.' : 'SIGNAL: MATCH·VIOLATION·DEVIATION 뒤에 acceptance 항목별 인용→근거→MET/NOT_MET 을 적어라.'} 기록은 오케스트레이터가 남긴다 (agents/${policyRole(ctx).split(':').at(-1)}.md).`;
const remoteReason =
  "원격 반영 금지 — 원격 반영은 오케스트레이터·사람의 몫이다. 예외 둘도 오케스트레이터의 것이다. 액터가 다르기 때문에 사용자 지시 전언으로 풀리지 않는다. 세션 블록 'Remote reflection only on explicit user instruction', harness:develop '사이클 종결': Subagents are out of scope — up to the local commit. SIGNAL: IMPLEMENTATION_COMPLETE 를 내고 커밋 해시를 보고하라 (agents/implementer.md). 원격 반영이 아닌데 막혔으면 오탐이니 사람에게 확인받아라. 낱말 인용(git log --grep push)과 로컬 명령(git stash push)은 걸리지 않는다. git subtree push 는 원격 반영이다; git subtree split 으로 로컬까지만 한다.";
function rejectAlias(ctx, tool) {
  if (toolAliased(tool, ctx.command))
    deny(
      ctx,
      `${tool} 를 변수에 담아 부르는 형태는 하위 명령을 읽을 수 없어 차단한다 — '${tool === 'gh' ? 'gh <그룹> <하위명령>' : rootForm(tool) + ' <하위명령>'} 형태로 직접 불러라. ${ctx.rule === 'r_remote' ? remoteReason : grader(ctx) ? '채점자는 읽기만 가능하다. ' + graderCan(ctx) : ''}`,
    );
}
function rootHint(ctx) {
  const explicit = ctx.env.HARNESS_ROOT;
  const root = explicit
    ? fs.existsSync(path.join(explicit, '.harness.json')) && explicit
    : rootOf(ctx, ctx.event.cwd)?.root;
  return root
    ? `이 호출의 cwd 에서 찾은 하네스 루트는 ${root} 다.`
    : '훅은 이 호출의 cwd 에서 하네스 루트를 찾지 못했다. 위임 메시지의 절대 경로를 쓰고 없으면 DECISION_NEEDED.';
}
function ledgerCalls(ctx) {
  return LEDGER_TOOLS.split(' ').flatMap((tool) =>
    execSegments(tool, ctx.command).map((segment) => ({
      tool,
      segment,
      sub: subcommands(tool, valueOptions(tool), segment)[0] ?? '',
    })),
  ); // PER_SEGMENT
}

export const RULES = [];

function protectedTarget(ctx, value) {
  const target = norm(ctx, value);
  const found = rootOf(ctx, target);
  if (found) {
    const first = path.relative(found.root, target).split(path.sep)[0];
    if (['.git'].includes(first)) return true;
  }
  const rawData = ctx.stateData || ctx.env.HARNESS_DATA_DIR;
  if (rawData && (typeof rawData !== 'string' || !path.isAbsolute(rawData) || /[\0\r\n]/.test(rawData)))
    throw new Error('state path missing/invalid');
  const data = rawData && norm(ctx, rawData);
  if (data && (target === data || target.startsWith(data + path.sep)))
    return !(ctx.common?.effect === 'state' && ctx.common.writes.some(value => norm(ctx, value) === target));
  return false;
}

export async function r_main_write(ctx) {
  if (ctx.event.harness_shell_dialect) return;
  const value = filePath(ctx);
  if (!value) return;
  if (protectedTarget(ctx, value)) deny(ctx, '보호 설정/상태 파일 직접 쓰기 금지 — 승인된 공통 명령을 사용한다');
  const found = await locate(ctx, value);
  if (!found) return;
  deny(
    ctx,
    `본 체크아웃 쓰기 금지 — ${found.target} 는 대상 레포 '${found.repo}' 의 본 체크아웃 안이다. 쓰기는 스토리 워크트리 안에서만 한다: ${found.root}/.claude/worktrees/<워크트리 이름>/ — workspace.mjs create 로 만든다.`,
  );
}
RULES.push({matcher: '*', run: r_main_write});

export async function r_main_shell(ctx) {
  if (ctx.workspace) return;
  if (ctx.common?.effect === 'projection') {
    if (child(ctx))
      deny(
        ctx,
        '원장 투영은 오케스트레이터의 몫이다 — 정확한 board 명령도 서브에이전트는 실행하지 않는다.',
      );
    return; // The exact loaded renderer confines publication to its docs projection.
  }
  for (const candidate of pathCandidates(ctx)) {
    if (protectedTarget(ctx, candidate))
      deny(ctx, 'Direct Git-internal/active-state writes are protected; use the common command');
    const found = await locate(ctx, candidate);
    const holder = !found && holdsTrees(ctx, candidate);
    if (found || holder)
      deny(ctx, `Protected write target: ${found?.target || holder.holder}. Work in a registered linked worktree.`);
  }
}
RULES.push({matcher: 'Bash', run: r_main_shell});

export function r_remote(ctx) {
  if (!child(ctx)) return;
  if (ctx.common?.remote) deny(ctx, remoteReason);
  rejectAlias(ctx, 'git');
  rejectAlias(ctx, 'gh');
  const reason = remoteReason;
  for (const segment of execSegments('git', ctx.command)) {
    const sub = subcommands('git', GIT_VALUE_OPTS, segment)[0];
    if (sub === 'push' || (sub === 'subtree' && hasToken(segment, 'push'))) deny(ctx, reason);
  }
  for (const segment of execSegments('dolt', ctx.command))
    if (subcommands('dolt', '', segment)[0] === 'push') deny(ctx, reason);
  for (const { sub, segment } of ledgerCalls(ctx))
    if (
      (sub === 'dolt' && hasToken(segment, 'push')) ||
      (sub === 'sync-check' && hasToken(segment, '--push'))
    )
      deny(ctx, reason);
  for (const segment of execSegments('gh', ctx.command)) {
    const first = subcommands('gh', '', segment)[0] ?? '';
    const second = first ? (subcommands(first, '', segment)[0] ?? '') : '';
    if (!first || member(GH_READ_EXEMPT, first) || member(GH_READ_EXEMPT, second)) continue;
    deny(
      ctx,
      `GitHub 조작 금지 — 'gh ${first}${second ? ' ' + second : ''}' 은 읽기 면제 목록에 없다. ${reason} 읽기 면제: ${GH_READ_EXEMPT} (gh pr view 등). gh api 는 형태를 가리지 않고 차단이다. 원장은 ledger.mjs 로 읽어라.`,
    );
  }
}
RULES.push({matcher: 'Bash', run: r_remote});

export function r_grader_write(ctx) {
  if (!grader(ctx)) return;
  const value = filePath(ctx);
  if (!value) return;
  const found = rootOf(ctx, value);
  if (!found) return; // GRADER_TREE_SCOPE
  deny(
    ctx,
    `채점자의 파일 수정 금지 — ${ctx.event.tool_name} 도구가 겨눈 ${found.target} 는 대상 레포 '${found.repo}' 의 트리 안이다(워크트리도 그 트리다). 트리 **밖** 메모는 막지 않는다. ${graderCan(ctx)}`,
  );
}
RULES.push({matcher: '*', run: r_grader_write});

export function r_grader_shell(ctx) {
  if (!grader(ctx)) return;
  if (['state', 'prepare', 'projection'].includes(ctx.common?.effect))
    deny(ctx, '채점자의 공통 명령 쓰기 금지 — ' + graderCan(ctx));
  rejectAlias(ctx, 'git');
  for (const segment of execSegments('git', ctx.command)) {
    const sub = subcommands('git', GIT_VALUE_OPTS, segment)[0] ?? '';
    if (member(GR_GIT_READ, sub)) continue;
    if (member(MC_GIT_READ_OPT, sub + ':' + nextToken(sub, segment))) continue; // GRADER_GIT_PAIR
    deny(
      ctx,
      `채점자의 git 쓰기 금지 — 'git ${sub || '<하위 명령 없음>'}' 은 읽기 면제 목록 밖이다. git 이 실행하는 하위 명령을 판정하며 revert·merge·rebase 도 막힌다. 읽기 면제: ${GR_GIT_READ}. 읽기 쌍: ${MC_GIT_READ_OPT}. 실행이 아닌 문자열(git log --grep commit)은 걸리지 않는다 — 그래도 막혔으면 오탐이다. ${graderCan(ctx)}`,
    );
  }
  for (const tool of LEDGER_TOOLS.split(' ')) rejectAlias(ctx, tool);
  for (const { tool, sub } of ledgerCalls(ctx)) {
    if (!sub || isLedgerRead(sub)) continue;
    deny(
      ctx,
      `채점자의 ${tool} 쓰기 금지 — '${tool} ${sub}' 는 읽기 면제 목록에 없다. 원장 지정을 붙여도 쓰기는 금지 — r_bd_root 와 다르다. 읽기 면제: ${BD_READ_EXEMPT} ${LEDGER_READ_EXEMPT}. 원장 기록은 오케스트레이터의 몫이다. ${graderCan(ctx)}`,
    );
  }
}
RULES.push({matcher: 'Bash', run: r_grader_shell});

export function r_impl_bd(ctx) {
  if (!member(IMPL_ROLES, policyRole(ctx))) return;
  for (const tool of LEDGER_TOOLS.split(' ')) rejectAlias(ctx, tool);
  for (const { tool, sub } of ledgerCalls(ctx)) {
    if (!sub) continue; // IMPL_OPTIONS_ONLY
    if (isLedgerRead(sub) || member(IMPL_BD_WRITE_ALLOW, sub)) continue;
    deny(
      ctx,
      `implementer 의 ${tool} 쓰기 금지 — '${tool} ${sub}' 는 허용 목록 밖이다. 허용된 쓰기는 '${IMPL_BD_WRITE_ALLOW}' 뿐이고, 원장 지정을 붙여도 그 밖의 쓰기는 금지 — r_bd_root 와 다르다. 읽기 면제: ${BD_READ_EXEMPT} ${LEDGER_READ_EXEMPT}. 원장 구조는 오케스트레이터의 몫이다. 필요하면 SIGNAL: DECISION_NEEDED 로 보고하라. '${rootForm(tool)} note <태스크ID>' 로 사실을 남긴다. update --append-notes 도 막힌다 (agents/implementer.md).`,
    );
  }
}
RULES.push({matcher: 'Bash', run: r_impl_bd});

export function r_bd_root(ctx) {
  if (!child(ctx)) return;
  for (const tool of LEDGER_TOOLS.split(' ')) rejectAlias(ctx, tool);
  for (const { tool, sub, segment } of ledgerCalls(ctx)) {
    if (!sub || isLedgerRead(sub)) continue;
    const before = segment.slice(0, segment.indexOf(sub));
    if (
      tool === 'bd'
        ? hasToken(before, '-C|--directory|--db')
        : hasToken(before, '--root') || /(^|[^A-Za-z0-9_])HARNESS_ROOT=/.test(before)
    )
      continue;
    deny(
      ctx,
      `${tool} 원장 지정 누락 — 서브에이전트의 쓰기는 '${rootForm(tool)} ${sub} …' 로 부른다. --directory·--db 는 bd의 같은 자리에서 인정된다. HARNESS_ROOT 변수는 그 명령 앞에 붙인다. 원장 지정 없이 다른 원장에 조용히 성공할 수 있다. 읽기(${BD_READ_EXEMPT} ${LEDGER_READ_EXEMPT})는 면제다. ${rootHint(ctx)}`,
    );
  }
}
RULES.push({matcher: 'Bash', run: r_bd_root});

async function dispatch(ctx) {
  for (const { matcher, run } of RULES) {
    ctx.rule = typeof run === 'function' ? run.name : String(run);
    if (typeof run !== 'function') deny(ctx, '규칙 등록부가 깨졌다 — 함수가 없다');
    if (matcher !== '*' && matcher !== ctx.event.tool_name) continue;
    if (matcher === 'Bash' && ctx.event.harness_shell_readonly) continue;
    await run(ctx);
  }
}

export async function evaluateGuard(
  raw,
  {
    env = process.env,
    readThread,
    resolveAntigravityIdentity = antigravityIdentity,
    pluginRoot = env.CLAUDE_PLUGIN_ROOT ||
      path.resolve(fileURLToPath(new URL('../../', import.meta.url))),
  } = {},
) {
  let event = raw,
    rule = 'UNREACHED-input',
    result;
  try {
    event = normalizeHookEvent(raw, { env, deferDelegatedRole: true });
    const roleIndependent = event.harness_shell_readonly ||
      ['Read', 'NotebookRead', 'Glob', 'Grep'].includes(event.tool_name) ||
      /^collaboration\.?(?:send_message|list_agents|wait_agent)$/.test(event.tool_name);
    if (raw?.harness_runtime === 'antigravity' && !roleIndependent) {
      const identity = await resolveAntigravityIdentity(raw, {env, pluginRoot});
      if (identity?.kind === 'parent') raw = {...raw, agent_id: '', agent_type: ''};
      else if (identity?.kind === 'child' && canonicalRole(identity.role))
        raw = {...raw, agent_type: canonicalRole(identity.role)};
      else throw new Error('Antigravity role identity UNREACHED');
      event = normalizeHookEvent(raw, {env});
      if (event.tool_name === 'Bash') {
        const commands = quotedSegments(event.tool_input.command).filter(part => part.trim());
        const parsed = commands.map(command => literalShellWords(command, {
          dialect: event.harness_shell_dialect, cwd: event.cwd,
        }));
        // Inspect literal argv, including quoted paths and wrapper operands.
        // Literal segments preserve existing composed commands. Dynamic child
        // commands cannot establish that enrollment is absent.
        if (hasToken(event.tool_input.command, 'parent-register') ||
            (identity.kind !== 'parent' && parsed.some(words => !words ||
              words.some(word => basename(word) === 'antigravity-role.mjs') ||
              (words.some(word => ['bash', 'sh', 'zsh'].includes(basename(word))) &&
                words.some(word => /^-[A-Za-z]*c/.test(word) || word === '--command')))))
          throw new Error('parent registration is operator-only; agent tool enrollment forbidden');
      }
    }
    if (raw?.agent_id && (!raw.agent_type || raw.agent_type === 'default') && !roleIndependent) {
      const { delegationHookRole } = await import('../runtime/delegation.mjs');
      const delegatedRole = await delegationHookRole(raw, { root: pluginRoot, env, readThread });
      event = normalizeHookEvent(raw, { env, delegatedRole });
    }
    const rawCommand = event.tool_input.command ?? '';
    const windowsOperands =
      event.tool_name === 'Bash'
        ? windowsCommandOperands(rawCommand, {
            dialect: event.harness_shell_dialect,
            ledgerTools: LEDGER_TOOLS.split(' '),
          })
        : null;

    const common =
      event.tool_name === 'Bash'
        ? await commonCommand(rawCommand, {
            pluginRoot,
            cwd: event.cwd,
            dialect: event.harness_shell_dialect,
            env,
          })
        : null;
    const workspace =
      event.tool_name === 'Bash' &&
      workspaceShellCommand(rawCommand, path.join(pluginRoot, 'scripts/workspace.mjs'), {
        dialect: event.harness_shell_dialect,
      });
    if (workspace && grader({ event }) && !['inspect', 'ready'].includes(workspace.action))
      throw new Error('grader cannot mutate workspace lifecycle');
    if (workspace) event.harness_operations = [];
    let policyCommand = stripQuotes(rawCommand);
    const policyText = (words) =>
      words
        .map((word, index) => {
          // Policy scanners use an ASCII token alphabet. Replace non-alphabet
          // data inside each already-lexed argv word, never split a path at ~,
          // Unicode or whitespace. Filesystem targets retain their original text.
          word = word.replaceAll('\\', '/').replace(/[^A-Za-z0-9_.:/=\-]/g, '_');
          if (index === 0 && /(?:^|\/)(?:git|gh|bd|dolt|node)(?:\.exe)?$/i.test(word))
            word = word.replace(
              /[^/]+$/,
              basename(word)
                .toLowerCase()
                .replace(/\.exe$/, ''),
            );
          if (index <= 1 && /(?:^|\/)ledger\.(?:mjs|sh)$/i.test(word))
            word = word.replace(/[^/]+$/, basename(word).toLowerCase());
          return word;
        })
        .join(' ');
    if (windowsOperands?.ledger && !event.harness_shell)
      policyCommand = policyText(windowsOperands.words);
    if (event.harness_shell && !workspace && !common) {
      const parsed = event.harness_shell;

      policyCommand = parsed.commands.map(policyText).join(';');

    }
    if (common)
      event.harness_operations = (common.effect === 'projection' ? [] : common.writes).map(
        (path) => ({ kind: 'update', path }),
      );
    const operations = event.harness_operations.flatMap((op) =>
      op.kind === 'move' ? [op.source, op.destination] : [op.path],
    );
    if (
      process.platform !== 'win32' &&
      operations.some((value) => /^[A-Za-z]:[\\/]|^\\\\/.test(value))
    )
      throw new Error('Windows filesystem policy is unavailable on this host');
    const ctx = {
      event,
      env,
      pluginRoot,
      raw: rawCommand,
      command: policyCommand,
      workspace,
      common,
      windowsOperands,
      workspaces: new Map(),
      rule,
    };
    try { ctx.stateData = (await resolveState({cwd: event.cwd, sessionId: event.session_id}, env)).data; }
    catch { /* An unscoped call receives no state-write exception. */ }
    await dispatch(ctx);
    for (const target of operations) {
      ctx.event = { ...event, tool_name: 'Write', tool_input: { file_path: target } };
      await dispatch(ctx);
    }
    rule = '-';
    result = { code: 0, stdout: '', stderr: '', rule };
  } catch (error) {
    rule = error instanceof Denial ? error.rule : 'UNREACHED-input';
    result = {
      code: 2,
      stdout: '',
      stderr: `GUARD-DENY: ${error instanceof Denial ? '' : 'UNREACHED — 판정에 도달하지 못했다: '}${error.message}\n`,
      rule,
    };
  }
  try {
    await guardLog(event ?? {}, rule, env);
  } catch (error) {
    // GUARD_OBSERVATION
    result.stderr += `STATE UNREACHED: guard observation was not persisted: ${error.message}\n`;
  }
  return result;
}
