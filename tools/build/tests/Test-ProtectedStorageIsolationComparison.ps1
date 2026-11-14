# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
$ErrorActionPreference = 'Stop'
$compare = Join-Path $PSScriptRoot '..\Compare-ProtectedStorageIsolationSnapshot.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('PowerToysIsolationComparison-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$checks = 0
function Check-Comparison($Before, $After, [string]$Mode, [bool]$Pass, [switch]$ProfileRemoved) {
    $Before | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $root 'before.json')
    $After | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $root 'after.json')
    $passed = $true
    try {
        & $compare -Before (Join-Path $root 'before.json') -After (Join-Path $root 'after.json') -Mode $Mode -RequireProfileRemoved:$ProfileRemoved | Out-Null
    } catch { $passed = $false }
    if ($passed -ne $Pass) { throw "Unexpected $Mode comparison result." }
    $script:checks++
}
function Clone($Value) { $Value | ConvertTo-Json -Depth 10 | ConvertFrom-Json }
try {
    $baseline = [pscustomobject]@{
        Schema=1;Machine='machine-a';OwnerSid='owner-a';VaSid='va-a';Errors=@()
        Service=@{State=4;Pid=100};Carrier=@(@{Code='carrier';Version='1.0.0'});Main=@(@{Code='main'})
        MainExecutable=@{Native=0;Hash='main-hash';Version='1.0.0.0'}
        Bootstrap=@{Pid=100;Birth='123';Sid='va-a'};Runtime=@{Pid=101;Birth='124';Sid='va-a'}
        Checks=@{Installed=$true;RemovedKeepData=$false;ProfileRemoved=$false}
        Markers=@{'cleanup-pending'=2;'profile-cleanup-id'=2}
        Profile=@{Path='C:\Windows\ServiceProfiles\TestProfile'}
        Data=@{Stable=$true;IndexHash='index';BlobHash='blob';Epoch='epoch';InitializationId='initialized';Sequence='2'}
    }
    Check-Comparison $baseline (Clone $baseline) Unchanged $true
    foreach ($property in @('Machine','OwnerSid','VaSid')) {
        $changed=Clone $baseline; $changed.$property='other'
        Check-Comparison $baseline $changed Unchanged $false
    }
    $changed=Clone $baseline; $changed.Runtime.Birth='new-process'
    Check-Comparison $baseline $changed Unchanged $false
    Check-Comparison $baseline $changed Restarted $true
    $changed=Clone $baseline; $changed.Data.IndexHash='changed'
    Check-Comparison $baseline $changed Unchanged $false
    $changed=Clone $baseline; $changed.MainExecutable.Hash='changed'
    Check-Comparison $baseline $changed Unchanged $false
    $changed=Clone $baseline; $changed.Errors=@('native5; cannot verify')
    Check-Comparison $baseline $changed Unchanged $false
    $removed=Clone $baseline; $removed.Checks.Installed=$false; $removed.Checks.RemovedKeepData=$true
    Check-Comparison $baseline $removed RemovedKeepData $true
    Check-Comparison $baseline $removed RemovedKeepData $false -ProfileRemoved
    $removed.Checks.ProfileRemoved=$true
    Check-Comparison $baseline $removed RemovedKeepData $true -ProfileRemoved
    $removed.Markers.'cleanup-pending'=0
    Check-Comparison $baseline $removed RemovedKeepData $false -ProfileRemoved
    $removed.Markers.'cleanup-pending'=2
    $changed=Clone $removed; $changed.Profile.Path='C:\Windows\ServiceProfiles\TestProfile.000'
    Check-Comparison $baseline $changed RemovedKeepData $false -ProfileRemoved
    Check-Comparison $removed $baseline ReinstalledKeepData $true
    $changed=Clone $baseline; $changed.Data.InitializationId='new-initialization'
    Check-Comparison $removed $changed ReinstalledKeepData $false
    $changed=Clone $baseline; $changed.Data.Stable=$false
    Check-Comparison $baseline $changed Unchanged $false
    Write-Output "PASS $checks isolation comparison cases; no services, profiles, registrations or business data changed."
} finally { Remove-Item -LiteralPath $root -Recurse -Force }
