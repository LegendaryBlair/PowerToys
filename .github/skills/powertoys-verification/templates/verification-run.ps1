#requires -Version 7.0
<#
.SYNOPSIS
Thin one-run lifecycle. Supply module observations/review and explicit restoration callbacks.
.NOTES
Callbacks receive the run (Cases) or active attempt (Preflight/Cleanup). This is not a scheduler.
No UI, retries, restarts, fixtures or verdicts are invented by this template.
Report receives a reporting-only Diagnostic attempt after cleanup and before sealing.
Its optionality preserves legacy callers; new skill-guided runs supply the required statistics.
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
    [scriptblock]$Report,
    [scriptblock]$Cleanup,
    [object[]]$CleanupPlan,
    $ResourcePlan,
    [long[]]$SettingsHwnd=@(),
    [object[]]$Retrospective,
    [switch]$NoFriction,
    [switch]$Resume
)
$ErrorActionPreference = 'Stop'
if (($NoFriction -and $Retrospective.Count) -or (-not $NoFriction -and -not $Retrospective.Count)) {
    throw 'Supply actual retrospective rows or an explicit NoFriction choice.'
}
if([bool]$Cleanup -eq [bool]$CleanupPlan){throw 'Supply exactly one CleanupPlan or legacy Cleanup callback.'}
Get-ChildItem "$Skill\scripts" -Filter '*.ps1' |
    Where-Object Name -ne 'pt-session-diagnose.ps1' | ForEach-Object { . $_.FullName }
