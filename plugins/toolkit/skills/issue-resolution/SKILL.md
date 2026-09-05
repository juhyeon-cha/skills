---
name: issue-resolution
description: Pick an open GitHub issue and close it — choose one that is not blocked, fix it, prove it by reverting, close it. Use for requests like "이슈 해결해줘", "열린 결함 처리해줘". For opening a new issue, use the `plan-issue` skill.
---

# Picking an open issue and closing it

## 0. Narrow before you read

Pulling issues in whole pours tens of thousands of words into context. **Narrow first, then open
exactly one.**

```bash
gh issue list --label bug --state open    # narrow by label
gh issue list --search '<keyword>'        # searches titles and bodies
gh issue view <number>                    # only after choosing, and only that one
```

## 1. What to pick

There are three labels — `bug`, `enhancement`, `documentation`. **Neither being blocked nor being a
fork in the road is in a label.** You learn it from the body's "how it closes" section.

| What the body says                         | What it means                              | What you may do                              |
| :----------------------------------------- | :----------------------------------------- | :------------------------------------------- |
| It needs a round trip to a live system      | It does not close without the real system   | **Nothing.** Access is the user's to approve  |
| The outcome is a product or scope decision  | It is filed as `enhancement`                | **Propose** the decision; do not act on it    |
| Anything else                               | It closes offline                           | Pick this one                                 |

> 🛑 **Blockedness is not answered by machine. Open the body before you choose.** Choosing from the
> list alone lands you on an item that needs a live system, or one you have no authority to decide.

Given equal conditions, pick **the narrower one.** A broad item is hard to walk back.

## 2. Before fixing, check that the issue is still true

**An issue body is a statement about the code on the day it was written.** It may already have been
fixed. Read the code at that spot before you go to fix it.

If the repository has a gate that matches regression fingerprints, **run it before matching by
hand.** A fingerprint usually takes this shape.

```
present <pattern> in <path>    the defect's trace is still there
absent  <pattern> in <path>    what a fix would have left is still missing
```

⚠️ **A fingerprint that no longer matches means "go look", not "it is fixed".** A formatter rewrapping
an expression is enough to throw it off. A human judges it by opening the code.

⚠️ **A fingerprint that still matches is weaker still.** A trace survives the fix, and on an item with
two ways to close, the fingerprint watches only one of them. **So let a fingerprint decide what to
pick, and never what is still alive.**

⚠️ Key on **what working code has to contain.** Keying on the *name* of what disappeared misfires —
the comment recording the deletion carries that name verbatim.

Already fixed is a result too. Write down where it lives and close it (§4).

## 3. Fix it, then prove it by reverting

Done is not that it passes — **done is that reverting it fails.**

1. Fix it.
2. **Revert** that fix.
3. **Watch the test go red.** Green means the test guards nothing, so fix the test before the code.
4. Restore what you reverted and confirm green.

Judge on the full gate output. Filtering it through `head` or `grep -c` first does not hide a defect
so much as **manufacture one.**

## 4. Closing — what you fixed is closed **by the PR**

An item you fixed does not take `gh issue close`. Write `Closes #<number>` in the PR body and **let
the merge close it.** The format and how to check it are written once, in the `writing-pull-request` skill.

Closing by hand first leaves the issue closed even when the PR is rejected or reverted, and no link
to what fixed it is created anywhere.

**Naming where the content lives is not optional.** Closing the issue is half the work; the other
half is naming the permanent document the content moved into. **A closed issue is not a permanent
document.** When it closes automatically that place is the commit message and the PR body, and that
is where you write it.

**Two cases close by hand.**

It turned out not to be a defect. A keyword-closed issue is always `completed`, so `not planned` is
set here and nowhere else — in the same slot the two **record a defect that never existed.**

```bash
gh issue close <number> --reason "not planned" --comment "<why it was not a defect>"
```

And it turned out in §2 to be **already fixed.** There is no PR to close it, so close it by hand and
put in the comment which commit fixed it and where the content lives.

```bash
gh issue close <number> --reason completed \
  --comment "Already fixed in <sha>. Where the content lives: <permanent document and symbol>"
```

For a regression or a wrong close, `gh issue reopen <number>`; for a newly found defect, the
`plan-issue` skill. **Fix one issue at a time** — a neighbouring one waits for its own run.

## 5. Where to stop

The following are **gated on the user**, and are not done in passing.

- Anything that touches a live system — a single read-only `GET` included.
- **Every write to GitHub** — closing, opening, commenting. It leaves the machine, so it takes an
  instruction every time. An approval from an earlier turn covers only that one turn.
  - `Closes #N` is not an exception; it **fits this rule better.** Writing it in a PR body is not a
    write, and what actually closes the issue is **the user merging.**
- Changing a gate's judgement model. **Count first** how many items a new check turns red: one or two
  is a correction, dozens is a scope change.
- Widening a baseline or an exemption list to stay green. That failure is the reason the area exists.
- Acting on a product or scope decision.

## 6. When one issue is done

Run every gate the repository has. Then commit on the worktree branch, and **ask before opening the
PR.**

**One item at a time.** Bundling several into one commit makes the revert-to-prove step impossible.
