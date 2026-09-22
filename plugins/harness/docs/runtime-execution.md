# Runtime execution boundary

The canonical handler is `scripts/hook.mjs`. Claude and Codex retain their
snake_case envelopes. Antigravity's [official hook contract](https://antigravity.google/docs/hooks)
supplies camelCase metadata and native tool arguments. `antigravity-hook.mjs`
maps one mounted workspace, conversation ID, file operations and command cwd
into the existing guard. Multiple workspaces, missing fields and malformed inputs
for known tools fail explicitly; opaque effects remain subject to host permissions. `run_command.Cwd` is observable; Codex's missing shell cwd
is not inferred from a model's prose or hidden process state.

Antigravity guard output uses `decision: allow|deny`. Transport exit zero means
that the JSON decision was delivered, not that the tool was allowed. Shared
policy code two is retained in state and doctor inputs. Malformed input emits
native deny plus an UNREACHED diagnostic; without a valid scope it produces no
successful state observation. Context uses transient `injectSteps` on
PreInvocation. Stop translates shared `block` into native `continue`, retaining
the shared cancellation, actor scope, oracle failure and retry ceiling.
`fullyIdle: false` and provider errors cannot establish completion. No native
subagent lifecycle event is manufactured from a conversation ID.

## Initial Antigravity parent registration

Parent registration is an optional identity/audit mechanism. Without enrollment,
ordinary local execution remains available under common protections; unresolved
identity retains child-scoped restrictions for recognized remote effects.
An operator uses the real provider-returned conversation ID and checks that its
context observation belongs to the intended workspace and loaded artifact.
Outside that Antigravity agent's tool stream, run:

```text
node "<loaded-plugin>/scripts/state.mjs" --data "<observed-data>" parent-register antigravity "<workspace>" "<conversation-id>" "<source-hash>"
```

`<observed-data>` comes from HARNESS_STATE_JSON; source hash is the `hash` field
from `node "<loaded-plugin>/scripts/distribution.mjs" check "<loaded-plugin>"`.
Registration requires a
successful PreInvocation observation, exact session/workspace and current
source hash. The executable wrapper records its own artifact root/hash and
workspace with that observation; provider payload source fields are ignored.
Operator attestation establishes the parent claim, not executable provenance.
Observations from another artifact, an earlier source or another worktree do
not qualify. A changed source or conflicting record fails; do not overwrite a
conflict to make diagnosis pass. A fresh, verified session can be registered
after an update. This external step prevents a circular requirement that the
unidentified agent authorize itself. The attested parent can use the explicit `state.mjs bind`/`cancel` workflow. An actor
binding alone never certifies parent identity.

The attestation is a local workflow trust boundary, not protection against a
malicious process with the same OS account. Agent tool enrollment is denied.
Direct protected configuration/state writes are denied; authorized common
commands retain their existing effects. Arbitrary shell effects remain limited
by the guard's documented static analysis; this is not an OS sandbox.

The resolver can recognize externally attested parents and bound children.
For child registration, READY/START activation and completion evidence, follow
[Runtime role execution](runtime-roles.md).
Unavailable optional identity evidence is not a blanket denial of ordinary work.
An audit that requires that evidence still reports it as unavailable.

## Evidence limits

The execution fixture compares allowed worktree writes, denied main/protected
writes and remote canaries for the same synthetic implementer role. Parent
remote authorization remains the existing human/cycle procedure; the adapter
adds no implicit grant or approval store. The bare remote receives no writes.
Bootstrap/check run through the common config runner and preserve argv,
stdout and failing status. Stop fixture actors are explicitly synthetic.

Actual runtime startup, trust, hook firing, native roles and all Codex desktop
and CLI surface observations remain separate acceptance evidence. A fixture
pass, parent attestation or transport exit alone cannot establish full parity.
