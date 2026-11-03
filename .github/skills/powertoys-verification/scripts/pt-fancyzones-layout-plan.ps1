#requires -Version 7.2
. "$PSScriptRoot\pt-fancyzones-state.ps1"

function ConvertTo-PtFancyZonesDevice {
    param([Parameter(Mandatory)]$Monitor)
    [pscustomobject][ordered]@{
        monitor=[string]$Monitor.monitor
        'monitor-instance'=[string]$Monitor.'monitor-instance-id'
        'monitor-number'=[int]$Monitor.'monitor-number'
        'serial-number'=[string]$Monitor.'monitor-serial-number'
        'virtual-desktop'=([guid]$Monitor.'virtual-desktop').ToString('B').ToUpperInvariant()
    }
}

function Test-PtFancyZonesNativeDevice {
    param($Left, $Right)
    if ([guid]$Left.'virtual-desktop' -ne [guid]$Right.'virtual-desktop' -or
        $Left.monitor -cne $Right.monitor) { return $false }
    if ($Left.'serial-number' -and $Right.'serial-number' -and
        $Left.'serial-number' -cne $Right.'serial-number') { return $false }
    if ([string]$Left.'monitor-instance' -cne [string]$Right.'monitor-instance') {
        return $Left.'monitor-number' -eq $Right.'monitor-number'
    }
    return $true
}

function ConvertTo-PtFancyZonesLayout {
    param([Parameter(Mandatory)]$Layout, [switch]$DefaultValues)
    if ($Layout.type -cnotin @('blank','focus','columns','rows','grid','priority-grid','custom')) {
        throw 'Unsupported layout type in serialization plan.'
    }
    [pscustomobject][ordered]@{
        uuid=$(if ($DefaultValues -and -not $Layout.uuid) { [guid]::Empty.ToString('B').ToUpperInvariant() } else { ([guid]$Layout.uuid).ToString('B').ToUpperInvariant() })
        type=[string]$Layout.type
        'show-spacing'=$(if ($DefaultValues -and -not $Layout.PSObject.Properties['show-spacing']) { $true } else { [bool]$Layout.'show-spacing' })
        spacing=$(if ($DefaultValues -and -not $Layout.PSObject.Properties['spacing']) { 16 } else { [int]$Layout.spacing })
        'zone-count'=$(if ($DefaultValues -and -not $Layout.PSObject.Properties['zone-count']) { 3 } else { [int]$Layout.'zone-count' })
        'sensitivity-radius'=$(if ($Layout.PSObject.Properties['sensitivity-radius']) { [int]$Layout.'sensitivity-radius' } else { 20 })
    }
}

function ConvertTo-PtFancyZonesNativeLayouts {
    <#.SYNOPSIS
    Project modern assignment JSON through the native reader's first-wins identity map.
    .NOTES
    Native device identity is not the editor's monitor-number-based matching rule.
    This projection alone neither authorizes a write nor proves its producing action.
    #>
    param([Parameter(Mandatory)]$Document)
    $records = [Collections.Generic.List[object]]::new()
    foreach ($record in $Document.'applied-layouts') {
        if (-not $record.device -or -not $record.'applied-layout') {
            throw 'Legacy or malformed assignments need a separate sourced plan.'
        }
        $device = $record.device
        $instance = [string]$device.'monitor-instance'
        $name = [string]$device.monitor
        if (-not $instance -and $name.Contains('#')) {
            $parts = $name.Split('#', 2)
            $name = $parts[0]; $instance = $parts[1]
        }
        $normalized = [pscustomobject][ordered]@{
            device=[pscustomobject][ordered]@{
                monitor=$name; 'monitor-instance'=$instance
                'monitor-number'=[int]$device.'monitor-number'; 'serial-number'=[string]$device.'serial-number'
                'virtual-desktop'=([guid]$device.'virtual-desktop').ToString('B').ToUpperInvariant()
            }
            'applied-layout'=(ConvertTo-PtFancyZonesLayout $record.'applied-layout')
        }
        if (-not @($records | Where-Object { Test-PtFancyZonesNativeDevice $_.device $normalized.device }).Count) {
            $records.Add($normalized)
        }
    }
    [pscustomobject]@{ 'applied-layouts'=@($records) }
}

