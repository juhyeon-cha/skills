# Runtime configuration: source references

Official documentation is the primary design reference; ECC is secondary. These references were checked during skills#300. Historical probe results and their limitations remain in skills#300 and skills#310 and in Git history. Full cross-runtime equivalence has not been established.

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
