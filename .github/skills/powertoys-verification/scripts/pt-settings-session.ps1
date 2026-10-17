# Settings-specific UI state over canonical identities, with explicit Runner-restart handover.
foreach($dependency in 'pt-ui-observation','pt-state-snapshot','pt-foreground-guard'){. "$PSScriptRoot\$dependency.ps1"}

function Get-PtSettingsAutomationRoot {
    param([Parameter(Mandatory)][long]$Hwnd)
    Initialize-PtUiAutomation
    [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Hwnd)
}

function Get-PtSettingsUiElements {
    param([Parameter(Mandatory)][long]$Hwnd)
    $identity=Get-PtWindowIdentity $Hwnd
    for($attempt=0;$attempt -lt 3;$attempt++){
        Assert-PtWindowIdentity $identity
        try{
            $root=Get-PtSettingsAutomationRoot $Hwnd
            return @($root.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition))
        }catch{
            if($_.Exception.GetBaseException() -isnot [Windows.Automation.ElementNotAvailableException] -or $attempt -eq 2){throw}
            Write-Warning 'Settings UIA provider was replaced; reacquiring the same HWND for a read-only observation.'
            Start-Sleep -Milliseconds 100
        }
    }
}

function Read-PtSettingsUiState {
    param([Parameter(Mandatory)][long]$Hwnd,[switch]$AllowUnselected)
    $elements=@(Get-PtSettingsUiElements $Hwnd)
    $selected=@();$expand=@();$scroll=@();$unsupported=@()
    foreach($element in $elements){
        $id=$element.Current.AutomationId
        $pattern=$null
        if($id -like '*NavItem'){
            if($element.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern,[ref]$pattern) -and $pattern.Current.IsSelected){
                $selected+=@($id)
            }
        }
        $pattern=$null
        if($element.TryGetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern,[ref]$pattern) -and
                $pattern.Current.ExpandCollapseState -in [Windows.Automation.ExpandCollapseState]::Expanded,[Windows.Automation.ExpandCollapseState]::Collapsed){
            if($id){
                $expand+=@([pscustomobject]@{Id=$id;State=$pattern.Current.ExpandCollapseState.ToString()})
            }else{$unsupported+=@('Unnamed expansion control')}
        }
        $pattern=$null
        if($element.TryGetCurrentPattern([Windows.Automation.ScrollPattern]::Pattern,[ref]$pattern)){
            if($id){
                $scroll+=@([pscustomobject]@{Id=$id;Horizontal=$pattern.Current.HorizontalScrollPercent;Vertical=$pattern.Current.VerticalScrollPercent})
            }else{$unsupported+=@('Unnamed scroll control')}
        }
    }
    if($AllowUnselected -and $selected.Count -eq 0){return}
    if($selected.Count -ne 1){throw "Cannot capture one selected Settings navigation page (found $($selected.Count)); no navigation permitted."}
    foreach($list in @(@{Values=$expand;Kind='expansion'},@{Values=$scroll;Kind='scroll'})){
        if(@($list.Values|Group-Object Id|Where-Object Count -ne 1).Count){throw "Ambiguous Settings $($list.Kind) control IDs."}
    }
    [pscustomobject]@{PageAutomationId=$selected[0];Expansion=@($expand|Sort-Object Id);Scroll=@($scroll|Sort-Object Id)
        UnsupportedControls=@($unsupported)}
}

function Wait-PtSettingsUiState {
    param([Parameter(Mandatory)][long]$Hwnd)
    Wait-PtCondition -Description 'Settings navigation provider readiness' -TimeoutSeconds 5 -Probe {
        Read-PtSettingsUiState $Hwnd -AllowUnselected
    }
}