function New-PtFancyZonesWorkAreaPlan {
    <#.SYNOPSIS
    Predict native default-work-area additions after a spanning transition.
    .NOTES
    Requires the immediately preceding assignments and current default-layout document.
    It does not model a process restart or a virtual-desktop migration.
    #>
    param(
        [Parameter(Mandatory)]$AppliedLayouts,
        [Parameter(Mandatory)]$EditorParameters,
        [Parameter(Mandatory)]$DefaultLayouts
    )
    $map = ConvertTo-PtFancyZonesNativeLayouts $AppliedLayouts
    $records = [Collections.Generic.List[object]]::new()
    foreach ($record in $map.'applied-layouts') { $records.Add($record) }
    $added = 0
    foreach ($monitor in $EditorParameters.monitors) {
        $device = ConvertTo-PtFancyZonesDevice $monitor
        if (@($records | Where-Object { Test-PtFancyZonesNativeDevice $_.device $device }).Count) { continue }
        $orientation = if (-not $EditorParameters.'span-zones-across-monitors' -and
            $monitor.'monitor-height' -gt $monitor.'monitor-width') { 'vertical' } else { 'horizontal' }
        $defaults = @($DefaultLayouts.'default-layouts' | Where-Object 'monitor-configuration' -CEQ $orientation)
        $layout = if ($defaults.Count) {
            ConvertTo-PtFancyZonesLayout $defaults[-1].layout -DefaultValues
        } else {
            [pscustomobject][ordered]@{
                uuid=[guid]::Empty.ToString('B').ToUpperInvariant()
                type=$(if ($orientation -eq 'vertical') { 'rows' } else { 'priority-grid' })
                'show-spacing'=$true; spacing=16; 'zone-count'=3; 'sensitivity-radius'=20
            }
        }
        $records.Add([pscustomobject][ordered]@{ device=$device; 'applied-layout'=$layout })
        $added++
    }
    [pscustomobject]@{
        WritesExpected=($added -gt 0)
        Document=$(if ($added) { [pscustomobject]@{ 'applied-layouts'=@($records) } } else { $AppliedLayouts })
        AddedWorkAreas=$added
    }
}

function New-PtFancyZonesEditorSavePlan {
    <#.SYNOPSIS
    Project editor assignment serialization: last matching monitor record, then unused records.
    .NOTES
    Pass the editor's actual current monitor layout settings as Overrides after an owned UI
    edit. Missing-custom-layout substitution is deliberately not inferred from a new GUID.
    #>
    param(
        [Parameter(Mandatory)]$AppliedLayouts,
        [Parameter(Mandatory)]$EditorParameters,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$CustomLayoutIds,
        [object[]]$Overrides = @()
    )
    $records = @($AppliedLayouts.'applied-layouts')
    $used = [Collections.Generic.HashSet[int]]::new()
    $output = [Collections.Generic.List[object]]::new()
    foreach ($monitor in $EditorParameters.monitors) {
        $device = ConvertTo-PtFancyZonesDevice $monitor
        $layout = $null
        for ($i=0; $i -lt $records.Count; $i++) {
            $prior = $records[$i].device
            if ($prior.monitor -ceq $device.monitor -and
                [string]$prior.'serial-number' -ceq [string]$device.'serial-number' -and
                [int]$prior.'monitor-number' -eq [int]$device.'monitor-number' -and
                ([guid]$prior.'virtual-desktop' -eq [guid]$device.'virtual-desktop' -or
                    [guid]$prior.'virtual-desktop' -eq [guid]::Empty)) {
                $layout = ConvertTo-PtFancyZonesLayout $records[$i].'applied-layout'
                [void]$used.Add($i)
            }
        }
        foreach ($change in $Overrides) {
            if ((Get-PtFancyZonesJsonKey ($change.device | ConvertTo-Json -Compress)) -ceq
                (Get-PtFancyZonesJsonKey ($device | ConvertTo-Json -Compress))) {
                $layout = ConvertTo-PtFancyZonesLayout $change.'applied-layout'
            }
        }
        if ($null -eq $layout) { continue }
        if ($layout.type -ceq 'custom' -and $layout.uuid -cnotin $CustomLayoutIds) {
            throw 'A missing custom layout requires its observed editor substitution before serialization.'
        }
        $output.Add([pscustomobject][ordered]@{ device=$device; 'applied-layout'=$layout })
    }
    for ($i=0; $i -lt $records.Count; $i++) {
        if (-not $used.Contains($i)) { $output.Add($records[$i]) }
    }
    [pscustomobject]@{ 'applied-layouts'=@($output) }
}
