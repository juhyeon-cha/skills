import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { normalizeHookEvent } from './hook-event.mjs';
import { normalizePath } from './operations.mjs';
import { workspaceShellCommand } from '../workspace/workspace-command.mjs';
import { inspectWorkspace } from '../workspace/workspace.mjs';
import { guardLog } from '../runtime/state.mjs';
import { powershellTargets, powershellReadonly } from './powershell-operations.mjs';
import { commonCommand, windowsCommandOperands } from './common-command.mjs';

// Policy inventories have one owner. Developer tests derive their populations
// from these exports and mutate copies, never an environment injection point.
export const BD_VALUE_OPTS = '-C --directory --db --actor --dolt-auto-commit';
export const GIT_VALUE_OPTS =
  '-C -c --git-dir --work-tree --namespace --config-env --exec-path --super-prefix --attr-source';
export const EXEC_WRAPPERS =
  'timeout env nice sudo bash sh zsh if then else elif while until do node node.exe';
export const LEDGER_TOOLS = 'ledger.sh ledger.mjs bd';
export const MC_READ_CMDS =
  'ls cat head tail wc stat file grep diff du tree readlink realpath test [ [[ cd pwd echo printf sed jq awk sort find';
export const MC_WRITE_OPTS =
  'sed:-[A-Za-z]*[iI][^\\s]*|--i[^\\s]*|-[A-Za-z]*f[^\\s]*|--file[^\\s]* awk:-[A-Za-z]*f[^\\s]*|--file[^\\s]* sort:-[A-Za-z]*o[^\\s]*|--o[^\\s]* find:-(delete|exec|execdir|ok|okdir|fprint|fprint0|fprintf|fls)';
