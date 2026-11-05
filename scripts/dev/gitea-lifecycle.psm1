Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-NativeWindowsHost {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw "Gitea backup, upgrade, and restore operations must run from native Windows PowerShell on the Docker Desktop host."
    }
}

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $rootPath = [System.IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Equals($rootPath, [StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath
    }
    return $fullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

function Test-PathContains {
    param(
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Child
    )

    $parentPath = (Get-FullPath -Path $Parent) + [System.IO.Path]::DirectorySeparatorChar
    $childPath = Get-FullPath -Path $Child
    return $childPath.StartsWith($parentPath, [StringComparison]::OrdinalIgnoreCase)
}

function Test-PathsOverlap {
    param([string]$First, [string]$Second)
    $firstPath = Get-FullPath -Path $First
    $secondPath = Get-FullPath -Path $Second
    return $firstPath.Equals($secondPath, [StringComparison]::OrdinalIgnoreCase) -or
        (Test-PathContains -Parent $firstPath -Child $secondPath) -or
        (Test-PathContains -Parent $secondPath -Child $firstPath)
}

function Assert-NoReparsePathAncestors {
    param([Parameter(Mandatory = $true)][string]$Path)

    $current = Get-FullPath -Path $Path
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "The configured backup path crosses a reparse point at '$current'; local backup storage must resolve directly to disk."
            }
        }
        $parent = [System.IO.Directory]::GetParent($current)
        if (-not $parent) { break }
        $current = $parent.FullName
    }
}

function Assert-SafeBackupRoot {
    param([hashtable]$Context)

    if (-not [System.IO.Path]::IsPathRooted($Context.BackupRoot)) {
        throw "The Gitea backup root must be an absolute Windows path. Set gitea.backup.root or pass -BackupRoot."
    }

    $backupRoot = Get-FullPath -Path $Context.BackupRoot
    if ($backupRoot -notmatch '^[A-Za-z]:\\') {
        throw "Gitea backups must use a local Windows drive path; UNC and relative locations are not allowed."
    }
    Assert-NoReparsePathAncestors -Path $backupRoot
    if (Test-PathsOverlap -First $backupRoot -Second $Context.RepoRoot) {
        throw "The Gitea backup root must not overlap the Git repository."
    }

    foreach ($livePath in @($Context.GiteaDataDir, $Context.GiteaConfigDir, $Context.GiteaPostgresDataDir)) {
        if (Test-PathsOverlap -First $backupRoot -Second $livePath) {
            throw "The Gitea backup root must be separate from every live Gitea and PostgreSQL data path."
        }
    }

    return $backupRoot
}

function Set-RestrictedBackupAcl {
    param([Parameter(Mandatory = $true)][string]$Path)

    $acl = Get-Acl -LiteralPath $Path
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) {
        [void]$acl.RemoveAccessRuleSpecific($rule)
    }

    $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::None
    if ((Get-Item -LiteralPath $Path).PSIsContainer) {
        $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    }
    $identities = @(
        [System.Security.Principal.WindowsIdentity]::GetCurrent().User,
        [System.Security.Principal.SecurityIdentifier]::new("S-1-5-18"),
        [System.Security.Principal.SecurityIdentifier]::new("S-1-5-32-544")
    )
    foreach ($identity in $identities) {
        $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
            $identity,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            $inheritanceFlags,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        [void]$acl.AddAccessRule($rule)
    }

    $acl.SetOwner([System.Security.Principal.WindowsIdentity]::GetCurrent().User)
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Ensure-BackupRoot {
    param([hashtable]$Context)

    $backupRoot = Assert-SafeBackupRoot -Context $Context
    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    }

    $resolvedRoot = (Resolve-Path -LiteralPath $backupRoot).Path
    if ((Get-FullPath -Path $resolvedRoot) -ne $backupRoot) {
        throw "The resolved Gitea backup root differs from the configured path; refusing a redirected backup location."
    }

    Set-RestrictedBackupAcl -Path $backupRoot
    return $backupRoot
}

function ConvertTo-ProcessArgumentString {
    param([string[]]$Arguments)

    $quoted = foreach ($argument in $Arguments) {
        if ($argument -match '[\s"]') {
            '"' + ($argument -replace '"', '\"') + '"'
        }
        else {
            $argument
        }
    }
    return [string]::Join(" ", $quoted)
}

function Invoke-GiteaDocker {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $dockerCommand) {
        throw "Docker CLI is not available on this Windows Host."
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $dockerCommand.Source
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $startInfo.Arguments = ConvertTo-ProcessArgumentString -Arguments $Arguments

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $stdout = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()
    $stderr = $stderrTask.Result.Trim()

    $result = [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut = $stdout.Trim()
        StdErr = $stderr
    }
    if (-not $AllowFailure -and $result.ExitCode -ne 0) {
        throw "Docker operation failed (exit $($result.ExitCode)): $stderr"
    }
    return $result
}

function Invoke-GiteaDockerToFile {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )

    $dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $dockerCommand) {
        throw "Docker CLI is not available on this Windows Host."
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $dockerCommand.Source
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $startInfo.Arguments = ConvertTo-ProcessArgumentString -Arguments $Arguments

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $output = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $process.StandardOutput.BaseStream.CopyTo($output)
    }
    finally {
        $output.Dispose()
    }
    $process.WaitForExit()
    $stderr = $stderrTask.Result.Trim()
    if ($process.ExitCode -ne 0) {
        throw "Database backup command failed (exit $($process.ExitCode)); output was not accepted. $stderr"
    }
}

function Invoke-GiteaDockerWithInputFile {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$InputPath
    )

    $dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $dockerCommand) {
        throw "Docker CLI is not available on this Windows Host."
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $dockerCommand.Source
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $startInfo.Arguments = ConvertTo-ProcessArgumentString -Arguments $Arguments

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $inputStream = [System.IO.File]::OpenRead($InputPath)
    try {
        $inputStream.CopyTo($process.StandardInput.BaseStream)
    }
    finally {
        $inputStream.Dispose()
        $process.StandardInput.Close()
    }
    $process.WaitForExit()
    $stderr = $stderrTask.Result.Trim()
    if ($process.ExitCode -ne 0) {
        throw "Docker input operation failed (exit $($process.ExitCode)); output was not accepted. $stderr"
    }
    $null = $stdoutTask.Result
}

function Assert-DockerDesktopReady {
    $info = Invoke-GiteaDocker -Arguments @("info", "--format", "{{json .}}")
    $identity = $info.StdOut | ConvertFrom-Json
    if ([string]$identity.OperatingSystem -notmatch "Docker Desktop") {
        throw "The active Docker engine is '$($identity.OperatingSystem)'; lifecycle operations require the intended Docker Desktop host."
    }
    return @{
        id = [string]$identity.ID
        name = [string]$identity.Name
        operatingSystem = [string]$identity.OperatingSystem
        dockerRootDir = [string]$identity.DockerRootDir
    }
}

function Get-GiteaContainerInfo {
    param([Parameter(Mandatory = $true)][string]$Name)

    $result = Invoke-GiteaDocker -Arguments @("container", "inspect", $Name, "--format", "{{json .}}") -AllowFailure
    if ($result.ExitCode -ne 0 -or -not $result.StdOut) {
        return $null
    }
    return $result.StdOut | ConvertFrom-Json
}

function ConvertFrom-DockerHostPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($Path -match '^/run/desktop/mnt/host/([a-z])/(.*)$' -or $Path -match '^/host_mnt/([a-z])/(.*)$' -or $Path -match '^/mnt/([a-z])/(.*)$') {
        return ("$($Matches[1].ToUpperInvariant()):\" + $Matches[2].Replace('/', '\'))
    }
    return $Path
}

