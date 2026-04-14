# ADR-0003: Phase 1 Runtime Egress and Secret Defaults

- Status: Accepted (Phase 1 implementation baseline)
- Date: 2026-04-14

## Context
ADR-0002 established the first runtime isolation strategy as an ephemeral container per task/session and described a restricted network posture opened only as needed.

The remaining open question was the default network and secret posture for the first implementation profile.

For the first closed loop, the project needs a practical default that:
- keeps the runtime boundary explicit
- allows early implementation without building a full egress-control system first
- preserves a stricter secret posture even if network posture is temporarily loose

This decision changes the default runtime egress assumption previously described in ADR-0002 and related design notes.

## Decision
For the initial Phase 1 implementation profile:

1. Runtime network egress is broadly allowed by default.
2. Secret injection remains minimal and profile-specific.
3. This is treated as a temporary implementation convenience, not as the desired long-term isolation posture.

## Decision Details

### Network Default
The initial runtime profile may reach external network destinations needed by the session without a strict destination allowlist.

This does not remove the runtime boundary. It only relaxes the first egress policy.

### Secret Default
Even with broad egress, secrets remain constrained:
- no secret injection unless the selected profile requires it
- inject only the minimum credentials required by the workflow
- do not assume that all sessions are allowed to receive forge or other credentials

### Review Trigger
This decision should be revisited before:
- enabling higher-risk task classes
- supporting multi-tenant execution
- moving beyond the first narrow closed loop

## Rationale

### Why Broad Egress Was Chosen
- reduces friction during the first implementation path
- avoids blocking Phase 1 on a more detailed network-enforcement subsystem
- keeps early runtime work focused on task/session isolation rather than egress tooling

### Why Secret Minimization Still Holds
- network reachability and credential reachability are different risks
- retaining minimal secret injection prevents the runtime from becoming broadly privileged too early

## Consequences

### Positive
- simpler first runtime scaffold
- fewer near-term blockers for dependency installation or remote fetches
- clearer separation between egress control and secret control

### Negative
- weaker isolation than the previously preferred posture
- greater risk if a session runs untrusted or overly broad commands
- future tightening work becomes mandatory rather than optional

## Follow-Up
This ADR should lead to:
- runtime profiles that make secret access explicit
- a later decision on destination allowlists or narrower egress control
- a clear review before broader task classes or stronger automation are enabled
