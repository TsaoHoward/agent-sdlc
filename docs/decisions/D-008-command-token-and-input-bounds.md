# D-008: Command Token And Input Bounds

## Purpose
This document analyzes the remaining detail decisions for the first Gitea issue comment command.

It follows the higher-level D-007 decision and focuses only on:
- user-facing task-class tokens
- `summary:` length bounds
- malformed input handling

## Background
The repository has already selected the first trigger command shape:

```text
@agent run <task-class>
summary: <short human intent>
```

What remains open is how strict and user-friendly the first command contract should be at the field level.

These choices matter because they determine:
- how easy the command is for humans to remember
- how much ambiguity the task gateway must resolve
- whether malformed commands fail safely and predictably

## Goals
- keep the command easy to type
- keep parsing deterministic
- bound free-form input
- avoid hidden AI interpretation of malformed commands

## Non-Goals
- designing a full command language
- supporting arbitrary multi-line prompt payloads
- allowing task-class meaning to drift away from policy-defined classes

## Decision Surface A: User-Facing Task-Class Tokens

### Option A1 - Full Canonical Tokens
Examples:
- `documentation_update`
- `bounded_code_change`
- `review_follow_up`
- `ci_failure_investigation`

Pros:
- directly aligned to normalized task classes
- no extra alias mapping layer

Cons:
- long and awkward to type
- less human-friendly in comments

### Option A2 - Short Stable Aliases
Examples:
- `docs`
- `code`
- `review`
- `ci`

Pros:
- short and easy to type
- friendly for human operators
- still deterministic if mapped cleanly to canonical task classes

Cons:
- requires an alias mapping layer
- some aliases may become overloaded if too many classes are added later

### Option A3 - Verb-Noun Tokens
Examples:
- `update-docs`
- `change-code`
- `followup-review`
- `investigate-ci`

Pros:
- more descriptive than short aliases
- shorter than canonical tokens

Cons:
- still somewhat verbose
- naming can drift over time

### Recommended Direction
Choose `Option A2 - Short Stable Aliases`.

Recommended Phase 1 alias set:
- `docs` -> `documentation_update`
- `code` -> `bounded_code_change`
- `review` -> `review_follow_up`
- `ci` -> `ci_failure_investigation`

`unsafe_or_high_risk` should not be a user-facing trigger token. It should remain an internal classification outcome used for rejection or escalation.

## Decision Surface B: Summary Length Cap

### Option B1 - 140 Characters
Pros:
- strongly bounded
- easy to scan in issue threads

Cons:
- may be too tight for practical task intent

### Option B2 - 280 Characters
Pros:
- still strongly bounded
- enough room for a practical one- or two-sentence intent
- familiar length expectation for social/comment interfaces

Cons:
- can still be abused if parsing rules are weak

### Option B3 - 500 Characters
Pros:
- more flexibility

Cons:
- starts to blur into free-form prompt territory
- harder to scan and audit

### Recommended Direction
Choose `Option B2 - 280 Characters`.

This preserves bounded intent while keeping the first command practical.

## Decision Surface C: Malformed Input Handling

### Option C1 - Fail Closed
Behavior:
- reject malformed commands
- provide visible feedback
- do not attempt partial interpretation

Pros:
- safest
- easiest to reason about
- avoids hidden AI interpretation

Cons:
- slightly less forgiving for users

### Option C2 - Ignore Unknown Lines, Use What Parses
Behavior:
- parse recognized fields
- ignore the rest

Pros:
- lower friction

Cons:
- easy to hide ambiguity
- weak auditability

### Option C3 - Soft Warning With Partial Execution
Behavior:
- attempt execution if core fields parse
- warn about invalid extras

Pros:
- more forgiving

Cons:
- still allows ambiguous execution
- complicates policy clarity

### Recommended Direction
Choose `Option C1 - Fail Closed`.

Phase 1 should reject malformed commands and return visible guidance rather than guessing user intent.

## Combined Recommendation
Recommended Phase 1 command contract detail:

```text
@agent run <task-token>
summary: <up to 280 characters>
```

With these rules:
- `<task-token>` must be one of `docs`, `code`, `review`, or `ci`
- `summary:` is required for `code` and `ci`
- `summary:` is optional for `docs` and `review`
- `summary:` must be at most 280 characters when present
- malformed commands fail closed with visible guidance
- extra unsupported fields are treated as malformed input rather than ignored silently
- aliases should be accepted case-insensitively and normalized to lowercase before policy lookup
- visible failure guidance should use a standard rejection comment template so parse failures are consistent and auditable

## Selected Phase 1 Defaults
- token aliases: `docs`, `code`, `review`, `ci`
- token parsing: case-insensitive, normalized to lowercase
- summary requirement: required for `code` and `ci`, optional for `docs` and `review`
- summary bound: 280 characters
- malformed-input behavior: fail closed
- operator feedback: standard visible rejection comment template
