Describe "Gitea lifecycle isolated Docker acceptance" -Tag "DockerE2E" -Skip:($env:AGENT_SDLC_GITEA_DOCKER_E2E -ne "1") {
    BeforeAll {
        if ($env:AGENT_SDLC_GITEA_DOCKER_E2E -ne "1") {
            throw "AGENT_SDLC_GITEA_DOCKER_E2E must remain set to 1 from Pester Discovery through Run."
        }

        . (Join-Path $PSScriptRoot "gitea-lifecycle.DockerE2E.Helpers.ps1")
        try {
            Import-Module (Join-Path $PSScriptRoot "../../scripts/dev/gitea-lifecycle-e2e-fixture-cleanup.psm1") -Force -ErrorAction Stop
            Import-Module (Join-Path $PSScriptRoot "../../scripts/dev/gitea-lifecycle.psm1") -Force -ErrorAction Stop
            $orasCommand = Get-Command oras.exe -ErrorAction Stop
            $script:orasExePath = [string]$orasCommand.Source
            $orasVersionOutput = @(& $script:orasExePath version 2>&1) -join "`n"
            if ($LASTEXITCODE -ne 0 -or $orasVersionOutput -notmatch '(?m)^Version:\s*v?1\.3\.5(?:\+|\s|$)') {
                throw "The isolated Registry E2E requires ORAS CLI 1.3.5 on PATH."
            }
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

        # Consume the exact snapshot produced by the 1.25.5 -> 1.26.4 upgrade,
        # then leave the shared fixture at 1.26.4 for the later adjacent-hop cases.
        InModuleScope gitea-lifecycle -Parameters @{ Context = $context; BackupId = [string]$state.InitialBackupId } {
            param($Context, $BackupId)
            Mock Confirm-GiteaLifecycleOperation {}
            Invoke-GiteaLifecycle -Action restore -Context $Context -BackupId $BackupId
        }
        [string](Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/version") -Method Get).version | Should -Be "1.25.5"
        InModuleScope gitea-lifecycle -Parameters @{ Context = $context } {
            param($Context)
            Mock Confirm-GiteaLifecycleOperation {}
            Invoke-GiteaLifecycle -Action upgrade -Context $Context -GiteaVersion "1.26.4"
        }
        [string](Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/version") -Method Get).version | Should -Be "1.26.4"
    }

    It "pushes and fetches a Git change, dispatches a real host-label Runner job, restarts the Runner, and verifies a second run and logs" {
        $state = Get-GiteaLifecycleE2EState
        $context = $state.Context
        $headers = @{
            Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($state.AdminUsername):$($state.AdminPassword)"))
        }
        $gitPath = (Get-Command git.exe -ErrorAction Stop).Source
        $credentialValue = "Authorization: Basic $($headers.Authorization.Substring(6))"

        function Invoke-E2EGit {
            param([string]$WorkingDirectory, [string[]]$Arguments)
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = $gitPath
            $startInfo.WorkingDirectory = $WorkingDirectory
            $startInfo.UseShellExecute = $false
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $startInfo.CreateNoWindow = $true
            $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $startInfo.Arguments = ConvertTo-GiteaLifecycleE2EArgumentString -Arguments $Arguments
            $startInfo.EnvironmentVariables["GIT_CONFIG_COUNT"] = "1"
            $startInfo.EnvironmentVariables["GIT_CONFIG_KEY_0"] = "http.extraHeader"
            $startInfo.EnvironmentVariables["GIT_CONFIG_VALUE_0"] = $credentialValue
            $startInfo.EnvironmentVariables["GIT_TERMINAL_PROMPT"] = "0"
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $startInfo
            [void]$process.Start()
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            if ($process.ExitCode -ne 0) {
                $safeStderr = [Regex]::Replace($stderr, '(?i)(Authorization:\s*Basic\s+)[A-Za-z0-9+/=]+', '$1[REDACTED]')
                throw "Isolated Git operation failed (exit $($process.ExitCode)): $safeStderr"
            }
            return $stdout.Trim()
        }

        $repo = Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/repos/e2e-admin/lifecycle-e2e-sentinel") -Method Get -Headers $headers
        $branch = [string]$repo.default_branch
        $repoUrl = "http://127.0.0.2:43000/e2e-admin/lifecycle-e2e-sentinel.git"
        $primaryClone = Join-Path $state.TestRoot "git-primary"
        $secondaryClone = Join-Path $state.TestRoot "git-secondary"
        Invoke-E2EGit -WorkingDirectory $state.TestRoot -Arguments @("clone", "--quiet", "--branch", $branch, $repoUrl, $primaryClone) | Out-Null

        $workflowDirectory = Join-Path $primaryClone ".gitea\workflows"
        New-Item -ItemType Directory -Path $workflowDirectory -Force | Out-Null
        $workflowPath = Join-Path $workflowDirectory "lifecycle-canary.yml"
        $workflow = @'
name: lifecycle-canary
on:
  workflow_dispatch:
    inputs:
      runNonce:
        required: true
        type: string
jobs:
  host-label-canary:
    runs-on: agent-sdlc-host
    steps:
      - name: Print isolated canary nonce
        run: echo "LIFECYCLE_CANARY=${{ inputs.runNonce }}"
'@
        [System.IO.File]::WriteAllText($workflowPath, $workflow, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText((Join-Path $primaryClone "git-push-sentinel.txt"), "pushed-by-real-git`n", [System.Text.UTF8Encoding]::new($false))
        Invoke-E2EGit -WorkingDirectory $primaryClone -Arguments @("config", "user.name", "Lifecycle E2E") | Out-Null
        Invoke-E2EGit -WorkingDirectory $primaryClone -Arguments @("config", "user.email", "lifecycle-e2e@example.invalid") | Out-Null
        Invoke-E2EGit -WorkingDirectory $primaryClone -Arguments @("add", "--", ".gitea/workflows/lifecycle-canary.yml", "git-push-sentinel.txt") | Out-Null
        Invoke-E2EGit -WorkingDirectory $primaryClone -Arguments @("commit", "--quiet", "-m", "add isolated lifecycle canary workflow") | Out-Null
        $expectedCommit = Invoke-E2EGit -WorkingDirectory $primaryClone -Arguments @("rev-parse", "HEAD")
        Invoke-E2EGit -WorkingDirectory $primaryClone -Arguments @("push", "origin", "HEAD:$branch") | Out-Null
        Invoke-E2EGit -WorkingDirectory $state.TestRoot -Arguments @("clone", "--quiet", "--branch", $branch, $repoUrl, $secondaryClone) | Out-Null
        Invoke-E2EGit -WorkingDirectory $primaryClone -Arguments @("fetch", "origin", $branch) | Out-Null
        $fetchedCommit = Invoke-E2EGit -WorkingDirectory $primaryClone -Arguments @("rev-parse", "origin/$branch")
        $clonedCommit = Invoke-E2EGit -WorkingDirectory $secondaryClone -Arguments @("rev-parse", "HEAD")
        $fetchedCommit | Should -Be $expectedCommit
        $clonedCommit | Should -Be $expectedCommit

        function Invoke-HostLabelCanary {
            param([string]$Nonce)
            $beforeDispatch = [DateTimeOffset]::UtcNow
            $dispatchBody = @{ ref = "refs/heads/$branch"; inputs = @{ runNonce = $Nonce } } | ConvertTo-Json -Depth 10
            $dispatchResponse = Invoke-WebRequest -Uri ($state.GiteaUrl + "api/v1/repos/e2e-admin/lifecycle-e2e-sentinel/actions/workflows/lifecycle-canary.yml/dispatches") -Method Post -Headers $headers -ContentType "application/json" -Body $dispatchBody -UseBasicParsing -ErrorAction Stop
            [int]$dispatchResponse.StatusCode | Should -BeIn @(200, 204)
            $dispatchDetails = $null
            if ($dispatchResponse.Content) {
                try { $dispatchDetails = $dispatchResponse.Content | ConvertFrom-Json -ErrorAction Stop } catch { $dispatchDetails = $null }
            }

            $run = $null
            for ($attempt = 0; $attempt -lt 90 -and -not $run; $attempt += 1) {
                $runList = Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/repos/e2e-admin/lifecycle-e2e-sentinel/actions/runs?limit=50") -Method Get -Headers $headers -TimeoutSec 15
                foreach ($candidate in @($runList.workflow_runs)) {
                    $createdAt = [DateTimeOffset]::MinValue
                    if (-not [DateTimeOffset]::TryParse([string]$candidate.created_at, [ref]$createdAt)) { continue }
                    if ([string]$candidate.event -ceq "workflow_dispatch" -and
                        [string]$candidate.head_branch -ceq $branch -and
                        $createdAt -ge $beforeDispatch.AddSeconds(-2)) {
                        $run = $candidate
                        break
                    }
                }
                if (-not $run) { Start-Sleep -Seconds 2 }
            }
            if (-not $run -or -not $run.id) {
                throw "The dispatch response was not treated as a Run ID; the real Runs API did not return the new workflow run."
            }
            if ($dispatchDetails -and $dispatchDetails.workflow_run_id -and [string]$dispatchDetails.workflow_run_id -ne [string]$run.id) {
                throw "The dispatch response and Runs API identify different workflow run IDs."
            }

            for ($attempt = 0; $attempt -lt 120; $attempt += 1) {
                $runStatus = Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/repos/e2e-admin/lifecycle-e2e-sentinel/actions/runs/$($run.id)") -Method Get -Headers $headers -TimeoutSec 15
                if ([string]$runStatus.status -in @("success", "failure", "cancelled", "skipped", "completed")) { break }
                Start-Sleep -Seconds 2
            }
            [string]$runStatus.status | Should -BeIn @("success", "completed")
            if ($runStatus.conclusion) { [string]$runStatus.conclusion | Should -Be "success" }

            $jobsResponse = Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/repos/e2e-admin/lifecycle-e2e-sentinel/actions/runs/$($run.id)/jobs?limit=50") -Method Get -Headers $headers -TimeoutSec 15
            $jobs = @($jobsResponse.jobs)
            $jobs.Count | Should -Be 1
            [string]$jobs[0].runner_name | Should -Be $state.RunnerName
            [string]$jobs[0].conclusion | Should -Be "success"
            $jobLog = Invoke-WebRequest -Uri ($state.GiteaUrl + "api/v1/repos/e2e-admin/lifecycle-e2e-sentinel/actions/jobs/$($jobs[0].id)/logs") -Method Get -Headers $headers -UseBasicParsing -TimeoutSec 15
            [string]$jobLog.Content | Should -Match ([Regex]::Escape("LIFECYCLE_CANARY=$Nonce"))

            $versionResponse = Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/version") -Method Get
            if ([string]$versionResponse.version -match '^1\.(?:25|26)\.') {
                if ($runStatus.PSObject.Properties["run_attempt"]) {
                    [long]$runStatus.run_attempt | Should -BeIn @(0, 1)
                    if ([long]$runStatus.run_attempt -eq 0) {
                        { Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/repos/e2e-admin/lifecycle-e2e-sentinel/actions/runs/$($run.id)/attempts/1") -Method Get -Headers $headers } | Should -Throw
                    }
                }
            }
            elseif ([string]$versionResponse.version -match '^(1\.27\.|28\.)') {
                [long]$runStatus.run_attempt | Should -BeGreaterThan 0
                $attemptResponse = Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/repos/e2e-admin/lifecycle-e2e-sentinel/actions/runs/$($run.id)/attempts/$($runStatus.run_attempt)") -Method Get -Headers $headers -TimeoutSec 15
                [string]$attemptResponse.id | Should -Be ([string]$run.id)
                [long]$attemptResponse.run_attempt | Should -Be ([long]$runStatus.run_attempt)
            }
            return $run
        }

        $firstRun = Invoke-HostLabelCanary -Nonce ([Guid]::NewGuid().ToString("N"))
        $originalRunnerId = [string](Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.RunnerName, "--format", "{{.Id}}"))
        Invoke-GiteaLifecycleE2EDocker -Arguments @("restart", $state.RunnerName) -Stage "restart the isolated host-label Runner" | Out-Null
        $runnerState = ""
        for ($attempt = 0; $attempt -lt 60 -and $runnerState -ne "running"; $attempt += 1) {
            $runnerState = [string](Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.RunnerName, "--format", "{{.State.Status}}"))
            if ($runnerState -ne "running") { Start-Sleep -Seconds 2 }
        }
        $runnerState | Should -Be "running"
        [string](Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.RunnerName, "--format", "{{.Id}}")) | Should -Be $originalRunnerId
        $secondRun = Invoke-HostLabelCanary -Nonce ([Guid]::NewGuid().ToString("N"))
        [string]$secondRun.id | Should -Not -Be ([string]$firstRun.id)
        [string](Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.RunnerName, "--format", "{{.State.Status}}")) | Should -Be "running"
    }

    It "uses ORAS 1.3.5 for isolated Registry tag/digest push-pull, package inspection, authentication refusal, and deletion" {
        $state = Get-GiteaLifecycleE2EState
        $headers = @{
            Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($state.AdminUsername):$($state.AdminPassword)"))
        }
        $orasConfigDirectory = Join-Path $state.TestRoot "oras-auth"
        New-Item -ItemType Directory -Path $orasConfigDirectory -Force | Out-Null
        $registryConfig = Join-Path $orasConfigDirectory "credentials.json"
        $unauthorizedConfig = Join-Path $orasConfigDirectory "unauthorized.json"
        $payloadPath = Join-Path $state.TestRoot "oras-payload.txt"
        [System.IO.File]::WriteAllText($payloadPath, "isolated-registry-round-trip", [System.Text.UTF8Encoding]::new($false))

        function Invoke-E2EOras {
            param([string[]]$Arguments, [string]$StandardInputText, [switch]$AllowFailure)
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = $script:orasExePath
            $startInfo.UseShellExecute = $false
            $startInfo.RedirectStandardInput = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $startInfo.CreateNoWindow = $true
            $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $startInfo.Arguments = ConvertTo-GiteaLifecycleE2EArgumentString -Arguments $Arguments
            $startInfo.EnvironmentVariables["DOCKER_CONFIG"] = Split-Path -Parent $registryConfig
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $startInfo
            [void]$process.Start()
            if ($null -ne $StandardInputText) {
                $process.StandardInput.WriteLine($StandardInputText)
            }
            $process.StandardInput.Close()
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            $safeStderr = [string]$stderr
            foreach ($secret in @($state.AdminPassword, "wrong-fixture-password")) {
                if ($secret) { $safeStderr = $safeStderr.Replace([string]$secret, "[REDACTED]") }
            }
            if (-not $AllowFailure -and $process.ExitCode -ne 0) {
                throw "ORAS operation failed (exit $($process.ExitCode)): $safeStderr"
            }
            return [pscustomobject]@{ ExitCode = [int]$process.ExitCode; StdOut = $stdout.Trim(); StdErr = $safeStderr.Trim() }
        }

        $registryHost = "127.0.0.2:43000"
        $tagReference = "$registryHost/e2e-admin/lifecycle-e2e-artifact:v1"
        $login = Invoke-E2EOras -Arguments @("login", "--plain-http", "--registry-config", $registryConfig, "--username", $state.AdminUsername, "--password-stdin", $registryHost) -StandardInputText $state.AdminPassword
        $login.ExitCode | Should -Be 0
        $push = Invoke-E2EOras -Arguments @("push", "--plain-http", "--registry-config", $registryConfig, "--no-tty", "--format", "go-template", "--template", "{{.digest}}", "--artifact-type", "application/vnd.agent-sdlc.lifecycle.e2e.v1", $tagReference, "$payloadPath:text/plain")
        $digest = [string]$push.StdOut.Trim()
        $digest | Should -Match '^sha256:[0-9a-f]{64}$'
        $resolvedDigest = Invoke-E2EOras -Arguments @("resolve", "--plain-http", "--registry-config", $registryConfig, $tagReference)
        [string]$resolvedDigest.StdOut | Should -Be $digest
        $descriptorJson = Invoke-E2EOras -Arguments @("manifest", "fetch", "--plain-http", "--registry-config", $registryConfig, "--descriptor", "--format", "json", $tagReference)
        $descriptor = $descriptorJson.StdOut | ConvertFrom-Json -ErrorAction Stop
        [string]$descriptor.digest | Should -Be $digest

        $tagPullPath = Join-Path $state.TestRoot "oras-pull-tag"
        $digestPullPath = Join-Path $state.TestRoot "oras-pull-digest"
        Invoke-E2EOras -Arguments @("pull", "--plain-http", "--registry-config", $registryConfig, "--output", $tagPullPath, $tagReference) | Out-Null
        Invoke-E2EOras -Arguments @("pull", "--plain-http", "--registry-config", $registryConfig, "--output", $digestPullPath, "$registryHost/e2e-admin/lifecycle-e2e-artifact@$digest") | Out-Null
        [System.IO.File]::ReadAllText((Join-Path $tagPullPath "oras-payload.txt")) | Should -BeExactly "isolated-registry-round-trip"
        [System.IO.File]::ReadAllText((Join-Path $digestPullPath "oras-payload.txt")) | Should -BeExactly "isolated-registry-round-trip"

        $package = Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/packages/e2e-admin/container/lifecycle-e2e-artifact/v1") -Method Get -Headers $headers -TimeoutSec 15
        [string]$package.type | Should -Be "container"
        [string]$package.name | Should -Be "lifecycle-e2e-artifact"
        [string]$package.version | Should -Be "v1"
        [string]$package.owner.login | Should -Be "e2e-admin"

        $refusedLogin = Invoke-E2EOras -Arguments @("login", "--plain-http", "--registry-config", $unauthorizedConfig, "--username", $state.AdminUsername, "--password-stdin", $registryHost) -StandardInputText "wrong-fixture-password" -AllowFailure
        $refusedLogin.ExitCode | Should -Not -Be 0
        $refusedPull = Invoke-E2EOras -Arguments @("manifest", "fetch", "--plain-http", "--registry-config", $unauthorizedConfig, $tagReference) -AllowFailure
        $refusedPull.ExitCode | Should -Not -Be 0
        $refusedPull.StdErr | Should -Not -Match "wrong-fixture-password"

        $deleteResponse = Invoke-WebRequest -Uri ($state.GiteaUrl + "api/v1/packages/e2e-admin/container/lifecycle-e2e-artifact/v1") -Method Delete -Headers $headers -UseBasicParsing -ErrorAction Stop
        [int]$deleteResponse.StatusCode | Should -Be 204
        try {
            Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/packages/e2e-admin/container/lifecycle-e2e-artifact/v1") -Method Get -Headers $headers -TimeoutSec 15 | Out-Null
            throw "The Registry package still exists after its explicit test-fixture deletion."
        }
        catch {
            if ([int]$_.Exception.Response.StatusCode -ne 404) { throw }
        }
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

        $fault = Invoke-GiteaLifecycleE2EUpgradeWithReservedRenameFault -Context $context `
            -GiteaVersion "1.27.3" `
            -ModulePath (Join-Path $PSScriptRoot "../../scripts/dev/gitea-lifecycle.psm1") `
            -FixtureGiteaName $state.GiteaName `
            -FixtureNetworkName $state.NetworkName `
            -FixtureRunId $state.RunId `
            -GiteaDataPath $state.DataPath `
            -GiteaConfigPath $state.ConfigPath
        $fault.FaultInjected | Should -BeTrue
        $fault.Result | Should -Be "failed"

        Test-Path -LiteralPath $recoveryMarker -PathType Leaf | Should -BeTrue
        $marker = Get-Content -LiteralPath $recoveryMarker -Raw | ConvertFrom-Json
        $reloadedStatus = Get-GiteaLifecycleE2EFreshProcessStatus -Context $context -ModulePath (Join-Path $PSScriptRoot "../../scripts/dev/gitea-lifecycle.psm1")
        $reloadedStatus.RecoveryPending | Should -BeTrue
        [string]$reloadedStatus.Marker.operationId | Should -Be ([string]$marker.operationId)
        [string]$reloadedStatus.Marker.phase | Should -Be "backup-verified"
        [int]$marker.schemaVersion | Should -Be 3
        [string]$marker.phase | Should -Be "backup-verified"
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
        $legacyManifest.schemaVersion = 1
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
        InModuleScope gitea-lifecycle -Parameters @{ BackupPath = $legacyBackupPath; Manifest = $legacyIntegrity.Manifest } {
            param($BackupPath, $Manifest)
            { Get-BackupRuntime -BackupPath $BackupPath -Manifest $Manifest } | Should -Throw "*immutable*"
        }

        $blocker = Get-GiteaLifecycleE2EContainer -ContainerId $fault.BlockerId
        [string](Get-GiteaLifecycleE2EOwnedContainerKind -Container $blocker) | Should -Be "gitea"
        [string]$blocker.Name.TrimStart("/") | Should -Be $fault.BlockerName
        [string]$blocker.State.Status | Should -Be "created"
        Invoke-GiteaLifecycleE2EDocker -Arguments @("rm", $fault.BlockerId) -Stage "remove the verified inert disposable rename blocker" | Out-Null
        [string](Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.GiteaName, "--format", "{{.Id}}")) | Should -Be $sourceGiteaId
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
            Invoke-GiteaLifecycle -Action reconcile-recovery -Context $Context -RecoveryMode original-source -BackupId $BackupId -ExpectedGiteaContainerId $GiteaId -ExpectedPostgresContainerId $PostgresId -ExpectedRunnerContainerId $RunnerId
        }

        Test-Path -LiteralPath $recoveryMarker | Should -BeFalse
        [string](Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.GiteaName, "--format", "{{.Id}}")) | Should -Be $sourceGiteaId
        [string](Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.PostgresName, "--format", "{{.Id}}")) | Should -Be $sourcePostgresId
        [string](Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.RunnerName, "--format", "{{.Id}}")) | Should -Be $sourceRunnerId
        [string](Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/version") -Method Get).version | Should -Be "1.26.4"
        (Invoke-GiteaLifecycleE2EPsql -ContainerName $state.PostgresName -DatabaseName "gitea" -Sql "SELECT 1") | Should -Be "1"
        $reconciliationRecord = Get-ChildItem -LiteralPath (Join-Path $context.RepoRoot ".agent-sdlc\dev-env\gitea\upgrades") -Filter "*.json" -File |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json } |
            Where-Object { [string]$_.recoveryMode -eq "original-source" } |
            Sort-Object completedAt -Descending |
            Select-Object -First 1
        $reconciliationRecord | Should -Not -BeNullOrEmpty
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

        $fault = Invoke-GiteaLifecycleE2EUpgradeWithDetachedTargetFault -Context $context `
            -GiteaVersion "1.27.3" `
            -ModulePath (Join-Path $PSScriptRoot "../../scripts/dev/gitea-lifecycle.psm1") `
            -FixtureGiteaName $state.GiteaName `
            -FixtureNetworkName $state.NetworkName
        $fault.FaultInjected | Should -BeTrue
        $fault.Result | Should -Be "failed"

        $recoveryMarker = Join-Path $context.RepoRoot ".agent-sdlc\dev-env\gitea\lifecycle-recovery.json"
        Test-Path -LiteralPath $recoveryMarker -PathType Leaf | Should -BeTrue
        $marker = Get-Content -LiteralPath $recoveryMarker -Raw | ConvertFrom-Json
        $reloadedStatus = Get-GiteaLifecycleE2EFreshProcessStatus -Context $context -ModulePath (Join-Path $PSScriptRoot "../../scripts/dev/gitea-lifecycle.psm1")
        $reloadedStatus.RecoveryPending | Should -BeTrue
        [string]$reloadedStatus.Marker.operationId | Should -Be ([string]$marker.operationId)
        [string]$reloadedStatus.Marker.phase | Should -Be "target-start-attempted"
        $state.RecoveryBackupId = [string]$marker.backupId
        $state.RecoveryBackupId | Should -Not -BeNullOrEmpty
        $recoveryBackupPath = Join-Path $state.BackupRoot $state.RecoveryBackupId
        $recoveryBackup = InModuleScope gitea-lifecycle -Parameters @{ BackupPath = $recoveryBackupPath } {
            param($BackupPath)
            Test-GiteaBackupIntegrity -BackupPath $BackupPath
        }
        $recoveryBackup.IsValid | Should -BeTrue
        [string]$recoveryBackup.Manifest.sourceVersion | Should -Be "1.26.4"
        # The real injected fault is a temporary network detach. Reconnect only
        # this disposable target after recording the failed-attempt evidence.
        Invoke-GiteaLifecycleE2EDocker -Arguments @("network", "connect", $state.NetworkName, $state.GiteaName) -Stage "reconnect the disposable target after fault evidence is captured" | Out-Null
        Wait-GiteaLifecycleE2EHttp -Uri ($state.GiteaUrl + "api/v1/version")
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

    It "round-trips each adjacent supported upgrade hop through a real backup and restore" {
        $state = Get-GiteaLifecycleE2EState
        $context = $state.Context
        $postgresId = [string](Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.PostgresName, "--format", "{{.Id}}"))
        $runnerId = [string](Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.RunnerName, "--format", "{{.Id}}"))
        $sequence = @(
            @{ From = "1.26.4"; To = "1.27.3" }
        )

        function Invoke-E2EUpgradeAndGetNewBackup {
            param([string]$Version, [string]$ExpectedSourceVersion)
            $backupRoot = [string]$state.BackupRoot
            $beforeIds = @(Get-ChildItem -LiteralPath $backupRoot -Directory | ForEach-Object { $_.Name })
            InModuleScope gitea-lifecycle -Parameters @{ Context = $context; Version = $Version } {
                param($Context, $Version)
                Mock Confirm-GiteaLifecycleOperation {}
                Invoke-GiteaLifecycle -Action upgrade -Context $Context -GiteaVersion $Version
            }
            $newDirectories = @(Get-ChildItem -LiteralPath $backupRoot -Directory | Where-Object { $beforeIds -notcontains $_.Name })
            $newDirectories.Count | Should -Be 1
            $newManifest = Get-Content -LiteralPath (Join-Path $newDirectories[0].FullName "manifest.json") -Raw | ConvertFrom-Json
            [string]$newManifest.kind | Should -Be "upgrade"
            [string]$newManifest.sourceVersion | Should -Be $ExpectedSourceVersion
            return [string]$newDirectories[0].Name
        }

        function Restore-E2EBackup {
            param([string]$BackupId, [string]$ExpectedVersion)
            InModuleScope gitea-lifecycle -Parameters @{ Context = $context; BackupId = $BackupId } {
                param($Context, $BackupId)
                Mock Confirm-GiteaLifecycleOperation {}
                Invoke-GiteaLifecycle -Action restore -Context $Context -BackupId $BackupId
            }
            [string](Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/version") -Method Get).version | Should -Be $ExpectedVersion
            $markerPath = Join-Path $context.RepoRoot ".agent-sdlc\dev-env\gitea\lifecycle-recovery.json"
            Test-Path -LiteralPath $markerPath | Should -BeFalse
            [string](Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.PostgresName, "--format", "{{.Id}}")) | Should -Be $postgresId
            [string](Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $state.RunnerName, "--format", "{{.Id}}")) | Should -Be $runnerId
            (Invoke-GiteaLifecycleE2EPsql -ContainerName $state.PostgresName -DatabaseName "gitea" -Sql "SELECT 1") | Should -Be "1"
            (Invoke-GiteaLifecycleE2EPsql -ContainerName $state.PostgresName -DatabaseName $state.UnrelatedDatabaseName -Sql "SELECT value FROM public.restore_sentinel") | Should -Be "preserve-me"
            Assert-GiteaLifecycleE2ENoAnonymousVolumes -ContainerName $state.GiteaName | Out-Null
        }

        foreach ($hop in $sequence) {
            [string](Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/version") -Method Get).version | Should -Be $hop.From
            $backupId = Invoke-E2EUpgradeAndGetNewBackup -Version $hop.To -ExpectedSourceVersion $hop.From
            [string](Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/version") -Method Get).version | Should -Be $hop.To
            Assert-GiteaLifecycleE2ENoAnonymousVolumes -ContainerName $state.GiteaName | Out-Null
            Restore-E2EBackup -BackupId $backupId -ExpectedVersion $hop.From
        }

        # Recreate the intermediate target after the first round trip, then
        # consume the source snapshot produced by the 1.27.3 -> 28.3.0 hop.
        $intermediateBackupId = Invoke-E2EUpgradeAndGetNewBackup -Version "1.27.3" -ExpectedSourceVersion "1.26.4"
        [string](Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/version") -Method Get).version | Should -Be "1.27.3"
        $finalHopBackupId = Invoke-E2EUpgradeAndGetNewBackup -Version "28.3.0" -ExpectedSourceVersion "1.27.3"
        [string](Invoke-RestMethod -Uri ($state.GiteaUrl + "api/v1/version") -Method Get).version | Should -Be "28.3.0"
        Restore-E2EBackup -BackupId $finalHopBackupId -ExpectedVersion "1.27.3"
    }
}
