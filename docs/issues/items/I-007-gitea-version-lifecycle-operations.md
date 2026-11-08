# I-007: Gitea Version Lifecycle Operations

## Metadata
- Issue ID: I-007
- Status: In Progress
- Last Updated: 2026-11-08
- Owner: Project Maintainer
- Related Docs / WBS: GitHub issue #3; `docs/roadmap.md` Phase 1 follow-up; WBS `3.12`; `docs/testing/items/TC-011-gitea-version-lifecycle-operations.md`
- Source Dashboard: docs/issues/issue-dashboard.md
- Source Template: docs/templates/issue-note.template.md

## Summary

Issue #3 adds safe, repeatable version lifecycle operations to the existing Windows PowerShell management entrypoint for the legacy Docker Gitea instance on port 43000.

## Why It Matters

The instance owns persistent repositories, Actions data, Registry packages, and a shared Runner. The separate Compose instance on port 46300 is a different data environment. A wrong-container operation or image-only rollback could make existing state unavailable.

## Current State

The latest GitHub spec requires explicit fixed-version upgrades, exact legacy-container and bind-mount checks, Runner quiescence, local capacity checks, a retained checksum-verified backup before container recreation, and a manually confirmed restore by Backup ID. Backups remain on the Windows Host and are never automatically rotated or deleted. A failed upgrade is left in place for diagnosis; restore first saves the current failed state as a separate diagnostic backup. PostgreSQL restore checks that the archive names the configured Gitea database, then recreates that database inside the same PostgreSQL container; unrelated databases remain out of scope. An incomplete operation leaves a recovery marker that blocks bootstrap `up` until an operator completes an explicit restore or safely reconciles a verified return to the original healthy source state. Isolated implementation acceptance passed on 2026-11-06 (bootstrap pin 5/5, full Pester 44/44, Docker E2E 3/3). A subsequent read-only observation of the site-wide Actions API found Run #95 reported as `status=completed`, `conclusion=failure`, and `completed_at=2026-11-06T11:52:25Z`; the preflight now accepts that response shape only with a legal conclusion and valid timezone-qualified completion time while retaining legacy terminal statuses and fail-closed handling. This compatibility fix did not perform a live lifecycle operation.

The second reported failure occurred during Gitea `1.25.5 → 1.26.4`: `gitea-runtime.json` contained three RepoDigests concatenated into one `imageReference`, causing Docker `invalid reference format`. The incident report identifies checksum-valid backup `20261108T053419Z-a5737137148a41a9bc45d6f7a78485df`, says the original Gitea/PostgreSQL/Runner container IDs were manually restored unchanged, and says the Recovery Marker remains. A direct Windows PowerShell 5.1 repro established the cause: a top-level JSON array passed through `ConvertFrom-Json` and the pipeline was assigned as one space-joined string; the prior loose candidate expression accepted the concatenation. The fix parses the JSON array as an object property, validates each entry, and emits exactly one legal immutable reference. Upgrade now validates the source image snapshot before stopping services; Restore validates its selected image reference and restore metadata before stopping services or writing a diagnostic backup.

Recovery Marker closeout is a separate safe path from restore. Never delete the marker directly or restore the database solely to clear it. When the original Gitea, PostgreSQL, and Runner containers are verified by full ID, the source Gitea image/version/API is healthy, the backup and topology validate, and the operator independently verifies current database health, `reconcile-recovery` records that evidence and clears only the marker. It does not stop/recreate services, restore the database, or delete the backup. Legacy schema 1 markers do not store IDs, so the operator must provide those verified IDs and confirm the database attestation. For compatibility with this incident only, reconciliation also accepts a schema-1 upgrade backup whose malformed `imageReference` is exactly three official Gitea digests joined by one space and whose manifest source fields match; it verifies the captured local image ID against the running Gitea and never uses the malformed value to operate on an image. Restore keeps strict immutable-reference validation and rejects this backup. If identities differ, the source is unhealthy, the marker is for a restore, the backup is invalid, or database state is uncertain, keep the marker and use the separately confirmed Restore workflow only if data actually needs reverting. This reconciliation path has not been run against the formal host.

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

