#requires -Version 7.2
param(
    [Parameter(Mandatory)][ValidateSet('Span','Child','FZ-ASSIGN','FZ-DRAG',
        'FZ-HISTORY','FZ-ELEVATION','FZ-PINNED','FZ-DISPLAY','FZ-RELAYOUT','FZ-LAST-ZONE',
        'FZ-CYCLE','FZ-INDEX','FZ-POSITION','FZ-QUICK','FZ-LAYOUT','FZ-RESET','FZ-ROTATION')][string]$Case,
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$FixturePath,
    [string]$CaseScript,
    [string]$ConditionScope,
    [switch]$ObservationOnly,
    [string]$StopFile
)
$ErrorActionPreference='Stop'
if($StopFile -and (Test-Path -LiteralPath $StopFile)){throw 'Stop requested before starting a new case.'}
$skill=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
foreach($file in Get-ChildItem "$skill\scripts" -Filter '*.ps1' -File) {
    if($file.Name -cne 'pt-session-diagnose.ps1'){. $file.FullName}
}
$itemId=switch -CaseSensitive ($Case){'Span'{'FZ-SPAN'} 'Child'{'FZ-CHILD'} default{$Case}}
$inventory=Import-PtAssertionInventory "$skill\references\assertion-inventories\fancyzones.json" "$skill\references\release-checklist\fancyzones.md"
$selected=@($inventory.Items|Where-Object Id -CEQ $itemId)
$frozen=@()
if($Case -cnotin @('Span','Child')){
    if(-not $CaseScript -or -not $ConditionScope){throw 'An explicit case script and frozen condition scope are required.'}
    $scopeDocument=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($ConditionScope))
    $frozen=@($scopeDocument.Conditions|Where-Object ScenarioId -CEQ $itemId)
    if(-not $frozen.Count -or @($frozen.ConditionId|Sort-Object -Unique).Count -ne $frozen.Count){
        throw 'Selected condition catalogue is empty or duplicated.'
    }
    foreach($condition in $frozen){
        $assertion=@($selected.Assertions|Where-Object Id -CEQ $condition.ChildId)
        if($assertion.Count -ne 1 -or $condition.Expected -cne $assertion[0].Description){throw 'Condition differs from the frozen inventory.'}
    }
    if(@(Compare-Object @($selected.Assertions.Id) @($frozen.ChildId|Sort-Object -Unique)).Count){throw 'Required child conditions are missing.'}
    $parseErrors=$null
    [Management.Automation.Language.Parser]::ParseFile([IO.Path]::GetFullPath($CaseScript),[ref]$null,[ref]$parseErrors)|Out-Null
    if($parseErrors.Count){throw 'Case script has parse errors; do not begin product mutations.'}
}
$settingsPath=Join-Path $env:LOCALAPPDATA 'PowerToys\WinUI3Apps\PowerToys.Settings.exe'
$hostPath=Join-Path $env:LOCALAPPDATA 'PowerToys\PowerToys.FancyZones.exe'
$editorPath=Join-Path $env:LOCALAPPDATA 'PowerToys\PowerToys.FancyZonesEditor.exe'
$settingsWindows=@(foreach($process in @(Get-PtResourceProcessCandidates $settingsPath)) {
    Get-PtNativeWindow -ProcessId $process.processId|Where-Object Title -CEQ 'PowerToys Settings'
})
if($settingsWindows.Count -ne 1){throw 'Exactly one existing Settings main window is required.'}
if(@(Get-PtResourceProcessCandidates $hostPath).Count -or @(Get-PtResourceProcessCandidates $editorPath).Count){
    throw 'This bounded fixture requires FancyZones initially disabled and its editor absent.'
}
$inputs=@(
    @{Name='case-driver.ps1';Role='Other';Path=$PSCommandPath},
    @{Name='fancyzones-checklist.md';Role='Checklist';Path="$skill\references\release-checklist\fancyzones.md"},
    @{Name='fancyzones-inventory.json';Role='Other';Path="$skill\references\assertion-inventories\fancyzones.json"},
    @{Name='fancyzones-profile.md';Role='Profile';Path="$skill\references\modules\fancyzones.md"},
    @{Name='surface.exe';Role='Other';Path=$FixturePath}
)
if($CaseScript){$inputs+=@(@{Name='case-operation.ps1';Role='Other';Path=$CaseScript})}
if($ConditionScope){$inputs+=@(@{Name='condition-scope.json';Role='Other';Path=$ConditionScope})}
$repository=Split-Path (Split-Path (Split-Path $skill -Parent) -Parent) -Parent
$editorSource=Join-Path $repository 'src\modules\fancyzones\editor\FancyZonesEditor'
$inputs+=@(@{Name='editor-opaque-client.xaml';Role='Other';Path="$editorSource\MainWindow.xaml"})
foreach($theme in 'Dark','Light','HighContrast1','HighContrast2','HighContrastBlack','HighContrastWhite'){
    $inputs+=@(@{Name="editor-theme-$theme.xaml";Role='Other';Path="$editorSource\Themes\$theme.xaml"})
}
$run=New-PtVerificationRun -Workspace $Workspace -Module FancyZones -Bits 'Installed 0.102.3001.0; one explicitly selected case' `
    -Scenario A -Items $selected -Inputs @(Get-PtVerificationInputs -Skill $skill -Inputs $inputs)
$private=Join-Path ([IO.Path]::GetDirectoryName($run.Workspace)) ([IO.Path]::GetFileName($run.Workspace)+'-private')
if(Test-Path $private){throw 'Private recovery already exists.'}
[IO.Directory]::CreateDirectory($private)|Out-Null
$global:FzCase=@{
    Run=$run;Private=$private;Settings=(Get-PtWindowIdentity $settingsWindows[0].Hwnd)
    OriginalModule=$null;ExpectedModule=$null;OriginalGeneral=$null;ExpectedGeneral=$null
    SettingsSnapshot=$null;Desktop=$null;Keyboard=$null;Lifecycle=$null;Host=$null
    Driver=$null;Surface=$null;SurfaceReady=$null;SurfaceState="$private\surface"
    TaskView=$null;HostPath=$hostPath;EditorPath=$editorPath
    Conditions=[Collections.Generic.List[object]]::new();Cleanup=[Collections.Generic.List[object]]::new()
    Frozen=$frozen;Ledger=@{}
    StopFile=$StopFile
}
foreach($condition in $frozen){
    $FzCase.Ledger[$condition.ConditionId]=[pscustomobject]@{
        Id=$condition.ConditionId;ChildId=$condition.ChildId;Mode=$condition.Spanning;Variant=$condition.Variant
        Expected=$condition.Expected;Verdict='NOT-OBSERVED';Category='not-observed';Passed=$false;Executed=$false
        Actual='Not executed.';Evidence=@();ObservationSequence=$null;AttemptId=$null
    }
}
$plan=@{Schema='PtRunResources.v1';Resources=@(
    @{Id='host';Kind='Process';Ownership='Owned';FilePath=$hostPath;RestoreStep='host'},
    @{Id='editor';Kind='Process';Ownership='Owned';FilePath=$editorPath;RestoreStep='editor'},
    @{Id='surface';Kind='Process';Ownership='Owned';FilePath=$FixturePath;RestoreStep='surface'},
    @{Id='task-view';Kind='Other';RestoreStep='task-view'},
    @{Id='module-files';Kind='File';RestoreStep='module-files'},
    @{Id='general-files';Kind='File';RestoreStep='general-files'},
    @{Id='desktop-input';Kind='Other';RestoreStep='desktop-input'},
    @{Id='settings';Kind='Settings';Hwnd=$FzCase.Settings.hwnd}
)}
Assert-PtRunResourcePlan -Plan $plan -CleanupPlan (New-PtFancyZonesCleanupPlan -Context $FzCase -SetEnabled {param($value) Set-CaseEnabled $value}) `
    -SettingsHwnd @($FzCase.Settings.hwnd)
