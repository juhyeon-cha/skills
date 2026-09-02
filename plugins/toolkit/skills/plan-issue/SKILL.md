---
name: plan-issue
description: File a discovered defect or open decision as a GitHub issue — what does and does not become an issue, the five-section skeleton for the body, and the standard label assignment. Use for requests like "이슈 등록해줘", "이슈로 남겨줘", "백로그에 넣어줘", "이거 이슈감이야". For fixing and closing an issue that already exists, use the `issue-resolution` skill.
---

# Filing what you found as an issue

Issues live **on GitHub.** Do not keep a copy in the tree — a copy in the tree gets read, and becomes
one more thing to keep in sync.

## 0. Most findings are not issues

**If no action is needed, do not file it.** Three questions come first.

| Question                                       | If it does not pass                                        |
| :--------------------------------------------- | :----------------------------------------------------------- |
| Can you state the **problem** in one sentence?  | That is an annoyance, not a problem. Ask back.                |
| Can you write **what finishes this**?           | An issue with no closing condition stays forever.             |
| **Can you fix it right now?**                   | If you can fix it, fix it. An issue is not a way to defer.    |

The third is broken most often. Filing something you could fix in 5 minutes turns 5 minutes into 30.

**Check for duplicates first.**

```bash
gh issue list --search '<keyword>'              # searches titles and bodies
gh issue list --state all --search '<keyword>'  # including closed ones
```

## 1. The body — five sections

The `template.md` in this skill folder is the skeleton. A section you cannot fill is **deleted**;
filled with `N/A` it reads as reviewed.

```bash
cp <this skill folder>/template.md /tmp/issue.md   # fill it in
gh issue create --title "<title>" --body-file /tmp/issue.md --label bug
```

| Section, in the order `template.md` holds them | What that section answers                                      |
| :---------------------------------------------- | :------------------------------------------------------------------ |
| **What is true**                                 | One refutable fact. Cite it by path and **symbol name**              |
| **Why it is so**                                 | The mechanism — which judgement produces this result                 |
| **Observed result**                              | What you saw, not what you inferred. As the user meets it            |
| **How it closes**                                | What finishes it + a plan to prove it by reverting + a negative control |
| **What it is not**                               | The difference from a neighbouring issue. Only when it applies       |

Two things to hold to.

- **Paste what you observed verbatim.** Put payloads, command output and file contents in a code
  block instead of summarising them. A summary cannot be rebuilt, and the original is expensive to
  reproduce.
- **Cite by path plus symbol, not `path:line`.** Line numbers point somewhere else once code moves,
  and that fact is invisible to whoever reads the citation. Only a frozen tree (a vendored copy and
  the like) is the exception that uses line numbers.

## 2. The title

**Write what is true, not the symptom.** A reader has to be able to tell from the title alone whether
it is their business.

- ❌ `push behaves oddly`
- ❌ `improve the retry queue`
- ✅ `files that never reached the server enter the retry queue, so the queue never empties`

## 3. There are only three labels

**Do not create a new label.** Of GitHub's nine default labels, only three are used.

| Label           | When                                                                 |
| :-------------- | :---------------------------------------------------------------------- |
| `bug`           | An observed defect. **The default** — use it when unsure                 |
| `enhancement`   | Work not yet chosen. Things to build and open decisions both go here     |
| `documentation` | Something that closes with a documentation change alone                  |

Why an item is blocked, and that it is an open decision, go in the **"How it closes" section**, not in
a label. That is why blocked items cannot be filtered out with `--label`, and why `issue-resolution`
§1 tells you to open the body before choosing.

**Withdrawing differs from closing.** When something turns out not to have been a defect, the **close
reason** tells them apart — not a label. Close it plainly and **a defect that never existed goes on
the record.**

```bash
gh issue close <number> --reason completed                      # fixed
gh issue close <number> --reason "not planned" --comment "<why it was not a defect>"
```

GitHub renders these two differently, so there is no reason to add a label on top.

## 4. Where to stop

- **Filing an issue is an external write. It requires an explicit instruction every time.** An
  approval from an earlier turn covers only that one turn.
- **Do not fix it while opening it.** If you are going to fix it, fix it instead of opening an issue
  (§0).
- A claim that can only be confirmed by touching the live system is written down **as unconfirmed.**
  A plausible guess does not go in the "What is true" section.
