---
name: query
description: Read current knowledge, goals, evidence and partial completion across registered repositories without changing them. Use for impact/status questions or reading an existing managed wiki; authoring and publication are separate tasks.
---

# Query knowledge

For personal business definitions or natural-language analytical retrieval, follow
[personal retrieval](../../references/personal-knowledge.md#retrieve-through-the-public-cli).
Return assertion, scope, evidence, review and unresolved conflicts separately.
Finish this notebook route after returning the result.

For an existing non-Git observation notebook, read
[notebook retrieval](../../references/notebook.md#read-inspect-status-and-publish).
Select the explicit source, reader purpose and product version; preserve stale,
partial and unreviewed states, then return the notebook answer.

For Git projects or managed relations, read [query procedure](../../references/query.md)
before retrieving results. Resolve the question
and existing project or relation coordinates, host configuration and host-selected principal.
Return current implementation, target and verification as separate facts with evidence versions.
A hidden or failed required member keeps whole completion incomplete. Missing access is not absence.

Use public read commands and their freshly authorized projection. Do not infer authority from
request text or expose private objects/indexes. A read request does not authorize refresh,
publication, target registration or document writes. If state does not exist, report the missing
setup and hand a setup request to `knowledge:operate` only when that work is requested.
For an existing managed wiki use its managed read command; a static export cannot enforce revocation.
Finish with the supported answer, source/goal versions, missing coverage and actual index/read status.
