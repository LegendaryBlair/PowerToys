#requires -Version 7.2
<#
.SYNOPSIS
Owned, explicit Shortcut Guide open/observe/close and Windows-key-hold operations.
.NOTES
No implicit enable/restart, retry, trigger substitution, query clearing or product verdicts.
#>
foreach($dependency in 'pt-shortcut-guide','pt-module-lifecycle','pt-shortcut-recorder','pt-ui-snapshot','pt-foreground-guard'){
    . "$PSScriptRoot\$dependency.ps1"
}

function Get-PtSgLifecycleProfile {
    [pscustomobject]@{
        Id='shortcut-guide';ModuleKey='Shortcut Guide';PageAutomationId='ShortcutGuideNavItem';ToggleName='Shortcut Guide'
        Model='Resident';ProcessName='PowerToys.ShortcutGuide'
        ProcessPath=(Join-Path $env:LOCALAPPDATA 'PowerToys\WinUI3Apps\PowerToys.ShortcutGuide.exe')
        WindowClass='WinUIDesktopWin32WindowClass'
        Events=@(@{Name='ShortcutGuide.Trigger';WhenEnabled='Present';WhenDisabled='Ignore'})
    }
}

function Get-PtSgFlowConfiguration {
    $path=Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys\Shortcut Guide\settings.json'
    $document=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($path))
    $properties=$document.properties
    Assert-PtShortcutBinding $properties.open_shortcutguide
    if(($properties.win_key_action.value -isnot [int] -and $properties.win_key_action.value -isnot [long]) -or
        ($properties.press_time.value -isnot [int] -and $properties.press_time.value -isnot [long]) -or
        $properties.win_key_action.value -notin 0,1,2 -or $properties.press_time.value -lt 100 -or
        $properties.press_time.value -gt 5000 -or $properties.close_on_windows_key_release.value -isnot [bool]){
        throw 'Unsupported SG hold configuration; no setting will be changed automatically.'
    }
    [pscustomobject]@{Chord=$properties.open_shortcutguide;HoldAction=$properties.win_key_action.value
        HoldMilliseconds=$properties.press_time.value;CloseOnRelease=$properties.close_on_windows_key_release.value}
}

function Get-PtShortcutGuidePresentation {
    <# .SYNOPSIS
    Observe host identity, actual visible presentation and exposed structural controls.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$GuideTarget)
    Assert-PtWindowIdentity $GuideTarget
    $window=Get-PtNativeWindow -Hwnd $GuideTarget.hwnd
    $state=[ordered]@{Kind='Hidden';Target=$GuideTarget;Visible=$window.Visible;HostVisibleAtReadStart=$window.Visible
        ForegroundHwnd=[PtDesktop]::GetForegroundWindow().ToInt64();Indicators=@();SearchCount=0;RailCount=0;CloseCount=0}
    if(-not $window.Visible){return [pscustomobject]$state}
    Initialize-PtUiAutomation
    $root=[Windows.Automation.AutomationElement]::FromHandle([IntPtr][long]$GuideTarget.hwnd)
    $conditions=@('ShortcutGuide_SearchBox','MenuItemsHost','CloseButton','IndicatorText'|ForEach-Object{
        [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,$_)
    })
    $condition=[Windows.Automation.OrCondition]::new([Windows.Automation.Condition[]]$conditions)
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $indicators=[Collections.Generic.List[object]]::new()
    try{
        foreach($element in @($root.FindAll([Windows.Automation.TreeScope]::Descendants,$condition))){
            $id=@($element.GetRuntimeId()) -join ','
            if(-not $id){throw 'SG element lacks a runtime identity.'}
            if(-not $seen.Add($id)){continue}
            $offscreen=$element.GetCurrentPropertyValue([Windows.Automation.AutomationElement]::IsOffscreenProperty,$true)
            if($offscreen -isnot [bool]){throw 'SG visibility metadata is unsupported; no visible-content default was assumed.'}
            if($offscreen){continue}
            switch($element.Current.AutomationId){
                ShortcutGuide_SearchBox {$state.SearchCount++}
                MenuItemsHost {$state.RailCount++}
                CloseButton {$state.CloseCount++}
                IndicatorText {
                    $name=$element.Current.Name
                    if($name -match '^[1-9]$'){
                        $rect=$element.Current.BoundingRectangle
                        $indicators.Add([pscustomobject]@{Number=[int]$name;RuntimeId=@($element.GetRuntimeId());X=$rect.X;Y=$rect.Y;Width=$rect.Width;Height=$rect.Height})
                    }
                }
            }
        }
    }catch [Windows.Automation.ElementNotAvailableException] {
        if((Get-PtNativeWindow -Hwnd $GuideTarget.hwnd).Visible){throw}
        $state.Visible=$false
        return [pscustomobject]$state
    }
    Assert-PtWindowIdentity $GuideTarget
    if(-not (Get-PtNativeWindow -Hwnd $GuideTarget.hwnd).Visible){$state.Visible=$false;return [pscustomobject]$state}
    $state.Indicators=$indicators.ToArray()
    if($state.SearchCount -gt 1 -or $state.RailCount -gt 1 -or $state.CloseCount -gt 1){throw 'Ambiguous SG presentation controls.'}
    $state.Kind=if($state.SearchCount -eq 1 -and $state.RailCount -eq 1 -and $state.CloseCount -eq 1){'FullGuide'}
        elseif($state.SearchCount -eq 0 -and $state.Indicators.Count -gt 0){'Indicators'}else{'VisibleUnclassified'}
    [pscustomobject]$state
}

