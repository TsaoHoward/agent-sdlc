Describe "Gitea lifecycle isolated Docker acceptance" -Tag "DockerE2E" -Skip:($env:AGENT_SDLC_GITEA_DOCKER_E2E -ne "1") {
    BeforeAll {
        if ($env:AGENT_SDLC_GITEA_DOCKER_E2E -ne "1") {
            throw "AGENT_SDLC_GITEA_DOCKER_E2E must remain set to 1 from Pester Discovery through Run."
        }

        . (Join-Path $PSScriptRoot "gitea-lifecycle.DockerE2E.Helpers.ps1")
        try {
            Import-Module (Join-Path $PSScriptRoot "../../scripts/dev/gitea-lifecycle-e2e-fixture-cleanup.psm1") -Force -ErrorAction Stop
            Import-Module (Join-Path $PSScriptRoot "../../scripts/dev/gitea-lifecycle.psm1") -Force -ErrorAction Stop
            Initialize-GiteaLifecycleE2EFixture
        }
        catch {
            $initializationError = $_.Exception.Message
            try { Remove-GiteaLifecycleE2EFixture } catch {
                $initializationError += " Cleanup also failed: $($_.Exception.Message)"
            }
            throw "Docker E2E fixture initialization failed: $initializationError"
        }
    }

    AfterEach {
        Register-GiteaLifecycleE2EOwnedContainers
    }

    AfterAll {
        if (Get-Command Remove-GiteaLifecycleE2EFixture -ErrorAction SilentlyContinue) {
            Remove-GiteaLifecycleE2EFixture
        }
    }

    It "upgrades, lists and validates a backup, restores it, and leaves existing containers unchanged" {
        $state = Get-GiteaLifecycleE2EState
        $context = $state.Context
        $headers = @{
            Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($state.AdminUsername):$($state.AdminPassword)"))
        }

        InModuleScope gitea-lifecycle -Parameters @{ Context = $context } {
            param($Context)
            Mock Confirm-GiteaLifecycleOperation {}
            Invoke-GiteaLifecycle -Action upgrade -Context $Context -GiteaVersion "1.26.4"
        }

        $version = Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/version") -Method Get
        [string]$version.version | Should -Be "1.26.4"
        $backupDirectories = @(Get-ChildItem -LiteralPath $state.BackupRoot -Directory | Sort-Object Name)
        $backupDirectories.Count | Should -BeGreaterThan 0
        $state.InitialBackupId = $backupDirectories[0].Name

        $runtimePath = Join-Path $backupDirectories[0].FullName "payload\private\gitea-runtime.json"
        $runtime = Get-Content -LiteralPath $runtimePath -Raw | ConvertFrom-Json
        [string]$runtime.imageReference | Should -Match '^(docker\.gitea\.com/gitea@sha256:[0-9a-f]{64}|sha256:[0-9a-f]{64})$'
        @($runtime.imageReference).Count | Should -Be 1

        $integrity = InModuleScope gitea-lifecycle -Parameters @{ BackupPath = $backupDirectories[0].FullName } {
            param($BackupPath)
            Test-GiteaBackupIntegrity -BackupPath $BackupPath
        }
        $integrity.IsValid | Should -BeTrue
        [string]$integrity.Manifest.sourceVersion | Should -Be "1.25.5"
        [string]$integrity.Manifest.sourceImageDigest | Should -Be ([string]$runtime.imageReference)
        $resolvedSourceImageId = Invoke-GiteaLifecycleE2EDocker -Arguments @("image", "inspect", [string]$runtime.imageReference, "--format", "{{.Id}}")
        [string]$resolvedSourceImageId | Should -Be ([string]$runtime.imageId)
        [long]$manifestFilesSize = 0
        foreach ($fileEntry in @($integrity.Manifest.files)) {
            $manifestFilesSize += [long]$fileEntry.sizeBytes
        }
        [long]$integrity.Manifest.sizeBytes | Should -Be $manifestFilesSize

        $backupList = InModuleScope gitea-lifecycle -Parameters @{ Context = $context } {
            param($Context)
            Mock Assert-NativeWindowsHost {}
            Invoke-GiteaLifecycle -Action backup-list -Context $Context 6>&1 | Out-String
        }
        [string]$backupList | Should -Match $state.InitialBackupId
        [string]$backupList | Should -Not -Match $state.AdminPassword
        [string]$backupList | Should -Not -Match "POSTGRES_PASSWORD"

        $repo = Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/repos/e2e-admin/lifecycle-e2e-sentinel") -Method Get -Headers $headers
        [string]$repo.name | Should -Be "lifecycle-e2e-sentinel"
    }

    It "resolves multi, duplicate, mixed, and malformed RepoDigest responses against an isolated Docker image" {
        $state = Get-GiteaLifecycleE2EState
        if (-not $state.InitialBackupId) {
            Set-ItResult -Skipped -Because "Blocked: the first Docker E2E scenario did not produce its prerequisite Backup ID."
            return
        }
        $imageReference = [string](Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.GiteaName, "--format", "{{.Config.Image}}"))
        $imageId = [string](Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.GiteaName, "--format", "{{.Image}}"))
        $imageReference | Should -Match '^docker\.gitea\.com/gitea@sha256:[0-9a-f]{64}$'
        $digest = $imageReference.Substring($imageReference.IndexOf("@") + 1)
        $otherRepositoryDigest = "ghcr.io/mirror/gitea@$digest"
        $secondOfficialDigest = "docker.gitea.com/gitea@sha256:$('f' * 64)"
        $references = InModuleScope gitea-lifecycle -Parameters @{
            ImageReference = $imageReference
            OtherRepositoryDigest = $otherRepositoryDigest
            SecondOfficialDigest = $secondOfficialDigest
        } {
            param($ImageReference, $OtherRepositoryDigest, $SecondOfficialDigest)
            $script:syntheticRepoDigests = "[]"
            Mock Invoke-GiteaDocker {
                return [pscustomobject]@{ ExitCode = 0; StdOut = $script:syntheticRepoDigests; StdErr = "" }
            }

            $script:syntheticRepoDigests = '["' + $ImageReference + '","' + $SecondOfficialDigest + '"]'
            $multiple = Get-ImageDigestReference -Image $ImageReference -RequireRegistryDigest
            @($multiple).Count | Should -Be 1

            $script:syntheticRepoDigests = '["' + $ImageReference + '","' + $ImageReference + '"]'
            $duplicate = Get-ImageDigestReference -Image $ImageReference -RequireRegistryDigest
            @($duplicate).Count | Should -Be 1

            $script:syntheticRepoDigests = '["' + $OtherRepositoryDigest + '","' + $ImageReference + '"]'
            $mixed = Get-ImageDigestReference -Image $ImageReference -RequireRegistryDigest
            @($mixed).Count | Should -Be 1

            $script:syntheticRepoDigests = '["docker.gitea.com/gitea@sha256:bad"]'
            { Get-ImageDigestReference -Image $ImageReference -RequireRegistryDigest } | Should -Throw
            $script:syntheticRepoDigests = '["' + $ImageReference
            { Get-ImageDigestReference -Image $ImageReference -RequireRegistryDigest } | Should -Throw

            return @($multiple, $duplicate, $mixed)
        }

        foreach ($reference in $references) {
            [string]$reference | Should -Be $imageReference
            $resolvedImageId = Invoke-GiteaLifecycleE2EDocker -Arguments @("image", "inspect", [string]$reference, "--format", "{{.Id}}")
            [string]$resolvedImageId | Should -Be $imageId
        }
    }

    It "reconciles a manually resumed original source without restoring the database" {
        $state = Get-GiteaLifecycleE2EState
        if (-not $state.InitialBackupId) {
            Set-ItResult -Skipped -Because "Blocked: the first Docker E2E scenario did not produce its prerequisite Backup ID."
            return
        }
        $context = $state.Context
        $sourceGiteaId = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.GiteaName, "--format", "{{.Id}}")
        $sourcePostgresId = [string]$state.PostgresContainerId
        $sourceRunnerId = [string]$state.RunnerContainerId
        $recoveryMarker = Join-Path $context.RepoRoot ".agent-sdlc\dev-env\gitea\lifecycle-recovery.json"

        InModuleScope gitea-lifecycle -Parameters @{ Context = $context } {
            param($Context)
            Mock Confirm-GiteaLifecycleOperation {}
            Mock New-GiteaContainerFromRuntime { throw "simulated-invalid-reference-before-container-start" }
            { Invoke-GiteaLifecycle -Action upgrade -Context $Context -GiteaVersion "1.27.3" } | Should -Throw "*simulated-invalid-reference-before-container-start*"
        }

        Test-Path -LiteralPath $recoveryMarker -PathType Leaf | Should -BeTrue
        $marker = Get-Content -LiteralPath $recoveryMarker -Raw | ConvertFrom-Json
        [int]$marker.schemaVersion | Should -Be 2
        [string]$marker.phase | Should -Be "target-start-attempted"
        [string]$marker.backupId | Should -Not -BeNullOrEmpty
        [string]$marker.giteaContainerId | Should -Be $sourceGiteaId
        [string]$marker.postgresContainerId | Should -Be $sourcePostgresId
        [string]$marker.runnerContainerId | Should -Be $sourceRunnerId

        $legacyBackupPath = Join-Path $state.BackupRoot $marker.backupId
        $legacyRuntimePath = Join-Path $legacyBackupPath "payload\private\gitea-runtime.json"
        $legacyManifestPath = Join-Path $legacyBackupPath "manifest.json"
        $legacyRuntime = Get-Content -LiteralPath $legacyRuntimePath -Raw | ConvertFrom-Json
        $sharedDigest = ([string]$legacyRuntime.imageReference).Substring(([string]$legacyRuntime.imageReference).IndexOf("@sha256:") + 1)
        $legacyDigestReference = @(
            "docker.gitea.com/gitea@$sharedDigest"
            "docker.gitea.com/gitea@$sharedDigest"
            "gitea/gitea@$sharedDigest"
        ) -join " "
        $legacyRuntime.imageReference = $legacyDigestReference
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($legacyRuntimePath, ($legacyRuntime | ConvertTo-Json -Depth 32), $utf8NoBom)

        $legacyManifest = Get-Content -LiteralPath $legacyManifestPath -Raw | ConvertFrom-Json
        $legacyManifest.schemaVersion | Should -Be 1
        $legacyManifest.sourceImageDigest = $legacyDigestReference
        $runtimeManifestEntries = @($legacyManifest.files | Where-Object { [string]$_.path -eq "payload/private/gitea-runtime.json" })
        $runtimeManifestEntries.Count | Should -Be 1
        $runtimeManifestEntries[0].sizeBytes = [long](Get-Item -LiteralPath $legacyRuntimePath).Length
        $runtimeManifestEntries[0].sha256 = (Get-FileHash -LiteralPath $legacyRuntimePath -Algorithm SHA256).Hash.ToLowerInvariant()
        [long]$legacyTotalBytes = 0
        foreach ($manifestEntry in @($legacyManifest.files)) {
            $legacyTotalBytes += [long]$manifestEntry.sizeBytes
        }
        $legacyManifest.sizeBytes = $legacyTotalBytes
        [System.IO.File]::WriteAllText($legacyManifestPath, ($legacyManifest | ConvertTo-Json -Depth 32), $utf8NoBom)
        $legacyIntegrity = InModuleScope gitea-lifecycle -Parameters @{ BackupPath = $legacyBackupPath } {
            param($BackupPath)
            Test-GiteaBackupIntegrity -BackupPath $BackupPath
        }
        $legacyIntegrity.IsValid | Should -BeTrue
        [string]$legacyIntegrity.Manifest.sourceImageDigest | Should -Be $legacyDigestReference
        InModuleScope gitea-lifecycle -Parameters @{ BackupPath = $legacyBackupPath } {
            param($BackupPath)
            { Get-BackupRuntime -BackupPath $BackupPath } | Should -Throw "*immutable*"
        }

        $preupgradeName = "$($state.GiteaName)-preupgrade-$($marker.backupId)"
        Invoke-GiteaLifecycleE2EDocker -Arguments @("rename", $preupgradeName, $state.GiteaName) | Out-Null
        Invoke-GiteaLifecycleE2EDocker -Arguments @("start", $state.GiteaName) | Out-Null
        Wait-GiteaLifecycleE2EHttp -Uri ($state.GiteaUrl + "api/v1/version")
        Invoke-GiteaLifecycleE2EDocker -Arguments @("start", $state.RunnerName) | Out-Null

        InModuleScope gitea-lifecycle -Parameters @{
            Context = $context
            BackupId = [string]$marker.backupId
            GiteaId = $sourceGiteaId
            PostgresId = $sourcePostgresId
            RunnerId = $sourceRunnerId
        } {
            param($Context, $BackupId, $GiteaId, $PostgresId, $RunnerId)
            Mock Confirm-GiteaLifecycleOperation {}
            Invoke-GiteaLifecycle -Action reconcile-recovery -Context $Context -BackupId $BackupId -ExpectedGiteaContainerId $GiteaId -ExpectedPostgresContainerId $PostgresId -ExpectedRunnerContainerId $RunnerId
        }

        Test-Path -LiteralPath $recoveryMarker | Should -BeFalse
        [string](Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.GiteaName, "--format", "{{.Id}}")) | Should -Be $sourceGiteaId
        [string](Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.PostgresName, "--format", "{{.Id}}")) | Should -Be $sourcePostgresId
        [string](Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.RunnerName, "--format", "{{.Id}}")) | Should -Be $sourceRunnerId
        [string](Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/version") -Method Get).version | Should -Be "1.26.4"
        (Invoke-GiteaLifecycleE2EPsql -ContainerName $state.PostgresName -DatabaseName "gitea" -Sql "SELECT 1") | Should -Be "1"
        $reconciliationRecordPath = Join-Path $context.RepoRoot ".agent-sdlc\dev-env\gitea\upgrades\$($marker.backupId)-recovery-reconciled.json"
        $reconciliationRecord = Get-Content -LiteralPath $reconciliationRecordPath -Raw | ConvertFrom-Json
        [bool]$reconciliationRecord.legacyImageReferenceReconciled | Should -BeTrue
        [int]$reconciliationRecord.legacyRepoDigestCount | Should -Be 3
        $reconciliationRecord.sourceImageDigest | Should -BeNullOrEmpty
        [bool]$reconciliationRecord.databaseRestorePerformed | Should -BeFalse
    }

    It "retains recovery evidence after a post-migration failure" {
        $state = Get-GiteaLifecycleE2EState
        if (-not $state.InitialBackupId) {
            Set-ItResult -Skipped -Because "Blocked: the first Docker E2E scenario did not produce its prerequisite Backup ID."
            return
        }
        $context = $state.Context

        InModuleScope gitea-lifecycle -Parameters @{ Context = $context } {
            param($Context)
            Mock Confirm-GiteaLifecycleOperation {}
            Mock Assert-GiteaApiVersion { throw "simulated-api-version-failure" }
            { Invoke-GiteaLifecycle -Action upgrade -Context $Context -GiteaVersion "1.27.3" } | Should -Throw "*simulated-api-version-failure*"
        }

        $recoveryMarker = Join-Path $context.RepoRoot ".agent-sdlc\dev-env\gitea\lifecycle-recovery.json"
        Test-Path -LiteralPath $recoveryMarker -PathType Leaf | Should -BeTrue
        $marker = Get-Content -LiteralPath $recoveryMarker -Raw | ConvertFrom-Json
        $state.RecoveryBackupId = [string]$marker.backupId
        $state.RecoveryBackupId | Should -Not -BeNullOrEmpty
        $recoveryBackupPath = Join-Path $state.BackupRoot $state.RecoveryBackupId
        $recoveryBackup = InModuleScope gitea-lifecycle -Parameters @{ BackupPath = $recoveryBackupPath } {
            param($BackupPath)
            Test-GiteaBackupIntegrity -BackupPath $BackupPath
        }
        $recoveryBackup.IsValid | Should -BeTrue
        [string]$recoveryBackup.Manifest.sourceVersion | Should -Be "1.26.4"
        InModuleScope gitea-lifecycle -Parameters @{ Context = $context } {
            param($Context)
            { Assert-NoPendingGiteaRecovery -Context $Context } | Should -Throw "*blocked*"
        }
        $runner = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.RunnerName, "--format", "{{.State.Status}}")
        $runner | Should -Be "exited"
        $activeName = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.GiteaName, "--format", "{{.State.Status}}")
        $activeName | Should -Be "running"
        $version = Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/version") -Method Get
        [string]$version.version | Should -Be "1.27.3"
        $headers = @{
            Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($state.AdminUsername):$($state.AdminPassword)"))
        }
        $repo = Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/repos/e2e-admin/lifecycle-e2e-sentinel") -Method Get -Headers $headers
        [string]$repo.name | Should -Be "lifecycle-e2e-sentinel"
        $probeCreated = Invoke-GiteaLifecycleE2EPsql -ContainerName $state.PostgresName -DatabaseName "gitea" -Sql "CREATE TABLE public.lifecycle_post_backup_probe (id integer PRIMARY KEY)"
        $probeCreated | Should -Be "CREATE TABLE"
        $probeState = Invoke-GiteaLifecycleE2EPsql -ContainerName $state.PostgresName -DatabaseName "gitea" -Sql "SELECT CASE WHEN to_regclass('public.lifecycle_post_backup_probe') IS NULL THEN 'absent' ELSE 'present' END"
        $probeState | Should -Be "present"
        $runnerId = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.RunnerName, "--format", "{{.Id}}")
        $runnerId | Should -Be $state.RunnerContainerId
    }

    It "explicitly restores the pre-failure exact database snapshot and preserves unrelated databases" {
        $state = Get-GiteaLifecycleE2EState
        if (-not $state.RecoveryBackupId) {
            Set-ItResult -Skipped -Because "Blocked: the preceding recovery scenario did not produce its prerequisite Recovery Backup ID."
            return
        }
        $context = $state.Context
        $backupId = $state.RecoveryBackupId
        $recoveryMarker = Join-Path $context.RepoRoot ".agent-sdlc\dev-env\gitea\lifecycle-recovery.json"
        InModuleScope gitea-lifecycle -Parameters @{ Context = $context; SelectedBackupId = $backupId } {
            param($Context, $SelectedBackupId)
            Mock Confirm-GiteaLifecycleOperation {}
            Invoke-GiteaLifecycle -Action restore -Context $Context -BackupId $SelectedBackupId
        }

        $version = Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/version") -Method Get
        [string]$version.version | Should -Be "1.26.4"
        Test-Path -LiteralPath $recoveryMarker | Should -BeFalse
        $probeState = Invoke-GiteaLifecycleE2EPsql -ContainerName $state.PostgresName -DatabaseName "gitea" -Sql "SELECT CASE WHEN to_regclass('public.lifecycle_post_backup_probe') IS NULL THEN 'absent' ELSE 'present' END"
        $probeState | Should -Be "absent"
        $unrelatedValue = Invoke-GiteaLifecycleE2EPsql -ContainerName $state.PostgresName -DatabaseName $state.UnrelatedDatabaseName -Sql "SELECT value FROM public.restore_sentinel"
        $unrelatedValue | Should -Be "preserve-me"
        $runner = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.RunnerName, "--format", "{{.State.Status}}")
        $runner | Should -Be "running"
        $runnerId = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.RunnerName, "--format", "{{.Id}}")
        $runnerId | Should -Be $state.RunnerContainerId
        $postgresId = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.PostgresName, "--format", "{{.Id}}")
        $postgresId | Should -Be $state.PostgresContainerId
        $headers = @{
            Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($state.AdminUsername):$($state.AdminPassword)"))
        }
        $repo = Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/repos/e2e-admin/lifecycle-e2e-sentinel") -Method Get -Headers $headers
        [string]$repo.name | Should -Be "lifecycle-e2e-sentinel"
        Assert-GiteaLifecycleE2EContainerSnapshot -Expected $state.ExistingContainers
    }
}
