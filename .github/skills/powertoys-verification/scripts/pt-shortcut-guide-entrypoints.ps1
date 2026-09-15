#requires -Version 7.2
foreach($dependency in 'pt-shortcut-guide-flow','pt-uia'){
    . "$PSScriptRoot\$dependency.ps1"
}

function Get-PtSgEntryWindowState {
    param([Parameter(Mandatory)]$Target)
    Assert-PtWindowIdentity $Target
    if(-not ('PtSgEntryNative' -as [type])){
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class PtSgEntryNative {
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out int value, int size);
    public static int Cloaked(long hwnd) {
        int value;
        Marshal.ThrowExceptionForHR(DwmGetWindowAttribute(new IntPtr(hwnd), 14, out value, sizeof(int)));
        return value;
    }
}
'@
    }
    $window=Get-PtNativeWindow -Hwnd $Target.hwnd
    [pscustomobject]@{Target=$Target;Visible=$window.Visible;Minimized=$window.Minimized
        Cloaked=[PtSgEntryNative]::Cloaked($Target.hwnd);Rect=$window.Rect
        ForegroundHwnd=[PtDesktop]::GetForegroundWindow().ToInt64()}
}

function Test-PtSgEntryForeground {
    param($State)
    $State.Visible -and -not $State.Minimized -and $State.Cloaked -eq 0 -and
        $State.ForegroundHwnd -eq $State.Target.hwnd -and
        $State.Rect.Right -gt $State.Rect.Left -and $State.Rect.Bottom -gt $State.Rect.Top
}

function Find-PtSgListenerStart {
    param([string]$Text,[datetime]$LogDate,[datetime]$ProcessStartTime)
    $timestamp=$null
    foreach($line in $Text -split '\r?\n'){
        if($line -match '^\[(\d{2}:\d{2}:\d{2}\.\d{7})\]'){
            $timestamp=$LogDate.Date.Add([TimeSpan]::ParseExact($Matches[1],'hh\:mm\:ss\.fffffff',[Globalization.CultureInfo]::InvariantCulture))
        }elseif($line.Trim() -in 'Shortcut Guide activation-event listener started.','Shortcut Guide show-event listener started.'){
            if($timestamp -and $timestamp -ge $ProcessStartTime){return $timestamp}
        }
    }
}

