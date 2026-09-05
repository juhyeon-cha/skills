# Enforcement mechanisms (as-built) — what is blocked, and what is persuasion only

> The full list of the guardrails and gates the harness actually runs, each one's limits, and where they live.
> The measurements themselves are in the ledger — a rule's measurements are the `note` of the task bead that made it, and the three decision documents are `decision` beads (`harness-bjj` · `harness-pl7` · `harness-dmy`, projected to `docs/adr/`). This document is the index.
> **How each mechanism is verified, and the as-built observations, are in [guardrail-verification.md](guardrail-verification.md)** — section numbers continue from this file. This document holds **what is blocked** (sections 1 · 2 · 3 · 5 · 5-1 · 6 · 6-1).
> Structure: [architecture.md](architecture.md). Development rules: [development.md](development.md).
>
> **Where the code is.** Every mechanism below except the `permissions.deny` list and the git hooks lives in the plugin `harness@skills` (`${CLAUDE_PLUGIN_ROOT}`, `plugins/harness` in the skills repo): `hooks/guard.sh` · `hooks/stop-resume.sh` · `checks/*.sh`. Paths written as `hooks/…` or `checks/…` are plugin-relative. The deny list is in this repo's `.claude/settings.json`; the git hooks are in this repo's `.beads/hooks/`.
>
> **Two words reach the ledger, and the rules watch both.** Skills and roles are told to call the adapter `scripts/ledger.sh`; its `beads` backend then calls the real `bd`, and a hand-typed `bd` is the way around the adapter. So `guard.sh` carries one list, `LEDGER_TOOLS="ledger.sh bd"`, and every ledger rule loops over it. The read exemption and the write allow list are shared because the subcommand sets are the same; what differs is **how the ledger is named** — `bd -C <harness root>` (`--directory`·`--db` too) against `HARNESS_ROOT=<harness root> ledger.sh …`. Below, "a ledger tool" means either word.

**A rule is wider than its gate.** A rule sentence stays when a gate appears — gates can be bypassed (indirect subprocesses, script smuggling, an equivalent command without the token) and the rule says why. One `guard.sh` denial already says so: "**훅이 통과시키는 것이 허가는 아니다 — 금지는 그 형태에도 그대로 걸려 있다.**" Do not read the "not blocked" columns below as **"allowed when not blocked."** They list the blind spots the guardrail does not reach, not permissions.

**A guardrail, not a fence.** Enforcement by inspecting command strings is not complete in principle. Three independent measurements pointed at the same place [`harness-uhy.1.1`]:

1. **Inline interpreter indirection** — with `permissions.deny` set and `bypassPermissions` on, `cat` was blocked and `python3 -c "open(...)"` **leaked the file** (one canary detected). Deny reaches only commands whose file arguments can be read statically.
2. **Script smuggling** — commands inside a script never appear to the hook as events. The tool call is one line, `bash x.sh`.
3. **Repeated failure of shape enumeration** — the same regex leaked three times across a wrapper (`timeout`) and an option position (`git -C`), and once matched **by accident** through a `.git` substring in a path.

So **these enforcement points are designed as "a guardrail against careless accidents", never "a security boundary against malicious bypass"**, and the documents say so. Call a guardrail a fence and someone will run something dangerous behind it. **A principled boundary needs a different layer** — blocking file access at the OS or sandbox level, or not putting secrets on that filesystem at all. That layer was not measured here.

**Four enforcement surfaces.** `PreToolUse` hook rules = plugin `hooks/guard.sh` (section 1) · **`Stop` hook = the stop guard `hooks/stop-resume.sh`** ([guardrail-verification.md](guardrail-verification.md) section 8) · `permissions.deny` (section 2) · `checks/` (section 3). The stop guard standing in section 8 of the other document is a matter of when it was built, not of being outside the list — this paragraph registers it. The table in section 1 lists **`PreToolUse` rules only**, so **absence from that table does not mean "not a mechanism".**

**More hooks are wired than these four — four events, five hook entries** (`hooks/hooks.json`: SessionStart · PreToolUse · PostToolUse(EnterWorktree) · Stop ×2). **Two of them are enforcement surfaces** (`guard.sh` · `stop-resume.sh`); **the other three are injection, wiring, and cancel** — `session-context.sh` (the always-on rule block) · `enter-worktree.sh` (ledger wiring of a new worktree; it fails loudly with exit 2 but blocks nothing, since PostToolUse runs after the tool) · `ralph-cancel.sh` (loop cancel marker). Just as the sentence above says "do not read absence as absence", this one says **"do not read everything present as enforcement".**

## 1. 훅 규칙 7종 — 플러그인 `hooks/guard.sh` (PreToolUse, 모든 도구)

Blocking is **exit code 2 + a reason on stderr**. Every judgment is **token presence**, not enumeration of command shapes (enumeration leaked three times in a row in the spike). The price is false positives, accepted deliberately. **The rules are the four anchor-free invariants** of story `harness-lzs3`: work only in a worktree · whoever built it does not grade it · a person opens the remote · one ledger. Rules that leaned on a tree anchor (`r_worktree` · `r_core_write` · `r_bead_leak` · `r_bd_body`) were removed with the plugin move — the reasons are the table in the note of `harness-lzs3.3.1`.