function Show-PtSettingsForObservation {
    param([Parameter(Mandatory)][long]$Hwnd,[switch]$RevealNavigation)
    $native=Get-PtWindowSnapshot $Hwnd
    if(-not $native.visible -or $native.placement.showCmd -in 2,6,7,11){
        $show=if(($native.placement.flags -band 2) -and $native.placement.showCmd -in 2,6,7,11){3}else{9}
        [void][PtDesktop]::ShowWindow([IntPtr]$Hwnd,$show)
    }
    Wait-PtCondition -Description 'Settings visible and not minimized' -TimeoutSeconds 5 -Probe {
        $window=Get-PtNativeWindow -Hwnd $Hwnd
        $window.Visible -and -not $window.Minimized
    }|Out-Null
    Assert-PtForegroundOrAbort -Hwnd $Hwnd
    if($RevealNavigation -and -not (Read-PtSettingsUiState $Hwnd -AllowUnselected)){
        $button=Resolve-PtUiElement -Hwnd $Hwnd -AutomationId PART_PaneButton -ControlType Button
        $button.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
    }
    Wait-PtSettingsUiState $Hwnd|Out-Null
}

function Test-PtSettingsUiStateMatch {
    param([Parameter(Mandatory)]$Expected,[Parameter(Mandatory)]$Actual,[switch]$AllowWinUiFloatReadback)
    $expectedText=ConvertTo-Json $Expected -Depth 20 -Compress
    if((ConvertTo-Json $Actual -Depth 20 -Compress) -ceq $expectedText){return $true}
    if(-not $AllowWinUiFloatReadback -or $Expected.Scroll.Count -ne $Actual.Scroll.Count){return $false}
    $wire=ConvertFrom-PtReportJson $expectedText
    for($index=0;$index -lt $wire.Scroll.Count;$index++){
        if($wire.Scroll[$index].Id -cne $Actual.Scroll[$index].Id){return $false}
        foreach($axis in 'Horizontal','Vertical'){
            $requested=$Expected.Scroll[$index].$axis
            $observed=$Actual.Scroll[$index].$axis
            if($requested -isnot [double] -and $requested -isnot [int] -and $requested -isnot [long]){return $false}
            if($observed -ne $requested -and $observed -ne [double][single]$requested){return $false}
            $wire.Scroll[$index].$axis=$observed
        }
    }
    (ConvertTo-Json $Actual -Depth 20 -Compress) -ceq (ConvertTo-Json $wire -Depth 20 -Compress)
}

function Wait-PtSettingsScrollLayout {
    param([Parameter(Mandatory)][long]$Hwnd)
    $settled=@{Signature=$null;Count=0}
    Wait-PtCondition -Description 'Settings scroll viewport and extent settlement' -TimeoutSeconds 5 -PollMilliseconds 100 -Probe {
        $metrics=@(foreach($element in Get-PtSettingsUiElements $Hwnd){
            $pattern=$null
            if($element.Current.AutomationId -and $element.TryGetCurrentPattern([Windows.Automation.ScrollPattern]::Pattern,[ref]$pattern)){
                [pscustomobject]@{Id=$element.Current.AutomationId;Width=$element.Current.BoundingRectangle.Width
                    Height=$element.Current.BoundingRectangle.Height;Horizontal=$pattern.Current.HorizontalViewSize;Vertical=$pattern.Current.VerticalViewSize}
            }
        })
        $signature=ConvertTo-Json -InputObject @($metrics|Sort-Object Id) -Compress
        if($metrics.Count -and $signature -ceq $settled.Signature){$settled.Count++}else{$settled.Count=1;$settled.Signature=$signature}
        $settled.Count -ge 3
    }|Out-Null
}

function Get-PtSettingsCurrentState {
    <#.SYNOPSIS
    Observe fresh UI state, explicitly surfacing minimized Settings and restoring desktop/native state.
    #>
    param([Parameter(Mandatory)][long]$Hwnd,[switch]$AllowTemporaryRestore)
    $native=Get-PtWindowSnapshot $Hwnd
    $surface=-not $native.visible -or $native.placement.showCmd -in 2,6,7,11
    if($surface -and -not $AllowTemporaryRestore){throw 'Minimized/hidden Settings needs explicit temporary restoration for a fresh UI observation.'}
    $desktop=$null;$failure=$null;$ui=$null
    try{
        if($surface){
            $desktop=Get-PtDesktopSnapshot
            Show-PtSettingsForObservation $Hwnd
        }
        $ui=Wait-PtSettingsUiState $Hwnd
        Assert-PtWindowIdentity $native.identity
    }catch{$failure=$_}
    finally{
        if($desktop){
            try{Restore-PtWindowSnapshot $native|Out-Null}
            catch{if($failure){$failure.Exception.Data['SettingsNativeRestoreFailure']=$_.Exception.Message}else{$failure=$_}}
            try{Restore-PtDesktopSnapshot $desktop|Out-Null}
            catch{if($failure){$failure.Exception.Data['SettingsDesktopRestoreFailure']=$_.Exception.Message}else{$failure=$_}}
        }
    }
    if($failure){throw $failure}
    [pscustomobject]@{Native=$native;Ui=$ui}
}