function Assert-BindMount {
    param(
        [Parameter(Mandatory = $true)][object]$Container,
        [Parameter(Mandatory = $true)][string]$ContainerPath,
        [Parameter(Mandatory = $true)][string]$HostPath
    )

    $expectedHostPath = Get-FullPath -Path $HostPath
    $mount = @($Container.Mounts | Where-Object { $_.Destination -eq $ContainerPath -and $_.Type -eq "bind" }) | Select-Object -First 1
    if (-not $mount) {
        throw "Container '$($Container.Name)' is missing the expected bind mount '$ContainerPath'."
    }

    $actualHostPath = Get-FullPath -Path (ConvertFrom-DockerHostPath -Path ([string]$mount.Source))
    if (-not $actualHostPath.Equals($expectedHostPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Container '$($Container.Name)' has an unexpected host mount for '$ContainerPath'; refusing to operate on ambiguous data."
    }
}

function Assert-PortBinding {
    param(
        [Parameter(Mandatory = $true)][object]$Container,
        [Parameter(Mandatory = $true)][string]$ContainerPort,
        [Parameter(Mandatory = $true)][string]$HostIp,
        [Parameter(Mandatory = $true)][int]$HostPort
    )

    $bindingProperty = $Container.HostConfig.PortBindings.PSObject.Properties[$ContainerPort]
    if (-not $bindingProperty -or @($bindingProperty.Value).Count -ne 1) {
        throw "Container '$($Container.Name)' does not have exactly one expected host binding for '$ContainerPort'."
    }

    $binding = @($bindingProperty.Value)[0]
    if ([string]$binding.HostIp -ne $HostIp -or [int]$binding.HostPort -ne $HostPort) {
        throw "Container '$($Container.Name)' has an unexpected host port binding for '$ContainerPort'."
    }
}

function ConvertTo-ContainerEnvironmentMap {
    param([Parameter(Mandatory = $true)][string[]]$Environment)

    $map = @{}
    foreach ($item in $Environment) {
        $separator = $item.IndexOf('=')
        if ($separator -gt 0) {
            $map[$item.Substring(0, $separator)] = $item.Substring($separator + 1)
        }
    }
    return $map
}

function Assert-GiteaDatabaseTarget {
    param(
        [Parameter(Mandatory = $true)][object]$GiteaContainer,
        [Parameter(Mandatory = $true)][object]$PostgresContainer,
        [Parameter(Mandatory = $true)][hashtable]$Context
    )

    $giteaEnvironment = ConvertTo-ContainerEnvironmentMap -Environment @($GiteaContainer.Config.Env)
    $postgresEnvironment = ConvertTo-ContainerEnvironmentMap -Environment @($PostgresContainer.Config.Env)
    if ($giteaEnvironment["GITEA__database__DB_TYPE"] -ne "postgres" -or
        $giteaEnvironment["GITEA__database__HOST"] -ne "db:5432" -or
        $giteaEnvironment["GITEA__database__NAME"] -ne $Context.GiteaPostgresDbName -or
        $giteaEnvironment["GITEA__database__USER"] -ne $Context.GiteaPostgresUser -or
        -not $giteaEnvironment["GITEA__database__PASSWD"] -or
        $giteaEnvironment["GITEA__database__PASSWD"] -ne $postgresEnvironment["POSTGRES_PASSWORD"] -or
        -not $postgresEnvironment["POSTGRES_PASSWORD"]) {
        throw "The existing Gitea and PostgreSQL containers do not have matching database identity and credentials."
    }
}

function Assert-GiteaContainerIdentity {
    param(
        [hashtable]$Context,
        [switch]$AllowStopped,
        [switch]$AllowMissing
    )

    if ($Context.GiteaHttpPort -ne 43000 -or $Context.GiteaDatabaseMode -ne "postgres") {
        throw "Lifecycle operations are limited to the legacy PostgreSQL Gitea instance on host port 43000."
    }

    $container = Get-GiteaContainerInfo -Name $Context.GiteaContainerName
    if (-not $container) {
        if ($AllowMissing) { return $null }
        throw "The expected legacy Gitea container '$($Context.GiteaContainerName)' was not found."
    }

    $status = [string]$container.State.Status
    if (-not $AllowStopped -and $status -ne "running") {
        throw "The legacy Gitea container is '$status'; expected a running container for preflight."
    }
    if ($AllowStopped -and $status -notin @("running", "exited", "created")) {
        throw "The legacy Gitea container is in unexpected state '$status'."
    }

    if ([string]$container.Name -ne "/$($Context.GiteaContainerName)") {
        throw "Docker returned a different Gitea container identity than requested."
    }
    $labels = $container.Config.Labels
    if ($labels -and $labels.PSObject.Properties["com.docker.compose.project"]) {
        throw "The selected Gitea container is Compose-managed; refusing to cross the legacy/Compose lifecycle boundary."
    }

    if (@($container.Mounts).Count -ne 2) {
        throw "The legacy Gitea container has unbacked extra mounts; refusing an incomplete snapshot."
    }
    $portNames = @($container.HostConfig.PortBindings.PSObject.Properties.Name | Sort-Object)
    if (($portNames -join ",") -ne "2222/tcp,3000/tcp") {
        throw "The legacy Gitea container has unexpected host port bindings; refusing to recreate an ambiguous topology."
    }
    Assert-BindMount -Container $container -ContainerPath "/var/lib/gitea" -HostPath $Context.GiteaDataDir
    Assert-BindMount -Container $container -ContainerPath "/etc/gitea" -HostPath $Context.GiteaConfigDir
    Assert-PortBinding -Container $container -ContainerPort "3000/tcp" -HostIp $Context.PortBindAddress -HostPort $Context.GiteaHttpPort
    Assert-PortBinding -Container $container -ContainerPort "2222/tcp" -HostIp $Context.PortBindAddress -HostPort $Context.GiteaSshPort

    if ([string]$container.HostConfig.NetworkMode -ne $Context.GiteaNetworkName -or
        -not $container.NetworkSettings.Networks.PSObject.Properties[$Context.GiteaNetworkName]) {
        throw "The legacy Gitea container has an unexpected Docker network."
    }

    $environment = ConvertTo-ContainerEnvironmentMap -Environment @($container.Config.Env)
    if ($environment["GITEA__database__DB_TYPE"] -ne "postgres" -or
        $environment["GITEA__database__HOST"] -ne "db:5432" -or
        $environment["GITEA__database__NAME"] -ne $Context.GiteaPostgresDbName -or
        $environment["GITEA__database__USER"] -ne $Context.GiteaPostgresUser) {
        throw "The legacy Gitea container's database target differs from the expected existing PostgreSQL service."
    }

    return $container
}

function Assert-PostgresContainerIdentity {
    param([hashtable]$Context)

    $container = Get-GiteaContainerInfo -Name $Context.GiteaPostgresContainerName
    if (-not $container -or [string]$container.State.Status -ne "running") {
        throw "The expected existing PostgreSQL container must be running; lifecycle operations never create or restart PostgreSQL."
    }
    if ([string]$container.Name -ne "/$($Context.GiteaPostgresContainerName)") {
        throw "Docker returned a different PostgreSQL container identity than requested."
    }
    $labels = $container.Config.Labels
    if ($labels -and $labels.PSObject.Properties["com.docker.compose.project"]) {
        throw "The selected PostgreSQL container is Compose-managed; refusing to cross the legacy/Compose lifecycle boundary."
    }

    Assert-BindMount -Container $container -ContainerPath "/var/lib/postgresql/data" -HostPath $Context.GiteaPostgresDataDir
    Assert-PortBinding -Container $container -ContainerPort "5432/tcp" -HostIp $Context.PortBindAddress -HostPort $Context.GiteaPostgresHostPort
    if ([string]$container.HostConfig.NetworkMode -ne $Context.GiteaNetworkName) {
        throw "The existing PostgreSQL container has an unexpected Docker network."
    }
    $network = $container.NetworkSettings.Networks.PSObject.Properties[$Context.GiteaNetworkName]
    if (-not $network -or @($network.Value.Aliases) -notcontains "db") {
        throw "The existing PostgreSQL container is missing the expected 'db' network alias used by Gitea."
    }
    $environment = ConvertTo-ContainerEnvironmentMap -Environment @($container.Config.Env)
    if ($environment["POSTGRES_DB"] -ne $Context.GiteaPostgresDbName -or
        $environment["POSTGRES_USER"] -ne $Context.GiteaPostgresUser) {
        throw "The existing PostgreSQL container database identity differs from the configured Gitea database."
    }
    return $container
}

function Get-GiteaApiHeaders {
    param([hashtable]$Context)

    if (-not $Context.GiteaAdminUsername -or -not $Context.GiteaAdminPassword) {
        throw "Configured local Gitea admin credentials are required to verify that Actions has no active work."
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes("$($Context.GiteaAdminUsername):$($Context.GiteaAdminPassword)")
    $token = [Convert]::ToBase64String($bytes)
    return @{ Authorization = "Basic $token" }
}

function Invoke-GiteaApiRead {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $uri = $Context.GiteaRootUrl.TrimEnd('/') + "/api/v1/" + $RelativePath.TrimStart('/')
    try {
        return Invoke-RestMethod -Uri $uri -Method Get -Headers (Get-GiteaApiHeaders -Context $Context) -TimeoutSec 15
    }
    catch {
        throw "Could not verify Gitea Actions state through the local API; refusing maintenance."
    }
}

function Assert-NoActiveGiteaActions {
    param([hashtable]$Context)

    $authenticatedUser = Invoke-GiteaApiRead -Context $Context -RelativePath "user"
    if (-not [bool]$authenticatedUser.is_admin) {
        throw "The configured Gitea API identity is not an administrator; all repositories cannot be checked for active work."
    }
    $limit = 50
    $page = 1
    $repositories = @()
    while ($true) {
        $response = Invoke-GiteaApiRead -Context $Context -RelativePath "repos/search?limit=$limit&page=$page"
        $dataProperty = $response.PSObject.Properties["data"]
        $totalProperty = $response.PSObject.Properties["total_count"]
        if (-not $dataProperty -or -not $totalProperty) {
            throw "Gitea repository enumeration returned an unexpected response; refusing maintenance."
        }
        $totalCount = [int]$totalProperty.Value
        if ($totalCount -lt 0) {
            throw "Gitea repository enumeration returned an invalid total; refusing maintenance."
        }
        $batch = @()
        if ($null -ne $dataProperty.Value) { $batch = @($dataProperty.Value) }
        $expectedCount = [Math]::Min($limit, [Math]::Max(0, $totalCount - (($page - 1) * $limit)))
        if ($batch.Count -ne $expectedCount) {
            throw "Gitea repository enumeration was incomplete; refusing maintenance."
        }
        $repositories += $batch
        if (($page * $limit) -ge $totalCount) {
            break
        }
        $page += 1
        if ($page -gt 10000) {
            throw "Gitea repository enumeration exceeded its safety bound; refusing maintenance."
        }
    }

    foreach ($repository in $repositories) {
        $owner = [Uri]::EscapeDataString([string]$repository.owner.login)
        $name = [Uri]::EscapeDataString([string]$repository.name)
        $runPage = 1
        while ($true) {
            $path = "repos/$owner/$name/actions/runs?limit=$limit&page=$runPage"
            $response = Invoke-GiteaApiRead -Context $Context -RelativePath $path
            $runsProperty = $response.PSObject.Properties["workflow_runs"]
            $totalProperty = $response.PSObject.Properties["total_count"]
            if (-not $runsProperty -or -not $totalProperty) {
                throw "Gitea Actions enumeration returned an unexpected response for '$($repository.full_name)'; refusing maintenance."
            }
            $totalCount = [int]$totalProperty.Value
            if ($totalCount -lt 0) {
                throw "Gitea Actions enumeration returned an invalid total for '$($repository.full_name)'; refusing maintenance."
            }
            $runs = @()
            if ($null -ne $runsProperty.Value) { $runs = @($runsProperty.Value) }
            $expectedCount = [Math]::Min($limit, [Math]::Max(0, $totalCount - (($runPage - 1) * $limit)))
            if ($runs.Count -ne $expectedCount) {
                throw "Gitea Actions run enumeration was incomplete for '$($repository.full_name)'; refusing maintenance."
            }
            # Gitea returns workflow_runs; unknown status values fail closed as active work.
            foreach ($run in $runs) {
                $status = [string]$run.status
                if ($status -notin @("success", "failure", "skipped", "cancelled", "completed")) {
                    throw "Gitea Actions has '$status' work in repository '$($repository.full_name)'; wait for it to finish before maintenance."
                }
            }
            if (($runPage * $limit) -ge $totalCount) {
                break
            }
            $runPage += 1
            if ($runPage -gt 10000) {
                throw "Gitea Actions run enumeration exceeded its safety bound; refusing maintenance."
            }
        }
    }
}

function Get-GiteaRunnerInfo {
    param([hashtable]$Context)

    if (-not $Context.GiteaRunnerContainerName) {
        throw "The configured shared Gitea Runner container name is missing."
    }
    $runner = Get-GiteaContainerInfo -Name $Context.GiteaRunnerContainerName
    if (-not $runner) {
        throw "The existing shared Runner container '$($Context.GiteaRunnerContainerName)' was not found."
    }
    return $runner
}

function Stop-GiteaRunner {
    param([Parameter(Mandatory = $true)][string]$Name)

    $runner = Get-GiteaContainerInfo -Name $Name
    if ($runner -and [string]$runner.State.Status -eq "running") {
        [void](Invoke-GiteaDocker -Arguments @("stop", "--time", "120", $Name))
    }
}

function Start-GiteaRunner {
    param([Parameter(Mandatory = $true)][string]$Name)

    $runner = Get-GiteaContainerInfo -Name $Name
    if (-not $runner) {
        throw "The original shared Runner container '$Name' is missing; it was not recreated."
    }
    if ([string]$runner.State.Status -ne "running") {
        [void](Invoke-GiteaDocker -Arguments @("start", $Name))
    }
}

function Get-GiteaReportedVersion {
    param([Parameter(Mandatory = $true)][object]$Container)

    if ([string]$Container.State.Status -eq "running") {
        $result = Invoke-GiteaDocker -Arguments @("exec", [string]$Container.Name.TrimStart('/'), "gitea", "--version") -AllowFailure
        if ($result.ExitCode -eq 0 -and $result.StdOut -match '(?<!\d)(\d+\.\d+\.\d+)(?!\d)') {
            return $Matches[1]
        }
    }

    $imageInfo = Invoke-GiteaDocker -Arguments @("image", "inspect", [string]$Container.Image, "--format", "{{json .Config.Labels}}") -AllowFailure
    if ($imageInfo.ExitCode -eq 0 -and $imageInfo.StdOut) {
        $labels = $imageInfo.StdOut | ConvertFrom-Json
        $version = [string]$labels.'org.opencontainers.image.version'
        if ($version -match '(?<!\d)(\d+\.\d+\.\d+)(?!\d)') {
            return $Matches[1]
        }
    }

    $image = [string]$Container.Config.Image
    if ($image -match ':(\d+\.\d+\.\d+)(?:-rootless)?$') {
        return $Matches[1]
    }
    throw "Could not identify the running Gitea version from the container; refusing an unverified upgrade path."
}

function Assert-SupportedGiteaVersionStep {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentVersion,
        [Parameter(Mandatory = $true)][string]$TargetVersion
    )

    if ($CurrentVersion -notmatch '^\d+\.\d+\.\d+$' -or $TargetVersion -notmatch '^\d+\.\d+\.\d+$') {
        throw "Gitea versions must use an exact numeric x.y.z form."
    }
    $current = [Version]$CurrentVersion
    $target = [Version]$TargetVersion
    if ($target -le $current) {
        throw "The target Gitea version must be newer than the current version."
    }

    # Gitea 28.x dropped the historical "1." prefix. The 28.x releases are
    # maintenance releases of the same series, and follow 1.27.x directly.
    $legacySameSeries = $current.Major -eq 1 -and $target.Major -eq 1 -and $target.Minor -eq $current.Minor
    $legacyNextSeries = $current.Major -eq 1 -and $target.Major -eq 1 -and $target.Minor -eq ($current.Minor + 1)
    $enterVersion28Series = $current.Major -eq 1 -and $current.Minor -eq 27 -and $target.Major -eq 28
    $withinVersion28Series = $current.Major -eq 28 -and $target.Major -eq 28
    if (-not ($legacySameSeries -or $legacyNextSeries -or $enterVersion28Series -or $withinVersion28Series)) {
        throw "The requested version is not the same Gitea series or its immediately following release series. Upgrade through each intermediate series and verify its release guidance."
    }
}

function Get-ImageDigestReference {
    param(
        [Parameter(Mandatory = $true)][string]$Image,
        [switch]$RequireRegistryDigest
    )

    $result = Invoke-GiteaDocker -Arguments @("image", "inspect", $Image, "--format", "{{json .RepoDigests}}")
    $digests = @($result.StdOut | ConvertFrom-Json)
    $digest = $digests | Where-Object { $_ -match '^docker\.gitea\.com/gitea@sha256:[0-9a-f]{64}$' } | Select-Object -First 1
    if ($digest) {
        return [string]$digest
    }
    if ($RequireRegistryDigest) {
        throw "The pulled Gitea image did not resolve to the expected immutable docker.gitea.com digest."
    }
    if ($Image -match '^sha256:[0-9a-f]{64}$') {
        return $Image
    }

    $inspect = Invoke-GiteaDocker -Arguments @("image", "inspect", $Image, "--format", "{{.Id}}")
    if ($inspect.StdOut -notmatch '^sha256:[0-9a-f]{64}$') {
        throw "Could not resolve an immutable local image identity for restore."
    }
    return $inspect.StdOut
}

function Get-DirectoryBytes {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Required live data directory '$Path' is missing."
    }
    if (((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Live data directory '$Path' is a reparse point; refusing a capacity estimate over redirected data."
    }
    $sum = [long]0
    foreach ($item in Get-ChildItem -LiteralPath $Path -Recurse -Force) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Live data contains a reparse point at '$($item.FullName)'; refusing a capacity estimate over redirected data."
        }
        if (-not $item.PSIsContainer) {
            $sum += [long]$item.Length
        }
    }
    return $sum
}