**The whole table hangs on `jq`.** The hook parses its input with `jq`, and **without it the hook does not die — it passes with a warning on stderr**; broken JSON input likewise. In an environment without `jq` every rule below is silently off. The reason is that this is a guardrail, not a fence: showing "the guardrail is off" costs less than blocking every tool call because one tool is missing. **The `jq` absence in `guardrail-check.sh` ([guardrail-verification.md](guardrail-verification.md) section 4) is a different place** — there the check goes dark, here the guardrail itself does.

**Role rules compare `agent_type` against `harness:<name>` only** (measured form `harness:implementer` · `harness:reviewer` · `harness:evaluator`). An un-prefixed value is not this harness's role — a same-named agent from outside the plugin must not be read as one.

**An internal error is a block, not a pass.** Claude Code reads only rc=2 as a block, so a hook dying with rc=1 on an unbound variable would pass the call — an EXIT trap turns every unreached judgment into rc=2 with a message.

| Rule | Tool | Applies to | Blocks | Not blocked · false positives (limit source) |
|---|---|---|---|---|
| `r_main_write` | **every tool that takes a path** (`*` matcher; only the read-only tools are exempt) | everyone | Writing a path inside a target repo's **main checkout**. Only `<repo>/.claude/worktrees/<story ID>/<anything>` passes. **Relative paths are folded against the payload `cwd`** — `../../../f` from a worktree is blocked | A relative path when the payload carries no `cwd` (not judged) · **a tool receiving the path under a key other than `file_path`·`notebook_path`** · **symbolic links** — normalization (`mc_norm`) is **lexical**, so a write through a link that points at the main checkout passes (physical resolution is not used because files that do not exist yet must be judged; `guard-check.sh` pins the rc=0 with a real link) · shell-mediated writes are the next rule's — `harness-uhy.3.3 note` |
| `r_main_shell` | Bash | everyone | A command string that contains a main-checkout path and is **not made only of read-only commands**. Read-only = the first executing word of every fragment is a **read shell command** (list `MC_READ_CMDS` in `guard.sh`) or a `git` subcommand **all of whose forms are reads** (`MC_GIT_READ` — `branch`·`tag`·`config`·`remote`·`stash` have write forms and are excluded), with no file redirection (`>`; `2>&1`·`>/dev/null` excepted). **`./`·`../` paths are folded against the payload `cwd`.** Paths inside argument text (`bd create -d "…path…"` · `gh pr create --body` · `git commit -m`) are blocked — the standard route is a file (`--body-file` · `git commit -F`, user decision `harness-qp1`) | Manipulation of the `.claude/worktrees` layer **itself** passes within the exception width (`rm -rf …/worktrees` included — narrowing it would block `cd <worktree> && git status`) · a relative path without a payload `cwd` · write options of exempt commands (`find` is outside the exemption, so `-delete` is blocked) · **a path assembled from variables** — `$HOME`·`${HOME}` are expanded first so `R="$HOME/.harness-workspace/repo"; echo x > "$R/main.txt"` is blocked, but `R="$HOME"; echo x > "$R/.harness-workspace/repo/f"` never has the clone path as one piece; command substitution likewise — `harness-uhy.3.3 note` limit 5 |
| `r_remote` | **Bash only** | **subagents only** | A command in which `git`·`dolt` or a ledger tool (`ledger.sh`·`bd`) **executes** a push subcommand (`git push` · `git subtree push` · `dolt push` · `bd dolt push` · `ledger.sh dolt push`) / a fragment in which `gh` **executes** and the two tokens after its leading options are not in the read exemption list (default is block). Word citations (`git log --grep push`), local commands (`git stash push`), `gh` at the end of a path or inside a URL, and option-only calls (`gh --version`) do not fire (`harness-2a5.3.1`) | **Tools other than `Bash` are not inspected** — `WebFetch`, a GitHub MCP, any path to a remote without a command string is rc=0 (pinned by the gate). The orchestrator — a hook cannot see "did the user instruct"; the two exceptions (ledger reflection tied to a push · working-branch push and PR of a cycle close) are allowed by design, the rest is persuasion (section 5-1). **Subagents have no exception** — every denial cites `harness:develop` "사이클 종결": "서브에이전트는 범위 밖이다 — 로컬 커밋까지". Variable substitution is caught through assignments (`G=git`·`G=gh`) but `eval` and scripts are not. `gh api <exempt word>` passes. **GitHub reflection without `gh`** — `curl -X POST https://api.github.com/…` passes. **Changing the remote itself** — `git remote set-url origin <other>` passes. False positive: the **value** of a leading option is not skipped — `gh --repo o/r pr view` is blocked. Exemption list of 8 — `harness-uhy.3.4 note` |
| `r_grader_write` | **every tool that takes a path** (`*` matcher; only the read-only tools are exempt) | `harness:reviewer` · `harness:evaluator` | Every file write | Shell-mediated writes (`echo x > f` · `sed -i` · `cat > f <<EOF`) — `harness-uhy.5.1 note` limit 1 · a path under another key |
| `r_grader_shell` | Bash | `harness:reviewer` · `harness:evaluator` | Every `git` subcommand **executed** outside the read exemption (`GR_GIT_READ` in `guard.sh` — wider than `MC_GIT_READ`, it includes `branch`·`grep`) — `commit`·`revert`·`rebase`·`reset`·`checkout`·`add` … · every write subcommand of either ledger tool. **Naming the ledger does not lift it** — that is what separates this rule from `r_bd_root`, which only asks that the ledger be named. Words in prose, search patterns, and downstream filters (`jq '.commit'` · `grep 'ledger.sh note'`) are not in executing position | `git branch -D` (exempt word `branch` — a grader has no reason to delete a branch; accepted) · shell-mediated file writes (`r_grader_write`'s column) · variable substitution is caught through assignments but not `eval` or scripts — `harness-uhy.5.1 note` |
| `r_impl_bd` | Bash | `harness:implementer` | When a ledger tool is in **executing position**, every write subcommand **except `note`** (a path-spelled call — `/opt/homebrew/bin/bd`, `bash <plugin>/scripts/ledger.sh` — is the same, the comparison is on the basename) | The value of a value-taking global option **not in the list** is read as the subcommand and hides the real one (`bd` only — `ledger.sh` takes no such option). The list is derived from `bd --help`·`git --help` and compared by the gate (⑧-값옵션), so **a real option going missing is detected** — what remains is an option that tool version's `--help` does not print · variable substitution is caught through `B=bd` but not `eval` or scripts (`bash /tmp/bd-writer.sh`) — `harness-uhy.5.2 note` limit 6 |
| `r_bd_root` | Bash | **subagents only** | A ledger tool in **executing position** with a write subcommand and **the ledger not named** — for `bd` that is no `-C` (·`--directory`·`--db`) before the subcommand, for `ledger.sh` no `HARNESS_ROOT=` in front of the command. Options are skipped and the subcommand read — `bd --json create x` reads as `create` and is blocked; option-only calls (`bd --help` · `bd --version` · `bd -C <root>`) are help/version output and read (`harness-2a5.3.1`). Either word in prose, paths, and search patterns does not fire | Words in the read exemption list · `eval` and scripts · the naming **after** the subcommand is not honored (`bd note x -C /h` is blocked — gate BD_FALSEPOS), and an `export HARNESS_ROOT=…` in an earlier fragment does not count as naming — `harness-uhy.3.2 note`. Kept even though today's registered clone roots have no ledger of their own (bare `bd` there dies loudly): the day a target repo adopts beads, silent misfiling returns, and this is the gate for it (`harness-lzs3.3.1` note) |

**Where rules overlap, registration order picks the message.** `bd dolt push` hits `r_remote` and `r_bd_root` together and the earlier `r_remote` message goes out. Overlaps are not removed by narrowing one side.

**A grader's reads pass.** Words in downstream filters (`HARNESS_ROOT=<harness root> ledger.sh show <ID> --json | jq -r '.notes[] | .commit'` · `… | grep -c 'ledger.sh note'`) are not in executing position, and read-only commands on the main checkout (`ls -d <clone>/<repo>/.beads` · `grep -c . <clone>/<repo>/docs/guardrails.md`) pass through `r_main_shell`'s read exemption. No action a grader needs to gather evidence is blocked — what remains is a path inside argument text (the `r_main_shell` row), which is a write command's place.

**The body of a ledger write is no longer guarded** (`r_bd_body` was removed). The rule still stands — the body goes to the ledger through a file option, never inside the command string, because backticks and `$VAR` inside a double-quoted body are expanded by the shell before the ledger tool sees them and it exits 0 anyway — but it is persuasion only. The form is `harness:develop` "원장에 본문을 넘기는 형태".

### 1-1. 슬래시 명령에 대한 한계 3건 [실측 `harness-dg0.3.1 note` 7.1, `harness-dg0.3.1`]

The rules in section 1 are **all `PreToolUse`**, so how a slash command appears in that event is the coverage.

| # | Limit | What it makes you misread |
|---|---|---|
| L1 | **A slash command typed by a person does not appear in `PreToolUse`** — with the hook wiring alive, only `UserPromptSubmit` fires. Only a model-initiated one appears, as a `Skill` tool call | Every rule that targets a slash command needs the qualifier **"model-initiated only"**. Without it, **"partial" reads as "present"** |
| L2 | `hide-from-slash-command-tool` **hides from the list only** — a hidden command is still callable and still hits `PreToolUse` | "Not in the subagent's list, so it cannot call it" is **not a defense** |
| L3 | **A tool named `SlashCommand` does not exist in this version** — 0 hits across 811 transcripts | A rule written against that name is **registered but watching nothing** |

**That is why the three loop rules (S4 — no arbitrary start · arguments required · one per machine) got no gate**. Blocking only the model-initiated path leaves the person-typed start untouched, and writing that half as "present" is the misreading L1 warns about.

### 1-2. 정정 보존의 append-only 는 원장 도구가 아니라 이 절이 만든다 [실측 2026-08-28, `harness-dg0.6.20`]

The rule "정정 보존" (when overturning a judgment, do not delete the earlier decision; quote it with `ledger.sh note` and say what was wrong) assumes the ledger's records **are not overwritten**. Measured whether that is a tool property or a hook effect (the `beads` backend, bd 1.2.2; only help was read). The adapter passes the subcommands through, so the answer is the backend's, not the adapter's — and it is the same answer on `github`·`notion`, whose APIs also edit and delete comments.

**Conclusion: the ledger tool is not append-only.** Several subcommands edit or delete notes — `update --notes` · `edit --notes` · `sql` (direct UPDATE/DELETE) · `delete` · `import` · `restore --apply` — plus `compact`·`flatten`·`gc`·`prune`·`purge`, which shrink history. **Only `note` is append-only**, and its own help says so (`--append-notes` shorthand).

**So append-only is made by section 1.** For subagents all of the above is already blocked — `r_impl_bd` leaves the implementer `note` alone, and `r_grader_shell` narrows the grader's ledger calls to reads. Both are exemption-list style, so a new ledger subcommand defaults to "blocked". The negative control is `checks/guard-check.sh` ⑬.

**Not blocked:**

| Path | Why |
|---|---|
| **The orchestrator session** | both rules judge by `agent_type`, so they are off in the parent session. Same structure and reason as `r_remote` — a hook cannot see whether the user instructed. **This half is persuasion** |
| **A path that bypasses the ledger tools** | on `beads`, raw `dolt` SQL on the same DB and editing `.beads/*.jsonl` before re-`import`ing; on `github`·`notion`, `gh` or `curl` straight at the API. In the hook `dolt` fires `r_remote` only with a `push` token, and `gh` writes are `r_remote`'s |
| **A form in which neither ledger word is readable as a name** | **none of the four roles can block it.** Every rule's entry gate is `has_token` on `ledger.sh` or `bd`, so a substitution that leaves neither literal in the command string (`B=$(printf 'b%s' d); $B update …`) never enters the judgment. What is blocked is the **literal-leaving example** (`B=bd; $B update …`), and there the three rules (`r_grader_shell`·`r_impl_bd`·`r_bd_root`) all answer with the same message through the assignment check |

## 2. 권한 deny 10종 — `permissions.deny` (하네스 루트 `.claude/settings.json`)

`Read(**/.env)` · `Read(**/.env.*)` · `Read(**/*.pem)` · `Read(**/secrets/**)` — the same four anchored at `~/.harness-workspace/**` — plus `Read(~/.aws/**)` · `Read(~/.ssh/**)`.

- **The enforcer is Claude Code's permission engine**, not this repo's code. `bypassPermissions` does not get through [measured]. So no `checks/` gate can verify this **blocking behavior** ([guardrail-verification.md](guardrail-verification.md) section 4).
- It holds with the project `.claude/settings.json` alone — no user settings required [measured]. **The plugin cannot carry it** — permissions are not a plugin component — so a target clone that opens a development session gets it only from its own settings (`scripts/repo.sh` writes nothing under a clone's `.claude/`; the deny list is the harness root's and does not travel).
- **`.env.example` is blocked too. Intended** — `deny` cannot be punched through with `allow`, and a safe-suffix allow list inverts polarity so a new suffix defaults to "pass".
- **So a rule that needs an exception cannot be expressed as deny.** Deny the parent and allow the child and **both are blocked** [measured `harness-uhy.3.1`] — which is why main-checkout protection (`r_main_write`) is in section 1 and not here.
- **The four home-anchored lines are not duplicates of the relative patterns — do not delete them.** A **project-relative pattern like `**/.env` is valid only inside the project directory**, and work happens inside `~/.harness-workspace/<repo>/.claude/worktrees/<story ID>/`. Measured: with only the four relative patterns, a `.env` in the worktree and one outside the project **were read** (two canaries leaked); adding the `~/.harness-workspace/**` anchors turned the worktree one to `BLOCKED` [`harness-uhy.2.1`].
- What gets through — 6 kinds, **all read paths; Write and Edit on `.env` are constrained by nothing**:

| # | Leaking path | Evidence |
|---|---|---|
| 1 | inline code interpreters (`python3 -c "open(...)"` …) | [measured] 2 canaries leaked |
| 2 | script smuggling — `cat .env` inside `bash x.sh` | [inferred] the hook never sees it as an event (measured); `deny` sees only tool arguments, so it shares the hole |
| 3 | paths outside `~/.harness-workspace` and outside the project | [measured — **different rule set**] with only the relative patterns, a `.env` outside the project was read. That it leaks under the shipped rules is [inferred] — the anchored lines cover only `~/.harness-workspace/**` |
| 4 | `HARNESS_CLONE_ROOT` set to a non-default value | [inferred] rules are static strings; `scripts/repo.sh`·`hooks/enter-worktree.sh` honor the variable, so the clone location moves |
| 5 | a session opened in a directory whose settings carry no deny list | [inferred] a target clone without the deny entries in its own settings loads no deny list (section 5, item 2) |
| 6 | a secret file name not in the list | by design — the list is an enumeration, not a derivation |

**1 can be closed with a hook, but 2 remains even then** — interpreter enumeration is not complete in principle. **So do not use this mechanism as "secrets cannot leak".** It blocks a careless accident — an agent skimming `.env` and its content landing in the ledger through `ledger.sh note` — and a principled boundary needs a different layer.

## 3. 검사 12종 — 플러그인 `checks/`

| Check | Sees | Wired where | Run condition |
|---|---|---|---|
| `board-check.sh` | **Ledger structure** — sprint ID format · `rail:` labels in `rails.json` · `sprint:` labels ↔ `sprints.json` both ways (+status) · label inheritance and ancestor existence of sprint descendants · acceptance of sprint tasks. Does not look at projections | **yes — harness-root `pre-commit`** (every commit here) · `check-all` · cycle close in a target repo (`harness:develop` "사이클 종결" step 1) | the ledger through `scripts/ledger.sh`, at the root `lib/harness-root.sh` prints; root or `ledger.json` not found → rc≠0, never a silent skip |
| `ledger-adapter-check.sh` | **The adapter itself** — ① boundary (no `ledger.json` · a `backend` outside the three → rc≠0 naming the cause; `--help` covers the whole set of `bd` subcommands the plugin actually calls, derived by grep from the tree) · ② `beads` read equivalence against `bd -C <root>`, byte for byte · ③ `beads` write round trip in a throwaway `bd init` fixture (the real ledger is never written) · ④ `github` offline against a fake `gh` · ⑤ `notion` offline against a fake `curl` | `check-all` | `jq`, and the harness root through `lib/harness-root.sh`. Live writes to GitHub and Notion are **not** here — those were walked by hand (`harness-m8gg.4.2`·`4.3`) |
| `ledger-check.sh` | **The ledger is ahead of its remote** — the silent-loss path. Goes through `ledger.sh sync-check [--push]`: in write mode (`LEDGER_CHECK_PUSH=1`) the `beads` backend runs `bd dolt push` instead of blocking, **recounts the tracking refs**, and blocks only if still ahead; without the switch it reflects nothing and only says so. On `github`·`notion` there is nothing to reflect, so it is `원격 반영 대상 없음` and rc 0 | **yes — harness-root `pre-push`** (write mode) · cycle close in a target repo (read mode, before and after the explicit ledger reflection) · `check-all` exempts it (remote dependence) | on `beads`: `dolt`, an embedded ledger, and a Dolt remote; otherwise fail-open with a warning. **A pass phrase says `건너뜀` or `앞서 있음(반영하지 않음 — 쓰기 모드 아님)` when nothing was judged** — never `확인됨` |
| `guardrail-check.sh` | **Disappearance of the enforcement itself** — S1 rule blocking behavior with A/B attribution · S2 `hooks.json` ↔ `hooks/*.sh` both ways (`matcher` included) · S5 script files (exec bit, syntax) · S6 `ledger-check`'s ledger discovery and auto-reflection (with `bd`/`dolt` stubs) · S7 the stop guard's paths (Stop payloads into the wired file) | `check-all` | `jq` (without it the whole gate skips with a warning — [guardrail-verification.md](guardrail-verification.md) section 4) |
| `guard-check.sh` | `guard.sh` **inside** — per-rule false-positive and miss boundaries, the exemption lists in full, pinned limits (rc=0 for what cannot be blocked), registry integrity both ways, option lists derived from `--help` | not wired — `check-all` exempts it (slower than all other checks together; run by hand on a commit that changes `guard.sh`) | `gh`·`bd` in PATH (sets are derived from `--help` — without them the derivation is empty and rc=1) |
| `rules-check.sh` | Static assertions on the ledger, the registries, and the plugin tree — R5 one `repo:` label per task · R18 `repos.json` key set · S12 harness-root `.gitignore` required and forbidden entries (parsed from the setup skill) · R-ACC acceptance of started tasks · R-REM stale sentences · **C6** the session block's 「절대 금지」 is alive and points at `docs/guardrails.md` · **R40** `repos.json` ↔ clone directories both ways · **S22** two actors in one (story, repo) worktree · **S24** an open story whose children are all terminal · **R-DATE** no date in the always-on block · **R-BEAD** every bead ID in the block exists · **R-WAIT** single ownership of the human-wait signal list · **R-DUP** no verbatim copy of the block in skills or agents · **R-BUDGET** byte ceiling of the block. Which read zero items as failure and which fall back is written in the script's header | `check-all` | the ledger through `scripts/ledger.sh` at the root `lib/harness-root.sh` prints; R40·S22 also read the clone root (`HARNESS_CLONE_ROOT`). **R-REM derives its scan set with `git ls-files` in the plugin tree**, so it reads 0 files — and fails loudly — when the plugin root is an install cache rather than a git checkout |
| `repo-check.sh` | `scripts/repo.sh`'s clone-root layer — ① `apply` writes `<clone root>/.harness-root` and is idempotent · ② it writes **nothing** under a clone's `.claude/` (the plugin is installed once at user scope, so a clone registers nothing) · ③ a `.harness-root` holding a different path is rc≠0 with both paths on stderr, never overwritten · ④ `list` has a harness-root row and no plugin row | `check-all` | a fake harness root and clone root only; `PATH` is narrowed to `/usr/bin:/bin` so that `repo.sh` not calling `claude` also shows |
| `rdup-language-probe.sh` | The R-DUP language narrowing works and its remaining coverage is alive — two fixtures fed to `rules-check.sh` through `RDUP_SCAN_EXTRA` | `check-all` | a baseline `rules-check.sh` at rc 0 |
| `shell-lint.sh` | **Static analysis of the shell** — every `*.sh` under `scripts`·`checks`·`hooks`·`lib` with `shellcheck --severity=warning` | `check-all` | **Without `shellcheck` rc 0 but the phrase says `건너뜀 — 판정하지 않았다`** |
| `workspace-check.sh` | The EnterWorktree flow round trip — reproduces what the native tool does (`git worktree add -b worktree-<id> …`), runs `hooks/enter-worktree.sh` on a sample payload (wiring · bootstrap fallback · a repo with its own hook · cwd outside a worktree · harness root not found → rc=2), then `scripts/workspace-cleanup.sh` | `check-all` | a temporary clone root and a synthetic registry (`REPOS_MANIFEST`) — no real clone is touched |
| `workspace-cleanup-check.sh` | `workspace-cleanup.sh`'s paths — normal cleanup · uncommitted → refused even with `--force` · unpushed → refused, `--force` proceeds · fetch failure → untouched · leftover non-worktree directory · idempotence · a caller standing on a symlinked path · branch-delete failure still reports · other stories' worktrees preserved · unregistered `repo:` label | `check-all` | a temporary clone root |
| `transcript-check.sh` | **Subagent transcripts** — SIGNAL counts per role · tool-use distribution · instance reuse, and **the A9 judgment** (a role reply's first line is exactly `SIGNAL: <VALUE>`). Reads every project directory under `~/.claude/projects` (`--projects`), so sessions opened in target clones are included | not wired — the target is **outside the tree** (`check-all` exempts it; `harness:retrospective` 1-2 calls it) | `python3` (otherwise `UNREACHED:` + rc=2) · transcripts exist. The negative control is its own `--self-check` |

**One more sits outside the table — the inline "disappearing tracked files" check in the harness-root `pre-push` hook.** It is hook body (`.beads/hooks/pre-push`), not a `checks/` script; section 5-1 says what it sees and its limits.

A wired gate's non-zero blocks **every** commit of that repo, so wiring demands three things: fast · no ledger writes · **no environment reason blocks a commit**. What is not wired violates at least one — the "wired where" column says which; the count is not written by hand here.

## 5. 배포 — 마켓플레이스가 나르지 않는 것

The core reaches a project as a plugin install (`claude plugin install harness@skills`), and updates as a marketplace update. The plugin carries skills, agents, hooks, checks, scripts, and the always-on block. **It does not carry settings, git hooks, or anything a clone root needs** — that is the list below. New items go here so nothing is assumed shipped.

| # | Item | Why not automatic | Who does it |
|---|---|---|---|
| 1 | **`permissions.deny` (section 2) and `permissions.allow`** | permissions are not a plugin component | the harness root's `.claude/settings.json` (git-tracked; comes with the clone). A target clone that needs them adds them to its own settings |
| 2 | **A session opened in a directory with no harness settings** | no deny list is loaded there. The plugin itself does load — it is a user-scope install, so it is not what is missing | open development sessions in a registered clone that `repo.sh` has wired; planning sessions at the harness root |
| 3 | **Git hooks** (commit gate · push gate · render) | the harness plants no git hook in any target repo (story `harness-lzs3`) | they exist at the harness root only (`.beads/hooks/`, git-tracked). In a target repo the orchestrator runs `board-check`·`ledger-check` and the backend's ledger reflection (`bd dolt push` on `beads`) as explicit steps of the cycle close |
| 4 | **The harness-root pointer for clone-root sessions** (`~/.harness-workspace/.harness-root`) | a clone root has no worktree wiring to follow (on `beads`, no `.beads/redirect`) | `scripts/repo.sh add`/`restore` write it, and `lib/harness-root.sh` accepts what it names only if `ledger.json` is there |
| 5 | **Taking a settings or plugin change into effect** | hooks, permissions, and plugin versions load at session start; an agent cannot restart its own session | a person restarts the session, then confirms a hook by **what it blocked**, not by its presence |
| 6 | **Enabled but not installed** | `enabledPlugins` turns a plugin on; installing it is a separate action, and the runtime silently skips the hooks of a plugin that is not there | `claude plugin list` shows what is installed; the resolver `scripts/plugin-root.sh` fails loudly when the cache has no install. No gate — [guardrail-verification.md](guardrail-verification.md) 8-1 |

## 5-1. push 게이트 — 원장 반영

**At the harness root** `git push` runs `.beads/hooks/pre-push`, which runs the plugin's `checks/ledger-check.sh` in write mode — **an un-reflected ledger is reflected automatically, and blocked only if that does not resolve it.** The auto-reflection happens only inside `LEDGER_CHECK_PUSH=1`, which that hook block alone sets.

Why ledger reflection is automatic: `git push` is itself an action that requires explicit user instruction, so that moment is already approved, and ledger reflection tied to it is within the same approval (user decision, `harness-bjj`). **The exception grew by one — the working-branch push and PR creation of a cycle close** (`harness-dg0.6.7`), on the same approval logic: what is irreversible is the **merge**, and **a person still merges.** Their triggers differ — ledger reflection is tied to a person's push, the cycle-close push is automatic only when no decision is unresolved. The boundary: **this far it is working-branch push and PR creation for repos registered in `repos.json`**; merge · tag push · release · GitHub issue changes · remote configuration · direct default-branch push · unregistered remotes stay explicit-instruction. The text is `CLAUDE.md` "절대 금지" and the plugin's session block; the approval boundary's evidence is `harness-dmy`.

**In a target repo there is no push hook**, so the ledger does not ride the push. The orchestrator runs the backend's ledger reflection (`bd -C <harness root> dolt push` on `beads`) as step 2 of the cycle close, right after the working-branch push, and reads `ledger-check` afterwards to see `확인됨`. Skip it and the ledger stays a local-only copy. Steps and the failure table: `harness:develop` "사이클 종결".

**The gate mark differs between the two exceptions.** Ledger reflection at the harness root has `ledger-check.sh` **executing and re-judging**. **The PR exception has no gate — neither axis of its judgment is visible.** Left (is a decision unresolved): of the human-wait signals only `status=blocked` shows in a ledger query; the rest (`SCOPE_EXCESS`·`DEVIATION`·`DECISION_NEEDED`·retry ceiling) live in note bodies with no status transition. Right (did the user approve): a hook has **no path at all** to see it. A check counting only `blocked` reports 0 on the rest and passes — exactly the case the exception meant to stop; the rule to read a zero-item pass as failure lands here. **So this exception is persuasion toward the orchestrator.** Building it needs a status transition or a dedicated marker **first**.

**For subagents neither is an exception.** Both belong to the orchestrator; a subagent stops at local commits — `r_remote` holds that line (section 1). Every one of its denials carries the sentence from `harness:develop` "사이클 종결": **what changed is when the orchestrator may, not who.**

An **attempted** auto-reflection does not pass the gate. Not `bd dolt push`'s exit code but a recount of the tracking refs decides. The pass phrase distinguishes `확인됨` (was in sync) from `이번에 수행함` (resolved by the auto-reflection).

**Remote reflection happens only with `LEDGER_CHECK_PUSH=1`, set in the `pre-push` block alone.** Every other call — a role comparing state, a person checking a document, the cycle close in a target repo — has no switch and **reflects nothing.** If the ledger is ahead then, rc is 0 and the phrase is `원격 반영 앞서 있음(반영하지 않음 — 쓰기 모드 아님)` — the judgment is not silenced, and it differs in letters from `확인됨`. The default is the safe side, so no persuasion is left at this place: `guardrail-check` S6 ⑤ asserts that a switchless call leaves `ahead` alone (`harness-x0i.2.1`).

**`r_remote` still cannot see this check** — the rule looks for a push subcommand in the command string, and this call is `bash …/checks/ledger-check.sh` with the reflection inside the script (section 1's "scripts are not seen"). So a call that **explicitly sets** the switch is not blocked by the hook. Keeping the switch to one hook block is the whole defense.

| Condition | Why silent | Resolution |
|---|---|---|
| the ledger is ahead of `remotes/origin/main` (`beads` only) | the ledger sits in `.beads/embeddeddolt/`, `.gitignore`d; git says nothing | **the gate runs `bd dolt push` for you** (harness root). In a target repo, the explicit step of the cycle close |

**The same hook has one more inline check — disappearing tracked files** (`.beads/hooks/pre-push`, right before `ledger-check`). It lists the tracked files that vanish when the pushed HEAD lands on the remote default branch (`git diff --no-renames --diff-filter=D <merge-base> HEAD`) and blocks if there is any. Evidence `harness-w8q` — a squash merge swallows the deletion half of a rename and still returns rc=0, so the names must be raised at push time to have a list to compare afterwards. That is why rename detection is **off** (on, that deletion folds into R and passes silently). The comparison point is the **merge-base**, not the remote tip — a two-point diff against the tip reports every file the default branch gained meanwhile as a deletion whenever local is merely behind. Paths that HEAD's `.gitignore` ignores are excluded — untracking a file to make it generated (the projections did that) is intended. Fail-open on no remote, no auth, or unrelated history, with a phrase saying "검사하지 못했다". Limit: it looks at HEAD — pushing a branch that is not checked out compares the wrong tree. The only escape is below.

**The only escape is `git push --no-verify`.** No dedicated variable or flag — a bypass we build becomes the default path, and using what git already gives leaves the fact in the command line.

**Fail-open boundary** (`ledger-check`): no `dolt` · no `.beads/embeddeddolt` (server mode, or a repo without a ledger) · no Dolt remote → warn and pass. Conversely a ledger that **exists** and is ahead is not "unavailable" but failure.

### 한계 (못 막는 것)

1. **`remotes/origin/main` is a local cache updated only at push and pull.** It catches "what I did not upload" exactly, but not "what others uploaded". Right for this gate's purpose, not a general sync judgment.
2. **Meaningful only where a local ledger exists — that is, on `beads`.** On `github`·`notion` every ledger write is already remote, so there is no un-reflected state for this gate to find and it says `원격 반영 대상 없음`. A push from a target repo never runs this hook — there the reflection is the orchestrator's explicit step, and a session that shipped no code does no `git push` at all, so a session that only piles up ledger writes has no gate at the harness root either. Nothing hangs at session end — the `Stop` hook fires every turn and is the wrong place.
3. **The worktree of the harness repo does run it.** From a harness worktree the ledger location resolves through the wiring the worktree carries, so the gate fires in an isolated workspace too (`harness-js9`).

## 6. 아직 게이트가 없는 규율

The survey (`harness-uhy.1.2 note`) sorted 54 candidates into **fit 30 / unfit 18 / undecided 6**. Of the fit 30, 6 (C1·R1·R2·R3·S7·S18) already had a check; **24 were new work.** Their state:

| State | Count | Items · where |
|---|---|---|
| **Implemented** | 12 | the seven hook rules of section 1 cover C2·C3·A1·A2·A3·A4·A5·R19·S3, and `rules-check.sh` covers R5·R18·S12. A8 (`harness-dg0.6.25`) was covered by `r_bead_leak`, which the plugin move removed — it is back to persuasion (the implementer definition still forbids leaking this ledger's bead IDs into a target repo's commits) |
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
6. **Can `Agent` calls be logged to compare role separation afterwards** (R7)? Unconfirmed. `transcript-check.sh` reads roles from the transcripts' `attributionAgent`, not from `Agent` calls — a different input for the same purpose, so not this item's answer.

**One place is misaligned the other way.** Secret-file handling (X1) has **a gate and no rule sentence** — the deny 10 came first. The survey judged "what protects `.env` today is not a rule but an accident."

## 6-1. 장치 없음 8건 — 설득 말고는 아무것도 없는 자리 [`harness-pl7` 6.4]

Section 6 covers rules without a gate, most of which still have **after-the-fact detection, a checklist, or a report-format constraint**. The eight below have **not even that** — the residue after the root-B audit sorted the substitute mechanisms of the 39 "cannot be gated" items.

**This document starts from mechanisms, so an item without one has no natural place.** It is pinned here so that a reader of sections 1–5 does not **read "covered" from "read".** Line numbers are not copied (they rot); exact locations are the same-ID rows of `harness-dg0.2.3 note`. Paths are plugin-relative.

| # | Rule sentence (where) | Why no mechanism |
|---|---|---|
| C8 | "Explicit user or orchestrator instructions override this Beads block" (`AGENTS.md` bd block) | the interpretation of instruction precedence exists only in conversation — **there is nothing to compare against**. What remains is **persuasion only** |
| R27 | "스토리가 막히면 스토리만 기록하고 다음으로 진행한다" (`skills/develop/SKILL.md` "운영 규율") | a **choice** in procedure flow, not observable as a tool call. What remains is **persuasion only** |
| A15 | "새 제약이 출구를 막지 않는지 본다" (`agents/reviewer.md`) | finding a conflict between rules is natural-language reasoning. What remains is **persuasion only** |
| A17 | "diff 의 각 hunk 가 어느 acceptance 항목에 귀속되는가" — incidental/excess/intrusion/omission and signal priority (`agents/evaluator.md`) | attribution is natural-language reasoning and **the role definition itself admits false positives**. What remains is **persuasion only** |
| S6 | "Do not bootstrap (install dependencies) by hand" (`skills/develop/SKILL.md`) | an approximate check blocks more legitimate local debugging than it catches, and the harm stops at a duplicate install — gain < cost. What remains is **persuasion only** |
| S9 | "Ask before promoting: **does this change follow the repo's convention, or leave it?**" · "**Count directly** …" (`skills/plan-story/SKILL.md`) | the gate is **a conversational act with a person**. What remains is **persuasion only** |
| S14 | "Describe what the project is for **only after user confirmation**" (`skills/setup/SKILL.md`) | whether the user confirmed exists only in conversation. What remains is **persuasion only** |
| S23 | do not start on another actor's claim · "reclaiming … is what a human confirms and directs" (`skills/develop/SKILL.md`) | the second sentence (reclaim instruction) exists only in conversation. The first is covered by the atomicity of `ledger.sh update --claim`, **which is a backend property, not a hook, deny, or check** (R10's reason). What remains is **persuasion only** |

**All eight are of the classes `[outside the boundary]` · `[natural language]` · `[gain<cost]`** — the gate was not left unbuilt; **there is no place to build one.** `A17` is special: it is **the substitute mechanism for two other items (A6·A12) while having none itself**, so the after-the-fact chain ends here in natural-language judgment.

Whether this list equals the 8 of `harness-pl7` 6.4 **as a set** is counted both ways, at the repo root. **The counterpart is that decision's projection** — the original is the ledger and `docs/adr/` is drawn by the plugin's `board.sh adr`, so in an unrendered tree the left side is empty and **an empty match is read as failure**:

```bash
A=docs/adr/natural-language.md; G=docs/guardrails.md   # A is the projection of harness-pl7
ids() { grep -oE '^\| [CRAS][0-9]+' "$1" | tr -d '| ' | sort; }
[ -s "$A" ] || echo "no projection — run board.sh adr first (do not read an empty diff as a match)"
diff <(grep -F '**장치 없음**' "$A" | ids /dev/stdin) \
     <(awk '/^## 6-1\./,0' "$G" | ids /dev/stdin)          # no output = the sets match
awk '/^## 6-1\./,0' "$G" | grep -cE '^\| [CRAS][0-9]+ \|.*persuasion only'   # 8 = written on each of the eight
```

**A value other than 8 and a non-empty diff are both failure.** A 0 on the first means the set matches but "persuasion only" is missing, and then this section is **a list that says a mechanism is absent without saying what that means.**
