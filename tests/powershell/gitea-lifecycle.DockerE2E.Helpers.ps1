function Get-GiteaLifecycleE2EDockerSubcommand {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    if ($Arguments.Count -eq 0) { return "docker operation" }
    switch ($Arguments[0]) {
        "network" {
            if ($Arguments.Count -gt 1 -and $Arguments[1] -in @("create", "inspect", "rm", "ls")) {
                return "docker network $($Arguments[1])"
            }
            return "docker network"
        }
        { $_ -in @("exec", "info", "inspect", "pull", "ps", "rm", "run") } { return "docker $($Arguments[0])" }
        default { return "docker operation" }
    }
}

function Get-GiteaLifecycleE2EDockerStage {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    if ($Arguments.Count -eq 0) { return "run the isolated Docker fixture operation" }
    switch ($Arguments[0]) {
        "info" { return "validate the Docker Desktop engine" }
        "pull" { return "pull a disposable fixture image" }
        "network" {
            if ($Arguments.Count -gt 1) {
                switch ($Arguments[1]) {
                    "create" { return "create the isolated fixture network" }
                    "inspect" { return "verify the isolated fixture network" }
                    "rm" { return "remove the verified fixture network" }
                    "ls" { return "check for a pre-existing fixture network" }
                }
            }
            return "manage the isolated fixture network"
        }
        "run" {
            $nameIndex = [Array]::IndexOf($Arguments, "--name")
            if ($nameIndex -ge 0 -and $nameIndex + 1 -lt $Arguments.Count) {
                $fixtureName = [string]$Arguments[$nameIndex + 1]
                if ($fixtureName -match "-db$") { return "start the disposable PostgreSQL fixture" }
                if ($fixtureName -match "-runner$") { return "start the inert disposable Runner fixture" }
                if ($fixtureName -match "-gitea(?:-|$)") { return "start the disposable Gitea fixture" }
            }
            return "start a disposable fixture container"
        }
        "exec" {
            if ($Arguments -contains "pg_isready") { return "check disposable PostgreSQL readiness" }
            if ($Arguments -contains "psql") { return "prepare or inspect the disposable fixture database" }
            if ($Arguments -contains "gitea") { return "configure the disposable Gitea fixture" }
            return "run a command in a disposable fixture container"
        }
        "ps" { return "inspect the existing Docker container snapshot" }
        "inspect" { return "inspect a fixture or existing container" }
        "rm" { return "remove a verified fixture container" }
        default { return "run the isolated Docker fixture operation" }
    }
}

