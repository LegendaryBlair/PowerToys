#requires -Version 7.2
<#
.SYNOPSIS
Offline H11 contract acceptance. No UI, registry, native input, processes or network are driven.
#>
param([string]$Workspace = (Join-Path $env:TEMP "pt-taskbar-offline-$([Guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference = 'Stop'
if (('PtChord' -as [type]) -or ('PtDesktop' -as [type]) -or ('PtFg' -as [type])) {
    throw 'Run this offline suite in a fresh pwsh process.'
}
Add-Type @'
using System.Collections.Generic;
public static class PtDesktop {
    public static System.Func<int,int,bool> MoveCursor;
    public static bool SetCursorPos(int x, int y) {
        if (MoveCursor==null) throw new System.InvalidOperationException("Missing offline cursor boundary.");
        return MoveCursor(x,y);
    }
}
public static class PtFg {}
public static class PtChord {
    public static HashSet<int> Held = new HashSet<int>();
    public static List<string> Events = new List<string>();
    public static int FailDown, FailUp, Digit;
    public static short GetAsyncKeyState(int key) { return Held.Contains(key) ? unchecked((short)0x8000) : (short)0; }
    public static uint Key(ushort key, bool up) {
        Events.Add((up ? "Up:" : "Down:") + key);
        if (up) {
            if (key==FailUp) return 0;
            Held.Remove(key);
        } else {
            if (key==FailDown) return 0;
            Held.Add(key);
            if (key>=49 && key<=57) Digit=key-48;
        }
        return 1;
    }
}
'@
. "$PSScriptRoot\..\pt-taskbar-fixture.ps1"
if (Test-Path -LiteralPath $Workspace) { throw 'Use a new test workspace.' }
[IO.Directory]::CreateDirectory($Workspace) | Out-Null
$Workspace = [IO.Path]::GetFullPath($Workspace)
$results = [Collections.Generic.List[object]]::new()
function Require([bool]$Value,[string]$Message) { if (-not $Value) { throw $Message } }
function Reject([scriptblock]$Body,[string]$Pattern) {
    try { & $Body | Out-Null }
    catch { if ($_.Exception.Message -notmatch $Pattern) { throw }; return $_ }
    throw "Expected rejection: $Pattern"
}
function Check([string]$Name,[scriptblock]$Body) {
    try { & $Body | Out-Null; $results.Add([pscustomobject]@{ Name = $Name; Status = 'PASS' }) }
    catch { $results.Add([pscustomobject]@{ Name = $Name; Status = 'FAIL'; Error = $_.Exception.Message; Stack = $_.ScriptStackTrace }); throw }
    finally { ConvertTo-Json -InputObject @($results) -Depth 8 | Set-Content -LiteralPath "$Workspace\results.json" }
}
function Copy-Value($Value) { ConvertTo-Json -InputObject $Value -Depth 32 | ConvertFrom-Json }
$taskbar = [pscustomobject]@{ hwnd = 90; processId = 900; processStartTicks = 9000; className = 'Shell_TrayWnd' }
$originalForeground = [pscustomobject]@{ hwnd = 10; processId = 100; processStartTicks = 1000; className = 'UserWindow' }
$state = @{
    Order = [Collections.Generic.List[string]]::new(); Windows = @{}; Processes = @{}; Foreground = $originalForeground
    Pointer = [pscustomobject]@{ X = 80; Y = 80 }; Calls = [Collections.Generic.List[string]]::new()
    DragCount = 0; RestoreCount = 0; CloseCount = 0; CompareCount = 0; LaunchCount = 0; MouseEvents = [Collections.Generic.List[string]]::new()
    FailClose = 0; NoOpDrag = $false; NoRoute = $false; FailMove = 0; MoveCount = 0; FailMouseDown = $false
    FailMouseUp = $false; ReadHook = $null; PinsChanged = $false; MouseStart = $null
    PlacementChanged = $false; DriftMove = 0; FailDesktopAfterUp = $false; FailNextDesktop = $false
    CursorFrames = [Collections.Generic.Queue[object]]::new(); FinalMoveFrames = @(); ReleaseFrames = @()
    FrameReads = 0; DeliveryReceiptPath = $null; PreDeliveryPointer = $null
    ParkingFrames = @(); OccludedInterior = $false; PointerSetCount = 0
    LateParkingFrames = @(); LateParkingQueued = $false
    PendingLayout = $null; LayoutDelayReads = 1; LayoutReads = 0; OrderAtRelease = @()
    CloseForeground = $null; TaskbarIdentityOverride = $null; PinnedCalculator = $false
    AlwaysOverlap = $false; LayoutFaults = 0; LayoutFaultKind = 'Geometry'
}
$script:TaskbarFakeState = $state
[PtDesktop]::MoveCursor = {
    param([int]$x,[int]$y)
    $fake = $script:TaskbarFakeState
    $fake.PointerSetCount++
    $fake.Pointer = [pscustomobject]@{ X = $x; Y = $y }
    foreach ($frame in $fake.ParkingFrames) { $fake.CursorFrames.Enqueue($frame) }
    $true
}
function Reset-Fake {
    $state = $script:TaskbarFakeState
    $state.Order.Clear()
    foreach ($id in 'user.A','user.B','user.C') { $state.Order.Add("Appid: $id") }
    $state.Windows.Clear(); $state.Processes.Clear(); $state.Foreground = Copy-Value $originalForeground
    $state.Pointer = [pscustomobject]@{ X = 80; Y = 80 }; $state.Calls.Clear(); $state.MouseEvents.Clear()
    foreach ($name in 'DragCount','RestoreCount','CloseCount','CompareCount','LaunchCount','FailClose','FailMove','MoveCount','DriftMove','FrameReads','PointerSetCount') { $state[$name] = 0 }
    foreach ($name in 'NoOpDrag','NoRoute','FailMouseDown','FailMouseUp','PinsChanged','PlacementChanged','FailDesktopAfterUp','FailNextDesktop') { $state[$name] = $false }
    $state.ReadHook = $null; $state.MouseStart = $null
    $state.CursorFrames.Clear(); $state.FinalMoveFrames = @(); $state.ReleaseFrames = @()
    $state.DeliveryReceiptPath = $null; $state.PreDeliveryPointer = $null
    $state.ParkingFrames = @(); $state.OccludedInterior = $false
    $state.LateParkingFrames = @(); $state.LateParkingQueued = $false
    $state.PendingLayout = $null; $state.LayoutDelayReads = 1; $state.LayoutReads = 0; $state.OrderAtRelease = @()
    $state.CloseForeground = $null; $state.TaskbarIdentityOverride = $null
    $state.PinnedCalculator = $false
    $state.AlwaysOverlap = $false; $state.LayoutFaults = 0; $state.LayoutFaultKind = 'Geometry'
    [PtChord]::Held.Clear(); [PtChord]::Events.Clear(); [PtChord]::FailDown = 0; [PtChord]::FailUp = 0; [PtChord]::Digit = 0
}
function Get-PtTaskbarSurface {
    $state = $script:TaskbarFakeState
    if ($state.ReadHook) { & $state.ReadHook }
    if ($state.PendingLayout -and -not $state.PendingLayout.Committed -and [PtChord]::Held.Contains(1)) {
        $state.LayoutReads++
        if ($state.LayoutReads -ge $state.LayoutDelayReads) {
            Reorder-Fake $state.PendingLayout.From $state.PendingLayout.To
            $state.PendingLayout.Committed = $true
        }
    }
    $apps = @(for ($i = 0; $i -lt $state.Order.Count; $i++) {
        [pscustomobject]@{ AutomationId = $state.Order[$i]; Offscreen = $false; RuntimeId = @(42,$i)
            X = 100 + 60 * $i; Y = 1010; Width = 50; Height = 60 }
    })
    $heldFault = $state.PendingLayout -and [PtChord]::Held.Contains(1) -and $state.LayoutFaults -gt 0
    if ($state.AlwaysOverlap -or $heldFault) {
        if ($heldFault -and $state.LayoutFaultKind -eq 'Identity') { $apps[1].AutomationId = $apps[0].AutomationId }
        else { $apps[1].X = $apps[0].X }
        if ($heldFault) { $state.LayoutFaults-- }
    }
    [pscustomobject]@{ Taskbar = (Copy-Value $taskbar)
        Rect = [pscustomobject]@{ Left = 0; Top = 1000; Right = 1920; Bottom = 1080 }
        Monitor = [pscustomobject]@{ Left = 0; Top = 0; Right = 1920; Bottom = 1080 }; Apps = $apps }
}
function Get-PtShortcutGuideTaskbarSnapshot {
    $state = $script:TaskbarFakeState
    $state.Calls.Add('BaselineTaskbar')
    [pscustomobject]@{ taskbar = (Copy-Value $taskbar)
        apps = @($state.Order | ForEach-Object { [pscustomobject]@{ automationId = $_ } })
        pinDirectoryExists = $true; pinFiles = @([pscustomobject]@{ name = 'User.lnk'; sha256 = 'original' })
        taskband = [pscustomobject]@{ values = @([pscustomobject]@{ name = 'Favorites'; value = 'original' }) } }
}
function Assert-PtShortcutGuideTaskbarRestored {
    param($Snapshot)
    $state = $script:TaskbarFakeState
    $state.CompareCount++
    if (($state.Order -join '|') -cne ($Snapshot.apps.automationId -join '|')) { throw 'Taskbar app order differs from baseline.' }
    if ($state.PinsChanged) { throw 'Taskbar pin files differ from baseline.' }
}
function Get-PtTaskbarProcess { param($ProcessId) $script:TaskbarFakeState.Processes[[int]$ProcessId] }
function Get-PtNativeWindow {
    param($ProcessId,$Hwnd,[switch]$Visible)
    $state = $script:TaskbarFakeState
    foreach ($window in @($state.Windows.Values)) {
        if ((-not $ProcessId -and -not $Hwnd) -or ($ProcessId -and $window.ProcessId -eq $ProcessId) -or ($Hwnd -and $window.Hwnd -eq $Hwnd)) { $window }
    }
}
function Get-PtTaskbarPointWindow {
    param($Point)
    $state = $script:TaskbarFakeState
    if ($state.OccludedInterior) { return $originalForeground.hwnd }
    $window = $state.Windows[[long]$state.Foreground.hwnd]
    if ($window -and $Point.X -ge $window.Rect.Left -and $Point.X -lt $window.Rect.Right -and
        $Point.Y -ge $window.Rect.Top -and $Point.Y -lt $window.Rect.Bottom) { return $window.Hwnd }
    $originalForeground.hwnd
}
function Get-PtWindowIdentity {
    param($Hwnd)
    $state = $script:TaskbarFakeState
    if ($Hwnd -eq $originalForeground.hwnd) { return Copy-Value $originalForeground }
    if ($Hwnd -eq $taskbar.hwnd) {
        if ($state.TaskbarIdentityOverride) { return Copy-Value $state.TaskbarIdentityOverride }
        return Copy-Value $taskbar
    }
    $window = $state.Windows[[long]$Hwnd]
    if (-not $window) { throw 'Stale fake HWND.' }
    [pscustomobject]@{ hwnd = [long]$Hwnd; processId = $window.ProcessId
        processStartTicks = $state.Processes[[int]$window.ProcessId].ProcessStartTicks; className = $window.ClassName }
}
function Assert-PtWindowIdentity {
    param($Identity)
    if ((ConvertTo-Json (Get-PtWindowIdentity $Identity.hwnd) -Compress) -cne (ConvertTo-Json $Identity -Compress)) {
        throw 'Window identity changed.'
    }
}
function Get-PtWindowSnapshot {
    param($Hwnd)
    [pscustomobject]@{ identity = (Get-PtWindowIdentity $Hwnd); visible = $true
        placement = [pscustomobject]@{ showCmd = $(if ($script:TaskbarFakeState.PlacementChanged) { 2 } else { 1 }) } }
}
function Get-PtForegroundWindow {
    $state = $script:TaskbarFakeState
    if ([PtChord]::Digit -and -not $state.NoRoute) {
        $automationId = $state.Order[[PtChord]::Digit - 1]
        $target = @($state.Windows.Values | Where-Object { "Appid: $($_.AppId)" -ceq $automationId })
        if ($target.Count -eq 1) { $state.Foreground = Get-PtWindowIdentity $target[0].Hwnd }
        [PtChord]::Digit = 0
    }
    [pscustomobject]@{ Hwnd = $state.Foreground.hwnd; ProcessId = $state.Foreground.processId }
}
function Get-PtDesktopSnapshot {
    $state = $script:TaskbarFakeState
    if ($state.FailNextDesktop) { $state.FailNextDesktop = $false; throw 'Injected post-drag desktop observation failure.' }
    if ($state.CursorFrames.Count) { Get-PtTaskbarPointer | Out-Null }
    $state.Calls.Add('Desktop')
    Get-PtForegroundWindow | Out-Null
    [pscustomobject]@{ coordinateSpace = 'Physical'; foreground = (Copy-Value $state.Foreground)
        pointer = (Copy-Value $state.Pointer); windows = @() }
}
function Restore-PtDesktopSnapshot {
    param($Snapshot)
    $state = $script:TaskbarFakeState
    $state.RestoreCount++
    $state.Foreground = Copy-Value $Snapshot.foreground; $state.Pointer = Copy-Value $Snapshot.pointer
    Get-PtDesktopSnapshot
}
function Get-PtTaskbarPointer {
    $state = $script:TaskbarFakeState
    if ($state.DeliveryReceiptPath -and $state.LateParkingFrames.Count -and
        -not $state.LateParkingQueued -and $state.PointerSetCount -eq 0) {
        $saved = Get-Content -LiteralPath $state.DeliveryReceiptPath -Raw | ConvertFrom-Json
        if ($saved.Pending.PointerCleanup -and -not $saved.Pending.PointerCleanup.Accepted) {
            Require ($saved.Pending.Pointer.Completed -and
                ($saved.Pending.ActualOrder -join '|') -ceq ($saved.Pending.ExpectedOrder -join '|')) 'Late sequence preceded verified order'
            foreach ($frame in $state.LateParkingFrames) { $state.CursorFrames.Enqueue($frame) }
            $state.LateParkingQueued = $true
        }
    }
    if ($state.CursorFrames.Count) {
        if ($state.DeliveryReceiptPath) {
            $saved = Get-Content -LiteralPath $state.DeliveryReceiptPath -Raw | ConvertFrom-Json
            $expectedPointer = if ($saved.Pending.PointerCleanup) { $saved.Pending.PointerCleanup.Before } else { $state.PreDeliveryPointer }
            Require ($saved.Pending.Pointer.Source -and $saved.Pending.Pointer.Destination -and
                $saved.LastDesktop.pointer.X -eq $expectedPointer.X -and
                $saved.LastDesktop.pointer.Y -eq $expectedPointer.Y) 'LastDesktop advanced before endpoint/release delivery settled'
        }
        $frame = $state.CursorFrames.Dequeue()
        $state.Pointer = [pscustomobject]@{ X = $frame.X; Y = $frame.Y }
        if ($frame.LeftHeld) { [void][PtChord]::Held.Add(1) } else { [void][PtChord]::Held.Remove(1) }
        $state.FrameReads++
    }
    Copy-Value $state.Pointer
}
function Start-PtTaskbarChild {
    param($Fixture,$App)
    $state = $script:TaskbarFakeState
    $state.Calls.Add('Launch')
    $state.LaunchCount++
    $record = Read-PtTaskbarFixture -ReceiptPath $Fixture.ReceiptPath
    Require ($record.Fixture.Apps[$App.AppIndex - 1].StartRequested) 'Launch preceded persisted intent'
    Require ($record.Marker.Desktop -and $record.Marker.Taskbar) 'Launch preceded baseline'
    $processId = 1000 + $App.AppIndex
    $hwnd = [long](2000 + $App.AppIndex)
    $process = [pscustomobject]@{ ProcessId = $processId; ProcessStartTicks = [long](3000 + $App.AppIndex) }
    $state.Processes[$processId] = $process
    $state.Windows[$hwnd] = [pscustomobject]@{ Hwnd = $hwnd; ProcessId = $processId; ClassName = 'OwnedWinForms'
        Visible = $true; Minimized = $false; AppId = $App.AppId
        Rect = [pscustomobject]@{ Left = 240 + 35 * $App.AppIndex; Top = 180 + 35 * $App.AppIndex
            Right = 740 + 35 * $App.AppIndex; Bottom = 440 + 35 * $App.AppIndex } }
    $state.Order.Add("Appid: $($App.AppId)")
    $state.Foreground = Get-PtWindowIdentity $hwnd
    Write-PtTaskbarJson -Path $App.StatePath -Create -Value ([pscustomobject]@{ Version = 1; FixtureId = $Fixture.Id
        Hwnd = $hwnd; ProcessId = $processId; ProcessStartTicks = $process.ProcessStartTicks; AppId = $App.AppId })
    Copy-Value $process
}
function New-LegacyTaskbarTestRecord {
    param([string]$Workspace,[int]$Count=3)
    # Historical receipt fixtures exercise shared routing/cleanup logic without launching any app.
    $id=[Guid]::NewGuid().ToString('N')
    $desktop=Get-PtDesktopSnapshot
    $baseline=Get-PtShortcutGuideTaskbarSnapshot
    $f=[pscustomobject]@{Kind='Taskbar';Version=1;Id=$id;Workspace=$Workspace
        ReceiptPath=(Join-Path $Workspace "taskbar-$id.json");MarkerPath=(Join-Path $Workspace "taskbar-$id.marker.json")
        MarkerHash='';Phase='Creating';Pending=$null;LastOperation=$null;LastDesktop=$desktop
        DesktopRestored=$false;CleanupErrors=@()
        Apps=@(for($i=1;$i -le $Count;$i++){
            [pscustomobject]@{AppIndex=$i;AppId="PowerToys.Verification.H11.$id.$i"
                StatePath=(Join-Path $Workspace "taskbar-$id.$i.state.json")
                StartRequested=$false;Launcher=$null;Identity=$null;CloseRequested=$false;Closed=$false}
        })}
    $marker=@{Kind='Taskbar';Version=1;Id=$id;Count=$Count;Workspace=$Workspace;ReceiptPath=$f.ReceiptPath
        Desktop=$desktop;ForegroundWindow=(Get-PtWindowSnapshot $desktop.foreground.hwnd);Taskbar=$baseline}
    Assert-PtTaskbarForeignOrder $f $marker (Get-PtTaskbarSlots)
    Write-PtTaskbarJson $f.MarkerPath $marker -Create
    $f.MarkerHash=(Get-FileHash $f.MarkerPath).Hash
    Save-PtTaskbarFixture $f -Create
    foreach($app in $f.Apps){
        Get-PtTaskbarGuardedDesktop $f $marker|Out-Null
        Assert-PtTaskbarForeignOrder $f $marker (Get-PtTaskbarSlots)
        $app.StartRequested=$true
        Save-PtTaskbarFixture $f
        $app.Launcher=Start-PtTaskbarChild $f $app
        Save-PtTaskbarFixture $f
        $app.Identity=Resolve-PtTaskbarOwnedWindow $f $app
        $f.LastDesktop=Get-PtTaskbarGuardedDesktop $f $marker
        Save-PtTaskbarFixture $f
    }
    $f.Phase='Ready'
    Save-PtTaskbarFixture $f
    $f
}
function Close-PtTrackedWindow {
    param($Identity)
    $state = $script:TaskbarFakeState
    Assert-PtWindowIdentity $Identity
    $state.CloseCount++
    if ($Identity.hwnd -eq $state.FailClose) { throw 'Injected owned close failure.' }
    $window = $state.Windows[[long]$Identity.hwnd]
    if (-not ($state.PinnedCalculator -and $window.AppId -eq 'Microsoft.WindowsCalculator_8wekyb3d8bbwe!App')) {
        [void]$state.Order.Remove("Appid: $($window.AppId)")
    }
    $state.Windows.Remove([long]$Identity.hwnd); $state.Processes.Remove([int]$Identity.processId)
    if ($state.Foreground.hwnd -eq $Identity.hwnd) {
        $state.Foreground = if ($state.CloseForeground) { Copy-Value $state.CloseForeground } else { Copy-Value $originalForeground }
    }
}
function Wait-PtCondition {
    param($Probe,$Description,$TimeoutSeconds,$PollMilliseconds)
    for ($poll = 0; $poll -lt 12; $poll++) {
        $value = & $Probe
        if ($value) { return $value }
    }
    throw "Timed out waiting for $Description (offline deterministic boundary)."
}
function Start-Sleep { param($Milliseconds) }
function Reorder-Fake([int]$FromX,[int]$ToX) {
    $state = $script:TaskbarFakeState
    if ($state.NoOpDrag) { return }
    $from = [int][Math]::Round(($FromX - 125) / 60)
    $to = [int][Math]::Round(($ToX - 125) / 60)
    $item = $state.Order[$from]
    $state.Order.RemoveAt($from); $state.Order.Insert($to,$item)
}
function Invoke-PtWinApp {
    param($Arguments)
    $state = $script:TaskbarFakeState
    Require ($Arguments[0] -ceq 'drag' -and $Arguments[3] -ceq '-w' -and $Arguments[4] -ceq '90') 'Unexpected winapp boundary'
    $receipts = @(Get-ChildItem -LiteralPath $Workspace -Filter 'taskbar-*.json' | Where-Object Name -Match '^taskbar-[a-f0-9]{32}\.json$')
    $pending = @($receipts | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json } |
        Where-Object { $_.Pending.Kind -eq 'Drag' -and $_.Phase -eq 'Ready' })
    Require ($pending.Count -eq 1) 'Drag did not have exactly one persisted mutation intent'
    $state.DragCount++
    $from = $Arguments[1].Split(','); $to = $Arguments[2].Split(',')
    $state.Pointer = [pscustomobject]@{ X = [int]$to[0]; Y = [int]$to[1] }
    Reorder-Fake ([int]$from[0]) ([int]$to[0])
    'CLI accepted'
}
function Send-PtTaskbarMouse {
    param($Kind,$X,$Y)
    $state = $script:TaskbarFakeState
    $state.MouseEvents.Add($Kind)
    if ($Kind -eq 'Move') {
        $state.MoveCount++
        if ($state.FailMove -eq $state.MoveCount) { return 0 }
        $state.Pointer = [pscustomobject]@{ X = $X; Y = $Y }
        if ($state.DriftMove -eq $state.MoveCount) { $state.Pointer.X++ }
        if ($state.MoveCount -eq 61) { foreach ($frame in $state.FinalMoveFrames) { $state.CursorFrames.Enqueue($frame) } }
        if ($state.MoveCount % 61 -eq 0 -and [PtChord]::Held.Contains(1)) {
            $state.PendingLayout = @{ From = $state.MouseStart; To = $X; Committed = $false }
        }
    } elseif ($Kind -eq 'Down') {
        if ($state.FailMouseDown) { return 0 }
        [void][PtChord]::Held.Add(1); $state.MouseStart = $state.Pointer.X
    } else {
        if ($state.FailMouseUp) { return 0 }
        $state.OrderAtRelease = @($state.Order)
        [void][PtChord]::Held.Remove(1)
        if ($null -ne $state.MouseStart -and (-not $state.PendingLayout -or -not $state.PendingLayout.Committed)) {
            Reorder-Fake $state.MouseStart $state.Pointer.X
        }
        foreach ($frame in $state.ReleaseFrames) { $state.CursorFrames.Enqueue($frame) }
        if ($state.FailDesktopAfterUp) { $state.FailNextDesktop = $true }
    }
    1
}

Check 'Offline ABI and source parse; no native entry points invoked' {
    foreach ($name in 'Get-PtTaskbarPointer','Get-PtTaskbarPointWindow','Send-PtTaskbarMouse','Get-PtDesktopSnapshot',
        'Get-PtNativeWindow','Start-PtTaskbarChild','Get-PtWindowSnapshot','Close-PtTrackedWindow','Restore-PtDesktopSnapshot') {
        Require ((Get-Command $name).ScriptBlock.File -ieq $PSCommandPath) "Offline fake boundary is missing: $name"
    }
    Initialize-PtTaskbarNative
    Require ([Runtime.InteropServices.Marshal]::SizeOf([type][PtTaskbarNative+INPUT]) -eq 40) 'Incorrect INPUT size'
    Require ([Runtime.InteropServices.Marshal]::OffsetOf([type][PtTaskbarNative+INPUT], 'data').ToInt32() -eq 8) 'Incorrect union offset'
    foreach ($path in @("$PSScriptRoot\..\pt-taskbar-fixture.ps1",$PSCommandPath)) {
        $tokens = $null; $parseErrors = $null
        [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors) | Out-Null
        Require ($parseErrors.Count -eq 0) "Parse errors: $path"
    }
}
Check 'Absolute input targets exact physical pixels, including negative origins and large desktops' {
    foreach ($extent in 1920,4320,7680,16384,65536) {
        foreach ($offset in 0,1,([int][Math]::Floor($extent / 2)),($extent - 1)) {
            $origin = -1920; $coordinate = $origin + $offset
            $normalized = [PtTaskbarNative]::NormalizePixel($coordinate,$origin,$extent)
            $decoded = [int][Math]::Floor([long]$normalized * $extent / 65536) + $origin
            Require ($decoded -eq $coordinate -and $normalized -ge 0 -and $normalized -le 65535) 'Absolute encoding landed in a neighboring pixel'
        }
    }
    Reject { [PtTaskbarNative]::NormalizePixel(0,0,65537) } 'not exactly addressable' | Out-Null
}
Check 'Slots reject invalid namespace, duplicate, empty, zero, overlap and offscreen geometry' {
    Reset-Fake
    $surface = Get-PtTaskbarSurface
    $slots = ConvertTo-PtTaskbarSlots $surface
    Require ($slots.Apps.Count -eq 3 -and $slots.Apps[0].Slot -eq 1 -and $slots.CoordinateSpace -ceq 'Physical') 'Slot contract changed'
    foreach ($edit in @(
        { param($s) $s.Apps[0].AutomationId = 'PowerShell7' },
        { param($s) $s.Apps[1].AutomationId = $s.Apps[0].AutomationId },
        { param($s) $s.Apps[0].Width = 0 },
        { param($s) $s.Apps[0].Height = -1 },
        { param($s) $s.Apps[0].X = [double]::NaN },
        { param($s) $s.Apps[0].Offscreen = $true },
        { param($s) $s.Apps[1].X = $s.Apps[0].X },
        { param($s) $s.Apps[0].Y = 900 },
        { param($s) $s.Apps = @() },
        { param($s) $s.Rect.Right = 40 }
    )) {
        $bad = Copy-Value $surface; & $edit $bad
        Reject { ConvertTo-PtTaskbarSlots $bad } 'identity|geometry|slots|horizontal' | Out-Null
    }
}
Check 'Three distinct owned identities, prelaunch baselines, no-op placement and idempotent cleanup' {
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    Require ($f.Apps.Count -eq 3 -and @($f.Apps.AppId | Select-Object -Unique).Count -eq 3) 'Default app identities not distinct'
    Require ($state.Calls.IndexOf('BaselineTaskbar') -lt $state.Calls.IndexOf('Launch') -and
        $state.Calls.IndexOf('Desktop') -lt $state.Calls.IndexOf('Launch')) 'Baselines followed launch'
    $hash = (Get-FileHash $f.ReceiptPath).Hash
    $facts = Move-PtTaskbarFixtureToSlot $f -Slot 4
    Require (-not $facts.Changed -and $state.DragCount -eq 0 -and $hash -ceq (Get-FileHash $f.ReceiptPath).Hash) 'No-op mutated state'
    Remove-PtTaskbarFixture $f | Out-Null
    Require ($state.Order.Count -eq 3 -and $state.CloseCount -eq 3 -and $f.Phase -eq 'Closed') 'Cleanup left owned resources'
    $hash = (Get-FileHash $f.ReceiptPath).Hash; $restoreCount = $state.RestoreCount
    Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath | Out-Null
    Require ($state.CloseCount -eq 3 -and $state.RestoreCount -eq $restoreCount -and
        $state.CompareCount -eq 2 -and $hash -ceq (Get-FileHash $f.ReceiptPath).Hash) 'Repeated cleanup changed restored state'
}
Check 'Owned-only drag verifies actual mapping and preserves foreign relative order' {
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    $result = Move-PtTaskbarFixtureToSlot $f -AppIndex 1 -Slot 1
    Require ($result.Changed -and $result.DragMethod -ceq 'Native' -and $state.DragCount -eq 0 -and
        $state.MoveCount -eq 61 -and $state.PointerSetCount -eq 1 -and $result.PointerCleanup.Completed -and
        $f.LastDesktop.pointer.X -eq 80) 'Default Native drag or post-drag pointer cleanup was substituted'
    Require ($state.Order[0] -ceq "Appid: $($f.Apps[0].AppId)" -and
        (@($state.Order | Where-Object { $_ -like 'Appid: user.*' }) -join ',') -ceq 'Appid: user.A,Appid: user.B,Appid: user.C') 'Mapping/order wrong'
    Remove-PtTaskbarFixture $f | Out-Null
}
Check 'CLI acceptance without observed reordering fails without hidden Native retry' {
    $readSlots = ${function:Get-PtTaskbarSlots}
    function Get-PtTaskbarSlots {
        $slots = & $readSlots
        $slots.ObservedAtUtc = '2026-09-11T08:42:13.1958600Z'
        $slots
    }
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    $state.NoOpDrag = $true
    $caught = Reject { Move-PtTaskbarFixtureToSlot $f -Slot 1 -DragMethod WinApp } 'actual taskbar order'
    Require ($state.DragCount -eq 1 -and $state.MouseEvents.Count -eq 0 -and $f.Phase -eq 'Faulted') 'Unobserved drag credited or silently retried'
    $diagnostics = $caught.Exception.Data['PtTaskbarOrder']
    Require (($diagnostics.ActualOrder -join '|') -ceq ($state.Order -join '|') -and
        ($diagnostics.ActualOrder -join '|') -cne ($diagnostics.ExpectedOrder -join '|') -and
        $diagnostics.ObservedAtUtc) 'Timeout lost the actual last observed order'
    Remove-PtTaskbarFixture $f | Out-Null
    $saved = (Read-PtTaskbarFixture -ReceiptPath $f.ReceiptPath).Fixture
    Require (($saved.LastOperation.ActualOrder -join '|') -ceq ($diagnostics.ActualOrder -join '|') -and
        $saved.LastOperation.OrderObservedAtUtc) 'Cleanup erased timeout order diagnostics'
    Require ($f.LastOperation.OrderObservedAtUtc -is [DateTime] -and
        $f.LastOperation.OrderObservedAtUtc.Kind -eq [DateTimeKind]::Utc -and
        $saved.LastOperation.OrderObservedAtUtc.Ticks -eq $f.LastOperation.OrderObservedAtUtc.Ticks) 'UTC timestamp precision/type changed through receipt persistence'
}
Check 'Insertion targets the fresh destination quarter on each direction without extra drags' {
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    $left = Move-PtTaskbarFixtureToSlot $f -AppIndex 3 -Slot 1
    Require ($left.Insertion.Side -ceq 'BeforeFirst' -and $left.Insertion.AutomationId -ceq 'Appid: user.A' -and
        $left.Pointer.Source.X -eq 425 -and $left.Pointer.Destination.X -eq 99 -and
        $left.Pointer.Destination.Y -eq 1040) 'First-slot insertion was not before the first app inside the taskbar'
    $right = Move-PtTaskbarFixtureToSlot $f -AppIndex 3 -Slot 6
    Require ($right.Insertion.Side -ceq 'Right' -and $right.Insertion.AutomationId -ceq "Appid: $($f.Apps[1].AppId)" -and
        $right.Pointer.Source.X -eq 125 -and $right.Pointer.Destination.X -eq 437 -and
        $state.Order[5] -ceq "Appid: $($f.Apps[2].AppId)" -and $state.MoveCount -eq 122 -and
        $state.PointerSetCount -eq 2) 'Right insertion used a center, wrong identity or extra drag'
    Remove-PtTaskbarFixture $f | Out-Null
}
Check 'Delayed Shell layout is observed while held; unresolved order releases cleanly' {
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    $state.LayoutDelayReads = 3
    $facts = Move-PtTaskbarFixtureToSlot $f -AppIndex 3 -Slot 1
    Require ($state.LayoutReads -eq 3 -and $facts.Pointer.OrderVerifiedWhileHeld -and
        ($state.OrderAtRelease -join '|') -ceq ($facts.Order -join '|') -and
        $state.MoveCount -eq 61 -and @($state.MouseEvents | Where-Object { $_ -eq 'Down' }).Count -eq 1 -and
        @($state.MouseEvents | Where-Object { $_ -eq 'Up' }).Count -eq 1) 'Drag released early or retried instead of observing delayed layout'
    Remove-PtTaskbarFixture $f | Out-Null
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    $state.NoOpDrag = $true
    Reject { Move-PtTaskbarFixtureToSlot $f -AppIndex 3 -Slot 1 } 'requested taskbar order while owned left button is held' | Out-Null
    Require (-not $f.Pending.Pointer.OrderVerifiedWhileHeld -and [PtChord]::Held.Count -eq 0 -and
        ($f.Pending.ActualOrder -join '|') -ceq ($state.Order -join '|') -and
        $state.MoveCount -eq 61 -and $state.PointerSetCount -eq 0 -and
        @($state.MouseEvents | Where-Object { $_ -eq 'Up' }).Count -eq 1) 'Unresolved order lost diagnostics, retried or leaked the owned button'
    Remove-PtTaskbarFixture $f | Out-Null
}
Check 'Only typed transient geometry is deferred during held layout; pre-action and other errors remain strict' {
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    $state.AlwaysOverlap = $true
    $caught = Reject { Move-PtTaskbarFixtureToSlot $f -AppIndex 3 -Slot 1 } 'Taskbar slot geometry'
    Require ($caught.FullyQualifiedErrorId.Split(',')[0] -ceq 'PtTaskbarGeometryUnavailable' -and
        $state.MoveCount -eq 0) 'Pre-action geometry was not a strict typed failure'
    $state.AlwaysOverlap = $false; $state.LayoutFaults = 1
    $facts = Move-PtTaskbarFixtureToSlot $f -AppIndex 3 -Slot 1
    Require ($facts.Pointer.GeometryUnavailableCount -eq 1 -and
        $facts.Pointer.LastGeometryError.ErrorId -like 'PtTaskbarGeometryUnavailable,*' -and
        $facts.Pointer.OrderVerifiedWhileHeld -and $facts.Order.Count -eq 6 -and
        ($state.OrderAtRelease -join '|') -ceq ($facts.Order -join '|') -and $state.MoveCount -eq 61) 'Transient overlap was used as order success or caused another gesture'
    Remove-PtTaskbarFixture $f | Out-Null
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    $state.LayoutFaults = 1; $state.LayoutFaultKind = 'Identity'
    Reject { Move-PtTaskbarFixtureToSlot $f -AppIndex 3 -Slot 1 } 'duplicate taskbar app identity' | Out-Null
    Require ($f.Pending.Pointer.GeometryUnavailableCount -eq 0 -and [PtChord]::Held.Count -eq 0) 'Unrelated identity error was swallowed or leaked the held button'
    Remove-PtTaskbarFixture $f | Out-Null
}
Check 'Foreign order/set, stale geometry, user-held input and unowned slots gate mutations' {
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    Reject { Invoke-PtTaskbarSlot $f -Slot 1 } 'not exactly one owned' | Out-Null
    [void][PtChord]::Held.Add(1)
    Reject { Move-PtTaskbarFixtureToSlot $f -Slot 1 } 'not idle' | Out-Null
    Require ([PtChord]::Held.Contains(1)) 'Guard released user mouse'
    [PtChord]::Held.Clear()
    $state.Pointer.X = 777
    Reject { Move-PtTaskbarFixtureToSlot $f -Slot 1 } 'unknown foreground/pointer' | Out-Null
    Require ($state.Pointer.X -eq 777 -and $state.DragCount -eq 0) 'Mutation guard adopted a user pointer change'
    $state.Pointer.X = 80
    $state.Order.Reverse(0,3)
    Reject { Move-PtTaskbarFixtureToSlot $f -Slot 1 } 'Foreign taskbar' | Out-Null
    Require ($state.DragCount -eq 0 -and [PtChord]::Events.Count -eq 0) 'Guard issued input'
    Reject { Remove-PtTaskbarFixture $f } 'Foreign taskbar' | Out-Null
    Require ($state.CloseCount -eq 3 -and $state.Order[0] -ceq 'Appid: user.C' -and
        $state.CompareCount -eq 1) 'Cleanup overwrote foreign order or skipped mandatory baseline comparison'
    $state.Order.Reverse(0,3)
    Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath | Out-Null
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    $counter = @{ Reads = 0 }
    $state.ReadHook = { $counter.Reads++; if ($counter.Reads -eq 2) { $state.Order.Add('Appid: concurrent') } }
    Reject { Move-PtTaskbarFixtureToSlot $f -Slot 1 } 'Foreign taskbar' | Out-Null
    Require ($state.DragCount -eq 0) 'Stale mapping passed final guard'
    $state.ReadHook = $null; [void]$state.Order.Remove('Appid: concurrent')
    Remove-PtTaskbarFixture $f | Out-Null
}
Check 'Held Windows routing sends only digit; ordinary routing owns and releases its own hold' {
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    Move-PtTaskbarFixtureToSlot $f -Slot 1 | Out-Null
    [void][PtChord]::Held.Add(0x5C)
    $facts = Invoke-PtTaskbarSlot $f -Slot 1 -WhileWindowsHeld -WindowsKey 0x5C
    Require (([PtChord]::Events -join ',') -ceq 'Down:49,Up:49' -and [PtChord]::Held.Contains(0x5C) -and
        $facts.ForegroundHwnd -eq $f.Apps[0].Identity.hwnd -and $facts.WindowsHeldAfter) 'Outer Windows hold modified or wrong target'
    [PtChord]::Held.Clear(); [PtChord]::Events.Clear(); $state.Foreground = Copy-Value $originalForeground
    $facts = Invoke-PtTaskbarSlot $f -Slot 1
    Require (([PtChord]::Events -join ',') -ceq 'Down:91,Down:49,Up:49,Up:91' -and -not $facts.WindowsHeldAfter) 'Ordinary hold ownership wrong'
    Reject { Invoke-PtTaskbarSlot $f -Slot 1 } 'already foreground' | Out-Null
    Remove-PtTaskbarFixture $f | Out-Null
}
Check 'Explicit held overlay is live/current and allowed only for its routing operation' {
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    Move-PtTaskbarFixtureToSlot $f -Slot 1 | Out-Null
    $state.Processes[2100] = [pscustomobject]@{ ProcessId = 2100; ProcessStartTicks = 21000 }
    $state.Windows[[long]2200] = [pscustomobject]@{ Hwnd = 2200; ProcessId = 2100; ClassName = 'BorrowedOverlay'
        Visible = $true; Minimized = $false; AppId = 'caller-owned-overlay' }
    $overlay = Get-PtWindowIdentity 2200
    $state.Foreground = Copy-Value $overlay
    Reject { Invoke-PtTaskbarSlot $f -Slot 1 -AllowedForegroundTarget $overlay } 'requires -WhileWindowsHeld' | Out-Null
    [void][PtChord]::Held.Add(0x5B)
    $stale = Copy-Value $overlay; $stale.processStartTicks++
    Reject { Invoke-PtTaskbarSlot $f -Slot 1 -WhileWindowsHeld -AllowedForegroundTarget $stale } 'identity changed' | Out-Null
    $state.Foreground = Copy-Value $originalForeground
    Reject { Invoke-PtTaskbarSlot $f -Slot 1 -WhileWindowsHeld -AllowedForegroundTarget $overlay } 'not the current foreground' | Out-Null
    $state.Foreground = Copy-Value $overlay
    Reject { Invoke-PtTaskbarSlot $f -Slot 2 -WhileWindowsHeld -AllowedForegroundTarget $overlay } 'not exactly one owned app' | Out-Null
    Require ([PtChord]::Events.Count -eq 0) 'Invalid overlay/slot admission sent input'
    $facts = Invoke-PtTaskbarSlot $f -Slot 1 -WhileWindowsHeld -AllowedForegroundTarget $overlay
    Require (([PtChord]::Events -join ',') -ceq 'Down:49,Up:49' -and [PtChord]::Held.Contains(0x5B) -and
        $facts.PriorForegroundHwnd -eq $overlay.hwnd -and $facts.ForegroundHwnd -eq $f.Apps[0].Identity.hwnd -and
        $f.LastDesktop.foreground.hwnd -eq $f.Apps[0].Identity.hwnd) 'Overlay routing touched Windows or failed to observe the owned target'
    Reject { Invoke-PtTaskbarSlot $f -Slot 1 -WhileWindowsHeld -AllowedForegroundTarget $f.Apps[0].Identity } 'already foreground' | Out-Null
    $state.Foreground = Copy-Value $overlay
    Reject { Invoke-PtTaskbarSlot $f -Slot 1 -WhileWindowsHeld } 'unknown foreground/pointer' | Out-Null
    Require ([PtChord]::Events.Count -eq 2) 'Overlay permission leaked to another operation'
    [PtChord]::Held.Clear(); $state.Foreground = Copy-Value $originalForeground
    Remove-PtTaskbarFixture $f | Out-Null
    Require ($state.Windows.ContainsKey([long]2200) -and $state.CloseCount -eq 3) 'Cleanup closed the borrowed overlay'
}
Check 'Routing failure never forces foreground and releases only accepted owned keys' {
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    Move-PtTaskbarFixtureToSlot $f -Slot 1 | Out-Null
    $state.NoRoute = $true; $state.Foreground = Copy-Value $originalForeground
    Reject { Invoke-PtTaskbarSlot $f -Slot 1 } 'exact routed foreground' | Out-Null
    Require ([PtChord]::Held.Count -eq 0 -and $state.Foreground.hwnd -eq 10 -and $state.RestoreCount -eq 0) 'Route forced foreground or leaked keys'
    Remove-PtTaskbarFixture $f | Out-Null
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    Move-PtTaskbarFixtureToSlot $f -Slot 1 | Out-Null
    $state.Foreground = Copy-Value $originalForeground; [PtChord]::FailDown = 49
    Reject { Invoke-PtTaskbarSlot $f -Slot 1 } 'key-down 49 failed' | Out-Null
    Require (([PtChord]::Events -join ',') -ceq 'Down:91,Down:49,Up:91') 'Unaccepted digit was released'
    [PtChord]::FailDown = 0
    Remove-PtTaskbarFixture $f | Out-Null
}
Check 'Explicit Native drag uses 60 steps and releases only its accepted left-button down' {
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    $facts = Move-PtTaskbarFixtureToSlot $f -Slot 1 -DragMethod Native
    Require ($facts.DragMethod -ceq 'Native' -and $state.MoveCount -eq 61 -and $state.PointerSetCount -eq 1 -and
        @($state.MouseEvents | Where-Object { $_ -eq 'Up' }).Count -eq 1 -and [PtChord]::Held.Count -eq 0) 'Native sequence or cleanup wrong'
    Remove-PtTaskbarFixture $f | Out-Null
    $from = [pscustomobject]@{ CenterX = 125; CenterY = 1040 }; $to = [pscustomobject]@{ CenterX = 185; CenterY = 1040 }
    Reset-Fake; $state.FailMouseDown = $true
    Reject { Invoke-PtTaskbarNativeDrag $from $to } 'down failed' | Out-Null
    Require (-not ($state.MouseEvents -contains 'Up')) 'Failed mouse down released a non-owned button'
    Reset-Fake; [void][PtChord]::Held.Add(1)
    Reject { Invoke-PtTaskbarNativeDrag $from $to } 'not idle' | Out-Null
    Require ($state.MouseEvents.Count -eq 0 -and [PtChord]::Held.Contains(1)) 'User-held mouse was touched'
    Reset-Fake; $state.FailMove = 3; $state.NoOpDrag = $true
    Reject { Invoke-PtTaskbarNativeDrag $from $to } 'move 2 failed' | Out-Null
    Require ($state.MouseEvents[-1] -ceq 'Up' -and [PtChord]::Held.Count -eq 0) 'Partial drag did not release owned mouse'
    Reset-Fake; $state.FailMove = 3; $state.FailMouseUp = $true
    $caught = Reject { Invoke-PtTaskbarNativeDrag $from $to } 'move 2 failed'
    Require ($caught.Exception.Data.Contains('InputCleanupFailure')) 'Mouse cleanup error masked/lost original failure'
    [PtChord]::Held.Clear()
}
Check 'Native partial movement persists only verified pointer ownership and the primary error for cleanup' {
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    $state.FailMove = 3
    $caught = Reject { Move-PtTaskbarFixtureToSlot $f -AppIndex 3 -Slot 1 } 'move 2 failed'
    $saved = (Read-PtTaskbarFixture -ReceiptPath $f.ReceiptPath).Fixture
    Require ($saved.Pending.Error.Message -ceq $caught.Exception.Message -and
        $saved.Pending.Error.ScriptStackTrace -and $saved.Pending.Pointer.Step -eq 1 -and
        $saved.LastDesktop.pointer.X -eq $state.Pointer.X -and $saved.LastDesktop.pointer.Y -eq $state.Pointer.Y -and
        $saved.Pending.Pointer.LeftUpAccepted -and -not $saved.Pending.Pointer.Completed) 'Partial gesture lost ownership, release state or original cause'
    Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath | Out-Null
    Require ($state.CloseCount -eq 3 -and $state.Pointer.X -eq 80 -and $state.Pointer.Y -eq 80) 'Cleanup rejected its persisted partial movement'
    $saved = (Read-PtTaskbarFixture -ReceiptPath $f.ReceiptPath).Fixture
    Require ($saved.LastOperation.Error.Message -ceq $caught.Exception.Message) 'Successful cleanup erased the original gesture failure'
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    $state.FailDesktopAfterUp = $true
    $caught = Reject { Move-PtTaskbarFixtureToSlot $f -AppIndex 3 -Slot 1 } 'post-drag desktop observation failure'
    $saved = (Read-PtTaskbarFixture -ReceiptPath $f.ReceiptPath).Fixture
    Require ($saved.Pending.Pointer.Completed -and $saved.Pending.Pointer.LeftUpAccepted -and
        $saved.LastDesktop.pointer.X -eq $saved.Pending.Pointer.Destination.X -and
        $saved.LastDesktop.pointer.Y -eq $saved.Pending.Pointer.Destination.Y -and
        $saved.Pending.Error.Message -ceq $caught.Exception.Message) 'Post-drag guard failure retained the pre-drag pointer or masked the cause'
    Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath | Out-Null
    $saved = (Read-PtTaskbarFixture -ReceiptPath $f.ReceiptPath).Fixture
    Require ($saved.Phase -ceq 'Closed' -and $saved.LastOperation.Error.Message -ceq $caught.Exception.Message -and
        $state.Pointer.X -eq 80 -and $state.Pointer.Y -eq 80) 'Cleanup lost endpoint ownership or the post-drag operation cause'
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    $state.DriftMove = 3
    Reject { Move-PtTaskbarFixtureToSlot $f -AppIndex 3 -Slot 1 } 'owned physical drag pointer' | Out-Null
    $saved = (Read-PtTaskbarFixture -ReceiptPath $f.ReceiptPath).Fixture
    Require ($saved.Pending.Pointer.LastRead.X -eq $state.Pointer.X -and
        $saved.Pending.Pointer.LastRead.X -ne $saved.Pending.Pointer.LastAccepted.X -and
        $saved.LastDesktop.pointer.X -ne $state.Pointer.X -and $saved.Pending.Error.Message) 'Unexpected pointer was adopted as owned'
    $unexpected = Copy-Value $state.Pointer
    Reject { Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath } 'unknown foreground/pointer' | Out-Null
    Require ($state.RestoreCount -eq 0 -and $state.CloseCount -eq 3 -and $state.Pointer.X -eq $unexpected.X) 'Cleanup overwrote unexpected pointer movement'
}
Check 'Queued native delivery waits for endpoint and release together; off-path and timeout stay explicit' {
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    $state.DeliveryReceiptPath = $f.ReceiptPath; $state.PreDeliveryPointer = Copy-Value $f.LastDesktop.pointer
    $state.FinalMoveFrames = @(
        @{ X = 191; Y = 1040; LeftHeld = $true },
        @{ X = 153; Y = 1040; LeftHeld = $true },
        @{ X = 99; Y = 1040; LeftHeld = $true })
    $state.ReleaseFrames = @(
        @{ X = 191; Y = 1040; LeftHeld = $true },
        @{ X = 99; Y = 1040; LeftHeld = $true },
        @{ X = 99; Y = 1040; LeftHeld = $false },
        @{ X = 99; Y = 1040; LeftHeld = $false })
    $state.LateParkingFrames = @(
        @{ X = 115; Y = 1040; LeftHeld = $true },
        @{ X = 99; Y = 1040; LeftHeld = $false },
        @{ X = 99; Y = 1040; LeftHeld = $false })
    $facts = Move-PtTaskbarFixtureToSlot $f -AppIndex 3 -Slot 1
    Require ($facts.Pointer.Settled -and $facts.Pointer.Completed -and $facts.Pointer.SettleSamples -eq 11 -and
        $state.LateParkingQueued -and $state.FrameReads -eq 10 -and
        $state.MoveCount -eq 61 -and $state.PointerSetCount -eq 1 -and $facts.PointerCleanup.Completed -and
        $f.LastDesktop.pointer.X -eq 80 -and -not [PtChord]::Held.Contains(1)) 'Accepted-but-pending input was credited early or pointer cleanup was skipped'
    Remove-PtTaskbarFixture $f | Out-Null
    Require ($state.Pointer.X -eq 80 -and $state.Pointer.Y -eq 80 -and $state.CloseCount -eq 3) 'Settled asynchronous drag did not restore baseline'
    foreach ($failure in 'OffPath','Timeout') {
        Reset-Fake
        $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
        $state.DeliveryReceiptPath = $f.ReceiptPath; $state.PreDeliveryPointer = Copy-Value $f.LastDesktop.pointer
        $state.LateParkingFrames = @(@{ X = 191; Y = $(if ($failure -eq 'OffPath') { 1100 } else { 1040 }); LeftHeld = $false })
        $pattern = if ($failure -eq 'OffPath') { 'left the planned path' } else { 'native drag endpoint and button release' }
        Reject { Move-PtTaskbarFixtureToSlot $f -AppIndex 3 -Slot 1 } $pattern | Out-Null
        $saved = (Read-PtTaskbarFixture -ReceiptPath $f.ReceiptPath).Fixture
        Require ($saved.Pending.Pointer.Settled -and $saved.Pending.Pointer.Completed -and $state.LateParkingQueued -and
            $saved.Pending.Pointer.SettlementError -match $pattern -and
            $saved.LastDesktop.pointer.X -eq 99 -and $saved.LastDesktop.pointer.Y -eq 1040 -and
            -not $saved.Pending.PointerCleanup.Accepted -and $state.PointerSetCount -eq 0) 'Late/off-path cursor changed the endpoint baseline or started parking'
        $actual = Copy-Value $state.Pointer
        Reject { Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath } 'unknown foreground/pointer' | Out-Null
        Require ($state.RestoreCount -eq 0 -and $state.CloseCount -eq 3 -and
            $state.Pointer.X -eq $actual.X -and $state.Pointer.Y -eq $actual.Y) 'Cleanup overwrote an unsettled/off-path cursor'
    }
    Check 'Verified drops leave taskbar hover safely, including queued pointer cleanup and owned-interior fallback' {
        Reset-Fake
        $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
        $state.DeliveryReceiptPath = $f.ReceiptPath; $state.PreDeliveryPointer = Copy-Value $f.LastDesktop.pointer
        $state.ParkingFrames = @(
            @{ X = 125; Y = 1040; LeftHeld = $false },
            @{ X = 1765; Y = 2112; LeftHeld = $false },
            @{ X = 80; Y = 80; LeftHeld = $true },
            @{ X = 80; Y = 80; LeftHeld = $false },
            @{ X = 80; Y = 80; LeftHeld = $false })
        $facts = Move-PtTaskbarFixtureToSlot $f -AppIndex 3 -Slot 1
        Require ($facts.PointerCleanup.Kind -ceq 'PreDrag' -and $facts.PointerCleanup.Completed -and
            $facts.PointerCleanup.Actual.X -eq 80 -and $state.FrameReads -eq 5 -and
            $state.MoveCount -eq 61 -and $state.PointerSetCount -eq 1 -and
            @($state.MouseEvents | Where-Object { $_ -eq 'Down' }).Count -eq 1 -and
            @($state.MouseEvents | Where-Object { $_ -eq 'Up' }).Count -eq 1) 'Pointer cleanup clicked, retried input or failed to wait for delivery'
        Remove-PtTaskbarFixture $f | Out-Null
        Reset-Fake
        $state.Pointer = [pscustomobject]@{ X = 125; Y = 1040 }
        $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
        $facts = Move-PtTaskbarFixtureToSlot $f -AppIndex 3 -Slot 1
        Require ($facts.PointerCleanup.Kind -ceq 'OwnedInterior' -and
            $facts.PointerCleanup.Window.hwnd -eq $f.Apps[2].Identity.hwnd -and
            $facts.PointerCleanup.Actual.Y -lt 1000 -and
            $f.LastDesktop.pointer.Y -eq $facts.PointerCleanup.Actual.Y) 'Taskbar-origin pointer was left hovering instead of parked in an owned interior'
        Remove-PtTaskbarFixture $f | Out-Null
        Require ($state.Pointer.X -eq 125 -and $state.Pointer.Y -eq 1040) 'Final cleanup lost the original taskbar pointer baseline'
        Reset-Fake
        $state.Pointer = [pscustomobject]@{ X = 125; Y = 1040 }
        $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
        $state.OccludedInterior = $true
        Reject { Move-PtTaskbarFixtureToSlot $f -AppIndex 3 -Slot 1 } 'interior is occluded' | Out-Null
        Require ($state.MoveCount -eq 61) 'Occluded owned interior still received pointer input'
        Remove-PtTaskbarFixture $f | Out-Null
        Reset-Fake
        $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
        $state.ParkingFrames = @(@{ X = 777; Y = 777; LeftHeld = $false })
        Reject { Move-PtTaskbarFixtureToSlot $f -AppIndex 3 -Slot 1 } 'Timed out waiting for post-drag pointer cleanup' | Out-Null
        Require ($state.PointerSetCount -eq 1 -and -not $f.Pending.PointerCleanup.Completed -and
            $f.LastDesktop.pointer.X -ne 777) 'Unsettled pointer was adopted or commanded again'
        Reject { Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath } 'unknown foreground/pointer' | Out-Null
        Require ($state.RestoreCount -eq 0 -and $state.CloseCount -eq 3 -and
            $state.Pointer.X -eq 777 -and $state.Pointer.Y -eq 777) 'Unexpected pointer movement was overwritten during cleanup'
    }
}
Check 'Marker, receipt and child ownership checks reject tampering before mutation' {
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    $changed = Copy-Value $f; $changed.Apps[0].Identity.hwnd = 999
    Reject { Remove-PtTaskbarFixture $changed } 'stale or changed' | Out-Null
    $changed = Copy-Value $f; $changed.Apps[0].AppId = $changed.Apps[1].AppId
    Write-PtTaskbarJson $f.ReceiptPath $changed
    Reject { Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath } 'app ownership record' | Out-Null
    Write-PtTaskbarJson $f.ReceiptPath $f
    $marker = Get-Content -LiteralPath $f.MarkerPath -Raw
    [IO.File]::AppendAllText($f.MarkerPath,' ')
    Reject { Move-PtTaskbarFixtureToSlot $f -Slot 1 } 'marker hash' | Out-Null
    [IO.File]::WriteAllText($f.MarkerPath,$marker,[Text.UTF8Encoding]::new($false))
    $child = Get-Content -LiteralPath $f.Apps[0].StatePath -Raw | ConvertFrom-Json
    $bad = Copy-Value $child; $bad.AppId = 'foreign'
    Write-PtTaskbarJson $f.Apps[0].StatePath $bad
    Reject { Invoke-PtTaskbarSlot $f -Slot 4 } 'child state' | Out-Null
    Write-PtTaskbarJson $f.Apps[0].StatePath $child
    Require ($state.CloseCount -eq 0 -and $state.DragCount -eq 0 -and [PtChord]::Events.Count -eq 0) 'Invalid ownership allowed a mutation'
    Remove-PtTaskbarFixture $f | Out-Null
}
Check 'Duplicate owned HWND and recycled PID refuse action; cleanup still tries other resources' {
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    $extra = Copy-Value $state.Windows[[long]2001]; $extra.Hwnd = 9999
    $state.Windows[[long]9999] = $extra
    Reject { Move-PtTaskbarFixtureToSlot $f -Slot 1 } 'exactly one owned fixture window' | Out-Null
    $state.Processes[1002].ProcessStartTicks++
    Reject { Remove-PtTaskbarFixture $f } 'exactly one owned|PID was reused' | Out-Null
    Require ($state.Windows.ContainsKey([long]2001) -and $state.Windows.ContainsKey([long]2002) -and
        -not $state.Windows.ContainsKey([long]2003) -and $state.CompareCount -eq 1) 'Partial cleanup closed unknown or skipped safe resources'
    $state.Windows.Remove([long]9999); $state.Processes[1002].ProcessStartTicks--
    Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath | Out-Null
}
Check 'Partial close retries persist progress; pin/desktop conflicts survive with final comparison' {
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    $state.FailClose = 2002
    Reject { Remove-PtTaskbarFixture $f } 'owned close failure' | Out-Null
    Require ($state.CloseCount -eq 3 -and $f.Apps[0].Closed -and -not $f.Apps[1].Closed -and $f.Apps[2].Closed) 'Cleanup did not attempt all apps'
    $state.FailClose = 0
    Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath | Out-Null
    Require ($state.CloseCount -eq 4 -and $state.CompareCount -eq 2) 'Retry repeated completed closes or skipped final comparison'
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    $state.Pointer.X = 999; $state.PinsChanged = $true
    Reject { Remove-PtTaskbarFixture $f } 'Desktop cleanup conflict.*pin files' | Out-Null
    Require ($state.CloseCount -eq 3 -and $state.RestoreCount -eq 0 -and $state.Pointer.X -eq 999) 'Conflict overwrote user desktop'
    $state.Pointer.X = 80; $state.PinsChanged = $false
    Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath | Out-Null
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    $state.PlacementChanged = $true
    Reject { Remove-PtTaskbarFixture $f } 'placement/visibility changed' | Out-Null
    Require ($state.PlacementChanged -and $state.RestoreCount -eq 0 -and $state.CloseCount -eq 3) 'User window placement was overwritten'
    $state.PlacementChanged = $false
    Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath | Out-Null
}
Check 'Cleanup admits only the live immutable taskbar foreground and preserves pointer guards' {
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    Move-PtTaskbarFixtureToSlot $f -Slot 1 | Out-Null
    $state.CloseForeground = Copy-Value $taskbar
    $result = Remove-PtTaskbarFixture $f
    Require ($result.Closed -and $result.DesktopRestored -and $result.TaskbarCompared -and
        $state.CloseCount -eq 3 -and $state.Foreground.hwnd -eq $originalForeground.hwnd) 'Exact taskbar foreground after owned closes blocked restoration'
    $state.Foreground = Copy-Value $taskbar
    $marker = (Read-PtTaskbarFixture -Fixture $f).Marker
    Reject { Get-PtTaskbarGuardedDesktop $f $marker } 'unknown foreground/pointer' | Out-Null
    $f.Phase = 'Cleaning'; $f.DesktopRestored = $false
    Save-PtTaskbarFixture $f
    Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath | Out-Null
    Require ($state.CloseCount -eq 3 -and $state.Foreground.hwnd -eq $originalForeground.hwnd) 'Cleanup reload closed another window or failed to restore'
    foreach ($conflict in 'OtherShell','ReusedTaskbar','Pointer') {
        Reset-Fake
        $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
        $state.CloseForeground = Copy-Value $taskbar
        if ($conflict -eq 'OtherShell') { $state.CloseForeground.hwnd = 91 }
        elseif ($conflict -eq 'ReusedTaskbar') {
            $state.TaskbarIdentityOverride = Copy-Value $taskbar
            $state.TaskbarIdentityOverride.processStartTicks++
            $state.CloseForeground = Copy-Value $state.TaskbarIdentityOverride
        } else { $state.Pointer.X = 777 }
        Reject { Remove-PtTaskbarFixture $f } 'unknown foreground/pointer|identity changed' | Out-Null
        Require ($state.CloseCount -eq 3 -and $state.RestoreCount -eq 0 -and $state.CompareCount -eq 1 -and
            $state.Foreground.hwnd -eq $state.CloseForeground.hwnd -and
            ($conflict -ne 'Pointer' -or $state.Pointer.X -eq 777)) 'Cleanup broadened Shell permission or overwrote an unrelated change'
    }
}
Check 'Untouched fixture cleanup does not restore an already matching desktop' {
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace -Count 1
    $state.Foreground = Copy-Value $originalForeground
    Remove-PtTaskbarFixture $f | Out-Null
    Require ($state.RestoreCount -eq 0 -and $state.Order.Count -eq 3 -and [PtChord]::Events.Count -eq 0) 'Unmodified desktop or user inputs changed'
}
Check 'Native 3/2/1 reorder and owned foreground close restore baseline, including Cleaning receipt reload' {
    foreach ($reload in @($false,$true)) {
        Reset-Fake
        foreach ($id in 'user.D','user.E','user.F','user.G','user.H','owned.Settings') { $state.Order.Add("Appid: $id") }
        $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
        foreach ($index in 3,2,1) {
            Move-PtTaskbarFixtureToSlot $f -AppIndex $index -Slot 1 | Out-Null
        }
        Require (($state.Order[0..2] -join '|') -ceq (@($f.Apps | ForEach-Object { "Appid: $($_.AppId)" }) -join '|')) 'Three first slots did not match observed app order'
        $lastDesktop = Copy-Value $f.LastDesktop
        Require ($lastDesktop.foreground.hwnd -eq $f.Apps[2].Identity.hwnd -and
            $f.LastOperation.PointerCleanup.Completed -and $lastDesktop.pointer.X -eq 80) 'Regression did not retain owned foreground and the restored pre-drag pointer'
        if ($reload) {
            foreach ($app in $f.Apps) {
                Close-PtTrackedWindow $app.Identity
                $app.CloseRequested = $true; $app.Closed = $true
            }
            $f.Phase = 'Cleaning'
            Save-PtTaskbarFixture $f
            Require ($state.Foreground.hwnd -eq $originalForeground.hwnd -and
                $state.Pointer.X -eq $lastDesktop.pointer.X -and $state.Pointer.Y -eq $lastDesktop.pointer.Y) 'Close did not reproduce the original-foreground/unchanged-pointer transition'
        }
        $result = Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath
        Require ($result.Closed -and $result.DesktopRestored -and $state.CloseCount -eq 3 -and
            $state.Order.Count -eq 9 -and $state.Pointer.X -eq 80 -and $state.Pointer.Y -eq 80 -and
            $state.Foreground.hwnd -eq $originalForeground.hwnd) 'Self-induced close transition blocked restoration'
    }
}
Check 'Cleaning reload rejects genuine foreground/pointer changes and records which guard failed' {
    foreach ($change in 'Foreground','Pointer') {
        Reset-Fake
        $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
        Move-PtTaskbarFixtureToSlot $f -AppIndex 3 -Slot 1 | Out-Null
        foreach ($app in $f.Apps) {
            Close-PtTrackedWindow $app.Identity
            $app.CloseRequested = $true; $app.Closed = $true
        }
        $f.Phase = 'Cleaning'
        Save-PtTaskbarFixture $f
        if ($change -eq 'Foreground') {
            $state.Foreground = [pscustomobject]@{ hwnd = 999; processId = 998; processStartTicks = 997; className = 'ForeignWindow' }
        } else { $state.Pointer.X++ }
        $before = Get-PtDesktopSnapshot
        $record = Read-PtTaskbarFixture -ReceiptPath $f.ReceiptPath
        $caught = Reject { Get-PtTaskbarGuardedDesktop $record.Fixture $record.Marker } 'unknown foreground/pointer'
        $facts = $caught.Exception.Data['PtTaskbarDesktopConflict']
        Require ($facts.ForegroundMatched -eq ($change -eq 'Pointer') -and
            $facts.PointerMatched -eq ($change -eq 'Foreground')) 'Conflict facts did not identify the failed guard'
        Reject { Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath } 'ActualForeground=.*ActualPointer=.*ExpectedPointer=' | Out-Null
        Require ($state.RestoreCount -eq 0 -and $state.CloseCount -eq 3 -and $state.CompareCount -eq 1 -and
            (ConvertTo-Json (Get-PtDesktopSnapshot) -Depth 12 -Compress) -ceq
            (ConvertTo-Json $before -Depth 12 -Compress)) 'Cleanup adopted or overwrote a concurrent desktop change'
    }
}
Check 'Interrupted creation and close progress can reload without guessing an unknown process' {
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    $f.Phase = 'Creating'; $f.Apps[1].Identity = $null
    Save-PtTaskbarFixture $f
    $result = Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath
    Require ($result.Closed -and $state.CloseCount -eq 3) 'Persisted child state did not recover unresolved HWND'
    Reset-Fake
    $f = New-LegacyTaskbarTestRecord -Workspace $Workspace
    $f.Apps[0].Identity = $null; $f.Apps[0].Launcher = $null; $f.Phase = 'Creating'
    Save-PtTaskbarFixture $f
    Reject { Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath } 'no persisted process identity' | Out-Null
    Require ($state.CloseCount -eq 2 -and $state.Windows.ContainsKey([long]2001) -and $state.CompareCount -eq 1) 'Unknown launcher was guessed or other cleanup skipped'
    # The fake resource is retained as conflict evidence, not closed by a fabricated identity.
}
function Get-PtTaskbarCalculator {
    [pscustomobject]@{AppId='Microsoft.WindowsCalculator_8wekyb3d8bbwe!App'
        ExecutablePath='C:\SyntheticCalculator\CalculatorApp.exe';PackageFullName='SyntheticCalculator'}
}
function Get-PtTaskbarCalculatorWindows {
    param($Calculator)
    foreach($window in @($script:TaskbarFakeState.Windows.Values|Where-Object AppId -eq $Calculator.AppId)){
        [pscustomobject]@{Identity=(Get-PtWindowIdentity $window.Hwnd);ContentProcess=$window.ContentProcess}
    }
}
function Start-PtTaskbarCalculator {
    param($Calculator)
    $state=$script:TaskbarFakeState
    $state.Calls.Add('CalculatorLaunch');$state.LaunchCount++
    $process=[pscustomobject]@{ProcessId=1001;ProcessStartTicks=[DateTime]::UtcNow.Ticks}
    $state.Processes[1001]=$process
    $state.Windows[[long]2001]=[pscustomobject]@{Hwnd=2001L;ProcessId=1001;ClassName='ApplicationFrameWindow'
        Visible=$true;Minimized=$false;AppId=$Calculator.AppId
        ContentProcess=[pscustomobject]@{ProcessId=3001;ProcessStartTicks=$process.ProcessStartTicks;Path=$Calculator.ExecutablePath}
        Rect=[pscustomobject]@{Left=240;Top=180;Right=740;Bottom=440}}
    if("Appid: $($Calculator.AppId)" -cnotin $state.Order){$state.Order.Add("Appid: $($Calculator.AppId)")}
    $state.Foreground=Get-PtWindowIdentity 2001
}
Check 'Default fixture launches only Calculator; count-three callers cannot create dummy apps' {
    Reset-Fake
    Reject {New-PtTaskbarFixture -Workspace $Workspace -Count 3} 'range|greater than|ValidateRange'|Out-Null
    Require ($state.LaunchCount -eq 0) 'Invalid count launched an app'
    $f=New-PtTaskbarFixture -Workspace $Workspace
    Require ($f.Version -eq 2 -and $f.Apps.Count -eq 1 -and $f.Apps[0].AppId -eq 'Microsoft.WindowsCalculator_8wekyb3d8bbwe!App') 'Default fixture is not Calculator'
    Require ($state.LaunchCount -eq 1 -and $state.Calls.IndexOf('BaselineTaskbar') -lt $state.Calls.IndexOf('CalculatorLaunch')) 'Calculator launch preceded baseline'
    Move-PtTaskbarFixtureToSlot $f -Slot 1|Out-Null
    $state.Foreground=Copy-Value $originalForeground
    $route=Invoke-PtTaskbarSlot $f -Slot 1
    Require ($route.ForegroundHwnd -eq 2001 -and -not $route.WindowsHeldAfter) 'Calculator slot did not route'
    $cleanup=Remove-PtTaskbarFixture $f
    Require ($cleanup.Closed -and $cleanup.TaskbarCompared -and $state.CloseCount -eq 1 -and $state.Order.Count -eq 3) 'Calculator was not restored'
    Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath|Out-Null
    Require ($state.CloseCount -eq 1) 'Repeated cleanup closed another window'
}
Check 'Already-open Calculator is never adopted, relaunched or closed' {
    Reset-Fake
    Start-PtTaskbarCalculator (Get-PtTaskbarCalculator)
    Reject {New-PtTaskbarFixture -Workspace $Workspace} 'already open'|Out-Null
    Require ($state.LaunchCount -eq 1 -and $state.CloseCount -eq 0 -and $state.Windows.Count -eq 1) 'Existing Calculator was mutated'
}
Check 'Pinned Calculator returns to its original slot and retains the pin after normal close' {
    Reset-Fake
    $state.PinnedCalculator=$true
    $state.Order.Insert(2,'Appid: Microsoft.WindowsCalculator_8wekyb3d8bbwe!App')
    $f=New-PtTaskbarFixture -Workspace $Workspace
    Require ((Read-PtTaskbarFixture $f).Marker.OriginalSlot -eq 3) 'Pinned position not captured'
    Move-PtTaskbarFixtureToSlot $f -Slot 1|Out-Null
    Require ($state.Order[0] -match 'WindowsCalculator') 'Calculator not first'
    $cleanup=Remove-PtTaskbarFixture $f
    Require ($cleanup.Closed -and $state.Order[2] -match 'WindowsCalculator' -and $state.Order.Count -eq 4 -and $state.CloseCount -eq 1) 'Pinned Calculator order or lifetime not restored'
}
Check 'Calculator creation waits through a transient foreign-order observation and retains its exact diff' {
    Reset-Fake
    $state.ReadHook={
        $state=$script:TaskbarFakeState
        if($state.LaunchCount -eq 1){
            if(-not $state.ContainsKey('AdmissionReads')){$state.AdmissionReads=0}
            $state.AdmissionReads++
            if($state.AdmissionReads -eq 1){$state.Order.Insert(0,'Appid: transient')}
            if($state.AdmissionReads -eq 2){[void]$state.Order.Remove('Appid: transient')}
        }
    }
    $f=New-PtTaskbarFixture -Workspace $Workspace
    Require ($f.Phase -eq 'Ready' -and $f.AdmissionConflict.Added -contains 'Appid: transient' -and $state.LaunchCount -eq 1) 'Transient mapping was either lost or triggered another launch'
    $state.ReadHook=$null
    Remove-PtTaskbarFixture $f|Out-Null
    $state.Remove('AdmissionReads')
}
Check 'Persistent foreign-order conflict never permits movement and remains actionable in the receipt' {
    Reset-Fake
    $state.ReadHook={if($script:TaskbarFakeState.LaunchCount -and 'Appid: foreign' -cnotin $script:TaskbarFakeState.Order){$script:TaskbarFakeState.Order.Add('Appid: foreign')}}
    $error=Reject {New-PtTaskbarFixture -Workspace $Workspace} 'stable foreign order'
    $state.ReadHook=$null
    $f=(Read-PtTaskbarFixture -ReceiptPath $error.Exception.Data['FixtureReceipt']).Fixture
    Require ($f.AdmissionConflict.Added -contains 'Appid: foreign' -and $state.MoveCount -eq 0 -and $state.CloseCount -eq 1) 'Conflict lost evidence or moved user apps'
    [void]$state.Order.Remove('Appid: foreign')
    Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath|Out-Null
}
Check 'Calculator shared content and root identities are both checked before routing or closing' {
    Reset-Fake
    $f=New-PtTaskbarFixture -Workspace $Workspace
    $state.Windows[[long]2001].ContentProcess.ProcessStartTicks++
    Reject {Remove-PtTaskbarFixture $f} 'Calculator identity changed'|Out-Null
    Require ($state.CloseCount -eq 0) 'Replaced Calculator content was closed'
    $state.Windows[[long]2001].ContentProcess.ProcessStartTicks--
    Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath|Out-Null
}
Check 'A reused background Calculator process is allowed only for a newly created frame' {
    Reset-Fake
    $launchCalculator=${function:Start-PtTaskbarCalculator}
    function Start-PtTaskbarCalculator {
        param($Calculator)
        & $launchCalculator $Calculator
        $script:TaskbarFakeState.Windows[[long]2001].ContentProcess.ProcessStartTicks=100L
    }
    try{
        $f=New-PtTaskbarFixture -Workspace $Workspace
        Require ($f.Apps[0].ContentProcess.ProcessStartTicks -eq 100) 'Background content process was mistaken for a user-owned window'
        Remove-PtTaskbarFixture $f|Out-Null
    }finally{Set-Item Function:\Start-PtTaskbarCalculator $launchCalculator}
}
Check 'An unobservable existing Calculator frame is not silently reported closed' {
    Reset-Fake
    $f=New-PtTaskbarFixture -Workspace $Workspace
    $readCalculator=${function:Get-PtTaskbarCalculatorWindows}
    function Get-PtTaskbarCalculatorWindows {param($Calculator)}
    try{
        Reject {Remove-PtTaskbarFixture $f} 'window still exists'|Out-Null
        Require ($state.CloseCount -eq 0 -and -not $f.Apps[0].Closed) 'Missing content observation became a successful close'
    }finally{Set-Item Function:\Get-PtTaskbarCalculatorWindows $readCalculator}
    Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath|Out-Null
}
Check 'Failed original pinned-slot restoration preserves Calculator and permits a scoped retry' {
    Reset-Fake
    $state.PinnedCalculator=$true
    $state.Order.Insert(2,'Appid: Microsoft.WindowsCalculator_8wekyb3d8bbwe!App')
    $f=New-PtTaskbarFixture -Workspace $Workspace
    Move-PtTaskbarFixtureToSlot $f -Slot 1|Out-Null
    $state.NoOpDrag=$true
    Reject {Remove-PtTaskbarFixture $f} 'Calculator order restoration'|Out-Null
    Require ($state.CloseCount -eq 0 -and $state.Windows.ContainsKey([long]2001)) 'Order restoration failure abandoned a moved pin'
    $state.NoOpDrag=$false
    $cleanup=Remove-PtTaskbarFixture -ReceiptPath $f.ReceiptPath
    Require ($cleanup.Closed -and $state.Order[2] -match 'WindowsCalculator' -and $state.CloseCount -eq 1) 'Pinned-slot retry failed to restore and close'
}
ConvertTo-Json -InputObject @(
    Get-FileHash -LiteralPath "$PSScriptRoot\..\pt-taskbar-fixture.ps1",$PSCommandPath
    Get-FileHash -LiteralPath "$PSScriptRoot\..\..\references\taskbar-fixtures.md"
) -Depth 4 | Set-Content -LiteralPath "$Workspace\source-hashes.json"
"PASS: $($results.Count) offline H11 contract groups. Results: $Workspace\results.json"
