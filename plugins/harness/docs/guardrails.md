# Enforcement mechanisms (as-built) — what is blocked, and what is persuasion only

> The full list of the guardrails and gates the harness actually runs, each one's limits, and where they live.
> The measurements themselves are in the ledger — a rule's measurements are the `note` of the task bead that made it, and the three decision documents are `decision` beads (`harness-bjj` · `harness-pl7` · `harness-dmy`, projected to `docs/adr/`). This document is the index.
> **How each mechanism is verified, and the as-built observations, are in [guardrail-verification.md](guardrail-verification.md)** — section numbers continue from this file. This document holds **what is blocked** (sections 1 · 2 · 3 · 5 · 5-1 · 6 · 6-1).
> Structure: [architecture.md](architecture.md). Engineering discipline: [engineering.md](engineering.md).
>
> **Where the code is.** Common policy lives in `lib/guard/guard.mjs`, Stop in `lib/runtime/stop.mjs`, and checks in `checks/*.mjs`. `scripts/hook.mjs` dispatches generated Claude/Codex transports; the old `.sh` entries are compatibility wrappers. Paths are plugin-relative. Claude's `permissions.deny` remains target-repository `.claude/settings.json` configuration and is not a portable Codex permission contract. The harness plants no Git hook; target repository hooks belong to that repository.
>
> **One ledger inventory.** `lib/guard/guard.mjs` owns `LEDGER_TOOLS` for native `ledger.mjs`, legacy `ledger.sh`, and direct `bd`. Every ledger rule shares that population and its read/write permission lists. Native calls explicitly name the repository with `node <plugin>/scripts/ledger.mjs --root <root> …`; legacy root forms remain recognized. [Commands](commands.md) owns portable invocation examples.

Rules and user approvals remain binding even when a hook cannot observe an effect.
Use host filesystem and execution permissions for isolation. These hooks prevent
recognized mistakes and record observations; their passing result does not prove
that arbitrary commands are safe.

`lib/hook-definitions.json` registers context, guard, workspace, Stop and role
observations. Stop is advisory unless continued execution was explicitly enabled
for this session. Generated Claude/Codex transports share the policy; actual
runtime firing is verified separately from direct handler tests.

## 1. Hook rules — `lib/guard/guard.mjs` (PreToolUse)

A denial returns code 2 with its reason. Malformed known tool inputs still fail
explicitly. The hook inspects concrete file operations; it is not an OS security
boundary or a complete shell interpreter. Host permissions enforce access for
opaque scripts and dynamic commands. User approval rules apply regardless of
whether the hook recognizes an action.

