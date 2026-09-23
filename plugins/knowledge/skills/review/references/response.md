# Review response

Copy the exact packet ID and plan ID from input. Return this JSON shape with no extra keys:

```json
{"packet":"<packet ID>","plan":"<plan ID>","verdict":"pass",
 "checks":{"source_fidelity":"pass","decision_coverage":"pass","reader_action":"pass","uncertainty":"pass"},
 "findings":[]}
```

Verdicts are pass, revise or blocked. Each of the four check values is pass, fail or unverified.
Findings is an array of nonempty strings describing concrete defects/missing evidence. A pass
requires all checks to pass and no findings. If the packet or plan ID is missing, ask the caller
for the complete packet; do not invent an ID. Revisions change packet identity and require review
of the new complete packet. The response is an actual review record, not a cryptographic signature.
