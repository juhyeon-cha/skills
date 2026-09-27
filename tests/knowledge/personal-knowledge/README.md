# Personal knowledge contract fixtures

Read this when reproducing the personal knowledge acceptance cases or inspecting
public request/response examples. These are synthetic local fixtures, not business
data or actual organizational review decisions. The authoritative runtime contract
is [personal knowledge](../../../plugins/knowledge/references/personal-knowledge.md).

Run from the repository root with Python 3.10+:

```sh
bash tests/knowledge/personal-knowledge-check.sh
python3 -B tests/knowledge/personal-knowledge-fixtures.py --output /absolute/new-fixture-output
```

Set `KNOWLEDGE_PYTHON` to select another interpreter. Set
`WIKI_MARKDOWN_IT_MODULE` to an existing absolute MarkdownIt module path to exercise
the rendered wiki; without it the rendering case explicitly skips. The generator
requires a new output directory and uses disposable notebooks through the public CLI.

`personal.json` and `sales-quantity.json` are definition-v2 inputs. `request.json`
is a retrieval-v1 request that needs no prior knowledge selection. `questions.json`
covers registered terms, aliases, related-term ambiguity, explicit host concept IDs
and unmatched expressions; it does not measure arbitrary paraphrase recall.

Each `responses/*.json` transcript contains initialization coordinates and ordered
`calls` with command, input and actual versioned response:

| Fixture | Boundary |
|---|---|
| `personal` | Assertion before technical evidence exists |
| `supported` | Complete imported evidence and a synthetic independent review |
| `conflicting` | Competing definitions remain visible |
| `stale` | Incomplete replacement evidence invalidates current support |
| `ambiguous` | Related-term-only matching requires interpretation |
| `missing` | No match does not prove concept absence |

The executable acceptance suite also covers scope isolation, corrections and
scheduled periods, retained history, failed first writes and initialization,
competing database ownership, and inert wiki rendering. Hosts own authorization,
conversation orchestration and live execution; fixture success does not establish
live business-data accuracy or production integration.