function Get-AvailableBackupBytes {
    param([Parameter(Mandatory = $true)][string]$Path)

    $volumeRoot = [System.IO.Path]::GetPathRoot($Path)
    $drive = [System.IO.DriveInfo]::new($volumeRoot)
    if (-not $drive.IsReady) {
        throw "The configured Gitea backup volume is not ready."
    }
    if ($drive.DriveType -ne [System.IO.DriveType]::Fixed) {
        throw "Gitea backups must use a fixed local Windows drive."
    }
    return [long]$drive.AvailableFreeSpace
}

function Assert-BackupCapacity {
    param([hashtable]$Context)

    $sourceBytes = (Get-DirectoryBytes -Path $Context.GiteaDataDir) +
        (Get-DirectoryBytes -Path $Context.GiteaConfigDir) +
        (Get-DirectoryBytes -Path $Context.GiteaPostgresDataDir)
    $minimumFree = [Math]::Max([long]1GB, [long]($sourceBytes * 2))
    $freeBytes = Get-AvailableBackupBytes -Path $Context.BackupRoot
    if ($freeBytes -lt $minimumFree) {
        throw "Insufficient free space for a conservative Gitea backup estimate; no existing backup will be removed."
    }
    return [pscustomobject]@{
        SourceBytes = $sourceBytes
        RequiredFreeBytes = $minimumFree
        AvailableFreeBytes = $freeBytes
    }
}

function Save-BackupJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )

    $json = ConvertTo-Json -InputObject $Value -Depth 100
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Copy-DirectoryTree {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Required Gitea data directory '$Source' is missing."
    }
    if (((Get-Item -LiteralPath $Source -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Backup source directory '$Source' is a reparse point; refusing an ambiguous snapshot."
    }
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Backup source contains a reparse point at '$($item.FullName)'; refusing an ambiguous snapshot."
        }
        $target = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) {
            Copy-DirectoryTree -Source $item.FullName -Destination $target
        }
        else {
            Copy-Item -LiteralPath $item.FullName -Destination $target
        }
    }
}

