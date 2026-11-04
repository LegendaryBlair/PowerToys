#requires -Version 7.2
. "$PSScriptRoot\pt-fancyzones-layout-plan.ps1"
. "$PSScriptRoot\pt-verification-report.ps1"

function Get-PtFancyZonesSnapshotJson {
    param([Parameter(Mandatory)]$Snapshot, [Parameter(Mandatory)][string]$FileName)
    $entries = @($Snapshot.FileState.Files | Where-Object RelativePath -CEQ $FileName)
    if ($entries.Count -eq 0) { return $null }
    if ($entries.Count -ne 1) { throw 'Snapshot entry is not unique.' }
    ConvertFrom-PtReportJson ([Text.UTF8Encoding]::new($false, $true).GetString(
        [Convert]::FromBase64String($entries[0].Base64)).TrimStart([char]0xFEFF))
}

function Test-PtFancyZonesJsonEqual {
    param($Left, $Right)
    if ($null -eq $Left -or $null -eq $Right) { return $null -eq $Left -and $null -eq $Right }
    (Get-PtFancyZonesJsonKey ($Left | ConvertTo-Json -Depth 80 -Compress)) -ceq
        (Get-PtFancyZonesJsonKey ($Right | ConvertTo-Json -Depth 80 -Compress))
}

function Wait-PtFancyZonesPersistence {
    <#.SYNOPSIS
    Wait for declared persistence readiness and stable selected bytes without adopting them.
    .NOTES
    Snapshots remain private. Stability is a bounded readiness signal, not a writer lock or
    permission to replace expected state. Attribution still runs in the enclosing action.
    #>
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][scriptblock]$Ready,
        [object[]]$ArgumentList=@(),[ValidateRange(0.1,30)][double]$TimeoutSeconds=8)
    $poll=@{Signature=$null;Stable=0;Samples=0;Ready=$false}
    try {
        Wait-PtCondition -Description 'declared FancyZones persistence and selected-file stability' -TimeoutSeconds $TimeoutSeconds -Probe {
            $snapshot=Get-PtFileSetSnapshot -Path $Context.ModuleRoot -FileNames $Context.ExpectedModule.FileNames -MaxBytes 8MB
            $poll.Samples++
            $signature=ConvertTo-Json -InputObject @($snapshot.FileState.Files|Select-Object RelativePath,Length,Sha256) -Compress
            $readyResult=@(& $Ready $snapshot @ArgumentList)
            if($readyResult.Count -ne 1 -or $readyResult[0] -isnot [bool]){throw 'Persistence readiness must return exactly one Boolean.'}
            $poll.Ready=$readyResult[0]
            if($poll.Ready){
                if($signature -ceq $poll.Signature){$poll.Stable++}else{$poll.Stable=1}
            }else{$poll.Stable=0}
            $poll.Signature=$signature
            if($poll.Ready -and $poll.Stable -ge 3){
                [pscustomobject]@{Ready=$true;Samples=$poll.Samples;StableSamples=3}
            }
        }
    } catch {
        $_.Exception.Data['FancyZonesPersistenceReadiness']=[pscustomobject]@{
            Samples=$poll.Samples;Ready=$poll.Ready;StableSamples=$poll.Stable
        }
        throw
    }
}

