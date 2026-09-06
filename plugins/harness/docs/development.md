# Development rules (when changing the harness itself)

> Rules for evolving the harness consistently. Structure: [architecture.md](architecture.md). Operation: [operations.md](operations.md).
>
> **Where the code is.** The core (skills · agents · hooks · checks · scripts · lib) is the plugin `harness@skills`, source `${CLAUDE_PLUGIN_ROOT}` (`plugins/harness` in the skills repo). This repo — the harness root — holds `ledger.json` (which backend the ledger has), the ledger itself when the backend is `beads`, the registries, `CLAUDE.md`, these documents, the git hooks under `.beads/hooks/`, and `scripts/plugin-root.sh`. A change to the core is a story on the `skills` repo; a change to a registry, a document, or a git hook is a story on the `harness` repo. Both follow the same flow: development session in the clone, `EnterWorktree`, PR.

## 판정과 게이트

- This repo's gate is `repos.json` → `harness.check`: it resolves the plugin with `scripts/plugin-root.sh` and runs the plugin's `scripts/check-all.sh` — every `checks/*.sh` of the plugin, with the exemptions (`guard-check` too slow · `transcript-check` judges outside the tree · `ledger-check` touches the remote) listed with reasons inside that file. The ledger-reading checks reach the ledger through the adapter `scripts/ledger.sh` and find the harness root through `lib/harness-root.sh`, whose marker is `ledger.json`; from a `beads` story worktree that is the redirect, so no environment variable is needed. `check-all.sh` runs every check **from the caller's cwd** (it only moves itself to the plugin root), so a run inside a harness worktree judges that worktree's `repos.json` · `.gitignore` and the ledger the worktree redirects to — not the plugin's own tree. Everywhere else — a copy root, a fixture, a `github`·`notion` worktree — set `HARNESS_ROOT`. Before the marketplace carries the plugin, export `HARNESS_PLUGIN_ROOT=<skills clone>/plugins/harness`. **Which checks the git hooks wire, why, and the fail-open rules are held by [guardrails.md](guardrails.md)** — enforcement talk lives in that one place.
- The plugin's own gate (in the skills repo) is `claude plugin validate --strict` per plugin; `check-all.sh` is run by hand there, or through this repo's `harness.check`.
- Write a new gate in the **inverted-polarity** form (`harness:develop` "운영 규율"): the checked set is derived from the whole, exemptions carry a reason, and the reverse assertion (the exempted key exists) sits beside them.
- **A gate is verified too** — measure the normal path at 0 and **a deliberately broken path at non-zero**, and write both into the commit message. **"The gate passed" and "there was something to check" differ** — an empty target set passes any gate, so look for the path that passes silently on zero items. The proof method is "검사가 죽었는지 검사한다" below.

## 검사가 죽었는지 검사한다

When creating or changing a check, **prove in the same turn that it fails when it dies.** A pass (rc=0) cannot distinguish "checked, no problem" from "never ran".

- **A/B attribution** — in a copy with only that rule's registration removed, the same input passes. Required whenever several rules share a judgment point.
- **Negative control** — a copy with the answer disturbed in one place is caught without fail.
- **Reached-judgment assertion** — each check leaves state saying it reached its judgment, and unreached is read as failure.
- **Target assertion** — pin **what** the check looks at. Use it wherever a same-named file exists in several trees (copies, projections, caches).

An assertion that becomes true on an empty set (a zero-item pass) is read as failure. **If the A/B or negative-control copy equals the original, or does not exist, that itself is failure** — assert both files exist first, then compare: `[ -s a ] && [ -s b ] && ! cmp -s a b`. **When a limit pinned as rc=0 is closed, do not delete it — move it to a blocking assertion.**

> Evidence: `harness-uhy` · `harness-4kc` · `harness-erf`.

## 셸 함정 (실측으로 확인된 것만)

- **Never feed JSON with `echo "$var" | jq` — use `printf '%s' "$var" |`.** In backslash-expanding shells (sh, xpg_echo) echo turns `\n`·`\uXXXX` inside fields into raw control characters and jq dies with rc=5. bash's builtin echo does not break, but that is the shebang covering for an unsafe pattern.
- **Quote the right-hand side of a `[[ ]]` string comparison.** bash treats an **unquoted right-hand side as a glob** with `=` and `==` alike (`b='w*'; [[ "wow" = $b ]]` matches) — the operator is no defense. Quote literal comparisons as `"$b"`; leave it unquoted only when glob matching is the intent, with a comment.
- **`git -C <path>` is overridden by `GIT_DIR`·`GIT_INDEX_FILE` in the environment — the environment beats the path argument.** Hooks carry those variables, so a call aimed at another tree goes to the wrong repo only inside a hook. Run by hand, the variables are absent and it passes, so **it breaks only at commit and push time.** Cut the environment with `env -u GIT_DIR -u GIT_INDEX_FILE …` for git calls aimed at another tree, and run a new gate once inside a hook to see the rc match.
- **Collect exit codes outside a pipe — throwaway verification scripts included.** `$?` after `cmd | tail` is tail's. Piping a command expected to fail into `| grep -q` lets pipefail steal the rc so a match reads as failure, and `grep -q` on multi-line output produces SIGPIPE (141) by exiting early. Standard pattern: `OUT=$(cmd 2>&1); rc=$?; echo "$OUT" | grep …`