function Get-RuntimeSnapshot {
    param(
        [hashtable]$Context,
        [object]$Container,
        [string]$SourceVersion
    )

    if (-not $Container) { return $null }
    $imageReference = Get-ImageDigestReference -Image ([string]$Container.Image)
    $ports = @()
    foreach ($property in $Container.HostConfig.PortBindings.PSObject.Properties) {
        foreach ($binding in @($property.Value)) {
            $ports += @{
                containerPort = [string]$property.Name
                hostIp = [string]$binding.HostIp
                hostPort = [string]$binding.HostPort
            }
        }
    }
    $mounts = @()
    foreach ($mount in @($Container.Mounts)) {
        $mounts += @{
            type = [string]$mount.Type
            source = [string]$mount.Source
            destination = [string]$mount.Destination
            readWrite = [bool]$mount.RW
        }
    }

    return @{
        containerName = [string]$Context.GiteaContainerName
        capturedContainerName = [string]$Container.Name.TrimStart('/')
        statusAtCapture = [string]$Container.State.Status
        sourceVersion = $SourceVersion
        originalImageReference = [string]$Container.Config.Image
        imageReference = $imageReference
        imageId = [string]$Container.Image
        networkMode = [string]$Container.HostConfig.NetworkMode
        restartPolicy = [string]$Container.HostConfig.RestartPolicy.Name
        ports = $ports
        mounts = $mounts
        environment = @($Container.Config.Env)
        configSource = [string]$Context.ConfigSource
        configPath = [string]$Context.ConfigPath
    }
}

function Get-PostgresTopologySnapshot {
    param([object]$Container)

    $ports = @()
    foreach ($property in $Container.HostConfig.PortBindings.PSObject.Properties) {
        foreach ($binding in @($property.Value)) {
            $ports += @{
                containerPort = [string]$property.Name
                hostIp = [string]$binding.HostIp
                hostPort = [string]$binding.HostPort
            }
        }
    }
    $mounts = @()
    foreach ($mount in @($Container.Mounts)) {
        $mounts += @{
            type = [string]$mount.Type
            source = [string]$mount.Source
            destination = [string]$mount.Destination
            readWrite = [bool]$mount.RW
        }
    }
    $networkProperty = $Container.NetworkSettings.Networks.PSObject.Properties[[string]$Container.HostConfig.NetworkMode]
    $networkAliases = @()
    if ($networkProperty -and $networkProperty.Value.Aliases) {
        $networkAliases = @($networkProperty.Value.Aliases | Sort-Object)
    }
    return @{
        containerName = [string]$Container.Name.TrimStart('/')
        originalImageReference = [string]$Container.Config.Image
        imageId = [string]$Container.Image
        networkMode = [string]$Container.HostConfig.NetworkMode
        networkAliases = $networkAliases
        ports = $ports
        mounts = $mounts
    }
}

function Assert-PostgresRestoreCompatibility {
    param(
        [Parameter(Mandatory = $true)][object]$BackupTopology,
        [Parameter(Mandatory = $true)][object]$CurrentContainer,
        [Parameter(Mandatory = $true)][hashtable]$Context
    )

    $current = Get-PostgresTopologySnapshot -Container $CurrentContainer
    if ([string]$BackupTopology.containerName -ne [string]$Context.GiteaPostgresContainerName -or
        [string]$BackupTopology.containerName -ne [string]$current.containerName -or
        [string]$BackupTopology.imageId -ne [string]$current.imageId -or
        [string]$BackupTopology.networkMode -ne [string]$current.networkMode -or
        ((@($BackupTopology.networkAliases | Sort-Object) -join ",") -ne (@($current.networkAliases | Sort-Object) -join ",")) -or
        @($current.networkAliases) -notcontains "db") {
        throw "The selected backup's PostgreSQL identity, image, or network differs from the existing service; restore is blocked."
    }

    $expectedMounts = @($BackupTopology.mounts)
    $currentMounts = @($current.mounts)
    if ($expectedMounts.Count -ne $currentMounts.Count) {
        throw "The selected backup's PostgreSQL mount topology differs from the existing service; restore is blocked."
    }
    foreach ($expected in $expectedMounts) {
        $currentMount = @($currentMounts | Where-Object { $_.destination -eq $expected.destination -and $_.type -eq $expected.type }) | Select-Object -First 1
        if (-not $currentMount -or
            -not (Get-FullPath -Path (ConvertFrom-DockerHostPath -Path ([string]$expected.source))).Equals((Get-FullPath -Path (ConvertFrom-DockerHostPath -Path ([string]$currentMount.source))), [StringComparison]::OrdinalIgnoreCase) -or
            [bool]$expected.readWrite -ne [bool]$currentMount.readWrite) {
            throw "The selected backup's PostgreSQL data mounts differ from the existing service; restore is blocked."
        }
    }

    $expectedPorts = @($BackupTopology.ports)
    $currentPorts = @($current.ports)
    if ($expectedPorts.Count -ne $currentPorts.Count) {
        throw "The selected backup's PostgreSQL port bindings differ from the existing service; restore is blocked."
    }
    foreach ($expected in $expectedPorts) {
        $currentPort = @($currentPorts | Where-Object { $_.containerPort -eq $expected.containerPort }) | Select-Object -First 1
        if (-not $currentPort -or [string]$expected.hostIp -ne [string]$currentPort.hostIp -or
            [string]$expected.hostPort -ne [string]$currentPort.hostPort) {
            throw "The selected backup's PostgreSQL port bindings differ from the existing service; restore is blocked."
        }
    }
}

