# Operating flow (operations)

> The order one sprint flows through, and what each step calls. Structure: [architecture.md](architecture.md). Enforcement mechanisms: [guardrails.md](guardrails.md).

## 표준 사이클

```
plan-sprint ─→ plan-story ─→ develop ─┬→ verify-code ─→ verify-implement ─→ ledger close
 (compose·label) (decompose·acceptance) │   (reviewer)      (evaluator·close)
                                      └── repeat per milestone (batch condition: develop section 3) ──┘
                                                   ↓ story complete
                                             retrospective
```

- Each step's procedure is the skill of the same name in the `harness@skills` plugin (`harness:<name>`). Skills carry delegation and signal handling; role discipline is carried by the plugin's `agents/` definitions — a delegation message carries only "paths + IDs + task-specific context".
- The completion-flow rules (whoever built it does not grade it, no close without MATCH, …) are owned by `harness:develop` "운영 규율"; the always-on subset is the plugin's session block.

## 새 세션 부트스트랩

**Two places, by what the session does.**

| Session | Open where | Why |
|---|---|---|
| Planning · retrospective (`harness:plan-sprint` · `harness:plan-story` · `harness:retrospective`) | the **harness root** (this repo) | the ledger and the registries are here; nothing is edited in a target repo |
| Development (`harness:develop` and the verify skills it calls) | the **clone root of the target repo** — `~/.harness-workspace/<repo>` | the target repo's own `CLAUDE.md`, rules, skills, and hooks load; `EnterWorktree` makes the story worktree inside that clone. One session per (story, repo) |

What loads automatically in both: the project `CLAUDE.md` of the directory the session opened in, and the plugin's SessionStart block (`hooks/session-context.md` — 절대 금지, ledger location, skills and roles, the hierarchy mapping, and where every other rule is owned). No hook primes a backend tool (`bd prime` on `beads` included). Parallel sessions split work **by story** — two sessions on the same (story, repo) are forbidden. Task claiming is `ledger.sh update <task ID> --claim --actor <value>`; the actor's source and the pickup rule are `harness:develop` section 1.

**Every ledger call in this document is the adapter** — `bash "$(bash scripts/plugin-root.sh)/scripts/ledger.sh" <subcommand>`, abbreviated `ledger.sh …`. Which backend answers is `ledger.json`'s `backend`; where a step only exists for one backend, the backend is named.

1. See ready work with `ledger.sh ready`. A sprint in progress is read from `docs/sprints/<ID>/` (outside git — if missing or stale, `bash "$(bash scripts/plugin-root.sh)/scripts/board.sh" all` at the harness root).
2. Call the skill that fits the work (the cycle above).
3. In a development session, `harness:develop` section 2 enters the worktree; inside it, `lib/harness-root.sh` finds the harness root through the wiring `ledger.sh wire-worktree` left (on `beads`, `.beads/redirect`). Before the worktree exists, the same helper reads `~/.harness-workspace/.harness-root` from the clone root, which `repo.sh` writes. Either way the marker of the root is `ledger.json`.

## 무인 루프

- **Drain permission prompts before an unattended loop.** The worktree is outside the project directory, so the first command there may ask for approval and nobody answers during the loop — run one command in the worktree interactively first, or put the needed allows into `.claude/settings.local.json` of the clone.
- The loop is `/loop` (built into Claude Code) and follows `harness:develop` "장기 실행" — how it relates to the pipeline, how it is broken from inside, and the stop guard's marker for the outside. **Those rules are not restated here** — that section is their single owner, so a copy necessarily diverges.

## 문서는 어디에도 나가지 않는다 — 투영은 git 밖이다

The ledger **rides no branch** — on `beads` it is a single `.gitignore`d DB global across branches and worktrees, and on `github`·`notion` it is not in the tree at all — and `docs/sprints/` · `docs/backlog/` · `docs/adr/` are `.gitignore`d generated files that ride no branch either. What goes to a remote is the ledger (`bd dolt push` on `beads`; nothing to send on the other two, which are remote already), and the receiving side redraws with `board.sh all` from the `post-merge`·`post-checkout` hooks. Whichever tree you look at, its documents are that machine's projection of the ledger — there is no document-mismatch window between branches.

| Artifact | What the commit carries | Endpoint |
|---|---|---|
| **Planning** (sprint composition · story decomposition) | only registry changes (`sprints.json` · `rails.json`) — `plan-sprint` 6 · `plan-story` 7. With no change there is no commit and no PR; only ledger reflection remains | **PR creation** — a person merges |
| **Task close** (`verify-implement` 3) | the code on the development branch. No documents | **PR creation** — a person merges |

**Ledger reflection differs by where the push happens.** At the **harness root**, `git push` runs the `pre-push` hook, which runs the plugin's `ledger-check.sh` in write mode — the ledger goes out with the push (exception one of `CLAUDE.md` "절대 금지"). In a **target repo**, no harness git hook is planted: the orchestrator runs `board-check` and `ledger-check` (read mode) after the commit, pushes the working branch, then runs the backend's ledger reflection as an explicit step (`bd -C <harness root> dolt push` on `beads`), and reads `ledger-check` again to see `확인됨`. The three steps (commit and ledger checks → remote reflection → PR creation), their scope, and failure handling are owned by `harness:develop` "사이클 종결".

## 원격 반영 — 경계는 `CLAUDE.md` "절대 금지" 첫 항목이 단일 소유한다

What goes out without instruction and what needs approval is held by that item's **two exceptions**. The list is not repeated here — a copy would make this file say two things, and a stale copy is what the plugin's `rules-check.sh` R-REM catches.

