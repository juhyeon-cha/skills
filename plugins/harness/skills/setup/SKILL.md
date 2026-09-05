---
name: setup
description: Harness install, join, and update procedures. Use when standing up a new harness from a release tarball, when joining a harness that already stands as a new participant, or when updating an existing install from an upstream release. "하네스 세팅해", "하네스 설치해", "하네스 업데이트해".
---

# Harness Setup — Three Entries

This skill holds all three.

- **A. New harness install** — the spot where the release tarball was unpacked becomes the harness (in-place).
- **B. Join an existing harness** — a new participant who uses the standing harness's ledger, `repos.json`, and `rails.json` as they are.
- **C. Update an existing install** — pull it after comparing against the upstream release.

Both the procedure and the verification differ per branch. **Decide the branch first and follow that section only.** Do not mix in commands from another section out of habit — calling A's `init` in C, or C's `update` in B, silently overwrites something different each time.

## 0. Branch decision — first action

```bash
ls -d .harness-state VERSION repos.json rails.json .beads 2>/dev/null
git rev-parse --git-dir >/dev/null 2>&1 && echo "git: yes" || echo "git: no"
bd list -n 1 >/dev/null 2>&1 && echo "ledger: yes" || echo "ledger: no"
```

| Observed | Branch |
|---|---|
| `.harness-state` yes · git no · `repos.json` no | **A** — a release tarball was just unpacked here → section 1 |
| `.harness-state` yes · git yes · `repos.json` yes · ledger no | **B** — a standing harness was cloned → section 2 |
| all of the above (ledger included) | **C** — a harness already in use. Update only → section 3 |
| `VERSION` yes · `.harness-state` no · ledger no | This is a **clone of the harness original** → **B**, follow section 2 as written. Today that is the only path for joining this project (no derived harness has been distributed yet). All five steps of B hold here — the hook files and `.claude/settings.json` are git-tracked so they come with the clone, and `repos.json`·`rails.json` come along too |
| `VERSION` yes · `.harness-state` no · ledger yes | This is the harness **original**, and a tree already in use. Ask the user what they intend to do |
| (common to both `.harness-state`-less rows) | The only thing ruled out is **section 3 (C)** — `check`·`update` must die in the original (the update source becomes itself). Do not call section 1 (A) either: this is not where a tarball was unpacked |

If no row of the table matches, do not guess your way forward — ask in one line. Picking the wrong branch falls toward the side that is expensive to undo (overwriting the core, initializing the ledger).

The second line of `.harness-state` is the **update source** — `# upstream <owner>/<repo>`, not a local path to the original checkout. That is the value C's `check`·`update` read.

## 1. A — New harness install (where the tarball was unpacked)

**The install procedure cannot be delegated wholesale to an implementer subagent.** Ledger initialization (1.6), and the checks after it that require a ledger (`workspace-check` creates a bead for the check — `checks/workspace-check.sh:51`), are blocked with rc=2 by `guard.sh`'s `r_impl_bd`. That rule's own block message says "원장 구조(계층·의존성·상태·라벨)의 변경은 오케스트레이터의 몫이다" — **that is the guardrail working as intended, and a human or an orchestrator session carries out this procedure.**

### 1.1 Confirm where you are

Read the version with `bash scripts/install.sh version` (the VERSION file is not shipped — the source of the version is the `.harness-state` header). Do not start outside the spot where the tarball was unpacked.

### 1.2 Make it a git repository and connect it to your own repo

```bash
git init
git remote add origin <url of the owner's own private repo>
```

- **Creating the repo (`gh repo create`) and pushing are remote writes — do them only after explicit user approval.** Before approval, stop at `git init`: take the remote url from the user and do the `remote add` alone.
- The harness is always a **standalone repo**. Do not plant it inside an existing project.
- Why this order: `init`'s hook wiring only holds inside a git repository. If it is not a repository, `init` prints "여기는 아직 git 저장소가 아니다" to stderr and ends **with no gate**.

### 1.3 Put the core in place

```bash
bash scripts/install.sh init
```

It takes no arguments (give one and it dies — the target is always the tree this script sits in). It does three things: merges hooks and permissions into `.claude/settings.json`, inserts the harness gate block into `.beads/hooks/pre-commit`·`pre-push`, and wires `core.hooksPath`.

