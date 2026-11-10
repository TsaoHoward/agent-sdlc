# TC-011: Local Gitea Version Lifecycle Operations

## Metadata
- Test ID: TC-011
- Status: In Progress
- Last Updated: 2026-11-10
- Owner: Project Maintainer
- Mode: Windows PowerShell/Pester safety tests, isolated Docker acceptance, and separate manual Windows Host acceptance
- Related Docs / WBS: GitHub issue #3; WBS `3.12`; `docs/issues/items/I-007-gitea-version-lifecycle-operations.md`
- Source Dashboard: docs/testing/test-dashboard.md
- Source Template: docs/templates/test-case.template.md

## Objective

Verify the operator-facing upgrade, backup-list, and restore commands protect the legacy Gitea data boundary and fail closed before unsafe changes.

## Scope

Recovery reconciliation alone accepts the known schema-1 upgrade backup defect when `imageReference` contains two identical `docker.gitea.com/gitea@sha256:<SHA>` references and one `gitea/gitea@sha256:<same SHA>` reference separated by single ASCII spaces, the manifest digest/source/version match the runtime payload, and the captured local image ID is valid. It never uses that malformed reference to start, pull, pin, or restore an image. The normal Restore runtime validator remains strict for the same payload.

Run the automated Pester suite against temporary directories and a mocked Docker/API boundary through the exported lifecycle command. It covers supported version steps, backup path separation, checksum validation, backup byte totals for empty and multiple Hashtable entries, upgrade ordering and health-failure behavior, recovery-marker/image-pin ordering, source-service recovery after stop failure, immutable image-reference parsing, restore Backup ID and manifest gates, typed-confirmation refusal, exact PostgreSQL database recreation, and diagnostic-backup retention after restore failure without opening a Docker connection. Digest parser cases include multiple official RepoDigests, duplicates, mixed repositories, malformed/non-array/null values, and the local immutable image-ID fallback. Upgrade and restore reject invalid image metadata before stopping services or creating a diagnostic backup. The tagged `WindowsAcl` test additionally runs against real NTFS from non-elevated Windows PowerShell: it calls the exported backup-list command with a GUID-named temporary backup root, checks the actual owner and DACL, confirms directory inheritance and child access, then exercises the real file ACL helper without mocking. It refuses to treat an elevated run as a pass and checks that `SeSecurityPrivilege` is not enabled. Cleanup checks the exact temp path and owner; it checks the ownership marker before recursive removal, or removes only an empty directory if setup stops before marker creation. The test never reads or writes the SACL and never uses the configured/formal backup path. For the Actions upgrade preflight, Pester responses follow the instance-wide `ActionWorkflowRunsResponse` contract (`total_count` plus `workflow_runs`), covering an empty list, private-repository runs, legacy terminal statuses, completed runs with valid conclusions and timestamps, active/unknown states, missing or malformed fields, complete and incomplete pagination, non-admin identities, and API errors. The preflight first verifies `/api/v1/user` reports `is_admin`, then pages the unfiltered instance-wide `GET /api/v1/admin/actions/runs`; it does not enumerate repositories, so private repositories are covered by the site-admin endpoint. Pages must match the returned total before the preflight succeeds.

The tagged `WindowsLongPath` test runs from non-elevated Windows PowerShell against real NTFS. It creates a GUID-owned temp tree with a destination file path longer than 260 characters, records whether unprefixed `Copy-Item` fails while both the source and destination parent still exist, then exercises extended-path tree copy, SHA256 generation, manifest write and integrity validation, restore replacement, content equality, and verified cleanup. It never changes Windows long-path policy or uses the configured/formal backup path.

The tagged `WindowsBootstrapPin` regression runs from non-elevated Windows PowerShell against real NTFS. It creates a GUID-owned temp tree whose bootstrap JSON path exceeds 260 characters and directly invokes `Set-GiteaBootstrapImagePin` without mocking file operations. It verifies replacement of an existing config, the exact pinned image digest, unchanged non-image settings, no replacement/temp files, and safe fixture cleanup. A read-only destination forces a real NTFS replacement failure; the test checks the original bytes remain intact and the temporary file is removed. A second injected failure after replacement confirms the helper restores the original config if cleanup of the previous-file backup fails. A separate injected failure confirms diagnostic stage/type reporting and masks password/token values echoed by the exception. The same test calls `Set-GiteaLifecycleRecoveryMarker` twice to cover replacing an existing recovery marker through the shared file helper.

The opt-in Docker E2E creates GUID-named Gitea/PostgreSQL/real host-label Runner fixtures with isolated bind mounts and publishes only on `127.0.0.2`; lifecycle operations use the real fixture Gitea API, including Actions preflight, dispatch, Runs/jobs/logs, and the real Runner registration/execution/restart path. It performs real Git clone/fetch/push and ORAS 1.3.5 Registry tag/digest push/pull/package/delete checks. It also exercises multi, repeated, mixed-repository, and malformed RepoDigest responses and confirms the selected immutable reference resolves to the isolated fixture image. A real Docker name reservation makes source rename fail before any target create/start; after an authorized source-state restoration the test verifies only original-source closeout succeeds. Another test detaches the disposable target from its fixture network after creation, verifies the fresh PowerShell process reloads the pending Marker, then reconnects only that target and explicitly restores from the same Backup ID. The test checks post-backup table removal, preserved repository/unrelated-database sentinels, and unchanged PostgreSQL/Runner identities. A separate hop test produces and consumes a real backup for each supported adjacent version transition. Every fixture container's declared image volumes must map to an owned bind mount, and cleanup removes only verified GUID-owned container IDs/network/temp paths. Teardown checks the run ID, ownership marker, owner, path, and reparse-point status and uses .NET extended-length filesystem APIs. These are test cases, not current acceptance evidence: the updated suite has not run on native Windows PowerShell 5.1/Docker Desktop.

