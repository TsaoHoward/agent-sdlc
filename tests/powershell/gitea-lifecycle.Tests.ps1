BeforeDiscovery {
    $modulePath = Join-Path $PSScriptRoot "../../scripts/dev/gitea-lifecycle.psm1"
    Import-Module (Resolve-Path $modulePath) -Force
}

Describe "Native Windows PowerShell 5.1 ProcessStartInfo argv boundary" -Tag "WindowsProcessArgv" -Skip:($env:OS -ne "Windows_NT" -or $PSVersionTable.PSVersion.Major -ne 5) {
    InModuleScope gitea-lifecycle -Parameters @{ TestDrive = $TestDrive; PSHome = $PSHOME } {
        param($TestDrive, $PSHome)
        It "round-trips empty, spaced, Unicode, quote, and leading/trailing slash arguments through a real child process" {
        $childPath = Join-Path $TestDrive "argv echo.ps1"
        $childScript = '[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false); $result = [pscustomobject]@{ commandLine = [Environment]::CommandLine; arguments = @($args) }; ConvertTo-Json -InputObject $result -Depth 4 -Compress'
        [System.IO.File]::WriteAllText($childPath, $childScript, [System.Text.UTF8Encoding]::new($false))
        $expected = @("", "two words", "雪貓 café", 'quote"inside', "leading space", "trailing space ", "path with space\", '\\server\share\', 'slashes \\" around')
        $powershellPath = Join-Path $PSHOME "powershell.exe"
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $powershellPath
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $processArguments = @("-NoProfile", "-NonInteractive", "-File", $childPath) + $expected
        $rawArguments = ConvertTo-ProcessArgumentString -Arguments $processArguments
        $startInfo.Arguments = $rawArguments
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        $process.ExitCode | Should -Be 0 -Because $stderr
        $childResult = ConvertFrom-Json -InputObject $stdout -ErrorAction Stop
        $childResult | Should -Not -BeNullOrEmpty -Because "ProcessStartInfo.Arguments was <$rawArguments>; child stdout was <$stdout>"
        $childResult.commandLine | Should -Match ([regex]::Escape($childPath)) -Because "ProcessStartInfo.Arguments was <$rawArguments>; child stdout was <$stdout>"
        $actual = @($childResult.arguments)
        $actual.Count | Should -Be $expected.Count
        for ($index = 0; $index -lt $expected.Count; $index += 1) {
            [string]$actual[$index] | Should -BeExactly $expected[$index] -Because "ProcessStartInfo.Arguments was <$rawArguments>; child command line was <$($childResult.commandLine)>; child stdout was <$stdout>"
        }
        }
    }
}

Describe "Gitea lifecycle read-only status" {
    InModuleScope gitea-lifecycle -Parameters @{ TestDrive = $TestDrive } {
        param($TestDrive)
        It "does not create lifecycle state while reading an empty status" {
            $repoRoot = Join-Path $TestDrive "status-read-only"
            New-Item -ItemType Directory -Path $repoRoot -Force | Out-Null
            $context = @{ RepoRoot = $repoRoot }

            $status = Get-GiteaLifecycleStatus -Context $context

            $status.RecoveryPending | Should -BeFalse
            $status.Marker | Should -BeNullOrEmpty
            $status.LatestOperationRecord | Should -BeNullOrEmpty
            Test-Path -LiteralPath (Join-Path $repoRoot ".agent-sdlc\dev-env\gitea") | Should -BeFalse
        }

        It "fails closed on an invalid marker without changing it" {
            $repoRoot = Join-Path $TestDrive "status-invalid-marker"
            $markerDirectory = Join-Path $repoRoot ".agent-sdlc\dev-env\gitea"
            New-Item -ItemType Directory -Path $markerDirectory -Force | Out-Null
            $markerPath = Join-Path $markerDirectory "lifecycle-recovery.json"
            [System.IO.File]::WriteAllText($markerPath, "{ invalid json", [System.Text.UTF8Encoding]::new($false))
            $before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($markerPath))

            { Get-GiteaLifecycleStatus -Context @{ RepoRoot = $repoRoot } } | Should -Throw "*unreadable*"

            [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($markerPath)) | Should -BeExactly $before
        }
    }
}

