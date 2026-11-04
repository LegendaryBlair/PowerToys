#requires -Version 7.2
# Compositions for the finite desktop-case recipe; no operations occur on import.
. "$PSScriptRoot\pt-fancyzones-driver.ps1"
. "$PSScriptRoot\pt-taskbar-fixture.ps1"
. "$PSScriptRoot\pt-shell-transition.ps1"
. "$PSScriptRoot\pt-owned-capture.ps1"
if(-not ('PtFancyZonesCaption' -as [type])){
    Add-Type @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class PtFancyZonesCaption {
    [DllImport("user32.dll",SetLastError=true)]
    static extern IntPtr SendMessageTimeoutW(IntPtr window,uint message,IntPtr w,IntPtr l,uint flags,uint timeout,out IntPtr result);
    public static long Hit(long window,int x,int y) {
        IntPtr result;
        if(SendMessageTimeoutW(new IntPtr(window),0x84,IntPtr.Zero,new IntPtr((y<<16)|(x&0xffff)),3,1000,out result)==IntPtr.Zero)
            throw new Win32Exception();
        return result.ToInt64();
    }
}
'@
}

function Set-PtFancyZonesCaseOption {
    param([Parameter(Mandatory)][string]$Option,[Parameter(Mandatory)][bool]$Value)
    $map=@{
        Shift=@('FancyZonesShiftDragCheckBoxControlHeader','fancyzones_shiftDrag')
        Mouse=@('FancyZonesMouseDragCheckBoxControlHeader','fancyzones_mouseSwitch')
        ShowAll=@('FancyZonesShowZonesOnAllMonitorsCheckBoxControl','fancyzones_show_on_all_monitors')
        Transparent=@('FancyZonesMakeDraggedWindowTransparentCheckBoxControl','fancyzones_makeDraggedWindowTransparent')
        Relayout=@('FancyZonesZoneSetChangeMoveWindows','fancyzones_zoneSetChange_moveWindows')
        History=@('FancyZonesAppLastZoneMoveWindows','fancyzones_appLastZone_moveWindows')
        ActiveMonitor=@('FancyZonesOpenWindowOnActiveMonitor','fancyzones_openWindowOnActiveMonitor')
        Switching=@('FancyZonesWindowSwitchingGroupSettings','fancyzones_windowSwitching')
        Override=@('FancyZonesOverrideSnapHotkeys','fancyzones_overrideSnapHotkeys')
        Across=@('FancyZonesMoveWindowsAcrossAllMonitorsCheckBoxControl','fancyzones_moveWindowAcrossMonitors')
        Quick=@('FancyZonesQuickLayoutSwitch','fancyzones_quickLayoutSwitch')
        Flash=@('FancyZonesFlashZonesOnQuickSwitch','fancyzones_flashZonesOnQuickSwitch')
    }
    if(-not $map.ContainsKey($Option)){throw 'Unknown module option.'}
    $mapping=$map[$Option]
    $current=Get-PtFancyZonesSnapshotJson $FzCase.Driver.ExpectedModule 'settings.json'
    $property=$current.properties.PSObject.Properties[$mapping[1]]
    if(-not $property -or $property.Value.value -isnot [bool]){throw "Expected Boolean setting is unavailable: $Option"}
    if($property.Value.value -eq $Value){
        $actual=ConvertFrom-PtReportJson (Read-PtSharedFileText "$($FzCase.Driver.ModuleRoot)\settings.json")
        if(-not(Test-PtFancyZonesJsonEqual $current $actual)){throw 'No-op setting read found an external change.'}
        return
    }
    Set-PtFancyZonesBoolean -Context $FzCase.Driver -ContainerId $mapping[0] -SettingKey $mapping[1] -Value $Value|Out-Null
}

