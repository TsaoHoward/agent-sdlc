BeforeDiscovery {
    $modulePath = Join-Path $PSScriptRoot "../../scripts/dev/gitea-lifecycle.psm1"
    Import-Module (Resolve-Path $modulePath) -Force
}

Describe "Gitea lifecycle isolated Docker failure diagnostics" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "gitea-lifecycle.DockerE2E.Helpers.ps1")
    }

    BeforeEach {
        $script:dockerE2EState = @{}
        $script:dockerE2ELastExitCode = 0
    }

    It "identifies the failing fixture stage and Docker subcommand without exposing arguments" {
        $arguments = @("run", "-d", "--name", "agent-sdlc-life-e2e-fixture-db", "-e", "POSTGRES_PASSWORD=fixture-db-secret", "postgres:16")

        Get-GiteaLifecycleE2EDockerStage -Arguments $arguments | Should -Be "start the disposable PostgreSQL fixture"
        Get-GiteaLifecycleE2EDockerSubcommand -Arguments $arguments | Should -Be "docker run"
    }

    It "redacts database and administrator credentials from Docker stderr" {
        $script:dockerE2EState = $null
        $dbPassword = "fixture-db-secret-keep-private"
        $adminPassword = "fixture-admin-secret-keep-private"
        $dbArguments = @("run", "-e", "POSTGRES_PASSWORD=$dbPassword", "postgres:16")
        $dbStderr = "failed POSTGRES_PASSWORD=$dbPassword; raw value: $dbPassword"
        $tcpArguments = @("exec", "-e", "PGPASSWORD=$dbPassword", "fixture-db", "psql")
        $tcpStderr = "failed PGPASSWORD=$dbPassword; raw value: $dbPassword"
        $adminArguments = @("exec", "fixture-gitea", "gitea", "admin", "user", "create", "--password", $adminPassword)
        $adminStderr = "docker echoed --password $adminPassword; raw value: $adminPassword"

        $sanitizedDbStderr = Protect-GiteaLifecycleE2EDockerStderr -Text $dbStderr -Arguments $dbArguments
        $sanitizedTcpStderr = Protect-GiteaLifecycleE2EDockerStderr -Text $tcpStderr -Arguments $tcpArguments
        $sanitizedAdminStderr = Protect-GiteaLifecycleE2EDockerStderr -Text $adminStderr -Arguments $adminArguments

        $sanitizedDbStderr | Should -Not -Match ([Regex]::Escape($dbPassword))
        $sanitizedDbStderr | Should -Match 'POSTGRES_PASSWORD=\[REDACTED\]'
        $sanitizedTcpStderr | Should -Not -Match ([Regex]::Escape($dbPassword))
        $sanitizedTcpStderr | Should -Match 'PGPASSWORD=\[REDACTED\]'
        $sanitizedAdminStderr | Should -Not -Match ([Regex]::Escape($adminPassword))
        $sanitizedAdminStderr | Should -Match '--password \[REDACTED\]'
    }

    It "waits for loopback TCP and an authenticated SQL query before fixture initialization continues" {
        $script:postgresTcpAttempts = 0
        $script:postgresSqlAttempts = 0
        $script:postgresReadinessArguments = [System.Collections.Generic.List[object]]::new()
        $script:postgresSqlArguments = [System.Collections.Generic.List[object]]::new()
        $script:dockerE2EState = @{ DatabasePassword = "fixture-db-secret" }

        Mock Invoke-GiteaLifecycleE2EDocker {
            param($Arguments, $Stage, $AllowFailure)

            if ($Arguments -contains "pg_isready") {
                $script:postgresReadinessArguments.Add(@($Arguments))
                if ($Arguments -contains "-h") {
                    $script:postgresTcpAttempts += 1
                    if ($script:postgresTcpAttempts -eq 1) {
                        $script:dockerE2ELastExitCode = 2
                        return @("127.0.0.1:5432 - no response")
                    }
                    $script:dockerE2ELastExitCode = 0
                    return @("127.0.0.1:5432 - accepting connections")
                }

                # Model the official image's initialization server: its Unix socket responds
                # even though the final TCP listener has not started yet.
                $script:dockerE2ELastExitCode = 0
                return @("/var/run/postgresql:5432 - accepting connections")
            }

            if ($Arguments -contains "psql") {
                $script:postgresSqlArguments.Add(@($Arguments))
                $script:postgresSqlAttempts += 1
                if ($script:postgresTcpAttempts -lt 2) {
                    throw "SQL readiness ran before loopback TCP became ready."
                }
                if ($script:postgresSqlAttempts -eq 1) {
                    $script:dockerE2ELastExitCode = 2
                    return @()
                }
                $script:dockerE2ELastExitCode = 0
                return @("1")
            }

            throw "Unexpected Docker readiness command."
        }
        Mock Start-Sleep {}

        Wait-GiteaLifecycleE2EPostgres -ContainerName "fixture-postgres" -DatabasePassword "fixture-db-secret"

        $script:postgresTcpAttempts | Should -Be 3
        $script:postgresSqlAttempts | Should -Be 2
        foreach ($arguments in $script:postgresReadinessArguments) {
            $arguments | Should -Contain "-h"
            $arguments | Should -Contain "127.0.0.1"
        }
        foreach ($arguments in $script:postgresSqlArguments) {
            $arguments | Should -Contain "PGPASSWORD=fixture-db-secret"
            $arguments | Should -Contain "PGCONNECT_TIMEOUT=1"
            $arguments | Should -Contain "127.0.0.1"
            $arguments | Should -Contain "SELECT 1"
        }
    }

    It "fails after a bounded number of TCP and SQL readiness attempts" {
        $script:postgresTcpAttempts = 0
        $script:postgresSqlAttempts = 0
        $script:dockerE2EState = @{ DatabasePassword = "fixture-db-secret" }

        Mock Invoke-GiteaLifecycleE2EDocker {
            param($Arguments, $Stage, $AllowFailure)

            if ($Arguments -contains "pg_isready") {
                $script:postgresTcpAttempts += 1
                $script:dockerE2ELastExitCode = 0
                return @("127.0.0.1:5432 - accepting connections")
            }
            if ($Arguments -contains "psql") {
                $script:postgresSqlAttempts += 1
                $script:dockerE2ELastExitCode = 2
                return @()
            }
            throw "Unexpected Docker readiness command."
        }
        Mock Start-Sleep {}

        { Wait-GiteaLifecycleE2EPostgres -ContainerName "fixture-postgres" -DatabasePassword "fixture-db-secret" } | Should -Throw "*TCP and SQL connections*"

        $script:postgresTcpAttempts | Should -Be 60
        $script:postgresSqlAttempts | Should -Be 60
    }
}

