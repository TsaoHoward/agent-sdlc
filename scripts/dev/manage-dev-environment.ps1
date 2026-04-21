[CmdletBinding()]
param(
    [ValidateSet("init", "up", "down", "status")]
    [string]$Command = "status",

    [string]$ConfigPath,

    [string]$GiteaDatabaseMode,

    [switch]$SkipGitea
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $RepoRoot "config\dev\gitea-bootstrap.json"
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Bootstrap config file was not found at '$ConfigPath'."
}

$BootstrapConfig = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

$ProjectStateRoot = Join-Path $RepoRoot ".agent-sdlc"
$StateRoot = Join-Path $ProjectStateRoot "state"
$TaskRequestStateDir = Join-Path $StateRoot "task-requests"
$AgentSessionStateDir = Join-Path $StateRoot "agent-sessions"
$TraceabilityDir = Join-Path $ProjectStateRoot "traceability"
$DevEnvRoot = Join-Path $ProjectStateRoot "dev-env"
$GiteaRoot = Join-Path $DevEnvRoot "gitea"
$ControlHostRoot = Join-Path $DevEnvRoot "control-host"
$ControlHostLogDir = Join-Path $ControlHostRoot "logs"
$ControlHostServiceDir = Join-Path $ControlHostRoot "services"
$GiteaDataDir = Join-Path $GiteaRoot "data"
$GiteaConfigDir = Join-Path $GiteaRoot "config"
$GiteaPostgresDataDir = Join-Path $GiteaRoot "postgres-data"
$GiteaSecretsPath = Join-Path $GiteaRoot "generated-secrets.json"
$GiteaBootstrapSummaryPath = Join-Path $GiteaRoot "bootstrap-summary.json"
$EffectiveBootstrapSettingsPath = Join-Path $GiteaRoot "effective-settings.json"

$DockerDesktopPath = if ($env:AGENT_SDLC_DOCKER_DESKTOP_PATH) {
    $env:AGENT_SDLC_DOCKER_DESKTOP_PATH
} elseif ($BootstrapConfig.dockerDesktop.path) {
    [string]$BootstrapConfig.dockerDesktop.path
} else {
    "C:\Program Files\Docker\Docker\Docker Desktop.exe"
}

$DockerDesktopStartupTimeoutSeconds = if ($env:AGENT_SDLC_DOCKER_START_TIMEOUT_SECONDS) {
    [int]$env:AGENT_SDLC_DOCKER_START_TIMEOUT_SECONDS
} elseif ($BootstrapConfig.dockerDesktop.startupTimeoutSeconds) {
    [int]$BootstrapConfig.dockerDesktop.startupTimeoutSeconds
} else {
    90
}

$PortBindAddress = if ($BootstrapConfig.ports.bindAddress) { [string]$BootstrapConfig.ports.bindAddress } else { "127.0.0.1" }
$GiteaHttpPort = if ($env:AGENT_SDLC_GITEA_HTTP_PORT) {
    [int]$env:AGENT_SDLC_GITEA_HTTP_PORT
} else {
    [int]$BootstrapConfig.ports.giteaHttpHost
}
$GiteaSshPort = if ($env:AGENT_SDLC_GITEA_SSH_PORT) {
    [int]$env:AGENT_SDLC_GITEA_SSH_PORT
} else {
    [int]$BootstrapConfig.ports.giteaSshHost
}
$GiteaPostgresHostPort = if ($env:AGENT_SDLC_GITEA_POSTGRES_PORT) {
    [int]$env:AGENT_SDLC_GITEA_POSTGRES_PORT
} else {
    [int]$BootstrapConfig.ports.postgresHost
}

$GiteaContainerName = "agent-sdlc-gitea"
$GiteaPostgresContainerName = "agent-sdlc-gitea-db"
$GiteaNetworkName = "agent-sdlc-gitea-network"
$GiteaImage = if ($env:AGENT_SDLC_GITEA_IMAGE) {
    $env:AGENT_SDLC_GITEA_IMAGE
} else {
    [string]$BootstrapConfig.gitea.image
}
$GiteaHostName = if ($BootstrapConfig.gitea.hostName) { [string]$BootstrapConfig.gitea.hostName } else { "localhost" }
$GiteaRootUrl = if ($BootstrapConfig.gitea.rootUrl) { [string]$BootstrapConfig.gitea.rootUrl } else { "http://$GiteaHostName`:$GiteaHttpPort/" }
$GiteaWebhookAllowedHostList = if ($BootstrapConfig.gitea.webhook.allowedHostList) {
    [string]$BootstrapConfig.gitea.webhook.allowedHostList
} else {
    "external,private"
}
$GiteaAppName = if ($BootstrapConfig.gitea.appName) { [string]$BootstrapConfig.gitea.appName } else { "Agent SDLC Dev Forge" }
$GiteaInstallLock = if ($null -ne $BootstrapConfig.gitea.installLock) { [bool]$BootstrapConfig.gitea.installLock } else { $true }
$GiteaDisableRegistration = if ($null -ne $BootstrapConfig.gitea.disableRegistration) { [bool]$BootstrapConfig.gitea.disableRegistration } else { $true }
$GiteaRequireSignInView = if ($null -ne $BootstrapConfig.gitea.requireSignInView) { [bool]$BootstrapConfig.gitea.requireSignInView } else { $false }
$GiteaEnableActions = if ($null -ne $BootstrapConfig.gitea.enableActions) { [bool]$BootstrapConfig.gitea.enableActions } else { $true }
$GiteaDefaultBranch = if ($BootstrapConfig.gitea.defaultBranch) { [string]$BootstrapConfig.gitea.defaultBranch } else { "main" }
$GiteaUserUid = if ($null -ne $BootstrapConfig.gitea.userUid) { [int]$BootstrapConfig.gitea.userUid } else { 1000 }
$GiteaUserGid = if ($null -ne $BootstrapConfig.gitea.userGid) { [int]$BootstrapConfig.gitea.userGid } else { 1000 }
$GiteaAdminUsername = [string]$BootstrapConfig.gitea.admin.username
$GiteaAdminPassword = [string]$BootstrapConfig.gitea.admin.password
$GiteaAdminEmail = [string]$BootstrapConfig.gitea.admin.email
$GiteaAdminMustChangePassword = if ($null -ne $BootstrapConfig.gitea.admin.mustChangePassword) { [bool]$BootstrapConfig.gitea.admin.mustChangePassword } else { $false }
$GiteaDatabaseMode = if ($GiteaDatabaseMode) { $GiteaDatabaseMode } elseif ($env:AGENT_SDLC_GITEA_DB_MODE) { $env:AGENT_SDLC_GITEA_DB_MODE } else { [string]$BootstrapConfig.gitea.databaseMode }