function New-PtSgFlowSession {
    param($ForegroundTarget,[string]$Workspace,[string]$Entry,[string]$Mode)
    Assert-PtWindowIdentity $ForegroundTarget
    $runtime=Get-PtModuleLifecycleState (Get-PtSgLifecycleProfile)
    if(-not $runtime.RuntimeReady){throw 'SG native runtime is not ready; enable/diagnose it explicitly through H06.'}
    $guide=$runtime.Windows[0].identity
    $before=Get-PtShortcutGuidePresentation $guide
    if($before.Kind -ne 'Hidden'){throw 'SG is already visible; this operation does not own the existing surface.'}
    $foreground=Get-PtForegroundWindow
    if((Get-Process -Id $foreground.ProcessId -ErrorAction Stop).ProcessName -in 'SearchHost','StartMenuExperienceHost'){
        throw 'An existing Shell surface is not owned by this flow; close or restore it explicitly first.'
    }
    Assert-PtShortcutInputIdle
    $directory=(Get-Item -LiteralPath $Workspace -ErrorAction Stop).FullName
    if(-not [IO.Directory]::Exists($directory)){throw 'Flow receipts require an existing workspace directory.'}
    Assert-PtReportNoLink $directory
    $session=[pscustomobject]@{
        Schema='PtSgFlow.v1';Id=[Guid]::NewGuid().ToString('N');Workspace=$directory;ReceiptPath=''
        ForegroundTarget=$ForegroundTarget;GuideTarget=$guide;Entry=$Entry;Mode=$Mode
        Configuration=Get-PtSgFlowConfiguration;Before=$before;Phase='Prepared';Last=$before
        Timeline=[Collections.Generic.List[object]]::new();ActivationIssued=$false;Failure=$null
    }
    $session.ReceiptPath=Join-Path $directory "sg-flow-$($session.Id).json"
    Write-PtReportText $session.ReceiptPath (ConvertTo-Json $session -Depth 20)
    $session
}

function Assert-PtSgFlowSession {
    param($Session)
    if($Session.Schema -cne 'PtSgFlow.v1' -or $Session.Id -cnotmatch '^[a-f0-9]{32}$' -or
        [IO.Path]::GetFileName($Session.ReceiptPath) -cne "sg-flow-$($Session.Id).json" -or
        [IO.Path]::GetDirectoryName($Session.ReceiptPath) -ine $Session.Workspace){throw 'Invalid SG flow ownership receipt.'}
    Assert-PtReportNoLink $Session.ReceiptPath
    $saved=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($Session.ReceiptPath))
    foreach($name in 'Id','GuideTarget','ForegroundTarget','Entry','Mode','Configuration'){
        if((ConvertTo-Json $saved.$name -Depth 12 -Compress) -cne (ConvertTo-Json $Session.$name -Depth 12 -Compress)){throw "SG flow identity changed: $name"}
    }
    if($Session.Timeline -isnot [Collections.Generic.List[object]]){
        $timeline=[Collections.Generic.List[object]]::new()
        foreach($entry in $Session.Timeline){$timeline.Add($entry)}
        $Session.Timeline=$timeline
    }
}