The recovery-reconciliation E2E converts only its GUID-isolated upgrade backup into an integrity-valid schema-1 fixture containing two official references plus one `gitea/gitea` alias with the same SHA, updating that fixture's manifest checksums. It verifies the ordinary `Get-BackupRuntime` Restore validator still rejects that payload, then confirms `reconcile-recovery` clears the isolated marker without using the malformed image reference or restoring the database. The reconciliation test leaves `Assert-BackupRuntimeMatchesContext` unmocked so it also verifies the real topology and image-reference validation path.

Live acceptance for the real 43000 instance is a separate, authorized Windows Host operation. It must also cover API, Git read/write, Registry access, Actions dispatch and Runner execution, Run Attempt visibility, and representative integrations. The local-agent-infra #29 E2E remains a separate result.

## Preconditions

- Use native Windows PowerShell with Pester 5 or 6.2.0, Node.js 22+, npm, and a Docker Desktop engine.
- Run `npm run test:gitea-lifecycle:acl` from non-elevated Windows PowerShell to exercise real NTFS rules; if the test reports skipped because the shell is elevated, rerun it from a standard non-admin session.
- Run `npm run test:gitea-lifecycle:long-path` from non-elevated Windows PowerShell to exercise real NTFS paths over 260 characters; capture the source/parent existence and unprefixed `Copy-Item` result printed by the controlled diagnostic.
- Run `npm run test:gitea-lifecycle:bootstrap-pin` from non-elevated Windows PowerShell to directly exercise image-pin and recovery-marker replacement on real NTFS, including an extended-length config path and the read-only failure case.
- The real ACL check uses only a GUID-named temp directory with an ownership marker. It does not modify the configured backup root or any existing backup.
- The Docker E2E requires `AGENT_SDLC_GITEA_DOCKER_E2E=1`; it refuses occupied test endpoints and runs Gitea at `127.0.0.2:43000`, isolated from a legacy service bound to `127.0.0.1:43000`.
- The E2E Runner is the pinned `gitea/act_runner:0.2.13` image registered through the isolated Gitea admin API. A real host-label canary checks run/job/log results and a second job after restarting the same Runner container. Docker/container actions are outside this baseline.
- Never point tests at the real Gitea containers, host mounts, repository, Registry, or shared Runner.
- For live acceptance, use native Windows PowerShell, verify the actual legacy container topology and disk capacity, review the official upgrade path, and obtain separate explicit authorization.

## Test Data

- Current and target Gitea versions with allowed same-series/next-series transitions.
- A temporary legacy-style Gitea and PostgreSQL container description with bind-mounted data/config, port 43000, and an isolated Runner.
- Corrupt/missing manifest, changed checksum, insufficient-space, and active-job fixtures.
- Backup set containing database dump, data/config trees, sensitive bootstrap payload, private runtime topology, and a manifest.
- A second database with a sentinel row plus a table created in the Gitea database after the selected backup, to prove database scope and exact restoration.

## Steps

1. Run `npm ci`, `npm run typecheck`, `npm run test:gitea-lifecycle:acl`, `npm run test:gitea-lifecycle:long-path`, `npm run test:gitea-lifecycle:bootstrap-pin`, and `npm run test:gitea-lifecycle`; record each exit status separately. Run all NTFS commands from non-elevated PowerShell; a skipped result from an elevated shell is not a pass.
2. On a Windows test host, run `status` and confirm existing commands remain read-only with respect to containers.
3. Run `upgrade` without a version, with a floating tag, an unsupported version jump, an unexpected port/mount/network, or active Runner jobs; confirm each stops before service mutation.
4. Force insufficient backup space and confirm no older backup is removed and no container is stopped/recreated.
5. Run `npm run test:gitea-lifecycle`; confirm the Actions preflight checks admin identity, accepts the official empty response, sees private-repository runs, pages every result, rejects incomplete pages and unknown/active statuses, and fails closed on malformed responses and API errors. Confirm completed runs require an allowed conclusion and valid completion time. Confirm RepoDigest parsing returns one legal immutable reference for multi/duplicate/mixed lists and fails closed for malformed data. Verify malformed source image metadata blocks upgrade before Runner/Gitea stop, and malformed backup metadata blocks restore before service stop or diagnostic backup. Also confirm readiness regressions reject socket-only readiness, require authenticated TCP `SELECT 1`, retry transient failures, stop after 60 attempts, and redact `PGPASSWORD`.
6. Set `$env:AGENT_SDLC_GITEA_DOCKER_E2E = "1"` and run `npm run test:gitea-lifecycle:docker-e2e`; confirm it uses only GUID-named fixtures, an isolated network and bind mounts, and the `.2` loopback endpoints. Confirm fixture upgrades use the real Gitea `/user` and `/admin/actions/runs` API preflight with no mock at either preflight seam. Before fixture SQL setup, confirm the helper uses `pg_isready -h 127.0.0.1` and the authenticated TCP SQL check succeeds.
7. Confirm the real host-label Runner registers through the fixture admin API, executes a unique workflow-dispatch canary, exposes run/job/log evidence, and completes a second canary after the same Runner container is restarted. Confirm real Git clone/fetch/push and ORAS 1.3.5 Registry push/pull-by-tag/pull-by-digest/package-list/detail/delete and invalid-credential refusal.
8. Confirm the `1.25.5 → 1.26.4` upgrade backup is consumed by Restore and that the fixture is returned to `1.26.4`. For each later adjacent hop through `1.27.3` and `28.3.0`, create a real upgrade backup, validate the target API version, restore that exact backup, and verify PostgreSQL/Runner identities and both Gitea and unrelated database sentinels.
9. Inject real Docker failures at source rename (reserved disposable container name) and after target creation (disconnect only the disposable target network). In a fresh PowerShell process, reload the Marker and operation record. Confirm original-source reconciliation is rejected once target create/start may have begun; reconnect only the fixture target and consume the same upgrade Backup ID through explicit Restore. Confirm no automatic resume or rollback occurs.
10. Attempt restore with a missing ID, corrupt checksum, or incorrect typed confirmation; confirm fixture data is unchanged.
11. Confirm a valid restore creates and verifies a separate diagnostic snapshot first, then recreates only the database named by the selected archive. Verify files/settings/Image/topology as one unit, PostgreSQL and unrelated-database identity/content, Runner identity, and append-only attempt records.
12. If separately authorized, perform the manual Windows Host acceptance sequence and record all smoke evidence before treating the service upgrade as accepted. Formal Gitea/Recovery Marker/backup operations and #29 downstream acceptance are outside this isolated procedure.
13. For original-source closeout, require an Upgrade Marker whose phase proves target create/start has not begun; manually restore captured service IDs/states first. Verify source image/version/API, bootstrap pin, PostgreSQL topology/database, and Runner state. The CLI must reject original-source closeout at or after target-start-attempted and leave the marker in place; use same-Backup-ID Restore or stop for operator maintenance.

