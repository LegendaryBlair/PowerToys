# scripts/pt-foreground-guard.ps1
# Verify and force a window to foreground BEFORE sending SendInput.
# Without this guard, SendInput keys silently leak to the caller's terminal when
# the target window has lost foreground (common with CmdPal AppX where Windows
# foreground-lock blocks SetForegroundWindow after the first attempt).
#
# Use winapp ui set-value for UIA-friendly inputs (no foreground required).
# Use this guard ONLY when you need real keystrokes (e.g. CmdPal alias detection).

if (-not (Get-Command Invoke-PtWinApp -ErrorAction Ignore)) {
    . "$PSScriptRoot\pt-desktop.ps1"
}

if (-not ('PtFg' -as [type])) {
    Add-Type -TypeDefinition @'
        using System;
        using System.Runtime.InteropServices;
        public static class PtFg {
            [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
            [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
            [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
            [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
            [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
            [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
            [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
            [DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int pid);
            [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
            [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
            [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
        }
'@
}

function Test-PtForeground {
    <#
    .SYNOPSIS
    Check whether the target AppX is currently foreground by parsing winapp ui list-windows output
    for the literal substring 'foreground'.
    #>
    [CmdletBinding(DefaultParameterSetName='App')]
    param(
        [Parameter(Mandatory,ParameterSetName='App')][string]$AppId,
        [Parameter(Mandatory,ParameterSetName='Window')][ValidateRange(1,[long]::MaxValue)][long]$Hwnd
    )
    if ($PSCmdlet.ParameterSetName -eq 'Window') {
        return [PtFg]::IsWindowVisible([IntPtr]$Hwnd) -and [PtFg]::GetForegroundWindow().ToInt64() -eq $Hwnd
    }
    $r = Invoke-PtWinApp -Arguments @('list-windows','-a',$AppId)
    return ($r -match 'foreground')
}

function Get-PtHwnd {
    <#
    .SYNOPSIS
    Return the first HWND for the given AppX/exe. Returns [IntPtr]::Zero if none.
    #>
    param([Parameter(Mandatory)][string]$AppId)
    $r = Invoke-PtWinApp -Arguments @('list-windows','-a',$AppId)
    if ($r -match 'HWND (\d+):') { return [IntPtr][int64]$matches[1] }
    return [IntPtr]::Zero
}

function Force-PtForeground {
    <#
    .SYNOPSIS
    Force the target AppX window to foreground using the AttachThreadInput + AllowSetForegroundWindow
    trick. Returns $true if window is foreground after this attempt; $false otherwise.
    .NOTES
    Foreground locks may deny activation. Prefer a normal UI activation of the tracked app
    and retry the exact HWND; never terminate a user/shared process to obtain foreground.
    #>
    [CmdletBinding(DefaultParameterSetName='App')]
    param(
        [Parameter(Mandatory,ParameterSetName='App')][string]$AppId,
        [Parameter(Mandatory,ParameterSetName='Window')][ValidateRange(1,[long]::MaxValue)][long]$Hwnd
    )
    $h = if ($PSCmdlet.ParameterSetName -eq 'Window') { [IntPtr]$Hwnd } else { Get-PtHwnd -AppId $AppId }
    if ($h -eq [IntPtr]::Zero -or -not [PtFg]::IsWindow($h)) {
        Write-Warning 'Foreground target does not exist; re-resolve its identity.'
        return $false
    }
    if (-not [PtFg]::IsWindowVisible($h)) {
        Write-Warning 'Foreground target is hidden; activate it through its documented entry path first.'
        return $false
    }

    # Permission grant
    $proc = Get-Process | Where-Object { $_.MainWindowHandle -eq $h } | Select-Object -First 1
    if ($proc) { [PtFg]::AllowSetForegroundWindow($proc.Id) | Out-Null }

    if ([PtFg]::IsIconic($h)) {
        [PtFg]::ShowWindow($h, 9) | Out-Null
        Start-Sleep -Milliseconds 150
    }

    # AttachThreadInput trick
    $fg = [PtFg]::GetForegroundWindow()
    $fgPid = 0
    $fgThread = [PtFg]::GetWindowThreadProcessId($fg, [ref]$fgPid)
    $curThread = [PtFg]::GetCurrentThreadId()
    $attached = $false
    try {
        if ($fgThread -ne 0 -and $fgThread -ne $curThread) {
            $attached = [PtFg]::AttachThreadInput($curThread, $fgThread, $true)
        }
        [PtFg]::BringWindowToTop($h) | Out-Null
        [PtFg]::SetForegroundWindow($h) | Out-Null
    } finally {
        if ($attached) { [PtFg]::AttachThreadInput($curThread, $fgThread, $false) | Out-Null }
    }
    Start-Sleep -Milliseconds 400
    return (Test-PtForeground -Hwnd $h.ToInt64())
}

function Assert-PtForegroundOrAbort {
    <#
    .SYNOPSIS
    Guard helper. Throws if the target AppX is NOT foreground. Use this immediately before any
    SendInput call to ensure keys don't leak to the wrong window.
    #>
    [CmdletBinding(DefaultParameterSetName='App')]
    param(
        [Parameter(Mandatory,ParameterSetName='App')][string]$AppId,
        [Parameter(Mandatory,ParameterSetName='Window')][ValidateRange(1,[long]::MaxValue)][long]$Hwnd
    )
    $target = if ($PSCmdlet.ParameterSetName -eq 'Window') { @{ Hwnd = $Hwnd } } else { @{ AppId = $AppId } }
    if (-not (Test-PtForeground @target)) {
        if (-not (Force-PtForeground @target)) {
            throw "ABORT: target $($target.Values -join ',') cannot be made foreground. No keys were sent."
        }
    }
}