function Invoke-PtFancyZonesCaseTaskView {
    param([Parameter(Mandatory)]$Target,[Parameter(Mandatory)][scriptblock]$Action,
        [object[]]$ArgumentList=@(),[string]$Title='Task View')
    if($FzCase.TaskView -and $FzCase.TaskView.State -cne 'Closed'){
        throw 'An earlier Task View transition is unresolved.'
    }
    $transition=$null
    try {
        Invoke-PtTaskViewScope -TargetIdentity $Target -Transition ([ref]$transition) `
            -Action $Action -ArgumentList $ArgumentList -Title $Title
    } finally {
        $FzCase.TaskView=$transition
        Save-Private 'task-view-transition.json' $transition
    }
}

function Set-PtFancyZonesCasePositionMode {
    param([Parameter(Mandatory)][bool]$Relative)
    $scope=New-PtFancyZonesDriverScope $FzCase.Driver
    $scope.SettingKeys=@('fancyzones_moveWindowsBasedOnPosition')
    $scope.WorkAreas=@()
    Invoke-PtFancyZonesDriverAction -Context $FzCase.Driver -Scope $scope -ArgumentList @($Relative) -Action {
        param($requested)
        $container=Show-Setting FancyZonesOverrideSnapHotkeys
        $buttons=@($container.FindAll([Windows.Automation.TreeScope]::Descendants,
            [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::Button)))
        foreach($button in $buttons){
            $expander=$null
            if($button.TryGetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern,[ref]$expander) -and
                $expander.Current.ExpandCollapseState -eq 'Collapsed'){$expander.Expand()}
        }
        $group=Show-Setting FancyZonesMoveWindow
        $combo=Select-PtUniqueUiElement -Description 'movement-mode ComboBox' -Elements @(
            $group.FindAll([Windows.Automation.TreeScope]::Descendants,
                [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::ComboBox)))
        $expansion=$combo.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern)
        $expansion.Expand()
        try {
            $items=@(Wait-PtCondition -Description 'two realized movement modes' -TimeoutSeconds 4 -Probe {
                $options=@($combo.FindAll([Windows.Automation.TreeScope]::Descendants,
                    [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::ListItem)))
                if($options.Count -eq 2){$options}
            })
            $items[[int]$requested].GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select()
        } finally {$expansion.Collapse()}
        Wait-PtCondition -Description 'movement mode persistence' -TimeoutSeconds 5 -Probe {
            $settings=ConvertFrom-PtReportJson (Read-PtSharedFileText "$($FzCase.Driver.ModuleRoot)\settings.json")
            $settings.properties.fancyzones_moveWindowsBasedOnPosition.value -eq $requested
        }|Out-Null
    }|Out-Null
}

function Invoke-PtFancyZonesCaseButton {
    param([Parameter(Mandatory)][string]$AutomationId)
    $element=Resolve-PtUiElement -Hwnd $FzCase.Driver.Editor.hwnd -AutomationId $AutomationId -ControlType Button
    $element.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
}

function Open-PtFancyZonesCaseLayoutProperties {
    param([Parameter(Mandatory)][string]$Name)
    Open-PtFancyZonesEditor $FzCase.Driver|Out-Null
    $button=Resolve-PtUiElement -Hwnd $FzCase.Driver.Editor.hwnd -Name $Name -ControlType Button
    if($button.Current.AutomationId -cne 'EditLayoutButton'){throw 'Named element is not the expected layout edit control.'}
    $button.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
    Wait-PtCondition -Description 'layout properties save control' -TimeoutSeconds 5 -Probe {
        $root=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$FzCase.Driver.Editor.hwnd)
        $buttons=@($root.FindAll([Windows.Automation.TreeScope]::Descendants,
            [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,'PrimaryButton'))|
            Where-Object {-not $_.Current.IsOffscreen})
        if($buttons.Count -eq 1){$buttons[0]}
    }|Out-Null
}

function Save-PtFancyZonesDefaultEvidence {
    param([Parameter(Mandatory)]$Attempt,[Parameter(Mandatory)][string]$LayoutId,
        [Parameter(Mandatory)][ValidateSet('Horizontal','Vertical')][string]$Orientation)
    if($LayoutId -cnotin $FzCase.Driver.LayoutIds){throw 'Default observation requires a creation-owned custom layout.'}
    $layouts=Get-PtFancyZonesSnapshotJson $FzCase.Driver.ExpectedModule 'custom-layouts.json'
    $layout=@($layouts.'custom-layouts'|Where-Object uuid -CEQ $LayoutId)
    if($layout.Count -ne 1){throw 'Owned layout identity is not unique.'}
    Open-PtFancyZonesCaseLayoutProperties $layout[0].name
    try {
        $selectedId="${Orientation}DefaultLayoutButton"
        $unselectedId="SetLayoutAs${Orientation}DefaultButton"
        $root=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$FzCase.Driver.Editor.hwnd)
        $buttons=@($root.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|
            Where-Object {$_.Current.ControlType -eq [Windows.Automation.ControlType]::Button -and
                $_.Current.AutomationId -cin @($selectedId,$unselectedId) -and -not $_.Current.IsOffscreen})
        $button=Select-PtUniqueUiElement -Elements $buttons -Description "actual $Orientation default state"
        $ancestor=$button
        while($ancestor){
            $scroll=$null
            if($ancestor.TryGetCurrentPattern([Windows.Automation.ScrollPattern]::Pattern,[ref]$scroll) -and $scroll.Current.VerticallyScrollable){
                $scroll.SetScrollPercent(-1,100)
                break
            }
            $ancestor=[Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($ancestor)
        }
        $viewportReadiness=@{Signature=$null;Stable=0}
        Wait-PtCondition -Description 'complete default control inside its viewport' -TimeoutSeconds 5 -Probe {
            $bounds=$button.Current.BoundingRectangle
            $clipped=@(Get-PtControlViewportBounds -Element $button -WindowIdentity $FzCase.Driver.Editor|
                Where-Object {$bounds.Left -lt $_.Left -or $bounds.Top -lt $_.Top -or $bounds.Right -gt $_.Right -or $bounds.Bottom -gt $_.Bottom})
            $signature="$($bounds.Left),$($bounds.Top),$($bounds.Right),$($bounds.Bottom)"
            if(-not $button.Current.IsOffscreen -and $clipped.Count -eq 0){
                if($signature -ceq $viewportReadiness.Signature){$viewportReadiness.Stable++}else{$viewportReadiness.Stable=1}
            }else{$viewportReadiness.Stable=0}
            $viewportReadiness.Signature=$signature
            $viewportReadiness.Stable -ge 2
        }|Out-Null
        $path=New-PtVerificationArtifactPath -Attempt $Attempt -Name "default-$Orientation.png"
        Save-PtOwnedControlScreenshot -Path $path -WindowIdentity $FzCase.Driver.Editor -Element $button `
            -OpaqueBackgroundIdentity $FzCase.Driver.Editor|Out-Null
        $image=Add-PtVerificationArtifact -Attempt $Attempt -Path $path -Kind Screenshot -Description "Exact $Orientation default control; not Save/Cancel or layout-creation controls"
        $state=Add-PtVerificationArtifact -Attempt $Attempt -Path "$path.state.json" -Kind Evidence -Description 'Control runtime identity and complete pre/post capture bounds'
        [pscustomobject]@{Selected=($button.Current.AutomationId -ceq $selectedId);ControlId=$button.Current.AutomationId
            Orientation=$Orientation;LayoutId=$LayoutId;Evidence=@($image,$state)}
    } finally {Invoke-PtFancyZonesCaseButton SecondaryButton}
}

