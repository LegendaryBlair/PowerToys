#requires -Version 7.0
<#
.SYNOPSIS
Thin one-run lifecycle. Supply module observations/review and explicit restoration callbacks.
.NOTES
Callbacks receive the run (Cases) or active attempt (Preflight/Cleanup). This is not a scheduler.
No UI, retries, restarts, fixtures or verdicts are invented by this template.
#>
param(
    [Parameter(Mandatory)][string]$Skill,
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$Module,
    [Parameter(Mandatory)][string]$Bits,
    [ValidateSet('A','B','InfrastructureAcceptance')][string]$Scenario = 'A',
    [Parameter(Mandatory)][object[]]$Items,
    [Parameter(Mandatory)][object[]]$Inputs,
    [Parameter(Mandatory)][scriptblock]$Preflight,
    [Parameter(Mandatory)][scriptblock]$Cases,
    [Parameter(Mandatory)][scriptblock]$Cleanup,
    [object[]]$Retrospective,
    [switch]$NoFriction,
    [switch]$Resume
)
$ErrorActionPreference = 'Stop'
if (($NoFriction -and $Retrospective.Count) -or (-not $NoFriction -and -not $Retrospective.Count)) {
    throw 'Supply actual retrospective rows or an explicit NoFriction choice.'
}
Get-ChildItem "$Skill\scripts" -Filter '*.ps1' |
    Where-Object Name -ne 'pt-session-diagnose.ps1' | ForEach-Object { . $_.FullName }
if ($Resume) {
    $run = Open-PtVerificationRun -Workspace $Workspace
    Assert-PtReportOpen $run
    $state = Get-PtReportState $run
    if (@($state.Attempts | Where-Object { -not $_.Complete }).Count -or @($state.Steps | Where-Object Status -eq 'INCOMPLETE').Count) {
        throw 'Resume requires stopped attempts; interrupted gestures require explicit recovery, not automatic continuation.'
    }
    $metadata = ConvertFrom-PtReportJson ([IO.File]::ReadAllText((Join-Path $run.Workspace 'run.json')))
    if ($metadata.Module -cne $Module -or $metadata.Bits -cne $Bits -or $metadata.Scenario -cne $Scenario -or
        (ConvertTo-Json -InputObject $metadata.Items -Depth 30 -Compress) -cne (ConvertTo-Json -InputObject $Items -Depth 30 -Compress)) {
        throw 'Resume requires the same module, bits, scenario and complete inventory; use recorded inputs.'
    }
} else {
    $run = New-PtVerificationRun -Workspace $Workspace -Module $Module -Bits $Bits -Scenario $Scenario -Items $Items -Inputs $Inputs
}
$rootError = $null
try {
    Invoke-PtVerificationCase -Run $run -Context Preflight -Name 'Preflight' `
        -Command 'Execute supplied preflight callback (snapshot retained)' -Action $Preflight | Out-Null
    & $Cases $run | Out-Null
} catch { $rootError = $_ }
finally {
    try {
        Invoke-PtVerificationCase -Run $run -Context Cleanup -Name 'Final restoration' `
            -Command 'Execute supplied restoration callback and compare baseline (snapshot retained)' -Action $Cleanup | Out-Null
    } catch {
        if ($rootError) {
            $rootError.Exception.Data['CleanupFailure'] = $_.Exception.Message
            [Console]::Error.WriteLine("Cleanup failed: $($_.Exception.Message)")
        } else { $rootError = $_ }
    }
    Set-PtActiveVerificationAttempt -Attempt $null
}
try {
    $retrospectiveChoice = if ($NoFriction) { @{NoFriction=$true} } else { @{Retrospective=$Retrospective} }
    $export = if ($rootError) { Export-PtVerificationReport -Run $run } else { Complete-PtVerificationRun -Run $run @retrospectiveChoice }
} catch {
    if (-not $rootError) { throw }
    $rootError.Exception.Data['ReportFailure'] = $_.Exception.Message
    [Console]::Error.WriteLine("Report export failed: $($_.Exception.Message)")
}
if ($rootError) { throw $rootError }
$export