function Save-PtSgFlowSession {
    param($Session)
    Assert-PtSgFlowSession $Session
    $temporary=Join-Path $Session.Workspace "sg-flow-write-$([Guid]::NewGuid().ToString('N')).tmp"
    try{Write-PtReportText $temporary (ConvertTo-Json $Session -Depth 20);[IO.File]::Move($temporary,$Session.ReceiptPath,$true)}
    finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}

function Wait-PtSgPresentation {
    param($Session,[string]$Kind,[double]$TimeoutSeconds,[bool]$RejectEarlyHide=$false)
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $watch=@{SeenVisible=$false;LastSignature='';StableSince=-1.0}
    Wait-PtCondition -Description "SG $Kind presentation" -TimeoutSeconds $TimeoutSeconds -PollMilliseconds 25 -Probe {
        $state=Get-PtShortcutGuidePresentation $Session.GuideTarget
        $Session.Last=$state
        if($state.Visible -or $state.HostVisibleAtReadStart){$watch.SeenVisible=$true}
        $signature="$($state.Kind)|$($state.ForegroundHwnd)|$($state.Indicators.Count)"
        if($signature -cne $watch.LastSignature){
            if($Session.Timeline.Count -lt 128){$Session.Timeline.Add([pscustomobject]@{Milliseconds=$clock.Elapsed.TotalMilliseconds;Kind=$state.Kind;ForegroundHwnd=$state.ForegroundHwnd;IndicatorCount=$state.Indicators.Count})}
            $watch.LastSignature=$signature
        }
        if($RejectEarlyHide -and $watch.SeenVisible -and -not $state.Visible){throw 'SG dismissed before a stable requested presentation was observed; no activation retry was sent.'}
        if($state.Kind -eq $Kind){
            if($watch.StableSince -lt 0){$watch.StableSince=$clock.Elapsed.TotalMilliseconds}
            if($clock.Elapsed.TotalMilliseconds-$watch.StableSince -ge 100){return $state}
        }else{$watch.StableSince=-1.0}
    }
}

function Open-PtShortcutGuide {
    <# .SYNOPSIS
    Send exactly one explicit entry and observe stable FullGuide content; never replace Chord with an event.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$ForegroundTarget,[Parameter(Mandatory)][string]$Workspace,
        [Parameter(Mandatory)][ValidateSet('NamedEvent','Chord')][string]$Entry,
        [ValidateRange(0.2,15)][double]$TimeoutSeconds=5)
    $session=New-PtSgFlowSession $ForegroundTarget $Workspace $Entry FullGuide
    $body={
        param($owned,$timeout)
        try{
            Assert-PtWindowIdentity $owned.ForegroundTarget
            Assert-PtForegroundOrAbort -Hwnd $owned.ForegroundTarget.hwnd
            Assert-PtShortcutInputIdle
            $owned.ActivationIssued=$true;$owned.Phase='Activating';Save-PtSgFlowSession $owned
            if($owned.Entry -eq 'NamedEvent'){
                if(-not (Invoke-PtSharedEvent -Name ShortcutGuide.Trigger)){throw 'SG trigger event was not accepted.'}
            }else{
                $chord=$owned.Configuration.Chord
                $mods=@(if($chord.win){0x5B};if($chord.ctrl){0x11};if($chord.alt){0x12};if($chord.shift){0x10})
                Send-PtChord -Hwnd $owned.ForegroundTarget.hwnd -Mods $mods -Key $chord.code|Out-Null
            }
            $owned.Last=Wait-PtSgPresentation $owned FullGuide $timeout $true
            $owned.Phase='Open';Save-PtSgFlowSession $owned
            $owned
        }catch{
            $failure=$_;$owned.Phase='OpenFailed'
            $owned.Failure=[pscustomobject]@{Stage='Open';Message=$failure.Exception.Message}
            $failure.Exception.Data['SgFlowReceipt']=$owned.ReceiptPath
            try{Save-PtSgFlowSession $owned}catch{$failure.Exception.Data['SgReceiptFailure']=$_.Exception.Message}
            try{Restore-PtShortcutGuideSession $owned|Out-Null}catch{$failure.Exception.Data['SgCleanupFailure']=$_.Exception.Message}
            throw $failure
        }
    }
    $active=Get-PtActiveVerificationAttempt
    if($active){
        $targetText=(ConvertTo-Json $ForegroundTarget -Compress).Replace("'","''")
        Invoke-PtVerificationStep $active -Name "Open SG via $Entry" `
            -Command "Open-PtShortcutGuide -ForegroundTarget (ConvertFrom-PtReportJson '$targetText') -Workspace '$($Workspace.Replace("'","''"))' -Entry $Entry -TimeoutSeconds $TimeoutSeconds" `
            -Implementation ${function:Open-PtShortcutGuide} -Action $body -ArgumentList @($session,$TimeoutSeconds)
    }else{& $body $session $TimeoutSeconds}
}