function Set-PtFancyZonesCaseZoneCount {
    param([Parameter(Mandatory)][string]$Template,[Parameter(Mandatory)][ValidateRange(1,64)][int]$Count)
    Open-PtFancyZonesCaseLayoutProperties $Template
    $scope=New-PtFancyZonesDriverScope $FzCase.Driver
    $scope.TemplateTypes=@($Template.ToLowerInvariant())
    $FzCase.Driver.TemplateTypes=@($FzCase.Driver.TemplateTypes+$scope.TemplateTypes|Sort-Object -Unique)
    $defaults=Get-PtFancyZonesSnapshotJson $FzCase.Driver.ExpectedModule 'default-layouts.json'
    $referencing=@($defaults.'default-layouts'|Where-Object {$_.layout.type -ceq $Template.ToLowerInvariant()})
    foreach($reference in $referencing){$reference.layout.'zone-count'=$Count}
    $scope|Add-Member NoteProperty PredictedDefaults $defaults
    Invoke-PtFancyZonesDriverAction -Context $FzCase.Driver -Scope $scope -ArgumentList @($Count,$Template.ToLowerInvariant(),$defaults) -Action {
        param($count,$type,$predictedDefaults)
        $root=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$FzCase.Driver.Editor.hwnd)
        $elements=@($root.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|
            Where-Object {$_.Current.AutomationId -in @('TemplateZoneCount','TemplateZoneSlider') -and -not $_.Current.IsOffscreen})
        $written=$false
        foreach($element in $elements){
            $pattern=$null
            if($element.TryGetCurrentPattern([Windows.Automation.RangeValuePattern]::Pattern,[ref]$pattern)){
                $pattern.SetValue($count);$written=$true;break
            }
            if($element.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern,[ref]$pattern)){
                $pattern.SetValue("$count");$written=$true;break
            }
        }
        if(-not $written){throw 'No supported numeric zone-count peer was found.'}
        Invoke-PtFancyZonesCaseButton PrimaryButton
        Wait-PtFancyZonesPersistence -Context $FzCase.Driver -ArgumentList @($type,$count,$predictedDefaults) -Ready {
            param($snapshot,$tag,$expectedCount,$expectedDefaults)
            $templates=Get-PtFancyZonesSnapshotJson $snapshot 'layout-templates.json'
            $savedDefaults=Get-PtFancyZonesSnapshotJson $snapshot 'default-layouts.json'
            @($templates.'layout-templates'|Where-Object {$_.type -ceq $tag -and $_.'zone-count' -eq $expectedCount}).Count -eq 1 -and
                (Test-PtFancyZonesJsonEqual $savedDefaults $expectedDefaults)
        }|Out-Null
    }|Out-Null
}