Describe "Gitea lifecycle append-only operation records" {
    InModuleScope gitea-lifecycle -Parameters @{ TestDrive = $TestDrive } {
        param($TestDrive)

        It "accepts an identical retry and rejects replacement content without changing terminal evidence" {
            $context = @{ RepoRoot = (Join-Path $TestDrive "append-only-records") }
            $record = @{
                schemaVersion = 2
                operationId = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                operationKind = "upgrade"
                result = "interrupted-target-start-attempted"
                completedAt = "2026-11-10T00:00:00.0000000Z"
                backupId = "20261110T000000Z-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
            }

            New-GiteaOperationRecord -Context $context -Record $record | Out-Null
            $recordPath = Get-GiteaOperationRecordPath -Context $context -OperationId $record.operationId
            $originalBytes = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($recordPath))
            New-GiteaOperationRecord -Context $context -Record $record | Should -Not -BeNullOrEmpty

            $conflict = @{} + $record
            $conflict.result = "reconciled-original-source-without-restore"
            { New-GiteaOperationRecord -Context $context -Record $conflict } | Should -Throw "*append-only*"
            [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($recordPath)) | Should -BeExactly $originalBytes
        }

        It "clears a legacy marker only while its deterministic reconciliation record remains unchanged" {
            $context = @{ RepoRoot = (Join-Path $TestDrive "legacy-terminal-marker") }
            $backupId = "20261108T053419Z-a5737137148a41a9bc45d6f7a78485df"
            $recordId = "b92dd52df319a08fd98c6cba181a75e0"
            $markerPath = Get-GiteaLifecycleRecoveryMarkerPath -Context $context
            New-Item -ItemType Directory -Path (Get-LongPathParent -Path $markerPath) -Force | Out-Null
            [System.IO.File]::WriteAllText(
                $markerPath,
                (ConvertTo-Json -InputObject ([pscustomobject]@{
                    schemaVersion = 1
                    operationKind = "upgrade"
                    backupId = $backupId
                }) -Compress),
                [System.Text.UTF8Encoding]::new($false)
            )
            $record = New-GiteaOperationRecord -Context $context -Record @{
                schemaVersion = 2
                operationId = $recordId
                operationKind = "reconcile-recovery"
                result = "reconciled-original-source-without-restore"
                recoveryMode = "original-source"
                backupId = $backupId
                markerSchemaVersion = 1
                databaseRestorePerformed = $false
                lifecycleTransaction = "complete"
                integrationAcceptance = "pending"
                operatorAttestation = "RECONCILE original-source $backupId DATABASE VERIFIED"
                giteaContainerId = "a" * 64
                postgresContainerId = "b" * 64
                runnerContainerId = "c" * 64
                sourceVersion = "1.26.4"
            }
            $recordPath = Get-GiteaOperationRecordPath -Context $context -OperationId $recordId
            $conflict = ConvertTo-Json -InputObject $record -Depth 100 -Compress | ConvertFrom-Json
            $conflict.sourceVersion = "1.27.3"
            [System.IO.File]::WriteAllText($recordPath, (ConvertTo-Json -InputObject $conflict -Depth 100 -Compress), [System.Text.UTF8Encoding]::new($false))

            {
                Clear-GiteaLifecycleRecoveryMarker -Context $context -ExpectedLegacySchemaVersion 1 -ExpectedLegacyOperationKind "upgrade" -ExpectedLegacyBackupId $backupId -ExpectedLegacyRecoveryMode "original-source" -ExpectedReconciliationRecord $record
            } | Should -Throw "*changed after verification*"
            Test-LongPath -Path $markerPath -PathType Leaf | Should -BeTrue

            [System.IO.File]::WriteAllText($recordPath, (ConvertTo-Json -InputObject $record -Depth 100 -Compress), [System.Text.UTF8Encoding]::new($false))
            Clear-GiteaLifecycleRecoveryMarker -Context $context -ExpectedLegacySchemaVersion 1 -ExpectedLegacyOperationKind "upgrade" -ExpectedLegacyBackupId $backupId -ExpectedLegacyRecoveryMode "original-source" -ExpectedReconciliationRecord $record
            Test-LongPath -Path $markerPath -PathType Leaf | Should -BeFalse
            Test-LongPath -Path $recordPath -PathType Leaf | Should -BeTrue
        }

        It "clears a schema-3 marker only after its matching terminal record is reloadable" {
            $context = @{ RepoRoot = (Join-Path $TestDrive "terminal-marker") }
            $operationId = "cccccccccccccccccccccccccccccccc"
            $backupId = "20261110T000000Z-dddddddddddddddddddddddddddddddd"
            Set-GiteaLifecycleRecoveryMarker -Context $context -OperationKind restore -BackupId $backupId -OperationId $operationId -Phase "restore-prepared" -NextAction "stop-runner"
            $markerPath = Get-GiteaLifecycleRecoveryMarkerPath -Context $context

            { Clear-GiteaLifecycleRecoveryMarker -Context $context -OperationId $operationId } | Should -Throw "*terminal Operation Record*"
            Test-LongPath -Path $markerPath -PathType Leaf | Should -BeTrue

            New-GiteaOperationRecord -Context $context -Record @{
                schemaVersion = 2
                operationId = $operationId
                operationKind = "restore"
                result = "interrupted-restore-prepared"
                completedAt = [DateTime]::UtcNow.ToString("o")
                backupId = $backupId
            } | Out-Null
            Clear-GiteaLifecycleRecoveryMarker -Context $context -OperationId $operationId
            Test-LongPath -Path $markerPath | Should -BeFalse
        }
    }
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

        It "accepts the existing terminal statuses and completed runs with valid conclusions and timestamps" {
            $terminalStatuses = @("success", "failure", "cancelled", "skipped")
            $legacyRuns = @($terminalStatuses | ForEach-Object {
                [pscustomobject]@{ id = 1; status = $_ }
            })
            $completedRuns = @(
                [pscustomobject]@{
                    id = 95
                    status = "completed"
                    conclusion = "failure"
                    completed_at = "2026-11-06T11:52:25Z"
                }
                [pscustomobject]@{
                    id = 96
                    status = "completed"
                    conclusion = "success"
                    completed_at = "2026-11-06T11:52:25.123456789+00:00"
                }
                [pscustomobject]@{
                    id = 97
                    status = "completed"
                    conclusion = "cancelled"
                    completed_at = "2026-11-06T19:52:25+08:00"
                }
                [pscustomobject]@{
                    id = 98
                    status = "completed"
                    conclusion = "skipped"
                    completed_at = "2026-11-06T11:52:25Z"
                }
            )
            $runs = @($legacyRuns) + @($completedRuns)
            $script:actionsRunPages = @([pscustomobject]@{
                total_count = $runs.Count
                workflow_runs = $runs
            })

            { Assert-NoActiveGiteaActions -Context $script:actionsContext } | Should -Not -Throw
        }

        It "rejects running, queued, waiting, blocked, and unknown statuses" {
            foreach ($status in @("running", "queued", "waiting", "blocked", "mystery", "Completed")) {
                $script:actionsRunPages = @([pscustomobject]@{
                    total_count = 1
                    workflow_runs = @([pscustomobject]@{ id = 99; status = $status })
                })

                { Assert-NoActiveGiteaActions -Context $script:actionsContext } | Should -Throw
            }
        }

        It "fails closed when a completed run is missing or has an invalid conclusion or completion time" {
            $invalidCompletedRuns = @(
                [pscustomobject]@{ id = 95; status = "completed"; completed_at = "2026-11-06T11:52:25Z" }
                [pscustomobject]@{ id = 95; status = "completed"; conclusion = $null; completed_at = "2026-11-06T11:52:25Z" }
                [pscustomobject]@{ id = 95; status = "completed"; conclusion = "neutral"; completed_at = "2026-11-06T11:52:25Z" }
                [pscustomobject]@{ id = 95; status = "completed"; conclusion = "Failure"; completed_at = "2026-11-06T11:52:25Z" }
                [pscustomobject]@{ id = 95; status = "completed"; conclusion = "failure" }
                [pscustomobject]@{ id = 95; status = "completed"; conclusion = "failure"; completed_at = $null }
                [pscustomobject]@{ id = 95; status = "completed"; conclusion = "failure"; completed_at = "" }
                [pscustomobject]@{ id = 95; status = "completed"; conclusion = "failure"; completed_at = "not-a-time" }
                [pscustomobject]@{ id = 95; status = "completed"; conclusion = "failure"; completed_at = "2026-02-30T11:52:25Z" }
                [pscustomobject]@{ id = 95; status = "completed"; conclusion = "failure"; completed_at = "2026-11-06T11:52:25" }
            )

            foreach ($run in $invalidCompletedRuns) {
                $script:actionsRunPages = @([pscustomobject]@{
                    total_count = 1
                    workflow_runs = @($run)
                })

                { Assert-NoActiveGiteaActions -Context $script:actionsContext } | Should -Throw
            }
        }

        It "fails closed when a run has no status field" {
            $script:actionsRunPages = @([pscustomobject]@{
                total_count = 1
                workflow_runs = @([pscustomobject]@{ id = 99 })
            })

            { Assert-NoActiveGiteaActions -Context $script:actionsContext } | Should -Throw "*without a status*"
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

Describe "Gitea immutable image digest resolution" {
    InModuleScope gitea-lifecycle {
        BeforeEach {
            $script:imageInspectStdOut = "[]"
            $script:localImageId = "sha256:$('f' * 64)"
            $script:imageInspectCalls = [System.Collections.Generic.List[object]]::new()

            Mock Invoke-GiteaDocker {
                param($Arguments, $AllowFailure)
                $script:imageInspectCalls.Add(@($Arguments))
                if ($Arguments -contains "{{.Id}}") {
                    return [pscustomobject]@{ ExitCode = 0; StdOut = $script:localImageId; StdErr = "" }
                }
                return [pscustomobject]@{ ExitCode = 0; StdOut = $script:imageInspectStdOut; StdErr = "" }
            }
        }

        It "selects one official digest from multiple RepoDigests under Windows PowerShell 5.1" {
            $first = "docker.gitea.com/gitea@sha256:$('a' * 64)"
            $second = "docker.gitea.com/gitea@sha256:$('b' * 64)"
            $third = "docker.gitea.com/gitea@sha256:$('c' * 64)"
            $script:imageInspectStdOut = '["' + $first + '","' + $second + '","' + $third + '"]'

            $reference = Get-ImageDigestReference -Image "docker.gitea.com/gitea:1.26.4-rootless" -RequireRegistryDigest

            $reference | Should -Be $first
            @($reference).Count | Should -Be 1
            $reference | Should -Match '^docker\.gitea\.com/gitea@sha256:[0-9a-f]{64}$'
        }

        It "deduplicates repeated RepoDigests while returning one legal reference" {
            $digest = "docker.gitea.com/gitea@sha256:$('d' * 64)"
            $script:imageInspectStdOut = '["' + $digest + '","' + $digest + '"]'

            $reference = Get-ImageDigestReference -Image "docker.gitea.com/gitea:1.26.4-rootless" -RequireRegistryDigest

            $reference | Should -Be $digest
            @($reference).Count | Should -Be 1
        }

        It "ignores valid RepoDigests from other repositories and chooses the official Gitea reference" {
            $other = "ghcr.io/mirror/gitea@sha256:$('e' * 64)"
            $official = "docker.gitea.com/gitea@sha256:$('a' * 64)"
            $script:imageInspectStdOut = '["' + $other + '","' + $official + '"]'

            $reference = Get-ImageDigestReference -Image "docker.gitea.com/gitea:1.26.4-rootless" -RequireRegistryDigest

            $reference | Should -Be $official
            @($reference).Count | Should -Be 1
        }

        It "rejects malformed JSON and malformed RepoDigest entries instead of persisting them" {
            $script:imageInspectStdOut = '["docker.gitea.com/gitea@sha256:'
            { Get-ImageDigestReference -Image "docker.gitea.com/gitea:1.26.4-rootless" } | Should -Throw

            $script:imageInspectStdOut = '["docker.gitea.com/gitea@sha256:bad"]'
            { Get-ImageDigestReference -Image "docker.gitea.com/gitea:1.26.4-rootless" } | Should -Throw

            $script:imageInspectStdOut = '[null]'
            { Get-ImageDigestReference -Image "docker.gitea.com/gitea:1.26.4-rootless" } | Should -Throw

            $script:imageInspectStdOut = '{}'
            { Get-ImageDigestReference -Image "docker.gitea.com/gitea:1.26.4-rootless" } | Should -Throw

            $script:imageInspectStdOut = '[7]'
            { Get-ImageDigestReference -Image "docker.gitea.com/gitea:1.26.4-rootless" } | Should -Throw

            $script:imageInspectStdOut = '[]'
            { Get-ImageDigestReference -Image "docker.gitea.com/gitea:1.26.4-rootless" -RequireRegistryDigest } | Should -Throw
        }

        It "uses a valid local image ID only when no repository digest exists" {
            $script:imageInspectStdOut = "[]"

            $reference = Get-ImageDigestReference -Image "agent-sdlc-local:gitea"

            $reference | Should -Be $script:localImageId
            $script:imageInspectCalls.Count | Should -Be 2
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
            $script:upgradeRecoveryMarker = $null
            $script:upgradeTerminalRecord = $null
            $script:upgradeCreatedBackupId = $null
            $script:upgradeMarkerBackupId = $null
            $script:upgradeMarkerOperationId = $null
            $script:upgradeGiteaEnvironment = @()
            $script:upgradeGiteaArgs = @()
            $script:upgradeContext = @{
                RepoRoot = (Join-Path $TestRoot "upgrade-repo")
                BackupRoot = (Join-Path $TestRoot "upgrade-backups")
                GiteaDataDir = (Join-Path $TestRoot "upgrade-live\data")
                GiteaPostgresDataDir = (Join-Path $TestRoot "upgrade-live\postgres-data")
                GiteaContainerName = "agent-sdlc-gitea"
                GiteaRunnerContainerName = "agent-sdlc-gitea-runner"
                GiteaPostgresContainerName = "agent-sdlc-gitea-db"
                GiteaConfigDir = (Join-Path $TestRoot "upgrade-config")
                ConfigPath = (Join-Path $TestRoot "upgrade-repo\config\dev\gitea-bootstrap.json")
                ConfigSource = "template"
                GiteaNetworkName = "agent-sdlc-gitea-network"
                GiteaRootUrl = "http://localhost:43000/"
            }
            New-Item -ItemType Directory -Path $script:upgradeContext.GiteaConfigDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:upgradeContext.GiteaConfigDir "app.ini"), "[storage]`r`nSTORAGE_TYPE = local`r`n[attachment]`r`nPATH = data/attachments`r`n[lfs]`r`nPATH = data/lfs`r`n", [System.Text.UTF8Encoding]::new($false))

            $script:upgradeBackupId = "20261105T000000Z-0123456789abcdef0123456789abcdef"
            $script:upgradeBackupPath = Join-Path $script:upgradeContext.BackupRoot $script:upgradeBackupId
            $script:upgradeRuntimeSnapshot = [pscustomobject]@{
                schemaVersion = 1
                containerName = "agent-sdlc-gitea"
                capturedContainerName = "agent-sdlc-gitea"
                containerId = "1111111111111111111111111111111111111111111111111111111111111111"
                statusAtCapture = "running"
                sourceVersion = "1.25.5"
                originalImageReference = "docker.gitea.com/gitea:1.25.5-rootless"
                imageReference = "docker.gitea.com/gitea@sha256:$('a' * 64)"
                imageId = "sha256:$('a' * 64)"
                networkMode = "agent-sdlc-gitea-network"
                restartPolicy = "unless-stopped"
                ports = @(
                    [pscustomobject]@{ containerPort = "3000/tcp"; hostIp = "127.0.0.1"; hostPort = "43000" }
                    [pscustomobject]@{ containerPort = "2222/tcp"; hostIp = "127.0.0.1"; hostPort = "43022" }
                )
                mounts = @(
                    [pscustomobject]@{ type = "bind"; source = $script:upgradeContext.GiteaDataDir; destination = "/var/lib/gitea"; readWrite = $true }
                    [pscustomobject]@{ type = "bind"; source = $script:upgradeContext.GiteaConfigDir; destination = "/etc/gitea"; readWrite = $true }
                )
                environment = @()
                configSource = "template"
                configPath = $script:upgradeContext.ConfigPath
            }

            $backupPrivatePath = Join-Path $script:upgradeBackupPath "payload/private"
            $backupDataPath = Join-Path $script:upgradeBackupPath "payload/gitea-data"
            $backupConfigPath = Join-Path $script:upgradeBackupPath "payload/gitea-config"
            $backupOperatorPath = Join-Path $script:upgradeBackupPath "payload/operator-state"
            foreach ($directory in @($backupPrivatePath, $backupDataPath, $backupConfigPath, $backupOperatorPath)) {
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
            }
            [System.IO.File]::WriteAllBytes((Join-Path $script:upgradeBackupPath "payload/postgres.dump"), [System.Text.Encoding]::ASCII.GetBytes("PGDMP-fixture"))
            [System.IO.File]::WriteAllText((Join-Path $backupDataPath "fixture-data.txt"), "isolated backup data", [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $backupConfigPath "app.ini"), [System.IO.File]::ReadAllText((Join-Path $script:upgradeContext.GiteaConfigDir "app.ini")), [System.Text.UTF8Encoding]::new($false))
            Save-BackupJson -Path (Join-Path $backupPrivatePath "gitea-runtime.json") -Value $script:upgradeRuntimeSnapshot
            Save-BackupJson -Path (Join-Path $backupPrivatePath "postgres-topology.json") -Value @{
                schemaVersion = 1
                containerName = "agent-sdlc-gitea-db"
                containerId = "2222222222222222222222222222222222222222222222222222222222222222"
                originalImageReference = "postgres:16"
                imageId = "sha256:$('f' * 64)"
                networkMode = "agent-sdlc-gitea-network"
                networkAliases = @("db")
                databaseName = "gitea"
                databaseUser = "gitea"
                ports = @(@{ containerPort = "5432/tcp"; hostIp = "127.0.0.1"; hostPort = "43001" })
                mounts = @(@{ type = "bind"; source = $script:upgradeContext.GiteaPostgresDataDir; destination = "/var/lib/postgresql/data"; readWrite = $true })
            }
            Save-BackupJson -Path (Join-Path $backupPrivatePath "restore-context.json") -Value @{
                schemaVersion = 1
                configPath = $script:upgradeContext.ConfigPath
                configSource = "template"
                databaseName = "gitea"
                databaseUser = "gitea"
                runnerWasRunning = $true
            }
            Save-BackupJson -Path (Join-Path $backupOperatorPath "bootstrap-config.json") -Value @{ gitea = @{ image = "docker.gitea.com/gitea:1.25.5-rootless" } }
            $script:upgradeManifest = [ordered]@{
                schemaVersion = 2
                format = "agent-sdlc-gitea-backup"
                backupId = $script:upgradeBackupId
                operationId = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                kind = "upgrade"
                createdAt = "2026-11-05T00:00:00.0000000Z"
                sourceVersion = "1.25.5"
                sourceImage = "docker.gitea.com/gitea:1.25.5-rootless"
                sourceImageDigest = "docker.gitea.com/gitea@sha256:$('a' * 64)"
                dockerHost = "isolated-test-engine"
                hostPort = 43000
                network = "agent-sdlc-gitea-network"
                runnerWasRunning = $true
                sourceBytes = [long]10
                availableBytesBeforeBackup = [long]4096
                requiredComponents = @("postgres-dump", "gitea-data", "gitea-config", "operator-state", "runtime-snapshot", "postgres-topology", "restore-context")
                sizeBytes = [long]0
                files = @()
            }
            $script:upgradeManifest.files = @(Get-BackupFileEntries -BackupPath $script:upgradeBackupPath)
            $script:upgradeManifest.sizeBytes = Measure-BackupFileEntriesSize -Entries $script:upgradeManifest.files
            $script:upgradeManifest.metadataSha256 = Get-GiteaBackupManifestDigest -Manifest ([pscustomobject]$script:upgradeManifest)
            Save-BackupJson -Path (Join-Path $script:upgradeBackupPath "manifest.json") -Value $script:upgradeManifest
            $upgradeFixtureIntegrity = Test-GiteaBackupIntegrity -BackupPath $script:upgradeBackupPath
            $upgradeFixtureIntegrity.IsValid | Should -BeTrue -Because "the shared Upgrade fixture must have a valid manifest and complete payload ($($upgradeFixtureIntegrity.Reason))"

            Mock Assert-NativeWindowsHost {}
            Mock Assert-DockerDesktopReady { return @{ id = "isolated-test-engine" } }
            Mock Assert-NoPendingGiteaRecovery {}
            Mock Ensure-BackupRoot {}
            Mock Assert-GiteaConfigCanBePinned {}
            Mock Assert-GiteaContainerIdentity {
                return [pscustomobject]@{
                    Id = "1111111111111111111111111111111111111111111111111111111111111111"
                    Name = "/agent-sdlc-gitea"
                    Image = "sha256:$('a' * 64)"
                    State = [pscustomobject]@{ Status = "running" }
                    Args = @($script:upgradeGiteaArgs)
                    Config = [pscustomobject]@{
                        Image = "docker.gitea.com/gitea:1.25.5-rootless"
                        Env = @($script:upgradeGiteaEnvironment)
                        Cmd = @()
                    }
                }
            }
            Mock Assert-PostgresContainerIdentity {
                return [pscustomobject]@{
                    Id = "2222222222222222222222222222222222222222222222222222222222222222"
                    Name = "/agent-sdlc-gitea-db"
                    Image = "sha256:$('f' * 64)"
                    State = [pscustomobject]@{ Status = "running" }
                    Config = [pscustomobject]@{ Image = "postgres:16"; Env = @("POSTGRES_DB=gitea", "POSTGRES_USER=gitea", "POSTGRES_PASSWORD=fixture-secret") }
                }
            }
            Mock Get-GiteaRunnerInfo {
                return [pscustomobject]@{
                    Id = "3333333333333333333333333333333333333333333333333333333333333333"
                    Name = "/agent-sdlc-gitea-runner"
                    State = [pscustomobject]@{ Status = "running" }
                }
            }
            Mock Get-GiteaReportedVersion { return "1.25.5" }
            Mock Get-RuntimeSnapshot { return $script:upgradeRuntimeSnapshot }
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
            Mock New-GiteaBackupId { return $script:upgradeBackupId }
            Mock New-GiteaBackupSet {
                param($BackupId)
                if ([string]$BackupId -cne [string]$script:upgradeBackupId) {
                    throw "The Upgrade Backup ID did not match the isolated fixture."
                }
                $script:upgradeCreatedBackupId = [string]$BackupId
                $script:lifecycleActions.Add("backup")
                return [pscustomobject]@{
                    BackupId = $BackupId
                    Path = $script:upgradeBackupPath
                    Manifest = [pscustomobject]$script:upgradeManifest
                }
            }
            Mock Get-BackupRuntime {
                $script:lifecycleActions.Add("read-runtime")
                return $script:upgradeRuntimeSnapshot
            }
            Mock New-GiteaContainerFromRuntime { $script:lifecycleActions.Add("create-gitea") }
            Mock Wait-GiteaHealthy {
                $script:lifecycleActions.Add("health")
                if ($script:failGiteaHealth) { throw "simulated health failure" }
            }
            Mock Assert-GiteaApiVersion { $script:lifecycleActions.Add("api-version") }
            Mock Set-GiteaBootstrapImagePin { $script:lifecycleActions.Add("pin-image") }
            Mock Set-GiteaLifecycleRecoveryMarker {
                param(
                    $Context, $OperationKind, $BackupId, $DiagnosticBackupId, $Phase, $OperationId,
                    $NextAction, $LastCompletedStage, $GiteaContainerId, $TargetContainerId,
                    $PostgresContainerId, $RunnerContainerId, $SourceImageId, $SourceImageReference,
                    $SourceOriginalImageReference, $SourceVersion, $TargetImageDigest, $TargetVersion,
                    $GiteaState, $PostgresState, $RunnerState, $SupersedesOperationId,
                    $PriorDiagnosticBackupIds, $ReplaceExisting
                )
                $createdAt = [DateTime]::UtcNow.ToString("o")
                $script:upgradeRecoveryMarker = [pscustomobject]@{
                    schemaVersion = 3
                    operationId = $OperationId
                    operationKind = $OperationKind
                    phase = $Phase
                    backupId = $BackupId
                    diagnosticBackupId = $DiagnosticBackupId
                    revision = 1
                    createdAt = $createdAt
                    updatedAt = $createdAt
                    lastCompletedStage = $LastCompletedStage
                    nextAction = $NextAction
                    giteaContainerId = $GiteaContainerId
                    targetContainerId = $TargetContainerId
                    postgresContainerId = $PostgresContainerId
                    runnerContainerId = $RunnerContainerId
                    sourceImageId = $SourceImageId
                    sourceImageReference = $SourceImageReference
                    sourceOriginalImageReference = $SourceOriginalImageReference
                    sourceVersion = $SourceVersion
                    targetImageDigest = $TargetImageDigest
                    targetVersion = $TargetVersion
                    giteaState = $GiteaState
                    postgresState = $PostgresState
                    runnerState = $RunnerState
                    supersedesOperationId = $SupersedesOperationId
                    priorDiagnosticBackupIds = @($PriorDiagnosticBackupIds)
                }
                $script:upgradeMarkerBackupId = [string]$BackupId
                $script:upgradeMarkerOperationId = [string]$OperationId
                $script:lifecycleActions.Add("set-recovery-marker")
            }
            Mock Get-GiteaLifecycleRecoveryMarker { return $script:upgradeRecoveryMarker }
            Mock Update-GiteaLifecycleRecoveryMarkerPhase {
                param($Context, $BackupId, $OperationId, $Phase, $NextAction, $LastCompletedStage, $DiagnosticBackupId, $GiteaContainerId, $TargetContainerId, $RunnerState)
                if (-not $script:upgradeRecoveryMarker -or [string]$script:upgradeRecoveryMarker.operationId -cne [string]$OperationId -or [string]$script:upgradeRecoveryMarker.backupId -cne [string]$BackupId) {
                    throw "The persisted Recovery Marker operation identity changed; refusing to advance another attempt."
                }
                $script:upgradeRecoveryMarker.phase = $Phase
                if ($NextAction) { $script:upgradeRecoveryMarker.nextAction = $NextAction }
                if ($LastCompletedStage) { $script:upgradeRecoveryMarker.lastCompletedStage = $LastCompletedStage }
                if ($DiagnosticBackupId) { $script:upgradeRecoveryMarker.diagnosticBackupId = $DiagnosticBackupId }
                if ($GiteaContainerId) { $script:upgradeRecoveryMarker.giteaContainerId = $GiteaContainerId }
                if ($TargetContainerId) { $script:upgradeRecoveryMarker.targetContainerId = $TargetContainerId }
                if ($RunnerState) { $script:upgradeRecoveryMarker.runnerState = $RunnerState }
                $script:upgradeRecoveryMarker.revision = [int]$script:upgradeRecoveryMarker.revision + 1
                $script:upgradeRecoveryMarker.updatedAt = [DateTime]::UtcNow.ToString("o")
                $script:lifecycleActions.Add("target-start-attempted")
            }
            Mock Clear-GiteaLifecycleRecoveryMarker {
                param($Context, $OperationId)
                if (-not $script:upgradeRecoveryMarker -or [string]$script:upgradeRecoveryMarker.operationId -cne [string]$OperationId -or
                    -not $script:upgradeTerminalRecord -or [string]$script:upgradeTerminalRecord.operationId -cne [string]$OperationId) {
                    throw "A matching terminal Operation Record is required before clearing the Recovery Marker."
                }
                $script:lifecycleActions.Add("clear-recovery-marker")
                $script:upgradeRecoveryMarker = $null
            }
            Mock Start-GiteaRunner { $script:lifecycleActions.Add("start-runner") }
            Mock New-GiteaOperationRecord {
                param($Context, $Record)
                $script:upgradeTerminalRecord = $Record
                $script:lifecycleActions.Add("operation-record")
            }
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

        It "blocks external storage selected by app.ini before backup-root or service changes" {
            [System.IO.File]::WriteAllText((Join-Path $script:upgradeContext.GiteaConfigDir "app.ini"), "[storage]`r`nSTORAGE_TYPE = local`r`n[attachment]`r`nSTORAGE_TYPE = minio`r`n", [System.Text.UTF8Encoding]::new($false))

            { Invoke-GiteaLifecycle -Action upgrade -Context $script:upgradeContext -GiteaVersion "1.26.4" } | Should -Throw "*outside the backup payload*"

            $script:lifecycleActions | Should -Not -Contain "stop-runner"
            $script:lifecycleActions | Should -Not -Contain "backup"
            $script:lifecycleActions | Should -Not -Contain "set-recovery-marker"
            Should -Invoke Ensure-BackupRoot -Times 0 -Exactly
        }

        It "blocks storage environment overrides and uncovered paths before service changes" {
            $script:upgradeGiteaEnvironment = @("GITEA__storage__STORAGE_TYPE=s3")
            { Invoke-GiteaLifecycle -Action upgrade -Context $script:upgradeContext -GiteaVersion "1.26.4" } | Should -Throw "*outside the backup payload*"

            $script:upgradeGiteaEnvironment = @("GITEA_CONFIG=/tmp/external-app.ini")
            { Invoke-GiteaLifecycle -Action upgrade -Context $script:upgradeContext -GiteaVersion "1.26.4" } | Should -Throw "*outside the captured /etc/gitea payload*"

            $script:upgradeGiteaEnvironment = @("GITEA__picture__REPOSITORY_AVATAR_UPLOAD_PATH=/srv/external-avatars")
            { Invoke-GiteaLifecycle -Action upgrade -Context $script:upgradeContext -GiteaVersion "1.26.4" } | Should -Throw "*outside the captured*"

            $script:upgradeGiteaEnvironment = @()
            [System.IO.File]::WriteAllText((Join-Path $script:upgradeContext.GiteaConfigDir "app.ini"), "[storage]`r`nSTORAGE_TYPE = local`r`n[picture]`r`nAVATAR_UPLOAD_PATH = /mnt/external/avatars`r`n", [System.Text.UTF8Encoding]::new($false))
            { Invoke-GiteaLifecycle -Action upgrade -Context $script:upgradeContext -GiteaVersion "1.26.4" } | Should -Throw "*outside the captured*"

            $script:lifecycleActions | Should -Not -Contain "stop-runner"
            $script:lifecycleActions | Should -Not -Contain "backup"
            $script:lifecycleActions | Should -Not -Contain "set-recovery-marker"
            Should -Invoke Ensure-BackupRoot -Times 0 -Exactly
        }

        It "accepts an empty container Environment during Upgrade preflight" {
            $script:upgradeGiteaEnvironment = @()
            Mock Assert-BackupCapacity { throw "empty-environment-preflight-reached" }

            { Invoke-GiteaLifecycle -Action upgrade -Context $script:upgradeContext -GiteaVersion "1.26.4" } | Should -Throw "empty-environment-preflight-reached"

            $script:lifecycleActions | Should -Not -Contain "stop-runner"
            $script:lifecycleActions | Should -Not -Contain "backup"
            $script:lifecycleActions | Should -Not -Contain "set-recovery-marker"
        }

        It "parses storage Environment overrides before proceeding with Upgrade preflight" {
            $script:upgradeGiteaEnvironment = @("GITEA__picture__AVATAR_UPLOAD_PATH=data/avatars")
            Mock Assert-BackupCapacity { throw "storage-environment-preflight-reached" }

            { Invoke-GiteaLifecycle -Action upgrade -Context $script:upgradeContext -GiteaVersion "1.26.4" } | Should -Throw "storage-environment-preflight-reached"

            $script:lifecycleActions | Should -Not -Contain "stop-runner"
            $script:lifecycleActions | Should -Not -Contain "backup"
            $script:lifecycleActions | Should -Not -Contain "set-recovery-marker"
        }

        It "blocks an explicit app.ini command override outside the mounted config before service changes" {
            $script:upgradeGiteaArgs = @("web", "--config", "/tmp/external-app.ini")

            { Invoke-GiteaLifecycle -Action upgrade -Context $script:upgradeContext -GiteaVersion "1.26.4" } | Should -Throw "*outside the captured /etc/gitea payload*"

            $script:lifecycleActions | Should -Not -Contain "stop-runner"
            $script:lifecycleActions | Should -Not -Contain "set-recovery-marker"
            Should -Invoke Ensure-BackupRoot -Times 0 -Exactly
        }

        It "validates the source image reference before stopping Gitea or Runner" {
            Mock Get-RuntimeSnapshot { throw "source RepoDigests are malformed" }

            { Invoke-GiteaLifecycle -Action upgrade -Context $script:upgradeContext -GiteaVersion "1.26.4" } | Should -Throw "*source RepoDigests are malformed*"

            $script:lifecycleActions | Should -Not -Contain "stop-runner"
            $script:lifecycleActions | Should -Not -Contain "backup"
            $script:lifecycleActions | Should -Not -Contain "docker stop --time 60 agent-sdlc-gitea"
        }

        It "retains the Recovery Marker and does not auto-resume when Actions work appears after Runner stop" {
            $script:actionsCheckCount = 0
            Mock Assert-NoActiveGiteaActions {
                $script:actionsCheckCount += 1
                if ($script:actionsCheckCount -eq 3) { throw "active-run-detected" }
            }
            Mock Get-GiteaContainerInfo {
                return [pscustomobject]@{ State = [pscustomobject]@{ Status = "running" } }
            }

            $failureMessage = $null
            try {
                Invoke-GiteaLifecycle -Action upgrade -Context $script:upgradeContext -GiteaVersion "1.26.0"
            }
            catch {
                $failureMessage = $_.Exception.Message
            }

            $failureMessage | Should -Match "active-run-detected"

            $script:lifecycleActions | Should -Contain "stop-runner"
            $script:lifecycleActions | Should -Contain "set-recovery-marker"
            $script:lifecycleActions | Should -Not -Contain "clear-recovery-marker"
            $script:lifecycleActions | Should -Not -Contain "health"
            $script:lifecycleActions | Should -Not -Contain "start-runner"
            $script:lifecycleActions | Should -Not -Contain "docker start agent-sdlc-gitea"
            $script:lifecycleActions | Should -Not -Contain "backup"
            $script:lifecycleActions | Should -Not -Contain "create-gitea"

            $marker = $script:upgradeRecoveryMarker
            $marker.schemaVersion | Should -Be 3
            $marker.operationId | Should -BeExactly $script:upgradeMarkerOperationId
            $script:upgradeTerminalRecord.operationKind | Should -BeExactly "upgrade"
            $script:upgradeTerminalRecord.result | Should -BeExactly "interrupted-upgrade-prepared"
            $script:upgradeTerminalRecord.errorSummary | Should -Match "active-run-detected"
            $script:upgradeTerminalRecord.operationId | Should -BeExactly $marker.operationId
            $script:upgradeTerminalRecord.backupId | Should -BeExactly $marker.backupId
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
                sizeBytes = [long](Get-Item -LiteralPath $payloadFile).Length
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
            $script:upgradeTerminalRecord.operationKind | Should -BeExactly "upgrade"
            $script:upgradeTerminalRecord.operationId | Should -Match "^[0-9a-f]{32}$"
            $script:upgradeTerminalRecord.startedAt | Should -Not -BeNullOrEmpty
            $script:upgradeMarkerBackupId | Should -BeExactly $script:upgradeCreatedBackupId
            $script:upgradeCreatedBackupId | Should -BeExactly $script:upgradeBackupId
            $script:upgradeTerminalRecord.operationId | Should -BeExactly $script:upgradeMarkerOperationId
            $script:upgradeTerminalRecord.backupId | Should -BeExactly $script:upgradeMarkerBackupId
            $script:upgradeTerminalRecord.result | Should -BeExactly "healthy-manual-smoke-required"
        }

        It "does not change the bootstrap image when the recovery marker cannot be written" {
            Mock Get-GiteaContainerInfo {
                return [pscustomobject]@{
                    State = [pscustomobject]@{ Status = "running" }
                }
            }
            Mock Set-GiteaLifecycleRecoveryMarker { throw "marker-write-failed" }

            { Invoke-GiteaLifecycle -Action upgrade -Context $script:upgradeContext -GiteaVersion "1.26.0" } | Should -Throw "marker-write-failed"

            $script:lifecycleActions | Should -Not -Contain "backup"
            $script:lifecycleActions | Should -Not -Contain "stop-runner"
            $script:lifecycleActions | Should -Not -Contain "pin-image"
            $script:lifecycleActions | Should -Not -Contain "create-gitea"
        }

        It "preserves a pre-marker Upgrade failure when an Operation Record write would fail" {
            $script:markerReadCount = 0
            Mock Get-GiteaLifecycleRecoveryMarker {
                $script:markerReadCount += 1
                if ($script:markerReadCount -gt 1) {
                    return [pscustomobject]@{
                        operationId = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                        operationKind = "upgrade"
                        phase = "upgrade-prepared"
                        backupId = "20261110T000000Z-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
                        createdAt = "2026-11-10T00:00:00.0000000Z"
                    }
                }
                return $null
            }
            Mock Assert-NativeWindowsHost { throw "preflight-root-cause" }
            Mock New-GiteaOperationRecord { throw "operation-record-write-failed" }

            $failureMessage = $null
            try {
                Invoke-GiteaLifecycle -Action upgrade -Context $script:upgradeContext -GiteaVersion "1.26.4"
            }
            catch {
                $failureMessage = $_.Exception.Message
            }

            $failureMessage | Should -BeExactly "preflight-root-cause"
            Should -Invoke New-GiteaOperationRecord -Times 0 -Exactly
        }

        It "writes the interrupted Operation Record after a verified Recovery Marker exists" {
            $script:actionsCheckCount = 0
            $script:upgradeRecoveryMarker = $null
            $script:upgradeTerminalRecord = $null
            $script:upgradeAttemptOperationId = $null
            Mock Set-GiteaLifecycleRecoveryMarker {
                param(
                    $Context, $OperationKind, $BackupId, $DiagnosticBackupId, $Phase, $OperationId,
                    $NextAction, $LastCompletedStage, $GiteaContainerId, $TargetContainerId,
                    $PostgresContainerId, $RunnerContainerId, $SourceImageId, $SourceImageReference,
                    $SourceOriginalImageReference, $SourceVersion, $TargetImageDigest, $TargetVersion,
                    $GiteaState, $PostgresState, $RunnerState, $SupersedesOperationId,
                    $PriorDiagnosticBackupIds, $ReplaceExisting
                )
                $script:upgradeAttemptOperationId = $OperationId
                $createdAt = "2026-11-10T00:00:00.0000000Z"
                $script:upgradeRecoveryMarker = [pscustomobject]@{
                    schemaVersion = 3
                    operationId = $OperationId
                    operationKind = $OperationKind
                    phase = $Phase
                    backupId = $BackupId
                    diagnosticBackupId = $DiagnosticBackupId
                    revision = 1
                    createdAt = $createdAt
                    updatedAt = $createdAt
                    lastCompletedStage = $LastCompletedStage
                    nextAction = $NextAction
                    giteaContainerId = $GiteaContainerId
                    targetContainerId = $TargetContainerId
                    postgresContainerId = $PostgresContainerId
                    runnerContainerId = $RunnerContainerId
                    sourceImageId = $SourceImageId
                    sourceImageReference = $SourceImageReference
                    sourceOriginalImageReference = $SourceOriginalImageReference
                    sourceVersion = $SourceVersion
                    targetImageDigest = $TargetImageDigest
                    targetVersion = $TargetVersion
                    giteaState = $GiteaState
                    postgresState = $PostgresState
                    runnerState = $RunnerState
                    supersedesOperationId = $SupersedesOperationId
                    priorDiagnosticBackupIds = @($PriorDiagnosticBackupIds)
                }
                $script:lifecycleActions.Add("set-recovery-marker:$OperationId")
            }
            Mock Get-GiteaLifecycleRecoveryMarker { return $script:upgradeRecoveryMarker }
            Mock Assert-NoActiveGiteaActions {
                $script:actionsCheckCount += 1
                $script:lifecycleActions.Add("assert-actions-$script:actionsCheckCount")
                if ($script:actionsCheckCount -eq 3) {
                    $script:lifecycleActions.Add("injected-fault:$($script:upgradeRecoveryMarker.operationId)")
                    throw "post-marker-root-cause"
                }
            }
            Mock New-GiteaOperationRecord {
                param($Context, $Record)
                $script:upgradeTerminalRecord = $Record
                $script:lifecycleActions.Add("operation-record:$($Record.operationId)")
            }

            $failureMessage = $null
            try {
                Invoke-GiteaLifecycle -Action upgrade -Context $script:upgradeContext -GiteaVersion "1.26.4"
            }
            catch {
                $failureMessage = $_.Exception.Message
            }

            $failureMessage | Should -Match "post-marker-root-cause"

            $marker = $script:upgradeRecoveryMarker
            $markerPropertyNames = [string[]]$marker.PSObject.Properties.Name
            foreach ($requiredMarkerProperty in @(
                "schemaVersion", "operationId", "operationKind", "phase", "backupId", "diagnosticBackupId",
                "revision", "createdAt", "updatedAt", "lastCompletedStage", "nextAction", "giteaContainerId",
                "targetContainerId", "postgresContainerId", "runnerContainerId", "sourceImageId",
                "sourceImageReference", "sourceOriginalImageReference", "sourceVersion", "targetImageDigest",
                "targetVersion", "giteaState", "postgresState", "runnerState", "supersedesOperationId",
                "priorDiagnosticBackupIds"
            )) {
                $markerPropertyNames | Should -Contain $requiredMarkerProperty
            }

            $marker.schemaVersion | Should -Be 3
            $marker.diagnosticBackupId | Should -BeNullOrEmpty
            $marker.operationId | Should -BeExactly $script:upgradeAttemptOperationId
            $marker.operationId | Should -Match "^[0-9a-f]{32}$"
            $script:upgradeTerminalRecord.operationKind | Should -BeExactly "upgrade"
            $script:upgradeTerminalRecord.result | Should -BeExactly "interrupted-upgrade-prepared"
            $script:upgradeTerminalRecord.errorSummary | Should -Match "post-marker-root-cause"
            $script:upgradeTerminalRecord.operationId | Should -BeExactly $marker.operationId
            $script:upgradeTerminalRecord.backupId | Should -BeExactly $marker.backupId

            $markerEvent = "set-recovery-marker:$($script:upgradeAttemptOperationId)"
            $faultEvent = "injected-fault:$($script:upgradeAttemptOperationId)"
            $recordEvent = "operation-record:$($script:upgradeAttemptOperationId)"
            $script:lifecycleActions | Should -Contain $markerEvent
            $script:lifecycleActions | Should -Contain $faultEvent
            $script:lifecycleActions | Should -Contain $recordEvent
            $script:lifecycleActions.IndexOf($markerEvent) | Should -BeLessThan $script:lifecycleActions.IndexOf($faultEvent)
            $script:lifecycleActions.IndexOf($faultEvent) | Should -BeLessThan $script:lifecycleActions.IndexOf($recordEvent)
        }

        It "surfaces the safe image-pin stage, exception type, and masked cause after health checks" {
            Mock Get-GiteaContainerInfo {
                return [pscustomobject]@{
                    State = [pscustomobject]@{ Status = "running" }
                }
            }
            Mock Set-GiteaBootstrapImagePin {
                throw "Bootstrap image pin update failed during stage 'atomically replace the existing bootstrap config'. Exception type 'System.UnauthorizedAccessException'. Masked cause: adminPassword=[REDACTED]"
            }

            $failureMessage = $null
            try {
                Invoke-GiteaLifecycle -Action upgrade -Context $script:upgradeContext -GiteaVersion "1.26.0"
            }
            catch {
                $failureMessage = $_.Exception.Message
            }

            $failureMessage | Should -Match "stage 'atomically replace the existing bootstrap config'"
            $failureMessage | Should -Match "System\.UnauthorizedAccessException"
            $failureMessage | Should -Match 'adminPassword=\[REDACTED\]'
            $failureMessage | Should -Match "Backup ID|backup '20261105T000000Z-0123456789abcdef0123456789abcdef'"
            $failureMessage | Should -Match 'Runner remains stopped'
            $script:lifecycleActions | Should -Contain "set-recovery-marker"
            $script:lifecycleActions | Should -Not -Contain "clear-recovery-marker"
            $script:lifecycleActions | Should -Not -Contain "start-runner"
        }

        It "fails closed without auto-resuming the source service or Runner when stopping Gitea fails" {
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

            $failureMessage = $null
            try {
                Invoke-GiteaLifecycle -Action upgrade -Context $script:upgradeContext -GiteaVersion "1.26.0"
            }
            catch {
                $failureMessage = $_.Exception.Message
            }

            $failureMessage | Should -Match "simulated-stop-failure"

            $script:lifecycleActions | Should -Contain "set-recovery-marker"
            $script:lifecycleActions | Should -Not -Contain "clear-recovery-marker"
            $script:lifecycleActions | Should -Not -Contain "docker start agent-sdlc-gitea"
            $script:lifecycleActions | Should -Not -Contain "health"
            $script:lifecycleActions | Should -Not -Contain "start-runner"
            $script:lifecycleActions | Should -Not -Contain "backup"
            $script:lifecycleActions | Should -Not -Contain "pin-image"
            $script:lifecycleActions | Should -Not -Contain "create-gitea"

            $marker = $script:upgradeRecoveryMarker
            $marker.schemaVersion | Should -Be 3
            $marker.operationId | Should -BeExactly $script:upgradeMarkerOperationId
            $marker.backupId | Should -BeExactly $script:upgradeMarkerBackupId
            $script:upgradeTerminalRecord.operationKind | Should -BeExactly "upgrade"
            $script:upgradeTerminalRecord.result | Should -BeExactly "interrupted-upgrade-prepared"
            $script:upgradeTerminalRecord.errorSummary | Should -Match "simulated-stop-failure"
            $script:upgradeTerminalRecord.operationId | Should -BeExactly $marker.operationId
            $script:upgradeTerminalRecord.backupId | Should -BeExactly $marker.backupId
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

Describe "Gitea recovery marker reconciliation" {
    InModuleScope gitea-lifecycle {
        BeforeEach {
            $script:reconcileBackupId = "20261108T053419Z-a5737137148a41a9bc45d6f7a78485df"
            $script:reconcileGiteaId = "a" * 64
            $script:reconcilePostgresId = "b" * 64
            $script:reconcileRunnerId = "c" * 64
            $script:reconcileActions = [System.Collections.Generic.List[string]]::new()
            $script:reconcileRecord = $null
            $script:reconcileRecordWriteCount = 0
            $script:reconcileClearArguments = $null
            $script:reconcileContext = @{
                RepoRoot = "C:\isolated-repo"
                GiteaContainerName = "agent-sdlc-gitea"
                GiteaPostgresContainerName = "agent-sdlc-gitea-db"
                GiteaRunnerContainerName = "agent-sdlc-gitea-runner"
                GiteaNetworkName = "agent-sdlc-gitea-network"
                GiteaDataDir = "C:\isolated-repo\.agent-sdlc\dev-env\gitea\data"
                GiteaConfigDir = (Join-Path (Get-PSDrive -Name TestDrive).Root "reconcile-config")
                GiteaPostgresDataDir = "C:\isolated-repo\.agent-sdlc\dev-env\gitea\postgres-data"
                PortBindAddress = "127.0.0.1"
                GiteaHttpPort = 43000
                GiteaSshPort = 43022
                GiteaPostgresHostPort = 43001
                GiteaPostgresDbName = "gitea"
                GiteaPostgresUser = "gitea"
                BackupRoot = "C:\isolated-backups"
            }
            New-Item -ItemType Directory -Path $script:reconcileContext.GiteaConfigDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:reconcileContext.GiteaConfigDir "app.ini"), "[storage]`r`nSTORAGE_TYPE = local`r`n", [System.Text.UTF8Encoding]::new($false))
            $script:reconcileMarker = [pscustomobject]@{
                schemaVersion = 1
                operationKind = "upgrade"
                backupId = $script:reconcileBackupId
            }
            $script:reconcileRuntime = [pscustomobject]@{
                containerName = "agent-sdlc-gitea"
                containerId = $script:reconcileGiteaId
                originalImageReference = "docker.gitea.com/gitea:1.26.4-rootless"
                imageReference = "docker.gitea.com/gitea@sha256:$('d' * 64)"
                imageId = "sha256:$('e' * 64)"
                sourceVersion = "1.26.4"
                networkMode = "agent-sdlc-gitea-network"
                mounts = @(
                    [pscustomobject]@{ type = "bind"; source = $script:reconcileContext.GiteaDataDir; destination = "/var/lib/gitea" }
                    [pscustomobject]@{ type = "bind"; source = $script:reconcileContext.GiteaConfigDir; destination = "/etc/gitea" }
                )
                ports = @(
                    [pscustomobject]@{ containerPort = "3000/tcp"; hostIp = "127.0.0.1"; hostPort = "43000" }
                    [pscustomobject]@{ containerPort = "2222/tcp"; hostIp = "127.0.0.1"; hostPort = "43022" }
                )
            }
            $script:reconcileBackup = [pscustomobject]@{
                Path = "C:\isolated-backups\$($script:reconcileBackupId)"
                Manifest = [pscustomobject]@{
                    schemaVersion = 1
                    kind = "upgrade"
                    sourceVersion = "1.26.4"
                    sourceImage = $script:reconcileRuntime.originalImageReference
                    sourceImageDigest = $script:reconcileRuntime.imageReference
                    runnerWasRunning = $true
                }
            }
            $script:reconcileGitea = [pscustomobject]@{
                Id = $script:reconcileGiteaId
                Name = "/agent-sdlc-gitea"
                Image = $script:reconcileRuntime.imageId
                Args = @()
                Config = [pscustomobject]@{ Image = $script:reconcileRuntime.originalImageReference; Env = @(); Cmd = @() }
                State = [pscustomobject]@{ Status = "running" }
            }
            $script:reconcilePostgres = [pscustomobject]@{
                Id = $script:reconcilePostgresId
                State = [pscustomobject]@{ Status = "running" }
            }
            $script:reconcileRunner = [pscustomobject]@{
                Id = $script:reconcileRunnerId
                State = [pscustomobject]@{ Status = "running" }
            }

            Mock Assert-NativeWindowsHost {}
            Mock Assert-DockerDesktopReady { return @{ id = "isolated-test-engine" } }
            Mock Get-GiteaLifecycleRecoveryMarker { return $script:reconcileMarker }
            Mock Get-GiteaBackupById { return $script:reconcileBackup }
            Mock Test-LongPath {
                param($Path, $PathType)
                if ($script:reconcileRecord -and [string]$PathType -ceq "Leaf" -and
                    [string]$Path -ceq (Get-GiteaOperationRecordPath -Context $script:reconcileContext -OperationId ([string]$script:reconcileRecord.operationId))) {
                    return $true
                }
                if ([string]$Path -ceq (Join-Path $script:reconcileContext.BackupRoot $script:reconcileBackupId) -and [string]$PathType -ceq "Container") { return $true }
                if ($PathType) { return Test-Path -LiteralPath $Path -PathType $PathType }
                return Test-Path -LiteralPath $Path
            }
            Mock Test-GiteaBackupIntegrity { return [pscustomobject]@{ IsValid = $true; Manifest = $script:reconcileBackup.Manifest } }
            Mock Assert-GiteaContainerIdentity { return $script:reconcileGitea }
            Mock Assert-PostgresContainerIdentity { return $script:reconcilePostgres }
            Mock Get-GiteaRunnerInfo { return $script:reconcileRunner }
            Mock Read-LongPathText {
                param($Path)
                if ($script:reconcileRecord -and
                    [string]$Path -ceq (Get-GiteaOperationRecordPath -Context $script:reconcileContext -OperationId ([string]$script:reconcileRecord.operationId))) {
                    return (ConvertTo-Json -InputObject $script:reconcileRecord -Depth 100 -Compress)
                }
                if ([string]$Path -like "*gitea-runtime.json") {
                    return ($script:reconcileRuntime | ConvertTo-Json -Depth 20)
                }
                return (@{
                    schemaVersion = 1
                    containerName = "agent-sdlc-gitea-db"
                    containerId = $script:reconcilePostgresId
                    originalImageReference = "postgres:16"
                    imageId = "sha256:$('f' * 64)"
                    networkMode = "agent-sdlc-gitea-network"
                    networkAliases = @("db")
                    databaseName = "gitea"
                    databaseUser = "gitea"
                    ports = @(@{ containerPort = "5432/tcp"; hostIp = "127.0.0.1"; hostPort = "43001" })
                    mounts = @(@{ type = "bind"; source = "C:\isolated-repo\.agent-sdlc\dev-env\gitea\postgres-data"; destination = "/var/lib/postgresql/data"; readWrite = $true })
                } | ConvertTo-Json -Depth 10)
            }
            Mock Assert-PostgresRestoreCompatibility { $script:reconcileActions.Add("validate-postgres-topology") }
            Mock Assert-GiteaDatabaseTarget { $script:reconcileActions.Add("validate-database-target") }
            Mock Assert-GiteaApiVersion { $script:reconcileActions.Add("validate-api-version") }
            Mock Assert-GiteaBootstrapImagePin {}
            Mock Confirm-GiteaLifecycleOperation { $script:reconcileActions.Add("confirm-with-full-container-ids") }
            Mock New-GiteaOperationRecord {
                param($Context, $Record)
                $script:reconcileActions.Add("write-operation-record")
                $script:reconcileRecordWriteCount += 1
                $script:reconcileRecord = ConvertTo-Json -InputObject $Record -Depth 100 -Compress | ConvertFrom-Json
                return $script:reconcileRecord
            }
            Mock Clear-GiteaLifecycleRecoveryMarker {
                param($Context, $OperationId, $ExpectedLegacySchemaVersion, $ExpectedLegacyOperationKind, $ExpectedLegacyBackupId, $ExpectedLegacyRecoveryMode, $ExpectedReconciliationRecord)
                $script:reconcileActions.Add("clear-recovery-marker")
                $script:reconcileClearArguments = @{
                    OperationId = $OperationId
                    ExpectedLegacySchemaVersion = $ExpectedLegacySchemaVersion
                    ExpectedLegacyOperationKind = $ExpectedLegacyOperationKind
                    ExpectedLegacyBackupId = $ExpectedLegacyBackupId
                    ExpectedLegacyRecoveryMode = $ExpectedLegacyRecoveryMode
                    ExpectedReconciliationRecord = $ExpectedReconciliationRecord
                }
            }
        }

        It "records explicit unchanged-container confirmation before clearing a legacy marker without restoring data" {
            $script:reconcileMarker.PSObject.Properties.Name | Should -Not -Contain "runnerState"
            $script:reconcileBackup.Manifest.runnerWasRunning | Should -BeTrue

            Invoke-GiteaLifecycle -Action reconcile-recovery -Context $script:reconcileContext -BackupId $script:reconcileBackupId -ExpectedGiteaContainerId $script:reconcileGiteaId -ExpectedPostgresContainerId $script:reconcilePostgresId -ExpectedRunnerContainerId $script:reconcileRunnerId

            $script:reconcileActions | Should -Contain "confirm-with-full-container-ids"
            $script:reconcileActions.IndexOf("write-operation-record") | Should -BeLessThan $script:reconcileActions.IndexOf("clear-recovery-marker")
            $script:reconcileRecord.result | Should -Be "reconciled-original-source-without-restore"
            $script:reconcileRecord.databaseRestorePerformed | Should -BeFalse
            $script:reconcileRecord.markerSchemaVersion | Should -Be 1
            $script:reconcileRecord.giteaContainerId | Should -Be $script:reconcileGiteaId
            $script:reconcileRecord.operatorAttestation | Should -Match "DATABASE VERIFIED"
            $script:reconcileRecord.legacyImageReferenceReconciled | Should -BeFalse
        }

        It "keeps legacy Runner-state validation fail-closed using the verified backup Manifest" {
            $script:reconcileMarker.PSObject.Properties.Name | Should -Not -Contain "runnerState"
            $script:reconcileBackup.Manifest.runnerWasRunning | Should -BeTrue
            $script:reconcileRunner.State.Status = "exited"

            { Invoke-GiteaLifecycle -Action reconcile-recovery -Context $script:reconcileContext -BackupId $script:reconcileBackupId -ExpectedGiteaContainerId $script:reconcileGiteaId -ExpectedPostgresContainerId $script:reconcilePostgresId -ExpectedRunnerContainerId $script:reconcileRunnerId } | Should -Throw "*shared Runner state differs from the captured upgrade source*"

            $script:reconcileActions | Should -Not -Contain "confirm-with-full-container-ids"
            $script:reconcileActions | Should -Not -Contain "write-operation-record"
            $script:reconcileActions | Should -Not -Contain "clear-recovery-marker"
        }

        It "derives a stable schema-2 reconciliation identity without adding an Operation ID to the legacy Marker" {
            $script:reconcileMarker.schemaVersion = 2

            Invoke-GiteaLifecycle -Action reconcile-recovery -Context $script:reconcileContext -BackupId $script:reconcileBackupId -ExpectedGiteaContainerId $script:reconcileGiteaId -ExpectedPostgresContainerId $script:reconcilePostgresId -ExpectedRunnerContainerId $script:reconcileRunnerId

            $script:reconcileMarker.PSObject.Properties.Name | Should -Not -Contain "operationId"
            $script:reconcileRecord.markerSchemaVersion | Should -Be 2
            $script:reconcileRecord.operationId | Should -BeExactly "2ac408808019502a2f5293d41af7b59b"
            $script:reconcileClearArguments.OperationId | Should -BeNullOrEmpty
            $script:reconcileClearArguments.ExpectedLegacySchemaVersion | Should -Be 2
        }

        It "replays the same schema-1 reconciliation record and fails closed when its evidence conflicts" {
            Invoke-GiteaLifecycle -Action reconcile-recovery -Context $script:reconcileContext -BackupId $script:reconcileBackupId -ExpectedGiteaContainerId $script:reconcileGiteaId -ExpectedPostgresContainerId $script:reconcilePostgresId -ExpectedRunnerContainerId $script:reconcileRunnerId
            $script:reconcileRecord.operationId | Should -BeExactly "b92dd52df319a08fd98c6cba181a75e0"
            $script:reconcileRecordWriteCount | Should -Be 1

            $script:reconcileActions.Clear()
            Invoke-GiteaLifecycle -Action reconcile-recovery -Context $script:reconcileContext -BackupId $script:reconcileBackupId -ExpectedGiteaContainerId $script:reconcileGiteaId -ExpectedPostgresContainerId $script:reconcilePostgresId -ExpectedRunnerContainerId $script:reconcileRunnerId
            $script:reconcileActions | Should -Not -Contain "write-operation-record"
            $script:reconcileActions | Should -Contain "clear-recovery-marker"
            $script:reconcileRecordWriteCount | Should -Be 1

            $script:reconcileRecord.operatorAttestation = "conflicting evidence"
            $script:reconcileActions.Clear()
            {
                Invoke-GiteaLifecycle -Action reconcile-recovery -Context $script:reconcileContext -BackupId $script:reconcileBackupId -ExpectedGiteaContainerId $script:reconcileGiteaId -ExpectedPostgresContainerId $script:reconcilePostgresId -ExpectedRunnerContainerId $script:reconcileRunnerId
            } | Should -Throw "*different evidence*"
            $script:reconcileActions | Should -Not -Contain "write-operation-record"
            $script:reconcileActions | Should -Not -Contain "clear-recovery-marker"
            $script:reconcileRecordWriteCount | Should -Be 1
        }

        It "keeps schema-3 reconciliation identity tied to the immutable Marker Operation ID" {
            $markerOperationId = "1" * 32
            $script:reconcileMarker = [pscustomobject]@{
                schemaVersion = 3
                operationId = $markerOperationId
                operationKind = "upgrade"
                phase = "backup-verified"
                backupId = $script:reconcileBackupId
                diagnosticBackupId = $null
                revision = 1
                createdAt = "2026-11-10T00:00:00.0000000Z"
                updatedAt = "2026-11-10T00:00:00.0000000Z"
                lastCompletedStage = "backup-verified"
                nextAction = "rename-source-container"
                giteaContainerId = $script:reconcileGiteaId
                targetContainerId = $null
                postgresContainerId = $script:reconcilePostgresId
                runnerContainerId = $script:reconcileRunnerId
                sourceImageId = $script:reconcileRuntime.imageId
                sourceImageReference = $script:reconcileRuntime.imageReference
                sourceOriginalImageReference = $script:reconcileRuntime.originalImageReference
                sourceVersion = $script:reconcileRuntime.sourceVersion
                targetImageDigest = "docker.gitea.com/gitea@sha256:$('c' * 64)"
                targetVersion = "1.27.3"
                giteaState = "running"
                postgresState = "running"
                runnerState = "running"
                supersedesOperationId = $null
                priorDiagnosticBackupIds = @()
            }
            Mock Test-GiteaTerminalOperationRecord { return $true }

            Invoke-GiteaLifecycle -Action reconcile-recovery -Context $script:reconcileContext -BackupId $script:reconcileBackupId -ExpectedGiteaContainerId $script:reconcileGiteaId -ExpectedPostgresContainerId $script:reconcilePostgresId -ExpectedRunnerContainerId $script:reconcileRunnerId

            $script:reconcileRecord.operationId | Should -BeExactly "2a88c5321753b7b36f58a628f9143ee0"
            $script:reconcileRecord.markerSchemaVersion | Should -Be 3
            $script:reconcileClearArguments.OperationId | Should -BeExactly $markerOperationId
        }

        It "reconciles the exact schema-1 incident reference through the real runtime topology validator without using it as an image" {
            $sharedDigest = "d" * 64
            $legacyReference = @(
                "docker.gitea.com/gitea@sha256:$sharedDigest"
                "docker.gitea.com/gitea@sha256:$sharedDigest"
                "gitea/gitea@sha256:$sharedDigest"
            ) -join " "
            $script:reconcileRuntime.imageReference = $legacyReference
            $script:reconcileBackup.Manifest.sourceImageDigest = $legacyReference

            $validatedRuntime = Get-GiteaRecoveryRuntime -BackupPath $script:reconcileBackup.Path -Manifest $script:reconcileBackup.Manifest
            { Assert-BackupRuntimeMatchesContext -Context $script:reconcileContext -Runtime $validatedRuntime -AllowValidatedLegacyImageReference } | Should -Not -Throw
            { Assert-BackupRuntimeMatchesContext -Context $script:reconcileContext -Runtime $validatedRuntime } | Should -Throw "*valid immutable*"

            Invoke-GiteaLifecycle -Action reconcile-recovery -Context $script:reconcileContext -BackupId $script:reconcileBackupId -ExpectedGiteaContainerId $script:reconcileGiteaId -ExpectedPostgresContainerId $script:reconcilePostgresId -ExpectedRunnerContainerId $script:reconcileRunnerId

            $script:reconcileActions.IndexOf("write-operation-record") | Should -BeLessThan $script:reconcileActions.IndexOf("clear-recovery-marker")
            $script:reconcileRecord.legacyImageReferenceReconciled | Should -BeTrue
            $script:reconcileRecord.legacyRepoDigestCount | Should -Be 3
            $script:reconcileRecord.sourceImageDigest | Should -BeNullOrEmpty
            $script:reconcileRecord.sourceImageId | Should -Be $script:reconcileRuntime.imageId
            $script:reconcileRecord.databaseRestorePerformed | Should -BeFalse
        }

        It "rejects other concatenated digest counts and leaves the Recovery Marker intact" {
            $sharedDigest = "d" * 64
            $legacyReference = @(
                "docker.gitea.com/gitea@sha256:$sharedDigest"
                "docker.gitea.com/gitea@sha256:$sharedDigest"
            ) -join " "
            $script:reconcileRuntime.imageReference = $legacyReference
            $script:reconcileBackup.Manifest.sourceImageDigest = $legacyReference

            { Invoke-GiteaLifecycle -Action reconcile-recovery -Context $script:reconcileContext -BackupId $script:reconcileBackupId -ExpectedGiteaContainerId $script:reconcileGiteaId -ExpectedPostgresContainerId $script:reconcilePostgresId -ExpectedRunnerContainerId $script:reconcileRunnerId } | Should -Throw "*narrowly supported schema-1 recovery format*"

            $script:reconcileActions | Should -Not -Contain "write-operation-record"
            $script:reconcileActions | Should -Not -Contain "clear-recovery-marker"
        }

        It "rejects the incident repositories when their SHA values do not match" {
            $legacyReference = @(
                "docker.gitea.com/gitea@sha256:$('d' * 64)"
                "docker.gitea.com/gitea@sha256:$('d' * 64)"
                "gitea/gitea@sha256:$('e' * 64)"
            ) -join " "
            $script:reconcileRuntime.imageReference = $legacyReference
            $script:reconcileBackup.Manifest.sourceImageDigest = $legacyReference

            { Invoke-GiteaLifecycle -Action reconcile-recovery -Context $script:reconcileContext -BackupId $script:reconcileBackupId -ExpectedGiteaContainerId $script:reconcileGiteaId -ExpectedPostgresContainerId $script:reconcilePostgresId -ExpectedRunnerContainerId $script:reconcileRunnerId } | Should -Throw "*narrowly supported schema-1 recovery format*"

            $script:reconcileActions | Should -Not -Contain "write-operation-record"
            $script:reconcileActions | Should -Not -Contain "clear-recovery-marker"
        }

        It "retains the marker when any live container ID differs from the operator's verified original ID" {
            $script:reconcileGitea.Id = "f" * 64

            { Invoke-GiteaLifecycle -Action reconcile-recovery -Context $script:reconcileContext -BackupId $script:reconcileBackupId -ExpectedGiteaContainerId $script:reconcileGiteaId -ExpectedPostgresContainerId $script:reconcilePostgresId -ExpectedRunnerContainerId $script:reconcileRunnerId } | Should -Throw "*container ID*"

            $script:reconcileActions | Should -Not -Contain "confirm-with-full-container-ids"
            $script:reconcileActions | Should -Not -Contain "write-operation-record"
            $script:reconcileActions | Should -Not -Contain "clear-recovery-marker"
        }

        It "forbids original-source closeout once target startup may have begun" {
            $script:reconcileMarker = [pscustomobject]@{
                schemaVersion = 3
                operationId = "d" * 32
                operationKind = "upgrade"
                phase = "target-start-attempted"
                backupId = $script:reconcileBackupId
                diagnosticBackupId = $null
                revision = 1
                createdAt = "2026-11-10T00:00:00.0000000Z"
                updatedAt = "2026-11-10T00:00:00.0000000Z"
                lastCompletedStage = "source-container-renamed"
                nextAction = "verify-source-or-restore"
                giteaContainerId = $script:reconcileGiteaId
                targetContainerId = $null
                postgresContainerId = $script:reconcilePostgresId
                runnerContainerId = $script:reconcileRunnerId
                sourceImageId = $script:reconcileRuntime.imageId
                sourceImageReference = $script:reconcileRuntime.imageReference
                sourceOriginalImageReference = $script:reconcileRuntime.originalImageReference
                sourceVersion = $script:reconcileRuntime.sourceVersion
                targetImageDigest = "docker.gitea.com/gitea@sha256:$('c' * 64)"
                targetVersion = "1.27.3"
                giteaState = "running"
                postgresState = "running"
                runnerState = "running"
                supersedesOperationId = $null
                priorDiagnosticBackupIds = @()
            }

            { Invoke-GiteaLifecycle -Action reconcile-recovery -Context $script:reconcileContext -BackupId $script:reconcileBackupId -ExpectedGiteaContainerId $script:reconcileGiteaId -ExpectedPostgresContainerId $script:reconcilePostgresId -ExpectedRunnerContainerId $script:reconcileRunnerId } | Should -Throw "*target create/start stage may have begun*"

            $script:reconcileActions | Should -Not -Contain "validate-api-version"
            $script:reconcileActions | Should -Not -Contain "write-operation-record"
            $script:reconcileActions | Should -Not -Contain "clear-recovery-marker"
        }

        It "does not reconcile markers created by a restore operation" {
            $script:reconcileMarker.operationKind = "restore"

            { Invoke-GiteaLifecycle -Action reconcile-recovery -Context $script:reconcileContext -BackupId $script:reconcileBackupId -ExpectedGiteaContainerId $script:reconcileGiteaId -ExpectedPostgresContainerId $script:reconcilePostgresId -ExpectedRunnerContainerId $script:reconcileRunnerId } | Should -Throw "*does not match the active restore marker*"

            $script:reconcileActions | Should -Not -Contain "clear-recovery-marker"
        }
    }
}

Describe "Gitea Restore runtime image reference validation" {
    InModuleScope gitea-lifecycle {
        It "rejects the incident-shaped concatenated reference through the real strict backup runtime reader" {
            $sharedDigest = "d" * 64
            $script:restoreStrictRuntime = [pscustomobject]@{
                imageReference = @(
                    "docker.gitea.com/gitea@sha256:$sharedDigest"
                    "docker.gitea.com/gitea@sha256:$sharedDigest"
                    "gitea/gitea@sha256:$sharedDigest"
                ) -join " "
                mounts = @([pscustomobject]@{ destination = "/var/lib/gitea" })
                ports = @([pscustomobject]@{ containerPort = "3000/tcp" })
            }
            Mock Read-LongPathText { return ($script:restoreStrictRuntime | ConvertTo-Json -Depth 10) }

            { Get-BackupRuntime -BackupPath "C:\isolated-backups\20261108T053419Z-a5737137148a41a9bc45d6f7a78485df" -Manifest ([pscustomobject]@{ schemaVersion = 1 }) } | Should -Throw "*valid immutable*"
        }
    }
}

Describe "Gitea backup artifact schema validation" {
    InModuleScope gitea-lifecycle {
        It "rejects an unknown Gitea runtime snapshot schema" {
            Mock Read-LongPathText { return (@{ schemaVersion = 2; imageReference = "sha256:$('a' * 64)"; mounts = @(@{ destination = "/var/lib/gitea" }); ports = @(@{ containerPort = "3000/tcp" }) } | ConvertTo-Json -Depth 10) }

            { Get-BackupRuntime -BackupPath "C:\isolated-backups\fixture" -Manifest ([pscustomobject]@{ schemaVersion = 2 }) } | Should -Throw "*unsupported schemaVersion*"
        }

        It "rejects unknown Restore Context and PostgreSQL topology schemas" {
            Mock Read-LongPathText { return (@{ schemaVersion = 7 } | ConvertTo-Json -Depth 10) }

            { Read-GiteaRestoreContext -BackupPath "C:\isolated-backups\fixture" -Manifest ([pscustomobject]@{ schemaVersion = 2 }) } | Should -Throw "*unsupported schemaVersion*"
            { Get-GiteaPostgresTopology -BackupPath "C:\isolated-backups\fixture" -Manifest ([pscustomobject]@{ schemaVersion = 2 }) } | Should -Throw "*unreadable or incomplete*"
        }

        It "rejects a replacement PostgreSQL container even when its name and topology match" {
            $postgresId = "a" * 64
            $container = @'
{"Id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","Name":"/agent-sdlc-gitea-db","Image":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","State":{"Status":"running"},"Config":{"Image":"postgres:16","Env":["POSTGRES_DB=gitea","POSTGRES_USER=gitea"]},"HostConfig":{"PortBindings":{"5432/tcp":[{"HostIp":"127.0.0.1","HostPort":"45432"}]},"NetworkMode":"agent-sdlc-gitea-network"},"NetworkSettings":{"Networks":{"agent-sdlc-gitea-network":{"Aliases":["db"]}}},"Mounts":[{"Type":"bind","Source":"C:\\isolated\\postgres-data","Destination":"/var/lib/postgresql/data","RW":true}]}
'@ | ConvertFrom-Json
            # The compatibility reader consumes ConvertFrom-Json PSCustomObjects from disk.
            # Round-trip the producer result so the test exercises that same property model.
            $topology = Get-PostgresTopologySnapshot -Container $container | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $topology.containerId = "c" * 64
            $context = @{ GiteaPostgresContainerName = "agent-sdlc-gitea-db"; GiteaPostgresDbName = "gitea"; GiteaPostgresUser = "gitea" }

            { Assert-PostgresRestoreCompatibility -BackupTopology $topology -CurrentContainer $container -Context $context -ManifestSchemaVersion 2 } | Should -Throw "*full container ID*"
            $topology.containerId = $postgresId
            $topology.databaseName = "other"
            { Assert-PostgresRestoreCompatibility -BackupTopology $topology -CurrentContainer $container -Context $context -ManifestSchemaVersion 2 } | Should -Throw "*full container ID or database identity*"
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
            $script:restoreRecoveryMarker = $null
            $script:restoreTerminalRecord = $null
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
            $giteaConfigPath = Join-Path $script:restorePayloadPath "payload/gitea-config"
            New-Item -ItemType Directory -Path $privatePath -Force | Out-Null
            New-Item -ItemType Directory -Path $giteaConfigPath -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $giteaConfigPath "app.ini"), "[storage]`r`nSTORAGE_TYPE = local`r`n", [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $privatePath "postgres-topology.json"), (@{
                schemaVersion = 1
                containerName = "agent-sdlc-gitea-db"
                containerId = "b" * 64
                originalImageReference = "postgres:16"
                imageId = "sha256:$('f' * 64)"
                networkMode = "agent-sdlc-gitea-network"
                networkAliases = @("db")
                databaseName = "gitea"
                databaseUser = "gitea"
                ports = @(@{ containerPort = "5432/tcp"; hostIp = "127.0.0.1"; hostPort = "45432" })
                mounts = @(@{ type = "bind"; source = "C:\isolated-repo\.agent-sdlc\dev-env\gitea\postgres-data"; destination = "/var/lib/postgresql/data"; readWrite = $true })
            } | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
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
                Manifest = [pscustomobject]@{ schemaVersion = 2; runnerWasRunning = $false }
            }

            Mock Assert-NativeWindowsHost {}
            Mock Assert-DockerDesktopReady { return @{ id = "isolated-test-engine" } }
            Mock Get-BackupRuntime { return $script:restoreRuntime }
            Mock Assert-BackupRuntimeMatchesContext {}
            Mock Read-GiteaRestoreContext { return [pscustomobject]@{ databaseName = "gitea"; databaseUser = "gitea"; configSource = "template" } }
            Mock Assert-ConfigRestoreCompatibility {}
            Mock Assert-PostgresContainerIdentity {
                return [pscustomobject]@{
                    Id = "b" * 64
                    Name = "/agent-sdlc-gitea-db"
                    Image = "sha256:$('f' * 64)"
                    State = [pscustomobject]@{ Status = "running" }
                    Config = [pscustomobject]@{ Image = "postgres:16"; Env = @("POSTGRES_DB=gitea", "POSTGRES_USER=gitea", "POSTGRES_PASSWORD=fixture-secret") }
                }
            }
            Mock Assert-PostgresRestoreCompatibility {}
            Mock Assert-GiteaDatabaseTarget {}
            Mock Assert-GiteaContainerIdentity { return $null }
            Mock Get-GiteaRunnerInfo { return [pscustomobject]@{ Id = "c" * 64; State = [pscustomobject]@{ Status = "exited" } } }
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
            Mock Set-GiteaLifecycleRecoveryMarker {
                param(
                    $Context, $OperationKind, $BackupId, $DiagnosticBackupId, $Phase, $OperationId,
                    $NextAction, $LastCompletedStage, $GiteaContainerId, $TargetContainerId,
                    $PostgresContainerId, $RunnerContainerId, $SourceImageId, $SourceImageReference,
                    $SourceOriginalImageReference, $SourceVersion, $TargetImageDigest, $TargetVersion,
                    $GiteaState, $PostgresState, $RunnerState, $SupersedesOperationId,
                    $PriorDiagnosticBackupIds, $ReplaceExisting
                )
                $createdAt = [DateTime]::UtcNow.ToString("o")
                $script:restoreRecoveryMarker = [pscustomobject]@{
                    schemaVersion = 3
                    operationId = $OperationId
                    operationKind = $OperationKind
                    phase = $Phase
                    backupId = $BackupId
                    diagnosticBackupId = $DiagnosticBackupId
                    revision = 1
                    createdAt = $createdAt
                    updatedAt = $createdAt
                    lastCompletedStage = $LastCompletedStage
                    nextAction = $NextAction
                    giteaContainerId = $GiteaContainerId
                    targetContainerId = $TargetContainerId
                    postgresContainerId = $PostgresContainerId
                    runnerContainerId = $RunnerContainerId
                    sourceImageId = $SourceImageId
                    sourceImageReference = $SourceImageReference
                    sourceOriginalImageReference = $SourceOriginalImageReference
                    sourceVersion = $SourceVersion
                    targetImageDigest = $TargetImageDigest
                    targetVersion = $TargetVersion
                    giteaState = $GiteaState
                    postgresState = $PostgresState
                    runnerState = $RunnerState
                    supersedesOperationId = $SupersedesOperationId
                    priorDiagnosticBackupIds = @($PriorDiagnosticBackupIds)
                }
                $script:restoreActions.Add("set-recovery-marker")
            }
            Mock Get-GiteaLifecycleRecoveryMarker { return $script:restoreRecoveryMarker }
            Mock Update-GiteaLifecycleRecoveryMarkerPhase {
                param($Context, $BackupId, $Phase, $NextAction, $LastCompletedStage, $DiagnosticBackupId, $GiteaContainerId, $TargetContainerId, $RunnerState, $OperationId)
                if (-not $script:restoreRecoveryMarker -or [string]$script:restoreRecoveryMarker.operationId -cne [string]$OperationId -or [string]$script:restoreRecoveryMarker.backupId -cne [string]$BackupId) {
                    throw "The persisted Recovery Marker operation identity changed; refusing to advance another attempt."
                }
                $script:restoreRecoveryMarker.phase = $Phase
                if ($NextAction) { $script:restoreRecoveryMarker.nextAction = $NextAction }
                if ($LastCompletedStage) { $script:restoreRecoveryMarker.lastCompletedStage = $LastCompletedStage }
                if ($DiagnosticBackupId) { $script:restoreRecoveryMarker.diagnosticBackupId = $DiagnosticBackupId }
                if ($GiteaContainerId) { $script:restoreRecoveryMarker.giteaContainerId = $GiteaContainerId }
                if ($TargetContainerId) { $script:restoreRecoveryMarker.targetContainerId = $TargetContainerId }
                if ($RunnerState) { $script:restoreRecoveryMarker.runnerState = $RunnerState }
                $script:restoreRecoveryMarker.revision = [int]$script:restoreRecoveryMarker.revision + 1
                $script:restoreRecoveryMarker.updatedAt = [DateTime]::UtcNow.ToString("o")
                $script:restoreActions.Add("marker-next:$NextAction")
            }
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
            Mock New-GiteaOperationRecord {
                param($Context, $Record)
                $script:restoreTerminalRecord = $Record
                $script:restoreActions.Add("operation-record")
            }
            Mock Clear-GiteaLifecycleRecoveryMarker {
                param($Context, $OperationId)
                if (-not $script:restoreRecoveryMarker -or [string]$script:restoreRecoveryMarker.operationId -cne [string]$OperationId -or
                    -not $script:restoreTerminalRecord -or [string]$script:restoreTerminalRecord.operationId -cne [string]$OperationId) {
                    throw "A matching terminal Operation Record is required before clearing the Recovery Marker."
                }
                $script:restoreActions.Add("clear-recovery-marker")
                $script:restoreRecoveryMarker = $null
            }
        }

        It "rejects a restore without a valid Backup ID before service or data operations" {
            { Invoke-GiteaLifecycle -Action restore -Context $script:restoreContext -BackupId "bad-id" } | Should -Throw
            $script:restoreActions | Should -BeNullOrEmpty
        }

        It "rejects an external-storage backup before confirmation, Marker creation, or service changes" {
            $backupId = "20261105T000001Z-0123456789abcdef0123456789abcdef"
            [System.IO.File]::WriteAllText((Join-Path $script:restorePayloadPath "payload/gitea-config/app.ini"), "[storage]`r`nSTORAGE_TYPE = minio`r`n", [System.Text.UTF8Encoding]::new($false))
            Mock Get-GiteaBackupById { return $script:selectedBackup }

            { Invoke-GiteaLifecycle -Action restore -Context $script:restoreContext -BackupId $backupId } | Should -Throw "*outside the backup payload*"

            $script:restoreActions | Should -BeNullOrEmpty
        }

        It "rejects a multi-digest runtime reference before stopping services or creating a diagnostic backup" {
            $backupId = "20261105T000001Z-0123456789abcdef0123456789abcdef"
            $sharedDigest = "a" * 64
            $script:restoreRuntime.imageReference = @(
                "docker.gitea.com/gitea@sha256:$sharedDigest"
                "docker.gitea.com/gitea@sha256:$sharedDigest"
                "gitea/gitea@sha256:$sharedDigest"
            ) -join " "
            Mock Get-GiteaBackupById { return $script:selectedBackup }

            { Invoke-GiteaLifecycle -Action restore -Context $script:restoreContext -BackupId $backupId } | Should -Throw

            $script:restoreActions | Should -Not -Contain "stop-runner"
            $script:restoreActions | Should -Not -Contain "docker stop --time 60 agent-sdlc-gitea"
            $script:restoreActions | Should -Not -Contain "backup-pre-restore-diagnostic"
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

        It "writes the Recovery Marker before stopping services or creating diagnostic data" {
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

            $script:restoreActions.IndexOf("set-recovery-marker") | Should -BeLessThan $script:restoreActions.IndexOf("backup-pre-restore-diagnostic")
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
            $script:restoreActions | Should -Contain "operation-record"
            $script:restoreActions | Should -Not -Contain "clear-recovery-marker"
            $script:restoreActions | Should -Not -Contain "create-gitea:$($script:restoreRuntime.imageReference)"
            $script:restoreRecoveryMarker.schemaVersion | Should -Be 3
            $script:restoreRecoveryMarker.operationKind | Should -BeExactly "restore"
            $script:restoreRecoveryMarker.operationId | Should -Match "^[0-9a-f]{32}$"
            $script:restoreRecoveryMarker.backupId | Should -BeExactly "20261105T000000Z-0123456789abcdef0123456789abcdef"
            $script:restoreRecoveryMarker.phase | Should -BeExactly "restore-applying"
            $script:restoreRecoveryMarker.nextAction | Should -BeExactly "restore-postgres"
            $script:restoreTerminalRecord.operationId | Should -BeExactly $script:restoreRecoveryMarker.operationId
            $script:restoreTerminalRecord.operationKind | Should -BeExactly "restore"
            $script:restoreTerminalRecord.result | Should -BeExactly "interrupted-restore-applying"
            $script:restoreTerminalRecord.backupId | Should -BeExactly $script:restoreRecoveryMarker.backupId
            $script:restoreTerminalRecord.errorSummary | Should -Match "simulated-postgres-restore-failure"
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

Describe "Gitea backup manifest byte totals" {
    It "returns zero bytes for an empty file-entry list" {
        InModuleScope gitea-lifecycle {
            Measure-BackupFileEntriesSize -Entries @() | Should -Be 0
        }
    }

    It "sums sizeBytes from multiple hashtable file entries" {
        $entries = @(
            @{ path = "payload/first.dump"; sizeBytes = [long]17; sha256 = "a" },
            @{ path = "payload/second.json"; sizeBytes = [long]29; sha256 = "b" },
            @{ path = "payload/third.bin"; sizeBytes = [long]54; sha256 = "c" }
        )

        InModuleScope gitea-lifecycle -Parameters @{ Entries = $entries } {
            param($Entries)
            Measure-BackupFileEntriesSize -Entries $Entries | Should -Be 100
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
            InModuleScope gitea-lifecycle -Parameters @{ Context = $context } {
                param($Context)
                Ensure-BackupRoot -Context $Context | Out-Null
            }
            $initialBackupEntries = @(InModuleScope gitea-lifecycle -Parameters @{ Path = $backupRoot } {
                param($Path)
                Get-LongPathDirectoryEntries -Path $Path
            })
            $initialBackupEntries.Count | Should -Be 0
            $initialRootSecurity = [System.IO.Directory]::GetAccessControl($backupRoot, $sections)
            $initialRootSecurityDescriptor = $initialRootSecurity.GetSecurityDescriptorSddlForm($sections)
            Invoke-GiteaLifecycle -Action backup-list -Context $context

            (Test-Path -LiteralPath $backupRoot -PathType Container) | Should -BeTrue
            $postListEntries = @(InModuleScope gitea-lifecycle -Parameters @{ Path = $backupRoot } {
                param($Path)
                Get-LongPathDirectoryEntries -Path $Path
            })
            $postListEntries.Count | Should -Be 0
            $postListSecurity = [System.IO.Directory]::GetAccessControl($backupRoot, $sections)
            $postListSecurity.GetSecurityDescriptorSddlForm($sections) | Should -BeExactly $initialRootSecurityDescriptor

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
                    sizeBytes = [long]$entries[0].sizeBytes
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
                    (((Get-LongPathItem -Path $resolvedRoot).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) |
                        Should -BeTrue

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

Describe "Gitea isolated Docker fixture cleanup on real NTFS" -Tag "WindowsLongPath" {
    BeforeAll {
        $script:fixtureCleanupModulePath = Join-Path $PSScriptRoot "../../scripts/dev/gitea-lifecycle-e2e-fixture-cleanup.psm1"
        Import-Module $script:fixtureCleanupModulePath -Force -ErrorAction Stop
    }

    It "previews and then removes only the approved marked fixture, including long descendants" {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            Set-ItResult -Skipped -Because "Docker fixture cleanup regression requires Windows NTFS."
            return
        }

        $runId = [Guid]::NewGuid().ToString("N")
        $prefix = "agent-sdlc-life-e2e-$runId"
        $fixtureRoot = Join-Path $env:TEMP $prefix
        $markerPath = Join-Path $fixtureRoot ".agent-sdlc-lifecycle-e2e-owner.json"
        $extendedRoot = "\\?\" + [System.IO.Path]::GetFullPath($fixtureRoot)
        $fixtureRootCreated = $false
        $markerWritten = $false
        $cleanupCompleted = $false

        try {
            [System.IO.Directory]::CreateDirectory($extendedRoot) | Out-Null
            $fixtureRootCreated = $true
            [System.IO.File]::WriteAllText(
                "\\?\" + [System.IO.Path]::GetFullPath($markerPath),
                (@{ runId = $runId; prefix = $prefix } | ConvertTo-Json -Compress),
                [System.Text.UTF8Encoding]::new($false)
            )
            $markerWritten = $true

            $deepPath = $fixtureRoot
            for ($index = 0; $index -lt 6; $index++) {
                $deepPath = Join-Path $deepPath ("segment-{0}-{1}" -f $index, ("x" * 38))
            }
            [System.IO.Directory]::CreateDirectory("\\?\" + [System.IO.Path]::GetFullPath($deepPath)) | Out-Null
            $deepFilePath = Join-Path $deepPath "fixture-payload.txt"
            [System.IO.File]::WriteAllText(
                "\\?\" + [System.IO.Path]::GetFullPath($deepFilePath),
                "owned fixture payload",
                [System.Text.UTF8Encoding]::new($false)
            )
            $deepFilePath.Length | Should -BeGreaterThan 260

            {
                Remove-GiteaLifecycleE2EFixtureDirectory `
                    -RunId $runId `
                    -ExpectedPath (Join-Path $env:TEMP "agent-sdlc-life-e2e-other-$runId") `
                    -WhatIf
            } | Should -Throw "*exact GUID-named direct child*"
            Remove-GiteaLifecycleE2EFixtureDirectory -RunId $runId -ExpectedPath $fixtureRoot -WhatIf | Out-Null
            (([System.IO.File]::GetAttributes($extendedRoot) -band [System.IO.FileAttributes]::Directory) -ne 0) |
                Should -BeTrue
            {
                Remove-GiteaLifecycleE2EFixtureDirectory `
                    -RunId $runId `
                    -ExpectedPath $fixtureRoot `
                    -ApproveRunId "00000000000000000000000000000000" `
                    -Confirm:$false
            } | Should -Throw "*same RunId*"
            $result = Remove-GiteaLifecycleE2EFixtureDirectory `
                -RunId $runId `
                -ExpectedPath $fixtureRoot `
                -ApproveRunId $runId `
                -Confirm:$false

            $result.Removed | Should -BeTrue
            (Test-Path -LiteralPath $fixtureRoot) | Should -BeFalse
            $cleanupCompleted = $true
        }
        finally {
            if ($fixtureRootCreated -and -not $cleanupCompleted -and [System.IO.Directory]::Exists($extendedRoot)) {
                if ($markerWritten) {
                    Remove-GiteaLifecycleE2EFixtureDirectory `
                        -RunId $runId `
                        -ExpectedPath $fixtureRoot `
                        -ApproveRunId $runId `
                        -Confirm:$false | Out-Null
                }
                elseif (@([System.IO.Directory]::EnumerateFileSystemEntries($extendedRoot)).Count -eq 0) {
                    [System.IO.Directory]::Delete($extendedRoot, $false)
                }
            }
        }
    }

    It "refuses a fixture tree with a reparse point and preserves its target" {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            Set-ItResult -Skipped -Because "Docker fixture cleanup regression requires Windows NTFS."
            return
        }

        $runId = [Guid]::NewGuid().ToString("N")
        $targetId = [Guid]::NewGuid().ToString("N")
        $prefix = "agent-sdlc-life-e2e-$runId"
        $fixtureRoot = Join-Path $env:TEMP $prefix
        $extendedRoot = "\\?\" + [System.IO.Path]::GetFullPath($fixtureRoot)
        $markerPath = Join-Path $fixtureRoot ".agent-sdlc-lifecycle-e2e-owner.json"
        $targetRoot = Join-Path $env:TEMP "agent-sdlc-life-e2e-target-$targetId"
        $junctionPath = Join-Path $fixtureRoot "redirected-target"
        $fixtureCreated = $false
        $targetCreated = $false
        $junctionCreated = $false

        try {
            [System.IO.Directory]::CreateDirectory($extendedRoot) | Out-Null
            $fixtureCreated = $true
            [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetFullPath($targetRoot)) | Out-Null
            $targetCreated = $true
            [System.IO.File]::WriteAllText(
                "\\?\" + [System.IO.Path]::GetFullPath($markerPath),
                (@{ runId = $targetId; prefix = $prefix } | ConvertTo-Json -Compress),
                [System.Text.UTF8Encoding]::new($false)
            )
            {
                Remove-GiteaLifecycleE2EFixtureDirectory `
                    -RunId $runId `
                    -ExpectedPath $fixtureRoot `
                    -ApproveRunId $runId `
                    -Confirm:$false
            } | Should -Throw "*ownership marker does not match*"
            [System.IO.Directory]::Exists($extendedRoot) | Should -BeTrue
            [System.IO.File]::WriteAllText(
                "\\?\" + [System.IO.Path]::GetFullPath($markerPath),
                (@{ runId = $runId; prefix = $prefix } | ConvertTo-Json -Compress),
                [System.Text.UTF8Encoding]::new($false)
            )
            try {
                New-Item -ItemType Junction -Path $junctionPath -Target $targetRoot -ErrorAction Stop | Out-Null
                $junctionCreated = $true
            }
            catch {
                Set-ItResult -Skipped -Because "This Windows host could not create the disposable junction used to verify fail-closed cleanup."
                return
            }

            {
                Remove-GiteaLifecycleE2EFixtureDirectory `
                    -RunId $runId `
                    -ExpectedPath $fixtureRoot `
                    -ApproveRunId $runId `
                    -Confirm:$false
            } | Should -Throw "*reparse point*"

            [System.IO.Directory]::Exists($extendedRoot) | Should -BeTrue
            [System.IO.Directory]::Exists("\\?\" + [System.IO.Path]::GetFullPath($targetRoot)) | Should -BeTrue
        }
        finally {
            if ($junctionCreated) {
                [System.IO.Directory]::Delete("\\?\" + [System.IO.Path]::GetFullPath($junctionPath), $false)
            }
            if ($fixtureCreated -and [System.IO.Directory]::Exists($extendedRoot)) {
                [System.IO.File]::WriteAllText(
                    "\\?\" + [System.IO.Path]::GetFullPath($markerPath),
                    (@{ runId = $runId; prefix = $prefix } | ConvertTo-Json -Compress),
                    [System.Text.UTF8Encoding]::new($false)
                )
                Remove-GiteaLifecycleE2EFixtureDirectory `
                    -RunId $runId `
                    -ExpectedPath $fixtureRoot `
                    -ApproveRunId $runId `
                    -Confirm:$false | Out-Null
            }
            if ($targetCreated -and [System.IO.Directory]::Exists("\\?\" + [System.IO.Path]::GetFullPath($targetRoot))) {
                [System.IO.Directory]::Delete("\\?\" + [System.IO.Path]::GetFullPath($targetRoot), $true)
            }
        }
    }
}
