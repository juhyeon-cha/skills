# Runtime parity: M0 evidence and implementation paths

Task: skills#300, story: skills#298. The exact official-document check date, probe dates and source baseline are recorded in [the evidence receipt](runtime-parity-receipt.json), under `verification`. Repository document-audit rules prohibit dated measurement lines in Markdown; the structured receipt preserves that required provenance without changing the gate.

## Evidence priority and scope

Official product documentation defines the provider contract. Observations establish which parts actually apply to the installed version and invocation. ECC is a secondary architecture reference; no capability or acceptance below is established from ECC.

This is prerequisite evidence for implementation, not final parity certification. `OBSERVED` means the named probe reached its observation; `UNREACHED` is not a pass. A documented implementation path can justify M1–M4 work without pretending that M5 has run. If an evaluator finds a required path absent or unestablished, M0 is `DEVIATION` and its dependent work must stop.

The proposed paths below use documented provider interfaces and the repository's common core. No product-level absence was established. Current installation differences and an unregistered diagnostic child caused concrete failures; they are not evidence that the provider lacks hooks or subagents. Full C1–C10 parity remains unverified.

## Installed execution surfaces

| Surface | Actual version / observation | What it establishes |
|---|---|---|
| Claude Code CLI | `claude --version`: `2.1.269` | Native CLI probes below; not Claude desktop/IDE certification |
| Codex CLI | `codex --version`: `0.154.0` | Standalone macOS aarch64 CLI; separate from desktop |
| Codex desktop | `26.908.40834`, build `8881`, bundle identifier `com.openai.codex` | Parent observed running Codex Renderer/Service in ChatGPT.app and read its plist; `codex doctor --json` independently reported the same app version and successful desktop app-server handshake |
| Antigravity CLI | `agy --version`: `1.2.2` | macOS CLI with explicit `--add-dir` and `--sandbox`; not Antigravity desktop/IDE certification |

Claude's default-profile auth probe returned `M0_AUTH_OK`, `is_error:false`, rc 0. The older `oauth_org_not_allowed` condition recorded in skills#268 was not reproduced. This does not close that story's broader live acceptance.

The same default-profile response exposed installed harness `2.3.3` in its Stop guidance. Codex `/hooks` showed the installed harness `2.3.5` command as trusted. This is an actual C1/C9 installation discrepancy. No installed artifact was edited or updated. Claude's auth probe also received an unrelated in-progress-work Stop continuation; subsequent Claude provider probes used explicit fixture settings to avoid that existing ledger interaction. The auth probe was instructed not to call tools and did not claim or close work.

## Official contracts checked

All links in this section were opened as official page bodies during M0, not accepted from search snippets. Current documents can describe behavior beyond the installed build; discrepancies stay visible below.

