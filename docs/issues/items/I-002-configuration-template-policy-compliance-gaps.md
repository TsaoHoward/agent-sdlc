# I-002: Configuration Template Policy Compliance Gaps

## Metadata
- Issue ID: I-002
- Status: Done
- Last Updated: 2026-04-23
- Owner: Project Maintainer
- Related Docs / WBS: ADR-0008; `docs/policies/configuration-management.md`; `docs/roadmap.md` Phase 1; `docs/wbs.md` WBS `3.1`, `3.3`, `3.5`, `3.9`
- Source Dashboard: docs/issues/issue-dashboard.md
- Source Template: docs/templates/issue-note.template.md

## Summary
Several existing startup and integration modules predate ADR-0008's repository-wide configuration-template policy. The first compliant module is `agent-execution`, but other operator-controlled settings still need to be moved behind checked-in templates plus ignored generated local config, or documented as explicit exceptions.

## Why It Matters
Configuration drift makes local setup harder to reproduce and review. When ports, callback URLs, provider/runtime selectors, or secret-adjacent defaults live only in tracked realized config, package scripts, workflow env, or code constants, future operators and agents cannot reliably tell which settings are safe to edit, safe to commit, or expected to vary per machine.

## Current State
The following surfaces were identified in the 2026-04-23 audit:

- `agent-execution` is compliant: `config/agent-execution.template.yaml` is tracked, `config/agent-execution.yaml` is ignored, and `scripts/dev/ensure-agent-execution-config.js` generates the local file.
- `config/policy/*.yaml` is a documented exception category: these files are committed machine-readable policy source-of-truth, not generated operator-local config.
- Local Gitea/dev bootstrap now follows ADR-0008: `config/dev/gitea-bootstrap.template.json` is tracked, `config/dev/gitea-bootstrap.json` is ignored, and `scripts/dev/ensure-gitea-bootstrap-config.js` generates the local file.
- Task-gateway and review-surface npm listener startup now reads from the Gitea bootstrap template/local config; explicit host/port/route CLI flags remain available for manual override.
- Local Gitea Actions runner defaults for container name, image, labels, network, and instance URL now resolve from the Gitea bootstrap template/local config, with environment overrides still available.
- Worker-runtime defaults for image and container-reachable Gitea host now resolve from the Gitea bootstrap template/local config, with environment overrides still available.
- The CI-to-host traceability callback URL is embedded in `.gitea/workflows/phase1-ci.yml` and is now documented as a committed workflow-local configuration exception.

## Dependencies And Constraints
- ADR-0008 requires operator-controlled module configuration to have a checked-in template and ignored local config when values can vary by operator, machine, provider, credential, or local runtime.
- Secret values should not be introduced into checked-in templates. Ignored local config may carry local-only credentials when project-file configuration is the selected source of truth.
- `config/policy/*.yaml` should remain committed policy input unless a future ADR changes policy source-of-truth ownership.
- Remediation should preserve the current working local Gitea, webhook, runner, CI callback, and worker-runtime behavior.

## Proposed Handling Or Work Packaging
Handle this in small implementation slices:

- Completed: split `config/dev/gitea-bootstrap.json` into `config/dev/gitea-bootstrap.template.json` plus ignored generated `config/dev/gitea-bootstrap.json`, and added a repo-owned helper to create the local file.
- Completed: centralized task-gateway and review-surface npm listener startup so package entrypoints and managed bootstrap use the same template-backed source for normal local operation.
- Completed: moved local runner and worker-runtime startup defaults under the Gitea bootstrap template/local config while preserving environment overrides.
- Completed: documented the embedded CI host callback URL as a committed workflow-local configuration exception because the workflow runs from the checked-out proposal branch inside the CI runner.

## Exit Path
This issue can move out of the active dashboard at the next issue-maintenance pass because all current gaps either follow ADR-0008's template/local-config pattern or carry an explicit documented exception.

## Next Actions
- Move this issue out of the active dashboard at the next maintenance pass if no new config-template gap appears.

## Change Log
- 2026-04-23: Initial version from the configuration-template policy compliance audit.
- 2026-04-23: Moved local Gitea/dev bootstrap to tracked template plus ignored generated local config; kept the issue open for webhook, runner, worker-runtime, and CI callback settings.
- 2026-04-23: Moved npm task-gateway and review-surface webhook startup to template/local bootstrap settings; kept the issue open for runner, worker-runtime, and CI callback settings.
- 2026-04-23: Moved local runner and worker-runtime startup defaults to template/local bootstrap settings; kept the issue open for the CI-to-host callback URL.
- 2026-04-23: Marked the issue done after documenting the CI-to-host callback URL as a committed workflow-local configuration exception.
