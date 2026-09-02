---
name: api-contract-diff
description: Turn two API spec snapshot JSON files (before and after) into one self-contained HTML page that colour-codes added and removed endpoints and fields and lists the endpoints they affect. Use for requests like "API 뭐가 바뀌었는지 정리해줘", "이번 배포에서 계약이 어떻게 달라졌나", "클라이언트팀에 변경분 알려야 해".
---

# Building an API contract change page

**What this skill takes is two snapshot files, not commits.** Extracting a snapshot from a commit is
the `api-spec-viewer` skill's job, and this skill sees only those two outputs. So the two sides need
not even be two points of the same repo — the same shape is enough.

## 1. Procedure

1. **Obtain two snapshots.** Use the ones that already exist. Otherwise build them with
   `api-spec-viewer` — for two points of the same repo, extract once from each point's source tree.

   ```bash
   # Example: extract from two commits. This leaves the working tree untouched.
   mkdir -p /tmp/before && git -C <repo> archive <before commit> | tar -x -C /tmp/before
   python3 ../api-spec-viewer/extract-fastapi.py /tmp/before > before.json
   python3 ../api-spec-viewer/extract-fastapi.py <repo> > after.json
   ```

   **The two snapshots must carry the same `framework`.** Otherwise this skill refuses with `rc=1` —
   things of different shape are not forced into a comparison.

2. **Build the page.** The argument order is before, then after. Reversed, additions and removals
   come out swapped.

   ```bash
   python3 render-diff.py <before.json> <after.json> > diff.html
   ```

3. **Read the exit code.**

   | rc | Meaning | What to do |
   | :--- | :--- | :--- |
   | 0 | It was produced. **Zero changes is also 0** — an empty diff is not an error, and the page that comes out states "no changes" explicitly | Done |
   | 1 | The input is wrong: missing file · not JSON · missing schema key · framework mismatch | Read the path and the key name printed on stderr, and fix it |
   | 2 | The argument count is not two | Give both, before and after |

4. **Name where both input snapshots came from in the completion report** — the repo and the two
   commits. Without this the next person cannot rebuild the same page.

## 2. What gets compared

| Subject | Matching key | What comes out |
| :--- | :--- | :--- |
| Endpoint | `method + path` | added · removed · request/response type changed |
| Model | `name` | model added · removed · **field added · field removed · field type changed** |

**Fields are the body of this page.** A response model losing a single field while the endpoint list
stays identical is the common way clients break, and in a commit diff that is one line nobody notices.

**Affected endpoints** are found backwards from the changed models. Collect every model reachable
from an endpoint's request and response types by following field types, and list the endpoint if a
changed model is among them. Not only direct references — **references through nested models are
caught too.**

Models sharing a name (common in multi-module repos) are compared **merged into one item**, because
the snapshot schema carries no module path to tell them apart — their fields become a union.

## 3. The page

**The starting point is the `diff-review` template of the `playground` skill.** One self-contained
HTML file, dark theme, zero external dependencies — keep that contract as is. The colours are that
template's too: **additions green (`#7ee787`), removals red (`#f85149`), type changes yellow
(`#d29922`)**.

| Slot | What goes in it |
| :--- | :--- |
| Header | A count summary of additions, removals and changes. Items at 0 are dimmed |
| Body cards | removed endpoints → added endpoints → endpoints whose types changed → models whose fields changed → added and removed models. Each card carries `+`/`-`/`~` lines and chips for the affected endpoints |
| **The prompt output slot** | Repurposed as **a copy button for request/response JSON samples** |

The original template's "per-line comments → prompt output" slot is not used. The purpose of this
page is not to gather review comments and hand them back to Claude but **to tell another team what
contract changed**, so that slot instead holds a copy button that lifts a request/response JSON
sample in its after shape (a user decision). The `api-spec-viewer` page uses the same slot for the
same thing.

Samples for removed endpoints come from the **before** snapshot, everything else from the **after**
one. Sample values are placeholders chosen from type names, not real data.

## 4. Check

```bash
bash check.sh
```

With two synthetic snapshots it asserts counts for endpoint addition and removal, field addition,
removal and type change, and impact propagation through a nested model, then checks that 5 kinds of
input that must fail actually do (two missing files · key composition mismatch · framework mismatch ·
too few arguments). No network needed.