## 원장 관리 — `dolt gc` 와 pull·push

**This whole section is the `beads` backend's.** It is about the embedded Dolt DB that backend keeps at the harness root; on `github`·`notion` the ledger is somebody else's server and none of it applies. The commands here are `bd`'s own, not adapter subcommands — `ledger.sh` passes `dolt`·`export`·`import`·`bootstrap` straight through on `beads` and exits non-zero on the other two.

**A growing ledger is normal.** Dolt is copy-on-write — every write creates new prolly-tree chunks and materializes intermediate state on disk. Only what is reachable from the commit graph is permanent; the rest is reclaimable. And `bd` **makes a Dolt commit per write** — every `note`·`close`·`create`·`label` is a commit, so ordinary use alone grows it.

### `dolt gc` 가 하는 일과 언제 돌리는가

Removes unreachable chunks. Generational: chunks reachable from a commit move to `oldgen` and are skipped by later gc. Three modes — default (new gen only) · `--shallow` (faster, less thorough) · `--full` (oldgen too). **Start with the default.** `--full` scans more, so its connection-blocking window is longer, and the extra reclaim exists only when oldgen has piled up.

**When — once the journal has bloated.** Most of the reclaim is the `.dolt/noms/vvvv…` journal, so `du -sh .beads/embeddeddolt/<name>/.dolt/noms/vvvv*` around 100M is the trigger — an **arbitrary baseline** taken from an observed 237M, not a measured threshold. In the measurement the journal went 237M → 4.0K and `.dolt` 372M → 239M (−36%). Local queries got faster too, but **one measurement without controlling cache state, so the multiplier is not a baseline** (roughly 1.5–2×). Size figures do not depend on cache, so they stand. Evidence: `harness-5qyb.2.1`.

### 실행 전 — 이 절의 핵심

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

### `bd dolt pull`·`push` 가 느린 것은 고치지 않는다

Seconds, and that is normal. Measured: `bd dolt pull` (nothing to receive) 7.6 s — **split in two, neither of which the harness can touch**: `dolt fetch` directly is 3.7 s (network round trip to the remote) and the remaining 3 s is inside the `bd` wrapper. **That local ledger size is unrelated to transfer volume (incremental) is a judgment, not a measurement** — pull was not re-timed after gc. On that judgment, no further investigation. Evidence: story `harness-5qyb` body ②.

## 새 클론·새 프로젝트 설정

- **A new clone of this repo — make the ledger answer first.** `ledger.json` comes with the clone and its `backend` decides what "restore" means; the full branch-by-branch procedure is `harness:setup` "B — Join an existing harness". On `github` and `notion` there is nothing to restore (the ledger is already remote) and only access has to be granted on this machine. On **`beads`**, `.beads/embeddeddolt/` (ledger data) is gitignored and does not come with the clone, so until it exists every skill and gate is powerless. Order:
  1. `ledger.sh bootstrap` — restores the DB from the remote (`config.yaml`'s `sync.remote`) or git's `refs/dolt/data`. `ledger.sh bootstrap --dry-run` shows what it would do. (`beads` only — the other two backends skip to step 4.)
  2. If the restore fails with `remote at that url contains no Dolt data`, **the ledger has never been pushed.** The machine holding the original DB must `bd dolt push`, which is remote reflection and needs explicit user instruction. Until then this clone cannot run the harness.
  3. Confirm `ledger.sh list` is rc 0. Then confirm `core.hooksPath` points at `.beads/hooks` — the commit gate (`board-check`), the push gate (`ledger-check`), and the projection render hang on it. beads (`bd doctor`) manages it; if it is unset, `git config core.hooksPath .beads/hooks` by hand.
  4. Install the plugin — **once per machine, at user scope**: `claude plugin marketplace add juhyeon-cha/skills` then `claude plugin install harness@skills` (user is the default scope). Neither this root nor any clone registers it, so there is no per-directory step. Confirm with `claude plugin list`. Before the marketplace carries the plugin, load it from a source tree (`claude --plugin-dir <skills clone>/plugins/harness`) and point `HARNESS_PLUGIN_ROOT` at the same directory for the git hooks and `harness.check`.
  5. Draw the projections: `bash "$(bash scripts/plugin-root.sh)/scripts/board.sh" all` — they are outside git. From then on the hooks redraw after every pull and checkout.
  6. Restore the target clones: `bash "$(bash scripts/plugin-root.sh)/scripts/repo.sh" restore` (re-clones from the registry's urls into `~/.harness-workspace/`; `check`·`bootstrap` are still in the registry) — it also writes `~/.harness-workspace/.harness-root`. It writes nothing under a clone's `.claude/`: the user-scope install of step 4 already serves every clone.
- **On `beads` the remote is the only ledger backup.** Lose `.beads/embeddeddolt/` and the sprint and judgment history is gone — projections are outside git and cannot restore the ledger. A ledger on one machine only is not a normal state. `github`·`notion` have no local copy to lose.
- **Standing up a new harness**: create a git repo that will be the harness root, install the plugin if this machine does not have it yet (step 4 — one user-scope install per machine, with no place to install it *to*), and run `harness:setup`, which interviews for the project context (`repos.json` · `rails.json` · `sprints.json` · `ledger.json` · `CLAUDE.md` · the ledger the chosen backend needs). The core is never copied into a project — the plugin is installed next to it.
- **Updating a standing harness**: the core arrives through the marketplace — `claude plugin marketplace update skills` then `claude plugin update harness@skills` (restart the session to apply). Nothing in this repo is overwritten by an update; the project context is this repo's own. Version and changelog of the core: [development.md](development.md) "릴리스".
