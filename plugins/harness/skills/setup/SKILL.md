---
name: setup
description: Harness setup, join, and update procedures. Use when standing up a new harness root in an empty directory, when joining a harness that already stands as a new participant, or when bringing the installed plugin up to the marketplace's edition. "하네스 세팅해", "하네스 설치해", "하네스 업데이트해".
---

# Harness Setup — Three Entries

This skill holds all three.

- **A. New harness** — the first participant. There is no ledger yet, so this branch creates one.
- **B. Join an existing harness** — a ledger already stands and this machine is pointed at it. Nothing is created in the ledger.
- **C. Update** — bring the installed plugin up to the marketplace's edition, then check what the new edition needs from the root.

Both the procedure and the verification differ per branch. **Decide the branch first and follow that section only.** Do not mix in commands from another section out of habit — calling A's `init` in B or C silently overwrites something different each time.

A harness root is the clone root — the machine-local directory `~/.harness-workspace`, recognized by the `ledger.json` directly under it (section 0) — holding the context files of section 5 and nothing of the plugin. **It is a plain directory, not a git repo**: nothing under it is committed, pushed, or cloned, and it carries no git hook of its own. That is why B does not start from a clone — every machine builds its own root, and what is shared between machines is the ledger, which is remote by nature on `github`·`notion` and a Dolt remote on `beads`. The plugin (skills · role definitions · hooks · checks · scripts) is installed once per machine at user scope and is never copied into the root — `${CLAUDE_PLUGIN_ROOT}` below is its installed location.

## 0. Branch decision — first action

```bash
ls -d ~/.harness-workspace/ledger.json 2>/dev/null    # the harness root marker — this machine's pointer to a ledger
```

`ledger.json` directly under `~/.harness-workspace` is the marker — the same file `lib/harness-root.sh` uses to recognize a harness root — so that path, not the current directory, decides. When it is absent, nothing on this machine points at a ledger and the second question is whether a ledger already exists elsewhere: **the coordinates of one** (for `github` the `owner` and the Projects v2 `project` number; for `notion` the `database_id`; for `beads` the ledger's remote url) either were handed to you or were not. Ask the user in one line if it was not said.

| Observed | Branch |
|---|---|
| the marker is **absent** · you were **not** handed the coordinates of an existing ledger | You are the first participant. Create the ledger → **A**, section 1 |
| the marker is **absent** · you **were** handed them | A ledger stands; point this machine at it → **B**, section 2 |
| the marker is **present** | This machine already points at a ledger. Update only → **C**, section 3 |

The three observations are mutually exclusive and cover every case: the marker is present or it is not, and when it is not, the coordinates were handed over or they were not.

**A present marker whose backend does not answer is still C, not B.** C's verification (3.3) runs `ledger.sh list` and fails loudly there; the fix is access on this machine (`gh auth`, `NOTION_TOKEN`, the Dolt remote), not a second setup. Re-running A or B over a marker that already exists is the expensive-to-undo direction — that is why the marker alone decides the third row.

## 1. A — New harness

**The procedure cannot be delegated wholesale to an implementer subagent.** Ledger initialization (1.4), and the checks after it that require a ledger (`workspace-check` creates a bead for the check — `${CLAUDE_PLUGIN_ROOT}/checks/workspace-check.sh`), are blocked with rc=2 by `guard.sh`'s `r_impl_bd`. That rule's own block message says "원장 구조(계층·의존성·상태·라벨)의 변경은 오케스트레이터의 몫이다" — **that is the guardrail working as intended, and a human or an orchestrator session carries out this procedure.**

### 1.1 Install the plugin

The harness plugin is installed **once, at user scope** — it is not registered per harness tree or per target clone. Pass no scope: user is the default, and a project or local install writes `enabledPlugins` into the tree it is run in (the harness tree or a target clone) and shows up as a second registration in `~/.claude/plugins/installed_plugins.json`.

```bash
claude plugin marketplace add juhyeon-cha/skills   # once per machine; a no-op if it is already added
claude plugin install harness@skills
```

### 1.2 Interview

Follow section 4.

### 1.3 Create the context files

Follow section 5 (`repos.json` · `rails.json` · `sprints.json` · `ledger.json` · `CLAUDE.md`).

### 1.4 Ledger initialization

The ledger backend is one value — `backend` in `ledger.json` at the harness root (shape in section 5) — and the plugin's `scripts/ledger.sh` reads nothing else to choose it: no file, or a value outside `github`·`beads`·`notion`, and every ledger command dies with rc≠0. **The default for a new harness is `github`.** Backend-specific initialization is the adapter's `init`; setup writes `ledger.json` and calls it, nothing more:

```bash
HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh init   # arguments differ per backend — below
```

**Every `ledger.sh` call in this procedure is prefixed with `HARNESS_ROOT=$PWD` (run from the harness root), and so is every plugin check and script that reads the ledger.** Without the variable, `ledger.sh` asks `lib/harness-root.sh` for the root, and during setup its only other source is not there yet — the clone root's own `ledger.json`, written later by `scripts/repo.sh root` (or already there and naming *another* harness on a machine that carries one — a silent write into someone else's ledger). With `HARNESS_ROOT` set, `ledger.sh` uses it as-is. The prefix is harmless in any backend, so the commands below carry it everywhere.

