#requires -Version 7.2
if (-not ('PtFancyZonesDisplays' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class PtFancyZonesDisplays {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct MonitorInfo {
        public int Size; public Rect Bounds, Work; public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string Device;
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct DisplayDevice {
        public int Size;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string Name;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Description;
        public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Id;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Key;
    }
    public sealed class Monitor {
        public long Handle;
        public string Device, Name, Instance, Serial = "";
        public int Number;
        public uint Dpi;
        public bool Primary, HardwareIdentity;
        public Rect PhysicalBounds, PhysicalWork, LogicalBounds, LogicalWork;
    }
    delegate bool Callback(IntPtr monitor, IntPtr dc, ref Rect bounds, IntPtr data);
    [DllImport("user32.dll", SetLastError=true)] static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, Callback callback, IntPtr data);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool GetMonitorInfoW(IntPtr monitor, ref MonitorInfo info);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool EnumDisplayDevicesW(string device, uint index, ref DisplayDevice info, uint flags);
    [DllImport("user32.dll", SetLastError=true)] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("shcore.dll")] static extern int GetDpiForMonitor(IntPtr monitor, int kind, out uint x, out uint y);
    [DllImport("user32.dll", SetLastError=true)] static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromPoint(Point point, uint flags);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    static MonitorInfo ReadInfo(IntPtr handle) {
        var info = new MonitorInfo { Size=Marshal.SizeOf<MonitorInfo>() };
        if (!GetMonitorInfoW(handle, ref info)) throw new Win32Exception();
        return info;
    }
    public static long Target(bool cursor) {
        if (!cursor) return MonitorFromWindow(GetForegroundWindow(), 1).ToInt64();
        Point point;
        if (!GetCursorPos(out point)) throw new Win32Exception();
        return MonitorFromPoint(point, 1).ToInt64();
    }
    public static Monitor[] Read() {
        var old = SetThreadDpiAwarenessContext(new IntPtr(-4));
        if (old == IntPtr.Zero) throw new Win32Exception();
        var result = new List<Monitor>();
        Exception error = null;
        Callback callback = (IntPtr handle, IntPtr dc, ref Rect bounds, IntPtr data) => {
            try {
                var physical = ReadInfo(handle);
                uint x, y;
                int hr = GetDpiForMonitor(handle, 0, out x, out y);
                if (hr != 0) Marshal.ThrowExceptionForHR(hr);
                if (x == 0 || x != y) throw new InvalidOperationException("Unsupported monitor DPI.");
                var prior = SetThreadDpiAwarenessContext(new IntPtr(-1));
                if (prior == IntPtr.Zero) throw new Win32Exception();
                MonitorInfo logical;
                try { logical = ReadInfo(handle); }
                finally {
                    if (SetThreadDpiAwarenessContext(prior) == IntPtr.Zero) throw new Win32Exception();
                }
                var monitor = new Monitor {
                    Handle=handle.ToInt64(), Device=physical.Device, Name=physical.Device, Instance="",
                    Dpi=x, Primary=(physical.Flags & 1)!=0, PhysicalBounds=physical.Bounds,
                    PhysicalWork=physical.Work, LogicalBounds=logical.Bounds, LogicalWork=logical.Work
                };
                string numberSource = physical.Device;
                for (uint index=0; index<128; index++) {
                    var device = new DisplayDevice { Size=Marshal.SizeOf<DisplayDevice>() };
                    if (!EnumDisplayDevicesW(physical.Device, index, ref device, 1)) break;
                    if ((device.Flags & 1)==0 || (device.Flags & 8)!=0) continue;
                    string[] pieces = device.Id.Split('#');
                    monitor.Name = pieces.Length >= 4 ? pieces[1] : device.Id;
                    monitor.Instance = pieces.Length >= 4 ? pieces[2] : "";
                    monitor.HardwareIdentity = true;
                    int separator = device.Name.LastIndexOf('\\');
                    numberSource = separator < 0 ? device.Name : device.Name.Substring(0, separator);
                    break;
                }
                string digits = "";
                foreach (char c in numberSource) if (c >= '0' && c <= '9') digits += c;
                int number;
                monitor.Number = int.TryParse(digits, out number) ? number : 0;
                result.Add(monitor);
                return true;
            } catch (Exception caught) { error=caught; return false; }
        };
        try {
            if (!EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero)) {
                if (error != null) throw error;
                throw new Win32Exception();
            }
            if (result.Count == 0) throw new InvalidOperationException("No active monitors.");
            return result.ToArray();
        } finally {
            if (SetThreadDpiAwarenessContext(old) == IntPtr.Zero) throw new Win32Exception();
        }
    }
}
'@
}