For ordinary versus managed child classification, consult
[Runtime role contract](roles.md#standalone-investigation-and-review). Absence of
a harness role does not prohibit ordinary execution. Classification retains the
child identity, so child-scoped rules below still apply; a passing hook neither
grants host permissions nor establishes user approval.

| Rule | Scope | Enforcement |
|---|---|---|
| `r_main_write` | File tools and patches | Protect the main checkout, Git internals and active state. Repository settings in a registered worktree are editable within the authorized task. |
| `r_main_shell` | Shell operations | Check literal output redirects and recognized file-command targets, plus effects declared by exact common commands. A source path, quoted body or arbitrary script argument alone is not a write. |
| `r_task_create` | Children | Keep user-task creation with the parent; host authorization still applies. |
| `r_remote` | Children | Reject recognized remote writes; the parent remains responsible for user authorization. |
| `r_grader_write` | Independent reviewers/evaluators | Keep the reviewed repository unchanged. Scratch files outside it remain available. |
| `r_grader_shell` | Independent reviewers/evaluators | Reject Git/ledger mutations and common state/preparation writes. |
| `r_impl_bd` | Implementers | Restrict ledger writes to implementation state and summaries; completion stays with the orchestrator. |
| `r_bd_root` | Children | Require explicit ledger coordinates for mutations. |

POSIX shell targets are derived from output redirects and literal operands of
`rm`, `rmdir`, `unlink`, `touch`, `mkdir`, `tee`, `cp` and `mv`. PowerShell recognizes
file cmdlets and output redirects. Literal Git output options and recognized
writes inside command substitutions are also checked. Unknown script effects and
unrecognized write options are outside this bounded analysis. Mere inability to
classify a command's effects does not prohibit running it under host permissions.

Direct writes to `.git` and active runtime state stay protected. `.harness.json`,
`.agents`, `.claude` and `.codex` in a linked worktree are ordinary versioned
configuration for authorized changes. This does not authorize changing the main
checkout or an installed plugin copy.

Common commands validate their own arguments and destinations. Graders cannot
change state or workspace preparation; subagents cannot publish projections or
request remote reflection. See [Commands](commands.md) for invocation and
[Runtime state](state.md) for session-scoped state.

The selected verification path comes from `verify-code`, not tool-hook success.
Low-risk work can complete with local checks and acceptance evidence. Independent
review remains required for its risk categories and explicit repository/user
requirements.

Additional tool effect classifications live in `lib/guard/tool-contract.mjs`.
Questions, waits, task reads and project listings are role-independent. Task
creation is parent-only. The host validates tool inputs and permissions, including
CUA and tools without harness-specific policy. Those opaque tools pass through
without a read-only or safety claim; recognized file tools still enforce targets.

`literalReadEffects` preserves main's read/output distinction and role-independent
read recovery. Commands outside that literal subset use recognized write-target
analysis, not broad path-string blocking. Metadata diagnostics remain separate
from command bodies and do not establish execution or completion.

### 1-1. Three limits on slash commands [measured — `harness-dg0.3.1` note 7.1]

The rules in section 1 are **all `PreToolUse`**, so how a slash command appears in that event is the coverage.

| # | Limit | What it makes you misread |
|---|---|---|
| L1 | **A slash command typed by a person does not appear in `PreToolUse`** — with the hook wiring alive, only `UserPromptSubmit` fires. Only a model-initiated one appears, as a `Skill` tool call | Every rule that targets a slash command needs the qualifier **"model-initiated only"**. Without it, **"partial" reads as "present"** |
| L2 | `hide-from-slash-command-tool` **hides from the list only** — a hidden command is still callable and still hits `PreToolUse` | "Not in the subagent's list, so it cannot call it" is **not a defense** |
| L3 | **A tool named `SlashCommand` does not exist in this version** — 0 hits across 811 transcripts | A rule written against that name is **registered but watching nothing** |

**That is why the three loop rules (S4 — no arbitrary start · arguments required · one per machine) got no gate**. Blocking only the model-initiated path leaves the person-typed start untouched, and writing that half as "present" is the misreading L1 warns about.

### 1-2. Append-only for correction preservation comes from this section, not from the ledger tool [measured — `harness-dg0.6.20`]

The rule "Correction preservation" (`harness:develop` "운영 규율" — when overturning a judgment, do not delete the earlier decision; quote it with `ledger.sh note` and say what was wrong) assumes the ledger's records **are not overwritten**. Measured whether that is a tool property or a hook effect (the `beads` backend, bd 1.2.2; only help was read). The adapter passes the subcommands through, so the answer is the backend's, not the adapter's — and it is the same answer on `github`·`notion`, whose APIs also edit and delete comments.

**Conclusion: the ledger tool is not append-only.** Several subcommands edit or delete notes — `update --notes` · `edit --notes` · `sql` (direct UPDATE/DELETE) · `delete` · `import` · `restore --apply` — plus `compact`·`flatten`·`gc`·`prune`·`purge`, which shrink history. **Only `note` is append-only**, and its own help says so (`--append-notes` shorthand).

**Event preservation is a procedural rule.** State and summary records are deliberately mutable; decisions and reversals remain event notes under section 1. For subagents all of the above is already blocked — `r_impl_bd` permits implementer event notes and mutable state/summary records; structural writes remain blocked, and `r_grader_shell` narrows the grader's ledger calls to reads. Both are exemption-list style, so a new ledger subcommand defaults to "blocked". The negative control is `tests/harness/guard-check.sh` ⑬.

**Not blocked:**

| Path | Why |
|---|---|
| **The orchestrator session** | both rules judge by `agent_type`, so they are off in the parent session. Same structure and reason as `r_remote` — a hook cannot see whether the user instructed. **This half is persuasion** |
| **A path that bypasses the ledger tools** | on `beads`, raw `dolt` SQL on the same DB and editing `.beads/*.jsonl` before re-`import`ing; on `github`·`notion`, `gh` or `curl` straight at the API. In the hook `dolt` fires `r_remote` only with a `push` token, and `gh` writes are `r_remote`'s |
| **A form in which neither ledger word is readable as a name** | **none of the four roles can block it.** Every rule's entry gate is `has_token` on `ledger.sh` or `bd`, so a substitution that leaves neither literal in the command string (`B=$(printf 'b%s' d); $B update …`) never enters the judgment. What is blocked is the **literal-leaving example** (`B=bd; $B update …`), and there the three rules (`r_grader_shell`·`r_impl_bd`·`r_bd_root`) all answer with the same message through the assignment check |

## 2. Permission deny (10) — `permissions.deny` in the session tree's `.claude/settings.json`

`Read(**/.env)` · `Read(**/.env.*)` · `Read(**/*.pem)` · `Read(**/secrets/**)` — the same four anchored at the repo's own absolute path (`<clone>/**`) — plus `Read(~/.aws/**)` · `Read(~/.ssh/**)`.

- **The enforcer is Claude Code's permission engine**, not the harness's code. `bypassPermissions` does not get through [measured]. So no `checks/` gate can verify this **blocking behavior** ([guardrail-verification.md](guardrail-verification.md) section 4).
- It holds with the project `.claude/settings.json` alone — no user settings required [measured]. **The plugin cannot carry it** — permissions are not a plugin component — so a repo that opens a development session gets it only from its own settings — there is no harness-owned settings file for it to travel from.
- **`.env.example` matches the secret-file deny pattern too.** Keep real secrets protected. For public setup guidance, maintain a reviewed, secret-free template such as `config.example` outside secret-name patterns and point users to it. A filename alone does not establish that contents are safe; changing the actual deny policy requires repository-specific review.
- **So a rule that needs an exception cannot be expressed as deny.** Deny the parent and allow the child and **both are blocked** [measured `harness-uhy.3.1`] — which is why main-checkout protection (`r_main_write`) is in section 1 and not here.
- **The four absolute-anchored lines are not duplicates of the relative patterns — do not delete them.** A **project-relative pattern like `**/.env` is valid only inside the project directory**, and work happens inside `<clone>/.claude/worktrees/<worktree name>/`. Measured: with only the four relative patterns, a `.env` in the worktree and one outside the project **were read** (two canaries leaked); adding the absolute anchors turned the worktree one to `BLOCKED` [`harness-uhy.2.1`]. **With no fixed clone location the anchor is per repo** — each repo's own settings anchor at its own root, so this line cannot be shipped as one shared string.
- What gets through — 6 kinds, **all read paths; Write and Edit on `.env` are constrained by nothing**:

| # | Leaking path | Evidence |
|---|---|---|
| 1 | inline code interpreters (`python3 -c "open(...)"` …) | [measured] 2 canaries leaked |
| 2 | script smuggling — `cat .env` inside `bash x.sh` | [inferred] the hook never sees it as an event (measured); `deny` sees only tool arguments, so it shares the hole |
| 3 | paths outside the repo and outside the project | [measured — **different rule set**] with only the relative patterns, a `.env` outside the project was read. That it leaks under the shipped rules is [inferred] — the anchored lines cover only that repo's own tree |
| 4 | a clone moved after the settings were written | [inferred] rules are static strings, and the clone location is free — move the clone and the anchor points at nothing |
| 5 | a session opened in a directory whose settings carry no deny list | [inferred] a repo without the deny entries in its own settings loads no deny list (section 5, item 2) |
| 6 | a secret file name not in the list | by design — the list is an enumeration, not a derivation |

**1 can be closed with a hook, but 2 remains even then** — interpreter enumeration is not complete in principle. **So do not use this mechanism as "secrets cannot leak".** It blocks a careless accident — an agent skimming `.env` and its content landing in the ledger through `ledger.sh note` — and a principled boundary needs a different layer.

## 3. Checks (6) — the plugin's `checks/`, the ones that ship

| Check | Sees | Wired where | Run condition |
|---|---|---|---|
| `board-check.sh` | **Ledger structure** — sprint ID format · `rail:` labels ↔ the rail registry · `sprint:` labels ↔ the sprint registry both ways (+status) · label inheritance and ancestor existence of sprint descendants · acceptance of sprint tasks. **Both registries come from the adapter** (`ledger.sh rails`·`sprints`); this check opens no registry file, so what backs them is the backend's business — `beads` reads the root's `rails.json`·`sprints.json`, `github`·`notion` derive them from the ledger itself. Does not look at projections | `tests/run-all.sh` · cycle close in a target repo (`harness:develop` "사이클 종결" step 1) | the ledger through `scripts/ledger.sh`, at the root `lib/harness-root.sh` prints; root or `.harness.json` not found → rc≠0, never a silent skip |
| `ledger-check.sh` | **The ledger is ahead of its remote** — the silent-loss path. Goes through `ledger.sh sync-check [--push]`: in write mode (`LEDGER_CHECK_PUSH=1`) the `beads` backend runs `bd dolt push` instead of blocking, **recounts the tracking refs**, and blocks only if still ahead; without the switch it reflects nothing and only says so. On `github`·`notion` there is nothing to reflect, so it is `원격 반영 대상 없음` and rc 0 | cycle close in a target repo (read mode, before and after the explicit ledger reflection) · the skills repo's `tests/run-all.sh` exempts it (remote dependence). **Write mode (`LEDGER_CHECK_PUSH=1`) has no automatic caller** — the harness-root push hook that set it is gone, so reflecting is the orchestrator's explicit step | on `beads`: `dolt`, an embedded ledger, and a Dolt remote; otherwise fail-open with a warning. **A pass phrase says `건너뜀` or `앞서 있음(반영하지 않음 — 쓰기 모드 아님)` when nothing was judged** — never `확인됨` |
| `guardrail-check.mjs` | S1 policy with positive/negative controls · S2 generated hook wiring · S5 executable sources · S6 ledger sync fixtures · S7 Stop paths | `tests/run-all.sh` via the compatibility wrapper | Node and Git, temporary offline fixtures. Missing runtime or unreached assertions fail; fixture success does not prove live hook activation |
| `rules-check.sh` | Static assertions **on the ledger** — R5 one `repo:` label per task · R-ACC acceptance of started tasks · **S22** two actors in one (story, repo) worktree · **S24** an open story whose children are all terminal. Which read zero items as failure and which fall back is written in the script's header | `setup` 1.5·2·3, and `tests/run-all.sh` during development | the ledger through `scripts/ledger.sh` at the root `lib/harness-root.sh` prints (resolved from the caller's cwd). **S22 counts worktrees of the repo the run stands in only** — with no fixed clone location the harness cannot see another repo's worktrees, so a row for another `repo:` label is reported and not judged; running the gate in each repo covers the whole set. The assertions on the **plugin tree** (R-REM · C6 · R-DATE · R-BEAD · R-WAIT · R-DUP · R-BUDGET) are not here — they judge an artifact that can only change before release, so they live in the skills repo as `tests/harness/doc-rules-check.sh` |
| `workspace-check.sh` | Read-only Git identity and repository config of the supplied workspace (default: cwd) | `tests/run-all.sh`, or manually before entry | All backends; no ledger or remote calls. Roundtrip and failure fixtures live in the source repository’s `tests/harness/workspace-contract-check.sh` |
| `transcript-check.sh` | Required invocation inventory and runtime transcript observations — source-derived A9, partial coverage, token availability and role/tool aggregates. [Runtime observations](transcripts.md) owns formats and limits | retrospective 1-2; not a commit gate over private runtime data | Node; explicit scoped inventory or the Claude directory adapter. Missing/unfinished/unsupported evidence gives UNREACHED, rc 2. `--self-check` keeps A9 negative controls |

