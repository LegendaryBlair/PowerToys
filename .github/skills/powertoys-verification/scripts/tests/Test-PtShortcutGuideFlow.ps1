#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-sg-flow-$([Guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-shortcut-guide-flow.ps1"
Initialize-PtUiAutomation
if(Test-Path $Workspace){throw 'Use a new workspace.'}
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
    finally{$results|ConvertTo-Json -Depth 8|Set-Content "$Workspace\results.json"}
}
$foreground=[pscustomobject]@{hwnd=10;processId=20;processStartTicks=30;className='Fixture'}
$guide=[pscustomobject]@{hwnd=11;processId=21;processStartTicks=31;className='Guide'}
$fixture=@{Kind='Hidden';Events=0;Chords=0;Closes=0;HoldReleases=0;Query='';Ready=$true}
function Presentation([string]$Kind){
    [pscustomobject]@{Kind=$Kind;Target=$guide;Visible=($Kind -ne 'Hidden');HostVisibleAtReadStart=($Kind -ne 'Hidden')
        ForegroundHwnd=10;Indicators=@($(if($Kind -eq 'Indicators'){@{Number=1}}));SearchCount=0;RailCount=0;CloseCount=0}
}
function Assert-PtWindowIdentity {param($Identity)}
function Assert-PtForegroundOrAbort {param($Hwnd)}
function Assert-PtShortcutInputIdle {}
function Get-PtForegroundWindow {[pscustomobject]@{Hwnd=10;ProcessId=$PID}}
function Get-PtModuleLifecycleState {param($Profile) [pscustomobject]@{RuntimeReady=$fixture.Ready;Windows=@(@{identity=$guide})}}
function Get-PtShortcutGuidePresentation {param($GuideTarget) Presentation $fixture.Kind}
function Get-PtSgFlowConfiguration {
    [pscustomobject]@{Chord=[pscustomobject]@{win=$true;ctrl=$false;alt=$false;shift=$true;code=191;key=''}
        HoldAction=1;HoldMilliseconds=100;CloseOnRelease=$true}
}
function Invoke-PtSharedEvent {param($Name) $fixture.Events++;$fixture.Kind='FullGuide';$true}
function Send-PtChord {param($Hwnd,$Mods,$Key) $fixture.Chords++;$fixture.Kind=if($fixture.Kind -eq 'FullGuide'){'Hidden'}else{'FullGuide'};6}
function Resolve-PtUiElement {
    param($Hwnd,$AutomationId,$ControlType,$WithinAutomationId)
    $pattern=[pscustomobject]@{Fixture=$fixture}
    $pattern|Add-Member ScriptMethod Invoke {$this.Fixture.Closes++;$this.Fixture.Kind='Hidden'}
    $control=[pscustomobject]@{Pattern=$pattern}
    $control|Add-Member ScriptMethod GetCurrentPattern {param($id) $this.Pattern}
    $control
}
function Get-PtUiObservation {param($Target,$AutomationId,$ControlType,$WithinAutomationId,$Property) [pscustomobject]@{Value=$fixture.Query}}
Check 'Explicit entry paths issue exactly one activation and do not substitute event for chord' {
    $session=Open-PtShortcutGuide -ForegroundTarget $foreground -Workspace $Workspace -Entry Chord -TimeoutSeconds 1
    Require ($fixture.Chords -eq 1 -and $fixture.Events -eq 0 -and $session.Phase -eq 'Open') 'Chord entry was replaced/repeated'
    Close-PtShortcutGuide $session -Route CloseButton -TimeoutSeconds 1|Out-Null
    $session=Open-PtShortcutGuide -ForegroundTarget $foreground -Workspace $Workspace -Entry NamedEvent -TimeoutSeconds 1
    Require ($fixture.Events -eq 1 -and $fixture.Chords -eq 1) 'Named-event entry sent keys'
    Close-PtShortcutGuide $session -Route Chord -TimeoutSeconds 1|Out-Null
    Require ($fixture.Kind -eq 'Hidden' -and $fixture.Chords -eq 2) 'Requested chord close route was changed'
}
Check 'Not-ready/already-visible preconditions never enable, restart or close unowned UI' {
    $fixture.Ready=$false
    Reject {Open-PtShortcutGuide -ForegroundTarget $foreground -Workspace $Workspace -Entry NamedEvent} 'not ready'
    $fixture.Ready=$true;$fixture.Kind='FullGuide'
    $before=$fixture.Events
    Reject {Open-PtShortcutGuide -ForegroundTarget $foreground -Workspace $Workspace -Entry NamedEvent} 'already visible'
    Require ($fixture.Events -eq $before) 'Precondition failure still activated'
    $fixture.Kind='Hidden'
}
Check 'Normal close does not credit an already-hidden surface or silently clear a query' {
    $session=Open-PtShortcutGuide -ForegroundTarget $foreground -Workspace $Workspace -Entry NamedEvent -TimeoutSeconds 1
    $fixture.Query='existing query';$before=$fixture.Chords
    Reject {Close-PtShortcutGuide $session -Route Escape} 'would clear the query'
    Require ($fixture.Chords -eq $before -and $fixture.Query -ceq 'existing query') 'Close erased query or sent Escape'
    $fixture.Query=''
    Close-PtShortcutGuide $session -Route Escape -TimeoutSeconds 1|Out-Null
    Reject {Close-PtShortcutGuide $session -Route CloseButton} 'not visible'
    $restored=Restore-PtShortcutGuideSession -ReceiptPath $session.ReceiptPath
    Require ($restored.Hidden -and $restored.CleanupOnly) 'Idempotent cleanup was confused with a tested close'
}
Check 'Early dismissal is retained and does not cause an activation retry' {
    $session=New-PtSgFlowSession $foreground $Workspace Chord FullGuide
    $sequence=[Collections.Generic.Queue[object]]::new()
    $sequence.Enqueue((Presentation 'VisibleUnclassified'))
    $sequence.Enqueue((Presentation 'Hidden'))
    function Get-PtShortcutGuidePresentation {param($GuideTarget) $sequence.Dequeue()}
    Reject {Wait-PtSgPresentation $session FullGuide 1 $true} 'dismissed before'
    Require ($session.Timeline.Count -eq 2) 'Early transition evidence was lost'
}
Check 'Observer errors release the held key and cleanup keeps the original failure' {
    function Invoke-PtHeldKeys {
        param($Hwnd,$Keys,$KeyDownDelayMilliseconds,$Action)
        $fixture.Kind='Indicators'
        try{& $Action}finally{$fixture.HoldReleases++;$fixture.Kind='Hidden'}
    }
    Reject {
        Invoke-PtShortcutGuideHold -ForegroundTarget $foreground -Workspace $Workspace -Mode Indicators -TimeoutSeconds 1 -Action {
            param($session) throw 'owned observer failed'
        }
    } 'owned observer failed'
    Require ($fixture.HoldReleases -eq 1 -and $fixture.Kind -eq 'Hidden') 'Held input cleanup did not run'
    $result=Invoke-PtShortcutGuideHold -ForegroundTarget $foreground -Workspace $Workspace -Mode Indicators -TimeoutSeconds 1 `
        -Action {param($session,$value) "observed-$value"} -ArgumentList @('held')
    Require ($result.Output[0] -ceq 'observed-held' -and $result.AfterRelease.Kind -eq 'Hidden') 'Held callback output or after-release state was lost'
}
Check 'Receipt tampering is rejected before any close route' {
    $session=New-PtSgFlowSession $foreground $Workspace Chord FullGuide
    $session.GuideTarget=[pscustomobject]@{hwnd=99;processId=99;processStartTicks=99;className='Unowned'}
    Reject {Restore-PtShortcutGuideSession $session} 'identity changed'
}
Check 'A failed full-guide observer is preserved and cleanup does not credit the requested normal route' {
    $fixture.Kind='Hidden'
    $beforeChords=$fixture.Chords;$beforeCloses=$fixture.Closes
    Reject {
        Invoke-PtShortcutGuideCycle -ForegroundTarget $foreground -Workspace $Workspace -Entry NamedEvent -CloseRoute Chord -TimeoutSeconds 1 `
            -Action {param($session) throw 'full observer failed'}
    } 'full observer failed'
    Require ($fixture.Kind -eq 'Hidden' -and $fixture.Chords -eq $beforeChords -and $fixture.Closes -eq $beforeCloses+1) 'Cleanup changed the requested close evidence or left the guide open'
}
Check 'Failed held observers wait for asynchronous release dismissal before cleanup' {
    $release=@{Requested=$false;Samples=0}
    function Get-PtShortcutGuidePresentation {
        param($GuideTarget)
        if($release.Requested){
            $release.Samples++
            if($release.Samples -ge 3){$fixture.Kind='Hidden'}
        }
        Presentation $fixture.Kind
    }
    function Invoke-PtHeldKeys {
        param($Hwnd,$Keys,$KeyDownDelayMilliseconds,$Action)
        $fixture.Kind='Indicators'
        try{& $Action}finally{$release.Requested=$true}
    }
    Reject {
        Invoke-PtShortcutGuideHold -ForegroundTarget $foreground -Workspace $Workspace -Mode Indicators -TimeoutSeconds 1 `
            -Action {param($session) throw 'observer error before asynchronous release'}
    } 'observer error before asynchronous release'
    Require ($release.Samples -ge 3 -and $fixture.Kind -eq 'Hidden') 'Cleanup treated delayed release delivery as an unclosable surface'
}
Check 'Cleanup waits through only the typed transient no-foreground condition' {
    $fixture.Kind='Hidden'
    $session=New-PtSgFlowSession $foreground $Workspace Chord FullGuide
    $h08ForegroundProbe=@{Reads=0}
    function Get-PtForegroundWindow {
        $h08ForegroundProbe.Reads++
        if($h08ForegroundProbe.Reads -eq 1){
            $failure=[InvalidOperationException]::new('Transient foreground transition')
            $failure.Data['PtDesktopStatus']='NoForeground'
            throw $failure
        }
        [pscustomobject]@{Hwnd=10;ProcessId=$PID}
    }
    $restored=Restore-PtShortcutGuideSession $session
    Require ($h08ForegroundProbe.Reads -eq 2 -and $restored.Hidden) 'Typed transition was not waited out'
}
Check 'Cleanup propagates unrelated foreground failures without retry or a restored phase' {
    $fixture.Kind='Hidden'
    $session=New-PtSgFlowSession $foreground $Workspace Chord FullGuide
    $h08ForegroundProbe=@{Reads=0}
    function Get-PtForegroundWindow {
        $h08ForegroundProbe.Reads++
        throw [InvalidOperationException]::new('Unrelated foreground read failure')
    }
    Reject {Restore-PtShortcutGuideSession $session} 'Unrelated foreground read failure'
    Require ($h08ForegroundProbe.Reads -eq 1 -and $session.Phase -eq 'Prepared') 'Unrelated error was retried or cleanup was credited'
}
"PASS: $($results.Count) offline SG flow groups. $Workspace"
