---
name: retrospective
description: Retrospective procedure after a story or a sprint closes. Sweeps the execution feedback piled up in ledger notes and the subagent transcript aggregate (checks/transcript-check.sh) into proposed edits to the skills, role definitions, and session context block the harness plugin holds (`${CLAUDE_PLUGIN_ROOT}` — the source is the skills repo `plugins/harness/`). Use on "회고", "레트로", or "이번 스토리에서 배운 것 반영해줘", and right after a story is finished.
---

# Retrospective

## 1. Gather the material

There are three inputs — **the ledger (notes)**, **the subagent transcripts**, and **the guard firing log**. A note holds what a role decided to write down; a transcript holds what the role actually did; the log holds what the guardrail refused to let it do. None stands in for the others.

### 1-1. The ledger

- Read the full `ledger.sh show <ID>` of the target story (or stories) and the notes of every task under it.
- Check what this round left in the harness backlog with `ledger.sh list -l harness`.
- In each note, separate **observation** (what actually happened) from **proposal** (what to change) and pull both out.

### 1-2. Subagent transcripts

- **Path**: `~/.claude/projects/<project directory>/<session UUID>/subagents/agent-*.jsonl`. **This round's session UUID is the last UUID in the scratchpad path the system prompt gives** — pass that to the call below.
- **`${CLAUDE_PLUGIN_ROOT}/checks/transcript-check.sh` is the one place that reads them.** The retrospective **only calls it** — this skill parses no transcript itself. Two parsers make the aggregate diverge.
- **Call**: `bash ${CLAUDE_PLUGIN_ROOT}/checks/transcript-check.sh --since <story start time> --session <session UUID> --json`. `--since` takes ISO8601 or `Nd` / `Nh` — cut the window at the Started of `ledger.sh show <story ID>`. rc is 0 no violations / 1 violations found / 2 judgment unreached.
- **The two are independent axes, so pass both.** `--session` alone leaves a session that ran several stories undivided by round, and `--since` alone mixes in other sessions from the same window — their intersection is this story's this round. **When the session UUID is unknown** (an inherited session, someone else's story), drop `--session`, run it, write that fact into the aggregate quotation, and screen attribution with the fallback in section 3.
- **Aggregate — quote the four JSON keys verbatim.**
  - `signals.<role>`: SIGNAL counts per role. The reviewer rejection rate is `CHANGES_REQUESTED / (CHANGES_REQUESTED + LGTM)`, the evaluator's is `VIOLATION / (MATCH + VIOLATION)`.
  - `tools.<role>`: tool-call distribution — `calls_per_response` · `parallel_responses` · `max_per_response` · `top`. Compliance with the parallel-call discipline comes out here.
  - `reuse`: instance reuse — the count and the combinations of transcripts holding two or more SIGNALs. `CHANGES_REQUESTED,LGTM` in one transcript means the same instance carried the re-review.
  - `a9.verdicts`: violation count for the first-line `SIGNAL:` discipline in role responses.
- **What lives in the transcripts and not in the notes** — at least two come only from this side: ① **the tool-call distribution** (which role fires how many calls in parallel per response, and what it uses — nobody writes that into a note) ② **the role signal counts** (how many times the evaluator rejected — `close_reason` keeps the final MATCH alone).
- **Quote ratios rather than totals.** The directory is live, so totals grow every session. Everything from the transcripts is **observation** — proposals live elsewhere.
- **The failure path is recorded as unmeasured, and stays recorded.** On rc=2 (no transcript directory · 0 delegations completed in the window · no python3), put the `UNREACHED:` lines from stderr (the `unreached` array in JSON) verbatim on the story bead with `ledger.sh note` — "전사 미실측: <UNREACHED 원문>". Then proceed on the ledger alone, and treat the transcript-only items (rejection rate · parallel rate · reuse) as **unmeasured** rather than "no observation" — they enter the 2-observation count in section 3 as nothing at all, not as 0.

### 1-3. The guard log — false-positive rate per rule

The harness says a gate does not weaken a prohibition. The other side has no place to be read: **a rule whose false positives outnumber its true ones is a net loss** — it costs the round more work than it prevents. This is where that gets measured. **Measurement without an action is not measurement**, so ③ below is part of the step, not a follow-up.

**① What to run**

    bash ${CLAUDE_PLUGIN_ROOT}/scripts/guard-log.sh rows [<round>]

