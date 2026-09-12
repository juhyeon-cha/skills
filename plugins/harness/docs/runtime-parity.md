# Runtime parity contract

`lib/runtime/parity-contract.mjs` owns the required semantic inventory. This is an
implementation contract for Claude CLI, Codex CLI and desktop, and Antigravity
CLI on macOS. The table describes required capabilities, not released support.
An adapter must establish an observed native or harness implementation path for
every cell. A prompt describing a policy does not establish its enforcement.

Official provider documentation governs native integration: [Claude memory](https://code.claude.com/docs/en/memory),
[hooks](https://code.claude.com/docs/en/hooks), [permissions](https://code.claude.com/docs/en/permissions)
and [agents](https://code.claude.com/docs/en/sub-agents);
[Codex configuration](https://learn.chatgpt.com/docs/config-file/config-basic),
[instructions](https://learn.chatgpt.com/docs/agent-configuration/agents-md),
[hooks](https://learn.chatgpt.com/docs/hooks), [security](https://learn.chatgpt.com/docs/agent-approvals-security)
and [agents](https://learn.chatgpt.com/docs/agent-configuration/subagents);
[Antigravity plugins](https://antigravity.google/docs/cli/plugins),
[hooks](https://antigravity.google/docs/hooks), [permissions](https://antigravity.google/docs/cli/permissions)
and [agents](https://antigravity.google/docs/cli/subagents/).
Verify applicability against the invoked version. ECC is only a secondary
architecture reference and does not determine this contract or supported status.

<!-- parity-contract:start -->
| Contract | Required scenarios | Required surfaces | Permitted implementation path |
|---|---|---|---|
| C1: Canonical source | repository, config, instructions, skills, roles | claude-cli, codex-cli, codex-desktop, antigravity-cli | native or harness; observation required |
| C2: Instructions and skills | policy-loaded, skills-discovered, duplicate-rejected, override-omission-rejected | claude-cli, codex-cli, codex-desktop, antigravity-cli | native or harness; observation required |
| C3: Roles and tools | implementer-tools, reviewer-read, reviewer-write-denied, evaluator-tools, author-grader-independent, identity-mismatch-rejected | claude-cli, codex-cli, codex-desktop, antigravity-cli | native or harness; observation required |
| C4: Permission boundaries | worktree-write, main-write-denied, protected-write-denied, remote-canary-denied, malformed-payload-rejected, ambiguous-workspace-rejected | claude-cli, codex-cli, codex-desktop, antigravity-cli | native or harness; observation required |
| C5: Preparation and checks | bootstrap-input, check-input, bootstrap-failure-preserved, check-failure-preserved | claude-cli, codex-cli, codex-desktop, antigravity-cli | native or harness; observation required |
| C6: Ledger and resume | ledger-coordinates, actor-ownership, explicit-rebind, cancel-isolated | claude-cli, codex-cli, codex-desktop, antigravity-cli | native or harness; observation required |
| C7: Stop and completion | unfinished-continued, cancel-respected, error-preserved, resume-bounded, missing-completion-rejected | claude-cli, codex-cli, codex-desktop, antigravity-cli | native or harness; observation required |
| C8: Model policy | parent-inherited, role-selection, explicit-override, unsupported-override-rejected, actual-selection-recorded | claude-cli, codex-cli, codex-desktop, antigravity-cli | native or harness; observation required |
| C9: Installation lifecycle | clean-install, existing-install, user-edits-preserved, managed-policy-preserved, update, stale-rejected, duplicate-rejected, rollback | claude-cli, codex-cli, codex-desktop, antigravity-cli | native or harness; observation required |
| C10: Complete scenario coverage | new-session, resumed-session, updated-session, unrun-rejected, cross-surface-evidence-rejected | claude-cli, codex-cli, codex-desktop, antigravity-cli | native or harness; observation required |
<!-- parity-contract:end -->

## Comparison boundary

Run `node <plugin-root>/scripts/runtime-parity.mjs <canonical-baseline.json> <reports.json>`.
The command reads files, emits a JSON verdict with field-level reasons, and exits
0 for MATCH or 1 for MISMATCH, malformed input, or unreadable documentation.
It does not install, execute a provider, authenticate evidence, or close a task.
Even MATCH returns `liveCertified:false`: independent acceptance still has to
inspect the referenced observations. Documentation disagreement fails rather
than silently changing the required inventory.

The caller obtains the canonical baseline independently of runtime reports:

- `repository`: canonical Git repository identity, resolved before comparing.
- `sourceSha256`: digest of the canonical policy, skills and role source manifest.
- `configSha256`: digest of the repository-owned effective configuration input.
- `contractSha256`: the module's exported `parityContractSha256`.
- `origin`: `fixture` or `live`; never mix them in one comparison.
- `inputs`: every exported `parityScenarioIds` key mapped to its common semantic
  input SHA-256. Product-specific paths, tool names and model IDs are normalized
  by an adapter against this input; they are not required to be identical strings.

Reports are an array with exactly one entry per required surface. Each entry has
`schemaVersion:1`, `surface`, actual `version`, `platform:"darwin"`, `origin`, and
the four canonical identity/hash fields above. `capabilities` contains exactly
C1 through C10, each with `status:"AVAILABLE"`, `mode:"native"` or `"harness"`,
and a nonempty `reference` to the implementation and observation. AVAILABLE is
a caller claim checked for completeness here; adapters and independent review
must verify it. Neither native identity nor an OS sandbox is inferred from a
harness path. UNKNOWN, UNAVAILABLE, missing fields and unknown schema fail.

`scenarios` contains every required scenario key, for example
`C3/reviewer-write-denied`. Each result has `outcome:"MATCH"`, `inputSha256`,
`stages:{static:"MATCH",loaded:"MATCH",live:"MATCH"}`, and
`evidence:{reference,surface,scenario,origin}`. MATCH means the named semantic
expectation occurred: a denied-write scenario requires an actual denial and
absent side effect; a read/write-positive scenario requires its successful
effect. Rejection for missing identity is not reviewer-policy denial. Preserved
failure means the nonzero result remains failure, not successful transport.
The three stages distinguish content, actual loading, and behavior. Synthetic
stage results always retain fixture origin; fixtures cannot certify live use.

Scenario references must retain input, surface and invocation provenance. This
comparison rejects copied surface/scenario labels, missing stages, unexecuted
results and input drift; it cannot detect a falsified observation behind a valid
reference. Collectors must bind references to raw receipts and report missing
evidence as UNREACHED. Keep credentials and private raw logs out of shared reports.

C1 requires the same repository/configuration and instruction/skill/role content;
C2 rejects duplicate or omitted policy. C3 requires all canonical roles and
author/grader independence. C4 uses disposable local bare repositories for remote
canaries, preserving normal approvals. C5 preserves commands, inputs and failures.
C6 explicitly rebinds a new session without importing another session's cancel
or actor ownership. C7 requires bounded continuation and verified completion.
C8 preserves parent inheritance, role selection and explicit overrides, records
actual model selection, and rejects unsupported overrides without substitution.
C9 preserves user and managed settings through installation, update and rollback.
C10 requires new, resumed and updated sessions on every surface. No CLI result
can certify desktop, and no unrun or unsupported scenario can pass.
