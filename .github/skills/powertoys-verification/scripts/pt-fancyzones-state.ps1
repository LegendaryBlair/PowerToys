#requires -Version 7.2
. "$PSScriptRoot\pt-file-set-snapshot.ps1"

function ConvertTo-PtFancyZonesJsonKey {
    param([System.Text.Json.JsonElement]$Element)
    switch ($Element.ValueKind.ToString()) {
        'Object' {
            $properties = [Collections.Generic.SortedDictionary[string,string]]::new([StringComparer]::Ordinal)
            foreach ($property in $Element.EnumerateObject()) {
                $properties.Add($property.Name, (ConvertTo-PtFancyZonesJsonKey $property.Value))
            }
            '{' + (@(foreach ($key in $properties.Keys) {
                (ConvertTo-Json -InputObject $key -Compress) + ':' + $properties[$key]
            }) -join ',') + '}'
        }
        'Array' {
            '[' + (@(foreach ($item in $Element.EnumerateArray()) {
                ConvertTo-PtFancyZonesJsonKey $item
            }) -join ',') + ']'
        }
        'String' { ConvertTo-Json -InputObject $Element.GetString() -Compress }
        default { $Element.GetRawText() }
    }
}

function Get-PtFancyZonesJsonKey {
    param([Parameter(Mandatory)][string]$Json)
    $document = [System.Text.Json.JsonDocument]::Parse($Json)
    try {
        if ($document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
            throw 'FancyZones state must be a JSON object.'
        }
        ConvertTo-PtFancyZonesJsonKey $document.RootElement
    } finally { $document.Dispose() }
}

function Invoke-PtFancyZonesFileAction {
    <#
    .SYNOPSIS
    Track explicitly planned FancyZones JSON writes around one recorded UI operation.
    .DESCRIPTION
    ExpectedJson maps file names to complete, independently predicted JSON strings (null
    means expected absence). Build it before acting, using the requested settings/layout
    and fresh work-area model, not the old monitor array or the post-action file.
    Only whitespace and object property order are ignored; numbers and array order stay exact.
    Editor entry can write both parameters and assignments. Spanning replaces the monitor
    model; it need not preserve monitor count, identity, DPI or coordinate units.

    The caller establishes process/window ownership, settles writers around snapshots,
    records Action, and privately persists ExpectedState even when this function throws.
    ExpectedState is a private recovery snapshot, not public evidence. The original
    baseline is never mutated. Confirmed files advance independently; unconfirmed files
    retain their previous expectations and still fail the unchanged rollback guard.
    This is not a writer lock, an ownership grant, a product assertion or conflict recovery.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ref]$ExpectedState,
        [Parameter(Mandatory)][ValidateSet('EditorOpen','EditorClose','SpanChange')][string]$Operation,
        [Parameter(Mandatory)][Collections.IDictionary]$ExpectedJson,
        [Parameter(Mandatory)][scriptblock]$Action,
        [object[]]$ArgumentList = @(),
        [ValidateRange(1,2147483647)][long]$MaxBytes = 8MB
    )
    $previous = $ExpectedState.Value | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $previousMap = ConvertTo-PtFileSetSnapshotMap $previous $MaxBytes
    $allowed = switch ($Operation) {
        'EditorOpen' { @('editor-parameters.json','applied-layouts.json') }
        'EditorClose' { @('editor-parameters.json','applied-layouts.json','custom-layouts.json',
            'default-layouts.json','layout-hotkeys.json','layout-templates.json') }
        'SpanChange' { @('settings.json','editor-parameters.json','applied-layouts.json') }
    }
    $planned = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($name in $ExpectedJson.Keys) {
        if ($name -cnotin $previous.FileNames -or $name -cnotin $allowed) {
            throw "File is outside the declared FancyZones operation: $name"
        }
        $json = $ExpectedJson[$name]
        if ($null -ne $json -and $json -isnot [string]) { throw 'Expected JSON must be a pre-action string or null.' }
        $planned.Add($name, $(if ($null -eq $json) { $null } else { Get-PtFancyZonesJsonKey $json }))
    }
    $before = Get-PtFileSetSnapshot -Path $previous.FileState.Path -FileNames $previous.FileNames -MaxBytes $MaxBytes
    $beforeMap = ConvertTo-PtFileSetSnapshotMap $before $MaxBytes
    foreach ($name in $previous.FileNames) {
        if (-not (Test-PtDirectoryEntryEqual $previousMap[$name] $beforeMap[$name])) {
            throw "Pre-action state conflict; no action performed: $name"
        }
    }

    $actionError = $null
    try { & $Action @ArgumentList | Out-Null } catch { $actionError = $_ }
    $after = Get-PtFileSetSnapshot -Path $previous.FileState.Path -FileNames $previous.FileNames -MaxBytes $MaxBytes
    $afterMap = ConvertTo-PtFileSetSnapshotMap $after $MaxBytes
    $confirmed = [Collections.Generic.List[string]]::new()
    $unconfirmed = [Collections.Generic.List[string]]::new()
    $retained = [Collections.Generic.List[object]]::new()
    foreach ($name in $previous.FileNames) {
        $valid = Test-PtDirectoryEntryEqual $previousMap[$name] $afterMap[$name]
        if ($planned.ContainsKey($name)) {
            $actual = $afterMap[$name]
            if ($null -eq $planned[$name]) {
                $valid = $null -eq $actual
            } elseif ($null -eq $actual) {
                $valid = $false
            } else {
                try {
                    $text = [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String($actual.Base64))
                    $valid = (Get-PtFancyZonesJsonKey $text.TrimStart([char]0xFEFF)) -ceq $planned[$name]
                } catch { $valid = $false }
            }
        }
        if ($valid) {
            if (-not (Test-PtDirectoryEntryEqual $previousMap[$name] $afterMap[$name])) { $confirmed.Add($name) }
            if ($null -ne $afterMap[$name]) { $retained.Add($afterMap[$name]) }
        } else {
            $unconfirmed.Add($name)
            if ($null -ne $previousMap[$name]) { $retained.Add($previousMap[$name]) }
        }
    }
    $next = $previous | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $next.FileState.Files = @($retained | Select-Object RelativePath,Length,Sha256,Base64)
    $ExpectedState.Value = $next
    $receipt = [pscustomobject]@{
        Operation = $Operation
        ConfirmedFiles = @($confirmed)
        UnconfirmedFiles = @($unconfirmed)
        ActionSucceeded = $null -eq $actionError
    }
    if ($unconfirmed.Count) {
        $failure = [InvalidOperationException]::new("Unconfirmed FancyZones changes; dependent actions must stop: $($unconfirmed -join ', ')")
        $failure.Data['PtFancyZonesFileActionReceipt'] = $receipt
        if ($actionError) { $failure.Data['ActionError'] = $actionError.Exception.Message }
        throw $failure
    }
    if ($actionError) {
        $actionError.Exception.Data['PtFancyZonesFileActionReceipt'] = $receipt
        throw $actionError
    }
    $receipt
}