function Apply-PtFancyZonesCaseLayout {
    param([Parameter(Mandatory)][string]$Name,[int]$MonitorNumber=0)
    Open-PtFancyZonesEditor $FzCase.Driver|Out-Null
    if($MonitorNumber){Select-PtFancyZonesMonitor $FzCase.Driver $MonitorNumber}
    $parameters=Get-PtFancyZonesSnapshotJson $FzCase.Driver.ExpectedModule 'editor-parameters.json'
    $monitors=@($parameters.monitors|Where-Object 'monitor-number' -EQ $FzCase.Driver.SelectedMonitorNumber)
    if($monitors.Count -ne 1){throw 'Current editor selection is not uniquely bound to a native monitor.'}
    $device=ConvertTo-PtFancyZonesDevice $monitors[0]
    $custom=Get-PtFancyZonesSnapshotJson $FzCase.Driver.ExpectedModule 'custom-layouts.json'
    $layouts=@($custom.'custom-layouts'|Where-Object name -CEQ $Name)
    $types=@{Columns='columns';Rows='rows';Grid='grid';Focus='focus';'Priority grid'='priority-grid';'No layout'='blank'}
    if($layouts.Count -gt 1 -or ($layouts.Count -eq 0 -and -not $types.ContainsKey($Name))){throw 'Layout expectation is ambiguous or unsupported.'}
    $expectation=if($layouts.Count){@{Uuid=$layouts[0].uuid}}else{@{Type=$types[$Name]}}
    $scope=New-PtFancyZonesDriverScope $FzCase.Driver
    Invoke-PtFancyZonesDriverAction -Context $FzCase.Driver -Scope $scope -ArgumentList @($Name,$device,$expectation) -Action {
        param($name,$targetDevice,$expectedLayout)
        $card=Resolve-PtUiElement -Hwnd $FzCase.Driver.Editor.hwnd -Name $name -ControlType ListItem
        Invoke-PtFancyZonesElementClick -Hwnd $FzCase.Driver.Editor.hwnd -Element $card
        Wait-PtFancyZonesPersistence -Context $FzCase.Driver -ArgumentList @($card,$targetDevice,$expectedLayout) -Ready {
            param($snapshot,$selectedCard,$deviceId,$layoutId)
            $selection=$null
            if(-not $selectedCard.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern,[ref]$selection)){
                throw 'Layout card has no independent selection readback.'
            }
            $applied=Get-PtFancyZonesSnapshotJson $snapshot 'applied-layouts.json'
            $matching=@($applied.'applied-layouts'|Where-Object {Test-PtFancyZonesNativeDevice $deviceId $_.device})
            if($matching.Count -ne 1){return $false}
            $layout=$matching[0].'applied-layout'
            $selection.Current.IsSelected -and $(if($layoutId.Uuid){$layout.uuid -ieq $layoutId.Uuid}else{$layout.type -ceq $layoutId.Type})
        }|Out-Null
    }|Out-Null
}

