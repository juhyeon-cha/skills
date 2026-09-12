# Codex subagents: invocation, hook identity and models

Verified against official OpenAI documentation and Codex CLI 0.154.0 on 2026-09-12.

## Documented invocation

[Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents) defines
custom agents in project `.codex/agents/*.toml` or user `~/.codex/agents/*.toml`.
The required fields are `name`, `description`, and `developer_instructions`.
Model and reasoning can be selected in the agent file, explicit spawn options,
or `[agents]` defaults. The custom-agent file wins; global defaults should not be
rewritten to implement a role-specific choice.

Harness generates these files with `scripts/roles.mjs register codex` and verifies
their receipt. A current collaboration tool with no native role selector cannot
prove native agent invocation by merely mentioning a custom name in its prompt.
Use the explicitly selected generic contract in that case; no automatic fallback.

## Actual identity boundary

[Hooks](https://learn.chatgpt.com/docs/hooks) supplies a subagent identifier and
type, with the parent's session ID. It does not promise that the identifier is
the path returned by `collaboration.spawn_agent`. The 2.3.2 live run supplied a
UUID and `default`, while the tool returned `/root/<name>`.

[App Server](https://learn.chatgpt.com/docs/app-server) documents metadata-only
`thread/read` and generation of a schema matching the installed CLI. The 0.154.0
schema includes `source.subAgent.thread_spawn.parent_thread_id`, `agent_path`,
and `agent_role`. An actual read of the previously blocked child confirmed its
UUID, exact tool path and parent. The guard verifies those fields before applying
the existing delegation inventory rules. No timing match or rollout parsing is
used. Missing optional metadata fails closed, including on remote-only state.

## Model decision

[Models](https://learn.chatgpt.com/docs/models) describes Terra as balanced and
lower-cost, Sol as suited to complex coding. The selected policy lives in
`plugins/harness/lib/runtime/role-models.mjs`: reviewer Sol/high, evaluator
Terra/medium, implementer parent inheritance. Claude evaluator retains Sonnet.
Ambiguous acceptance or conflicting evidence should return a decision request;
an explicitly approved escalation can use Sol/high. No token-saving ratio or
quality equivalence to Sonnet has been measured.

A real bounded subagent was spawned with explicit Terra/medium and no history
fork. App Server metadata confirmed the same model and effort and the exact
tool path. Its short model-policy response is a configuration smoke test, not a
Harness review or acceptance verdict. Thread metadata reports current configured
or latest persisted settings, not per-turn execution telemetry.

## Verification boundary

`generic-hook-check.mjs` covers UUID/default metadata, wrong parent/path/profile,
unavailable metadata, terminal calls and grader write denial. The transport test
checks the read-only handshake and protocol failure paths. Registration tests
verify generated role model/effort and unchanged Claude source ownership.
Those fixtures do not establish activation of the changed installed hook. A
fresh live child must still reach its first tool using the updated artifact before
claiming that the original runtime execution failure is resolved.