$LocalRepoEnsureOnBootstrap = if ($null -ne $BootstrapConfig.localRepo.ensureOnBootstrap) { [bool]$BootstrapConfig.localRepo.ensureOnBootstrap } else { $false }
$LocalRepoOwner = if ($BootstrapConfig.localRepo.owner) { [string]$BootstrapConfig.localRepo.owner } else { "" }
$LocalRepoName = if ($BootstrapConfig.localRepo.repo) { [string]$BootstrapConfig.localRepo.repo } else { "" }
$LocalRepoSeedFrom = if ($BootstrapConfig.localRepo.seedFrom) { [string]$BootstrapConfig.localRepo.seedFrom } else { "" }

$ControlHostCallbackScheme = if ($BootstrapConfig.controlHost.callbackScheme) { [string]$BootstrapConfig.controlHost.callbackScheme } else { "http" }
$ControlHostCallbackHost = if ($BootstrapConfig.controlHost.callbackHost) { [string]$BootstrapConfig.controlHost.callbackHost } else { "host.docker.internal" }
$IssueCommentWebhookEnabled = if ($null -ne $BootstrapConfig.controlHost.issueCommentWebhook.enabled) { [bool]$BootstrapConfig.controlHost.issueCommentWebhook.enabled } else { $true }
$IssueCommentWebhookHost = if ($BootstrapConfig.controlHost.issueCommentWebhook.host) { [string]$BootstrapConfig.controlHost.issueCommentWebhook.host } else { "0.0.0.0" }
$IssueCommentWebhookPort = if ($BootstrapConfig.controlHost.issueCommentWebhook.port) { [int]$BootstrapConfig.controlHost.issueCommentWebhook.port } else { 4010 }
$IssueCommentWebhookRoute = if ($BootstrapConfig.controlHost.issueCommentWebhook.route) { [string]$BootstrapConfig.controlHost.issueCommentWebhook.route } else { "/hooks/gitea/issue-comment" }
$IssueCommentWebhookAutoStartSession = if ($null -ne $BootstrapConfig.controlHost.issueCommentWebhook.autoStartSession) { [bool]$BootstrapConfig.controlHost.issueCommentWebhook.autoStartSession } else { $true }
$ReviewWebhookEnabled = if ($null -ne $BootstrapConfig.controlHost.reviewWebhook.enabled) { [bool]$BootstrapConfig.controlHost.reviewWebhook.enabled } else { $true }
$ReviewWebhookHost = if ($BootstrapConfig.controlHost.reviewWebhook.host) { [string]$BootstrapConfig.controlHost.reviewWebhook.host } else { "0.0.0.0" }
$ReviewWebhookPort = if ($BootstrapConfig.controlHost.reviewWebhook.port) { [int]$BootstrapConfig.controlHost.reviewWebhook.port } else { 4011 }
$ReviewWebhookRoute = if ($BootstrapConfig.controlHost.reviewWebhook.route) { [string]$BootstrapConfig.controlHost.reviewWebhook.route } else { "/hooks/gitea/pull-request-review" }
$IssueCommentWebhookHealthUrl = "${ControlHostCallbackScheme}://127.0.0.1:${IssueCommentWebhookPort}${IssueCommentWebhookRoute}"
$ReviewWebhookHealthUrl = "${ControlHostCallbackScheme}://127.0.0.1:${ReviewWebhookPort}${ReviewWebhookRoute}"
$IssueCommentWebhookCallbackUrl = "${ControlHostCallbackScheme}://${ControlHostCallbackHost}:${IssueCommentWebhookPort}${IssueCommentWebhookRoute}"
$ReviewWebhookCallbackUrl = "${ControlHostCallbackScheme}://${ControlHostCallbackHost}:${ReviewWebhookPort}${ReviewWebhookRoute}"
$TaskGatewayServiceStatePath = Join-Path $ControlHostServiceDir "task-gateway-webhook.json"
$ReviewSurfaceServiceStatePath = Join-Path $ControlHostServiceDir "review-surface-webhook.json"

