---
name: pr-body
description: Write a PR body — the four required sections (What / Why / Verification / What the green run does not establish), the three conditional ones, and the rule that section names are English while their content is Korean. Use for requests like "PR 만들자", "PR 열어줘", "PR 본문 써줘", "pull request 올려줘".
---

# What belongs in a PR body

The diff shows what changed. Everything below is what **a reviewer cannot reconstruct from the diff**.

Pushing and opening the PR require an explicit instruction every time. An approval from an earlier turn covers only that one turn.

## Shape

```markdown
## What

## Why

## Verification

## What the green run does not establish

## Corrections <!-- when applicable -->

## Where deleted content went <!-- when applicable -->

## Out of scope <!-- when applicable -->
```

## The body closes the issue it fixed — `Closes #N`

**When this branch fixes an issue, write `Closes #N` in the body.** It is one line rather than a
section, and it goes inline inside the section where a reviewer acts on it — usually `What`. GitHub
reads that line, closes the issue **the moment the PR merges**, and leaves issue and PR pointing at
each other permanently.

```markdown
## What

- Fixed **the retry queue never draining** (`3ff21ab`). Closes #133.
```

How to check:

```bash
gh pr view <n> --json closingIssuesReferences --jq '.closingIssuesReferences | length'
```

**A 0 means GitHub did not read the line.** An issue in another repository, a typo, `Closed #N`, a
line inside a code block — each of them silently yields 0, and all of them look identical to a human.

> ⚠️ **This count trails a body edit by a few seconds. Read it immediately and you get the _previous_ state.**
> Read right after adding the line and you judge **a healthy body to be broken**; read right after
> removing it and you judge **a link that is already gone to be there.** So **never judge on a single
> read.** On a 0, read once more, and suspect the body only when it is still 0.

⚠️ **Two things this keyword cannot do. Close those by hand, following `issue-resolution` §4.**

- **An item that turned out not to be a defect.** A keyword-closed issue is always `completed`.
  `not planned` can only be set by hand, and putting both in the same slot **records a defect that
  never existed.**
- **A neighbouring issue this branch does _not_ close.** Write the number without the keyword.
  `What the green run does not establish` or `Out of scope` is its place.

**Do not create a section that collects issue numbers.** A number goes inline where it is used.

> [!IMPORTANT]
> **Section names are English, their content is Korean.** English names are fixed anchors when
> scanning on GitHub and do not shift with every translation. The content is written in the language
> its readers use — Korean.

## What each section demands

**What** — what the branch does, in a shape that can be reviewed. **Do not concatenate commit
messages**: they are already inside the PR, and a second copy is one more thing to keep in sync.

**Why** — state the **problem**, in a form that can be argued with. "Improves the tracker" is not a
problem; "closing an item silently drops its old number alias, and 97 of 101 items carry one" is. If
you cannot write the why without describing the change, the change is looking for a justification.

**Verification** — **what breaks when you revert it.** The author answers this first, so review
becomes confirmation rather than reconstruction. Verification that can only be done by hand and
cannot be turned into a test says so, with the reason.

**What the green run does not establish** — name what the gates did not see **about this change**: a
rule enforced by a list nobody added to, a path no test reaches, a claim only a live system can
answer. The answer differs every time, so it never becomes a template.

**Corrections** — when a documented claim turned out to be wrong, write what it was. The reviewer
needs it because code written against the old claim may live outside this diff.

**Where deleted content went** — for everything this branch deleted. Deleting is half the work, and
naming the permanent home of whatever was worth keeping is the other half — the half that goes
missing. **"There was nothing worth keeping" is a complete answer when it is true.**

**Out of scope** — what you found and deliberately did not do, because the outcome is a product or
scope decision. Left unwritten it stays in the author's head and gets rediscovered later at the same
cost.

## Length — a body stops working once its reader tires

**The whole body within 60 lines / 500 words.** Missing that budget usually means the fault is not the
branch but the body.

- **One item, one sentence.** When more is needed the detail **lives in the commit**, and the item
  names that commit (``(`ecef63f`)``). The correction stays in the body, and **the road to the
  correction goes to the commit.**
- **One fact, one section.** When two sections want the same fact, put it in **the section where the
  reviewer acts on it**.
- **What and Why have to be enough to decide whether to keep reading.** The two together within 15
  lines. The rest is scanned rather than read — the body's job is to let the reviewer decide **where
  to look**, not to prove anything.

> Measuring it yourself: `gh pr view <n> --json body -q .body | wc -l -w`.

### Telling whether a section earns its place

A section takes the same test an item does — **does the reviewer act differently because of it?**

- **Do not write what GitHub already shows.** The changed-file count and `+/−` render above the body.
- **`Where deleted content went` is strictly a subset of `What`, and it still gets a heading.** With a
  heading an omission is visible; dissolved into prose it disappears quietly. Keeping `Verification`
  and `What the green run does not establish` apart has the same reason: merged, the one people skip
  becomes the tail of a section they stop reading.

## Rules of form

- **Delete a section that has nothing to say. Do not write `N/A`.** A filled blank reads as reviewed,
  and an absent heading reads as absent.
