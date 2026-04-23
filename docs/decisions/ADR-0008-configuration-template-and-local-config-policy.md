# ADR-0008: Configuration Template And Local Config Policy

- Status: Accepted
- Date: 2026-04-23

## Context
The Phase 1 agent execution adapter introduced the first provider-facing module configuration that operators may need to customize locally, especially for activation posture, backend selection, model choice, and provider credentials.

That exposed a broader repository concern:
- checked-in configuration should remain reviewable and reproducible
- operator-local configuration may contain machine-specific or secret-adjacent values
- future modules should not each invent their own pattern for examples, templates, ignored files, and config generation
- accidental commits of local configuration would weaken governance and make local environment differences harder to reason about

The repository already separates durable docs, machine-readable policy, and local runtime state. Configuration should follow the same source-of-truth discipline.

## Decision
The repository will use a uniform configuration-template policy:

1. Modules that require operator-controlled configuration must provide a checked-in template file.
2. Operator-local realized configuration should be generated or copied from the template and ignored by Git by default when it may vary per operator, environment, provider, credential surface, or local runtime.
3. Runtime code should prefer the local realized config when present, then fall back to the checked-in template when safe.
4. A repo-owned helper script should exist when generating the local config is non-obvious or likely to be repeated.
5. Local config files must not be the only durable source of configuration shape or defaults.
6. Checked-in templates should contain safe defaults and no secrets.
7. Docs and tests should refer to both the template path and the generated local path when a module follows this pattern.
8. For project-owned module settings, runtime code should treat the resolved project config file as the source of truth and should not let ambient environment variables silently override those settings unless an explicit exception exists.

## Decision Details

### 1. Template Role
Templates are the durable review surface for:
- supported keys
- safe defaults
- schema shape
- comments or examples when needed

Template files should use a clear suffix such as `.template.yaml`, `.template.json`, or `.template.env`.

### 2. Local Config Role
Local realized config is the operator-editable surface for:
- enabling or disabling optional integrations
- selecting local backends or endpoints
- choosing model, service, or runtime options
- storing provider credentials or other machine-specific values when they must remain local and ignored by Git

Local config should be ignored by Git unless an ADR explicitly states that a specific config must be committed.

### 3. Secrets
Templates should avoid storing secret values directly.

Ignored local config may store local-only credentials when the project policy requires settings to be maintained in project files rather than ambient environment variables. Those files must remain ignored by Git and must not be copied into tracked docs, templates, prompts, or evidence.

### 4. Loader Behavior
Module loaders should document and implement a predictable resolution order.

The default resolution order is:
1. generated local config
2. checked-in template config
3. code-level emergency defaults only when no template exists

Evidence records should include which source was used when configuration affects behavior.

## Rationale
If every module invents its own config convention, future agents and operators must rediscover where settings live, which files are safe to edit, and which files should not be committed.

A single policy makes configuration behavior easier to review and safer to automate. Templates keep module defaults and schema visible in code review without forcing operator-specific values into source control.

## Consequences

### Positive
- future modules get a consistent configuration pattern
- local provider settings are less likely to be committed accidentally
- code review can focus on template defaults and schema shape
- tests can validate both fallback and local-config paths
- provider configuration is less likely to drift because the resolved project config is the single operator-editable source

### Negative
- each configurable module needs a small amount of extra scaffolding
- docs must mention both template and local realized paths
- loaders must be clear about precedence
- ignored local config can contain sensitive local credentials, so `.gitignore` coverage and review discipline matter more

## Follow-Up
- Keep `docs/policies/configuration-management.md` aligned with this ADR.
- Update module docs and tests when new configurable modules are added.
- Treat exceptions as explicit decisions, and promote them to ADRs when they affect source-of-truth ownership, security posture, or governance expectations.

## Change Log
- 2026-04-23: Clarified that project-owned module settings should be maintained in project config rather than silently overridden by ambient environment variables.
