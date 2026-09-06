# Operating flow (operations)

> The order one sprint flows through, and what each step calls. Structure: `architecture.md` at the harness root. Enforcement mechanisms: [guardrails.md](guardrails.md).

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

**Two places, by what the session does.**

| Session | Open where | Why |
|---|---|---|
| Planning · retrospective (`harness:plan-sprint` · `harness:plan-story` · `harness:retrospective`) | the **harness root** | the ledger and the registries are here; nothing is edited in a target repo |
| Development (`harness:develop` and the verify skills it calls) | the **clone root of the target repo** — `~/.harness-workspace/<repo>` | the target repo's own `CLAUDE.md`, rules, skills, and hooks load; `EnterWorktree` makes the story worktree inside that clone. One session per (story, repo) |

What loads automatically in both: the project `CLAUDE.md` of the directory the session opened in, and the plugin's SessionStart block (`hooks/session-context.md` — "절대 금지", ledger location, skills and roles, the hierarchy mapping, and where every other rule is owned). No hook primes a backend tool (`bd prime` on `beads` included). Parallel sessions split work **by story** — two sessions on the same (story, repo) are forbidden. Task claiming is `ledger.sh update <task ID> --claim --actor <value>`; the actor's source and the pickup rule are `harness:develop` section 1.

**Every ledger call in this document is the adapter** — `bash "$(bash scripts/plugin-root.sh)/scripts/ledger.sh" <subcommand>`, abbreviated `ledger.sh …`. Which backend answers is `ledger.json`'s `backend`; where a step only exists for one backend, the backend is named.

1. See ready work with `ledger.sh ready`. A sprint in progress is read from `docs/sprints/<ID>/` (outside git — if missing or stale, `bash "$(bash scripts/plugin-root.sh)/scripts/board.sh" all` at the harness root).
2. Call the skill that fits the work (the cycle above).
3. In a development session, `harness:develop` section 2 enters the worktree; inside it, `lib/harness-root.sh` finds the harness root through the wiring `ledger.sh wire-worktree` left (on `beads`, `.beads/redirect`). Before the worktree exists, the same helper reads `~/.harness-workspace/.harness-root` from the clone root, which `repo.sh` writes. Either way the marker of the root is `ledger.json`.

## Unattended loop

- **Drain permission prompts before an unattended loop.** The worktree is outside the project directory, so the first command there may ask for approval and nobody answers during the loop — run one command in the worktree interactively first, or put the needed allows into `.claude/settings.local.json` of the clone.
- The loop is `/loop` (built into Claude Code) and follows `harness:develop` "장기 실행" — how it relates to the pipeline, how it is broken from inside, and the stop guard's marker for the outside. **Those rules are not restated here** — that section is their single owner, so a copy necessarily diverges.

## Documents go nowhere — projections are outside git

The ledger **rides no branch** — on `beads` it is a single `.gitignore`d DB global across branches and worktrees, and on `github`·`notion` it is not in the tree at all — and `docs/sprints/` · `docs/backlog/` · `docs/adr/` are `.gitignore`d generated files that ride no branch either. What goes to a remote is the ledger (`bd dolt push` on `beads`; nothing to send on the other two, which are remote already), and the receiving side redraws with `board.sh all` from the `post-merge`·`post-checkout` hooks. Whichever tree you look at, its documents are that machine's projection of the ledger — there is no document-mismatch window between branches.

| Artifact | What the commit carries | Endpoint |
|---|---|---|
| **Planning** (sprint composition · story decomposition) | only registry changes (`sprints.json` · `rails.json`) — `plan-sprint` 6 · `plan-story` 7. With no change there is no commit and no PR; only ledger reflection remains | **PR creation** — a person merges |
| **Task close** (`verify-implement` 3) | the code on the development branch. No documents | **PR creation** — a person merges |

