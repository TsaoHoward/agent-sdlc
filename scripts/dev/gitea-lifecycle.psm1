Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-NativeWindowsHost {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw "Gitea backup, upgrade, and restore operations must run from native Windows PowerShell on the Docker Desktop host."
    }
}

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $normalized = $Path.Replace('/', '\')
    if ($normalized.StartsWith('\\?\UNC\', [StringComparison]::OrdinalIgnoreCase)) {
        $normalized = '\\' + $normalized.Substring(8)
    }
    elseif ($normalized.StartsWith('\\?\', [StringComparison]::OrdinalIgnoreCase)) {
        $extendedPath = $normalized.Substring(4)
        if ($extendedPath -notmatch '^[A-Za-z]:\\') {
            throw "Only extended-length drive and UNC paths are supported for Gitea lifecycle file operations."
        }
        $normalized = $extendedPath
    }

    if ($normalized -match '^([A-Za-z]):\\') {
        $rootPath = $Matches[1].ToUpperInvariant() + ':\'
        $segments = [System.Collections.Generic.List[string]]::new()
        foreach ($segment in $normalized.Substring(3).Split([char[]]@('\'))) {
            if (-not $segment -or $segment -eq '.') { continue }
            if ($segment -eq '..') {
                if ($segments.Count -gt 0) { $segments.RemoveAt($segments.Count - 1) }
                continue
            }
            if ($segment -match '[<>:"|?*\x00-\x1f]') {
                throw "The path contains a character that is invalid in a Windows file name."
            }
            if ($segment.EndsWith('.') -or $segment.EndsWith(' ')) {
                throw "The path contains a Windows path segment with a trailing dot or space."
            }
            $segments.Add($segment)
        }
        if ($segments.Count -eq 0) { return $rootPath }
        return $rootPath + ($segments -join '\')
    }

    if ($normalized.StartsWith('\\')) {
        if ($normalized.StartsWith('\\.\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Device namespace paths are not supported for Gitea lifecycle file operations."
        }
        $uncSegments = @($normalized.Substring(2).Split([char[]]@('\')))
        if ($uncSegments.Count -lt 2 -or -not $uncSegments[0] -or -not $uncSegments[1]) {
            throw "The UNC path does not include both a server and share name."
        }
        $uncRoot = '\\' + $uncSegments[0] + '\' + $uncSegments[1]
        $segments = [System.Collections.Generic.List[string]]::new()
        foreach ($segment in $uncSegments | Select-Object -Skip 2) {
            if (-not $segment -or $segment -eq '.') { continue }
            if ($segment -eq '..') {
                if ($segments.Count -gt 0) { $segments.RemoveAt($segments.Count - 1) }
                continue
            }
            if ($segment -match '[<>:"|?*\x00-\x1f]') {
                throw "The path contains a character that is invalid in a Windows file name."
            }
            if ($segment.EndsWith('.') -or $segment.EndsWith(' ')) {
                throw "The path contains a Windows path segment with a trailing dot or space."
            }
            $segments.Add($segment)
        }
        if ($segments.Count -eq 0) { return $uncRoot }
        return $uncRoot + '\' + ($segments -join '\')
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $rootPath = [System.IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Equals($rootPath, [StringComparison]::OrdinalIgnoreCase)) { return $fullPath }
    return $fullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

function Get-LongPathParent {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = Get-FullPath -Path $Path
    if ($fullPath -match '^[A-Za-z]:\\$') { return $fullPath }
    if ($fullPath -match '^\\\\[^\\]+\\[^\\]+$') { return $fullPath }
    $separator = $fullPath.LastIndexOf('\')
    if ($separator -lt 0) { return $null }
    if ($separator -eq 2) { return $fullPath.Substring(0, 3) }
    return $fullPath.Substring(0, $separator)
}

function Get-LongPathLeaf {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = Get-FullPath -Path $Path
    $separator = $fullPath.LastIndexOf('\')
    if ($separator -lt 0) { return $fullPath }
    return $fullPath.Substring($separator + 1)
}

function ConvertTo-ExtendedLengthPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = Get-FullPath -Path $Path
    if ($fullPath -match '^[A-Za-z]:\\') { return '\\?\' + $fullPath }
    if ($fullPath.StartsWith('\\')) { return '\\?\UNC\' + $fullPath.Substring(2) }
    throw "Long-path file operations require an absolute drive or UNC path."
}

function ConvertFrom-ExtendedLengthPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($Path.StartsWith('\\?\UNC\', [StringComparison]::OrdinalIgnoreCase)) {
        return '\\' + $Path.Substring(8)
    }
    if ($Path.StartsWith('\\?\', [StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Substring(4)
    }
    return $Path
}

function Test-LongPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateSet('Any', 'Container', 'Leaf')][string]$PathType = 'Any'
    )

    try {
        $attributes = [System.IO.File]::GetAttributes((ConvertTo-ExtendedLengthPath -Path $Path))
    }
    catch [System.IO.FileNotFoundException] { return $false }
    catch [System.IO.DirectoryNotFoundException] { return $false }

    $isContainer = (($attributes -band [System.IO.FileAttributes]::Directory) -ne 0)
    if ($PathType -eq 'Container') { return $isContainer }
    if ($PathType -eq 'Leaf') { return -not $isContainer }
    return $true
}

function Get-LongPathItem {
    param([Parameter(Mandatory = $true)][string]$Path)

    $extendedPath = ConvertTo-ExtendedLengthPath -Path $Path
    $attributes = [System.IO.File]::GetAttributes($extendedPath)
    $isContainer = (($attributes -band [System.IO.FileAttributes]::Directory) -ne 0)
    $length = [long]0
    if (-not $isContainer) { $length = [long]([System.IO.FileInfo]::new($extendedPath).Length) }
    $fullPath = ConvertFrom-ExtendedLengthPath -Path $extendedPath
    $separator = $fullPath.LastIndexOf('\')
    $name = if ($separator -ge 0) { $fullPath.Substring($separator + 1) } else { $fullPath }
    return [pscustomobject]@{
        FullName = $fullPath
        Name = $name
        Attributes = $attributes
        PSIsContainer = $isContainer
        Length = $length
    }
}

function Get-LongPathDirectoryEntries {
    param([Parameter(Mandatory = $true)][string]$Path)

    $entries = [System.Collections.Generic.List[object]]::new()
    $extendedDirectory = ConvertTo-ExtendedLengthPath -Path $Path
    foreach ($extendedEntry in [System.IO.Directory]::EnumerateFileSystemEntries($extendedDirectory)) {
        $entryPath = ConvertFrom-ExtendedLengthPath -Path $extendedEntry
        $entries.Add((Get-LongPathItem -Path $entryPath))
    }
    return $entries.ToArray()
}

function Test-LongPathDirectoryEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $matches = @(
        Get-LongPathDirectoryEntries -Path $Directory |
            Where-Object { [string]$_.Name -ceq $Name }
    )
    foreach ($match in $matches) {
        if ($match.PSIsContainer -or
            (($match.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw "Temporary lifecycle path '$($match.FullName)' is not a regular file."
        }
    }
    return $matches.Count -gt 0
}

function Get-LongPathTreeEntries {
    param([Parameter(Mandatory = $true)][string]$Path)

    $entries = [System.Collections.Generic.List[object]]::new()
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push((Get-FullPath -Path $Path))
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($entry in @(Get-LongPathDirectoryEntries -Path $directory)) {
            $entries.Add($entry)
            if ($entry.PSIsContainer -and
                (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0)) {
                $pending.Push($entry.FullName)
            }
        }
    }
    return $entries.ToArray()
}

function New-LongPathDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    [void][System.IO.Directory]::CreateDirectory((ConvertTo-ExtendedLengthPath -Path $Path))
}

function Remove-LongPathEntry {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-LongPathItem -Path $Path
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to remove reparse point '$Path'."
    }
    $extendedPath = ConvertTo-ExtendedLengthPath -Path $Path
    if ($item.PSIsContainer) {
        foreach ($child in @(Get-LongPathDirectoryEntries -Path $Path)) {
            Remove-LongPathEntry -Path $child.FullName
        }
        [System.IO.File]::SetAttributes($extendedPath, [System.IO.FileAttributes]::Normal)
        [System.IO.Directory]::Delete($extendedPath, $false)
    }
    else {
        [System.IO.File]::SetAttributes($extendedPath, [System.IO.FileAttributes]::Normal)
        [System.IO.File]::Delete($extendedPath)
    }
}

function Remove-LongPathTree {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-LongPathItem -Path $Path
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to remove reparse point '$Path'."
    }
    foreach ($entry in @(Get-LongPathTreeEntries -Path $Path)) {
        if (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to remove a tree containing reparse point '$($entry.FullName)'."
        }
    }
    Remove-LongPathEntry -Path $Path
}

function Copy-LongPathFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [switch]$Force
    )

    $sourceItem = Get-LongPathItem -Path $Source
    if ($sourceItem.PSIsContainer -or
        (($sourceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "Copy source '$Source' is not a regular file; refusing a redirected or ambiguous copy."
    }
    $destinationExtended = ConvertTo-ExtendedLengthPath -Path $Destination
    if (Test-LongPath -Path $Destination) {
        $destinationItem = Get-LongPathItem -Path $Destination
        if ($destinationItem.PSIsContainer -or
            (($destinationItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw "Copy destination '$Destination' is not a regular file."
        }
        if (-not $Force) { throw "Copy destination '$Destination' already exists." }
        [System.IO.File]::SetAttributes($destinationExtended, [System.IO.FileAttributes]::Normal)
        [System.IO.File]::Delete($destinationExtended)
    }

    $sourceStream = $null
    $destinationStream = $null
    try {
        $sourceStream = [System.IO.FileStream]::new(
            (ConvertTo-ExtendedLengthPath -Path $Source),
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        $destinationStream = [System.IO.FileStream]::new(
            $destinationExtended,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $sourceStream.CopyTo($destinationStream)
        $destinationStream.Flush($true)
    }
    finally {
        if ($destinationStream) { $destinationStream.Dispose() }
        if ($sourceStream) { $sourceStream.Dispose() }
    }
}

function Move-LongPathFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [switch]$Force
    )

    $sourceItem = Get-LongPathItem -Path $Source
    if ($sourceItem.PSIsContainer -or
        (($sourceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "Move source '$Source' is not a regular file."
    }
    $sourceExtended = ConvertTo-ExtendedLengthPath -Path $Source
    $destinationExtended = ConvertTo-ExtendedLengthPath -Path $Destination
    if (Test-LongPath -Path $Destination) {
        $destinationItem = Get-LongPathItem -Path $Destination
        if ($destinationItem.PSIsContainer -or
            (($destinationItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw "Move destination '$Destination' is not a regular file."
        }
        if (-not $Force) { throw "Move destination '$Destination' already exists." }
        # Windows PowerShell 5.1's .NET Framework rejects a null File.Replace backup path, including extended-length paths.
        $replacementBackupPath = Join-Path (Get-LongPathParent -Path $Destination) (
            ".{0}.{1}.replace-backup.tmp" -f (Get-LongPathLeaf -Path $Destination), [Guid]::NewGuid().ToString("N")
        )
        if (Test-LongPath -Path $replacementBackupPath) {
            throw "A temporary replacement backup path already exists; refusing to overwrite it."
        }
        $replacementBackupExtended = ConvertTo-ExtendedLengthPath -Path $replacementBackupPath
        [System.IO.File]::Replace($sourceExtended, $destinationExtended, $replacementBackupExtended)
        $replacementBackupDirectory = Get-LongPathParent -Path $replacementBackupPath
        $replacementBackupName = Get-LongPathLeaf -Path $replacementBackupPath
        if (Test-LongPathDirectoryEntry -Directory $replacementBackupDirectory -Name $replacementBackupName) {
            try {
                Remove-LongPathEntry -Path $replacementBackupPath
                if (Test-LongPathDirectoryEntry -Directory $replacementBackupDirectory -Name $replacementBackupName) {
                    throw "The temporary previous-file backup remains after cleanup."
                }
            }
            catch {
                $cleanupException = Get-GiteaLifecycleRootException -Exception $_.Exception
                $rollbackPath = Join-Path (Get-LongPathParent -Path $Destination) (
                    ".{0}.{1}.replace-rollback.tmp" -f (Get-LongPathLeaf -Path $Destination), [Guid]::NewGuid().ToString("N")
                )
                if (Test-LongPath -Path $rollbackPath) {
                    throw "Atomic replacement completed, but its previous-file backup could not be removed or safely rolled back. The original file remains preserved at '$replacementBackupPath'. Cleanup exception type '$($cleanupException.GetType().FullName)': $($cleanupException.Message)"
                }
                $rollbackExtended = ConvertTo-ExtendedLengthPath -Path $rollbackPath
                try {
                    [System.IO.File]::Replace($replacementBackupExtended, $destinationExtended, $rollbackExtended)
                }
                catch {
                    $rollbackException = Get-GiteaLifecycleRootException -Exception $_.Exception
                    if (Test-LongPath -Path $replacementBackupPath -PathType Leaf) {
                        throw "Atomic replacement completed, but the previous-file backup could not be removed or restored. The original file remains preserved at '$replacementBackupPath'. Cleanup exception type '$($cleanupException.GetType().FullName)': $($cleanupException.Message) Rollback exception type '$($rollbackException.GetType().FullName)': $($rollbackException.Message)"
                    }
                    throw "Atomic replacement completed, but cleanup and restoration of the previous file both failed. Inspect the destination before retrying. Cleanup exception type '$($cleanupException.GetType().FullName)': $($cleanupException.Message) Rollback exception type '$($rollbackException.GetType().FullName)': $($rollbackException.Message)"
                }

                try {
                    if (Test-LongPath -Path $rollbackPath -PathType Leaf) {
                        Remove-LongPathEntry -Path $rollbackPath
                    }
                }
                catch {
                    $rollbackCleanupException = Get-GiteaLifecycleRootException -Exception $_.Exception
                    throw "The original file was restored, but cleanup of the replacement file failed. The replacement remains at '$rollbackPath'. Exception type '$($rollbackCleanupException.GetType().FullName)': $($rollbackCleanupException.Message)"
                }
                throw "Atomic replacement was rolled back because its temporary previous-file backup could not be removed. The original file is restored. Cleanup exception type '$($cleanupException.GetType().FullName)': $($cleanupException.Message)"
            }
        }
        return
    }
    [System.IO.File]::Move($sourceExtended, $destinationExtended)
}

function Read-LongPathText {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.File]::ReadAllText((ConvertTo-ExtendedLengthPath -Path $Path))
}

function Write-LongPathText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )
    [System.IO.File]::WriteAllText(
        (ConvertTo-ExtendedLengthPath -Path $Path),
        $Text,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Get-LongPathSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = $null
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.FileStream]::new(
            (ConvertTo-ExtendedLengthPath -Path $Path),
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        return [System.BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        if ($stream) { $stream.Dispose() }
        $algorithm.Dispose()
    }
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
        if (Test-LongPath -Path $current) {
            $item = Get-LongPathItem -Path $current
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "The configured backup path crosses a reparse point at '$current'; local backup storage must resolve directly to disk."
            }
        }
        if ($current -match '^[A-Za-z]:\\$') { break }
        $separator = $current.LastIndexOf('\')
        if ($separator -lt 2) { break }
        if ($separator -eq 2) { $current = $current.Substring(0, 3) }
        else { $current = $current.Substring(0, $separator) }
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

function Get-BackupObjectSecurity {
    param([Parameter(Mandatory = $true)][string]$Path)

    $sections = [System.Security.AccessControl.AccessControlSections]::Access -bor
        [System.Security.AccessControl.AccessControlSections]::Owner
    $item = Get-LongPathItem -Path $Path
    if ($item.PSIsContainer) {
        return [System.IO.Directory]::GetAccessControl((ConvertTo-ExtendedLengthPath -Path $Path), $sections)
    }
    return [System.IO.File]::GetAccessControl((ConvertTo-ExtendedLengthPath -Path $Path), $sections)
}

function Assert-RestrictedBackupAcl {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][System.Security.Principal.SecurityIdentifier]$OwnerSid,
        [Parameter(Mandatory = $true)][bool]$IsDirectory
    )

    $security = Get-BackupObjectSecurity -Path $Path
    $securityIdentifierType = [System.Security.Principal.SecurityIdentifier]
    $actualOwner = $security.GetOwner($securityIdentifierType)
    if (-not $actualOwner -or $actualOwner.Value -ne $OwnerSid.Value) {
        throw "The Gitea backup object '$Path' is not owned by the current user; refusing to accept its ACL."
    }
    if (-not $security.AreAccessRulesProtected) {
        throw "The Gitea backup object '$Path' still inherits access rules; refusing to accept its ACL."
    }

    $expectedSids = @(
        $OwnerSid.Value,
        "S-1-5-18",
        "S-1-5-32-544"
    )
    $expectedSidSet = @{}
    foreach ($sid in $expectedSids) { $expectedSidSet[$sid] = $true }
    $expectedInheritance = [System.Security.AccessControl.InheritanceFlags]::None
    if ($IsDirectory) {
        $expectedInheritance = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
            [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    }

    $rules = @($security.GetAccessRules($true, $true, $securityIdentifierType))
    if ($rules.Count -ne $expectedSids.Count) {
        throw "The Gitea backup object '$Path' has an unexpected number of access rules; refusing to accept its ACL."
    }

    $actualSids = @{}
    foreach ($rule in $rules) {
        $sid = $rule.IdentityReference.Value
        if (-not $expectedSidSet.ContainsKey($sid) -or $actualSids.ContainsKey($sid)) {
            throw "The Gitea backup object '$Path' contains an unexpected or duplicate access rule; refusing to accept its ACL."
        }
        if ($rule.IsInherited -or
            $rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow -or
            [int]$rule.FileSystemRights -ne [int][System.Security.AccessControl.FileSystemRights]::FullControl -or
            $rule.InheritanceFlags -ne $expectedInheritance -or
            $rule.PropagationFlags -ne [System.Security.AccessControl.PropagationFlags]::None) {
            throw "The Gitea backup object '$Path' does not have the required explicit full-control rule for '$sid'."
        }
        $actualSids[$sid] = $true
    }

    foreach ($sid in $expectedSids) {
        if (-not $actualSids.ContainsKey($sid)) {
            throw "The Gitea backup object '$Path' is missing the required access rule for '$sid'."
        }
    }
}

function Set-RestrictedBackupAcl {
    param([Parameter(Mandatory = $true)][string]$Path)

    $currentUserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $item = Get-LongPathItem -Path $Path
    $isDirectory = [bool]$item.PSIsContainer
    $security = Get-BackupObjectSecurity -Path $Path
    $existingOwner = $security.GetOwner([System.Security.Principal.SecurityIdentifier])
    if (-not $existingOwner -or $existingOwner.Value -ne $currentUserSid.Value) {
        throw "The Gitea backup object '$Path' is not owned by the current user; refusing to change its DACL."
    }

    if ($isDirectory) {
        $security = [System.Security.AccessControl.DirectorySecurity]::new()
    }
    else {
        $security = [System.Security.AccessControl.FileSecurity]::new()
    }
    $security.SetAccessRuleProtection($true, $false)

    $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::None
    if ($isDirectory) {
        $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
            [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    }
    $identities = @(
        $currentUserSid,
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
        [void]$security.AddAccessRule($rule)
    }

    # PowerShell Set-Acl first persists AccessControlSections.All, including Audit;
    # its PrivilegeNotHeldException fallback excludes Audit only in limited cases.
    # FileSystemSecurity persists only sections modified on this new descriptor, so
    # changing access rules here writes the DACL without requesting the SACL.
    if ($isDirectory) {
        ([System.IO.DirectoryInfo]::new((ConvertTo-ExtendedLengthPath -Path $Path))).SetAccessControl($security)
    }
    else {
        ([System.IO.FileInfo]::new((ConvertTo-ExtendedLengthPath -Path $Path))).SetAccessControl($security)
    }

    Assert-RestrictedBackupAcl -Path $Path -OwnerSid $currentUserSid -IsDirectory $isDirectory
}

function Ensure-BackupRoot {
    param([hashtable]$Context)

    $backupRoot = Assert-SafeBackupRoot -Context $Context
    if (-not (Test-LongPath -Path $backupRoot -PathType Container)) {
        New-LongPathDirectory -Path $backupRoot
    }

    Assert-NoReparsePathAncestors -Path $backupRoot
    if ((Get-FullPath -Path $backupRoot) -ne $backupRoot) {
        throw "The resolved Gitea backup root differs from the configured path; refusing a redirected backup location."
    }

    Set-RestrictedBackupAcl -Path $backupRoot
    return $backupRoot
}

function ConvertTo-ProcessArgumentString {
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
            if ($character -eq [char]92) {
                $backslashes += 1
                continue
            }
            if ($character -eq [char]34) {
                if ($backslashes -gt 0) { [void]$builder.Append([string]::new([char]92, $backslashes * 2)) }
                [void]$builder.Append('\"')
                $backslashes = 0
                continue
            }
            if ($backslashes -gt 0) {
                [void]$builder.Append([string]::new([char]92, $backslashes))
                $backslashes = 0
            }
            [void]$builder.Append($character)
        }
        if ($backslashes -gt 0) { [void]$builder.Append([string]::new([char]92, $backslashes * 2)) }
        [void]$builder.Append('"')
        $builder.ToString()
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
    $output = [System.IO.File]::Open((ConvertTo-ExtendedLengthPath -Path $OutputPath), [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
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
    $inputStream = [System.IO.File]::OpenRead((ConvertTo-ExtendedLengthPath -Path $InputPath))
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
    return $stdoutTask.Result.Trim()
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

function Get-GiteaContainerId {
    param([AllowNull()][object]$Container)

    if ($null -eq $Container) { return "" }
    if ($Container -is [System.Collections.IDictionary]) {
        if ($Container.Contains("Id")) { return [string]$Container["Id"] }
        return ""
    }
    $property = $Container.PSObject.Properties["Id"]
    if ($property) { return [string]$property.Value }
    return ""
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
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Environment)

    $map = @{}
    foreach ($item in $Environment) {
        $separator = $item.IndexOf('=')
        if ($separator -gt 0) {
            $map[$item.Substring(0, $separator)] = $item.Substring($separator + 1)
        }
    }
    return $map
}

function Assert-GiteaLocalStorageOnly {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigFilePath,
        [string[]]$Environment = @(),
        [object]$Container
    )

    if (-not (Test-LongPath -Path $ConfigFilePath -PathType Leaf)) {
        throw "Gitea's effective app.ini '$ConfigFilePath' is missing; local-payload storage coverage cannot be proven."
    }
    $configItem = Get-LongPathItem -Path $ConfigFilePath
    if (($configItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Gitea's effective app.ini is a reparse point; local-payload storage coverage cannot be proven."
    }
    $containerEnvironment = ConvertTo-ContainerEnvironmentMap -Environment @($Environment)
    foreach ($environmentName in @("GITEA_CONFIG", "GITEA_CONFIG_FILE")) {
        if ($containerEnvironment[$environmentName] -and $containerEnvironment[$environmentName] -cne "/etc/gitea/app.ini") {
            throw "Gitea's $environmentName override selects an app.ini outside the captured /etc/gitea payload."
        }
    }
    $storagePathSections = @("storage", "attachment", "lfs", "avatar", "picture", "repo-avatar", "repository-avatar", "repository-archive", "packages", "actions", "server", "repository")
    if ($Container) {
        $arguments = @()
        if ($Container.Args) { $arguments += @($Container.Args) }
        if ($Container.Config -and $Container.Config.Cmd) { $arguments += @($Container.Config.Cmd) }
        for ($index = 0; $index -lt $arguments.Count; $index += 1) {
            $argument = [string]$arguments[$index]
            if ($argument -match '^--config=(.*)$') {
                $configuredPath = [string]$Matches[1]
                if ($configuredPath -cne "/etc/gitea/app.ini") {
                    throw "Gitea's command-line config override selects an app.ini outside the captured /etc/gitea payload."
                }
            }
            elseif ($argument -ceq "--config") {
                if ($index + 1 -ge $arguments.Count -or [string]$arguments[$index + 1] -cne "/etc/gitea/app.ini") {
                    throw "Gitea's command-line config override selects an app.ini outside the captured /etc/gitea payload."
                }
                $index += 1
            }
        }
    }

    $sections = @{}
    $sectionName = ""
    foreach ($line in (Read-LongPathText -Path $ConfigFilePath) -split "`r?`n") {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith(";") -or $trimmed.StartsWith("#")) { continue }
        if ($trimmed -match '^\[([^\]]+)\]$') {
            $sectionName = $Matches[1].Trim().ToLowerInvariant()
            if (-not $sections.ContainsKey($sectionName)) { $sections[$sectionName] = @{} }
            continue
        }
        $separator = $trimmed.IndexOf('=')
        if ($separator -lt 1) { continue }
        if (-not $sectionName) {
            throw "Gitea's effective app.ini contains a setting outside a section; local-payload storage coverage cannot be proven."
        }
        $key = $trimmed.Substring(0, $separator).Trim().ToLowerInvariant()
        $value = $trimmed.Substring($separator + 1).Trim()
        if ($sections[$sectionName].ContainsKey($key)) {
            $storageRelevantSection = $sectionName -in $storagePathSections -or $sectionName.StartsWith("storage.")
            if ($storageRelevantSection -and ($key -match '(^|_)storage_type$' -or $key -match '(^|_)(path|dir|directory|root)$')) {
                throw "Gitea's effective app.ini repeats setting '$sectionName.$key'; local-payload storage coverage is ambiguous."
            }
        }
        $sections[$sectionName][$key] = $value
    }

    foreach ($item in $Environment) {
        $separator = $item.IndexOf('=')
        if ($separator -lt 1) { continue }
        $name = $item.Substring(0, $separator)
        if ($name -notmatch '^GITEA__(.+)$') { continue }
        $parts = $Matches[1].Split(@('__'), [StringSplitOptions]::None)
        if ($parts.Count -lt 2 -or -not [Regex]::IsMatch($parts[-1], '^(?:.*storage_type|.*(?:path|dir|directory|root))$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) { continue }
        $key = $parts[-1].ToLowerInvariant()
        $section = ($parts[0..($parts.Count - 2)] -join '.').ToLowerInvariant()
        if (-not $sections.ContainsKey($section)) { $sections[$section] = @{} }
        $sections[$section][$key] = $item.Substring($separator + 1).Trim()
    }

    $defaultStorageType = "local"
    if ($sections.ContainsKey("storage") -and $sections["storage"].ContainsKey("storage_type")) {
        $defaultStorageType = [string]$sections["storage"]["storage_type"]
    }
    if ($defaultStorageType -and $defaultStorageType -notin @("local", "default")) {
        throw "Gitea shared storage selects '$defaultStorageType'; external storage is outside the backup payload and lifecycle operations are blocked."
    }

    foreach ($section in $sections.Keys) {
        foreach ($key in $sections[$section].Keys) {
            if ($key -notmatch '(^|_)storage_type$') { continue }
            $storageType = [string]$sections[$section][$key]
            if ($storageType -and $storageType -notin @("local", "default")) {
                throw "Gitea storage selector '$section.$key' uses '$storageType'; external or custom storage is outside the backup payload and lifecycle operations are blocked."
            }
        }
    }

    foreach ($section in $sections.Keys) {
        if ($section -notin $storagePathSections -and -not $section.StartsWith("storage.")) { continue }
        foreach ($key in $sections[$section].Keys) {
            if ($key -notmatch '(^|_)(path|dir|directory|root)$') { continue }
            $storagePath = [string]$sections[$section][$key]
            if (-not $storagePath) { continue }
            if ($storagePath -match '[\x00-\x1f]' -or $storagePath -match '(^|[\\/])\.\.([\\/]|$)' -or
                $storagePath -match '^~' -or $storagePath -match '^[A-Za-z][A-Za-z0-9+.-]*://' -or
                $storagePath.Contains('$') -or $storagePath.Contains('%')) {
                throw "Gitea local storage path '$section.$key' is not a safe path within the captured payload."
            }
            if ([IO.Path]::IsPathRooted($storagePath) -and
                $storagePath -cnotmatch '^/var/lib/gitea(?:/|$)' -and
                $storagePath -cnotmatch '^/etc/gitea(?:/|$)') {
                throw "Gitea local storage path '$section.$key' is outside the captured /var/lib/gitea and /etc/gitea payloads."
            }
        }
    }
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

function Test-GiteaActionsCompletionTime {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return $false
    }
    if ($Value -is [DateTimeOffset]) {
        return $true
    }
    if ($Value -is [DateTime]) {
        return $Value.Kind -ne [DateTimeKind]::Unspecified
    }
    if ($Value -isnot [string]) {
        return $false
    }

    $text = [string]$Value
    $timestampPattern = '\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\z'
    if ($text -cnotmatch $timestampPattern) {
        return $false
    }

    # .NET Framework stores seven fractional digits; discard any additional
    # RFC 3339 precision only after the full timestamp shape has been checked.
    $parseableText = $text -replace '(?<=\.\d{7})\d+(?=(?:Z|[+-]\d{2}:\d{2})\z)', ''
    $parsedValue = [DateTimeOffset]::MinValue
    return [DateTimeOffset]::TryParse(
        $parseableText,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None,
        [ref]$parsedValue
    )
}

function Assert-NoActiveGiteaActions {
    param([hashtable]$Context)

    $authenticatedUser = Invoke-GiteaApiRead -Context $Context -RelativePath "user"
    if (-not [bool]$authenticatedUser.is_admin) {
        throw "The configured Gitea API identity is not an administrator; all repositories cannot be checked for active work."
    }
    $limit = 50
    $page = 1
    while ($true) {
        $response = Invoke-GiteaApiRead -Context $Context -RelativePath "admin/actions/runs?limit=$limit&page=$page"
        if ($null -eq $response) {
            throw "Gitea instance-wide Actions enumeration returned an empty response; refusing maintenance."
        }
        $runsProperty = $response.PSObject.Properties["workflow_runs"]
        $totalProperty = $response.PSObject.Properties["total_count"]
        if (-not $runsProperty -or -not $totalProperty) {
            throw "Gitea instance-wide Actions enumeration returned an unexpected response; refusing maintenance."
        }

        $totalValue = $totalProperty.Value
        if ($totalValue -isnot [int] -and $totalValue -isnot [long]) {
            throw "Gitea instance-wide Actions enumeration returned an invalid total; refusing maintenance."
        }
        $totalCount = [long]$totalValue
        if ($totalCount -lt 0) {
            throw "Gitea instance-wide Actions enumeration returned an invalid total; refusing maintenance."
        }

        $runs = @($runsProperty.Value)
        $expectedCount = [Math]::Min($limit, [Math]::Max(0, $totalCount - (($page - 1) * $limit)))
        if ($runs.Count -ne $expectedCount) {
            throw "Gitea instance-wide Actions run enumeration was incomplete; refusing maintenance."
        }

        # Preserve Gitea's direct terminal statuses and accept the completed / conclusion
        # shape only when both its outcome and completion timestamp are trustworthy.
        foreach ($run in $runs) {
            if ($null -eq $run -or -not $run.PSObject.Properties["status"]) {
                throw "Gitea instance-wide Actions enumeration returned a run without a status; refusing maintenance."
            }
            $status = [string]$run.status
            $runId = if ($run.PSObject.Properties["id"]) { [string]$run.id } else { "unknown" }
            if ($status -ceq "completed") {
                $conclusionProperty = $run.PSObject.Properties["conclusion"]
                $validConclusions = @("success", "failure", "cancelled", "skipped")
                if (-not $conclusionProperty -or [string]$conclusionProperty.Value -cnotin $validConclusions) {
                    throw "Gitea Actions run '$runId' has a missing or unrecognized completed conclusion; refusing maintenance."
                }

                $completedAtProperty = $run.PSObject.Properties["completed_at"]
                if (-not $completedAtProperty -or -not (Test-GiteaActionsCompletionTime -Value $completedAtProperty.Value)) {
                    throw "Gitea Actions run '$runId' is completed without a valid completion time; refusing maintenance."
                }
                continue
            }

            if ($status -cnotin @("success", "failure", "skipped", "cancelled")) {
                throw "Gitea Actions has active or unrecognized '$status' work in run '$runId'; wait for it to finish before maintenance."
            }
        }

        if (($page * $limit) -ge $totalCount) {
            break
        }
        $page += 1
        if ($page -gt 10000) {
            throw "Gitea instance-wide Actions run enumeration exceeded its safety bound; refusing maintenance."
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

function Assert-GiteaImmutableImageReference {
    param([Parameter(Mandatory = $true)][string]$Reference)

    if ($Reference -notmatch '^(docker\.gitea\.com/gitea@sha256:[0-9a-f]{64}|sha256:[0-9a-f]{64})$') {
        throw "The Gitea image reference is not one valid immutable registry digest or local image ID."
    }
}

function Get-ImageDigestReference {
    param(
        [Parameter(Mandatory = $true)][string]$Image,
        [switch]$RequireRegistryDigest
    )

    $result = Invoke-GiteaDocker -Arguments @("image", "inspect", $Image, "--format", "{{json .RepoDigests}}")
    try {
        # Windows PowerShell 5.1 enumerates a top-level JSON array through the pipeline as
        # one space-joined string. Nesting it in an object preserves the array as an object
        # property so each RepoDigest remains a separate value.
        $envelope = ('{"repoDigests":' + [string]$result.StdOut + '}') | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Docker returned malformed RepoDigests JSON for image '$Image'."
    }

    $repoDigestsProperty = $envelope.PSObject.Properties["repoDigests"]
    if (-not $repoDigestsProperty) {
        throw "Docker returned an unexpected RepoDigests response for image '$Image'."
    }
    $repoDigestsValue = $repoDigestsProperty.Value
    if ($null -eq $repoDigestsValue) {
        $digests = @()
    }
    elseif ($repoDigestsValue -is [System.Array]) {
        $digests = @($repoDigestsValue)
    }
    else {
        throw "Docker returned a non-array RepoDigests value for image '$Image'."
    }

    $digest = $null
    foreach ($candidate in $digests) {
        if ($candidate -isnot [string] -or
            $candidate -notmatch '^[a-z0-9][a-z0-9._:-]*(?:/[a-z0-9][a-z0-9._-]*)+@sha256:[0-9a-f]{64}$') {
            throw "Docker returned an invalid RepoDigest entry for image '$Image'."
        }
        if (-not $digest -and $candidate -match '^docker\.gitea\.com/gitea@sha256:[0-9a-f]{64}$') {
            $digest = [string]$candidate
        }
    }
    if ($digest) {
        Assert-GiteaImmutableImageReference -Reference $digest
        return $digest
    }
    if ($RequireRegistryDigest) {
        throw "The pulled Gitea image did not resolve to the expected immutable docker.gitea.com digest."
    }
    if ($Image -match '^sha256:[0-9a-f]{64}$') {
        return $Image
    }

    $inspect = Invoke-GiteaDocker -Arguments @("image", "inspect", $Image, "--format", "{{.Id}}")
    if ([string]$inspect.StdOut -notmatch '^sha256:[0-9a-f]{64}$') {
        throw "Could not resolve an immutable local image identity for restore."
    }
    $imageId = [string]$inspect.StdOut
    Assert-GiteaImmutableImageReference -Reference $imageId
    return $imageId
}

function Get-DirectoryBytes {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-LongPath -Path $Path -PathType Container)) {
        throw "Required live data directory '$Path' is missing."
    }
    if (((Get-LongPathItem -Path $Path).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Live data directory '$Path' is a reparse point; refusing a capacity estimate over redirected data."
    }
    $sum = [long]0
    foreach ($item in @(Get-LongPathTreeEntries -Path $Path)) {
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
    Write-LongPathText -Path $Path -Text $json
}

function Get-GiteaBackupManifestDigest {
    param([Parameter(Mandatory = $true)][object]$Manifest)

    $fields = [ordered]@{}
    foreach ($property in @($Manifest.PSObject.Properties | Where-Object { $_.Name -cne "metadataSha256" })) {
        $fields[$property.Name] = $property.Value
    }
    $canonicalJson = ConvertTo-Json -InputObject $fields -Depth 100 -Compress
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($canonicalJson)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [System.BitConverter]::ToString($sha256.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function New-GiteaBackupId {
    return "{0}-{1}" -f [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ"), [Guid]::NewGuid().ToString("N")
}

function Assert-GiteaBackupArtifactSchema {
    param(
        [Parameter(Mandatory = $true)][object]$Artifact,
        [Parameter(Mandatory = $true)][string]$ArtifactName,
        [Parameter(Mandatory = $true)][object]$Manifest
    )

    $schemaProperty = $Artifact.PSObject.Properties["schemaVersion"]
    if ($schemaProperty) {
        if ([int]$schemaProperty.Value -ne 1) {
            throw "The backup $ArtifactName uses an unsupported schemaVersion; restore/recovery is blocked."
        }
        return
    }
    if ([int]$Manifest.schemaVersion -ne 1) {
        throw "The backup $ArtifactName is missing schemaVersion and is not covered by the schema-1 compatibility rule."
    }
}

function Copy-DirectoryTree {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not (Test-LongPath -Path $Source -PathType Container)) {
        throw "Required Gitea data directory '$Source' is missing."
    }
    if (((Get-LongPathItem -Path $Source).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Backup source directory '$Source' is a reparse point; refusing an ambiguous snapshot."
    }
    if (Test-LongPath -Path $Destination) {
        if (-not (Test-LongPath -Path $Destination -PathType Container) -or
            (((Get-LongPathItem -Path $Destination).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw "Backup destination '$Destination' is not a regular directory."
        }
    }
    else {
        New-LongPathDirectory -Path $Destination
    }

    foreach ($item in @(Get-LongPathDirectoryEntries -Path $Source)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Backup source contains a reparse point at '$($item.FullName)'; refusing an ambiguous snapshot."
        }
        $target = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) {
            Copy-DirectoryTree -Source $item.FullName -Destination $target
        }
        else {
            Copy-LongPathFile -Source $item.FullName -Destination $target
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
        schemaVersion = 1
        containerName = [string]$Context.GiteaContainerName
        capturedContainerName = [string]$Container.Name.TrimStart('/')
        containerId = Get-GiteaContainerId -Container $Container
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
    $environment = ConvertTo-ContainerEnvironmentMap -Environment @($Container.Config.Env)
    return @{
        schemaVersion = 1
        containerName = [string]$Container.Name.TrimStart('/')
        containerId = Get-GiteaContainerId -Container $Container
        originalImageReference = [string]$Container.Config.Image
        imageId = [string]$Container.Image
        networkMode = [string]$Container.HostConfig.NetworkMode
        networkAliases = $networkAliases
        databaseName = [string]$environment["POSTGRES_DB"]
        databaseUser = [string]$environment["POSTGRES_USER"]
        ports = $ports
        mounts = $mounts
    }
}

function Get-GiteaPostgresTopology {
    param(
        [Parameter(Mandatory = $true)][string]$BackupPath,
        [Parameter(Mandatory = $true)][object]$Manifest
    )

    try {
        $topology = Read-LongPathText -Path (Join-Path $BackupPath "payload\private\postgres-topology.json") | ConvertFrom-Json -ErrorAction Stop
        Assert-GiteaBackupArtifactSchema -Artifact $topology -ArtifactName "PostgreSQL topology" -Manifest $Manifest
        foreach ($requiredField in @("containerName", "originalImageReference", "imageId", "networkMode", "networkAliases", "ports", "mounts")) {
            if (-not $topology.PSObject.Properties[$requiredField]) {
                throw "The backup PostgreSQL topology is missing '$requiredField'."
            }
        }
        if ($topology.PSObject.Properties["schemaVersion"] -and [int]$topology.schemaVersion -eq 1) {
            foreach ($requiredField in @("containerId", "databaseName", "databaseUser")) {
                if (-not $topology.PSObject.Properties[$requiredField] -or -not [string]$topology.$requiredField) {
                    throw "The schema-1 PostgreSQL topology is missing '$requiredField'."
                }
            }
            if ([string]$topology.containerId -cnotmatch '^[a-f0-9]{64}$') {
                throw "The schema-1 PostgreSQL topology has an invalid full container ID."
            }
        }
        return $topology
    }
    catch {
        throw "The backup PostgreSQL topology is unreadable or incomplete; restore/recovery is blocked. $($_.Exception.Message)"
    }
}

function Assert-PostgresRestoreCompatibility {
    param(
        [Parameter(Mandatory = $true)][object]$BackupTopology,
        [Parameter(Mandatory = $true)][object]$CurrentContainer,
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [Parameter(Mandatory = $true)][int]$ManifestSchemaVersion
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
    if ($BackupTopology.PSObject.Properties["schemaVersion"] -and [int]$BackupTopology.schemaVersion -eq 1) {
        if ([string]$BackupTopology.containerId -cne [string]$current.containerId -or
            [string]$BackupTopology.databaseName -cne [string]$current.databaseName -or
            [string]$BackupTopology.databaseUser -cne [string]$current.databaseUser -or
            [string]$current.databaseName -cne [string]$Context.GiteaPostgresDbName -or
            [string]$current.databaseUser -cne [string]$Context.GiteaPostgresUser) {
            throw "The selected backup's PostgreSQL full container ID or database identity differs from the existing service; restore is blocked."
        }
    }
    elseif ($ManifestSchemaVersion -ne 1) {
        throw "The selected backup's legacy PostgreSQL topology is not covered by the schema-1 compatibility rule."
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

function Measure-BackupFileEntriesSize {
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Entries = @()
    )

    [long]$totalBytes = 0
    foreach ($entry in @($Entries)) {
        if ($null -eq $entry) { continue }
        if ($entry -isnot [System.Collections.IDictionary] -or -not $entry.Contains("sizeBytes")) {
            throw "A backup file entry is missing its sizeBytes value."
        }

        [long]$sizeBytes = 0
        $rawSizeBytes = [string]$entry["sizeBytes"]
        $parsed = [long]::TryParse(
            $rawSizeBytes,
            [System.Globalization.NumberStyles]::Integer,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$sizeBytes
        )
        if (-not $parsed -or $sizeBytes -lt 0) {
            throw "A backup file entry has an invalid sizeBytes value."
        }
        if ($totalBytes -gt ([long]::MaxValue - $sizeBytes)) {
            throw "The total backup file size exceeds the supported byte count."
        }
        $totalBytes += $sizeBytes
    }

    return [long]$totalBytes
}

function Get-BackupFileEntries {
    param([Parameter(Mandatory = $true)][string]$BackupPath)

    $entries = @()
    $manifestPath = Join-Path $BackupPath "manifest.json"
    $backupRoot = (Get-FullPath -Path $BackupPath).TrimEnd('\', '/')
    foreach ($file in @(Get-LongPathTreeEntries -Path $backupRoot)) {
        if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Backup contains a reparse point at '$($file.FullName)'; refusing to checksum redirected content."
        }
        if ($file.PSIsContainer -or $file.FullName.Equals($manifestPath, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $relativePath = $file.FullName.Substring($backupRoot.Length).TrimStart('\', '/') -replace '\\', '/'
        $entries += @{
            path = $relativePath
            sizeBytes = [long]$file.Length
            sha256 = Get-LongPathSha256 -Path $file.FullName
        }
    }
    return $entries
}

function Test-GiteaBackupIntegrity {
    param([Parameter(Mandatory = $true)][string]$BackupPath)

    $manifestPath = Join-Path $BackupPath "manifest.json"
    if (-not (Test-LongPath -Path $manifestPath -PathType Leaf)) {
        return [pscustomobject]@{ IsValid = $false; Reason = "manifest-missing"; Manifest = $null }
    }
    try {
        if (((Get-LongPathItem -Path $BackupPath).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            ((Get-LongPathItem -Path $manifestPath).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            return [pscustomobject]@{ IsValid = $false; Reason = "reparse-point-found"; Manifest = $null }
        }
        foreach ($item in @(Get-LongPathTreeEntries -Path $BackupPath)) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                return [pscustomobject]@{ IsValid = $false; Reason = "reparse-point-found"; Manifest = $null }
            }
        }
        $manifest = Read-LongPathText -Path $manifestPath | ConvertFrom-Json
        if ([int]$manifest.schemaVersion -notin @(1, 2) -or [string]$manifest.backupId -ne (Get-LongPathLeaf -Path $BackupPath)) {
            return [pscustomobject]@{ IsValid = $false; Reason = "manifest-identity-invalid"; Manifest = $manifest }
        }
        if ([int]$manifest.schemaVersion -eq 2) {
            foreach ($requiredField in @("format", "kind", "operationId", "createdAt", "sourceVersion", "sourceImage", "sourceImageDigest", "dockerHost", "hostPort", "network", "runnerWasRunning", "requiredComponents", "sizeBytes", "files", "metadataSha256")) {
                if (-not $manifest.PSObject.Properties[$requiredField]) {
                    return [pscustomobject]@{ IsValid = $false; Reason = "manifest-required-field-missing"; Manifest = $manifest }
                }
            }
            if ([string]$manifest.format -cne "agent-sdlc-gitea-backup" -or
                [string]$manifest.operationId -notmatch '^[0-9a-f]{32}$' -or
                [string]$manifest.metadataSha256 -notmatch '^[0-9a-f]{64}$' -or
                (Get-GiteaBackupManifestDigest -Manifest $manifest) -cne [string]$manifest.metadataSha256) {
                return [pscustomobject]@{ IsValid = $false; Reason = "manifest-metadata-digest-mismatch"; Manifest = $manifest }
            }
            $requiredComponents = @("postgres-dump", "gitea-data", "gitea-config", "operator-state", "runtime-snapshot", "postgres-topology", "restore-context")
            if (@($manifest.requiredComponents).Count -ne $requiredComponents.Count) {
                throw "The backup manifest required component set is not exact."
            }
            foreach ($component in $requiredComponents) {
                if (@($manifest.requiredComponents | Where-Object { [string]$_ -ceq $component }).Count -ne 1) {
                    return [pscustomobject]@{ IsValid = $false; Reason = "manifest-required-component-missing"; Manifest = $manifest }
                }
            }
        }

        $rootPrefix = (Get-FullPath -Path $BackupPath).TrimEnd('\', '/') + '\'
        $listedPaths = @()
        $pathSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in @($manifest.files)) {
            $relative = [string]$entry.path
            $segments = $relative.Split([char[]]@('/'))
            if (-not $relative -or $relative.StartsWith('/') -or $relative.Contains('\') -or
                $relative -match '^[A-Za-z]:' -or $relative -match '[<>:"|?*\x00-\x1f]' -or
                @($segments | Where-Object { -not $_ -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
                return [pscustomobject]@{ IsValid = $false; Reason = "manifest-path-invalid"; Manifest = $manifest }
            }
            if (-not $pathSet.Add($relative)) {
                return [pscustomobject]@{ IsValid = $false; Reason = "manifest-path-duplicate"; Manifest = $manifest }
            }
            $fullPath = Get-FullPath -Path (Join-Path $BackupPath ($relative -replace '/', '\'))
            if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -or
                -not (Test-LongPath -Path $fullPath -PathType Leaf)) {
                return [pscustomobject]@{ IsValid = $false; Reason = "backup-file-missing"; Manifest = $manifest }
            }
            $hash = Get-LongPathSha256 -Path $fullPath
            if ($hash -ne [string]$entry.sha256 -or (Get-LongPathItem -Path $fullPath).Length -ne [long]$entry.sizeBytes) {
                return [pscustomobject]@{ IsValid = $false; Reason = "checksum-mismatch"; Manifest = $manifest }
            }
            $listedPaths += $relative
        }

        $actualPaths = @((Get-BackupFileEntries -BackupPath $BackupPath).path | Sort-Object)
        $expectedPaths = @($listedPaths | Sort-Object)
        if (($actualPaths -join "`n") -ne ($expectedPaths -join "`n")) {
            return [pscustomobject]@{ IsValid = $false; Reason = "manifest-file-set-mismatch"; Manifest = $manifest }
        }
        $actualBytes = Measure-BackupFileEntriesSize -Entries @(Get-BackupFileEntries -BackupPath $BackupPath)
        if (-not $manifest.PSObject.Properties["sizeBytes"] -or [long]$manifest.sizeBytes -ne $actualBytes) {
            return [pscustomobject]@{ IsValid = $false; Reason = "manifest-total-size-mismatch"; Manifest = $manifest }
        }
        if ([int]$manifest.schemaVersion -eq 2) {
            $requiredPayloadPaths = @(
                "payload/postgres.dump",
                "payload/private/gitea-runtime.json",
                "payload/private/postgres-topology.json",
                "payload/private/restore-context.json",
                "payload/operator-state/bootstrap-config.json"
            )
            foreach ($requiredPath in $requiredPayloadPaths) {
                if ($actualPaths -notcontains $requiredPath) {
                    return [pscustomobject]@{ IsValid = $false; Reason = "backup-required-payload-missing"; Manifest = $manifest }
                }
            }
            if (@($actualPaths | Where-Object { $_ -like "payload/gitea-data/*" }).Count -eq 0 -or
                @($actualPaths | Where-Object { $_ -like "payload/gitea-config/*" }).Count -eq 0) {
                return [pscustomobject]@{ IsValid = $false; Reason = "backup-required-payload-missing"; Manifest = $manifest }
            }
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
        [Parameter(Mandatory = $true)][object]$Capacity,
        [object]$RuntimeSnapshot,
        [string]$BackupId,
        [string]$OperationId
    )

    $backupRoot = Ensure-BackupRoot -Context $Context
    if (-not $BackupId) { $BackupId = New-GiteaBackupId }
    if (-not $OperationId) { $OperationId = [Guid]::NewGuid().ToString("N") }
    if ($BackupId -notmatch '^\d{8}T\d{6}Z-[0-9a-f]{32}$' -or $OperationId -notmatch '^[0-9a-f]{32}$') {
        throw "The reserved backup or operation identity is invalid."
    }
    $backupPath = Join-Path $backupRoot $backupId
    if (Test-LongPath -Path $backupPath) {
        throw "The reserved Backup ID already exists; refusing to overwrite retained backup data."
    }
    New-LongPathDirectory -Path $backupPath
    Set-RestrictedBackupAcl -Path $backupPath

    $payloadPath = Join-Path $backupPath "payload"
    $dataPath = Join-Path $payloadPath "gitea-data"
    $configPath = Join-Path $payloadPath "gitea-config"
    $operatorPath = Join-Path $payloadPath "operator-state"
    $privatePath = Join-Path $payloadPath "private"
    foreach ($directory in @($payloadPath, $dataPath, $configPath, $operatorPath, $privatePath)) {
        New-LongPathDirectory -Path $directory
    }

    Copy-DirectoryTree -Source $Context.GiteaDataDir -Destination $dataPath
    Copy-DirectoryTree -Source $Context.GiteaConfigDir -Destination $configPath
    if (-not (Test-LongPath -Path $Context.ConfigPath -PathType Leaf)) {
        throw "The active Gitea bootstrap config is missing; refusing to create a partial backup."
    }
    if (((Get-LongPathItem -Path $Context.ConfigPath).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "The active Gitea bootstrap config is a reparse point; refusing to back up redirected settings."
    }
    Copy-LongPathFile -Source $Context.ConfigPath -Destination (Join-Path $operatorPath "bootstrap-config.json")
    foreach ($entry in @(
        @{ Source = $Context.GiteaSecretsPath; Name = "generated-secrets.json" },
        @{ Source = $Context.GiteaBootstrapSummaryPath; Name = "bootstrap-summary.json" },
        @{ Source = $Context.EffectiveBootstrapSettingsPath; Name = "effective-settings.json" }
    )) {
        if (Test-LongPath -Path $entry.Source -PathType Leaf) {
            if (((Get-LongPathItem -Path $entry.Source).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Operator state file '$($entry.Source)' is a reparse point; refusing to back up redirected settings."
            }
            Copy-LongPathFile -Source $entry.Source -Destination (Join-Path $operatorPath $entry.Name)
        }
    }

    $runtime = if ($RuntimeSnapshot) {
        $RuntimeSnapshot
    }
    elseif ($GiteaContainer) {
        Get-RuntimeSnapshot -Context $Context -Container $GiteaContainer -SourceVersion $SourceVersion
    }
    else {
        $null
    }
    Save-BackupJson -Path (Join-Path $privatePath "gitea-runtime.json") -Value $runtime
    Save-BackupJson -Path (Join-Path $privatePath "postgres-topology.json") -Value (Get-PostgresTopologySnapshot -Container $PostgresContainer)
    Save-BackupJson -Path (Join-Path $privatePath "restore-context.json") -Value @{
        schemaVersion = 1
        configPath = [string]$Context.ConfigPath
        configSource = [string]$Context.ConfigSource
        databaseName = [string]$Context.GiteaPostgresDbName
        databaseUser = [string]$Context.GiteaPostgresUser
        runnerWasRunning = $RunnerWasRunning
    }

    $dumpPath = Join-Path $payloadPath "postgres.dump"
    $dumpCommand = 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump --format=custom --no-owner --no-acl --username "$POSTGRES_USER" --dbname "$POSTGRES_DB"'
    Invoke-GiteaDockerToFile -Arguments @("exec", $Context.GiteaPostgresContainerName, "sh", "-c", $dumpCommand) -OutputPath $dumpPath
    $dumpStream = [System.IO.File]::OpenRead((ConvertTo-ExtendedLengthPath -Path $dumpPath))
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
    $totalBytes = Measure-BackupFileEntriesSize -Entries $files
    $manifest = [ordered]@{
        schemaVersion = 2
        format = "agent-sdlc-gitea-backup"
        backupId = $backupId
        operationId = $OperationId
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
        requiredComponents = @("postgres-dump", "gitea-data", "gitea-config", "operator-state", "runtime-snapshot", "postgres-topology", "restore-context")
        files = $files
    }
    $manifest.metadataSha256 = Get-GiteaBackupManifestDigest -Manifest ([pscustomobject]$manifest)
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
    $backupRoot = [string]$Context.BackupRoot
    if (-not (Test-LongPath -Path $backupRoot -PathType Container)) {
        throw "Backup ID '$BackupId' was not found."
    }
    $backupPath = Join-Path $backupRoot $BackupId
    if (-not (Test-LongPath -Path $backupPath -PathType Container)) {
        throw "Backup ID '$BackupId' was not found."
    }
    $validation = Test-GiteaBackupIntegrity -BackupPath $backupPath
    if (-not $validation.IsValid) {
        throw "Backup '$BackupId' failed integrity validation ($($validation.Reason)); restore is blocked."
    }
    if (-not (Test-LongPath -Path (Join-Path $backupPath "payload\postgres.dump") -PathType Leaf) -or
        -not (Test-LongPath -Path (Join-Path $backupPath "payload\private\gitea-runtime.json") -PathType Leaf) -or
        -not (Test-LongPath -Path (Join-Path $backupPath "payload\private\postgres-topology.json") -PathType Leaf) -or
        -not (Test-LongPath -Path (Join-Path $backupPath "payload\private\restore-context.json") -PathType Leaf)) {
        throw "Backup '$BackupId' is missing required restore payloads."
    }
    return [pscustomobject]@{
        Path = $backupPath
        Manifest = $validation.Manifest
    }
}

function Show-GiteaBackupList {
    param([hashtable]$Context)

    $backupRoot = [string]$Context.BackupRoot
    if (-not (Test-LongPath -Path $backupRoot -PathType Container)) {
        Write-Host "No Gitea backups found (backup root is missing)."
        return
    }
    $directories = @(Get-LongPathDirectoryEntries -Path $backupRoot | Where-Object { $_.PSIsContainer } | Sort-Object Name -Descending)
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
        $state = if ($validation.IsValid) { "valid" } elseif ($validation.Reason -eq "manifest-missing") { "partial" } else { "corrupt" }
        Write-Host ("{0}  {1}  source={2}  size={3}  state={4}  integrity={5}" -f $directory.Name, $created, $version, $size, $state, $validation.Reason)
    }
}

function Get-GiteaLifecycleStatus {
    param([hashtable]$Context)

    $marker = Get-GiteaLifecycleRecoveryMarker -Context $Context
    $recordDirectory = Join-Path $Context.RepoRoot ".agent-sdlc\dev-env\gitea\upgrades"
    $latestRecord = $null
    if (Test-LongPath -Path $recordDirectory -PathType Container) {
        foreach ($file in @(Get-LongPathDirectoryEntries -Path $recordDirectory | Where-Object { -not $_.PSIsContainer -and $_.Name -like "*.json" } | Sort-Object LastWriteTimeUtc -Descending)) {
            try {
                $latestRecord = Read-LongPathText -Path $file.FullName | ConvertFrom-Json -ErrorAction Stop
                break
            }
            catch {
                continue
            }
        }
    }
    return [pscustomobject]@{
        RecoveryPending = ($null -ne $marker)
        Marker = $marker
        LatestOperationRecord = $latestRecord
    }
}

function Get-BackupRuntime {
    param(
        [Parameter(Mandatory = $true)][string]$BackupPath,
        [Parameter(Mandatory = $true)][object]$Manifest
    )

    $runtimePath = Join-Path $BackupPath "payload\private\gitea-runtime.json"
    $runtime = Read-LongPathText -Path $runtimePath | ConvertFrom-Json
    Assert-GiteaBackupArtifactSchema -Artifact $runtime -ArtifactName "Gitea runtime snapshot" -Manifest $Manifest
    if (-not $runtime -or -not $runtime.imageReference -or -not $runtime.mounts -or -not $runtime.ports) {
        throw "The backup does not contain enough protected runtime metadata to restore the Gitea container."
    }
    Assert-GiteaImmutableImageReference -Reference ([string]$runtime.imageReference)
    return $runtime
}

function Get-GiteaRecoveryRuntime {
    param(
        [Parameter(Mandatory = $true)][string]$BackupPath,
        [Parameter(Mandatory = $true)][object]$Manifest
    )

    $runtimePath = Join-Path $BackupPath "payload\private\gitea-runtime.json"
    try {
        $runtime = Read-LongPathText -Path $runtimePath | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "The upgrade backup runtime metadata is unreadable; recovery reconciliation is blocked."
    }
    Assert-GiteaBackupArtifactSchema -Artifact $runtime -ArtifactName "Gitea runtime snapshot" -Manifest $Manifest
    if (-not $runtime -or -not $runtime.imageReference -or -not $runtime.mounts -or -not $runtime.ports -or
        [string]$runtime.imageId -cnotmatch '^sha256:[0-9a-f]{64}$' -or
        [string]$runtime.sourceVersion -cnotmatch '^\d+\.\d+\.\d+$' -or
        [string]$Manifest.sourceVersion -cne [string]$runtime.sourceVersion -or
        [string]$Manifest.sourceImage -cne [string]$runtime.originalImageReference -or
        [string]$Manifest.sourceImageDigest -cne [string]$runtime.imageReference) {
        throw "The upgrade backup runtime metadata does not match its manifest or lacks a captured source image identity; recovery reconciliation is blocked."
    }

    $reference = [string]$runtime.imageReference
    $isLegacyConcatenation = $false
    $legacyDigestCount = 0
    if ($reference -cmatch '^(docker\.gitea\.com/gitea@sha256:[0-9a-f]{64}|sha256:[0-9a-f]{64})$') {
        Assert-GiteaImmutableImageReference -Reference $reference
    }
    else {
        # Compatibility is limited to the reported schema-1 upgrade backup defect:
        # two identical official refs and one gitea/gitea alias at the same SHA,
        # joined with one ASCII space. This value is never used as an image reference.
        $references = $reference.Split([char[]]@([char]32), [System.StringSplitOptions]::None)
        $officialDigestCount = 0
        $aliasDigestCount = 0
        $sharedDigest = $null
        $matchesIncidentDigestShape = $references.Count -eq 3
        foreach ($candidate in $references) {
            if ($candidate -cmatch '^docker\.gitea\.com/gitea@sha256:([0-9a-f]{64})$') {
                $candidateDigest = [string]$Matches[1]
                $officialDigestCount++
            }
            elseif ($candidate -cmatch '^gitea/gitea@sha256:([0-9a-f]{64})$') {
                $candidateDigest = [string]$Matches[1]
                $aliasDigestCount++
            }
            else {
                $matchesIncidentDigestShape = $false
                break
            }
            if ($null -eq $sharedDigest) { $sharedDigest = $candidateDigest }
            elseif ($candidateDigest -cne $sharedDigest) { $matchesIncidentDigestShape = $false }
        }
        if ([int]$Manifest.schemaVersion -ne 1 -or [string]$Manifest.kind -cne "upgrade" -or
            -not $matchesIncidentDigestShape -or $officialDigestCount -ne 2 -or $aliasDigestCount -ne 1 -or
            [string]::Join(" ", $references) -cne $reference) {
            throw "The upgrade backup image reference is invalid and does not match the narrowly supported schema-1 recovery format; recovery reconciliation is blocked."
        }
        $isLegacyConcatenation = $true
        $legacyDigestCount = $references.Count
    }

    $runtime | Add-Member -NotePropertyName recoveryUsedLegacyDigestCompatibility -NotePropertyValue $isLegacyConcatenation -Force
    $runtime | Add-Member -NotePropertyName recoveryLegacyDigestCount -NotePropertyValue $legacyDigestCount -Force
    return $runtime
}

function Assert-BackupRuntimeMatchesContext {
    param(
        [hashtable]$Context,
        [object]$Runtime,
        [switch]$AllowValidatedLegacyImageReference
    )

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
    if ($AllowValidatedLegacyImageReference) {
        $legacyValidationFlag = $Runtime.PSObject.Properties["recoveryUsedLegacyDigestCompatibility"]
        $legacyDigestCount = $Runtime.PSObject.Properties["recoveryLegacyDigestCount"]
        if (-not $legacyValidationFlag -or -not [bool]$legacyValidationFlag.Value -or
            -not $legacyDigestCount -or [int]$legacyDigestCount.Value -ne 3) {
            throw "Recovery reconciliation received an unverified legacy image reference; the backup topology is blocked."
        }
    }
    else {
        Assert-GiteaImmutableImageReference -Reference ([string]$Runtime.imageReference)
    }
}

function Write-TemporaryEnvironmentFile {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Environment
    )

    foreach ($entry in $Environment) {
        if ($entry -match '[\r\n]') {
            throw "The captured Gitea environment contains a line break and cannot be restored safely."
        }
    }
    $backupRoot = Ensure-BackupRoot -Context $Context
    $path = Join-Path $backupRoot (".gitea-env-{0}.tmp" -f [Guid]::NewGuid().ToString("N"))
    $environmentText = if ($Environment.Count -gt 0) {
        [string]::Join([Environment]::NewLine, $Environment) + [Environment]::NewLine
    }
    else { "" }
    Write-LongPathText -Path $path -Text $environmentText
    Set-RestrictedBackupAcl -Path $path
    return $path
}

function New-GiteaContainerFromRuntime {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][object]$Runtime,
        [Parameter(Mandatory = $true)][string]$ImageReference
    )

    Assert-GiteaImmutableImageReference -Reference $ImageReference
    Assert-BackupRuntimeMatchesContext -Context $Context -Runtime $Runtime
    $environmentFile = Write-TemporaryEnvironmentFile -Context $Context -Environment @($Runtime.environment)
    try {
        $arguments = @("run", "-d", "--name", $Context.GiteaContainerName, "--restart", [string]$Runtime.restartPolicy)
        if ($Context.GiteaLifecycleE2ERunId) {
            if ([string]$Context.GiteaLifecycleE2ERunId -notmatch '^[0-9a-f]{32}$') {
                throw "The isolated lifecycle E2E ownership label is invalid; refusing to create a fixture container."
            }
            $arguments += @("--label", "agent-sdlc.lifecycle-e2e.run-id=$($Context.GiteaLifecycleE2ERunId)")
        }
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
        if (Test-LongPath -Path $environmentFile -PathType Leaf) {
            Remove-LongPathEntry -Path $environmentFile
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

    $archiveListing = Invoke-GiteaDockerWithInputFile -Arguments @("exec", "-i", $Context.GiteaPostgresContainerName, "pg_restore", "--list") -InputPath $DumpPath
    $databaseMatch = [regex]::Match([string]$archiveListing, '(?m)^;\s*dbname:\s*(?<name>.*?)\s*$')
    if (-not $databaseMatch.Success) {
        throw "The selected PostgreSQL archive does not identify its database; restore is blocked."
    }
    $archiveDatabaseName = [string]$databaseMatch.Groups["name"].Value.Trim()
    if ($archiveDatabaseName -ne [string]$Context.GiteaPostgresDbName) {
        throw "The selected PostgreSQL archive database name does not match the configured Gitea database; restore is blocked."
    }

    # --create with --clean drops and recreates only the database recorded in this verified archive.
    # The connection database is the default administrative database; the PostgreSQL container stays in place.
    $restoreCommand = 'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore --clean --if-exists --create --exit-on-error --no-owner --no-acl --username "$POSTGRES_USER" --dbname postgres'
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
    param(
        [Parameter(Mandatory = $true)][string]$BackupPath,
        [Parameter(Mandatory = $true)][object]$Manifest
    )
    $restoreContext = Read-LongPathText -Path (Join-Path $BackupPath "payload\private\restore-context.json") | ConvertFrom-Json -ErrorAction Stop
    Assert-GiteaBackupArtifactSchema -Artifact $restoreContext -ArtifactName "Restore Context" -Manifest $Manifest
    foreach ($requiredField in @("configPath", "configSource", "databaseName", "databaseUser", "runnerWasRunning")) {
        if (-not $restoreContext.PSObject.Properties[$requiredField]) {
            throw "The backup Restore Context is missing '$requiredField'; restore is blocked."
        }
    }
    return $restoreContext
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
        Copy-LongPathFile -Source (Join-Path $operatorPath "bootstrap-config.json") -Destination $RestoreContext.configPath -Force
    }
    foreach ($entry in @(
        @{ Name = "generated-secrets.json"; Destination = $Context.GiteaSecretsPath },
        @{ Name = "bootstrap-summary.json"; Destination = $Context.GiteaBootstrapSummaryPath },
        @{ Name = "effective-settings.json"; Destination = $Context.EffectiveBootstrapSettingsPath }
    )) {
        $source = Join-Path $operatorPath $entry.Name
        if (Test-LongPath -Path $source -PathType Leaf) {
            Copy-LongPathFile -Source $source -Destination $entry.Destination -Force
        }
        elseif (Test-LongPath -Path $entry.Destination -PathType Leaf) {
            Remove-LongPathEntry -Path $entry.Destination
        }
    }
}

function Replace-GiteaDataTree {
    param(
        [Parameter(Mandatory = $true)][string]$BackupSource,
        [Parameter(Mandatory = $true)][string]$LiveDestination
    )

    if (Test-LongPath -Path $LiveDestination) {
        if (((Get-LongPathItem -Path $LiveDestination).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Live Gitea destination '$LiveDestination' is a reparse point; refusing to overwrite redirected data."
        }
        Remove-LongPathTree -Path $LiveDestination
    }
    New-LongPathDirectory -Path $LiveDestination
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

    if (-not $Record.operationId -or [string]$Record.operationId -notmatch '^[A-Za-z0-9][A-Za-z0-9T._-]{0,95}$') {
        throw "The operation record identity is missing or invalid."
    }
    $recordPathRoot = Join-Path $Context.RepoRoot ".agent-sdlc\dev-env\gitea\upgrades"
    $recordDirectory = $recordPathRoot
    if (-not (Test-LongPath -Path $recordDirectory -PathType Container)) {
        New-LongPathDirectory -Path $recordDirectory
    }
    $recordPath = Join-Path $recordDirectory ("{0}.json" -f $Record.operationId)
    $expectedJson = ConvertTo-Json -InputObject $Record -Depth 100 -Compress
    $expectedBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($expectedJson)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $expectedDigest = [System.BitConverter]::ToString($sha256.ComputeHash($expectedBytes)).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha256.Dispose() }

    if (Test-LongPath -Path $recordPath -PathType Leaf) {
        try {
            $existing = Read-LongPathText -Path $recordPath | ConvertFrom-Json -ErrorAction Stop
            $existingJson = ConvertTo-Json -InputObject $existing -Depth 100 -Compress
            $existingBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($existingJson)
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            try {
                $existingDigest = [System.BitConverter]::ToString($sha256.ComputeHash($existingBytes)).Replace('-', '').ToLowerInvariant()
            }
            finally { $sha256.Dispose() }
            if ($existingDigest -cne $expectedDigest) {
                throw "An operation record with this ID already exists with different content; append-only history will not be overwritten."
            }
            return $existing
        }
        catch {
            if ($_.Exception.Message -like "An operation record with this ID already exists*") { throw }
            throw "An existing operation record is unreadable; refusing to replace it."
        }
    }

    $temporaryPath = Join-Path $recordDirectory (".{0}.{1}.tmp" -f $Record.operationId, [Guid]::NewGuid().ToString("N"))
    try {
        Save-BackupJson -Path $temporaryPath -Value $Record
        Move-LongPathFile -Source $temporaryPath -Destination $recordPath
        $saved = Read-LongPathText -Path $recordPath | ConvertFrom-Json -ErrorAction Stop
        $savedJson = ConvertTo-Json -InputObject $saved -Depth 100 -Compress
        $savedBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($savedJson)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $savedDigest = [System.BitConverter]::ToString($sha256.ComputeHash($savedBytes)).Replace('-', '').ToLowerInvariant()
        }
        finally { $sha256.Dispose() }
        if ($savedDigest -cne $expectedDigest) {
            throw "The operation record failed reload verification; the recovery marker must remain."
        }
        return $saved
    }
    finally {
        if (Test-LongPath -Path $temporaryPath -PathType Leaf) { Remove-LongPathEntry -Path $temporaryPath }
    }
}

function Get-GiteaOperationRecordPath {
    param([hashtable]$Context, [Parameter(Mandatory = $true)][string]$OperationId)
    if ($OperationId -notmatch '^[0-9a-f]{32}$') { throw "The operation record ID is invalid." }
    return Join-Path (Join-Path $Context.RepoRoot ".agent-sdlc\dev-env\gitea\upgrades") ("{0}.json" -f $OperationId)
}

function Test-GiteaTerminalOperationRecord {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$OperationId,
        [string[]]$AllowedResultPrefix = @("complete", "healthy-", "restored-", "reconciled-", "superseded-", "interrupted-")
    )
    try {
        $recordPath = Get-GiteaOperationRecordPath -Context $Context -OperationId $OperationId
        if (-not (Test-LongPath -Path $recordPath -PathType Leaf)) { return $false }
        $record = Read-LongPathText -Path $recordPath | ConvertFrom-Json -ErrorAction Stop
        if ([string]$record.operationId -cne $OperationId -or -not $record.result) { return $false }
        foreach ($prefix in $AllowedResultPrefix) {
            if ([string]$record.result -like "$prefix*") { return $true }
        }
        return $false
    }
    catch { return $false }
}

function Write-GiteaInterruptedOperationRecord {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][object]$Marker,
        [Parameter(Mandatory = $true)][string]$ErrorMessage
    )
    if (Test-GiteaTerminalOperationRecord -Context $Context -OperationId ([string]$Marker.operationId)) { return }
    $safeMessage = [Regex]::Replace([string]$ErrorMessage, '(?i)(password|token|secret|authorization|credential)(\s*[=:]\s*)[^\s,;]+', '$1$2[REDACTED]')
    if ($safeMessage.Length -gt 1000) { $safeMessage = $safeMessage.Substring(0, 1000) }
    New-GiteaOperationRecord -Context $Context -Record @{
        schemaVersion = 2
        operationId = [string]$Marker.operationId
        operationKind = [string]$Marker.operationKind
        startedAt = [string]$Marker.createdAt
        completedAt = [DateTime]::UtcNow.ToString("o")
        result = "interrupted-$([string]$Marker.phase)"
        backupId = [string]$Marker.backupId
        diagnosticBackupId = [string]$Marker.diagnosticBackupId
        nextAction = [string]$Marker.nextAction
        lastCompletedStage = [string]$Marker.lastCompletedStage
        errorSummary = $safeMessage
        giteaContainerId = [string]$Marker.giteaContainerId
        targetContainerId = [string]$Marker.targetContainerId
        postgresContainerId = [string]$Marker.postgresContainerId
        runnerContainerId = [string]$Marker.runnerContainerId
        sourceVersion = [string]$Marker.sourceVersion
        targetVersion = [string]$Marker.targetVersion
        targetImageDigest = [string]$Marker.targetImageDigest
    } | Out-Null
}

function Get-GiteaLifecycleRecoveryMarkerPath {
    param([hashtable]$Context)
    return Join-Path $Context.RepoRoot ".agent-sdlc\dev-env\gitea\lifecycle-recovery.json"
}

function Get-GiteaLifecycleRecoveryMarker {
    param([hashtable]$Context)

    $markerPath = Get-GiteaLifecycleRecoveryMarkerPath -Context $Context
    if (-not (Test-LongPath -Path $markerPath)) { return $null }
    if (-not (Test-LongPath -Path $markerPath -PathType Leaf)) {
        throw "A Gitea lifecycle recovery marker exists but is not a file; automatic lifecycle operations are blocked."
    }
    try {
        $marker = Read-LongPathText -Path $markerPath | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "A Gitea lifecycle recovery marker is unreadable; an operator must review it before continuing."
    }
    if ([int]$marker.schemaVersion -notin @(1, 2, 3) -or
        [string]$marker.operationKind -notin @("upgrade", "restore") -or
        [string]$marker.backupId -notmatch '^\d{8}T\d{6}Z-[0-9a-f]{32}$') {
        throw "The Gitea lifecycle recovery marker has an unsupported or incomplete schema; automatic lifecycle operations are blocked."
    }
    if ([int]$marker.schemaVersion -eq 3 -and
        ([string]$marker.operationId -notmatch '^[0-9a-f]{32}$' -or
         [int]$marker.revision -lt 1 -or
         -not $marker.PSObject.Properties["nextAction"] -or
         -not $marker.PSObject.Properties["lastCompletedStage"] -or
         -not $marker.PSObject.Properties["createdAt"] -or
         -not $marker.PSObject.Properties["updatedAt"])) {
        throw "The Gitea lifecycle recovery marker has an unsupported or incomplete schema; automatic lifecycle operations are blocked."
    }
    return $marker
}

function Assert-NoPendingGiteaRecovery {
    param([hashtable]$Context)

    $marker = Get-GiteaLifecycleRecoveryMarker -Context $Context
    if (-not $marker) { return }
    throw "A previous Gitea $($marker.operationKind) operation is incomplete. Lifecycle operations remain blocked. Review the current service and retained Backup ID '$($marker.backupId)'. Use reconcile-recovery only after verifying the exact original-source, healthy-target, or restore-complete state. Use Restore only with the same Backup ID and a new explicit confirmation; no automatic resume or rollback is attempted."
}

function Set-GiteaLifecycleRecoveryMarker {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][ValidateSet("upgrade", "restore")][string]$OperationKind,
        [Parameter(Mandatory = $true)][string]$BackupId,
        [string]$DiagnosticBackupId,
        [ValidateSet("upgrade-prepared", "backup-in-progress", "backup-verified", "target-start-attempted", "restore-prepared", "restore-applying", "close-pending", "reconcile-pending")][string]$Phase = "backup-verified",
        [string]$OperationId = ([Guid]::NewGuid().ToString("N")),
        [string]$NextAction = "",
        [string]$LastCompletedStage = "preflight",
        [string]$GiteaContainerId,
        [string]$TargetContainerId,
        [string]$PostgresContainerId,
        [string]$RunnerContainerId,
        [string]$SourceImageId,
        [string]$SourceImageReference,
        [string]$SourceOriginalImageReference,
        [string]$SourceVersion,
        [string]$TargetImageDigest,
        [string]$TargetVersion,
        [string]$GiteaState,
        [string]$PostgresState,
        [string]$RunnerState,
        [string]$SupersedesOperationId,
        [string[]]$PriorDiagnosticBackupIds = @(),
        [switch]$ReplaceExisting
    )

    if ($OperationId -notmatch '^[0-9a-f]{32}$') { throw "A valid operation ID is required for a Recovery Marker." }
    if (-not $NextAction) { $NextAction = if ($OperationKind -eq "upgrade") { "stop-runner" } else { "stop-runner" } }
    $markerPath = Get-GiteaLifecycleRecoveryMarkerPath -Context $Context
    if (Test-LongPath -Path $markerPath) {
        if (-not $ReplaceExisting) { throw "A Recovery Marker already exists; refusing to replace an active attempt." }
        $existingMarker = Get-GiteaLifecycleRecoveryMarker -Context $Context
        if (-not $existingMarker) { throw "The existing Recovery Marker could not be verified; refusing replacement." }
        if ([string]$existingMarker.backupId -cne $BackupId -or
            [string]$existingMarker.operationId -cne $SupersedesOperationId -or
            -not (Test-GiteaTerminalOperationRecord -Context $Context -OperationId ([string]$existingMarker.operationId) -AllowedResultPrefix @("interrupted-"))) {
            throw "Only a terminal interrupted attempt for the same Backup ID can be superseded; the existing Recovery Marker remains."
        }
    }
    $markerDirectory = Get-LongPathParent -Path $markerPath
    if (-not (Test-LongPath -Path $markerDirectory -PathType Container)) {
        New-LongPathDirectory -Path $markerDirectory
    }
    $temporaryPath = Join-Path $markerDirectory (".lifecycle-recovery-{0}.tmp" -f [Guid]::NewGuid().ToString("N"))
    try {
        Save-BackupJson -Path $temporaryPath -Value ([ordered]@{
            schemaVersion = 3
            operationId = $OperationId
            operationKind = $OperationKind
            phase = $Phase
            backupId = $BackupId
            diagnosticBackupId = $DiagnosticBackupId
            revision = 1
            createdAt = [DateTime]::UtcNow.ToString("o")
            updatedAt = [DateTime]::UtcNow.ToString("o")
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
        })
        Move-LongPathFile -Source $temporaryPath -Destination $markerPath -Force
        $saved = Get-GiteaLifecycleRecoveryMarker -Context $Context
        if ([string]$saved.operationId -cne $OperationId -or [int]$saved.revision -ne 1 -or [string]$saved.backupId -cne $BackupId) {
            throw "The initial Recovery Marker failed reload verification."
        }
    }
    finally {
        if (Test-LongPath -Path $temporaryPath -PathType Leaf) {
            Remove-LongPathEntry -Path $temporaryPath
        }
    }
}

function Update-GiteaLifecycleRecoveryMarkerPhase {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$BackupId,
        [Parameter(Mandatory = $true)][string]$Phase,
        [string]$NextAction,
        [string]$LastCompletedStage,
        [string]$DiagnosticBackupId,
        [string]$GiteaContainerId,
        [string]$TargetContainerId,
        [string]$RunnerState,
        [string]$OperationId
    )

    $marker = Get-GiteaLifecycleRecoveryMarker -Context $Context
    if (-not $marker -or [string]$marker.backupId -ne $BackupId) {
        throw "The expected Recovery Marker is missing or does not match Backup ID '$BackupId'; refusing to continue the lifecycle operation."
    }
    if ($OperationId -and [string]$marker.operationId -cne $OperationId) {
        throw "The active Recovery Marker operation ID changed; refusing to advance another attempt."
    }
    if ([int]$marker.schemaVersion -ne 3) {
        throw "Only a schema-3 Recovery Marker can be advanced automatically."
    }
    $marker.phase = $Phase
    if ($NextAction) { $marker.nextAction = $NextAction }
    if ($LastCompletedStage) { $marker.lastCompletedStage = $LastCompletedStage }
    if ($DiagnosticBackupId) { $marker.diagnosticBackupId = $DiagnosticBackupId }
    if ($GiteaContainerId) { $marker.giteaContainerId = $GiteaContainerId }
    if ($TargetContainerId) { $marker.targetContainerId = $TargetContainerId }
    if ($RunnerState) { $marker.runnerState = $RunnerState }
    $marker.revision = [int]$marker.revision + 1
    $marker.updatedAt = [DateTime]::UtcNow.ToString("o")
    $markerPath = Get-GiteaLifecycleRecoveryMarkerPath -Context $Context
    $markerDirectory = Get-LongPathParent -Path $markerPath
    $temporaryPath = Join-Path $markerDirectory (".lifecycle-recovery-{0}.tmp" -f [Guid]::NewGuid().ToString("N"))
    try {
        Save-BackupJson -Path $temporaryPath -Value $marker
        Move-LongPathFile -Source $temporaryPath -Destination $markerPath -Force
        $saved = Get-GiteaLifecycleRecoveryMarker -Context $Context
        if ([int]$saved.revision -ne [int]$marker.revision -or [string]$saved.operationId -cne [string]$marker.operationId) {
            throw "The Recovery Marker transition failed reload verification."
        }
    }
    finally {
        if (Test-LongPath -Path $temporaryPath -PathType Leaf) {
            Remove-LongPathEntry -Path $temporaryPath
        }
    }
}

function Clear-GiteaLifecycleRecoveryMarker {
    param([hashtable]$Context, [string]$OperationId)

    $markerPath = Get-GiteaLifecycleRecoveryMarkerPath -Context $Context
    if ((Test-LongPath -Path $markerPath) -and -not (Test-LongPath -Path $markerPath -PathType Leaf)) {
        throw "The Gitea lifecycle recovery marker path is not a file; refusing to clear it automatically."
    }
    if (Test-LongPath -Path $markerPath -PathType Leaf) {
        $marker = Get-GiteaLifecycleRecoveryMarker -Context $Context
        if ([int]$marker.schemaVersion -eq 3) {
            $requiredOperationId = if ($OperationId) { $OperationId } else { [string]$marker.operationId }
            if ([string]$marker.operationId -cne $requiredOperationId) {
                throw "The Recovery Marker operation changed; refusing to clear it."
            }
            $recordPath = Join-Path (Join-Path $Context.RepoRoot ".agent-sdlc\dev-env\gitea\upgrades") ("{0}.json" -f $requiredOperationId)
            if (-not (Test-LongPath -Path $recordPath -PathType Leaf)) {
                throw "A reloadable terminal Operation Record is required before clearing the Recovery Marker."
            }
            $record = Read-LongPathText -Path $recordPath | ConvertFrom-Json -ErrorAction Stop
            if ([string]$record.operationId -cne $requiredOperationId -or [string]$record.result -notmatch '^(complete|healthy-|restored-|reconciled-|superseded-|interrupted-)') {
                throw "The Operation Record does not match the Recovery Marker terminal attempt; marker remains."
            }
        }
        Remove-LongPathEntry -Path $markerPath
    }
}

function Invoke-GiteaRecoveryReconciliation {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$BackupId,
        [ValidateSet("original-source", "healthy-target", "restore-complete")][string]$Mode = "original-source",
        [Parameter(Mandatory = $true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedGiteaContainerId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedPostgresContainerId,
        [Parameter(Mandatory = $true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedRunnerContainerId
    )

    Assert-NativeWindowsHost
    $Context.DockerHost = Assert-DockerDesktopReady
    $marker = Get-GiteaLifecycleRecoveryMarker -Context $Context
    if (-not $marker -or [string]$marker.backupId -ne $BackupId) {
        throw "Recovery reconciliation requires the matching retained Recovery Marker and Backup ID."
    }
    if (($Mode -in @("original-source", "healthy-target") -and [string]$marker.operationKind -ne "upgrade") -or
        ($Mode -eq "restore-complete" -and [string]$marker.operationKind -ne "restore")) {
        throw "Recovery mode '$Mode' does not match the active $($marker.operationKind) marker."
    }

    $selected = $null
    $runtime = $null
    $earlySourceCloseout = $false
    if ($Mode -eq "original-source") {
        if ([int]$marker.schemaVersion -eq 3 -and [string]$marker.operationKind -eq "upgrade" -and
            [string]$marker.phase -notin @("upgrade-prepared", "backup-in-progress", "backup-verified")) {
            throw "The target create/start stage may have begun; original-source closeout is forbidden. Use the same Backup ID for explicit Restore or stop for operator maintenance."
        }
        $backupPath = Join-Path ([string]$Context.BackupRoot) $BackupId
        if (Test-LongPath -Path $backupPath -PathType Container) {
            $integrity = Test-GiteaBackupIntegrity -BackupPath $backupPath
            if ($integrity.IsValid) {
                if ([string]$integrity.Manifest.kind -cne "upgrade") {
                    throw "The Recovery Marker Backup ID resolves to a different valid backup kind; original-source closeout is blocked."
                }
                $selected = Get-GiteaBackupById -Context $Context -BackupId $BackupId
                $runtime = Get-GiteaRecoveryRuntime -BackupPath $selected.Path -Manifest $selected.Manifest
                Assert-BackupRuntimeMatchesContext -Context $Context -Runtime $runtime -AllowValidatedLegacyImageReference:([bool]$runtime.recoveryUsedLegacyDigestCompatibility)
                if ([string]$selected.Manifest.sourceVersion -cne [string]$runtime.sourceVersion) {
                    throw "The upgrade backup manifest and runtime source versions disagree; recovery reconciliation is blocked."
                }
            }
        }
        if (-not $selected) {
            if ([int]$marker.schemaVersion -ne 3 -or
                [string]$marker.phase -notin @("upgrade-prepared", "backup-in-progress", "backup-verified") -or
                -not $marker.sourceImageId -or -not $marker.sourceImageReference -or
                -not $marker.sourceOriginalImageReference -or -not $marker.sourceVersion) {
                throw "Original-source closeout requires either a valid retained upgrade Backup or complete write-ahead source image/version identity before target startup; marker remains."
            }
            Assert-GiteaImmutableImageReference -Reference ([string]$marker.sourceImageReference)
            $runtime = [pscustomobject]@{
                sourceVersion = [string]$marker.sourceVersion
                imageId = [string]$marker.sourceImageId
                imageReference = [string]$marker.sourceImageReference
                originalImageReference = [string]$marker.sourceOriginalImageReference
                recoveryUsedLegacyDigestCompatibility = $false
                recoveryLegacyDigestCount = 0
            }
            $earlySourceCloseout = $true
        }
    }
    else {
        $selected = Get-GiteaBackupById -Context $Context -BackupId $BackupId
        if ([string]$selected.Manifest.kind -ne "upgrade") {
            throw "Recovery reconciliation requires a valid upgrade backup; no service state was changed."
        }
        $runtime = Get-GiteaRecoveryRuntime -BackupPath $selected.Path -Manifest $selected.Manifest
        Assert-BackupRuntimeMatchesContext -Context $Context -Runtime $runtime -AllowValidatedLegacyImageReference:([bool]$runtime.recoveryUsedLegacyDigestCompatibility)
        if ([string]$selected.Manifest.sourceVersion -ne [string]$runtime.sourceVersion) {
            throw "The upgrade backup manifest and runtime source versions disagree; recovery reconciliation is blocked."
        }
    }

    $gitea = Assert-GiteaContainerIdentity -Context $Context
    Assert-GiteaLocalStorageOnly -ConfigFilePath (Join-Path $Context.GiteaConfigDir "app.ini") -Environment @($gitea.Config.Env) -Container $gitea
    $postgres = Assert-PostgresContainerIdentity -Context $Context
    $runner = Get-GiteaRunnerInfo -Context $Context
    $recordedGiteaId = if ($Mode -eq "original-source") {
        if ($marker.PSObject.Properties["giteaContainerId"]) { [string]$marker.giteaContainerId } else { "" }
    }
    else {
        if ($marker.PSObject.Properties["targetContainerId"]) { [string]$marker.targetContainerId } else { "" }
    }
    $recordedPostgresId = if ($marker.PSObject.Properties["postgresContainerId"]) { [string]$marker.postgresContainerId } else { "" }
    $recordedRunnerId = if ($marker.PSObject.Properties["runnerContainerId"]) { [string]$marker.runnerContainerId } else { "" }
    foreach ($identity in @(
        @{ Name = "Gitea"; Expected = $ExpectedGiteaContainerId; Actual = (Get-GiteaContainerId -Container $gitea); Recorded = $recordedGiteaId },
        @{ Name = "PostgreSQL"; Expected = $ExpectedPostgresContainerId; Actual = (Get-GiteaContainerId -Container $postgres); Recorded = $recordedPostgresId },
        @{ Name = "Runner"; Expected = $ExpectedRunnerContainerId; Actual = (Get-GiteaContainerId -Container $runner); Recorded = $recordedRunnerId }
    )) {
        if (-not $identity.Actual -or $identity.Actual -ne $identity.Expected -or
            ($identity.Recorded -and $identity.Recorded -ne $identity.Expected)) {
            throw "The current $($identity.Name) container ID does not match the explicitly confirmed original ID; recovery marker remains."
        }
    }
    $expectedVersion = if ($Mode -eq "original-source") { [string]$runtime.sourceVersion } elseif ($Mode -eq "healthy-target") { [string]$marker.targetVersion } else { [string]$runtime.sourceVersion }
    if ($Mode -eq "original-source") {
        if ([string]$gitea.State.Status -ne "running" -or [string]$gitea.Image -ne [string]$runtime.imageId -or
            [string]$gitea.Config.Image -ne [string]$runtime.originalImageReference) {
            throw "The current Gitea container is not the captured source image in a running state; recovery marker remains."
        }
        Assert-GiteaBootstrapImagePin -Context $Context -ExpectedImageReference ([string]$runtime.originalImageReference)
    }
    elseif ([string]$gitea.State.Status -ne "running" -or
        [string]$gitea.Config.Image -cne $(if ($Mode -eq "healthy-target") { [string]$marker.targetImageDigest } else { [string]$runtime.imageReference })) {
        throw "The current Gitea container is not the verified $Mode target image in a running state; recovery marker remains."
    }
    $expectedRunnerStatus = if ($Mode -eq "original-source" -and $marker.runnerState) {
        [string]$marker.runnerState
    }
    elseif ($selected -and [bool]$selected.Manifest.runnerWasRunning) { "running" }
    else { "exited" }
    if ($Mode -eq "healthy-target") {
        $expectedRunnerStatus = if ([string]$marker.runnerState -eq "running") { "running" } else { "exited" }
        Assert-GiteaBootstrapImagePin -Context $Context -ExpectedImageReference ([string]$marker.targetImageDigest)
    }
    elseif ($Mode -eq "restore-complete") {
        Assert-GiteaBootstrapImagePin -Context $Context -ExpectedImageReference ([string]$runtime.imageReference)
    }
    if ([string]$runner.State.Status -ne $expectedRunnerStatus) {
        throw "The shared Runner state differs from the captured upgrade source; recovery marker remains."
    }

    if (-not $earlySourceCloseout) {
        $postgresTopology = Get-GiteaPostgresTopology -BackupPath $selected.Path -Manifest $selected.Manifest
        Assert-PostgresRestoreCompatibility -BackupTopology $postgresTopology -CurrentContainer $postgres -Context $Context -ManifestSchemaVersion ([int]$selected.Manifest.schemaVersion)
    }
    Assert-GiteaDatabaseTarget -GiteaContainer $gitea -PostgresContainer $postgres -Context $Context
    Assert-GiteaApiVersion -Context $Context -ExpectedVersion $expectedVersion

    if ($Mode -eq "restore-complete") {
        if (-not $marker.diagnosticBackupId) {
            throw "Restore closeout requires the retained diagnostic Backup ID; the marker remains."
        }
        $diagnostic = Get-GiteaBackupById -Context $Context -BackupId ([string]$marker.diagnosticBackupId)
        if ([string]$diagnostic.Manifest.kind -cne "pre-restore-diagnostic") {
            throw "Restore closeout's diagnostic Backup ID does not identify a valid pre-restore diagnostic backup."
        }
    }

    $expectedConfirmation = switch ($Mode) {
        "healthy-target" { "RECONCILE healthy-target $BackupId TARGET $($marker.targetImageDigest) VERSION $($marker.targetVersion) GITEA $ExpectedGiteaContainerId POSTGRES $ExpectedPostgresContainerId RUNNER $ExpectedRunnerContainerId DATABASE VERIFIED" }
        "restore-complete" { "RECONCILE restore-complete $BackupId TARGET $($runtime.imageReference) VERSION $($runtime.sourceVersion) GITEA $ExpectedGiteaContainerId POSTGRES $ExpectedPostgresContainerId RUNNER $ExpectedRunnerContainerId DATABASE VERIFIED" }
        default { "RECONCILE original-source $BackupId GITEA $ExpectedGiteaContainerId POSTGRES $ExpectedPostgresContainerId RUNNER $ExpectedRunnerContainerId DATABASE VERIFIED" }
    }
    Confirm-GiteaLifecycleOperation -Prompt "Confirm the selected recovery mode, immutable image/version where applicable, all full container IDs, Gitea version health, and current database health. No database restore will run. Type '$expectedConfirmation'" -ExpectedText $expectedConfirmation

    if ([int]$marker.schemaVersion -eq 3 -and -not (Test-GiteaTerminalOperationRecord -Context $Context -OperationId ([string]$marker.operationId))) {
        Write-GiteaInterruptedOperationRecord -Context $Context -Marker $marker -ErrorMessage "The lifecycle attempt ended before writing its terminal operation record; the operator verified the selected reconciliation mode."
    }

    $reconciliationIdentity = "reconcile|$([string]$marker.operationId)|$Mode|$BackupId"
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $reconciliationOperationId = [System.BitConverter]::ToString($sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($reconciliationIdentity))).Replace('-', '').ToLowerInvariant().Substring(0, 32)
    }
    finally { $sha256.Dispose() }
    $reconciliationRecordPath = Get-GiteaOperationRecordPath -Context $Context -OperationId $reconciliationOperationId
    $expectedSourceDigest = if ([bool]$runtime.recoveryUsedLegacyDigestCompatibility) { $null } else { [string]$runtime.imageReference }
    if (Test-LongPath -Path $reconciliationRecordPath -PathType Leaf) {
        $existingCloseout = Read-LongPathText -Path $reconciliationRecordPath | ConvertFrom-Json -ErrorAction Stop
        if ([string]$existingCloseout.operationId -cne $reconciliationOperationId -or
            [string]$existingCloseout.operationKind -cne "reconcile-recovery" -or
            [string]$existingCloseout.result -cne "reconciled-$Mode-without-restore" -or
            [string]$existingCloseout.recoveryMode -cne $Mode -or
            [string]$existingCloseout.backupId -cne $BackupId -or
            [string]$existingCloseout.giteaContainerId -cne $ExpectedGiteaContainerId -or
            [string]$existingCloseout.postgresContainerId -cne $ExpectedPostgresContainerId -or
            [string]$existingCloseout.runnerContainerId -cne $ExpectedRunnerContainerId -or
            [string]$existingCloseout.sourceImageDigest -cne $expectedSourceDigest -or
            [string]$existingCloseout.sourceVersion -cne [string]$runtime.sourceVersion -or
            [string]$existingCloseout.sourceImageId -cne [string]$runtime.imageId -or
            [string]$existingCloseout.originalImageReference -cne [string]$runtime.originalImageReference -or
            [bool]$existingCloseout.databaseRestorePerformed -or
            [string]$existingCloseout.lifecycleTransaction -cne "complete" -or
            [string]$existingCloseout.integrationAcceptance -cne "pending" -or
            [string]$existingCloseout.operatorAttestation -cne $expectedConfirmation) {
            throw "A deterministic recovery closeout ID exists with different evidence; refusing to overwrite it or clear the Recovery Marker."
        }
    }
    else {
        New-GiteaOperationRecord -Context $Context -Record @{
        schemaVersion = 2
        operationId = $reconciliationOperationId
        operationKind = "reconcile-recovery"
        startedAt = if ($marker.PSObject.Properties["createdAt"]) { [string]$marker.createdAt } else { [DateTime]::UtcNow.ToString("o") }
        result = "reconciled-$Mode-without-restore"
        completedAt = [DateTime]::UtcNow.ToString("o")
        backupId = $BackupId
        sourceVersion = [string]$runtime.sourceVersion
        sourceImageDigest = $expectedSourceDigest
        sourceImageId = [string]$runtime.imageId
        originalImageReference = [string]$runtime.originalImageReference
        legacyImageReferenceReconciled = [bool]$runtime.recoveryUsedLegacyDigestCompatibility
        legacyRepoDigestCount = [int]$runtime.recoveryLegacyDigestCount
        giteaContainerId = $ExpectedGiteaContainerId
        postgresContainerId = $ExpectedPostgresContainerId
        runnerContainerId = $ExpectedRunnerContainerId
        operatorAttestation = $expectedConfirmation
        recoveryMode = $Mode
        databaseRestorePerformed = $false
        lifecycleTransaction = "complete"
        integrationAcceptance = "pending"
        markerSchemaVersion = [int]$marker.schemaVersion
        } | Out-Null
    }
    Clear-GiteaLifecycleRecoveryMarker -Context $Context -OperationId ([string]$marker.operationId)
    Write-Host "Recovery marker reconciled in '$Mode' mode after verifying Gitea, PostgreSQL, Runner and database state. No database restore or service restart was performed. Backup '$BackupId' was retained."
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
    $temporaryPath = Join-Path (Get-LongPathParent -Path $Context.ConfigPath) (".gitea-config-preflight-{0}.tmp" -f [Guid]::NewGuid().ToString("N"))
    try {
        Write-LongPathText -Path $temporaryPath -Text "preflight"
    }
    finally {
        if (Test-LongPath -Path $temporaryPath -PathType Leaf) {
            Remove-LongPathEntry -Path $temporaryPath
        }
    }
}

function Assert-GiteaBootstrapImagePin {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$ExpectedImageReference
    )

    if ([string]$Context.ConfigSource -ne "local" -or -not (Test-LongPath -Path $Context.ConfigPath -PathType Leaf)) {
        throw "Recovery closeout requires the generated local bootstrap config so its image pin can be verified."
    }
    try {
        $bootstrap = Read-LongPathText -Path $Context.ConfigPath | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "The local bootstrap config is unreadable; the recovery marker remains."
    }
    if ([string]$bootstrap.gitea.image -cne $ExpectedImageReference) {
        throw "The local bootstrap image pin does not match the verified image reference; the recovery marker remains."
    }
}

function Add-GiteaLifecycleDiagnosticValues {
    param(
        [AllowNull()][object]$Value,
        [AllowEmptyString()][string]$PropertyName,
        [System.Collections.Generic.List[string]]$Values,
        [bool]$MaskAllStrings = $false
    )

    if ($null -eq $Value) { return }
    $propertyIsSensitive = $PropertyName -match '(?i)password|passwd|token|secret|credential|authorization|private[_-]?key|access[_-]?key'
    if ($Value -is [string]) {
        if (($MaskAllStrings -or $propertyIsSensitive) -and $Value.Length -ge 4) {
            $Values.Add($Value)
        }
        return
    }

    $maskChildren = $MaskAllStrings -or $propertyIsSensitive
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            Add-GiteaLifecycleDiagnosticValues -Value $Value[$key] -PropertyName ([string]$key) -Values $Values -MaskAllStrings $maskChildren
        }
        return
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        foreach ($item in $Value) {
            Add-GiteaLifecycleDiagnosticValues -Value $item -PropertyName $PropertyName -Values $Values -MaskAllStrings $maskChildren
        }
        return
    }

    foreach ($property in $Value.PSObject.Properties) {
        Add-GiteaLifecycleDiagnosticValues -Value $property.Value -PropertyName $property.Name -Values $Values -MaskAllStrings $maskChildren
    }
}

function Add-GiteaLifecycleRawJsonDiagnosticValues {
    param(
        [AllowEmptyString()][string]$JsonText,
        [System.Collections.Generic.List[string]]$Values
    )

    if (-not $JsonText) { return }
    $pattern = '"(?<key>[^"\\]*(?:password|passwd|token|secret|credential|authorization|private[_-]?key|access[_-]?key)[^"\\]*)"\s*:\s*"(?<value>(?:\\.|[^"\\])*)"'
    foreach ($match in [Regex]::Matches($JsonText, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        $rawValue = [string]$match.Groups['value'].Value
        if ($rawValue.Length -ge 4) { $Values.Add($rawValue) }
        try {
            $decodedValue = ('"' + $rawValue + '"') | ConvertFrom-Json -ErrorAction Stop
            if ($decodedValue -is [string] -and $decodedValue.Length -ge 4) { $Values.Add($decodedValue) }
        }
        catch { }
    }
}

function Get-GiteaLifecycleRootException {
    param([Parameter(Mandatory = $true)][System.Exception]$Exception)

    $root = $Exception
    while ($root.InnerException) { $root = $root.InnerException }
    return $root
}

function Protect-GiteaLifecycleDiagnosticMessage {
    param(
        [AllowEmptyString()][string]$Message,
        [string[]]$SensitiveValues = @()
    )

    $sanitized = [string]$Message
    foreach ($sensitiveValue in @($SensitiveValues | Where-Object { $_ } | Sort-Object -Unique | Sort-Object Length -Descending)) {
        $sanitized = [Regex]::Replace(
            $sanitized,
            [Regex]::Escape([string]$sensitiveValue),
            '[REDACTED]',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
    }
    $sanitized = [Regex]::Replace(
        $sanitized,
        '(?im)(\b[A-Z0-9_.-]*(?:password|passwd|token|secret|credential|authorization|private[_-]?key|access[_-]?key)[A-Z0-9_.-]*\s*[=:]\s*)(?:"[^"]*"|''[^'']*''|[^\s,;]+)',
        '$1[REDACTED]'
    )
    $sanitized = [Regex]::Replace($sanitized, '(?i)\b(Basic\s+|Bearer\s+)[A-Za-z0-9._~+/-]+=*', '$1[REDACTED]')
    $sanitized = [Regex]::Replace($sanitized, '(?i)(https?://[^:/\s@]+:)[^@\s]+(@)', '$1[REDACTED]$2').Trim()
    if (-not $sanitized) { return '(no safe exception message available)' }
    if ($sanitized.Length -gt 1000) { return $sanitized.Substring(0, 1000) + ' [message truncated]' }
    return $sanitized
}

function New-GiteaBootstrapImagePinFailure {
    param(
        [Parameter(Mandatory = $true)][System.Management.Automation.ErrorRecord]$ErrorRecord,
        [Parameter(Mandatory = $true)][string]$Stage,
        [System.Collections.Generic.List[string]]$SensitiveValues
    )

    $rootException = Get-GiteaLifecycleRootException -Exception $ErrorRecord.Exception
    $cause = Protect-GiteaLifecycleDiagnosticMessage -Message $rootException.Message -SensitiveValues @($SensitiveValues)
    return [System.InvalidOperationException]::new(
        "Bootstrap image pin update failed during stage '$Stage'. Exception type '$($rootException.GetType().FullName)'. Masked cause: $cause"
    )
}

function Set-GiteaBootstrapImagePin {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$ImageReference
    )

    $sensitiveValues = [System.Collections.Generic.List[string]]::new()
    Add-GiteaLifecycleDiagnosticValues -Value $Context -PropertyName 'context' -Values $sensitiveValues
    $temporaryPath = $null
    $configurationText = $null
    $failure = $null
    $stage = 'read the existing bootstrap config'
    try {
        $configurationText = Read-LongPathText -Path $Context.ConfigPath
        Add-GiteaLifecycleRawJsonDiagnosticValues -JsonText $configurationText -Values $sensitiveValues
        $stage = 'parse the existing bootstrap config'
        $config = $configurationText | ConvertFrom-Json -ErrorAction Stop
        Add-GiteaLifecycleDiagnosticValues -Value $config -PropertyName 'config' -Values $sensitiveValues -MaskAllStrings $true
        $stage = 'update the Gitea image setting'
        $config.gitea.image = $ImageReference
        $temporaryPath = Join-Path (Get-LongPathParent -Path $Context.ConfigPath) (".gitea-config-{0}.tmp" -f [Guid]::NewGuid().ToString("N"))
        $stage = 'write the temporary bootstrap config'
        Save-BackupJson -Path $temporaryPath -Value $config
        $stage = 'atomically replace the existing bootstrap config'
        Move-LongPathFile -Source $temporaryPath -Destination $Context.ConfigPath -Force
    }
    catch {
        $failure = New-GiteaBootstrapImagePinFailure -ErrorRecord $_ -Stage $stage -SensitiveValues $sensitiveValues
    }
    finally {
        if ($temporaryPath -and (
            (Test-LongPath -Path $temporaryPath -PathType Leaf) -or
            (Test-LongPathDirectoryEntry -Directory (Get-LongPathParent -Path $temporaryPath) -Name (Get-LongPathLeaf -Path $temporaryPath))
        )) {
            try {
                Remove-LongPathEntry -Path $temporaryPath
            }
            catch {
                $cleanupFailure = New-GiteaBootstrapImagePinFailure -ErrorRecord $_ -Stage 'clean the temporary bootstrap config' -SensitiveValues $sensitiveValues
                if ($failure) {
                    $failure = [System.InvalidOperationException]::new(
                        "$($failure.Message) Temporary-file cleanup also failed. $($cleanupFailure.Message)"
                    )
                }
                else {
                    $failure = $cleanupFailure
                }
            }
        }
    }
    if ($failure) { throw $failure }
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

function Invoke-GiteaUpgradeAttempt {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$GiteaVersion,
        [hashtable]$OperationState
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

    $gitea = Assert-GiteaContainerIdentity -Context $Context
    Assert-GiteaLocalStorageOnly -ConfigFilePath (Join-Path $Context.GiteaConfigDir "app.ini") -Environment @($gitea.Config.Env) -Container $gitea
    $null = Ensure-BackupRoot -Context $Context
    Assert-GiteaConfigCanBePinned -Context $Context
    $postgres = Assert-PostgresContainerIdentity -Context $Context
    Assert-GiteaDatabaseTarget -GiteaContainer $gitea -PostgresContainer $postgres -Context $Context
    $runner = Get-GiteaRunnerInfo -Context $Context
    $runnerWasRunning = [string]$runner.State.Status -eq "running"
    $sourceVersion = Get-GiteaReportedVersion -Container $gitea
    $sourceRuntime = Get-RuntimeSnapshot -Context $Context -Container $gitea -SourceVersion $sourceVersion
    Assert-SupportedGiteaVersionStep -CurrentVersion $sourceVersion -TargetVersion $GiteaVersion
    Assert-NoActiveGiteaActions -Context $Context
    $capacity = Assert-BackupCapacity -Context $Context

    $targetTag = "docker.gitea.com/gitea:$GiteaVersion-rootless"
    Confirm-GiteaLifecycleOperation -Prompt "Type UPGRADE $GiteaVersion ON agent-sdlc-gitea:43000 to continue" -ExpectedText "UPGRADE $GiteaVersion ON agent-sdlc-gitea:43000"
    [void](Invoke-GiteaDocker -Arguments @("pull", $targetTag))
    $targetImage = Get-ImageDigestReference -Image $targetTag -RequireRegistryDigest
    $capacity = Assert-BackupCapacity -Context $Context

    $operationId = [Guid]::NewGuid().ToString("N")
    $backupId = New-GiteaBackupId
    Set-GiteaLifecycleRecoveryMarker -Context $Context -OperationKind upgrade -BackupId $backupId -OperationId $operationId -Phase "upgrade-prepared" -NextAction "stop-runner" -LastCompletedStage "preflight" -GiteaContainerId (Get-GiteaContainerId -Container $gitea) -PostgresContainerId (Get-GiteaContainerId -Container $postgres) -RunnerContainerId (Get-GiteaContainerId -Container $runner) -SourceImageId ([string]$sourceRuntime.imageId) -SourceImageReference ([string]$sourceRuntime.imageReference) -SourceOriginalImageReference ([string]$sourceRuntime.originalImageReference) -SourceVersion $sourceVersion -TargetImageDigest $targetImage -TargetVersion $GiteaVersion -GiteaState ([string]$gitea.State.Status) -PostgresState ([string]$postgres.State.Status) -RunnerState ([string]$runner.State.Status)
    if ($OperationState) {
        $OperationState.RecoveryMarkerCreated = $true
        $OperationState.OperationId = $operationId
    }

    # Close the window for new work before stopping Gitea. Any queued or active run blocks the snapshot.
    Assert-NoActiveGiteaActions -Context $Context
    try {
        Stop-GiteaRunner -Name $Context.GiteaRunnerContainerName
        Update-GiteaLifecycleRecoveryMarkerPhase -Context $Context -BackupId $backupId -OperationId $operationId -Phase "upgrade-prepared" -NextAction "stop-gitea" -LastCompletedStage "runner-quiesced"
        Assert-NoActiveGiteaActions -Context $Context
        [void](Invoke-GiteaDocker -Arguments @("stop", "--time", "60", $Context.GiteaContainerName))
        Update-GiteaLifecycleRecoveryMarkerPhase -Context $Context -BackupId $backupId -OperationId $operationId -Phase "backup-in-progress" -NextAction "create-upgrade-backup" -LastCompletedStage "services-stopped"
    }
    catch {
        throw "The upgrade stopped before target migration. Recovery Marker '$operationId' remains; inspect Gitea/Runner IDs and states, then use the permitted original-source closeout only after an authorized operator restores the captured state. $($_.Exception.Message)"
    }

    try {
        $backup = New-GiteaBackupSet -Context $Context -Kind upgrade -GiteaContainer $gitea -PostgresContainer $postgres -SourceVersion $sourceVersion -RunnerWasRunning $runnerWasRunning -Capacity $capacity -RuntimeSnapshot $sourceRuntime -BackupId $backupId -OperationId $operationId
    }
    catch {
        throw "Upgrade backup creation failed. Recovery Marker, Backup ID '$backupId', and any partial snapshot are retained; no target image was started. Restore the captured source state only through an authorized operator and keep the marker until exact source reconciliation. $($_.Exception.Message)"
    }
    Update-GiteaLifecycleRecoveryMarkerPhase -Context $Context -BackupId $backup.BackupId -OperationId $operationId -Phase "backup-verified" -NextAction "rename-source-container" -LastCompletedStage "backup-verified"

    $oldContainerName = "$($Context.GiteaContainerName)-preupgrade-$($backup.BackupId)"
    [void](Invoke-GiteaDocker -Arguments @("rename", $Context.GiteaContainerName, $oldContainerName))
    Update-GiteaLifecycleRecoveryMarkerPhase -Context $Context -BackupId $backup.BackupId -OperationId $operationId -Phase "target-start-attempted" -NextAction "create-and-start-target" -LastCompletedStage "source-container-renamed"
    try {
        $runtime = Get-BackupRuntime -BackupPath $backup.Path -Manifest $backup.Manifest
        New-GiteaContainerFromRuntime -Context $Context -Runtime $runtime -ImageReference $targetImage
        Wait-GiteaHealthy -Context $Context
        Assert-GiteaApiVersion -Context $Context -ExpectedVersion $GiteaVersion
    }
    catch {
        throw "Gitea upgrade did not pass its startup/version health checks. Backup '$($backup.BackupId)' and the stopped source container '$oldContainerName' are retained; no automatic rollback was attempted. $($_.Exception.Message)"
    }
    $targetContainer = Assert-GiteaContainerIdentity -Context $Context
    Update-GiteaLifecycleRecoveryMarkerPhase -Context $Context -BackupId $backup.BackupId -OperationId $operationId -Phase "close-pending" -NextAction "pin-target-image" -LastCompletedStage "target-health-verified" -TargetContainerId (Get-GiteaContainerId -Container $targetContainer)

    try {
        # Keep the bootstrap image unchanged until the migrated service proves healthy.
        Set-GiteaBootstrapImagePin -Context $Context -ImageReference $targetImage
    }
    catch {
        $pinFailureDiagnostic = [string]$_.Exception.Message
        throw "Gitea passed startup/version health checks, but the bootstrap image pin could not be updated. $pinFailureDiagnostic Recovery marker and backup '$($backup.BackupId)' are retained; the Runner remains stopped."
    }
    Update-GiteaLifecycleRecoveryMarkerPhase -Context $Context -BackupId $backup.BackupId -OperationId $operationId -Phase "close-pending" -NextAction "resume-runner" -LastCompletedStage "target-image-pinned"
    if ($runnerWasRunning) {
        try {
            Start-GiteaRunner -Name $Context.GiteaRunnerContainerName
        }
        catch {
            throw "Gitea passed startup/version health checks, but the original Runner could not be resumed. Recovery marker and backup '$($backup.BackupId)' are retained."
        }
    }
    Update-GiteaLifecycleRecoveryMarkerPhase -Context $Context -BackupId $backup.BackupId -OperationId $operationId -Phase "close-pending" -NextAction "write-operation-record" -LastCompletedStage "runner-restored"

    $record = @{
        schemaVersion = 2
        operationId = $operationId
        operationKind = "upgrade"
        startedAt = [string](Get-GiteaLifecycleRecoveryMarker -Context $Context).createdAt
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
    Clear-GiteaLifecycleRecoveryMarker -Context $Context -OperationId $operationId
    Write-Host "Gitea '$sourceVersion' was upgraded to '$GiteaVersion' and passed HTTP/API health checks."
    Write-Host "Backup ID: $($backup.BackupId)"
    Write-Host "The old Gitea container is retained as '$oldContainerName'; PostgreSQL and the shared Runner were not recreated."
    Write-Host "Complete TC-011's Git, Registry, Actions, Runner, and Run Attempt smoke checks before treating the live upgrade as accepted."
}

function Invoke-GiteaUpgrade {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$GiteaVersion
    )
    $operationState = @{
        RecoveryMarkerCreated = $false
        OperationId = $null
    }
    try {
        Invoke-GiteaUpgradeAttempt -Context $Context -GiteaVersion $GiteaVersion -OperationState $operationState
    }
    catch {
        $failure = $_
        if (-not $operationState.RecoveryMarkerCreated) {
            throw $failure
        }
        try {
            $marker = Get-GiteaLifecycleRecoveryMarker -Context $Context
            if (-not $marker -or [string]$marker.operationKind -cne "upgrade" -or
                [string]$marker.operationId -cne [string]$operationState.OperationId) {
                throw "The persisted Recovery Marker does not match this Upgrade attempt; no terminal Operation Record was written."
            }
            Write-GiteaInterruptedOperationRecord -Context $Context -Marker $marker -ErrorMessage $failure.Exception.Message
        }
        catch {
            throw "Upgrade failed after its Recovery Marker was created and its immutable terminal record could not be verified or written. The Recovery Marker and retained state remain; inspect them before any retry. Original error: $($failure.Exception.Message) Record error: $($_.Exception.Message)"
        }
        throw $failure
    }
}

function Invoke-GiteaRestore {
    param(
        [hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$BackupId
    )

    Assert-NativeWindowsHost
    $Context.DockerHost = Assert-DockerDesktopReady
    $previousMarker = Get-GiteaLifecycleRecoveryMarker -Context $Context
    $supersedesOperationId = $null
    $priorDiagnosticBackupIds = @()
    $previousAttemptNeedsTerminalRecord = $false
    if ($previousMarker) {
        if ([string]$previousMarker.operationKind -notin @("upgrade", "restore") -or
            [string]$previousMarker.backupId -cne $BackupId -or
            [int]$previousMarker.schemaVersion -ne 3 -or
            [string]$previousMarker.operationId -notmatch '^[0-9a-f]{32}$') {
            throw "Restore retry requires the same Backup ID and a schema-3 attempt. The existing Recovery Marker remains unchanged."
        }
        $previousRecordPath = Get-GiteaOperationRecordPath -Context $Context -OperationId ([string]$previousMarker.operationId)
        if (Test-LongPath -Path $previousRecordPath) {
            if (-not (Test-GiteaTerminalOperationRecord -Context $Context -OperationId ([string]$previousMarker.operationId) -AllowedResultPrefix @("interrupted-"))) {
                throw "The prior lifecycle attempt already has a different terminal record or an unreadable record; Restore will not supersede it."
            }
        }
        else {
            $previousAttemptNeedsTerminalRecord = $true
        }
        $supersedesOperationId = [string]$previousMarker.operationId
        $priorDiagnosticBackupIds = @($previousMarker.priorDiagnosticBackupIds)
        if ($previousMarker.diagnosticBackupId) { $priorDiagnosticBackupIds += [string]$previousMarker.diagnosticBackupId }
        $priorDiagnosticBackupIds = @($priorDiagnosticBackupIds | Where-Object { $_ } | Select-Object -Unique)
    }

    $selected = Get-GiteaBackupById -Context $Context -BackupId $BackupId
    $runtime = Get-BackupRuntime -BackupPath $selected.Path -Manifest $selected.Manifest
    Assert-BackupRuntimeMatchesContext -Context $Context -Runtime $runtime
    $restoreContext = Read-GiteaRestoreContext -BackupPath $selected.Path -Manifest $selected.Manifest
    Assert-ConfigRestoreCompatibility -Context $Context -RestoreContext $restoreContext
    Assert-GiteaLocalStorageOnly -ConfigFilePath (Join-Path $selected.Path "payload\gitea-config\app.ini") -Environment @($runtime.environment)
    if ([string]$restoreContext.databaseName -ne [string]$Context.GiteaPostgresDbName -or
        [string]$restoreContext.databaseUser -ne [string]$Context.GiteaPostgresUser) {
        throw "The selected backup's PostgreSQL database name or user differs from the configured existing service; restore is blocked."
    }
    $postgresTopology = Get-GiteaPostgresTopology -BackupPath $selected.Path -Manifest $selected.Manifest
    $gitea = Assert-GiteaContainerIdentity -Context $Context -AllowStopped -AllowMissing
    if ($gitea) {
        Assert-GiteaLocalStorageOnly -ConfigFilePath (Join-Path $Context.GiteaConfigDir "app.ini") -Environment @($gitea.Config.Env) -Container $gitea
    }
    elseif (Test-LongPath -Path (Join-Path $Context.GiteaConfigDir "app.ini") -PathType Leaf) {
        Assert-GiteaLocalStorageOnly -ConfigFilePath (Join-Path $Context.GiteaConfigDir "app.ini") -Environment @()
    }
    if ([string]$restoreContext.configSource -eq "local") {
        Assert-GiteaConfigCanBePinned -Context $Context
    }

    $postgres = Assert-PostgresContainerIdentity -Context $Context
    Assert-PostgresRestoreCompatibility -BackupTopology $postgresTopology -CurrentContainer $postgres -Context $Context -ManifestSchemaVersion ([int]$selected.Manifest.schemaVersion)
    $capturedGitea = [pscustomobject]@{ Config = [pscustomobject]@{ Env = @($runtime.environment) } }
    Assert-GiteaDatabaseTarget -GiteaContainer $capturedGitea -PostgresContainer $postgres -Context $Context
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
    Assert-GiteaImmutableImageReference -Reference $targetImage
    if ($targetImage -match '^docker\.gitea\.com/gitea@sha256:') {
        [void](Invoke-GiteaDocker -Arguments @("pull", $targetImage))
    }
    else {
        [void](Invoke-GiteaDocker -Arguments @("image", "inspect", $targetImage))
    }
    $capacity = Assert-BackupCapacity -Context $Context
    Confirm-GiteaLifecycleOperation -Prompt "Type RESTORE $BackupId TO agent-sdlc-gitea:43000 to overwrite the current instance" -ExpectedText "RESTORE $BackupId TO agent-sdlc-gitea:43000"

    $diagnosticVersion = "unavailable"
    $diagnosticRuntime = $null
    if ($gitea) {
        if ($apiHealth.IsHealthy -and $apiHealth.Version) {
            $diagnosticVersion = [string]$apiHealth.Version
        }
        else {
            try { $diagnosticVersion = Get-GiteaReportedVersion -Container $gitea }
            catch { $diagnosticVersion = "unavailable" }
        }
        $diagnosticRuntime = Get-RuntimeSnapshot -Context $Context -Container $gitea -SourceVersion $diagnosticVersion
    }

    $operationId = [Guid]::NewGuid().ToString("N")
    $restoreStartedAt = [DateTime]::UtcNow.ToString("o")
    $sourceImageId = if ($gitea) { [string]$gitea.Image } else { "" }
    $sourceImageReference = if ($gitea) { [string]$gitea.Config.Image } else { "" }
    if ($previousAttemptNeedsTerminalRecord) {
        Write-GiteaInterruptedOperationRecord -Context $Context -Marker $previousMarker -ErrorMessage "The operator confirmed a same-Backup-ID Restore retry after the prior attempt ended without a terminal record."
    }
    Set-GiteaLifecycleRecoveryMarker -Context $Context -OperationKind restore -BackupId $BackupId -OperationId $operationId -Phase "restore-prepared" -NextAction "stop-runner" -LastCompletedStage "preflight" -GiteaContainerId (Get-GiteaContainerId -Container $gitea) -PostgresContainerId (Get-GiteaContainerId -Container $postgres) -RunnerContainerId (Get-GiteaContainerId -Container $runner) -SourceImageId $sourceImageId -SourceImageReference $sourceImageReference -SourceOriginalImageReference $sourceImageReference -SourceVersion $diagnosticVersion -TargetImageDigest $targetImage -TargetVersion ([string]$runtime.sourceVersion) -GiteaState $(if ($gitea) { [string]$gitea.State.Status } else { "missing" }) -PostgresState ([string]$postgres.State.Status) -RunnerState ([string]$runner.State.Status) -SupersedesOperationId $supersedesOperationId -PriorDiagnosticBackupIds $priorDiagnosticBackupIds -ReplaceExisting:([bool]$previousMarker)

    $diagnostic = $null
    try {
        if ($runnerWasRunningNow) {
            Update-GiteaLifecycleRecoveryMarkerPhase -Context $Context -BackupId $BackupId -OperationId $operationId -Phase "restore-prepared" -NextAction "stop-runner" -LastCompletedStage "preflight"
            Stop-GiteaRunner -Name $Context.GiteaRunnerContainerName
            Update-GiteaLifecycleRecoveryMarkerPhase -Context $Context -BackupId $BackupId -OperationId $operationId -Phase "restore-prepared" -NextAction "stop-gitea" -LastCompletedStage "runner-stopped"
            if ($apiHealth.IsHealthy) { Assert-NoActiveGiteaActions -Context $Context }
        }
        if ($gitea -and [string]$gitea.State.Status -eq "running") {
            Update-GiteaLifecycleRecoveryMarkerPhase -Context $Context -BackupId $BackupId -OperationId $operationId -Phase "restore-prepared" -NextAction "stop-gitea" -LastCompletedStage $(if ($runnerWasRunningNow) { "runner-stopped" } else { "preflight" })
            [void](Invoke-GiteaDocker -Arguments @("stop", "--time", "60", $Context.GiteaContainerName))
        }
        $diagnosticBackupId = New-GiteaBackupId
        Update-GiteaLifecycleRecoveryMarkerPhase -Context $Context -BackupId $BackupId -OperationId $operationId -Phase "restore-prepared" -NextAction "create-diagnostic-backup" -LastCompletedStage "services-stopped" -DiagnosticBackupId $diagnosticBackupId

        $diagnostic = New-GiteaBackupSet -Context $Context -Kind pre-restore-diagnostic -GiteaContainer $gitea -PostgresContainer $postgres -SourceVersion $diagnosticVersion -RunnerWasRunning $runnerWasRunningNow -Capacity $capacity -RuntimeSnapshot $diagnosticRuntime -BackupId $diagnosticBackupId -OperationId $operationId
        Update-GiteaLifecycleRecoveryMarkerPhase -Context $Context -BackupId $BackupId -OperationId $operationId -Phase "restore-prepared" -NextAction "rename-current-container" -LastCompletedStage "diagnostic-backup-verified" -DiagnosticBackupId $diagnostic.BackupId

        if ($gitea) {
            $failedContainerName = "$($Context.GiteaContainerName)-failed-$($diagnostic.BackupId)"
            [void](Invoke-GiteaDocker -Arguments @("rename", $Context.GiteaContainerName, $failedContainerName))
        }

        Update-GiteaLifecycleRecoveryMarkerPhase -Context $Context -BackupId $BackupId -OperationId $operationId -Phase "restore-applying" -NextAction "restore-postgres" -LastCompletedStage "current-container-retained"
        $dumpPath = Join-Path $selected.Path "payload\postgres.dump"
        Invoke-GiteaPostgresRestore -Context $Context -DumpPath $dumpPath
        Update-GiteaLifecycleRecoveryMarkerPhase -Context $Context -BackupId $BackupId -OperationId $operationId -Phase "restore-applying" -NextAction "replace-gitea-data" -LastCompletedStage "postgres-restored"

        Replace-GiteaDataTree -BackupSource (Join-Path $selected.Path "payload\gitea-data") -LiveDestination $Context.GiteaDataDir
        Update-GiteaLifecycleRecoveryMarkerPhase -Context $Context -BackupId $BackupId -OperationId $operationId -Phase "restore-applying" -NextAction "replace-gitea-config" -LastCompletedStage "gitea-data-restored"
        Replace-GiteaDataTree -BackupSource (Join-Path $selected.Path "payload\gitea-config") -LiveDestination $Context.GiteaConfigDir
        Update-GiteaLifecycleRecoveryMarkerPhase -Context $Context -BackupId $BackupId -OperationId $operationId -Phase "restore-applying" -NextAction "restore-operator-state" -LastCompletedStage "gitea-config-restored"
        Restore-GiteaOperatorState -Context $Context -BackupPath $selected.Path -RestoreContext $restoreContext
        if ([string]$restoreContext.configSource -eq "local") {
            Update-GiteaLifecycleRecoveryMarkerPhase -Context $Context -BackupId $BackupId -OperationId $operationId -Phase "restore-applying" -NextAction "pin-restored-image" -LastCompletedStage "operator-state-restored"
            Set-GiteaBootstrapImagePin -Context $Context -ImageReference $targetImage
        }

        Update-GiteaLifecycleRecoveryMarkerPhase -Context $Context -BackupId $BackupId -OperationId $operationId -Phase "restore-applying" -NextAction "create-restored-container" -LastCompletedStage "operator-state-restored"
        New-GiteaContainerFromRuntime -Context $Context -Runtime $runtime -ImageReference $targetImage
        Wait-GiteaHealthy -Context $Context
        Assert-GiteaApiVersion -Context $Context -ExpectedVersion ([string]$runtime.sourceVersion)
        $restoredContainer = Assert-GiteaContainerIdentity -Context $Context
        Update-GiteaLifecycleRecoveryMarkerPhase -Context $Context -BackupId $BackupId -OperationId $operationId -Phase "close-pending" -NextAction "restore-runner-state" -LastCompletedStage "restored-gitea-healthy" -TargetContainerId (Get-GiteaContainerId -Container $restoredContainer)

        if ([bool]$selected.Manifest.runnerWasRunning) {
            Start-GiteaRunner -Name $Context.GiteaRunnerContainerName
        }
        $runnerAfterRestore = Get-GiteaRunnerInfo -Context $Context
        if ((Get-GiteaContainerId -Container $runnerAfterRestore) -cne (Get-GiteaContainerId -Container $runner)) {
            throw "The shared Runner container identity changed during Restore; Recovery Marker remains."
        }
        Update-GiteaLifecycleRecoveryMarkerPhase -Context $Context -BackupId $BackupId -OperationId $operationId -Phase "close-pending" -NextAction "write-operation-record" -LastCompletedStage "runner-state-restored" -RunnerState ([string]$runnerAfterRestore.State.Status)

        New-GiteaOperationRecord -Context $Context -Record @{
            schemaVersion = 2
            operationId = $operationId
            operationKind = "restore"
            startedAt = $restoreStartedAt
            result = "restored-manual-smoke-required"
            completedAt = [DateTime]::UtcNow.ToString("o")
            backupId = $BackupId
            diagnosticBackupId = $diagnostic.BackupId
            priorDiagnosticBackupIds = @($priorDiagnosticBackupIds)
            supersedesOperationId = $supersedesOperationId
            restoredVersion = [string]$runtime.sourceVersion
            restoredImageDigest = $targetImage
            targetContainerId = Get-GiteaContainerId -Container $restoredContainer
            postgresContainerId = Get-GiteaContainerId -Container $postgres
            runnerContainerId = Get-GiteaContainerId -Container $runnerAfterRestore
            activeContainerName = $Context.GiteaContainerName
            endpoint = $Context.GiteaRootUrl
            dockerHost = $Context.DockerHost
            automaticHealthChecks = @("HTTP endpoint", "Gitea version API", "PostgreSQL identity", "shared Runner identity")
            manualSmokeStillRequired = @("Git read/write", "Registry push/pull", "Actions dispatch and Run API", "Runner canary", "Run Attempt visibility", "representative integrations")
        } | Out-Null
        Clear-GiteaLifecycleRecoveryMarker -Context $Context -OperationId $operationId
    }
    catch {
        $failure = $_
        try {
            $currentMarker = Get-GiteaLifecycleRecoveryMarker -Context $Context
            if ($currentMarker -and [string]$currentMarker.operationId -ceq $operationId) {
                Write-GiteaInterruptedOperationRecord -Context $Context -Marker $currentMarker -ErrorMessage $failure.Exception.Message
            }
        }
        catch {
            throw "Restore attempt failed and its immutable terminal record could not be verified or written. Recovery Marker '$operationId' remains; do not retry with another Backup ID. Original error: $($failure.Exception.Message) Record error: $($_.Exception.Message)"
        }
        throw $failure
    }

    Write-Host "Restored Gitea from Backup ID '$BackupId' and passed HTTP/API health checks."
    Write-Host "Diagnostic backup ID: $($diagnostic.BackupId); the overwritten state is retained."
    Write-Host "PostgreSQL and the shared Runner identities/storage were preserved. Complete TC-011's remaining isolated acceptance checks."
}

function Invoke-GiteaLifecycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet("upgrade", "backup-list", "restore", "reconcile-recovery", "status")][string]$Action,
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [string]$GiteaVersion,
        [string]$BackupId,
        [ValidateSet("original-source", "healthy-target", "restore-complete")][string]$RecoveryMode = "original-source",
        [string]$ExpectedGiteaContainerId,
        [string]$ExpectedPostgresContainerId,
        [string]$ExpectedRunnerContainerId
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
        "status" {
            $status = Get-GiteaLifecycleStatus -Context $Context
            if ($status.Marker) {
                Write-Host ("Gitea lifecycle recovery: pending kind={0} phase={1} backup={2} operation={3}" -f $status.Marker.operationKind, $status.Marker.phase, $status.Marker.backupId, $status.Marker.operationId)
                if ($status.Marker.PSObject.Properties["nextAction"]) { Write-Host ("Next action: {0}" -f $status.Marker.nextAction) }
            }
            else { Write-Host "Gitea lifecycle recovery: none" }
            if ($status.LatestOperationRecord) {
                Write-Host ("Latest Gitea lifecycle operation: id={0} result={1}" -f $status.LatestOperationRecord.operationId, $status.LatestOperationRecord.result)
            }
            else { Write-Host "Latest Gitea lifecycle operation: none" }
            return $status
        }
        "restore" {
            if (-not $BackupId) { throw "The restore command requires -BackupId <id>." }
            Invoke-GiteaRestore -Context $Context -BackupId $BackupId
        }
        "reconcile-recovery" {
            if (-not $BackupId -or -not $ExpectedGiteaContainerId -or -not $ExpectedPostgresContainerId -or -not $ExpectedRunnerContainerId) {
                throw "Recovery reconciliation requires -BackupId and the verified full Gitea, PostgreSQL, and Runner container IDs."
            }
            Invoke-GiteaRecoveryReconciliation -Context $Context -BackupId $BackupId -Mode $RecoveryMode -ExpectedGiteaContainerId $ExpectedGiteaContainerId -ExpectedPostgresContainerId $ExpectedPostgresContainerId -ExpectedRunnerContainerId $ExpectedRunnerContainerId
        }
    }
}

Export-ModuleMember -Function Invoke-GiteaLifecycle, Get-GiteaLifecycleStatus