function Get-BackupFileEntries {
    param([Parameter(Mandatory = $true)][string]$BackupPath)

    $entries = @()
    $manifestPath = Join-Path $BackupPath "manifest.json"
    foreach ($file in Get-ChildItem -LiteralPath $BackupPath -File -Recurse -Force | Where-Object { -not $_.FullName.Equals($manifestPath, [StringComparison]::OrdinalIgnoreCase) }) {
        $relativePath = $file.FullName.Substring($BackupPath.Length).TrimStart('\', '/') -replace '\\', '/'
        $entries += @{
            path = $relativePath
            sizeBytes = [long]$file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    return $entries
}

function Test-GiteaBackupIntegrity {
    param([Parameter(Mandatory = $true)][string]$BackupPath)

    $manifestPath = Join-Path $BackupPath "manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return [pscustomobject]@{ IsValid = $false; Reason = "manifest-missing"; Manifest = $null }
    }
    try {
        if (((Get-Item -LiteralPath $BackupPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            ((Get-Item -LiteralPath $manifestPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            return [pscustomobject]@{ IsValid = $false; Reason = "reparse-point-found"; Manifest = $null }
        }
        foreach ($item in Get-ChildItem -LiteralPath $BackupPath -Recurse -Force) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                return [pscustomobject]@{ IsValid = $false; Reason = "reparse-point-found"; Manifest = $null }
            }
        }
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ([int]$manifest.schemaVersion -ne 1 -or [string]$manifest.backupId -ne (Split-Path -Leaf $BackupPath)) {
            return [pscustomobject]@{ IsValid = $false; Reason = "manifest-identity-invalid"; Manifest = $manifest }
        }

        $rootPrefix = (Get-FullPath -Path $BackupPath) + [System.IO.Path]::DirectorySeparatorChar
        $listedPaths = @()
        foreach ($entry in @($manifest.files)) {
            $relative = [string]$entry.path
            if (-not $relative -or [System.IO.Path]::IsPathRooted($relative) -or $relative -match '(^|/)\.\.(/|$)') {
                return [pscustomobject]@{ IsValid = $false; Reason = "manifest-path-invalid"; Manifest = $manifest }
            }
            $fullPath = [System.IO.Path]::GetFullPath((Join-Path $BackupPath ($relative -replace '/', '\')))
            if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -or
                -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                return [pscustomobject]@{ IsValid = $false; Reason = "backup-file-missing"; Manifest = $manifest }
            }
            $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($hash -ne [string]$entry.sha256 -or (Get-Item -LiteralPath $fullPath).Length -ne [long]$entry.sizeBytes) {
                return [pscustomobject]@{ IsValid = $false; Reason = "checksum-mismatch"; Manifest = $manifest }
            }
            $listedPaths += $relative
        }

        $actualPaths = @((Get-BackupFileEntries -BackupPath $BackupPath).path | Sort-Object)
        $expectedPaths = @($listedPaths | Sort-Object)
        if (($actualPaths -join "`n") -ne ($expectedPaths -join "`n")) {
            return [pscustomobject]@{ IsValid = $false; Reason = "manifest-file-set-mismatch"; Manifest = $manifest }
        }
        return [pscustomobject]@{ IsValid = $true; Reason = "valid"; Manifest = $manifest }
    }
    catch {
        return [pscustomobject]@{ IsValid = $false; Reason = "manifest-unreadable"; Manifest = $null }
    }
}

function New-GiteaBackupSet {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][ValidateSet("upgrade", "pre-restore-diagnostic")][string]$Kind,
        [object]$GiteaContainer,
        [Parameter(Mandatory = $true)][object]$PostgresContainer,
        [string]$SourceVersion,
        [bool]$RunnerWasRunning,
        [Parameter(Mandatory = $true)][object]$Capacity
    )

    $backupRoot = Ensure-BackupRoot -Context $Context
    $backupId = "{0}-{1}" -f [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ"), [Guid]::NewGuid().ToString("N")
    $backupPath = Join-Path $backupRoot $backupId
    New-Item -ItemType Directory -Path $backupPath | Out-Null
    Set-RestrictedBackupAcl -Path $backupPath

    $payloadPath = Join-Path $backupPath "payload"
    $dataPath = Join-Path $payloadPath "gitea-data"
    $configPath = Join-Path $payloadPath "gitea-config"
    $operatorPath = Join-Path $payloadPath "operator-state"
    $privatePath = Join-Path $payloadPath "private"
    foreach ($directory in @($payloadPath, $dataPath, $configPath, $operatorPath, $privatePath)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    Copy-DirectoryTree -Source $Context.GiteaDataDir -Destination $dataPath
    Copy-DirectoryTree -Source $Context.GiteaConfigDir -Destination $configPath
    if (-not (Test-Path -LiteralPath $Context.ConfigPath -PathType Leaf)) {
        throw "The active Gitea bootstrap config is missing; refusing to create a partial backup."
    }
    if (((Get-Item -LiteralPath $Context.ConfigPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "The active Gitea bootstrap config is a reparse point; refusing to back up redirected settings."
    }
    Copy-Item -LiteralPath $Context.ConfigPath -Destination (Join-Path $operatorPath "bootstrap-config.json")
    foreach ($entry in @(
        @{ Source = $Context.GiteaSecretsPath; Name = "generated-secrets.json" },
        @{ Source = $Context.GiteaBootstrapSummaryPath; Name = "bootstrap-summary.json" },
        @{ Source = $Context.EffectiveBootstrapSettingsPath; Name = "effective-settings.json" }
    )) {
        if (Test-Path -LiteralPath $entry.Source -PathType Leaf) {
            if (((Get-Item -LiteralPath $entry.Source -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Operator state file '$($entry.Source)' is a reparse point; refusing to back up redirected settings."
            }
            Copy-Item -LiteralPath $entry.Source -Destination (Join-Path $operatorPath $entry.Name)
        }
    }

    $runtime = Get-RuntimeSnapshot -Context $Context -Container $GiteaContainer -SourceVersion $SourceVersion
    Save-BackupJson -Path (Join-Path $privatePath "gitea-runtime.json") -Value $runtime
    Save-BackupJson -Path (Join-Path $privatePath "postgres-topology.json") -Value (Get-PostgresTopologySnapshot -Container $PostgresContainer)
    Save-BackupJson -Path (Join-Path $privatePath "restore-context.json") -Value @{
        configPath = [string]$Context.ConfigPath
        configSource = [string]$Context.ConfigSource
        databaseName = [string]$Context.GiteaPostgresDbName
        databaseUser = [string]$Context.GiteaPostgresUser
        runnerWasRunning = $RunnerWasRunning
    }

    $dumpPath = Join-Path $payloadPath "postgres.dump"
    $dumpCommand = 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump --format=custom --no-owner --no-acl --username "$POSTGRES_USER" --dbname "$POSTGRES_DB"'
    Invoke-GiteaDockerToFile -Arguments @("exec", $Context.GiteaPostgresContainerName, "sh", "-c", $dumpCommand) -OutputPath $dumpPath
    $dumpStream = [System.IO.File]::OpenRead($dumpPath)
    try {
        $magic = New-Object byte[] 5
        $read = $dumpStream.Read($magic, 0, 5)
    }
    finally {
        $dumpStream.Dispose()
    }
    if ($read -ne 5 -or [System.Text.Encoding]::ASCII.GetString($magic) -ne "PGDMP") {
        throw "The PostgreSQL dump did not pass its archive-format check; Gitea will not be recreated."
    }

    $files = Get-BackupFileEntries -BackupPath $backupPath
    $totalBytes = [long](($files | Measure-Object -Property sizeBytes -Sum).Sum)
    $manifest = @{
        schemaVersion = 1
        backupId = $backupId
        kind = $Kind
        createdAt = [DateTime]::UtcNow.ToString("o")
        sourceVersion = $SourceVersion
        sourceImage = if ($runtime) { [string]$runtime.originalImageReference } else { "unavailable" }
        sourceImageDigest = if ($runtime) { [string]$runtime.imageReference } else { "unavailable" }
        dockerHost = $Context.DockerHost
        hostPort = $Context.GiteaHttpPort
        network = $Context.GiteaNetworkName
        runnerWasRunning = $RunnerWasRunning
        sourceBytes = [long]$Capacity.SourceBytes
        availableBytesBeforeBackup = [long]$Capacity.AvailableFreeBytes
        sizeBytes = $totalBytes
        files = $files
    }
    Save-BackupJson -Path (Join-Path $backupPath "manifest.json") -Value $manifest
    $validation = Test-GiteaBackupIntegrity -BackupPath $backupPath
    if (-not $validation.IsValid) {
        throw "The new Gitea backup failed integrity validation ($($validation.Reason)); Gitea will not be recreated."
    }

    return [pscustomobject]@{
        BackupId = $backupId
        Path = $backupPath
        Manifest = $manifest
    }
}

function Get-GiteaBackupById {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$BackupId
    )

    if ($BackupId -notmatch '^\d{8}T\d{6}Z-[0-9a-f]{32}$') {
        throw "Backup ID has an invalid format."
    }
    $backupRoot = Ensure-BackupRoot -Context $Context
    $backupPath = Join-Path $backupRoot $BackupId
    if (-not (Test-Path -LiteralPath $backupPath -PathType Container)) {
        throw "Backup ID '$BackupId' was not found."
    }
    $validation = Test-GiteaBackupIntegrity -BackupPath $backupPath
    if (-not $validation.IsValid) {
        throw "Backup '$BackupId' failed integrity validation ($($validation.Reason)); restore is blocked."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $backupPath "payload\postgres.dump") -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $backupPath "payload\private\gitea-runtime.json") -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $backupPath "payload\private\postgres-topology.json") -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $backupPath "payload\private\restore-context.json") -PathType Leaf)) {
        throw "Backup '$BackupId' is missing required restore payloads."
    }
    return [pscustomobject]@{
        Path = $backupPath
        Manifest = $validation.Manifest
    }
}

function Show-GiteaBackupList {
    param([hashtable]$Context)

    $backupRoot = Ensure-BackupRoot -Context $Context
    $directories = @(Get-ChildItem -LiteralPath $backupRoot -Directory -Force | Where-Object { $_.Name -match '^\d{8}T\d{6}Z-[0-9a-f]{32}$' } | Sort-Object Name -Descending)
    if ($directories.Count -eq 0) {
        Write-Host "No Gitea backups found under '$backupRoot'."
        return
    }

    foreach ($directory in $directories) {
        $validation = Test-GiteaBackupIntegrity -BackupPath $directory.FullName
        if ($validation.Manifest) {
            $manifest = $validation.Manifest
            $created = [string]$manifest.createdAt
            $version = [string]$manifest.sourceVersion
            $size = [long]$manifest.sizeBytes
        }
        else {
            $created = "unknown"
            $version = "unknown"
            $size = [long]0
        }
        Write-Host ("{0}  {1}  source={2}  size={3}  integrity={4}" -f $directory.Name, $created, $version, $size, $validation.Reason)
    }
}

function Get-BackupRuntime {
    param([Parameter(Mandatory = $true)][string]$BackupPath)

    $runtimePath = Join-Path $BackupPath "payload\private\gitea-runtime.json"
    $runtime = Get-Content -LiteralPath $runtimePath -Raw | ConvertFrom-Json
    if (-not $runtime -or -not $runtime.imageReference -or -not $runtime.mounts -or -not $runtime.ports) {
        throw "The backup does not contain enough protected runtime metadata to restore the Gitea container."
    }
    return $runtime
}

function Assert-BackupRuntimeMatchesContext {
    param([hashtable]$Context, [object]$Runtime)

    if ([string]$Runtime.containerName -ne $Context.GiteaContainerName -or
        [string]$Runtime.networkMode -ne $Context.GiteaNetworkName) {
        throw "The selected backup belongs to a different Gitea container or network; restore is blocked."
    }

    $expectedMounts = @{
        "/var/lib/gitea" = $Context.GiteaDataDir
        "/etc/gitea" = $Context.GiteaConfigDir
    }
    if (@($Runtime.mounts).Count -ne $expectedMounts.Count -or @($Runtime.ports).Count -ne 2) {
        throw "The selected backup contains an unexpected Gitea mount or port topology."
    }
    foreach ($destination in $expectedMounts.Keys) {
        $mount = @($Runtime.mounts | Where-Object { [string]$_.destination -eq $destination -and [string]$_.type -eq "bind" }) | Select-Object -First 1
        if (-not $mount) {
            throw "The selected backup does not record the expected '$destination' bind mount."
        }
        $actual = Get-FullPath -Path (ConvertFrom-DockerHostPath -Path ([string]$mount.source))
        $expected = Get-FullPath -Path $expectedMounts[$destination]
        if (-not $actual.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
            throw "The selected backup belongs to a different host data path; restore is blocked."
        }
    }

    $httpBinding = @($Runtime.ports | Where-Object { $_.containerPort -eq "3000/tcp" }) | Select-Object -First 1
    $sshBinding = @($Runtime.ports | Where-Object { $_.containerPort -eq "2222/tcp" }) | Select-Object -First 1
    if (-not $httpBinding -or $httpBinding.hostIp -ne $Context.PortBindAddress -or [int]$httpBinding.hostPort -ne 43000 -or
        -not $sshBinding -or $sshBinding.hostIp -ne $Context.PortBindAddress -or [int]$sshBinding.hostPort -ne $Context.GiteaSshPort) {
        throw "The selected backup does not identify the expected legacy 43000 topology."
    }
    if ([string]$Runtime.imageReference -notmatch '(@sha256:[0-9a-f]{64}$|^sha256:[0-9a-f]{64}$)') {
        throw "The selected backup does not identify an immutable source image."
    }
}

function Write-TemporaryEnvironmentFile {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][string[]]$Environment
    )

    foreach ($entry in $Environment) {
        if ($entry -match '[\r\n]') {
            throw "The captured Gitea environment contains a line break and cannot be restored safely."
        }
    }
    $backupRoot = Ensure-BackupRoot -Context $Context
    $path = Join-Path $backupRoot (".gitea-env-{0}.tmp" -f [Guid]::NewGuid().ToString("N"))
    [System.IO.File]::WriteAllLines($path, $Environment, [System.Text.UTF8Encoding]::new($false))
    Set-RestrictedBackupAcl -Path $path
    return $path
}

function New-GiteaContainerFromRuntime {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][object]$Runtime,
        [Parameter(Mandatory = $true)][string]$ImageReference
    )

    Assert-BackupRuntimeMatchesContext -Context $Context -Runtime $Runtime
    $environmentFile = Write-TemporaryEnvironmentFile -Context $Context -Environment @($Runtime.environment)
    try {
        $arguments = @("run", "-d", "--name", $Context.GiteaContainerName, "--restart", [string]$Runtime.restartPolicy)
        foreach ($binding in @($Runtime.ports)) {
            $arguments += @("-p", "$($binding.hostIp):$($binding.hostPort):$($binding.containerPort)")
        }
        foreach ($mount in @($Runtime.mounts)) {
            if ([string]$mount.type -ne "bind") {
                throw "The source Gitea container uses an unsupported mount type; refusing an incomplete recreation."
            }
            $hostPath = switch ([string]$mount.destination) {
                "/var/lib/gitea" { $Context.GiteaDataDir }
                "/etc/gitea" { $Context.GiteaConfigDir }
                default { throw "The backup contains an unexpected Gitea mount destination." }
            }
            $mountArgument = "type=bind,source=$hostPath,target=$($mount.destination)"
            if (-not [bool]$mount.readWrite) { $mountArgument += ",readonly" }
            $arguments += @("--mount", $mountArgument)
        }
        $arguments += @("--network", [string]$Runtime.networkMode, "--env-file", $environmentFile, $ImageReference)
        [void](Invoke-GiteaDocker -Arguments $arguments)
    }
    finally {
        if (Test-Path -LiteralPath $environmentFile -PathType Leaf) {
            Remove-Item -LiteralPath $environmentFile -Force
        }
    }
}

