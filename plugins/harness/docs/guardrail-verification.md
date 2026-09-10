# Verifying the enforcement mechanisms, and as-built observations — how to confirm, and what was observed

> The **full list** of guardrails and gates (what is blocked) is [guardrails.md](guardrails.md).
> This document is its pair: **how to confirm** (section 4) and **as-built observations** (sections 7 · 8 · 8-1 · 9 · 11).
> **Section numbers continue from that document** — other documents and scripts point at "section 8" and "section 11" by number, so the numbers stay and a retired section leaves its number vacant rather than renumbering the rest. Sections 1 · 2 · 3 · 5 · 5-1 · 6 · 6-1 are in guardrails.md, not here.
> Structure: [architecture.md](architecture.md). Engineering discipline: [engineering.md](engineering.md).
> Paths written as `hooks/…` · `checks/…` · `scripts/…` are inside the plugin `harness@skills` (`${CLAUDE_PLUGIN_ROOT}`, `plugins/harness` in the skills repo); `docs/…` · `.beads/…` · `.claude/…` are harness-root-relative.

## 4. Verification — how the enforcement mechanisms are confirmed

- **Confirm by blocking behavior, never by presence.** A rule can be registered with its function present and block nothing because of a typo in the judgment; a presence check passes it.
- **A/B attribution is the only attribution.** `checks/guardrail-check.sh` S1 feeds each rule the synthetic stdin it must block and requires rc=2, and **requires the same input to return rc=0 in a copy with only that rule's registration removed.** Without the second half, a block by some other rule reads as "this rule is alive". The denial string does not say which rule fired — that is the measured conclusion of `harness-uhy.2.1 note`.
- **A gate leaves its own negative measurement** — the normal path rc=0 and a deliberately broken path non-zero, both in the commit message.
- **Distinguish three refusal strings; otherwise a leaking path is misread as blocked.** Only the first two are blocks.

  | `tool_result` text | What it is | With a person present |
  |---|---|---|
  | `File is in a directory that is denied by your permission settings.` | Read blocked by `deny` — **a real block** | cannot be punched through |
  | `Permission to use Bash with command <cmd> has been denied.` | Bash blocked by `deny` — **a real block** | cannot be punched through |
  | `This command requires approval` / `Claude requested permissions to read from <path>, but you haven't granted it yet.` | matched no rule and fell to an approval prompt, auto-refused because non-interactive — **not a block** | one approval button passes it |

  In the default permission mode `python3 -c` shows the third line, and the same command passes under `bypassPermissions` and spits the canary. To be sure, run a `--permission-mode bypassPermissions` control — `deny` holds even there, so a pass there is a real pass [measured `harness-uhy.2.1`, reproduced both ways].