if ($GiteaDatabaseMode -notin @("postgres", "sqlite")) {
    throw "Unsupported Gitea database mode '$GiteaDatabaseMode'. Supported values: postgres, sqlite."
}

$GiteaPostgresImage = if ($env:AGENT_SDLC_GITEA_POSTGRES_IMAGE) {
    $env:AGENT_SDLC_GITEA_POSTGRES_IMAGE
} else {
    [string]$BootstrapConfig.postgres.image
}
$GiteaPostgresDbName = if ($env:AGENT_SDLC_GITEA_POSTGRES_DB) {
    $env:AGENT_SDLC_GITEA_POSTGRES_DB
} else {
    [string]$BootstrapConfig.postgres.database
}
$GiteaPostgresUser = if ($env:AGENT_SDLC_GITEA_POSTGRES_USER) {
    $env:AGENT_SDLC_GITEA_POSTGRES_USER
} else {
    [string]$BootstrapConfig.postgres.user
}
$GiteaPostgresPassword = if ($env:AGENT_SDLC_GITEA_POSTGRES_PASSWORD) {
    $env:AGENT_SDLC_GITEA_POSTGRES_PASSWORD
} else {
    [string]$BootstrapConfig.postgres.password
}

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Save-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $Path -Value $json
}

function Get-NodeExecutable {
    $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
    if (-not $nodeCommand) {
        return $null
    }

    return $nodeCommand.Source
}

function Test-ProcessAlive {
    param(
        [Parameter(Mandatory = $true)]
        [int]$ProcessId
    )

    return $null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Read-ServiceState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath
    )

    if (-not (Test-Path -LiteralPath $StatePath)) {
        return $null
    }

    return Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
}

function Remove-ServiceStateIfPresent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath
    )

    if (Test-Path -LiteralPath $StatePath) {
        Remove-Item -LiteralPath $StatePath -Force
    }
}

function Get-WebhookHealthStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -Method Get -UseBasicParsing -TimeoutSec 3
        return $response.StatusCode -ge 200
    }
    catch {
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            return $statusCode -in @(200, 404, 405)
        }

        return $false
    }
}

function Wait-ForWebhookHealth {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Get-WebhookHealthStatus -Url $Url) {
            return
        }

        Start-Sleep -Seconds 1
    }

    throw "Webhook listener at '$Url' did not become reachable within $TimeoutSeconds seconds."
}

function Start-ManagedNodeService {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$StatePath,

        [Parameter(Mandatory = $true)]
        [string]$RelativeScriptPath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$HealthUrl
    )

    Initialize-ProjectState

    $existingState = Read-ServiceState -StatePath $StatePath
    if ($existingState -and (Test-ProcessAlive -ProcessId ([int]$existingState.pid))) {
        if (Get-WebhookHealthStatus -Url $HealthUrl) {
            return $existingState
        }
    }

    Remove-ServiceStateIfPresent -StatePath $StatePath

    $nodeExecutable = Get-NodeExecutable
    if (-not $nodeExecutable) {
        throw "Node.js was not found on PATH. It is required to start the control-host webhook listeners."
    }

    $stdoutPath = Join-Path $ControlHostLogDir "$Name.stdout.log"
    $stderrPath = Join-Path $ControlHostLogDir "$Name.stderr.log"
    $scriptPath = Join-Path $RepoRoot $RelativeScriptPath
    $process = Start-Process -FilePath $nodeExecutable -ArgumentList (@($scriptPath) + $Arguments) -WorkingDirectory $RepoRoot -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru -WindowStyle Hidden

    $serviceState = @{
        name = $Name
        pid = $process.Id
        script = $RelativeScriptPath
        arguments = $Arguments
        healthUrl = $HealthUrl
        stdoutPath = $stdoutPath
        stderrPath = $stderrPath
        startedAt = (Get-Date).ToString("o")
    }
    Save-JsonFile -Path $StatePath -Value $serviceState

    try {
        Wait-ForWebhookHealth -Url $HealthUrl
    }
    catch {
        if (Test-ProcessAlive -ProcessId $process.Id) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }

        $stderrTail = ""
        if (Test-Path -LiteralPath $stderrPath) {
            $stderrTail = Get-Content -LiteralPath $stderrPath -Tail 20 | Out-String
        }

        Remove-ServiceStateIfPresent -StatePath $StatePath
        throw "Failed to start service '$Name'. $($_.Exception.Message) $stderrTail".Trim()
    }

    return $serviceState
}

function Stop-ManagedNodeService {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath
    )

    $serviceState = Read-ServiceState -StatePath $StatePath
    if (-not $serviceState) {
        return
    }

    if ($serviceState.pid -and (Test-ProcessAlive -ProcessId ([int]$serviceState.pid))) {
        Stop-Process -Id ([int]$serviceState.pid) -Force -ErrorAction SilentlyContinue
    }

    Remove-ServiceStateIfPresent -StatePath $StatePath
}