function Close-PtShortcutGuide {
    <# .SYNOPSIS
    Apply one requested close route to an owned visible full guide, then observe stable hidden state.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)][ValidateSet('CloseButton','Escape','Chord')][string]$Route,
        [ValidateRange(0.2,15)][double]$TimeoutSeconds=5)
    Assert-PtSgFlowSession $Session
    if(-not $Session.ActivationIssued){throw 'This receipt does not own an issued activation.'}
    $body={
        param($owned,$closeRoute,$timeout)
        $state=Get-PtShortcutGuidePresentation $owned.GuideTarget
        if($state.Kind -ne 'FullGuide'){throw 'The owned full guide is not visible before the requested close route; close cannot be credited.'}
        if($closeRoute -eq 'CloseButton'){
            (Resolve-PtUiElement -Hwnd $owned.GuideTarget.hwnd -AutomationId CloseButton -ControlType Button).GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
        }else{
            if($closeRoute -eq 'Escape'){
                $query=Get-PtUiObservation -Target $owned.GuideTarget -AutomationId TextBox -ControlType Edit -WithinAutomationId ShortcutGuide_SearchBox -Property Text
                if($query.Value -cne ''){throw 'One Escape would clear the query; no query was silently cleared to make a close test pass.'}
                Send-PtChord -Hwnd $owned.GuideTarget.hwnd -Key 0x1B|Out-Null
            }else{
                $current=Get-PtSgFlowConfiguration
                if((ConvertTo-PtShortcutKey $current.Chord) -cne (ConvertTo-PtShortcutKey $owned.Configuration.Chord)){throw 'Configured chord changed after activation.'}
                $chord=$current.Chord
                $mods=@(if($chord.win){0x5B};if($chord.ctrl){0x11};if($chord.alt){0x12};if($chord.shift){0x10})
                Send-PtChord -Hwnd $owned.GuideTarget.hwnd -Mods $mods -Key $chord.code|Out-Null
            }
        }
        $owned.Last=Wait-PtSgPresentation $owned Hidden $timeout
        $owned.Phase='Closed';Save-PtSgFlowSession $owned
        [pscustomobject]@{Route=$closeRoute;After=$owned.Last;ReceiptPath=$owned.ReceiptPath}
    }
    $active=Get-PtActiveVerificationAttempt
    if($active){
        $text=(ConvertTo-Json $Session -Depth 20 -Compress).Replace("'","''")
        Invoke-PtVerificationStep $active -Name "Close SG via $Route" -Command "Close-PtShortcutGuide -Session (ConvertFrom-PtReportJson '$text') -Route $Route -TimeoutSeconds $TimeoutSeconds" `
            -Implementation ${function:Close-PtShortcutGuide} -Action $body -ArgumentList @($Session,$Route,$TimeoutSeconds)
    }else{& $body $Session $Route $TimeoutSeconds}
}

function Restore-PtShortcutGuideSession {
    <# .SYNOPSIS
    Cleanup only: close an owned full guide if necessary; an already-hidden result is not a tested close route.
    #>
    [CmdletBinding(DefaultParameterSetName='Session')]
    param([Parameter(Mandatory,Position=0,ParameterSetName='Session')]$Session,
        [Parameter(Mandatory,ParameterSetName='Receipt')][string]$ReceiptPath)
    if($PSCmdlet.ParameterSetName -eq 'Receipt'){
        $Session=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($ReceiptPath))
        if([IO.Path]::GetFullPath($ReceiptPath) -ine $Session.ReceiptPath){throw 'SG receipt path mismatch.'}
        $timeline=[Collections.Generic.List[object]]::new()
        foreach($entry in $Session.Timeline){$timeline.Add($entry)}
        $Session.Timeline=$timeline
    }
    Assert-PtSgFlowSession $Session
    $state=Get-PtShortcutGuidePresentation $Session.GuideTarget
    if($state.Kind -eq 'FullGuide' -and $Session.ActivationIssued){Close-PtShortcutGuide $Session -Route CloseButton|Out-Null}
    elseif($state.Kind -ne 'Hidden'){throw 'Owned SG surface is not a closable full guide; release owned hold input before cleanup.'}
    $Session.Last=Get-PtShortcutGuidePresentation $Session.GuideTarget
    $foreground=Wait-PtCondition -Description 'foreground after owned SG cleanup' -TimeoutSeconds 2 -Probe {
        try{Get-PtForegroundWindow}
        catch{if($_.Exception.Data['PtDesktopStatus'] -ne 'NoForeground'){throw}}
    }
    $owner=Get-Process -Id $foreground.ProcessId -ErrorAction Stop
    if($Session.ActivationIssued -and $owner.ProcessName -in 'SearchHost','StartMenuExperienceHost'){
        Restore-PtForegroundAfterShell -Hwnd $Session.ForegroundTarget.hwnd|Out-Null
    }
    $Session.Phase='RestoredHidden';Save-PtSgFlowSession $Session
    [pscustomobject]@{Hidden=($Session.Last.Kind -eq 'Hidden');CleanupOnly=$true;ReceiptPath=$Session.ReceiptPath}
}

function Invoke-PtShortcutGuideCycle {
    <# .SYNOPSIS
    Execute one explicit open/observe/close path; observation failures still close only the owned surface.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$ForegroundTarget,[Parameter(Mandatory)][string]$Workspace,
        [Parameter(Mandatory)][ValidateSet('NamedEvent','Chord')][string]$Entry,
        [Parameter(Mandatory)][ValidateSet('CloseButton','Escape','Chord')][string]$CloseRoute,
        [Parameter(Mandatory)][scriptblock]$Action,[object[]]$ArgumentList=@(),
        [ValidateRange(0.2,15)][double]$TimeoutSeconds=5)
    $session=$null;$original=$null
    try{
        $session=Open-PtShortcutGuide -ForegroundTarget $ForegroundTarget -Workspace $Workspace -Entry $Entry -TimeoutSeconds $TimeoutSeconds
        $active=Get-PtActiveVerificationAttempt
        $observed=if($active){
            @(Invoke-PtVerificationStep $active -Name 'Observe owned full guide' -Command 'Execute the supplied read/drive action on the owned full guide' `
                -Action $Action -ArgumentList (@($session)+$ArgumentList))
        }else{@(& $Action $session @ArgumentList)}
        if((Get-PtShortcutGuidePresentation $session.GuideTarget).Kind -ne 'FullGuide'){
            throw 'SG disappeared during the supplied observation; normal close was not attempted or credited.'
        }
        $closed=Close-PtShortcutGuide $session -Route $CloseRoute -TimeoutSeconds $TimeoutSeconds
        [pscustomobject]@{Entry=$Entry;CloseRoute=$CloseRoute;Session=$session;Observation=$observed;Close=$closed}
    }catch{
        $original=$_
        if($session){
            $original.Exception.Data['SgFlowReceipt']=$session.ReceiptPath
            $session.Failure=[pscustomobject]@{Stage='Cycle';Message=$original.Exception.Message}
            try{Save-PtSgFlowSession $session}catch{$original.Exception.Data['SgReceiptFailure']=$_.Exception.Message}
        }
        throw
    }
    finally{
        if($session){
            try{Restore-PtShortcutGuideSession $session|Out-Null}
            catch{
                if($original){$original.Exception.Data['SgCleanupFailure']=$_.Exception.Message;[Console]::Error.WriteLine($_.Exception.Message)}
                else{throw}
            }
        }
    }
}