Describe "Gitea Actions upgrade preflight" {
    InModuleScope gitea-lifecycle {
        BeforeEach {
            $script:actionsApiRequests = [System.Collections.Generic.List[string]]::new()
            $script:actionsApiIsAdmin = $true
            $script:actionsApiFailure = $false
            $script:actionsRunPages = @()
            $script:actionsContext = @{
                GiteaRootUrl = "http://127.0.0.2:43000/"
                GiteaAdminUsername = "fixture-admin"
                GiteaAdminPassword = "fixture-password"
            }

            Mock Invoke-GiteaApiRead {
                param($Context, $RelativePath)

                $script:actionsApiRequests.Add($RelativePath)
                if ($RelativePath -eq "user") {
                    return [pscustomobject]@{ is_admin = $script:actionsApiIsAdmin }
                }
                if ($script:actionsApiFailure) {
                    throw "simulated API permission failure"
                }
                if ($RelativePath -match '^admin/actions/runs\?limit=50&page=(\d+)$') {
                    $pageNumber = [int]$matches[1]
                    return $script:actionsRunPages[$pageNumber - 1]
                }

                throw "Unexpected Gitea API path '$RelativePath'."
            }
        }

        It "accepts the official empty instance-wide workflow-run response" {
            $script:actionsRunPages = @([pscustomobject]@{
                total_count = 0
                workflow_runs = @()
            })

            { Assert-NoActiveGiteaActions -Context $script:actionsContext } | Should -Not -Throw

            $script:actionsApiRequests -join "," | Should -Be "user,admin/actions/runs?limit=50&page=1"
        }

        It "checks active runs from private repositories through the instance-wide admin endpoint" {
            $script:actionsRunPages = @([pscustomobject]@{
                total_count = 1
                workflow_runs = @([pscustomobject]@{
                    id = 42
                    run_attempt = 1
                    run_number = 7
                    repository_id = 9001
                    status = "running"
                    repository = [pscustomobject]@{
                        id = 9001
                        name = "private-repo"
                        full_name = "private-owner/private-repo"
                        private = $true
                    }
                })
            })

            { Assert-NoActiveGiteaActions -Context $script:actionsContext } | Should -Throw "*running*"

            $script:actionsApiRequests -join "," | Should -Be "user,admin/actions/runs?limit=50&page=1"
            $script:actionsApiRequests | Should -Not -Contain "repos/search?limit=50&page=1"
        }

        It "accepts only recognized terminal workflow statuses" {
            $terminalStatuses = @("success", "failure", "cancelled", "skipped")
            $runs = @($terminalStatuses | ForEach-Object {
                [pscustomobject]@{ id = 1; status = $_ }
            })
            $script:actionsRunPages = @([pscustomobject]@{
                total_count = $runs.Count
                workflow_runs = $runs
            })

            { Assert-NoActiveGiteaActions -Context $script:actionsContext } | Should -Not -Throw
        }

        It "rejects running, queued, waiting, blocked, and unknown statuses" {
            foreach ($status in @("running", "queued", "waiting", "blocked", "completed", "mystery")) {
                $script:actionsRunPages = @([pscustomobject]@{
                    total_count = 1
                    workflow_runs = @([pscustomobject]@{ id = 99; status = $status })
                })

                { Assert-NoActiveGiteaActions -Context $script:actionsContext } | Should -Throw
            }
        }

        It "reads every page of instance-wide workflow runs" {
            $firstPageRuns = @(1..50 | ForEach-Object {
                [pscustomobject]@{ id = $_; status = "success" }
            })
            $script:actionsRunPages = @(
                [pscustomobject]@{ total_count = 51; workflow_runs = $firstPageRuns },
                [pscustomobject]@{ total_count = 51; workflow_runs = @([pscustomobject]@{ id = 51; status = "success" }) }
            )

            { Assert-NoActiveGiteaActions -Context $script:actionsContext } | Should -Not -Throw

            $script:actionsApiRequests -join "," | Should -Be "user,admin/actions/runs?limit=50&page=1,admin/actions/runs?limit=50&page=2"
        }

        It "fails closed when a workflow-run page is incomplete" {
            $firstPageRuns = @(1..50 | ForEach-Object {
                [pscustomobject]@{ id = $_; status = "success" }
            })
            $script:actionsRunPages = @(
                [pscustomobject]@{ total_count = 51; workflow_runs = $firstPageRuns },
                [pscustomobject]@{ total_count = 51; workflow_runs = @() }
            )

            { Assert-NoActiveGiteaActions -Context $script:actionsContext } | Should -Throw "*incomplete*"

            $script:actionsApiRequests.Count | Should -Be 3
        }

        It "fails closed when the response does not match the official run-list contract" {
            $script:actionsRunPages = @([pscustomobject]@{
                workflow_runs = @()
            })

            { Assert-NoActiveGiteaActions -Context $script:actionsContext } | Should -Throw "*unexpected response*"

            $script:actionsRunPages = @([pscustomobject]@{
                total_count = "0"
                workflow_runs = @()
            })

            { Assert-NoActiveGiteaActions -Context $script:actionsContext } | Should -Throw "*invalid total*"
        }

        It "requires an administrator before calling the instance-wide endpoint" {
            $script:actionsApiIsAdmin = $false

            { Assert-NoActiveGiteaActions -Context $script:actionsContext } | Should -Throw "*not an administrator*"

            $script:actionsApiRequests.Count | Should -Be 1
            $script:actionsApiRequests[0] | Should -Be "user"
        }

        It "fails closed when the instance-wide endpoint denies access or errors" {
            $script:actionsApiFailure = $true

            { Assert-NoActiveGiteaActions -Context $script:actionsContext } | Should -Throw "*permission failure*"

            $script:actionsApiRequests.Count | Should -Be 2
            $script:actionsApiRequests[1] | Should -Be "admin/actions/runs?limit=50&page=1"
        }
    }
}