function Get-ManagedNodeServiceStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath,

        [Parameter(Mandatory = $true)]
        [string]$HealthUrl
    )

    $serviceState = Read-ServiceState -StatePath $StatePath
    if (-not $serviceState) {
        return "not-started"
    }

    if (-not $serviceState.pid -or -not (Test-ProcessAlive -ProcessId ([int]$serviceState.pid))) {
        return "stopped"
    }

    if (Get-WebhookHealthStatus -Url $HealthUrl) {
        return "running"
    }

    return "degraded"
}

function Ensure-ControlHostWebhookServices {
    if ($IssueCommentWebhookEnabled) {
        $taskGatewayArguments = @(
            (Join-Path "scripts" "task-gateway.js"),
            "serve-gitea-webhook",
            "--host", $IssueCommentWebhookHost,
            "--port", [string]$IssueCommentWebhookPort,
            "--route", $IssueCommentWebhookRoute
        )

        if (-not $IssueCommentWebhookAutoStartSession) {
            $taskGatewayArguments += "--no-auto-start-session"
        }

        Start-ManagedNodeService -Name "task-gateway-webhook" -StatePath $TaskGatewayServiceStatePath -RelativeScriptPath (Join-Path "scripts" "task-gateway.js") -Arguments $taskGatewayArguments[1..($taskGatewayArguments.Length - 1)] -HealthUrl $IssueCommentWebhookHealthUrl | Out-Null
    }

    if ($ReviewWebhookEnabled) {
        $reviewArguments = @(
            "serve-gitea-review-webhook",
            "--host", $ReviewWebhookHost,
            "--port", [string]$ReviewWebhookPort,
            "--route", $ReviewWebhookRoute
        )

        Start-ManagedNodeService -Name "review-surface-webhook" -StatePath $ReviewSurfaceServiceStatePath -RelativeScriptPath (Join-Path "scripts" "review-surface.js") -Arguments $reviewArguments -HealthUrl $ReviewWebhookHealthUrl | Out-Null
    }
}

function Stop-ControlHostWebhookServices {
    Stop-ManagedNodeService -StatePath $TaskGatewayServiceStatePath
    Stop-ManagedNodeService -StatePath $ReviewSurfaceServiceStatePath
}

function Ensure-DefaultLocalRepoBootstrap {
    if (-not $LocalRepoEnsureOnBootstrap) {
        return
    }

    if (-not $LocalRepoOwner -or -not $LocalRepoName) {
        throw "Bootstrap config localRepo.ensureOnBootstrap is enabled, but owner/repo is incomplete."
    }

    $nodeExecutable = Get-NodeExecutable
    if (-not $nodeExecutable) {
        throw "Node.js was not found on PATH. It is required to bootstrap the default local Gitea repo."
    }

    $repoHelperPath = Join-Path $RepoRoot "scripts\dev\ensure-local-gitea-repo.js"
    $repoHelperArguments = @(
        $repoHelperPath,
        "ensure-local-repo",
        "--owner", $LocalRepoOwner,
        "--repo", $LocalRepoName
    )

    if ($LocalRepoSeedFrom) {
        $seedSource = if ([System.IO.Path]::IsPathRooted($LocalRepoSeedFrom)) {
            $LocalRepoSeedFrom
        }
        else {
            Join-Path $RepoRoot $LocalRepoSeedFrom
        }

        $repoHelperArguments += @("--seed-from", $seedSource)
    }

    $result = & $nodeExecutable @repoHelperArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to bootstrap the default local Gitea repo. $result"
    }
}

function Initialize-ProjectState {
    $paths = @(
        $TaskRequestStateDir,
        $AgentSessionStateDir,
        $TraceabilityDir,
        $ControlHostRoot,
        $ControlHostLogDir,
        $ControlHostServiceDir,
        $GiteaDataDir,
        $GiteaConfigDir,
        $GiteaPostgresDataDir
    )

    foreach ($path in $paths) {
        Ensure-Directory -Path $path
    }

    Save-JsonFile -Path $EffectiveBootstrapSettingsPath -Value @{
        configPath = $ConfigPath
        dockerDesktopPath = $DockerDesktopPath
        dockerDesktopStartupTimeoutSeconds = $DockerDesktopStartupTimeoutSeconds
        bindAddress = $PortBindAddress
        gitea = @{
            image = $GiteaImage
            databaseMode = $GiteaDatabaseMode
            rootUrl = $GiteaRootUrl
            hostName = $GiteaHostName
            webhook = @{
                allowedHostList = $GiteaWebhookAllowedHostList
            }
            httpPort = $GiteaHttpPort
            sshPort = $GiteaSshPort
            appName = $GiteaAppName
            installLock = $GiteaInstallLock
            disableRegistration = $GiteaDisableRegistration
            requireSignInView = $GiteaRequireSignInView
            enableActions = $GiteaEnableActions
            defaultBranch = $GiteaDefaultBranch
            userUid = $GiteaUserUid
            userGid = $GiteaUserGid
            admin = @{
                username = $GiteaAdminUsername
                email = $GiteaAdminEmail
                mustChangePassword = $GiteaAdminMustChangePassword
            }
        }
        localRepo = @{
            ensureOnBootstrap = $LocalRepoEnsureOnBootstrap
            owner = $LocalRepoOwner
            repo = $LocalRepoName
            seedFrom = $LocalRepoSeedFrom
        }
        controlHost = @{
            callbackScheme = $ControlHostCallbackScheme
            callbackHost = $ControlHostCallbackHost
            issueCommentWebhook = @{
                enabled = $IssueCommentWebhookEnabled
                host = $IssueCommentWebhookHost
                port = $IssueCommentWebhookPort
                route = $IssueCommentWebhookRoute
                callbackUrl = $IssueCommentWebhookCallbackUrl
                autoStartSession = $IssueCommentWebhookAutoStartSession
            }
            reviewWebhook = @{
                enabled = $ReviewWebhookEnabled
                host = $ReviewWebhookHost
                port = $ReviewWebhookPort
                route = $ReviewWebhookRoute
                callbackUrl = $ReviewWebhookCallbackUrl
            }
        }
        postgres = @{
            image = $GiteaPostgresImage
            hostPort = $GiteaPostgresHostPort
            database = $GiteaPostgresDbName
            user = $GiteaPostgresUser
        }
    }
}

