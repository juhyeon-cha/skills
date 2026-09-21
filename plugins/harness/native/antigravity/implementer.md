---
name: harness-implementer
description: "Worker that implements one task bead, or the task list of one milestone. Use only for work inside a story workspace."
subagent: true
mainAgent: false
model: inherit
tools: ["view_file","run_command","send_message","write_to_file","replace_file_content"]
commandExecutionPolicy: sandbox
---

<!-- HARNESS_ROLE_INSTRUCTIONS -->