- **Assert registry integrity from the source and behavior.** `lib/guard.mjs` owns exported `r_` functions and ordered `RULES.push` registrations. The dispatcher validates callable entries before matcher comparison. `tests/harness/guard-source-fixture.mjs` derives definitions and registrations in both directions, checks ordering/prefix/duplicates/nonempty populations, and mutates source copies. The complete legacy `guard-check.sh` corpus now executes that Node policy. Historical Bash measurement `harness-uhy.3.5` established why a missing registration needs its own negative control; its old `RULES+=` syntax is not current production policy.
- **Environmental unavailability is not a pass.** Native handlers need Node, not jq/Bash/Python. Node-only PATH fixtures prove allowed reads and denied writes still work; missing Node, invalid JSON, unknown role and broken source have independent failure controls. The native guardrail check has no jq skip. Claude exec launch failure is kept distinct from a completed hook with rc 2.
- **Compare every firing condition and transport field.** S2 compares the common registry with generated Claude and Codex metadata, including event, matcher, command, Claude args and Codex commandWindows. Missing/duplicate entries and drift fail. A separate transport fixture actually launches generated commands (Codex Windows uses the CLI's cmd.exe outer quoting); neither test establishes trust, runtime loading or real hook firing. The historical matcher-only miss is the reason S2 compares the full contract.
- **What it cannot catch**: a surface erased **on both sides at once** (a rule function and its test; `hooks.json` and the hook file) looks like an agreed change, not drift. That requires editing the check file itself, which is visible in review.

### 4-1. The counts these documents carry — what is checked and what is not

These two documents are the full list, so they carry numbers. **The only ones that can rot are counts claiming the size of a set in the current tree.** Three classes, three treatments:

| Class | Example | Treatment |
|---|---|---|
| **current-tree claim** | counts in document headings | The native guardrail check asserts its five `SURFACES`, derives rule/registration/probe populations and Stop outcome/log populations. It does not parse every number in prose; headings must change with their owning population |
| **frozen point-in-time observation** | transcript file counts · ledger record counts · violation counts | the value and its date go to the ledger note of the bead that measured it; the document keeps the conclusion and the bead pointer. When a flowing value is evidence, write movement and ratios rather than absolutes (section 8 ceiling 3 · section 9) |
| **inline self-enumeration** | "6 kinds (inline interpreters · script smuggling · …)" in [guardrails.md](guardrails.md) section 2 | the value and the enumeration sit together, so a mismatch shows in the text. No machine comparison |

### 4-2. What is written as "cannot block" — measuring that it is not blocked

**One check runs the opposite direction.** Where the items above ask "is what must be blocked blocked", `tests/harness/guard-check.sh` pins **"is what is written as not blockable actually not blocked"** — the limits in the "not blocked" column of [guardrails.md](guardrails.md) section 1 that have an rc=0 fixture (the relative-path and symlink cases of ⑨ · for `r_remote`: `WebFetch` to the GitHub API, `curl -X POST` to `api.github.com`, `git remote set-url` (`RM_LIMIT`) · `git branch -D` for graders · the false-positive sets `BD_FALSEPOS` and `RM_FALSEPOS`). When a rule is widened and a limit is closed, that fixture flips to rc=2 and the gate breaks loudly — the rule *"a limit pinned as rc=0 is moved to a blocking assertion when closed, not deleted"* is meant for exactly that. **When it breaks, the job is not to delete the line** but to move it into the blocking set and fix the column in guardrails.md in the same change. Delete it and the closure disappears from the gate, and the same hole can reopen unseen.

**What this pinning cannot see.**

- **One shape per item.** A column that enumerates several shapes has one fixture. Splitting the column further would be parsing natural language.
- **[guardrails.md](guardrails.md) section 2 and the "Limits (what it cannot block)" list of 5-1 have no fixtures.** The former's enforcer is the permission engine, so no hook emits an rc; the latter's judgment is a tree, a remote, or an install configuration, not one command's rc — the configuration side is S6's fixtures.
- **A single rc=0 cannot tell "this shape leaks" from "the rule is dead".** That the rule is alive is S1's blocking assertion, and the check asserts the pair exists.

## 7. No git hook is planted anywhere — the ledger checks are explicit steps of the cycle close

**The harness plants no git hook at all** — not in a target repo (story `harness-lzs3` decision; it closes `harness-v8n`), and not at its own root, which is a plain directory and no git repo. So in a worktree a commit runs only that repo's own hooks, and a push runs no ledger check. `board-check` and `ledger-check` are run **by the orchestrator, as explicit steps of the cycle close** — the steps are owned by `harness:develop` "사이클 종결" and not restated here.

**What that means for evidence.** "The commit succeeded" is never evidence that the ledger was checked in a target repo — only "the check was run, and here is its rc" is. The failure table of the cycle close names each step's failure a **close incomplete** and the story stays open; that is the whole mechanism. **There is no gate** on whether the orchestrator ran the steps — the checks run at its hand, and `r_remote` does not see `bd dolt push` typed by the orchestrator (it is not a subagent).

**There is no exempt tree.** The harness's own core lives in the `skills` repo, which is a target repo like any other and gets the same treatment — the checks fire because a step runs them, nowhere because a hook does.

## 8. The stop guard — `lib/stop.mjs` (Stop; legacy `hooks/stop-resume.sh` wrapper)

When confirmed session work remains `in_progress`, the Stop guard may push back. Its paths are `BLOCK`, `IDLE`, `RECURSE`, `GAVE_UP`, `ORACLE_FAIL`, `CANCEL`, `VERIFY_PENDING` and `SCOPE_FAIL`. SCOPE_FAIL continues to a judgment path and writes two records; unavailable state produces an explicit UNREACHED diagnostic instead.

State identity, paths, locks and cancellation are defined in [Runtime state](state.md). The Node resolver separates runtime/repository/session state and preserves legacy files without promoting them to successful observations. Storage failure is diagnosed; the Stop guard allows exit without claiming that work is idle.

**The ledger is reached through the common Node adapter/root resolver** — `HARNESS_ROOT`, else the first `.harness.json` walking up from the payload cwd. Not found → `ORACLE_FAIL` and allowed exit, never an idle claim. S6 uses the real backend with an injected process seam; it never contacts the live ledger or remote during the check.

**Only ledger-confirmed actor bindings narrow the oracle.** After claim succeeds, `state.mjs bind` re-reads the task and verifies its status and actor; the state contract suite tests this boundary. PreToolUse writes no successful mapping. S7 supplies isolated matching and mismatched scope records and removes narrowing in a source mutation. Missing or legacy-only bindings leave the whole-ledger scope and emit SCOPE_FAIL.

**Verification-pending and just-delegated share one mark contract** [lineage `harness-2a5.4.2` · `harness-o59`]. `VERIFY_PENDING: <commit>` marks implementation awaiting verification; `DELEGATED: <milestone>` marks a batch just delegated. The latest matching marker line wins, so later prose does not erase a mark and a later DELEGATED supersedes VERIFY_PENDING. All marked issues pass (mixed marks included); any unmarked issue blocks, with both counts in the reason. S7 tests each marker, prose, mixed/rework/missing marks and independent marker-removal mutations. This supersedes the historical last-nonempty-line behavior. A malformed list is ORACLE_FAIL, never zero work.

**An unreadable oracle does not become zero work.** At three re-injections in the session log, the guard stops blocking. To stop immediately, use the explicit runtime/repository/session cancel command in [Runtime state](state.md); another session cannot acquire cancellation by observing a shared marker first.

### Ceilings (what it cannot do)

1. **The oracle is ledger-wide; the narrowing is the judgment after it.** When the mapping cannot be read (`SCOPE_FAIL`) every session that runs this hook is pushed back at every stop, up to three times, even one working on something unrelated. The scope: the hook is plugin-wide and the plugin is a single user-scope install, so it runs in **every session on that machine** — the harness root, every clone, and any directory unrelated to the harness alike. The lower bound: **a session whose `cwd` reaches no ledger always passes** (`ORACLE_FAIL`).
2. **Direct checks cannot establish runtime firing.** S2 checks metadata and S7 executes the common handler with isolated ledger/state fixtures, exact outcome counts and source mutations. Doctor separately requires actual loaded-artifact, hook and role receipts. Neither direct handler tests nor generated-command launches prove that the runtime honors `decision: "block"`; absent actual evidence remains UNREACHED.
3. It **pushes back but does not guarantee resumption.** Whether `decision: "block"` stops the stop is a runtime contract, not confirmed by execution in this tree.
4. **The oracle counts wider than the acceptance text.** The text says "in_progress **tasks**"; the hook counts every `in_progress` **issue** — a milestone or story in `in_progress` is in-progress work too. Same value today; the day milestones are moved to `in_progress` by operation, the hook blocks more often than the text. Narrowing is one `--type task` in the oracle call.
5. **A session waiting for a person is blocked too — a status transition was not introduced** [decision `harness-dg0.6.16`]. On a human-wait signal (the list is owned by `harness:develop` "사람 대기") the task stays `in_progress`; the oracle counts it, so a legitimately waiting session's stop is pushed back. Cost: at most 3 wasted turns per session lifetime, one per stop cycle (path `RECURSE` passes the re-stop right after a block). `blocked` was not adopted because it already means the opposite ("walk past it" — `IMPLEMENTATION_BLOCKED`), the wanted thing already exists as the one-turn cancel marker, and the human-wait signals other than `blocked` are visible only in `bd note` bodies — making them visible needs a dedicated marker, out of that decision's scope.
6. **Binding is separate from claim execution.** Failure to persist a verified binding leaves the successful ledger claim intact and the state mapping UNREACHED. Stop retains the whole-ledger fallback until bind succeeds; a failed claim is never inferred as success from PreToolUse.
7. **An unbound claim widens the scope.** A claim without a successful explicit bind leaves Stop at `SCOPE_FAIL`, judging the whole ledger. The actual ledger actor must be supplied to bind; PreToolUse command text and implicit actor defaults cannot establish ownership. The missing mapping does not produce `NO_CLAIM` or prove that this session has no work.
8. **Deleting the mapping requires an explicit rebind.** The runtime/repository/session `actors.json` is ordinary state storage. If it disappears, Stop logs `SCOPE_FAIL` and judges the whole ledger until `state.mjs bind` verifies and persists the current ledger actor again. A subsequent claim alone does not restore the mapping. Actor bindings are not rotated with diagnostic logs.

### Measured — the Stop hook fires while a subagent is alive

**A live background subagent does not keep the session from reaching Stop — the Stop hook fires inside a subagent's liveness window** (measured from one session transcript; the counts are in the `harness-m8gg.8.12` note). What kept the loop plugin then in use stuck at `iteration` 1 was not a firing failure but a **registration failure**: every `stop_hook_summary` record ran only the loop-cancel hook this harness wired at the time, because the loop plugin was in `enabledPlugins` but not in `installed_plugins.json`, with `.orphaned_at` in its cache. Not "a layer that does not fire" but **"a plugin that is not installed"** — the case section 8-1 is about.

## 8-1. Enabled but not installed — what silently dies [`harness-dg0.6.35`]

**The shape of the mismatch**: `enabledPlugins` in a settings file **turns a plugin on**. Turning on and **installing** are different — a settings file can name a plugin the machine does not have. "Registered everywhere, installed nowhere" is a normal product of a fresh clone. Measured (`harness-dg0.6.35`): a project `.claude/settings.json` named `harness@skills` and a loop plugin from `claude-plugins-official`, and a new clone had installed neither.

**What silently dies in that state**:

- **Every** hook, skill, and command of that plugin — not some, all.
- **No signal.** The settings file does not know whether what it names is installed, and the runtime simply does not call the hooks of a plugin that is not there. No error, warning, or log.
- So **"a state in which a mechanism is believed present" is created.** This project paid that cost once: a loop ran nine hours with `iteration` at 1, and the orchestrator, seeing `hooks.json` in the cache, concluded "plugin hook registration is normal" and built a **false hypothesis** on top (section 8's measurement).
- **Files remaining in the cache and a plugin being alive are different things.** The misjudgment was exactly that confusion — the cache directory was there, with `.orphaned_at` inside it.

**Current diagnosis is doctor**, documented in [installation.md](installation.md). It distinguishes expected source from loaded content/version, installation from hook receipts, and role registration from role execution. Inactive/missing hooks and unsupported identity evidence remain UNREACHED. S2 remains an artifact check, not an installation oracle. The incident above describes historical Claude installation behavior, not a Codex installation contract.

**Ceilings**

- **`claude plugin list` is a registration check, not a firing check.** Installed does not prove its hooks run — section 8 ceiling 2.
- **The cache's `.orphaned_at` is not a discriminator on its own** [`harness-dg0.6.43`]: it was observed coexisting with `.in_use/<pid>` while the plugin's skills were alive in the session. At most it means "collection candidate".
- **Historical highest-cache-version discovery was insufficient.** Current diagnosis requires the expected and observed artifact identities to agree; merely finding a newer cache directory never proves that version loaded.

## 9. Where runtime observations are read — `checks/transcript-check.sh`

[Runtime observations](transcripts.md) owns format selection, ordinary inventory, aggregate completeness and token semantics. The check is the retrospective entry; runtime decoders live in `lib/transcripts/`. Retrospective calls the entry and never parses raw records itself.

A9 checks the exact first-line SIGNAL against the source role vocabulary. The clean/dirty and asynchronous notification negative controls remain in `--self-check`; `tests/harness/transcript-contract-check.sh` also checks missing/unfinished calls, unknown formats and mixed reached/unreached populations. Existing measurement lineage is `harness-dg0.6.18`, `harness-m8gg.8.12` and `skills#264`.

The ordinary workflow records required calls before invocation and validates native returns against subsequent hook observations. Historical Claude directory scans derive invocations from Agent/Task records. Completion-only fragments cannot establish the population, and a missing completion is retained as UNREACHED. Other natural-language discipline items do not gain a judgment merely because their data can be read here.

### Ceilings

1. The live transcript directory and session inventory are outside the commit tree. A commit-gate result does not replace running this check over the intended session/window.
2. An incomplete inventory yields a partial aggregate and nonzero exit. Ratios require a known, complete denominator and attribution to the story. Token UNKNOWN is separate from SIGNAL violation.
3. Native on-disk rollout and exec JSONL are different inputs. Unsupported formats and missing native wait identities remain UNREACHED; neither role prose in prompts nor a final success sentence repairs them.
4. A task-notification alone cannot identify a role invocation. Unmatched notifications stay unresolved instead of being silently dropped. Known background jobs may therefore need a narrower explicit inventory.
5. Historical multi-signal transcripts expose reuse counts, but their final reply does not prove that every earlier review was valid. Ordinary role results require fresh instance identity and reject repeated lifecycle chains.

## 11. When firing counts can be used as evidence

Use `node <plugin>/scripts/guard-log.mjs --runtime <runtime> --data <absolute data> --repo <absolute repository> count|rows [session]` for scoped observations, or explicitly choose `--log <absolute legacy TSV>`. The old `guard-log.sh` delegates to the same Node implementation. **When counts are evidence** is pinned here: "0 false positives" and "logging did not happen" must remain different outcomes.

**Both subcommands are covered here** — `count` (round × rule firing counts) and `rows [<round>]` (one line per blocked call, with a classifiability column). This section owns **what those numbers mean and what they cannot see**; the procedure that reads them on a schedule is `skills/retrospective/SKILL.md` section 1-3, and it points back here rather than repeating the table below.

### Conditions — only when all three hold

1. **The loaded `lib/guard.mjs` has the logging call.** Source changes do not establish execution in an already-open installed session. Doctor distinguishes expected source from observed artifact; legacy TSV counts have unverified scope.
2. **The counting command reads the log the hook writes.** Both use the Node state resolver. Supply the active runtime and actual plugin data directory to ordinary CLI calls, or explicitly select a legacy TSV. A home-path guess is not evidence that this is the current hook log.
3. **The round column has not collapsed.** A payload without `session_id` folds rounds into `-` (⑯ (e) pins that value).

### Every kind of absence — told apart by rc and phrase

**Reading two of these as one is how "0 false positives" gets fabricated.** rc=4 says the blocking really was 0; rc=6 says blocking happened and none of it can be classified. A retrospective that folds rc=6 into rc=4 reports a clean rule that was never measured.

| State | rc | Usable as evidence? |
|---|---|---|
| rows or counts come out | 0 | **yes.** Round × rule counts, and the per-row axes, are machine values |
| no log, and **the inspected `lib/guard.mjs` has the logging call** | 1 | Observation UNREACHED: check hook execution, selected path and logging failure; absence alone does not prove the hook never ran |
| no log, and **the inspected `lib/guard.mjs` has no logging call** | 3 | **not "0 firings".** The inspected artifact cannot emit guard observations |
| log present, **0 blocked rows in range** (`rows`) | 4 | **yes** — blocking really was 0. The one rc that licenses "no false positives in this range" |
| the **given round** has no row at all (`rows <round>`) | 5 | **not "0 blocked".** Rotation dropped it, or the round name is wrong |
| blocked rows exist but **all are unclassifiable** (`rows`) | 6 | **no.** Not "0 false positives" — **could not be counted.** Read it as an unmeasured round, never as a clean one |

rc=2 is neither: an unknown subcommand, i.e. an operator typo, checked before the log is even read so it cannot come back as rc=1.

The rc=0/1/3 branches are reproduced, and a copy of the counting command with the distinction removed is shown unable to tell them apart, by `tests/harness/guard-check.sh` ⑱; rc=4/5/6 are pinned against synthetic logs by ⑯ (h).

### Ceilings (what it cannot do)

1. **Counts alone do not identify the loaded artifact.** The command inspects its own plugin tree when distinguishing logging absence. Compare that tree with doctor receipts for the actual session; a TSV alone, especially a legacy TSV, cannot establish version or runtime identity.
2. **rc=3 separates only the cause of absence.** A non-empty log with a non-logging version mixed in (sessions on different plugin versions) is not caught — that round's rows are simply missing, and missing rows appear under no rc. **A miss remains, and it is the more dangerous shape.**
3. **Rotation loss and missing session identity reduce the observed population.** The shared state resolver owns persistence and rotation; missing records cannot establish a clean session.
4. **Legacy commands cut at 120 characters remain truncated evidence.** The Bash-era `skills#228` observation counted 240 of 449 blocked rows as truncated; that is a frozen measurement, not a current rate. Native `rows` measures Unicode characters and retains the `truncated` classification for those records. The denominator of a classifiable false-positive rate is the `ok` rows alone. Updating the installed writer cannot recover past text.
5. **The denominator is the wrong population for "was a legitimate task blocked".** The log samples **what the guard blocked**, which is not the same set as **legitimate work that got stopped**. Blocks that never reach `guard.sh` leave no line at all — Claude Code's own worktree-isolation refusal is one, measured in the `skills#221` round. A rate computed here is a rate over guard firings, and cannot be read as a rate over the agent's blocked work.
6. **The log spans rule versions.** Rows are appended and never rewritten, and `rows` with no argument returns every round in the file — so a round that ran *before* a rule was narrowed still shows the false positives the narrowing has since removed. Real instance: `r_grader_write` was narrowed in `skills#225`, and `docs/guardrails.md` section 1 still records two false positives of it from the `skills#191` round. The direction is "dirtier than the rule now is", so it cannot fabricate a *clean* rule — what it can do is produce **a proposal to narrow a rule that is already narrow.** Before quoting a rate for a rule, cut the population to the rounds after that rule last changed; the round column is what does the cutting.
7. **The cost of a false positive is not recorded.** The log ends at the block. Whether the agent then gave up, or routed around it, is nowhere in the file — and routing around is real: in the `skills#221` round an evaluator blocked by `r_grader_write` delegated the write to another agent instead of stopping. So the rate says how often the guard was wrong, never what being wrong cost.