Describe "Gitea lifecycle safety helpers" {
    InModuleScope gitea-lifecycle {
        BeforeAll {
            $TestRoot = (Get-PSDrive -Name TestDrive).Root
        }

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

        It "accepts the Gitea 1.27 to 28.x versioning boundary and direct 28-series maintenance updates" {
            { Assert-SupportedGiteaVersionStep -CurrentVersion "1.27.9" -TargetVersion "28.3.0" } | Should -Not -Throw
            { Assert-SupportedGiteaVersionStep -CurrentVersion "28.0.0" -TargetVersion "28.3.0" } | Should -Not -Throw
            { Assert-SupportedGiteaVersionStep -CurrentVersion "28.2.0" -TargetVersion "28.3.0" } | Should -Not -Throw
        }

        It "rejects floating, same-or-older, and unverified multi-series targets" {
            { Assert-SupportedGiteaVersionStep -CurrentVersion "1.25.5" -TargetVersion "latest" } | Should -Throw
            { Assert-SupportedGiteaVersionStep -CurrentVersion "1.25.5" -TargetVersion "1.25.5" } | Should -Throw
            { Assert-SupportedGiteaVersionStep -CurrentVersion "1.25.5" -TargetVersion "28.3.0" } | Should -Throw
        }

        It "fails closed on insufficient backup capacity before stopping services" {
            Mock Assert-BackupCapacity { throw "insufficient-space" }

            { Invoke-GiteaLifecycle -Action upgrade -Context $script:upgradeContext -GiteaVersion "1.26.0" } | Should -Throw "insufficient-space"

            $script:lifecycleActions | Should -Not -Contain "stop-runner"
            $script:lifecycleActions | Should -Not -Contain "backup"
            $script:lifecycleActions | Should -Not -Contain "pin-image"
            $script:lifecycleActions | Should -Not -Contain "create-gitea"
        }

        It "resumes the original Runner when new Actions work is detected after it stops" {
            $script:actionsCheckCount = 0
            Mock Assert-NoActiveGiteaActions {
                $script:actionsCheckCount += 1
                if ($script:actionsCheckCount -eq 3) { throw "active-run-detected" }
            }
            Mock Get-GiteaContainerInfo {
                return [pscustomobject]@{ State = [pscustomobject]@{ Status = "running" } }
            }

            { Invoke-GiteaLifecycle -Action upgrade -Context $script:upgradeContext -GiteaVersion "1.26.0" } | Should -Throw "active-run-detected"

            $script:lifecycleActions | Should -Contain "stop-runner"
            $script:lifecycleActions | Should -Contain "health"
            $script:lifecycleActions | Should -Contain "start-runner"
            $script:lifecycleActions | Should -Not -Contain "backup"
            $script:lifecycleActions | Should -Not -Contain "create-gitea"
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
            $context.BackupRoot = $root
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
            Invoke-GiteaLifecycle -Action upgrade -Context $script:upgradeContext -GiteaVersion "1.26.0"

            $script:lifecycleActions.IndexOf("backup") | Should -BeLessThan $script:lifecycleActions.IndexOf("docker rename agent-sdlc-gitea agent-sdlc-gitea-preupgrade-20261105T000000Z-0123456789abcdef0123456789abcdef")
            $script:lifecycleActions.IndexOf("backup") | Should -BeLessThan $script:lifecycleActions.IndexOf("create-gitea")
            $script:lifecycleActions | Should -Contain "set-recovery-marker"
            $script:lifecycleActions | Should -Contain "clear-recovery-marker"
            $script:lifecycleActions | Should -Contain "start-runner"
            $script:lifecycleActions.IndexOf("set-recovery-marker") | Should -BeLessThan $script:lifecycleActions.IndexOf("pin-image")
            $script:lifecycleActions.IndexOf("api-version") | Should -BeLessThan $script:lifecycleActions.IndexOf("pin-image")
            $script:lifecycleActions | Should -Not -Contain "docker start agent-sdlc-gitea"
        }

        It "does not change the bootstrap image when the recovery marker cannot be written" {
            Mock Get-GiteaContainerInfo {
                return [pscustomobject]@{
                    State = [pscustomobject]@{ Status = "running" }
                }
            }
            Mock Set-GiteaLifecycleRecoveryMarker { throw "marker-write-failed" }

            { Invoke-GiteaLifecycle -Action upgrade -Context $script:upgradeContext -GiteaVersion "1.26.0" } | Should -Throw "marker-write-failed"

            $script:lifecycleActions | Should -Contain "backup"
            $script:lifecycleActions | Should -Contain "start-runner"
            $script:lifecycleActions | Should -Not -Contain "pin-image"
            $script:lifecycleActions | Should -Not -Contain "create-gitea"
        }

        It "resumes the unchanged source service and original Runner when stopping Gitea fails" {
            $script:sourceContainerStopped = $false
            Mock Get-GiteaContainerInfo {
                $status = if ($script:sourceContainerStopped) { "exited" } else { "running" }
                return [pscustomobject]@{ State = [pscustomobject]@{ Status = $status } }
            }
            Mock Invoke-GiteaDocker {
                param($Arguments, $AllowFailure)
                $command = "docker $($Arguments -join ' ')"
                $script:lifecycleActions.Add($command)
                if ($command -eq "docker stop --time 60 agent-sdlc-gitea") {
                    $script:sourceContainerStopped = $true
                    throw "simulated-stop-failure"
                }
                return [pscustomobject]@{ ExitCode = 0; StdOut = ""; StdErr = "" }
            }

            { Invoke-GiteaLifecycle -Action upgrade -Context $script:upgradeContext -GiteaVersion "1.26.0" } | Should -Throw "simulated-stop-failure"

            $script:lifecycleActions | Should -Contain "docker start agent-sdlc-gitea"
            $script:lifecycleActions | Should -Contain "health"
            $script:lifecycleActions | Should -Contain "start-runner"
            $script:lifecycleActions | Should -Not -Contain "backup"
            $script:lifecycleActions | Should -Not -Contain "pin-image"
            $script:lifecycleActions | Should -Not -Contain "create-gitea"
        }

        It "retains the backup and does not automatically roll back after a health failure" {
            $script:failGiteaHealth = $true

            { Invoke-GiteaLifecycle -Action upgrade -Context $script:upgradeContext -GiteaVersion "1.26.0" } | Should -Throw

            $script:lifecycleActions | Should -Contain "backup"
            $script:lifecycleActions | Should -Contain "create-gitea"
            $script:lifecycleActions | Should -Contain "set-recovery-marker"
            $script:lifecycleActions | Should -Not -Contain "clear-recovery-marker"
            $script:lifecycleActions | Should -Not -Contain "docker start agent-sdlc-gitea"
            $script:lifecycleActions | Should -Not -Contain "start-runner"
        }
    }
}

