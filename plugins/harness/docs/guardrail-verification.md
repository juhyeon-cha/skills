# Verifying the enforcement mechanisms, and as-built observations — how to confirm, and what was observed

> The **full list** of guardrails and gates (what is blocked) is [guardrails.md](guardrails.md).
> This document is its pair: **how to confirm** (section 4) and **as-built observations** (sections 7–11).
> **Section numbers continue from that document** — other documents and scripts point at "section 8" by number, so the numbers stay. Sections 1 · 2 · 3 · 5 · 5-1 · 6 · 6-1 are in guardrails.md, not here.
> Structure: `architecture.md` at the harness root. Development rules: [development.md](development.md).
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
- **The registry's own integrity is not visible by running the hook — assert it from the source.** A mistyped key like `RULES+=("Bash:r_pusk")` printed `command not found` to stderr with **exit code 0**, and `PreToolUse` reads rc=0 as pass, so one rule went dark without a signal. The dispatcher now asserts `declare -F "$fn"` **before** matcher comparison and denies if absent. The reverse direction (**function exists → registered**) is `checks/guard-check.sh`'s `registry_intact`, which derives the `r_`-prefixed function set from the source and asserts four things: every defined rule function is registered · every `RULES+=` comes after `RULES=()` · every registered name has the `r_` prefix · the derived set is non-empty. New rules default to "checked" (inverted polarity). Measured [`harness-uhy.3.5`]: a copy defining a rule function without `RULES+=` is rc=0 under the old gate and rc=1 now.
- **Environmental unavailability is fail-open + warning; only a real violation of the checked target is fail-closed.** Silent skips are forbidden (the warning goes to stderr). `guardrail-check.sh` without `jq` skips the whole gate — S1 does not call `jq` itself, but **the `guard.sh` it tests passes everything without `jq`**, so all its cases would flip to ✗; letting only S5 through would read rc=0 as "the guardrails were checked" when one surface of five was. Partial passes are not read as passes.
- **When checking a setting, compare down to the condition under which it fires.** Measured: change only the `matcher` of a `PreToolUse` entry from `""` to `"WebFetch"` and `guard.sh` never fires on Bash·Write·Edit, while a check that compared file, registration, and command string passed rc=0 and the commit landed. The comparison key was widened to `"<event>\t<matcher>\t<command>"` — S2 compares `hooks/hooks.json` against `hooks/*.sh` that way, both directions.
- **What it cannot catch**: a surface erased **on both sides at once** (a rule function and its test; `hooks.json` and the hook file) looks like an agreed change, not drift. That requires editing the check file itself, which is visible in review.

### 4-1. The counts these documents carry — what is checked and what is not

These two documents are the full list, so they carry numbers. **The only ones that can rot are counts claiming the size of a set in the current tree.** Three classes, three treatments:

| Class | Example | Treatment |
|---|---|---|
| **current-tree claim** | the counts in the headings of [guardrails.md](guardrails.md) sections 1 · 2 · 3 · the surface count in its front matter | **no machine compares them** — the plugin's `guardrail-check.sh` compares its own header's surface count against its section labels, not this document. When a rule or check is added, the heading here is edited by hand in the same change, and the `rules-check` C6 pointer is what keeps the session block pointing here |
| **frozen point-in-time observation** | transcript file counts · ledger record counts · violation counts | the value and its date go to the ledger note of the bead that measured it; the document keeps the conclusion and the bead pointer. When a flowing value is evidence, write movement and ratios rather than absolutes (section 8 ceiling 3 · section 9) |
| **inline self-enumeration** | "6 kinds (inline interpreters · script smuggling · …)" in [guardrails.md](guardrails.md) section 2 | the value and the enumeration sit together, so a mismatch shows in the text. No machine comparison |

### 4-2. What is written as "cannot block" — measuring that it is not blocked

**One check runs the opposite direction.** Where the items above ask "is what must be blocked blocked", `checks/guard-check.sh` pins **"is what is written as not blockable actually not blocked"** — the limits in the "not blocked" column of [guardrails.md](guardrails.md) section 1 that have an rc=0 fixture (the relative-path and symlink cases of ⑨ · for `r_remote`: `WebFetch` to the GitHub API, `curl -X POST` to `api.github.com`, `git remote set-url` (`RM_LIMIT`) · `git branch -D` for graders · the false-positive sets `BD_FALSEPOS` and `RM_FALSEPOS`). When a rule is widened and a limit is closed, that fixture flips to rc=2 and the gate breaks loudly — the rule *"a limit pinned as rc=0 is moved to a blocking assertion when closed, not deleted"* is meant for exactly that. **When it breaks, the job is not to delete the line** but to move it into the blocking set and fix the column in guardrails.md in the same change. Delete it and the closure disappears from the gate, and the same hole can reopen unseen.

