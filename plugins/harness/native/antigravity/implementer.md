---
name: harness-implementer
description: "Worker that implements an assigned outcome in a linked worktree, from a standalone request or ledger-backed tasks."
subagent: true
mainAgent: false
model: inherit
tools: ["view_file","run_command","send_message","write_to_file","replace_file_content"]
commandExecutionPolicy: sandbox
---

<!-- HARNESS_ROLE_INSTRUCTIONS -->