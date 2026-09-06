---
name: setup
description: Harness setup, join, and update procedures. Use when standing up a new harness root in an empty directory, when joining a harness that already stands as a new participant, or when bringing the installed plugin up to the marketplace's edition. "하네스 세팅해", "하네스 설치해", "하네스 업데이트해".
---

# Harness Setup — Three Entries

This skill holds all three.

- **A. New harness** — an empty directory becomes the harness root.
- **B. Join an existing harness** — a new participant who uses the standing harness's ledger, `repos.json`, and `rails.json` as they are.
- **C. Update** — bring the installed plugin up to the marketplace's edition, then check what the new edition needs from the root.

Both the procedure and the verification differ per branch. **Decide the branch first and follow that section only.** Do not mix in commands from another section out of habit — calling A's `init` in B or C silently overwrites something different each time.

A harness root is an ordinary git repo holding the context files of section 5 and nothing of the plugin. The plugin (skills · role definitions · hooks · checks · scripts) is installed once per machine at user scope and is never copied into the root — `${CLAUDE_PLUGIN_ROOT}` below is its installed location.

## 0. Branch decision — first action

```bash
ls -d repos.json rails.json sprints.json ledger.json .beads 2>/dev/null
git rev-parse --git-dir >/dev/null 2>&1 && echo "git: yes" || echo "git: no"
HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list -n 1 >/dev/null 2>&1 && echo "ledger: yes" || echo "ledger: no"
```

`HARNESS_ROOT=$PWD` is not optional here — 1.5 says why. "ledger: yes" means the backend named in `ledger.json` answers — for `beads` that is the local Dolt DB, for `github`·`notion` a reachable remote (a `notion` tree needs `NOTION_TOKEN` exported first, or the probe says "no" for a ledger that exists).

| Observed | Branch |
|---|---|
| `ledger.json` no · git no | Nothing stands here yet — an empty directory where a **new harness** is set up → **A**, section 1 |
| `ledger.json` yes · git yes · ledger no | A standing harness was cloned — the root's files came with the clone, and this machine has no ledger access yet → **B**, section 2 |
| `ledger.json` yes · git yes · ledger yes | A harness already in use on this machine. Update only → **C**, section 3 |

The discriminator is `ledger.json` — the same file `lib/harness-root.sh` uses to recognize a harness root.

If no row of the table matches (a `ledger.json` with no git repository, say), do not guess your way forward — ask in one line. Picking the wrong branch falls toward the side that is expensive to undo (initializing a ledger over one that exists).

## 1. A — New harness

**The procedure cannot be delegated wholesale to an implementer subagent.** Ledger initialization (1.5), and the checks after it that require a ledger (`workspace-check` creates a bead for the check — `${CLAUDE_PLUGIN_ROOT}/checks/workspace-check.sh`), are blocked with rc=2 by `guard.sh`'s `r_impl_bd`. That rule's own block message says "원장 구조(계층·의존성·상태·라벨)의 변경은 오케스트레이터의 몫이다" — **that is the guardrail working as intended, and a human or an orchestrator session carries out this procedure.**

### 1.1 Make it a git repository and connect it to your own repo

```bash
git init
git remote add origin <url of the owner's own private repo>
```

- **Creating the repo (`gh repo create`) and pushing are remote writes — do them only after explicit user approval.** Before approval, stop at `git init`: take the remote url from the user and do the `remote add` alone.
- The harness is always a **standalone repo**. Do not plant it inside an existing project.

### 1.2 Install the plugin

The harness plugin is installed **once, at user scope** — it is not registered per harness tree or per target clone. Pass no scope: user is the default, and a project or local install writes `enabledPlugins` into the tree it is run in (the harness tree or a target clone) and shows up as a second registration in `~/.claude/plugins/installed_plugins.json`.

```bash
claude plugin marketplace add juhyeon-cha/skills   # once per machine; a no-op if it is already added
claude plugin install harness@skills
```

### 1.3 Interview

Follow section 4.

### 1.4 Create the context files

Follow section 5 (`repos.json` · `rails.json` · `sprints.json` · `ledger.json` · `CLAUDE.md`).

### 1.5 Ledger initialization