## Expected Results

- Every preflight error is fail-closed and leaves containers and files untouched.
- The non-elevated NTFS ACL check confirms the backup root owner is the current user, the root DACL is protected from parent inheritance, and its only explicit allow rules are Full Control for the current user, SYSTEM, and Administrators. New children inherit those rules. The private file ACL is explicit, protected, and limited to the same three identities. The current user can perform a real write/read check. The test neither reads nor writes SACL data.
- The non-elevated NTFS long-path check copies a file whose target path exceeds 260 characters, records that its source and destination parent exist during the unprefixed `Copy-Item` control, verifies the extended-path SHA256 and manifest, restores the data tree with identical contents, and safely removes only its marked fixture.
- The non-elevated bootstrap-pin test replaces an existing JSON file at a path over 260 characters, verifies the exact digest and unchanged settings, and leaves no temporary replacement files. A real read-only-file failure preserves the original JSON bytes and cleans the staged config. A second recovery-marker write replaces the prior marker and leaves no replacement backup. Failure diagnostics identify the stage and underlying exception type while masking password/token values.
- If cleanup of a previous-file backup fails after an atomic replacement, the helper restores the original destination before reporting failure; if restoration itself fails, it retains the previous file at the reported path for operator recovery.
- Backup manifest `sizeBytes` is zero for an empty file-entry list, sums multiple Hashtable values correctly, and matches the sum of manifest file entries for a real Docker E2E backup.
- E2E scenarios that lack a prerequisite Backup ID are skipped with an explicit blocked-prerequisite reason.
- Actions preflight authenticates a site administrator and uses the unfiltered instance-wide run endpoint, which includes private repositories; every page must match the official `total_count`/`workflow_runs` response before maintenance proceeds.
- Existing terminal statuses (`success`, `failure`, `cancelled`, `skipped`) remain accepted. A `completed` run is accepted only with a recognized conclusion (`success`, `failure`, `cancelled`, `skipped`) and a valid timezone-qualified `completed_at` value. Active states (`running`, `waiting`, `queued`, `blocked`), missing fields, malformed completion data, unknown states, and incomplete pages stop maintenance.
- The new Gitea container is not created until a complete, integrity-verified backup exists.
- Backup storage is outside all live Gitea/PostgreSQL writable mounts, has a restrictive Windows ACL, and no command silently deletes a prior backup.
- Restore requires a valid Backup ID, intact manifest/checksums, and a typed confirmation naming that ID and the overwritten instance.
- Restore validates that the archive's embedded database name matches the configured Gitea database, then uses `pg_restore --clean --create` to recreate that database from the backup point. It does not recreate the PostgreSQL container or touch another database.
- Restore preserves the overwritten failed state separately and never starts an old Image against the upgraded database.
- If database restore fails, the diagnostic backup and recovery marker remain and automatic bootstrap stays blocked.
- An incomplete lifecycle operation blocks automatic bootstrap startup until an explicit restore completes successfully.
- PostgreSQL and Runner container identities/storage are preserved; Compose 46300 and unrelated services are untouched.
- No live acceptance is reported from the isolated simulation.
- The integration fixture never binds `0.0.0.0`, never uses Compose port `46300`, and never targets the production container names or shared Runner.

## Evidence To Capture

- sanitized command output and exit status
- for the NTFS ACL test, record non-elevated status, NTFS volume, owner SID, protected-DACL result, exact allowed SIDs, inheritance results, and ownership-marker cleanup; do not capture SACL contents
- for the NTFS long-path test, record NTFS volume, source/parent existence, target character count, unprefixed `Copy-Item` outcome, checksum/manifest result, restored-content comparison, and ownership-marker cleanup
- for the NTFS bootstrap-pin test, record PowerShell/.NET versions, NTFS volume, extended config path length, existing-file replacement, digest and unchanged-settings checks, forced-failure exception type/stage, original-file equality, temporary-file cleanup, and ownership-marker cleanup; do not capture fixture secret values
- when a Docker operation fails, record its named fixture stage, Docker subcommand, and sanitized stderr; confirm no database/admin password or complete credential-bearing argument is present
- container action order from the test Docker boundary
- Backup IDs, manifest/checksum validation results, byte sizes, and free-space readings
- source/target image digests and container mount/port/network identity
- restore diagnostic snapshot ID and confirmation result
- for authorized live acceptance only: before/after topology, health/API result, and the API/Git/Registry/Actions/Runner/Run Attempt smoke results

## Current Execution Result

