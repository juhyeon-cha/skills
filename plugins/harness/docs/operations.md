# Operating flow (operations)

> The order one sprint flows through, and what each step calls. Structure: [architecture.md](architecture.md). Enforcement mechanisms: [guardrails.md](guardrails.md).

## Standard cycle

```
plan-sprint ─→ plan-story ─→ develop ─┬→ verify-code ─→ verify-implement ─→ ledger close
 (compose·label) (decompose·acceptance) │   (reviewer)      (evaluator·close)
                                      └── repeat per milestone (batch condition: develop section 3) ──┘
                                                   ↓ story complete
                                             retrospective
```

- Each step's procedure is the skill of the same name in the `harness@skills` plugin (`harness:<name>`). Skills carry delegation and signal handling; role discipline is carried by the plugin's `agents/` definitions — a delegation message carries only "paths + IDs + task-specific context".
- The completion-flow rules (whoever built it does not grade it, no close without MATCH, …) are owned by `harness:develop` "운영 규율"; the always-on subset is the plugin's session block.

## New-session bootstrap

**One place: inside a target repo.** The session's cwd is what picks the ledger — `lib/harness-root.sh` walks up to the first `.harness.json` — so there is nowhere else to open.

| Session | Open where | Why |
|---|---|---|
| Planning · retrospective (`harness:plan-sprint` · `harness:plan-story` · `harness:retrospective`) | the **main checkout** of the repo the work concerns | the work is entirely in the ledger; nothing is edited, so the main checkout is where to stand. With several repos any of them answers the same ledger — pick the one the stories concern |
| Development (`harness:develop` and the verify skills it calls) | the **main checkout of the target repo** | that repo's own `CLAUDE.md`, rules, skills, and hooks load; `EnterWorktree` makes the story worktree inside it. One session per (story, repo) |

What loads automatically in both: the project `CLAUDE.md` of the directory the session opened in, and the plugin's SessionStart block (`hooks/session-context.md` — "절대 금지", ledger location, skills and roles, the hierarchy mapping, and where every other rule is owned). No hook primes a backend tool (`bd prime` on `beads` included). Parallel sessions split work **by story** — two sessions on the same (story, repo) are forbidden. Task claiming is `ledger.sh update <task ID> --claim --actor <value>`; the actor's source and the pickup rule are `harness:develop` section 1.

**Every ledger call in this document is the adapter** — `bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh <subcommand>`, abbreviated `ledger.sh …`. Which backend answers is `.harness.json`'s `ledger.backend`; where a step only exists for one backend, the backend is named.

1. See ready work with `ledger.sh ready`. On a backend with no UI of its own, a sprint in progress is read from the projection `docs/sprints/<ID>/` in the repo (outside git — if missing or stale, `bash ${CLAUDE_PLUGIN_ROOT}/scripts/board.sh all`); on `github`·`notion` the ledger's own board is that screen and nothing is rendered.
2. Call the skill that fits the work (the cycle above).
3. In a development session, `harness:develop` section 2 enters the worktree. `lib/harness-root.sh` answers from the cwd — `HARNESS_ROOT`, else the first `.harness.json` walking up; a worktree carries its own copy, so it answers itself and the ledger coordinates are the same values the main checkout holds. Worktree wiring (on `beads`, `.beads/redirect`) is a beads-backend matter and takes no part in finding the root.

## Unattended loop

- **Drain permission prompts before an unattended loop.** The worktree is outside the project directory, so the first command there may ask for approval and nobody answers during the loop — run one command in the worktree interactively first, or put the needed allows into `.claude/settings.local.json` of the clone.
- The loop is `/loop` (built into Claude Code) and follows `harness:develop` "장기 실행" — how it relates to the pipeline, how it is broken from inside, and the stop guard's marker for the outside. **Those rules are not restated here** — that section is their single owner, so a copy necessarily diverges.

## Documents go nowhere — projections are outside git

The ledger **rides no branch** — on `beads` it is a single `.gitignore`d DB global across branches and worktrees, and on `github`·`notion` it is not in the tree at all — and the projections `docs/sprints/` · `docs/backlog/` · `docs/adr/`, where they exist at all, sit under the harness root, which is not a git tree. What goes to a remote is the ledger (`bd dolt push` on `beads`; nothing to send on the other two, which are remote already), and whoever wants the documents redraws them with `board.sh all` — a step a person or a procedure runs, since no git hook does it. Whichever tree you look at, its harness documents are that machine's projection of the ledger, so there is no document-mismatch window between branches.

| Artifact | What the commit carries | Endpoint |
|---|---|---|
| **Planning** (sprint composition · story decomposition) | **nothing** — the registries are behind the adapter and the root's files are machine-local, so planning produces no diff in any repo. What is left is the ledger's own reflection (`plan-sprint` 6 · `plan-story` 7) | no PR — there is nothing to merge |
| **Task close** (`verify-implement` 3) | the code on the development branch. No documents | **PR creation** — a person merges |

**Ledger reflection is an explicit step, never something a push carries.** No harness git hook exists, at the harness root or in a target repo, so the reflection happens where the cycle close says it does — the steps, their order, scope, and failure handling are owned by `harness:develop` "사이클 종결" and not restated here.

