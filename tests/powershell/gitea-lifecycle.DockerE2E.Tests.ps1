$script:dockerE2EEnabled = $env:AGENT_SDLC_GITEA_DOCKER_E2E -eq "1"
$script:dockerE2EState = $null

function Invoke-GiteaLifecycleE2EDocker {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $output = @(& docker @Arguments 2>$null)
    $exitCode = $LASTEXITCODE
    $script:dockerE2ELastExitCode = $exitCode
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "Docker E2E operation failed with exit code $exitCode."
    }
    return @($output | ForEach-Object { [string]$_ })
}

function Get-GiteaLifecycleE2EContainerSnapshot {
    $snapshot = @{}
    $containerIds = @(Invoke-GiteaLifecycleE2EDocker -Arguments @("ps", "-aq", "--no-trunc") | Where-Object { $_ })
    foreach ($containerId in $containerIds) {
        $json = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $containerId, "--format", "{{json .}}")
        $container = $json | ConvertFrom-Json
        $snapshot[[string]$container.Id] = @{
            name = [string]$container.Name
            status = [string]$container.State.Status
            startedAt = [string]$container.State.StartedAt
            restartCount = [int]$container.RestartCount
        }
    }
    return $snapshot
}

function Assert-GiteaLifecycleE2EContainerSnapshot {
    param([hashtable]$Expected)

    $actual = Get-GiteaLifecycleE2EContainerSnapshot
    foreach ($containerId in $Expected.Keys) {
        if (-not $actual.ContainsKey($containerId)) {
            throw "An existing Docker container disappeared during the isolated lifecycle E2E."
        }
        foreach ($property in @("name", "status", "startedAt", "restartCount")) {
            if ([string]$actual[$containerId][$property] -ne [string]$Expected[$containerId][$property]) {
                throw "An existing Docker container changed state during the isolated lifecycle E2E."
            }
        }
    }
}

function Assert-GiteaLifecycleE2EPortsAvailable {
    param([string[]]$Ports)

    $conflictingAddresses = @("0.0.0.0", "::", "127.0.0.2", "*")
    $listeners = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue)
    foreach ($port in $Ports) {
        $conflict = @($listeners | Where-Object {
            [int]$_.LocalPort -eq [int]$port -and $conflictingAddresses -contains [string]$_.LocalAddress
        })
        if ($conflict.Count -gt 0) {
            throw "Isolated Docker E2E host endpoint 127.0.0.2:$port is already occupied; no fixture was created."
        }
    }

    $runningIds = @(Invoke-GiteaLifecycleE2EDocker -Arguments @("ps", "-q", "--no-trunc") | Where-Object { $_ })
    foreach ($containerId in $runningIds) {
        $json = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $containerId, "--format", "{{json .}}")
        $container = $json | ConvertFrom-Json
        foreach ($bindingProperty in @($container.HostConfig.PortBindings.PSObject.Properties)) {
            foreach ($binding in @($bindingProperty.Value)) {
                if ($Ports -contains [string]$binding.HostPort -and
                    [string]$binding.HostIp -in @("", "0.0.0.0", "::", "127.0.0.2")) {
                    throw "A running Docker container already reserves an isolated E2E host port; no fixture was created."
                }
            }
        }
    }
}

function New-GiteaLifecycleE2ETestPassword {
    $bytes = New-Object byte[] 32
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $generator.GetBytes($bytes) } finally { $generator.Dispose() }
    return [Convert]::ToBase64String($bytes).TrimEnd("=").Replace("+", "A").Replace("/", "B")
}

function Wait-GiteaLifecycleE2EPostgres {
    param([string]$ContainerName)

    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        $result = Invoke-GiteaLifecycleE2EDocker -Arguments @("exec", $ContainerName, "pg_isready", "-U", "gitea", "-d", "gitea") -AllowFailure
        if ($script:dockerE2ELastExitCode -eq 0 -and (@($result) -join "`n") -match "accepting connections") { return }
        Start-Sleep -Seconds 2
    }
    throw "The isolated PostgreSQL fixture did not become ready."
}

function Wait-GiteaLifecycleE2EHttp {
    param([string]$Uri)

    for ($attempt = 0; $attempt -lt 90; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $Uri -Method Get -UseBasicParsing -TimeoutSec 3
            if ([int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 400) { return }
        }
        catch { }
        Start-Sleep -Seconds 2
    }
    throw "The isolated Gitea fixture did not become reachable."
}