function Wait-GiteaHealthy {
    param(
        [hashtable]$Context,
        [int]$TimeoutSeconds = 180
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $Context.GiteaRootUrl -Method Get -UseBasicParsing -TimeoutSec 5
            if ([int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 400) { return }
        }
        catch { }
        Start-Sleep -Seconds 2
    }
    throw "Gitea did not become reachable at the configured legacy endpoint within $TimeoutSeconds seconds."
}

function Assert-GiteaApiVersion {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$ExpectedVersion
    )

    try {
        $result = Invoke-RestMethod -Uri ($Context.GiteaRootUrl.TrimEnd('/') + "/api/v1/version") -Method Get -TimeoutSec 10
    }
    catch {
        throw "Gitea's version API did not respond after container startup."
    }
    if ([string]$result.version -ne $ExpectedVersion) {
        throw "Gitea's API reports '$($result.version)' after startup; expected '$ExpectedVersion'."
    }
}

function Invoke-GiteaPostgresRestore {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$DumpPath
    )

    $restoreCommand = 'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore --clean --if-exists --no-owner --no-acl --username "$POSTGRES_USER" --dbname "$POSTGRES_DB"'
    Invoke-GiteaDockerWithInputFile -Arguments @("exec", "-i", $Context.GiteaPostgresContainerName, "sh", "-c", $restoreCommand) -InputPath $DumpPath
}

function Get-GiteaApiHealth {
    param([hashtable]$Context)

    try {
        $response = Invoke-RestMethod -Uri ($Context.GiteaRootUrl.TrimEnd('/') + "/api/v1/version") -Method Get -TimeoutSec 5
        return [pscustomobject]@{ IsHealthy = $true; Version = [string]$response.version }
    }
    catch {
        return [pscustomobject]@{ IsHealthy = $false; Version = "" }
    }
}

function Read-GiteaRestoreContext {
    param([Parameter(Mandatory = $true)][string]$BackupPath)
    return Get-Content -LiteralPath (Join-Path $BackupPath "payload\private\restore-context.json") -Raw | ConvertFrom-Json
}

function Assert-ConfigRestoreCompatibility {
    param(
        [hashtable]$Context,
        [object]$RestoreContext
    )

    if ([string]$RestoreContext.configSource -in @("local", "custom")) {
        if (-not $RestoreContext.configPath -or
            -not (Get-FullPath -Path ([string]$RestoreContext.configPath)).Equals((Get-FullPath -Path $Context.ConfigPath), [StringComparison]::OrdinalIgnoreCase)) {
            throw "The selected backup's sensitive bootstrap config belongs to a different path; restore is blocked."
        }
    }
}

function Restore-GiteaOperatorState {
    param(
        [hashtable]$Context,
        [string]$BackupPath,
        [object]$RestoreContext
    )

    $operatorPath = Join-Path $BackupPath "payload\operator-state"
    if ([string]$RestoreContext.configSource -in @("local", "custom")) {
        Copy-Item -LiteralPath (Join-Path $operatorPath "bootstrap-config.json") -Destination $RestoreContext.configPath -Force
    }
    foreach ($entry in @(
        @{ Name = "generated-secrets.json"; Destination = $Context.GiteaSecretsPath },
        @{ Name = "bootstrap-summary.json"; Destination = $Context.GiteaBootstrapSummaryPath },
        @{ Name = "effective-settings.json"; Destination = $Context.EffectiveBootstrapSettingsPath }
    )) {
        $source = Join-Path $operatorPath $entry.Name
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source -Destination $entry.Destination -Force
        }
        elseif (Test-Path -LiteralPath $entry.Destination -PathType Leaf) {
            Remove-Item -LiteralPath $entry.Destination -Force
        }
    }
}

function Replace-GiteaDataTree {
    param(
        [Parameter(Mandatory = $true)][string]$BackupSource,
        [Parameter(Mandatory = $true)][string]$LiveDestination
    )

    if (Test-Path -LiteralPath $LiveDestination) {
        if (((Get-Item -LiteralPath $LiveDestination -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Live Gitea destination '$LiveDestination' is a reparse point; refusing to overwrite redirected data."
        }
        Remove-Item -LiteralPath $LiveDestination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $LiveDestination -Force | Out-Null
    Copy-DirectoryTree -Source $BackupSource -Destination $LiveDestination
}

function Confirm-GiteaLifecycleOperation {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$ExpectedText
    )

    $response = Read-Host $Prompt
    if ($response -cne $ExpectedText) {
        throw "Confirmation did not match; no lifecycle operation was started."
    }
}

function New-GiteaOperationRecord {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][object]$Record
    )

    $recordDirectory = Join-Path $Context.RepoRoot ".agent-sdlc\dev-env\gitea\upgrades"
    if (-not (Test-Path -LiteralPath $recordDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $recordDirectory -Force | Out-Null
    }
    $recordPath = Join-Path $recordDirectory ("{0}.json" -f $Record.operationId)
    Save-BackupJson -Path $recordPath -Value $Record
}

function Get-GiteaLifecycleRecoveryMarkerPath {
    param([hashtable]$Context)
    return Join-Path $Context.RepoRoot ".agent-sdlc\dev-env\gitea\lifecycle-recovery.json"
}

function Assert-NoPendingGiteaRecovery {
    param([hashtable]$Context)

    $markerPath = Get-GiteaLifecycleRecoveryMarkerPath -Context $Context
    if (-not (Test-Path -LiteralPath $markerPath)) { return }
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
        throw "A Gitea lifecycle recovery marker exists but is not a file; automatic lifecycle operations are blocked."
    }
    try {
        $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "A Gitea lifecycle recovery marker is unreadable; automatic bootstrap is blocked until an operator reviews it."
    }
    throw "A previous Gitea $($marker.operationKind) operation is incomplete. Automatic bootstrap is blocked; use an explicitly confirmed restore. Backup ID: '$($marker.backupId)'."
}

