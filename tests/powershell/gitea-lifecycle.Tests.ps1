BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "../../scripts/dev/gitea-lifecycle.psm1"
    Import-Module (Resolve-Path $modulePath) -Force
}

Describe "Gitea lifecycle safety helpers" {
    InModuleScope gitea-lifecycle -Parameters @{ TestRoot = $TestDrive } {
        param($TestRoot)

        BeforeEach {
            $script:lifecycleActions = [System.Collections.Generic.List[string]]::new()
            $script:failGiteaHealth = $false
            $script:upgradeContext = @{
                GiteaContainerName = "agent-sdlc-gitea"
                GiteaRunnerContainerName = "agent-sdlc-gitea-runner"
                GiteaPostgresContainerName = "agent-sdlc-gitea-db"
                GiteaRootUrl = "http://localhost:43000/"
            }

            Mock Assert-NativeWindowsHost {}
            Mock Assert-DockerDesktopReady { return @{ id = "isolated-test-engine" } }
            Mock Assert-NoPendingGiteaRecovery {}
            Mock Ensure-BackupRoot {}
            Mock Assert-GiteaConfigCanBePinned {}
            Mock Assert-GiteaContainerIdentity { return [pscustomobject]@{ Name = "/agent-sdlc-gitea" } }
            Mock Assert-PostgresContainerIdentity { return [pscustomobject]@{ Name = "/agent-sdlc-gitea-db" } }
            Mock Get-GiteaRunnerInfo { return [pscustomobject]@{ State = [pscustomobject]@{ Status = "running" } } }
            Mock Get-GiteaReportedVersion { return "1.25.5" }
            Mock Assert-GiteaDatabaseTarget {}
            Mock Assert-NoActiveGiteaActions {}
            Mock Assert-BackupCapacity { return [pscustomobject]@{ SourceBytes = 10; RequiredFreeBytes = 1024; AvailableFreeBytes = 4096 } }
            Mock Confirm-GiteaLifecycleOperation {}
            Mock Invoke-GiteaDocker {
                param($Arguments, $AllowFailure)
                $script:lifecycleActions.Add("docker $($Arguments -join ' ')")
                return [pscustomobject]@{ ExitCode = 0; StdOut = ""; StdErr = "" }
            }
            Mock Get-ImageDigestReference { return ("docker.gitea.com/gitea@sha256:" + ("a" * 64)) }
            Mock Stop-GiteaRunner { $script:lifecycleActions.Add("stop-runner") }
            Mock New-GiteaBackupSet {
                $script:lifecycleActions.Add("backup")
                return [pscustomobject]@{ BackupId = "20261105T000000Z-0123456789abcdef0123456789abcdef"; Path = "C:\isolated-backups\fixture" }
            }
            Mock Get-BackupRuntime { $script:lifecycleActions.Add("read-runtime"); return [pscustomobject]@{} }
            Mock New-GiteaContainerFromRuntime { $script:lifecycleActions.Add("create-gitea") }
            Mock Wait-GiteaHealthy {
                $script:lifecycleActions.Add("health")
                if ($script:failGiteaHealth) { throw "simulated health failure" }
            }
            Mock Assert-GiteaApiVersion { $script:lifecycleActions.Add("api-version") }
            Mock Set-GiteaBootstrapImagePin { $script:lifecycleActions.Add("pin-image") }
            Mock Set-GiteaLifecycleRecoveryMarker { $script:lifecycleActions.Add("set-recovery-marker") }
            Mock Clear-GiteaLifecycleRecoveryMarker { $script:lifecycleActions.Add("clear-recovery-marker") }
            Mock Start-GiteaRunner { $script:lifecycleActions.Add("start-runner") }
            Mock New-GiteaOperationRecord { $script:lifecycleActions.Add("operation-record") }
        }
        It "accepts a later patch in the same series" {
            { Assert-SupportedGiteaVersionStep -CurrentVersion "1.25.5" -TargetVersion "1.25.6" } | Should -Not -Throw
        }

        It "accepts only the immediately following minor series" {
            { Assert-SupportedGiteaVersionStep -CurrentVersion "1.25.5" -TargetVersion "1.26.0" } | Should -Not -Throw
            { Assert-SupportedGiteaVersionStep -CurrentVersion "1.25.5" -TargetVersion "1.27.0" } | Should -Throw
        }

        It "accepts the Gitea 1.27 to 28.0 versioning boundary" {
            { Assert-SupportedGiteaVersionStep -CurrentVersion "1.27.9" -TargetVersion "28.0.0" } | Should -Not -Throw
        }

        It "rejects floating, same-or-older, and unverified multi-series targets" {
            { Assert-SupportedGiteaVersionStep -CurrentVersion "1.25.5" -TargetVersion "latest" } | Should -Throw
            { Assert-SupportedGiteaVersionStep -CurrentVersion "1.25.5" -TargetVersion "1.25.5" } | Should -Throw
            { Assert-SupportedGiteaVersionStep -CurrentVersion "1.25.5" -TargetVersion "28.3.0" } | Should -Throw
        }

        It "rejects backup roots inside the repository or overlapping live data" {
            $root = Join-Path $TestRoot "layout"
            $repo = Join-Path $root "repo"
            $data = Join-Path $root "live\data"
            $config = Join-Path $root "live\config"
            $postgres = Join-Path $root "live\postgres"
            $context = @{
                BackupRoot = Join-Path $root "backups"
                RepoRoot = $repo
                GiteaDataDir = $data
                GiteaConfigDir = $config
                GiteaPostgresDataDir = $postgres
            }

            { Assert-SafeBackupRoot -Context $context } | Should -Not -Throw
            $context.BackupRoot = Join-Path $repo "backups"
            { Assert-SafeBackupRoot -Context $context } | Should -Throw
            $context.BackupRoot = Join-Path $data "backups"
            { Assert-SafeBackupRoot -Context $context } | Should -Throw
        }

        It "validates every backup checksum and rejects changed payloads" {
            $backupPath = Join-Path $TestRoot "fixture"
            $payload = Join-Path $backupPath "payload\private"
            New-Item -ItemType Directory -Path $payload -Force | Out-Null
            $payloadFile = Join-Path $payload "restore-context.json"
            [System.IO.File]::WriteAllText($payloadFile, '{"databaseName":"gitea"}')
            $manifest = @{
                schemaVersion = 1
                backupId = "fixture"
                files = @(@{
                    path = "payload/private/restore-context.json"
                    sizeBytes = [long](Get-Item -LiteralPath $payloadFile).Length
                    sha256 = (Get-FileHash -LiteralPath $payloadFile -Algorithm SHA256).Hash.ToLowerInvariant()
                })
            }
            Save-BackupJson -Path (Join-Path $backupPath "manifest.json") -Value $manifest

            (Test-GiteaBackupIntegrity -BackupPath $backupPath).IsValid | Should -BeTrue
            [System.IO.File]::AppendAllText($payloadFile, "changed")
            (Test-GiteaBackupIntegrity -BackupPath $backupPath).Reason | Should -Be "checksum-mismatch"
        }

        It "creates a valid backup before recreating only the Gitea container" {
            Invoke-GiteaUpgrade -Context $script:upgradeContext -GiteaVersion "1.26.0"

            $script:lifecycleActions.IndexOf("backup") | Should -BeLessThan $script:lifecycleActions.IndexOf("docker rename agent-sdlc-gitea agent-sdlc-gitea-preupgrade-20261105T000000Z-0123456789abcdef0123456789abcdef")
            $script:lifecycleActions.IndexOf("backup") | Should -BeLessThan $script:lifecycleActions.IndexOf("create-gitea")
            $script:lifecycleActions | Should -Contain "set-recovery-marker"
            $script:lifecycleActions | Should -Contain "clear-recovery-marker"
            $script:lifecycleActions | Should -Contain "start-runner"
            $script:lifecycleActions | Should -Not -Contain "docker start agent-sdlc-gitea"
        }

        It "retains the backup and does not automatically roll back after a health failure" {
            $script:failGiteaHealth = $true

            { Invoke-GiteaUpgrade -Context $script:upgradeContext -GiteaVersion "1.26.0" } | Should -Throw

            $script:lifecycleActions | Should -Contain "backup"
            $script:lifecycleActions | Should -Contain "create-gitea"
            $script:lifecycleActions | Should -Contain "set-recovery-marker"
            $script:lifecycleActions | Should -Not -Contain "clear-recovery-marker"
            $script:lifecycleActions | Should -Not -Contain "docker start agent-sdlc-gitea"
            $script:lifecycleActions | Should -Not -Contain "start-runner"
        }
    }
}