function Test-DockerCliAvailable {
    return $null -ne (Get-Command docker -ErrorAction SilentlyContinue)
}

function Invoke-DockerProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "docker"
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $quotedArguments = foreach ($argument in $Arguments) {
        if ($argument -match '[\s"]') {
            '"' + ($argument -replace '"', '\"') + '"'
        }
        else {
            $argument
        }
    }
    $startInfo.Arguments = [string]::Join(" ", $quotedArguments)

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut = $stdout.Trim()
        StdErr = $stderr.Trim()
    }
}

function Test-DockerDaemonReady {
    if (-not (Test-DockerCliAvailable)) {
        return $false
    }

    $result = Invoke-DockerProcess -Arguments @("info")
    return $result.ExitCode -eq 0
}

function Try-StartDockerDesktop {
    if (Test-DockerDaemonReady) {
        return $true
    }

    if (-not (Test-Path -LiteralPath $DockerDesktopPath)) {
        return $false
    }

    Write-Host "Docker daemon is not ready. Attempting to start Docker Desktop from '$DockerDesktopPath'."
    Start-Process -FilePath $DockerDesktopPath | Out-Null

    $deadline = (Get-Date).AddSeconds($DockerDesktopStartupTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        if (Test-DockerDaemonReady) {
            Write-Host "Docker Desktop is ready."
            return $true
        }
    }

    return $false
}

function Assert-DockerReady {
    if (-not (Test-DockerCliAvailable)) {
        throw "Docker CLI was not found. Install Docker or use '-Command init' to prepare only the local state directories."
    }

    if (-not (Test-DockerDaemonReady)) {
        $desktopStarted = Try-StartDockerDesktop
        if (-not $desktopStarted) {
            throw "Docker is installed but the daemon is not ready. Start Docker Desktop or another Docker-compatible daemon and try again."
        }
    }
}

function Get-ContainerStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName
    )

    if (-not (Test-DockerDaemonReady)) {
        return $null
    }

    $result = Invoke-DockerProcess -Arguments @("container", "inspect", $ContainerName, "--format", "{{.State.Status}}")
    if ($result.ExitCode -ne 0) {
        return $null
    }

    return $result.StdOut.Trim()
}

function Get-ContainerHealthStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName
    )

    if (-not (Test-DockerDaemonReady)) {
        return $null
    }

    $result = Invoke-DockerProcess -Arguments @("container", "inspect", $ContainerName, "--format", "{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}")
    if ($result.ExitCode -ne 0) {
        return $null
    }

    return $result.StdOut.Trim()
}

function Ensure-DockerNetwork {
    $inspectResult = Invoke-DockerProcess -Arguments @("network", "inspect", $GiteaNetworkName)
    if ($inspectResult.ExitCode -eq 0) {
        return
    }

    & docker network create $GiteaNetworkName | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create Docker network '$GiteaNetworkName'."
    }
}

function Wait-ForContainerHealth {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [int]$TimeoutSeconds = 120
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $status = Get-ContainerStatus -ContainerName $ContainerName
        $health = Get-ContainerHealthStatus -ContainerName $ContainerName

        if ($status -eq "running" -and ($health -eq "healthy" -or $health -eq "none")) {
            return
        }

        Start-Sleep -Seconds 2
    }

    throw "Container '$ContainerName' did not become ready within $TimeoutSeconds seconds."
}

function Invoke-GiteaContainerCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $dockerArguments = @("exec", $GiteaContainerName) + $Arguments
    return Invoke-DockerProcess -Arguments $dockerArguments
}

function New-GiteaGeneratedSecret {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SecretName
    )

    $result = Invoke-DockerProcess -Arguments @("run", "--rm", $GiteaImage, "gitea", "generate", "secret", $SecretName)
    if ($result.ExitCode -ne 0 -or -not $result.StdOut) {
        throw "Failed to generate Gitea secret '$SecretName'. $($result.StdErr)"
    }

    return $result.StdOut
}

function Ensure-GiteaSecrets {
    Assert-DockerReady
    Initialize-ProjectState

    if (Test-Path -LiteralPath $GiteaSecretsPath) {
        return Get-Content -LiteralPath $GiteaSecretsPath -Raw | ConvertFrom-Json
    }

    $secrets = [pscustomobject]@{
        secretKey = New-GiteaGeneratedSecret -SecretName "SECRET_KEY"
        internalToken = New-GiteaGeneratedSecret -SecretName "INTERNAL_TOKEN"
    }

    Save-JsonFile -Path $GiteaSecretsPath -Value $secrets
    return $secrets
}

