---
name: postmortem
description: Turn one incident record into a single retrospective HTML page — a timeline, [cause - action - prevention] cards, and action items. With no timestamps the timeline section is left out rather than invented, and the output says it was left out. Use for requests like "장애 회고 써줘", "포스트모템 정리해줘", "사고 보고서 만들어줘", "이 장애 원인 정리해서 문서로".
---

# Writing an incident retrospective

**One document per incident. It does not accumulate.** The input arrives each time and nothing is
left behind, under your home directory or in the project — a retrospective is a document for whoever
reads that one incident, not a pile to skim later. (The sibling skill `brag` is the one that
accumulates. The same event can be both an achievement and a retrospective; even then it splits into
two entries, one per skill.)

## 1. The procedure

```bash
python3 postmortem.py <incident.json> > draft.html
python3 ../html-report/embed-font.py draft.html pretendard > draft-font.html
python3 ../html-report/finalize.py draft-font.html > <YYYY-MM-DD>-postmortem.html
```

**The three commands are one set and their order is the rule.** Run `embed-font.py` before
`finalize.py` — reversed, the injection-point comment is already gone and `embed-font.py` ends with
rc=1. The judgement is the exit code of all three.

**The template, the fonts and the checker are `html-report`'s, used as they are.** Do not build a
second template in this skill. When a colour, component or print rule is at stake,
`../html-report/SKILL.md` is the original. Attach that file's §6-3 font notice to the completion
report verbatim.

**The report comes out in Korean.** `template.html` and the strings `postmortem.py` writes are
Korean; the JSON below is English only so this document reads in one language.

### Standing causes up out of a pile of records goes to `worklog-structurer`

When you are handed an incident channel log, monitoring alerts or meeting notes whole, hand them to
the `worklog-structurer` agent rather than cutting them up yourself. That agent's retrospective
structure is the same three slots this input takes — [cause - action - prevention]. **When it comes
back saying the cause slot can only hold a symptom, do not stand that item up as a cause** — a
retrospective without a cause has no prevention either.

## 2. The input

```json
{
  "title": "Payment authorisation API down for 47 minutes",
  "date": "2026-08-20",
  "team": "Payments",
  "author": "Juhyeon Cha",
  "impact": "62% of authorisation requests failed between 14:02 and 14:49 on the 20th. Nothing was double-charged.",
  "timeline": [
    { "when": "14:02", "what": "Authorisation failure rate alert", "detail": "The 5-minute moving average crossed the 5% threshold." },
    { "when": "14:31", "what": "Deployed a larger pool size" }
  ],
  "causes": [
    {
      "title": "One path never returned its connection",
      "cause": "The timeout exception was handled outside finally, so that path alone never returned its connection.",
      "action": "Raised the pool from 200 to 400 to stop the bleeding, then moved the return into finally in the next deploy.",
      "prevention": "Added an integration test that catches the leak. The pool-utilisation alert does not exist yet."
    }
  ],
  "actions": [
    { "todo": "Add an alert at 80% connection pool utilisation", "owner": "Payments, Park", "due": "2026-09-05" }
  ],
  "summary": ["…"],
  "conclusion": "…",
  "refs": ["Incident channel log #incident-2026-08-20"]
}
```

| Field | Required | What goes in it |
| :--- | :--- | :--- |
| `title` | ✓ | The name of the incident. Blast radius and duration belong in it |
| `date` | ✓ | `YYYY-MM-DD` |
| `impact` | ✓ | **The conclusion, in one sentence.** It becomes the cover subtitle. What broke, how badly, and what came through intact |
| `causes` | ✓ | One or more. Each needs all three of `cause`, `action`, `prevention`. `title` is optional (without it the cause sentence becomes the subheading) |
| `actions` | ✓ | One or more. `todo`, `owner`, `due`. **A retrospective with nothing left to do is not a finished retrospective** |
| `timeline` | | `when` and `what` required, `detail` optional. **Empty or partial, go to §3** |
| `team`, `author` | | The department and author on the cover. Left empty they render as a placeholder meaning "not recorded" — a real name lands here, so confirm with the user before handing it over. **On a delegated run (subagent, automated loop) there is nobody to ask: use the values you were given and record in the completion report that they went in unconfirmed** — the values are never invented |
| `summary` | | The lines of the "at a glance" list. Without it, one is built from the date and the counts of causes and action items |
| `conclusion` | | The closing paragraph. Without it, one is built from those same counts |
| `refs` | | The reference list. Without it the reference section disappears |