function Initialize-GiteaLifecycleE2EFixture {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw "The isolated Docker lifecycle E2E requires native Windows PowerShell and Docker Desktop."
    }
    $dockerInfo = Invoke-GiteaLifecycleE2EDocker -Arguments @("info", "--format", "{{json .}}") | ConvertFrom-Json
    if ([string]$dockerInfo.OperatingSystem -notmatch "Docker Desktop") {
        throw "The isolated Docker lifecycle E2E requires the Docker Desktop engine."
    }
    Assert-GiteaLifecycleE2EPortsAvailable -Ports @("43000", "42222", "45432")

    $runId = [Guid]::NewGuid().ToString("N")
    $prefix = "agent-sdlc-life-e2e-$runId"
    $testRoot = Join-Path $env:TEMP $prefix
    $repoRoot = Join-Path $testRoot "repo"
    $dataPath = Join-Path $testRoot "volumes\gitea-data"
    $configPath = Join-Path $testRoot "volumes\gitea-config"
    $postgresPath = Join-Path $testRoot "volumes\postgres-data"
    $backupRoot = Join-Path $testRoot "backups"
    $networkName = "$prefix-network"
    $giteaName = "$prefix-gitea"
    $postgresName = "$prefix-db"
    $runnerName = "$prefix-runner"
    $giteaUrl = "http://127.0.0.2:43000/"
    $dbPassword = New-GiteaLifecycleE2ETestPassword
    $adminPassword = New-GiteaLifecycleE2ETestPassword
    $imageTag = "docker.gitea.com/gitea:1.25.5-rootless"

    $existingNames = @(Invoke-GiteaLifecycleE2EDocker -Arguments @("ps", "-aq", "--format", "{{.Names}}") | Where-Object { $_ })
    if (@($existingNames | Where-Object { $_ -eq $giteaName -or $_ -eq $postgresName -or $_ -eq $runnerName }).Count -gt 0) {
        throw "A unique isolated Docker E2E container name already exists; no fixture was created."
    }

    New-Item -ItemType Directory -Path @($repoRoot, $dataPath, $configPath, $postgresPath, $backupRoot) -Force | Out-Null
    $configDirectory = Join-Path $repoRoot "config\dev"
    $operatorDirectory = Join-Path $repoRoot ".agent-sdlc\dev-env\gitea"
    New-Item -ItemType Directory -Path @($configDirectory, $operatorDirectory) -Force | Out-Null
    $bootstrapConfigPath = Join-Path $configDirectory "gitea-bootstrap.json"
    [System.IO.File]::WriteAllText(
        $bootstrapConfigPath,
        '{"gitea":{"image":"' + $imageTag + '"}}',
        [System.Text.UTF8Encoding]::new($false)
    )

    $script:dockerE2EState = @{
        RunId = $runId
        Prefix = $prefix
        TestRoot = $testRoot
        NetworkName = $networkName
        NetworkCreated = $false
        GiteaName = $giteaName
        PostgresName = $postgresName
        RunnerName = $runnerName
        RunnerContainerId = $null
        PostgresContainerId = $null
        GiteaUrl = $giteaUrl
        AdminUsername = "e2e-admin"
        AdminPassword = $adminPassword
        BackupRoot = $backupRoot
        InitialBackupId = $null
        ExistingContainers = Get-GiteaLifecycleE2EContainerSnapshot
        Context = @{
            RepoRoot = $repoRoot
            ConfigPath = $bootstrapConfigPath
            LocalConfigPath = $bootstrapConfigPath
            ConfigSource = "local"
            GiteaImageEnvironmentOverride = $false
            BackupRoot = $backupRoot
            GiteaDataDir = $dataPath
            GiteaConfigDir = $configPath
            GiteaPostgresDataDir = $postgresPath
            GiteaSecretsPath = Join-Path $operatorDirectory "generated-secrets.json"
            GiteaBootstrapSummaryPath = Join-Path $operatorDirectory "bootstrap-summary.json"
            EffectiveBootstrapSettingsPath = Join-Path $operatorDirectory "effective-settings.json"
            GiteaContainerName = $giteaName
            GiteaPostgresContainerName = $postgresName
            GiteaRunnerContainerName = $runnerName
            GiteaNetworkName = $networkName
            GiteaRootUrl = $giteaUrl
            GiteaDatabaseMode = "postgres"
            GiteaHttpPort = 43000
            GiteaSshPort = 42222
            GiteaPostgresHostPort = 45432
            PortBindAddress = "127.0.0.2"
            GiteaPostgresDbName = "gitea"
            GiteaPostgresUser = "gitea"
            GiteaAdminUsername = "e2e-admin"
            GiteaAdminPassword = $adminPassword
        }
    }

    Invoke-GiteaLifecycleE2EDocker -Arguments @("pull", "postgres:16") | Out-Null
    Invoke-GiteaLifecycleE2EDocker -Arguments @("pull", "alpine:3.20") | Out-Null
    Invoke-GiteaLifecycleE2EDocker -Arguments @("pull", $imageTag) | Out-Null
    Invoke-GiteaLifecycleE2EDocker -Arguments @("network", "create", "--label", "agent-sdlc.lifecycle-e2e.run-id=$runId", $networkName) | Out-Null
    $script:dockerE2EState.NetworkCreated = $true

    Invoke-GiteaLifecycleE2EDocker -Arguments @(
        "run", "-d", "--name", $postgresName, "--network", $networkName, "--network-alias", "db",
        "--restart", "unless-stopped", "--label", "agent-sdlc.lifecycle-e2e.run-id=$runId",
        "--mount", "type=bind,source=$postgresPath,target=/var/lib/postgresql/data",
        "-p", "127.0.0.2:45432:5432", "-e", "POSTGRES_DB=gitea", "-e", "POSTGRES_USER=gitea",
        "-e", "POSTGRES_PASSWORD=$dbPassword", "postgres:16"
    ) | Out-Null
    Wait-GiteaLifecycleE2EPostgres -ContainerName $postgresName

    Invoke-GiteaLifecycleE2EDocker -Arguments @(
        "run", "-d", "--name", $runnerName, "--network", $networkName, "--restart", "unless-stopped",
        "--label", "agent-sdlc.lifecycle-e2e.run-id=$runId", "--entrypoint", "sh", "alpine:3.20", "-c", "sleep infinity"
    ) | Out-Null
    $script:dockerE2EState.RunnerContainerId = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $runnerName, "--format", "{{.Id}}")
    $script:dockerE2EState.PostgresContainerId = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $postgresName, "--format", "{{.Id}}")

    Invoke-GiteaLifecycleE2EDocker -Arguments @(
        "run", "-d", "--name", $giteaName, "--network", $networkName, "--restart", "unless-stopped",
        "--mount", "type=bind,source=$dataPath,target=/var/lib/gitea",
        "--mount", "type=bind,source=$configPath,target=/etc/gitea",
        "-p", "127.0.0.2:43000:3000", "-p", "127.0.0.2:42222:2222",
        "-e", "GITEA__database__DB_TYPE=postgres", "-e", "GITEA__database__HOST=db:5432",
        "-e", "GITEA__database__NAME=gitea", "-e", "GITEA__database__USER=gitea",
        "-e", "GITEA__database__PASSWD=$dbPassword", "-e", "GITEA__server__ROOT_URL=$giteaUrl",
        "-e", "GITEA__server__HTTP_PORT=3000", "-e", "GITEA__server__SSH_PORT=2222",
        "-e", "GITEA__security__INSTALL_LOCK=true", "-e", "GITEA__actions__ENABLED=true", $imageTag
    ) | Out-Null

    Wait-GiteaLifecycleE2EHttp -Uri ($giteaUrl + "api/v1/version")
    Invoke-GiteaLifecycleE2EDocker -Arguments @(
        "exec", $giteaName, "gitea", "admin", "user", "create", "--username", "e2e-admin",
        "--password", $adminPassword, "--email", "e2e-admin@example.invalid", "--admin", "--must-change-password=false"
    ) | Out-Null
    $script:dockerE2EState.AdminPassword = $adminPassword

    $headers = @{
        Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("e2e-admin:$adminPassword"))
    }
    $repoBody = @{ name = "lifecycle-e2e-sentinel"; private = $true; auto_init = $true } | ConvertTo-Json
    Invoke-RestMethod -Uri ($giteaUrl + "api/v1/user/repos") -Method Post -Headers $headers -ContentType "application/json" -Body $repoBody | Out-Null

    Import-Module (Join-Path $PSScriptRoot "../../scripts/dev/gitea-lifecycle.psm1") -Force
}

