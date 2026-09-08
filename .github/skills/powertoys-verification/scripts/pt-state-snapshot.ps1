# Paired snapshots. These functions never restart apps or infer which resources a case owns.

function Get-PtFileSnapshot {
    <# .SYNOPSIS
    Capture exact file bytes and absence. Persist the returned object before a mutation.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (Test-Path -LiteralPath $fullPath -PathType Container) { throw "Expected a file, not a directory: $fullPath" }
    $exists = Test-Path -LiteralPath $fullPath -PathType Leaf
    [pscustomobject]@{
        path = $fullPath
        exists = $exists
        base64 = $(if ($exists) { [Convert]::ToBase64String([IO.File]::ReadAllBytes($fullPath)) } else { $null })
    }
}

function Restore-PtFileSnapshot {
    <# .SYNOPSIS
    Restore bytes/existence without consuming the backup; safe to repeat after partial failure.
    #>
    param([Parameter(Mandatory)]$Snapshot)
    $current = Get-PtFileSnapshot -Path $Snapshot.path
    if ($current.exists -eq $Snapshot.exists -and $current.base64 -ceq $Snapshot.base64) { return $current }
    if (Test-Path -LiteralPath $Snapshot.path -PathType Container) { throw "Restore conflict: a directory occupies $($Snapshot.path)." }
    if ($Snapshot.exists) {
        [IO.File]::WriteAllBytes($Snapshot.path, [Convert]::FromBase64String($Snapshot.base64))
    } elseif (Test-Path -LiteralPath $Snapshot.path -PathType Leaf) {
        Remove-Item -LiteralPath $Snapshot.path -ErrorAction Stop
    }
    $actual = Get-PtFileSnapshot -Path $Snapshot.path
    if ($actual.exists -ne $Snapshot.exists -or $actual.base64 -cne $Snapshot.base64) { throw "File restore did not match: $($Snapshot.path)" }
    $actual
}

