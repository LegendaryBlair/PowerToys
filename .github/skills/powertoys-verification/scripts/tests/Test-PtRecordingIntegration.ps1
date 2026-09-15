<#
.SYNOPSIS
Offline acceptance of the actual winapp wrapper/recorder wiring and recording overhead.
#>
param(
    [ValidateRange(1,1000)][int]$StepCount = 30,
    [string]$Workspace = (Join-Path $env:TEMP "pt-recording-integration-$([Guid]::NewGuid().ToString('N'))")
)
$ErrorActionPreference = 'Stop'
$helpers = Split-Path $PSScriptRoot -Parent
$skill = Split-Path $helpers -Parent
. "$helpers\pt-verification-report.ps1"
. "$helpers\pt-desktop.ps1"
$run = New-PtVerificationRun -Workspace $Workspace -Module 'Recorder integration' `
    -Bits 'Synthetic helper acceptance only; no product UI was driven' -Scenario InfrastructureAcceptance `
    -Inputs @(
        @{ Name = 'SKILL.md'; Role = 'Skill'; Path = "$skill\SKILL.md" }
        @{ Name = 'acceptance.ps1'; Role = 'Checklist'; Path = $PSCommandPath }
        @{ Name = 'pt-desktop.ps1'; Role = 'Helper'; Path = "$helpers\pt-desktop.ps1" }
        @{ Name = 'recorder.ps1'; Role = 'Helper'; Path = "$helpers\pt-verification-report.ps1" }
    ) -Items @(
        @{ Id = 'I1'; Description = 'Native wrapper records every invocation without changing its stdout contract'
           Admin = 'NO'; Clarity = 'CLEAR'; UserVisible = $false
           Assertions = @(@{ Id = 'commands'; Description = 'Outer helper and nested native call both retained' }) }
    )
$preflight = Start-PtVerificationAttempt -Run $run -Context Preflight -Kind Normal -Name 'Offline CLI availability' -Activate
$helpOutput = Invoke-PtWinApp -Arguments @('--help')
if ($helpOutput -notmatch 'inspect') { throw 'Actual wrapper returned unexpected CLI help.' }
Stop-PtVerificationAttempt $preflight -Reason 'Help-only probe; no desktop access'
$attempt = Start-PtVerificationAttempt -Run $run -ItemId I1 -Kind Normal -Name 'Nested command capture' -Activate
$nested = Invoke-PtVerificationStep -Attempt $attempt -Name 'Outer helper' -Command 'Invoke-PtWinApp -Arguments --help' -Action {
    Invoke-PtWinApp -Arguments @('--help')
}
if ($nested -cne $helpOutput) { throw 'Recording changed raw stdout.' }
$clock = [Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt $StepCount; $i++) {
    Invoke-PtVerificationStep -Attempt $attempt -Name "probe-$i" -Command "offline-probe $i" -ArgumentList @($i) -Action {
        param($index)
        "result-$index"
    } | Out-Null
}
$clock.Stop()
$timing = @{ steps = $StepCount; recordingMilliseconds = $clock.Elapsed.TotalMilliseconds }
$path = New-PtVerificationArtifactPath -Attempt $attempt -Name 'timing.json'
$timing | ConvertTo-Json | Set-Content -LiteralPath $path
$evidence = Add-PtVerificationArtifact -Attempt $attempt -Path $path -Kind Evidence -Description 'Offline command count and recording duration'
Add-PtVerificationAssertion -Attempt $attempt -AssertionId commands -Verdict PASS `
    -Category 'Offline wrapper integration' -Reason 'Native stdout preserved and nested commands recorded' -Evidence @($evidence)
Stop-PtVerificationAttempt $attempt -Reason 'Integration probes finished'
Complete-PtVerificationItem -Run $run -ItemId I1 -Reason 'Synthetic recorder integration only'
$cleanup = Start-PtVerificationAttempt -Run $run -Context Cleanup -Kind Normal -Name 'No live state mutations' -Activate
$receipt = Invoke-PtVerificationStep -Attempt $cleanup -Name 'Restoration scope' -Command 'Assert no desktop or product operations in this script' -Action {
    'Only help commands and local evidence files were used; no product files, registry or windows were changed.'
}
$path = New-PtVerificationArtifactPath -Attempt $cleanup -Name 'restoration.txt'
$receipt | Set-Content -LiteralPath $path
$evidence = Add-PtVerificationArtifact -Attempt $cleanup -Path $path -Kind Restoration -Description 'Explicit offline-only mutation scope'
Add-PtVerificationRestoration -Attempt $cleanup -Verdict PASS -Reason 'No live state mutations' -Evidence @($evidence)
Stop-PtVerificationAttempt $cleanup -Reason 'Offline scope recorded'
$export = Complete-PtVerificationRun -Run $run -NoFriction
$state = Get-Content $export.Results -Raw | ConvertFrom-Json
$winappSteps = @($state.Steps | Where-Object { $_.Command -like 'winapp ui *' })
if ($winappSteps.Count -ne 2 -or @($state.Steps | Where-Object ParentStepId).Count -ne 1) { throw 'Nested winapp command coverage was lost.' }
if ($export.Signoff -ne 'APPROVED') { throw "Synthetic acceptance unexpectedly withheld: $($state.SignoffReasons -join '; ')" }
Test-PtVerificationArchive -Workspace $Workspace | Out-Null
$timing | ConvertTo-Json
"PASS: offline native integration. Evidence: $Workspace"