function Remove-GiteaLifecycleE2EFixture {
    if (-not $script:dockerE2EState) { return }
    $state = $script:dockerE2EState
    $cleanupComplete = $false
    try {
        $allIds = @(Invoke-GiteaLifecycleE2EDocker -Arguments @("ps", "-aq", "--no-trunc") | Where-Object { $_ })
        foreach ($containerId in $allIds) {
            $json = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $containerId, "--format", "{{json .}}")
            $container = $json | ConvertFrom-Json
            $name = [string]$container.Name.TrimStart("/")
            if ($name -eq $state.Prefix -or $name.StartsWith($state.Prefix + "-", [StringComparison]::Ordinal)) {
                Invoke-GiteaLifecycleE2EDocker -Arguments @("rm", "-f", $name) | Out-Null
            }
        }
        if ($state.NetworkCreated) {
            $networkJson = Invoke-GiteaLifecycleE2EDocker -Arguments @("network", "inspect", $state.NetworkName, "--format", "{{json .Labels}}") -AllowFailure
            if ($script:dockerE2ELastExitCode -ne 0) {
                throw "Could not confirm whether the isolated Docker E2E network was removed."
            }
            $networkLabels = $networkJson | ConvertFrom-Json
            if ([string]$networkLabels.'agent-sdlc.lifecycle-e2e.run-id' -ne [string]$state.RunId) {
                throw "The Docker E2E network identity changed; refusing to remove an unverified network."
            }
            Invoke-GiteaLifecycleE2EDocker -Arguments @("network", "rm", $state.NetworkName) | Out-Null
        }

        $remainingIds = @(Invoke-GiteaLifecycleE2EDocker -Arguments @("ps", "-aq", "--no-trunc") | Where-Object { $_ })
        foreach ($containerId in $remainingIds) {
            $remainingJson = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $containerId, "--format", "{{json .}}")
            $remainingContainer = $remainingJson | ConvertFrom-Json
            $remainingName = [string]$remainingContainer.Name.TrimStart("/")
            if ($remainingName -eq $state.Prefix -or $remainingName.StartsWith($state.Prefix + "-", [StringComparison]::Ordinal)) {
                throw "An isolated Docker E2E container remains after cleanup."
            }
        }
        $cleanupComplete = $true
    }
    finally {
        if ($cleanupComplete -and (Test-Path -LiteralPath $state.TestRoot)) {
            Remove-Item -LiteralPath $state.TestRoot -Recurse -Force
        }
        elseif (-not $cleanupComplete) {
            Write-Warning "Docker cleanup could not be confirmed. Fixture data is preserved at '$($state.TestRoot)' for manual cleanup."
        }
        Assert-GiteaLifecycleE2EContainerSnapshot -Expected $state.ExistingContainers
    }
}

