# I-004: Second External Target Fixture Family

## Metadata
- Issue ID: I-004
- Status: In Progress
- Last Updated: 2026-04-24
- Owner: Project Maintainer
- Related Docs / WBS: `docs/roadmap.md` Phase 1; `docs/wbs.md` WBS `3.10`, `3.11`
- Source Dashboard: docs/issues/issue-dashboard.md
- Source Template: docs/templates/issue-note.template.md

## Summary
The first external-target baseline now proves docs-only service evaluation on a non-platform repo. This follow-up adds a second fixture family so the project can start comparing docs-oriented and bounded-code behavior without jumping straight to broader pilot claims.

## Why It Matters
One docs-only target is enough to prove the platform/target-repo separation, but not enough to answer how the current provider-backed path behaves on small code edits. A second fixture family keeps Phase 1 narrow while making service-evaluation evidence less one-dimensional.

## Current State
- `target-docs` is already provisionable and has one valid passed evaluation run.
- The platform now needs a second fixture that still stays controlled, resettable, and cheap to validate.
- The intended second fixture is `target-code-small`, a tiny Node.js repo with:
  - bounded editable paths under `src/**`
  - repo-local validation commands
  - the same minimal target-side CI integration kit used by the first fixture family
- The fixture baseline and command surface are now in place:
  - `npm run eval:target-code-small:provision`
  - `npm run eval:target-code-small:reset`
  - seeded local forge target: `gitea:localhost:43000/eval/target-code-small`
- This follow-up does not change architecture boundaries or ADR-0009. It extends the evidence surface inside the existing platform-repo versus target-repo separation model.

## Dependencies And Constraints
- Keep the fixture small enough that it remains a Phase 1 internal-eval asset, not a broad sample application.
- Reuse the existing target-side CI and traceability kit so the second fixture does not become a new workflow model.
- Do not reframe self-targeted `agent-sdlc` runs as service-evaluation evidence while adding this fixture.

## Proposed Handling Or Work Packaging
1. Add `target-code-small` as a provisionable/resettable external target repo.
2. Add a canonical test case for the first bounded-code evaluation baseline on that repo.
3. Keep the first validation goal narrow: one small `@agent run code` task with explicit edit boundaries and service-evaluation rubric.
4. Leave pilot-readiness language unchanged until real external-target evidence exists for the new fixture family.

## Exit Path
This issue exits the active dashboard when:
- `target-code-small` exists as a runnable fixture with provision/reset commands
- the canonical test case is documented
- the remaining work is only the first live evaluation run, which can then move to test-tracking rather than fixture-bootstrap tracking

## Next Actions
- provision the second fixture into local Gitea and confirm the new command surface works
- keep testing docs explicit that the fixture is baseline-ready before it has passed service-evaluation evidence
- run the first bounded-code evaluation only after the fixture baseline and rubric are stable

## Change Log
- 2026-04-24: Initial version.
- 2026-04-24: Updated after validating the `target-code-small` provision command and seeding `eval/target-code-small` into local Gitea.