**What this pinning cannot see.**

- **One shape per item.** A column that enumerates several shapes has one fixture. Splitting the column further would be parsing natural language.
- **[guardrails.md](guardrails.md) section 2 and the "Limits (what it cannot block)" list of 5-1 have no fixtures.** The former's enforcer is the permission engine, so no hook emits an rc; the latter's judgment is a tree, a remote, or an install configuration, not one command's rc — the configuration side is S6's fixtures.
- **A single rc=0 cannot tell "this shape leaks" from "the rule is dead".** That the rule is alive is S1's blocking assertion, and the check asserts the pair exists.

## 7. No git hook is planted in a target repo — the ledger checks are explicit steps of the cycle close

**The harness plants no git hook in a target repo** (story `harness-lzs3` decision; it closes `harness-v8n`). So in a target worktree a commit runs only that repo's own hooks, and a push runs no ledger check. The two things the harness-root hooks do for the harness repo — `board-check` at commit, `ledger-check` in write mode at push — are done in a target repo **by the orchestrator, as explicit steps of the cycle close** — the steps are owned by `harness:develop` "사이클 종결" and not restated here.

**What that means for evidence.** "The commit succeeded" is never evidence that the ledger was checked in a target repo — only "the check was run, and here is its rc" is. The failure table of the cycle close names each step's failure a **close incomplete** and the story stays open; that is the whole mechanism. **There is no gate** on whether the orchestrator ran the steps — the checks run at its hand, and `r_remote` does not see `bd dolt push` typed by the orchestrator (it is not a subagent).

The harness repo itself is the exception: its clone's worktrees share the harness root's `.beads/hooks` through `core.hooksPath`, and `bd where` from such a worktree follows the redirect to the harness ledger, so the commit and push gates fire there too.

## 8. The stop guard — `hooks/stop-resume.sh` (Stop)

When **this session's claimed** work is left `in_progress` and the session tries to stop, it pushes back once. Nine paths each leave one line in the log — `BLOCK` (pushed back) · `IDLE` (oracle 0) · `RECURSE` (re-entry pass) · `GAVE_UP` (ceiling) · `ORACLE_FAIL` (oracle failed) · `CANCEL` (dedicated marker consumed) · `VERIFY_PENDING` (verification-pending pass — the `DELEGATED` mark right after delegation is this path too) · `NO_CLAIM` (this session claimed nothing) · `SCOPE_FAIL` (could not read the mapping, so the scope was not narrowed — this one continues to a judgment path, so that turn writes two lines).

**Every state file is under `${HARNESS_DATA_DIR:-~/.claude/plugins/data/harness}`** — `stop-resume.log` · the cancel entrance `stop-resume-cancel` (claimed as `stop-resume-cancel.<session_id>` by the first session that sees it). Nothing is written into a project tree or a worktree, so a worktree being removed loses no record, and a session opened in any repo or worktree writes to the same place. If the directory cannot be created the guard passes without judging and says so on stderr.

**The ledger is reached through `lib/harness-root.sh`** with the payload `cwd` as the working directory — from a worktree that is the redirect, from a clone root the `~/.harness-workspace/.harness-root` file. Not found → `ORACLE_FAIL` and pass (never a fallback to 0 — "could not read" must not read as "nothing in progress"). **`ORACLE_FAIL` is a pass path**: a session in a clone root before `repo.sh` has written the pointer file has this guard effectively off, and "the guard is on" must not be read there.

**The scope is the actor this session claimed** [`harness-qih`]. The oracle still reads the whole ledger (`bd list --status in_progress`), and the judgment narrows to this session's share using the session→actor mapping `guard.sh` writes (`~/.claude/harness-session-actor.tsv`, override `HARNESS_SESSION_ACTOR_LOG`) — one tab-separated line `<UTC time> <session_id> <actor>` whenever `PreToolUse` passes a `bd … --claim --actor <value>`. **It is an observation, not a derivation**: `actor` is six random characters, reused across sessions by the pickup rule, so the only place the two values meet is the moment of the claim. The two fallbacks differ: mapping **unreadable** → judge on the whole ledger and log `SCOPE_FAIL`; readable but **no actor for this session** → pass with `NO_CLAIM`. `checks/guardrail-check.sh` S7 pins four fixtures for this and attributes both sides with A/B.

