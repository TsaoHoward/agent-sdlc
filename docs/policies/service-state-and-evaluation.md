# Service State And Evaluation Policy

## Purpose
This document defines the repository rule for service-state labeling, promotion evidence, and the distinction between platform self-test and external target service evaluation.

It supports ADR-0009.

## 1. Core Rule
Do not treat a successful self-targeted run against the platform repository as sufficient evidence that the service is ready for broader user use.

The project must distinguish between:
- platform regression evidence
- service-evaluation evidence
- pilot or production promotion evidence

## 2. Service States
Use one of these service-state labels when describing the current operational posture of a workflow slice or task class:

- `Workbench`
- `Internal Eval`
- `Pilot`
- `Production`

If a document or status note does not explicitly say otherwise, the current repository posture should be treated as `Workbench` moving toward `Internal Eval`, not as pilot or production service.

## 3. Evidence Classes

### 3.1 Platform Regression Evidence
Platform regression evidence comes from runs that primarily validate the platform itself.

Typical examples:
- self-targeted runs against `agent-sdlc`
- local bootstrap smoke tests
- listener, traceability, or workflow troubleshooting runs
- deterministic replay of example events against the platform repo

This evidence is valid for:
- platform stability claims
- implementation debugging
- regression checks for listeners, proposal logic, CI scripts, and traceability

It is not sufficient by itself for:
- pilot-readiness claims
- production-readiness claims
- general claims about user-facing AI task quality

### 3.2 Service-Evaluation Evidence
Service-evaluation evidence comes from external target repositories that are distinct from the platform control repository.

This evidence is required for:
- task-quality evaluation
- provider/model comparison
- task-class promotion beyond workbench-only claims
- pilot and production readiness review

## 4. Repository Roles
- `agent-sdlc` is the platform control repository.
- external target repositories are the service-evaluation and later pilot-use targets.
- evaluation fixtures or corpus entries should define which target repo, task token, prompt summary, and expected outcome belong to a repeatable evaluation case.

## 5. Promotion Guidance

### Workbench -> Internal Eval
Requires at least:
- stable platform regression path
- explicit current-state docs
- at least one defined external-target evaluation path for the workflow under review, even if coverage is still narrow

### Internal Eval -> Pilot
Requires at least:
- external-target evidence for the task class or workflow slice
- stable traceability and CI behavior
- bounded target-repo scope
- durable test and issue write-back for known gaps and exit paths

### Pilot -> Production
Requires at least:
- explicit production operating model
- rollout and rollback rules
- promotion gates that are no longer inferred only from evaluation notes
- architecture and governance docs aligned with that service posture

## 6. Document Write-Back Rule
When service state, evidence class, or promotion meaning changes, update all directly affected surfaces in the same maintenance pass:
- roadmap
- WBS
- capability matrix
- testing plan/framework/dashboard
- issue dashboard
- ADRs or policies when governance or architecture ownership changes

Do not leave service-state meaning only in chat, shell history, or one-off test notes.

## 7. Near-Term Rule For This Repository
The current local `howard/agent-sdlc` seeded repo workflow remains valid for:
- bootstrap
- platform regression
- workflow troubleshooting

It should not be presented as the only or primary evidence that:
- `@agent run <token>` is ready for pilot users
- the service behaves well on repositories other than the platform repo

## 8. ADR Trigger
Create or update an ADR before changing this policy if the change affects:
- the ownership boundary between platform repo and target repos
- what counts as sufficient promotion evidence
- service-state definitions or governance expectations
- whether pilot or production claims can be made from self-targeted evidence alone

## Change Log
- 2026-04-24: Initial version.