Seven TSV columns — time · round · agent · tool · rule · classifiability · command; the summary goes to stderr. `<round>` is a `session_id`; leave it off to take every round in the log. Run it with no argument first — the round column is the axis, not the filter.

That run is hundreds of rows, so group them before reading any:

    bash ${CLAUDE_PLUGIN_ROOT}/scripts/guard-log.sh rows | cut -f2,5,6 | sort | uniq -c

Round × rule × classifiability with a count — that is the denominator per rule, and it is what ② and ③ below are computed over. Then read the full rows of the rules that clear ③'s 5-row floor. **Rules older than the log get their rate quoted per round, never pooled** — ceiling 6 of section 11 says why.

**Read rc before reading a single row.** rc=4 ("blocking really was 0") and rc=6 ("blocking happened, none of it classifiable") are the pair that fabricates a clean rule when folded together, and rc=5 is a missing round, not an empty one. The full rc table and every ceiling on these numbers are **[guardrail-verification.md](../../docs/guardrail-verification.md) section 11, "When firing counts can be used as evidence"** — that section owns them, this one does not restate them. Read it before quoting any rate; two of its ceilings (the 120-character cut halving the denominator, and the log sampling guard firings rather than blocked work) decide how the rate may be worded.

**② What is judged — and by whom**

Per rule, over that rule's `ok` rows only: how many blocks were **false positives** (a legitimate task refused) against how many were **true** (the rule caught what it exists to catch).

| Half | Who | What it is |
|---|---|---|
| The axes — round, rule, agent, tool, command head, classifiability | **machine.** `rows` produces them | The command classifies nothing; it prepares the material up to the point a person reads |
| Was this block justified? | **human.** No command decides it | Measured at **47.4%** needing natural-language judgment (`skills#224`) — the rule name alone does not separate a justified block from a false one |

Do not hide that split, and do not report a rate as if the whole of it were machine-produced. `truncated` and `nocmd` rows are **neither** — they are unclassified, so they leave the denominator rather than landing in either column.

**③ Threshold, and what happens when it is crossed**

**A rule is over threshold when its false positives outnumber its true ones (> 50% of its `ok` rows) and it has at least 5 `ok` rows.** Below 5 the rate is one or two rows of noise; leave it and say so.

Over threshold, stand up **a proposal to narrow that rule** — not a note about it. The proposal goes out on the section 5 path (a per-file diff, applied after human approval), and it carries: the rule name · the rate with **its denominator and the round** · the `ok` rows read as false positives, quoted · what narrowing them costs on the other side (which true blocks the narrowing would also drop). A narrowing with no answer to that last one is not ready.

The section 3 promotion bar still applies: one round's rate is one observation. Register it as a `-l harness` bead with the numbers in the body, and promote on the second.

## 2. Three-way sort

| Branch | Where it goes | Criterion |
|---|---|---|
| Personal preference | User memory | What holds for this user alone |
| Immediate fix | Edit the harness file directly | Typos and dead links only — fixes that **leave behavior unchanged**. A behavior change in a rule, a role, or a skill goes through the approval path in section 5, even when a measurement pinned the defect down |
| Rule candidate | The promotion screen in section 3 | A general rule about how work gets done |

Skipping the sort promotes personal taste into a rule and turns the harness into a pile of documents.

**"Edit the harness file directly" means the plugin's source, never the installed copy.** The skills, role definitions, hooks, checks, and scripts an agent runs come from the installed plugin (`${CLAUDE_PLUGIN_ROOT}`), and the next plugin update overwrites that copy — even a typo fix made there **disappears quietly**. The file to edit is in the skills repo `plugins/harness/`, and the edit reaches installs through a release and a plugin update (`setup` section 3). Landing it there is a PR to that repo, so it goes out **only on explicit user instruction**; until then the improvement goes out as a **ledger** entry rather than a file edit:

- Leave it in your own ledger as backlog — make a `-t task -l harness` issue with `ledger.sh create` and write the verbatim observation and the reproduction conditions into it. That is the only record that survives in this tree.
- Once the fix has landed in the plugin's source, leave a "반영됨 → <커밋>" note on that bead.

**Almost nothing is outside the plugin any more** — the rail and sprint registries are the adapter's answers, and each target repo's gate command and ledger coordinates are its own `.harness.json`. Neither is a place to land a rule, so the table above covers every proposal this procedure can make.

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