Describe "Gitea lifecycle operator restore command" {
    InModuleScope gitea-lifecycle {
        BeforeAll {
            $TestRoot = (Get-PSDrive -Name TestDrive).Root
        }

        BeforeEach {
            $script:restoreActions = [System.Collections.Generic.List[string]]::new()
            $script:restoreContext = @{
                RepoRoot = (Join-Path $TestRoot "repo")
                ConfigPath = (Join-Path $TestRoot "repo/config/dev/gitea-bootstrap.json")
                ConfigSource = "template"
                BackupRoot = (Join-Path $TestRoot "backups")
                GiteaDataDir = (Join-Path $TestRoot "repo/.agent-sdlc/dev-env/gitea/data")
                GiteaConfigDir = (Join-Path $TestRoot "repo/.agent-sdlc/dev-env/gitea/config")
                GiteaPostgresDataDir = (Join-Path $TestRoot "repo/.agent-sdlc/dev-env/gitea/postgres-data")
                GiteaSecretsPath = (Join-Path $TestRoot "repo/.agent-sdlc/dev-env/gitea/generated-secrets.json")
                GiteaBootstrapSummaryPath = (Join-Path $TestRoot "repo/.agent-sdlc/dev-env/gitea/bootstrap-summary.json")
                EffectiveBootstrapSettingsPath = (Join-Path $TestRoot "repo/.agent-sdlc/dev-env/gitea/effective-settings.json")
                GiteaContainerName = "agent-sdlc-gitea"
                GiteaPostgresContainerName = "agent-sdlc-gitea-db"
                GiteaRunnerContainerName = "agent-sdlc-gitea-runner"
                GiteaNetworkName = "agent-sdlc-gitea-network"
                GiteaRootUrl = "http://localhost:43000/"
                GiteaDatabaseMode = "postgres"
                GiteaHttpPort = 43000
                GiteaSshPort = 42222
                GiteaPostgresHostPort = 45432
                PortBindAddress = "127.0.0.1"
                GiteaPostgresDbName = "gitea"
                GiteaPostgresUser = "gitea"
                GiteaAdminUsername = "admin"
                GiteaAdminPassword = "fixture-secret"
            }

            $script:restorePayloadPath = Join-Path $TestRoot "selected-backup"
            $privatePath = Join-Path $script:restorePayloadPath "payload/private"
            New-Item -ItemType Directory -Path $privatePath -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $privatePath "postgres-topology.json"), "{}")
            $script:restoreRuntime = [pscustomobject]@{
                containerName = "agent-sdlc-gitea"
                networkMode = "agent-sdlc-gitea-network"
                imageReference = "docker.gitea.com/gitea@sha256:$('b' * 64)"
                sourceVersion = "1.26.0"
                environment = @("GITEA__database__DB_TYPE=postgres")
                mounts = @(@{ destination = "/var/lib/gitea" }, @{ destination = "/etc/gitea" })
                ports = @(@{ containerPort = "3000/tcp" }, @{ containerPort = "2222/tcp" })
            }
            $script:selectedBackup = [pscustomobject]@{
                Path = $script:restorePayloadPath
                Manifest = [pscustomobject]@{ runnerWasRunning = $false }
            }

            Mock Assert-NativeWindowsHost {}
            Mock Assert-DockerDesktopReady { return @{ id = "isolated-test-engine" } }
            Mock Get-BackupRuntime { return $script:restoreRuntime }
            Mock Assert-BackupRuntimeMatchesContext {}
            Mock Read-GiteaRestoreContext { return [pscustomobject]@{ databaseName = "gitea"; databaseUser = "gitea"; configSource = "template" } }
            Mock Assert-ConfigRestoreCompatibility {}
            Mock Assert-PostgresContainerIdentity { return [pscustomobject]@{ Name = "/agent-sdlc-gitea-db" } }
            Mock Assert-PostgresRestoreCompatibility {}
            Mock Assert-GiteaDatabaseTarget {}
            Mock Assert-GiteaContainerIdentity { return $null }
            Mock Get-GiteaRunnerInfo { return [pscustomobject]@{ State = [pscustomobject]@{ Status = "exited" } } }
            Mock Get-GiteaApiHealth { return [pscustomobject]@{ IsHealthy = $false; Version = "" } }
            Mock Invoke-GiteaDocker {
                param($Arguments, $AllowFailure)
                $script:restoreActions.Add("docker $($Arguments -join ' ')")
                return [pscustomobject]@{ ExitCode = 0; StdOut = ""; StdErr = "" }
            }
            Mock Assert-BackupCapacity { return [pscustomobject]@{ SourceBytes = 10; RequiredFreeBytes = 1024; AvailableFreeBytes = 4096 } }
            Mock Confirm-GiteaLifecycleOperation { $script:restoreActions.Add("confirm") }
            Mock Stop-GiteaRunner { $script:restoreActions.Add("stop-runner") }
            Mock New-GiteaBackupSet {
                param($Context, $Kind, $GiteaContainer, $PostgresContainer, $SourceVersion, $RunnerWasRunning, $Capacity)
                $script:restoreActions.Add("backup-$Kind")
                return [pscustomobject]@{ BackupId = "20261105T000001Z-0123456789abcdef0123456789abcdef"; Path = "C:\isolated-backups\diagnostic" }
            }
            Mock Set-GiteaLifecycleRecoveryMarker { $script:restoreActions.Add("set-recovery-marker") }
            Mock Invoke-GiteaPostgresRestore {
                param($Context, $DumpPath)
                $script:restoreActions.Add("restore-postgres:$DumpPath")
            }
            Mock Replace-GiteaDataTree {
                param($BackupSource, $LiveDestination)
                $script:restoreActions.Add("replace-data:$BackupSource->$LiveDestination")
            }
            Mock Restore-GiteaOperatorState {
                param($Context, $BackupPath, $RestoreContext)
                $script:restoreActions.Add("restore-operator-state:$BackupPath")
            }
            Mock New-GiteaContainerFromRuntime {
                param($Context, $Runtime, $ImageReference)
                $script:restoreActions.Add("create-gitea:$ImageReference")
            }
            Mock Wait-GiteaHealthy { $script:restoreActions.Add("health") }
            Mock Assert-GiteaApiVersion { $script:restoreActions.Add("api-version") }
            Mock New-GiteaOperationRecord { $script:restoreActions.Add("operation-record") }
            Mock Clear-GiteaLifecycleRecoveryMarker { $script:restoreActions.Add("clear-recovery-marker") }
        }

        It "rejects a restore without a valid Backup ID before service or data operations" {
            { Invoke-GiteaLifecycle -Action restore -Context $script:restoreContext -BackupId "bad-id" } | Should -Throw
            $script:restoreActions | Should -BeNullOrEmpty
        }

        It "refuses a restore whose backup manifest is missing or corrupt" {
            $backupId = "20261105T000000Z-0123456789abcdef0123456789abcdef"
            $backupPath = Join-Path $script:restoreContext.BackupRoot $backupId
            New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
            Mock Ensure-BackupRoot { param($Context) return [string]$Context.BackupRoot }

            { Invoke-GiteaLifecycle -Action restore -Context $script:restoreContext -BackupId $backupId } | Should -Throw "*failed integrity validation*"
            $script:restoreActions | Should -BeNullOrEmpty
        }

        It "does not stop or overwrite the service when typed confirmation is rejected" {
            Mock Get-GiteaBackupById { return $script:selectedBackup }
            Mock Confirm-GiteaLifecycleOperation {
                $script:restoreActions.Add("confirm")
                throw "confirmation-mismatch"
            }

            { Invoke-GiteaLifecycle -Action restore -Context $script:restoreContext -BackupId "20261105T000000Z-0123456789abcdef0123456789abcdef" } | Should -Throw "confirmation-mismatch"

            $script:restoreActions | Should -Contain "confirm"
            $script:restoreActions | Should -Not -Contain "stop-runner"
            $script:restoreActions | Should -Not -Contain "backup-pre-restore-diagnostic"
            @($script:restoreActions | Where-Object { $_ -like "restore-postgres:*" }) | Should -BeNullOrEmpty
            @($script:restoreActions | Where-Object { $_ -like "restore-operator-state:*" }) | Should -BeNullOrEmpty
        }

        It "creates a diagnostic backup before restoring matching PostgreSQL and Gitea state" {
            Mock Get-GiteaBackupById { return $script:selectedBackup }

            Invoke-GiteaLifecycle -Action restore -Context $script:restoreContext -BackupId "20261105T000000Z-0123456789abcdef0123456789abcdef"

            foreach ($expectedAction in @(
                "backup-pre-restore-diagnostic",
                "set-recovery-marker",
                "restore-postgres:$($script:restorePayloadPath)\payload\postgres.dump",
                "replace-data:$($script:restorePayloadPath)\payload\gitea-data->$($script:restoreContext.GiteaDataDir)",
                "replace-data:$($script:restorePayloadPath)\payload\gitea-config->$($script:restoreContext.GiteaConfigDir)",
                "restore-operator-state:$($script:restorePayloadPath)",
                "create-gitea:$($script:restoreRuntime.imageReference)",
                "health",
                "api-version",
                "operation-record",
                "clear-recovery-marker"
            )) {
                $script:restoreActions | Should -Contain $expectedAction
            }

            $script:restoreActions.IndexOf("backup-pre-restore-diagnostic") | Should -BeLessThan $script:restoreActions.IndexOf("set-recovery-marker")
            $script:restoreActions.IndexOf("set-recovery-marker") | Should -BeLessThan $script:restoreActions.IndexOf("restore-postgres:$($script:restorePayloadPath)\payload\postgres.dump")
            $script:restoreActions.IndexOf("restore-postgres:$($script:restorePayloadPath)\payload\postgres.dump") | Should -BeLessThan $script:restoreActions.IndexOf("replace-data:$($script:restorePayloadPath)\payload\gitea-data->$($script:restoreContext.GiteaDataDir)")
            $script:restoreActions.IndexOf("replace-data:$($script:restorePayloadPath)\payload\gitea-data->$($script:restoreContext.GiteaDataDir)") | Should -BeLessThan $script:restoreActions.IndexOf("replace-data:$($script:restorePayloadPath)\payload\gitea-config->$($script:restoreContext.GiteaConfigDir)")
            $script:restoreActions.IndexOf("replace-data:$($script:restorePayloadPath)\payload\gitea-config->$($script:restoreContext.GiteaConfigDir)") | Should -BeLessThan $script:restoreActions.IndexOf("restore-operator-state:$($script:restorePayloadPath)")
            $script:restoreActions.IndexOf("restore-operator-state:$($script:restorePayloadPath)") | Should -BeLessThan $script:restoreActions.IndexOf("create-gitea:$($script:restoreRuntime.imageReference)")
            $script:restoreActions.IndexOf("api-version") | Should -BeLessThan $script:restoreActions.IndexOf("operation-record")
            $script:restoreActions.IndexOf("operation-record") | Should -BeLessThan $script:restoreActions.IndexOf("clear-recovery-marker")
            $script:restoreActions | Should -Contain "clear-recovery-marker"
        }

        It "retains the recovery marker and diagnostic backup when PostgreSQL restore fails" {
            Mock Get-GiteaBackupById { return $script:selectedBackup }
            Mock Invoke-GiteaPostgresRestore { throw "simulated-postgres-restore-failure" }

            { Invoke-GiteaLifecycle -Action restore -Context $script:restoreContext -BackupId "20261105T000000Z-0123456789abcdef0123456789abcdef" } | Should -Throw "simulated-postgres-restore-failure"

            $script:restoreActions | Should -Contain "backup-pre-restore-diagnostic"
            $script:restoreActions | Should -Contain "set-recovery-marker"
            $script:restoreActions | Should -Not -Contain "clear-recovery-marker"
            $script:restoreActions | Should -Not -Contain "create-gitea:$($script:restoreRuntime.imageReference)"
        }
    }
}