function Protect-GiteaLifecycleE2EDockerStderr {
    param(
        [AllowEmptyString()][string]$Text,
        [string[]]$Arguments
    )

    $sanitized = [string]$Text
    $secrets = [System.Collections.Generic.List[string]]::new()
    $sensitiveFlag = $false
    foreach ($argument in $Arguments) {
        $value = [string]$argument
        if ($sensitiveFlag -and $value) { $secrets.Add($value) }
        $sensitiveFlag = $value -match "^--?(?:password|passwd|token|secret|credential|authorization|auth)$"

        if ($value -match "(?i)^[^=]*(?:password|passwd|token|secret|credential|authorization|auth|private[_-]?key|access[_-]?key)[^=]*=(.*)$") {
            $assignedSecret = [string]$Matches[1]
            if ($assignedSecret) {
                $secrets.Add($assignedSecret.Trim([char[]]@('"', "'")))
            }
        }
    }

    $state = $script:dockerE2EState
    if ($state -and $state.AdminPassword) { $secrets.Add([string]$state.AdminPassword) }
    if ($state -and $state.Context -and $state.Context.GiteaAdminPassword) {
        $secrets.Add([string]$state.Context.GiteaAdminPassword)
    }

    foreach ($secret in @($secrets | Where-Object { $_ } | Sort-Object -Unique | Sort-Object Length -Descending)) {
        $sanitized = [Regex]::Replace($sanitized, [Regex]::Escape($secret), "[REDACTED]", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }

    $sanitized = [Regex]::Replace(
        $sanitized,
        '(?im)(\b[A-Z0-9_.-]*(?:password|passwd|token|secret|credential|authorization|auth|private[_-]?key|access[_-]?key)[A-Z0-9_.-]*\s*[=:]\s*)(?:"[^"]*"|''[^'']*''|[^\s,;]+)',
        '$1[REDACTED]'
    )
    $sanitized = [Regex]::Replace(
        $sanitized,
        '(?i)(--?(?:password|passwd|token|secret|credential|authorization|auth)(?:=|\s+))(?:"[^"]*"|''[^'']*''|[^\s,;]+)',
        '$1[REDACTED]'
    )
    $sanitized = [Regex]::Replace($sanitized, '(?i)\b(Basic\s+|Bearer\s+)[A-Za-z0-9._~+/-]+=*', '$1[REDACTED]')
    $sanitized = [Regex]::Replace($sanitized, '(?i)(https?://[^:/\s@]+:)[^@\s]+(@)', '$1[REDACTED]$2').Trim()

    if (-not $sanitized) { return "(no stderr captured)" }
    if ($sanitized.Length -gt 4000) {
        return $sanitized.Substring(0, 4000) + "`n[stderr truncated]"
    }
    return $sanitized
}

function Invoke-GiteaLifecycleE2EDocker {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$Stage,
        [switch]$AllowFailure
    )

    $dockerSubcommand = Get-GiteaLifecycleE2EDockerSubcommand -Arguments $Arguments
    if (-not $Stage) { $Stage = Get-GiteaLifecycleE2EDockerStage -Arguments $Arguments }
    $stderrPath = $null
    $processFailedToStart = $false
    $exitCode = 1
    try {
        $stderrPath = [System.IO.Path]::GetTempFileName()
        $global:LASTEXITCODE = 0
        $output = @(& docker @Arguments 2> $stderrPath)
        if ($null -ne $LASTEXITCODE) { $exitCode = [int]$LASTEXITCODE }
    }
    catch {
        # Do not include PowerShell's invocation error because it can render the full argument list.
        $processFailedToStart = $true
        $output = @()
    }
    finally {
        $stderrText = ""
        if ($stderrPath -and (Test-Path -LiteralPath $stderrPath -PathType Leaf)) {
            try { $stderrText = [System.IO.File]::ReadAllText($stderrPath) } catch { $stderrText = "" }
            try { [System.IO.File]::WriteAllText($stderrPath, "") } catch { }
            Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
        }
    }

    $script:dockerE2ELastExitCode = $exitCode
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        $safeStderr = Protect-GiteaLifecycleE2EDockerStderr -Text $stderrText -Arguments $Arguments
        if ($processFailedToStart -and $safeStderr -eq "(no stderr captured)") {
            $safeStderr = "Docker CLI could not be started."
        }
        throw "Docker E2E stage '$Stage' failed: '$dockerSubcommand' exited with code $exitCode. stderr: $safeStderr"
    }
    return @($output | ForEach-Object { [string]$_ })
}

function Get-GiteaLifecycleE2EState {
    return $script:dockerE2EState
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

function Get-GiteaLifecycleE2EContainer {
    param([Parameter(Mandatory = $true)][string]$ContainerId)

    $json = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $ContainerId, "--format", "{{json .}}")
    return ($json | ConvertFrom-Json)
}

