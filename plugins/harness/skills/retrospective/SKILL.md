---
name: retrospective
description: Retrospective procedure after a story or a sprint closes. Sweeps the execution feedback piled up in ledger notes and the subagent transcript aggregate (checks/transcript-check.sh) into proposed edits to the skills, role definitions, and session context block the harness plugin holds (`${CLAUDE_PLUGIN_ROOT}` — the source is the skills repo `plugins/harness/`). Use on "회고", "레트로", or "이번 스토리에서 배운 것 반영해줘", and right after a story is finished.
---

# Retrospective

## 1. Gather the material

There are two inputs — **the ledger (notes)** and **the subagent transcripts**. A note holds what a role decided to write down; a transcript holds what the role actually did. Neither stands in for the other.

### 1-1. The ledger

- Read the full `ledger.sh show <ID>` of the target story (or stories) and the notes of every task under it.
- Check what this round left in the harness backlog with `ledger.sh list -l harness`.
- In each note, separate **observation** (what actually happened) from **proposal** (what to change) and pull both out.

### 1-2. Subagent transcripts

- **Path**: `~/.claude/projects/<project directory>/<session UUID>/subagents/agent-*.jsonl`. **This round's session UUID is the last UUID in the scratchpad path the system prompt gives** — pass that to the call below.
- **`checks/transcript-check.sh` is the one place that reads them.** The retrospective **only calls it** — this skill parses no transcript itself. Two parsers make the aggregate diverge.
- **Call**: `bash checks/transcript-check.sh --since <story start time> --session <session UUID> --json`. `--since` takes ISO8601 or `Nd` / `Nh` — cut the window at the Started of `ledger.sh show <story ID>`. rc is 0 no violations / 1 violations found / 2 judgment unreached.
- **The two are independent axes, so pass both.** `--session` alone leaves a session that ran several stories undivided by round, and `--since` alone mixes in other sessions from the same window — their intersection is this story's this round. **When the session UUID is unknown** (an inherited session, someone else's story), drop `--session`, run it, write that fact into the aggregate quotation, and screen attribution with the fallback in section 3.
- **Aggregate — quote the four JSON keys verbatim.**
  - `signals.<role>`: SIGNAL counts per role. The reviewer rejection rate is `CHANGES_REQUESTED / (CHANGES_REQUESTED + LGTM)`, the evaluator's is `VIOLATION / (MATCH + VIOLATION)`.
  - `tools.<role>`: tool-call distribution — `calls_per_response` · `parallel_responses` · `max_per_response` · `top`. Compliance with the parallel-call discipline comes out here.
  - `reuse`: instance reuse — the count and the combinations of transcripts holding two or more SIGNALs. `CHANGES_REQUESTED,LGTM` in one transcript means the same instance carried the re-review.
  - `a9.verdicts`: violation count for the first-line `SIGNAL:` discipline in role responses.
- **What lives in the transcripts and not in the notes** — at least two come only from this side: ① **the tool-call distribution** (which role fires how many calls in parallel per response, and what it uses — nobody writes that into a note) ② **the role signal counts** (how many times the evaluator rejected — `close_reason` keeps the final MATCH alone).
- **Quote ratios rather than totals.** The directory is live, so totals grow every session. Everything from the transcripts is **observation** — proposals live elsewhere.
- **The failure path is recorded as unmeasured, and stays recorded.** On rc=2 (no transcript directory · 0 delegations completed in the window · no python3), put the `UNREACHED:` lines from stderr (the `unreached` array in JSON) verbatim on the story bead with `ledger.sh note` — "전사 미실측: <UNREACHED 원문>". Then proceed on the ledger alone, and treat the transcript-only items (rejection rate · parallel rate · reuse) as **unmeasured** rather than "no observation" — they enter the 2-observation count in section 3 as nothing at all, not as 0.

## 2. Three-way sort

