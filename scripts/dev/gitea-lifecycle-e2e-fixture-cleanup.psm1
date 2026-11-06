function Get-GiteaLifecycleE2ENormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $rootPath = [System.IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Equals($rootPath, [StringComparison]::OrdinalIgnoreCase)) { return $fullPath }
    return $fullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

function ConvertTo-GiteaLifecycleE2EExtendedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = Get-GiteaLifecycleE2ENormalizedPath -Path $Path
    if ($fullPath -match '^[A-Za-z]:\\') { return '\\?\' + $fullPath }
    if ($fullPath.StartsWith('\\')) { return '\\?\UNC\' + $fullPath.Substring(2) }
    throw "Long-path fixture cleanup requires an absolute drive or UNC path."
}

function Test-GiteaLifecycleE2EPathExists {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        [void][System.IO.File]::GetAttributes((ConvertTo-GiteaLifecycleE2EExtendedPath -Path $Path))
        return $true
    }
    catch [System.IO.FileNotFoundException] { return $false }
    catch [System.IO.DirectoryNotFoundException] { return $false }
}

function Assert-GiteaLifecycleE2ENoReparseAncestors {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = Get-GiteaLifecycleE2ENormalizedPath -Path $Path
    $rootPath = [System.IO.Path]::GetPathRoot($fullPath)
    $currentPath = $rootPath
    $pathsToCheck = [System.Collections.Generic.List[string]]::new()
    $pathsToCheck.Add($currentPath)
    $remainder = $fullPath.Substring($rootPath.Length)
    foreach ($segment in @($remainder.Split([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)) | Where-Object { $_ })) {
        $currentPath = [System.IO.Path]::Combine($currentPath, $segment)
        $pathsToCheck.Add($currentPath)
    }

    foreach ($candidate in $pathsToCheck) {
        $attributes = [System.IO.File]::GetAttributes((ConvertTo-GiteaLifecycleE2EExtendedPath -Path $candidate))
        if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Fixture path component '$candidate' is a reparse point; refusing cleanup."
        }
        if (($attributes -band [System.IO.FileAttributes]::Directory) -eq 0) {
            throw "Fixture path component '$candidate' is not a directory; refusing cleanup."
        }
    }
}

function Assert-GiteaLifecycleE2ENoReparseTree {
    param([Parameter(Mandatory = $true)][string]$Path)

    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push((ConvertTo-GiteaLifecycleE2EExtendedPath -Path $Path))
    while ($pending.Count -gt 0) {
        $directoryPath = $pending.Pop()
        foreach ($entryPath in [System.IO.Directory]::EnumerateFileSystemEntries($directoryPath)) {
            $attributes = [System.IO.File]::GetAttributes($entryPath)
            if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Fixture tree contains reparse point '$entryPath'; refusing cleanup."
            }
            if (($attributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
                $pending.Push($entryPath)
            }
        }
    }
}

function Remove-GiteaLifecycleE2EFixtureEntry {
    param([Parameter(Mandatory = $true)][string]$ExtendedPath)

    $attributes = [System.IO.File]::GetAttributes($ExtendedPath)
    if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to remove reparse point '$ExtendedPath'."
    }

    if (($attributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
        foreach ($entryPath in [System.IO.Directory]::EnumerateFileSystemEntries($ExtendedPath)) {
            Remove-GiteaLifecycleE2EFixtureEntry -ExtendedPath $entryPath
        }
        [System.IO.File]::SetAttributes($ExtendedPath, [System.IO.FileAttributes]::Normal)
        [System.IO.Directory]::Delete($ExtendedPath, $false)
    }
    else {
        [System.IO.File]::SetAttributes($ExtendedPath, [System.IO.FileAttributes]::Normal)
        [System.IO.File]::Delete($ExtendedPath)
    }
}

