# Target Docs Sandbox

This repository is a controlled external target used by `agent-sdlc` to evaluate docs-only agent behavior outside the platform repo itself.

## Purpose

- provide one repeatable non-platform repo for `@agent run docs`
- keep the edit boundary narrow to `README.md` and `docs/**`
- carry a minimal target-side CI integration kit so PRs still produce traceability and CI evidence

## Operator Notes

- Provision into local Gitea from the platform repo with `npm run eval:target-docs:provision`
- Reset the repo back to this checked-in baseline with `npm run eval:target-docs:reset`
- Use this repo as service-evaluation evidence, not as a platform-regression shortcut
