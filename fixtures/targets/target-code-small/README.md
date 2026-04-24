# Target Code Small Sandbox

This repository is a controlled external target used by `agent-sdlc` to evaluate bounded-code agent behavior outside the platform repo itself.

## Purpose

- provide one repeatable non-platform repo for `@agent run code`
- keep the edit boundary narrow to `src/**` and `README.md`
- carry a minimal target-side CI integration kit so PRs still produce traceability and CI evidence

## Operator Notes

- Provision into local Gitea from the platform repo with `npm run eval:target-code-small:provision`
- Reset the repo back to this checked-in baseline with `npm run eval:target-code-small:reset`
- Use this repo as service-evaluation evidence, not as a platform-regression shortcut

## Fixture Surface

- `src/task-summary.js`: small summary-formatting utilities
- `src/task-priority.js`: priority normalization and ordering helpers
- `scripts/validate-code-target.js`: repo-local structural and behavior checks