function Wait-PtShortcutGuideInitialized {
    <# .SYNOPSIS
    Observe this SG process's listener-start receipt after its startup Activate/Hide sequence, not merely HWND existence.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$GuideTarget,[ValidateRange(0.5,20)][double]$TimeoutSeconds=10)
    Assert-PtWindowIdentity $GuideTarget
    $process=Get-Process -Id $GuideTarget.processId -ErrorAction Stop
    try{$started=$process.StartTime;$version=$process.FileVersion}finally{$process.Dispose()}
    $logRoot=Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\ShortcutGuide\Logs\$version"
    Wait-PtCondition -Description 'SG startup activation/hide and listener initialization' -TimeoutSeconds $TimeoutSeconds -Probe {
        Assert-PtWindowIdentity $GuideTarget
        if(Test-Path -LiteralPath $logRoot){
            foreach($file in @(Get-ChildItem -LiteralPath $logRoot -File -Filter '*.log')){
                if($file.Name -notmatch '(\d{4}-\d{2}-\d{2})\.log$'){continue}
                $date=[datetime]::ParseExact($Matches[1],'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
                if($date.Date -lt $started.Date){continue}
                $stream=[IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
                $reader=[IO.StreamReader]::new($stream)
                try{$text=$reader.ReadToEnd()}finally{$reader.Dispose()}
                $listener=Find-PtSgListenerStart $text $date $started
                if($listener -and -not (Get-PtNativeWindow -Hwnd $GuideTarget.hwnd).Visible){
                    return [pscustomobject]@{GuideTarget=$GuideTarget;ProcessStarted=$started.ToString('o')
                        ListenerStarted=$listener.ToString('o');LogPath=$file.FullName;Hidden=$true}
                }
            }
        }
    }
}

function Wait-PtSgEntryState {
    param([scriptblock]$Probe,[scriptblock]$Ready,[string]$Description,[double]$TimeoutSeconds=5,
        [Collections.Generic.List[object]]$Observations)
    if($null -eq $Observations){$Observations=[Collections.Generic.List[object]]::new()}
    $watch=@{Signature='';Count=0}
    $entryStateProbe=$Probe
    $entryStateReady=$Ready
    try{
        Wait-PtCondition -Description $Description -TimeoutSeconds $TimeoutSeconds -PollMilliseconds 100 -Probe {
            $sample=& $entryStateProbe
            $signature=ConvertTo-Json -InputObject $sample -Depth 12 -Compress
            if($signature -cne $watch.Signature){$Observations.Add($sample)}
            if(& $entryStateReady $sample){
                $watch.Count=if($signature -ceq $watch.Signature){$watch.Count+1}else{1}
                $watch.Signature=$signature
                if($watch.Count -ge 2){$sample}
            }else{$watch.Signature=$signature;$watch.Count=0}
        }
    }catch{
        $_.Exception.Data['PtSgEntryObservations']=$Observations.ToArray()
        throw
    }
}

function Get-PtSgQuickAccessState {
    param([Parameter(Mandatory)]$QuickAccessTarget,[string]$ModuleName='Shortcut Guide')
    $state=Get-PtSgEntryWindowState $QuickAccessTarget
    $state|Add-Member NoteProperty ControlsObserved $false
    $state|Add-Member NoteProperty ButtonCount 0
    $state|Add-Member NoteProperty TileCount 0
    $state|Add-Member NoteProperty TileEnabled $false
    if(Test-PtSgEntryForeground $state){
        Initialize-PtUiAutomation
        $root=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$QuickAccessTarget.hwnd)
        $condition=[Windows.Automation.PropertyCondition]::new(
            [Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::Button)
        $buttons=@($root.FindAll([Windows.Automation.TreeScope]::Descendants,$condition)|Where-Object {-not $_.Current.IsOffscreen})
        $tiles=@($buttons|Where-Object {$_.Current.Name -ceq $ModuleName})
        if($tiles.Count -gt 1){throw 'Quick Access has more than one matching module tile; no arbitrary selection is allowed.'}
        $state.ControlsObserved=$true;$state.ButtonCount=$buttons.Count;$state.TileCount=$tiles.Count
        if($tiles.Count){$state.TileEnabled=$tiles[0].Current.IsEnabled}
    }
    $state
}

function Wait-PtShortcutGuideQuickAccess {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$QuickAccessTarget,[Parameter(Mandatory)][bool]$Enabled,
        [string]$ModuleName='Shortcut Guide',[ValidateRange(0.5,15)][double]$TimeoutSeconds=5)
    Wait-PtSgEntryState -Description 'settled Quick Access module entry' -TimeoutSeconds $TimeoutSeconds `
        -Probe {Get-PtSgQuickAccessState $QuickAccessTarget $ModuleName} -Ready {
            param($sample)
            Test-PtSgQuickAccessReady $sample $Enabled
        }
}

function Test-PtSgQuickAccessReady {
    param($State,[bool]$Enabled)
    (Test-PtSgEntryForeground $State) -and $State.ControlsObserved -and $State.ButtonCount -gt 0 -and
        $(if($Enabled){$State.TileCount -eq 1 -and $State.TileEnabled}else{$State.TileCount -eq 0 -or -not $State.TileEnabled})
}

function Get-PtSgSettingsLandingState {
    param([Parameter(Mandatory)]$SettingsTarget,$GuideTarget)
    $state=Get-PtSgEntryWindowState $SettingsTarget
    $state|Add-Member NoteProperty PageObserved $false
    $state|Add-Member NoteProperty ShortcutGuideSelected $false
    if($GuideTarget){
        Assert-PtWindowIdentity $GuideTarget
        $state|Add-Member NoteProperty GuideVisible (Get-PtNativeWindow -Hwnd $GuideTarget.hwnd).Visible
    }
    if(Test-PtSgEntryForeground $state){
        try{
            $page=Resolve-PtUiElement -Hwnd $SettingsTarget.hwnd -AutomationId ShortcutGuideNavItem -ControlType ListItem
            $state.PageObserved=$true
            $state.ShortcutGuideSelected=$page.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected
        }catch{
            if($_.Exception.Data['PtUiResolutionStatus'] -ne 'Missing'){throw}
        }
    }
    $state
}

function Invoke-PtShortcutGuideSettings {
    <# .SYNOPSIS
    Click the rail Settings action once, then observe the existing Settings window actually coming foreground.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)]$SettingsTarget,
        [string]$SettingsName='Settings',[ValidateRange(0.5,15)][double]$TimeoutSeconds=5)
    Assert-PtSgFlowSession $Session
    Assert-PtWindowIdentity $SettingsTarget
    if(-not $Session.ActivationIssued -or
        (Get-PtShortcutGuidePresentation $Session.GuideTarget).Kind -ne 'FullGuide' -or
        -not (Test-PtForeground -Hwnd $Session.GuideTarget.hwnd)){
        throw 'The owned full guide must be foreground before clicking its Settings action.'
    }
    $tree=Invoke-PtWinApp -Arguments @('inspect','--depth','18','-w',"$($Session.GuideTarget.hwnd)",'--json')|ConvertFrom-Json
    $items=@(Get-PtUiElements $tree|Where-Object {$_.type -eq 'ListItem' -and $_.name -ceq $SettingsName -and -not $_.isOffscreen})
    if($items.Count -ne 1 -or -not $items[0].selector){throw 'The visible Settings rail item is not uniquely identified.'}
    # The shipped rail handles Tapped; UIA Invoke alone need not dispatch that mouse action.
    Invoke-PtWinApp -Arguments @('click',$items[0].selector,'-w',"$($Session.GuideTarget.hwnd)")|Out-Null
    Wait-PtSgEntryState -Description 'Settings foreground with Shortcut Guide selected' -TimeoutSeconds $TimeoutSeconds `
        -Probe {Get-PtSgSettingsLandingState $SettingsTarget $Session.GuideTarget} -Ready {
            param($sample)
            (Test-PtSgEntryForeground $sample) -and $sample.PageObserved -and $sample.ShortcutGuideSelected
        }
}

function Save-PtSgEntryCapture {
    <# .SYNOPSIS
    Reobserve a settling window without repeating its action; retain rejected captures as evidence, not screenshots proving PASS.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Attempt,[Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Probe,[Parameter(Mandatory)][scriptblock]$Ready,
        [ValidateRange(0.5,15)][double]$TimeoutSeconds=5)
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $rejected=[Collections.Generic.List[object]]::new()
    $observations=[Collections.Generic.List[object]]::new()
    try{
        do{
            $remaining=$TimeoutSeconds-$clock.Elapsed.TotalSeconds
            if($remaining -lt 0.1){throw 'Window did not settle for a valid passive capture before the observation timeout.'}
            Wait-PtSgEntryState -Description "$Name capture readiness" -Probe $Probe -Ready $Ready `
                -TimeoutSeconds $remaining -Observations $observations|Out-Null
            $image=New-PtVerificationArtifactPath $Attempt "$Name.png"
            try{
                $capture=Save-PtPassiveScreenshot -Path $image -Observe $Probe
            }catch{
                if($_.Exception.Data['PtCaptureStatus'] -ne 'ObservationChanged'){throw}
                $rejected.Add((Add-PtVerificationArtifact $Attempt $image Evidence 'Rejected unstable capture; not passing screenshot evidence'))
                $rejected.Add((Add-PtVerificationArtifact $Attempt "$image.state.json" Evidence 'Unstable capture before/after state'))
                continue
            }
            if(-not (& $Ready $capture.before.observation) -or -not (& $Ready $capture.after.observation)){
                $rejected.Add((Add-PtVerificationArtifact $Attempt $image Evidence 'Capture no longer satisfies target readiness'))
                $rejected.Add((Add-PtVerificationArtifact $Attempt "$image.state.json" Evidence 'Capture readiness mismatch'))
                continue
            }
            $photo=Add-PtVerificationArtifact $Attempt $image Screenshot 'Settled target and unchanged before/after passive capture'
            $sidecar=Add-PtVerificationArtifact $Attempt "$image.state.json" Evidence 'Settled capture state'
            return [pscustomobject]@{State=$capture.after.observation;Screenshot=$photo;StateEvidence=$sidecar
                RejectedCaptures=$rejected.ToArray();Observations=$observations.ToArray()}
        }while($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds)
        throw 'Window did not settle for a valid passive capture before the observation timeout.'
    }catch{
        $_.Exception.Data['PtSgEntryObservations']=$observations.ToArray()
        $_.Exception.Data['PtRejectedCaptures']=$rejected.ToArray()
        $failure=$_
        try{
            $path=New-PtVerificationArtifactPath $Attempt "$Name-observations.json"
            ConvertTo-Json -InputObject $observations.ToArray() -Depth 20|Set-Content -LiteralPath $path
            $failure.Exception.Data['PtSgEntryObservationEvidence']=Add-PtVerificationArtifact $Attempt $path Evidence 'Actual window states before capture timeout/error'
        }catch{$failure.Exception.Data['PtEntryEvidenceFailure']=$_.Exception.Message;[Console]::Error.WriteLine($_.Exception.Message)}
        throw $failure
    }
}
