# Engineering discipline (in whatever repo a cycle runs)

> The discipline a development cycle carries into **any** target repo: how to prove a gate is alive, the shell traps measured here, where a document goes, and two environment facts that decide whether a command works at all. Structure: [architecture.md](architecture.md). Operation: [operations.md](operations.md). Enforcement mechanisms: [guardrails.md](guardrails.md).
>
> **This document ships.** It is read while a cycle runs, so it lives in the plugin. The rules for changing the harness **itself** — the repo gate, adding a hook rule, the plugin boundary — are not here: they are the skills repo's own `docs/development.md`, because only a session in that clone can act on them.

## Checking that a check is alive

When creating or changing a check, **prove in the same turn that it fails when it dies.** A pass (rc=0) cannot distinguish "checked, no problem" from "never ran".

- **A/B attribution** — in a copy with only that rule's registration removed, the same input passes. Required whenever several rules share a judgment point.
- **Negative control** — a copy with the answer disturbed in one place is caught without fail.
- **Reached-judgment assertion** — each check leaves state saying it reached its judgment, and unreached is read as failure.
- **Target assertion** — pin **what** the check looks at. Use it wherever a same-named file exists in several trees (copies, projections, caches).

An assertion that becomes true on an empty set (a zero-item pass) is read as failure. **If the A/B or negative-control copy equals the original, or does not exist, that itself is failure** — assert both files exist first, then compare: `[ -s a ] && [ -s b ] && ! cmp -s a b`. **When a limit pinned as rc=0 is closed, do not delete it — move it to a blocking assertion.**

**A gate is verified too** — measure the normal path at 0 and **a deliberately broken path at non-zero**, and write both into the commit message. **"The gate passed" and "there was something to check" differ** — an empty target set passes any gate, so look for the path that passes silently on zero items.

Write a new gate in the **inverted-polarity** form (`harness:develop` "운영 규율"): the checked set is derived from the whole, exemptions carry a reason, and the reverse assertion (the exempted key exists) sits beside them.

> Evidence: `harness-uhy` · `harness-4kc` · `harness-erf`.

## Shell traps (measured only)

- **Never feed JSON with `echo "$var" | jq` — use `printf '%s' "$var" |`.** In backslash-expanding shells (sh, xpg_echo) echo turns `\n`·`\uXXXX` inside fields into raw control characters and jq dies with rc=5. bash's builtin echo does not break, but that is the shebang covering for an unsafe pattern.
- **Quote the right-hand side of a `[[ ]]` string comparison.** bash treats an **unquoted right-hand side as a glob** with `=` and `==` alike (`b='w*'; [[ "wow" = $b ]]` matches) — the operator is no defense. Quote literal comparisons as `"$b"`; leave it unquoted only when glob matching is the intent, with a comment.
- **`git -C <path>` is overridden by `GIT_DIR`·`GIT_INDEX_FILE` in the environment — the environment beats the path argument.** Hooks carry those variables, so a call aimed at another tree goes to the wrong repo only inside a hook. Run by hand, the variables are absent and it passes, so **it breaks only at commit and push time.** Cut the environment with `env -u GIT_DIR -u GIT_INDEX_FILE …` for git calls aimed at another tree, and run a new gate once inside a hook to see the rc match.
- **Collect exit codes outside a pipe — throwaway verification scripts included.** `$?` after `cmd | tail` is tail's. Piping a command expected to fail into `| grep -q` lets pipefail steal the rc so a match reads as failure, and `grep -q` on multi-line output produces SIGPIPE (141) by exiting early. Standard pattern: `OUT=$(cmd 2>&1); rc=$?; echo "$OUT" | grep …`

## The environment a command actually runs in