function Remove-GiteaLifecycleE2EFixtureDirectory {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[0-9a-fA-F]{32}$')]
        [string]$RunId,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedPath,

        [string]$ApproveRunId
    )

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        throw "Fixture cleanup requires native Windows PowerShell."
    }

    $runPrefix = "agent-sdlc-life-e2e-$RunId"
    $tempPath = [System.Environment]::GetEnvironmentVariable('TEMP')
    if (-not $tempPath) {
        throw "The Windows TEMP environment variable is missing; refusing to infer a fixture path."
    }
    $tempRoot = Get-GiteaLifecycleE2ENormalizedPath -Path $tempPath
    $expectedRoot = Get-GiteaLifecycleE2ENormalizedPath -Path ([System.IO.Path]::Combine($tempRoot, $runPrefix))
    $actualRoot = Get-GiteaLifecycleE2ENormalizedPath -Path $ExpectedPath
    if (-not $actualRoot.Equals($expectedRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not ([System.IO.Path]::GetDirectoryName($actualRoot)).Equals($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not ([System.IO.Path]::GetFileName($actualRoot)).Equals($runPrefix, [StringComparison]::Ordinal)) {
        throw "Expected path does not match this run's exact GUID-named direct child of the Windows temp directory; refusing cleanup."
    }

    Assert-GiteaLifecycleE2ENoReparseAncestors -Path $tempRoot
    if (-not (Test-GiteaLifecycleE2EPathExists -Path $actualRoot)) {
        Write-Host "No residual fixture exists at '$actualRoot'; nothing was removed."
        return [pscustomobject]@{ RunId = $RunId; Path = $actualRoot; Removed = $false; Reason = 'not-found' }
    }

    $rootAttributes = [System.IO.File]::GetAttributes((ConvertTo-GiteaLifecycleE2EExtendedPath -Path $actualRoot))
    if (($rootAttributes -band [System.IO.FileAttributes]::Directory) -eq 0 -or
        ($rootAttributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Fixture root is not a regular directory; refusing cleanup."
    }

    $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $ownerSections = [System.Security.AccessControl.AccessControlSections]::Owner
    $rootAcl = [System.IO.Directory]::GetAccessControl(
        (ConvertTo-GiteaLifecycleE2EExtendedPath -Path $actualRoot),
        $ownerSections
    )
    $rootOwnerSid = $rootAcl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
    if (-not $currentSid.Equals($rootOwnerSid, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Fixture root owner does not match the current Windows user; refusing cleanup."
    }

    $markerPath = [System.IO.Path]::Combine($actualRoot, '.agent-sdlc-lifecycle-e2e-owner.json')
    if (-not (Test-GiteaLifecycleE2EPathExists -Path $markerPath)) {
        throw "Fixture ownership marker is missing; refusing cleanup."
    }
    $markerAttributes = [System.IO.File]::GetAttributes((ConvertTo-GiteaLifecycleE2EExtendedPath -Path $markerPath))
    if (($markerAttributes -band [System.IO.FileAttributes]::Directory) -ne 0 -or
        ($markerAttributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Fixture ownership marker is not a regular file; refusing cleanup."
    }
    $markerAcl = [System.IO.File]::GetAccessControl(
        (ConvertTo-GiteaLifecycleE2EExtendedPath -Path $markerPath),
        $ownerSections
    )
    $markerOwnerSid = $markerAcl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
    if (-not $currentSid.Equals($markerOwnerSid, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Fixture ownership marker owner does not match the current Windows user; refusing cleanup."
    }

    $marker = [System.IO.File]::ReadAllText((ConvertTo-GiteaLifecycleE2EExtendedPath -Path $markerPath)) | ConvertFrom-Json -ErrorAction Stop
    if ([string]$marker.runId -cne $RunId -or [string]$marker.prefix -cne $runPrefix) {
        throw "Fixture ownership marker does not match the requested run ID; refusing cleanup."
    }

    Assert-GiteaLifecycleE2ENoReparseTree -Path $actualRoot
    if (-not $WhatIfPreference -and $ApproveRunId -cne $RunId) {
        throw "To delete the verified fixture, pass -ApproveRunId with the same RunId after reviewing the candidate path."
    }

    Write-Host "Verified fixture cleanup candidate: $actualRoot"
    Write-Host "Verified Run ID and marker: $RunId / $($marker.prefix)"
    Write-Host "Verified root and marker owner SID: $currentSid"
    Write-Host "Verified path is the exact temp child and contains no reparse points."
    if ($PSCmdlet.ShouldProcess($actualRoot, "Remove this verified Gitea lifecycle E2E fixture")) {
        Remove-GiteaLifecycleE2EFixtureEntry -ExtendedPath (ConvertTo-GiteaLifecycleE2EExtendedPath -Path $actualRoot)
        if (Test-GiteaLifecycleE2EPathExists -Path $actualRoot) {
            throw "Fixture cleanup returned without removing the verified path."
        }
        Write-Host "Removed verified fixture directory '$actualRoot'."
        return [pscustomobject]@{ RunId = $RunId; Path = $actualRoot; Removed = $true; Reason = 'removed' }
    }

    return [pscustomobject]@{ RunId = $RunId; Path = $actualRoot; Removed = $false; Reason = 'what-if-or-declined' }
}

Export-ModuleMember -Function Remove-GiteaLifecycleE2EFixtureDirectory