function Set-GiteaLifecycleRecoveryMarker {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][ValidateSet("upgrade", "restore")][string]$OperationKind,
        [Parameter(Mandatory = $true)][string]$BackupId,
        [string]$DiagnosticBackupId
    )

    $markerPath = Get-GiteaLifecycleRecoveryMarkerPath -Context $Context
    $markerDirectory = Split-Path -Parent $markerPath
    if (-not (Test-Path -LiteralPath $markerDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $markerDirectory -Force | Out-Null
    }
    $temporaryPath = Join-Path $markerDirectory (".lifecycle-recovery-{0}.tmp" -f [Guid]::NewGuid().ToString("N"))
    try {
        Save-BackupJson -Path $temporaryPath -Value @{
            schemaVersion = 1
            operationKind = $OperationKind
            backupId = $BackupId
            diagnosticBackupId = $DiagnosticBackupId
            createdAt = [DateTime]::UtcNow.ToString("o")
        }
        Move-Item -LiteralPath $temporaryPath -Destination $markerPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Clear-GiteaLifecycleRecoveryMarker {
    param([hashtable]$Context)

    $markerPath = Get-GiteaLifecycleRecoveryMarkerPath -Context $Context
    if ((Test-Path -LiteralPath $markerPath) -and -not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
        throw "The Gitea lifecycle recovery marker path is not a file; refusing to clear it automatically."
    }
    if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
        Remove-Item -LiteralPath $markerPath -Force
    }
}

function Assert-GiteaConfigCanBePinned {
    param([hashtable]$Context)

    if ($Context.GiteaImageEnvironmentOverride) {
        throw "Clear AGENT_SDLC_GITEA_IMAGE before lifecycle operations; the environment override would supersede the pinned local bootstrap config."
    }
    if ([string]$Context.ConfigSource -ne "local" -or
        -not (Get-FullPath -Path $Context.ConfigPath).Equals((Get-FullPath -Path $Context.LocalConfigPath), [StringComparison]::OrdinalIgnoreCase)) {
        throw "Generate and use the ignored local Gitea bootstrap config before upgrading; the tracked template must never be changed by a lifecycle operation."
    }
    $temporaryPath = Join-Path (Split-Path -Parent $Context.ConfigPath) (".gitea-config-preflight-{0}.tmp" -f [Guid]::NewGuid().ToString("N"))
    try {
        [System.IO.File]::WriteAllText($temporaryPath, "preflight", [System.Text.UTF8Encoding]::new($false))
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Set-GiteaBootstrapImagePin {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$ImageReference
    )

    $config = Get-Content -LiteralPath $Context.ConfigPath -Raw | ConvertFrom-Json
    $config.gitea.image = $ImageReference
    $temporaryPath = Join-Path (Split-Path -Parent $Context.ConfigPath) (".gitea-config-{0}.tmp" -f [Guid]::NewGuid().ToString("N"))
    try {
        Save-BackupJson -Path $temporaryPath -Value $config
        Move-Item -LiteralPath $temporaryPath -Destination $Context.ConfigPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Resume-GiteaUpgradeSource {
    param(
        [hashtable]$Context,
        [bool]$RunnerWasRunning
    )

    $source = Get-GiteaContainerInfo -Name $Context.GiteaContainerName
    if (-not $source) {
        throw "The unchanged source Gitea container '$($Context.GiteaContainerName)' is missing."
    }
    if ([string]$source.State.Status -ne "running") {
        [void](Invoke-GiteaDocker -Arguments @("start", $Context.GiteaContainerName))
    }
    Wait-GiteaHealthy -Context $Context -TimeoutSeconds 120
    if ($RunnerWasRunning) {
        Start-GiteaRunner -Name $Context.GiteaRunnerContainerName
    }
}

function Invoke-GiteaUpgrade {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$GiteaVersion
    )

    Assert-NativeWindowsHost
    $Context.DockerHost = Assert-DockerDesktopReady
    Assert-NoPendingGiteaRecovery -Context $Context
    if ($GiteaVersion -notmatch '^\d+\.\d+\.\d+$') {
        throw "Supply an explicit fixed Gitea x.y.z version with -GiteaVersion; floating tags are not accepted."
    }
    if ([string]$Context.GiteaRunnerContainerName -eq [string]$Context.GiteaContainerName -or
        -not $Context.GiteaRunnerContainerName) {
        throw "The configured shared Runner must remain a distinct existing container."
    }

    $null = Ensure-BackupRoot -Context $Context
    Assert-GiteaConfigCanBePinned -Context $Context
    $gitea = Assert-GiteaContainerIdentity -Context $Context
    $postgres = Assert-PostgresContainerIdentity -Context $Context
    Assert-GiteaDatabaseTarget -GiteaContainer $gitea -PostgresContainer $postgres -Context $Context
    $runner = Get-GiteaRunnerInfo -Context $Context
    $runnerWasRunning = [string]$runner.State.Status -eq "running"
    $sourceVersion = Get-GiteaReportedVersion -Container $gitea
    Assert-SupportedGiteaVersionStep -CurrentVersion $sourceVersion -TargetVersion $GiteaVersion
    Assert-NoActiveGiteaActions -Context $Context
    $capacity = Assert-BackupCapacity -Context $Context

    $targetTag = "docker.gitea.com/gitea:$GiteaVersion-rootless"
    Confirm-GiteaLifecycleOperation -Prompt "Type UPGRADE $GiteaVersion ON agent-sdlc-gitea:43000 to continue" -ExpectedText "UPGRADE $GiteaVersion ON agent-sdlc-gitea:43000"
    [void](Invoke-GiteaDocker -Arguments @("pull", $targetTag))
    $targetImage = Get-ImageDigestReference -Image $targetTag -RequireRegistryDigest
    $capacity = Assert-BackupCapacity -Context $Context

    # Close the window for new work before stopping Gitea. Any queued or active run blocks the snapshot.
    Assert-NoActiveGiteaActions -Context $Context
    try {
        Stop-GiteaRunner -Name $Context.GiteaRunnerContainerName
        Assert-NoActiveGiteaActions -Context $Context
        [void](Invoke-GiteaDocker -Arguments @("stop", "--time", "60", $Context.GiteaContainerName))
    }
    catch {
        try {
            Resume-GiteaUpgradeSource -Context $Context -RunnerWasRunning $runnerWasRunning
        }
        catch {
            throw "The upgrade stopped before backup or data migration, but the unchanged source service could not be resumed. Inspect Gitea and Runner container state."
        }
        throw
    }

    try {
        $backup = New-GiteaBackupSet -Context $Context -Kind upgrade -GiteaContainer $gitea -PostgresContainer $postgres -SourceVersion $sourceVersion -RunnerWasRunning $runnerWasRunning -Capacity $capacity
    }
    catch {
        # No new Image has started, so the unchanged source container is safe to resume.
        try {
            Resume-GiteaUpgradeSource -Context $Context -RunnerWasRunning $runnerWasRunning
        }
        catch {
            throw "Backup creation failed before upgrade. The source data was not migrated; Gitea or Runner could not be resumed automatically. Inspect the incomplete backup and container state."
        }
        throw
    }

    try {
        Set-GiteaLifecycleRecoveryMarker -Context $Context -OperationKind upgrade -BackupId $backup.BackupId
    }
    catch {
        try {
            Resume-GiteaUpgradeSource -Context $Context -RunnerWasRunning $runnerWasRunning
        }
        catch {
            throw "The backup is valid, but the recovery marker could not be written and the unchanged source service could not be resumed. Inspect Backup ID '$($backup.BackupId)' and container state."
        }
        throw
    }

    $oldContainerName = "$($Context.GiteaContainerName)-preupgrade-$($backup.BackupId)"
    [void](Invoke-GiteaDocker -Arguments @("rename", $Context.GiteaContainerName, $oldContainerName))
    try {
        $runtime = Get-BackupRuntime -BackupPath $backup.Path
        New-GiteaContainerFromRuntime -Context $Context -Runtime $runtime -ImageReference $targetImage
        Wait-GiteaHealthy -Context $Context
        Assert-GiteaApiVersion -Context $Context -ExpectedVersion $GiteaVersion
    }
    catch {
        throw "Gitea upgrade did not pass its startup/version health checks. Backup '$($backup.BackupId)' and the stopped source container '$oldContainerName' are retained; no automatic rollback was attempted. $($_.Exception.Message)"
    }

    try {
        # Keep the bootstrap image unchanged until the migrated service proves healthy.
        Set-GiteaBootstrapImagePin -Context $Context -ImageReference $targetImage
    }
    catch {
        throw "Gitea passed startup/version health checks, but the bootstrap image pin could not be updated. Recovery marker and backup '$($backup.BackupId)' are retained; the Runner remains stopped."
    }
    if ($runnerWasRunning) {
        try {
            Start-GiteaRunner -Name $Context.GiteaRunnerContainerName
        }
        catch {
            throw "Gitea passed startup/version health checks, but the original Runner could not be resumed. Recovery marker and backup '$($backup.BackupId)' are retained."
        }
    }

    $record = @{
        schemaVersion = 1
        operationId = $backup.BackupId
        result = "healthy-manual-smoke-required"
        completedAt = [DateTime]::UtcNow.ToString("o")
        sourceVersion = $sourceVersion
        targetVersion = $GiteaVersion
        targetImageDigest = $targetImage
        sourceContainerName = $oldContainerName
        activeContainerName = $Context.GiteaContainerName
        backupId = $backup.BackupId
        endpoint = $Context.GiteaRootUrl
        dockerHost = $Context.DockerHost
        automaticHealthChecks = @("HTTP endpoint", "Gitea version API")
        manualSmokeStillRequired = @("Git read/write", "Registry", "Actions dispatch", "Runner execution", "Run Attempt visibility", "representative integrations")
    }
    New-GiteaOperationRecord -Context $Context -Record $record
    Clear-GiteaLifecycleRecoveryMarker -Context $Context
    Write-Host "Gitea '$sourceVersion' was upgraded to '$GiteaVersion' and passed HTTP/API health checks."
    Write-Host "Backup ID: $($backup.BackupId)"
    Write-Host "The old Gitea container is retained as '$oldContainerName'; PostgreSQL and the shared Runner were not recreated."
    Write-Host "Complete TC-011's Git, Registry, Actions, Runner, and Run Attempt smoke checks before treating the live upgrade as accepted."
}

function Invoke-GiteaRestore {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$BackupId
    )

    Assert-NativeWindowsHost
    $Context.DockerHost = Assert-DockerDesktopReady
    $selected = Get-GiteaBackupById -Context $Context -BackupId $BackupId
    $runtime = Get-BackupRuntime -BackupPath $selected.Path
    Assert-BackupRuntimeMatchesContext -Context $Context -Runtime $runtime
    $restoreContext = Read-GiteaRestoreContext -BackupPath $selected.Path
    Assert-ConfigRestoreCompatibility -Context $Context -RestoreContext $restoreContext
    if ([string]$restoreContext.databaseName -ne [string]$Context.GiteaPostgresDbName -or
        [string]$restoreContext.databaseUser -ne [string]$Context.GiteaPostgresUser) {
        throw "The selected backup's PostgreSQL database name or user differs from the configured existing service; restore is blocked."
    }
    $postgresTopology = Get-Content -LiteralPath (Join-Path $selected.Path "payload\private\postgres-topology.json") -Raw | ConvertFrom-Json
    if ([string]$restoreContext.configSource -eq "local") {
        Assert-GiteaConfigCanBePinned -Context $Context
    }

    $postgres = Assert-PostgresContainerIdentity -Context $Context
    Assert-PostgresRestoreCompatibility -BackupTopology $postgresTopology -CurrentContainer $postgres -Context $Context
    $capturedGitea = [pscustomobject]@{ Config = [pscustomobject]@{ Env = @($runtime.environment) } }
    Assert-GiteaDatabaseTarget -GiteaContainer $capturedGitea -PostgresContainer $postgres -Context $Context
    $gitea = Assert-GiteaContainerIdentity -Context $Context -AllowStopped -AllowMissing
    $runner = Get-GiteaRunnerInfo -Context $Context
    $runnerWasRunningNow = [string]$runner.State.Status -eq "running"
    $giteaWasRunning = $gitea -and [string]$gitea.State.Status -eq "running"
    $apiHealth = Get-GiteaApiHealth -Context $Context
    if ($apiHealth.IsHealthy -and -not $giteaWasRunning) {
        throw "The legacy endpoint responds without the expected running Gitea container identity; restore is blocked."
    }
    if ($apiHealth.IsHealthy) {
        Assert-NoActiveGiteaActions -Context $Context
    }
    elseif ($runnerWasRunningNow) {
        throw "Gitea API is unavailable while the shared Runner is running; active jobs cannot be ruled out, so restore is blocked."
    }

    $targetImage = [string]$runtime.imageReference
    if ($targetImage -match '^docker\.gitea\.com/gitea@sha256:') {
        [void](Invoke-GiteaDocker -Arguments @("pull", $targetImage))
    }
    else {
        [void](Invoke-GiteaDocker -Arguments @("image", "inspect", $targetImage))
    }
    $capacity = Assert-BackupCapacity -Context $Context
    Confirm-GiteaLifecycleOperation -Prompt "Type RESTORE $BackupId TO agent-sdlc-gitea:43000 to overwrite the current instance" -ExpectedText "RESTORE $BackupId TO agent-sdlc-gitea:43000"

    if ($runnerWasRunningNow) {
        Stop-GiteaRunner -Name $Context.GiteaRunnerContainerName
        if ($apiHealth.IsHealthy) {
            try {
                Assert-NoActiveGiteaActions -Context $Context
            }
            catch {
                Start-GiteaRunner -Name $Context.GiteaRunnerContainerName
                throw
            }
        }
    }
    if ($gitea -and [string]$gitea.State.Status -eq "running") {
        [void](Invoke-GiteaDocker -Arguments @("stop", "--time", "60", $Context.GiteaContainerName))
    }

    $diagnosticVersion = "unavailable"
    if ($gitea) {
        try { $diagnosticVersion = Get-GiteaReportedVersion -Container $gitea }
        catch { $diagnosticVersion = "unavailable" }
    }
    try {
        $diagnostic = New-GiteaBackupSet -Context $Context -Kind pre-restore-diagnostic -GiteaContainer $gitea -PostgresContainer $postgres -SourceVersion $diagnosticVersion -RunnerWasRunning $runnerWasRunningNow -Capacity $capacity
    }
    catch {
        try {
            if ($giteaWasRunning) {
                [void](Invoke-GiteaDocker -Arguments @("start", $Context.GiteaContainerName))
                if ($apiHealth.IsHealthy) { Wait-GiteaHealthy -Context $Context -TimeoutSeconds 120 }
            }
            if ($runnerWasRunningNow) { Start-GiteaRunner -Name $Context.GiteaRunnerContainerName }
        }
        catch {
            throw "Diagnostic backup creation failed before restore. No database or Gitea files were overwritten, but the original service state could not be resumed automatically. Inspect the incomplete diagnostic backup and container state."
        }
        throw
    }

    try {
        Set-GiteaLifecycleRecoveryMarker -Context $Context -OperationKind restore -BackupId $BackupId -DiagnosticBackupId $diagnostic.BackupId
    }
    catch {
        try {
            if ($giteaWasRunning) {
                [void](Invoke-GiteaDocker -Arguments @("start", $Context.GiteaContainerName))
                if ($apiHealth.IsHealthy) { Wait-GiteaHealthy -Context $Context -TimeoutSeconds 120 }
            }
            if ($runnerWasRunningNow) { Start-GiteaRunner -Name $Context.GiteaRunnerContainerName }
        }
        catch {
            throw "The diagnostic backup exists, but the recovery marker could not be written and the original service state could not be resumed. Inspect both Backup IDs and container state."
        }
        throw
    }

    if ($gitea) {
        $failedContainerName = "$($Context.GiteaContainerName)-failed-$($diagnostic.BackupId)"
        [void](Invoke-GiteaDocker -Arguments @("rename", $Context.GiteaContainerName, $failedContainerName))
    }

    $dumpPath = Join-Path $selected.Path "payload\postgres.dump"
    Invoke-GiteaPostgresRestore -Context $Context -DumpPath $dumpPath
    Replace-GiteaDataTree -BackupSource (Join-Path $selected.Path "payload\gitea-data") -LiveDestination $Context.GiteaDataDir
    Replace-GiteaDataTree -BackupSource (Join-Path $selected.Path "payload\gitea-config") -LiveDestination $Context.GiteaConfigDir
    Restore-GiteaOperatorState -Context $Context -BackupPath $selected.Path -RestoreContext $restoreContext
    if ([string]$restoreContext.configSource -eq "local") {
        Set-GiteaBootstrapImagePin -Context $Context -ImageReference $targetImage
    }

    New-GiteaContainerFromRuntime -Context $Context -Runtime $runtime -ImageReference $targetImage
    Wait-GiteaHealthy -Context $Context
    Assert-GiteaApiVersion -Context $Context -ExpectedVersion ([string]$runtime.sourceVersion)
    if ([bool]$selected.Manifest.runnerWasRunning) {
        Start-GiteaRunner -Name $Context.GiteaRunnerContainerName
    }

    New-GiteaOperationRecord -Context $Context -Record @{
        schemaVersion = 1
        operationId = "$($diagnostic.BackupId)-restore"
        result = "restored-manual-smoke-required"
        completedAt = [DateTime]::UtcNow.ToString("o")
        backupId = $BackupId
        diagnosticBackupId = $diagnostic.BackupId
        restoredVersion = [string]$runtime.sourceVersion
        restoredImageDigest = $targetImage
        activeContainerName = $Context.GiteaContainerName
        endpoint = $Context.GiteaRootUrl
        dockerHost = $Context.DockerHost
        automaticHealthChecks = @("HTTP endpoint", "Gitea version API")
        manualSmokeStillRequired = @("Git read/write", "Registry", "Actions dispatch", "Runner execution", "Run Attempt visibility", "representative integrations")
    }
    Clear-GiteaLifecycleRecoveryMarker -Context $Context

    Write-Host "Restored Gitea from Backup ID '$BackupId' and passed HTTP/API health checks."
    Write-Host "Diagnostic backup ID: $($diagnostic.BackupId); the overwritten state is retained."
    Write-Host "PostgreSQL and the shared Runner identities/storage were preserved. Complete TC-011's remaining manual smoke checks."
}

function Invoke-GiteaLifecycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet("upgrade", "backup-list", "restore")][string]$Action,
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [string]$GiteaVersion,
        [string]$BackupId
    )

    switch ($Action) {
        "upgrade" {
            if (-not $GiteaVersion) { throw "The upgrade command requires -GiteaVersion <fixed-x.y.z>." }
            Invoke-GiteaUpgrade -Context $Context -GiteaVersion $GiteaVersion
        }
        "backup-list" {
            Assert-NativeWindowsHost
            Show-GiteaBackupList -Context $Context
        }
        "restore" {
            if (-not $BackupId) { throw "The restore command requires -BackupId <id>." }
            Invoke-GiteaRestore -Context $Context -BackupId $BackupId
        }
    }
}

Export-ModuleMember -Function Invoke-GiteaLifecycle