- **Approval rules do not cover a command with a file redirection** [measured — `harness-m8gg.8.12` note]. `bash <script> >/dev/null 2>&1` is refused under `Bash(<prefix>:*)` · `Bash(<prefix> *)` · `Bash(*)` alike — not a rule-syntax issue: the redirection is split off for approval before rule matching. `2>&1` alone and pipes are approved. To cut prompts, **drop the `>` from the command**, not the rule. A command after `;`·`&&` is not approved by a prefix rule either — the approval rule is not an injection channel.
- **The shell baseline is macOS's default `bash` 3.2.** No `mapfile`/`readarray`, `declare -A`, `${var,,}`, `${var^^}`. (Measured: a missing `mapfile` killed one check of `ledger-check` outright while the script reported only the remaining reasons — with a clean audit log that would have been a false rc=0 pass.)

## Where a document goes

A standalone user-requested report or investigation can be saved in the task artifact directory. It is not a generated ledger projection or a plugin instruction. Repository files still use an assigned linked worktree; producing an external artifact does not require creating a story or PR.

**Pick the place from this table before creating a document.** If none of the five fits, it is not a document yet but an unsorted memo.

| Kind | Place | Why there |
|---|---|---|
| **Decision** — what was decided and why | a `decision` bead in the ledger, status `pinned` | rides no branch, so it reads the same from every tree. Supersession is not deletion but `ledger.sh supersede <old> --with <new>` keeping the lineage (a `beads`-only subcommand — on another backend the lineage is kept by the backend's own means) |
| **Core document** — rules, structure, procedure **an install reads** | the plugin (`skills/` · `agents/` · `hooks/session-context.md` · `docs/`) | the plugin is what every install receives. Only sentences that change the next person's behavior |
| **Document only the people building the tool read** | the source repo, outside the plugin (for the harness: the skills repo's `docs/`) | an install copies the plugin tree whole and cannot leave a file out, so a document it never opens is weight it carries forever. The test is the same one the code takes: **does the installed copy read it?** |
| **Time-stamped record** — measurements, history, counts, dates | the **`note` of the bead** that produced the change | in a rule body it costs load every session. A rule keeps a one-line pointer (first item below) |
| **Projection outside git** — the ledger drawn for people | `docs/sprints/` · `docs/backlog/` · `docs/adr/` — **three** | the ledger is the SSOT. All three are `.gitignore`d and one command, the plugin's `scripts/board.sh all`, draws them |

- **Decisions do not go into `docs/` as markdown.** The two things a decision needs — riding no branch, and a supersession lineage — a file gives neither. `docs/adr/` is a **projection** of decision beads, not the original.
- **The three projections are never hand-edited.** The next render overwrites them — fix the ledger.
- **Measurement in a rule body goes only as far as the mechanism that changes behavior** — dates, counts, and the story of what happened belong to the **`note` of the task bead** that produced the change, and lineage belongs to commit messages and git. Rules load every session and the reader is an agent: a sentence that does not change the next action only costs load.
  - **One criterion: does deleting the sentence change the next person's behavior?** If yes, it stays in the rule; if not, it goes to the bead and **one pointer line** (`실측 근거는 <bead ID>`) stays. Never delete the evidence outright — a rule without a reason gets deleted by the next person.
- Renaming a rule, skill, or file is done globally at once, with **zero remaining old names** confirmed by grep before reporting.
- **Comments and documents carry the behavior after the change (the fact), not a correction history.** No "it used to be X, now it is Y" paragraphs — delete the old description and write the **current fact**. Do not keep the previous figure next to an updated one. Correction paragraphs turn a comment into a résumé that hides the current behavior, and git and the ledger already hold the history — same direction as the criterion above.
  - **Exception ① where a user decision was applied.** Then keep the decision and its reason — a decision steers the next person's behavior and cannot be reconstructed once deleted.
  - **Exception ② the ledger (`ledger.sh note`) is outside this rule.** It is governed by "Correction preservation" in `harness:develop` "운영 규율": when overturning a judgment, quote the original and write what was wrong and why. **The two rules point in opposite directions, so they split by target — a file (comment, document) deletes and keeps the current fact; the ledger keeps.**
