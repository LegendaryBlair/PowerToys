#requires -Version 7.2
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-fancyzones-driver.ps1"
. "$PSScriptRoot\..\pt-cleanup-plan.ps1"
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-PtReportName {param($Name)}
function Invoke-PtVerificationStep {
    param($Attempt,$Name,$Command,$ArgumentList,$Action)
    $recorded=@(ConvertTo-PtReportArguments $ArgumentList)
    Require ((ConvertTo-Json -InputObject $recorded -Depth 20 -WarningAction Stop) -notmatch 'private-sentinel') 'Private recovery data entered recorded arguments.'
    & $Action @ArgumentList
}
function New-PtVerificationArtifactPath {param($Attempt,$Name) $Name}
function Write-PtReportText {param($Path,$Text)}
function Add-PtVerificationArtifact {param($Attempt,$Path,$Kind,$Description) [pscustomobject]@{Path=$Path}}
function Add-PtVerificationRestoration {param($Attempt,$Verdict,$Reason,$Evidence)}
function Register-PtCreatedProcessWindows {param($Creation)}
function Restore-PtPointerPosition {param($Snapshot)}
function Close-PtTaskViewTransition {param($Transition) if($f.ShellFailure){throw 'Shell release failed'};$Transition.State='Closed'}
function Close-PtFancyZonesEditor {param($Context) $Context.EditorCreation=$null}
function Get-PtResourceProcessCandidates {param($Path) if($Path -eq 'host' -and $f.HostAlive){[pscustomobject]@{processId=1}}}
function Get-PtResourceProcessIdentity {param($ProcessId) if($ProcessId -eq 2 -and $f.SurfaceAlive){[pscustomobject]@{processStartTicks=20L}}}
function Stop-PtOwnedProcess {
    param($Creation,$TimeoutSeconds,$ArgumentList,$RequestExit)
    if($Creation.ProcessId -eq 1){
        if($f.HostFailure){throw 'Host exit not observed'}
        & $RequestExit $Creation @ArgumentList|Out-Null
        $f.HostAlive=$false;$f.Order.Add('host')
    }else{$f.SurfaceAlive=$false;$f.Order.Add('surface')}
}
function Restore-PtSettingsUiSnapshot {param($Snapshot) $f.Order.Add('settings');[pscustomobject]@{Restored=$true}}
function Restore-PtFileSetSnapshot {
    param($Snapshot,$ExpectedState,$OwnedFileNames)
    if(@($OwnedFileNames).Count){$f.Writes.Add($Snapshot.Kind);$f.Order.Add($Snapshot.Kind)}
    [pscustomobject]@{SelectedFilesMatchBaseline=$true}
}
function Restore-PtDesktopSnapshot {param($Snapshot)}
function Restore-PtKeyboardLayoutSnapshot {param($Snapshot,$ExpectedLayout)}
function New-Fixture {
    $script:f=@{HostAlive=$true;SurfaceAlive=$true;HostFailure=$false;ShellFailure=$false
        Writes=[Collections.Generic.List[string]]::new();Order=[Collections.Generic.List[string]]::new()}
    @{
        TaskView=[pscustomobject]@{State='Opened'}
        Driver=@{EditorCreation=$true;ExpectedModule=@{}}
        Host=@{ProcessId=1};HostPath='host';EditorPath='editor'
        Surface=@{ProcessId=2;ProcessStartTicks=20L};SurfaceState='unused'
        Desktop=@{pointer=@{}};Keyboard=@{Layout=1};SettingsSnapshot=@{Captured=$true}
        OriginalModule=@{Kind='module';FileNames=@('module.json');PrivatePayload='private-sentinel'}
        OriginalGeneral=@{Kind='general';FileNames=@('settings.json')};ExpectedGeneral=@{}
    }
}
$attempt=[pscustomobject]@{Phase='Cleanup';Kind='Normal'}
$context=New-Fixture
$global:FzCase=$context
$steps=New-PtFancyZonesCleanupPlan $context {param($enabled) Require (-not $enabled) 'Cleanup must disable the owned host.'}
Invoke-PtCleanupPlan -Attempt $attempt -Steps $steps|Out-Null
Require ($f.Writes.Count -eq 2 -and $f.Order.IndexOf('host') -lt $f.Order.IndexOf('general') -and
    $f.Order.IndexOf('settings') -lt $f.Order.IndexOf('general')) 'Successful cleanup order is wrong.'
foreach($failure in 'HostFailure','ShellFailure'){
    $context=New-Fixture
    $global:FzCase=$context
    $f[$failure]=$true
    $steps=New-PtFancyZonesCleanupPlan $context {}
    $caught=$null
    try{Invoke-PtCleanupPlan -Attempt $attempt -Steps $steps|Out-Null}catch{$caught=$_}
    Require ($null -ne $caught -and $f.Writes.Count -eq 0) 'Unsafe file restoration ran after release failure.'
    Require (-not $f.SurfaceAlive) 'Independent owned-fixture cleanup was skipped.'
    Require (@($caught.Exception.Data['CleanupResults']|Where-Object {$_.Resource -eq 'general-files' -and $_.Verdict -eq 'BLOCKED'}).Count -eq 1) 'Blocked dependency not recorded.'
}
$global:FzCase=$null
'PASS: host/Shell failure blocks file rollback; independent cleanup continues; successful restore is ordered.'
