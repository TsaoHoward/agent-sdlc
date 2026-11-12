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

function ConvertTo-GiteaLifecycleE2EArgumentString {
    param([string[]]$Arguments)

    $quoted = foreach ($argument in $Arguments) {
        if ($null -eq $argument) { $argument = "" }
        if ($argument.Length -gt 0 -and $argument -notmatch '[\s"]') {
            $argument
            continue
        }
        $builder = New-Object System.Text.StringBuilder
        [void]$builder.Append('"')
        $backslashes = 0
        foreach ($character in $argument.ToCharArray()) {
            if ($character -eq [char]92) { $backslashes += 1; continue }
            if ($character -eq [char]34) {
                if ($backslashes -gt 0) { [void]$builder.Append(('\' * ($backslashes * 2))) }
                [void]$builder.Append('\"')
                $backslashes = 0
                continue
            }
            if ($backslashes -gt 0) { [void]$builder.Append(('\' * $backslashes)); $backslashes = 0 }
            [void]$builder.Append($character)
        }
        if ($backslashes -gt 0) { [void]$builder.Append(('\' * ($backslashes * 2))) }
        [void]$builder.Append('"')
        $builder.ToString()
    }
    return [string]::Join(" ", $quoted)
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
                if ($fixtureName -match "-runner$") { return "start the real disposable host-label Runner fixture" }
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

function Get-GiteaLifecycleE2ERunnerFixtureMounts {
    param([Parameter(Mandatory = $true)][hashtable]$State)

    $expectedRunnerDataPath = Join-Path $State.TestRoot "volumes\runner-data"
    $expectedSocketPlaceholderPath = Join-Path $State.TestRoot "volumes\runner-docker-socket"
    if (-not (Test-GiteaLifecycleE2EPathEqual -Left ([string]$State.RunnerDataPath) -Right $expectedRunnerDataPath) -or
        -not (Test-GiteaLifecycleE2EPathEqual -Left ([string]$State.RunnerSocketPlaceholderPath) -Right $expectedSocketPlaceholderPath)) {
        throw "Runner bind mounts must stay under this GUID-owned fixture's exact volume paths."
    }

    return [string[]]@(
        "type=bind,source=$($State.RunnerDataPath),target=/data",
        "type=bind,source=$($State.RunnerSocketPlaceholderPath),target=/var/run/docker.sock,readonly"
    )
}

function Assert-GiteaLifecycleE2ENoAnonymousVolumes {
    param([Parameter(Mandatory = $true)][string]$ContainerName)

    $container = Get-GiteaLifecycleE2EContainer -ContainerId $ContainerName
    $declaredPaths = @()
    if ($container.Config.Volumes) { $declaredPaths = @($container.Config.Volumes.PSObject.Properties.Name) }
    $mounts = @($container.Mounts)
    foreach ($declaredPath in $declaredPaths) {
        $matchingMounts = @($mounts | Where-Object { [string]$_.Destination -ceq [string]$declaredPath })
        if ($matchingMounts.Count -ne 1 -or [string]$matchingMounts[0].Type -cne "bind") {
            throw "Fixture container '$ContainerName' has an image-declared volume without exactly one owned bind mount at '$declaredPath'; fixture cleanup is blocked."
        }
        if ([string]$declaredPath -ceq "/var/run/docker.sock" -and
            (-not $script:dockerE2EState -or
                [string]::IsNullOrWhiteSpace([string]$script:dockerE2EState.RunnerSocketPlaceholderPath) -or
                [bool]$matchingMounts[0].RW -or
                -not (Test-GiteaLifecycleE2EPathEqual -Left ([string]$matchingMounts[0].Source) -Right ([string]$script:dockerE2EState.RunnerSocketPlaceholderPath)))) {
            throw "Fixture Runner Docker socket volume is not bound to its GUID-owned placeholder; fixture cleanup is blocked."
        }
    }
    if (@($mounts | Where-Object { [string]$_.Type -ceq "volume" }).Count -gt 0) {
        throw "Fixture container '$ContainerName' has a Docker volume outside the GUID-owned fixture tree; fixture cleanup is blocked."
    }
    return $container
}

function Invoke-GiteaLifecycleE2EUpgradeWithDetachedTargetFault {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$GiteaVersion,
        [Parameter(Mandatory = $true)][string]$ModulePath,
        [Parameter(Mandatory = $true)][string]$FixtureGiteaName,
        [Parameter(Mandatory = $true)][string]$FixtureNetworkName,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds = 300
    )

    $markerPath = Join-Path $Context.RepoRoot ".agent-sdlc\dev-env\gitea\lifecycle-recovery.json"
    $job = Start-Job -ScriptBlock {
        param($LifecycleContext, $TargetVersion, $LifecycleModulePath)
        Import-Module $LifecycleModulePath -Force -ErrorAction Stop
        function Read-Host {
            param([string]$Prompt)
            $confirmation = "UPGRADE $TargetVersion ON agent-sdlc-gitea:43000"
            if ($Prompt -like "*UPGRADE $TargetVersion ON agent-sdlc-gitea:43000*") { return $confirmation }
            throw "Unexpected lifecycle prompt in the isolated E2E child process."
        }
        try {
            Invoke-GiteaLifecycle -Action upgrade -Context $LifecycleContext -GiteaVersion $TargetVersion
            return [pscustomobject]@{ Result = "completed"; Error = "" }
        }
        catch {
            return [pscustomobject]@{ Result = "failed"; Error = [string]$_.Exception.Message }
        }
    } -ArgumentList @($Context, $GiteaVersion, $ModulePath)

    $faultInjected = $false
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline -and $job.State -eq "Running") {
        if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
            try {
                $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json -ErrorAction Stop
                if ([string]$marker.operationKind -eq "upgrade" -and [string]$marker.nextAction -eq "create-and-start-target") {
                    $target = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $FixtureGiteaName, "--format", "{{.Id}}") -AllowFailure
                    if ($script:dockerE2ELastExitCode -eq 0 -and [string]$target -and [string]$target -cne [string]$marker.giteaContainerId) {
                        Invoke-GiteaLifecycleE2EDocker -Arguments @("network", "disconnect", "--force", $FixtureNetworkName, $FixtureGiteaName) -Stage "inject a real Docker network fault into the disposable target" | Out-Null
                        $faultInjected = $true
                        break
                    }
                }
            }
            catch {
                if ($faultInjected) { throw }
            }
        }
        Start-Sleep -Milliseconds 100
    }

    if ($faultInjected) {
        Wait-Job -Job $job -Timeout $TimeoutSeconds | Out-Null
    }
    elseif ($job.State -eq "Running") {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
    }
    $result = Receive-Job -Job $job -ErrorAction SilentlyContinue | Where-Object { $_.PSObject.Properties["Result"] } | Select-Object -Last 1
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{
        FaultInjected = $faultInjected
        Result = if ($result) { [string]$result.Result } else { "no-result" }
        Error = if ($result) { [string]$result.Error } else { "" }
        MarkerPath = $markerPath
    }
}

function Invoke-GiteaLifecycleE2EUpgradeWithReservedRenameFault {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$GiteaVersion,
        [Parameter(Mandatory = $true)][string]$ModulePath,
        [Parameter(Mandatory = $true)][string]$FixtureGiteaName,
        [Parameter(Mandatory = $true)][string]$FixtureNetworkName,
        [Parameter(Mandatory = $true)][string]$FixtureRunId,
        [Parameter(Mandatory = $true)][string]$GiteaDataPath,
        [Parameter(Mandatory = $true)][string]$GiteaConfigPath,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds = 300
    )

    $markerPath = Join-Path $Context.RepoRoot ".agent-sdlc\dev-env\gitea\lifecycle-recovery.json"
    $sourceImageReference = [string](Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $FixtureGiteaName, "--format", "{{.Config.Image}}"))
    $job = Start-Job -ScriptBlock {
        param($LifecycleContext, $TargetVersion, $LifecycleModulePath)
        Import-Module $LifecycleModulePath -Force -ErrorAction Stop
        function Read-Host {
            param([string]$Prompt)
            $confirmation = "UPGRADE $TargetVersion ON agent-sdlc-gitea:43000"
            if ($Prompt -like "*UPGRADE $TargetVersion ON agent-sdlc-gitea:43000*") { return $confirmation }
            throw "Unexpected lifecycle prompt in the isolated E2E child process."
        }
        try {
            Invoke-GiteaLifecycle -Action upgrade -Context $LifecycleContext -GiteaVersion $TargetVersion
            return [pscustomobject]@{ Result = "completed"; Error = "" }
        }
        catch {
            return [pscustomobject]@{ Result = "failed"; Error = [string]$_.Exception.Message }
        }
    } -ArgumentList @($Context, $GiteaVersion, $ModulePath)

    $faultInjected = $false
    $blockerName = $null
    $blockerId = $null
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline -and $job.State -eq "Running") {
        if (-not $faultInjected -and (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
            try {
                $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json -ErrorAction Stop
                if ([string]$marker.operationKind -eq "upgrade" -and
                    [string]$marker.phase -in @("upgrade-prepared", "backup-in-progress", "backup-verified") -and
                    [string]$marker.backupId -match '^\d{8}T\d{6}Z-[0-9a-f]{32}$') {
                    $blockerName = "$FixtureGiteaName-preupgrade-$($marker.backupId)"
                    $createdId = Invoke-GiteaLifecycleE2EDocker -Arguments @(
                        "create", "--name", $blockerName,
                        "--network", $FixtureNetworkName,
                        "--label", "agent-sdlc.lifecycle-e2e.run-id=$FixtureRunId",
                        "--mount", "type=bind,source=$GiteaDataPath,target=/var/lib/gitea",
                        "--mount", "type=bind,source=$GiteaConfigPath,target=/etc/gitea",
                        $sourceImageReference
                    ) -Stage "reserve the disposable pre-upgrade container name to fail the real Docker rename" -AllowFailure
                    if ($script:dockerE2ELastExitCode -eq 0) {
                        $blockerId = [string](@($createdId)[0]).Trim()
                        $faultInjected = $true
                    }
                    else {
                        $existing = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $blockerName, "--format", "{{.Id}}|{{.State.Status}}|{{.Config.Labels.agent-sdlc.lifecycle-e2e.run-id}}") -AllowFailure
                        if ($script:dockerE2ELastExitCode -eq 0) {
                            $parts = [string]$existing -split '\|'
                            if ($parts.Count -eq 3 -and $parts[1] -ceq "created" -and $parts[2] -ceq $FixtureRunId) {
                                $blockerId = $parts[0]
                                $faultInjected = $true
                            }
                        }
                    }
                }
            }
            catch {
                if ($faultInjected) { throw }
            }
        }
        Start-Sleep -Milliseconds 100
    }

    if ($faultInjected) {
        Wait-Job -Job $job -Timeout $TimeoutSeconds | Out-Null
    }
    elseif ($job.State -eq "Running") {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
    }
    if ($job.State -eq "Running") {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
    }
    $result = Receive-Job -Job $job -ErrorAction SilentlyContinue | Where-Object { $_.PSObject.Properties["Result"] } | Select-Object -Last 1
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{
        FaultInjected = $faultInjected
        BlockerName = $blockerName
        BlockerId = $blockerId
        Result = if ($result) { [string]$result.Result } else { "no-result" }
        Error = if ($result) { [string]$result.Error } else { "" }
        MarkerPath = $markerPath
    }
}

function Get-GiteaLifecycleE2EFreshProcessStatus {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$ModulePath
    )

    $job = Start-Job -ScriptBlock {
        param($LifecycleContext, $LifecycleModulePath)
        Import-Module $LifecycleModulePath -Force -ErrorAction Stop
        Get-GiteaLifecycleStatus -Context $LifecycleContext
    } -ArgumentList @($Context, $ModulePath)
    try {
        Wait-Job -Job $job -Timeout 30 | Out-Null
        if ($job.State -eq "Running") {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            throw "A new PowerShell process did not reload the isolated Recovery Marker within 30 seconds."
        }
        $status = Receive-Job -Job $job -ErrorAction Stop | Select-Object -Last 1
        if (-not $status) { throw "A new PowerShell process returned no lifecycle status evidence." }
        return $status
    }
    finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
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
        $runnerMounts = @($Container.Mounts)
        $runnerDataMount = @($runnerMounts | Where-Object { [string]$_.Destination -ceq "/data" -and [string]$_.Type -ceq "bind" })
        $runnerSocketMount = @($runnerMounts | Where-Object { [string]$_.Destination -ceq "/var/run/docker.sock" -and [string]$_.Type -ceq "bind" })
        if ($runnerMounts.Count -eq 2 -and $runnerDataMount.Count -eq 1 -and $runnerSocketMount.Count -eq 1 -and
            (Test-GiteaLifecycleE2EPathEqual -Left ([string]$runnerDataMount[0].Source) -Right ([string]$state.RunnerDataPath)) -and
            -not [bool]$runnerSocketMount[0].RW -and
            (Test-GiteaLifecycleE2EPathEqual -Left ([string]$runnerSocketMount[0].Source) -Right ([string]$state.RunnerSocketPlaceholderPath))) {
            return "runner"
        }
        return $null
    }

    $giteaNamePattern = "^{0}(?:-(?:preupgrade|failed)-[A-Za-z0-9T-]+)?$" -f [Regex]::Escape([string]$state.GiteaName)
    $onlyOnFixtureOrDetached = $isOnFixtureNetwork -or $networkNames.Count -eq 0
    if ($name -match $giteaNamePattern -and $runIdLabel -eq [string]$state.RunId -and $onlyOnFixtureOrDetached) {
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
        elseif ($container.Config.Labels -and
            [string]$container.Config.Labels.'agent-sdlc.lifecycle-e2e.run-id' -ceq [string]$state.RunId) {
            throw "A run-labeled Docker E2E container does not match a verified fixture identity; refusing cleanup."
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
    $runnerDataPath = Join-Path $testRoot "volumes\runner-data"
    $runnerSocketPlaceholderPath = Join-Path $testRoot "volumes\runner-docker-socket"
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
        RunnerDataPath = $runnerDataPath
        RunnerSocketPlaceholderPath = $runnerSocketPlaceholderPath
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
    New-Item -ItemType Directory -Path @($repoRoot, $dataPath, $configPath, $postgresPath, $runnerDataPath, $runnerSocketPlaceholderPath, $backupRoot) -Force -ErrorAction Stop | Out-Null
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
            GiteaLifecycleE2ERunId = $runId
    }

    Invoke-GiteaLifecycleE2EDocker -Arguments @("pull", "postgres:16") -Stage "pull disposable PostgreSQL fixture image" | Out-Null
    $runnerImage = "docker.io/gitea/act_runner:0.2.13"
    Invoke-GiteaLifecycleE2EDocker -Arguments @("pull", $runnerImage) -Stage "pull pinned Gitea Runner fixture image" | Out-Null
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
    [void](Assert-GiteaLifecycleE2ENoAnonymousVolumes -ContainerName $postgresName)
    Wait-GiteaLifecycleE2EPostgres -ContainerName $postgresName -DatabasePassword $dbPassword
    Invoke-GiteaLifecycleE2EPsql -ContainerName $postgresName -DatabaseName "postgres" -Sql "CREATE DATABASE e2e_unrelated" | Out-Null
    Invoke-GiteaLifecycleE2EPsql -ContainerName $postgresName -DatabaseName "e2e_unrelated" -Sql "CREATE TABLE public.restore_sentinel (value text NOT NULL); INSERT INTO public.restore_sentinel (value) VALUES ('preserve-me')" | Out-Null

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
    [void](Assert-GiteaLifecycleE2ENoAnonymousVolumes -ContainerName $giteaName)

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

    $runnerToken = [string](Invoke-GiteaLifecycleE2EDocker -Arguments @("exec", $giteaName, "gitea", "actions", "generate-runner-token") -Stage "generate a disposable Runner registration token" | Select-Object -First 1)
    if (-not $runnerToken -or $runnerToken -match "\s") {
        throw "Gitea did not return one valid Runner registration token; fixture setup stopped before starting the Runner."
    }
    $runnerMounts = @(Get-GiteaLifecycleE2ERunnerFixtureMounts -State $script:dockerE2EState)
    $runnerArguments = @(
        "run", "-d", "--name", $runnerName, "--network", $networkName, "--restart", "unless-stopped",
        "--label", "agent-sdlc.lifecycle-e2e.run-id=$runId"
    )
    foreach ($runnerMount in $runnerMounts) {
        $runnerArguments += @("--mount", $runnerMount)
    }
    $runnerArguments += @(
        "-e", "GITEA_INSTANCE_URL=http://$giteaName:3000/",
        "-e", "GITEA_RUNNER_REGISTRATION_TOKEN=$runnerToken",
        "-e", "GITEA_RUNNER_NAME=$runnerName",
        "-e", "GITEA_RUNNER_LABELS=agent-sdlc-host:host",
        $runnerImage
    )
    Invoke-GiteaLifecycleE2EDocker -Stage "start real host-label disposable Runner fixture" -Arguments $runnerArguments | Out-Null
    [void](Assert-GiteaLifecycleE2ENoAnonymousVolumes -ContainerName $runnerName)
    $script:dockerE2EState.RunnerContainerId = Invoke-GiteaLifecycleE2EDocker -Arguments @("inspect", $runnerName, "--format", "{{.Id}}")
    $runnerApi = $null
    for ($attempt = 0; $attempt -lt 60 -and -not $runnerApi; $attempt += 1) {
        try {
            $runnerApi = Invoke-RestMethod -Uri ($giteaUrl + "api/v1/admin/actions/runners") -Method Get -Headers $headers -TimeoutSec 10
            if (-not @($runnerApi.runners | Where-Object { [string]$_.name -ceq $runnerName }).Count) { $runnerApi = $null }
        }
        catch { $runnerApi = $null }
        if (-not $runnerApi) { Start-Sleep -Seconds 2 }
    }
    if (-not $runnerApi) {
        throw "The real isolated host-label Runner did not register through Gitea's admin Runner API."
    }

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
        $verifiedContainers = @()
        foreach ($containerId in @($state.OwnedContainers.Keys)) {
            $expected = $state.OwnedContainers[$containerId]
            $container = Get-GiteaLifecycleE2EContainer -ContainerId ([string]$containerId)
            $kind = Get-GiteaLifecycleE2EOwnedContainerKind -Container $container
            if ([string]$container.Id -ne [string]$expected.id -or [string]$kind -ne [string]$expected.kind) {
                throw "A fixture container no longer matches its recorded test-owned identity; refusing to remove it."
            }
            [void](Assert-GiteaLifecycleE2ENoAnonymousVolumes -ContainerName ([string]$container.Name).TrimStart('/'))
            $verifiedContainers += [pscustomobject]@{ ContainerId = [string]$expected.id }
        }

        foreach ($verifiedContainer in $verifiedContainers) {
            Invoke-GiteaLifecycleE2EDocker -Arguments @("rm", "-f", [string]$verifiedContainer.ContainerId) -Stage "remove verified disposable fixture container" | Out-Null
            $containerId = [string]$verifiedContainer.ContainerId
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

        if ($state.TestRootCreated) {
            Remove-GiteaLifecycleE2EFixtureDirectory `
                -RunId $state.RunId `
                -ExpectedPath $state.TestRoot `
                -ApproveRunId $state.RunId `
                -Confirm:$false
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
