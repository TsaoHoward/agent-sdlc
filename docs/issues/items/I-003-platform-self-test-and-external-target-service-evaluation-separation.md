# I-003: Platform Self-Test And External Target Service-Evaluation Separation

## Metadata
- Issue ID: I-003
- Status: Done
- Last Updated: 2026-04-24
- Owner: Project Maintainer
- Related Docs / WBS: ADR-0009; `docs/roadmap.md` Phase 1; `docs/wbs.md` WBS `3.10`, `3.11`
- Source Dashboard: docs/issues/issue-dashboard.md
- Source Template: docs/templates/issue-note.template.md

## Summary
The current local closed loop is strong enough to support platform regression and internal troubleshooting, but it still uses the platform repo as the dominant seeded target. This note captures the rollout work needed to separate self-targeted platform regression from external target-repo service evaluation.

## Why It Matters
If the project keeps treating self-targeted local runs as the main proof surface, it becomes hard to answer the user-facing question "what is this service actually good for?" with evidence that is meaningful outside the platform repo itself.

## Current State
- The repo has a working local issue-comment-to-PR-to-CI path.
- The same local path now has provider-enabled evidence for all currently supported task tokens.
- Most repeatable local procedures still exercise `howard/agent-sdlc`, which is useful for platform regression but not sufficient as long-term service-evaluation evidence.
- The first concrete external-target baseline now exists as `fixtures/targets/target-docs/`.
- The platform repo now exposes:
  - `npm run eval:targets`
  - `npm run eval:target-docs:provision`
  - `npm run eval:target-docs:reset`
- The `target-docs` fixture carries a minimal target-side CI integration kit so proposal branches can still emit `.agent-sdlc/traceability/*.json`, `.agent-sdlc/ci/verification-metadata.json`, and host callback payloads without reusing the platform repo as the target under test.
- Local provisioning has now been validated by seeding `eval/target-docs` into the local forge with the standard issue-comment and review-follow-up webhook set.
- The first valid external-target evidence set now exists: issue `#3` / comment `#153` -> task `trq-f77d70ed7f92` -> session `ags-7f12724630cc` -> PR `#4` -> CI run `#56` (`success`) with bounded edits to `README.md` and `docs/faq.md`.
- A same-day seeding bug was also corrected: nested fixture directories under the platform repo now seed through a temporary snapshot repo instead of accidentally pushing the parent platform repo `HEAD`.
- ADR-0009 now records:
  - `agent-sdlc` is the platform control repo
  - self-targeted runs remain valid for bootstrap and platform regression
  - broader service-quality evidence must come from external target repos
  - service-state labeling should distinguish `Workbench`, `Internal Eval`, `Pilot`, and `Production`

## Recommended Work Packaging
1. Reclassify current local procedures.
   Mark the existing `howard/agent-sdlc` workflows as platform self-test / platform regression in testing docs and current-state docs.
2. Add service-evaluation procedures.
   Turn `TC-006` into the first repeatable external-target evaluation case with task input, edit boundary, expected verification, and outcome rubric.
3. Add service-state labeling.
   Current-state docs should say clearly whether the workflow is `Workbench`, `Internal Eval`, `Pilot`, or `Production`.
4. Add promotion rules.
   Later pilot claims should require external-target evidence instead of self-targeted smoke success alone.

## Dependencies And Constraints
- Keep the current local self-hosted path because it is still the fastest platform regression path.
- Do not let new external target repos collapse the control-plane and target-repo ownership model into one repo again.
- Keep the first external target path narrow enough to remain repeatable.

## Exit Path
This issue exits the active dashboard when:
- at least one external target-repo path exists and has at least one captured evaluation run
- testing docs clearly distinguish platform regression from service evaluation
- the capability matrix and roadmap no longer imply that self-targeted local runs are sufficient service proof by themselves

## Next Actions
- move this bootstrap issue out at the next maintenance pass if no immediate second-fixture follow-up is needed
- keep future pilot-readiness language tied to external-target evidence rather than fixture existence alone
- use a separate issue if a second external target family (`code` or `ci`) becomes near-term

## Change Log
- 2026-04-24: Initial version.
- 2026-04-24: Updated after landing the first `target-docs` external fixture and repo-local provisioning/reset commands.
- 2026-04-24: Marked done after fixing nested-fixture seeding and collecting the first valid external-target evidence set on `eval/target-docs`.