$profileKey=switch($Module.Replace(' ','').ToLowerInvariant()){
    'colorpicker'{'color-picker'} 'workspaces'{'workspaces'} 'shortcutguide'{'shortcut-guide'}
    'environmentvariables'{'environment-variables'}
}
if($Scenario -eq 'A' -and $profileKey -and (-not $ResourcePlan -or $Cleanup)){
    throw 'Aligned module runs require ResourcePlan and CleanupPlan; legacy Cleanup cannot substitute for resource wiring.'
}
if($ResourcePlan){
    if($Cleanup){throw 'ResourcePlan requires CleanupPlan, not the legacy Cleanup callback.'}
    Assert-PtRunResourcePlan -Plan $ResourcePlan -CleanupPlan $CleanupPlan -SettingsHwnd $SettingsHwnd
    $ResourcePlan=ConvertFrom-PtReportJson (ConvertTo-Json $ResourcePlan -Depth 20)
    $SettingsHwnd=@($ResourcePlan.Resources|Where-Object Kind -EQ 'Settings'|ForEach-Object Hwnd)
}
elseif($CleanupPlan){Assert-PtCleanupPlan $CleanupPlan}
if($Scenario -eq 'A' -and $profileKey){
    $inventoryPath="$Skill\references\assertion-inventories\$profileKey.json"
    $checklistPath="$Skill\references\release-checklist\$profileKey.md"
    $inventory=Import-PtAssertionInventory $inventoryPath $checklistPath
    if((ConvertTo-Json -InputObject $Items -Depth 30 -Compress) -cne
        (ConvertTo-Json -InputObject $inventory.Items -Depth 30 -Compress)){
        throw 'Use the frozen module inventory Items; run-local child regrouping is not accepted.'
    }
    foreach($source in @(@{Path=$inventoryPath;Name="$profileKey-inventory.json";Role='Other'},
        @{Path=$checklistPath;Name="$profileKey-checklist.md";Role='Checklist'})){
        if(-not @($Inputs|Where-Object {[IO.Path]::GetFullPath($_.Path) -ieq [IO.Path]::GetFullPath($source.Path)}).Count){$Inputs+=@($source)}
    }
}
if ($Resume) {
    $run = Open-PtVerificationRun -Workspace $Workspace
    Assert-PtReportOpen $run
    $state = Get-PtReportState $run
    if (@($state.Attempts | Where-Object { -not $_.Complete }).Count -or @($state.Steps | Where-Object Status -eq 'INCOMPLETE').Count) {
        throw 'Resume requires stopped attempts; interrupted gestures require explicit recovery, not automatic continuation.'
    }
    $metadata = ConvertFrom-PtReportJson ([IO.File]::ReadAllText((Join-Path $run.Workspace 'run.json')))
    $planPath=Join-Path $run.Workspace 'run-resource-plan.json'
    if(Test-Path -LiteralPath $planPath){
        $originalPlan=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($planPath))
        if((ConvertTo-Json $originalPlan -Depth 20 -Compress) -cne (ConvertTo-Json $ResourcePlan -Depth 20 -Compress)){
            throw 'Resume requires the original resource plan; do not weaken or replace its scope.'
        }
    }elseif($ResourcePlan){throw 'Resume cannot add a missing original resource plan after mutations.'}
    if ($metadata.Module -cne $Module -or $metadata.Bits -cne $Bits -or $metadata.Scenario -cne $Scenario -or
        (ConvertTo-Json -InputObject $metadata.Items -Depth 30 -Compress) -cne (ConvertTo-Json -InputObject $Items -Depth 30 -Compress)) {
        throw 'Resume requires the same module, bits, scenario and complete inventory; use recorded inputs.'
    }
} else {
    $recordedInputs = @(Get-PtVerificationInputs -Skill $Skill -Inputs $Inputs)
    $run = New-PtVerificationRun -Workspace $Workspace -Module $Module -Bits $Bits -Scenario $Scenario -Items $Items -Inputs $recordedInputs
    if($ResourcePlan){Write-PtReportText (Join-Path $run.Workspace 'run-resource-plan.json') (ConvertTo-Json $ResourcePlan -Depth 20)}
}
$rootError = $null
$sessionOpened=$false
$scopeState=[pscustomobject]@{Settings=@();Desktop=$null}
try {
    if($Resume){Open-PtResourceSession -Run $run|Out-Null}
    else{New-PtResourceSession -Run $run|Out-Null}
    $sessionOpened=$true
    $resources=Get-PtActiveResourceSession
    if($ResourcePlan){
        if($Resume -and (ConvertTo-Json $resources.ResourcePlan -Depth 20 -Compress) -cne (ConvertTo-Json $ResourcePlan -Depth 20 -Compress)){
            throw 'Resource-session plan differs from the original run plan.'
        }
        if(-not $Resume){$resources.ResourcePlan=$ResourcePlan;Save-PtResourceSession $resources}
    }
    if($SettingsHwnd.Count){
        if(-not $resources.Desktop){
            if($Resume){throw 'Resume has no original desktop baseline; do not replace it with current state.'}
            $resources.Desktop=Get-PtDesktopSnapshot
            Save-PtResourceSession $resources
        }
        foreach($hwndValue in $SettingsHwnd){
            Get-PtSettingsUiSnapshot -Hwnd $hwndValue -Workspace $run.Workspace|Out-Null
        }
    }
    Invoke-PtVerificationCase -Run $run -Context Preflight -Name 'Preflight' `
        -Command 'Capture this run baseline and evaluate its actual prerequisites' -Action $Preflight | Out-Null
    & $Cases $run | Out-Null
} catch { $rootError = $_ }
finally {
    if($sessionOpened){
        $resources=Get-PtActiveResourceSession
        $scopeState.Desktop=$resources.Desktop
        $scopeState.Settings=@($resources.Settings)
        try {
            Invoke-PtVerificationCase -Run $run -Context Cleanup -Name 'Final restoration' `
                -Command 'Execute declared restoration steps and validate resource obligations' `
                -ArgumentList @($Cleanup,$CleanupPlan,$scopeState) -Action {
                    param($attempt,$legacy,$plan,$state)
                    $cleanupError=$null
                    try{
                        if($plan){Invoke-PtCleanupPlan -Attempt $attempt -Steps $plan|Out-Null}
                        else{& $legacy $attempt|Out-Null}
                    }catch{$cleanupError=$_}
                    foreach($record in $state.Settings){
                        try{
                            $snapshot=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($record.Path))
                            Restore-PtSettingsUiSnapshot $snapshot|Out-Null
                        }
                        catch{
                            if($cleanupError){$cleanupError.Exception.Data["Settings-$($record.Identity.hwnd)"]=$_.Exception.Message}
                            else{$cleanupError=$_}
                        }
                    }
                    if($state.Desktop){
                        try{Restore-PtDesktopSnapshot $state.Desktop|Out-Null}
                        catch{
                            if($cleanupError){$cleanupError.Exception.Data['DesktopCleanupFailure']=$_.Exception.Message}
                            else{$cleanupError=$_}
                        }
                    }
                    try{Complete-PtResourceSession -Attempt $attempt|Out-Null}
                    catch{
                        if($cleanupError){$cleanupError.Exception.Data['ResourceCleanupFailure']=$_.Exception.Message}
                        else{$cleanupError=$_}
                    }
                    if($cleanupError){throw $cleanupError}
                } | Out-Null
        } catch {
            if ($rootError) {
                $rootError.Exception.Data['CleanupFailure'] = $_.Exception.Message
                [Console]::Error.WriteLine("Cleanup failed: $($_.Exception.Message)")
            } else { $rootError = $_ }
        }
        Set-PtActiveVerificationAttempt -Attempt $null
        if(-not $rootError){
            $global:PtActiveResourceSession=$null
            $global:PtLiveResourceGuards=@{}
        }
    }
}
if($Report){
    try{
        Invoke-PtVerificationCase -Run $run -Context Diagnostic -Kind Diagnostic -Name 'Report preparation' `
            -Command 'Extract bounded agent-origin execution statistics; no product actions or cleanup' -Action $Report|Out-Null
    }catch{
        if($rootError){
            $rootError.Exception.Data['ReportPreparationFailure']=$_.Exception.Message
            [Console]::Error.WriteLine("Report preparation failed: $($_.Exception.Message)")
        }else{$rootError=$_}
    }
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