function Get-PtSettingsUiSnapshot {
    <#.SYNOPSIS
    Capture the borrowed Settings window before navigation, preserving only explicitly supported state.
    #>
    param([Parameter(Mandatory)][long]$Hwnd,[Parameter(Mandatory)][string]$Workspace,[switch]$AllowRunnerRestart)
    $identity=Get-PtWindowIdentity $Hwnd
    $session=Get-PtActiveResourceSession
    if($session){
        Assert-PtResourceSession $session
        $planned=@($session.ResourcePlan.Resources|Where-Object {$_.Kind -eq 'Settings' -and $_.Hwnd -eq $Hwnd})
        if($AllowRunnerRestart -and $planned.Count -eq 1 -and $planned[0].AllowRunnerRestart -ne $true){
            throw 'Settings restart permission must agree with the original resource plan.'
        }
        $existing=@($session.Settings|Where-Object {$_.Identity.hwnd -eq $Hwnd})
        if($existing.Count){
            if($AllowRunnerRestart -and -not $existing[0].AllowRunnerRestart){
                throw 'A same-instance Settings baseline cannot become restartable after capture.'
            }
            if($existing[0].Hash -cne (Get-PtReportHash ([IO.File]::ReadAllBytes($existing[0].Path)))){
                throw 'Settings original snapshot changed.'
            }
            $original=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($existing[0].Path))
            Assert-PtWindowIdentity $original.Identity
            return $original
        }
    }
    $current=Get-PtSettingsCurrentState $Hwnd -AllowTemporaryRestore
    $native=$current.Native;$ui=$current.Ui
    Assert-PtWindowIdentity $identity
    if(Get-PtActiveResourceSession){Register-PtBorrowedWindow $identity|Out-Null}
    $snapshot=[pscustomobject]@{
        Schema='PtSettingsUi.v1';Identity=$identity;Native=$native;Ui=$ui
        Scope=@('WindowIdentity','Placement','Visibility','SelectedPage','NamedExpansion','NamedScrollPatterns')
        UnsupportedState=@('IME composition/conversion','Keyboard focus','Unsaved page drafts','Unexposed scroll state')+@($ui.UnsupportedControls)
        Path=Join-Path $Workspace "settings-ui-$([guid]::NewGuid().ToString('N')).json"
    }
    if($AllowRunnerRestart){
        if(-not $session){throw 'Restartable Settings requires an active resource session.'}
        $process=Get-PtResourceProcessIdentity -ProcessId $identity.processId
        if(-not $process -or [IO.Path]::GetFileName($process.path) -ine 'PowerToys.Settings.exe'){
            throw 'Restartable Settings must belong to the actual Settings executable.'
        }
        $snapshot|Add-Member NoteProperty AllowRunnerRestart $true
        $snapshot|Add-Member NoteProperty Process $process
    }
    Write-PtReportText $snapshot.Path (ConvertTo-Json $snapshot -Depth 20)
    Register-PtSettingsObligation $snapshot
    $snapshot
}

