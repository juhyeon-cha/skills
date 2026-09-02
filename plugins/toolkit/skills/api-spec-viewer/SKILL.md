---
name: api-spec-viewer
description: Read a source tree statically to extract an API spec snapshot JSON, and turn it into one self-contained HTML catalogue page with search, filters and a schema tree. Supports Spring Boot and FastAPI. Use for requests like "이 레포 API 뭐뭐 있는지 뽑아줘", "엔드포인트 목록 정리해줘", "API 스펙 화면으로 보여줘".
---

# Building an API spec catalogue

**The app is never started.** No `/openapi.json` is fetched; only source files are read — so it runs
on someone else's repo as is, with no dependencies, database or configuration. The price is that
routes assembled at runtime are missed.

There are **two** outputs. Do not merge them into one.

| Output | What | Why it is separate |
| :--- | :--- | :--- |
| `<name>.json` | The spec snapshot | People keep and pass it around, and it is the input to `api-contract-diff` |
| `<name>.html` | The catalogue page | For reading and sharing. One self-contained file, so it opens wherever you send it |

## 1. Procedure

1. **Decide the target source tree.** The path given as an argument, or the current repo if none.
2. **Choose the extractor.** One executable per framework.

   | What is in the source | Extractor |
   | :--- | :--- |
   | `.java` · `@RestController` · `@GetMapping` | `extract-spring.py` |
   | `.py` · `APIRouter` · `@router.get(...)` | `extract-fastapi.py` |

   **When both apply, run each on its own tree.** Do not mix them in one run — one snapshot is one
   framework. When neither applies, stop here and tell the user. **Do not force an extractor to
   fit** — the way to add a framework is to add one more file to this folder.

3. **Extract the snapshot.** The output goes to stdout, so always capture it to a file.

   ```bash
   python3 extract-spring.py <source tree> > <name>.json
   ```

   `rc=0` and you are done. `rc=3` means "not a single endpoint was found" and **is not success** —
   either the framework was chosen wrongly or that tree has no API. Do not turn an empty result into
   a page.

4. **Build the HTML.** The input is the snapshot file from the previous step.

   ```bash
   python3 render.py <name>.json > <name>.html
   ```

   `render.py` asserts the snapshot's schema again. On a missing key it prints **the name of the
   missing key** to stderr and exits `rc=1`. Zero endpoints is `rc=1` too.

5. **Put the two side by side in the same folder.** Wherever the path you were given points, or the
   current working directory otherwise. Name them so the subject is recognisable, like
   `<repo name>-api`.
6. **Write both paths in the completion report.** Do not leave out the JSON — it is the input the
   next `api-contract-diff` run takes.

### To compare two points in time

Run step 3 twice on different commits of the same repo to make two snapshots, then hand them to the
`api-contract-diff` skill. This skill does not take commits — what it takes is always a snapshot file.

## 2. The snapshot JSON

`snapshot-schema.md` in the same folder defines the shape. **Both extractors emit the same shape** —
that shape is the interface of a framework-neutral diff. Values are the strings written in the
source, with no type normalisation.

Two runs over the same input produce byte-identical output, because it carries no file paths or
timestamps — so a snapshot can be committed and compared later without drifting.

## 3. The page

**The starting point is the `data-explorer` template of the `playground` skill.** One self-contained
HTML file, dark theme, zero external dependencies — keep that contract as is.

| Slot | What goes in it |
| :--- | :--- |
| Left controls | Search boxes for path and type, HTTP method chip filters, the filtered endpoint list |
| Right preview | The request and response schema tree of the chosen endpoint. Model types expand as `<details>`, nested models go 8 deep, and circular references are marked and stopped |
| **The prompt output slot** | Repurposed as **request/response JSON samples with a copy button** |

**The playground original's "prompt output + copy button" slot is used for copying JSON samples
rather than a prompt** (a user decision). In the original that slot turns what the user did into a
prompt and hands it back to Claude, but an API catalogue is for reading and sharing, so there is
nothing to hand back. What people actually do on this page is lift a sample request and paste it into
`curl` or a test. The `api-contract-diff` page uses the same slot for the same thing — the two pages
must not disagree on how they are operated.

Sample values are placeholders chosen from type names (`Long`→`0`, `LocalDateTime`→an ISO string).
**They are not real data.**

## 4. Check

```bash
bash check.sh
```

It fetches two sample repos at fixed commits, runs both extractors, and checks the schema assertion,
the `render.py` output and the failure paths (missing key · zero endpoints · missing file) together.
Network needed. `check.sh <snapshot.json>` runs the schema assertion alone on that one file.
