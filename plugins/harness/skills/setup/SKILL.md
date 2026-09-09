---
name: setup
description: Harness setup, join, and update procedures. Use when standing up a harness on a repo for the first time, when joining a harness that already stands as a new participant, or when bringing the installed plugin up to the marketplace's edition. "하네스 세팅해", "하네스 설치해", "하네스 업데이트해".
---

# Harness Setup — Three Entries

This skill holds all three.

- **A. New harness** — the first participant. There is no ledger yet, so this branch creates one.
- **B. Join an existing harness** — a ledger already stands and the repo already carries `.harness.json`. Nothing is created in the ledger.
- **C. Update** — bring the installed plugin up to the marketplace's edition.

Both the procedure and the verification differ per branch. **Decide the branch first and follow that section only.** Do not mix in commands from another section out of habit — calling A's `init` in B or C writes to a ledger someone else owns.

**There is no harness directory.** The harness root is the target repo itself, recognized by the `.harness.json` at its root (section 0) — a file that repo owns and commits. The plugin (skills · role definitions · hooks · checks · scripts) is installed once per machine at user scope and is never copied anywhere; `${CLAUDE_PLUGIN_ROOT}` below is its installed location. That is the whole reason **B is two steps**: install the plugin, clone the repo.

## 0. Branch decision — first action

Before installation or verification in any branch, follow `${CLAUDE_PLUGIN_ROOT}/docs/installation.md` for common prerequisites, the selected runtime's installation, and static/loaded/live doctor evidence. Keep runtime installation checks separate from the repository and ledger checks below.

```bash
ls .harness.json          # the harness root marker — run this at the target repo's root
```

