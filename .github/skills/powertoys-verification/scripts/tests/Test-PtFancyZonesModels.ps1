#requires -Version 7.2
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\pt-fancyzones-displays.ps1"
. "$PSScriptRoot\..\pt-fancyzones-layout-plan.ps1"
function Require([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
function Rect($Left,$Top,$Right,$Bottom) { [pscustomobject]@{Left=$Left;Top=$Top;Right=$Right;Bottom=$Bottom} }
$desktop = '{11111111-2222-3333-4444-555555555555}'
$monitors = @(
    [pscustomobject]@{Handle=1;Name='Display';Instance='Shared';Serial='Serial';Number=1;Dpi=144
        PhysicalBounds=(Rect -2560 0 0 1440);PhysicalWork=(Rect -2560 0 0 1368)
        LogicalBounds=(Rect -1707 0 0 960);LogicalWork=(Rect -1707 0 0 912)},
    [pscustomobject]@{Handle=2;Name='Display';Instance='Shared';Serial='Serial';Number=2;Dpi=144
        PhysicalBounds=(Rect 0 0 2560 1440);PhysicalWork=(Rect 0 0 2560 1368)
        LogicalBounds=(Rect 0 0 1707 960);LogicalWork=(Rect 0 0 1707 912)}
)
$model = [pscustomobject]@{Monitors=$monitors;CurrentDesktop=$desktop}
$separate = New-PtFancyZonesEditorParameters -DisplayModel $model -HostProcessId 42 -Spanning $false -TargetMonitor 2
$span = New-PtFancyZonesEditorParameters -DisplayModel $model -HostProcessId 42 -Spanning $true -TargetMonitor 2
Require ($separate.monitors.Count -eq 2 -and $span.monitors.Count -eq 1) 'Spanning must replace the monitor model.'
Require ($span.monitors[0].'monitor-width' -eq 5120 -and $span.monitors[0].'work-area-width' -eq 3414) 'Physical and logical widths were conflated.'
Require ($span.monitors[0].'left-coordinate' -eq -1707 -and $span.monitors[0].dpi -eq 0) 'Combined origin/DPI does not match the native input contract.'
Require (-not $separate.monitors[0].'is-selected' -and $separate.monitors[1].'is-selected') 'Target monitor was not resolved by current identity.'
$remote=ConvertFrom-Json ($separate|ConvertTo-Json -Depth 10)
$remote.monitors[0].'monitor-number'=881
$remote.monitors[1].'monitor-number'=882
Require ((Get-PtFancyZonesMonitorOrdinal $remote 882) -eq 2) 'Native remote monitor number was confused with the UI ordinal.'
$layouts = @(foreach ($number in 1,2) {
    [pscustomobject][ordered]@{
        device=(ConvertTo-PtFancyZonesDevice $separate.monitors[$number-1])
        'applied-layout'=[pscustomobject]@{
            uuid="$(if($number -eq 1){'{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}'}else{'{BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB}'})"
            type='columns';'show-spacing'=$true;spacing=16;'zone-count'=$number;'sensitivity-radius'=20
        }
    }
})
$document = [pscustomobject]@{'applied-layouts'=$layouts}
$original = $document | ConvertTo-Json -Depth 15 -Compress
$native = ConvertTo-PtFancyZonesNativeLayouts $document
Require ($native.'applied-layouts'.Count -eq 1 -and $native.'applied-layouts'[0].'applied-layout'.'zone-count' -eq 1) 'Native first-wins identity normalization is wrong.'
$editor = New-PtFancyZonesEditorSavePlan -AppliedLayouts $document -EditorParameters $separate -CustomLayoutIds @()
Require ($editor.'applied-layouts'.Count -eq 2 -and $editor.'applied-layouts'[1].'applied-layout'.'zone-count' -eq 2) 'Editor monitor-number matching was replaced by native identity matching.'
$plan = New-PtFancyZonesWorkAreaPlan -AppliedLayouts $document -EditorParameters $span -DefaultLayouts ([pscustomobject]@{'default-layouts'=@()})
Require ($plan.WritesExpected -and $plan.AddedWorkAreas -eq 1 -and $plan.Document.'applied-layouts'.Count -eq 2) 'Native normalization and combined-work-area creation were not composed.'
$second = New-PtFancyZonesWorkAreaPlan -AppliedLayouts $plan.Document -EditorParameters $span -DefaultLayouts ([pscustomobject]@{'default-layouts'=@()})
Require (-not $second.WritesExpected) 'Existing combined work area caused a fictitious write.'
$defaults = [pscustomobject]@{'default-layouts'=@([pscustomobject]@{
    'monitor-configuration'='horizontal';layout=[pscustomobject]@{uuid='';type='rows'}
})}
$defaultPlan = New-PtFancyZonesWorkAreaPlan -AppliedLayouts $document -EditorParameters $span -DefaultLayouts $defaults
$last = $defaultPlan.Document.'applied-layouts'[-1].'applied-layout'
Require ($last.uuid -eq [guid]::Empty.ToString('B').ToUpperInvariant() -and $last.type -eq 'rows' -and $last.spacing -eq 16) 'Native default-layout values were not preserved.'
Require (($document | ConvertTo-Json -Depth 15 -Compress) -ceq $original) 'Planning changed the input baseline.'
$original=[pscustomobject]@{ZoneMask=3;Frame=(Rect 0 0 600 800)}
$reduced=[pscustomobject]@{ZoneMask=3;Frame=(Rect 0 0 1000 800)}
$returned=[pscustomobject]@{ZoneMask=3;Frame=(Rect 0 0 600 800)}
$observation=Get-PtFancyZonesRelayoutObservation $original $reduced $returned (Rect 0 0 1000 800)
Require ($observation.FitsRemainingZone -and $observation.ReturnsToOriginalGeometry -and $observation.ReturnsToOriginalAssignment) 'Retained requested indices falsely failed correct reduced geometry.'
$reduced.ZoneMask=1;$reduced.Frame=Rect 0 0 400 800
$returned.ZoneMask=1
$observation=Get-PtFancyZonesRelayoutObservation $original $reduced $returned (Rect 0 0 1000 800)
Require (-not $observation.FitsRemainingZone -and -not $observation.ReturnsToOriginalAssignment) 'A desired mask hid incorrect geometry or lost requested indices.'
'PASS: physical/logical topology, negative origin, editor target, native/editor identity differences, combined assignment creation, defaults and immutable inputs.'
