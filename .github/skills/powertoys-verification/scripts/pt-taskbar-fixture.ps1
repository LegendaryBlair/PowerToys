#requires -Version 7.2
# System Calculator taskbar fixture. Importing this library never launches apps or sends input.
foreach ($dependency in 'pt-desktop','pt-state-snapshot','pt-foreground-guard','pt-sendinput-chord','pt-uia','pt-shortcut-guide') {
    . "$PSScriptRoot\$dependency.ps1"
}

function Initialize-PtTaskbarNative {
    if ('PtTaskbarNative' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class PtTaskbarNative {
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct MONITORINFO {
        public uint cbSize; public RECT rcMonitor, rcWork; public uint dwFlags;
    }
    [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT {
        public int dx, dy; public uint mouseData, dwFlags, time; public UIntPtr dwExtraInfo;
    }
    [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT {
        public ushort wVk, wScan; public uint dwFlags, time; public UIntPtr dwExtraInfo;
    }
    [StructLayout(LayoutKind.Sequential)] public struct HARDWAREINPUT { public uint uMsg; public ushort wParamL, wParamH; }
    [StructLayout(LayoutKind.Explicit)] public struct UNION {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }
    [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public UNION data; }
    [DllImport("user32.dll", SetLastError=true)] static extern uint SendInput(uint count, INPUT[] inputs, int size);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT point);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
    [DllImport("user32.dll", SetLastError=true)] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    public static long PointWindow(int x, int y) {
        var previous=SetThreadDpiAwarenessContext(new IntPtr(-4));
        if (previous==IntPtr.Zero) throw new Win32Exception();
        try {
            var hwnd=WindowFromPoint(new POINT { X=x, Y=y });
            if (hwnd==IntPtr.Zero) throw new InvalidOperationException("No window at the owned pointer target.");
            var root=GetAncestor(hwnd, 2);
            if (root==IntPtr.Zero) throw new InvalidOperationException("No root window at the owned pointer target.");
            return root.ToInt64();
        } finally {
            if (SetThreadDpiAwarenessContext(previous)==IntPtr.Zero) throw new Win32Exception();
        }
    }
    public static RECT PrimaryMonitor(long hwnd) {
        var info=new MONITORINFO(); info.cbSize=(uint)Marshal.SizeOf<MONITORINFO>();
        var monitor=MonitorFromWindow(new IntPtr(hwnd), 0);
        if (monitor==IntPtr.Zero || !GetMonitorInfo(monitor, ref info)) throw new Win32Exception();
        if ((info.dwFlags & 1)==0) throw new InvalidOperationException("Taskbar is not on the primary monitor.");
        return info.rcMonitor;
    }
    public static int NormalizePixel(int coordinate, int origin, int extent) {
        long offset=(long)coordinate-origin;
        if (extent<1 || extent>65536 || offset<0 || offset>=extent)
            throw new ArgumentOutOfRangeException(nameof(coordinate), "Physical pixel is not exactly addressable on this virtual desktop.");
        // Aim inside the pixel's normalized cell, not at a boundary between pixels.
        return (int)((offset*65536L+32768L)/extent);
    }
    public static uint Mouse(string kind, int x, int y) {
        if (IntPtr.Size!=8 || Marshal.SizeOf<INPUT>()!=40)
            throw new PlatformNotSupportedException("Native taskbar input requires the 40-byte x64/ARM64 INPUT ABI.");
        var input=new INPUT();
        if (kind=="Down" || kind=="Up") {
            input.data.mi.dwFlags=kind=="Down" ? 0x0002u : 0x0004u;
            return SendInput(1, new[] {input}, Marshal.SizeOf<INPUT>());
        }
        if (kind!="Move") throw new ArgumentException("Unknown mouse operation.");
        var previous=SetThreadDpiAwarenessContext(new IntPtr(-4));
        if (previous==IntPtr.Zero) throw new Win32Exception();
        try {
            int left=GetSystemMetrics(76), top=GetSystemMetrics(77);
            int width=GetSystemMetrics(78), height=GetSystemMetrics(79);
            if (width<=1 || height<=1 || x<left || y<top || x>=left+width || y>=top+height)
                throw new InvalidOperationException("Pointer endpoint is outside the physical virtual desktop.");
            input.data.mi.dx=NormalizePixel(x, left, width);
            input.data.mi.dy=NormalizePixel(y, top, height);
            input.data.mi.dwFlags=0xC001;
            return SendInput(1, new[] {input}, Marshal.SizeOf<INPUT>());
        } finally {
            if (SetThreadDpiAwarenessContext(previous)==IntPtr.Zero) throw new Win32Exception();
        }
    }
}
'@
}

function Assert-PtTaskbarLocalPath {
    param([Parameter(Mandatory)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.StartsWith('\\') -or $full -cne $Path) { throw 'Fixture paths must be absolute local canonical paths.' }
    for ($part = $full; $part; $part = [IO.Path]::GetDirectoryName($part)) {
        if ((Test-Path -LiteralPath $part) -and
            ((Get-Item -LiteralPath $part -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Fixture path is a reparse point: $part"
        }
    }
}

function Write-PtTaskbarJson {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value,[switch]$Create)
    Assert-PtTaskbarLocalPath $Path
    $temporary = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Value -Depth 32))
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
    # Same-directory rename is atomic; retain the temporary evidence if replacement fails.
    [IO.File]::Move($temporary, $Path, -not $Create)
}

function Save-PtTaskbarFixture {
    param([Parameter(Mandatory)]$Fixture,[switch]$Create)
    if (-not $Create -and (Test-Path -LiteralPath $Fixture.ReceiptPath)) {
        $stored = Get-Content -LiteralPath $Fixture.ReceiptPath -Raw -ErrorAction Stop | ConvertFrom-Json
        if ((ConvertTo-Json $stored -Depth 32 -Compress) -ceq (ConvertTo-Json $Fixture -Depth 32 -Compress)) { return }
    }
    Write-PtTaskbarJson -Path $Fixture.ReceiptPath -Value $Fixture -Create:$Create
}

function Read-PtTaskbarFixture {
    param($Fixture,[string]$ReceiptPath)
    if ($Fixture) { $ReceiptPath = $Fixture.ReceiptPath }
    Assert-PtTaskbarLocalPath $ReceiptPath
    $stored = Get-Content -LiteralPath $ReceiptPath -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($Fixture -and (ConvertTo-Json $Fixture -Depth 32 -Compress) -cne (ConvertTo-Json $stored -Depth 32 -Compress)) {
        throw 'Fixture receipt is stale or changed; reload the persisted receipt before acting.'
    }
    if ($stored.Kind -cne 'Taskbar' -or $stored.Version -notin 1,2 -or $stored.Id -cnotmatch '^[a-f0-9]{32}$' -or
        $stored.ReceiptPath -cne $ReceiptPath -or
        $ReceiptPath -cne (Join-Path $stored.Workspace "taskbar-$($stored.Id).json") -or
        $stored.MarkerPath -cne (Join-Path $stored.Workspace "taskbar-$($stored.Id).marker.json")) {
        throw 'Invalid taskbar ownership receipt.'
    }
    Assert-PtTaskbarLocalPath $stored.MarkerPath
    if ((Get-FileHash -LiteralPath $stored.MarkerPath -ErrorAction Stop).Hash -cne $stored.MarkerHash) {
        throw 'Taskbar fixture marker hash mismatch.'
    }
    $marker = Get-Content -LiteralPath $stored.MarkerPath -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($marker.Id -cne $stored.Id -or $marker.Kind -cne 'Taskbar' -or $marker.Version -ne $stored.Version -or
        $marker.Workspace -cne $stored.Workspace -or $marker.ReceiptPath -cne $ReceiptPath -or
        $marker.Count -lt 1 -or $marker.Count -gt 9 -or @($stored.Apps).Count -ne $marker.Count -or
        $marker.Desktop.coordinateSpace -cne 'Physical' -or -not $marker.Taskbar.apps.Count -or
        -not $marker.ForegroundWindow -or $marker.ForegroundWindow.identity.hwnd -ne $marker.Desktop.foreground.hwnd -or
        $stored.Phase -cnotin @('Creating','Ready','Faulted','Cleaning','Closed')) {
        throw 'Invalid fixture marker/receipt contract.'
    }
    for ($i = 1; $i -le $marker.Count; $i++) {
        $app = $stored.Apps[$i - 1]
        if ($stored.Version -eq 2) {
            if ($marker.Count -ne 1 -or $app.AppIndex -ne 1 -or
                $app.AppId -cne 'Microsoft.WindowsCalculator_8wekyb3d8bbwe!App' -or
                $marker.Calculator.AppId -cne $app.AppId -or
                $app.StartRequested -isnot [bool] -or $app.Closed -isnot [bool] -or
                $app.CloseRequested -isnot [bool] -or $marker.OriginalSlot -lt 0 -or
                ($app.StartRequested -and $app.LaunchAfterTicks -le 0)) {
                throw 'Invalid Calculator ownership record.'
            }
            $baselineSlot = @($marker.Taskbar.apps | Where-Object automationId -CEQ "Appid: $($app.AppId)")
            $expectedSlot = if ($baselineSlot.Count) {
                [array]::IndexOf(@($marker.Taskbar.apps.automationId), "Appid: $($app.AppId)") + 1
            } else { 0 }
            if ($marker.OriginalSlot -ne $expectedSlot) { throw 'Calculator original slot differs from the immutable taskbar baseline.' }
            if ($app.Identity -and (-not $app.StartRequested -or -not $app.ContentProcess -or $app.Identity.hwnd -le 0 -or
                $app.ContentProcess.ProcessId -le 0 -or $app.ContentProcess.ProcessStartTicks -le 0 -or
                $app.ContentProcess.Path -ine $marker.Calculator.ExecutablePath -or
                $app.Identity.hwnd -in $marker.ExistingWindows)) { throw 'Invalid Calculator window identity.' }
            continue
        }
        if ($app.AppIndex -ne $i -or $app.AppId -cne "PowerToys.Verification.H11.$($stored.Id).$i" -or
            $app.StatePath -cne (Join-Path $stored.Workspace "taskbar-$($stored.Id).$i.state.json") -or
            $app.StartRequested -isnot [bool] -or $app.Closed -isnot [bool] -or
            $app.CloseRequested -isnot [bool]) { throw 'Invalid fixture app ownership record.' }
        Assert-PtTaskbarLocalPath $app.StatePath
        if ($app.Launcher -and ($app.Launcher.ProcessId -le 0 -or $app.Launcher.ProcessStartTicks -le 0 -or -not $app.StartRequested)) {
            throw 'Invalid fixture launcher identity.'
        }
        if ($app.Identity -and (-not $app.Launcher -or $app.Identity.hwnd -le 0 -or
            $app.Identity.processId -ne $app.Launcher.ProcessId -or
            $app.Identity.processStartTicks -ne $app.Launcher.ProcessStartTicks -or -not $app.Identity.className)) {
            throw 'Invalid fixture window identity.'
        }
    }
    [pscustomobject]@{ Fixture = $(if ($Fixture) { $Fixture } else { $stored }); Marker = $marker }
}

function Get-PtTaskbarSurface {
    Initialize-PtUiAutomation
    Initialize-PtTaskbarNative
    $taskbars = @(Get-PtNativeWindow -ClassName Shell_TrayWnd -Visible)
    if ($taskbars.Count -ne 1) { throw 'Expected exactly one visible primary taskbar.' }
    $window = $taskbars[0]
    $dpi = [PtDesktop]::SetThreadDpiAwarenessContext([IntPtr](-4))
    if ($dpi -eq [IntPtr]::Zero) { throw 'Cannot establish physical taskbar coordinates.' }
    try {
        $monitor = [PtTaskbarNative]::PrimaryMonitor($window.Hwnd)
        $root = [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$window.Hwnd)
        $condition = [Windows.Automation.PropertyCondition]::new(
            [Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Button)
        $apps = @(foreach ($element in $root.FindAll([Windows.Automation.TreeScope]::Descendants, $condition)) {
            $current = $element.Current
            if ($current.AutomationId.StartsWith('Appid:', [StringComparison]::Ordinal)) {
                $rect = $current.BoundingRectangle
                [pscustomobject]@{ AutomationId = $current.AutomationId; Offscreen = $current.IsOffscreen
                    RuntimeId = @($element.GetRuntimeId()); X = $rect.X; Y = $rect.Y; Width = $rect.Width; Height = $rect.Height }
            }
        })
        [pscustomobject]@{ Taskbar = (Get-PtWindowIdentity $window.Hwnd); Rect = $window.Rect; Monitor = $monitor; Apps = $apps }
    } finally { [void][PtDesktop]::SetThreadDpiAwarenessContext($dpi) }
}

function ConvertTo-PtTaskbarSlots {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Surface)
    $rect = $Surface.Rect
    $monitor = $Surface.Monitor
    if ($Surface.Taskbar.hwnd -le 0 -or $Surface.Taskbar.className -cne 'Shell_TrayWnd' -or
        $rect.Right -le $rect.Left -or $rect.Bottom -le $rect.Top -or
        ($rect.Right - $rect.Left) -le ($rect.Bottom - $rect.Top) -or
        $rect.Left -lt $monitor.Left -or $rect.Right -gt $monitor.Right -or
        $rect.Top -lt $monitor.Top -or $rect.Bottom -gt $monitor.Bottom -or
        ($rect.Top -ne $monitor.Top -and $rect.Bottom -ne $monitor.Bottom)) {
        throw 'Only a fully visible horizontal primary taskbar is supported.'
    }
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $apps = @($Surface.Apps | Sort-Object X)
    if (-not $apps.Count) { throw 'No taskbar app slots were observed.' }
    $slots = @()
    $right = $rect.Left
    $rowTop = $rect.Top
    $rowBottom = $rect.Bottom
    foreach ($app in $apps) {
        if ($app.AutomationId -cnotmatch '^Appid: .+$' -or -not $ids.Add($app.AutomationId)) {
            throw 'Wrong or duplicate taskbar app identity; never infer a group from its caption.'
        }
        foreach ($value in @($app.X,$app.Y,$app.Width,$app.Height)) {
            if ($null -eq $value -or -not [double]::IsFinite([double]$value)) { throw 'Non-finite taskbar slot geometry.' }
        }
        if ($app.Offscreen -or $app.Width -le 0 -or $app.Height -le 0 -or
            $app.X -lt $right -or $app.Y -lt $rect.Top -or
            $app.X + $app.Width -gt $rect.Right -or $app.Y + $app.Height -gt $rect.Bottom) {
            $error = [Management.Automation.ErrorRecord]::new(
                [InvalidOperationException]::new('Taskbar slot geometry is zero, overlapping, offscreen or outside the primary taskbar.'),
                'PtTaskbarGeometryUnavailable', [Management.Automation.ErrorCategory]::ResourceUnavailable, $Surface.Taskbar)
            $PSCmdlet.ThrowTerminatingError($error)
        }
        $rowTop = [Math]::Max($rowTop, $app.Y)
        $rowBottom = [Math]::Min($rowBottom, $app.Y + $app.Height)
        if ($rowTop -ge $rowBottom) { throw 'Multiple taskbar rows are unsupported.' }
        $right = $app.X + $app.Width
        $centerX = [int][Math]::Floor($app.X + $app.Width / 2)
        $centerY = [int][Math]::Floor($app.Y + $app.Height / 2)
        if ($centerX -lt $app.X -or $centerY -lt $app.Y) { throw 'Taskbar slot geometry has no safe physical center.' }
        $slots += [pscustomobject]@{ Slot = $slots.Count + 1; AutomationId = $app.AutomationId
            AppId = $app.AutomationId.Substring(7)
            X = $app.X; Y = $app.Y; Width = $app.Width; Height = $app.Height
            CenterX = $centerX; CenterY = $centerY }
    }
    [pscustomobject]@{ Taskbar = $Surface.Taskbar; CoordinateSpace = 'Physical'; ObservedAtUtc = [DateTime]::UtcNow.ToString('o')
        Bounds = $rect; Apps = $slots }
}

function Get-PtTaskbarSlots {
    <# .SYNOPSIS
    Fresh, shallow physical app identities/slots on the visible horizontal primary taskbar.
    #>
    param()
    ConvertTo-PtTaskbarSlots (Get-PtTaskbarSurface)
}

function Assert-PtTaskbarForeignOrder {
    param($Fixture,$Marker,$Slots)
    if ((ConvertTo-Json $Slots.Taskbar -Compress) -cne (ConvertTo-Json $Marker.Taskbar.taskbar -Compress)) {
        throw 'Taskbar identity changed; refusing mutation after Explorer/window replacement.'
    }
    $owned = @($Fixture.Apps | ForEach-Object { "Appid: $($_.AppId)" })
    $foreign = @($Slots.Apps | Where-Object { $_.AutomationId -cnotin $owned } | ForEach-Object AutomationId)
    $original = @($Marker.Taskbar.apps | Where-Object { $_.automationId -cnotin $owned } | ForEach-Object automationId)
    if ((ConvertTo-Json -InputObject $foreign -Compress) -cne (ConvertTo-Json -InputObject $original -Compress)) {
        # Match JSON's DateTime round-trip so unchanged receipts remain comparable.
        $observedAtUtc = [DateTime]::Parse($Slots.ObservedAtUtc,
            [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        $facts = [pscustomobject]@{ ExpectedOrder=$original; ActualOrder=$foreign; ObservedAtUtc=$observedAtUtc
            Added=@($foreign | Where-Object { $_ -cnotin $original }); Removed=@($original | Where-Object { $_ -cnotin $foreign }) }
        $error = [InvalidOperationException]::new('Foreign taskbar app order/set conflict; concurrent changes are preserved. ' +
            "Expected=$($original -join ','); Actual=$($foreign -join ',').")
        $error.Data['PtTaskbarForeignOrder'] = $facts
        throw $error
    }
}

function Get-PtTaskbarGuardedDesktop {
    param($Fixture,$Marker,$ExpectedPointer = $Fixture.LastDesktop.pointer,$AdditionalForeground)
    $current = Get-PtDesktopSnapshot
    $foregroundWindow = Get-PtWindowSnapshot -Hwnd $Marker.Desktop.foreground.hwnd
    if ((ConvertTo-Json $foregroundWindow -Depth 12 -Compress) -cne
        (ConvertTo-Json $Marker.ForegroundWindow -Depth 12 -Compress)) {
        throw 'Desktop cleanup conflict: original foreground window placement/visibility changed; preserving it.'
    }
    $allowed = @($Marker.Desktop.foreground,$Fixture.LastDesktop.foreground) +
        @($Fixture.Apps | Where-Object Identity | ForEach-Object Identity)
    if ($AdditionalForeground) { $allowed += $AdditionalForeground }
    $matches = @($allowed | Where-Object {
        (ConvertTo-Json $_ -Compress) -ceq (ConvertTo-Json $current.foreground -Compress)
    })
    $pointerMatches = $current.pointer.X -eq $ExpectedPointer.X -and $current.pointer.Y -eq $ExpectedPointer.Y
    $alreadyRestored = (ConvertTo-Json $current -Depth 12 -Compress) -ceq (ConvertTo-Json $Marker.Desktop -Depth 12 -Compress)
    if (-not $matches.Count -or (-not $pointerMatches -and -not $alreadyRestored)) {
        $error = [InvalidOperationException]::new(
            "Desktop cleanup conflict: unknown foreground/pointer changes are preserved. " +
            "ForegroundMatched=$([bool]$matches.Count); PointerMatched=$pointerMatches; " +
            "ActualForeground=$($current.foreground.hwnd)/$($current.foreground.processId)/$($current.foreground.processStartTicks); " +
            "AllowedHwnds=$(@($allowed.hwnd | Select-Object -Unique) -join ','); " +
            "ActualPointer=$($current.pointer.X),$($current.pointer.Y); ExpectedPointer=$($ExpectedPointer.X),$($ExpectedPointer.Y).")
        $error.Data['PtTaskbarDesktopConflict'] = [pscustomobject]@{
            ForegroundMatched = [bool]$matches.Count; PointerMatched = $pointerMatches; AlreadyRestored = $alreadyRestored
            ActualForeground = $current.foreground; AllowedForeground = $allowed
            ActualPointer = $current.pointer; ExpectedPointer = $ExpectedPointer
        }
        throw $error
    }
    $current
}

function Get-PtTaskbarProcess {
    param([Parameter(Mandatory)][int]$ProcessId)
    try { $process = [Diagnostics.Process]::GetProcessById($ProcessId) }
    catch [ArgumentException] { return $null }
    try {
        [pscustomobject]@{ ProcessId = $process.Id; ProcessStartTicks = $process.StartTime.ToUniversalTime().Ticks }
    } catch [InvalidOperationException] {
        if (-not $process.HasExited) { throw }
    } finally { $process.Dispose() }
}

function Resolve-PtTaskbarOwnedWindow {
    param($Fixture,$App,[switch]$AllowAbsent)
    if ($Fixture.Version -eq 2) {
        if (-not $App.StartRequested) {
            if ($AllowAbsent) { return }
            throw 'Calculator was not launched.'
        }
        $marker = (Read-PtTaskbarFixture -ReceiptPath $Fixture.ReceiptPath).Marker
        $candidates = @(Get-PtTaskbarCalculatorWindows -Calculator $marker.Calculator |
            Where-Object { $_.Identity.className -cne 'Windows.UI.Core.CoreWindow' })
        if (-not $candidates.Count -and $AllowAbsent) {
            if (-not $App.Identity) { throw 'Calculator activation has no resolved window identity; preserve the receipt for cleanup after activation settles.' }
            if (@(Get-PtNativeWindow | Where-Object Hwnd -eq $App.Identity.hwnd).Count) {
                throw 'Calculator window still exists but its content identity is unavailable; preserving it.'
            }
            return
        }
        if ($candidates.Count -ne 1) { throw 'Expected exactly one Calculator window; no shared or ambiguous window is owned.' }
        $candidate = $candidates[0]
        $sameContent = $App.ContentProcess -and
            (ConvertTo-Json $candidate.ContentProcess -Compress) -ceq (ConvertTo-Json $App.ContentProcess -Compress)
        $startupReparent = $sameContent -and $App.Identity.className -ceq 'Windows.UI.Core.CoreWindow' -and
            $candidate.Identity.className -ceq 'ApplicationFrameWindow' -and
            $Fixture.Phase -in 'Creating','Cleaning' -and -not $Fixture.Pending -and -not $Fixture.LastOperation
        if ($candidate.Identity.hwnd -in $marker.ExistingWindows -or
            ($App.Identity -and -not $startupReparent -and (ConvertTo-Json $candidate.Identity -Compress) -cne (ConvertTo-Json $App.Identity -Compress)) -or
            ($App.ContentProcess -and -not $sameContent)) {
            throw 'Calculator identity changed or belongs to a pre-existing window; refusing to close or route.'
        }
        if ($startupReparent) {
            $Fixture | Add-Member -Force NoteProperty StartupReparent ([pscustomobject]@{
                From=$App.Identity; To=$candidate.Identity; ContentProcess=$candidate.ContentProcess
            })
        }
        if (-not $App.ContentProcess) {
            $App.ContentProcess = [pscustomobject]@{ ProcessId=$candidate.ContentProcess.ProcessId
                ProcessStartTicks=$candidate.ContentProcess.ProcessStartTicks; Path=$candidate.ContentProcess.Path }
        }
        Assert-PtWindowIdentity $candidate.Identity
        return $candidate.Identity
    }
    if (-not $App.Launcher) {
        if ($App.StartRequested) { throw 'Launch intent has no persisted process identity; ownership is unresolved.' }
        if ($AllowAbsent) { return }
        throw 'Fixture was not launched.'
    }
    $process = Get-PtTaskbarProcess $App.Launcher.ProcessId
    if (-not $process) {
        if ($AllowAbsent) { return }
        throw 'Owned fixture process has exited.'
    }
    if ($process.ProcessStartTicks -ne $App.Launcher.ProcessStartTicks) { throw 'Fixture PID was reused; refusing to close or route.' }
    if (-not (Test-Path -LiteralPath $App.StatePath)) { throw 'Fixture state is not ready; retain receipt and retry cleanup.' }
    $state = Get-Content -LiteralPath $App.StatePath -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($state.Version -ne 1 -or $state.FixtureId -cne $Fixture.Id -or $state.AppId -cne $App.AppId -or
        $state.ProcessId -ne $process.ProcessId -or $state.ProcessStartTicks -ne $process.ProcessStartTicks -or $state.Hwnd -le 0) {
        throw 'Fixture child state does not match the owned process/app marker.'
    }
    $windows = @(Get-PtNativeWindow -ProcessId $process.ProcessId -Visible)
    if ($windows.Count -eq 0 -and $AllowAbsent) {
        $remaining = @(Get-PtNativeWindow -ProcessId $process.ProcessId | Where-Object Hwnd -eq $state.Hwnd)
        if (-not $remaining.Count) { return }
        $windows = $remaining
    }
    if ($windows.Count -ne 1 -or $windows[0].Hwnd -ne $state.Hwnd) {
        throw 'Expected exactly one owned fixture window; foreign/duplicate HWNDs are not close targets.'
    }
    $identity = Get-PtWindowIdentity $state.Hwnd
    if ($identity.processId -ne $state.ProcessId -or $identity.processStartTicks -ne $state.ProcessStartTicks -or
        ($App.Identity -and (ConvertTo-Json $identity -Compress) -cne (ConvertTo-Json $App.Identity -Compress))) {
        throw 'Fixture HWND identity changed.'
    }
    $identity
}

function Assert-PtTaskbarTargets {
    param($Fixture,$Slots)
    foreach ($app in $Fixture.Apps) {
        if ($app.Closed -or @($Slots.Apps | Where-Object AutomationId -CEQ "Appid: $($app.AppId)").Count -ne 1) {
            throw 'Expected exactly one taskbar button per owned app.'
        }
        $identity = Resolve-PtTaskbarOwnedWindow $Fixture $app
        if (-not $app.Identity) { throw 'Fixture window identity has not been persisted.' }
        Assert-PtWindowIdentity $identity
    }
}

function Test-PtTaskbarKeyDown {
    param([int]$Key)
    ([PtChord]::GetAsyncKeyState($Key) -band 0x8000) -ne 0
}

function Assert-PtTaskbarInputIdle {
    param([int]$HeldWindowsKey = 0)
    foreach ($key in @(1,2,4,5,6,0x10,0x11,0x12,0x5B,0x5C,0xA0,0xA1,0xA2,0xA3,0xA4,0xA5) + @(0x30..0x39)) {
        if ($key -eq $HeldWindowsKey) { continue }
        if (Test-PtTaskbarKeyDown $key) { throw "Input is not idle (VK $key); no input or cleanup release is permitted." }
    }
    if ($HeldWindowsKey -and -not (Test-PtTaskbarKeyDown $HeldWindowsKey)) { throw 'The specified Windows key is not held.' }
    Get-PtForegroundWindow | Out-Null
}

function Get-PtTaskbarPointer {
    $point = [PtDesktop+POINT]::new()
    if (-not [PtDesktop]::GetCursorPos([ref]$point)) { throw 'Cannot observe physical pointer.' }
    $point
}

function Send-PtTaskbarMouse {
    param([ValidateSet('Move','Down','Up')][string]$Kind,[int]$X,[int]$Y)
    Initialize-PtTaskbarNative
    [PtTaskbarNative]::Mouse($Kind, $X, $Y)
}

function Wait-PtTaskbarDragDelivery {
    param($Movement,[switch]$WhileButtonHeld)
    $plannedPoints = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for ($step = 0; $step -le 60; $step++) {
        $x = [int][Math]::Round($Movement.Source.X + ($Movement.Destination.X - $Movement.Source.X) * $step / 60)
        $y = [int][Math]::Round($Movement.Source.Y + ($Movement.Destination.Y - $Movement.Source.Y) * $step / 60)
        [void]$plannedPoints.Add("$x,$y")
    }
    $settle = @{ Consecutive = 0 }
    $expectedPoint = $Movement.LastAccepted
    $buttonState = if ($WhileButtonHeld) { 'owned button held' } else { 'button release' }
    try {
        Wait-PtCondition -Description "native drag endpoint and $buttonState at $($expectedPoint.X),$($expectedPoint.Y)" `
            -TimeoutSeconds 4 -PollMilliseconds 25 -Probe {
                $observed = Get-PtTaskbarPointer
                $Movement.LastRead = [pscustomobject]@{ X = $observed.X; Y = $observed.Y }
                $Movement.SettleSamples++
                if (-not $plannedPoints.Contains("$($observed.X),$($observed.Y)")) {
                    throw "Native drag pointer left the planned path: actual $($observed.X),$($observed.Y); expected $($expectedPoint.X),$($expectedPoint.Y)."
                }
                $buttonDown = Test-PtTaskbarKeyDown 1
                if ($WhileButtonHeld -and -not $buttonDown) { throw 'Owned drag button was released before layout verification.' }
                if ($observed.X -eq $expectedPoint.X -and $observed.Y -eq $expectedPoint.Y -and
                    $buttonDown -eq [bool]$WhileButtonHeld) { $settle.Consecutive++ }
                else { $settle.Consecutive = 0 }
                if ($settle.Consecutive -ge 2) { $Movement.LastRead }
            }
    } catch { $Movement.SettlementError = $_.Exception.Message; throw }
}

function Invoke-PtTaskbarNativeDrag {
    param($From,$To,$Fixture,$Marker)
    Assert-PtTaskbarInputIdle
    $down = $false
    $original = $null
    $motionComplete = $false
    $movement = [pscustomobject]@{
        CoordinateSpace = 'Physical'; Source = [pscustomobject]@{ X = $From.CenterX; Y = $From.CenterY }
        Destination = [pscustomobject]@{ X = $To.CenterX; Y = $To.CenterY }
        LastAccepted = $null; LastObserved = $null; LastRead = $null; Step = -1
        LeftDownAccepted = $false; LeftUpAccepted = $false; Settled = $false; SettleSamples = 0
        SettlementError = $null; OrderVerifiedWhileHeld = $false; Completed = $false
        GeometryUnavailableCount = 0; LastGeometryError = $null
    }
    if ($Fixture) { $Fixture.Pending.Pointer = $movement; Save-PtTaskbarFixture $Fixture }
    try {
        for ($step = 0; $step -le 60; $step++) {
            $x = [int][Math]::Round($From.CenterX + ($To.CenterX - $From.CenterX) * $step / 60)
            $y = [int][Math]::Round($From.CenterY + ($To.CenterY - $From.CenterY) * $step / 60)
            if ((Send-PtTaskbarMouse Move $x $y) -ne 1) { throw "Native drag move $step failed." }
            $movement.LastAccepted = [pscustomobject]@{ X = $x; Y = $y }
            $movement.Step = $step
            $point = Wait-PtCondition -Description "owned physical drag pointer $x,$y at step $step" `
                -TimeoutSeconds 1 -PollMilliseconds 25 -Probe {
                    $observed = Get-PtTaskbarPointer
                    $movement.LastRead = [pscustomobject]@{ X = $observed.X; Y = $observed.Y }
                    if ($observed.X -eq $x -and $observed.Y -eq $y) { $movement.LastRead }
                }
            $movement.LastObserved = $point
            if ($Fixture) {
                if ($step -eq 0 -or $step -eq 60) { Save-PtTaskbarFixture $Fixture }
            }
            if ($step -eq 0) {
                Assert-PtTaskbarInputIdle
                if ((Send-PtTaskbarMouse Down) -ne 1) { throw 'Native left-button down failed.' }
                $down = $true
                $movement.LeftDownAccepted = $true
                if ($Fixture) { Save-PtTaskbarFixture $Fixture }
                Wait-PtCondition -Description 'injected left-button down' -TimeoutSeconds 1 -PollMilliseconds 25 -Probe {
                    Test-PtTaskbarKeyDown 1
                } | Out-Null
            } else { Start-Sleep -Milliseconds 25 }
        }
        if ($Fixture) {
            Wait-PtCondition -Description 'requested taskbar order while owned left button is held' `
                -TimeoutSeconds 4 -PollMilliseconds 50 -Probe {
                    Wait-PtTaskbarDragDelivery $movement -WhileButtonHeld | Out-Null
                    try { $current = Get-PtTaskbarSlots }
                    catch {
                        if ($_.FullyQualifiedErrorId.Split(',')[0] -cne 'PtTaskbarGeometryUnavailable') { throw }
                        $movement.GeometryUnavailableCount++
                        $movement.LastGeometryError = [pscustomobject]@{ ErrorId = $_.FullyQualifiedErrorId
                            Message = $_.Exception.Message; ObservedAtUtc = [DateTime]::UtcNow }
                        return $null
                    }
                    $Fixture.Pending.ActualOrder = @($current.Apps.AutomationId)
                    $Fixture.Pending.OrderObservedAtUtc = [DateTime]::Parse($current.ObservedAtUtc,
                        [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
                    Assert-PtTaskbarForeignOrder $Fixture $Marker $current
                    Assert-PtTaskbarTargets $Fixture $current
                    if (-not (Test-PtTaskbarKeyDown 1)) { throw 'Owned drag button was released before layout verification.' }
                    $point = Get-PtTaskbarPointer
                    $movement.LastRead = [pscustomobject]@{ X = $point.X; Y = $point.Y }
                    if ($point.X -eq $To.CenterX -and $point.Y -eq $To.CenterY -and
                        (ConvertTo-Json -InputObject @($current.Apps.AutomationId) -Compress) -ceq
                        (ConvertTo-Json -InputObject @($Fixture.Pending.ExpectedOrder) -Compress)) { $current }
                } | Out-Null
            $movement.OrderVerifiedWhileHeld = $true
        }
        $motionComplete = $true
    } catch { $original = $_; throw }
    finally {
        $releaseError = $null
        if ($down) {
            try {
                if ((Send-PtTaskbarMouse Up) -ne 1) { throw 'Native left-button release failed.' }
                $movement.LeftUpAccepted = $true
            } catch { $releaseError = $_ }
        }
        if (-not $releaseError -and $movement.LastAccepted) {
            try {
                $delivered = Wait-PtTaskbarDragDelivery $movement
                $movement.LastObserved = $delivered
                $movement.Settled = $true
                # Accepted SendInput is not delivery; commit only after endpoint and release settle together.
                if ($Fixture) { $Fixture.LastDesktop.pointer = $delivered }
            } catch {
                $movement.SettlementError = $_.Exception.Message
                $releaseError = $_
            }
        }
        $movement.Completed = $motionComplete -and $movement.Settled -and -not $releaseError
        if ($Fixture) {
            try { Save-PtTaskbarFixture $Fixture }
            catch {
                if ($original) { $original.Exception.Data['ReceiptFailure'] = $_; [Console]::Error.WriteLine($_) }
                elseif ($releaseError) { $releaseError.Exception.Data['ReceiptFailure'] = $_; [Console]::Error.WriteLine($_) }
                else { throw }
            }
        }
        if ($releaseError) {
            if ($original) { $original.Exception.Data['InputCleanupFailure'] = $releaseError; [Console]::Error.WriteLine($releaseError) }
            else { throw $releaseError }
        }
    }
}

function Get-PtTaskbarCalculator {
    $packages = @(Get-AppxPackage -Name Microsoft.WindowsCalculator -ErrorAction Stop)
    if ($packages.Count -ne 1) { throw 'Exactly one registered system Calculator package is required; no dummy app will be substituted.' }
    $package = $packages[0]
    $manifest = Get-AppxPackageManifest -Package $package.PackageFullName -ErrorAction Stop
    $apps = @($manifest.Package.Applications.Application | Where-Object Id -eq 'App')
    if ($package.PackageFamilyName -cne 'Microsoft.WindowsCalculator_8wekyb3d8bbwe' -or $apps.Count -ne 1 -or -not $apps[0].Executable) {
        throw 'Unexpected Calculator package identity or executable.'
    }
    $path = Join-Path $package.InstallLocation $apps[0].Executable
    if (-not [IO.File]::Exists($path)) { throw "Calculator executable is missing: $path" }
    [pscustomobject]@{ AppId="$($package.PackageFamilyName)!App"; ExecutablePath=$path; PackageFullName=$package.PackageFullName }
}

function Get-PtTaskbarCalculatorWindows {
    param([Parameter(Mandatory)]$Calculator)
    Initialize-PtUiAutomation
    $processErrors = @()
    $processes = @(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($Calculator.ExecutablePath)) -ErrorAction SilentlyContinue -ErrorVariable processErrors)
    foreach ($errorRecord in $processErrors) {
        if ($errorRecord.FullyQualifiedErrorId -notlike 'NoProcessFoundForGivenName*') { throw $errorRecord }
    }
    foreach ($process in $processes) {
        try {
            if ($process.Path -ine $Calculator.ExecutablePath) { throw 'Calculator process path differs from the registered package.' }
            $content = [pscustomobject]@{ ProcessId=$process.Id; ProcessStartTicks=$process.StartTime.ToUniversalTime().Ticks; Path=$process.Path }
            $windows = @(Get-PtNativeWindow -ProcessId $process.Id -Visible)
            # Older Calculator versions put their content inside a shared ApplicationFrameHost window.
            foreach ($frame in @(Get-PtNativeWindow -ClassName ApplicationFrameWindow -Visible)) {
                $element = [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$frame.Hwnd)
                $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ProcessIdProperty, $process.Id)
                if ($element.FindFirst([Windows.Automation.TreeScope]::Descendants, $condition)) { $windows += $frame }
            }
            foreach ($window in @($windows | Sort-Object Hwnd -Unique)) {
                [pscustomobject]@{ Identity=(Get-PtWindowIdentity $window.Hwnd); ContentProcess=$content }
            }
        } finally { $process.Dispose() }
    }
}

function Start-PtTaskbarCalculator {
    param([Parameter(Mandatory)]$Calculator)
    Start-Process -FilePath "shell:AppsFolder\$($Calculator.AppId)" -ErrorAction Stop
}

function Get-PtTaskbarPointWindow {
    param($Point)
    Initialize-PtTaskbarNative
    [PtTaskbarNative]::PointWindow($Point.X, $Point.Y)
}

function Restore-PtTaskbarDragPointer {
    param($Fixture,$Marker,$Slots)
    $observeBeforeParking = {
        Read-PtTaskbarFixture -Fixture $Fixture | Out-Null
        if ($Fixture.Pending.Method -ceq 'Native') {
            $pointer = $Fixture.Pending.Pointer
            $restoringCalculator = $Fixture.Version -eq 2 -and $Fixture.Phase -ceq 'Cleaning' -and
                $Fixture.Pending.Slot -eq $Marker.OriginalSlot -and $Fixture.Pending.AppId -ceq $Marker.Calculator.AppId
            if (($Fixture.Phase -cne 'Ready' -and -not $restoringCalculator) -or $Fixture.Pending.Kind -cne 'Drag' -or
                $Fixture.Pending.PointerCleanup.Accepted -or $pointer.CoordinateSpace -cne 'Physical' -or
                -not $pointer.Completed -or -not $pointer.Settled -or $pointer.Step -ne 60 -or
                -not $pointer.LeftDownAccepted -or -not $pointer.LeftUpAccepted -or
                $pointer.LastAccepted.X -ne $pointer.Destination.X -or $pointer.LastAccepted.Y -ne $pointer.Destination.Y -or
                $Fixture.LastDesktop.pointer.X -ne $pointer.Destination.X -or
                $Fixture.LastDesktop.pointer.Y -ne $pointer.Destination.Y) {
                throw 'Pre-parking settlement requires this persisted, completed Native drag and its unchanged endpoint baseline.'
            }
            Wait-PtTaskbarDragDelivery $pointer | Out-Null
        }
        Assert-PtTaskbarInputIdle
        Get-PtTaskbarGuardedDesktop $Fixture $Marker
    }
    $before = & $observeBeforeParking
    $target = $Fixture.Pending.PointerBefore
    $bounds = $Slots.Bounds
    $windowTarget = $null
    $kind = 'PreDrag'
    if ($target.X -ge $bounds.Left -and $target.X -lt $bounds.Right -and
        $target.Y -ge $bounds.Top -and $target.Y -lt $bounds.Bottom) {
        $foreground = (Get-PtForegroundWindow).Hwnd
        $app = @($Fixture.Apps | Where-Object { $_.Identity.hwnd -eq $foreground })
        $windowTarget = if ($app.Count -eq 1) { $app[0].Identity } else { $Fixture.Apps[-1].Identity }
        Assert-PtWindowIdentity $windowTarget
        $window = Get-PtNativeWindow -Hwnd $windowTarget.hwnd
        $rect = $window.Rect
        if (-not $window.Visible -or $window.Minimized -or $rect.Right -le $rect.Left -or $rect.Bottom -le $rect.Top) {
            throw 'No visible owned fixture interior is available for pointer cleanup.'
        }
        $target = [pscustomobject]@{ X = [int][Math]::Floor(($rect.Left + $rect.Right) / 2)
            Y = [int][Math]::Floor(($rect.Top + $rect.Bottom) / 2) }
        if (($target.X -ge $bounds.Left -and $target.X -lt $bounds.Right -and
            $target.Y -ge $bounds.Top -and $target.Y -lt $bounds.Bottom) -or
            (Get-PtTaskbarPointWindow $target) -ne $windowTarget.hwnd) {
            throw 'Owned fixture interior is occluded or on the taskbar; refusing to park the pointer there.'
        }
        $kind = 'OwnedInterior'
    }
    $cleanup = [pscustomobject]@{ Kind = $kind; Before = $before.pointer; Target = $target
        Window = $windowTarget; Accepted = $false; Actual = $null; Completed = $false }
    $Fixture.Pending.PointerCleanup = $cleanup
    Save-PtTaskbarFixture $Fixture
    & $observeBeforeParking | Out-Null
    Assert-PtTaskbarInputIdle
    if ($windowTarget) {
        Assert-PtWindowIdentity $windowTarget
        if ((Get-PtTaskbarPointWindow $target) -ne $windowTarget.hwnd) { throw 'Owned pointer target became occluded before movement.' }
    }
    if (-not [PtDesktop]::SetCursorPos($target.X, $target.Y)) { throw 'Owned post-drag SetCursorPos failed.' }
    $cleanup.Accepted = $true
    $settle = @{ Consecutive = 0 }
    $delivered = Wait-PtCondition -Description "post-drag pointer cleanup at $($target.X),$($target.Y)" `
        -TimeoutSeconds 4 -PollMilliseconds 25 -Probe {
            $point = Get-PtTaskbarPointer
            $cleanup.Actual = [pscustomobject]@{ X = $point.X; Y = $point.Y }
            if ($point.X -eq $target.X -and $point.Y -eq $target.Y -and
                -not (Test-PtTaskbarKeyDown 1)) { $settle.Consecutive++ }
            else { $settle.Consecutive = 0 }
            if ($settle.Consecutive -ge 2) { $cleanup.Actual }
        }
    Assert-PtTaskbarInputIdle
    $Fixture.LastDesktop.pointer = $delivered
    Save-PtTaskbarFixture $Fixture
    if ($windowTarget) {
        Assert-PtWindowIdentity $windowTarget
        if ((Get-PtTaskbarPointWindow $delivered) -ne $windowTarget.hwnd) { throw 'Owned pointer target became occluded after movement.' }
    }
    $Fixture.LastDesktop = Get-PtTaskbarGuardedDesktop $Fixture $Marker
    $cleanup.Completed = $true
    Save-PtTaskbarFixture $Fixture
    $cleanup
}

function New-PtTaskbarFixture {
    <# .SYNOPSIS
    Launch one system Calculator with a prelaunch ownership baseline; never create a dummy app.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Workspace,[ValidateRange(1,1)][int]$Count = 1)
    $directory = (Get-Item -LiteralPath $Workspace -ErrorAction Stop).FullName
    Assert-PtTaskbarLocalPath $directory
    if (-not [IO.Directory]::Exists($directory)) { throw 'Use an existing local workspace directory.' }
    $calculator = Get-PtTaskbarCalculator
    if (@(Get-PtTaskbarCalculatorWindows -Calculator $calculator).Count) {
        throw 'Calculator is already open; preserve the user window and use this fixture only after it is no longer in use.'
    }
    Assert-PtTaskbarInputIdle
    $desktop = Get-PtDesktopSnapshot
    $foregroundWindow = Get-PtWindowSnapshot -Hwnd $desktop.foreground.hwnd
    $baseline = Get-PtShortcutGuideTaskbarSnapshot
    $initialSlots = Get-PtTaskbarSlots
    $id = [Guid]::NewGuid().ToString('N')
    $original = @($initialSlots.Apps | Where-Object AppId -CEQ $calculator.AppId)
    $fixture = [pscustomobject]@{ Kind = 'Taskbar'; Version = 2; Id = $id; Workspace = $directory
        ReceiptPath = (Join-Path $directory "taskbar-$id.json"); MarkerPath = (Join-Path $directory "taskbar-$id.marker.json")
        MarkerHash = ''; Phase = 'Creating'; Pending = $null; LastOperation = $null; LastDesktop = $desktop
        DesktopRestored = $false; CleanupErrors = @()
        Apps = @([pscustomobject]@{ AppIndex=1; AppId=$calculator.AppId; StartRequested=$false
            LaunchAfterTicks=0L; ContentProcess=$null; Identity=$null; CloseRequested=$false; Closed=$false }) }
    $marker = [pscustomobject]@{ Kind = 'Taskbar'; Version = 2; Id = $id; Count = 1; Workspace = $directory
        ReceiptPath = $fixture.ReceiptPath; Desktop = $desktop; ForegroundWindow = $foregroundWindow; Taskbar = $baseline
        Calculator=$calculator; OriginalSlot=$(if ($original.Count) { $original[0].Slot } else { 0 })
        ExistingWindows=@(Get-PtNativeWindow | ForEach-Object Hwnd) }
    Assert-PtTaskbarForeignOrder $fixture $marker $initialSlots
    Write-PtTaskbarJson -Path $fixture.MarkerPath -Value $marker -Create
    $fixture.MarkerHash = (Get-FileHash -LiteralPath $fixture.MarkerPath).Hash
    Save-PtTaskbarFixture $fixture -Create
    try {
        if (@(Get-PtTaskbarCalculatorWindows -Calculator $calculator).Count) {
            throw 'Calculator appeared before fixture activation; preserving the concurrent window.'
        }
        $app = $fixture.Apps[0]
        $app.StartRequested = $true
        $app.LaunchAfterTicks = [DateTime]::UtcNow.Ticks
        Save-PtTaskbarFixture $fixture
        Start-PtTaskbarCalculator -Calculator $calculator
        $windowReady = @{ Signature=''; Count=0 }
        Wait-PtCondition -Description 'settled Calculator top-level frame' -TimeoutSeconds 15 -Probe {
            $candidates = @(Get-PtTaskbarCalculatorWindows -Calculator $calculator |
                Where-Object { $_.Identity.className -cne 'Windows.UI.Core.CoreWindow' })
            if ($candidates.Count -gt 1) { throw 'More than one Calculator top-level frame appeared; ownership is ambiguous.' }
            if ($candidates.Count -eq 1) {
                $signature = ConvertTo-Json $candidates[0] -Depth 6 -Compress
                $windowReady.Count = if ($signature -ceq $windowReady.Signature) { $windowReady.Count + 1 } else { 1 }
                $windowReady.Signature = $signature
                if ($windowReady.Count -ge 2) { $true }
            } else { $windowReady.Count=0; $windowReady.Signature='' }
        } | Out-Null
        $app.Identity = Resolve-PtTaskbarOwnedWindow $fixture $app
        Save-PtTaskbarFixture $fixture
        $fixture.LastDesktop = Get-PtTaskbarGuardedDesktop $fixture $marker
        Save-PtTaskbarFixture $fixture
        $admission = @{ Stable=0 }
        $slots = Wait-PtCondition -Description 'Calculator taskbar button and stable foreign order' -TimeoutSeconds 9 -Probe {
            $current = Get-PtTaskbarSlots
            try { Assert-PtTaskbarForeignOrder $fixture $marker $current }
            catch {
                if (-not $_.Exception.Data.Contains('PtTaskbarForeignOrder')) { throw }
                $fixture | Add-Member -Force NoteProperty AdmissionConflict $_.Exception.Data['PtTaskbarForeignOrder']
                Save-PtTaskbarFixture $fixture
                $admission.Stable = 0
                return
            }
            if (@($current.Apps | Where-Object AppId -CEQ $app.AppId).Count -eq 1) {
                $admission.Stable++
                if ($admission.Stable -ge 2) { $current }
            } else { $admission.Stable = 0 }
        }
        Assert-PtTaskbarTargets $fixture $slots
        $fixture.Phase = 'Ready'
        $fixture.LastDesktop = Get-PtTaskbarGuardedDesktop $fixture $marker
        Save-PtTaskbarFixture $fixture
        $fixture
    } catch {
        $original = $_
        $original.Exception.Data['FixtureReceipt'] = $fixture.ReceiptPath
        try { Remove-PtTaskbarFixture -ReceiptPath $fixture.ReceiptPath | Out-Null }
        catch { $original.Exception.Data['FixtureCleanupFailure'] = $_; [Console]::Error.WriteLine($_) }
        throw $original
    }
}

function Move-PtTaskbarFixtureToSlot {
    <# .SYNOPSIS
    Drag only an owned app; actual observed order, not CLI success, completes the operation.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Fixture,[ValidateRange(1,9)][int]$AppIndex = 1,
        [ValidateRange(1,2147483647)][int]$Slot = 1,[ValidateSet('WinApp','Native')][string]$DragMethod = 'Native',
        [switch]$RestoreOriginalSlot)
    $record = Read-PtTaskbarFixture -Fixture $Fixture
    if ($RestoreOriginalSlot) {
        if ($Fixture.Version -ne 2 -or $Fixture.Phase -cne 'Cleaning' -or $AppIndex -ne 1 -or
            $Slot -ne $record.Marker.OriginalSlot) { throw 'Cleanup may only restore Calculator to its recorded original slot.' }
    } elseif ($Fixture.Phase -cne 'Ready' -or $Fixture.Pending) { throw 'Fixture is not ready; cleanup is required.' }
    $apps = @($Fixture.Apps | Where-Object AppIndex -eq $AppIndex)
    if ($apps.Count -ne 1) { throw 'Requested owned app index is absent.' }
    Assert-PtTaskbarInputIdle
    $preDrag = Get-PtTaskbarGuardedDesktop $Fixture $record.Marker
    $before = Get-PtTaskbarSlots
    Assert-PtTaskbarForeignOrder $Fixture $record.Marker $before
    Assert-PtTaskbarTargets $Fixture $before
    if ($Slot -gt $before.Apps.Count) { throw 'Requested taskbar slot is absent.' }
    $from = @($before.Apps | Where-Object AppId -CEQ $apps[0].AppId)[0]
    if ($from.Slot -eq $Slot) {
        return [pscustomobject]@{ Changed = $false; AppId = $from.AppId; Slot = $Slot; Target = $apps[0].Identity; DragMethod = $null }
    }
    $expected = [Collections.Generic.List[string]]::new()
    foreach ($item in $before.Apps) { $expected.Add($item.AutomationId) }
    $expected.RemoveAt($from.Slot - 1)
    $expected.Insert($Slot - 1, $from.AutomationId)
    $Fixture.Pending = [pscustomobject]@{ Kind = 'Drag'; AppId = $from.AppId; Slot = $Slot; Method = $DragMethod
        PointerBefore = $preDrag.pointer; Pointer = $null; PointerCleanup = $null; Insertion = $null
        ExpectedOrder = @($expected); ActualOrder = $null; OrderObservedAtUtc = $null; Error = $null }
    $intent = $Fixture.Pending
    Save-PtTaskbarFixture $Fixture
    try {
        $fresh = Get-PtTaskbarSlots
        Assert-PtTaskbarForeignOrder $Fixture $record.Marker $fresh
        Assert-PtTaskbarTargets $Fixture $fresh
        if ((ConvertTo-Json $fresh.Apps -Compress) -cne (ConvertTo-Json $before.Apps -Compress)) {
            throw 'Taskbar geometry/order changed before drag; no gesture issued.'
        }
        $from = @($fresh.Apps | Where-Object AppId -CEQ $apps[0].AppId)[0]
        $destination = $fresh.Apps[$Slot - 1]
        $movingLeft = $from.Slot -gt $Slot
        $fraction = if ($movingLeft) { 0.25 } else { 0.75 }
        $minimumX = [Math]::Ceiling($destination.X)
        $maximumX = [Math]::Ceiling($destination.X + $destination.Width) - 1
        if ($minimumX -gt $maximumX) { throw 'Destination button has no physical insertion point.' }
        $dropX = [int][Math]::Max($minimumX, [Math]::Min($maximumX,
            [Math]::Floor($destination.X + $destination.Width * $fraction)))
        $side = if ($movingLeft) { 'Left' } else { 'Right' }
        if ($Slot -eq 1) {
            $dropX = [int][Math]::Ceiling($destination.X) - 1
            if ($dropX -lt $fresh.Bounds.Left -or $dropX -ge $fresh.Bounds.Right) {
                throw 'No physical insertion point before the first app exists inside the taskbar.'
            }
            $side = 'BeforeFirst'
        }
        $to = [pscustomobject]@{ CenterX = $dropX; CenterY = $destination.CenterY }
        $intent.Insertion = [pscustomobject]@{ Side = $side
            AutomationId = $destination.AutomationId; X = $dropX; Y = $destination.CenterY }
        Save-PtTaskbarFixture $Fixture
        Get-PtTaskbarGuardedDesktop $Fixture $record.Marker | Out-Null
        Assert-PtTaskbarInputIdle
        if ($DragMethod -eq 'Native') { Invoke-PtTaskbarNativeDrag $from $to -Fixture $Fixture -Marker $record.Marker }
        else {
            Invoke-PtWinApp -Arguments @('drag',"$($from.CenterX),$($from.CenterY)","$($to.CenterX),$($to.CenterY)",
                '-w',"$($fresh.Taskbar.hwnd)",'--hold-ms','250','--dwell-ms','100') | Out-Null
        }
        Assert-PtTaskbarInputIdle
        $pointer = [pscustomobject]@{ X = $to.CenterX; Y = $to.CenterY }
        $Fixture.LastDesktop = Get-PtTaskbarGuardedDesktop $Fixture $record.Marker -ExpectedPointer $pointer -AdditionalForeground $fresh.Taskbar
        Save-PtTaskbarFixture $Fixture
        $actual = Wait-PtCondition -Description 'actual taskbar order after owned drag' -TimeoutSeconds 4 -Probe {
            $current = Get-PtTaskbarSlots
            $intent.ActualOrder = @($current.Apps.AutomationId)
            $intent.OrderObservedAtUtc = [DateTime]::Parse($current.ObservedAtUtc,
                [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            Assert-PtTaskbarForeignOrder $Fixture $record.Marker $current
            if ((ConvertTo-Json -InputObject @($current.Apps.AutomationId) -Compress) -ceq
                (ConvertTo-Json -InputObject @($expected) -Compress)) { $current }
        }
        Assert-PtTaskbarTargets $Fixture $actual
        Save-PtTaskbarFixture $Fixture
        $pointerCleanup = Restore-PtTaskbarDragPointer $Fixture $record.Marker $actual
        $actual = Get-PtTaskbarSlots
        $intent.ActualOrder = @($actual.Apps.AutomationId)
        $intent.OrderObservedAtUtc = [DateTime]::Parse($actual.ObservedAtUtc,
            [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        Assert-PtTaskbarForeignOrder $Fixture $record.Marker $actual
        Assert-PtTaskbarTargets $Fixture $actual
        if ((ConvertTo-Json -InputObject @($actual.Apps.AutomationId) -Compress) -cne
            (ConvertTo-Json -InputObject @($expected) -Compress)) { throw 'Taskbar order changed during pointer cleanup.' }
        $facts = [pscustomobject]@{ Changed = $true; AppId = $from.AppId; Slot = $Slot; Target = $apps[0].Identity
            DragMethod = $DragMethod; Order = @($actual.Apps.AutomationId); Pointer = $Fixture.Pending.Pointer
            PointerCleanup = $pointerCleanup; Insertion = $intent.Insertion }
        $Fixture.LastOperation = $facts
        $Fixture.LastDesktop = Get-PtTaskbarGuardedDesktop $Fixture $record.Marker
        $Fixture.Pending = $null
        Save-PtTaskbarFixture $Fixture
        $facts
    } catch {
        $original = $_
        $Fixture.Phase = 'Faulted'
        $Fixture.Pending = $intent
        $Fixture.Pending.Error = [pscustomobject]@{ Message = $original.Exception.Message
            ErrorId = $original.FullyQualifiedErrorId; ScriptStackTrace = $original.ScriptStackTrace }
        $original.Exception.Data['PtTaskbarOrder'] = [pscustomobject]@{
            ExpectedOrder = $intent.ExpectedOrder; ActualOrder = $intent.ActualOrder
            ObservedAtUtc = $intent.OrderObservedAtUtc; Insertion = $intent.Insertion }
        $Fixture.LastOperation = [pscustomobject]@{ Kind = 'Drag'; AppId = $intent.AppId; Slot = $intent.Slot
            DragMethod = $intent.Method; Outcome = 'Error'; Pointer = $intent.Pointer
            PointerCleanup = $intent.PointerCleanup; Insertion = $intent.Insertion
            ExpectedOrder = $intent.ExpectedOrder; ActualOrder = $intent.ActualOrder
            OrderObservedAtUtc = $intent.OrderObservedAtUtc; Error = $intent.Error }
        try { Save-PtTaskbarFixture $Fixture } catch { $original.Exception.Data['ReceiptFailure'] = $_ }
        throw $original
    }
}

function Invoke-PtTaskbarSlot {
    <# .SYNOPSIS
    Route a guarded Win+digit to one exact owned HWND; return observed facts, never product PASS.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Fixture,[ValidateRange(1,9)][int]$Slot = 1,
        [switch]$WhileWindowsHeld,[ValidateSet(0x5B,0x5C)][int]$WindowsKey = 0x5B,
        [ValidateNotNull()]$AllowedForegroundTarget)
    $hasAllowedForeground = $PSBoundParameters.ContainsKey('AllowedForegroundTarget')
    if ($hasAllowedForeground -and -not $WhileWindowsHeld) { throw 'AllowedForegroundTarget requires -WhileWindowsHeld.' }
    $validateAllowedForeground = {
        if ($hasAllowedForeground) {
            Assert-PtWindowIdentity $AllowedForegroundTarget
            if ((Get-PtForegroundWindow).Hwnd -ne $AllowedForegroundTarget.hwnd) {
                throw 'Allowed foreground target is not the current foreground window.'
            }
        }
    }
    $record = Read-PtTaskbarFixture -Fixture $Fixture
    if ($Fixture.Phase -cne 'Ready' -or $Fixture.Pending) { throw 'Fixture is not ready; cleanup is required.' }
    $held = if ($WhileWindowsHeld) { $WindowsKey } else { 0 }
    Assert-PtTaskbarInputIdle -HeldWindowsKey $held
    & $validateAllowedForeground
    Get-PtTaskbarGuardedDesktop $Fixture $record.Marker -AdditionalForeground $AllowedForegroundTarget | Out-Null
    $before = Get-PtTaskbarSlots
    Assert-PtTaskbarForeignOrder $Fixture $record.Marker $before
    Assert-PtTaskbarTargets $Fixture $before
    $mapping = @($before.Apps | Where-Object Slot -eq $Slot)
    $app = @($Fixture.Apps | Where-Object AppId -CEQ $mapping.AppId)
    if ($mapping.Count -ne 1 -or $app.Count -ne 1) { throw 'Requested slot is not exactly one owned app; no digit sent.' }
    $target = $app[0].Identity
    $priorForeground = (Get-PtForegroundWindow).Hwnd
    if ($priorForeground -eq $target.hwnd) { throw 'Target is already foreground; Win+digit could minimize it instead of routing.' }
    $Fixture.Pending = [pscustomobject]@{ Kind = 'Route'; Slot = $Slot; AppId = $app[0].AppId; WindowsKey = $WindowsKey
        WhileWindowsHeld = [bool]$WhileWindowsHeld; AllowedForegroundTarget = $AllowedForegroundTarget }
    Save-PtTaskbarFixture $Fixture
    try {
        $route = {
            Assert-PtTaskbarInputIdle -HeldWindowsKey $WindowsKey
            $fresh = Get-PtTaskbarSlots
            Assert-PtTaskbarForeignOrder $Fixture $record.Marker $fresh
            Assert-PtTaskbarTargets $Fixture $fresh
            if (@($fresh.Apps | Where-Object { $_.Slot -eq $Slot -and $_.AppId -ceq $app[0].AppId }).Count -ne 1) {
                throw 'Slot mapping changed before digit input.'
            }
            & $validateAllowedForeground
            Get-PtTaskbarGuardedDesktop $Fixture $record.Marker -AdditionalForeground $AllowedForegroundTarget | Out-Null
            Assert-PtTaskbarInputIdle -HeldWindowsKey $WindowsKey
            Send-PtChord -Key ([uint16](0x30 + $Slot)) | Out-Null
            Wait-PtCondition -Description "exact routed foreground HWND $($target.hwnd)" -TimeoutSeconds 4 -PollMilliseconds 50 -Probe {
                Assert-PtWindowIdentity $target
                if (-not (Test-PtTaskbarKeyDown $WindowsKey)) { throw 'Windows key was released before routing observation.' }
                (Get-PtForegroundWindow).Hwnd -eq $target.hwnd
            } | Out-Null
        }
        if ($WhileWindowsHeld) { & $route }
        else {
            Invoke-PtHeldKeys -Keys @([uint16]$WindowsKey) -KeyDownDelayMilliseconds 0 -Action {
                Wait-PtCondition -Description 'owned Windows-key down' -TimeoutSeconds 1 -PollMilliseconds 10 -Probe {
                    Test-PtTaskbarKeyDown $WindowsKey
                } | Out-Null
                & $route
            }
        }
        Assert-PtTaskbarInputIdle -HeldWindowsKey $held
        $actual = Get-PtTaskbarSlots
        Assert-PtTaskbarForeignOrder $Fixture $record.Marker $actual
        Assert-PtTaskbarTargets $Fixture $actual
        if (@($actual.Apps | Where-Object { $_.Slot -eq $Slot -and $_.AppId -ceq $app[0].AppId }).Count -ne 1 -or
            (Get-PtForegroundWindow).Hwnd -ne $target.hwnd) { throw 'Target mapping/foreground changed after routing.' }
        $facts = [pscustomobject]@{ Slot = $Slot; AppId = $app[0].AppId; Target = $target; ForegroundHwnd = $target.hwnd
            PriorForegroundHwnd = $priorForeground; WindowsKey = $WindowsKey; WhileWindowsHeld = [bool]$WhileWindowsHeld
            WindowsHeldAfter = (Test-PtTaskbarKeyDown $WindowsKey); AllowedForegroundTarget = $AllowedForegroundTarget }
        $Fixture.LastOperation = $facts
        $Fixture.LastDesktop = Get-PtTaskbarGuardedDesktop $Fixture $record.Marker
        $Fixture.Pending = $null
        Save-PtTaskbarFixture $Fixture
        $facts
    } catch {
        $original = $_
        $Fixture.Phase = 'Faulted'
        try { Save-PtTaskbarFixture $Fixture } catch { $original.Exception.Data['ReceiptFailure'] = $_ }
        throw $original
    }
}

function Remove-PtTaskbarFixture {
    <# .SYNOPSIS
    Close only owned windows, attempt every resource, and compare the original taskbar baseline.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Fixture')]
    param([Parameter(Mandatory,Position = 0,ParameterSetName = 'Fixture')]$Fixture,
        [Parameter(Mandatory,ParameterSetName = 'Receipt')][string]$ReceiptPath)
    $record = Read-PtTaskbarFixture -Fixture $Fixture -ReceiptPath $ReceiptPath
    $Fixture = $record.Fixture
    $marker = $record.Marker
    $errors = [Collections.Generic.List[string]]::new()
    $desktopSafe = $false
    if ($Fixture.Version -eq 2 -and $Fixture.Apps[0].Identity.className -ceq 'Windows.UI.Core.CoreWindow' -and
        $Fixture.Phase -in 'Creating','Cleaning' -and -not $Fixture.Pending -and -not $Fixture.LastOperation) {
        $identity = Resolve-PtTaskbarOwnedWindow $Fixture $Fixture.Apps[0] -AllowAbsent
        if ($identity) {
            $Fixture.Apps[0].Identity = $identity
            Save-PtTaskbarFixture $Fixture
        }
    }
    try {
        Assert-PtTaskbarInputIdle
        Assert-PtWindowIdentity $marker.Taskbar.taskbar
        Get-PtTaskbarGuardedDesktop $Fixture $marker -AdditionalForeground $marker.Taskbar.taskbar | Out-Null
        $desktopSafe = $true
    } catch { $errors.Add($_.Exception.Message) }
    if ($Fixture.Phase -ne 'Closed') {
        $Fixture.Phase = 'Cleaning'
        Save-PtTaskbarFixture $Fixture
        $restoreOrderFailed = $false
        if ($Fixture.Version -eq 2 -and $marker.OriginalSlot -gt 0 -and -not $Fixture.Apps[0].Closed) {
            try {
                if (-not $desktopSafe) { throw 'Cannot safely restore the pinned Calculator slot after a desktop conflict.' }
                $identity = Resolve-PtTaskbarOwnedWindow $Fixture $Fixture.Apps[0] -AllowAbsent
                if ($identity) {
                    Move-PtTaskbarFixtureToSlot $Fixture -Slot $marker.OriginalSlot -RestoreOriginalSlot | Out-Null
                } else {
                    $current = Get-PtTaskbarSlots
                    if (@($current.Apps | Where-Object { $_.AppId -ceq $Fixture.Apps[0].AppId -and $_.Slot -eq $marker.OriginalSlot }).Count -ne 1) {
                        throw 'Calculator closed before its original pinned slot was restored.'
                    }
                }
            } catch {
                $restoreOrderFailed = $true
                $errors.Add("Calculator order restoration: $($_.Exception.Message)")
            }
        }
        foreach ($app in $Fixture.Apps) {
            try {
                if ($restoreOrderFailed) { throw 'Calculator is retained so its original pinned slot can be restored safely.' }
                # Re-resolve even a previously closed entry; never credit a reused PID or forged Closed flag.
                $identity = Resolve-PtTaskbarOwnedWindow $Fixture $app -AllowAbsent
                if ($identity) {
                    if ($app.Closed) { throw 'Closed fixture resource reappeared; preserving it as a cleanup conflict.' }
                    $app.Identity = $identity
                    $app.CloseRequested = $true
                    Save-PtTaskbarFixture $Fixture
                    Close-PtTrackedWindow $identity
                }
                if ($Fixture.Version -eq 1 -and $app.Launcher) {
                    Wait-PtCondition -Description "owned fixture PID $($app.Launcher.ProcessId) exit" -TimeoutSeconds 5 -Probe {
                        $process = Get-PtTaskbarProcess $app.Launcher.ProcessId
                        if ($process -and $process.ProcessStartTicks -ne $app.Launcher.ProcessStartTicks) {
                            throw 'Fixture PID was reused during cleanup.'
                        }
                        -not $process
                    } | Out-Null
                }
                $app.Closed = $true
                Save-PtTaskbarFixture $Fixture
            } catch { $errors.Add("App $($app.AppIndex): $($_.Exception.Message)") }
        }
    }
    if ($desktopSafe) {
        try {
            Assert-PtTaskbarInputIdle
            Assert-PtWindowIdentity $marker.Taskbar.taskbar
            $now = Get-PtTaskbarGuardedDesktop $Fixture $marker -AdditionalForeground $marker.Taskbar.taskbar
            if ((ConvertTo-Json $now -Depth 12 -Compress) -cne (ConvertTo-Json $marker.Desktop -Depth 12 -Compress)) {
                Restore-PtDesktopSnapshot $marker.Desktop | Out-Null
            }
            $Fixture.DesktopRestored = $true
            $Fixture.LastDesktop = Get-PtDesktopSnapshot
        } catch { $errors.Add($_.Exception.Message) }
    }
    # This comparison is mandatory even on partial cleanup and repeated removal.
    try {
        $slots = Get-PtTaskbarSlots
        Assert-PtTaskbarForeignOrder $Fixture $marker $slots
        if (($Fixture.Version -eq 1 -or $marker.OriginalSlot -eq 0) -and
            -not @($Fixture.Apps | Where-Object { -not $_.Closed }).Count -and
            @($slots.Apps | Where-Object AppId -CIn @($Fixture.Apps.AppId)).Count) {
            Wait-PtCondition -Description 'closed fixture taskbar buttons to disappear' -TimeoutSeconds 3 -Probe {
                $current = Get-PtTaskbarSlots
                Assert-PtTaskbarForeignOrder $Fixture $marker $current
                -not @($current.Apps | Where-Object AppId -CIn @($Fixture.Apps.AppId)).Count
            } | Out-Null
        }
    } catch { $errors.Add("Taskbar cleanup conflict: $($_.Exception.Message)") }
    try { Assert-PtShortcutGuideTaskbarRestored -Snapshot $marker.Taskbar | Out-Null }
    catch { $errors.Add("Taskbar baseline comparison: $($_.Exception.Message)") }
    $Fixture.CleanupErrors = @($errors)
    if (-not $errors.Count) { $Fixture.Phase = 'Closed'; $Fixture.Pending = $null }
    Save-PtTaskbarFixture $Fixture
    if ($errors.Count) { throw "Taskbar fixture cleanup incomplete; receipt $($Fixture.ReceiptPath): $($errors -join '; ')" }
    [pscustomobject]@{ Closed = $true; DesktopRestored = $Fixture.DesktopRestored; TaskbarCompared = $true; ReceiptPath = $Fixture.ReceiptPath }
}
