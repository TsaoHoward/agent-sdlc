# Configuration Management Policy

## Purpose
This document defines the repository-wide rule for configurable modules, checked-in templates, generated local configuration, and source-control boundaries.

It supports ADR-0008.

## 1. Core Rule
Any module that needs operator-controlled configuration should expose that configuration through a dedicated config file with a checked-in template.

Do not leave meaningful module configuration only in code constants, prompt text, shell history, or chat.

## 2. Required Pattern
For each configurable module:
- provide a checked-in template such as `*.template.yaml`, `*.template.json`, or `*.template.env`
- keep the template safe to commit
- generate or copy an operator-local config file from the template when local edits are needed
- ignore the local config file in `.gitignore` when it can vary by operator, machine, provider, credentials, or local runtime
- document the template path, local path, and generation command

## 3. Loader Precedence
Module loaders should use this order unless a documented exception exists:
1. local generated config
2. checked-in template config
3. code-level emergency defaults

When configuration affects lifecycle behavior or evidence, records should include which source was used.

For project-owned module settings, runtime code should treat the resolved project config file as the source of truth. Do not let ambient environment variables silently override those settings unless an explicit policy or ADR exception exists.

## 4. Secret Handling
Templates must not contain raw secret values.

Ignored local config may contain local-only credentials when the module is governed by project-file configuration. Those files must remain ignored by Git and must not be copied into tracked docs, templates, prompts, or evidence.

If a future module needs a different secret handling model, update the relevant policy and create an ADR when source-of-truth ownership or security posture changes.

## 5. When To Add A Template
Add a template when a module has settings such as:
- enablement flags
- backend or provider selection
- service base URLs
- model or runtime identifiers
- local ports or callback URLs
- credential fields in ignored local config
- limits, thresholds, allowlists, or capability-like knobs

Small constants that are not operator-controlled do not need a template.

## 6. Current Example
The first module following this pattern is agent execution:
- template: `config/agent-execution.template.yaml`
- local config: `config/agent-execution.yaml`
- generator: `npm run dev:agent-execution-config`
- loader: `scripts/lib/agent-execution.js`

The local file is ignored by Git and can be regenerated from the template. Provider credentials such as `agentExecution.apiKey` belong in that ignored local file, not in ambient environment variables.

The local Gitea/dev bootstrap config also follows this pattern:
- template: `config/dev/gitea-bootstrap.template.json`
- local config: `config/dev/gitea-bootstrap.json`
- generator: `npm run dev:gitea-bootstrap-config`
- loader surfaces: `scripts/dev/manage-dev-environment.ps1` and `scripts/lib/gitea-client.js`

## 7. Current Explicit Exceptions
`config/policy/*.yaml` files are committed machine-readable policy source-of-truth, not operator-local config.

`.gitea/workflows/phase1-ci.yml` is a committed workflow source-of-truth. Its local CI-to-host callback URL is currently a workflow-owned local default rather than an ignored local config value because the workflow must run from the checked-out proposal branch inside the CI runner. Revisit this exception when workflow generation, repository variables, or another runner-supported configuration injection path becomes part of the implementation.

## 8. Change Control
Changes to template shape or safe defaults are usually implementation or planning changes.

Create or update an ADR before changing this policy if the change affects:
- source-of-truth ownership
- secret handling expectations
- governance rules for what must or must not be committed
- runtime isolation or provider-control assumptions

## Change Log
- 2026-04-23: Initial version.
- 2026-04-23: Clarified that project-owned module settings should be maintained in project config rather than silently overridden by ambient environment variables.