function Get-PtFancyZonesDisplayModel {
    [CmdletBinding()]
    param()
    $monitors = @([PtFancyZonesDisplays]::Read())
    $hardwareStatus = 'Observed'
    $hardwareError = $null
    try { $hardware = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop) }
    catch {
        $hardware = @()
        $hardwareStatus = 'ReadError: empty serial fallback requires live host comparison'
        $hardwareError = $_.Exception.Message
    }
    foreach ($entry in $hardware) {
        $parts = $entry.InstanceName -split '\\'
        if ($parts.Count -lt 3) { continue }
        $serial = -join @($entry.SerialNumberID | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
        foreach ($monitor in $monitors) {
            if ($monitor.Name -ceq $parts[1]) { $monitor.Serial = $serial }
        }
    }
    $sessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $base = 'Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops'
    $ids = @()
    $current = $null
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($base, $false)
    if ($key) {
        try {
            $bytes = $key.GetValue('VirtualDesktopIDs', $null)
            if ($null -ne $bytes) {
                if ($bytes -isnot [byte[]] -or $bytes.Length % 16) { throw 'Malformed virtual desktop IDs.' }
                $ids = @(for ($i=0; $i -lt $bytes.Length; $i+=16) {
                    [guid]::new([byte[]]$bytes[$i..($i+15)]).ToString('B').ToUpperInvariant()
                })
            }
            $bytes = $key.GetValue('CurrentVirtualDesktop', $null)
            if ($null -ne $bytes) { $current = [guid]::new([byte[]]$bytes).ToString('B').ToUpperInvariant() }
        } finally { $key.Dispose() }
    }
    if (-not $current) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\$sessionId\VirtualDesktops", $false)
        if ($key) {
            try {
                $bytes = $key.GetValue('CurrentVirtualDesktop', $null)
                if ($null -ne $bytes) { $current = [guid]::new([byte[]]$bytes).ToString('B').ToUpperInvariant() }
            } finally { $key.Dispose() }
        }
    }
    if (-not $current) { $current = if ($ids.Count) { $ids[0] } else { [guid]::Empty.ToString('B').ToUpperInvariant() } }
    [pscustomobject]@{ Monitors=$monitors; CurrentDesktop=$current; DesktopIds=$ids; SessionId=$sessionId
        HardwareIdentityStatus=$hardwareStatus; HardwareIdentityError=$hardwareError }
}

function New-PtFancyZonesEditorParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$DisplayModel,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$HostProcessId,
        [Parameter(Mandatory)][bool]$Spanning,
        [Parameter(Mandatory)][long]$TargetMonitor
    )
    $monitors = @($DisplayModel.Monitors)
    if (-not $monitors.Count) { throw 'An observed monitor model is required.' }
    if (-not $Spanning -and @($monitors | Where-Object Handle -EQ $TargetMonitor).Count -ne 1) {
        throw 'Editor target must identify exactly one observed monitor.'
    }
    $entries = if ($Spanning) {
        $physical = $monitors.PhysicalBounds
        $logical = $monitors.LogicalWork
        [pscustomobject][ordered]@{
            monitor='FancyZones'; 'monitor-instance-id'='MultiMonitorDevice'
            'monitor-serial-number'=''; 'monitor-number'=0; 'virtual-desktop'=$DisplayModel.CurrentDesktop
            dpi=0; 'top-coordinate'=[int](($logical.Top | Measure-Object -Minimum).Minimum)
            'left-coordinate'=[int](($logical.Left | Measure-Object -Minimum).Minimum)
            'work-area-width'=[int](($logical.Right | Measure-Object -Maximum).Maximum - ($logical.Left | Measure-Object -Minimum).Minimum)
            'work-area-height'=[int](($logical.Bottom | Measure-Object -Maximum).Maximum - ($logical.Top | Measure-Object -Minimum).Minimum)
            'monitor-width'=[int](($physical.Right | Measure-Object -Maximum).Maximum - ($physical.Left | Measure-Object -Minimum).Minimum)
            'monitor-height'=[int](($physical.Bottom | Measure-Object -Maximum).Maximum - ($physical.Top | Measure-Object -Minimum).Minimum)
            'is-selected'=$true
        }
    } else {
        foreach ($monitor in $monitors) {
            [pscustomobject][ordered]@{
                monitor=$monitor.Name; 'monitor-instance-id'=$monitor.Instance
                'monitor-serial-number'=$monitor.Serial; 'monitor-number'=$monitor.Number
                'virtual-desktop'=$DisplayModel.CurrentDesktop; dpi=$monitor.Dpi
                'top-coordinate'=$monitor.LogicalWork.Top; 'left-coordinate'=$monitor.LogicalWork.Left
                'work-area-width'=($monitor.LogicalWork.Right-$monitor.LogicalWork.Left)
                'work-area-height'=($monitor.LogicalWork.Bottom-$monitor.LogicalWork.Top)
                'monitor-width'=($monitor.LogicalBounds.Right-$monitor.LogicalBounds.Left)
                'monitor-height'=($monitor.LogicalBounds.Bottom-$monitor.LogicalBounds.Top)
                'is-selected'=($monitor.Handle -eq $TargetMonitor)
            }
        }
    }
    [pscustomobject][ordered]@{ 'process-id'=$HostProcessId; 'span-zones-across-monitors'=$Spanning; monitors=@($entries) }
}
