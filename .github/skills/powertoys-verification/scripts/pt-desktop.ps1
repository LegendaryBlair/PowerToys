# Native desktop observations are independent of PowerToys window names and MainWindowHandle.
if (-not ('PtDesktop' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
public static class PtDesktop {
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct PLACEMENT {
        public int length, flags, showCmd;
        public POINT ptMinPosition, ptMaxPosition;
        public RECT rcNormalPosition;
    }
    public class Window {
        public long Hwnd;
        public uint ProcessId;
        public string ClassName, Title;
        public bool Visible, Minimized;
        public RECT Rect;
    }
    delegate bool EnumProc(IntPtr hwnd, IntPtr param);
    [DllImport("user32.dll", SetLastError=true)] static extern bool EnumWindows(EnumProc proc, IntPtr param);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", SetLastError=true)] static extern bool GetWindowRect(IntPtr h, out RECT rect);
    [DllImport("user32.dll", SetLastError=true)] static extern bool GetWindowPlacement(IntPtr h, ref PLACEMENT p);
    [DllImport("user32.dll", SetLastError=true)] static extern bool SetWindowPlacement(IntPtr h, ref PLACEMENT p);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll", EntryPoint="GetCursorPos", SetLastError=true)] static extern bool ReadCursor(out POINT point);
    [DllImport("user32.dll", EntryPoint="SetCursorPos", SetLastError=true)] static extern bool MoveCursor(int x, int y);
    [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    public static bool GetCursorPos(out POINT point) {
        IntPtr previous=SetThreadDpiAwarenessContext(new IntPtr(-4));
        try { return ReadCursor(out point); }
        finally { if (previous != IntPtr.Zero) SetThreadDpiAwarenessContext(previous); }
    }
    public static bool SetCursorPos(int x, int y) {
        IntPtr previous=SetThreadDpiAwarenessContext(new IntPtr(-4));
        try { return MoveCursor(x,y); }
        finally { if (previous != IntPtr.Zero) SetThreadDpiAwarenessContext(previous); }
    }
    public static Window Read(IntPtr h) {
        if (!IsWindow(h)) throw new Win32Exception(1400, "Window no longer exists: " + h);
        var cls=new StringBuilder(512); var title=new StringBuilder(2048); uint pid, currentPid; RECT rect;
        uint thread=GetWindowThreadProcessId(h, out pid);
        if (thread == 0) throw new Win32Exception(1400, "Window disappeared: " + h);
        if (GetClassName(h, cls, cls.Capacity) == 0) throw new Win32Exception();
        GetWindowText(h, title, title.Capacity);
        if (!GetWindowRect(h, out rect)) throw new Win32Exception();
        if (GetWindowThreadProcessId(h, out currentPid) != thread || pid != currentPid)
            throw new Win32Exception(1400, "Window identity changed while reading: " + h);
        return new Window { Hwnd=h.ToInt64(), ProcessId=pid, ClassName=cls.ToString(), Title=title.ToString(),
            Visible=IsWindowVisible(h), Minimized=IsIconic(h), Rect=rect };
    }
    public static Window[] Windows() { return Windows(0, null); }
    public static Window[] Windows(uint processId, string className) {
        var windows=new List<Window>();
        Exception failure=null;
        bool completed=EnumWindows((h,p) => {
            try {
                uint owner;
                if (GetWindowThreadProcessId(h, out owner) == 0) return true;
                if (processId != 0 && owner != processId) return true;
                if (!String.IsNullOrEmpty(className)) {
                    var name=new StringBuilder(512);
                    if (GetClassName(h,name,name.Capacity) == 0) {
                        int error=Marshal.GetLastWin32Error();
                        if (!IsWindow(h)) return true;
                        throw new Win32Exception(error);
                    }
                    if (!String.Equals(name.ToString(),className,StringComparison.OrdinalIgnoreCase)) return true;
                }
                var window=Read(h);
                if ((processId == 0 || window.ProcessId == processId) &&
                    (String.IsNullOrEmpty(className) || String.Equals(window.ClassName,className,StringComparison.OrdinalIgnoreCase))) windows.Add(window);
            } catch (Win32Exception ex) when (ex.NativeErrorCode == 1400) {
                // A top-level window may close between enumeration and reading its properties.
            } catch (Exception ex) {
                failure=ex;
                return false; // Never let managed exceptions escape through the native callback.
            }
            return true;
        }, IntPtr.Zero);
        if (failure != null) throw failure;
        if (!completed) throw new Win32Exception();
        return windows.ToArray();
    }
    public static PLACEMENT Placement(IntPtr h) {
        IntPtr previous=SetThreadDpiAwarenessContext(new IntPtr(-4));
        try {
            var p=new PLACEMENT(); p.length=Marshal.SizeOf(typeof(PLACEMENT));
            if (!GetWindowPlacement(h, ref p)) throw new Win32Exception();
            return p;
        } finally { if (previous != IntPtr.Zero) SetThreadDpiAwarenessContext(previous); }
    }
    public static void Place(IntPtr h, PLACEMENT p) {
        IntPtr previous=SetThreadDpiAwarenessContext(new IntPtr(-4));
        try {
            p.length=Marshal.SizeOf(typeof(PLACEMENT));
            if (!SetWindowPlacement(h, ref p)) throw new Win32Exception();
        } finally { if (previous != IntPtr.Zero) SetThreadDpiAwarenessContext(previous); }
    }
}
'@
}

function Wait-PtCondition {
    <#
    .SYNOPSIS
    Poll a read-only probe until it returns a truthy result. Probe errors propagate immediately.
    .NOTES
    Keep probes bounded. Use Invoke-PtWinApp for external UI commands; do not hide driver errors
    as "not ready". A timeout does not authorize a product restart.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Probe,
        [Parameter(Mandatory)][string]$Description,
        [ValidateRange(0.1,300)][double]$TimeoutSeconds = 9,
        [ValidateRange(10,5000)][int]$PollMilliseconds = 100
    )
    $clock = [Diagnostics.Stopwatch]::StartNew()
    do {
        $result = & $Probe
        if ($result) { return $result }
        $remaining = $TimeoutSeconds * 1000 - $clock.Elapsed.TotalMilliseconds
        if ($remaining -le 0) { break }
        Start-Sleep -Milliseconds ([int][Math]::Min($PollMilliseconds, $remaining))
    } while ($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    throw [TimeoutException]::new("Timed out waiting for $Description after $($clock.Elapsed.TotalSeconds.ToString('F2')) seconds.")
}

function Get-PtNativeWindow {
    <# .SYNOPSIS
    Enumerate native top-level windows in physical screen coordinates; never infer a main window.
    #>
    [CmdletBinding()]
    param([long]$Hwnd, [ValidateRange(1,2147483647)][int]$ProcessId, [string]$ClassName, [switch]$Visible)
    $dpi = [PtDesktop]::SetThreadDpiAwarenessContext([IntPtr](-4))
    try {
        $windows = if ($PSBoundParameters.ContainsKey('Hwnd')) {
            if ($Hwnd -eq 0) { throw 'HWND=0 is not a target window.' }
            [PtDesktop]::Read([IntPtr]$Hwnd)
        } else { [PtDesktop]::Windows([uint32]$ProcessId, $ClassName) }
        $windows | Where-Object {
            (-not $ProcessId -or $_.ProcessId -eq $ProcessId) -and
            (-not $ClassName -or $_.ClassName -eq $ClassName) -and
            (-not $Visible -or $_.Visible)
        }
    } finally { if ($dpi -ne [IntPtr]::Zero) { [void][PtDesktop]::SetThreadDpiAwarenessContext($dpi) } }
}

function Wait-PtWindow {
    <# .SYNOPSIS
    Wait for exactly one window matching an explicit process and optional native class.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$ProcessId,
        [string]$ClassName,
        [switch]$Visible,
        [ValidateRange(0.1,300)][double]$TimeoutSeconds = 9
    )
    $originalProcess = Get-Process -Id $ProcessId -ErrorAction Stop
    $started = $originalProcess.StartTime.ToUniversalTime().Ticks
    Wait-PtCondition -Description "window for PID $ProcessId ($ClassName)" -TimeoutSeconds $TimeoutSeconds -Probe {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        if ($process.StartTime.ToUniversalTime().Ticks -ne $started) { throw "Process identity changed while waiting for PID $ProcessId." }
        $windows = @(Get-PtNativeWindow -ProcessId $process.Id -ClassName $ClassName -Visible:$Visible)
        if ($windows.Count -gt 1) { throw "Ambiguous window selection for PID $ProcessId; supply a more specific class or track the exact HWND." }
        if ($windows.Count -eq 1) { $windows[0] }
    }
}

function Get-PtForegroundWindow {
    <# .SYNOPSIS
    Read the actual foreground HWND directly; Shell surfaces may be absent from EnumWindows.
    #>
    [CmdletBinding()]
    param()
    $foreground = [PtDesktop]::GetForegroundWindow().ToInt64()
    if (-not $foreground) {
        $error=[InvalidOperationException]::new('No foreground window on the current input desktop.')
        $error.Data['PtDesktopStatus']='NoForeground'
        throw $error
    }
    Get-PtNativeWindow -Hwnd $foreground
}

function Invoke-PtWinApp {
    <# .SYNOPSIS
    Run a bounded winapp ui command. Return raw output; throw on timeout or nonzero exit.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][ValidateNotNull()][string[]]$Arguments,
        [ValidateRange(1,120)][int]$TimeoutSeconds = 15,
        [switch]$SkipRecording
    )
    if (-not $SkipRecording -and (Get-Command Get-PtActiveVerificationAttempt -ErrorAction Ignore)) {
        $activeAttempt = Get-PtActiveVerificationAttempt
        if ($activeAttempt) {
            $quoted = $Arguments | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }
            return Invoke-PtVerificationStep -Attempt $activeAttempt -Name 'winapp' `
                -Command ('winapp ui ' + ($quoted -join ' ')) `
                -Implementation ${function:Invoke-PtWinApp} `
                -ArgumentList @($Arguments, $TimeoutSeconds) -Action {
                    param([string[]]$RecordedArguments, [int]$RecordedTimeout)
                    Invoke-PtWinApp -Arguments $RecordedArguments -TimeoutSeconds $RecordedTimeout -SkipRecording
                }
        }
    }
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        if ($Arguments[$i] -in '-w','--window' -and
            ($i + 1 -eq $Arguments.Count -or $Arguments[$i + 1] -notmatch '^[1-9][0-9]*$')) {
            throw 'winapp requires a nonzero numeric HWND after -w/--window.'
        }
    }
    $info = [Diagnostics.ProcessStartInfo]::new((Get-Command winapp -ErrorAction Stop).Source)
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.ArgumentList.Add('ui')
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw 'Could not start winapp.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw [TimeoutException]::new("winapp ui $($Arguments -join ' ') exceeded $TimeoutSeconds seconds (owned PID $($process.Id) stopped).")
        }
        $output = $stdout.GetAwaiter().GetResult()
        $errorOutput = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw "winapp ui $($Arguments -join ' ') failed ($($process.ExitCode)): $errorOutput$output" }
        if ($errorOutput) { Write-Verbose $errorOutput }
        return $output
    } finally { $process.Dispose() }
}

function Get-PtUiElements {
    <# .SYNOPSIS
    Flatten an already-captured winapp JSON tree without issuing another inspect command.
    #>
    param([Parameter(Mandatory)]$Tree)
    $queue = [Collections.Generic.Queue[object]]::new()
    foreach ($window in $Tree.windows) { foreach ($element in $window.elements) { $queue.Enqueue($element) } }
    while ($queue.Count) {
        $element = $queue.Dequeue()
        $element
        foreach ($child in $element.children) { $queue.Enqueue($child) }
    }
}

function Save-PtPassiveScreenshot {
    <#
    .SYNOPSIS
    Capture the virtual desktop without activating a window; reject overwritten or disturbed evidence.
    .PARAMETER Observe
    Optional read-only probe returning stable invariants (visibility, menu presence, held keys).
    Do not include timestamps or other intentionally changing values.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [scriptblock]$Observe)
    Add-Type -AssemblyName System.Drawing, System.Windows.Forms
    $before = [ordered]@{ foreground = [PtDesktop]::GetForegroundWindow().ToInt64(); observation = $(if ($Observe) { & $Observe }) }
    if (-not $before.foreground) { throw 'No interactive foreground desktop; capture aborted.' }
    $dpi = [PtDesktop]::SetThreadDpiAwarenessContext([IntPtr](-4))
    try {
        $bounds = [Windows.Forms.SystemInformation]::VirtualScreen
        $bitmap = [Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
        try {
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            try { $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size) }
            finally { $graphics.Dispose() }
            $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png) }
            finally { $stream.Dispose() }
        } finally { $bitmap.Dispose() }
    } finally { if ($dpi -ne [IntPtr]::Zero) { [void][PtDesktop]::SetThreadDpiAwarenessContext($dpi) } }
    $after = [ordered]@{ foreground = [PtDesktop]::GetForegroundWindow().ToInt64(); observation = $(if ($Observe) { & $Observe }) }
    $state = [ordered]@{ before = $before; after = $after; path = [IO.Path]::GetFullPath($Path) }
    $sidecar = [IO.File]::Open("$Path.state.json", [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($state | ConvertTo-Json -Depth 20))
        $sidecar.Write($bytes, 0, $bytes.Length)
    } finally { $sidecar.Dispose() }
    if (($before | ConvertTo-Json -Depth 15 -Compress) -cne ($after | ConvertTo-Json -Depth 15 -Compress)) {
        throw "Observation changed during capture; evidence is invalid, retained at $Path (see state sidecar)."
    }
    [pscustomobject]$state
}