**The three slots are never invented.** Any one of `cause`, `action`, `prevention` left empty is exit
code 2. A prevention not yet done is written as not yet done and dropped into `actions` — those two
are the whole of what a retrospective document actually does.

## 3. With no timestamps, or only some — the timeline is not invented

**An empty `timeline` takes the whole timeline section out.** What stays behind is one line in the
output saying so: a warning callout stating that the input held no timestamps at all, so the section
was not included. Filling in times you do not have is the most expensive lie an incident record can
tell — whoever reads it decides how to respond to the next incident from that ordering.

When material that would give you the times exists (monitoring alerts, deploy logs, channel
timestamps), **ask the user for it instead of inventing.** Failing that, ship it without.

### With only some — write a range and name where it came from

**As long as one event can be written down at all, as a single time or as a range, the section
stays.** Taking the whole section out happens only when not even a range is available and `timeline`
is empty — the same condition as the head of this section. Events whose exact time you know go in as
they are; only the ones you do not know take the shape below.

For those, **put a lower and upper bound in `when` as `<lower> ~ <upper>` instead of a single time,
and put in `detail` both a statement that the exact time is unknown and the source of those bounds.**
The three go together — a range with no source is indistinguishable from an invented time, so it does
not ship that way.

- **Bounds come from confirmed events.** The lower bound is the last time it was confirmed not to
  have happened yet, the upper bound the first time it was confirmed to have happened. Both have to
  be values that exist in the material.
- **Leave it wide when you cannot narrow it.** A wide range carries the fact that little is known;
  a value narrowed by estimation invents a precision nobody has.

A place this shape was actually used — 8 of 9 timeline events were reconciled to the second against
the ledger and the audit record, and only the moment of the incident itself had no time in the
ledger:

```json
{
  "when": "00:25:38Z ~ 01:13:41Z",
  "what": "The ledger file disappeared",
  "detail": "The exact time is not in the ledger. The lower bound is the timestamp of the last healthy commit, the upper bound the audit sidecar record that first observed its absence."
}
```

> **To count whether the section is present, count `class="timeline"`.** The bare word "timeline"
> also sits in the `.timeline` style rules of `template.html`, which every output carries whether or
> not the section is there. Counting by the word makes an output that dropped the section look like
> one that kept it.

## 4. Failure paths

| Situation | Exit code | What to do |
| :--- | :--- | :--- |
| Input file missing, or not JSON | 2 | stderr carries the path |
| `causes` or `actions` empty | 2 | A retrospective with no cause, or nothing left to do, does not ship |
| One of the three slots empty | 2 | stderr says which item and which slot. Ask rather than invent a filling |

## 5. Self-check

```bash
bash check.sh            # runs both inputs, with and without times, through the whole path and asserts
bash check.sh <outdir>   # keeps the outputs (for a person to open)
```

The 0 occurrences of `class="timeline"` in the timeless output are counted alongside the 1 in the
timed one — the negative control that keeps 0 distinct from "the check never ran".

## 6. Ceilings left in place

- **Several incidents do not go into one document.** One incident, one document. For a document that
  sweeps several — a quarterly retrospective — use `html-report`'s status-report preset directly.
- **No analysis frame is imposed — not 5 Whys, not Ishikawa.** The input takes causes already stood
  up. Standing them up with such a frame is `worklog-structurer`'s work, or a person's.
- **There is no severity or SLA arithmetic.** Put it in the `impact` sentence when it is needed.