**Ledger reflection differs by where the push happens.** At the **harness root**, `git push` runs the `pre-push` hook, which runs the plugin's `ledger-check.sh` in write mode — the ledger goes out with the push (exception one of `CLAUDE.md` "절대 금지"). In a **target repo**, no harness git hook is planted: the ledger reflection is an explicit step of the cycle close, and the steps, their order, scope, and failure handling are owned by `harness:develop` "사이클 종결" — not restated here.

## Remote reflection — the boundary is single-owned by the first item of `CLAUDE.md` "절대 금지"

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

## 원장 이전 — `beads` → `github`

Moving a standing ledger to another backend. The tool is `${CLAUDE_PLUGIN_ROOT}/scripts/ledger-migrate.sh`, and **the order of its three subcommands is the procedure** — each one's output is the next one's input.

```bash
P=${CLAUDE_PLUGIN_ROOT}
bash $P/scripts/ledger-migrate.sh plan   --from <harness root> > plan.json
bash $P/scripts/ledger-migrate.sh apply  --plan plan.json --map map.txt --from <harness root>
bash $P/scripts/ledger-migrate.sh verify --plan plan.json --map map.txt --from <harness root>
```

- **`plan` reads only.** It takes every **open** item out of `bd` as a JSON array and touches no network. Closed items do not move — the finished work stays in the old ledger, which is why a closed sprint renders as 0 items afterwards (`board.sh` passes that; `scripts/board.sh` says why at its zero-count branch).
- **`apply` writes,** and `map.txt` (`<beads id> <repo>#<number>` per line) is what makes it idempotent — a re-run skips what the map already names. Keep the map; without it a second `apply` duplicates every issue.
- **`verify` compares** the plan against the issues themselves, reading each one by the id in the map. It does not judge by search or listing: right after creation `gh issue list` returned 3 of 5 and only had 5 after 39 s, and `gh project item-list` did not show new items either (`harness-kw0l.1.1`). **`verify` is the orchestrator's** — it reads through `gh api graphql`, which `guard.sh` denies to a subagent.
- Details the tool owns and this section does not restate: the issue conventions (id shape · the `## Acceptance` section · `type:`/`status:` labels), the repo-decision rule, and what happens to a parent or a dependency that falls outside the plan array. They are in that script's header comment.

**Run a migration as the only session on the ledger.** Same discipline as `dolt gc` above, for a different reason: `apply` is writing the same items that another session may be reading, and a half-applied ledger is not a state anyone can judge from — a reviewer looking up acceptance mid-migration gets an item that exists in one backend and not the other, and nothing in the output says which. So: tell the other sessions of this machine (find them through the ledger's `in_progress`·`assignee`·`updated_at`), **put a numeric wait limit in the notice** (`<HH:MM>까지 회신이 없으면 진행합니다`), wait for a reply rather than assuming one, run `plan`→`apply`→`verify` to the end in one sitting, and say afterwards that it is done. Switching `ledger.json`'s `backend` is the last step, not the first — until `verify` passes, the old ledger is still the one to read.

## New clone, new harness, update

- **A new clone of the harness root — make the ledger answer first.** `ledger.json` comes with the clone and its `backend` decides what "restore" means. The per-backend procedure (ledger restore · plugin install at user scope · `core.hooksPath` · target clones through `repo.sh restore`) is owned by `harness:setup` "2. B — Join an existing harness (from a clone)" and is not restated here. Until `ledger.sh list` is rc 0, every skill and gate is powerless.
- **On `beads` the remote is the only ledger backup.** Lose `.beads/embeddeddolt/` and the sprint and judgment history is gone — projections are outside git and cannot restore the ledger. A ledger on one machine only is not a normal state. `github`·`notion` have no local copy to lose.
- **Standing up a new harness**: `harness:setup` "1. A — New harness". The core is never copied into a project — the plugin is installed next to it.
- **Updating a standing harness**: `harness:setup` "3. C — Update" (`claude plugin marketplace update skills` then `claude plugin update harness@skills`, then restart the session). Nothing at the harness root is overwritten by an update. Version and changelog of the core: [development.md](development.md) "Release".