At this point `.beads/hooks` does not exist yet, so **only the first of the three (the settings merge) happens** — the two hook insertions skip with "beads 미초기화", and the `core.hooksPath` wiring does not happen either (the wiring call sits inside `merge_git_hook`, after the block insertion, so it is never reached when the hook file is missing). That is normal — 1.6 runs it again and attaches them.

### 1.4 Interview

Follow section 4.

### 1.5 Create the context files

Follow section 5 (`repos.json` · `rails.json` · `sprints.json` · `CLAUDE.md`).

### 1.6 Ledger initialization and gate wiring

1. `bd init --prefix <the prefix decided in section 4>`.
2. **Connect the new ledger to a remote.** What `bd init` creates is **the local DB alone**. Skip this step and the ledger becomes the **sole copy** on this machine — when the machine dies, the issues and the judgment evidence die with it. And **`checks/ledger-check.sh` does not block that state**: a missing remote is a fail-open boundary, so it prints one warning line and returns rc=0 (that file, line 32 and lines 98-102). That is why the loss path is silent.

   Do the three below at once, after the remote repo **actually exists** and push has been approved. If approval has not come, defer all three — wiring without reflecting makes the next `git push` fail at the pre-push gate with rc=1 (row ⓑ below).

   ```bash
   URL=<the repo url attached in 1.2>
   bd dolt remote add origin "git+$URL"                              # the ledger's Dolt remote
   grep -q '^sync\.remote:' .beads/config.yaml \
     || printf '\nsync.remote: "git+%s"\n' "$URL" >> .beads/config.yaml   # the restore source for other machines
   bd dolt push                                                      # first reflection — this is a remote write
   ```

   - The `git+<git url>` form carries the ledger in that git remote's `refs/dolt/data` — no separate Dolt hosting needed.
   - `sync.remote` is **the source another machine restores this ledger from**. Section 2 (B)'s `bd bootstrap` reads that value **first**. Leaving it out does not block joining — `bd help bootstrap`'s auto-detection has a fallback, "if git origin has `refs/dolt/data`, clone from there and wire origin", and finishing the three lines above makes that ref real (that fallback is what 2.1 leans on). The reason to write it anyway is to leave the restore source **explicit in the ledger config rather than inferred from the git remote's state**.
   - The `grep -q` guard above is for re-runs. Appending (`>>`) is not idempotent — run it twice and the `sync.remote` key is duplicated, unlike the `install.sh init` re-run in item 3 below, which is idempotent.
   - Judge success by the **tracking reference**, not by `bd dolt push`'s rc: origin must be in `bd dolt remote list`, and 1.7's `ledger-check` must print "원격 반영 확인됨". **That check does not reflect anything itself** — if it prints "원격 반영 앞서 있음(반영하지 않음 — 쓰기 모드 아님)", run this command once more.

   These are the results `ledger-check` gives for the three ledger wiring states:

   | Ledger state | ledger-check |
   |---|---|
   | ⓐ no remote (right after `bd init`) | **rc 0** · `⚠ 원장에 Dolt 원격이 없다` — the sole local copy passes as is |
   | ⓑ wired but not yet reflected | **rc 1** · `✗ 원장이 원격에 한 번도 반영된 적이 없다` |
   | ⓒ wired + first reflection | **rc 0** · `✓ … 원격 반영 확인됨` — no warning |