function Copy-PtFancyZonesCaseTemplate {
    param([Parameter(Mandatory)][ValidateSet('Columns','Rows','Grid')][string]$Template)
    Open-PtFancyZonesEditor $FzCase.Driver|Out-Null
    $before=Get-PtFancyZonesSnapshotJson $FzCase.Driver.ExpectedModule 'custom-layouts.json'
    $maximum=0
    foreach($layout in @($before.'custom-layouts')){
        if($layout.name -cmatch ('^'+[regex]::Escape($Template)+' \((\d+)\)$')){
            $maximum=[Math]::Max($maximum,[int]$Matches[1])
        }
    }
    $newName="$Template ($($maximum+1))"
    Open-PtFancyZonesCaseLayoutProperties $Template
    $scope=New-PtFancyZonesDriverScope $FzCase.Driver
    $scope.NewLayoutName=$newName;$scope.NewLayoutType='grid'
    Invoke-PtFancyZonesDriverAction -Context $FzCase.Driver -Scope $scope -ArgumentList @($newName,@($before.'custom-layouts'.uuid)) -Action {
        param($expectedName,$originalIds)
        Invoke-PtFancyZonesCaseButton createFromTemplateLayoutButton
        Wait-PtFancyZonesPersistence -Context $FzCase.Driver -ArgumentList @($expectedName,$originalIds) -Ready {
            param($snapshot,$name,$oldIds)
            $layouts=Get-PtFancyZonesSnapshotJson $snapshot 'custom-layouts.json'
            @($layouts.'custom-layouts'|Where-Object {$_.name -ceq $name -and $_.uuid -cnotin $oldIds}).Count -eq 1
        }|Out-Null
    }|Out-Null
    $after=Get-PtFancyZonesSnapshotJson $FzCase.Driver.ExpectedModule 'custom-layouts.json'
    $created=@($after.'custom-layouts'|Where-Object { $_.uuid -cnotin @($before.'custom-layouts'.uuid) -and $_.name -ceq $newName })
    if($created.Count -ne 1){throw 'Template duplication did not produce one uniquely identified owned layout.'}
    $FzCase.Driver.LayoutIds+=@($created[0].uuid)
    $created[0]
}

function Initialize-PtFancyZonesCaseWindows {
    if(-not $FzCase.Surface){Start-CaseSurface}
    $FzCase.Target=Get-PtWindowIdentity $FzCase.SurfaceReady.Target
    $FzCase.Second=Get-PtWindowIdentity $FzCase.SurfaceReady.Second
    $FzCase.Child=Get-PtWindowIdentity $FzCase.SurfaceReady.Child
    $FzCase.DisplayModel=Get-PtFancyZonesDisplayModel
}

function Show-PtFancyZonesCaseWindow {
    param([Parameter(Mandatory)]$Target,[switch]$Backgrounds)
    if($FzCase.Driver.EditorCreation){Close-PtFancyZonesEditor $FzCase.Driver}
    if($Backgrounds){
        foreach($background in $FzCase.SurfaceReady.Backgrounds){
            Surface-Command "show|$background"|Out-Null
            Assert-PtForegroundOrAbort -Hwnd $background
        }
    }
    Surface-Command "show|$($Target.hwnd)"|Out-Null
    Surface-Command "focus|$($Target.hwnd)"|Out-Null
    Assert-PtForegroundOrAbort -Hwnd $Target.hwnd
}