Describe "Gitea PostgreSQL exact-state restore" {
    InModuleScope gitea-lifecycle {
        BeforeEach {
            $script:postgresRestoreInputCalls = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-GiteaDockerWithInputFile {
                param($Arguments, $InputPath)
                $script:postgresRestoreInputCalls.Add([pscustomobject]@{
                    Arguments = @($Arguments)
                    InputPath = $InputPath
                })
                if (@($Arguments) -contains "--list") {
                    return ";     dbname: gitea`n;     TOC Entries: 123"
                }
                return ""
            }
        }

        It "recreates only the database named by the selected archive in the existing PostgreSQL container" {
            $context = @{
                GiteaPostgresContainerName = "fixture-postgres"
                GiteaPostgresDbName = "gitea"
            }

            Invoke-GiteaPostgresRestore -Context $context -DumpPath "C:\isolated-backups\fixture\payload\postgres.dump"

            $script:postgresRestoreInputCalls.Count | Should -Be 2
            ($script:postgresRestoreInputCalls[0].Arguments -join " ") | Should -Be "exec -i fixture-postgres pg_restore --list"
            $script:postgresRestoreInputCalls[0].InputPath | Should -Be "C:\isolated-backups\fixture\payload\postgres.dump"
            $restoreCommand = [string]$script:postgresRestoreInputCalls[1].Arguments[-1]
            $restoreCommand | Should -Match 'pg_restore --clean --if-exists --create --exit-on-error'
            $restoreCommand | Should -Match '--username "\$POSTGRES_USER" --dbname postgres'
            $restoreCommand | Should -Not -Match '--dbname "\$POSTGRES_DB"'
            $script:postgresRestoreInputCalls[1].Arguments[2] | Should -Be "fixture-postgres"
            $script:postgresRestoreInputCalls[1].InputPath | Should -Be "C:\isolated-backups\fixture\payload\postgres.dump"
        }

        It "refuses an archive whose embedded database name differs from the configured Gitea database" {
            Mock Invoke-GiteaDockerWithInputFile {
                param($Arguments, $InputPath)
                return ";     dbname: unrelated_database`n;     TOC Entries: 123"
            }
            $context = @{
                GiteaPostgresContainerName = "fixture-postgres"
                GiteaPostgresDbName = "gitea"
            }

            { Invoke-GiteaPostgresRestore -Context $context -DumpPath "C:\isolated-backups\fixture\payload\postgres.dump" } | Should -Throw "*database name*does not match*"

            Should -Invoke Invoke-GiteaDockerWithInputFile -Times 1 -ParameterFilter { @($Arguments) -contains "--list" }
        }
    }
}

