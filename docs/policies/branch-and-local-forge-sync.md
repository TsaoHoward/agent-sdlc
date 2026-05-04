# Branch And Local Forge Sync Policy

## Purpose
This document defines the repository rule for proposal-branch naming, branch-content sourcing, and local-forge synchronization during Phase 1.

It standardizes the branch behavior that the current proposal and CI path already depends on, so that this knowledge does not remain only in testing notes or shell history.

## 1. Core Rule
For the current Phase 1 proposal path, branch content must come from the forge target repository and target branch, and the local forge's seeded default branch must stay aligned with the workspace commit that is under test.

Do not treat proposal-branch correctness as "normal feature branch hygiene" only. In the local seeded-forge workflow, stale forge content can invalidate CI and proposal behavior even when the operator's workspace branch looks correct locally.

## 2. Current Phase 1 Branch Model
The repository currently has:
- one canonical shared default branch: `main`
- one proposal-branch convention for agent-created work: `agent/<task_request_id>`
- local maintainer workspace branches as implementation detail, not as a separately governed long-lived branch tier

The repository does not currently define:
- a `develop` branch
- a GitFlow-style release branch model
- a long-lived feature-branch governance document beyond normal Git practice

If that broader branch model becomes necessary later, add or update an ADR before changing the repository's workflow assumptions.

## 3. Proposal Branch Rule
Proposal branches must follow the proposal-path convention already defined in architecture docs:
- branch name: `agent/<task_request_id>`
- proposal branch content should be prepared from the forge target repository and target branch
- proposal branches should not be seeded from an arbitrary local workspace snapshot when the forge target repository is the intended source of truth for proposal and CI behavior

This prevents proposal branches from silently missing tracked workflow, CI, or platform files that exist in the forge target branch.

## 4. Local Forge Sync Rule
When maintainers use the default local seeded repo workflow (`howard/agent-sdlc` seeded from this workspace), the local forge's `main` branch must be reseeded from the workspace `HEAD` before proposal or CI validation whenever the workspace contains relevant unseeded changes.

Treat reseed as required when local changes affect areas such as:
- `.gitea/workflows/`
- `scripts/`
- `package.json`, `package-lock.json`, or `tsconfig.json`
- bootstrap, proposal, review, traceability, runtime, or CI behavior
- any tracked file that the operator expects the proposal branch and CI runner to exercise

The standard reseed command is:

```powershell
npm run dev:gitea-repo -- ensure-local-repo --owner <owner> --repo <repo> --seed-from .
```

For the default local repo posture in this repository, that is usually:

```powershell
npm run dev:gitea-repo -- ensure-local-repo --owner howard --repo agent-sdlc --seed-from .
```

## 5. Proposal Creation Guardrail
`node scripts/proposal-surface.js create-gitea-pr --session <path>` is expected to fail fast when the default local seeded repo is stale relative to workspace `HEAD`.

This preflight is a protection mechanism, not a substitute for operator discipline. The policy still requires reseeding before proposal and CI validation when the local forge has not yet been updated to the commit under test.

## 6. What This Policy Does Not Require
This policy does not require:
- rebasing every local workspace branch on every run
- introducing a second shared branch such as `develop`
- mirroring general GitHub/GitFlow branch governance that the repository has not selected

The immediate risk being managed is narrower:
- stale local forge `main`
- proposal branches created from stale forge content
- CI validating older workflow or finalize-script revisions than the workspace the maintainer believes is under test

## 7. Operator Workflow Expectation
For the default local validation path:
1. make or update the workspace changes you want to test
2. reseed the local forge repo when the forge has not yet been updated to that workspace `HEAD`
3. create or refresh the session/proposal path
4. let CI validate the resulting proposal branch

If proposal creation reports a stale-forge preflight failure, reseed first and then retry with a fresh session or proposal attempt.

## 8. Documentation Write-Back Rule
When branch behavior, forge seeding expectations, or proposal-branch sourcing changes, update all relevant surfaces in the same maintenance pass:
- `docs/architecture/pr-and-ci-path-definition.md`
- `docs/environment-bootstrap.md`
- `docs/testing/local-test-procedures.md` when operator steps change
- active issue or test dashboard items when the change affects current validation state

Do not leave meaningful branch-sync rules only in chat, test transcripts, or one-off troubleshooting notes.

## 9. ADR Trigger
Create or update an ADR before changing this policy if the change affects:
- the repository's shared-branch model
- source-of-truth ownership for proposal content
- whether forge, workspace, or provider-managed state owns the canonical branch under test
- CI ownership or branch-trigger semantics

## Change Log
- 2026-04-24: Initial version.