function Get-PtFancyZonesCaseMoveEvents {
    param([Parameter(Mandatory)]$Target,[Parameter(Mandatory)][long]$Since)
    $path=Join-Path $FzCase.SurfaceState 'events.ndjson'
    if(-not(Test-Path $path)){return @()}
    @((Read-PtSharedFileText $path) -split "`n"|Where-Object {$_}|ForEach-Object {ConvertFrom-PtReportJson $_}|
        Where-Object {$_.Hwnd -eq $Target.hwnd -and $_.Ticks -ge $Since})
}

function Invoke-PtFancyZonesCaseDrag {
    param([Parameter(Mandatory)]$Target,[Parameter(Mandatory)][int]$X,[Parameter(Mandatory)][int]$Y,
        [Parameter(Mandatory)][scriptblock]$During,[object[]]$ArgumentList=@(),[switch]$Cancel)
    Assert-PtWindowIdentity $Target
    Assert-PtForegroundOrAbort -Hwnd $Target.hwnd
    Initialize-PtTaskbarNative
    foreach($key in 1,2,4){if(([PtChord]::GetAsyncKeyState($key)-band 0x8000)-ne 0){throw 'A mouse button is already held.'}}
    $frame=(Get-PtFancyZonesWindowState $Target).Native.Frame
    $point=$null
    foreach($dx in 150,250,80){
        foreach($dy in 20,10,30){
            $px=[int]($frame.Left+$dx);$py=[int]($frame.Top+$dy)
            if($px -ge $frame.Right-40 -or $py -ge $frame.Bottom){continue}
            if([PtTaskbarNative]::PointWindow($px,$py) -eq $Target.hwnd -and
                [PtFancyZonesCaption]::Hit($Target.hwnd,$px,$py) -eq 2){$point=@{X=$px;Y=$py};break}
        }
        if($point){break}
    }
    if(-not $point){throw 'No unobscured physical caption hit on the owned fixture.'}
    Send-PtTaskbarMouse -Kind Move -X $point.X -Y $point.Y|Out-Null
    if([PtTaskbarNative]::PointWindow($point.X,$point.Y) -ne $Target.hwnd){throw 'Caption became occluded.'}
    $ticks=[Diagnostics.Stopwatch]::GetTimestamp()
    Send-PtTaskbarMouse -Kind Down|Out-Null
    try {
        for($i=1;$i -le 16;$i++){
            Send-PtTaskbarMouse -Kind Move -X ([int]($point.X+($X-$point.X)*$i/16)) -Y ([int]($point.Y+($Y-$point.Y)*$i/16))|Out-Null
            Start-Sleep -Milliseconds 20
        }
        Wait-PtCondition -Description 'actual owned modal move begins' -TimeoutSeconds 3 -Probe {
            @(Get-PtFancyZonesCaseMoveEvents $Target $ticks|Where-Object Kind -CEQ 'MoveBegin').Count -eq 1
        }|Out-Null
        & $During @ArgumentList
        if($Cancel){Send-PtChord -Hwnd $Target.hwnd -Key 0x1B|Out-Null}
    } finally {Send-PtTaskbarMouse -Kind Up|Out-Null}
    Wait-PtCondition -Description 'actual owned modal move ends' -TimeoutSeconds 3 -Probe {
        @(Get-PtFancyZonesCaseMoveEvents $Target $ticks|Where-Object Kind -CEQ 'MoveEnd').Count -eq 1
    }|Out-Null
    $FzCase.LastMoveEvents=@(Get-PtFancyZonesCaseMoveEvents $Target $ticks)
}