## Remote reflection — the boundary is single-owned by the first item of the session block's "절대 금지"

What goes out without instruction and what needs approval is held by that item's **two exceptions**. The list is not repeated here — a copy would make this file say two things, and a stale copy is what the plugin's `rules-check.sh` R-REM catches.

## Ledger maintenance — `dolt gc`, pull, push

**This whole section is the `beads` backend's.** It is about the embedded Dolt DB that backend keeps at the harness root; on `github`·`notion` the ledger is somebody else's server and none of it applies. The commands here are `bd`'s own, not adapter subcommands — `ledger.sh` passes `dolt`·`export`·`import`·`bootstrap` straight through on `beads` and exits non-zero on the other two.

**A growing ledger is normal.** Dolt is copy-on-write — every write creates new prolly-tree chunks and materializes intermediate state on disk. Only what is reachable from the commit graph is permanent; the rest is reclaimable. And `bd` **makes a Dolt commit per write** — every `note`·`close`·`create`·`label` is a commit, so ordinary use alone grows it.

### What `dolt gc` does and when to run it

Removes unreachable chunks. Generational: chunks reachable from a commit move to `oldgen` and are skipped by later gc. Three modes — default (new gen only) · `--shallow` (faster, less thorough) · `--full` (oldgen too). **Start with the default.** `--full` scans more, so its connection-blocking window is longer, and the extra reclaim exists only when oldgen has piled up.

**When — once the journal has bloated.** Most of the reclaim is the `.dolt/noms/vvvv…` journal, so `du -sh .beads/embeddeddolt/<name>/.dolt/noms/vvvv*` around 100M is the trigger — an **arbitrary baseline** taken from an observed 237M, not a measured threshold. In the measurement the journal went 237M → 4.0K and `.dolt` 372M → 239M (−36%). Local queries got faster too, but **one measurement without controlling cache state, so the multiplier is not a baseline** (roughly 1.5–2×). Size figures do not depend on cache, so they stand. Evidence: `harness-5qyb.2.1`.

### Before running — the core of this section

1. **It is irreversible.** Take a JSONL backup with `ledger.sh export` first and record line count and size. Recovery path: `ledger.sh bootstrap` + `ledger.sh import`.
2. **It is an explicit-instruction action.** An agent does not run it on its own judgment.
3. **It resets DB connections — do not run while another session is writing the ledger.** No data is lost, but in-flight queries fail. The danger is not the failure itself but **a ledger-reading judgment (a reviewer's acceptance lookup, say) mistaking an empty result for the answer.**

**"Not writing" is confirmed by a reply, not by a notice.** Order: notify → back up → **wait** → run → compare before/after → notify afterwards.

- **Who to notify**: the users of this machine's other sessions, identified through the ledger's `in_progress`·`assignee`·`updated_at`.
- **Put the wait limit in the notice as a number.** "A moment" is not a limit — form: `<HH:MM>까지 회신이 없으면 진행합니다`.
- **When the limit passes, proceed.** Waiting forever makes one dead session a deadlock. Say in the after-notice that you proceeded.

**What the notified side checks** — did my ledger-reading work fall into that window:

1. Did a judgment fail to quote the acceptance, or mention "lookup failed / empty result"?
2. Was a judgment's evidence written from the commit diff alone, never compared with the ledger text?
3. Was a `bd` lookup error written into a report?

None of the three → no contamination. Any one → redo that judgment.

**There may be no stakeholder — that is the default path.** With no other session writing the ledger, there is nobody to notify and the check above is your own. Another session catching a flaw in your measurement is nice to have, not something to count on.

### Slow `bd dolt pull`·`push` is not fixed

Seconds, and that is normal. Measured: `bd dolt pull` (nothing to receive) 7.6 s — **split in two, neither of which the harness can touch**: `dolt fetch` directly is 3.7 s (network round trip to the remote) and the remaining 3 s is inside the `bd` wrapper. **That local ledger size is unrelated to transfer volume (incremental) is a judgment, not a measurement** — pull was not re-timed after gc. On that judgment, no further investigation. Evidence: story `harness-5qyb` body ②.

## New clone, new harness, update

- **A new machine joining a standing harness — two commands.** Install the plugin at user scope and clone a repo that already carries `.harness.json`; the clone brings the ledger coordinates with it and may live anywhere. What still needs credentials per backend (`gh auth` · `NOTION_TOKEN` · `ledger.sh bootstrap`) is owned by `harness:setup` "2. B — Join an existing harness" and is not restated here. Until `ledger.sh list` is rc 0, every skill and gate is powerless.
- **On `beads` the remote is the only ledger backup.** Lose `.beads/embeddeddolt/` and the sprint and judgment history is gone — projections are outside git and cannot restore the ledger. A ledger on one machine only is not a normal state. `github`·`notion` have no local copy to lose.
- **Standing up a new harness**: `harness:setup` "1. A — New harness". The core is never copied into a project — the plugin is installed next to it.
- **Updating a standing harness**: `harness:setup` "3. C — Update" (`claude plugin marketplace update skills` then `claude plugin update harness@skills`, then restart the session). No file of the repo is overwritten by an update.
