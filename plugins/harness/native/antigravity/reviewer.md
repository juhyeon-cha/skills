---
name: harness-reviewer
description: "Supervisor that reviews the code quality of a task's changes. Does not compare against completion criteria."
subagent: true
mainAgent: false
model: inherit
tools: ["view_file","run_command","send_message"]
commandExecutionPolicy: sandbox
---

<!-- HARNESS_ROLE_INSTRUCTIONS -->