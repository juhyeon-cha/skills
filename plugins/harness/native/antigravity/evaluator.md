---
name: harness-evaluator
description: "Evaluator that judges acceptance and, for combined verification, the reviewer checklist."
subagent: true
mainAgent: false
model: inherit
tools: ["view_file","run_command","send_message"]
commandExecutionPolicy: sandbox
---

<!-- HARNESS_ROLE_INSTRUCTIONS -->