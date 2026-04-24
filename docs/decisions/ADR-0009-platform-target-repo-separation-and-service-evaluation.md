# ADR-0009: Platform / Target Repo Separation And Service-Evaluation Evidence Model

- Status: Accepted
- Date: 2026-04-24

## Context
The current Phase 1 closed loop is now executable end to end, but most local validation still uses the platform repository itself as the seeded local forge repo and as the proposal target.

That was acceptable for early bootstrap because it:
- reduced setup friction
- made workflow, traceability, and CI convergence easier to debug
- let the project prove the first narrow issue-comment-to-PR path quickly

However, keeping the platform repository as the primary target for ongoing service-quality claims now creates a governance and evaluation problem:
- platform regression and agent service evaluation become conflated
- successful self-hosted runs can overstate real user value
- the platform learns too much from its own implementation layout and workflow files
- promotion from local validation to pilot or production cannot be justified from self-targeted evidence alone

The project needs an explicit rule for:
- which repository is the platform control repo
- which repositories are valid agent-work targets
- which evidence counts as platform regression only versus service-evaluation evidence
- how service state should progress from internal workbench to later pilot or production operation

## Decision
The repository will adopt the following model:

1. `agent-sdlc` is the platform control repository, not the default long-term service-evaluation target.
2. Self-targeted runs against the platform repository remain allowed for bootstrap and platform regression, but they do not count as sufficient evidence for broader service-quality claims.
3. Service evaluation must use external target repositories that are distinct from the platform control repository.
4. The project will use explicit service states:
   - `Workbench`
   - `Internal Eval`
   - `Pilot`
   - `Production`
5. Promotion between service states must rely on evidence from the appropriate tier, and self-hosted platform runs alone cannot promote a task class or workflow into pilot or production readiness.

## Decision Details

### 1. Repository Roles

#### Platform Control Repository
`agent-sdlc` owns:
- task intake
- policy
- agent control
- runtime integration
- proposal and traceability logic
- testing workflow and governance documents

It may still be used for:
- local bootstrap smoke tests
- platform CLI and listener regression
- workflow and traceability troubleshooting

#### External Target Repositories
Distinct target repositories will be introduced for:
- documentation-oriented evaluation
- bounded code-change evaluation
- CI investigation evaluation
- later pilot service use

These repositories are the correct place to observe whether the service behaves well for users rather than merely whether the platform can operate on itself.

#### Evaluation Corpus
The project should maintain a durable evaluation corpus that ties:
- target repository
- task token and summary
- expected edit boundary
- expected verification behavior
- human review rubric

to repeatable service-evaluation runs.

### 2. Evidence Classes

#### Platform Regression Evidence
Evidence from self-targeted runs against the platform repository is valid for:
- listener health
- task/session/proposal/traceability continuity
- local bootstrap regression
- workflow and CI script regression
- platform adapter debugging

It is not sufficient on its own for:
- claiming general user readiness
- promoting a task class to pilot use
- representing real target-repo quality

#### Service-Evaluation Evidence
Evidence from external target repositories is required for:
- judging AI task quality
- comparing providers or models
- evaluating edit-boundary compliance in a non-platform repo
- pilot-readiness or production-readiness claims

### 3. Service States

#### Workbench
- development and bootstrap mode
- self-targeted platform runs are expected
- no service-quality claim beyond internal engineering progress

#### Internal Eval
- controlled live workflow
- external target repositories should exist
- task classes can be compared and scored
- still limited to maintainers or designated operators

#### Pilot
- limited real users, limited repos, limited task classes
- promotion requires external-target evidence plus stable workflow/traceability/CI behavior

#### Production
- formal service posture
- explicit operating commitments, rollout control, and promotion gates

### 4. Promotion Rule
A task class or workflow slice must not be treated as pilot-ready or production-ready unless:
- platform regression remains healthy
- external target repo evaluation exists for that slice
- durable testing and issue docs reflect the current status
- promotion criteria are satisfied by the selected service state policy

## Rationale

### Why Keep Self-Targeted Runs At All
- they remain the fastest troubleshooting path
- they are useful for platform maintenance
- removing them would slow Phase 1 progress without improving service evidence by itself

### Why Separate Target Repos Now
- it preserves realism before pilot claims begin
- it keeps service-quality evidence from being distorted by platform-specific structure
- it lets maintainers observe AI behavior against repositories that look more like actual users' codebases

### Why Introduce Explicit Service States
- it prevents "live locally" from being mistaken for "ready to serve users"
- it gives planning and testing docs a stable way to describe promotion gates
- it supports gradual rollout without flattening workbench, evaluation, and production into one status

## Consequences

### Positive
- clearer distinction between platform health and service quality
- stronger basis for future pilot decisions
- better alignment between testing evidence and actual user value
- less risk of overstating readiness from self-referential smoke tests

### Negative
- more repo and fixture setup work
- more documentation and dashboard maintenance
- some current "passed" local runs must be reinterpreted as platform regression rather than service proof

## Follow-Up
This ADR should be reflected in:
- roadmap and WBS updates for external target repo evaluation and service-state tiering
- testing docs that distinguish platform regression from service evaluation
- issue and test dashboards for the near-term rollout work
- a dedicated policy for service states and evaluation evidence
- current-state docs such as the capability matrix and environment/bootstrap guidance