`.harness.json` at the repo root is the marker — the same file `lib/harness-root.sh` uses to recognize a harness root. When it is absent, the second question is whether a ledger already exists elsewhere: **the coordinates of one** (for `github` the `owner` and the Projects v2 `project` number; for `notion` the `database_id`; for `beads` the ledger's remote url) either were handed to you or were not. Ask the user in one line if it was not said.

| Observed | Branch |
|---|---|
| the marker is **absent** · you were **not** handed the coordinates of an existing ledger | You are the first participant. Create the ledger → **A**, section 1 |
| the marker is **absent** · you **were** handed them | A ledger stands; write the marker pointing at it → **B**, section 2 |
| the marker is **present** | This repo already points at a ledger. Update only → **C**, section 3 |

The three observations are mutually exclusive and cover every case.

**A present marker whose backend does not answer is still C, not B.** C's verification (3.3) runs `ledger.sh list` and fails loudly there; the fix is access on this machine (`gh auth`, `NOTION_TOKEN`, the Dolt remote), not a second setup.

## 1. A — New harness

**The procedure cannot be delegated wholesale to an implementer subagent.** Ledger initialization (1.3), and the checks after it that require a ledger, are blocked with rc=2 by `guard.sh`'s `r_impl_bd`. That rule's own block message says "원장 구조(계층·의존성·상태·라벨)의 변경은 오케스트레이터의 몫이다" — **that is the guardrail working as intended, and a human or an orchestrator session carries out this procedure.**

### 1.1 Install the plugin

Install through the selected runtime branch in `${CLAUDE_PLUGIN_ROOT}/docs/installation.md`. Finish its static checks before creating repository configuration; loaded/live checks require a new diagnostic session.

### 1.2 Write `.harness.json` and commit it

Follow section 5 for the shape. **This file is the whole setup** — it carries the gate command, the branching base, the optional bootstrap, and the ledger coordinates, and its presence is what makes the repo a harness root. Write it at the repo root of a **worktree** (the guard refuses writes to a main checkout) and commit it there.

Interview first — section 4.

### 1.3 Ledger initialization

The ledger backend is one value — `ledger.backend` in `.harness.json` — and `scripts/ledger.sh` reads nothing else to choose it: no file, or a value outside `github`·`beads`·`notion`, and every ledger command dies with rc≠0. **The default for a new harness is `github`.** Backend-specific initialization is the adapter's `init`; setup writes the file and calls it, nothing more.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh init     # arguments differ per backend — below
```

Run every command of this procedure **from inside the repo**. The finder walks up from the cwd to the first `.harness.json`, so the answer follows where you stand; `HARNESS_ROOT=<repo>` pins it explicitly when you cannot (a subagent, a check fixture).

Follow the one branch that matches `ledger.backend`, then continue at "all backends".

#### backend: github (default)

Prerequisites: `gh` installed and `gh auth login` done, with the `project` scope on the token — `gh auth refresh -s project,read:project` (add `-h github.com` when the runner is non-interactive; without it gh dies with `--hostname required`). Write `.harness.json` with `ledger` = `{"backend": "github", "owner": "<github login>"}`, then run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh init` (optionally `--title <project name>`) — it fills in `ledger.project`. Issues live in the repos a story's `repo:` label names, so there is no ledger repo to create and no remote wiring — the ledger is remote by nature. `type:*`·`status:*` labels are created on demand.

**What `init` makes, and what it deliberately does not.** Two things, and it is idempotent in both — running it again on a repo that already has them changes nothing and says so:

| | made by `init` | why |
|---|---|---|
| the Projects v2 | created when `ledger.project` is absent, and its number written back into `.harness.json`; when it is already there, the number is only verified as readable | it is the ledger's boundary — see the paragraph below |
| an `ITERATION` field named `Sprint` on it | created when the project has no `ITERATION` field; when one is already there, `init` names it and leaves it alone | **this backend's sprints are that field's iterations.** Without it `ledger.sh sprints` dies rc≠0 and no sprint can be registered |
| iterations inside that field | **none** — GitHub adds none of its own either (measured, below) | an iteration's title *is* the sprint ID (`YYYY-SNN`), and people pick it in `plan-sprint`. A placeholder would show up in `sprints` as a sprint that does not exist |

So a freshly initialized repo answers `ledger.sh sprints --json` with rc 0 and `[]`, and a stderr line saying the field is there but holds no iterations yet — that is the normal empty state, and it reads differently from the missing-field failure.

**That empty answer was measured against real GitHub, not only against the fixture.** A throwaway Projects v2 got the same `createProjectV2Field(dataType: ITERATION)` call `init` makes: the mutation answered `configuration` `{duration:0, startDay:0, iterations:[], completedIterations:[]}`; reading the field back with a separate `fields(first:100)` query gave the same two empty arrays, so it is not an artifact of the create response; and `ledger.sh sprints --json` on that state gave rc 0, `[]`, and the "iteration 이 하나도 없다" stderr line. The throwaway project was deleted afterwards. This matters because a default configuration shipped by GitHub would make a freshly initialized repo register a sprint that does not exist — the very hazard the row above names.

**A harness set up before `init` made that field** has the project but no `ITERATION` field, so `sprints` dies rc≠0 naming the field. Re-run `ledger.sh init`: it sees the project already present, creates only the missing field, and touches nothing else.

**The ledger's boundary is membership in that Projects v2, not "the issues of the repos".** Reads (`list`·`ready`, and therefore every projection and check built on them) return only the issues that are in the `project`, so a repo's own issues — bug reports, other people's backlog — stay outside the harness even though they live in a repo the harness reads. That is the point: without the boundary, `triage` would offer somebody else's backlog as harness work. What puts an issue inside is `ledger.sh create`, which adds it to the project as it makes it; an issue made any other way is not in the ledger until someone adds it to the project.

#### backend: notion

Prerequisites: an internal integration token exported as `NOTION_TOKEN` (never written into a tracked file — the adapter reads the environment variable only), and a page shared with that integration. Write `ledger` as `{"backend": "notion"}` and run `NOTION_TOKEN=… bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh init --parent-page <that page's id>`: it creates the database with the schema (two requests — the self-relations `Parent`·`Blocked by` cannot go into the create request) and writes `ledger.database_id` back into `.harness.json`; with that key already present it only re-applies the schema (idempotent).

#### backend: beads

**On this backend the ledger DB lives in the repo** — `LEDGER_ROOT` is the directory that holds `.harness.json`, so `bd`'s `.beads/` and the `rails.json`·`sprints.json` registries (section 5) sit at that repo's root. A harness spanning several repos picks **one** of them as the ledger's home; the others reach it through `bd`'s own `.beads/redirect`, the same file `ledger.sh wire-worktree` writes for worktrees.

1. Write `ledger` as `{"backend": "beads"}` and run `ledger.sh init --prefix <the prefix decided in section 4>` (the `beads` adapter runs bd's own init in that tree). Add `.beads` to that repo's `.git/info/exclude` — the EnterWorktree hook does it for worktrees, but the ledger's home repo needs it too.
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
   - `sync.remote` is **the source another machine restores this ledger from**. Section 2 (B)'s `ledger.sh bootstrap` reads that value **first**. Leaving it out does not block joining — the bootstrap help (`ledger.sh bootstrap --help`) describes an auto-detection fallback, "if git origin has `refs/dolt/data`, clone from there and wire origin", and finishing the three lines above makes that ref real. The reason to write it anyway is to leave the restore source **explicit in the ledger config rather than inferred from the git remote's state**.
   - The `grep -q` guard above is for re-runs. Appending (`>>`) is not idempotent — run it twice and the `sync.remote` key is duplicated.
   - Judge success by the **tracking reference**, not by `bd dolt push`'s rc: origin must be in `bd dolt remote list`, and 1.4's `ledger-check` must print "원격 반영 확인됨". **That check does not reflect anything itself** — if it prints "원격 반영 앞서 있음(반영하지 않음 — 쓰기 모드 아님)", run this command once more.

   These are the results `ledger-check` gives for the three ledger wiring states:

   | Ledger state | ledger-check |
   |---|---|
   | ⓐ no remote (right after `ledger.sh init`) | **rc 0** · `⚠ 원장에 Dolt 원격이 없다` — the sole local copy passes as is |
   | ⓑ wired but not yet reflected | **rc 1** · `✗ 원장이 원격에 한 번도 반영된 적이 없다` |
   | ⓒ wired + first reflection | **rc 0** · `✓ … 원격 반영 확인됨` — no warning |
3. Noise and permission cleanup: `git config beads.role maintainer` (leave it unset and every ledger call spits a beads warning, dirtying the output an agent has to parse) · `chmod 700 .beads` (bd's recommended permissions).

#### all backends — from here on

Confirm the backend answers: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list` rc 0 (an empty list is the correct output for a new ledger).

### 1.4 Verification (A) — all measured

| Run | Expected |
|---|---|
| `bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list` | rc 0. If this is blocked, everything after it is meaningless |
| `bash ${CLAUDE_PLUGIN_ROOT}/checks/guardrail-check.sh` | rc 0. If a "no `jq`" warning appeared, **the wiring was not checked** — install `jq` and run it again |
| `bash ${CLAUDE_PLUGIN_ROOT}/checks/workspace-check.sh` | rc 0 (it self-verifies with a temporary clone) |
| `bash ${CLAUDE_PLUGIN_ROOT}/scripts/board.sh all` | rc 0, and **what it means differs by backend.** On one with its own UI (`github`·`notion`) it draws nothing and says so in one line — the ledger's own screens are the projection. On `beads` it draws, and even with no story an empty table `docs/backlog/index.md` comes out |
| `bash ${CLAUDE_PLUGIN_ROOT}/checks/board-check.sh` | rc 0. With no sprint yet, the ledger has **0 `sprint:` labels and the registry answers 0 entries**, so the two-way comparison passes with 0 on both sides. On `beads` **even an empty registry needs the `sprints.json` file itself to exist** — without it the adapter fails and this is rc=1 (section 5 creates it); on `github`·`notion` it is derived from the ledger and no registry file is read |
| `bash ${CLAUDE_PLUGIN_ROOT}/checks/rules-check.sh` | rc 0 |
| runtime installation and doctor in `docs/installation.md` | inventory and static checks pass; current-session loaded/live are reported separately |

#### backend: beads — one more row

| Run | Expected |
|---|---|
| `bash ${CLAUDE_PLUGIN_ROOT}/checks/ledger-check.sh` | rc 0. **This call reflects nothing** — a remote write happens only when `LEDGER_CHECK_PUSH=1` turns it on. **If you did 1.3-2**, the pass phrase is `원격 반영 확인됨`. If `원격 반영 앞서 있음(반영하지 않음 — 쓰기 모드 아님)` appears, the ledger moved further after 1.3-2's `bd dolt push`, so run that command once more (it is a remote write, so it is subject to user approval). **If you deferred 1.3-2, `건너뜀` is normal** — then write "the ledger exists on this machine only · 1.3-2 must be done after approval" into the remaining manual items. `건너뜀` has four causes, told apart by the stderr warning phrase: `원장에 Dolt 원격이 없다`(= 1.3-2 not run) · `dolt 미설치` · `임베디드 원장 없음` · `DB 디렉토리가 N개다`. The last three are not a deferral but **an unreachable judgment** — remove the cause and run it again |

Then:

1. **Commit `.harness.json`** (and, on `beads`, `rails.json`·`sprints.json`) in the worktree. Push only on explicit user instruction — setup is not a cycle close, so the exception in the session block's "절대 금지" does not apply here.
2. **Ask the user to restart the session** (an agent cannot restart its own session). After the restart, confirm that the `harness:*` procedure skills load.
3. Report the result: the files created, the check exit codes, and the remaining manual items.

## 2. B — Join an existing harness

The ledger already stands. **This is the two-step branch**, and which two depends on one thing: whether the repo already carries `.harness.json`.

### 2.1 The repo already carries it — clone and go

```bash
git clone <url> && cd <the clone>                  # anywhere you like — no fixed location
```

Install through 1.1, then clone. The clone brought the ledger coordinates with it, so `lib/harness-root.sh` recognizes the repo the moment you stand in it. Go to 2.3 for what still needs credentials, then 2.4 to verify.

### 2.2 The repo does not carry it yet — write the marker

Someone stood up the ledger without committing `.harness.json` to this repo (or this is a second repo joining an existing ledger). Write it from the coordinates you were handed, following section 5, in a worktree, and commit it. **Do not run `ledger.sh init`** — the ledger exists, and `init` writes to a structure that belongs to whoever created it (on `github` it creates the `ITERATION` field when that is missing). If `sprints` dies naming a missing `ITERATION` field, say so to that person rather than running `init` yourself; 1.3's github branch has the upgrade path.

### 2.3 Credentials — per backend

- **github** — `gh auth status` rc 0, with the `project` scope on the token (`gh auth refresh -s project,read:project`; 1.3 has the `-h github.com` caveat for a non-interactive runner). The scope is not optional: the ledger's boundary is Projects v2 membership, so reads need it too, not just writes.
- **notion** — export `NOTION_TOKEN` on this machine. A token is never written into a file.
- **beads** — the DB is local, so restore it: `ledger.sh bootstrap --dry-run` to look at the plan, then `ledger.sh bootstrap`. Then `git config beads.role maintainer` (without it every ledger call spits a warning that dirties the output an agent has to parse) and `chmod 700 .beads`.

### 2.4 Verification (B) — all measured

| Run | Expected |
|---|---|
| `bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list` | rc 0, and rows. rc 0 with rows means this machine reads the same ledger as the others |
| runtime installation and doctor in `docs/installation.md` | inventory and static checks pass; current-session loaded/live are reported separately |
| `git config beads.role` (backend: beads only) | `maintainer` |
| `bash ${CLAUDE_PLUGIN_ROOT}/checks/board-check.sh` | rc 0. Dying here means there is a `rail:` or `sprint:` label the registry does not have — on `beads` fix the file (section 5), on `github`·`notion` the registry comes from the ledger and the label is what is wrong |
| `bash ${CLAUDE_PLUGIN_ROOT}/checks/guardrail-check.sh` | rc 0 |

If that `list` prints 0 rows while the repos do have issues, `ledger.sh` says so on stderr — on `github` the `ledger.project` number is pointing somewhere else. Do not "fix" it by running `init`; ask whoever created the ledger.

**A rail is a person**, so joining usually means one more rail exists. Where that is recorded is the backend's business: on `beads` it is a key in `rails.json` (section 5), and on `github`·`notion` the adapter derives rails from the ledger's own stories, so there is nothing to write until a story carries your `rail:` label.

Then **ask the user to restart the session** — hooks and permissions load at session start. After the restart, confirm that the `harness:*` procedure skills load.

## 3. C — Update

The core is the plugin, so an update touches no file of the repo. Before switching artifacts, follow `${CLAUDE_PLUGIN_ROOT}/docs/migration.md` for retained configuration, workspaces, role receipts, state and rollback. Then follow the selected runtime's update and role-projection procedure in `${CLAUDE_PLUGIN_ROOT}/docs/installation.md` and start a new session. A repository-owned preparation-hook migration is a separate repository change.

### 3.1 Confirm what was pulled

Run the runtime inventory and static doctor checks in `docs/installation.md`; matching versions alone cannot establish current-session load. Read the new edition's `CHANGELOG.md` entry at `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md` after the restart: a MAJOR entry names the hand work an install has to do, and that hand work is what 3.2 and 3.3 look for.

### 3.2 What the new edition requires of `.harness.json`

The repo owns that file, so a plugin update does not change it — the plugin becomes new while what it reads is missing. Ask the adapter, not a file:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list -n 1 || echo "the ledger does not answer — the marker's shape may be the new edition's"
bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh sprints --json || echo "the sprint registry does not answer — see below"
```

On `beads`, a missing sprint answer means a missing `sprints.json`; create it in the shape from section 5. **If the ledger already has `sprint:` labels, register every one of those IDs** with `ledger.sh sprint-add <ID>` (the file has to exist first — registering does not create it) — `board-check` blocks both a label the registry does not have and a registration the ledger does not have (two-way). This command produces the IDs to register.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list --all --json -n 0 | jq -r '[.[] | (.labels // [])[] | select(startswith("sprint:")) | sub("sprint:";"")] | unique | .[]'
```

A sprint in progress is `active`, one already finished is `closed`. If you do not know which, **do not infer it from the count of closed issues** — ask the user (the mapping table in the session context block, sprint row).

### 3.3 Verification (C) — all measured

`claude plugin update`'s rc 0 is not evidence that "it was updated". Look again at what actually decides the state.

| Run | Expected |
|---|---|
| the runtime doctor of 3.1 (after the restart) | report static, loaded and live independently; unresolved observations stay UNREACHED |
| `bash ${CLAUDE_PLUGIN_ROOT}/checks/guardrail-check.sh` | rc 0 |
| `bash ${CLAUDE_PLUGIN_ROOT}/checks/rules-check.sh` | rc 0 |
| `bash ${CLAUDE_PLUGIN_ROOT}/checks/workspace-check.sh` | rc 0 |
| `bash ${CLAUDE_PLUGIN_ROOT}/scripts/board.sh all` | rc 0. On a backend with its own UI (`github`·`notion`) it draws nothing and says so in one line; on `beads` it draws |
| `bash ${CLAUDE_PLUGIN_ROOT}/checks/board-check.sh` | rc 0 |
| `bash ${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh list` | rc 0 |

### 3.4 Claude only: move the plugin to user scope — one time only

Installs made before the plugin moved to user scope registered `harness@skills` per tree. Those registrations stay behind after an update and load the same plugin several times over. Look at the scopes first.

```bash
jq -r '.plugins["harness@skills"][] | "\(.scope)\t\(.projectPath // "-")"' ~/.claude/plugins/installed_plugins.json
```

The target state is exactly one line, `user`. If a `user` line is missing, install it: `claude plugin install harness@skills` (no scope argument). Then remove every other line — each one has to be uninstalled from inside the tree it was registered in, at its own scope:

```bash
jq -r '.plugins["harness@skills"][] | select(.scope != "user") | "\(.scope)\t\(.projectPath)"' ~/.claude/plugins/installed_plugins.json \
| while IFS=$'\t' read -r scope dir; do (cd "$dir" && claude plugin uninstall harness@skills --scope "$scope"); done
```

Run the first command again and confirm the single `user` line. Then look at the file each removed registration lived in — `.claude/settings.json` of the tree for project scope, `.claude/settings.local.json` for local — and make sure `enabledPlugins["harness@skills"]` is gone; if the key is still there, delete it by hand. **That file is tracked by the repo it lives in, so the change is a diff to commit there** — in a worktree, not the main checkout.

Then **ask the user to restart the session** — the updated plugin, its hooks, and its permissions load at session start.

## 4. Interview (A only)

Ask the user (all at once):

1. **The gate command** — a single line run at the repo root that reports success or failure through its exit code. The default branch is auto-detected from `origin/HEAD`, so you need not ask.
2. **The rail scheme** — the list of participants. A rail is a person, so there is one per assignee, and the IDs are numbers growing as `r1`·`r2`.
3. **The work ledger** — the backend (`github` unless the user says otherwise · `beads` · `notion`) and what that backend needs: the GitHub login that owns the Projects v2 for `github`, the issue prefix **and the url of the private repo that will carry the ledger** for `beads`, the id of a page shared with the integration for `notion`.
4. **Other repos**, if the work spans more than one. Each of them gets its own `.harness.json` carrying the **same** `ledger` object, and its own clone wherever the person who works on it wants it. There is no registry — a story's `repo:` label names the repo, and the person opens a session in that clone.

## 5. `.harness.json` — the one file a repo owns

This file lives **at the root of the target repo and is committed there**. It holds everything the harness needs to know about that repo, and its presence is the discriminator `lib/harness-root.sh` uses. Write it in a worktree and commit it — the guard refuses writes to a main checkout.

```json
{
  "check": "<one-line gate command>",
  "default_branch": "main",
  "bootstrap": "<worktree preparation command (optional — leave the key out when there is none)>",
  "ledger": { "backend": "github", "owner": "<github login>", "project": 4 }
}
```

| Field | Where it is used |
|---|---|
| `check` | A single line run at the repo root that reports success or failure through its exit code. implementer runs it last, evaluator re-runs it. Knowledge of the language and build tools lives here and nowhere else |
| `default_branch` | The branching base for worktrees. EnterWorktree cuts them from `origin/<the default branch>` (`worktree.baseRef` default `fresh`) |
| `bootstrap` | Repository-owned preparation command, consumed by common workspace `enter`/`prepare`. Strings retain Bash semantics; structured argv runs directly. Success is reused only for matching config and declared inputs. See `${CLAUDE_PLUGIN_ROOT}/docs/workspace.md` for readiness, retry and migration from repository-owned EnterWorktree hooks; a hook or old marker is not preparation evidence |
| `preparation` | Optional `timeout_ms` and explicit relative-file `inputs`; shared by both runtimes. Leave bootstrap absent when no preparation is needed. Before delegation, require workspace `ready` exit 0 and `canDelegate: true` |
| `ledger` | The ledger coordinates. **Every repo of one harness carries the same object** — that is what makes them one harness |

The three `ledger` shapes:

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
| `backend` | picks `scripts/ledger-<backend>.sh`. Required. No file, or a value outside the three, and every ledger command dies with rc≠0 — there is no fallback |
| `owner` (github) | the Projects v2 owner (a user login). **It also owns the repos the issues live in** — the adapter derives a repo slug as `owner/<the repo: label's name>` |
| `project` (github) | the Projects v2 number. `ledger.sh init` creates the project and writes it; `create` refuses to make an issue without it. **It is also the read boundary** — `list`·`ready` return only the issues in this project, so a wrong number yields 0 rows (with a stderr line saying so) |
| `database_id` (notion) | the database. `ledger.sh init --parent-page <id>` creates it and writes it. The token is `NOTION_TOKEN` in the environment and never in this file |

`ledger.sh init` writes `ledger.project`·`ledger.database_id` into this file — the only values a tool writes here. **Commit what it wrote.**

### `rails.json` · `sprints.json` — `beads` only

On `beads` the adapter backs `ledger.sh rails`·`sprints` with two files at the ledger home repo's root (1.3's beads branch). On `github`·`notion` the adapter derives both from the ledger and neither file is read — do not create them there.

```json
{
  "doc": "레일 등록부. 레일은 사람이다 — 담당자 1명당 레일 1개이고, 그 사람이 무엇을 맡는지는 레일이 정하지 않는다. 한 레일이 여러 레포를 넘나들며, 레포 경계는 repo:<이름> 라벨이 표현한다. 키는 rail:<ID> 라벨과 대응하고 r1·r2… 로 늘어난다. 숫자형인 이유는 개명이 없어야 하기 때문이다 — 레일 ID 는 스토리 슬러그의 접두사로 문서 경로에 들어간다. owner: 그 레일의 담당자 1명. board-check 검증의 원본.",
  "rails": { "r1": { "owner": "<담당자>", "description": "<이 사람이 하는 일에 대한 짧은 메모>" } }
}
```

| Field | Where it is used |
|---|---|
| the key (`<rail ID>`) | Corresponds to a story's `rail:<ID>` label. It does not go into document paths — a story directory is the slug |
| `owner` | **Required.** One person per rail. `board.sh` uses it as the `owner` of a document's frontmatter and refuses to render without it |
| `description` | A description for humans. No tool reads it |

**`board-check.sh` rejects a `rail:` label the registry does not have.** When adding a rail, fix this file before the label.

`sprints.json` is **the source of whether a sprint is closed**. A label has no room to carry state, and while this file did not exist there was a case of misjudging "every closed issue is closed, so the sprint is over". A new harness has no sprints, so **build it as an empty registry. That is the correct output** — `board-check.sh` compares the ledger's `sprint:` label set against this key set two ways, so 0 on both sides passes.

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

## 6. `CLAUDE.md` — the repo's top-level rules (A only)

If the repo already has one, append only the harness sections; if not, write a new one. The skeleton is these four.

- **Status** — the work ledger (backend), the task loop, the orchestration means. The fact that the harness is development-language-neutral and that `.harness.json` owns the build and test commands
- **How To Work** — the session context block the harness plugin injects at SessionStart, the order of the procedure skills, where the role definitions are, the documents under the plugin's `docs/`
- **Quick Reference** — `ledger.sh ready` · `ledger.sh list` · `ledger.sh show <id>`, `scripts/board.sh all`, `EnterWorktree` · `scripts/workspace-cleanup.sh <story ID>`
- **"절대 금지"** — remote reflection only on explicit instruction (**two exceptions**: the ledger reflection tied to `git push`, and the working-branch push and PR creation of a cycle closing with no unresolved decision — from merge onward it is explicit instruction) · no direct edits to the main checkout · **fixing the plugin core also only on explicit instruction** · no judging completion by impression. **Do not mark the items with per-item gate notes** — the full list of gates, their limits, and how to verify them is held by `${CLAUDE_PLUGIN_ROOT}/docs/guardrails.md`, and the section points at that file instead of restating it. the skills repo's `tests/harness/doc-rules-check.sh` C6 asserts that pointer is alive before a release

**Do not drop the core-editing item.** This skeleton is **the only path by which that discipline enters a repo's `CLAUDE.md`**. Write all three of the following together.

- **What the core is** — the installed plugin (`${CLAUDE_PLUGIN_ROOT}`: skills · role definitions · hooks · checks · scripts). `.harness.json` is not core but owned by this repo
- **Why explicit instruction is needed** — an edit to the installed copy is overwritten by the next plugin update and vanishes silently. The place to fix is the plugin's source, the skills repo `plugins/harness/`, from which a release and a plugin update (section 3) carry it to every install. Do not write it as an unconditional ban — with instruction it can be done, and even then the same fix has to go to the source so that the next update does not undo it
- **The gate** — none (persuasion alone). There is nothing for a hook to guard — the loss itself is the consequence

**Improvement ideas go into the ledger, not into code.** On finding a defect in or an improvement for the core, (1) leave it in the ledger as a backlog issue (make a `-t task -l harness` issue with `ledger.sh create` — with the raw observation and the reproduction conditions), and (2) carry it to the plugin's source — a change there is a PR to the skills repo, so it goes out **only on explicit user instruction**. Section 2 of the `retrospective` procedure holds the same path.

Describe what the project is for **only after user confirmation**. Do not fill it in by guessing.