3. **Re-run** `bash scripts/install.sh init` — the hook files exist now, so the gate blocks get attached. It is idempotent. Read the `hooksPath:` line of the output with your own eyes. It must say "하네스 블록이 있다"; if it says "없다", the commit gate **does not run**.
4. Noise and permission cleanup: `git config beads.role maintainer` (leave it unset and every bd call spits a warning, dirtying the output an agent has to parse) · `chmod 700 .beads` (bd's recommended permissions).
5. Add these to `.gitignore`: `.claude/worktrees/` · `.claude/ralph-loop.local.md` · `.claude/ralph-cancel` · `.claude/stop-resume.log` · `.claude/stop-resume-cancel*` · `*.harness-bak` · `docs/sprints/` · `docs/backlog/` · `docs/adr/`(the three projections — the ledger is SSOT and the hooks render them locally) · `.beads/interactions.jsonl`(the audit-log sidecar — the history lives in Dolt's events table, but this file grows on every bd call and keeps the tree permanently dirty). **Never gitignore `.harness-state`** — it is the install record, so it has to be committed for later updates to judge drift.

### 1.7 Verification (A) — all measured

| Run | Expected |
|---|---|
| `bd list` | rc 0. If this is blocked, everything after it is meaningless |
| `bash checks/ledger-check.sh` | rc 0. **This call reflects nothing** — a remote write happens only when `LEDGER_CHECK_PUSH=1` turns it on, and the one place that turns it on is the `pre-push` block. **If you did 1.6-2**, the pass phrase is `원격 반영 확인됨`. If `원격 반영 앞서 있음(반영하지 않음 — 쓰기 모드 아님)` appears, the ledger moved further after 1.6-2's `bd dolt push`, so run that command once more (it is a remote write, so it is subject to user approval). **If you deferred 1.6-2 (its "If approval has not come, defer all three"), `건너뜀` is normal** — then write "the ledger exists on this machine only · 1.6-2 must be done after approval" into the **remaining manual items** in item 4 below. `건너뜀` has four causes, told apart by the stderr warning phrase: `원장에 Dolt 원격이 없다`(= 1.6-2 not run) · `dolt 미설치` · `임베디드 원장 없음` · `DB 디렉토리가 N개다`. The last three are not a deferral but **an unreachable judgment** — remove the cause and run it again |
| `bash checks/guardrail-check.sh` | rc 0. If a "no `jq`" warning appeared, **the wiring was not checked** — install `jq` and run it again |
| `bash checks/workspace-check.sh` | rc 0 (it self-verifies with a temporary clone, so it passes even with no registered repo) |
| `bash scripts/board.sh all` | rc 0. Even with no story in the ledger, an empty table `docs/backlog/index.md` comes out — the projections are outside git, so do not commit them |
| `bash checks/board-check.sh` | rc 0. With no sprint yet, the ledger has **0 `sprint:` labels and the registry `{"sprints": {}}` has 0 keys**, so the two-way comparison passes with 0 on both sides. **Even an empty registry needs the `sprints.json` file itself to exist** — without it, rc=1 (section 5 creates it) |
| `bash checks/rules-check.sh` | rc 0 (S12 compares this file's `.gitignore` convention against the real file) |
| `grep -c '^# --- BEGIN HARNESS GATE ---$' "$(git rev-parse --git-path hooks)/pre-commit"` | `1`. If it is 0, the gate does not run |
| `bash scripts/install.sh manifest` · `bash checks/release-check.sh` | **non-zero is normal** — both are original-only and this is a derived install. A 0 here means the discrimination is broken. To actually compare the artifact you received, use the **argument mode** that the rc=1 output points to: `bash checks/release-check.sh <artifact directory>` — it does not call pack, so it runs in a derived install too, and it compares against this tree's CORE list |

Then:

1. Make the first commit. It must include `.harness-state`. Push only on explicit user instruction.
2. **Ask the user to restart the session** (an agent cannot restart its own session). After the restart, confirm that the seven procedure skills load.
3. Confirm that the pre-commit gate **fires**: register in `sprints.json` a sprint the ledger does not have, deliberately, try to commit, watch it get blocked once, and revert. A hook is confirmed by **what it blocked**, not by the fact that it is installed.
4. Report the result: the list of files created, the gate exit codes, and the remaining manual items.

## 2. B — Join an existing harness (from a clone)

**Do not use a release artifact.** The core is already inside the clone (`git clone` brought it) and the version is what this harness's owner decided. What you stand up here is the four things **missing on this machine alone**: the ledger · the target repo clones · `core.hooksPath` · `beads.role`.

`repos.json`·`rails.json`·`sprints.json`·`CLAUDE.md` are inherited. Do not run section 5's creation procedure.

### 2.1 Restore the ledger

```bash
bd bootstrap --dry-run   # look at the plan first
bd bootstrap             # restore from the remote, or from git refs/dolt/data
bd list                  # confirm rc 0
```

If `bd list` is not rc 0, stop here — every step after it is meaningless.

### 2.2 Restore the target repo clones

```bash
scripts/repo.sh restore   # re-clone repos that are registered but have no clone
scripts/repo.sh list      # confirm registration and clone existence together
```

Not a single "클론 없음" may remain in `list`. **Do not call `repo.sh add`** — the registry already exists, and adding a repo is not joining but a separate decision.

### 2.3 Confirm the commit gate fires

The hook files (`.beads/hooks/*`) are committed to the repo, so they come with the clone. What disappears with every clone is **the local setting `core.hooksPath`, and that alone**.

```bash
grep -q '^# --- BEGIN HARNESS GATE ---$' "$(git rev-parse --git-path hooks)/pre-commit" \
  && echo "gate fires" || echo "gate does not run"
```

Do not compare paths by eye — every combination of notation (absolute/relative) and tree kind (main checkout / linked worktree) leaves a falsehood pointing the other way. The only question is **whether the pre-commit git will actually call has the harness block**.

If it does not run: `bash .claude/hooks/ensure-hookspath.sh` (it wires the setting when unset, and when someone else's real hook sits in `.git/hooks` it does not set anything and tells you instead). If it still does not run after you handle what it says, wire it by hand and nothing more: `git config core.hooksPath .beads/hooks`.

**Do not use `scripts/install.sh init` as a fallback.** `init` first compares the record in `.harness-state` against the sha of the real files, and in a clone of a derived harness whose owner fixed the core under explicit instruction and committed it, it dies right there with "릴리스 tarball 을 다시 받아 풀어라". That is the wrong instruction for a joiner — that tree's core is what the owner decided, and drift is the owner's business to hear about, not the joiner's.

### 2.4 Set the bd role

`git config beads.role maintainer` · `chmod 700 .beads`. Without the former, every bd call spits a warning and dirties the output an agent has to parse.

### 2.5 Add your own rail to `rails.json`

**A rail is a person** — one rail per assignee. Joining is precisely the event of one rail being added.

- Take the next number (`r1`·`r2`… in order) as the key and fill in `owner`. `description` is a memo for humans.
- **Do not touch the existing rails' keys or `owner`.** A rail ID goes into document paths as the prefix of a story slug — change it and every past path and external link breaks.
- This is **a file, not the ledger**. Nothing is left in `bd`.
- **The commit/push boundary**: `rails.json` is a repo file, so go as far as a local commit. **Push is a remote reflection, so do it only on explicit user instruction.** But other participants cannot see my rail without a push, so ask in one line right after the commit whether to push now — defer without asking and a story using my `rail:` label trips `board-check` in someone else's tree.

### 2.6 Verification (B) — all measured

| Run | Expected |
|---|---|
| `bd list` | rc 0 (the ledger was restored) |
| `scripts/repo.sh list` | 0 occurrences of "클론 없음" |
| `grep -c '^# --- BEGIN HARNESS GATE ---$' "$(git rev-parse --git-path hooks)/pre-commit"` | `1` |
| `git config beads.role` | `maintainer` |
| `jq -e '.rails["<my rail ID>"].owner' rails.json` | rc 0, my name |
| `bash checks/board-check.sh` | rc 0. Dying here means `rails.json` was edited wrong, or there is a `rail:` label that the registry does not have |
| `bash checks/guardrail-check.sh` | rc 0 |

Then **ask the user to restart the session** — hooks and permissions load at session start. After the restart, confirm that the seven procedure skills load, and confirm the gate fires the same way as item 3 of 1.7.

If this clone has no `.harness-state`, this is the harness **original** — in that case section 3 (update) does not hold.

## 3. C — Update an existing install

For derived installs only (`.harness-state` has to exist). The upstream is the second line of that file, and without it the update fails. `gh` installed and `gh auth login` done are prerequisites — the upstream is a private repo, so there is no other path.

### 3.1 Compare before pulling

```bash
bash scripts/install.sh check
```

It is read-only — it fetches the `*.state` artifact alone and no tarball. Read the three outputs: the current version · the upstream latest · **the drift list** (core files whose local copy differs from their own install record).

### 3.2 Report the difference to the user and get approval

- If the version matches and there is no drift, **it ends here.** There is nothing to pull.
- If there is drift, report that file list as it is. The next `update` pushes those aside into `.harness-bak` and overwrites them with the release copies — they do not vanish silently, but they do not come back either. Keeping those edits means putting them upstream first, and **that is a remote reflection, so it is subject to explicit user instruction**.
- An update is an operation that overwrites the core wholesale. Get the user's confirmation on whether to run it, then proceed.

### 3.3 Pull and update in place

```bash
bash scripts/install.sh update
```

It takes no arguments. It fetches the tarball and **a temporary copy of** install.sh updates this tree (it does not keep executing while overwriting itself). This command's rc is that update's rc.

**Right after the update, look at whether the context files the new core requires exist in this tree.** The target owns the context files, so `update` does not create them — the core alone becomes new while what it reads is missing. Today there are two such files, and **their handling is split** — `sprints.json` holds a value that is not derived from the ledger (whether a sprint is closed), so it is created by hand here, while `docs/backlog/` is rebuilt by a single command and the `board.sh backlog` row of the 3.4 table is its spot. What follows deals with the former only.

```bash
[ -f sprints.json ] || echo "missing — create it as below"
```

If it is missing, create it in the `sprints.json` shape from section 5. **If the ledger already has `sprint:` labels, register every one of those IDs** — `board-check` blocks both a label the registry does not have and a registration the ledger does not have (two-way). This command produces the IDs to register.

```bash
bd list --all --json -n 0 | jq -r '[.[] | (.labels // [])[] | select(startswith("sprint:")) | sub("sprint:";"")] | unique | .[]'
```

A sprint in progress is `active`, one already finished is `closed`. If you do not know which, **do not infer it from the count of closed issues** — ask the user (the mapping table in the session context block, sprint row).

### 3.4 Verification (C) — all measured

`update`'s rc 0 is not evidence that "it was updated". Look again at what actually decides the state.

| Run | Expected |
|---|---|
| `bash scripts/install.sh check` (re-run) | current version == upstream latest · no drift |
| `bash checks/guardrail-check.sh` | rc 0 |
| `bash checks/rules-check.sh` | rc 0 |
| `bash checks/workspace-check.sh` | rc 0 |
| `bash scripts/board.sh all` | rc 0. Even with no story in the ledger, an empty table `docs/backlog/index.md` comes out — the projections are outside git, so do not commit them |
| `bash checks/board-check.sh` | rc 0 |
| `bd list` | rc 0 |
| `find . -name '*.harness-bak'` | Anything found is a core file of mine that got pushed aside. **Do not delete it** — report the list and a `diff` to the user |



Then:

1. Locally commit the updated core files and `.harness-state`. Push only on explicit user instruction.
2. **Ask the user to restart the session** — updated hooks and permissions load at session start.

## 4. Interview (A only)

Ask the user (all at once):

1. **Target repos** — the clone url, the name (omit it and it is taken from the url — it becomes the label `repo:<name>`), and the gate command (a single line run at the repo root that reports success or failure through its exit code). The default branch is auto-detected after cloning, so you need not ask.
2. **The rail scheme** — the list of participants. A rail is a person, so there is one per assignee, and the IDs are numbers growing as `r1`·`r2`.
3. **The work ledger** — the beads issue prefix.

## 5. Creating the context files (A only)

These four are not core but **owned by the target**, so they do not ship with the install. The shapes below are the specification — build them from here rather than from another file. (B inherits all four. Beyond the one entry for its own rail in 2.5, B touches none of them.)

The first three are read directly by tools, so their absence kills those tools with a non-zero exit immediately: without `rails.json`, `board.sh`·`board-check.sh` stop; without `sprints.json`, `board-check.sh`·`board.sh all` stop; without `repos.json`, `workspace.sh` stops. `CLAUDE.md` is not read by any script, but it is the top-level rule set an agent reads first every session — without it, work starts with no discipline.

### `repos.json` — the target repo registry

**Do not build this file by hand.** Running the following for each repo gathered in the interview clones and registers it in one go.

```bash
scripts/repo.sh add <url> --check "<one-line gate command>" --bootstrap "<worktree preparation command>"
# to give it a name different from the url use --name, to pin the default branch use --branch
# on a new machine that has the registry but no clones: scripts/repo.sh restore
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
| `default_branch` | The branching base for worktrees. They are cut from the latest commit of `origin/<this value>` — **without it workspace.sh fails** (required, so that nothing branches off a stale local HEAD). `repo.sh` detects it from `origin/HEAD` or takes it via `--branch` |
| `check` | A single line run at the repo root that reports success or failure through its exit code. implementer runs it last, evaluator re-runs it. Knowledge of the language and build tools lives here and nowhere else. **Register without `--check` and it stays empty and `repo.sh` warns** — until it is filled, that repo cannot run a gate |
| `bootstrap` | A preparation command run once inside a worktree right after it is created (installing dependencies and the like; optional). Without it, a bare worktree can fail the gate for reasons unrelated to the code — `workspace.sh` runs it and returns non-zero on failure |

Confirm the registration result with `scripts/repo.sh list` — it shows registration and clone existence together.

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

If the target already has one, append only the harness sections; if not, write a new one. The skeleton is these four.

- **Status** — the work ledger (beads), the task loop, the orchestration means. The fact that this repo is development-language-neutral and that `repos.json` owns the build and test commands
- **How To Work** — the session context block the harness plugin injects at SessionStart, the order of the seven procedure skills, where the role definitions are, the documents under `docs/`
- **Quick Reference** — `bd ready` · `bd list` · `bd show <id>`, `scripts/repo.sh add|list`, `scripts/board.sh all`, `scripts/workspace.sh <story ID>`
- **절대 금지** — remote reflection only on explicit instruction (**two exceptions**: the ledger reflection tied to `git push`, and the working-branch push and PR creation of a cycle closing with no unresolved decision — from merge onward it is explicit instruction) · no direct edits to a target repo's main checkout · **fixing the core (the harness itself) also only on explicit instruction** · no judging completion by impression. For each item, write **whether a gate enforces it** — where there is none, write "게이트 없음(설득뿐)". The full list of gates, their limits, and how to verify them is held by `docs/guardrails.md`

**Do not drop the core-editing item.** The harness stood up here is a derived install that received a release, and this skeleton is **the only path by which that discipline enters a derived install's `CLAUDE.md`**. Write all three of the following together.

- **What the core is** — the files whose paths are written in the root `.harness-state` (`scripts/install.sh`'s `CORE`). The project context created in this section (`repos.json`·`rails.json`·`sprints.json`·`CLAUDE.md`·`.beads`) is not core but owned by this repo
- **Why explicit instruction is needed** — a core file fixed in a derived install is seen as drift by the next `scripts/install.sh update`, pushed aside into `.harness-bak`, and overwritten with the release copy. It vanishes silently. So **do not do it without explicit user instruction**. Do not write it as an unconditional ban — with instruction it can be done, and even then the same fix has to go up to the original so that the next update does not undo it
- **The gate's reach and what it cannot block** — present (half): `guard.sh`'s `r_core_write` blocks **a subagent's** writes to core files with rc=2 (the discriminator is the existence of `.harness-state`, and the core list is read from that file too). What it cannot block: **the orchestrator session** (a hook cannot see whether the user gave explicit instruction — that half is persuasion alone) · writes through the shell (`sed -i`, redirection) · relative paths · going through a script · a worktree with no `.harness-state`. That `scripts/install.sh update` is not caught is **intended** — an update is the regular path that overwrites the core wholesale

**Improvement ideas go into the ledger, not into code.** On finding a defect in or an improvement for the core, (1) leave it in your own ledger as a backlog issue (make a `-t task -l harness` issue with `bd` — with the raw observation and the reproduction conditions), and (2) report it to the original that the second line of `.harness-state`, `# upstream <owner>/<repo>`, points at — reporting is a remote reflection, so do it **only on explicit user instruction**. The original is what gets fixed, and derived installs receive it with `scripts/install.sh update`. Section 2 of the `retrospective` procedure holds the same path.

Describe what the project is for **only after user confirmation**. Do not fill it in by guessing.