function Set-PtSettingsUiState {
    param([Parameter(Mandatory)][long]$Hwnd,[Parameter(Mandatory)]$State,[switch]$DeferScroll)
    function Element([string]$Id){
        Wait-PtCondition -Description "realized Settings control $Id" -TimeoutSeconds 5 -Probe {
            $matches=@((Get-PtSettingsUiElements $Hwnd)|Where-Object {$_.Current.AutomationId -ceq $Id})
            if($matches.Count){Select-PtUniqueUiElement -Elements $matches -Description "Settings $Id"}
        }
    }
    foreach($item in @($State.Scroll|Where-Object Id -IN 'MenuItemsScrollViewer','FooterItemsScrollViewer')){
        $scroll=(Element $item.Id).GetCurrentPattern([Windows.Automation.ScrollPattern]::Pattern)
        if($scroll.Current.VerticalScrollPercent -ge 0 -and $item.Vertical -ge 0 -and
            $scroll.Current.VerticalScrollPercent -ne $item.Vertical){$scroll.SetScrollPercent(-1,$item.Vertical)}
    }
    foreach($item in @($State.Expansion|Where-Object {$_.Id -like '*NavItem' -and $_.State -eq 'Expanded'})){
        $pattern=(Element $item.Id).GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern)
        if($pattern.Current.ExpandCollapseState -ne [Windows.Automation.ExpandCollapseState]::Expanded){$pattern.Expand()}
    }
    $page=Element $State.PageAutomationId
    $select=$page.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern)
    if(-not $select.Current.IsSelected){$select.Select()}
    Wait-PtCondition -Description 'Original Settings page selected' -TimeoutSeconds 5 -Probe {
        (Read-PtSettingsUiState $Hwnd -AllowUnselected).PageAutomationId -ceq $State.PageAutomationId
    }|Out-Null
    foreach($item in @($State.Expansion|Where-Object {$_.Id -notlike '*NavItem' -and $_.State -eq 'Expanded'})){
        $pattern=(Element $item.Id).GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern)
        if($pattern.Current.ExpandCollapseState -ne [Windows.Automation.ExpandCollapseState]::Expanded){$pattern.Expand()}
    }
    foreach($item in @($State.Expansion|Where-Object State -eq 'Collapsed')){
        $pattern=(Element $item.Id).GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern)
        if($pattern.Current.ExpandCollapseState -ne [Windows.Automation.ExpandCollapseState]::Collapsed){$pattern.Collapse()}
    }
    if(-not $DeferScroll){Set-PtSettingsScrollState -Hwnd $Hwnd -Scroll $State.Scroll|Out-Null}
}

function Set-PtSettingsScrollState {
    param([Parameter(Mandatory)][long]$Hwnd,[object[]]$Scroll)
    if(-not $Scroll.Count){return}
    Wait-PtSettingsScrollLayout $Hwnd
    foreach($item in $Scroll){
        $matches=@((Get-PtSettingsUiElements $Hwnd)|Where-Object {$_.Current.AutomationId -ceq $item.Id})
        $element=Select-PtUniqueUiElement -Elements $matches -Description "Settings $($item.Id)"
        $pattern=$element.GetCurrentPattern([Windows.Automation.ScrollPattern]::Pattern)
        if($pattern.Current.HorizontalScrollPercent -ne $item.Horizontal -or $pattern.Current.VerticalScrollPercent -ne $item.Vertical){
            $before=[pscustomobject]@{HorizontalView=$pattern.Current.HorizontalViewSize;VerticalView=$pattern.Current.VerticalViewSize}
            $pattern.SetScrollPercent($item.Horizontal,$item.Vertical)
            Wait-PtSettingsScrollLayout $Hwnd
            $after=[pscustomobject]@{HorizontalView=$pattern.Current.HorizontalViewSize;VerticalView=$pattern.Current.VerticalViewSize}
            $changed=(ConvertTo-Json $before -Compress) -cne (ConvertTo-Json $after -Compress)
            if($changed){
                # A newly realized extent changes the meaning of a percentage; apply once to that observed layout.
                $pattern.SetScrollPercent($item.Horizontal,$item.Vertical)
                Wait-PtSettingsScrollLayout $Hwnd
            }
            [pscustomobject]@{Id=$item.Id;Before=$before;After=$after;ReappliedForChangedExtent=$changed
                Horizontal=$pattern.Current.HorizontalScrollPercent;Vertical=$pattern.Current.VerticalScrollPercent}
        }
    }
}