function Wait-ForGiteaHttp {
    param(
        [int]$TimeoutSeconds = 120
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $GiteaRootUrl -UseBasicParsing -TimeoutSec 5
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                return
            }
        }
        catch {
            Start-Sleep -Seconds 2
            continue
        }
    }

    throw "Gitea did not become reachable at '$GiteaRootUrl' within $TimeoutSeconds seconds."
}

function Start-GiteaPostgresContainer {
    Assert-DockerReady
    Initialize-ProjectState
    Ensure-DockerNetwork

    $existingStatus = Get-ContainerStatus -ContainerName $GiteaPostgresContainerName
    if ($existingStatus -eq "running") {
        Wait-ForContainerHealth -ContainerName $GiteaPostgresContainerName
        Write-Host "Gitea PostgreSQL container '$GiteaPostgresContainerName' is already running."
        return
    }

    if ($existingStatus) {
        & docker start $GiteaPostgresContainerName | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to start existing PostgreSQL container '$GiteaPostgresContainerName'."
        }

        Wait-ForContainerHealth -ContainerName $GiteaPostgresContainerName
        Write-Host "Started existing PostgreSQL container '$GiteaPostgresContainerName'."
        return
    }

    $resolvedPostgresDataDir = (Resolve-Path -LiteralPath $GiteaPostgresDataDir).Path

    $dockerArgs = @(
        "run",
        "-d",
        "--name", $GiteaPostgresContainerName,
        "--restart", "unless-stopped",
        "--network", $GiteaNetworkName,
        "--network-alias", "db",
        "-p", "${PortBindAddress}:${GiteaPostgresHostPort}:5432",
        "-e", "POSTGRES_DB=$GiteaPostgresDbName",
        "-e", "POSTGRES_USER=$GiteaPostgresUser",
        "-e", "POSTGRES_PASSWORD=$GiteaPostgresPassword",
        "--health-cmd", "pg_isready -U $GiteaPostgresUser -d $GiteaPostgresDbName",
        "--health-interval", "5s",
        "--health-timeout", "5s",
        "--health-retries", "20",
        "-v", "${resolvedPostgresDataDir}:/var/lib/postgresql/data",
        $GiteaPostgresImage
    )

    & docker @dockerArgs | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create PostgreSQL container '$GiteaPostgresContainerName'."
    }

    Wait-ForContainerHealth -ContainerName $GiteaPostgresContainerName
    Write-Host "Started new PostgreSQL container '$GiteaPostgresContainerName'."
}

function Get-GiteaEnvironmentVariables {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Secrets
    )

    $variables = @(
        "-e", "USER_UID=$GiteaUserUid",
        "-e", "USER_GID=$GiteaUserGid",
        "-e", "GITEA__DEFAULT__APP_NAME=$GiteaAppName",
        "-e", "GITEA__server__ROOT_URL=$GiteaRootUrl",
        "-e", "GITEA__server__DOMAIN=$GiteaHostName",
        "-e", "GITEA__server__SSH_DOMAIN=$GiteaHostName",
        "-e", "GITEA__server__SSH_PORT=$GiteaSshPort",
        "-e", "GITEA__server__SSH_LISTEN_PORT=2222",
        "-e", "GITEA__server__START_SSH_SERVER=true",
        "-e", "GITEA__webhook__ALLOWED_HOST_LIST=$GiteaWebhookAllowedHostList",
        "-e", "GITEA__security__INSTALL_LOCK=$($GiteaInstallLock.ToString().ToLowerInvariant())",
        "-e", "GITEA__security__SECRET_KEY=$($Secrets.secretKey)",
        "-e", "GITEA__security__INTERNAL_TOKEN=$($Secrets.internalToken)",
        "-e", "GITEA__service__DISABLE_REGISTRATION=$($GiteaDisableRegistration.ToString().ToLowerInvariant())",
        "-e", "GITEA__service__REQUIRE_SIGNIN_VIEW=$($GiteaRequireSignInView.ToString().ToLowerInvariant())",
        "-e", "GITEA__repository__DEFAULT_BRANCH=$GiteaDefaultBranch",
        "-e", "GITEA__actions__ENABLED=$($GiteaEnableActions.ToString().ToLowerInvariant())"
    )

    if ($GiteaDatabaseMode -eq "postgres") {
        $variables += @(
            "-e", "GITEA__database__DB_TYPE=postgres",
            "-e", "GITEA__database__HOST=db:5432",
            "-e", "GITEA__database__NAME=$GiteaPostgresDbName",
            "-e", "GITEA__database__USER=$GiteaPostgresUser",
            "-e", "GITEA__database__PASSWD=$GiteaPostgresPassword",
            "-e", "GITEA__database__SSL_MODE=disable"
        )
    }

    return $variables
}

