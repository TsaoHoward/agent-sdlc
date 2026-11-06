Describe "Gitea lifecycle isolated Docker acceptance" -Tag "DockerE2E" -Skip:($env:AGENT_SDLC_GITEA_DOCKER_E2E -ne "1") {
    BeforeAll {
        if ($env:AGENT_SDLC_GITEA_DOCKER_E2E -ne "1") {
            throw "AGENT_SDLC_GITEA_DOCKER_E2E must remain set to 1 from Pester Discovery through Run."
        }

        . (Join-Path $PSScriptRoot "gitea-lifecycle.DockerE2E.Helpers.ps1")
        try {
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

        $integrity = InModuleScope gitea-lifecycle -Parameters @{ BackupPath = $backupDirectories[0].FullName } {
            param($BackupPath)
            Test-GiteaBackupIntegrity -BackupPath $BackupPath
        }
        $integrity.IsValid | Should -BeTrue
        [string]$integrity.Manifest.sourceVersion | Should -Be "1.25.5"

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

    It "retains recovery evidence after a post-migration failure" {
        $state = Get-GiteaLifecycleE2EState
        $context = $state.Context
        $state.InitialBackupId | Should -Not -BeNullOrEmpty

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
        $context = $state.Context
        $backupId = $state.RecoveryBackupId
        $backupId | Should -Not -BeNullOrEmpty
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
