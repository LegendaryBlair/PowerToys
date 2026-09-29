#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-session-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
$helpers=Split-Path $PSScriptRoot -Parent
foreach($name in 'pt-desktop','pt-verification-report','pt-settings-session','pt-cleanup-plan'){
    . "$helpers\$name.ps1"
}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$results=[Collections.Generic.List[object]]::new()
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body,[string]$Pattern){
    try{& $Body|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return}
    throw "Expected rejection: $Pattern"
}
function Check([string]$Name,[scriptblock]$Body){
    try{& $Body|Out-Null;$results.Add(@{Name=$Name;Status='PASS'})}
    catch{$results.Add(@{Name=$Name;Status='FAIL';Error=$_.Exception.Message;Stack=$_.ScriptStackTrace});throw}
    finally{ConvertTo-Json -InputObject @($results) -Depth 8|Set-Content "$Workspace\results.json"}
}
$script:windows=@{}
$script:processes=@{}
$script:nextProcess=20
function Get-PtNativeWindow {
    param([long]$Hwnd,[int]$ProcessId)
    if($Hwnd){if(-not $script:windows.ContainsKey($Hwnd)){throw 'Missing fixture HWND'};$script:windows[$Hwnd]}
    else{$script:windows.Values|Where-Object {-not $ProcessId -or $_.ProcessId -eq $ProcessId}}
}
function Get-Process {
    param([int]$Id)
    if($Id){$script:processes[$Id]}else{$script:processes.Values}
}
function Start-Process {
    param($FilePath,$ArgumentList,[switch]$PassThru,$ErrorAction)
    if($FilePath -eq 'reused.exe'){return $script:processes[10]}
    if($FilePath -eq 'failed.exe'){throw 'Synthetic launch failure'}
    $script:nextProcess++
    $value=[pscustomobject]@{Id=$script:nextProcess;StartTime=[datetime]'2026-01-01T01:00:00Z'}
    $script:processes[$value.Id]=$value
    $value
}
function Native([long]$Hwnd,[int]$ProcessId){
    $script:windows[$Hwnd]=[pscustomobject]@{Hwnd=$Hwnd;ProcessId=$ProcessId;ClassName='OwnedFixture'}
    Get-PtWindowIdentity $Hwnd
}
function Session {
    $global:PtActiveResourceSession=$null;$global:PtLiveResourceGuards=@{}
    $script:windows=@{};$script:processes=@{10=[pscustomobject]@{Id=10;StartTime=[datetime]'2025-01-01T00:00:00Z'}}
    Native 10 10|Out-Null
    $run=New-PtVerificationRun -Workspace (Join-Path $Workspace ([guid]::NewGuid().ToString('N'))) `
        -Module 'Session fixture' -Bits 'Offline synthetic objects; no product mutation' -Scenario InfrastructureAcceptance `
        -Items @(@{Id='I1';Description='Contract';Admin='NO';Clarity='CLEAR';UserVisible=$false;Assertions=@(@{Id='a';Description='Synthetic behavior'})}) `
        -Inputs @(Get-PtVerificationInputs -Skill (Split-Path $helpers -Parent) -Inputs @(@{Name='test.ps1';Role='Checklist';Path=$PSCommandPath}))
    New-PtResourceSession $run|Out-Null
    $run
}
Check 'Borrowed and pre-existing windows cannot become owned or be closed' {
    $run=Session;$identity=Get-PtWindowIdentity 10
    Register-PtBorrowedWindow $identity|Out-Null
    Reject {Close-PtTrackedWindow $identity} 'no explicit owned'
    Reject {Register-PtOwnedWindowRecord (Get-PtActiveResourceSession) $identity Run 'fake'} 'Pre-existing'
    Require ($script:windows.Count -eq 1) 'Borrowed window changed'
}
Check 'Direct launches require actual PID/start time and reject shared process adoption' {
    $run=Session
    Reject {Start-PtOwnedProcess reused.exe} 'reused'
    $creation=Start-PtOwnedProcess fixture.exe
    $identity=Native 21 $creation.ProcessId
    Reject {Register-PtCreatedWindow $identity @{Id='fake'}} 'not a product'
    Register-PtCreatedWindow $identity $creation|Out-Null
    Native 22 $creation.ProcessId|Out-Null
    Reject {Assert-PtWindowRelease $identity} 'unowned sibling'
    $script:windows.Remove(22L)
    Assert-PtWindowRelease $identity
    $script:processes[$creation.ProcessId].StartTime=[datetime]'2026-02-01T00:00:00Z'
    Reject {Assert-PtWindowIdentity $identity} 'identity changed'
}
Check 'Receipt and immutable baseline edits fail before further mutation' {
    $run=Session;$session=Get-PtActiveResourceSession
    $saved=[IO.File]::ReadAllText($session.Path)
    [IO.File]::WriteAllText($session.Path,$saved.Replace('PtResources.v1','invalid'))
    Reject {Start-PtOwnedProcess fixture.exe} 'session changed'
    [IO.File]::WriteAllText($session.Path,$saved)
    [IO.File]::AppendAllText($session.BaselinePath,' ')
    Reject {Register-PtBorrowedWindow (Get-PtWindowIdentity 10)} 'baseline was altered'
}
Check 'Clipboard owner/writer release is gated, restored guards clear it, resume retains unresolved data' {
    $run=Session;$guard=[pscustomobject]@{Restored=$false}
    Add-PtClipboardObligation $guard 10
    Protect-PtClipboardWriter $guard 25
    Reject {Assert-PtProcessRelease @(25)} 'clipboard obligation'
    Assert-PtProcessRelease @(26)
    $guard.Restored=$true;Assert-PtProcessRelease @(10,25)
    $other=[pscustomobject]@{Restored=$false};Add-PtClipboardObligation $other 26
    $global:PtActiveResourceSession=$null
    Open-PtResourceSession $run|Out-Null
    Reject {Assert-PtProcessRelease @(26)} 'clipboard obligation'
    Assert-PtProcessRelease @(25)
}
Check 'Unresolved launches remain visible at final resource completion' {
    $run=Session
    Reject {Start-PtOwnedProcess failed.exe} 'Synthetic launch'
    $attempt=Start-PtVerificationAttempt -Run $run -Context Cleanup -Name 'Cleanup' -Kind Normal
    try{Reject {Complete-PtResourceSession $attempt} 'unresolved ownership'}
    finally{Stop-PtVerificationAttempt $attempt -Reason 'Expected unresolved launch'}
    Require (@((Get-PtReportState $run).Restoration|Where-Object Verdict -eq 'PASS').Count -eq 0) 'Failed launch certified clean'
}
Check 'Settings restores page, scroll and minimized placement; failed UI cleanup still restores placement' {
    $run=Session
    $script:ui=[pscustomobject]@{PageAutomationId='DashboardNavItem';Expansion=@();Scroll=@(@{Id='scroll';Vertical=42;Horizontal=-1});UnsupportedControls=@()}
    $script:placement=[pscustomobject]@{showCmd=2;Normal=@(10,20,600,800)}
    $script:restoreCount=0
    function Get-PtWindowSnapshot {param($Hwnd) [pscustomobject]@{identity=Get-PtWindowIdentity $Hwnd;placement=$script:placement;visible=$true}}
    function Restore-PtWindowSnapshot {param($Snapshot) $script:restoreCount++;$script:placement=$Snapshot.placement;$Snapshot}
    function Read-PtSettingsUiState {param($Hwnd) $script:ui}
    function Get-PtSettingsCurrentState {param($Hwnd,[switch]$AllowTemporaryRestore) [pscustomobject]@{Native=Get-PtWindowSnapshot $Hwnd;Ui=$script:ui}}
    function Set-PtSettingsUiState {param($Hwnd,$State) if($script:failUi){throw 'Synthetic UI failure'};$script:ui=$State}
    function Assert-PtForegroundOrAbort {param($Hwnd)}
    function Show-PtSettingsForObservation {param($Hwnd)}
    $snapshot=Get-PtSettingsUiSnapshot 10 $run.Workspace
    $script:ui=[pscustomobject]@{PageAutomationId='FixtureNavItem';Expansion=@();Scroll=@();UnsupportedControls=@()}
    $script:placement=[pscustomobject]@{showCmd=1;Normal=@(20,30,700,900)}
    $actual=Restore-PtSettingsUiSnapshot $snapshot
    Require ($actual.Restored -and $script:ui.PageAutomationId -eq 'DashboardNavItem' -and $script:placement.showCmd -eq 2) 'Settings state was not restored'
    Require ((Get-PtActiveResourceSession).Settings[0].Restored) 'Settings obligation not completed'
    $script:ui=[pscustomobject]@{PageAutomationId='FixtureNavItem';Expansion=@();Scroll=@();UnsupportedControls=@()}
    $script:failUi=$true
    Reject {Restore-PtSettingsUiSnapshot $snapshot} 'Synthetic UI failure'
    Require ($script:restoreCount -eq 4) 'UI failure skipped placement restoration'
    $script:failUi=$false
    $attempt=Start-PtVerificationAttempt -Run $run -Context Cleanup -Name 'Late Settings mutation' -Kind Normal
    try{Reject {Complete-PtResourceSession $attempt} 'unresolved ownership'}
    finally{Stop-PtVerificationAttempt $attempt -Reason 'Expected current-state mismatch despite prior receipt'}
    [IO.File]::AppendAllText($snapshot.Path,' ')
    Reject {Restore-PtSettingsUiSnapshot $snapshot} 'original snapshot changed'
    Require ($script:restoreCount -eq 4) 'Changed baseline was replayed'
}
Check 'Cleanup enforces order, requires Boolean comparison and continues independent steps after failure' {
    $run=Session;$script:ran=[Collections.Generic.List[string]]::new()
    $attempt=Start-PtVerificationAttempt -Run $run -Context Cleanup -Name 'Plan' -Kind Normal
    $steps=@(
        @{Id='clipboard';Phase='Clipboard';DependsOn=@();Action={throw 'Synthetic clipboard failure'};Verify={$true}},
        @{Id='writer';Phase='Quiesce';DependsOn=@('clipboard');Action={$script:ran.Add('writer')};Verify={$true}},
        @{Id='independent';Phase='Files';DependsOn=@();Action={$script:ran.Add('files')};Verify={$true}},
        @{Id='false-success';Phase='Verify';DependsOn=@();Action={};Verify={'true'}}
    )
    try{
        Reject {Invoke-PtCleanupPlan $attempt $steps} 'Cleanup incomplete'
        Require (($script:ran -join ',') -ceq 'files') 'Dependent action ran or independent action skipped'
        Reject {Invoke-PtCleanupPlan $attempt @($steps[2],$steps[0])} 'safe order'
    }finally{Stop-PtVerificationAttempt $attempt -Reason 'Expected injected failures'}
}
$global:PtActiveResourceSession=$null;$global:PtLiveResourceGuards=@{}
"PASS: $($results.Count) session contract groups; no real desktop/clipboard mutation. $Workspace"
