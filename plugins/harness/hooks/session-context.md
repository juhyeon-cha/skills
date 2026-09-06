# Harness session context

The always-on block the harness plugin injects at SessionStart. A rule that is not here is held by the skill that uses it — the table at the bottom.

## 절대 금지

A gate does not weaken a prohibition — every gate can be bypassed, and "cannot block" is not "allowed". The full list of enforcement mechanisms and their limits is `${CLAUDE_PLUGIN_ROOT}/docs/guardrails.md`.

- **Remote reflection only on explicit user instruction** — merge · tag push · release publication · GitHub issue changes · remote configuration changes · direct push to a default branch · a remote not registered in `repos.json` · `bd dolt push`. The two exceptions are user decisions.
  - Exception one — ledger reflection tied to a target-repo push is automatic. A hand-typed push is itself the explicit instruction, and the working-branch push of cycle-close stage 2 is the same approval — inside that approval the orchestrator runs `bd dolt push` as an explicit stage (no harness git hook is planted in a target repo, so no pre-push does it instead). The procedure is `harness:develop` "사이클 종결".
  - Exception two — the working-branch push and PR creation of a cycle close are automatic **only when no decision is unresolved**. Scope: repos registered in `repos.json` — registration is the approval surface.

    | State at the end of the cycle | Working-branch push · PR creation |
    |---|---|
    | No decision-needed item came up | **Do it** (without instruction) |
    | One came up and the user instructed or approved | **Do it** |
    | One came up and there is no user instruction or approval | **Do not** |

    Even when the table says "do it", **a target repo's own push·PR rules come first.** An unresolved decision = a task whose human-wait signal came up and which the human has not yet decided + a task whose `status` is `blocked`. The signal list is `harness:develop` "사람 대기"; the stages and failure handling are the same skill's "사이클 종결".
- **Never modify a target repo's main checkout (`~/.harness-workspace/<repo>` itself) directly** — work only in its `.claude/worktrees/<story-id>/` worktree.
- **Never improve the plugin core (skills · roles · hooks) in the installed copy without explicit user instruction** — the place to fix is the skills repo `plugins/harness/`, and the installed copy receives it through a marketplace update. The project context (`repos.json`·`rails.json`·`sprints.json`·`CLAUDE.md`·`.beads`) is owned by the harness root.
- **Never judge completion by impression** — the only evidence is gate exit codes and the acceptance comparison. Whoever built it does not grade it.

## Ledger

- The ledger is reached only through the adapter `${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh` — every `ledger.sh …` in this block and in the skill bodies is that path. Subcommands, arguments, and JSON keys are `bd`'s (`ledger.sh --help`). One value picks the backend, `backend` in the harness root's `ledger.json` (`github`·`beads`·`notion`); no file, or a value outside the three, is rc≠0 — no fallback.
- Harness root discovery goes `HARNESS_ROOT` → the worktree's `.beads/redirect` (beads wiring) → the root pointer under `~/.harness-workspace/` (written by `scripts/repo.sh`), and the discriminator is the `ledger.json` at that spot. The finder lives in the plugin's `lib/` — `harness:develop` section 1.
- When delegating to a subagent, give the harness root absolute path on the first line, and the subagent calls only `HARNESS_ROOT=<harness root> ledger.sh …` — a call without the variable can reach another harness's ledger through root discovery.
- The ledger is the SSOT. `docs/sprints/`·`docs/backlog/`·`docs/adr/` are projections of `scripts/board.sh all`, so they are never edited by hand.
- Bodies (note·description·acceptance·close reason) are passed through file options, never inside a shell command string — the form is `harness:develop` "원장에 본문을 넘기는 형태".

## Procedure skills (10)

`harness:plan-sprint` (sprint composition) → `harness:plan-story` (breakdown · acceptance) → `harness:develop` (implementation cycle — owner of the operating rules) → `harness:verify-code` (review) → `harness:verify-implement` (judgment · close) → `harness:retrospective` (retrospective) + `harness:setup` (first-time setup) · `harness:triage` (backlog triage) · `harness:status` (status, read-only) · `harness:release` (plugin release).

Role definitions (3 — subagents, the Agent tool's `subagent_type`): `harness:implementer` · `harness:reviewer` · `harness:evaluator`.

## Agile hierarchy ↔ ledger mapping

| Level | Ledger form | Convention |
|---|---|---|
| Sprint | label `sprint:<ID>` | ID format `YYYY-SNN`. Dates go on each story bead's `--due`. **The source of the status (`active`/`closed`) is the root `sprints.json`** — closure is never judged from the count of closed issues. `board-check` sees that the registry and the labels match both ways |
| Rail | label `rail:<ID>` | **A person.** One rail per assignee; one rail crosses several repos. Repo boundaries are `repo:` labels. **Only IDs registered in the root `rails.json`**, in the numbered form `r1`·`r2`. Child issues inherit it |
| Story | `--type epic` | Names the repos involved with `repo:<name>` labels (several allowed). Carries a mandatory `slug:<rail ID>-<name>` label that becomes its documentation directory name — the rail-ID prefix keeps different people's slugs from colliding. Uniqueness is required within a sprint, and the renderer asserts it |
| Milestone | `--type feature --parent <story ID>` | A stage inside a story. Order goes through `blocks` dependencies |
| Task | `--type task --parent <milestone ID>` | The unit of execution. `--acceptance` is mandatory. **Exactly one `repo:` label** — when inheritance hands it several, plan-story keeps only the one it actually touches (`ledger.sh label remove`). With several, develop refuses to start |

Creation forms:

```bash
ledger.sh create "<story title>" -t epic -l sprint:<sprint ID>,rail:<rail ID>,slug:<rail ID>-<slug>,repo:<repo>[,repo:<repo>]
ledger.sh create "<milestone title>" -t feature --parent <story ID>
ledger.sh create "<task title>" -t task --parent <milestone ID> --acceptance "<machine-judgeable completion criterion>"
```

## Rules owned elsewhere

Rules kept out of the always-on block. Each is needed only while running its procedure, so its owner holds it — the wording is not repeated here.

| Rule | Owner |
|---|---|
| "운영 규율" · "원장에 본문을 넘기는 형태" · "상태 주장의 근거" · "결정 상태" · "진단 가설 규율" · "사람 대기" · "대상 레포의 관례" · "사이클 종결" · "멀티 레포" | `harness:develop` (sections of the same titles) |
| "위임 메시지의 환경 스냅샷" · "장기 실행" | `harness:develop` |
| "여러 개를 한 번에 등재할 때 — id 를 예측하지 않는다" | `harness:plan-story` |
| "재시도 카운터" | `harness:verify-code` |
| "Checking that a check is alive" | `${CLAUDE_PLUGIN_ROOT}/docs/development.md` |
