---
name: operate
description: Set up and operate local knowledge automation or repository relations, process events and host receipts, inspect failures, stop or resume. Uses existing project workflows; a read-only knowledge question uses knowledge:query.
---

# Operate knowledge workflows

Read [project setup](../../references/project.md) for runtime and host capabilities. Reuse existing
project/state directories; if no reviewed baseline exists, hand its scope to `knowledge:bootstrap`.
For event requests, polling, host task receipts or failure recovery read
[automation](../../references/automation.md). For relation setup, goal registration, verification,
impact records or index maintenance read [relations](../../references/multi-repo.md).
Those procedures own commands, authority, locks, receipts and state; keep one authoritative record.

Inspect status and original host calls before choosing the next operation. Preserve source/goal
identity and actual authorization. Dispatch returned prompts through real host capabilities with
required author/reviewer separation. Import only the actual response for the exact pending task.
After response loss or an unknown outcome, reconcile the original call; do not launch a replacement
writer or rewrite saved prompt hashes. A real policy/access decision remains a named wait.

Project document changes use `knowledge:update`; independent judgments use `knowledge:review`.
Querying state does not authorize publication. Stop follows the documented next-boundary behavior;
it does not kill in-flight calls or roll back writes. After resume recheck state and receipts.
Finish with actual execution status, pending task or next action, separate document/implementation
outcomes, failure evidence and unverified coverage. No central scheduler or remote service is implied.