function Ensure-GiteaAdminUser {
    Wait-ForGiteaHttp

    $listResult = Invoke-GiteaContainerCommand -Arguments @("gitea", "admin", "user", "list", "--admin")
    if ($listResult.ExitCode -ne 0) {
        throw "Failed to list Gitea admin users. $($listResult.StdErr)"
    }

    $escapedAdminUsername = [regex]::Escape($GiteaAdminUsername)
    if ($listResult.StdOut -match "(?m)^\s*\d+\s+$escapedAdminUsername\s+") {
        $changePasswordResult = Invoke-GiteaContainerCommand -Arguments @(
            "gitea", "admin", "user", "change-password",
            "--username", $GiteaAdminUsername,
            "--password", $GiteaAdminPassword,
            "--must-change-password=$($GiteaAdminMustChangePassword.ToString().ToLowerInvariant())"
        )
        if ($changePasswordResult.ExitCode -ne 0) {
            throw "Failed to refresh the admin password for '$GiteaAdminUsername'. $($changePasswordResult.StdErr)"
        }

        Write-Host "Verified existing Gitea admin user '$GiteaAdminUsername'."
        return
    }

    $createArguments = @(
        "gitea", "admin", "user", "create",
        "--username", $GiteaAdminUsername,
        "--password", $GiteaAdminPassword,
        "--email", $GiteaAdminEmail,
        "--admin",
        "--must-change-password=$($GiteaAdminMustChangePassword.ToString().ToLowerInvariant())"
    )

    $createResult = Invoke-GiteaContainerCommand -Arguments $createArguments
    if ($createResult.ExitCode -ne 0) {
        throw "Failed to create the Gitea admin user '$GiteaAdminUsername'. $($createResult.StdErr)"
    }

    Write-Host "Created Gitea admin user '$GiteaAdminUsername'."
}

function Write-GiteaBootstrapSummary {
    Save-JsonFile -Path $GiteaBootstrapSummaryPath -Value @{
        baseUrl = $GiteaRootUrl
        bindAddress = $PortBindAddress
        databaseMode = $GiteaDatabaseMode
        webhook = @{
            allowedHostList = $GiteaWebhookAllowedHostList
        }
        httpPort = $GiteaHttpPort
        sshPort = $GiteaSshPort
        postgresPort = if ($GiteaDatabaseMode -eq "postgres") { $GiteaPostgresHostPort } else { $null }
        adminUsername = $GiteaAdminUsername
        adminEmail = $GiteaAdminEmail
        installedNonInteractively = $true
        installLock = $GiteaInstallLock
        configPath = $ConfigPath
        generatedSecretsPath = $GiteaSecretsPath
        localRepo = @{
            ensureOnBootstrap = $LocalRepoEnsureOnBootstrap
            owner = $LocalRepoOwner
            repo = $LocalRepoName
            seedFrom = $LocalRepoSeedFrom
        }
        controlHost = @{
            issueCommentWebhook = @{
                enabled = $IssueCommentWebhookEnabled
                callbackUrl = $IssueCommentWebhookCallbackUrl
                healthUrl = $IssueCommentWebhookHealthUrl
                status = Get-ManagedNodeServiceStatus -StatePath $TaskGatewayServiceStatePath -HealthUrl $IssueCommentWebhookHealthUrl
            }
            reviewWebhook = @{
                enabled = $ReviewWebhookEnabled
                callbackUrl = $ReviewWebhookCallbackUrl
                healthUrl = $ReviewWebhookHealthUrl
                status = Get-ManagedNodeServiceStatus -StatePath $ReviewSurfaceServiceStatePath -HealthUrl $ReviewWebhookHealthUrl
            }
        }
        generatedAt = (Get-Date).ToString("o")
    }
}

function Start-GiteaContainer {
    Assert-DockerReady
    Initialize-ProjectState
    $secrets = Ensure-GiteaSecrets

    if ($GiteaDatabaseMode -eq "postgres") {
        Start-GiteaPostgresContainer
    }

    $existingStatus = Get-ContainerStatus -ContainerName $GiteaContainerName
    if ($existingStatus -eq "running") {
        Wait-ForGiteaHttp
        Ensure-GiteaAdminUser
        Ensure-ControlHostWebhookServices
        Ensure-DefaultLocalRepoBootstrap
        Write-GiteaBootstrapSummary
        Write-Host "Gitea development container '$GiteaContainerName' is already running."
        return
    }

    if ($existingStatus) {
        & docker start $GiteaContainerName | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to start existing Gitea container '$GiteaContainerName'."
        }

        Wait-ForGiteaHttp
        Ensure-GiteaAdminUser
        Ensure-ControlHostWebhookServices
        Ensure-DefaultLocalRepoBootstrap
        Write-GiteaBootstrapSummary
        Write-Host "Started existing Gitea development container '$GiteaContainerName'."
        return
    }

    $resolvedDataDir = (Resolve-Path -LiteralPath $GiteaDataDir).Path
    $resolvedConfigDir = (Resolve-Path -LiteralPath $GiteaConfigDir).Path

    $dockerArgs = @(
        "run",
        "-d",
        "--name", $GiteaContainerName,
        "--restart", "unless-stopped",
        "-p", "${PortBindAddress}:${GiteaHttpPort}:3000",
        "-p", "${PortBindAddress}:${GiteaSshPort}:2222",
        "-v", "${resolvedDataDir}:/var/lib/gitea",
        "-v", "${resolvedConfigDir}:/etc/gitea"
    )

    if ($GiteaDatabaseMode -eq "postgres") {
        Ensure-DockerNetwork
        $dockerArgs += @("--network", $GiteaNetworkName)
    }

    $dockerArgs += Get-GiteaEnvironmentVariables -Secrets $secrets
    $dockerArgs += $GiteaImage

    & docker @dockerArgs | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create Gitea development container '$GiteaContainerName'."
    }

    Wait-ForGiteaHttp
    Ensure-GiteaAdminUser
    Ensure-ControlHostWebhookServices
    Ensure-DefaultLocalRepoBootstrap
    Write-GiteaBootstrapSummary
    Write-Host "Started new Gitea development container '$GiteaContainerName' using '$GiteaDatabaseMode' mode."
}