function Test-GiteaLifecycleE2EPathEqual {
    param([string]$Left, [string]$Right)

    if (-not $Left -or -not $Right) { return $false }
    try {
        $normalizedLeft = [System.IO.Path]::GetFullPath($Left).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        $normalizedRight = [System.IO.Path]::GetFullPath($Right).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        return [string]::Equals($normalizedLeft, $normalizedRight, [StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

function Get-GiteaLifecycleE2EOwnedContainerKind {
    param([Parameter(Mandatory = $true)][object]$Container)

    $state = $script:dockerE2EState
    $name = [string]$Container.Name.TrimStart("/")
    $labels = $Container.Config.Labels
    $runIdLabel = if ($labels) { [string]$labels.'agent-sdlc.lifecycle-e2e.run-id' } else { "" }
    $networkNames = @($Container.NetworkSettings.Networks.PSObject.Properties.Name)
    $isOnFixtureNetwork = $networkNames -contains [string]$state.NetworkName

    if ($name -eq $state.PostgresName -and $isOnFixtureNetwork -and $runIdLabel -eq [string]$state.RunId) {
        $postgresMount = @($Container.Mounts | Where-Object { [string]$_.Destination -eq "/var/lib/postgresql/data" })
        if ($postgresMount.Count -eq 1 -and (Test-GiteaLifecycleE2EPathEqual -Left ([string]$postgresMount[0].Source) -Right ([string]$state.PostgresPath))) {
            return "postgres"
        }
        return $null
    }

    if ($name -eq $state.RunnerName -and $isOnFixtureNetwork -and $runIdLabel -eq [string]$state.RunId) {
        return "runner"
    }

    $giteaNamePattern = "^{0}(?:-(?:preupgrade|failed)-[A-Za-z0-9T-]+)?$" -f [Regex]::Escape([string]$state.GiteaName)
    if ($name -match $giteaNamePattern -and $isOnFixtureNetwork) {
        $mounts = @($Container.Mounts)
        $dataMount = @($mounts | Where-Object { [string]$_.Destination -eq "/var/lib/gitea" })
        $configMount = @($mounts | Where-Object { [string]$_.Destination -eq "/etc/gitea" })
        if ($mounts.Count -eq 2 -and $dataMount.Count -eq 1 -and $configMount.Count -eq 1 -and
            (Test-GiteaLifecycleE2EPathEqual -Left ([string]$dataMount[0].Source) -Right ([string]$state.DataPath)) -and
            (Test-GiteaLifecycleE2EPathEqual -Left ([string]$configMount[0].Source) -Right ([string]$state.ConfigPath))) {
            return "gitea"
        }
    }

    return $null
}

function Register-GiteaLifecycleE2EOwnedContainers {
    if (-not $script:dockerE2EState) { return }
    $state = $script:dockerE2EState
    $networkJson = Invoke-GiteaLifecycleE2EDocker -Arguments @("network", "inspect", $state.NetworkName, "--format", "{{json .}}") -AllowFailure
    if ($script:dockerE2ELastExitCode -ne 0) {
        if ($state.NetworkCreated) {
            throw "Could not confirm the isolated Docker E2E network before recording fixture ownership."
        }
        return
    }
    $network = $networkJson | ConvertFrom-Json
    if ([string]$network.Labels.'agent-sdlc.lifecycle-e2e.run-id' -ne [string]$state.RunId -or
        ($state.NetworkId -and [string]$network.Id -ne [string]$state.NetworkId)) {
        throw "The Docker E2E network identity changed; refusing to claim attached containers."
    }
    $state.NetworkCreated = $true
    $state.NetworkId = [string]$network.Id

    $containerIds = @(Invoke-GiteaLifecycleE2EDocker -Arguments @("ps", "-aq", "--no-trunc") | Where-Object { $_ })
    foreach ($containerId in $containerIds) {
        $container = Get-GiteaLifecycleE2EContainer -ContainerId ([string]$containerId)
        $kind = Get-GiteaLifecycleE2EOwnedContainerKind -Container $container
        if ($kind) {
            $state.OwnedContainers[[string]$container.Id] = @{
                id = [string]$container.Id
                name = [string]$container.Name.TrimStart("/")
                kind = [string]$kind
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
    param(
        [Parameter(Mandatory = $true)][string]$ContainerName,
        [Parameter(Mandatory = $true)][string]$DatabasePassword
    )

    if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
        throw "A fixture database password is required to verify PostgreSQL readiness."
    }

    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        $result = Invoke-GiteaLifecycleE2EDocker -Arguments @(
            "exec", $ContainerName, "pg_isready", "-h", "127.0.0.1", "-p", "5432",
            "-U", "gitea", "-d", "gitea", "-t", "1"
        ) -Stage "wait for disposable PostgreSQL TCP readiness" -AllowFailure

        if ($script:dockerE2ELastExitCode -eq 0 -and (@($result) -join "`n") -match "accepting connections") {
            $sqlResult = Invoke-GiteaLifecycleE2EPsql -ContainerName $ContainerName `
                -DatabaseName "gitea" `
                -Sql "SELECT 1" `
                -ServerAddress "127.0.0.1" `
                -Password $DatabasePassword `
                -AllowFailure
            if ($script:dockerE2ELastExitCode -eq 0 -and (@($sqlResult) -join "`n").Trim() -eq "1") { return }
        }

        if ($attempt -lt 59) { Start-Sleep -Seconds 2 }
    }
    throw "The isolated PostgreSQL fixture did not become ready for TCP and SQL connections."
}

function Invoke-GiteaLifecycleE2EPsql {
    param(
        [Parameter(Mandatory = $true)][string]$ContainerName,
        [Parameter(Mandatory = $true)][string]$DatabaseName,
        [Parameter(Mandatory = $true)][string]$Sql,
        [string]$ServerAddress,
        [string]$Password,
        [switch]$AllowFailure
    )

    $arguments = @("exec")
    if ($ServerAddress) {
        if ([string]::IsNullOrWhiteSpace($Password)) {
            throw "A password is required for a TCP connection to the disposable PostgreSQL fixture."
        }
        $arguments += @("-e", "PGPASSWORD=$Password", "-e", "PGCONNECT_TIMEOUT=1")
    }
    $arguments += @($ContainerName, "psql", "--no-psqlrc", "--no-password", "--set", "ON_ERROR_STOP=1")
    if ($ServerAddress) { $arguments += @("--host", $ServerAddress, "--port", "5432") }
    $arguments += @(
        "--username", "gitea", "--dbname", $DatabaseName,
        "--tuples-only", "--no-align", "--command", $Sql
    )

    if ($AllowFailure) {
        $output = Invoke-GiteaLifecycleE2EDocker -Stage "run SQL against the disposable fixture database" -Arguments $arguments -AllowFailure
    }
    else {
        $output = Invoke-GiteaLifecycleE2EDocker -Stage "run SQL against the disposable fixture database" -Arguments $arguments
    }
    return (@($output) -join "`n").Trim()
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
    if (Test-Path -LiteralPath $testRoot) {
        throw "The unique isolated Docker E2E directory already exists; no fixture was created."
    }
    if (@($existingNames | Where-Object { $_ -eq $giteaName -or $_ -eq $postgresName -or $_ -eq $runnerName }).Count -gt 0) {
        throw "A unique isolated Docker E2E container name already exists; no fixture was created."
    }

    $existingNetworks = @(Invoke-GiteaLifecycleE2EDocker -Arguments @("network", "ls", "--format", "{{.Name}}") | Where-Object { $_ })
    if ($existingNetworks -contains $networkName) {
        throw "A unique isolated Docker E2E network name already exists; no fixture was created."
    }

    $script:dockerE2EState = @{
        RunId = $runId
        Prefix = $prefix
        TestRoot = $testRoot
        TestRootCreated = $false
        OwnershipMarkerPath = Join-Path $testRoot ".agent-sdlc-lifecycle-e2e-owner.json"
        NetworkName = $networkName
        NetworkId = $null
        NetworkCreated = $false
        GiteaName = $giteaName
        PostgresName = $postgresName
        RunnerName = $runnerName
        DataPath = $dataPath
        ConfigPath = $configPath
        PostgresPath = $postgresPath
        RunnerContainerId = $null
        PostgresContainerId = $null
        OwnedContainers = @{}
        UnrelatedDatabaseName = "e2e_unrelated"
        GiteaUrl = $giteaUrl
        AdminUsername = "e2e-admin"
        AdminPassword = $adminPassword
        BackupRoot = $backupRoot
        InitialBackupId = $null
        ExistingContainers = Get-GiteaLifecycleE2EContainerSnapshot
    }

    New-Item -ItemType Directory -Path $testRoot -ErrorAction Stop | Out-Null
    $script:dockerE2EState.TestRootCreated = $true
    [System.IO.File]::WriteAllText(
        $script:dockerE2EState.OwnershipMarkerPath,
        (@{ runId = $runId; prefix = $prefix } | ConvertTo-Json -Compress),
        [System.Text.UTF8Encoding]::new($false)
    )
    New-Item -ItemType Directory -Path @($repoRoot, $dataPath, $configPath, $postgresPath, $backupRoot) -Force -ErrorAction Stop | Out-Null
    $configDirectory = Join-Path $repoRoot "config\dev"
    $operatorDirectory = Join-Path $repoRoot ".agent-sdlc\dev-env\gitea"
    New-Item -ItemType Directory -Path @($configDirectory, $operatorDirectory) -Force -ErrorAction Stop | Out-Null
    $bootstrapConfigPath = Join-Path $configDirectory "gitea-bootstrap.json"
    [System.IO.File]::WriteAllText(
        $bootstrapConfigPath,
        '{"gitea":{"image":"' + $imageTag + '"}}',
        [System.Text.UTF8Encoding]::new($false)
    )

    $script:dockerE2EState.Context = @{
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

    Invoke-GiteaLifecycleE2EDocker -Arguments @("pull", "postgres:16") -Stage "pull disposable PostgreSQL fixture image" | Out-Null
    Invoke-GiteaLifecycleE2EDocker -Arguments @("pull", "alpine:3.20") -Stage "pull inert Runner fixture image" | Out-Null
    Invoke-GiteaLifecycleE2EDocker -Arguments @("pull", $imageTag) -Stage "pull disposable Gitea fixture image" | Out-Null
    $networkId = [string]((Invoke-GiteaLifecycleE2EDocker -Arguments @("network", "create", "--label", "agent-sdlc.lifecycle-e2e.run-id=$runId", $networkName) -Stage "create isolated fixture network" | Select-Object -First 1)).Trim()
    $script:dockerE2EState.NetworkCreated = $true
    $script:dockerE2EState.NetworkId = $networkId

    Invoke-GiteaLifecycleE2EDocker -Stage "start disposable PostgreSQL fixture" -Arguments @(
        "run", "-d", "--name", $postgresName, "--network", $networkName, "--network-alias", "db",
        "--restart", "unless-stopped", "--label", "agent-sdlc.lifecycle-e2e.run-id=$runId",
        "--mount", "type=bind,source=$postgresPath,target=/var/lib/postgresql/data",
        "-p", "127.0.0.2:45432:5432", "-e", "POSTGRES_DB=gitea", "-e", "POSTGRES_USER=gitea",
        "-e", "POSTGRES_PASSWORD=$dbPassword", "postgres:16"
    ) | Out-Null
    Wait-GiteaLifecycleE2EPostgres -ContainerName $postgresName -DatabasePassword $dbPassword
    Invoke-GiteaLifecycleE2EPsql -ContainerName $postgresName -DatabaseName "postgres" -Sql "CREATE DATABASE e2e_unrelated" | Out-Null
    Invoke-GiteaLifecycleE2EPsql -ContainerName $postgresName -DatabaseName "e2e_unrelated" -Sql "CREATE TABLE public.restore_sentinel (value text NOT NULL); INSERT INTO public.restore_sentinel (value) VALUES ('preserve-me')" | Out-Null

    Invoke-GiteaLifecycleE2EDocker -Stage "start inert disposable Runner fixture" -Arguments @(
        "run", "-d", "--name", $runnerName, "--network", $networkName, "--restart", "unless-stopped",
        "--label", "agent-sdlc.lifecycle-e2e.run-id=$runId", "--entrypoint", "sh", "alpine:3.20", "-c", "sleep infinity"
    ) | Out-Null
    $script:dockerE2EState.RunnerContainerId = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $runnerName, "--format", "{{.Id}}")
    $script:dockerE2EState.PostgresContainerId = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $postgresName, "--format", "{{.Id}}")

    Invoke-GiteaLifecycleE2EDocker -Stage "start disposable Gitea fixture" -Arguments @(
        "run", "-d", "--name", $giteaName, "--network", $networkName, "--restart", "unless-stopped",
        "--label", "agent-sdlc.lifecycle-e2e.run-id=$runId",
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
    Invoke-GiteaLifecycleE2EDocker -Stage "create disposable Gitea administrator" -Arguments @(
        "exec", $giteaName, "gitea", "admin", "user", "create", "--username", "e2e-admin",
        "--password", $adminPassword, "--email", "e2e-admin@example.invalid", "--admin", "--must-change-password=false"
    ) | Out-Null
    $script:dockerE2EState.AdminPassword = $adminPassword

    $headers = @{
        Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("e2e-admin:$adminPassword"))
    }
    $repoBody = @{ name = "lifecycle-e2e-sentinel"; private = $true; auto_init = $true } | ConvertTo-Json
    Invoke-RestMethod -Uri ($giteaUrl + "api/v1/user/repos") -Method Post -Headers $headers -ContentType "application/json" -Body $repoBody | Out-Null

    Register-GiteaLifecycleE2EOwnedContainers
}

function Remove-GiteaLifecycleE2EFixture {
    if (-not $script:dockerE2EState) { return }
    $state = $script:dockerE2EState
    if ($state.CleanupComplete) { return }
    $cleanupComplete = $false
    $cleanupError = $null
    try {
        Register-GiteaLifecycleE2EOwnedContainers
        foreach ($containerId in @($state.OwnedContainers.Keys)) {
            $expected = $state.OwnedContainers[$containerId]
            $container = Get-GiteaLifecycleE2EContainer -ContainerId ([string]$containerId)
            $kind = Get-GiteaLifecycleE2EOwnedContainerKind -Container $container
            if ([string]$container.Id -ne [string]$expected.id -or [string]$kind -ne [string]$expected.kind) {
                throw "A fixture container no longer matches its recorded test-owned identity; refusing to remove it."
            }
            Invoke-GiteaLifecycleE2EDocker -Arguments @("rm", "-f", [string]$expected.id) -Stage "remove verified disposable fixture container" | Out-Null
            $state.OwnedContainers.Remove([string]$containerId)
        }

        $networkJson = Invoke-GiteaLifecycleE2EDocker -Arguments @("network", "inspect", $state.NetworkName, "--format", "{{json .}}") -AllowFailure
        if ($script:dockerE2ELastExitCode -eq 0) {
            $network = $networkJson | ConvertFrom-Json
            if ([string]$network.Labels.'agent-sdlc.lifecycle-e2e.run-id' -ne [string]$state.RunId -or
                ($state.NetworkId -and [string]$network.Id -ne [string]$state.NetworkId)) {
                throw "The Docker E2E network identity changed; refusing to remove an unverified network."
            }
            $attachedIds = @($network.Containers.PSObject.Properties.Name | Where-Object { $_ })
            if ($attachedIds.Count -gt 0) {
                throw "The isolated Docker E2E network has attached containers without a confirmed test-owned identity; refusing network and data cleanup."
            }
            Invoke-GiteaLifecycleE2EDocker -Arguments @("network", "rm", [string]$network.Id) -Stage "remove verified isolated fixture network" | Out-Null
            $state.NetworkCreated = $false
            $state.NetworkId = $null
        }
        elseif ($state.NetworkCreated) {
            throw "Could not confirm whether the isolated Docker E2E network was removed."
        }

        $rootExpected = Join-Path ([System.IO.Path]::GetFullPath($env:TEMP)) $state.Prefix
        if (-not (Test-GiteaLifecycleE2EPathEqual -Left $state.TestRoot -Right $rootExpected) -or
            [string]([System.IO.Path]::GetFileName($state.TestRoot)) -ne [string]$state.Prefix) {
            throw "The Docker E2E fixture directory is outside its expected unique temp path; refusing filesystem cleanup."
        }
        if ($state.TestRootCreated -and (Test-Path -LiteralPath $state.TestRoot)) {
            if (-not (Test-Path -LiteralPath $state.OwnershipMarkerPath -PathType Leaf)) {
                throw "The Docker E2E fixture ownership marker is missing; refusing filesystem cleanup."
            }
            $owner = Get-Content -LiteralPath $state.OwnershipMarkerPath -Raw | ConvertFrom-Json
            if ([string]$owner.runId -ne [string]$state.RunId -or [string]$owner.prefix -ne [string]$state.Prefix) {
                throw "The Docker E2E fixture ownership marker does not match this run; refusing filesystem cleanup."
            }
            Remove-Item -LiteralPath $state.TestRoot -Recurse -Force -ErrorAction Stop
            $state.TestRootCreated = $false
        }
        $cleanupComplete = $true
    }
    catch {
        $cleanupError = $_.Exception.Message
    }
    finally {
        if (-not $cleanupComplete) {
            Write-Warning "Docker cleanup could not be confirmed. Fixture data is preserved at '$($state.TestRoot)' for manual cleanup."
        }
        try {
            Assert-GiteaLifecycleE2EContainerSnapshot -Expected $state.ExistingContainers
        }
        catch {
            if ($cleanupError) { $cleanupError += " Existing-container snapshot check also failed: $($_.Exception.Message)" }
            else { $cleanupError = "Existing-container snapshot check failed: $($_.Exception.Message)" }
        }
    }
    if ($cleanupComplete) { $state.CleanupComplete = $true }
    if ($cleanupError) {
        throw "Docker E2E cleanup failed: $cleanupError"
    }
}