- The latest failure is explained by a direct Windows PowerShell 5.1/.NET Framework NTFS probe: `File.Replace` with a null backup path fails with `ArgumentException` / HRESULT `0x80070057`, including for extended-length paths; a unique same-directory backup path succeeds. `Move-LongPathFile -Force` now supplies that backup and rolls the replacement back if backup cleanup fails. Direct image-pin and Recovery Marker coverage was added under `WindowsBootstrapPin`; the upgrade catch preserves sanitized stage/type/cause details. Focused real-NTFS Pester passed 5/5. Combined non-Docker Pester was 43/44; the sole failure was `whoami.exe /priv` returning no output in this WSL Windows-interop session, so native-host full-suite status remains to be confirmed. The post-fix Docker E2E has not been rerun.
- Next verification: Native Windows bootstrap-pin 5/5, full Pester 44/44 and isolated Docker E2E 3/3 have passed on commit `071cb08`. Only the separately authorized real 43000 upgrade and API/Git/Registry/Actions/Runner/Run Attempt smoke acceptance remain; retain Issue #3 active until that evidence is recorded.
- Actions preflight compatibility follow-up (2026-11-08): Windows PowerShell 5.1/Pester 6.2.0 ran 45/46 tests; the only failure was the existing WSL interop `WindowsAcl` precondition because `whoami.exe /priv` returned no output. The same suite excluding that tag passed 45/45. Coverage includes the reported `completed` / `failure` / RFC 3339 timestamp shape plus valid/invalid conclusions, timestamps, missing fields, legacy terminal values, active/unknown states and incomplete pagination. The GUID-owned Windows temp copy was removed. The formal Gitea, PostgreSQL, Runner, backup and upgrade surfaces were not accessed.
- RepoDigest/recovery follow-up (2026-11-08): Reproduced the three-digest string corruption in Windows PowerShell 5.1 and confirmed the parser fix with multi, duplicate, mixed-repository, malformed and local-ID cases. Full Pester was 55/56; the only failure was the known WSL interop ACL precondition. Excluding that tag passed 55/55. Docker E2E did not pass preflight because the available engine was not Docker Desktop, and stopped before fixture creation. No formal service, backup, or marker was accessed.
- Legacy backup reconciliation follow-up (2026-11-08): Added compatibility only to `reconcile-recovery` for the exact three-official-digest schema-1 upgrade payload with matching manifest fields; Restore still uses strict `Get-BackupRuntime` validation. A unit regression covers the incident shape and rejects other concatenation counts; isolated E2E mutates only its owned fixture backup and verifies checksum integrity plus no-restore reconciliation. Per maintainer direction, this follow-up's native Windows Pester and isolated Docker E2E have not yet been run; prior Pester evidence applies to the original PR #6 head only.
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
- 2026-11-06: Recorded Windows Pester 33/33, ACL 1/1, and E2E `DirectoryNotFoundException` at the 268-character Git Object copy target; added explicit extended-length file operations and a real-NTFS copy/checksum/manifest/restore regression. Post-patch Windows Pester and E2E remain pending.
- 2026-11-06: Recorded the 34/34 Pester, 1/1 long-path, and Docker E2E Hashtable-total/cleanup failures; added regression coverage, dependent-case skips, and a standalone ownership-verified long-path cleanup command. Post-patch Windows validation remains pending.
- 2026-11-06: Confirmed `File.Replace(..., $null)` fails on Windows PowerShell 5.1/.NET Framework for ordinary and extended paths; changed replacement to use a unique same-directory backup with rollback on cleanup failure and added direct real-NTFS image-pin/recovery-marker cases with safe diagnostics. Focused Pester passed 5/5; combined non-Docker Pester was 43/44 due to the WSL interop `whoami` precondition; post-fix Docker E2E remains pending.
- 2026-11-06: Native Windows image-pin 5/5, full Pester 44/44, and GUID-isolated Docker E2E 3/3 passed. Fixture cleanup confirmed; production 43000 acceptance deferred pending explicit authorization.
- 2026-11-08: Recorded the instance-wide Actions Run #95 compatibility regression, guarded `completed`/conclusion/completion-time handling, and Pester results (45/46 full; 45/45 excluding the WSL interop ACL precondition); formal 43000 acceptance remains separate and unauthorized.