**The development-time checks are not in this table.** Every check that hits plugin code with a fixture lives in the skills repo under `tests/` and never ships — the list, with the same four columns, is that repo's `docs/development.md`. A check is in this table only if an installed copy runs it.

**Nothing in the table is wired to a git hook.** Target repository hooks belong to that repository. These checks run through the named procedure steps or explicit invocation.

## 5. Deployment — what the marketplace does not carry

The core reaches a project as a plugin install (`claude plugin install harness@skills`), and updates as a marketplace update. The plugin carries skills, agents, hooks, checks, scripts, and the always-on block. **It does not carry settings or anything a repo owns** — that is the list below. New items go here so nothing is assumed shipped.

| # | Item | Why not automatic | Who does it |
|---|---|---|---|
| 1 | **`permissions.deny` (section 2) and `permissions.allow`** | permissions are not a plugin component | the `.claude/settings.json` of each repo a session opens in, committed to that repo |
| 2 | **A session opened in a directory with no harness settings** | no deny list is loaded there. The plugin itself does load — it is a user-scope install, so it is not what is missing | open every session in a repo that carries the entries — planning sessions included, since there is no other place to open one |
| 3 | **Git hooks** (commit gate · push gate · render) | **the harness plants no git hook anywhere** (story `harness-lzs3`) | every gate fires as an explicit step instead: the orchestrator runs `board-check`·`ledger-check` and the backend's ledger reflection (`bd dolt push` on `beads`) at the cycle close |
| 4 | **The harness root marker** (`<repo>/.harness.json`) | the harness root **is** the target repo, and this committed file is what makes it recognizable — `lib/harness-root.sh` looks at `HARNESS_ROOT` and then walks up from the cwd to the first one | a person writes it once and commits it (`harness:setup` section 5); after that, cloning the repo carries it |
| 5 | **Taking a settings or plugin change into effect** | hooks, permissions, and plugin versions load at session start; an agent cannot restart its own session | a person restarts the session, then confirms a hook by **what it blocked**, not by its presence |
| 6 | **Enabled but not installed** | `enabledPlugins` turns a plugin on; installing it is a separate action, and the runtime silently skips the hooks of a plugin that is not there | `claude plugin list` shows what is installed. `${CLAUDE_PLUGIN_ROOT}` resolves only for a plugin the runtime has, so an uninstalled one does nothing rather than reaching a wrong tree. No gate — [guardrail-verification.md](guardrail-verification.md) 8-1 |

