---
name: agent-doc-audit
description: Sweep the documents an agent reads (CLAUDE.md, AGENTS.md, rules, SKILL.md, role definitions) against seven criteria, put every stale sentence in a proposal table, and apply only what the user confirms. Use for requests like "문서 정리해줘", "doc audit", "에이전트 문서 낡은 거 걷어내줘", as a periodic /loop job, and before a release. Writing a new document is the `writing-for-agents` skill; this one prunes documents that already exist.
---

# Auditing the documents an agent reads

A rule loads every session, and its reader is an agent. Every sentence that does not change the
agent's next action is pure load — and sentences go stale silently, because adding feels safe and
removing feels risky. This procedure cores through that sediment on a schedule: machine detection
first, then a reading pass, then a proposal table the user confirms **before any file changes**.

## The seven criteria

Each heading below is one criterion. The question under it is the judgment for one sentence: a
"yes" puts the sentence in the proposal table.

### 1. Correction history

Does the sentence describe what the text used to say, or that something was fixed, instead of
stating the current fact? A document carries the fact after the change; git and the ledger hold the
history. (Exception: a user decision and its reason stay — a decision steers the next reader and
cannot be rebuilt once deleted.)

### 2. Behavior-neutral wording

Would deleting the sentence change what the agent does next? If not — an instruction the model
already follows by default, a reassurance, a fixed phrase to append to every reply — it goes.

### 3. Duplication and contradiction

Does the same meaning live in more than one place, or do two places disagree? One place owns the
meaning; every other place points at it by file and section title, never by restating it.

### 4. Numbers, dates, line numbers

Is there a measurement, a date, a count, or a `<path>:<line>` pointer in the rule body? Measured
values belong in the ledger note of the task that produced the change, with a one-line pointer
(`실측 근거는 <bead ID>`) left in the rule. The only number a rule keeps is one that **is** the
rule (a limit, a retry count), and it lives in exactly one place. A line-number pointer moves the
moment the code moves and tells nobody; cite by path plus symbol or section title.

### 5. Evidence and anecdotes

Is the sentence telling the story of what happened rather than giving the test to apply? Rewrite it
as the judgment criterion, and move the story to the ledger behind an ID pointer.

### 6. Dead pointers

Does every path, command, flag, and section title the document names exist? `check.sh` tests paths
by existence; commands, flags, and section titles are checked by hand in the reading pass — run the
command with `--help`, open the section.

### 7. Language

Is the sentence written in English? A document an agent reads is written in English; a Korean
sentence is unfinished work. The only exceptions are strings the document quotes rather than
speaks — a section title it points at, a user utterance it triggers on, a fixed-format string it
tells the agent to emit.

## Procedure

The order is fixed. Steps 1 and 2 read; step 3 writes a table; **step 5 is the first step that
touches a file, and it runs only after step 4.**

### 1. Detect

```bash
bash check.sh <dir> [<dir>…] [--root <dir>]…
```

One line per candidate on stdout: `<file>:<line>:<criterion>:<sentence>`. It catches what a regex
can: dates, line-number pointers, correction vocabulary, backtick paths that do not exist, and lines
with Korean outside quotes and headings. When the documents point into another tree (a plugin
pointing at its harness root), pass that tree as `--root` — it is consulted for path existence but
not scanned; otherwise its paths read as dead. `CHANGELOG.md` files are skipped: a changelog is history,
not a place a command is called from, so its old paths and dates are correct as they stand. A missing directory is rc≠0 with the reason on stderr. rc 0 means the sweep ran, not that nothing was found.

### 2. Read

Read every scanned file top to bottom with the seven questions in hand. Criteria 2, 3, 5, and the
command/flag/section half of 6 are not machine-detectable; this pass is where they are found. Every
line `check.sh` printed gets a verdict here too — a match is a candidate, not a finding.

### 3. Propose

One table, one row per sentence, nothing applied yet:

| Location | Criterion | Action | Replacement |
|---|---|---|---|
| `<file>` · section title | 1–7 | delete / rewrite / move to ledger | the new sentence, or the bead ID the evidence moves to |

An empty table is a valid result — report "nothing to prune" and stop.

### 4. Confirm

Show the table to the user and wait. Apply only the rows the user confirms; a row the user rejects
or leaves undecided stays out. There is no batch approval implied by silence.

### 5. Apply

Edit the confirmed rows. A move-to-ledger row is two edits: the evidence goes into the bead note
first, then the sentence in the file becomes the pointer. A rename or a deleted section title is
followed by a global grep for the old string — zero remaining hits before reporting.

### 6. Gate

Run the target repo's own gate (its `check` command, or `claude plugin validate --strict` for a
plugin), then rerun `check.sh` on the same directories and confirm the confirmed rows are gone.
Commit under the repo's commit convention.

## Self-check

The skill is its own first target: `bash check.sh <this skill's folder>` yields zero candidates
under criteria 1 and 4. Keep it that way when editing this file.
