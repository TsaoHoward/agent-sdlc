# D-007: Gitea Issue Comment Command Design

## Purpose
This document analyzes the next detail decisions needed after choosing `Gitea issue comment command` as the first trigger path.

It does not replace the decision backlog entry. It is the supporting analysis document for the active near-term trigger-design decisions.

## Scope
This document covers:
- command syntax shape
- trigger authorization boundary
- how much free-form instruction content should be allowed in the first command format

It does not cover:
- lower-level webhook implementation details
- exact task gateway code
- broader multi-trigger support

## Background
The repository has already chosen:
- first forge target: `Gitea`
- first trigger family: `issue comment command`

That decision narrowed the intake path, but the actual command contract is still open. Without a concrete trigger command design, the first adapter still has avoidable ambiguity.

## Reference Pattern: GitHub Copilot
As of 2026-04-14, GitHub's documented interaction model is not one single universal comment syntax.

Instead, GitHub uses multiple surface-specific patterns:
- issue initiation can happen by assigning an issue to Copilot
- PR iteration can happen by mentioning `@copilot` in pull request comments
- other entry points can accept direct free-form prompts in chat, dashboard, CLI, or similar surfaces

This matters because it suggests:
- `@copilot` is not the whole product contract
- free-form prompts work best when the interaction surface already gives strong context
- a first issue-comment trigger for Gitea does not need to mimic PR-comment iteration exactly

## Re-Evaluation Summary
If the goal is to imitate GitHub Copilot's overall user experience, there are two different interaction styles to consider:

### Style 1 - Start Work From A Narrow, Explicit Trigger
Best fit for:
- issue comments
- low-ambiguity intake
- first closed loop implementation

Characteristics:
- explicit action syntax
- easier policy mapping
- better auditability

### Style 2 - Iterate On Existing Work With Free-Form Review Comments
Best fit for:
- pull request follow-up
- already-bounded review context
- later-phase refinement flows

Characteristics:
- more natural language
- lower user friction
- more context already provided by the existing PR

## Implication For This Project
For a Gitea-based Phase 1, the safest interpretation is:
- keep `issue comment` initiation explicit
- reserve `mention + freer prompt` as a likely future pattern for PR follow-up rather than the first intake path

This is closer to GitHub's actual multi-surface behavior than forcing one comment style to do everything.

## Goals
- make human intent explicit
- keep parsing simple for the first adapter
- avoid hidden policy inside natural-language comments
- preserve room for later expansion without breaking the first contract

## Non-Goals
- supporting every future task class expression
- designing a full chatops language in Phase 1
- allowing the comment itself to become the only durable policy source

## Decision Surface A: Command Syntax Shape

### Option A1 - Minimal Slash Command With Task Class
Example:

```text
/agent docs_update
```

Pros:
- easy to parse
- low ambiguity
- easy to audit

Cons:
- weak room for reviewer-visible intent
- too little structured context for many useful tasks

### Option A2 - Verb-Based Command With Required Task Class
Example:

```text
/agent run documentation_update
```

Pros:
- explicit intent and action
- clearer for humans scanning issue threads
- extensible if future verbs are added

Cons:
- slightly more verbose than the minimal form

### Option A3 - Structured Block Payload
Example:

```text
/agent
task_class: documentation_update
summary: refresh architecture notes
```

Pros:
- highly extensible
- easy to attach more fields later

Cons:
- heavier for the first loop
- more parsing surface than Phase 1 needs

### Option A4 - Mention Plus Explicit Command
Example:

```text
@agent run documentation_update
```

Pros:
- feels closer to GitHub-style conversational invocation
- still keeps an explicit task-class token
- easy to extend later for PR-comment iteration

Cons:
- mention syntax is mostly cosmetic unless the platform gives it special semantics
- slightly more coupled to social/chat style conventions

### Selected Direction
Choose `Option A4 - Mention Plus Explicit Command`.

Recommended baseline form:

```text
@agent run <task-class>
```

Rationale:
- keeps the command short and more human-friendly
- preserves explicit task classification
- stays closer to a mention-driven interaction style

## Decision Surface B: Trigger Authorization Boundary

### Option B1 - Any Commenter
Pros:
- lowest friction

Cons:
- too permissive
- unsafe for the first loop

### Option B2 - Trusted Repository Members Only
Pros:
- aligns with explicit human intent
- keeps trust simple for Phase 1
- avoids a full approval-on-every-comment model

Cons:
- requires a clear definition of trusted membership

### Option B3 - Any Commenter With Separate Approval Step
Pros:
- more flexible

Cons:
- adds coordination complexity too early

### Selected Direction
Choose `Option B1 - Any Commenter`.

Rationale:
- repository access and contribution controls are managed by the forge and repository owner
- important branch outcomes should still be guarded by human review and repository protection controls
- this keeps the first trigger path simpler and lower-friction

Phase 1 should therefore not require a separate trigger-time trusted-membership gate inside the command contract itself.

## Decision Surface C: Free-Form Instruction Handling

### Option C1 - Task Class Only
Example:

```text
/agent run documentation_update
```

Pros:
- safest parsing model
- strongly policy-driven

Cons:
- too restrictive for practical issue-driven work

### Option C2 - Task Class Plus Short Free-Form Summary
Example:

```text
/agent run documentation_update
summary: update roadmap wording for Phase 1
```

Pros:
- keeps task class explicit
- allows useful human intent
- still bounded enough for Phase 1

Cons:
- requires a small second-line convention

### Option C3 - Fully Free-Form Natural Language Command
Example:

```text
/agent run please review the architecture docs and fix anything inconsistent
```

Pros:
- flexible for users

Cons:
- turns parsing and policy classification into hidden AI behavior
- weak auditability

### Recommended Direction
Choose `Option C2 - Task Class Plus Short Free-Form Summary`.

Recommended first command shape:

```text
@agent run <task-class>
summary: <short human intent>
```

The `summary:` line should be optional for strictly template-like tasks, but recommended for most practical tasks.

Additional constraint:
- free-form input must stay bounded
- the first command format should impose a maximum allowed summary length
- the command should not expand into an unbounded multi-line prompt surface

## Combined Recommendation
For Phase 1, the recommended trigger command design is:

```text
@agent run <task-class>
summary: <short human intent>
```

With these rules:
- trigger authorization relies on normal repository access controls rather than a separate trusted-member gate in the command contract
- `task-class` must be one of the policy-recognized task classes
- the optional `summary` is bounded human intent, not a replacement for policy
- additional lines should be ignored or rejected until explicitly supported
- important branch outcomes should still depend on human review and repository protection controls

This recommendation is an inference from the GitHub docs pattern, not a direct copy of one GitHub command contract.

It tries to combine:
- GitHub-like mention-driven ergonomics
- explicit task classification for policy clarity
- bounded free-form intent for human usability without allowing unbounded prompt growth

## Open Questions
- what exact list of task-class tokens should be user-facing in the first command?
- what exact maximum length should apply to `summary:`?
- should `summary:` be optional or required for some task classes?
- should malformed extra fields fail closed or be ignored with a visible warning?
- should issue comments and later PR comments intentionally use different interaction styles?
