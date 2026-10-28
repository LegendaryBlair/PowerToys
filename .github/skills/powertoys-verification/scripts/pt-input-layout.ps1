. "$PSScriptRoot\pt-desktop.ps1"
. "$PSScriptRoot\pt-state-snapshot.ps1"
. "$PSScriptRoot\pt-sendinput-chord.ps1"

if (-not ('PtInputLayout' -as [type])) {
    Add-Type @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class PtInputLayout {
    [DllImport("user32.dll", SetLastError=true)] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] static extern IntPtr GetKeyboardLayout(uint thread);
    [DllImport("user32.dll")] static extern int GetKeyboardLayoutList(int count, [Out] IntPtr[] layouts);
    [DllImport("user32.dll", SetLastError=true)] static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wparam, IntPtr lparam);
    public static long Read(long hwnd) {
        uint pid;
        var thread = GetWindowThreadProcessId((IntPtr)hwnd, out pid);
        if (thread == 0) throw new Win32Exception(Marshal.GetLastWin32Error());
        var layout = GetKeyboardLayout(thread);
        if (layout == IntPtr.Zero) throw new InvalidOperationException("Target thread has no observable keyboard layout.");
        return layout.ToInt64();
    }
    public static bool Installed(long layout) {
        var values = new IntPtr[GetKeyboardLayoutList(0, null)];
        var count = GetKeyboardLayoutList(values.Length, values);
        for (var i = 0; i < count; i++) if (values[i].ToInt64() == layout) return true;
        return false;
    }
    public static void Request(long hwnd, long layout) {
        if (!PostMessage((IntPtr)hwnd, 0x0050, IntPtr.Zero, (IntPtr)layout))
            throw new Win32Exception(Marshal.GetLastWin32Error());
    }
}
'@
}

function Get-PtKeyboardLayoutSnapshot {
    <#.SYNOPSIS
    Read an identity-checked window thread's layout. This does not capture IME composition/conversion.
    #>
    param([Parameter(Mandatory)]$Target)
    Assert-PtWindowIdentity $Target
    $layout = [PtInputLayout]::Read($Target.hwnd)
    Assert-PtWindowIdentity $Target
    [pscustomobject]@{
        Schema = 'PtKeyboardLayout.v1'
        Target = [pscustomobject]@{
            hwnd = [long]$Target.hwnd
            processId = [int]$Target.processId
            processStartTicks = [long]$Target.processStartTicks
            className = [string]$Target.className
        }
        Layout = $layout
    }
}

function Restore-PtKeyboardLayoutSnapshot {
    <#.SYNOPSIS
    Restore an explicitly affected foreground thread only from its known owned post-layout.
    .NOTES
    Call after final owned-writer closure and Settings/desktop restoration, before sealing the run.
    No activation, layout installation, global configuration change, key injection or automatic retry.
    #>
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][ValidateCount(1,16)][long[]]$ExpectedLayout
    )
    if ($Snapshot.Schema -cne 'PtKeyboardLayout.v1' -or
        ($Snapshot.Layout -isnot [long] -and $Snapshot.Layout -isnot [int]) -or
        $Snapshot.Layout -eq 0 -or @($ExpectedLayout | Where-Object { $_ -eq 0 }).Count) {
        throw 'Keyboard-layout restoration requires an original snapshot and explicit nonzero owned post-layouts.'
    }
    Assert-PtWindowIdentity $Snapshot.Target
    $before = [PtInputLayout]::Read($Snapshot.Target.hwnd)
    $changed = $before -ne $Snapshot.Layout
    if ($changed) {
        if ($before -notin $ExpectedLayout) {
            throw 'Keyboard-layout restoration conflict: current layout is neither original nor an expected owned post-state.'
        }
        if ([PtDesktop]::GetForegroundWindow().ToInt64() -ne $Snapshot.Target.hwnd) {
            throw 'Restore the original physical desktop before its keyboard layout; this helper does not activate windows.'
        }
        if (-not [PtInputLayout]::Installed($Snapshot.Layout)) {
            throw 'Original keyboard layout is no longer installed; no installation attempted.'
        }
        foreach ($key in 16,17,18,91,92) {
            if (([PtChord]::GetAsyncKeyState($key) -band 0x8000) -ne 0) {
                throw 'A modifier is held; keyboard-layout restoration was not requested.'
            }
        }
        Assert-PtWindowIdentity $Snapshot.Target
        if ([PtInputLayout]::Read($Snapshot.Target.hwnd) -ne $before) {
            throw 'Keyboard-layout restoration conflict: layout changed during the guarded check.'
        }
        [PtInputLayout]::Request($Snapshot.Target.hwnd, $Snapshot.Layout)
        Wait-PtCondition -Description 'original foreground thread keyboard layout' -TimeoutSeconds 5 -Probe {
            Assert-PtWindowIdentity $Snapshot.Target
            [PtInputLayout]::Read($Snapshot.Target.hwnd) -eq $Snapshot.Layout
        } | Out-Null
    }
    $after = Get-PtKeyboardLayoutSnapshot -Target $Snapshot.Target
    if ($after.Layout -ne $Snapshot.Layout) { throw 'Final keyboard-layout comparison failed.' }
    [pscustomobject]@{
        Target = $Snapshot.Target
        Original = $Snapshot.Layout
        Before = $before
        After = $after.Layout
        Changed = $changed
        Restored = $true
        Scope = 'Thread keyboard layout only; IME composition/conversion is not certified.'
    }
}