Follow the one branch that matches `backend`, then continue at "all backends".

#### backend: github (default)

Prerequisites: `gh` installed and `gh auth login` done, with the `project` scope on the token — `gh auth refresh -s project,read:project` (add `-h github.com` when the runner is non-interactive; without it gh dies with `--hostname required`). Create the ledger pointer with `bash ${CLAUDE_PLUGIN_ROOT}/scripts/repo.sh root --backend github --owner <github login>` — it writes `~/.harness-workspace/ledger.json`, the harness root marker. **Do not write that file by hand**: the guard reserves the clone-root layer for `repo.sh`, so a direct write is refused. Then run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh init` (optionally `--title <project name>`). Issues live in the target repos of `repos.json` (a story's `repo:` label picks the repo), so there is no ledger repo to create and no remote wiring — the ledger is remote by nature. `type:*`·`status:*` labels are created on demand. Item 2 below (the Dolt remote) does not apply.

**What `init` makes, and what it deliberately does not.** Two things, and it is idempotent in both — running it again on a root that already has them changes nothing and says so:

| | made by `init` | why |
|---|---|---|
| the Projects v2 | created when `project` is absent, and its number written back into `ledger.json`; when `project` is already there, the number is only verified as readable | it is the ledger's boundary — see the paragraph below |
| an `ITERATION` field named `Sprint` on it | created when the project has no `ITERATION` field; when one is already there, `init` names it and leaves it alone | **this backend's sprints are that field's iterations.** Without it `ledger.sh sprints` dies rc≠0 and no sprint can be registered |
| iterations inside that field | **none** — GitHub adds none of its own either (measured, below) | an iteration's title *is* the sprint ID (`YYYY-SNN`), and people pick it in `plan-sprint`. A placeholder would show up in `sprints` as a sprint that does not exist |

So a freshly initialized root answers `ledger.sh sprints --json` with rc 0 and `[]`, and a stderr line saying the field is there but holds no iterations yet — that is the normal empty state, and it reads differently from the missing-field failure.

**That empty answer was measured against real GitHub, not only against the fixture.** A throwaway Projects v2 got the same `createProjectV2Field(dataType: ITERATION)` call `init` makes: the mutation answered `configuration` `{duration:0, startDay:0, iterations:[], completedIterations:[]}`; reading the field back with a separate `fields(first:100)` query gave the same two empty arrays, so it is not an artifact of the create response; and `ledger.sh sprints --json` on that state gave rc 0, `[]`, and the "iteration 이 하나도 없다" stderr line. The throwaway project was deleted afterwards. This matters because a default configuration shipped by GitHub would make a freshly initialized root register a sprint that does not exist — the very hazard the row above names.

**A harness that was set up before `init` made that field** has the project but no `ITERATION` field, so `sprints` dies rc≠0 naming the field. Re-run `ledger.sh init` on that root: it sees the project already present, creates only the missing field, and touches nothing else.

**The ledger's boundary is membership in that Projects v2, not "the issues of the registered repos".** Reads (`list`·`ready`, and therefore every projection and check built on them) return only the issues that are in the `project`, so a target repo's own issues — bug reports, other people's backlog — stay outside the harness even though they live in a repo the harness reads. That is the point: without the boundary, `triage` would offer somebody else's backlog as harness work. What puts an issue inside is `ledger.sh create`, which adds it to the project as it makes it; an issue made any other way is not in the ledger until someone adds it to the project.

#### backend: notion

Prerequisites: an internal integration token exported as `NOTION_TOKEN` (never written into a tracked file — the adapter reads the environment variable only), and a page shared with that integration. Write `ledger.json` as `{"backend":"notion"}` and run `HARNESS_ROOT=$PWD NOTION_TOKEN=… bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh init --parent-page <that page's id>`: it creates the database with the schema (two requests — the self-relations `Parent`·`Blocked by` cannot go into the create request) and writes `database_id` back into `ledger.json`; with `database_id` already present it only re-applies the schema (idempotent). Item 2 below does not apply.