function Get-PtSettingsRestorationSnapshot {
    <#.SYNOPSIS
    Resolve an explicitly authorized replacement without rewriting the original baseline.
    #>
    param([Parameter(Mandatory)]$Snapshot,$ReplacementIdentity)
    $session=Get-PtActiveResourceSession
    $record=@($session.Settings|Where-Object Path -CEQ $Snapshot.Path)
    if(-not $ReplacementIdentity -and $record.Count -eq 1){$ReplacementIdentity=$record[0].ReplacementIdentity}
    if(-not $ReplacementIdentity){return $Snapshot}
    if(-not $session -or $record.Count -ne 1 -or -not $Snapshot.AllowRunnerRestart -or
        -not $record[0].AllowRunnerRestart -or -not $record[0].RestartAuthorization){
        throw 'Settings replacement requires original opt-in and a recorded Restart-PtRunner transition.'
    }
    Assert-PtResourceSession $session
    if($record[0].Hash -cne (Get-PtReportHash ([IO.File]::ReadAllBytes($Snapshot.Path)))){
        throw 'Settings original snapshot changed.'
    }
    if($record[0].ReplacementIdentity -and
        (ConvertTo-Json $record[0].ReplacementIdentity -Compress) -ceq (ConvertTo-Json $ReplacementIdentity -Compress)){
        Assert-PtWindowIdentity $ReplacementIdentity
    }else{
        Assert-PtRestartedWindowIdentity $Snapshot.Identity $Snapshot.Process $record[0].RestartAuthorization $ReplacementIdentity
    }
    $effective=ConvertFrom-PtReportJson (ConvertTo-Json $Snapshot -Depth 20)
    $effective.Identity=$ReplacementIdentity;$effective.Native.identity=$ReplacementIdentity
    $effective.Scope=@($Snapshot.Scope|Where-Object {$_ -cne 'WindowIdentity'})+@('AuthorizedReplacementIdentity')
    $effective
}

