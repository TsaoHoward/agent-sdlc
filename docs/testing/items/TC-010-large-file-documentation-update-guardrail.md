# TC-010: Large-File Documentation Update Guardrail

## Metadata
- Test ID: TC-010
- Status: In Progress
- Last Updated: 2026-04-29
- Owner: Project Maintainer
- Mode: GUI live / proposal diff review
- Related Docs / WBS: `docs/issues/items/I-006-large-file-documentation-truncation-risk.md`; `config/agent-execution.template.yaml`; WBS `3.9`
- Source Dashboard: `docs/testing/test-dashboard.md`
- Source Template: `docs/templates/test-case.template.md`

## Objective
Verify that a supported `documentation_update` request against a large markdown file does not silently delete unseen content from the tail of the file.

## Scope
This case covers:
- provider-backed docs updates on files larger than the current `maxFileBytes` context cap
- proposal diff inspection for tail truncation or other destructive whole-file rewrite behavior
- post-fix regression coverage once the execution contract is hardened

It does not replace:
- generic provider connectivity coverage in `TC-004` and `TC-005`

## Current Known Failure
Current live evidence already demonstrates the regression:
- issue `#41` / comment `#193`
- task `trq-097cad6b8f77`
- session `ags-2736c300be71`
- PR `#42`
- commit `83acd236a04c1d59dbf109c964e389308b53a053`

Observed behavior:
- the task asked only for a short README note about weather
- the proposal diff added the requested note
- the same diff also deleted the unseen tail of `README.md`

The root-cause hypothesis is strong and repo-local:
- `README.md` is `11606` bytes
- `maxFileBytes` is `8000`
- the execution prompt still requires complete file content in the provider response

## Required Future Proof
Capture one repeatable post-fix run where:
- the target markdown file exceeds the context cap or equivalent large-file threshold
- the provider-backed docs update either preserves the untouched tail correctly or fails closed before proposal creation
- the resulting proposal diff no longer shows destructive tail truncation

## Evidence To Capture
- task request JSON
- session JSON
- proposal or no-proposal outcome
- diff excerpt showing preserved or blocked large-file handling
- the exact mitigation mode used, such as truncation block, patch mode, or targeted context loading

## Exit Rule
This case can move to `Passed` once a repeatable post-fix run proves that the large-file docs-update path no longer truncates unseen content.

## Change Log
- 2026-04-29: Initial version after analyzing PR `#42` / commit `83acd236a04c1d59dbf109c964e389308b53a053` and turning the large-file truncation regression into a dedicated guardrail test item.
