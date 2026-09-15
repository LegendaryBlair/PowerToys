#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-sg-entry-contracts-$([Guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-shortcut-guide-entrypoints.ps1"
if(Test-Path -LiteralPath $Workspace){throw 'Use a new workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$checks=[Collections.Generic.List[object]]::new()
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body,[string]$Pattern){
    try{& $Body|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return $_}
    throw "Expected rejection: $Pattern"
}
function Check([string]$Name,[scriptblock]$Body){
    try{& $Body|Out-Null;$checks.Add(@{Name=$Name;Status='PASS'})}
    catch{$checks.Add(@{Name=$Name;Status='FAIL';Error=$_.Exception.Message;Stack=$_.ScriptStackTrace});throw}
    finally{ConvertTo-Json -InputObject $checks.ToArray() -Depth 8|Set-Content "$Workspace\results.json"}
}
$target=[pscustomobject]@{hwnd=10;processId=20;processStartTicks=30;className='Window'}
function State([long]$Foreground=10,[bool]$Selected=$true){
    [pscustomobject]@{Target=$target;Visible=$true;Minimized=$false;Cloaked=0;ForegroundHwnd=$Foreground
        Rect=@{Left=0;Top=0;Right=500;Bottom=400};PageObserved=$true;ShortcutGuideSelected=$Selected;GuideVisible=$false}
}
function Wait-PtCondition {
    param($Probe,$Description,$TimeoutSeconds,$PollMilliseconds)
    foreach($number in 1..8){$value=& $Probe;if($value){return $value}}
    throw "Timed out waiting for $Description"
}
Check 'Native visibility alone does not establish an actionable Quick Access surface' {
    $s=State
    Require (Test-PtSgEntryForeground $s) 'Ready window rejected'
    foreach($property in 'Cloaked','Minimized','ForegroundHwnd'){
        $s=State
        if($property -eq 'Cloaked'){$s.Cloaked=1}elseif($property -eq 'Minimized'){$s.Minimized=$true}else{$s.ForegroundHwnd=99}
        Require (-not (Test-PtSgEntryForeground $s)) "Unready $property accepted"
    }
    Check 'Initialization receipt must belong to the current SG process, not an earlier listener' {
        $date=[datetime]'2026-09-15'
        $text="[12:00:00.1234567] [Info] App.cs::Listen`n    Shortcut Guide activation-event listener started."
        Require ($null -eq (Find-PtSgListenerStart $text $date ([datetime]'2026-09-15T12:00:01'))) 'Old-process listener was accepted'
        Require ((Find-PtSgListenerStart $text $date ([datetime]'2026-09-15T11:59:59')) -eq [datetime]'2026-09-15T12:00:00.1234567') 'Current-process listener not recognized'
        Require ($null -eq (Find-PtSgListenerStart 'Shortcut Guide activation-event listener started.' $date $date)) 'Untimestamped marker was accepted'
    }
}
Check 'Selected Settings page behind the guide cannot satisfy navigation' {
    $sample=State 99
    $error=Reject {Wait-PtSgEntryState -Probe {$sample} -Ready {param($s) (Test-PtSgEntryForeground $s) -and $s.ShortcutGuideSelected} -Description landing} 'Timed out'
    Require ($error.Exception.Data['PtSgEntryObservations'][0].ForegroundHwnd -eq 99) 'Failed transition facts were lost'
}
Check 'Enabled and disabled Quick Access capture predicates cannot accept the opposite state' {
    $s=State
    $s|Add-Member NoteProperty ControlsObserved $true
    $s|Add-Member NoteProperty ButtonCount 4
    $s|Add-Member NoteProperty TileCount 1
    $s|Add-Member NoteProperty TileEnabled $true
    Require ((Test-PtSgQuickAccessReady $s $true) -and -not (Test-PtSgQuickAccessReady $s $false)) 'Enabled tile satisfies disabled capture'
    $s.TileCount=0;$s.TileEnabled=$false
    Require ((Test-PtSgQuickAccessReady $s $false) -and -not (Test-PtSgQuickAccessReady $s $true)) 'Missing tile satisfies enabled capture'
    $s.ButtonCount=0
    Require (-not (Test-PtSgQuickAccessReady $s $false)) 'Empty UIA surface satisfies disabled capture'
}
Check 'A foreground transition must settle and show the correct Settings page' {
    $queue=[Collections.Generic.Queue[object]]::new()
    foreach($s in @((State 99),(State 10 $false),(State),(State 99),(State),(State))){$queue.Enqueue($s)}
    $observed=Wait-PtSgEntryState -Probe {$queue.Dequeue()} -Ready {
        param($s) (Test-PtSgEntryForeground $s) -and $s.PageObserved -and $s.ShortcutGuideSelected
    } -Description landing
    Require ($queue.Count -eq 0 -and $observed.ForegroundHwnd -eq 10) 'Transient foreground or stale page was accepted'
}
Check 'Settings uses one physical click and never manufactures foreground after the action' {
    $counts=@{Clicks=0;Invokes=0}
    function Assert-PtSgFlowSession {param($Session)}
    function Assert-PtWindowIdentity {param($Identity)}
    function Get-PtShortcutGuidePresentation {param($GuideTarget) @{Kind='FullGuide'}}
    function Test-PtForeground {param($Hwnd) $true}
    function Force-PtForeground {throw 'Forbidden result forcing'}
    function Assert-PtForegroundOrAbort {throw 'Forbidden result forcing'}
    function Get-PtSgSettingsLandingState {param($SettingsTarget) $s=State;$s.GuideVisible=$true;$s}
    function Invoke-PtWinApp {
        param($Arguments)
        switch($Arguments[0]){
            inspect {'{"windows":[{"elements":[{"type":"ListItem","name":"Settings","selector":"settings-rail","isOffscreen":false}]}]}'}
            click {$counts.Clicks++}
            invoke {$counts.Invokes++;throw 'Invoke does not dispatch the Tapped fixture'}
            default {throw 'Unexpected UI action'}
        }
    }
    $session=@{ActivationIssued=$true;GuideTarget=$target}
    $result=Invoke-PtShortcutGuideSettings -Session $session -SettingsTarget $target
    Require ($result.ShortcutGuideSelected -and $result.GuideVisible -and $counts.Clicks -eq 1 -and $counts.Invokes -eq 0) 'Settings action was repeated, substituted or given an unrelated close requirement'
}
Check 'Observation errors are not swallowed as transition latency' {
    $error=Reject {Wait-PtSgEntryState -Probe {throw 'identity changed'} -Ready {$true} -Description native} 'identity changed'
    Require ($error.Exception.Message -eq 'identity changed') 'Original observer error changed'
}
Check 'An unstable screenshot is retained, then only observation is repeated' {
    $file=Join-Path $Workspace 'fixture.txt';[IO.File]::WriteAllText($file,'Synthetic-only proof')
    $run=New-PtVerificationRun -Workspace "$Workspace\capture" -Module 'SG entry observer fixture' -Bits 'Synthetic only' `
        -Scenario InfrastructureAcceptance -Items @(@{Id='I1';Description='Settled capture';Admin='NO';Clarity='CLEAR';UserVisible=$false
            Assertions=@(@{Id='capture';Description='Only settled capture is passing evidence'})}) `
        -Inputs @(@{Name='skill.txt';Role='Skill';Path=$file},@{Name='test.ps1';Role='Checklist';Path=$PSCommandPath},
            @{Name='entry.ps1';Role='Helper';Path="$PSScriptRoot\..\pt-shortcut-guide-entrypoints.ps1"})
    $attempt=Start-PtVerificationAttempt $run -ItemId I1 -Kind Normal -Name capture
    $counts=@{Captures=0}
    function Save-PtPassiveScreenshot {
        param($Path,$Observe)
        $counts.Captures++
        [IO.File]::WriteAllBytes($Path,[Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWZkAAAAASUVORK5CYII='))
        $before=State;$after=if($counts.Captures -eq 1){State 99}else{State}
        $state=@{before=@{observation=$before};after=@{observation=$after}}
        [IO.File]::WriteAllText("$Path.state.json",(ConvertTo-Json $state -Depth 10))
        if($counts.Captures -eq 1){
            $e=[InvalidOperationException]::new('Capture changed');$e.Data['PtCaptureStatus']='ObservationChanged';throw $e
        }
        $state
    }
    $capture=Save-PtSgEntryCapture -Attempt $attempt -Name settled -Probe {State} -Ready {param($s) Test-PtSgEntryForeground $s}
    Require ($counts.Captures -eq 2 -and $capture.RejectedCaptures.Count -eq 2 -and $capture.Screenshot.Kind -eq 'Screenshot') 'Capture recovery contract failed'
    Require (@($capture.RejectedCaptures|Where-Object Kind -ne Evidence).Count -eq 0) 'Rejected pixels were labeled as passing screenshots'
    $events=@(Read-PtReportEvents $run)
    Require (@($events|Where-Object Type -eq ArtifactReserved).Count -eq @($events|Where-Object Type -eq ArtifactAdded).Count) 'Capture left unregistered evidence'
}
"PASS: $($checks.Count) SG entry contracts. $Workspace"