Describe "Gitea backup ACL on real NTFS" -Tag "WindowsAcl" {
    It "restricts real backup directories and files from non-elevated Windows PowerShell" {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            Set-ItResult -Skipped -Because "This ACL integration check requires Windows NTFS."
            return
        }

        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
        $administratorsSid = [System.Security.Principal.SecurityIdentifier]::new("S-1-5-32-544")
        if ($principal.IsInRole($administratorsSid)) {
            Set-ItResult -Skipped -Because "Run this ACL check from non-elevated Windows PowerShell."
            return
        }

        $whoamiPath = Join-Path $env:WINDIR "System32\whoami.exe"
        $privilegeOutput = @(& $whoamiPath /priv 2>$null)
        if ($LASTEXITCODE -ne 0) {
            throw "Could not inspect the Windows token privileges for the NTFS ACL test."
        }
        $securityPrivilege = @($privilegeOutput | Where-Object { $_ -match '^\s*SeSecurityPrivilege\s+' })
        if (@($securityPrivilege | Where-Object { $_ -match '\bEnabled\b' }).Count -gt 0) {
            throw "The NTFS ACL test requires SeSecurityPrivilege to be absent or disabled."
        }

        $tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
        $runId = [Guid]::NewGuid().ToString("N")
        $fixtureRoot = Join-Path $tempParent "agent-sdlc-gitea-acl-$runId"
        $backupRoot = Join-Path $fixtureRoot "backup-root"
        $markerPath = Join-Path $fixtureRoot ".agent-sdlc-acl-test-owner"
        $sections = [System.Security.AccessControl.AccessControlSections]::Access -bor
            [System.Security.AccessControl.AccessControlSections]::Owner
        $currentSid = $identity.User
        $expectedSidValues = @($currentSid.Value, "S-1-5-18", "S-1-5-32-544")
        $expectedDirectoryInheritance = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
            [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        $markerValue = "agent-sdlc-gitea-acl-test:$runId"
        $fixtureRootCreated = $false
        $markerCreatedByThisRun = $false
        $markerWriteCompleted = $false

        try {
            $drive = [System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($fixtureRoot))
            $drive.DriveFormat | Should -Be "NTFS"

            (Test-Path -LiteralPath $fixtureRoot) | Should -BeFalse
            New-Item -ItemType Directory -Path $fixtureRoot -ErrorAction Stop | Out-Null
            $fixtureRootCreated = $true
            $markerStream = [System.IO.File]::Open(
                $markerPath,
                [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::None
            )
            $markerCreatedByThisRun = $true
            try {
                $markerBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($markerValue)
                $markerStream.Write($markerBytes, 0, $markerBytes.Length)
                $markerStream.Flush($true)
                $markerWriteCompleted = $true
            }
            finally {
                $markerStream.Dispose()
            }

            $context = @{
                BackupRoot = $backupRoot
                RepoRoot = Join-Path $fixtureRoot "repo"
                GiteaDataDir = Join-Path $fixtureRoot "live-data"
                GiteaConfigDir = Join-Path $fixtureRoot "live-config"
                GiteaPostgresDataDir = Join-Path $fixtureRoot "live-postgres"
            }
            Invoke-GiteaLifecycle -Action backup-list -Context $context

            $rootAcl = [System.IO.Directory]::GetAccessControl($backupRoot, $sections)
            $rootAcl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value | Should -Be $currentSid.Value
            $rootAcl.AreAccessRulesProtected | Should -BeTrue
            $rootRules = @($rootAcl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
            $rootRules.Count | Should -Be 3
            (@($rootRules | ForEach-Object { $_.IdentityReference.Value } | Sort-Object) -join ",") |
                Should -Be (@($expectedSidValues | Sort-Object) -join ",")
            foreach ($rule in $rootRules) {
                $rule.IsInherited | Should -BeFalse
                $rule.AccessControlType | Should -Be ([System.Security.AccessControl.AccessControlType]::Allow)
                [int]$rule.FileSystemRights | Should -Be ([int][System.Security.AccessControl.FileSystemRights]::FullControl)
                $rule.InheritanceFlags | Should -Be $expectedDirectoryInheritance
                $rule.PropagationFlags | Should -Be ([System.Security.AccessControl.PropagationFlags]::None)
            }

            $childDirectory = Join-Path $backupRoot "inherited-child"
            New-Item -ItemType Directory -Path $childDirectory -ErrorAction Stop | Out-Null
            $childAcl = [System.IO.Directory]::GetAccessControl($childDirectory, $sections)
            $childAcl.AreAccessRulesProtected | Should -BeFalse
            $childRules = @($childAcl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
            $childRules.Count | Should -Be 3
            (@($childRules | ForEach-Object { $_.IdentityReference.Value } | Sort-Object) -join ",") |
                Should -Be (@($expectedSidValues | Sort-Object) -join ",")
            foreach ($rule in $childRules) {
                $rule.IsInherited | Should -BeTrue
                $rule.AccessControlType | Should -Be ([System.Security.AccessControl.AccessControlType]::Allow)
                [int]$rule.FileSystemRights | Should -Be ([int][System.Security.AccessControl.FileSystemRights]::FullControl)
            }

            $effectiveAccessFile = Join-Path $childDirectory "effective-access.txt"
            [System.IO.File]::WriteAllText($effectiveAccessFile, "write-check", [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::ReadAllText($effectiveAccessFile) | Should -Be "write-check"

            $privateFile = Join-Path $backupRoot "private-test.dat"
            [System.IO.File]::WriteAllText($privateFile, "private", [System.Text.UTF8Encoding]::new($false))
            InModuleScope gitea-lifecycle -Parameters @{ Path = $privateFile } {
                param($Path)
                Set-RestrictedBackupAcl -Path $Path
            }
            $privateAcl = [System.IO.File]::GetAccessControl($privateFile, $sections)
            $privateAcl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value | Should -Be $currentSid.Value
            $privateAcl.AreAccessRulesProtected | Should -BeTrue
            $privateRules = @($privateAcl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
            $privateRules.Count | Should -Be 3
            (@($privateRules | ForEach-Object { $_.IdentityReference.Value } | Sort-Object) -join ",") |
                Should -Be (@($expectedSidValues | Sort-Object) -join ",")
            foreach ($rule in $privateRules) {
                $rule.IsInherited | Should -BeFalse
                $rule.AccessControlType | Should -Be ([System.Security.AccessControl.AccessControlType]::Allow)
                [int]$rule.FileSystemRights | Should -Be ([int][System.Security.AccessControl.FileSystemRights]::FullControl)
                $rule.InheritanceFlags | Should -Be ([System.Security.AccessControl.InheritanceFlags]::None)
            }
            [System.IO.File]::WriteAllText($privateFile, "updated", [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::ReadAllText($privateFile) | Should -Be "updated"
        }
        finally {
            if ($fixtureRootCreated -and (Test-Path -LiteralPath $fixtureRoot -PathType Container)) {
                $resolvedFixtureRoot = [System.IO.Path]::GetFullPath($fixtureRoot)
                $tempPrefix = $tempParent + [System.IO.Path]::DirectorySeparatorChar
                $resolvedFixtureRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) | Should -BeTrue
                [System.IO.Path]::GetFileName($resolvedFixtureRoot) | Should -Be "agent-sdlc-gitea-acl-$runId"
                ([System.IO.Path]::GetDirectoryName($resolvedFixtureRoot)).Equals(
                    $tempParent,
                    [StringComparison]::OrdinalIgnoreCase
                ) | Should -BeTrue
                (([System.IO.File]::GetAttributes($resolvedFixtureRoot) -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) |
                    Should -BeTrue

                $fixtureRootAcl = [System.IO.Directory]::GetAccessControl(
                    $resolvedFixtureRoot,
                    [System.Security.AccessControl.AccessControlSections]::Owner
                )
                $fixtureRootAcl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value | Should -Be $currentSid.Value

                if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
                    if (-not $markerCreatedByThisRun) {
                        throw "Refusing to clean the ACL test directory because its ownership marker was not created by this test."
                    }
                    if ($markerWriteCompleted) {
                        [System.IO.File]::ReadAllText($markerPath) | Should -Be $markerValue
                    }
                    Remove-Item -LiteralPath $resolvedFixtureRoot -Recurse -Force -ErrorAction Stop
                }
                else {
                    $remainingEntries = @(Get-ChildItem -LiteralPath $resolvedFixtureRoot -Force -ErrorAction Stop)
                    $remainingEntries.Count | Should -Be 0
                    [System.IO.Directory]::Delete($resolvedFixtureRoot, $false)
                }
            }
        }
    }
}

Describe "Gitea lifecycle backup long paths on real NTFS" -Tag "WindowsLongPath" {
    It "copies, checksums, validates, restores and safely cleans files beyond MAX_PATH" {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            Set-ItResult -Skipped -Because "This long-path regression check requires Windows NTFS."
            return
        }

        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
        $administratorsSid = [System.Security.Principal.SecurityIdentifier]::new("S-1-5-32-544")
        if ($principal.IsInRole($administratorsSid)) {
            Set-ItResult -Skipped -Because "Run this long-path regression check from non-elevated Windows PowerShell."
            return
        }

        $tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')
        $runId = [Guid]::NewGuid().ToString("N")
        $fixtureRoot = Join-Path $tempParent "agent-sdlc-gitea-long-path-$runId"
        $markerPath = Join-Path $fixtureRoot ".agent-sdlc-long-path-owner"
        $markerValue = "agent-sdlc-gitea-long-path-test:$runId"
        $drive = [System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($fixtureRoot))
        $drive.DriveFormat | Should -Be "NTFS"

        InModuleScope gitea-lifecycle -Parameters @{
            FixtureRoot = $fixtureRoot
            TempParent = $tempParent
            RunId = $runId
            MarkerPath = $markerPath
            MarkerValue = $markerValue
            CurrentUserSid = $identity.User.Value
        } {
            param($FixtureRoot, $TempParent, $RunId, $MarkerPath, $MarkerValue, $CurrentUserSid)

            $fixtureRootCreated = $false
            $markerWriteCompleted = $false
            try {
                New-LongPathDirectory -Path $FixtureRoot
                $fixtureRootCreated = $true
                Write-LongPathText -Path $MarkerPath -Text $MarkerValue
                $markerWriteCompleted = $true

                $sourceRoot = Join-Path $FixtureRoot "live-source"
                $backupPath = Join-Path $FixtureRoot ("backup-root-{0}-{1}" -f ("b" * 140), $RunId)
                $backupDataPath = Join-Path $backupPath "payload\gitea-data"
                $restoreRoot = Join-Path $FixtureRoot ("restored-live-root-{0}" -f ("r" * 72))
                $restoreDataPath = Join-Path $restoreRoot "gitea-data"
                $segmentOne = "repository-" + ("a" * 39)
                $segmentTwo = "objects-" + ("c" * 42)
                $fileName = "pack-" + ("d" * 31) + ".pack"
                $relativeObjectPath = Join-Path (Join-Path $segmentOne $segmentTwo) $fileName
                $sourceFile = Join-Path $sourceRoot $relativeObjectPath
                $targetFile = Join-Path $backupDataPath $relativeObjectPath
                $targetParent = Get-LongPathParent -Path $targetFile
                $payloadText = "real-NTFS-long-path-payload:$RunId"

                New-LongPathDirectory -Path (Get-LongPathParent -Path $sourceFile)
                New-LongPathDirectory -Path $backupPath
                Set-RestrictedBackupAcl -Path $backupPath
                New-LongPathDirectory -Path $targetParent
                Write-LongPathText -Path $sourceFile -Text $payloadText

                $sourceExistsBefore = Test-LongPath -Path $sourceFile -PathType Leaf
                $destinationParentExistsBefore = Test-LongPath -Path $targetParent -PathType Container
                $sourceExistsBefore | Should -BeTrue
                $destinationParentExistsBefore | Should -BeTrue
                $sourceFile.Length | Should -BeLessThan 260
                $targetFile.Length | Should -BeGreaterThan 260
                (Join-Path $backupPath "manifest.json").Length | Should -BeGreaterThan 260

                $legacyCopyOutcome = "succeeded"
                try {
                    Copy-Item -LiteralPath $sourceFile -Destination $targetFile -ErrorAction Stop
                }
                catch {
                    $legacyCopyOutcome = $_.Exception.GetBaseException().GetType().FullName
                }
                $sourceExistsAfter = Test-LongPath -Path $sourceFile -PathType Leaf
                $destinationParentExistsAfter = Test-LongPath -Path $targetParent -PathType Container
                Write-Host ("Long-path diagnostic: sourceBefore={0}; parentBefore={1}; sourceAfter={2}; parentAfter={3}; targetCharacters={4}; unprefixedCopyItem={5}" -f `
                    $sourceExistsBefore,
                    $destinationParentExistsBefore,
                    $sourceExistsAfter,
                    $destinationParentExistsAfter,
                    $targetFile.Length,
                    $legacyCopyOutcome)
                $sourceExistsAfter | Should -BeTrue
                $destinationParentExistsAfter | Should -BeTrue
                if (Test-LongPath -Path $targetFile -PathType Leaf) {
                    Remove-LongPathEntry -Path $targetFile
                }

                Copy-DirectoryTree -Source $sourceRoot -Destination $backupDataPath
                $expectedBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($payloadText)
                $sha256 = [System.Security.Cryptography.SHA256]::Create()
                try {
                    $expectedHash = [System.BitConverter]::ToString($sha256.ComputeHash($expectedBytes)).Replace('-', '').ToLowerInvariant()
                }
                finally {
                    $sha256.Dispose()
                }
                $entries = @(Get-BackupFileEntries -BackupPath $backupPath)
                $entries.Count | Should -Be 1
                $entries[0].path | Should -Be ("payload/gitea-data/" + ($relativeObjectPath -replace '\\', '/'))
                $entries[0].sizeBytes | Should -Be $expectedBytes.Length
                $entries[0].sha256 | Should -Be $expectedHash

                Save-BackupJson -Path (Join-Path $backupPath "manifest.json") -Value @{
                    schemaVersion = 1
                    backupId = Get-LongPathLeaf -Path $backupPath
                    files = $entries
                }
                $validation = Test-GiteaBackupIntegrity -BackupPath $backupPath
                $validation.IsValid | Should -BeTrue
                $validation.Reason | Should -Be "valid"

                New-LongPathDirectory -Path $restoreDataPath
                $staleFile = Join-Path $restoreDataPath "stale-before-restore.txt"
                Write-LongPathText -Path $staleFile -Text "must be removed"
                Replace-GiteaDataTree -BackupSource $backupDataPath -LiveDestination $restoreDataPath
                (Test-LongPath -Path $staleFile) | Should -BeFalse

                $restoredFile = Join-Path $restoreDataPath $relativeObjectPath
                (Test-LongPath -Path $restoredFile -PathType Leaf) | Should -BeTrue
                (Read-LongPathText -Path $restoredFile) | Should -Be $payloadText
                (Get-LongPathSha256 -Path $restoredFile) | Should -Be $expectedHash
                $restoredFile.Length | Should -BeGreaterThan 260
            }
            finally {
                if ($fixtureRootCreated -and (Test-LongPath -Path $FixtureRoot -PathType Container)) {
                    $resolvedRoot = Get-FullPath -Path $FixtureRoot
                    $expectedParent = Get-FullPath -Path $TempParent
                    (Get-LongPathParent -Path $resolvedRoot).Equals(
                        $expectedParent,
                        [StringComparison]::OrdinalIgnoreCase
                    ) | Should -BeTrue
                    (Get-LongPathLeaf -Path $resolvedRoot) | Should -Be "agent-sdlc-gitea-long-path-$RunId"
                    ((Get-LongPathItem -Path $resolvedRoot).Attributes -band [System.IO.FileAttributes]::ReparsePoint) |
                        Should -Be ([System.IO.FileAttributes]::Normal)

                    if (Test-LongPath -Path $MarkerPath -PathType Leaf) {
                        if (-not $markerWriteCompleted) {
                            throw "Refusing long-path fixture cleanup because its ownership marker was not fully written."
                        }
                        (Read-LongPathText -Path $MarkerPath) | Should -Be $MarkerValue
                        $ownerAcl = [System.IO.Directory]::GetAccessControl(
                            (ConvertTo-ExtendedLengthPath -Path $resolvedRoot),
                            [System.Security.AccessControl.AccessControlSections]::Owner
                        )
                        $ownerAcl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value | Should -Be $CurrentUserSid
                        Remove-LongPathTree -Path $resolvedRoot
                    }
                    else {
                        @(Get-LongPathDirectoryEntries -Path $resolvedRoot).Count | Should -Be 0
                        [System.IO.Directory]::Delete((ConvertTo-ExtendedLengthPath -Path $resolvedRoot), $false)
                    }
                    (Test-LongPath -Path $resolvedRoot) | Should -BeFalse
                }
            }
        }
    }
}