**Verification-pending and just-delegated are not unfinished work** [`harness-2a5.4.2` · `harness-o59`]. Two marks, same place and rule — `VERIFY_PENDING: <commit>` on finished work awaiting verification, `DELEGATED: <milestone ID>` written by the orchestrator right before a batch delegation. If every `in_progress` task's last non-empty note line starts with one of them (mixed is fine), the guard passes with `VERIFY_PENDING`; one without → block, and the message counts both marks. **"Last line" is the judgment**: a note appended after the mark (a re-review finding, say) lifts it. `bd list --json` carries `notes` as one string per issue (bd 1.2.2), so there is no per-issue re-query; if that changes the judgment leans toward **blocking** (`${pending:-0}`). S7 pins three fixtures and an A/B per judgment line; `rules-check` S22 does not count such tasks as concurrent delegation.

Two places it backs off by design. **An unreadable oracle does not fall back to 0.** **At three re-injections per session it stops blocking** — a guard a person cannot leave is not a guard. The ceiling is counted from the `BLOCK` lines of the same session in the log (no second state file). To turn it off at once, `touch "${HARNESS_DATA_DIR:-~/.claude/plugins/data/harness}/stop-resume-cancel"` — the owner is in the file name: the first session that sees the entrance renames it to `stop-resume-cancel.<session_id>` and afterwards reads only its own; no path removes another session's marker. This marker is the guard's own and **is shared with no other mechanism** — one marker for two mechanisms leaves the record unable to say which was turned off.

### Ceilings (what it cannot do)

1. **The oracle is ledger-wide; the narrowing is the judgment after it.** When the mapping cannot be read (`SCOPE_FAIL`) every session that runs this hook is pushed back at every stop, up to three times, even one working on something unrelated. The scope: the hook is plugin-wide and the plugin is a single user-scope install, so it runs in **every session on that machine** — the harness root, every clone, and any directory unrelated to the harness alike. The lower bound: **a session whose `cwd` reaches no ledger always passes** (`ORACLE_FAIL`).
2. **Nobody checks that it fires.** S2 is a wiring check (`hooks.json` ↔ files), not a firing check. S7 runs the hook **directly** with Stop payloads and a fake oracle — nine paths, one log line each, execution count equal to line count, negative control (two runs differing only in the oracle), A/B against the wiring — but **what it cannot see is the runtime**: whether the runtime calls this hook at stop, and whether `decision: "block"` actually prevents the stop. S7 runs in a sandbox `cwd` with `GIT_DIR` and `GIT_INDEX_FILE` unset and `HARNESS_DATA_DIR` redirected, so it never touches the real log.
3. It **pushes back but does not guarantee resumption.** Whether `decision: "block"` stops the stop is a runtime contract, not confirmed by execution in this tree.
4. **The oracle counts wider than the acceptance text.** The text says "in_progress **tasks**"; the hook counts every `in_progress` **issue** — a milestone or story in `in_progress` is in-progress work too. Same value today; the day milestones are moved to `in_progress` by operation, the hook blocks more often than the text. Narrowing is one `--type task` in the oracle call.
5. **A session waiting for a person is blocked too — a status transition was not introduced** [decision `harness-dg0.6.16`]. On a human-wait signal (the list is owned by `harness:develop` "사람 대기") the task stays `in_progress`; the oracle counts it, so a legitimately waiting session's stop is pushed back. Cost: at most 3 wasted turns per session lifetime, one per stop cycle (path `RECURSE` passes the re-stop right after a block). `blocked` was not adopted because it already means the opposite ("walk past it" — `IMPLEMENTATION_BLOCKED`), the wanted thing already exists as the one-turn cancel marker, and the human-wait signals other than `blocked` are visible only in `bd note` bodies — making them visible needs a dedicated marker, out of that decision's scope.
6. **Whether a claim succeeded is unknown** [`harness-qih`]. The mapping is written at `PreToolUse`, before execution — a refused claim still leaves its line. Not addressed: a refused claim is still **this session's own actor value**, so the scope is not widened to someone else's, and with no `in_progress` under that actor the narrowed set is empty and passes `IDLE`. The error runs in the counting direction, not the blocking one, and its value is 0.
7. **An unobserved claim silently turns the guard off — the one direction this design forbids, and it has no gate** [`harness-qih`]. The observation sees only a claim with `--actor <value>`. `bd update <ID> --claim` without it lets bd pick the value (`$BEADS_ACTOR`, git `user.name`, `$USER`), which the hook cannot see in the command string — **no mapping line, and that session ends past its own work with `NO_CLAIM`.** Not hypothetical: the ledger's `assignee` holds non-`sess-` values. Blocking it needs a rule against `--actor`-less claims, which turns an observation into a judgment — outside that story's decision. **Registered as no gate**; the claim rule in `harness:develop` section 1 requiring `--actor` is the only wall, and it is persuasion.
8. **Delete the mapping file and the scope goes with it** [`harness-qih`]. It is an ordinary file under `~/.claude/`; deleted, the next stop logs `SCOPE_FAIL` and judges on the whole ledger — what is lost is the scope, not the guard. It recovers by itself at that session's next claim. **No rotation, deliberately**: a line per claim is a different order of magnitude from the guard log, and a ceiling would erase an old session's `actor` and let that session pass silently with `NO_CLAIM` — the worse direction.

