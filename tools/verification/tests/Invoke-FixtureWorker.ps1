#requires -Version 7.0
# Copyright (c) Microsoft Corporation
# Licensed under the MIT license.
<#
.SYNOPSIS
Deterministic offline worker for coordinator tests. Not an AI agent or product verification.
#>
param([Parameter(Mandatory)][string]$PacketPath, [Parameter(Mandatory)][string]$ResultPath)
$ErrorActionPreference = 'Stop'
$packet = Get-Content -LiteralPath $PacketPath -Raw | ConvertFrom-Json -AsHashtable
$directory = Split-Path $PacketPath -Parent
$proof = Join-Path $directory 'fixture-proof.txt'
[IO.File]::WriteAllText($proof, 'Synthetic fixture only; no desktop, product settings or external service access.')
$result = @{ taskId = $packet.taskId; workerId = $packet.workerId; status = 'completed'; summary = 'Synthetic worker result'; evidence = @($proof) }
if ($packet.role -eq 'runner') {
    . "$PSScriptRoot\..\..\..\.github\skills\powertoys-verification\scripts\pt-verification-report.ps1"
    $inputs = @($packet.bundle.files | ForEach-Object {
        @{ Name = [IO.Path]::GetFileName($_.relativePath); Role = $_.role; Path = $_.file.path }
    })
    $inputs += @{ Name = 'worker.ps1'; Role = 'Other'; Path = $PSCommandPath }
    $run = New-PtVerificationRun -Workspace (Join-Path $directory 'archive') -Module $packet.module -Bits $packet.bits `
        -Scenario InfrastructureAcceptance -Inputs $inputs -Items @(
            @{ Id = 'fixture'; Description = 'Synthetic observer reads its value'; Admin = 'NO'; Clarity = 'CLEAR'; UserVisible = $false
                Assertions = @(@{ Id = 'value'; Description = 'Synthetic value is observed' }) }
        )
    Invoke-PtVerificationCase -Run $run -Context Preflight -Name 'Synthetic preflight' -Command 'No product access' -Action { 'offline' } | Out-Null
    $attempt = Start-PtVerificationAttempt $run -ItemId fixture -Kind Normal -Name 'Synthetic observation'
    $helper = @($packet.bundle.files | Where-Object { $_.role -eq 'helper' })[0].file.path
    . $helper
    $observationError = $null
    try {
        $value = Invoke-PtVerificationStep $attempt -Name 'Synthetic observer' -Command 'Get-VfFixtureValue' -Action { Get-VfFixtureValue }
        if ($value -cne 'observed') { throw 'Synthetic observer returned an unexpected value.' }
    } catch { $observationError = $_ }
    $evidence = Add-PtVerificationArtifact $attempt $proof Evidence 'Synthetic observation receipt' -Synthetic
    if ($observationError) {
        Add-PtVerificationAssertion $attempt value BLOCKED BLK-INFRASTRUCTURE $observationError.Exception.Message -Evidence @($evidence)
    } else { Add-PtVerificationAssertion $attempt value PASS fixture 'Synthetic value matched' -Evidence @($evidence) }
    Stop-PtVerificationAttempt $attempt -Reason 'Synthetic observation finished'
    Complete-PtVerificationItem $run fixture -Reason 'Explicit synthetic result'
    $cleanup = Start-PtVerificationAttempt $run -Context Cleanup -Kind Normal -Name 'Synthetic restoration'
    Invoke-PtVerificationStep $cleanup -Name cleanup -Command 'No product state was mutated' -Action { 'No product changes' } | Out-Null
    $evidence = Add-PtVerificationArtifact $cleanup $proof Restoration 'Synthetic complete no-mutation scope' -Synthetic
    Add-PtVerificationRestoration $cleanup PASS 'No live state changes' -Evidence @($evidence)
    Stop-PtVerificationAttempt $cleanup -Reason 'Synthetic restoration recorded'
    Complete-PtVerificationRun $run -NoFriction | Out-Null
    $result.archivePath = $run.Workspace
} elseif ($packet.role -eq 'reviewer') {
    $archive = $packet.priorRun.archive.archivePath
    $state = Get-Content -LiteralPath (Join-Path $archive 'results.json') -Raw | ConvertFrom-Json -AsHashtable
    $result.findings = @()
    if (@($state.Steps | Where-Object { $_.Status -eq 'Error' }).Count) {
        $result.recommendation = 'repair'
        $result.findings = @(@{ layer = 'harness'; summary = 'Synthetic observer fails; expectation is unchanged.'; evidence = @((Join-Path $archive 'results.json')) })
    } else { $result.recommendation = 'accept' }
} elseif ($packet.role -eq 'repairer') {
    $relative = @($packet.bundle.files | Where-Object { $_.role -eq 'helper' })[0].relativePath
    $helper = Join-Path $packet.candidateRoot $relative
    [IO.File]::WriteAllText($helper, 'function Get-VfFixtureValue { "observed" }')
    . $helper
    if ((Get-VfFixtureValue) -cne 'observed') { throw 'Synthetic candidate validation failed.' }
    [IO.File]::AppendAllText($proof, "`nCandidate observer returned the exact expected value.")
} else { throw "Unexpected fixture role: $($packet.role)" }
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ResultPath
