# TC-011: Local Gitea Version Lifecycle Operations

## Metadata
- Test ID: TC-011
- Status: In Progress
- Last Updated: 2026-11-06
- Owner: Project Maintainer
- Mode: Windows PowerShell/Pester safety tests, isolated Docker acceptance, and separate manual Windows Host acceptance
- Related Docs / WBS: GitHub issue #3; WBS `3.12`; `docs/issues/items/I-007-gitea-version-lifecycle-operations.md`
- Source Dashboard: docs/testing/test-dashboard.md
- Source Template: docs/templates/test-case.template.md

## Objective

Verify the operator-facing upgrade, backup-list, and restore commands protect the legacy Gitea data boundary and fail closed before unsafe changes.

## Scope

Run the automated Pester suite against temporary directories and a mocked Docker/API boundary through the exported lifecycle command. It covers supported version steps, backup path separation, checksum validation, upgrade ordering and health-failure behavior, recovery-marker/image-pin ordering, source-service recovery after stop failure, restore Backup ID and manifest gates, typed-confirmation refusal, exact PostgreSQL database recreation, and diagnostic-backup retention after restore failure without opening a Docker connection. The tagged `WindowsAcl` test additionally runs against real NTFS from non-elevated Windows PowerShell: it calls the exported backup-list command with a GUID-named temporary backup root, checks the actual owner and DACL, confirms directory inheritance and child access, then exercises the real file ACL helper without mocking. It refuses to treat an elevated run as a pass and checks that `SeSecurityPrivilege` is not enabled. The test never reads or writes the SACL and never uses the configured/formal backup path. For the Actions upgrade preflight, Pester responses follow the Gitea 1.25.5 `ActionWorkflowRunsResponse` contract (`total_count` plus `workflow_runs`), covering an empty list, private-repository runs, terminal/active/unknown statuses, complete and incomplete pagination, non-admin identities, malformed responses, and API errors. The preflight first verifies `/api/v1/user` reports `is_admin`, then pages the unfiltered instance-wide `GET /api/v1/admin/actions/runs`; it does not enumerate repositories, so private repositories are covered by the site-admin endpoint. Gitea 1.25.5 documents `page` and `limit` on this endpoint, its admin handler calls the shared run listing with both owner and repository IDs set to zero, and its run status values are `success`, `failure`, `cancelled`, `skipped`, `waiting`, `running`, `blocked`, or `unknown` ([API contract](https://docs.gitea.com/api/1.25/operations/list-admin-workflow-runs/), [v1.25.5 admin handler](https://github.com/go-gitea/gitea/blob/v1.25.5/routers/api/v1/admin/action.go), [v1.25.5 API route and site-admin guard](https://github.com/go-gitea/gitea/blob/v1.25.5/routers/api/v1/api.go), [v1.25.5 status values](https://github.com/go-gitea/gitea/blob/v1.25.5/models/actions/status.go)).

The opt-in Docker E2E creates GUID-named Gitea/PostgreSQL/Runner fixtures with isolated bind mounts and publishes only on `127.0.0.2`; its lifecycle operations use the real fixture Gitea API, including the Actions preflight, without mocking `Assert-NoActiveGiteaActions` or `Invoke-GiteaApiRead`. The empty-run preflight therefore verifies the actual admin endpoint and response contract. Before fixture SQL changes data, it waits for PostgreSQL to accept loopback TCP connections and for authenticated `SELECT 1` to succeed over TCP. It then upgrades from `1.25.5` to `1.26.4`, checks backup listing/integrity, then starts `1.27.3` and injects a failure after the new version is reachable. It explicitly restores the `1.26.4` pre-failure backup, verifies a table added after that backup disappears, confirms existing repository data remains, and verifies an unrelated database in the same PostgreSQL container is unchanged. The E2E snapshots all pre-existing container identities/states and removes only fixture container IDs whose label or GUID-scoped network and exact bind mounts confirm ownership. The network and temp directory are removed only after their run ID and ownership marker are verified.

Live acceptance for the real 43000 instance is a separate, authorized Windows Host operation. It must also cover API, Git read/write, Registry access, Actions dispatch and Runner execution, Run Attempt visibility, and representative integrations. The local-agent-infra #29 E2E remains a separate result.

## Preconditions

- Use native Windows PowerShell with Pester 5 or 6.2.0, Node.js 22+, npm, and a Docker Desktop engine.
- Run `npm run test:gitea-lifecycle:acl` from non-elevated Windows PowerShell to exercise real NTFS rules; if the test reports skipped because the shell is elevated, rerun it from a standard non-admin session.
- The real ACL check uses only a GUID-named temp directory with an ownership marker. It does not modify the configured backup root or any existing backup.
- The Docker E2E requires `AGENT_SDLC_GITEA_DOCKER_E2E=1`; it refuses occupied test endpoints and runs Gitea at `127.0.0.2:43000`, isolated from a legacy service bound to `127.0.0.1:43000`.
- The E2E's Runner is an inert disposable container used to verify identity and stop/start handling; it does not validate Actions registration or job execution.
- Never point tests at the real Gitea containers, host mounts, repository, Registry, or shared Runner.
- For live acceptance, use native Windows PowerShell, verify the actual legacy container topology and disk capacity, review the official upgrade path, and obtain separate explicit authorization.

## Test Data

- Current and target Gitea versions with allowed same-series/next-series transitions.
- A temporary legacy-style Gitea and PostgreSQL container description with bind-mounted data/config, port 43000, and an isolated Runner.
- Corrupt/missing manifest, changed checksum, insufficient-space, and active-job fixtures.
- Backup set containing database dump, data/config trees, sensitive bootstrap payload, private runtime topology, and a manifest.
- A second database with a sentinel row plus a table created in the Gitea database after the selected backup, to prove database scope and exact restoration.

## Steps

1. Run `npm ci`, `npm run typecheck`, `npm run test:gitea-lifecycle:acl`, and `npm run test:gitea-lifecycle`; record each exit status separately. Run the ACL command from non-elevated PowerShell; a skipped result from an elevated shell is not an ACL-test pass.
2. On a Windows test host, run `status` and confirm existing commands remain read-only with respect to containers.
3. Run `upgrade` without a version, with a floating tag, an unsupported version jump, an unexpected port/mount/network, or active Runner jobs; confirm each stops before service mutation.
4. Force insufficient backup space and confirm no older backup is removed and no container is stopped/recreated.
5. Run `npm run test:gitea-lifecycle`; confirm the Actions preflight checks admin identity, accepts the official empty response, sees private-repository runs, pages every result, rejects incomplete pages and unknown/active statuses, and fails closed on malformed responses and API errors. Also confirm the readiness regressions reject socket-only readiness, require authenticated TCP `SELECT 1`, retry transient failures, stop after 60 attempts, and redact `PGPASSWORD`.
6. Set `$env:AGENT_SDLC_GITEA_DOCKER_E2E = "1"` and run `npm run test:gitea-lifecycle:docker-e2e`; confirm it uses only GUID-named fixtures, an isolated network and bind mounts, and the `.2` loopback endpoints. Confirm fixture upgrades use the real Gitea `/user` and `/admin/actions/runs` API preflight with no mock at either preflight seam. Before fixture SQL setup, confirm the helper uses `pg_isready -h 127.0.0.1` and the authenticated TCP SQL check succeeds.
7. Confirm the E2E upgrades `1.25.5` to `1.26.4`, validates the retained backup and backup-list output, then requests the valid next step `1.27.3`. The test injects an API-version-check failure after startup; verify the new API reports `1.27.3`, the marker identifies the retained `1.26.4` backup, the fixture Runner stays stopped, and no automatic rollback occurs.
8. After the failed upgrade backup has been captured, create `public.lifecycle_post_backup_probe` in the fixture Gitea database. Explicitly restore the marker's `1.26.4` Backup ID. Verify the API reports `1.26.4`, the probe table is absent, the pre-existing sentinel repository remains, the separate `e2e_unrelated` database still contains its sentinel row, the marker is cleared, and the same fixture Runner and PostgreSQL container IDs remain in place.
9. Attempt restore with a missing ID, corrupt checksum, or incorrect typed confirmation; confirm live data is unchanged.
10. Confirm a valid restore creates a separate diagnostic snapshot first, then recreates only the database whose name is recorded in the selected archive. Verify files/settings/Image/topology are restored as a unit, the PostgreSQL container and unrelated databases remain unchanged, and the Runner keeps its original container and registration.
11. If separately authorized, perform the manual Windows Host acceptance sequence and record all smoke evidence before treating the service upgrade as accepted.

## Expected Results

- Every preflight error is fail-closed and leaves containers and files untouched.
- The non-elevated NTFS ACL check confirms the backup root owner is the current user, the root DACL is protected from parent inheritance, and its only explicit allow rules are Full Control for the current user, SYSTEM, and Administrators. New children inherit those rules. The private file ACL is explicit, protected, and limited to the same three identities. The current user can perform a real write/read check. The test neither reads nor writes SACL data.
- Actions preflight authenticates a site administrator and uses the unfiltered instance-wide run endpoint, which includes private repositories; every page must match the official `total_count`/`workflow_runs` response before maintenance proceeds.
- Only Gitea 1.25.5 terminal statuses (`success`, `failure`, `cancelled`, `skipped`) are accepted. Active statuses, empty/malformed statuses, and unknown values stop maintenance.
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
- This WSL workspace has Windows PowerShell/Pester installed through Windows interop, but Pester cannot resolve the Linux workspace current directory (`Directory.GetParent` reports an unsupported path format); no post-fix Pester result is claimed.
- Passed in this WSL pass: `npm run validate:platform`, `git diff --check`, and `package.json` JSON parsing.
- Not executed in WSL: Pester; `npm run test:gitea-lifecycle` exits 127 because `powershell` is not installed in WSL.
- Not completed: Typecheck; `npm run typecheck` exits 1 because `node_modules/typescript/bin/tsc` is absent. The earlier `npm ci` attempt could not fetch `@types/node` because `registry.npmjs.org` returned `EAI_AGAIN`; it was not retried in this pass.
- Not executed in WSL: Docker E2E; `npm run test:gitea-lifecycle:docker-e2e` exits 127 because `powershell` is not installed. Separately, `docker info` is denied access to `/var/run/docker.sock` in WSL.
- No PowerShell/Pester, TypeScript, or Docker E2E result is marked passed.
- No live Gitea, PostgreSQL, Runner, or Compose service was operated.

## Cleanup

Use disposable test directories/containers only. Do not delete backup fixtures as part of the tested lifecycle operation; test teardown may remove only the isolated temporary fixture after evidence is captured.

## Change Log
- 2026-11-05: Initial version from issue #3 implementation contract.
- 2026-11-05: Added exported lifecycle-command coverage for restore identity, integrity, confirmation, diagnostic snapshot, and ordered matching-state restoration gates.
- 2026-11-05: Added unexecuted Windows Docker E2E coverage and recorded the WSL PowerShell, Docker socket, and npm dependency-install limitations.
- 2026-11-05: Fixed the isolated failure path to use the valid `1.26.4` to `1.27.3` step and added exact database recreation plus post-backup-table and unrelated-database assertions; Windows execution remains pending.
- 2026-11-06: Recorded the Windows Host Discovery failure and corrected test-module loading and TestDrive timing; post-fix Windows Pester rerun remains pending.
- 2026-11-06: Recorded Windows Pester 6.2.0 results (three Docker E2E failures; unit suite 19/19 passed), moved fixture setup/helpers into Run, and tightened ownership-verified cleanup; post-fix E2E remains pending.
- 2026-11-06: Added stage/subcommand and credential-redacted Docker stderr diagnostics; code inspection found no additional confirmed fixture initialization defect, and Windows E2E acceptance remains pending.
- 2026-11-06: Confirmed the socket-only PostgreSQL initialization readiness race; added TCP plus authenticated SQL readiness checks with a 60-attempt bound and Pester regression cases. Native Windows Pester and Docker E2E reruns remain pending.
- 2026-11-06: Recorded Windows Pester 23/23 and successful isolated fixture initialization before the Actions-preflight E2E failure; replaced repository enumeration with Gitea 1.25.5's paginated instance-wide admin run endpoint, added contract-shaped Pester cases, and retained the unmocked real API preflight in Docker E2E. Post-fix Windows Pester and Docker E2E remain pending.