BeforeAll {
    if ($script:dockerE2EEnabled) {
        Initialize-GiteaLifecycleE2EFixture
    }
}

AfterAll {
    if ($script:dockerE2EEnabled) {
        Remove-GiteaLifecycleE2EFixture
    }
}

Describe "Gitea lifecycle isolated Docker acceptance" -Tag "DockerE2E" {
    It "upgrades, lists and validates a backup, restores it, and leaves existing containers unchanged" -Skip:(-not $script:dockerE2EEnabled) {
        $context = $script:dockerE2EState.Context
        $headers = @{
            Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($script:dockerE2EState.AdminUsername):$($script:dockerE2EState.AdminPassword)"))
        }

        InModuleScope gitea-lifecycle -Parameters @{ Context = $context } {
            param($Context)
            Mock Confirm-GiteaLifecycleOperation {}
            Invoke-GiteaLifecycle -Action upgrade -Context $Context -GiteaVersion "1.26.4"
        }

        $version = Invoke-RestMethod -Uri ($script:dockerE2EState.GiteaUrl + "api/v1/version") -Method Get
        [string]$version.version | Should -Be "1.26.4"
        $backupDirectories = @(Get-ChildItem -LiteralPath $script:dockerE2EState.BackupRoot -Directory | Sort-Object Name)
        $backupDirectories.Count | Should -BeGreaterThan 0
        $script:dockerE2EState.InitialBackupId = $backupDirectories[0].Name

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
        [string]$backupList | Should -Match $script:dockerE2EState.InitialBackupId
        [string]$backupList | Should -Not -Match $script:dockerE2EState.AdminPassword
        [string]$backupList | Should -Not -Match "POSTGRES_PASSWORD"

        $repo = Invoke-RestMethod -Uri ($script:dockerE2EState.GiteaUrl + "api/v1/repos/e2e-admin/lifecycle-e2e-sentinel") -Method Get -Headers $headers
        [string]$repo.name | Should -Be "lifecycle-e2e-sentinel"
    }

    It "retains recovery evidence after a post-migration failure" -Skip:(-not $script:dockerE2EEnabled) {
        $context = $script:dockerE2EState.Context
        $script:dockerE2EState.InitialBackupId | Should -Not -BeNullOrEmpty

        InModuleScope gitea-lifecycle -Parameters @{ Context = $context } {
            param($Context)
            Mock Confirm-GiteaLifecycleOperation {}
            Mock Assert-GiteaApiVersion { throw "simulated-api-version-failure" }
            { Invoke-GiteaLifecycle -Action upgrade -Context $Context -GiteaVersion "1.26.4" } | Should -Throw "*simulated-api-version-failure*"
        }

        $recoveryMarker = Join-Path $context.RepoRoot ".agent-sdlc\dev-env\gitea\lifecycle-recovery.json"
        Test-Path -LiteralPath $recoveryMarker -PathType Leaf | Should -BeTrue
        InModuleScope gitea-lifecycle -Parameters @{ Context = $context } {
            param($Context)
            { Assert-NoPendingGiteaRecovery -Context $Context } | Should -Throw "*blocked*"
        }
        $runner = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $script:dockerE2EState.RunnerName, "--format", "{{.State.Status}}")
        $runner | Should -Be "exited"
        $activeName = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $script:dockerE2EState.GiteaName, "--format", "{{.State.Status}}")
        $activeName | Should -Be "running"
        $version = Invoke-RestMethod -Uri ($script:dockerE2EState.GiteaUrl + "api/v1/version") -Method Get
        [string]$version.version | Should -Be "1.26.4"
        $runnerId = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $script:dockerE2EState.RunnerName, "--format", "{{.Id}}")
        $runnerId | Should -Be $script:dockerE2EState.RunnerContainerId
    }

    It "explicitly restores the matching source snapshot" -Skip:(-not $script:dockerE2EEnabled) {
        $context = $script:dockerE2EState.Context
        $backupId = $script:dockerE2EState.InitialBackupId
        $backupId | Should -Not -BeNullOrEmpty
        $recoveryMarker = Join-Path $context.RepoRoot ".agent-sdlc\dev-env\gitea\lifecycle-recovery.json"
        InModuleScope gitea-lifecycle -Parameters @{ Context = $context; SelectedBackupId = $backupId } {
            param($Context, $SelectedBackupId)
            Mock Confirm-GiteaLifecycleOperation {}
            Invoke-GiteaLifecycle -Action restore -Context $Context -BackupId $SelectedBackupId
        }

        $version = Invoke-RestMethod -Uri ($script:dockerE2EState.GiteaUrl + "api/v1/version") -Method Get
        [string]$version.version | Should -Be "1.25.5"
        Test-Path -LiteralPath $recoveryMarker | Should -BeFalse
        $runner = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $script:dockerE2EState.RunnerName, "--format", "{{.State.Status}}")
        $runner | Should -Be "running"
        $runnerId = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $script:dockerE2EState.RunnerName, "--format", "{{.Id}}")
        $runnerId | Should -Be $script:dockerE2EState.RunnerContainerId
        $postgresId = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $script:dockerE2EState.PostgresName, "--format", "{{.Id}}")
        $postgresId | Should -Be $script:dockerE2EState.PostgresContainerId
        $headers = @{
            Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($script:dockerE2EState.AdminUsername):$($script:dockerE2EState.AdminPassword)"))
        }
        $repo = Invoke-RestMethod -Uri ($script:dockerE2EState.GiteaUrl + "api/v1/repos/e2e-admin/lifecycle-e2e-sentinel") -Method Get -Headers $headers
        [string]$repo.name | Should -Be "lifecycle-e2e-sentinel"
        Assert-GiteaLifecycleE2EContainerSnapshot -Expected $script:dockerE2EState.ExistingContainers
    }
}