- Latest Windows Host report before the ACL correction: `npm ci`, `npm run typecheck`, and Pester passed (32/32). Docker E2E passed PostgreSQL readiness, fixture initialization, and the real Actions API preflight, then failed while setting the backup ACL with `PrivilegeNotHeldException: SeSecurityPrivilege`. The test volume was healthy NTFS and the shell was non-elevated. Root cause: PowerShell `Set-Acl` first persists `AccessControlSections.All`, which includes Audit/SACL; after a privilege failure it retries with a reduced section set only when its audit-rule/protection heuristic permits it. The SACL requires `SeSecurityPrivilege`; the observed path still requested it. The direct .NET `FileSystemSecurity` persistence now changes only DACL rules. References: [PowerShell Set-Acl provider source](https://github.com/PowerShell/PowerShell/blob/master/src/System.Management.Automation/namespaces/FileSystemSecurity.cs), [Microsoft SACL privilege requirements](https://learn.microsoft.com/en-us/windows/win32/secauthz/sacl-access-right), [.NET Framework changed-section persistence](https://github.com/Microsoft/referencesource/blob/main/mscorlib/system/security/accesscontrol/filesecurity.cs). No service operation was authorized or performed.
- The ACL implementation now reads only the DACL and owner, preserves the existing current-user owner, modifies only access rules through .NET `FileSystemSecurity`, then reads back and validates the protected DACL and exact allowed ACEs. SACL data is not read or written. Any owner, inheritance, or rule mismatch throws before backup/upgrade proceeds.
- Added a real NTFS Pester test under the `WindowsAcl` tag and a focused `npm run test:gitea-lifecycle:acl` command. It uses a GUID-owned temp directory, verifies actual owner and DACL rules on directory and file objects, checks inherited child access and current-user read/write, and removes only the marked test directory. Post-fix Windows Pester and Docker E2E have not yet been run; no post-fix pass is claimed.
- This workspace cannot establish the Windows result unless native Windows PowerShell and Docker are reachable; record any attempted local/interop command separately and leave Windows verification pending until the actual host rerun.
- This WSL pass attempted `npm run test:gitea-lifecycle`; it exits 127 because the `powershell` command is not installed. Direct `powershell.exe` interop using the WSL UNC path failed at startup with `UtilBindVsockAnyPort:307: socket failed 1`. No post-fix Pester result is claimed. The Docker E2E was not run and remains pending on Windows; no acceptance pass is claimed.
- Windows Host report: `npm ci`, `npm run typecheck`, and mocked Pester unit tests (19/19) passed. The opt-in Docker E2E ran under Pester 6.2.0 and all three cases failed. The first reported `No modules named 'gitea-lifecycle' are currently loaded`; the next two failed because the fixture had not initialized and its Backup ID was empty.
- Root cause: the test selected cases with `$script:dockerE2EEnabled` set at file scope during Discovery, then reused that Discovery-only value in Run's `BeforeAll`. With Pester 6's isolated Discovery/Run phases, Run skipped fixture initialization and module loading. The E2E now applies opt-in only to `Describe` selection, rechecks the environment in Run, dot-sources its helper file and imports the lifecycle module before fixture initialization. Initialization errors are rethrown as explicit fixture failures.
- Cleanup now registers exact fixture container IDs and verifies the run label or GUID network plus expected mounts before removing them. It verifies the owned network ID/label and a run-specific temp-directory ownership marker before cleanup; unverified resources and fixture data are preserved.
- Docker CLI failures during fixture setup and teardown now report the operation stage, Docker subcommand, exit code, and bounded stderr after redacting credential assignments and known password values. No separate fixture initialization logic defect was confirmed by code inspection; the prior Run-phase setup issue is already fixed.
- Follow-up code inspection confirmed a PostgreSQL readiness race: the official image starts a temporary initialization server that listens only on its Unix socket, and the old `pg_isready` call omitted `-h`, so it could accept the socket-only server. Fixture readiness now requires `pg_isready -h 127.0.0.1` followed by authenticated `psql "SELECT 1"` over TCP, with one-second connection timeouts and a maximum of 60 attempts before fixture SQL begins.
- Added two Pester regression cases for the socket-only false positive, transient TCP/SQL failures, the retry bound, and `PGPASSWORD` redaction.
- The Windows operator confirmed the failed E2E left no fixture containers, network, or temporary directory behind.
- This pass attempted Pester through Windows PowerShell interop, but Pester 6.2.0 could not resolve the WSL workspace path (`Directory.GetParent` reported an unsupported path format). The new Pester cases and Docker E2E were not run; no Pester or Docker E2E pass is claimed.
- This pass added Pester cases for stage/subcommand selection and credential redaction, but did not run them: launching `powershell.exe` through WSL failed with `UtilBindVsockAnyPort:307: socket failed 1`. Pester and Docker E2E were not executed in this pass.
- The post-fix Windows Pester/Docker E2E rerun remains pending. No post-fix Docker E2E pass is claimed.
- Latest Windows Host report before the long-path patch: real NTFS ACL passed 1/1 and Pester passed 33/33. Docker E2E completed fixture initialization, the real Actions preflight, and backup ACL setup, then raised `DirectoryNotFoundException` from `Copy-DirectoryTree` at `gitea-lifecycle.psm1:835` while copying a Git Object to a reported 268-character target. The two later E2E failures only lacked the Backup ID created by the failed first case. The lifecycle flow stops Gitea and Runner before the snapshot, and fixture cleanup runs after the test, so code inspection found no concurrent source-deletion or destination-cleanup path during this copy. The path length crossing the traditional 260-character limit is the leading cause; the original run did not capture source and target-parent existence at the exact failing call, so the controlled `WindowsLongPath` diagnostic must confirm that distinction on the host.
- The lifecycle file operations now normalize paths lexically and pass absolute `\\?\` paths to .NET file/directory APIs for traversal, copy, SHA256, manifest read/write, validation, ACL operations, restore and cleanup. This avoids dependence on Windows registry or machine policy and retains reparse-point checks, backup-root isolation, DACL enforcement and fail-closed exceptions. The new real-NTFS regression covers copy, checksum, manifest validation, restore and safe cleanup. Windows Pester and Docker E2E have not been run after this patch; no pass is claimed.
- This WSL workspace has Windows PowerShell/Pester installed through Windows interop, but Pester cannot resolve the Linux workspace current directory (`Directory.GetParent` reports an unsupported path format); no post-fix Pester result is claimed.
- Passed in this WSL pass: `npm run validate:platform`, `git diff --check`, and `package.json` JSON parsing.
- Not executed in WSL: Pester; `npm run test:gitea-lifecycle` exits 127 because `powershell` is not installed in WSL.
- Not completed: Typecheck; `npm run typecheck` exits 1 because `node_modules/typescript/bin/tsc` is absent. The earlier `npm ci` attempt could not fetch `@types/node` because `registry.npmjs.org` returned `EAI_AGAIN`; it was not retried in this pass.
- Not executed in WSL: Docker E2E; `npm run test:gitea-lifecycle:docker-e2e` exits 127 because `powershell` is not installed. Separately, `docker info` is denied access to `/var/run/docker.sock` in WSL.
- No PowerShell/Pester, TypeScript, or Docker E2E result is marked passed.
- No live Gitea, PostgreSQL, Runner, or Compose service was operated.
- Latest Windows Host report for this continuation: real NTFS long-path test passed 1/1 and full Pester passed 34/34. Docker E2E passed fixture setup, Actions preflight, ACL setup, long-path copy, and PostgreSQL dump, then failed in `New-GiteaBackupSet` at `Measure-Object -Property sizeBytes -Sum` because `Get-BackupFileEntries` returns Hashtable entries. The later two E2E failures lacked the first Backup ID, and teardown failed when `Remove-Item -Recurse` reached the long-path fixture tree. This patch adds Hashtable-safe aggregation, an E2E manifest-total assertion, blocked-prerequisite skips, and a Run ID/marker/owner/path/reparse-verified extended-path cleanup tool. Post-patch Windows Pester and Docker E2E remain pending; no Docker E2E pass is claimed.
- Windows PowerShell 5.1 (`5.1.26100.9711`) on .NET Framework (`4.0.30319.42000`) ran a disposable NTFS compatibility probe. `[System.IO.File]::Replace(source, destination, $null)` failed for both ordinary and extended-length paths with `System.ArgumentException` / HRESULT `0x80070057`; supplying a unique same-directory backup path succeeded for both, including a 406-character path. A read-only destination with a named backup failed with `System.UnauthorizedAccessException` and left the original readable and unchanged. This confirms the production helper's null backup argument as the image-pin failure cause and validates the named-backup API on extended paths. The probe fixture was removed.
- The focused `WindowsBootstrapPin` test then passed 5/5 under Windows PowerShell 5.1/Pester 6.2.0. It ran the module against real NTFS temporary fixtures, including an extended-length bootstrap path, and removed its owned fixtures. The combined non-Docker lifecycle suite reported 43 passed and one failed: the pre-existing `WindowsAcl` test could not inspect `whoami.exe /priv` in this WSL Windows-interop session; a direct probe returned no stdout and no exit code. This does not establish the ACL case as passed or failed on a native Windows shell; rerun the full suite there.
- The prior isolated Docker E2E reached Gitea startup and API/version health checks, then failed while setting the bootstrap image pin; the two dependent cases were skipped because no Backup ID was produced. The `File.Replace` fix and diagnostic changes have not been followed by another Docker E2E run. No post-fix E2E pass or live-service acceptance is claimed.
- Minimum native Windows Host rerun from the repository root, using a non-elevated Windows PowerShell 5.1 session: `npm run test:gitea-lifecycle:bootstrap-pin`, then `npm run test:gitea-lifecycle`. The first isolates the reported regression. The Docker E2E remains a separate opt-in acceptance run and was intentionally not repeated in this pass.

## Native Windows isolated acceptance — 2026-11-06 (PR #4, head `071cb08`)

The operator executed these tests from non-elevated native Windows PowerShell 5.1 with Pester 6.2.0:

- `npm run test:gitea-lifecycle:bootstrap-pin`: **5 passed, 0 failed, 0 skipped**. Includes real-NTFS existing-file replacement, recovery-marker replacement, read-only failure safety, rollback on temporary-backup cleanup failure, and credential redaction.
- `npm run test:gitea-lifecycle`: **44 passed, 0 failed, 0 skipped**. The prior WSL-interop-only ACL preflight failure did not reproduce on the native host.
- `AGENT_SDLC_GITEA_DOCKER_E2E=1` with `npm run test:gitea-lifecycle:docker-e2e`: **3 passed, 0 failed, 0 skipped**. The isolated Gitea fixture upgraded from 1.25.5 to 1.26.4; backup creation/listing, manifest integrity and size, and HTTP/API checks passed. The next case injected a post-migration failure at 1.27.3, retained recovery evidence, and stopped the fixture Runner. Explicit restore to the 1.26.4 snapshot succeeded, including deletion of a post-backup table, preservation of an unrelated PostgreSQL database, and unchanged PostgreSQL/Runner container identities.
- The ownership-verified teardown removed fixture `agent-sdlc-life-e2e-0fed2f593b394ce3ad53103b961e46e4`. No cleanup failure was reported.

**Acceptance boundary:** This completes *isolated implementation acceptance* for PR #4 only. No upgrade, backup/restore operation, or production smoke verification has been carried out on the real legacy `127.0.0.1:43000` service. Before Issue #3 can be closed, schedule a separately authorized live maintenance window, verify topology/capacity/upgrade path and restoration prerequisites, and record API, Git read/write, Registry, Actions dispatch/Runner, Run Attempt, and representative-integration smoke evidence. Keep `local-agent-infra#29` E2E separate.

## Actions preflight compatibility rerun — 2026-11-08

The current non-Docker lifecycle suite was run under Windows PowerShell 5.1 (`5.1.26100.9711`) with Pester 6.2.0. To avoid Pester's .NET Framework failure on the WSL UNC workspace path, the five required test/module files were copied to a GUID-named Windows temp directory, executed there, and removed after verifying the exact path and ownership marker.

- Full suite: **45 passed, 1 failed**. The sole failure was the existing `WindowsAcl` precondition: `whoami.exe /priv` returned no output/no exit code through this WSL interop launch. This matches the previously recorded interop limitation and does not establish the ACL case as passed or failed on a native Windows shell.
- Rerun excluding only `WindowsAcl`: **45 passed, 0 failed, 0 skipped**. This includes the new completed/conclusion/timestamp acceptance cases, missing and invalid field cases, active/unknown status rejection, legacy terminal statuses, pagination checks, and the rest of the non-Docker lifecycle tests.
- No Docker E2E was run. No live Gitea, PostgreSQL, shared Runner, configured backup directory, or upgrade operation was accessed.

## RepoDigest and recovery reconciliation rerun — 2026-11-08

The Windows PowerShell 5.1 repro confirmed that piping a top-level `ConvertFrom-Json` array into an assignment produced a single string with the RepoDigest entries separated by spaces. The prior selector accepted that concatenation as one candidate because its expression only constrained the string prefix/suffix. Parsing the array as an object property preserves element boundaries; the resolver now validates entries and returns exactly one official immutable Gitea digest (or a validated local image ID where registry pinning is not required).

The incident report identifies checksum-valid backup `20261108T053419Z-a5737137148a41a9bc45d6f7a78485df`, unchanged original Gitea/PostgreSQL/Runner container IDs after manual recovery, and a retained Recovery Marker. These are recorded reports only; this implementation run did not inspect or operate the formal backup, services, or marker.

- Focused parser/pre-stop/recovery-reconciliation Pester cases: **10 passed, 0 failed**. The parser-only red run before the fix was **1 passed, 4 failed**, with failures showing the multi-digest concatenated string.
- Full Windows PowerShell 5.1/Pester 6.2.0 suite: **55 passed, 1 failed**. The only failure was the pre-existing WSL interop `WindowsAcl` prerequisite (`whoami.exe /priv` returned no output). Excluding only that tag: **55 passed, 0 failed, 0 skipped**.
- The Docker E2E discovered five cases but stopped in `BeforeAll` because the available engine did not identify as Docker Desktop. No E2E fixture container, network, or data tree was created. Rerun on native Windows with Docker Desktop to validate digest-to-image resolution and the manual source-recovery reconciliation flow end to end.
- No formal Gitea, PostgreSQL, Runner, backup, Recovery Marker, or lifecycle operation was accessed or changed.

## PR #6 legacy backup compatibility follow-up — 2026-11-08

Added a regression for the exact schema-1 backup form: two identical official Gitea digest references plus one `gitea/gitea` alias at the same SHA, joined by single ASCII spaces and matched by manifest fields. Reconciliation records that the legacy reference was handled but never records or uses it as an image digest; Restore continues through strict `Get-BackupRuntime` validation and rejects the same reference. The unmocked topology assertion covers the prior second rejection point. The isolated Docker E2E changes only its GUID-owned backup fixture, recomputes its manifest checksum, checks Restore rejection, and then exercises no-restore reconciliation.

- Per maintainer direction, **native Windows Pester and Docker E2E have not been run on this follow-up PR head yet**. The 55/55 Pester result above applies to the preceding PR #6 commit and is not evidence for these additions.
- No formal Gitea, PostgreSQL, Runner, backup, Recovery Marker, or lifecycle operation was accessed or changed.

## Current PR #6 implementation and acceptance status — 2026-11-10

The implementation now includes schema-2 backup manifests with metadata digest and exact file-set/size validation; schema-3 Recovery Marker revisions; schema-versioned Gitea runtime, PostgreSQL topology, and Restore Context artifacts; PostgreSQL full-ID/database-name/database-user matching; append-only terminal attempt records; same-Backup-ID Restore handoff/retry; read-only `status`/`backup-list`; the `up`/`down` marker command matrix; Windows CRT-compatible process arguments; immutable RepoDigest parsing; and healthy-target/restore-complete/original-source recovery modes. Original-source closeout is rejected when the marker phase means target create/start may have begun, and closeout validates the bootstrap image pin. Upgrade, Restore, and reconciliation inspect effective `app.ini`, Gitea environment overrides, and command-line config paths; they fail closed on external/custom storage or local paths outside the captured Gitea data/config mounts. E2E fixtures use a real registered host-label Runner and real Git, Actions, ORAS Registry, PostgreSQL, container identity, and bind-mount boundaries. A true Docker name-conflict fault covers the pre-target rename stage; target network detach covers a post-create failure and fresh-process Marker reload. The suite contains real backup producers and Restore consumers for the adjacent version path.

No current-head PowerShell/Pester or Docker Desktop acceptance result is available from this WSL environment. `npm run validate:platform` passed. `npm run typecheck` could not start because `node_modules/typescript/bin/tsc` is absent. `npm run test:gitea-lifecycle` exited 127 because `powershell` is not installed in WSL. The available `powershell.exe` native Windows launcher was also attempted, but WSL interop failed before PowerShell started with `UtilBindVsockAnyPort:307: socket failed 1`. Read-only `docker --context desktop-linux info` failed with `Failed to initialize: protocol not available`; the default Docker socket is not usable from this WSL session. The previously recorded Pester 55/55 excluding the ACL interop precondition applies to an earlier commit and does not validate current PR #6. No tests were run through WSL as a substitute for native Windows PowerShell 5.1.

| AC | Current code/test coverage | Current-head result |
|---|---|---|
| AC-01 | Native PowerShell 5.1 child-process argv echo case covers empty, whitespace, Unicode, quote, slash, and multi-argument inputs. | Not run; not accepted |
| AC-02 | RepoDigests array boundary, malformed/mixed/duplicate cases, immutable reference selection, and digest-to-image identity checks are implemented in unit/E2E cases. | Not run; not accepted |
| AC-03 | Marker schema 1/2/3 parsing, atomic revision updates, and fresh-process reload checks for two injected failure points are covered; the full transition/interruption matrix is not. | Partial coverage; not run; not accepted |
| AC-04 | Manifest metadata digest, exact files, duplicate/path checks, per-file hashes/sizes, total bytes, schema-versioned runtime/topology/Restore Context, PostgreSQL full ID/database identity, and effective local-storage coverage checks are implemented. | Not run; not accepted |
| AC-05 | Real NTFS ACL, long-path, replacement, bootstrap-pin, and cleanup cases exist. | Not run on current head; not accepted |
| AC-06 | Marker command guards, read-only status/list, CLI aliases, and pure-read status regressions are implemented; the full operator-script command/exit-code matrix is incomplete. | Partial coverage; not run; not accepted |
| AC-07 | Disposable image-declared volumes must have exact owned bind mounts; fixture identity and cleanup checks are present. | Not run on Docker Desktop; not accepted |
| AC-08 | Real PostgreSQL dump/restore E2E checks Gitea database replacement, unrelated database preservation, and stable PostgreSQL identity. | Not run; Restore-stage fault matrix is incomplete; not accepted |
| AC-09 | Real producer/consumer test path covers `1.25.5 → 1.26.4 → 1.27.3 → 28.3.0` with each produced upgrade Backup ID consumed by Restore. | Not run; not accepted |
| AC-10 | Real Gitea API preflight and existing parser tests cover admin identity, pagination, and active/unknown run refusal. | Not run on current head; not accepted |
| AC-11 | Real Git client clone/fetch/push and commit-ref comparison are in the Docker E2E. | Not run; not accepted |
| AC-12 | ORAS 1.3.5 test covers credential refusal, push, tag/digest pull, package details, and delete. | Not run; not accepted |
| AC-13 | Real Actions dispatch is correlated through Runs API, then jobs and logs are checked; a 204 response is not treated as a Run ID. | Not run; not accepted |
| AC-14 | Real-run attempt checks branch by observed Gitea version/API shape and cover legacy missing/zero versus newer attempt resources. | Not run; not accepted |
| AC-15 | Real host-label Runner registration, first canary, Runner restart, second canary, and job logs are in the E2E. | Not run; not accepted |
| AC-16 | Real Docker rename conflict and post-create network detach cover two Upgrade fault points; fresh PowerShell process reload is asserted. Same-Backup-ID Restore retry/handoff is implemented, but retry fault injection and most U0–U9/R0–R9/C1–C2 pre/post interruption cases are not implemented or run. | Partial implementation; not accepted |

AC-17 formal `43000` acceptance, production Recovery Marker/backups, and formal Upgrade/Restore/Reconcile were not touched. AC-18 `local-agent-infra#29` remains separate and was not run. The PR must remain open for review; implementation acceptance is pending native Windows PowerShell 5.1 and isolated Docker Desktop evidence, and the larger AC-16 matrix remains a known gap.

## A0 — Pester ExitCode Propagation

This is the independent A0 harness repair based on frozen PR #6 head `a1ebbe9`. It changes only the npm-to-PowerShell Pester invocation boundary. It does not change Lifecycle behavior, fix other Pester failures, or expand AC-16. The focused Windows cases below exercise a passing Pester run, an intentional Pester failure, and a run with no tests discovered:

```powershell
npm run test:gitea-lifecycle:exitcode:pass
$passExitCode = $LASTEXITCODE
npm run test:gitea-lifecycle:exitcode:fail
$failExitCode = $LASTEXITCODE
npm run test:gitea-lifecycle:exitcode:no-tests
$noTestsExitCode = $LASTEXITCODE

if ($passExitCode -ne 0 -or $failExitCode -eq 0 -or $noTestsExitCode -eq 0) {
    throw "Unexpected Pester ExitCodes: pass=$passExitCode, intentional-fail=$failExitCode, no-tests=$noTestsExitCode"
}
"PASS: pass=$passExitCode; intentional-fail=$failExitCode; no-tests=$noTestsExitCode"
```

Expected Pester output is retained, including Passed/Failed/Skipped counts. The pass fixture should report one Passed test and ExitCode 0; the intentional-failure fixture should report one Failed test and a nonzero ExitCode; the no-tests fixture must also return nonzero. Run from a native Windows checkout with Node.js/npm, Windows PowerShell 5.1, and Pester 5 or 6.2.0.

Current WSL attempt is not Windows acceptance evidence. Windows PowerShell `5.1.26100.9711` and Pester `6.2.0` were visible through interop, but Pester discovery from the workspace UNC path `\\wsl.localhost\...` stopped in `FindRepoRoot` with `NotSupportedException` before tests were discovered; the old inline `Invoke-Pester` command returned process ExitCode 0. A later npm attempt through WSL interop failed before PowerShell started (`UtilBindVsockAnyPort:307: socket failed 1`) and npm returned 1. Native Windows execution of all three focused cases remains pending.

## Cleanup

Use disposable test directories/containers only. Do not delete backup fixtures as part of the tested lifecycle operation; test teardown may remove only the isolated temporary fixture after evidence is captured.

For a leftover Docker E2E temp directory, first confirm no matching fixture containers or network remain for this exact run ID. The standalone cleanup command derives the allowed path from `%TEMP%` plus the exact GUID Run ID, verifies the path, root and marker owners, marker JSON, and every descendant's Reparse Point status, then requires the same ID as `-ApproveRunId` and PowerShell confirmation before deleting. Run the preview first and review every printed value:

```powershell
$runId = "90ffd2e1df0741c4a05b256e2cff4308"
docker ps -a --filter "label=agent-sdlc.lifecycle-e2e.run-id=$runId" --no-trunc
docker network ls --filter "label=agent-sdlc.lifecycle-e2e.run-id=$runId"
$fixturePath = Join-Path $env:TEMP "agent-sdlc-life-e2e-$runId"
& .\scripts\dev\cleanup-gitea-lifecycle-e2e-fixture.ps1 -RunId $runId -ExpectedPath $fixturePath -WhatIf
& .\scripts\dev\cleanup-gitea-lifecycle-e2e-fixture.ps1 -RunId $runId -ExpectedPath $fixturePath -ApproveRunId $runId -Confirm
```

The preview must identify the expected GUID path, matching ownership marker, current-user owner SID, and no reparse points. If any check fails, leave the directory untouched and inspect it manually. For another run, use only that run's exact 32-hex GUID.

## Change Log
- 2026-11-05: Initial version from issue #3 implementation contract.
- 2026-11-05: Added exported lifecycle-command coverage for restore identity, integrity, confirmation, diagnostic snapshot, and ordered matching-state restoration gates.
- 2026-11-05: Added unexecuted Windows Docker E2E coverage and recorded the WSL PowerShell, Docker socket, and npm dependency-install limitations.
- 2026-11-05: Fixed the isolated failure path to use the valid `1.26.4` to `1.27.3` step and added exact database recreation plus post-backup-table and unrelated-database assertions; Windows execution remains pending.
- 2026-11-06: Recorded the Windows Host Discovery failure and corrected test-module loading and TestDrive timing; post-fix Windows Pester rerun remains pending.
- 2026-11-06: Recorded Windows Pester 6.2.0 results (three Docker E2E failures; unit suite 19/19 passed), moved fixture setup/helpers into Run, and tightened ownership-verified cleanup; post-fix E2E remains pending.
- 2026-11-06: Recorded Windows Pester 33/33 and NTFS ACL 1/1, followed by the isolated E2E `DirectoryNotFoundException` at a 268-character copy target; added a real-NTFS long-path diagnostic/regression and updated the host rerun sequence. Post-patch Windows results remain pending.
- 2026-11-06: Added stage/subcommand and credential-redacted Docker stderr diagnostics; code inspection found no additional confirmed fixture initialization defect, and Windows E2E acceptance remains pending.
- 2026-11-06: Confirmed the socket-only PostgreSQL initialization readiness race; added TCP plus authenticated SQL readiness checks with a 60-attempt bound and Pester regression cases. Native Windows Pester and Docker E2E reruns remain pending.
- 2026-11-06: Recorded Windows Pester 23/23 and successful isolated fixture initialization before the Actions-preflight E2E failure; replaced repository enumeration with Gitea 1.25.5's paginated instance-wide admin run endpoint, added contract-shaped Pester cases, and retained the unmocked real API preflight in Docker E2E. Post-fix Windows Pester and Docker E2E remain pending.
- 2026-11-06: Recorded Windows long-path 1/1 and Pester 34/34, plus Docker E2E failure at Hashtable byte aggregation and long-path teardown. Added empty/multi-entry byte-sum coverage, a manifest-total assertion, blocked-prerequisite skips, and GUID/marker/owner/path/reparse-verified long-path fixture cleanup. Post-patch Windows verification remains pending.
- 2026-11-06: Added direct real-NTFS bootstrap image-pin coverage for extended-length replacement, digest/settings preservation, read-only failure safety, secret-masked diagnostics, recovery-marker replacement, and fixture cleanup. Native PowerShell compatibility evidence confirms `File.Replace` needs a named same-directory backup on .NET Framework; Pester and Docker E2E reruns remain pending because the WSL UNC workspace is unsupported by Pester's repo-root discovery.
- 2026-11-06: Added upgrade-level assertions that the masked stage/type/cause survive the outer catch and added rollback coverage for a failed temporary-backup cleanup after replacement. Native Pester remains pending on the Windows checkout.
- 2026-11-06: Focused real-NTFS bootstrap-pin Pester passed 5/5. Combined non-Docker lifecycle Pester was 43/44; the only failure was the Windows ACL test's `whoami.exe /priv` precondition under WSL interop. Recorded the null-backup root cause and fix; post-fix Docker E2E remains unrun.
- 2026-11-06: Native Windows PowerShell 5.1 accepted bootstrap pin 5/5 and full Pester 44/44; GUID-isolated Docker E2E passed 3/3 with verified fixture cleanup. Real 43000 maintenance and smoke acceptance remain outstanding.
- 2026-11-08: Added the Run #95 `completed` / `failure` / completion-time compatibility regression while retaining legacy terminal acceptance and fail-closed cases. No formal Gitea service was contacted.
- 2026-11-08: Ran the non-Docker suite under Windows PowerShell 5.1/Pester 6.2.0: 45/46 passed, with only the known WSL interop `WindowsAcl` precondition failing; rerun excluding that tag passed 45/45. The GUID-owned Windows temp copy was removed; no service was accessed.
- 2026-11-08: Recorded the RepoDigest array-concatenation root cause, pre-stop Upgrade/Restore validation, and operator-attested Recovery Marker reconciliation. Pester passed 55/55 excluding the WSL interop ACL prerequisite; Docker E2E awaits native Docker Desktop.
- 2026-11-08: Added schema-1 triple-digest reconciliation compatibility, a strict Restore rejection assertion, and an isolated E2E that mutates only its owned backup fixture. Updated-head native Pester and Docker E2E remain pending per maintainer direction.