function Restore-PtSettingsUiSnapshot {
    param([Parameter(Mandatory)]$Snapshot,$ReplacementIdentity)
    $session=Get-PtActiveResourceSession
    if($session){
        Assert-PtResourceSession $session
        $registered=@($session.Settings|Where-Object Path -CEQ $Snapshot.Path)
        if($registered.Count -ne 1 -or
            $registered[0].Hash -cne (Get-PtReportHash ([IO.File]::ReadAllBytes($Snapshot.Path)))){
            throw 'Settings original snapshot changed or is not registered.'
        }
    }
    $stored=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($Snapshot.Path))
    if($stored.Schema -cne 'PtSettingsUi.v1' -or
        (ConvertTo-Json $stored -Depth 20 -Compress) -cne (ConvertTo-Json $Snapshot -Depth 20 -Compress)){
        throw 'Settings baseline changed; refusing restoration.'
    }
    $Snapshot=Get-PtSettingsRestorationSnapshot -Snapshot $Snapshot -ReplacementIdentity $ReplacementIdentity
    if($ReplacementIdentity){
        $registered[0].ReplacementIdentity=$ReplacementIdentity
        $registered[0].Restored=$false
        Save-PtResourceSession $session
    }
    Assert-PtWindowIdentity $Snapshot.Identity
    $winUi=$Snapshot.Identity.className -ceq 'WinUIDesktopWin32WindowClass'
    $normalFinal=$Snapshot.Native.visible -and $Snapshot.Native.placement.showCmd -notin 2,6,7,11
    $placement=Get-PtWindowSnapshot $Snapshot.Identity.hwnd
    $alreadyRestored=$false
    if($normalFinal -and (ConvertTo-Json $placement -Depth 20 -Compress) -ceq (ConvertTo-Json $Snapshot.Native -Depth 20 -Compress)){
        $current=Read-PtSettingsUiState $Snapshot.Identity.hwnd -AllowUnselected
        $alreadyRestored=$current -and (Test-PtSettingsUiStateMatch -Expected $Snapshot.Ui -Actual $current -AllowWinUiFloatReadback:$winUi)
    }
    $scrollTransitions=@()
    $failure=$null
    if(-not $alreadyRestored){try{
        # Restore original layout before applying scroll percentages. WinUI may unload its
        # automation subtree while minimized, so observe while surfaced, then re-minimize.
        Restore-PtWindowSnapshot $Snapshot.Native|Out-Null
        Show-PtSettingsForObservation $Snapshot.Identity.hwnd -RevealNavigation:($Snapshot.Scope -contains 'AuthorizedReplacementIdentity')
        $current=Wait-PtSettingsUiState $Snapshot.Identity.hwnd
        if(-not (Test-PtSettingsUiStateMatch -Expected $Snapshot.Ui -Actual $current -AllowWinUiFloatReadback:$winUi)){
            Set-PtSettingsUiState -Hwnd $Snapshot.Identity.hwnd -State $Snapshot.Ui -DeferScroll:$normalFinal
            if(-not $normalFinal){
                $current=Wait-PtCondition -Description 'Original Settings expansion and scroll readback' -TimeoutSeconds 5 -Probe {
                    $actual=Read-PtSettingsUiState $Snapshot.Identity.hwnd -AllowUnselected
                    if($actual -and (Test-PtSettingsUiStateMatch -Expected $Snapshot.Ui -Actual $actual -AllowWinUiFloatReadback:$winUi)){$actual}
                }
            }
        }
    }catch{$failure=$_}
    try{$placement=Restore-PtWindowSnapshot -Snapshot $Snapshot.Native}
    catch{
        if($failure){$failure.Exception.Data['PlacementRestorationFailure']=$_.Exception.Message}
        else{$failure=$_}
    }
    if($failure){throw $failure}
    if($normalFinal){
        # Final placement can change the viewport; replay percentages only after that transition.
        $current=Read-PtSettingsUiState $Snapshot.Identity.hwnd
        if(-not (Test-PtSettingsUiStateMatch -Expected $Snapshot.Ui -Actual $current -AllowWinUiFloatReadback:$winUi)){
            $scrollTransitions=@(Set-PtSettingsScrollState -Hwnd $Snapshot.Identity.hwnd -Scroll $Snapshot.Ui.Scroll)
        }
        $current=Wait-PtCondition -Description 'final-layout Settings state readback' -TimeoutSeconds 5 -Probe {
            $actual=Read-PtSettingsUiState $Snapshot.Identity.hwnd -AllowUnselected
            if($actual -and (Test-PtSettingsUiStateMatch -Expected $Snapshot.Ui -Actual $actual -AllowWinUiFloatReadback:$winUi)){$actual}
        }
    }}
    $receiptPath="$($Snapshot.Path).restored-$([guid]::NewGuid().ToString('N')).json"
    $receipt=[pscustomobject]@{Restored=$true;Scope=$Snapshot.Scope;UnsupportedState=$Snapshot.UnsupportedState;Path=$receiptPath
        Identity=$Snapshot.Identity;Ui=$current;Native=$placement;ScrollTransitions=@($scrollTransitions)
        ScrollComparison=$(if($winUi){'Exact or exact float32 command readback; original raw percentages retained'}else{'Exact'})}
    Write-PtReportText $receiptPath (ConvertTo-Json $receipt -Depth 20)
    Complete-PtSettingsObligation $Snapshot $receiptPath
    $receipt
}

function Invoke-PtSettingsScope {
    <#.SYNOPSIS
    Borrow Settings for one recorded action and verify its supported original UI state in finally.
    #>
    param([Parameter(Mandatory)][long]$Hwnd,[Parameter(Mandatory)][string]$Workspace,
        [Parameter(Mandatory)][scriptblock]$Action,[object[]]$ArgumentList=@())
    $snapshot=Get-PtSettingsUiSnapshot -Hwnd $Hwnd -Workspace $Workspace
    $failure=$null;$output=@()
    try{$output=@(& $Action $snapshot.Identity @ArgumentList)}
    catch{$failure=$_}
    finally{
        try{
            $restored=Restore-PtSettingsUiSnapshot $snapshot
        }catch{
            if($failure){$failure.Exception.Data['SettingsRestorationFailure']=$_.Exception.Message}
            else{$failure=$_}
        }
    }
    if($failure){throw $failure}
    [pscustomobject]@{Output=$output;Restoration=$restored;ReceiptPath=$restored.Path}
}