export const MC_GIT_READ =
  'status log diff show ls-files rev-parse blame describe cat-file ls-remote grep for-each-ref merge-base ls-tree rev-list shortlog diff-tree name-rev check-ignore var count-objects whatchanged archive';
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
const tokens = (text) => text.split(/[^A-Za-z0-9_.:/=\[\-]+/).filter(Boolean);
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
function shellWrapped(segment) {
  for (const word of tokens(segment)) {
    if (word.startsWith('-') || /^\d+[smhd]?$/.test(word) || word.includes('=')) continue;
    const base = basename(word);
    if (['bash', 'sh', 'zsh'].includes(base)) return true;
    if (!member(EXEC_WRAPPERS, base)) return false;
  }
  return false;
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
function scriptWrites(word, raw) {
  if (word === 'awk') return /system|\x01|getline/.test(raw);
  if (word !== 'sed') return false;
  const words = [];
  let token = '',
    quote = '',
    active = false;
  for (let i = 0; i < raw.length; i++) {
    const c = raw[i];
    if (quote) {
      if (c === quote) quote = '';
      else token += c;
      continue;
    }
    if (c === '"' || c === "'") {
      quote = c;
      active = true;
      continue;
    }
    if (c === '\\') {
      token += raw[++i] ?? '';
      continue;
    }
    if (/\s/.test(c)) {
      if (token || active) words.push(token);
      token = '';
      active = false;
      continue;
    }
    token += c;
  }
  if (token || active) words.push(token);
  const start = words.findIndex((word) => basename(word) === 'sed');
  if (start < 0) return false;
  const expressions = [];
  let first;
  for (let i = start + 1; i < words.length; i++) {
    const x = words[i];
    if (x === '--') continue;
    if (x.startsWith('--expression=')) {
      expressions.push(x.slice(13));
      continue;
    }
    if (x === '--expression') {
      expressions.push(words[++i] ?? '');
      continue;
    }
    if (/^--(file|line-length)=/.test(x)) continue;
    if (['--file', '--line-length'].includes(x)) {
      i++;
      continue;
    }
    if (/^-[^-]/.test(x)) {
      if (/^-[A-Za-z]*e$/.test(x)) expressions.push(words[++i] ?? '');
      else if (/^-[A-Za-z]*e./.test(x)) expressions.push(x.replace(/^-[A-Za-z]*e/, ''));
      else if (/^-[A-Za-z]*[fl]$/.test(x)) i++;
      continue;
    }
    first ??= x;
  }
  if (!expressions.length && first !== undefined) expressions.push(first);
  return expressions.some((value) => /[wW]/.test(value));
}
function allReadonly(command) {
  let any = false;
  for (const raw of quotedSegments(command)) {
    const segment = stripQuotes(raw);
    if (!segment.trim()) continue;
    any = true;
    if (
      segment
        .replace(/[0-9]?>&[0-9]/g, '')
        .replace(/[0-9]?>\/dev\/null/g, '')
        .includes('>') ||
      shellWrapped(segment)
    )
      return false;
    const word = execWord(segment);
    if (!word || ['for', 'done', 'fi', 'esac'].includes(word)) continue;
    if (member(MC_READ_CMDS, word)) {
      const expression = MC_WRITE_OPTS.split(' ')
        .find((entry) => entry.startsWith(word + ':'))
        ?.slice(word.length + 1);
      if (expression && new RegExp('(^|\\s)(' + expression + ')(\\s|$)').test(segment))
        return false;
      if (scriptWrites(word, raw)) return false;
      continue;
    }
    if (word === 'git') {
      const sub = subcommands('git', GIT_VALUE_OPTS, segment)[0];
      if (member(MC_GIT_READ, sub) || member(MC_GIT_READ_OPT, sub + ':' + nextToken(sub, segment)))
        continue;
    }
    if (word === 'gh') {
      const first = subcommands('gh', '', segment)[0];
      const second = subcommands(first, '', segment)[0];
      if (member(GH_READ_EXEMPT, first) || member(GH_READ_EXEMPT, second)) continue;
    }
    return false;
  }
  return any;
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
  return normalizePath(value, ctx.event.cwd);
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
function isHarnessRoot(ctx, value) {
  return (
    Boolean(value) &&
    (fs.existsSync(path.join(norm(ctx, value), '.harness.json')) || Boolean(holdsTrees(ctx, value)))
  );
}
function pathCandidates(ctx) {
  if (ctx.common) return [...ctx.common.paths, ...ctx.common.writes];
  if (ctx.event.harness_shell_dialect === 'powershell')
    return ctx.event.harness_operations.map((operation) => operation.path);
  let command = ctx.command;
  command = command.replaceAll('${HOME}', ctx.env.HOME || os.homedir()); // EXPAND_HOME
  command = command.replaceAll('$HOME', ctx.env.HOME || os.homedir()); // EXPAND_HOME
  for (const word of command.split(/[ \t]/)) {
    if (!word.startsWith('HARNESS_ROOT=')) continue;
    const root = word.slice(13);
    if (isHarnessRoot(ctx, root)) command = command.replaceAll('HARNESS_ROOT=' + root + ' ', ''); // ROOT_ASSIGNMENT
  }
  // Bash is also a real Windows transport. Keep drive/UNC operands intact;
  // the POSIX slash scanner alone drops backslash paths without spaces.
  const literal = ctx.windowsOperands;
  const candidates = literal
    ? literal.operands
        .filter(
          (operand) =>
            operand.kind !== 'transport' &&
            (operand.kind !== 'ledger-root' || !isHarnessRoot(ctx, operand.path)),
        )
        .map((operand) => operand.path)
    : [...ctx.raw.matchAll(/'([^']*)'|"([^"]*)"/g)]
        .map((match) => match[1] ?? match[2])
        .filter((value) => /^[A-Za-z]:[\\/]|^\\\\/.test(value));
  if (literal) {
    const handled = new Set(literal.operands.map((operand) => operand.index));
    // Preserve option positions while keeping an already-classified operand
    // out of the legacy slash scanner (which cannot retain a Windows drive).
    command = stripQuotes(
      literal.words
        .map((word, index) => (handled.has(index) ? '__WINDOWS_OPERAND__' : word))
        .join(' '),
    );
  }
  for (const segment of segments(command.replaceAll('`', '\n'))) {
    // CANDIDATE_BACKTICKS
    const executable = execWord(segment);
    let previous = '';
    for (const word of segment.split(/[ \t]/).filter(Boolean)) {
      const coordinate =
        (executable === 'bd' && ['-C', '--directory', '--db'].includes(previous)) ||
        (['ledger.sh', 'ledger.mjs'].includes(executable) && previous === '--root');
      if (coordinate && isHarnessRoot(ctx, word)) {
        previous = word;
        continue;
      }
      // A native adapter's own file is transport, never its mutation target.
      if (['ledger.sh', 'ledger.mjs'].includes(executable) && basename(word) === executable) {
        previous = word;
        continue;
      }
      candidates.push(
        ...[...word.matchAll(/(?:^|=)((?:[A-Za-z]:[\\/]|\\\\)[^\s"'`;|&()<>]*)/g)].map(
          (match) => match[1],
        ),
      );
      candidates.push(...(word.match(/[~/][^\s"'`;|&()<>]*/g) ?? []));
      if (/^\.\.?\//.test(word)) candidates.push(word);
      previous = word;
    }
  }
  return candidates;
}
const filePath = (ctx) =>
  member('Read NotebookRead Glob Grep', ctx.event.tool_name)
    ? ''
    : ctx.event.tool_input.file_path || ctx.event.tool_input.notebook_path || '';
const grader = (ctx) => member(GR_ROLES, ctx.event.agent_type);
const child = (ctx) => Boolean(ctx.event.agent_id || ctx.event.agent_type);
const rootForm = (tool) =>
  tool === 'bd'
    ? 'bd -C <하네스루트>'
    : tool === 'ledger.mjs'
      ? 'node ledger.mjs --root <하네스루트>'
      : 'HARNESS_ROOT=<하네스루트> ledger.sh';
const graderCan = (ctx) =>
  `${ctx.event.agent_type.split(':').at(-1)} 가 할 수 있는 것: 검증용 명령 실행은 허용된다 — 게이트·테스트 재실행, git status·git diff·git show, ledger.mjs show·list. 지적·판정은 파일이 아니라 응답에 쓴다. ${ctx.event.agent_type === 'harness:reviewer' ? 'SIGNAL: CHANGES_REQUESTED(또는 LGTM) 뒤에 MUST FIX·NIT 를 파일:라인과 함께 적어라.' : 'SIGNAL: MATCH·VIOLATION·DEVIATION 뒤에 acceptance 항목별 인용→근거→MET/NOT_MET 을 적어라.'} 기록은 오케스트레이터가 남긴다 (agents/${ctx.event.agent_type.split(':').at(-1)}.md).`;
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

export async function r_main_write(ctx) {
  const value = filePath(ctx);
  if (!value) return;
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
    if (process.platform !== 'win32' && /^[A-Za-z]:[\\/]|^\\\\/.test(candidate)) {
      if (allReadonly(ctx.raw)) return;
      throw new Error('Windows filesystem policy is unavailable on this host');
    }
    let found = await locate(ctx, candidate);
    if (!found) {
      let tail = candidate.replace(/^\//, '');
      while (tail.includes('/')) {
        tail = tail.slice(tail.indexOf('/') + 1);
        found = await locate(ctx, '/' + tail);
        if (found) break;
      }
    }
    if (!found) {
      const holder = holdsTrees(ctx, candidate);
      if (!holder) continue; // HOLDER_CHECK
      if (allReadonly(ctx.raw)) return;
      deny(
        ctx,
        `클론 루트 자체 금지 — 명령에 ${holder.holder} 가 들어 있다. 하네스 트리들을 **품고 있다**: ${holder.trees.join(' ')}. 클론·워크트리·미커밋 변경이 함께 사라진다.`,
      );
    }
    if (allReadonly(ctx.raw)) return;
    deny(
      ctx,
      `본 체크아웃 경로 금지 — 명령에 ${found.target} 가 들어 있다. 대상 레포 '${found.repo}' 의 본 체크아웃은 직접 건드리지 않는다. 읽기 전용 명령만으로 된 명령은 통과한다. 쓰기는 스토리 워크트리 안에서 한다: ${found.root}/.claude/worktrees/<워크트리 이름>/`,
    );
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
  if (!member(IMPL_ROLES, ctx.event.agent_type)) return;
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
    pluginRoot = env.CLAUDE_PLUGIN_ROOT ||
      path.resolve(fileURLToPath(new URL('../../', import.meta.url))),
  } = {},
) {
  let event = raw,
    rule = 'UNREACHED-input',
    result;
  try {
    event = normalizeHookEvent(raw, { env });
    const rawCommand = event.tool_input.command ?? '';
    const windowsOperands =
      event.tool_name === 'Bash'
        ? windowsCommandOperands(rawCommand, {
            dialect: event.harness_shell_dialect,
            ledgerTools: LEDGER_TOOLS.split(' '),
          })
        : null;
    if (windowsOperands?.ledger && !event.harness_shell) {
      event.harness_operations = event.harness_operations.filter(
        (operation) => !/^[A-Za-z]:[\\/]|^\\\\/.test(operation.path),
      );
      event.harness_operations.push(
        ...windowsOperands.operands
          .filter((operand) => operand.kind === 'target')
          .map((operand) => ({ kind: 'update', path: operand.path })),
      );
    }
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
      if (parsed.dynamic) throw new Error('dynamic PowerShell command cannot be classified');
      policyCommand = parsed.commands.map(policyText).join(';');
      // Keep command/option permission checks active for native ledger calls,
      // while excluding the executable and explicit root coordinate from files.
      const paths = parsed.commands.flatMap((words) => {
        if (powershellReadonly(words)) return [];
        const start = ['node', 'node.exe'].includes(basename(words[0]).toLowerCase()) ? 1 : 0;
        const executable = basename(words[start] ?? '').toLowerCase();
        if (['ledger.sh', 'ledger.mjs', 'bd'].includes(executable)) {
          const rest = words
            .slice(start + 1)
            .filter(
              (word, index, all) =>
                !member(valueOptions(executable), word) &&
                !member(valueOptions(executable), all[index - 1]),
            );
          return powershellTargets([executable, ...rest], event.cwd);
        }
        if (!parsed.redirect && allReadonly(policyText(words))) return [];
        return powershellTargets(words, event.cwd);
      });
      // Redirection targets are already normalized by the lexer.
      event.harness_operations = [
        ...new Set(parsed.redirect ? [...paths, ...parsed.paths] : paths),
      ].map((path) => ({ kind: 'update', path }));
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
