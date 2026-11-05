# TC-011: Local Gitea Version Lifecycle Operations

## Metadata
- Test ID: TC-011
- Status: In Progress
- Last Updated: 2026-11-05
- Owner: Project Maintainer
- Mode: Windows PowerShell/Pester safety tests, isolated Docker acceptance, and separate manual Windows Host acceptance
- Related Docs / WBS: GitHub issue #3; WBS `3.12`; `docs/issues/items/I-007-gitea-version-lifecycle-operations.md`
- Source Dashboard: docs/testing/test-dashboard.md
- Source Template: docs/templates/test-case.template.md

## Objective

Verify the operator-facing upgrade, backup-list, and restore commands protect the legacy Gitea data boundary and fail closed before unsafe changes.

## Scope

Run the automated Pester suite against temporary directories and a mocked Docker/API boundary through the exported lifecycle command. It covers supported version steps, backup path separation, checksum validation, upgrade ordering and health-failure behavior, recovery-marker/image-pin ordering, source-service recovery after stop failure, restore Backup ID and manifest gates, typed-confirmation refusal, and diagnostic-backup/database/data/config/image restoration ordering without opening a Docker connection. The opt-in Docker E2E creates GUID-named Gitea/PostgreSQL/Runner fixtures with isolated bind mounts and publishes only on `127.0.0.2`; it exercises an actual upgrade, backup listing/integrity, a forced post-migration failure, and explicit restore. The E2E snapshots all pre-existing container identities/states and removes only its uniquely named resources. Neither suite has been executed on Windows yet.

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

## Steps

1. Run `npm ci`, `npm run typecheck`, and `npm run test:gitea-lifecycle`; record each exit status separately.
2. On a Windows test host, run `status` and confirm existing commands remain read-only with respect to containers.
3. Run `upgrade` without a version, with a floating tag, an unsupported version jump, an unexpected port/mount/network, or active Runner jobs; confirm each stops before service mutation.
4. Force insufficient backup space and confirm no older backup is removed and no container is stopped/recreated.
5. Set `$env:AGENT_SDLC_GITEA_DOCKER_E2E = "1"` and run `npm run test:gitea-lifecycle:docker-e2e`; confirm it uses only GUID-named fixtures, an isolated network and bind mounts, and the `.2` loopback endpoints.
6. Confirm the E2E upgrades 1.25.5 to 1.26.4, validates the retained backup and backup-list output, then forces a post-migration API-version check failure. Verify the marker remains, the original fixture Runner stays stopped, and no automatic rollback occurs.
7. Confirm the E2E explicitly restores the selected 1.25.5 backup, passes HTTP/API checks, clears the marker, resumes the same fixture Runner, and leaves every pre-existing container identity/state unchanged.
8. Attempt restore with a missing ID, corrupt checksum, or incorrect typed confirmation; confirm live data is unchanged.
9. Confirm a valid restore; verify a separate diagnostic snapshot is retained first, then verify the selected database/files/settings/Image/topology are restored as one unit. Confirm the Runner keeps its original container and registration.
10. If separately authorized, perform the manual Windows Host acceptance sequence and record all smoke evidence before treating the service upgrade as accepted.

## Expected Results

- Every preflight error is fail-closed and leaves containers and files untouched.
- The new Gitea container is not created until a complete, integrity-verified backup exists.
- Backup storage is outside all live Gitea/PostgreSQL writable mounts, has a restrictive Windows ACL, and no command silently deletes a prior backup.
- Restore requires a valid Backup ID, intact manifest/checksums, and a typed confirmation naming that ID and the overwritten instance.
- Restore preserves the overwritten failed state separately and never starts an old Image against the upgraded database.
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

- Passed in WSL: `npm run validate:platform`.
- Not executed: Pester; `npm run test:gitea-lifecycle` exits 127 because `powershell` is not installed in WSL.
- Not executed: Typecheck; `npm run typecheck` exits 1 because `node_modules/typescript/bin/tsc` is absent. `npm ci` could not fetch `@types/node` because `registry.npmjs.org` returned `EAI_AGAIN`; the offline cache is incomplete and read-only.
- Not executed: Docker E2E; Docker CLI access is denied by the WSL Docker socket permission on `/var/run/docker.sock`.
- No live Gitea, PostgreSQL, Runner, or Compose service was operated.

## Cleanup

Use disposable test directories/containers only. Do not delete backup fixtures as part of the tested lifecycle operation; test teardown may remove only the isolated temporary fixture after evidence is captured.

## Change Log
- 2026-11-05: Initial version from issue #3 implementation contract.
- 2026-11-05: Added exported lifecycle-command coverage for restore identity, integrity, confirmation, diagnostic snapshot, and ordered matching-state restoration gates.
- 2026-11-05: Added unexecuted Windows Docker E2E coverage and recorded the WSL PowerShell, Docker socket, and npm dependency-install limitations.
