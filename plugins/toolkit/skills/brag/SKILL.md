---
name: brag
description: Build up what you did as [problem - solution - result] entries in one place under your home directory, and render what has accumulated into a quarterly achievement dashboard HTML page. Entries accumulate in `~/.brag/` rather than in a project, so achievements spanning several repos and several employers gather in one place. Use for requests like "이번 분기 한 일 정리해줘", "성과 기록해줘", "brag 문서 만들어줘", "평가 자료 뽑아줘", "연봉협상 자료 만들어줘".
---

# Accumulating achievement records and rendering a dashboard

**There are only two actions: accumulate (`add`) and render (`render`).** Accumulating is done one
entry at a time as you go; rendering is done once, at review or retrospective season. Do not try to do
both at once — the value of an achievement record comes from what was put away as it happened.

## 1. Where it accumulates — `~/.brag/entries.jsonl`

**Do not write into a project directory.** Achievements span several repos, and a personal review
record must not be committed to a company repo. So the location is fixed to one place under the home
directory, and every run appends to the same file whichever directory you are in. It is JSON Lines,
one entry per line, so a person can open and edit it and `grep` can find things in it.

**When it cannot be written, nothing is spilled elsewhere.** If it cannot be created under the home
directory, `brag.py` exits with code 2 — there is no fallback that quietly drops it in the current
directory.

## 2. Accumulating

```bash
python3 brag.py add <entry.json>
```

The entry file is one object or an array of objects. **Five fields are required** — if any one is
empty, the exit code is 2. Do not fill a blank with a plausible sentence; ask the user what is needed
to fill it.

```json
{
  "date": "2026-08-02",
  "project": "Settlement batch",
  "title": "Moved the nightly settlement batch to incremental processing",
  "problem": "It recomputed everything, so batch time grew linearly with transaction count. The 9am cutoff was missed twice.",
  "solution": "Placed a cursor so only transactions after the last success time are read, and made a failure resume from that cursor.",
  "result": "Batch time went from 4h 12m to 22m. Measured in the first week of August.",
  "metrics": [
    { "label": "Nightly batch duration", "from": "4h 12m", "to": "22m", "delta": "▼ 3h 50m", "good": true }
  ]
}
```

| Field | Required | What goes in it |
| :--- | :--- | :--- |
| `date` | ✓ | `YYYY-MM-DD`. The quarter is taken from this value |
| `project` | ✓ | The repo, service or team initiative name. Every entry carries it |
| `title` | ✓ | The name of one entry. What you did, in one line |
| `problem` | ✓ | What was stuck, and where the damage landed |
| `solution` | ✓ | What you did. What changed, not who did it |
| `result` | ✓ | What went from what to what. **Keep the evidence (period, measurement method) in the same sentence** |
| `metrics` | | Indicators with before and after values. Drawn as achievement metric cards |

In a `metrics` entry, `label` and `to` are required; `from`, `delta` and `good` are optional.

- Without `from`, the card becomes a plain statistic tile (when only one of before and after exists).
- **`delta` must start with one of `▲`, `▼` or `—`.** Otherwise the exit code is 2 — a direction
  distinguished by colour alone disappears in black-and-white printing and for colour-blind readers.
- `good` means **did it get better**, not did it go up. Response time or error rate going down is
  `"delta": "▼ …", "good": true`. The default is `true`. `—` (no change) has no direction, so `good`
  is ignored and it is drawn in grey.

### Hand a pile of records to `worklog-structurer` to build entries

When the user hands over a commit list, issues, a weekly log or meeting notes wholesale, **do not cut
them into entries yourself** — hand them to the `worklog-structurer` agent. Deciding what counts as
one entry, what to leave out, and which of the three fields is missing from the records is that
agent's job. Transcribe the [problem - solution - result] entries it returns into the JSON above and
`add` them.

When an entry comes back with a field left as "not in the records", **do not accumulate it as is — ask
the user.** The before and after values of `result` are what go missing most often. When a number has
to be computed, hand it to `data-analyst`.

## 3. Rendering

```bash
python3 brag.py render --team "<team>" --author "<name>" > draft.html
python3 ../html-report/embed-font.py draft.html pretendard > draft-font.html
python3 ../html-report/finalize.py draft-font.html > <YYYY-MM-DD>-brag.html
```

**The three commands are one set and the order is the discipline.** Run `embed-font.py` before
`finalize.py` — reversed, the injection-point comment is gone and `embed-font.py` ends at rc=1. The
judgement is the exit codes of the three commands, and the final output is one `.html` page with the
font embedded too.

- **Use the `html-report` template, fonts and checker as they are.** Do not build a second template in
  this skill. When colours, components or print rules come up, read `../html-report/SKILL.md` — that
  is the original.
- Without `--team` and `--author`, the team falls back to a "not stated" placeholder and the author to
  the login account name. **This is the slot where a real name is printed on the cover, so confirm
  with the user before passing it.**
  **When it runs delegated (a subagent or an automated loop) and there is no one to ask, use the
  values you were given and write in the completion report that you used them unconfirmed** — do not
  pretend to ask where asking is impossible. This does not mean values may be invented: a value you
  were not given stays at its default.
- The quarter split comes out of `date` automatically. The most recent quarter is on top.
- Paste the font guidance from `../html-report/SKILL.md` §6-3 into the completion report as is.

### Failure paths

| Situation | Exit code | What to do |
| :--- | :--- | :--- |
| Zero records accumulated | `render` rc=1 | No empty HTML is emitted. Tell the user to `add` some first |
| Cannot write under the home directory | `add` rc=2 | Nothing is written elsewhere. Pass the reason to the user as is |
| A required field is empty · `delta` has no symbol | `add` rc=2 | stderr says which field. Ask instead of inventing a value |

## 4. Self-check

```bash
bash check.sh             # isolates with a temporary HOME and asserts the full path plus two failure paths
bash check.sh <outdir>    # leaves the outputs behind (for a person to open)
```

Run as `root`, the "unwritable home" assertion bypasses the permission check and becomes meaningless.

## 5. Ceilings left in place

- **There is no command to edit or delete an accumulated record.** Edit `~/.brag/entries.jsonl`
  directly — JSON Lines, one entry per line, so an editor is enough. A delete command was left unbuilt
  to keep an irreversible action out of the tool.
- **There is no period filter.** `render` emits everything accumulated. To render only a certain
  period, copy `entries.jsonl` to another file, filter it there, and run with `HOME` changed.
- **Do not mix this with `postmortem`.** A retrospective has the three fields [cause - action -
  prevention] and does not accumulate. The same event can be both an achievement and a retrospective,
  but even then it is split into two entries, one for each skill.
