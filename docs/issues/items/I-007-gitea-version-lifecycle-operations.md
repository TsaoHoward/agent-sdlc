# I-007: Gitea Version Lifecycle Operations

## Metadata
- Issue ID: I-007
- Status: In Progress
- Last Updated: 2026-11-06
- Owner: Project Maintainer
- Related Docs / WBS: GitHub issue #3; `docs/roadmap.md` Phase 1 follow-up; WBS `3.12`; `docs/testing/items/TC-011-gitea-version-lifecycle-operations.md`
- Source Dashboard: docs/issues/issue-dashboard.md
- Source Template: docs/templates/issue-note.template.md

## Summary

Issue #3 adds safe, repeatable version lifecycle operations to the existing Windows PowerShell management entrypoint for the legacy Docker Gitea instance on port 43000.

## Why It Matters

The instance owns persistent repositories, Actions data, Registry packages, and a shared Runner. The separate Compose instance on port 46300 is a different data environment. A wrong-container operation or image-only rollback could make existing state unavailable.

## Current State

The latest GitHub spec requires explicit fixed-version upgrades, exact legacy-container and bind-mount checks, Runner quiescence, local capacity checks, a retained checksum-verified backup before container recreation, and a manually confirmed restore by Backup ID. Backups remain on the Windows Host and are never automatically rotated or deleted. A failed upgrade is left in place for diagnosis; restore first saves the current failed state as a separate diagnostic backup. PostgreSQL restore checks that the archive names the configured Gitea database, then recreates that database inside the same PostgreSQL container; unrelated databases remain out of scope. An incomplete operation leaves a recovery marker that blocks bootstrap `up` until explicit restore succeeds. Windows reported Pester 32/32 passed; Docker E2E passed PostgreSQL readiness, fixture initialization, and the real Actions preflight, then failed at backup ACL setup with `PrivilegeNotHeldException: SeSecurityPrivilege` under non-elevated PowerShell on healthy NTFS. `Set-Acl` was replaced by DACL-only persistence: the code preserves the current-user owner, disables parent inheritance, sets only the current-user/SYSTEM/Administrators Full Control ACEs, and verifies actual rules after writing. A tagged real-NTFS temp-directory Pester test covers owner, DACL protection, inheritance, file rules and effective current-user read/write, with ownership-marker-verified cleanup. Post-fix Windows Pester and Docker E2E remain pending. No live upgrade is authorized.

The issue identifies Gitea 28.3.0-rootless as a candidate. Official upgrade guidance supports upgrading directly to the latest release in the next series after a full backup. Gitea 28.0.0 documents that the historical `1.` prefix was dropped, and 28.3.0 is the third maintenance release of the 28 series. Based on that rule, the candidate path from the issue's 1.25.5 baseline is 1.26.4 -> 1.27.3 -> 28.3.0; skipping 28.0.0 is an inference from the documented next-series rule and the new version naming, not a published Gitea-specific migration matrix. Review each release changelog and confirm the actual source version before any separately authorized live maintenance. No live upgrade is authorized by this implementation request.

## Dependencies And Constraints

- Preserve the Gitea/PostgreSQL/Runner identities, configured mounts, host port, network, and local settings.
- Never target Compose port 46300, rebuild PostgreSQL, or modify unrelated services.
- Do not emit credentials in normal output or tracked files.
- Run the live acceptance from native Windows PowerShell only after a separate review, successful preflight, and explicit authorization.

## Proposed Handling Or Work Packaging

Implement under WBS `3.12` by extending `scripts/dev/manage-dev-environment.ps1` and its existing bootstrap config template/local config pattern. Validate with TC-011 through the operator-facing CLI against an isolated Docker boundary. Keep live Windows Host acceptance separate from code verification.

## Exit Path

Archive after implementation review and authorized Windows Host acceptance are complete. If live acceptance is deferred, retain this item as active with TC-011 documenting the remaining preconditions.

## Next Actions

- Next verification: run `npm run test:gitea-lifecycle:acl` from non-elevated Windows PowerShell, then rerun `npm run test:gitea-lifecycle` and the opt-in GUID-isolated Docker E2E. Record each post-fix result; do not treat the previous Pester 32/32 or the E2E run that failed at ACL setup as current acceptance.
- Before live maintenance, verify actual container topology, disk capacity, source version, official upgrade path, and representative smoke checks on Windows.

## Change Log
- 2026-11-05: Initial version from issue #3 and its latest authoritative spec comment.
- 2026-11-05: Added the guarded lifecycle entrypoint and mocked Pester coverage; native Windows integration and live acceptance remain outstanding.
- 2026-11-05: Added the isolated Docker E2E harness, corrected the 28.x upgrade-series handling from official Gitea guidance, and recorded that Windows execution is still required.
- 2026-11-05: Fixed the isolated migration-failure step and switched PostgreSQL restore to validated target-database recreation; Windows verification remains pending.
- 2026-11-06: Recorded Windows `npm ci`/typecheck success and the Pester Discovery failure; corrected test setup ordering and left Pester/Docker E2E reruns pending.
- 2026-11-06: Recorded Windows Pester 6.2.0 Docker E2E failures and the Run-phase setup/ownership cleanup fix; post-fix E2E rerun remains pending.
- 2026-11-06: Added stage/subcommand and credential-redacted Docker stderr diagnostics; post-fix Windows Docker E2E acceptance remains pending.
- 2026-11-06: Confirmed the socket-only PostgreSQL initialization readiness race and changed fixture gating to loopback TCP plus authenticated SQL; added bounded-retry regression tests and left Windows verification pending.
- 2026-11-06: Replaced repository-search Actions preflight with the official instance-wide admin-run endpoint after Windows E2E exposed a response-contract mismatch; added contract-shaped Pester coverage and kept the real API in Docker E2E. Post-fix Windows Pester and Docker E2E remain pending.
- 2026-11-06: Recorded Windows Pester 32/32 and the real fixture E2E ACL failure; switched to DACL-only persistence with ownership/inheritance/rule checks and added a non-elevated real-NTFS temp-directory test. Post-fix Windows Pester and E2E remain pending.
