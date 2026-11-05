# TC-011: Local Gitea Version Lifecycle Operations

## Metadata
- Test ID: TC-011
- Status: Draft
- Last Updated: 2026-11-05
- Owner: Project Maintainer
- Mode: Windows PowerShell/Pester safety tests, isolated Docker acceptance, and separate manual Windows Host acceptance
- Related Docs / WBS: GitHub issue #3; WBS `3.12`; `docs/issues/items/I-007-gitea-version-lifecycle-operations.md`
- Source Dashboard: docs/testing/test-dashboard.md
- Source Template: docs/templates/test-case.template.md

## Objective

Verify the operator-facing upgrade, backup-list, and restore commands protect the legacy Gitea data boundary and fail closed before unsafe changes.

## Scope

Run the automated Pester suite against temporary directories and mocked Docker/API calls. It covers supported version steps, backup path separation, checksum validation, backup-before-recreation ordering, and health-failure behavior without opening a Docker connection. Full topology, capacity, no-active-job, restore, and isolated disposable-container integration checks remain outstanding on a Windows test host.

Live acceptance for the real 43000 instance is a separate, authorized Windows Host operation. It must also cover API, Git read/write, Registry access, Actions dispatch and Runner execution, Run Attempt visibility, and representative integrations. The local-agent-infra #29 E2E remains a separate result.

## Preconditions

- Run `npm run test:gitea-lifecycle` on Windows PowerShell with Pester 5 available.
- For integration validation, use a disposable test config, temporary backup root, and isolated Docker simulator or disposable local daemon.
- Never point tests at the real Gitea containers, host mounts, repository, Registry, or shared Runner.
- For live acceptance, use native Windows PowerShell, verify the actual legacy container topology and disk capacity, review the official upgrade path, and obtain separate explicit authorization.

## Test Data

- Current and target Gitea versions with allowed same-series/next-series transitions.
- A temporary legacy-style Gitea and PostgreSQL container description with bind-mounted data/config, port 43000, and an isolated Runner.
- Corrupt/missing manifest, changed checksum, insufficient-space, and active-job fixtures.
- Backup set containing database dump, data/config trees, sensitive bootstrap payload, private runtime topology, and a manifest.

## Steps

1. Run `npm run test:gitea-lifecycle`; confirm the Pester cases pass without a Docker connection.
2. On a Windows test host, run `status` and confirm existing commands remain read-only with respect to containers.
3. Run `upgrade` without a version, with a floating tag, an unsupported version jump, an unexpected port/mount/network, or active Runner jobs; confirm each stops before service mutation.
4. Force insufficient backup space and confirm no older backup is removed and no container is stopped/recreated.
5. Run an allowed upgrade against the isolated boundary; confirm the application stops before the database/file snapshot, the backup manifest and checksums validate, and only the Gitea container is recreated with the requested digest and original topology.
6. Simulate backup failure and post-upgrade health failure; confirm no new Image is started before a valid backup, no automatic rollback occurs, and bootstrap `up` remains blocked by the recovery marker until explicit restore succeeds.
7. Run `backup-list`; confirm it reports IDs, source versions, sizes, and integrity without printing sensitive payloads.
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

## Evidence To Capture

- sanitized command output and exit status
- container action order from the test Docker boundary
- Backup IDs, manifest/checksum validation results, byte sizes, and free-space readings
- source/target image digests and container mount/port/network identity
- restore diagnostic snapshot ID and confirmation result
- for authorized live acceptance only: before/after topology, health/API result, and the API/Git/Registry/Actions/Runner/Run Attempt smoke results

## Cleanup

Use disposable test directories/containers only. Do not delete backup fixtures as part of the tested lifecycle operation; test teardown may remove only the isolated temporary fixture after evidence is captured.

## Change Log
- 2026-11-05: Initial version from issue #3 implementation contract.
