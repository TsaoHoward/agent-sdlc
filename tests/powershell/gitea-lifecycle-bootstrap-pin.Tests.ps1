BeforeDiscovery {
    $modulePath = Join-Path $PSScriptRoot "../../scripts/dev/gitea-lifecycle.psm1"
    Import-Module (Resolve-Path $modulePath) -Force
}

Describe "Gitea bootstrap image pin on real NTFS" -Tag "WindowsBootstrapPin" {
    BeforeEach {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            Set-ItResult -Skipped -Because "The bootstrap image pin integration check requires Windows NTFS."
            return
        }

        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
        $administratorsSid = [System.Security.Principal.SecurityIdentifier]::new("S-1-5-32-544")
        if ($principal.IsInRole($administratorsSid)) {
            Set-ItResult -Skipped -Because "Run this bootstrap image pin check from non-elevated Windows PowerShell."
            return
        }

        $script:pinRunId = [Guid]::NewGuid().ToString("N")
        $script:pinFixtureRoot = Join-Path ([System.IO.Path]::GetTempPath().TrimEnd('\', '/')) "agent-sdlc-gitea-pin-$script:pinRunId"
        $script:pinFixtureMarker = Join-Path $script:pinFixtureRoot ".agent-sdlc-gitea-pin-owner"
        $script:pinFixtureMarkerValue = "agent-sdlc-gitea-bootstrap-pin-test:$script:pinRunId"
        $script:pinConfigDirectory = $script:pinFixtureRoot
        [System.IO.Directory]::CreateDirectory($script:pinFixtureRoot) | Out-Null
        [System.IO.File]::WriteAllText($script:pinFixtureMarker, $script:pinFixtureMarkerValue, [System.Text.UTF8Encoding]::new($false))

        foreach ($index in 1..3) {
            $segment = "segment-{0}-{1}" -f $index, ("x" * 80)
            $script:pinConfigDirectory = Join-Path $script:pinConfigDirectory $segment
            [System.IO.Directory]::CreateDirectory("\\?\$script:pinConfigDirectory") | Out-Null
        }

        $script:pinConfigPath = Join-Path $script:pinConfigDirectory "gitea-bootstrap.json"
        $script:pinConfigExtendedPath = "\\?\$script:pinConfigPath"
        $script:pinExpectedImage = "docker.gitea.com/gitea@sha256:$('a' * 64)"
        $script:pinInitialConfig = [ordered]@{
            gitea = [ordered]@{
                image = "docker.gitea.com/gitea:1.25.5-rootless"
                rootUrl = "http://127.0.0.1:43000/"
                adminUsername = "fixture-admin"
                adminPassword = "fixture-admin-password-do-not-log"
                apiToken = "fixture-api-token-do-not-log"
            }
            postgres = [ordered]@{
                host = "agent-sdlc-gitea-db"
                database = "gitea"
                port = 5432
                sslMode = "disable"
            }
            ports = [ordered]@{ http = 43000 }
            unrelatedSettings = [ordered]@{
                backupRoot = "C:\Users\fixture\Backups\agent-sdlc\gitea"
                featureFlags = @("actions", "packages")
            }
        }
        $script:pinInitialJson = ConvertTo-Json -InputObject $script:pinInitialConfig -Depth 20
        [System.IO.File]::WriteAllText($script:pinConfigExtendedPath, $script:pinInitialJson, [System.Text.UTF8Encoding]::new($false))
        $script:pinContext = @{ ConfigPath = $script:pinConfigPath }

        $drive = [System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($script:pinFixtureRoot))
        $drive.DriveFormat | Should -Be "NTFS"
        $script:pinConfigPath.Length | Should -BeGreaterThan 260
    }

    AfterEach {
        if (-not $script:pinFixtureRoot -or -not [System.IO.Directory]::Exists($script:pinFixtureRoot)) { return }

        $tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')
        $resolvedRoot = [System.IO.Path]::GetFullPath($script:pinFixtureRoot).TrimEnd('\', '/')
        [System.IO.Path]::GetDirectoryName($resolvedRoot).Equals($tempParent, [StringComparison]::OrdinalIgnoreCase) | Should -BeTrue
        [System.IO.Path]::GetFileName($resolvedRoot) | Should -Be "agent-sdlc-gitea-pin-$script:pinRunId"

        [System.IO.File]::Exists($script:pinFixtureMarker) | Should -BeTrue
        [System.IO.File]::ReadAllText($script:pinFixtureMarker) | Should -Be $script:pinFixtureMarkerValue
        $expectedOwner = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $security = [System.IO.Directory]::GetAccessControl("\\?\$resolvedRoot")
        $security.GetOwner([System.Security.Principal.SecurityIdentifier]).Value | Should -Be $expectedOwner

        $treeEntries = InModuleScope gitea-lifecycle -Parameters @{ Root = $resolvedRoot } {
            param($Root)
            Get-LongPathTreeEntries -Path $Root
        }
        foreach ($entry in @($treeEntries)) {
            (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) | Should -BeTrue
        }

        [System.IO.Directory]::Delete("\\?\$resolvedRoot", $true)
        [System.IO.Directory]::Exists($resolvedRoot) | Should -BeFalse
    }

    It "replaces the existing config atomically with the digest and preserves all other settings" {
        $script:pinExpectedImage | Should -Match '^docker\.gitea\.com/gitea@sha256:[0-9a-f]{64}$'

        InModuleScope gitea-lifecycle -Parameters @{ Context = $script:pinContext; ImageReference = $script:pinExpectedImage } {
            param($Context, $ImageReference)
            Set-GiteaBootstrapImagePin -Context $Context -ImageReference $ImageReference
        }

        $actualText = [System.IO.File]::ReadAllText($script:pinConfigExtendedPath)
        $actualConfig = $actualText | ConvertFrom-Json
        $expectedConfig = $script:pinInitialJson | ConvertFrom-Json
        $expectedConfig.gitea.image = $script:pinExpectedImage
        $actualConfig.gitea.image | Should -Be $script:pinExpectedImage
        (ConvertTo-Json -InputObject $actualConfig -Depth 20 -Compress) |
            Should -Be (ConvertTo-Json -InputObject $expectedConfig -Depth 20 -Compress)

        $entries = @(InModuleScope gitea-lifecycle -Parameters @{ Directory = $script:pinConfigDirectory } {
            param($Directory)
            Get-LongPathDirectoryEntries -Path $Directory
        })
        $entries.Count | Should -Be 1
        $entries[0].Name | Should -Be "gitea-bootstrap.json"
    }

    It "supersedes a terminal interrupted attempt for the same Backup ID without leaving replacement files" {
        $context = @{ RepoRoot = $script:pinFixtureRoot }
        InModuleScope gitea-lifecycle -Parameters @{ Context = $context } {
            param($Context)
            $backupId = "20261105T000000Z-0123456789abcdef0123456789abcdef"
            $firstOperationId = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            $secondOperationId = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
            Set-GiteaLifecycleRecoveryMarker -Context $Context -OperationKind upgrade -BackupId $backupId -OperationId $firstOperationId -Phase "target-start-attempted" -NextAction "verify-source-or-restore"
            New-GiteaOperationRecord -Context $Context -Record @{
                schemaVersion = 2
                operationId = $firstOperationId
                operationKind = "upgrade"
                result = "interrupted-target-start-attempted"
                completedAt = [DateTime]::UtcNow.ToString("o")
                backupId = $backupId
            } | Out-Null
            Set-GiteaLifecycleRecoveryMarker -Context $Context -OperationKind restore -BackupId $backupId -OperationId $secondOperationId -SupersedesOperationId $firstOperationId -Phase "restore-prepared" -NextAction "stop-runner" -ReplaceExisting
        }

        $markerDirectory = Join-Path $script:pinFixtureRoot ".agent-sdlc\dev-env\gitea"
        $markerPath = Join-Path $markerDirectory "lifecycle-recovery.json"
        $marker = [System.IO.File]::ReadAllText("\\?\$markerPath") | ConvertFrom-Json
        $marker.operationKind | Should -Be "restore"
        $marker.backupId | Should -Be "20261105T000000Z-0123456789abcdef0123456789abcdef"
        $marker.operationId | Should -Be "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        $marker.supersedesOperationId | Should -Be "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

        $entries = @(InModuleScope gitea-lifecycle -Parameters @{ Directory = $markerDirectory } {
            param($Directory)
            Get-LongPathDirectoryEntries -Path $Directory
        })
        $entries.Count | Should -Be 1
        $entries[0].Name | Should -Be "lifecycle-recovery.json"
    }

    It "keeps the original config and removes temporary files when NTFS rejects replacement" {
        [System.IO.File]::SetAttributes($script:pinConfigExtendedPath, [System.IO.FileAttributes]::ReadOnly)
        $failureMessage = $null
        try {
            InModuleScope gitea-lifecycle -Parameters @{ Context = $script:pinContext; ImageReference = $script:pinExpectedImage } {
                param($Context, $ImageReference)
                Set-GiteaBootstrapImagePin -Context $Context -ImageReference $ImageReference
            }
        }
        catch {
            $failureMessage = $_.Exception.Message
        }
        finally {
            [System.IO.File]::SetAttributes($script:pinConfigExtendedPath, [System.IO.FileAttributes]::Normal)
        }

        $failureMessage | Should -Not -BeNullOrEmpty
        $failureMessage | Should -Match "stage 'atomically replace the existing bootstrap config'"
        $failureMessage | Should -Match 'System\.UnauthorizedAccessException'
        $failureMessage | Should -Not -Match 'fixture-admin-password-do-not-log|fixture-api-token-do-not-log'
        [System.IO.File]::ReadAllText($script:pinConfigExtendedPath) | Should -Be $script:pinInitialJson

        $entries = @(InModuleScope gitea-lifecycle -Parameters @{ Directory = $script:pinConfigDirectory } {
            param($Directory)
            Get-LongPathDirectoryEntries -Path $Directory
        })
        $entries.Count | Should -Be 1
        $entries[0].Name | Should -Be "gitea-bootstrap.json"
    }

    It "restores the original config when the previous-file backup cannot be cleaned" {
        $failureMessage = InModuleScope gitea-lifecycle -Parameters @{ Context = $script:pinContext; ImageReference = $script:pinExpectedImage } {
            param($Context, $ImageReference)
            Mock Remove-LongPathEntry {
                param($Path)
                if ($Path -match '\.replace-backup\.tmp$') {
                    throw "simulated previous-file backup cleanup failure"
                }
                $extendedPath = ConvertTo-ExtendedLengthPath -Path $Path
                [System.IO.File]::SetAttributes($extendedPath, [System.IO.FileAttributes]::Normal)
                [System.IO.File]::Delete($extendedPath)
            }
            try {
                Set-GiteaBootstrapImagePin -Context $Context -ImageReference $ImageReference
            }
            catch {
                $_.Exception.Message
            }
        }

        $failureMessage | Should -Match 'Atomic replacement was rolled back'
        $failureMessage | Should -Match "stage 'atomically replace the existing bootstrap config'"
        [System.IO.File]::ReadAllText($script:pinConfigExtendedPath) | Should -Be $script:pinInitialJson

        $entries = @(InModuleScope gitea-lifecycle -Parameters @{ Directory = $script:pinConfigDirectory } {
            param($Directory)
            Get-LongPathDirectoryEntries -Path $Directory
        })
        $entries.Count | Should -Be 1
        $entries[0].Name | Should -Be "gitea-bootstrap.json"
    }

    It "masks credentials echoed by a failed image-pin operation" {
        $failureMessage = InModuleScope gitea-lifecycle -Parameters @{ Context = $script:pinContext; ImageReference = $script:pinExpectedImage } {
            param($Context, $ImageReference)
            Mock Move-LongPathFile {
                throw "write failed: adminPassword=fixture-admin-password-do-not-log; apiToken=fixture-api-token-do-not-log"
            }
            try {
                Set-GiteaBootstrapImagePin -Context $Context -ImageReference $ImageReference
            }
            catch {
                $_.Exception.Message
            }
        }

        $failureMessage | Should -Match "stage 'atomically replace the existing bootstrap config'"
        $failureMessage | Should -Match 'System\.Management\.Automation\.RuntimeException'
        $failureMessage | Should -Match '\[REDACTED\]'
        $failureMessage | Should -Not -Match 'fixture-admin-password-do-not-log|fixture-api-token-do-not-log'
        [System.IO.File]::ReadAllText($script:pinConfigExtendedPath) | Should -Be $script:pinInitialJson

        $entries = @(InModuleScope gitea-lifecycle -Parameters @{ Directory = $script:pinConfigDirectory } {
            param($Directory)
            Get-LongPathDirectoryEntries -Path $Directory
        })
        $entries.Count | Should -Be 1
        $entries[0].Name | Should -Be "gitea-bootstrap.json"
    }
}