## 훅 규칙을 새로 쓸 때 — 플러그인 `hooks/guard.sh`

The as-built rule list and each rule's limits are [guardrails.md](guardrails.md) section 1. What is here is **the convention for whoever adds a rule** — in the plugin source, `${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh`.

- **One rule = one function + one `RULES` line, and the function name has the `r_` prefix.** Entry form is `"<tool name or *>:<function name>"`; the dispatcher matches against `tool_name` and calls only what matches. Block with `deny "<reason>"` (exit code 2 + stderr), pass with `return 0`.
- **Rule blocks come *after* the `RULES=()` declaration.** Above it, `RULES=()` wipes every registration already made and a hook with no rule at all passes silently with rc=0. It happened once. The `r_` prefix and this placement are derived from the source and asserted by `checks/guard-check.sh`'s `registry_intact`, so a name outside the prefix is caught by the gate too.
- **A rule body does not enumerate command shapes with regexes.** In the spike that approach leaked three times in a row (wrapper `timeout 5 git push`, option position `git -C repo worktree add`) and once matched **by accident** through a `.git` inside a path. Inverted polarity — the presence of the subcommand token only — caught all eight as intended. So the skeleton offers `has_token` alone, and false positives (`git log --grep worktree` blocks too) are the price of that trade.
- **Every rule added gets a blocking case and a passing case in `checks/guard-check.sh`.** Blocking cases alone cannot tell a dead rule; passing cases alone pass a rule that blocks nothing. Both are needed because of a measurement — one rule exiting through `deny` means the remaining rules never run for that call, so a wrongly blocking earlier rule leaves the later rules unverified yet green. The passing case is the only net for that.
- **Tree judgment uses the payload, not an anchor.** `GUARD_ROOT` is the plugin root (`CLAUDE_PLUGIN_ROOT`, else the script's own parent) and no rule uses it to judge a tree — it appears only in internal-error messages and to locate `lib/harness-root.sh`. Rules that need the clone root use `${HARNESS_CLONE_ROOT:-$HOME/.harness-workspace}` — the same convention `scripts/repo.sh` and `hooks/enter-worktree.sh` use — and relative paths are folded against the payload `cwd`. Role rules compare `agent_type` against `harness:<name>` only.
- **No rule-injection point in the shipped hook.** An early version sourced a file named by an environment variable, claiming rules could only be added. False — sourcing is just bash and can redefine anything; a two-line file (`RULES=()` and `deny() { return 0; }`) let `git push origin master` through with rc=0. The sourcing path is gone; the gate tests rule removal by inserting into a **copy** right after `RULES=()`, and asserts first that the copy differs from the original.

## 문서

### 무엇을 어디에 두는가

**Pick the place from this table before creating a document.** If none of the four fits, it is not a document yet but an unsorted memo.

| Kind | Place | Why there |
|---|---|---|
| **Decision** — what was decided and why | a `decision` bead in the ledger, status `pinned` | rides no branch, so it reads the same from every tree. Supersession is not deletion but `ledger.sh supersede <old> --with <new>` keeping the lineage (a `beads`-only subcommand — on another backend the lineage is kept by the backend's own means) |
| **Core document** — rules, structure, procedure | the plugin (`skills/` · `agents/` · `hooks/session-context.md`) for what every project shares; `docs/*.md` here for the harness root's own structure and rules | the plugin is what every install receives. Only sentences that change the next person's behavior |
| **Time-stamped record** — measurements, history, counts, dates | the **`note` of the bead** that produced the change | in a rule body it costs load every session. A rule keeps a one-line pointer (first item below) |
| **Projection outside git** — the ledger drawn for people | `docs/sprints/` · `docs/backlog/` · `docs/adr/` — **three** | the ledger is the SSOT. All three are `.gitignore`d and one command, the plugin's `scripts/board.sh all`, draws them |

- **Decisions do not go into `docs/` as markdown.** The two things a decision needs — riding no branch, and a supersession lineage — a file gives neither. `docs/adr/` is a **projection** of decision beads, not the original.
- **The three projections are never hand-edited.** The next render overwrites them — fix the ledger.
- **Measurement in a rule body goes only as far as the mechanism that changes behavior** — dates, counts, and the story of what happened belong to the **`note` of the task bead** that produced the change, and lineage belongs to commit messages and git. Rules load every session and the reader is an agent: a sentence that does not change the next action only costs load.
  - **One criterion: does deleting the sentence change the next person's behavior?** If yes, it stays in the rule; if not, it goes to the bead and **one pointer line** (`실측 근거는 <bead ID>`) stays. Never delete the evidence outright — a rule without a reason gets deleted by the next person.
- Renaming a rule, skill, or file is done globally at once, with **zero remaining old names** confirmed by grep before reporting.
- **Comments and documents carry the behavior after the change (the fact), not a correction history.** No "it used to be X, now it is Y" paragraphs — delete the old description and write the **current fact**. Do not keep the previous figure next to an updated one. Correction paragraphs turn a comment into a résumé that hides the current behavior, and git and the ledger already hold the history — same direction as the criterion above.
  - **Exception ① where a user decision was applied.** Then keep the decision and its reason — a decision steers the next person's behavior and cannot be reconstructed once deleted.
  - **Exception ② the ledger (`ledger.sh note`) is outside this rule.** It is governed by "정정 보존" in `harness:develop` "운영 규율": when overturning a judgment, quote the original and write what was wrong and why. **The two rules point in opposite directions, so they split by target — a file (comment, document) deletes and keeps the current fact; the ledger keeps.**

## 스킬·역할 정의

- A skill carries delegation, signal handling, and order only. Role discipline (path check, full-text gate judgment, the forbidden list) is owned by the plugin's `agents/` definitions — never the same rule in two places.
- No absolute path is **baked** into a core file. The clone root is `${HARNESS_CLONE_ROOT:-$HOME/.harness-workspace}` — checks redirect it to a temporary directory so they verify without touching real clones. The harness root is what `lib/harness-root.sh` prints, or `HARNESS_ROOT`.
- **The harness root travels in the delegation message.** The worktree is outside the harness (`~/.harness-workspace/<repo>/.claude/worktrees/<story ID>/`), so it cannot be derived from the path. A new role or skill that forgets the slot for that value leaves the subagent unable to call `ledger.sh` at all — `HARNESS_ROOT=<harness root>` is the only thing that points it at this harness.
- Skills and agents reference each other and the plugin's own files through `${CLAUDE_PLUGIN_ROOT}` — the runtime substitutes it with the install path in skill and agent bodies.

## 플러그인 경계

- **Core** (shared by every project): the plugin — `skills/` · `agents/` · `hooks/` · `checks/` · `scripts/` · `lib/` · `.claude-plugin/plugin.json`. Nothing in it names a project, a path under a home directory, or a person.
- **Project context** (differs per project): the harness root — `ledger.json` · `repos.json` · `rails.json` · `sprints.json` · `CLAUDE.md` · `.beads/` (the `beads` backend's ledger and git hooks) · `docs/` · `.claude/settings.json` (permissions) · `scripts/plugin-root.sh`. Projections are outside git and belong to neither.
- **What the plugin cannot carry, the harness root and `repo.sh` do.** `permissions.deny` (the 10 secret-file patterns) and `permissions.allow` are settings, not plugin components — they live in this repo's `.claude/settings.json`. The plugin itself is enabled by neither — it is installed at **user scope**, so nothing in a project or a clone registers it. The harness-root pointer for clone-root sessions is `~/.harness-workspace/.harness-root`, written by the plugin's `scripts/repo.sh`. Git hooks exist at the harness root only.
- **Approval rules do not cover a command with a file redirection** [measured 2026-09-04, claude 2.1.260]. `bash <script> >/dev/null 2>&1` is refused under `Bash(<prefix>:*)` · `Bash(<prefix> *)` · `Bash(*)` alike — not a rule-syntax issue: the redirection is split off for approval before rule matching. `2>&1` alone and pipes are approved. To cut prompts, **drop the `>` from the command**, not the rule. A command after `;`·`&&` is not approved by a prefix rule either — the approval rule is not an injection channel.
- **The shell baseline is macOS's default `bash` 3.2.** No `mapfile`/`readarray`, `declare -A`, `${var,,}`, `${var^^}`. (Measured: a missing `mapfile` killed one check of `ledger-check` outright while the script reported only the remaining reasons — with a clean audit log that would have been a false rc=0 pass.)

## 릴리스

- **This root carries no version number of its own.** What gets released is the plugin `harness@skills`, and the number has exactly one source — `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`. The history is `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md` and the tag is `harness-v<number>`; the marketplace reads the number from `plugin.json`.
- **The procedure is owned by the `harness:release` skill** — the sweep from the previous tag, the bump width (decided by what an install has to do by hand), the entry, raising the number, `claude plugin validate --strict`, and the local commit and tag. It is not restated here.
- **Tag push and a GitHub release (`gh release create`) only on explicit user instruction.**

## 원격

Local commits are free. Tag push · merge · release publishing only on explicit user instruction, and an approval is valid for that one time. **Working-branch push and PR creation are automatic only as the product of a cycle close** — only when no decision is unresolved in that cycle (exception two of `CLAUDE.md` "절대 금지"). At the harness root, ledger reflection rides that push; in a target repo it is the explicit ledger-reflection step of the cycle close (`bd dolt push` on `beads`).
