# Assess impact and structural changes

Use this procedure for structural changes, indirect dependencies, shared policy or index changes.
It connects existing intake, implementation and bootstrap procedures; the caller keeps its
bounded impact notes beside the original request rather than creating another state store.

## 1. Compare meaning and expected effects

Read [intake](intake.md) for origin, intent and authority. Pin both sides of the change and
classify additions, modifications, deletions, moves, rename candidates and decision changes.
Compare behavior before treating a moved file as the same policy. Reconcile code with the
authoritative intent; a defect requires implementation repair, not a matching false explanation.

For each change, inspect its direct and indirect callers, tests, contracts, shared policy,
reader documents and index entries. Start from the source bindings, then inspect references
outside those bindings: file-level evidence cannot discover undeclared dependencies. In the
other direction, map each changed goal or document commitment to the code and tests that must
establish it. Freeze expected changed, new and preserved artifacts and the reasons before work.
For preserved artifacts and each unlinked change, record why behavior and reader commitments are
unaffected, with the inspected evidence. Retain unresolved impact as remaining work.

## 2. Select the supported update boundary

Use [editing constraints](updates.md) for existing excerpts. If the result needs new claims,
new documents, consolidation or a changed scope, freeze a separate successor bundle and follow
[bootstrap](bootstrap.md), including independent review before initialization. Preserve old
documents and evidence; logical retirement changes the current selection, not the historical
bytes. Read [recovery](workflow.md) to terminate a pre-application run or retire its project and
connect the reviewed successor. Check the successor's actual initialization and baseline; a
recorded successor path alone is insufficient.

Keep a small caller-owned index when needed for the reader's task. Separate current claims,
targets and retired documents, and link each current claim to its exact document/source/test
versions and original decision. A later source revision does not change an unchanged claim's
original reason. Also link each change to the documents it actually affects. Preserve the
previous index so both directions remain traceable at the earlier version.

When a current document directs the reader to an index as its evidence, include that index in
the reviewed update boundary. For a small text index, existing baseline bindings and excerpt
replacement can bind its complete contents to the same packet. New bindings require a reviewed
baseline through bootstrap. Review the complete result, including retained references, before
application. Keep target and retired entries out of current-behavior results.

## 3. Verify the resulting boundary

Use [implementation continuation](implementation.md) for goal-version verification and returned
results. After the chosen document route finishes, compare actual changed and preserved hashes,
source/baseline, index and completion receipt with the frozen expectations. Trace a current
claim back to its original evidence and reason, and a change forward to affected documents.
The caller performs this semantic comparison; CLI file checks do not establish complete impact.

An unexpected difference or stale reference keeps completion pending. Preserve the actual
failure and use the existing repair or successor route. Report the reviewed source and goal
versions, remaining differences and the tested environment separately from deployment.
