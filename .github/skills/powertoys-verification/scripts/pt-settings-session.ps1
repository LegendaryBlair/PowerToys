# Settings-specific UI state over canonical window identities. No Settings process creation/termination.
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
    param([Parameter(Mandatory)][long]$Hwnd)
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
    Wait-PtSettingsUiState $Hwnd|Out-Null
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
    param([Parameter(Mandatory)][long]$Hwnd,[Parameter(Mandatory)][string]$Workspace)
    $identity=Get-PtWindowIdentity $Hwnd
    $session=Get-PtActiveResourceSession
    if($session){
        Assert-PtResourceSession $session
        $existing=@($session.Settings|Where-Object {$_.Identity.hwnd -eq $Hwnd})
        if($existing.Count){
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
    Write-PtReportText $snapshot.Path (ConvertTo-Json $snapshot -Depth 20)
    Register-PtSettingsObligation $snapshot
    $snapshot
}

function Set-PtSettingsUiState {
    param([Parameter(Mandatory)][long]$Hwnd,[Parameter(Mandatory)]$State)
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
    foreach($item in $State.Scroll){
        $pattern=(Element $item.Id).GetCurrentPattern([Windows.Automation.ScrollPattern]::Pattern)
        if($pattern.Current.HorizontalScrollPercent -ne $item.Horizontal -or $pattern.Current.VerticalScrollPercent -ne $item.Vertical){
            $pattern.SetScrollPercent($item.Horizontal,$item.Vertical)
        }
    }
}

function Restore-PtSettingsUiSnapshot {
    param([Parameter(Mandatory)]$Snapshot)
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
    Assert-PtWindowIdentity $Snapshot.Identity
    $failure=$null
    try{
        # Restore original layout before applying scroll percentages. WinUI may unload its
        # automation subtree while minimized, so observe while surfaced, then re-minimize.
        Restore-PtWindowSnapshot $Snapshot.Native|Out-Null
        Show-PtSettingsForObservation $Snapshot.Identity.hwnd
        $current=Wait-PtSettingsUiState $Snapshot.Identity.hwnd
        if((ConvertTo-Json $current -Depth 15 -Compress) -cne (ConvertTo-Json $Snapshot.Ui -Depth 15 -Compress)){
            Set-PtSettingsUiState -Hwnd $Snapshot.Identity.hwnd -State $Snapshot.Ui
            $current=Wait-PtCondition -Description 'Original Settings expansion and scroll readback' -TimeoutSeconds 5 -Probe {
                $actual=Read-PtSettingsUiState $Snapshot.Identity.hwnd -AllowUnselected
                if($actual -and (ConvertTo-Json $actual -Depth 15 -Compress) -ceq (ConvertTo-Json $Snapshot.Ui -Depth 15 -Compress)){$actual}
            }
        }
    }catch{$failure=$_}
    try{$placement=Restore-PtWindowSnapshot -Snapshot $Snapshot.Native}
    catch{
        if($failure){$failure.Exception.Data['PlacementRestorationFailure']=$_.Exception.Message}
        else{$failure=$_}
    }
    if($failure){throw $failure}
    $receiptPath="$($Snapshot.Path).restored-$([guid]::NewGuid().ToString('N')).json"
    $receipt=[pscustomobject]@{Restored=$true;Scope=$Snapshot.Scope;UnsupportedState=$Snapshot.UnsupportedState;Path=$receiptPath
        Identity=$Snapshot.Identity;Ui=$current;Native=$placement}
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
