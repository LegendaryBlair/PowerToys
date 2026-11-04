# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license. See LICENSE in the project root.
#requires -Version 7.2

. "$PSScriptRoot\pt-desktop.ps1"
. "$PSScriptRoot\pt-state-snapshot.ps1"

if (-not ('PtAlwaysOnTopObservation' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
public static class PtAlwaysOnTopObservation {
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern IntPtr GetProp(IntPtr hwnd, string name);
    [DllImport("user32.dll", SetLastError=true)]
    static extern bool GetLayeredWindowAttributes(IntPtr hwnd, out uint color, out byte alpha, out uint flags);
    [DllImport("dwmapi.dll")]
    static extern int DwmGetWindowAttribute(IntPtr hwnd, uint attribute, out Rect value, int size);
    [DllImport("user32.dll")]
    public static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("shell32.dll")]
    static extern int SHQueryUserNotificationState(out int state);
    [StructLayout(LayoutKind.Sequential)]
    public struct Rect { public int Left, Top, Right, Bottom; }
    public sealed class Layer {
        public bool Available;
        public uint ColorKey, Flags;
        public byte Alpha;
        public int Error;
    }
    public static Layer ReadLayer(IntPtr hwnd) {
        var result=new Layer();
        result.Available=GetLayeredWindowAttributes(hwnd,out result.ColorKey,out result.Alpha,out result.Flags);
        if(!result.Available) result.Error=Marshal.GetLastWin32Error();
        return result;
    }
    public static Rect Frame(IntPtr hwnd) {
        Rect rect;
        int result=DwmGetWindowAttribute(hwnd,9,out rect,Marshal.SizeOf(typeof(Rect)));
        if(result!=0) Marshal.ThrowExceptionForHR(result);
        return rect;
    }
    public static int NotificationState() {
        int state;
        int result=SHQueryUserNotificationState(out state);
        if(result!=0) Marshal.ThrowExceptionForHR(result);
        return state;
    }
    [ComImport, Guid("A5CD92FF-29BE-454C-8D04-D82879FB3F1B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IVirtualDesktopManager {
        [PreserveSig] int IsWindowOnCurrentVirtualDesktop(IntPtr window, [MarshalAs(UnmanagedType.Bool)] out bool current);
        [PreserveSig] int GetWindowDesktopId(IntPtr window, out Guid desktop);
        [PreserveSig] int MoveWindowToDesktop(IntPtr window, ref Guid desktop);
    }
    public sealed class Desktop {
        public Guid Id;
        public bool IsCurrent;
    }
    public static Desktop ReadDesktop(IntPtr hwnd) {
        var type=Type.GetTypeFromCLSID(new Guid("AA509086-5CA9-4C25-8F95-589D3C07B48A"),true);
        var manager=(IVirtualDesktopManager)Activator.CreateInstance(type);
        try {
            var result=new Desktop();
            Marshal.ThrowExceptionForHR(manager.GetWindowDesktopId(hwnd,out result.Id));
            Marshal.ThrowExceptionForHR(manager.IsWindowOnCurrentVirtualDesktop(hwnd,out result.IsCurrent));
            return result;
        } finally { Marshal.ReleaseComObject(manager); }
    }
}
'@ -ErrorAction Stop
}

function Get-PtAlwaysOnTopWindowState {
    <#
    .SYNOPSIS
    Observe pin marker, topmost, layered attributes and physical frame on an exact window.
    .NOTES
    Read-only: neither establishes ownership nor infers visible border/audio correctness.
    Per-pixel layered windows may not expose constant-alpha attributes; keep that distinct.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Identity)
    Assert-PtWindowIdentity -Identity $Identity | Out-Null
    $hwndValue = [IntPtr]$Identity.hwnd
    $style = [PtDesktop]::ExtendedStyle($hwndValue)
    $layered = ($style -band 0x80000) -ne 0
    $attributes = if ($layered) { [PtAlwaysOnTopObservation]::ReadLayer($hwndValue) }
    $result = [pscustomobject]@{
        Identity = $Identity
        Pinned = [PtAlwaysOnTopObservation]::GetProp($hwndValue, 'AlwaysOnTop_Pinned') -ne [IntPtr]::Zero
        Topmost = ($style -band 0x8) -ne 0
        Layered = $layered
        LayerStatus = $(if (-not $layered) { 'NotLayered' } elseif ($attributes.Available) { 'Available' } else { 'Unavailable' })
        Alpha = $(if ($layered -and $attributes.Available) { $attributes.Alpha } else { $null })
        LayerFlags = $(if ($layered -and $attributes.Available) { $attributes.Flags } else { $null })
        ColorKey = $(if ($layered -and $attributes.Available) { $attributes.ColorKey } else { $null })
        LayerError = $(if ($layered -and -not $attributes.Available) { $attributes.Error } else { $null })
        Dpi = [PtAlwaysOnTopObservation]::GetDpiForWindow($hwndValue)
        Frame = [PtAlwaysOnTopObservation]::Frame($hwndValue)
    }
    Assert-PtWindowIdentity -Identity $Identity | Out-Null
    $result
}

function Get-PtAlwaysOnTopDesktop {
    <# .SYNOPSIS
    Read the exact target's public virtual-desktop ID/current status; never switch desktops.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Identity)
    Assert-PtWindowIdentity -Identity $Identity | Out-Null
    $result = [PtAlwaysOnTopObservation]::ReadDesktop([IntPtr]$Identity.hwnd)
    Assert-PtWindowIdentity -Identity $Identity | Out-Null
    $result
}

function Get-PtAlwaysOnTopGameMode {
    <# .SYNOPSIS
    Read the same Windows notification condition used by Always On Top, without enabling it.
    #>
    [CmdletBinding()]
    param()
    $state = [PtAlwaysOnTopObservation]::NotificationState()
    [pscustomobject]@{ NotificationState = $state; RunningDirect3DFullScreen = $state -eq 3 }
}