function Reset-PtFancyZonesCaseWindow {
    param([Parameter(Mandatory)]$Target,[int]$MonitorIndex=0)
    Set-PtFancyZonesCaseOption Shift $true
    Set-PtFancyZonesCaseOption Mouse $false
    Show-PtFancyZonesCaseWindow $Target
    $area=$FzCase.DisplayModel.Monitors[$MonitorIndex].PhysicalWork
    if((Get-PtFancyZonesWindowState $Target).Native.ZoneMask -ne 0){
        $scope=New-PtFancyZonesDriverScope $FzCase.Driver
        Invoke-PtFancyZonesDriverAction -Context $FzCase.Driver -Scope $scope -ArgumentList @($Target,$area) -Action {
            param($window,$work)
            Invoke-PtFancyZonesCaseDrag -Target $window -X ([int]($work.Left+500)) -Y ([int]($work.Top+400)) -During {}
        }|Out-Null
        if((Get-PtFancyZonesWindowState $Target).Native.ZoneMask -ne 0){throw 'Actual unsnap did not clear the assignment.'}
    }
    Surface-Command "place|$($Target.hwnd)|$($area.Left+300)|$($area.Top+250)|700|500"|Out-Null
}

function Send-PtFancyZonesCaseKey {
    param([Parameter(Mandatory)]$Target,[Parameter(Mandatory)][int]$Key,[uint16[]]$Modifiers=@(0x5B))
    Show-PtFancyZonesCaseWindow $Target
    $scope=New-PtFancyZonesDriverScope $FzCase.Driver
    Invoke-PtFancyZonesDriverAction -Context $FzCase.Driver -Scope $scope -ArgumentList @($Target,$Key,$Modifiers) -Action {
        param($window,$key,$modifiers)
        Send-PtChord -Hwnd $window.hwnd -Mods $modifiers -Key $key -KeyDownMilliseconds 60|Out-Null
        Start-Sleep -Milliseconds 250
    }|Out-Null
    Get-PtFancyZonesWindowState $Target
}

function Get-PtFancyZonesCaseOverlays {
    Register-PtCreatedProcessWindows $FzCase.Host|Out-Null
    @(Get-PtNativeWindow -ProcessId $FzCase.Host.ProcessId -ClassName FancyZones_ZonesOverlay)
}

function Save-PtFancyZonesCaseOverlayCapture {
    param([Parameter(Mandatory)]$Attempt,[Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Region,[Parameter(Mandatory)][int]$MonitorIndex)
    Register-PtCreatedProcessWindows $FzCase.Surface|Out-Null
    $monitor=$FzCase.DisplayModel.Monitors[$MonitorIndex].PhysicalWork
    $backgrounds=@($FzCase.SurfaceReady.BackgroundInfo|Where-Object {
        $_.Area.Left -eq $monitor.Left -and $_.Area.Top -eq $monitor.Top -and
        $_.Area.Right -eq $monitor.Right -and $_.Area.Bottom -eq $monitor.Bottom
    })
    if($backgrounds.Count -ne 1){throw 'No exact opaque fixture background for the selected physical monitor.'}
    $background=Get-PtWindowIdentity $backgrounds[0].Hwnd
    $identities=@($background)+@(Get-PtFancyZonesCaseOverlays|Where-Object {
        $_.Visible -and $_.Rect.Left -lt ($Region.Left+$Region.Width) -and
        $_.Rect.Right -gt $Region.Left -and $_.Rect.Top -lt ($Region.Top+$Region.Height) -and $_.Rect.Bottom -gt $Region.Top
    }|ForEach-Object {Get-PtWindowIdentity $_.Hwnd})
    $path=New-PtVerificationArtifactPath -Attempt $Attempt -Name "$Name.png"
    Save-PtOwnedScreenshot -Path $path -WindowIdentity $identities -OpaqueBackgroundIdentity $background -Region $Region|Out-Null
    Add-PtVerificationArtifact -Attempt $Attempt -Path "$path.state.json" -Kind Evidence -Description 'Original before/after owned overlay scene'|Out-Null
    Add-PtVerificationArtifact -Attempt $Attempt -Path $path -Kind Screenshot -Description 'Live owned zone overlay region; actual pixels require review'
}
