[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{32}$')]
    [string]$RunId,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedPath,

    [string]$ApproveRunId
)

Import-Module (Join-Path $PSScriptRoot 'gitea-lifecycle-e2e-fixture-cleanup.psm1') -Force -ErrorAction Stop
Remove-GiteaLifecycleE2EFixtureDirectory @PSBoundParameters