#### backend: beads

1. Write `ledger.json` as `{"backend":"beads"}` and run `ledger.sh init --prefix <the prefix decided in section 4>` (the `beads` adapter runs bd's own init in that tree).
2. **Connect the new ledger to a remote.** What `ledger.sh init` creates is **the local DB alone**. Skip this step and the ledger becomes the **sole copy** on this machine — when the machine dies, the issues and the judgment evidence die with it. And **`checks/ledger-check.sh` does not block that state**: a missing remote is a fail-open boundary, so it prints one warning line and returns rc=0. That is why the loss path is silent.

   Do the three below at once, after the remote repo **actually exists** and push has been approved. If approval has not come, defer all three — wiring without reflecting makes `ledger-check` fail with rc=1 (row ⓑ below).

   ```bash
   URL=<the url of the private repo that will carry the ledger — asked in the interview (section 4)>
   bd dolt remote add origin "git+$URL"                              # the ledger's Dolt remote
   grep -q '^sync\.remote:' .beads/config.yaml \
     || printf '\nsync.remote: "git+%s"\n' "$URL" >> .beads/config.yaml   # the restore source for other machines
   bd dolt push                                                      # first reflection — this is a remote write
   ```

   - The `git+<git url>` form carries the ledger in that git remote's `refs/dolt/data` — no separate Dolt hosting needed.
   - `sync.remote` is **the source another machine restores this ledger from**. Section 2 (B)'s `ledger.sh bootstrap` reads that value **first**. Leaving it out does not block joining — the bootstrap help (`ledger.sh bootstrap --help`) describes an auto-detection fallback, "if git origin has `refs/dolt/data`, clone from there and wire origin", and finishing the three lines above makes that ref real (that fallback is what 2.1 leans on). The reason to write it anyway is to leave the restore source **explicit in the ledger config rather than inferred from the git remote's state**.
   - The `grep -q` guard above is for re-runs. Appending (`>>`) is not idempotent — run it twice and the `sync.remote` key is duplicated.
   - Judge success by the **tracking reference**, not by `bd dolt push`'s rc: origin must be in `bd dolt remote list`, and 1.5's `ledger-check` must print "원격 반영 확인됨". **That check does not reflect anything itself** — if it prints "원격 반영 앞서 있음(반영하지 않음 — 쓰기 모드 아님)", run this command once more.

   These are the results `ledger-check` gives for the three ledger wiring states:

   | Ledger state | ledger-check |
   |---|---|
   | ⓐ no remote (right after `ledger.sh init`) | **rc 0** · `⚠ 원장에 Dolt 원격이 없다` — the sole local copy passes as is |
   | ⓑ wired but not yet reflected | **rc 1** · `✗ 원장이 원격에 한 번도 반영된 적이 없다` |
   | ⓒ wired + first reflection | **rc 0** · `✓ … 원격 반영 확인됨` — no warning |
3. Noise and permission cleanup: `git config beads.role maintainer` (leave it unset and every ledger call spits a beads warning, dirtying the output an agent has to parse) · `chmod 700 .beads` (bd's recommended permissions).

#### all backends — from here on

4. Confirm the backend answers: `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list` rc 0 (an empty list is the correct output for a new ledger).

That is the end of A's procedure: the plugin is installed (1.1), the context files including `ledger.json` are written (1.3), and the adapter's `init` has run (1.4). **There is nothing to commit and no git hook to wire** — the root is a plain directory (section 0), so it has no `.gitignore` contract, no remote, and no `core.hooksPath`. Gates are run by hand and by the target repos' own cycles, not by hooks under this root; `${CLAUDE_PLUGIN_ROOT}/docs/guardrails.md` holds where each one fires.

### 1.5 Verification (A) — all measured

| Run | Expected |
|---|---|
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list` | rc 0. If this is blocked, everything after it is meaningless |
| `bash ${CLAUDE_PLUGIN_ROOT}/checks/guardrail-check.sh` | rc 0. If a "no `jq`" warning appeared, **the wiring was not checked** — install `jq` and run it again |
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/checks/workspace-check.sh` | rc 0 (it self-verifies with a temporary clone, so it passes even with no registered repo) |
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/board.sh all` | rc 0, and **what it means differs by backend.** On one with its own UI (`github`·`notion`) it draws nothing and says so in one line — the ledger's own screens are the projection. On `beads` it draws, and even with no story an empty table `docs/backlog/index.md` comes out. Either way the output is a machine-local file tree, not something to keep |
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/checks/board-check.sh` | rc 0. With no sprint yet, the ledger has **0 `sprint:` labels and the registry answers 0 entries**, so the two-way comparison passes with 0 on both sides. The registry comes from the adapter, so what it needs differs by backend: on `beads` **even an empty registry needs the `sprints.json` file itself to exist** — without it the adapter fails and this is rc=1 (section 5 creates it); on `github`·`notion` it is derived from the ledger and no registry file is read |
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/checks/rules-check.sh` | rc 0 |
| `jq -e '.plugins["harness@skills"] \| map(.scope) == ["user"]' ~/.claude/plugins/installed_plugins.json` | rc 0 — the plugin is registered at user scope and nowhere else |

#### backend: beads — one more row

| Run | Expected |
|---|---|
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/checks/ledger-check.sh` | rc 0. **This call reflects nothing** — a remote write happens only when `LEDGER_CHECK_PUSH=1` turns it on. **If you did 1.4-2**, the pass phrase is `원격 반영 확인됨`. If `원격 반영 앞서 있음(반영하지 않음 — 쓰기 모드 아님)` appears, the ledger moved further after 1.4-2's `bd dolt push`, so run that command once more (it is a remote write, so it is subject to user approval). **If you deferred 1.4-2 (its "If approval has not come, defer all three"), `건너뜀` is normal** — then write "the ledger exists on this machine only · 1.4-2 must be done after approval" into the **remaining manual items** in item 2 below. `건너뜀` has four causes, told apart by the stderr warning phrase: `원장에 Dolt 원격이 없다`(= 1.4-2 not run) · `dolt 미설치` · `임베디드 원장 없음` · `DB 디렉토리가 N개다`. The last three are not a deferral but **an unreachable judgment** — remove the cause and run it again |

Then:

1. **Ask the user to restart the session** (an agent cannot restart its own session). After the restart, confirm that the `harness:*` procedure skills load.
2. Report the result: the list of files created, the check exit codes, and the remaining manual items. **There is no commit here** — the root is not a git repo, and the target repos were not touched.

## 2. B — Join an existing harness

The ledger already stands and you were handed its coordinates (section 0). **Nothing is cloned and nothing is inherited** — the harness root is a machine-local plain directory, so this machine builds its own, exactly as A does. The one difference from A is the whole point of this branch: **the ledger exists, so `ledger.sh init` is not run.** `ledger.json` is written to point at what is already there.

What you stand up: the plugin · a `ledger.json` pointing at the standing ledger · the target repo clones and their registry · (`beads` only) `beads.role` and the ledger remote. Section 5 owns the shapes of the context files, and B follows it too — with `ledger.json` filled from the coordinates you were handed rather than from an `init`.

### 2.1 Point this machine at the ledger

`ledger.json` is what makes `~/.harness-workspace` a harness root, and it is written by `scripts/repo.sh root`, never by hand. Its `backend` decides the rest. Follow one branch.

#### backend: github

The issues and the Projects v2 live on GitHub, so there is nothing local to restore. Three things:

1. **Write the pointer**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/repo.sh root --backend github --owner <the login you were handed>`, then put the **existing** `project` number into `~/.harness-workspace/ledger.json`. **Do not run `ledger.sh init`.** It is idempotent and would not make a second project while `project` is set, but it writes to the shared ledger's structure (it creates the `ITERATION` field when that is missing), and that belongs to whoever created the ledger. If `sprints` dies naming a missing `ITERATION` field, say so to that person rather than running `init` yourself — 1.4's github branch has the upgrade path.
2. **`gh auth status` rc 0, with the `project` scope on the token** — `gh auth refresh -s project,read:project` if it is missing (1.4 has the same command and the `-h github.com` caveat for a non-interactive runner). The scope is not optional: the ledger's boundary is Projects v2 membership, so reads need it too, not just writes.
3. **`HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list -n 1` rc 0** (the `HARNESS_ROOT` prefix is 1.4's rule). This is the whole join: rc 0 with a row means this machine reads the same ledger as the others.

If that `list` prints 0 rows while the target repos do have issues, `ledger.sh` says so on stderr — the `project` number you wrote is pointing somewhere else. Do not "fix" it by running `init`; ask whoever created the ledger.

#### backend: notion

Nothing to restore either. Write the pointer (`{"backend":"notion","database_id":"<the id you were handed>"}` — through `repo.sh root`, section 5), export `NOTION_TOKEN` on this machine (a token is never written into a file), then `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list -n 1` rc 0 (the `HARNESS_ROOT` prefix is 1.4's rule).

#### backend: beads

```bash
HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh bootstrap --dry-run   # look at the plan first
HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh bootstrap             # restore from the remote, or from git refs/dolt/data
HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list                  # confirm rc 0
```

If that `list` is not rc 0, stop here — every step after it is meaningless.

### 2.2 Install the plugin and stand up the target repo clones

The plugin is installed once at user scope (no scope argument — user is the default; see 1.1 for why). `repo.sh` registers nothing per clone.

```bash
claude plugin marketplace add juhyeon-cha/skills   # once per machine; a no-op if it is already added
claude plugin install harness@skills
```

Then the clones. **The registry is machine-local and nothing brought it here**, so which path applies depends on whether `~/.harness-workspace/repos.json` already exists:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/repo.sh add <url>   # no registry yet — register and clone in one go, per repo (section 5)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/repo.sh restore     # a registry is there but its clones are not (a rebuilt machine)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/repo.sh list        # confirm registration and clone existence together
```

Not a single "클론 없음" may remain in `list`. Which repos to register is a question for whoever runs the harness — a repo that no story targets is not needed here.

### 2.3 Set the beads role (backend: beads only)

`git config beads.role maintainer` · `chmod 700 .beads`. Without the former, every ledger call spits a warning and dirties the output an agent has to parse. With `github`·`notion` there is no `.beads` and nothing to set.

### 2.4 Verification (B) — all measured

| Run | Expected |
|---|---|
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list` | rc 0 (the backend in `ledger.json` answers) |
| `jq -e '.plugins["harness@skills"] \| map(.scope) == ["user"]' ~/.claude/plugins/installed_plugins.json` | rc 0 — user scope and nowhere else |
| `bash ${CLAUDE_PLUGIN_ROOT}/scripts/repo.sh list` | 0 occurrences of "클론 없음" |
| `git config beads.role` (backend: beads only) | `maintainer` |
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/checks/board-check.sh` | rc 0. Dying here means there is a `rail:` or `sprint:` label the registry does not have — on `beads` fix the file (section 5), on `github`·`notion` the registry comes from the ledger and the label is what is wrong |
| `bash ${CLAUDE_PLUGIN_ROOT}/checks/guardrail-check.sh` | rc 0 |

**A rail is a person**, so joining usually means one more rail exists. Where that is recorded is the backend's business, not this procedure's: on `beads` it is a key in the root's own `rails.json` (section 5), and on `github`·`notion` the adapter derives rails from the ledger's own stories, so there is nothing to write until a story carries your `rail:` label. Either way it is machine-local or remote — there is no file to commit or push here.

Then **ask the user to restart the session** — hooks and permissions load at session start. After the restart, confirm that the `harness:*` procedure skills load.

## 3. C — Update

The core is the plugin, so an update touches no file of the root. Two commands; the plugin's `release` skill names the same pair, and `claude plugin update` applies only after a session restart.

```bash
claude plugin marketplace update skills
claude plugin update harness@skills
```

### 3.1 Confirm what was pulled

`jq -r '.plugins["harness@skills"][] | "\(.scope)\t\(.version)"' ~/.claude/plugins/installed_plugins.json` — one `user` line whose version is the marketplace's latest (`claude plugin list` shows the same). Read the new edition's `CHANGELOG.md` entry at `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md` after the restart: a MAJOR entry names the hand work an install has to do (the `release` skill's width table), and that hand work is what 3.2 and 3.3 look for.

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
| `HARNESS_ROOT=$PWD bash ${CLAUDE_PLUGIN_ROOT}/scripts/board.sh all` | rc 0. On a backend with its own UI (`github`·`notion`) it draws nothing and says so in one line; on `beads` it draws, and even with no story an empty table `docs/backlog/index.md` comes out |
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

Run the first command again and confirm the single `user` line. Then look at the file each removed registration lived in — `.claude/settings.json` of the tree for project scope, `.claude/settings.local.json` for local — and make sure `enabledPlugins["harness@skills"]` is gone; if the key is still there, delete it by hand. **When that file is tracked by the tree it lives in — a target repo clone — the change is a diff to commit there.** The harness root is not a git repo, so nothing under it is ever committed.

Then:

1. Commit whatever 3.4 changed in a **target repo's** tracked `settings.json`, locally. Push only on explicit user instruction. What 3.2 created (`sprints.json`) sits in the machine-local root and is not committed anywhere.
2. **Ask the user to restart the session** — the updated plugin, its hooks, and its permissions load at session start.

## 4. Interview (A only)

Ask the user (all at once):

1. **Target repos** — the clone url, the name (omit it and it is taken from the url — it becomes the label `repo:<name>`), and the gate command (a single line run at the repo root that reports success or failure through its exit code). The default branch is auto-detected after cloning, so you need not ask.
2. **The rail scheme** — the list of participants. A rail is a person, so there is one per assignee, and the IDs are numbers growing as `r1`·`r2`.
3. **The work ledger** — the backend (`github` unless the user says otherwise · `beads` · `notion`) and what that backend needs: the GitHub login that owns the Projects v2 for `github`, the issue prefix **and the url of the private repo that will carry the ledger** for `beads`, the id of a page shared with the integration for `notion`.

## 5. Creating the context files (A only)

These five are not part of the plugin but **owned by the root**, so the plugin does not create them. The shapes below are the specification — build them from here rather than from another file. **B builds them too** — nothing is inherited, because the root is machine-local (section 0); B's only difference is that `ledger.json` is filled from the coordinates of a ledger that already exists instead of from `ledger.sh init`.

All five live directly under the clone root (= the harness root, section 0). Two of them are read by tools there, so their absence kills those tools with a non-zero exit immediately: without `repos.json`, `scripts/repo.sh` and `workspace-cleanup.sh` stop; without `ledger.json`, the harness root cannot be recognized at all and every `scripts/ledger.sh` call stops. **`rails.json`·`sprints.json` are backend-dependent** — `board.sh`·`board-check.sh` reach the two registries only through the adapter (`ledger.sh rails`·`sprints`) and open no file of their own. On `beads` the adapter reads exactly these two files, so without `rails.json` `board.sh`·`board-check.sh` stop and without `sprints.json` `board-check.sh`·`board.sh all` stop; on `github`·`notion` the adapter derives both registries from the ledger and neither file is opened. `CLAUDE.md` is not read by any script, but it is the top-level rule set an agent reads first every session — without it, work starts with no discipline.

| File | What it holds |
|---|---|
| `repos.json` | the target repo registry, at `~/.harness-workspace/repos.json` — `scripts/repo.sh add` writes it |
| `rails.json` | the rail registry — one rail per person |
| `sprints.json` | the sprint registry — the only source of whether a sprint is closed |
| `ledger.json` | the ledger backend — `github` (default) · `beads` · `notion` — and what that backend needs to find the ledger. It lives at `~/.harness-workspace/ledger.json` and **being there is what makes that directory the harness root**; `scripts/repo.sh root` writes it |
| `CLAUDE.md` | the top-level rules |

### `ledger.json` — the ledger backend

This file sits directly under the clone root (`~/.harness-workspace/ledger.json`) and is written by `scripts/repo.sh root`, never by hand. One key, `backend`, decides which backend `scripts/ledger.sh` talks to; the rest is what that backend needs. No file, or a value outside the three, and every ledger command dies with rc≠0 — there is no fallback. The default for a new harness is `github`. The three shapes:

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
| `owner` (github) | the Projects v2 owner (a user login). **It also owns the repos the issues live in** — the adapter derives a repo slug as `owner/<the repo: label's name>` |
| `project` (github) | the Projects v2 number. `ledger.sh init` creates the project and writes it; `create` refuses to make an issue without it. **It is also the read boundary** — `list`·`ready` return only the issues in this project, so a wrong number yields 0 rows (with a stderr line saying so), not the repos' issues |
| `database_id` (notion) | the database. `ledger.sh init --parent-page <id>` creates it and writes it. The token is `NOTION_TOKEN` in the environment and never in this file |

`ledger.sh init` writes `project`·`database_id` into this file — the only values a tool writes here.

### `repos.json` — the target repo registry (machine-local, directly under the harness root)

**Do not build this file by hand** — it sits directly under the harness root (`~/.harness-workspace/repos.json`), which the guard reserves for `scripts/repo.sh`. Running the following for each repo gathered in the interview clones and registers it in one go.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/repo.sh add <url> --check "<one-line gate command>" --bootstrap "<worktree preparation command>"
# to give it a name different from the url use --name, to pin the default branch use --branch
# --check/--branch/--bootstrap go into the clone's own .harness.json (below) — commit them to that repo
# on a new machine that has the registry but no clones: repo.sh restore
```

The clone location is fixed at `~/.harness-workspace/<name>` and no path is written into `repos.json` — a path written by hand rots. **The registry holds `name` and `url` and nothing else** — how the harness treats a repo (gate command, default branch, bootstrap) is owned by that repo itself, in its own `.harness.json` (below). The result looks like this.

```json
{
  "doc": "대상 레포 manifest. name: repo:<name> 라벨과 대응. url: 클론 소스. 클론 위치는 ~/.harness-workspace/<name> 으로 고정(scripts/repo.sh 가 관리). 게이트 명령·기본 브랜치·부트스트랩은 여기 없다 — 대상 레포 자신의 .harness.json 이 소유한다.",
  "repos": [
    { "name": "<repo name>", "url": "<clone url>" }
  ]
}
```

| Field | Where it is used |
|---|---|
| `name` | Corresponds to a story's `repo:<name>` label. The clone location (`~/.harness-workspace/<name>`) is derived from it too |
| `url` | The clone source. `repo.sh add` records it, and `repo.sh restore` re-clones from it on a new machine |

Confirm the registration result with `bash ${CLAUDE_PLUGIN_ROOT}/scripts/repo.sh list` — it shows registration and clone existence together.

### `.harness.json` — how the harness treats one target repo

This file lives **at the root of the target repo and is committed there**, not at the harness root. The repo is what knows its own gate command; put it in the harness's registry instead and the person who knows the repo cannot fix it, and two harnesses hold two different values. `repo.sh add` creates it when the clone does not have one yet — **commit it to that repo**; when the clone already has one, `repo.sh` leaves it alone.

```json
{
  "check": "<one-line gate command>",
  "default_branch": "main",
  "bootstrap": "<worktree preparation command (optional — leave the key out when there is none)>"
}
```

| Field | Where it is used |
|---|---|
| `check` | A single line run at the repo root that reports success or failure through its exit code. implementer runs it last, evaluator re-runs it; `repo.sh check <name>` prints it, and **rc≠0 naming the path when the file or the value is missing** — no fallback, because an absent gate must not read as a passing one. Knowledge of the language and build tools lives here and nowhere else |
| `default_branch` | The branching base for worktrees. EnterWorktree cuts them from `origin/<the default branch>` (`worktree.baseRef` default `fresh`). `repo.sh add` records what it detected from `origin/HEAD` or took via `--branch`; `repo.sh restore` does not read it — it re-detects from `origin/HEAD`, since a clone has to exist before this file can be read |
| `bootstrap` | A preparation command run once inside a worktree right after it is created (installing dependencies and the like; optional). Without it, a bare worktree can fail the gate for reasons unrelated to the code — the EnterWorktree hook (`hooks/enter-worktree.sh`) reads it **from the worktree's own copy** and runs it once as the fallback when the target repo has no EnterWorktree hook of its own, reporting failure on stderr |

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
- **Quick Reference** — `ledger.sh ready` · `ledger.sh list` · `ledger.sh show <id>`, `scripts/repo.sh add|list`, `scripts/board.sh all`, `EnterWorktree` · `scripts/workspace-cleanup.sh <story ID>`
- **"절대 금지"** — remote reflection only on explicit instruction (**two exceptions**: the ledger reflection tied to `git push`, and the working-branch push and PR creation of a cycle closing with no unresolved decision — from merge onward it is explicit instruction) · no direct edits to a target repo's main checkout · **fixing the plugin core also only on explicit instruction** · no judging completion by impression. For each item, write **whether a gate enforces it** — where there is none, write "게이트 없음(설득뿐)". The full list of gates, their limits, and how to verify them is held by `${CLAUDE_PLUGIN_ROOT}/docs/guardrails.md`

**Do not drop the core-editing item.** This skeleton is **the only path by which that discipline enters a root's `CLAUDE.md`**. Write all three of the following together.

- **What the core is** — the installed plugin (`${CLAUDE_PLUGIN_ROOT}`: skills · role definitions · hooks · checks · scripts). The project context created in this section (`repos.json`·`rails.json`·`sprints.json`·`ledger.json`·`CLAUDE.md`·`.beads`) is not core but owned by this root
- **Why explicit instruction is needed** — an edit to the installed copy is overwritten by the next plugin update and vanishes silently. The place to fix is the plugin's source, the skills repo `plugins/harness/`, from which a release (the `release` skill) and a plugin update (section 3) carry it to every install. Do not write it as an unconditional ban — with instruction it can be done, and even then the same fix has to go to the source so that the next update does not undo it
- **The gate** — none (persuasion alone). There is nothing for a hook to guard — the loss itself is the consequence

**Improvement ideas go into the ledger, not into code.** On finding a defect in or an improvement for the core, (1) leave it in your own ledger as a backlog issue (make a `-t task -l harness` issue with `ledger.sh create` — with the raw observation and the reproduction conditions), and (2) carry it to the plugin's source — a change there is a PR to the skills repo, so it goes out **only on explicit user instruction**. Section 2 of the `retrospective` procedure holds the same path.

Describe what the project is for **only after user confirmation**. Do not fill it in by guessing.
