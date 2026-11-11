[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $Paths,

    [string[]] $Tag = @(),

    [string] $Output
)

try {
    $testPaths = @(
        $Paths -split ',' |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($testPaths.Count -eq 0) {
        throw 'No Pester test paths were provided.'
    }

    Import-Module Pester -ErrorAction Stop

    $invokeParameters = @{
        Path     = $testPaths
        PassThru = $true
    }
    if ($Tag.Count -gt 0) {
        $invokeParameters.Tag = $Tag
    }
    if (-not [string]::IsNullOrWhiteSpace($Output)) {
        $invokeParameters.Output = $Output
    }

    $result = Invoke-Pester @invokeParameters -ErrorAction Stop
    if ($null -eq $result) {
        throw 'Invoke-Pester returned no result object.'
    }

    foreach ($propertyName in @('TotalCount', 'PassedCount', 'FailedCount', 'SkippedCount')) {
        if ($null -eq $result.PSObject.Properties[$propertyName]) {
            throw "Pester result is missing the required '$propertyName' count."
        }
    }

    $failureReasons = @()
    if ($result.TotalCount -le 0) {
        $failureReasons += 'Pester discovered no tests.'
    }
    if ($result.PassedCount -le 0) {
        $failureReasons += 'Pester ran no passing tests.'
    }
    if ($result.FailedCount -gt 0) {
        $failureReasons += "Pester reported $($result.FailedCount) failed test(s)."
    }

    foreach ($propertyName in @('FailedBlocksCount', 'FailedContainersCount')) {
        $property = $result.PSObject.Properties[$propertyName]
        if ($null -ne $property -and $property.Value -gt 0) {
            $failureReasons += "Pester reported $($property.Value) failed $propertyName value(s)."
        }
    }

    $resultProperty = $result.PSObject.Properties['Result']
    if ($null -ne $resultProperty -and $resultProperty.Value -ne 'Passed') {
        $failureReasons += "Pester run result was '$($resultProperty.Value)'."
    }

    $executedProperty = $result.PSObject.Properties['Executed']
    if ($null -ne $executedProperty -and -not $executedProperty.Value) {
        $failureReasons += 'Pester did not execute the selected test run.'
    }

    if ($failureReasons.Count -gt 0) {
        [Console]::Error.WriteLine(($failureReasons -join ' '))
        exit 1
    }

    exit 0
}
catch {
    [Console]::Error.WriteLine("Pester invocation failed: $($_.Exception.Message)")
    exit 1
}