function Test-PtFancyZonesScopedFileChange {
    <#
    .SYNOPSIS
    Attribute only a predeclared operation's owned records, not its desired product result.
    .NOTES
    A wrong result inside an owned record can still be observed as a product FAIL and
    restored. Unowned records cannot be silently accepted as part of that result.
    Scope must be frozen before input and backed by resource/creation receipts.
    #>
    param(
        [Parameter(Mandatory)][string]$FileName,
        $Before,
        $After,
        [Parameter(Mandatory)]$Scope
    )
    if (Test-PtFancyZonesJsonEqual $Before $After) { return $true }
    if ($null -eq $After) { return $false }
    if ($FileName -ceq 'editor-parameters.json') {
        return $Scope.GeneratedEditorInput -eq $true -and
            $Scope.HostProcessId -gt 0 -and $After.'process-id' -eq $Scope.HostProcessId -and
            $After.'span-zones-across-monitors' -is [bool] -and $After.monitors -is [array] -and
            $After.monitors.Count -gt 0 -and @($After.PSObject.Properties).Count -eq 3
    }
    if ($null -eq $Before) {
        $array = switch -CaseSensitive ($FileName) {
            'custom-layouts.json' { if ($Scope.NewLayoutName) { 'custom-layouts' } }
            'app-zone-history.json' { if (@($Scope.ApplicationPaths).Count) { 'app-zone-history' } }
            'applied-layouts.json' { if (@($Scope.WorkAreas).Count) { 'applied-layouts' } }
            'layout-hotkeys.json' { if (@($Scope.HotkeyDigits).Count) { 'layout-hotkeys' } }
            'default-layouts.json' { if (@($Scope.DefaultOrientations).Count) { 'default-layouts' } }
            'layout-templates.json' { if (@($Scope.TemplateTypes).Count) { 'layout-templates' } }
        }
        if ($FileName -ceq 'last-used-virtual-desktop.json' -and $Scope.TargetDesktop) {
            return $After.'last-used-virtual-desktop' -ceq $Scope.TargetDesktop -and @($After.PSObject.Properties).Count -eq 1
        }
        if (-not $array) { return $false }
        $Before = [pscustomobject]@{ $array=@() }
    }
    $old = ConvertFrom-PtReportJson ($Before | ConvertTo-Json -Depth 80 -Compress)
    $new = ConvertFrom-PtReportJson ($After | ConvertTo-Json -Depth 80 -Compress)
    switch -CaseSensitive ($FileName) {
        'settings.json' {
            foreach ($key in @($Scope.SettingKeys)) {
                $old.properties.PSObject.Properties.Remove($key)
                $new.properties.PSObject.Properties.Remove($key)
            }
        }
        'applied-layouts.json' {
            if ($Scope.NativeSerialization) {
                $old.'applied-layouts' = (ConvertTo-PtFancyZonesNativeLayouts $old).'applied-layouts'
                $normalized = (ConvertTo-PtFancyZonesNativeLayouts $new).'applied-layouts'
                if (@($normalized).Count -ne @($new.'applied-layouts').Count) { return $false }
                for ($i=0; $i -lt @($normalized).Count; $i++) {
                    if (-not (Test-PtFancyZonesJsonEqual $normalized[$i] $new.'applied-layouts'[$i])) { return $false }
                }
            }
            foreach ($document in @($old,$new)) {
                $unowned = @(foreach ($record in $document.'applied-layouts') {
                    $owned = @($Scope.WorkAreas | Where-Object { Test-PtFancyZonesNativeDevice $_ $record.device }).Count -gt 0
                    if (-not $owned) { $record }
                })
                $document.'applied-layouts' = @($unowned | Sort-Object {
                    Get-PtFancyZonesJsonKey ($_ | ConvertTo-Json -Depth 30 -Compress)
                })
            }
        }
        'custom-layouts.json' {
            $oldIds = @($old.'custom-layouts' | ForEach-Object uuid)
            $newIds = @($new.'custom-layouts' | ForEach-Object uuid)
            if (@($newIds | Sort-Object -Unique).Count -ne $newIds.Count) { return $false }
            $created = @($new.'custom-layouts' | Where-Object uuid -CNotIn $oldIds)
            if ($created.Count) {
                if ($created.Count -ne 1 -or -not $Scope.NewLayoutName -or
                    $created[0].name -cne $Scope.NewLayoutName -or
                    $created[0].type -cne $Scope.NewLayoutType) { return $false }
                $id = [guid]::Empty
                if (-not [guid]::TryParse($created[0].uuid, [ref]$id) -or $id -eq [guid]::Empty) { return $false }
            }
            $owned = @($Scope.LayoutIds | Where-Object { $_ }) + @($created | ForEach-Object uuid)
            $old.'custom-layouts' = @($old.'custom-layouts' | Where-Object uuid -CNotIn $owned)
            $new.'custom-layouts' = @($new.'custom-layouts' | Where-Object uuid -CNotIn $owned)
        }
        'app-zone-history.json' {
            $old.'app-zone-history' = @($old.'app-zone-history' | Where-Object 'app-path' -NotIn @($Scope.ApplicationPaths))
            $new.'app-zone-history' = @($new.'app-zone-history' | Where-Object 'app-path' -NotIn @($Scope.ApplicationPaths))
        }
        'layout-hotkeys.json' {
            $old.'layout-hotkeys' = @($old.'layout-hotkeys' | Where-Object key -NotIn @($Scope.HotkeyDigits))
            $new.'layout-hotkeys' = @($new.'layout-hotkeys' | Where-Object key -NotIn @($Scope.HotkeyDigits))
        }
        'default-layouts.json' {
            if($Scope.PSObject.Properties['PredictedDefaults']){
                return Test-PtFancyZonesJsonEqual $Scope.PredictedDefaults $After
            }
            $old.'default-layouts' = @($old.'default-layouts' | Where-Object 'monitor-configuration' -CNotIn @($Scope.DefaultOrientations))
            $new.'default-layouts' = @($new.'default-layouts' | Where-Object 'monitor-configuration' -CNotIn @($Scope.DefaultOrientations))
        }
        'layout-templates.json' {
            $old.'layout-templates' = @($old.'layout-templates' | Where-Object type -CNotIn @($Scope.TemplateTypes))
            $new.'layout-templates' = @($new.'layout-templates' | Where-Object type -CNotIn @($Scope.TemplateTypes))
        }
        'last-used-virtual-desktop.json' {
            return $Scope.TargetDesktop -and
                $After.'last-used-virtual-desktop' -ceq $Scope.TargetDesktop -and
                @($After.PSObject.Properties).Count -eq 1
        }
        default { return $false }
    }
    Test-PtFancyZonesJsonEqual $old $new
}