function Get-PtRegistrySnapshot {
    <#
    .SYNOPSIS
    Capture explicitly selected HKCU value names, kinds and raw values, never a provider object.
    .NOTES
    Other values/subkeys are outside the restore scope. Do not use registry writes to restore
    taskbar pin/order state; that must be restored through normal taskbar UI.
    #>
    param([Parameter(Mandatory)][string]$SubKey, [Parameter(Mandatory)][AllowEmptyString()][string[]]$ValueNames)
    if (-not $SubKey.Trim('\') -or $SubKey.StartsWith('\')) { throw 'Specify a non-root HKCU subkey.' }
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($SubKey, $false)
    try {
        $names = if ($null -ne $key) { $key.GetValueNames() } else { @() }
        $values = @(foreach ($name in $ValueNames) {
            $exists = $names -contains $name
            $kind = if ($exists) { $key.GetValueKind($name).ToString() } else { $null }
            $raw = if ($exists) { ,$key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } else { $null }
            [pscustomobject]@{
                name = $name; exists = $exists; kind = $kind
                value = $(if ($kind -in 'Binary','None') { [Convert]::ToBase64String([byte[]]$raw) }
                    elseif ($kind -eq 'MultiString') { ,([string[]]$raw) } else { $raw })
            }
        })
        [pscustomobject]@{ subKey = $SubKey; keyExists = ($null -ne $key); values = $values }
    } finally { if ($null -ne $key) { $key.Dispose() } }
}

function Restore-PtRegistrySnapshot {
    <# .SYNOPSIS
    Restore only captured HKCU values; retain unrelated values and detect key-existence conflicts.
    #>
    param([Parameter(Mandatory)]$Snapshot)
    if (-not $Snapshot.subKey.Trim('\') -or $Snapshot.subKey.StartsWith('\')) { throw 'Refusing a root registry restore.' }
    $current = Get-PtRegistrySnapshot -SubKey $Snapshot.subKey -ValueNames @($Snapshot.values.name)
    if (($current | ConvertTo-Json -Depth 10 -Compress) -ceq ($Snapshot | ConvertTo-Json -Depth 10 -Compress)) { return $current }
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Snapshot.subKey, $true)
    if ($null -eq $key -and ($Snapshot.keyExists -or @($Snapshot.values | Where-Object exists).Count)) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($Snapshot.subKey)
    }
    if ($null -ne $key) {
        try {
            foreach ($value in $Snapshot.values) {
                if (-not $value.exists) { $key.DeleteValue($value.name, $false); continue }
                $kind = [Microsoft.Win32.RegistryValueKind]$value.kind
                $raw = switch ($value.kind) {
                    { $_ -in 'Binary','None' } { ,([Convert]::FromBase64String($value.value)); break }
                    'DWord' { [int]$value.value; break }
                    'QWord' { [long]$value.value; break }
                    'MultiString' { ,([string[]]$value.value); break }
                    default { [string]$value.value }
                }
                $key.SetValue($value.name, $raw, $kind)
            }
            $empty = $key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0
        } finally { $key.Dispose() }
        if (-not $Snapshot.keyExists) {
            if (-not $empty) { throw "Registry restore conflict: new unrelated contents remain in HKCU\$($Snapshot.subKey)." }
            [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKey($Snapshot.subKey, $false)
        }
    }
    $actual = Get-PtRegistrySnapshot -SubKey $Snapshot.subKey -ValueNames @($Snapshot.values.name)
    if (($actual | ConvertTo-Json -Depth 10 -Compress) -cne ($Snapshot | ConvertTo-Json -Depth 10 -Compress)) {
        throw "Registry restore did not match: HKCU\$($Snapshot.subKey)"
    }
    $actual
}

function Get-PtWindowIdentity {
    <# .SYNOPSIS
    Track HWND, owner PID, process start time and class; a recycled PID/HWND is not the same target.
    #>
    param([Parameter(Mandatory)][long]$Hwnd)
    $window = Get-PtNativeWindow -Hwnd $Hwnd
    $process = Get-Process -Id $window.ProcessId -ErrorAction Stop
    [pscustomobject]@{
        hwnd = $Hwnd; processId = $window.ProcessId
        processStartTicks = $process.StartTime.ToUniversalTime().Ticks
        className = $window.ClassName
    }
}

function Assert-PtWindowIdentity {
    <# .SYNOPSIS
    Reject stale/replaced windows before restoration or closing a tracked fixture.
    #>
    param([Parameter(Mandatory)]$Identity)
    $current = Get-PtWindowIdentity -Hwnd $Identity.hwnd
    if (($current | ConvertTo-Json -Compress) -cne ($Identity | ConvertTo-Json -Compress)) {
        throw "Window identity changed; refusing to act on HWND $($Identity.hwnd)."
    }
}

function Get-PtWindowSnapshot {
    <# .SYNOPSIS
    Capture complete native WINDOWPLACEMENT and visibility, not just the rendered rectangle.
    #>
    param([Parameter(Mandatory)][long]$Hwnd)
    $identity = Get-PtWindowIdentity -Hwnd $Hwnd
    [pscustomobject]@{
        identity = $identity
        placement = [PtDesktop]::Placement([IntPtr]$Hwnd)
        visible = [PtDesktop]::IsWindowVisible([IntPtr]$Hwnd)
    }
}

function Restore-PtWindowSnapshot {
    <# .SYNOPSIS
    Restore a surviving tracked window. Never substitute another window by title/process name.
    #>
    param([Parameter(Mandatory)]$Snapshot)
    Assert-PtWindowIdentity -Identity $Snapshot.identity
    $h = [IntPtr][long]$Snapshot.identity.hwnd
    $original = $Snapshot.placement
    $placement = [PtDesktop+PLACEMENT]::new()
    $placement.flags = $original.flags
    $placement.showCmd = $original.showCmd
    # Assign nested value types whole: changing a boxed field would only modify a copy.
    $placement.ptMinPosition = [PtDesktop+POINT]@{ X = $original.ptMinPosition.X; Y = $original.ptMinPosition.Y }
    $placement.ptMaxPosition = [PtDesktop+POINT]@{ X = $original.ptMaxPosition.X; Y = $original.ptMaxPosition.Y }
    $placement.rcNormalPosition = [PtDesktop+RECT]@{
        Left = $original.rcNormalPosition.Left; Top = $original.rcNormalPosition.Top
        Right = $original.rcNormalPosition.Right; Bottom = $original.rcNormalPosition.Bottom
    }
    [PtDesktop]::Place($h, $placement)
    if (-not $Snapshot.visible) { [void][PtDesktop]::ShowWindow($h, 0) }
    $expected = $Snapshot | ConvertTo-Json -Depth 8 -Compress
    $actual = Get-PtWindowSnapshot -Hwnd $h.ToInt64()
    if (($actual | ConvertTo-Json -Depth 8 -Compress) -cne $expected -and
        $original.ptMinPosition.X -eq -32000 -and $original.ptMinPosition.Y -eq -32000) {
        [void][PtDesktop]::ShowWindow($h, 6)
        [void][PtDesktop]::ShowWindow($h, $original.showCmd)
        if (-not $Snapshot.visible) { [void][PtDesktop]::ShowWindow($h, 0) }
    }
    Wait-PtCondition -Description "complete placement restoration for HWND $h" -TimeoutSeconds 3 -Probe {
        $actual = Get-PtWindowSnapshot -Hwnd $h.ToInt64()
        if (($actual | ConvertTo-Json -Depth 8 -Compress) -ceq $expected) { $actual }
    }
}

function Get-PtDesktopSnapshot {
    <# .SYNOPSIS
    Capture only explicitly affected windows plus original foreground identity and pointer.
    #>
    param([long[]]$WindowHwnd = @())
    $foreground = [PtDesktop]::GetForegroundWindow().ToInt64()
    if (-not $foreground) { throw 'Cannot capture desktop baseline without a foreground window.' }
    $point = [PtDesktop+POINT]::new()
    if (-not [PtDesktop]::GetCursorPos([ref]$point)) { throw 'Cannot capture pointer position.' }
    [pscustomobject]@{
        foreground = Get-PtWindowIdentity -Hwnd $foreground
        pointer = $point
        windows = @(foreach ($h in $WindowHwnd) { Get-PtWindowSnapshot -Hwnd $h })
    }
}

function Restore-PtDesktopSnapshot {
    <# .SYNOPSIS
    Attempt every restoration, then surface all errors; never mask partial cleanup as success.
    #>
    param([Parameter(Mandatory)]$Snapshot)
    $errors = [Collections.Generic.List[string]]::new()
    foreach ($window in $Snapshot.windows) {
        try { Restore-PtWindowSnapshot -Snapshot $window | Out-Null }
        catch { $errors.Add($_.Exception.Message) }
    }
    try {
        Assert-PtWindowIdentity -Identity $Snapshot.foreground
        Assert-PtForegroundOrAbort -Hwnd $Snapshot.foreground.hwnd
    } catch { $errors.Add($_.Exception.Message) }
    if (-not [PtDesktop]::SetCursorPos($Snapshot.pointer.X, $Snapshot.pointer.Y)) { $errors.Add('Pointer restore failed.') }
    $point = [PtDesktop+POINT]::new()
    if (-not [PtDesktop]::GetCursorPos([ref]$point) -or $point.X -ne $Snapshot.pointer.X -or $point.Y -ne $Snapshot.pointer.Y) {
        $errors.Add('Pointer restore comparison failed.')
    }
    if ($errors.Count) { throw "Desktop restoration incomplete: $($errors -join '; ')" }
    Get-PtDesktopSnapshot -WindowHwnd @(foreach ($window in $Snapshot.windows) { $window.identity.hwnd })
}

function Close-PtTrackedWindow {
    <# .SYNOPSIS
    Request normal close for an owned fixture after checking identity; never kill its shared host.
    #>
    param([Parameter(Mandatory)]$Identity)
    Assert-PtWindowIdentity -Identity $Identity
    if (-not [PtDesktop]::PostMessage([IntPtr][long]$Identity.hwnd, 0x10, [IntPtr]::Zero, [IntPtr]::Zero)) {
        throw "WM_CLOSE failed for HWND $($Identity.hwnd)."
    }
    Wait-PtCondition -Description "fixture HWND $($Identity.hwnd) to close" -TimeoutSeconds 5 -Probe {
        -not [PtDesktop]::IsWindow([IntPtr][long]$Identity.hwnd)
    } | Out-Null
}
