# Read knowledge and status

Read [relations](multi-repo.md#search-and-managed-wiki) for query/wiki authorization and status
semantics. Use the existing host-controlled `--host`, `--principal` and `--state`; resolve runtime
through [project setup](project.md) without requiring an authoring writer for a read-only query.

For an answer that must match the live browser, use `multi_repo.py read` with the existing goal
input and follow [managed reader](reader.md). Cite its projection ID and read time; preserve its
stricter publication/body boundary. The older `query` command retains its query-only permission
semantics and may expose more evidence than the managed reader. Do not combine their bodies.

For one known project inspect `knowledge.py --project PATH status` or `status --run ID` as needed.
For registered relations use `multi_repo.py --state PATH --host HOST --principal PRINCIPAL query
--input INPUT` with `{"goal":"ID"}` and optional literal `text`. For existing managed wiki bodies
use `wiki` with the same goal input. Commands return current authorized projections and separate
index/read/publication status. A recorded completion or stored hash does not prove currentness.

Answer using accessible evidence and locators from those public results. Keep repository ID,
path and URL distinct; distinguish observed implementation, target, document review and verification.
Report partial/inaccessible/stale/withdrawn states as returned. Whole completion still requires all
required members and integration evidence. Report exclusions without exposing hidden identifiers,
paths, titles or text; a query permission does not authorize private-object inspection.

An absent/stale index is a finding, not permission to `refresh`. Missing state is not permission to
`init`. Requested changes go to the responsible operation with the original question and missing
coordinates; never claim that a handoff completed the change.