## 5-1. Ledger reflection — an explicit step, with no gate behind it

**No push hook exists anywhere**, so the ledger never rides a `git push`. The orchestrator runs the backend's ledger reflection as an explicit step of the cycle close — the steps and the failure table are owned by `harness:develop` "사이클 종결". Skip it and the ledger stays a local-only copy (`beads` only; on `github`·`notion` every write was already remote).

Why ledger reflection is allowed without a fresh instruction: `git push` is itself an action that requires explicit user instruction, so that moment is already approved, and ledger reflection tied to it is within the same approval (user decision, `harness-bjj`). **The exception grew by one — the working-branch push and PR creation of a cycle close** (`harness-dg0.6.7`), on the same approval logic: what is irreversible is the **merge**, and **a person still merges.** Their triggers differ — ledger reflection is tied to a person's push, the cycle-close push is automatic only when no decision is unresolved. The boundary: **this far it is working-branch push and PR creation for repos carrying `.harness.json`**; merge · tag push · release · GitHub issue changes · remote configuration · direct default-branch push · unregistered remotes stay explicit-instruction. The text is the session block's "절대 금지"; the approval boundary's evidence is `harness-dmy`.

**Neither exception has a gate — for both, the judgment is invisible to code.** Ledger reflection is now a step someone has to run, not a hook that re-judges. **And the PR exception's two axes cannot be seen at all.** Left (is a decision unresolved): of the human-wait signals only `status=blocked` shows in a ledger query; the rest (`SCOPE_EXCESS`·`DEVIATION`·`DECISION_NEEDED`·retry progress exhausted or explicit user budget reached) live in note bodies with no status transition. Right (did the user approve): a hook has **no path at all** to see it. A check counting only `blocked` reports 0 on the rest and passes — exactly the case the exception meant to stop; the rule to read a zero-item pass as failure lands here. **So this exception is persuasion toward the orchestrator.** Building it needs a status transition or a dedicated marker **first**.