### Measured — the Stop hook fires while a subagent is alive

**A live background subagent does not keep the session from reaching Stop — the Stop hook fires inside a subagent's liveness window** (measured from one session transcript; the counts are in the `harness-m8gg.8.12` note). What kept the loop plugin then in use stuck at `iteration` 1 was not a firing failure but a **registration failure**: every `stop_hook_summary` record ran only the loop-cancel hook this harness wired at the time, because the loop plugin was in `enabledPlugins` but not in `installed_plugins.json`, with `.orphaned_at` in its cache. Not "a layer that does not fire" but **"a plugin that is not installed"** — the case section 8-1 is about.

## 8-1. Enabled but not installed — what silently dies [`harness-dg0.6.35`]

**The shape of the mismatch**: `enabledPlugins` in a settings file **turns a plugin on**. Turning on and **installing** are different — a settings file can name a plugin the machine does not have. "Registered everywhere, installed nowhere" is a normal product of a fresh clone. Measured (`harness-dg0.6.35`): the harness root's `.claude/settings.json` then named `harness@skills` and a loop plugin from `claude-plugins-official`, and a new clone had installed neither.

**What silently dies in that state**:

- **Every** hook, skill, and command of that plugin — not some, all.
- **No signal.** The settings file does not know whether what it names is installed, and the runtime simply does not call the hooks of a plugin that is not there. No error, warning, or log.
- So **"a state in which a mechanism is believed present" is created.** This project paid that cost once: a loop ran nine hours with `iteration` at 1, and the orchestrator, seeing `hooks.json` in the cache, concluded "plugin hook registration is normal" and built a **false hypothesis** on top (section 8's measurement).
- **Files remaining in the cache and a plugin being alive are different things.** The misjudgment was exactly that confusion — the cache directory was there, with `.orphaned_at` inside it.

**What catches it now.** For the harness plugin itself, the resolver `scripts/plugin-root.sh` at the harness root fails loudly (rc=1, with the install command) when neither `HARNESS_PLUGIN_ROOT` nor a cached install exists — so the commit and push gates and `harness.check` cannot run against nothing. For the *session* side there is **no gate**: `claude plugin list` is the check, by hand, and the plugin's own `guardrail-check.sh` compares `hooks.json` with the hook files inside the plugin tree, not with the machine's install list (the old S4, which compared an install script's plugin list with `settings.json` and the registry, went away with the install script).

**Ceilings**

- **`claude plugin list` is a registration check, not a firing check.** Installed does not prove its hooks run — section 8 ceiling 2.
- **The cache's `.orphaned_at` is not a discriminator on its own** [`harness-dg0.6.43`]: it was observed coexisting with `.in_use/<pid>` while the plugin's skills were alive in the session. At most it means "collection candidate".
- **The resolver picks the highest cached version**, not the one `installed_plugins.json` names for this scope. Two cached versions of `harness` with the older one installed would make the gates run the newer tree — a mismatch the resolver does not see.

## 9. Where transcripts are read — `checks/transcript-check.sh` [`harness-dg0.6.18`]

`docs/adr/natural-language.md` 6.4 lists 12 "after-the-fact detection" items, and **9 of them hang on this one place** (D4). The condition that document attached to after-the-fact detection asked for exactly this — *"without a place that actually reads the record, 0."* **The records existed; what was missing was the reader.** This check is that one, and **it is the only place that parses transcripts** (the retrospective only calls it — `harness-dg0.6.18` ↔ `harness-2a5.1.2` ownership agreement).

### Hook or batch — decided by measurement

**The subagent-stop payload carries the transcript path.** A `SubagentStop` hook in a scratch project dumped the payload (Claude Code 2.1.247): of its 14 keys, four serve this place directly — `agent_transcript_path` (that subagent's own `agent-*.jsonl`) · `transcript_path` (the parent session) · `agent_type`/`agent_id` · **`last_assistant_message`** (the reply body itself).

**So a hook would work. Batch was chosen anyway.** ① This place must produce an aggregate (signal counts per role · tool distribution · instance reuse); a hook sees one delegation at a time and would need its own state file — a derived state on top of a source that is already files. ② A retrospective looks at a past window; a hook built after the window is useless, batch reads what is already there. ③ Both would make two transcript parsers.

> **This measurement shakes one judgment ground of `adr-b` (a closed document, not edited).** The `Q1✗` ground of `R9`·`A9`·`S25` was *"no observation that a subagent's reply body appears to a hook"*. It appears, as `last_assistant_message`. But `SubagentStop` is called **after** the reply, so the **blocking-time tool boundary** that document demanded is still absent — whether the three "impossible" judgments flip is outside this scope; the observation is recorded.

### Only A9 is judged — nine items have a place, one has a judgment

`A9` = "the first line of a role reply is exactly `SIGNAL: <VALUE>`". The vocabulary is derived from the plugin's `agents/*.md`, so a role-definition change moves the check. **It caught real violations** — in one run about 2% of judgments were `NO_SIGNAL` (the counts are in the `harness-m8gg.8.12` note), all the same shape: a one-line summary before `SIGNAL` ("All anchors verified. Compiling the verdict." …). **To an orchestrator that parses the first line, that is a reply with no signal.** Counts flow (ceiling 3); the evidence is the ratio and the shape. **The other 8 (`R9`·`R12`·`R25`·`A7`·`A13`·`A16`·`A18`·`S25`) have a place but no judgment** — do not read registration as action.

**The quietest trap was that finished delegations come in two shapes** [measured]. A synchronous delegation records its end as `toolUseResult.status == "completed"` with `agentType`. **An asynchronous one leaves only `async_launched` there, with no `agentType`**, and the end arrives later as `<task-notification>` `<status>completed</status>`. A version that read only the first shape **dropped asynchronous delegations entirely** — silently, rc normal. **The dropped share is written as a ratio: about 60% of that session's delegations were asynchronous** (two counts the same day, in the `harness-m8gg.8.12` note — totals flow, the ratio holds). So the role is read from the transcript's own **`attributionAgent`** (common to both shapes, exactly one per file). `--self-check` feeds the same violation in both shapes to see that this path is alive.

**One layer down, the same class of trap, caught in review — a record is not a reply** [measured]. When one reply calls several tools **the transcript writer splits the record** (the pieces share one `message.id`). Counting `tool_use` blocks **per record** gave exactly 1 assistant record everywhere — "1.00 per reply, max 1", an **identity independent of input** — while the question this place answers is "does it call in parallel", and **it answered "no" on any data.** Grouped by `message.id`, parallelism is real: `implementer` 12.5% · `reviewer` 34.7% · `evaluator` 35.8% (up to 4–6 per reply).

**The negative control is inside the check**: `checks/transcript-check.sh --self-check` builds two fixtures, disturbs only the one line before `SIGNAL`, and expects `rc=0 → rc=1`, asserting first that both copies exist and differ (`[ -s a ] && [ -s b ] && ! cmp -s a b`), and that an empty copy yields `rc=2` with one `UNREACHED:` line.

### Ceilings (what it cannot do)

1. **Wired to no gate.** The target is `~/.claude/projects` — the **class that compares with something outside the tree**. Tied to a commit, rc changes whenever another session runs, and a violation unrelated to this tree blocks the commit. **So this check's rc is never substituted by a commit message — it is run where it is used.**
2. **The population is "delegations the parent session recorded as completed"** — in-progress ones are not judged, so that the auditing session's own subagents are not mixed in (the self-referential counting trap, `harness-dg0.6.17`). The price was measured: without this definition the auditing reply itself is caught as `NO_SIGNAL`.
3. **Totals flow — the evidence is the ratio.** The transcript directory grows with every session, and since sessions now open in target clones the transcripts are spread over several project directories under `~/.claude/projects` — the check reads all of them by default (`--projects` narrows), and the header line states the population. **Only the judgment count grows; the violation count can shrink** — the judgment reads `texts[-1]` per transcript, and one instance reused for several delegations has a mid-way violation covered by a later correct `SIGNAL`. **Do not read a falling violation count as improvement.**
4. **`<task-notification>` is not subagent-only.** A background shell job ends the same way. A notification with no transcript file cannot be attributed to a role and is removed from the population, and **that count goes into the header line**; a transcript whose role cannot be read leaves one unreached line — asynchronous role attribution hangs on `attributionAgent` alone, and if that field vanished the population would shrink to **0 unreached · 0 violations · rc=0**.
5. **The A9 judgment is lenient on leading whitespace.** It reads the first line after `lstrip()`, so it catches **content** before `SIGNAL`, not blank lines — narrower than the role definition's text ("no blank line before the first line"); widening it would make every serialization-side blank a violation.

## 10. Release width — a confirmation step, no gate

The width of a version bump is decided by **whether an install gets hand work** ([development.md](development.md) "Release"; the procedure is the `harness:release` skill). That judgment is natural language and **no gate sees it.** What exists is one confirmation command in that skill's sweep step: the diff of the plugin's `skills/setup/SKILL.md` since the previous tag (in the skills repo) — a new hand step in its update section is the definition of MAJOR.

**This item is not one of the eight in 6-1** — that list is locked as a set with `docs/adr/natural-language.md` 6.4, and the both-way count in that section asserts it. Adding this place as a row would break the count. It stands apart in place, not in kind.

### Ceilings (what it cannot do)

1. **It cannot be wired to any gate — the commit gate in principle.** The width is settled once, at release time, over the whole range since the previous tag; between releases there is no width for a commit to be compared against. Firing it on every commit makes every commit but the release one a false positive.
2. **It looks one way — a miss remains, and that is the dangerous shape.** The command sees only the setup skill's diff. **Hand work that appeared without the setup skill being updated is not caught.** Then an install updates with a narrow width and no procedure, and its gate breaks right after, with the person not knowing why. **That loss has not actually happened — a hypothesis**: no install has updated across a release yet.
3. **False positives remain.** A typo fix in the setup skill also produces output. The judgment is a person reading the diff — the command **points at what to read**, it does not judge.
4. **rc says nothing — the signal is whether there is output.** Both cases are rc=0.

## 11. When firing counts can be used as evidence

Several places say "do not quote a hand count; use the output of `scripts/guard-log.sh` as evidence". **When that holds** is pinned here — used where it does not, "0 false positives" and "logging did not happen" come out as the same value.

### Conditions — only when all three hold

1. **The `guard.sh` that fired has the logging call.** The log path is outside every tree (`~/.claude/harness-guard-log.tsv`, override `HARNESS_GUARD_LOG`), and the logging code is in the plugin — so **the firing hook is the installed plugin version** (or the `--plugin-dir` tree a session was started with), not whatever branch a worktree has checked out. A logging change in a plugin source tree counts nothing until that tree is what sessions load.
2. **The counting command reads the log the hook writes.** That the two files' `HARNESS_GUARD_LOG` default agrees is derived and compared by `checks/guard-check.sh` ⑯.
3. **The round column has not collapsed.** A payload without `session_id` folds rounds into `-` (⑯ (e) pins that value).

### Three kinds of absence — told apart by rc and phrase

| State | rc | Usable as evidence? |
|---|---|---|
| counts come out | 0 | **yes.** Round × rule counts are machine values |
| no log, and **the inspected `guard.sh` has the logging call** | 1 | "the hook never ran". **Only when the inspected hook is the one sessions load** — the phrase prints the path |
| no log, and **the inspected `guard.sh` has no logging call** | 3 | **not "0 firings".** The hook runs and leaves nothing |

The three branches are reproduced, and a copy of the counting command with the distinction removed is shown unable to tell them apart, by `checks/guard-check.sh` ⑱.

### Ceilings (what it cannot do)

1. **The counting command does not know which `guard.sh` actually fired.** Nothing records it afterwards — the log has no hook path, and an empty log has no log. The command inspects the plugin tree it sits in (`CLAUDE_PLUGIN_ROOT`, else its own location); when a session was started with a different `--plugin-dir`, the rc=1/rc=3 phrase is about the wrong tree — the printed path is what to compare.
2. **rc=3 separates only the cause of absence.** A non-empty log with a non-logging version mixed in (sessions on different plugin versions) is not caught — that round's rows are simply missing, and missing rows appear under no rc. **A miss remains, and it is the more dangerous shape.**
3. **Rotation loss and `session_id` absence are as the "발화 로그" comment of `guard.sh` says** — places where the denominator quietly shrinks.