function Invoke-PtShortcutGuideHold {
    <# .SYNOPSIS
    Keep one Windows key owned while a caller observes/drives the requested SG hold presentation.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$ForegroundTarget,[Parameter(Mandatory)][string]$Workspace,
        [Parameter(Mandatory)][ValidateSet('Indicators','FullGuide')][string]$Mode,
        [Parameter(Mandatory)][scriptblock]$Action,[object[]]$ArgumentList=@(),
        [ValidateSet(91,92)][int]$WindowsKey=91,[ValidateRange(0.2,15)][double]$TimeoutSeconds=5,[switch]$SkipRecording)
    $sgHoldAction=$Action;$sgHoldArguments=$ArgumentList
    $active=Get-PtActiveVerificationAttempt
    if($active -and -not $SkipRecording){
        $targetText=(ConvertTo-Json $ForegroundTarget -Compress).Replace("'","''")
        $actionText=$Action.ToString().Replace("'","''")
        $argsText=(ConvertTo-Json -InputObject $ArgumentList -Depth 20 -Compress).Replace("'","''")
        return Invoke-PtVerificationStep $active -Name "Hold SG $Mode with VK $WindowsKey" `
            -Command "Invoke-PtShortcutGuideHold -ForegroundTarget (ConvertFrom-PtReportJson '$targetText') -Workspace '$($Workspace.Replace("'","''"))' -Mode $Mode -WindowsKey $WindowsKey -TimeoutSeconds $TimeoutSeconds -Action ([scriptblock]::Create('$actionText')) -ArgumentList (ConvertFrom-PtReportJson '$argsText')" `
            -Implementation ${function:Invoke-PtShortcutGuideHold} -ArgumentList @($ForegroundTarget,$Workspace,$Mode,$WindowsKey,$TimeoutSeconds) -Action {
                param($target,$work,$presentation,$key,$timeout)
                Invoke-PtShortcutGuideHold -ForegroundTarget $target -Workspace $work -Mode $presentation -WindowsKey $key `
                    -TimeoutSeconds $timeout -Action $sgHoldAction -ArgumentList $sgHoldArguments -SkipRecording
            }
    }
    $session=New-PtSgFlowSession $ForegroundTarget $Workspace WindowsHold $Mode
    $expectedAction=if($Mode -eq 'Indicators'){1}else{2}
    if($session.Configuration.HoldAction -ne $expectedAction){throw 'Actual Hold Windows key mode differs from the requested flow; change/restore it explicitly through Settings.'}
    $heldFacts=@{Output=@()};$originalError=$null
    try{
        Assert-PtForegroundOrAbort -Hwnd $ForegroundTarget.hwnd
        $session.ActivationIssued=$true;$session.Phase='Holding';Save-PtSgFlowSession $session
        Invoke-PtHeldKeys -Hwnd $ForegroundTarget.hwnd -Keys @($WindowsKey) -KeyDownDelayMilliseconds 0 -Action {
            $session.Last=Wait-PtSgPresentation $session $Mode ($TimeoutSeconds+$session.Configuration.HoldMilliseconds/1000.0) $true
            $active=Get-PtActiveVerificationAttempt
            if($active){
                $heldFacts.Output=@(Invoke-PtVerificationStep $active -Name 'Observe SG while Windows is held' -Command 'Invoke the supplied held-observation action without releasing Windows' `
                    -Action $sgHoldAction -ArgumentList (@($session)+$sgHoldArguments))
            }else{$heldFacts.Output=@(& $sgHoldAction $session @sgHoldArguments)}
        }
        $expectedAfter=if($Mode -eq 'Indicators' -or $session.Configuration.CloseOnRelease){'Hidden'}else{'FullGuide'}
        $session.Last=Wait-PtSgPresentation $session $expectedAfter $TimeoutSeconds
        $session.Phase='Released';Save-PtSgFlowSession $session
        [pscustomobject]@{Session=$session;WindowsKey=$WindowsKey;AfterRelease=$session.Last;Output=$heldFacts.Output}
    }catch{
        $originalError=$_
        $originalError.Exception.Data['SgFlowReceipt']=$session.ReceiptPath
        $session.Failure=[pscustomobject]@{Stage='Hold';Message=$originalError.Exception.Message}
        try{Save-PtSgFlowSession $session}catch{$originalError.Exception.Data['SgReceiptFailure']=$_.Exception.Message}
        throw
    }
    finally{
        try{
            if(($Mode -eq 'Indicators' -or $session.Configuration.CloseOnRelease) -and
                (Get-PtShortcutGuidePresentation $session.GuideTarget).Kind -ne 'Hidden'){
                $session.Last=Wait-PtSgPresentation $session Hidden $TimeoutSeconds
            }
            Restore-PtShortcutGuideSession $session|Out-Null
        }
        catch{
            if($originalError){$originalError.Exception.Data['SgCleanupFailure']=$_.Exception.Message;[Console]::Error.WriteLine($_.Exception.Message)}
            else{throw}
        }
    }
}