| Branch | Where it goes | Criterion |
|---|---|---|
| Personal preference | User memory | What holds for this user alone |
| Immediate fix | Edit the harness file directly | Typos and dead links only — fixes that **leave behavior unchanged**. A behavior change in a rule, a role, or a skill goes through the approval path in section 5, even when a measurement pinned the defect down |
| Rule candidate | The promotion screen in section 3 | A general rule about how work gets done |

Skipping the sort promotes personal taste into a rule and turns the harness into a pile of documents.

**In a derived harness, "edit the harness file directly" needs an explicit user instruction the moment it touches the core.** A `.harness-state` at the root marks this tree as a derivative built from a release, and the files whose paths it lists (rules · role definitions · skills · scripts · hooks) are the core. Even a typo fix **disappears quietly**: the next `scripts/install.sh update` reads it as drift, pushes it out to `.harness-bak`, and overwrites with the release copy. So an improvement to the core goes out as a **ledger** entry rather than a file edit **unless an instruction says otherwise**. This is a conditional rather than a flat ban — once you fix it under instruction, land the same fix upstream too.

- Leave it in your own ledger as backlog — make a `-t task -l harness` issue with `bd` and write the verbatim observation and the reproduction conditions into it. That is the only record that survives in this tree.
- Report it to the origin named by the second line of `.harness-state`, `# upstream <owner>/<repo>`. Reporting is a remote push, so it waits for an explicit instruction from the user.
- The fix happens upstream and the derivative takes it via `scripts/install.sh update`. Once taken, leave an "upstream 반영됨 → <버전>" note on the original bead.

What is outside the core (`repos.json` · `rails.json` · `sprints.json` · `CLAUDE.md` · `.beads`) belongs to the derivative, so the table above applies as written. In the origin harness (no `.harness-state`) the table applies as written as well — fixing the core there is the normal work.

## 3. Promotion bar — 2 observations

Propose a change to a rule, a role definition, or a skill only once the same finding has been **observed twice or more**.

**A one-off gets registered as a harness backlog bead** — make it with `-l harness` and write into the body the verbatim observation, the reproduction conditions, and **that it is waiting for a second observation**. **A note alone loses it**: section 1-1 reads the notes of the target story only, `ledger.sh search` cannot search notes (title · ID, plus description via `--desc-contains`), and a closed story drops out of the default query — three layers deep, so **the next retrospective never finds the first observation.** Then the same finding gets judged "one observation" however often it appears, and promotion never arrives — or the count gets filled from outside the round (another session). That has happened (the account is in `harness-r4zw`).

Once registered, the `ledger.sh list -l harness` in 1-1 picks it up at the next retrospective. On the second observation, promote on the strength of that bead, and leave a "반영됨 → <커밋>" note on it afterwards.

**The observation count covers this round alone.** The `--session` in 1-2 cuts the population down to this round, which makes hand-matching **the fallback** — reach for it only when the session UUID was unknown and the run used `--since` alone, then screen attribution by matching each violation's `agent_id` against what this round actually delegated, and read the unattributed ones **as a trend, outside the count.**

## 4. Locating the miss — when a fix landed and the violation repeated

| Symptom | Diagnosis | Action |
|---|---|---|
| Fixed, and the same violation repeats | It was written into a file that work never loads | Move the load location (rule ↔ skill ↔ role definition) |
| Loaded, and it still repeats | This kind resists persuasion | Move it out of the rules and into a **gate or hook** |

## 5. Proposal and application

- Present a change as a **per-file diff** and apply it **after human approval**. Applying on your own is out. (The "immediate fix" in section 2 is limited to notation changes that leave behavior unchanged — a blurry boundary belongs on this path.)
- Quote the source (story ID, the gist of the note) in the applying commit message — that keeps the rule's lineage in git.
- Once a lesson has landed, leave a "반영됨 → <커밋>" note on the original bead to block a double application.

## 6. Rule audit (once a quarter)

Open the list of existing rules and skills and check which ones actually fired in recent rounds. At half or below, cut some — an unused rule eats context and nothing else.