| Provider | Contract and implementation consequence | Primary source |
|---|---|---|
| Claude | CLAUDE.md can import AGENTS.md; policy need not be copied into divergent bodies. Ancestor/local instructions also affect the effective input. | [Memory](https://code.claude.com/docs/en/memory) |
| Claude | Hooks expose session, tool, subagent and Stop events. `agent_type` and `agent_id` are native identity evidence; `SubagentStart` itself cannot prevent spawning. | [Hooks](https://code.claude.com/docs/en/hooks) |
| Claude | Custom agents select tools and model; plugin agents ignore `permissionMode`, `hooks`, and `mcpServers`. Per-invocation model selection and managed substitutions require actual-value verification. | [Subagents](https://code.claude.com/docs/en/sub-agents) |
| Claude | Deny/ask/allow and tool restrictions provide permission boundaries. Role instructions alone do not establish enforcement. | [Permissions](https://code.claude.com/docs/en/permissions) |
| Codex | AGENTS.override.md/AGENTS.md discovery, ordered scope, and size limits can omit or override required instructions. | [AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md) |
| Codex | Project `.codex` layers require project trust. CLI/project/profile/user/managed layers are distinct; a file's presence does not establish effective configuration. | [Config basics](https://learn.chatgpt.com/docs/config-file/config-basic) |
| Codex | Hooks merge across active sources; changed non-managed definitions require hash-specific trust. `/hooks` is the supported review UI. Tool denial, native subagent identity and Stop continuation are documented. | [Hooks](https://learn.chatgpt.com/docs/hooks) |
| Codex | Standalone custom-agent TOML supports `name`, `description`, `developer_instructions` and session settings including `sandbox_mode`. Agent-file model values can outrank explicit spawn values. | [Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents) |
| Codex | Approval policy and OS sandbox are separate controls. A denied action must not be retried by escalating out of the selected sandbox. | [Approvals and security](https://learn.chatgpt.com/docs/agent-approvals-security) |
| Antigravity | Workspace `.agents/rules` and global GEMINI.md have activation/scope rules. The local always-on diagnostic rule loaded in CLI 1.2.2. | [Rules](https://antigravity.google/docs/rules-workflows) |
| Antigravity | CLI plugins have their own manifest/install layout; localized rules, skills, hooks and agents are supported. No ECC adapter is necessary to establish these capabilities. | [CLI plugins and skills](https://antigravity.google/docs/cli/plugins) |
| Antigravity | PreInvocation injects context; PreToolUse receives camelCase tool calls and can deny; Stop supplies conversation/workspace identity and idle state. A continuation is an explicit decision. | [Hooks](https://antigravity.google/docs/hooks) |
| Antigravity | Native resource permissions distinguish read/write/command and apply deny before ask before allow. Workspace file reads are auto-allowed; shell execution is a separate permission. | [CLI permissions](https://antigravity.google/docs/cli/permissions) |
| Antigravity | Custom agents have tool/model/execution fields; unknown tool names have a documented validation problem. Child lifecycle is asynchronous. | [Subagents](https://antigravity.google/docs/subagents), [CLI subagents](https://antigravity.google/docs/cli/subagents/) |
| Antigravity | Headless JSON status alone is insufficient; stream-json provides tool/step observations and headless approval behavior differs from interactive use. | [Headless mode](https://antigravity.google/docs/cli/headless/) |

## Disposable probes and actual outcomes

The local evidence bundle contains `run.mjs`, exact argv/cwd in each `invocation.json`, fixtures, hook definitions, `stdout.log`, `stderr.log`, `exit.json`, and event JSONL. Private paths and runtime identities are deliberately excluded from this committed document. Bundle name: `harness-runtime-parity-m0-skills300`; the orchestrator retains its local location. The [hash receipt](runtime-parity-receipt.json) binds the referenced logs without publishing their contents. This receipt is an integrity pointer, not an independent grader or authenticated attestation.

All probes below exited 0. That exit is transport completion, not acceptance success: the failed Codex controls also exited 0.

| Local run directory | Conditions and reached observations | Limits |
|---|---|---|
| `claude-auth/` | Default user profile, no tools; model invocation succeeded | Installed legacy Stop guidance interacted with existing ledger state; not an isolated parity test |
| `claude-fixture/` | Explicit fixture settings, `--setting-sources project`, `dontAsk`, only Read/Agent; child read succeeded, native start/tool/stop IDs matched; canary denied once; instruction and SessionStart markers returned; Stop continued exactly once | Provider fixture, not proof that the installed harness loaded its latest distribution. No reviewer-write or full role acceptance claimed |
| `agy-fixture/` | Local `.agents`, explicit workspace, sandbox; allowed `view_file` reached PostToolUse with no error, canary hard-denied once; rules/context markers returned; Stop execution 0→1, idle true, then allowed exit | Shell-command approval not tested by this read-file success |
| `agy-role/` | `agy --add-dir <fixture> agents` listed `m0-reader`; native invocation named its TypeName; returned child ID correlated with child read events, parent-directed message and child idle Stop | No native SubagentStart/Stop event invented. Hook envelopes do not carry role/parent fields. See correlation boundary below |
| `codex-fixture/` | Ephemeral session before explicit project trust: AGENTS marker and main file read succeeded; canary read incorrectly succeeded; agent reported session-thread-not-found | No fixture events existed. This is a failed loading control, not a successful deny test or provider limitation |
| `codex-persistent/` | Separate persistent invocation after making fixture its own Git root, still before project trust: read succeeded, custom role unavailable | Persistence alone did not establish role loading. No second canary read attempted in this control |
| `codex-trusted/` | After official project/hook review: main read succeeded; canary denied once; instruction/context markers returned; native `m0-reader` start/stop IDs arrived; Stop continued once and finished | Child read was blocked by the installed harness's unidentified-role guard; it remains UNREACHED, not a read-success |

### Codex trust and role failure attribution

The first TUI `/hooks` inspection listed two active PreToolUse sources: the existing user hook and harness plugin. The diagnostic project hook was absent. A subsequent TUI start in the independent Git fixture displayed the official project-trust prompt. Trusting that fixture exposed six new project hooks. `/hooks` showed each affected event with installed 3 / active 2 / review 1. The reviewed diagnostic source and command matched the prepared fixture; there were no other new sources. The supported UI trust action produced installed 3 / active 3. No bypass flag or manual trust-database edit was used, and existing hooks remained enabled.

The trusted run's child Read-equivalent shell call failed with:

```text
GUARD-DENY: UNREACHED — 판정에 도달하지 못했다: child role is unidentified
```

`m0-reader` was a provider diagnostic role, not one of the installed harness's registered roles. Native role and instance IDs were present. The blocked operation was not retried with a new command or identity. The implementation path is to connect the canonical roles and their invocation receipts to the existing role contract and guard mapping in M4, then validate allowed reads and denied writes in M5. Native identity delivery is observed; allowed child reads through that completed harness mapping are not.

The independent-root/trust change and removal of `--ephemeral` were not an isolated A/B test of the session-thread-not-found error. Its exact cause is unproven; this report does not attribute it solely to ephemeral mode.

### Antigravity identity and model boundaries

The parent `invoke_subagent` call contained `TypeName: m0-reader`. Its native result supplied a child conversation ID. That ID matched child hook envelopes and the sender of the completion message. Parent Stop events with `fullyIdle:false` preceded child completion. This is an observable alternative to native SubagentStart/Stop for a version-bound adapter.

The correlation requires the actual native invocation result, known workspace and invocation ownership, plus the matching child's tool and completion events. A role marker in assistant prose or `send_message` alone is insufficient. The observed transcript representation is not treated as a stable provider API; prefer the documented stream-json tool/step surface and fail closed when native return correlation cannot be established. M4 must reject forged/missing/mismatched correlations. Such adversarial checks did not run in M0.

The agent declared only `view_file` but also used `send_message`. Therefore the frontmatter tool list was not measured as an exhaustive inventory. M4 must apply the shared guard policy to all observed tools and prove rejected write attempts rather than assume that list alone creates read-only enforcement.

Observed Antigravity `terminationReason` was `NO_TOOL_CALL` and `transcriptPath` ended in `transcript_full.jsonl`, unlike examples on the hooks page. Dispatch must use supported semantic fields, tolerate recorded reason strings deliberately, and consume the provided path rather than reconstruct a filename. Model observations included `gemini-3.8-flash-high`; Claude output included its actual model-usage IDs. Cross-product model-name equivalence was not inferred.

## C1–C10 implementation paths and remaining acceptance

All source paths below are repository-relative. They are implementation seams, not claims that Antigravity is already implemented.

| ID | Evidence / classification | Concrete path for follow-up | Still required before full parity |
|---|---|---|---|
| C1 canonical source | Installation discrepancy observed: Claude harness 2.3.3 vs Codex 2.3.5 | Extend `plugins/harness/lib/distribution.mjs` source/hash receipts and role projections to all runtimes, rooted at the same repository-owned configuration | Same-version/hash installs in every required surface; stale-cache negative control |
| C2 instructions/skills | CLI instruction/context markers observed in all three; official loading paths exist | Project policy references plus runtime-specific skill/distribution metadata; effective-source/duplicate/override checks | All nine actual skills loaded, mandatory policy not truncated or overridden; desktop-specific loading evidence |
| C3 roles/tools | Claude native child read and identity observed; Codex native IDs observed but child read UNREACHED from missing harness mapping; AG native return/child event correlation observed | `lib/runtime/roles.mjs`, `role-contract.mjs`, `delegation.mjs` and `lib/guard/hook-event.mjs`; add AG correlation, use canonical registered roles and enforce guards | Three canonical roles; positive read and negative write; author/grader independence; forged/missing identity rejection. Desktop generic prompt-only delegation is not enforced role isolation |
| C4 permission boundary | Main allowed read + hard deny observed on all three trusted fixtures; provider permission interfaces documented | Normalize native tool inputs/results to shared policy; preserve OS sandbox and approvals; project trust is an explicit prerequisite | Allowed worktree writes, denied main/protected writes and local-bare remote canaries; shell permissions and desktop boundary tests |
| C5 preparation/check | Repository `.harness.json` and `scripts/config.mjs` provide shared execution boundary; Git/Node present | Reuse one structured config runner and workspace preparation result; provider shell permission must permit precisely those operations | Same input/exit propagation and failed-bootstrap/failed-check controls in all runtimes |
| C6 ledger/resume | Shared `scripts/ledger.mjs` / `lib/runtime/state.mjs` already separate backend from runtime; session/conversation IDs observed | Add AG runtime identity and explicit rebind into the same state/ledger contract; never derive ownership from another session | Environment-switch rebind, actor ownership and cancellation isolation; no live cross-runtime ledger mutation tested here |
| C7 Stop/completion | One bounded continuation observed on all three CLI fixtures; AG parent busy/child idle also observed | Convert native Stop input/output into shared `lib/runtime/stop.mjs` semantics with persistent per-session recursion/cancel bounds | Error/cancel/limit paths, child-result evidence and actual close gates; desktop Stop verification |
| C8 model policy | Official products have different precedence; actual selected model is observable in provider outputs/events | Resolve common inheritance/explicit override before emitting a role; verify actual selection; prevent runtime fallback from silently satisfying the contract | Inheritance, explicit supported/unsupported override controls in each surface; no cross-model equivalence claim |
| C9 lifecycle | Official install/discovery paths exist; Codex project+hook trust prerequisite reproduced; current version drift observed | Ownership/hash receipts, non-destructive projections, exact trust review, conflict/drift/rollback diagnostics | Clean/existing install, update, rollback and duplicate/stale-hook tests; preserve all unrelated user settings |
| C10 final verdict | Failed rc-0 controls demonstrated why transport success is insufficient | Same scenario/result vocabulary with separate static/loaded/live and surface columns; aggregate only reached expected outcomes | M5 three-environment run and independent evaluator; M0 does not certify final parity |

### Desktop direct observations and policy path

The current desktop collaboration spawn schema exposes task name, message, model, reasoning effort and history options, but no custom-role selector. The parent found no native registration directory at the inspected user/project scopes. Official [Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents) documentation describes local custom TOML agents and desktop delegation; that does not establish native selection in this provider. It also says live parent permission overrides are reapplied to children. A custom file alone therefore cannot prove the effective sandbox. Native role loading remains UNREACHED on this desktop surface; no internal metadata was edited to manufacture it.

The following observations came from this desktop conversation and its actual child tools, not a CLI model subprocess. Local evidence filenames and hashes are in the receipt's `desktop-followup` entry.

| Contract | Direct observation | Boundary |
|---|---|---|
| C2 session instructions | The parent received the developer-context `Harness session context` block, installed artifact version 2.3.5 and `HARNESS_STATE_JSON` | Not a fresh nonce fixture, all-skills discovery, or override/truncation test |
| C3/C4 role policy | An independent managed reviewer read the evidence document with rc 0, then submitted one disposable canary creation through `apply_patch`. PreToolUse rejected it with the reviewer-specific file-modification prohibition; the parent observed `r_grader_write` in the guard log. Child and parent existence checks returned rc 1: no canary file | This demonstrates that particular local harness policy boundary, not provider-native role identity or an OS read-only sandbox |
| C3 completion/independence | The parent bound the actual provider-returned child and consumed its completed response through generic delegation complete, rc 0, OBSERVED. The call excluded both implementation authors | The diagnostic LGTM is not code review or task MATCH. Prompt-only/native-evidence-unavailable labels remain unchanged |
| C7 Stop | After the previous parent final response, the desktop delivered an actual Stop hook continuation prompt about unfinished work. Explicit cancellation returned rc 0 and cancelled true | One continuation delivery and cancellation; not every error, restart or limit scenario. The cancelled state was not manually undone |

The official [Hooks](https://learn.chatgpt.com/docs/hooks) contract describes Stop block as a new continuation prompt, matching the observed desktop delivery. The source connection for role policy is `lib/runtime/codex-identity.mjs` → `lib/runtime/delegation.mjs` → `lib/guard/hook-event.mjs` → `lib/guard/guard.mjs`, all under `plugins/harness/`. The identity resolver uses the documented [App Server](https://learn.chatgpt.com/docs/app-server) initialization and metadata-only `thread/read` boundary. It checks the exact child UUID, parent and canonical child path against active dispatch/binding records before assigning `harness_policy_role`. It does not start/resume a model thread, parse rollout contents or create native role evidence. Missing, mismatched, ambiguous or terminal records are rejected by the existing source contract; adversarial live controls remain required.

Recognized read-only commands intentionally bypass role-dependent lookup. Thus the positive read alone is not role-identity evidence; the reviewer-specific denial, rather than a generic unidentified-role failure, is the relevant observed connection. The local guard does not cover unobserved tools or authenticate same-user state files. Its denial must not be reported as provider-enforced role permissions. This provides a concrete alternative implementation path for the story's responsibility/tool-access/independence semantics while preserving native unavailability. M3–M5 must enumerate required tool paths, exercise allowed implementer writes and denied reviewer/protected/remote actions, and fail any required uncovered scenario. Desktop observations do not certify full C1–C10 parity or replace the independent M0 judgment.

The guard TSV's native-role column is empty (`-`). Its rule row alone omits target and invocation ownership; attribution also requires the actual child response and parent's dispatch/binding observation. The receipt preserves those separate sources. A read-only credential-pattern scan over the local fixture/model/hook evidence bundle returned rc 0, a passing synthetic positive control and no known-pattern matches. It printed no matching values. Counts and scope are recorded in the receipt; this check does not prove absence of every possible secret. Raw evidence remains local.

## Reproduction coordinates and safety limits

Exact prompts and generated hook/agent files are preserved locally with each invocation. Portable command forms (substitute only the fixture paths) are:

```text
claude --version
codex --version
agy --version
claude --print <probe-prompt> --setting-sources project --settings <fixture-settings.json> --agents <fixture-agent-json> --tools Read,Agent --permission-mode dontAsk --no-session-persistence --output-format stream-json --verbose --include-hook-events
agy --add-dir <fixture> --sandbox --print <probe-prompt> --output-format json --print-timeout 60s --log-file <local-cli-log>
agy --add-dir <fixture> agents
codex --no-alt-screen -C <fixture> -s read-only
codex exec --json -C <trusted-fixture> -s read-only <probe-prompt>
codex doctor --json
```

The Codex TUI inspection/review transcript and desktop plist observations are in the parent/tool conversation evidence rather than the subprocess log bundle. `codex doctor --json` returned rc 1 because `TERM=dumb`; its individual auth, provider reachability and desktop handshake checks succeeded. It was not represented as an overall pass.

The diagnostic hook reads stdin JSON, logs fixture events locally, injects a context marker, denies only the named disposable canary, and requests one bounded Stop continuation. It does not invoke a ledger or permit unrestricted commands. Claude's allowed tools were Read/Agent with Bash/Write/Edit explicitly denied. Antigravity granted only its exact fixture read in the diagnostic hook; other calls retained normal permission handling. Codex retained the OS read-only sandbox and all existing hooks.

No account/organization settings, installed harness files, global permission lists or remote configuration were changed. The only configuration additions were Codex's supported UI trust records for the diagnostic project and its six exact hook definitions. An official forget/delete operation for those records was not established; they were not removed by guessing at the trust storage format. Local fixture files are archived outside the worktree after collection, so their project hook file is no longer at the trusted path. Residual trust metadata must not be mistaken for an active installed harness or silently reused for a future fixture.

Raw logs remain local and were not submitted to GitHub. They contain private runtime IDs and paths, so only the sanitized observations and hash receipt are committed. No credential values were intentionally read or logged. The parent scanned the local bundle's log/JSON/JSONL files for known API-token, GitHub-token, Bearer-token and private-key patterns with `rg -l`: rc 1 and no output meant no matches to those patterns, not proof that every possible secret is absent. M1–M5 implementation and tests remain required; the evaluator owns the M0 path-sufficiency verdict.
