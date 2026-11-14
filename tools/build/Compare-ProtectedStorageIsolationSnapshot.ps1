# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Before,
    [Parameter(Mandatory)][string]$After,
    [ValidateSet('Unchanged','Restarted','RemovedKeepData','ReinstalledKeepData')][string]$Mode = 'Unchanged',
    [switch]$RequireProfileRemoved
)
$ErrorActionPreference = 'Stop'
$beforeState = Get-Content -LiteralPath $Before -Raw | ConvertFrom-Json
$afterState = Get-Content -LiteralPath $After -Raw | ConvertFrom-Json
$issues = [Collections.Generic.List[string]]::new()
foreach ($state in @($beforeState,$afterState)) {
    if ($state.Schema -ne 1 -or !$state.Machine -or !$state.OwnerSid -or !$state.VaSid) { $issues.Add('Missing snapshot identity/schema.') }
    if (@($state.Errors).Count -gt 0) { $issues.Add('A snapshot contains collection/check errors; absence cannot be inferred from access denial.') }
    if (!$state.Data.Stable -or !$state.Data.IndexHash -or !$state.Data.BlobHash -or !$state.Data.Epoch -or !$state.Data.InitializationId) {
        $issues.Add('Use snapshots of initialized stable workspace data, not an empty/unverified installation.')
    }
}
foreach ($property in @('Machine','OwnerSid','VaSid')) {
    if ($beforeState.$property -cne $afterState.$property) { $issues.Add("$property changed. Compare the same account on the same Windows instance.") }
}
if ($Mode -in @('Unchanged','Restarted')) {
    if (!$beforeState.Checks.Installed -or !$afterState.Checks.Installed) { $issues.Add('Unchanged comparison requires a verified running installation on both sides.') }
    $properties = if ($Mode -eq 'Unchanged') { @('Service','Carrier','Main','MainExecutable','Bootstrap','Runtime') } else { @('Carrier','Main','MainExecutable') }
    foreach ($property in $properties) {
        if (($beforeState.$property | ConvertTo-Json -Depth 6 -Compress) -cne ($afterState.$property | ConvertTo-Json -Depth 6 -Compress)) {
            $issues.Add("$property changed while the other account was maintained (including a process restart).")
        }
        if ($Mode -eq 'Restarted') {
            foreach ($property in @('Name','Account','Image','State','StartType','NativeCode')) {
                if ($beforeState.Service.$property -cne $afterState.Service.$property) { $issues.Add("Service.$property changed across reboot.") }
            }
        }
    }
}
if ($Mode -eq 'RemovedKeepData' -and (!$beforeState.Checks.Installed -or !$afterState.Checks.RemovedKeepData)) {
    $issues.Add('Expected verified installed -> removed-with-data-retained states.')
}
if ($Mode -eq 'ReinstalledKeepData' -and (!$beforeState.Checks.RemovedKeepData -or !$afterState.Checks.Installed)) {
    $issues.Add('Expected verified retained-data removal -> reinstalled states.')
}
foreach ($property in @('IndexHash','BlobHash','Epoch','InitializationId','Sequence')) {
    if ($beforeState.Data.$property -cne $afterState.Data.$property) {
        $issues.Add("Data.$property changed; do not edit/launch/save workspaces between these isolation snapshots.")
    }
}
if ($RequireProfileRemoved -and ($Mode -ne 'RemovedKeepData' -or !$afterState.Checks.ProfileRemoved -or
    $afterState.Markers.'cleanup-pending' -notin @(2,3) -or $afterState.Markers.'profile-cleanup-id' -notin @(2,3))) {
    $issues.Add('Post-reboot profile cleanup is incomplete or unverified.')
}
if ($RequireProfileRemoved -and $beforeState.Profile.Path -ine $afterState.Profile.Path) {
    $issues.Add('The prior registered profile used a different path; verify that exact directory separately, not only the default path.')
}
if ($issues.Count) { throw ($issues -join "`n") }
Write-Output "PASS ${Mode}: same machine/owner/VA, expected lifecycle state, and unchanged workspace bytes/initialization."
