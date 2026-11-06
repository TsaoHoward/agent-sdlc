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

Run the automated Pester suite against temporary directories and a mocked Docker/API boundary through the exported lifecycle command. It covers supported version steps, backup path separation, checksum validation, upgrade ordering and health-failure behavior, recovery-marker/image-pin ordering, source-service recovery after stop failure, restore Backup ID and manifest gates, typed-confirmation refusal, exact PostgreSQL database recreation, and diagnostic-backup retention after restore failure without opening a Docker connection. The opt-in Docker E2E creates GUID-named Gitea/PostgreSQL/Runner fixtures with isolated bind mounts and publishes only on `127.0.0.2`; it upgrades from `1.25.5` to `1.26.4`, checks backup listing/integrity, then starts `1.27.3` and injects a failure after the new version is reachable. It explicitly restores the `1.26.4` pre-failure backup, verifies a table added after that backup disappears, confirms existing repository data remains, and verifies an unrelated database in the same PostgreSQL container is unchanged. The E2E snapshots all pre-existing container identities/states and removes only its uniquely named resources.

Live acceptance for the real 43000 instance is a separate, authorized Windows Host operation. It must also cover API, Git read/write, Registry access, Actions dispatch and Runner execution, Run Attempt visibility, and representative integrations. The local-agent-infra #29 E2E remains a separate result.

## Preconditions

- Use native Windows PowerShell with Pester 5, Node.js 22+, npm, and a Docker Desktop engine.
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

1. Run `npm ci`, `npm run typecheck`, and `npm run test:gitea-lifecycle`; record each exit status separately.
2. On a Windows test host, run `status` and confirm existing commands remain read-only with respect to containers.
3. Run `upgrade` without a version, with a floating tag, an unsupported version jump, an unexpected port/mount/network, or active Runner jobs; confirm each stops before service mutation.
4. Force insufficient backup space and confirm no older backup is removed and no container is stopped/recreated.
5. Set `$env:AGENT_SDLC_GITEA_DOCKER_E2E = "1"` and run `npm run test:gitea-lifecycle:docker-e2e`; confirm it uses only GUID-named fixtures, an isolated network and bind mounts, and the `.2` loopback endpoints.
6. Confirm the E2E upgrades `1.25.5` to `1.26.4`, validates the retained backup and backup-list output, then requests the valid next step `1.27.3`. The test injects an API-version-check failure after startup; verify the new API reports `1.27.3`, the marker identifies the retained `1.26.4` backup, the fixture Runner stays stopped, and no automatic rollback occurs.
7. After the failed upgrade backup has been captured, create `public.lifecycle_post_backup_probe` in the fixture Gitea database. Explicitly restore the marker's `1.26.4` Backup ID. Verify the API reports `1.26.4`, the probe table is absent, the pre-existing sentinel repository remains, the separate `e2e_unrelated` database still contains its sentinel row, the marker is cleared, and the same fixture Runner and PostgreSQL container IDs remain in place.
8. Attempt restore with a missing ID, corrupt checksum, or incorrect typed confirmation; confirm live data is unchanged.
9. Confirm a valid restore creates a separate diagnostic snapshot first, then recreates only the database whose name is recorded in the selected archive. Verify files/settings/Image/topology are restored as a unit, the PostgreSQL container and unrelated databases remain unchanged, and the Runner keeps its original container and registration.
10. If separately authorized, perform the manual Windows Host acceptance sequence and record all smoke evidence before treating the service upgrade as accepted.

## Expected Results

- Every preflight error is fail-closed and leaves containers and files untouched.
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
- container action order from the test Docker boundary
- Backup IDs, manifest/checksum validation results, byte sizes, and free-space readings
- source/target image digests and container mount/port/network identity
- restore diagnostic snapshot ID and confirmation result
- for authorized live acceptance only: before/after topology, health/API result, and the API/Git/Registry/Actions/Runner/Run Attempt smoke results

## Current Execution Result

- Windows Host report: `npm ci` and `npm run typecheck` passed. `npm run test:gitea-lifecycle` failed during Pester Discovery with `No modules named 'gitea-lifecycle' are currently loaded`.
- Fixed the Discovery ordering by importing the module in `BeforeDiscovery`, before the `InModuleScope` blocks are discovered. Removed `$TestDrive` from Discovery-time `InModuleScope -Parameters` expressions and resolve the `TestDrive` PSDrive root inside `BeforeAll` during Run. The Windows Pester rerun is pending.
- This WSL workspace has Windows PowerShell/Pester installed through Windows interop, but Pester cannot resolve the Linux workspace current directory (`Directory.GetParent` reports an unsupported path format); no post-fix Pester result is claimed.
- Passed in this WSL pass: `npm run validate:platform`, `git diff --check`, and `package.json` JSON parsing.
- Not executed: Pester; `npm run test:gitea-lifecycle` exits 127 because `powershell` is not installed in WSL.
- Not completed: Typecheck; `npm run typecheck` exits 1 because `node_modules/typescript/bin/tsc` is absent. The earlier `npm ci` attempt could not fetch `@types/node` because `registry.npmjs.org` returned `EAI_AGAIN`; it was not retried in this pass.
- Not executed: Docker E2E; `npm run test:gitea-lifecycle:docker-e2e` exits 127 because `powershell` is not installed. Separately, `docker info` is denied access to `/var/run/docker.sock` in WSL.
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
