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

## 4. Secret Handling
Templates and local config should not contain raw secret values.

Preferred approach:
- config names an environment variable or secret reference
- the actual secret value is supplied outside the checked-in file

If a future module needs a different secret handling model, update the relevant policy and create an ADR when source-of-truth ownership or security posture changes.

## 5. When To Add A Template
Add a template when a module has settings such as:
- enablement flags
- backend or provider selection
- service base URLs
- model or runtime identifiers
- local ports or callback URLs
- credential environment variable names
- limits, thresholds, allowlists, or capability-like knobs

Small constants that are not operator-controlled do not need a template.

## 6. Current Example
The first module following this pattern is agent execution:
- template: `config/agent-execution.template.yaml`
- local config: `config/agent-execution.yaml`
- generator: `npm run dev:agent-execution-config`
- loader: `scripts/lib/agent-execution.js`

The local file is ignored by Git and can be regenerated from the template.

## 7. Change Control
Changes to template shape or safe defaults are usually implementation or planning changes.

Create or update an ADR before changing this policy if the change affects:
- source-of-truth ownership
- secret handling expectations
- governance rules for what must or must not be committed
- runtime isolation or provider-control assumptions

## Change Log
- 2026-04-23: Initial version.