New-PtResourceSession -Run $run -ResourcePlan $plan|Out-Null
function Save-Private([string]$Name,$Value) {
    [IO.File]::WriteAllText((Join-Path $FzCase.Private $Name),($Value|ConvertTo-Json -Depth 35),[Text.UTF8Encoding]::new($false))
}
function Show-Setting([string]$Id) {
    Assert-PtForegroundOrAbort -Hwnd $FzCase.Settings.hwnd
    Initialize-PtUiAutomation
    $root=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$FzCase.Settings.hwnd)
    $node=Select-PtUniqueUiElement -Description $Id -Elements @($root.FindAll(
        [Windows.Automation.TreeScope]::Descendants,
        [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,$Id)))
    $scroll=$null
    if($node.TryGetCurrentPattern([Windows.Automation.ScrollItemPattern]::Pattern,[ref]$scroll)){$scroll.ScrollIntoView()}
    if($Id -ceq 'EnableFancyZonesToggleSwitch' -and $node.Current.IsOffscreen){
        $ancestor=$node
        while($ancestor){
            $scroll=$null
            if($ancestor.TryGetCurrentPattern([Windows.Automation.ScrollPattern]::Pattern,[ref]$scroll) -and $scroll.Current.VerticallyScrollable){
                $scroll.SetScrollPercent(-1,0);break
            }
            $ancestor=[Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($ancestor)
        }
    }
    $node
}
function Set-CaseEnabled([bool]$Enabled) {
    Show-Setting 'EnableFancyZonesToggleSwitch'|Out-Null
    $before=$FzCase.ExpectedGeneral
    $actual=Get-PtFileSetSnapshot -Path $before.FileState.Path -FileNames $before.FileNames
    $old=ConvertTo-PtFileSetSnapshotMap $before 8MB
    $now=ConvertTo-PtFileSetSnapshotMap $actual 8MB
    foreach($name in $before.FileNames){
        if(-not(Test-PtDirectoryEntryEqual $old[$name] $now[$name])){throw "General pre-action conflict: $name"}
    }
    $predicted=Get-PtFancyZonesSnapshotJson $before 'settings.json'
    $predicted.enabled.FancyZones=$Enabled
    try { Set-PtModuleEnabled -Snapshot $FzCase.Lifecycle -Enabled $Enabled -TimeoutSeconds 12|Out-Null }
    finally {
        $after=Get-PtFileSetSnapshot -Path $before.FileState.Path -FileNames $before.FileNames
        $afterMap=ConvertTo-PtFileSetSnapshotMap $after 8MB
        if(-not(Test-PtFancyZonesJsonEqual $predicted (Get-PtFancyZonesSnapshotJson $after 'settings.json'))){
            throw 'Lifecycle wrote unexpected general settings.'
        }
        foreach($name in $before.FileNames|Where-Object {$_ -cne 'settings.json'}){
            if(-not(Test-PtDirectoryEntryEqual $old[$name] $afterMap[$name])){throw "Additional general write: $name"}
        }
        $FzCase.ExpectedGeneral=$after
        Save-Private 'general-expected.json' $after
    }
}
function Case-Proof($Attempt,[string]$Name,$Value,[string]$Kind='Evidence') {
    $path=New-PtVerificationArtifactPath -Attempt $Attempt -Name "$Name.json"
    Write-PtReportText $path ($Value|ConvertTo-Json -Depth 18)
    Add-PtVerificationArtifact -Attempt $Attempt -Path $path -Kind $Kind -Description $Name
}
function Record-CaseCondition {
    param(
        [Parameter(Mandatory)]$Attempt,
        [Parameter(Mandatory)][string]$ConditionId,
        [Parameter(Mandatory)][ValidateSet('PASS','FAIL','BLOCKED','NOT-OBSERVED')][string]$Verdict,
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Actual,
        [Parameter(Mandatory)][bool]$Executed,
        [object[]]$Evidence=@(),
        $Detail
    )
    if($FzCase.StopFile -and (Test-Path -LiteralPath $FzCase.StopFile)){
        throw 'Stop requested; leave the remaining conditions unobserved and restore this case.'
    }
    $row=$FzCase.Ledger[$ConditionId]
    if(-not $row -or $Attempt.ItemId -cne $itemId){throw 'Condition does not belong to this selected case.'}
    Assert-PtVerificationVerdictCategory $Verdict $Category
    if($Verdict -ceq 'PASS' -and -not $Executed){throw 'An unexecuted condition cannot PASS.'}
    if($PSBoundParameters.ContainsKey('Detail')){
        $Evidence+=@(Case-Proof $Attempt ('condition-'+[guid]::NewGuid().ToString('N')) $Detail)
    }
    if($Verdict -ceq 'PASS' -and -not $Evidence.Count){throw 'PASS requires actual producing evidence.'}
    if($row.Verdict -cne 'NOT-OBSERVED'){
        if(-not $row.PSObject.Properties['History']){$row|Add-Member NoteProperty History @()}
        $row.History+=@([pscustomobject]@{Verdict=$row.Verdict;Actual=$row.Actual;Evidence=$row.Evidence;AttemptId=$row.AttemptId})
    }
    $row.Verdict=$Verdict;$row.Category=$Category;$row.Actual=$Actual;$row.Executed=$Executed
    $row.Passed=$Verdict -ceq 'PASS';$row.Evidence=$Evidence;$row.AttemptId=$Attempt.Id
    $row.ObservationSequence=Add-PtVerificationObservation -Attempt $Attempt -AssertionId $row.ChildId -Actual "$ConditionId | $Actual" -Evidence $Evidence
    [IO.File]::WriteAllText((Join-Path $FzCase.Run.Workspace 'conditions-current.json'),
        (@($FzCase.Ledger.Values)|Sort-Object Id|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
}
function Complete-CaseConditions($Attempt) {
    foreach($assertion in $selected.Assertions){
        $rows=@($FzCase.Ledger.Values|Where-Object ChildId -CEQ $assertion.Id)
        $failed=@($rows|Where-Object Verdict -CEQ 'FAIL')
        $blocked=@($rows|Where-Object Verdict -CEQ 'BLOCKED')
        $missing=@($rows|Where-Object Verdict -CEQ 'NOT-OBSERVED')
        $verdict=if($failed.Count){'FAIL'}elseif($blocked.Count -or $missing.Count){'BLOCKED'}else{'PASS'}
        $category=if($failed.Count){$failed[0].Category}elseif($missing.Count){'BLK-INCOMPLETE'}elseif($blocked.Count){$blocked[0].Category}else{'recorded product observation'}
        $reason="$($rows.Count) conditions: $(@($rows|Where-Object Verdict -CEQ 'PASS').Count) pass, $($failed.Count) fail, $($blocked.Count) blocked, $($missing.Count) unobserved."
        $currentEvidence=@($rows|Where-Object AttemptId -CEQ $Attempt.Id|ForEach-Object {$_.Evidence})
        $detail=Case-Proof $Attempt ('child-'+$assertion.Id) $rows
        $currentEvidence+=@($detail)
        $sequence=Add-PtVerificationObservation -Attempt $Attempt -AssertionId $assertion.Id -Actual $reason -Evidence $currentEvidence
        Add-PtVerificationAssertion -Attempt $Attempt -AssertionId $assertion.Id -ObservationSequence $sequence `
            -Verdict $verdict -Category $category -Reason $reason -Evidence $currentEvidence
    }
}
function Set-CaseSpan([bool]$Value) {
    if($FzCase.Driver.EditorCreation){Close-PtFancyZonesEditor $FzCase.Driver}
    Set-PtFancyZonesBoolean -Context $FzCase.Driver -ContainerId FancyZonesSpanZonesAcrossMonitors `
        -SettingKey fancyzones_span_zones_across_monitors -Value $Value|Out-Null
}
function Surface-Command([string]$Command) {
    $path=Join-Path $FzCase.SurfaceState 'command.txt'
    if(Test-Path $path){throw 'Previous fixture command is pending.'}
    [IO.File]::Delete((Join-Path $FzCase.SurfaceState 'response.json'))
    $staging=$path+'.'+[guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($staging,$Command)
    [IO.File]::Move($staging,$path)
    $result=Wait-PtCondition -Description 'owned fixture command response' -TimeoutSeconds 5 -Probe {
        $response=Join-Path $FzCase.SurfaceState 'response.json'
        if(Test-Path $response){
            $json=ConvertFrom-PtReportJson (Read-PtSharedFileText $response)
            if($json.Command -ceq $Command){$json}
        }
    }
    if(-not $result.Success){throw "Fixture rejected operation: $($result.Error)"}
    $result
}
function Start-CaseSurface {
    [IO.Directory]::CreateDirectory($FzCase.SurfaceState)|Out-Null
    $FzCase.Surface=Start-PtOwnedProcess -FilePath $FixturePath -ArgumentList @($FzCase.SurfaceState) -Lifetime Run
    $FzCase.SurfaceReady=Wait-PtCondition -Description 'owned test windows ready' -TimeoutSeconds 10 -Probe {
        if(Test-Path "$($FzCase.SurfaceState)\ready.json"){
            ConvertFrom-PtReportJson (Read-PtSharedFileText "$($FzCase.SurfaceState)\ready.json")
        }
    }
    if($FzCase.SurfaceReady.Pid -ne $FzCase.Surface.ProcessId){throw 'Fixture ready PID does not match launch.'}
    Register-PtCreatedProcessWindows $FzCase.Surface|Out-Null
    $FzCase.Driver.ApplicationPaths=@($FixturePath)
    Surface-Command "hide|$($FzCase.SurfaceReady.Child)"|Out-Null
    Surface-Command "hide|$($FzCase.SurfaceReady.Second)"|Out-Null
}
function Capture-CaseRegion($Attempt,[string]$Name,$Target,$Region,$Element) {
    Register-PtCreatedProcessWindows $FzCase.Surface|Out-Null
    Register-PtCreatedProcessWindows $FzCase.Host|Out-Null
    if($FzCase.Driver.EditorCreation){Register-PtCreatedProcessWindows $FzCase.Driver.EditorCreation|Out-Null}
    # MainWindow's themed client uses FF-alpha brushes; the authored surface paints opaque controls.
    $editorTarget=$FzCase.Driver.Editor -and $Target.hwnd -eq $FzCase.Driver.Editor.hwnd
    if(-not $editorTarget -and $Target.processId -ne $FzCase.Surface.ProcessId){
        throw 'Only the source-verified opaque editor client or authored fixture client can be the backdrop.'
    }
    $background=$Target
    Assert-PtForegroundOrAbort -Hwnd $Target.hwnd
    $path=New-PtVerificationArtifactPath -Attempt $Attempt -Name "$Name.png"
    if($Element){
        Save-PtOwnedControlScreenshot -Path $path -WindowIdentity $Target -OpaqueBackgroundIdentity $background -Element $Element|Out-Null
    }else{
        Save-PtOwnedScreenshot -Path $path -WindowIdentity @($Target,$background) -OpaqueBackgroundIdentity $background -Region $Region|Out-Null
    }
    Add-PtVerificationArtifact -Attempt $Attempt -Path "$path.state.json" -Kind Evidence -Description 'Before/after owned capture scene'|Out-Null
    Add-PtVerificationArtifact -Attempt $Attempt -Path $path -Kind Screenshot -Description 'Owned composed region, paired with full native work-area geometry; not an accepted reference'
}
function Observe-Span($Attempt,[bool]$Enabled) {
    Set-CaseSpan $Enabled
    foreach($background in $FzCase.SurfaceReady.Backgrounds){Surface-Command "show|$background"|Out-Null}
    $editor=Open-PtFancyZonesEditor $FzCase.Driver
    $model=Get-PtFancyZonesDisplayModel
    $actual=Get-PtFancyZonesSnapshotJson $FzCase.Driver.ExpectedModule 'editor-parameters.json'
    $predicted=New-PtFancyZonesEditorParameters -DisplayModel $model -HostProcessId $FzCase.Host.ProcessId `
        -Spanning $Enabled -TargetMonitor $model.Monitors[0].Handle
    $expectedAreas=if($Enabled){
        @([pscustomobject]@{Left=($model.Monitors.PhysicalWork.Left|Measure-Object -Minimum).Minimum
            Top=($model.Monitors.PhysicalWork.Top|Measure-Object -Minimum).Minimum
            Right=($model.Monitors.PhysicalWork.Right|Measure-Object -Maximum).Maximum
            Bottom=($model.Monitors.PhysicalWork.Bottom|Measure-Object -Maximum).Maximum})
    }else{@($model.Monitors.PhysicalWork)}
    $windows=@(Get-PtNativeWindow -ProcessId $FzCase.Driver.EditorCreation.ProcessId -Visible)
    $matches=@(foreach($area in $expectedAreas){
        $found=@($windows|Where-Object {
            [Math]::Abs($_.Rect.Left-$area.Left) -le 2 -and [Math]::Abs($_.Rect.Top-$area.Top) -le 2 -and
            [Math]::Abs($_.Rect.Right-$area.Right) -le 2 -and [Math]::Abs($_.Rect.Bottom-$area.Bottom) -le 2
        })
        [pscustomobject]@{Expected=$area;Count=$found.Count;Actual=@($found|Select-Object Hwnd,Rect)}
    })
    $geometryFields=@('dpi','top-coordinate','left-coordinate','work-area-width','work-area-height','monitor-width','monitor-height')
    $expectedGeometry=@($predicted.monitors|Select-Object $geometryFields|Sort-Object 'left-coordinate')
    $actualGeometry=@($actual.monitors|Select-Object $geometryFields|Sort-Object 'left-coordinate')
    $sameGeometry=Test-PtFancyZonesJsonEqual @{Monitors=$expectedGeometry} @{Monitors=$actualGeometry}
    $passed=$actual.'span-zones-across-monitors' -eq $Enabled -and
        $actual.monitors.Count -eq $predicted.monitors.Count -and $sameGeometry -and
        @($matches|Where-Object Count -NE 1).Count -eq 0
    $label=if($Enabled){'on'}else{'off'}
    Initialize-PtUiAutomation
    $editorRoot=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$editor.hwnd)
    $selectors=@($editorRoot.FindAll([Windows.Automation.TreeScope]::Descendants,
        [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,'Monitors')))
    if($selectors.Count -gt 1){throw 'Ambiguous monitor selector.'}
    $selectorVisible=$selectors.Count -eq 1 -and -not $selectors[0].Current.IsOffscreen
    if($selectorVisible){
        $captureElement=$selectors[0]
        $bounds=$selectors[0].Current.BoundingRectangle
        $region=[pscustomobject]@{Left=[int]$bounds.Left;Top=[int]$bounds.Top;Width=[int]$bounds.Width;Height=[int]$bounds.Height}
    }else{
        $button=Resolve-PtUiElement -Hwnd $editor.hwnd -AutomationId NewLayoutButton -ControlType Button
        $captureElement=$button
        $bounds=$button.Current.BoundingRectangle
        $region=[pscustomobject]@{Left=[int]$bounds.Left;Top=[int]$bounds.Top;Width=[int]$bounds.Width;Height=[int]$bounds.Height}
    }
    $images=@(Capture-CaseRegion $Attempt "span-$label-editor-selector" $editor $region $captureElement)
    $evidence=Case-Proof $Attempt "span-$label" @{
        Spanning=$Enabled;PhysicalMonitorCount=$model.Monitors.Count
        ActualModelCount=$actual.monitors.Count;ExpectedModelCount=$predicted.monitors.Count
        GeometryMatches=$sameGeometry;ExpectedGeometry=$expectedGeometry;ActualGeometry=$actualGeometry
        OwnedEditorWindows=$matches;MonitorSelectorVisible=$selectorVisible;Passed=$passed
    }
    $FzCase.Conditions.Add([pscustomobject]@{Id="FZ-SPAN.$label";Passed=$passed;Evidence=$evidence})
    $sequence=Add-PtVerificationObservation -Attempt $Attempt -AssertionId "FZ-SPAN.$label" `
        -Actual "Spanning ${label}: host model count $($actual.monitors.Count), measured editor work-area geometry matches=$passed." -Evidence (@($evidence)+$images)
    Add-PtVerificationAssertion -Attempt $Attempt -AssertionId "FZ-SPAN.$label" -ObservationSequence $sequence `
        -Verdict $(if($passed){'PASS'}else{'FAIL'}) -Category product -Reason 'Current native display geometry compared with actual host input and owned editor overlay bounds.' -Evidence (@($evidence)+$images)
    Close-PtFancyZonesEditor $FzCase.Driver
}
function Cleanup-CaseStep($Attempt,[string]$Name,[scriptblock]$Action) {
    try {
        Invoke-PtVerificationStep -Attempt $Attempt -Name $Name -Command "Restore bounded case resource: $Name" -Action $Action|Out-Null
        $FzCase.Cleanup.Add(@{Name=$Name;Passed=$true})
    } catch { $FzCase.Cleanup.Add(@{Name=$Name;Passed=$false;Error=$_.Exception.Message}) }
}
function Prepare-ChildLayout([bool]$Spanning) {
    Set-CaseSpan $Spanning
    Open-PtFancyZonesEditor $FzCase.Driver|Out-Null
    $parameters=Get-PtFancyZonesSnapshotJson $FzCase.Driver.ExpectedModule 'editor-parameters.json'
    $monitorNumbers=if($Spanning){@(0)}else{@($parameters.monitors.'monitor-number')}
    foreach($number in $monitorNumbers){
        if(-not $Spanning){Select-PtFancyZonesMonitor -Context $FzCase.Driver -MonitorNumber $number}
        $scope=New-PtFancyZonesDriverScope $FzCase.Driver
        $scope.NativeSerialization=$true
        Invoke-PtFancyZonesDriverAction -Context $FzCase.Driver -Scope $scope -Action {
            $card=Resolve-PtUiElement -Hwnd $FzCase.Driver.Editor.hwnd -Name Columns -ControlType ListItem
            Invoke-PtFancyZonesElementClick -Hwnd $FzCase.Driver.Editor.hwnd -Element $card
        }|Out-Null
    }
    Close-PtFancyZonesEditor $FzCase.Driver
}
function Observe-Child($Attempt,[bool]$Spanning,[bool]$Enabled) {
    Set-PtFancyZonesBoolean -Context $FzCase.Driver -ContainerId FancyZonesAllowChildWindowSnap `
        -SettingKey fancyzones_allowChildWindowSnap -Value $Enabled|Out-Null
    foreach($background in $FzCase.SurfaceReady.Backgrounds){Surface-Command "show|$background"|Out-Null}
    Surface-Command "show|$($FzCase.SurfaceReady.Target)"|Out-Null
    $created=Surface-Command create-child
    Register-PtCreatedProcessWindows $FzCase.Surface|Out-Null
    $child=Get-PtWindowIdentity $created.Hwnd
    try {
        Surface-Command "focus|$($child.hwnd)"|Out-Null
        $before=Get-PtFancyZonesWindowState $child
        if($before.Native.ZoneMask -ne 0 -or $before.Native.Owner -ne $FzCase.SurfaceReady.Target){
            throw 'New child must be initially unsnapped with the exact owned parent.'
        }
        $parent=Get-PtNativeWindow -Hwnd $before.Native.Owner
        if(-not $parent.Visible){throw 'The genuine child must have a visible owner.'}
        $start=[Diagnostics.Stopwatch]::GetTimestamp()
        Send-PtChord -Hwnd $child.hwnd -Key 0x75|Out-Null
        Start-Sleep -Milliseconds 100
        $delivery=@((Read-PtSharedFileText "$($FzCase.SurfaceState)\events.ndjson") -split "`n"|
            Where-Object {$_}|ForEach-Object {ConvertFrom-PtReportJson $_}|
            Where-Object {$_.Hwnd -eq $child.hwnd -and $_.Ticks -ge $start -and $_.Key -eq 0x75})
        if(-not @($delivery|Where-Object Kind -EQ KeyDown).Count -or -not @($delivery|Where-Object Kind -EQ KeyUp).Count){
            throw 'Owned key delivery was not observed.'
        }
        $scope=New-PtFancyZonesDriverScope $FzCase.Driver
        Invoke-PtFancyZonesDriverAction -Context $FzCase.Driver -Scope $scope -ArgumentList @($child.hwnd) -Action {
            param($window)
            Send-PtChord -Hwnd $window -Mods @(0x5B) -Key 0x27 -KeyDownMilliseconds 80|Out-Null
            Start-Sleep -Milliseconds 400
        }|Out-Null
        $after=Get-PtFancyZonesWindowState $child
        $passed=if($Enabled){$after.Native.ZoneMask -gt 0}else{$after.Native.ZoneMask -eq 0}
        $mode=if($Spanning){'on'}else{'off'}
        $branch=if($Enabled){'enabled'}else{'disabled'}
        $label="child-$branch-$mode"
        $client=[PtDesktop]::ClientBounds([IntPtr][long]$child.hwnd)
        $region=[pscustomobject]@{Left=[int]$client.Left;Top=[int]$client.Top
            Width=[int]($client.Right-$client.Left);Height=[int]($client.Bottom-$client.Top)}
        $image=Capture-CaseRegion $Attempt $label $child $region
        $evidence=Case-Proof $Attempt $label @{
            Spanning=$Spanning;ChildSnapping=$Enabled;Before=$before.Native;After=$after.Native
            ChildClass=$child.className;VisibleOwner=$true;DeliveredKeys=$delivery;Passed=$passed
        }
        $FzCase.Conditions.Add([pscustomobject]@{Id="FZ-CHILD.$branch";Mode=$mode;Passed=$passed;Evidence=@($evidence,$image)})
    } finally {
        $scope=New-PtFancyZonesDriverScope $FzCase.Driver
        Invoke-PtFancyZonesDriverAction -Context $FzCase.Driver -Scope $scope -ArgumentList @($child.hwnd) -Action {
            param($window)
            Surface-Command "close|$window"|Out-Null
        }|Out-Null
    }
}
$failure=$null
try {
    Invoke-PtVerificationCase -Run $run -Context Preflight -Name 'Prepare current-state reversible fixture' -Command 'Capture baseline, navigate Settings, enable exact owned host' -Action {
        param($attempt)
        $FzCase.Desktop=Get-PtDesktopSnapshot
        $FzCase.Keyboard=Get-PtKeyboardLayoutSnapshot $FzCase.Desktop.foreground
        Save-Private 'desktop-original.json' $FzCase.Desktop
        Save-Private 'keyboard-original.json' $FzCase.Keyboard
        $FzCase.OriginalModule=Get-PtFileSetSnapshot -Path "$env:LOCALAPPDATA\Microsoft\PowerToys\FancyZones" -FileNames @(
            'settings.json','applied-layouts.json','custom-layouts.json','default-layouts.json','layout-hotkeys.json',
            'layout-templates.json','app-zone-history.json','editor-parameters.json','last-used-virtual-desktop.json')
        $FzCase.ExpectedModule=$FzCase.OriginalModule
        $FzCase.OriginalGeneral=Get-PtFileSetSnapshot -Path "$env:LOCALAPPDATA\Microsoft\PowerToys" -FileNames @(
            'settings.json','settings-ui.json','settings-placement.json')
        $FzCase.ExpectedGeneral=$FzCase.OriginalGeneral
        Save-Private 'module-original.json' $FzCase.OriginalModule
        Save-Private 'general-original.json' $FzCase.OriginalGeneral
        $FzCase.SettingsSnapshot=Get-PtSettingsUiSnapshot -Hwnd $FzCase.Settings.hwnd -Workspace $FzCase.Private
        if($ObservationOnly){
            Case-Proof $attempt 'observation-only-preflight' @{SelectedCase=$itemId;ModuleActivated=$false;PrivateBaselineCaptured=$true}|Out-Null
            return
        }
        Show-PtSettingsForObservation $FzCase.Settings.hwnd
        $nav=Resolve-PtUiElement -Hwnd $FzCase.Settings.hwnd -AutomationId FancyZonesNavItem -ControlType ListItem
        $nav.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Show-Setting EnableFancyZonesToggleSwitch|Out-Null
        $profile=@{Id='fancyzones';ModuleKey='FancyZones';PageAutomationId='FancyZonesNavItem';ToggleAutomationId='EnableFancyZonesToggleSwitch'
            Model='Resident';ProcessName='PowerToys.FancyZones';ProcessPath=$hostPath;WindowClass='SuperFancyZones'
            SettingsPath="$env:LOCALAPPDATA\Microsoft\PowerToys\settings.json";Events=@()}
        $FzCase.Lifecycle=Get-PtModuleLifecycleSnapshot -Profile $profile -SettingsTarget $FzCase.Settings -Workspace $FzCase.Private
        if($FzCase.Lifecycle.OriginalEnabled){throw 'Expected initially disabled module.'}
        $model=Get-PtFancyZonesDisplayModel
        if($model.Monitors.Count -ne 2 -or @($model.Monitors.Dpi|Sort-Object -Unique).Count -ne 1){throw 'Two compatible monitors required.'}
        $stamped=@(Get-PtNativeWindow -Visible|Where-Object { [PtFancyZonesDriverNative]::ZoneMask($_.Hwnd) -ne 0 })
        if($stamped.Count){throw 'Unowned snapped windows would be moved; do not activate.'}
        $areas=@(foreach($span in $false,$true) {
            $parameters=New-PtFancyZonesEditorParameters -DisplayModel $model -HostProcessId 1 -Spanning $span -TargetMonitor $model.Monitors[0].Handle
            foreach($monitor in $parameters.monitors){ConvertTo-PtFancyZonesDevice $monitor}
        })
        $expected=$FzCase.ExpectedModule
        try {
            Invoke-PtFancyZonesScopedAction -ExpectedState ([ref]$expected) -Scope @{WorkAreas=$areas;NativeSerialization=$true} -Action {
                $FzCase.Host=Invoke-PtOwnedProcessActivation -FilePath $hostPath -TimeoutSeconds 15 -Action {Set-CaseEnabled $true}
                Register-PtCreatedProcessWindows $FzCase.Host|Out-Null
            }|Out-Null
        } finally {$FzCase.ExpectedModule=$expected;Save-Private 'module-expected.json' $expected}
        $FzCase.Driver=New-PtFancyZonesDriverContext -ExpectedState $FzCase.ExpectedModule -HostCreation $FzCase.Host `
            -Settings $FzCase.Settings -EditorPath $editorPath -PrivateRecoveryDirectory $FzCase.Private
        $FzCase.Driver.StopFile=$StopFile
        Case-Proof $attempt 'preflight' @{MonitorCount=$model.Monitors.Count;Dpi=@($model.Monitors.Dpi)
            Host=$FzCase.Host.ProcessId;OriginalEnabled=$false;FullInventory=$inventory.Items.Count;SelectedCase=$itemId}|Out-Null
    }|Out-Null
    if($Case -ceq 'Span') {
        Invoke-PtVerificationCase -Run $run -ItemId $itemId -Name 'Spanning off and on' -Command 'Toggle actual Settings, observe host model and editor geometry, close normally' -Action {
            param($attempt)
            Start-CaseSurface
            Surface-Command "hide|$($FzCase.SurfaceReady.Target)"|Out-Null
            Observe-Span $attempt $false
            Observe-Span $attempt $true
        }|Out-Null
    } elseif($Case -ceq 'Child') {
        Invoke-PtVerificationCase -Run $run -ItemId $itemId -Name 'Child snapping in both modes' `
            -Command 'Apply a template via UI and exercise real keyboard snapping on same-class owned child windows' -Action {
            param($attempt)
            Set-PtFancyZonesBoolean -Context $FzCase.Driver -ContainerId FancyZonesAppLastZoneMoveWindows `
                -SettingKey fancyzones_appLastZone_moveWindows -Value $false|Out-Null
            Set-PtFancyZonesBoolean -Context $FzCase.Driver -ContainerId FancyZonesOverrideSnapHotkeys `
                -SettingKey fancyzones_overrideSnapHotkeys -Value $true|Out-Null
            Start-CaseSurface
            foreach($mode in $false,$true){
                Prepare-ChildLayout $mode
                Observe-Child $attempt $mode $true
                Observe-Child $attempt $mode $false
            }
            foreach($branch in 'enabled','disabled'){
                $conditions=@($FzCase.Conditions|Where-Object Id -CEQ "FZ-CHILD.$branch")
                $passed=$conditions.Count -eq 2 -and @($conditions|Where-Object Passed -EQ $false).Count -eq 0
                $evidence=@($conditions.Evidence)
                $sequence=Add-PtVerificationObservation -Attempt $attempt -AssertionId "FZ-CHILD.$branch" `
                    -Actual "Same-class genuine child snapping $branch in both spanning modes: matches=$passed." -Evidence $evidence
                Add-PtVerificationAssertion -Attempt $attempt -AssertionId "FZ-CHILD.$branch" -ObservationSequence $sequence `
                    -Verdict $(if($passed){'PASS'}else{'FAIL'}) -Category product -Reason 'Real input, exact owned parent/child identities and actual zone assignment in both modes.' -Evidence $evidence
            }
        }|Out-Null
    } else {
        Invoke-PtVerificationCase -Run $run -ItemId $itemId -Name 'Execute frozen selected conditions' `
            -Command "Execute the source-recorded finite operation script for $itemId" -Action {
                param($attempt)
                try {
                    Invoke-PtVerificationStep -Attempt $attempt -Name 'Selected case operations' `
                        -Command "Run $itemId actions and observations" -ScriptFile $CaseScript -ArgumentList @($attempt)|Out-Null
                } finally {
                    Complete-CaseConditions $attempt
                }
            }|Out-Null
    }
    Complete-PtVerificationItem -Run $run -ItemId $itemId -Reason 'All selected case conditions have producing observations and explicit judgments.'
} catch {$failure=$_}
finally {
    Invoke-PtVerificationCase -Run $run -Context Cleanup -Name 'Restore original case state' -Command 'Independent cleanup and original-state comparisons' -Action {
        param($attempt)
        $cleanupPlan=New-PtFancyZonesCleanupPlan -Context $FzCase -SetEnabled {param($value) Set-CaseEnabled $value}
        try {
            $cleanupRows=@(Invoke-PtCleanupPlan -Attempt $attempt -Steps $cleanupPlan)
        } catch {
            if(-not $_.Exception.Data['CleanupResults']){throw}
            $cleanupRows=@($_.Exception.Data['CleanupResults'])
        }
        foreach($row in $cleanupRows){
            $FzCase.Cleanup.Add(@{Name=$row.Resource;Passed=($row.Verdict -ceq 'PASS');Reason=$row.Reason})
        }
        Cleanup-CaseStep $attempt 'resources' {Complete-PtResourceSession -Attempt $attempt|Out-Null}
        $proof=Case-Proof $attempt 'cleanup-summary' @($FzCase.Cleanup) Restoration
        Add-PtVerificationRestoration -Attempt $attempt -Verdict $(if(@($FzCase.Cleanup|Where-Object Passed -EQ $false).Count){'BLOCKED'}else{'PASS'}) `
            -Reason 'Explicit case cleanup including files, UI, desktop and exact owned processes.' -Evidence @($proof)
    }|Out-Null
}
$retrospective=@(@{Friction='One explicitly selected case; conclusions do not cover the full module.';Source='ENVIRONMENT';Severity='LOW'
    Cost='Bounded one-case execution';SuggestedFix='Keep this scope distinct from full-inventory verification.'})
$export=Complete-PtVerificationRun -Run $run -Retrospective $retrospective
$integrity=Test-PtVerificationArchive -Workspace $run.Workspace
$state=Get-PtReportState $run
$summary=[ordered]@{Case=$itemId;RunId=$run.Id;Workspace=$run.Workspace;ArchiveValid=$integrity.Valid
    Verdict=$state.Items[0].Verdict;Signoff=$state.Signoff;Conditions=$(if($frozen.Count){@($FzCase.Ledger.Values|Sort-Object Id)}else{@($FzCase.Conditions)})
    Cleanup=@($FzCase.Cleanup);Error=$(if($failure){$failure.Exception.Message}else{$null})}
$summary|ConvertTo-Json -Depth 15|Set-Content (Join-Path $run.Workspace 'case-summary.json')
$summary|ConvertTo-Json -Depth 6
if($failure){throw $failure}
if($state.Items[0].Verdict -cne 'PASS' -or @($FzCase.Cleanup|Where-Object Passed -EQ $false).Count){throw 'Selected case or restoration is not PASS.'}