The ledger backend is one value — `backend` in `ledger.json` at the harness root (shape in section 5) — and the plugin's `scripts/ledger.sh` reads nothing else to choose it: no file, or a value outside `github`·`beads`·`notion`, and every ledger command dies with rc≠0. **The default for a new harness is `github`.** Backend-specific initialization is the adapter's `init`; setup writes `ledger.json` and calls it, nothing more:

```bash
HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh init   # arguments differ per backend — below
```

**Every `ledger.sh` call in this procedure is prefixed with `HARNESS_ROOT=$PWD` (run from the harness root), and so is every plugin check and script that reads the ledger.** Without the variable, `ledger.sh` asks `lib/harness-root.sh` for the root, and during setup the two other sources are not there yet — no story worktree wiring, and the clone root's `.harness-root` pointer is written later by `scripts/repo.sh` (or points at *another* harness on a machine that already has one — a silent write into someone else's ledger if that one has a `ledger.json`). With `HARNESS_ROOT` set, `ledger.sh` uses it as-is. The prefix is harmless in any backend, so the commands below carry it everywhere.

Follow the one branch that matches `backend`, then continue at "all backends".

#### backend: github (default)

Prerequisites: `gh` installed and `gh auth login` done, with the `project` scope on the token — `gh auth refresh -s project,read:project` (add `-h github.com` when the runner is non-interactive; without it gh dies with `--hostname required`). Write `ledger.json` as `{"backend":"github","owner":"<github login>"}` and run `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh init` (optionally `--title <project name>`): it creates the Projects v2 that groups the issues of every target repo and writes its `project` number back into `ledger.json` — or, if `project` is already there, verifies the number is readable. Issues live in the target repos of `repos.json` (a story's `repo:` label picks the repo), so there is no ledger repo to create and no remote wiring — the ledger is remote by nature. `type:*`·`status:*` labels are created on demand. Item 2 below (the Dolt remote) does not apply.

**The ledger's boundary is membership in that Projects v2, not "the issues of the registered repos".** Reads (`list`·`ready`, and therefore every projection and check built on them) return only the issues that are in the `project`, so a target repo's own issues — bug reports, other people's backlog — stay outside the harness even though they live in a repo the harness reads. That is the point: without the boundary, `triage` would offer somebody else's backlog as harness work. What puts an issue inside is `ledger.sh create`, which adds it to the project as it makes it; an issue made any other way is not in the ledger until someone adds it to the project.

#### backend: notion

Prerequisites: an internal integration token exported as `NOTION_TOKEN` (never written into a tracked file — the adapter reads the environment variable only), and a page shared with that integration. Write `ledger.json` as `{"backend":"notion"}` and run `HARNESS_ROOT=$PWD NOTION_TOKEN=… bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh init --parent-page <that page's id>`: it creates the database with the schema (two requests — the self-relations `Parent`·`Blocked by` cannot go into the create request) and writes `database_id` back into `ledger.json`; with `database_id` already present it only re-applies the schema (idempotent). Item 2 below does not apply.

#### backend: beads

1. Write `ledger.json` as `{"backend":"beads"}` and run `ledger.sh init --prefix <the prefix decided in section 4>` (the `beads` adapter runs bd's own init in that tree).
2. **Connect the new ledger to a remote.** What `ledger.sh init` creates is **the local DB alone**. Skip this step and the ledger becomes the **sole copy** on this machine — when the machine dies, the issues and the judgment evidence die with it. And **`checks/ledger-check.sh` does not block that state**: a missing remote is a fail-open boundary, so it prints one warning line and returns rc=0. That is why the loss path is silent.

   Do the three below at once, after the remote repo **actually exists** and push has been approved. If approval has not come, defer all three — wiring without reflecting makes `ledger-check` fail with rc=1 (row ⓑ below).

   ```bash
   URL=<the repo url attached in 1.1>
   bd dolt remote add origin "git+$URL"                              # the ledger's Dolt remote
   grep -q '^sync\.remote:' .beads/config.yaml \
     || printf '\nsync.remote: "git+%s"\n' "$URL" >> .beads/config.yaml   # the restore source for other machines
   bd dolt push                                                      # first reflection — this is a remote write
   ```

   - The `git+<git url>` form carries the ledger in that git remote's `refs/dolt/data` — no separate Dolt hosting needed.
   - `sync.remote` is **the source another machine restores this ledger from**. Section 2 (B)'s `ledger.sh bootstrap` reads that value **first**. Leaving it out does not block joining — the bootstrap help (`ledger.sh bootstrap --help`) describes an auto-detection fallback, "if git origin has `refs/dolt/data`, clone from there and wire origin", and finishing the three lines above makes that ref real (that fallback is what 2.1 leans on). The reason to write it anyway is to leave the restore source **explicit in the ledger config rather than inferred from the git remote's state**.
   - The `grep -q` guard above is for re-runs. Appending (`>>`) is not idempotent — run it twice and the `sync.remote` key is duplicated.
   - Judge success by the **tracking reference**, not by `bd dolt push`'s rc: origin must be in `bd dolt remote list`, and 1.6's `ledger-check` must print "원격 반영 확인됨". **That check does not reflect anything itself** — if it prints "원격 반영 앞서 있음(반영하지 않음 — 쓰기 모드 아님)", run this command once more.

   These are the results `ledger-check` gives for the three ledger wiring states:

   | Ledger state | ledger-check |
   |---|---|
   | ⓐ no remote (right after `ledger.sh init`) | **rc 0** · `⚠ 원장에 Dolt 원격이 없다` — the sole local copy passes as is |
   | ⓑ wired but not yet reflected | **rc 1** · `✗ 원장이 원격에 한 번도 반영된 적이 없다` |
   | ⓒ wired + first reflection | **rc 0** · `✓ … 원격 반영 확인됨` — no warning |
3. Noise and permission cleanup: `git config beads.role maintainer` (leave it unset and every ledger call spits a beads warning, dirtying the output an agent has to parse) · `chmod 700 .beads` (bd's recommended permissions).

#### all backends — from here on

4. Confirm the backend answers: `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list` rc 0 (an empty list is the correct output for a new ledger).
5. Add these to `.gitignore`: `.claude/worktrees/` · `docs/sprints/` · `docs/backlog/` · `docs/adr/` (the three projections — the ledger is SSOT and board.sh renders them locally) · `.beads/interactions.jsonl` (the audit-log sidecar — the history lives in Dolt's events table, but this file grows on every ledger call and keeps the tree permanently dirty). **Never gitignore `ledger.json` · `repos.json` · `rails.json` · `sprints.json`** — they are the root's context, and a clone (section 2) inherits them only when they are committed.
6. The plugin plants no git hook, here or in a target repo. Whether this root wires hooks of its own (a `pre-commit` that runs `${CLAUDE_PLUGIN_ROOT}/checks/board-check.sh`, a `pre-push` that runs `${CLAUDE_PLUGIN_ROOT}/checks/ledger-check.sh` in write mode) is the root's decision — when it does, write where they live and how `core.hooksPath` is wired into the root's `CLAUDE.md`, because section 2 reads it there.

### 1.6 Verification (A) — all measured

| Run | Expected |
|---|---|
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list` | rc 0. If this is blocked, everything after it is meaningless |
| `bash ${CLAUDE_PLUGIN_ROOT}/checks/guardrail-check.sh` | rc 0. If a "no `jq`" warning appeared, **the wiring was not checked** — install `jq` and run it again |
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/checks/workspace-check.sh` | rc 0 (it self-verifies with a temporary clone, so it passes even with no registered repo) |
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/board.sh all` | rc 0. Even with no story in the ledger, an empty table `docs/backlog/index.md` comes out — the projections are outside git, so do not commit them |
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/checks/board-check.sh` | rc 0. With no sprint yet, the ledger has **0 `sprint:` labels and the registry `{"sprints": {}}` has 0 keys**, so the two-way comparison passes with 0 on both sides. **Even an empty registry needs the `sprints.json` file itself to exist** — without it, rc=1 (section 5 creates it) |
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/checks/rules-check.sh` | rc 0 (S12 compares this file's `.gitignore` convention against the real file) |
| `jq -e '.plugins["harness@skills"] \| map(.scope) == ["user"]' ~/.claude/plugins/installed_plugins.json` | rc 0 — the plugin is registered at user scope and nowhere else |

#### backend: beads — one more row

| Run | Expected |
|---|---|
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/checks/ledger-check.sh` | rc 0. **This call reflects nothing** — a remote write happens only when `LEDGER_CHECK_PUSH=1` turns it on. **If you did 1.5-2**, the pass phrase is `원격 반영 확인됨`. If `원격 반영 앞서 있음(반영하지 않음 — 쓰기 모드 아님)` appears, the ledger moved further after 1.5-2's `bd dolt push`, so run that command once more (it is a remote write, so it is subject to user approval). **If you deferred 1.5-2 (its "If approval has not come, defer all three"), `건너뜀` is normal** — then write "the ledger exists on this machine only · 1.5-2 must be done after approval" into the **remaining manual items** in item 3 below. `건너뜀` has four causes, told apart by the stderr warning phrase: `원장에 Dolt 원격이 없다`(= 1.5-2 not run) · `dolt 미설치` · `임베디드 원장 없음` · `DB 디렉토리가 N개다`. The last three are not a deferral but **an unreachable judgment** — remove the cause and run it again |

Then:

1. Make the first commit — the context files and `.gitignore`. Push only on explicit user instruction.
2. **Ask the user to restart the session** (an agent cannot restart its own session). After the restart, confirm that the `harness:*` procedure skills load.
3. Report the result: the list of files created, the check exit codes, and the remaining manual items.

## 2. B — Join an existing harness (from a clone)

The root's files came with the clone (`git clone` brought the context files), and the plugin's edition is whatever the marketplace serves — the root carries no copy of it. What you stand up here is what is **missing on this machine alone**: ledger access · the plugin · the target repo clones · (`beads` only) `beads.role` and the remote.

`repos.json`·`rails.json`·`sprints.json`·`ledger.json`·`CLAUDE.md` are inherited. Do not run section 5's creation procedure.

### 2.1 Restore the ledger

`ledger.json` came with the clone; its `backend` decides what "restore" means here. Follow one branch.

#### backend: github

**Nothing to restore** — the issues and the Projects v2 live on GitHub, so there is no local copy to bring back and nothing to write into `ledger.json`. What a second participant actually does is four things:

1. **Clone the harness root** (`git clone <the root's url>` and `cd` into it) — this is what section 2 means by "from a clone", and it is the prerequisite for everything below.
2. **`ledger.json` came with that clone.** `owner` and `project` are already in it — do not run `ledger.sh init`, which would create a *second* Projects v2 and make this machine read a different ledger from everyone else's.
3. **`gh auth status` rc 0, with the `project` scope on the token** — `gh auth refresh -s project,read:project` if it is missing (1.5 has the same command and the `-h github.com` caveat for a non-interactive runner). The scope is not optional: the ledger's boundary is Projects v2 membership, so reads need it too, not just writes.
4. **`HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list -n 1` rc 0** (the `HARNESS_ROOT` prefix is 1.5's rule — the same discriminator gap applies to a clone). This is the whole restore: rc 0 with a row means this machine reads the same ledger as the others.

If that `list` prints 0 rows while the target repos do have issues, `ledger.sh` says so on stderr — the `project` number in the inherited `ledger.json` is pointing somewhere else. Do not "fix" it by running `init`; ask whoever owns the root.

#### backend: notion

Nothing to restore either. Export `NOTION_TOKEN` on this machine (the token never travels in the clone), then `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list -n 1` rc 0 (the `HARNESS_ROOT` prefix is 1.5's rule — the same discriminator gap applies to a clone).

#### backend: beads

```bash
HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh bootstrap --dry-run   # look at the plan first
HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh bootstrap             # restore from the remote, or from git refs/dolt/data
HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list                  # confirm rc 0
```

If that `list` is not rc 0, stop here — every step after it is meaningless.

### 2.2 Install the plugin and restore the target repo clones

The plugin is installed once at user scope (no scope argument — user is the default; see 1.2 for why). `repo.sh` registers nothing per clone.

```bash
claude plugin marketplace add juhyeon-cha/skills   # once per machine; a no-op if it is already added
claude plugin install harness@skills
bash ${CLAUDE_PLUGIN_ROOT}/scripts/repo.sh restore   # re-clone repos that are registered but have no clone
bash ${CLAUDE_PLUGIN_ROOT}/scripts/repo.sh list      # confirm registration and clone existence together
```

Not a single "클론 없음" may remain in `list`. **Do not call `repo.sh add`** — the registry already exists, and adding a repo is not joining but a separate decision.

### 2.3 The root's own git hooks

The plugin plants no git hook. When the root's `CLAUDE.md` names hooks of its own (1.5-6), what a clone loses is **the local setting `core.hooksPath`, and that alone** — wire it by hand as that file says (`git config core.hooksPath <the hooks directory>`), and when someone else's real hook already sits in `.git/hooks`, do not overwrite it; move those hooks under that directory first. Do not compare paths by eye — the only question is **whether the hook git will actually call is the one the root names**: `git rev-parse --git-path hooks` prints the directory git uses.

### 2.4 Set the beads role (backend: beads only)

`git config beads.role maintainer` · `chmod 700 .beads`. Without the former, every ledger call spits a warning and dirties the output an agent has to parse. With `github`·`notion` there is no `.beads` and nothing to set.

### 2.5 Add your own rail to `rails.json`

**A rail is a person** — one rail per assignee. Joining is precisely the event of one rail being added.

- Take the next number (`r1`·`r2`… in order) as the key and fill in `owner`. `description` is a memo for humans.
- **Do not touch the existing rails' keys or `owner`.** A rail ID goes into document paths as the prefix of a story slug — change it and every past path and external link breaks.
- This is **a file, not the ledger**. Nothing is left in the ledger.
- **The commit/push boundary**: `rails.json` is a repo file, so go as far as a local commit. **Push is a remote reflection, so do it only on explicit user instruction.** But other participants cannot see my rail without a push, so ask in one line right after the commit whether to push now — defer without asking and a story using my `rail:` label trips `board-check` in someone else's tree.

### 2.6 Verification (B) — all measured

| Run | Expected |
|---|---|
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list` | rc 0 (the backend in `ledger.json` answers) |
| `jq -e '.plugins["harness@skills"] \| map(.scope) == ["user"]' ~/.claude/plugins/installed_plugins.json` | rc 0 — user scope and nowhere else |
| `bash ${CLAUDE_PLUGIN_ROOT}/scripts/repo.sh list` | 0 occurrences of "클론 없음" |
| `git config beads.role` (backend: beads only) | `maintainer` |
| `jq -e '.rails["<my rail ID>"].owner' rails.json` | rc 0, my name |
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/checks/board-check.sh` | rc 0. Dying here means `rails.json` was edited wrong, or there is a `rail:` label that the registry does not have |
| `bash ${CLAUDE_PLUGIN_ROOT}/checks/guardrail-check.sh` | rc 0 |

Then **ask the user to restart the session** — hooks and permissions load at session start. After the restart, confirm that the `harness:*` procedure skills load.

## 3. C — Update

The core is the plugin, so an update touches no file of the root. Two commands, and `claude plugin update` applies only after a session restart.

```bash
claude plugin marketplace update skills
claude plugin update harness@skills
```

### 3.1 Confirm what was pulled

`jq -r '.plugins["harness@skills"][] | "\(.scope)\t\(.version)"' ~/.claude/plugins/installed_plugins.json` — one `user` line whose version is the marketplace's latest (`claude plugin list` shows the same). Read the new edition's `CHANGELOG.md` entry at `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md` after the restart: a MAJOR entry names the hand work an install has to do, and that hand work is what 3.2 and 3.3 look for.

### 3.2 Context files the new edition requires

The root owns the context files, so a plugin update does not create them — the plugin becomes new while what it reads is missing. Check `sprints.json` first: it holds a value that is not derived from the ledger (whether a sprint is closed), so it is created by hand here, while `docs/backlog/` is rebuilt by a single command and the `board.sh` row of the 3.3 table is its spot.

```bash
[ -f sprints.json ] || echo "missing — create it as below"
```

If it is missing, create it in the `sprints.json` shape from section 5. **If the ledger already has `sprint:` labels, register every one of those IDs** — `board-check` blocks both a label the registry does not have and a registration the ledger does not have (two-way). This command produces the IDs to register.

```bash
HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list --all --json -n 0 | jq -r '[.[] | (.labels // [])[] | select(startswith("sprint:")) | sub("sprint:";"")] | unique | .[]'
```

A sprint in progress is `active`, one already finished is `closed`. If you do not know which, **do not infer it from the count of closed issues** — ask the user (the mapping table in the session context block, sprint row).

### 3.3 Verification (C) — all measured

`claude plugin update`'s rc 0 is not evidence that "it was updated". Look again at what actually decides the state.

| Run | Expected |
|---|---|
| the `jq` of 3.1 (re-run after the restart) | one `user` line · the marketplace's latest version |
| `bash ${CLAUDE_PLUGIN_ROOT}/checks/guardrail-check.sh` | rc 0 |
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/checks/rules-check.sh` | rc 0 |
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/checks/workspace-check.sh` | rc 0 |
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/board.sh all` | rc 0. Even with no story in the ledger, an empty table `docs/backlog/index.md` comes out — the projections are outside git, so do not commit them |
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/checks/board-check.sh` | rc 0 |
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list` | rc 0 |

### 3.4 Move the plugin to user scope — one time only

Installs made before the plugin moved to user scope registered `harness@skills` per tree — at project scope in the harness tree and at local scope in each target clone (an earlier `repo.sh` did the latter). Those registrations stay behind after an update and load the same plugin several times over. Look at the scopes first.

```bash
jq -r '.plugins["harness@skills"][] | "\(.scope)\t\(.projectPath // "-")"' ~/.claude/plugins/installed_plugins.json
```

The target state is exactly one line, `user`. If a `user` line is missing, install it: `claude plugin install harness@skills` (no scope argument). Then remove every other line — each one has to be uninstalled from inside the tree it was registered in, at its own scope:

```bash
jq -r '.plugins["harness@skills"][] | select(.scope != "user") | "\(.scope)\t\(.projectPath)"' ~/.claude/plugins/installed_plugins.json \
| while IFS=$'\t' read -r scope dir; do (cd "$dir" && claude plugin uninstall harness@skills --scope "$scope"); done
```

Run the first command again and confirm the single `user` line. Then look at the file each removed registration lived in — `.claude/settings.json` of the tree for project scope, `.claude/settings.local.json` for local — and make sure `enabledPlugins["harness@skills"]` is gone; if the key is still there, delete it by hand. A change to the harness tree's tracked `settings.json` is a diff to commit.

Then:

1. Locally commit whatever 3.2 created or 3.4 changed (`sprints.json` · `settings.json`). Push only on explicit user instruction.
2. **Ask the user to restart the session** — the updated plugin, its hooks, and its permissions load at session start.

## 4. Interview (A only)

Ask the user (all at once):

1. **Target repos** — the clone url, the name (omit it and it is taken from the url — it becomes the label `repo:<name>`), and the gate command (a single line run at the repo root that reports success or failure through its exit code). The default branch is auto-detected after cloning, so you need not ask.
2. **The rail scheme** — the list of participants. A rail is a person, so there is one per assignee, and the IDs are numbers growing as `r1`·`r2`.
3. **The work ledger** — the backend (`github` unless the user says otherwise · `beads` · `notion`) and what that backend needs: the GitHub login that owns the Projects v2 for `github`, the issue prefix for `beads`, the id of a page shared with the integration for `notion`.

## 5. Creating the context files (A only)

These five are not part of the plugin but **owned by the root**, so the plugin does not create them. The shapes below are the specification — build them from here rather than from another file. (B inherits all five. Beyond the one entry for its own rail in 2.5, B touches none of them.)

The first four are read directly by tools, so their absence kills those tools with a non-zero exit immediately: without `rails.json`, `board.sh`·`board-check.sh` stop; without `sprints.json`, `board-check.sh`·`board.sh all` stop; without `repos.json`, the EnterWorktree hook (`hooks/enter-worktree.sh`) has no bootstrap to fall back on and `workspace-cleanup.sh` stops; without `ledger.json`, every `scripts/ledger.sh` call stops. `CLAUDE.md` is not read by any script, but it is the top-level rule set an agent reads first every session — without it, work starts with no discipline.

| File | What it holds |
|---|---|
| `repos.json` | the target repo registry — `scripts/repo.sh add` writes it |
| `rails.json` | the rail registry — one rail per person |
| `sprints.json` | the sprint registry — the only source of whether a sprint is closed |
| `ledger.json` | the ledger backend — `github` (default) · `beads` · `notion` — and what that backend needs to find the ledger |
| `CLAUDE.md` | the top-level rules |

### `ledger.json` — the ledger backend

One key, `backend`, decides which backend `scripts/ledger.sh` talks to; the rest is what that backend needs. No file, or a value outside the three, and every ledger command dies with rc≠0 — there is no fallback. The default for a new harness is `github`. The three shapes:

```json
{"backend": "github", "owner": "<github login that owns the Projects v2>", "project": 4}
```

```json
{"backend": "notion", "database_id": "<database id>"}
```

```json
{"backend": "beads"}
```

| Field | Where it is used |
|---|---|
| `backend` | picks `scripts/ledger-<backend>.sh`. Required |
| `owner` (github) | the Projects v2 owner (a user login). Issues themselves live in the repos of `repos.json` |
| `project` (github) | the Projects v2 number. `ledger.sh init` creates the project and writes it; `create` refuses to make an issue without it. **It is also the read boundary** — `list`·`ready` return only the issues in this project, so a wrong number yields 0 rows (with a stderr line saying so), not the repos' issues |
| `database_id` (notion) | the database. `ledger.sh init --parent-page <id>` creates it and writes it. The token is `NOTION_TOKEN` in the environment and never in this file |

`ledger.sh init` writes `project`·`database_id` into this file — the only values a tool writes here.

### `repos.json` — the target repo registry

**Do not build this file by hand.** Running the following for each repo gathered in the interview clones and registers it in one go.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/repo.sh add <url> --check "<one-line gate command>" --bootstrap "<worktree preparation command>"
# to give it a name different from the url use --name, to pin the default branch use --branch
# on a new machine that has the registry but no clones: repo.sh restore
```

The clone location is fixed at `~/.harness-workspace/<name>` and no path is written into `repos.json` — a path written by hand rots. The result looks like this.

```json
{
  "doc": "대상 레포 manifest. name: repo:<name> 라벨과 대응. url: 클론 소스. 클론 위치는 ~/.harness-workspace/<name> 으로 고정(scripts/repo.sh 가 관리). check: 레포가 소유한 게이트 명령(레포 루트 기준) — 하네스는 종료 코드만 본다. bootstrap: 워크트리 생성 직후 그 안에서 1회 실행할 준비 명령(의존성 설치 등, 선택). 언어·빌드 도구 정보는 이 파일에만 둔다.",
  "repos": [
    {
      "name": "<repo name>",
      "url": "<clone url>",
      "default_branch": "main",
      "check": "<one-line gate command>",
      "bootstrap": "<worktree preparation command (optional)>"
    }
  ]
}
```

| Field | Where it is used |
|---|---|
| `name` | Corresponds to a story's `repo:<name>` label. The clone location (`~/.harness-workspace/<name>`) is derived from it too |
| `url` | The clone source. `repo.sh add` records it |
| `default_branch` | The branching base for worktrees. EnterWorktree cuts them from `origin/<the default branch>` (`worktree.baseRef` default `fresh`); this field is what `repo.sh` records and `rules-check` R18 requires. `repo.sh` detects it from `origin/HEAD` or takes it via `--branch` |
| `check` | A single line run at the repo root that reports success or failure through its exit code. implementer runs it last, evaluator re-runs it. Knowledge of the language and build tools lives here and nowhere else. **Register without `--check` and it stays empty and `repo.sh` warns** — until it is filled, that repo cannot run a gate |
| `bootstrap` | A preparation command run once inside a worktree right after it is created (installing dependencies and the like; optional). Without it, a bare worktree can fail the gate for reasons unrelated to the code — the EnterWorktree hook (`hooks/enter-worktree.sh`) runs it once as the fallback when the target repo has no EnterWorktree hook of its own, and reports failure on stderr |

Confirm the registration result with `bash ${CLAUDE_PLUGIN_ROOT}/scripts/repo.sh list` — it shows registration and clone existence together.

### `rails.json` — the rail registry

```json
{
  "doc": "레일 등록부. 레일은 사람이다 — 담당자 1명당 레일 1개이고, 그 사람이 무엇을 맡는지는 레일이 정하지 않는다. 한 레일이 여러 레포를 넘나들며, 레포 경계는 repo:<이름> 라벨이 표현한다. 키는 rail:<ID> 라벨과 대응하고 r1·r2… 로 늘어난다. 숫자형인 이유는 개명이 없어야 하기 때문이다 — 레일 ID 는 스토리 슬러그의 접두사로 문서 경로에 들어간다. owner: 그 레일의 담당자 1명. board-check 검증의 원본.",
  "rails": {
    "r1": {
      "owner": "<담당자>",
      "description": "<이 사람이 하는 일에 대한 짧은 메모>"
    }
  }
}
```

| Field | Where it is used |
|---|---|
| the key (`<rail ID>`) | Corresponds to a story's `rail:<ID>` label. It does not go into document paths — a story directory is the slug |
| `owner` | **Required.** One person per rail. `board.sh` uses it as the `owner` of a document's frontmatter and refuses to render without it |
| `description` | A description for humans. No tool reads it |

**`board-check.sh` rejects a `rail:` label the registry does not have.** When adding a rail, fix this file before the label.

### `sprints.json` — the sprint registry

This is **the source of whether a sprint is closed**. A label has no room to carry state, and while this file did not exist there was a case of misjudging "every closed issue is closed, so the sprint is over".

A new harness has no sprints, so **build it as an empty registry. That is the correct output** — `board-check.sh` compares the ledger's `sprint:` label set against this key set two ways, so 0 on both sides passes. Do not stuff in a sprint ID that does not exist to make it pass — this time the phantom-registration direction blocks you.

```json
{
  "doc": "스프린트 등록부. 키는 sprint:<ID> 라벨과 대응하고 형식은 YYYY-SNN. status 는 active(진행 중) 또는 closed(회고까지 끝나 마감된 것) 둘뿐이다. 스프린트 종료 여부의 유일한 원본이 이 값이다 — 닫힌 이슈 개수로 판정하지 않는다. board-check 가 원장의 sprint:* 라벨 집합과 이 키 집합을 양방향으로 대조한다.",
  "sprints": {}
}
```

| Field | Where it is used |
|---|---|
| the key (`<sprint ID>`) | Corresponds to a story's `sprint:<ID>` label. The format is `YYYY-SNN` |
| `status` | **Required.** `active`·`closed` and nothing else — `board-check.sh` rejects any other value |

Writing this file while opening and closing sprints is the `plan-sprint` procedure.

### `CLAUDE.md` — the top-level rules

If the root already has one, append only the harness sections; if not, write a new one. The skeleton is these four.

- **Status** — the work ledger (backend), the task loop, the orchestration means. The fact that this repo is development-language-neutral and that `repos.json` owns the build and test commands
- **How To Work** — the session context block the harness plugin injects at SessionStart, the order of the procedure skills, where the role definitions are, the documents under the plugin's `docs/`
- **Quick Reference** — `ledger.sh ready` · `ledger.sh list` · `ledger.sh show <id>`, `scripts/repo.sh add|list`, `scripts/board.sh all`, `EnterWorktree` (name = story ID) · `scripts/workspace-cleanup.sh <story ID>`; the root's own git hooks when it has them (1.5-6)
- **"절대 금지"** — remote reflection only on explicit instruction (**two exceptions**: the ledger reflection tied to `git push`, and the working-branch push and PR creation of a cycle closing with no unresolved decision — from merge onward it is explicit instruction) · no direct edits to a target repo's main checkout · **fixing the plugin core also only on explicit instruction** · no judging completion by impression. For each item, write **whether a gate enforces it** — where there is none, write "게이트 없음(설득뿐)". The full list of gates, their limits, and how to verify them is held by `${CLAUDE_PLUGIN_ROOT}/docs/guardrails.md`

**Do not drop the core-editing item.** This skeleton is **the only path by which that discipline enters a root's `CLAUDE.md`**. Write all three of the following together.

- **What the core is** — the installed plugin (`${CLAUDE_PLUGIN_ROOT}`: skills · role definitions · hooks · checks · scripts). The project context created in this section (`repos.json`·`rails.json`·`sprints.json`·`ledger.json`·`CLAUDE.md`·`.beads`) is not core but owned by this root
- **Why explicit instruction is needed** — an edit to the installed copy is overwritten by the next plugin update and vanishes silently. The place to fix is the plugin's source, the skills repo `plugins/harness/`, from which a release and a plugin update (section 3) carry it to every install. Do not write it as an unconditional ban — with instruction it can be done, and even then the same fix has to go to the source so that the next update does not undo it
- **The gate** — none (persuasion alone). There is nothing for a hook to guard — the loss itself is the consequence

**Improvement ideas go into the ledger, not into code.** On finding a defect in or an improvement for the core, (1) leave it in your own ledger as a backlog issue (make a `-t task -l harness` issue with `ledger.sh create` — with the raw observation and the reproduction conditions), and (2) carry it to the plugin's source — a change there is a PR to the skills repo, so it goes out **only on explicit user instruction**. Section 2 of the `retrospective` procedure holds the same path.

Describe what the project is for **only after user confirmation**. Do not fill it in by guessing.