function Invoke-PtFancyZonesScopedAction {
    <#
    .SYNOPSIS
    Execute one owned UI operation and retain only its independently scoped file changes.
    .DESCRIPTION
    Scope declares owned layout/work-area/application identities and selected setting keys.
    It is deep-copied before Action. Ownership must come from the resource session and
    preceding creation receipts, never from these snapshots. Caller privately persists
    ExpectedState in finally and records the action through the shared recorder.
    No prior-run conflict can be adopted: the current pre-state must match this run's
    expected state byte-for-byte before any UI operation is dispatched.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ref]$ExpectedState,
        [Parameter(Mandatory)]$Scope,
        [Parameter(Mandatory)][scriptblock]$Action,
        [object[]]$ArgumentList=@(),
        [ValidateRange(1,2147483647)][long]$MaxBytes=8MB
    )
    $frozen = ConvertFrom-PtReportJson ($Scope | ConvertTo-Json -Depth 30 -Compress)
    foreach ($key in @('WorkAreas','LayoutIds','ApplicationPaths','SettingKeys','HotkeyDigits','DefaultOrientations','TemplateTypes')) {
        $values = @($frozen.$key | Where-Object { $null -ne $_ })
        $frozen | Add-Member -MemberType NoteProperty -Name $key -Value $values -Force
    }
    $previous = ConvertFrom-PtReportJson ($ExpectedState.Value | ConvertTo-Json -Depth 10 -Compress)
    $oldMap = ConvertTo-PtFileSetSnapshotMap $previous $MaxBytes
    $now = Get-PtFileSetSnapshot -Path $previous.FileState.Path -FileNames $previous.FileNames -MaxBytes $MaxBytes
    $nowMap = ConvertTo-PtFileSetSnapshotMap $now $MaxBytes
    foreach ($name in $previous.FileNames) {
        if (-not (Test-PtDirectoryEntryEqual $oldMap[$name] $nowMap[$name])) {
            throw "Pre-action file conflict; no input dispatched: $name"
        }
    }
    $actionError = $null
    try { & $Action @ArgumentList | Out-Null } catch { $actionError = $_ }
    $after = Get-PtFileSetSnapshot -Path $previous.FileState.Path -FileNames $previous.FileNames -MaxBytes $MaxBytes
    $afterMap = ConvertTo-PtFileSetSnapshotMap $after $MaxBytes
    $accepted = [Collections.Generic.List[string]]::new()
    $conflicts = [Collections.Generic.List[string]]::new()
    $files = [Collections.Generic.List[object]]::new()
    foreach ($name in $previous.FileNames) {
        $valid = Test-PtDirectoryEntryEqual $oldMap[$name] $afterMap[$name]
        if (-not $valid) {
            try {
                $valid = Test-PtFancyZonesScopedFileChange -FileName $name -Scope $frozen `
                    -Before (Get-PtFancyZonesSnapshotJson $previous $name) -After (Get-PtFancyZonesSnapshotJson $after $name)
            } catch { $valid = $false }
            if ($valid) { $accepted.Add($name) } else { $conflicts.Add($name) }
        }
        $entry = if ($valid) { $afterMap[$name] } else { $oldMap[$name] }
        if ($null -ne $entry) { $files.Add($entry) }
    }
    $previous.FileState.Files = @($files | Select-Object RelativePath,Length,Sha256,Base64)
    $ExpectedState.Value = $previous
    $receipt = [pscustomobject]@{ConfirmedFiles=@($accepted);Conflicts=@($conflicts);ActionSucceeded=($null -eq $actionError)}
    if ($conflicts.Count) {
        $error = [InvalidOperationException]::new("Unattributed FancyZones file changes: $($conflicts -join ', ')")
        $error.Data['PtFancyZonesMutationReceipt'] = $receipt
        if ($actionError) { $error.Data['ActionError'] = $actionError.Exception.Message }
        throw $error
    }
    if ($actionError) {
        $actionError.Exception.Data['PtFancyZonesMutationReceipt'] = $receipt
        throw $actionError
    }
    $receipt
}