function Remove-ContainerIfPresent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName
    )

    $existingStatus = Get-ContainerStatus -ContainerName $ContainerName
    if (-not $existingStatus) {
        return
    }

    & docker rm -f $ContainerName | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to remove container '$ContainerName'."
    }
}

function Stop-GiteaStack {
    Stop-ControlHostWebhookServices

    if (-not (Test-DockerDaemonReady)) {
        Write-Host "Docker is not ready. No local Gitea stack was stopped."
        return
    }

    Remove-ContainerIfPresent -ContainerName $GiteaContainerName
    Remove-ContainerIfPresent -ContainerName $GiteaPostgresContainerName

    $networkInspect = Invoke-DockerProcess -Arguments @("network", "inspect", $GiteaNetworkName)
    if ($networkInspect.ExitCode -eq 0) {
        & docker network rm $GiteaNetworkName | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Removed Docker network '$GiteaNetworkName'."
        }
    }

    Write-Host "Stopped the local Gitea development stack."
}

function Get-DirectoryState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        return "ready"
    }

    return "missing"
}

function Show-EnvironmentStatus {
    $dockerCli = Test-DockerCliAvailable
    $dockerDaemon = Test-DockerDaemonReady
    $giteaStatus = Get-ContainerStatus -ContainerName $GiteaContainerName
    $postgresStatus = Get-ContainerStatus -ContainerName $GiteaPostgresContainerName
    $taskGatewayStatus = Get-ManagedNodeServiceStatus -StatePath $TaskGatewayServiceStatePath -HealthUrl $IssueCommentWebhookHealthUrl
    $reviewWebhookStatus = Get-ManagedNodeServiceStatus -StatePath $ReviewSurfaceServiceStatePath -HealthUrl $ReviewWebhookHealthUrl

    if (-not $giteaStatus) {
        $giteaStatus = "not-started"
    }

    if (-not $postgresStatus) {
        $postgresStatus = "not-started"
    }

    Write-Host "Project root: $RepoRoot"
    Write-Host "Bootstrap config: $ConfigPath"
    Write-Host "Docker Desktop Path: $DockerDesktopPath"
    Write-Host "ENV-001 Forge (Gitea): $giteaStatus on $GiteaRootUrl"
    Write-Host "ENV-001 Port Forwarding: ${PortBindAddress}:${GiteaHttpPort}->3000 and ${PortBindAddress}:${GiteaSshPort}->2222"
    Write-Host "ENV-001 Gitea DB Mode: $GiteaDatabaseMode"
    if ($GiteaDatabaseMode -eq "postgres") {
        Write-Host "ENV-001 PostgreSQL: $postgresStatus on ${PortBindAddress}:${GiteaPostgresHostPort}->5432"
    }
    Write-Host "ENV-001 Non-Interactive Install: installLock=$GiteaInstallLock admin=$GiteaAdminUsername"
    Write-Host "ENV-001 Default Local Repo Bootstrap: enabled=$LocalRepoEnsureOnBootstrap repo=$LocalRepoOwner/$LocalRepoName"
    Write-Host "ENV-002 Task Gateway Webhook: $taskGatewayStatus at $IssueCommentWebhookHealthUrl (callback $IssueCommentWebhookCallbackUrl)"
    Write-Host "ENV-002 Review Webhook: $reviewWebhookStatus at $ReviewWebhookHealthUrl (callback $ReviewWebhookCallbackUrl)"
    Write-Host "ENV-003 Worker Runtime: docker-cli=$dockerCli docker-daemon=$dockerDaemon"
    Write-Host "ENV-004 CI Environment: not bootstrapped locally yet"
    Write-Host "ENV-005 Task Request State: $(Get-DirectoryState -Path $TaskRequestStateDir)"
    Write-Host "ENV-005 Agent Session State: $(Get-DirectoryState -Path $AgentSessionStateDir)"
    Write-Host "ENV-005 Traceability Path: $(Get-DirectoryState -Path $TraceabilityDir)"
    Write-Host "ENV-006 Secrets: repo-owned config plus generated local Gitea secrets under $GiteaSecretsPath"
}

switch ($Command) {
    "init" {
        Initialize-ProjectState
        Write-Host "Initialized project-local state directories under '$ProjectStateRoot'."
        Write-Host "Bootstrap config is sourced from '$ConfigPath'."
        break
    }

    "up" {
        Initialize-ProjectState
        Ensure-ControlHostWebhookServices
        if (-not $SkipGitea) {
            Start-GiteaContainer
        }
        Show-EnvironmentStatus
        break
    }

    "down" {
        if ($SkipGitea) {
            Stop-ControlHostWebhookServices
        }
        if (-not $SkipGitea) {
            Stop-GiteaStack
        }
        Show-EnvironmentStatus
        break
    }

    "status" {
        Show-EnvironmentStatus
        break
    }
}