**For subagents neither is an exception.** Both belong to the orchestrator; a subagent stops at local commits — `r_remote` holds that line (section 1). Its denials quote `harness:develop` "사이클 종결" ("Subagents are out of scope — up to the local commit"): **what changed is when the orchestrator may, not who.**

An **attempted** reflection does not pass the check. Not `bd dolt push`'s exit code but a recount of the tracking refs decides. The pass phrase distinguishes `확인됨` (was in sync) from `이번에 수행함` (resolved by the reflection).

**`ledger-check.sh` reflects only with `LEDGER_CHECK_PUSH=1`, and nothing sets it automatically any more.** Every call it actually receives — a role comparing state, a person checking a document, the cycle close in a target repo — has no switch and **reflects nothing.** If the ledger is ahead then, rc is 0 and the phrase is `원격 반영 앞서 있음(반영하지 않음 — 쓰기 모드 아님)` — the judgment is not silenced, and it differs in letters from `확인됨`. The default is the safe side: `guardrail-check` S6 ⑤ asserts that a switchless call leaves `ahead` alone (`harness-x0i.2.1`). **So reflecting is the orchestrator's own step**, and the write mode survives as the way that step can be spelled.

**`r_remote` cannot see this check** — the rule looks for a push subcommand in the command string, and this call is `bash …/checks/ledger-check.sh` with the reflection inside the script (section 1's "scripts are not seen"). So a call that **explicitly sets** the switch is not blocked by the hook.

| Condition | Why silent | Resolution |
|---|---|---|
| the ledger is ahead of `remotes/origin/main` (`beads` only) | the ledger sits in `.beads/embeddeddolt/`, `.gitignore`d; git says nothing | the explicit ledger-reflection step of the cycle close — nothing does it for you |

**Fail-open boundary** (`ledger-check`): no `dolt` · no `.beads/embeddeddolt` (server mode, or a repo without a ledger) · no Dolt remote → warn and pass. Conversely a ledger that **exists** and is ahead is not "unavailable" but failure.

### Limits (what it cannot block)

1. **`remotes/origin/main` is a local cache updated only at push and pull.** It catches "what I did not upload" exactly, but not "what others uploaded". Right for this gate's purpose, not a general sync judgment.
2. **Meaningful only where a local ledger exists — that is, on `beads`.** On `github`·`notion` every ledger write is already remote, so there is no un-reflected state to find and it says `원격 반영 대상 없음`.
3. **Nothing fires it on its own.** No git hook runs it, so a session that only piles up ledger writes is judged by nobody unless the cycle close runs the step. Nothing hangs at session end either — the `Stop` hook fires every turn and is the wrong place.

## 6. Rules without a gate yet

The survey (`harness-uhy.1.2 note`) sorted 54 candidates into **fit 30 / unfit 18 / undecided 6**. Of the fit 30, 6 (C1·R1·R2·R3·S7·S18) already had a check; **24 were new work.** Their state:

| State | Count | Items · where |
|---|---|---|
| **Implemented** | 10 | the seven hook rules of section 1 cover C2·C3·A1·A2·A3·A4·A5·R19·S3, and `rules-check.sh` covers R5. **S12** and **R18·R40** have nothing to assert: the harness root is a target repo rather than a directory of its own, and there is no repo registry — the rules' subjects do not exist, which is not "unimplemented" but an empty subject. A8 (`harness-dg0.6.25`) is persuasion only — no hook carries it, and the implementer definition is the whole of it (it forbids leaking this ledger's bead IDs into a target repo's commits) |
| **Not implemented — scope reduced by user instruction (deferred)** | 11 | C5→`harness-uhy.5.3` · R20→`5.4` · S1·S2→`6.1` · S11·S15→`6.2` · R8·R16→`7.2` · R4·S5→`7.3` · R17→`7.4` |

**Zero fit items remain unregistered** — all 11 exist as beads. Two more, found outside the survey and deferred with them: `harness-uhy.5.5` (blocking a subagent's worktree-script execution — moot now that creation is the native tool) · `harness-uhy.7.5` (orphan worktree detection).

**deferred is not remaining work** (`harness:develop` "결정 상태"). It is the third state a user closed explicitly; it does not block completion and does not appear on the remaining list. It is written here **so the next round does not repeat the discussion**, not to propose reopening. If circumstances change, ask in one line.

**The unfit 18 are a decision not to attach a gate** [`harness-uhy.1.2`] — all judged "the violation is silent, yet no gate":

| Class | Items | Common reason |
|---|---|---|
| natural-language quality judgment | C4 · R6 · R13 · S8 · S10 · S14 · S17 | a pass would be a **false signal** that means quality. Checking form replaces the rule with form |
| equivalent variants of a command string | R12 · A7 | shape enumeration leaked three times (front matter, item 3) — the same failure repeats here |
| acts outside the tool boundary | R14 · R15 · A10 · S9 · S13 · S16 | conversation, order, and periodic human activity do not appear as tool calls a hook sees |
| gain < cost | A6 · S6 | the harm is small (S6), or an approximate check blocks more legitimate work than it catches (A6) |
| cheaper to block the outcome than the procedure | R21 | C3 already covers the same harm |

**What the undecided 6 required, and what was answered:**

1. **Can a hook see a subagent's reply body** (R9 · A9)? Only that `agent_type` rides on child **tool calls** was measured. `SubagentStop` carries `last_assistant_message` — [guardrail-verification.md](guardrail-verification.md) section 9 — but after the reply, not at the tool boundary.
2. **Do slash commands appear as tool calls a hook sees** (S4)? → **Answered. Section 1-1.**
3. **Is `bd note` append-only** (R10)? → **Answered. Section 1-2 — no.**
4. **Does `bd` have other spellings of `-C`** (A4)? → **Answered.** The `r_bd_root` row lists `-C`·`--directory`·`--db`.
5. **Can "is this check inverted-polarity" be decided statically** (R11)? No general method found.
6. **Role-separation observations (R7).** The Claude adapter joins Agent/Task invocation identity with child attribution; ordinary workflow verifies native outcomes against hook role/instance chains. This supplies identity evidence, not a blanket judgment of every natural-language role-separation rule.

**One place is misaligned the other way.** Secret-file handling (X1) has **a gate and no rule sentence** — the deny 10 came first. The survey judged "what protects `.env` today is not a rule but an accident."

## 6-1. No mechanism (8) — places with nothing but persuasion [`harness-pl7` 6.4]

Section 6 covers rules without a gate, most of which still have **after-the-fact detection, a checklist, or a report-format constraint**. The eight below have **not even that** — the residue after the root-B audit sorted the substitute mechanisms of the 39 "cannot be gated" items.

**This document starts from mechanisms, so an item without one has no natural place.** It is pinned here so that a reader of sections 1–5 does not **read "covered" from "read".** Line numbers are not copied (they rot); exact locations are the same-ID rows of `harness-dg0.2.3 note`. Paths are plugin-relative.

| # | Rule sentence (where) | Why no mechanism |
|---|---|---|
| C8 | "Explicit user or orchestrator instructions override this Beads block" (`AGENTS.md` bd block) | the interpretation of instruction precedence exists only in conversation — **there is nothing to compare against**. What remains is **persuasion only** |
| R27 | "When a story is stuck, record the story alone and move on to the next" (`skills/develop/SKILL.md` "운영 규율") | a **choice** in procedure flow, not observable as a tool call. What remains is **persuasion only** |
| A15 | "Check that a new constraint does not close an exit" (`agents/reviewer.md`) | finding a conflict between rules is natural-language reasoning. What remains is **persuasion only** |
| A17 | "Which acceptance item does each hunk of the diff belong to" — incidental/excess/intrusion/omission and signal priority (`agents/evaluator.md`) | attribution is natural-language reasoning and **the role definition itself admits false positives**. What remains is **persuasion only** |
| S6 | "Do not bootstrap (install dependencies) by hand" (`skills/develop/SKILL.md`) | an approximate check blocks more legitimate local debugging than it catches, and the harm stops at a duplicate install — gain < cost. What remains is **persuasion only** |
| S9 | "Ask before promoting: **does this change follow the repo's convention, or leave it?**" · "**Count directly** …" (`skills/plan-story/SKILL.md`) | the gate is **a conversational act with a person**. What remains is **persuasion only** |
| S14 | "Describe what the project is for **only after user confirmation**" (`skills/setup/SKILL.md`) | whether the user confirmed exists only in conversation. What remains is **persuasion only** |
| S23 | do not start on another actor's claim · "reclaiming … is what a human confirms and directs" (`skills/develop/SKILL.md`) | the second sentence (reclaim instruction) exists only in conversation. The first is covered by the atomicity of `ledger.sh update --claim`, **which is a backend property, not a hook, deny, or check** (R10's reason). What remains is **persuasion only** |

**All eight are of the classes `[outside the boundary]` · `[natural language]` · `[gain<cost]`** — the gate was not left unbuilt; **there is no place to build one.** `A17` is special: it is **the substitute mechanism for two other items (A6·A12) while having none itself**, so the after-the-fact chain ends here in natural-language judgment.

Whether this list equals the 8 of `harness-pl7` 6.4 **as a set** is counted both ways. **The counterpart is that decision's projection** — the original is the ledger and `docs/adr/` is drawn by the plugin's `board.sh adr`, so in an unrendered tree the left side is empty and **an empty match is read as failure**:

```bash
A=docs/adr/natural-language.md; G=${CLAUDE_PLUGIN_ROOT}/docs/guardrails.md   # A is the projection of harness-pl7
ids() { grep -oE '^\| [CRAS][0-9]+' "$1" | tr -d '| ' | sort; }
[ -s "$A" ] || echo "no projection — run board.sh adr first (do not read an empty diff as a match)"
diff <(grep -F '**장치 없음**' "$A" | ids /dev/stdin) \
     <(awk '/^## 6-1\./,0' "$G" | ids /dev/stdin)          # no output = the sets match
awk '/^## 6-1\./,0' "$G" | grep -cE '^\| [CRAS][0-9]+ \|.*persuasion only'   # 8 = written on each of the eight
```

**A value other than 8 and a non-empty diff are both failure.** A 0 on the first means the set matches but "persuasion only" is missing, and then this section is **a list that says a mechanism is absent without saying what that means.**
