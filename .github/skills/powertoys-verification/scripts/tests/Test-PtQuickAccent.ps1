# Copyright (c) Microsoft Corporation.
# The Microsoft Corporation licenses this file to you under the MIT license.
# See the LICENSE file in the project root for more information.

param([switch]$Interactive, [long]$SurfaceWindowHandle = 0)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\pt-quick-accent.ps1"
$path = Join-Path ([IO.Path]::GetTempPath()) "pt-quick-accent-$([guid]::NewGuid().ToString('N')).json"
try {
    $absent = New-PtQuickAccentFileBaseline -Path $path
    [IO.File]::WriteAllText($path, '{"owned":true}')
    $owned = Get-PtQuickAccentFileHash -Path $path
    Restore-PtQuickAccentFileBaseline -Baseline $absent -ExpectedHash $owned | Out-Null
    if (Test-Path $path) { throw 'Absent baseline was not restored.' }

    $bytes = [byte[]]@(0, 255, 13, 10, 128)
    [IO.File]::WriteAllBytes($path, $bytes)
    $existing = New-PtQuickAccentFileBaseline -Path $path
    [IO.File]::WriteAllText($path, 'owned')
    $owned = Get-PtQuickAccentFileHash -Path $path
    [IO.File]::WriteAllText($path, 'external')
    $conflict = $false
    try { Restore-PtQuickAccentFileBaseline -Baseline $existing -ExpectedHash $owned }
    catch { $conflict = $_ -match 'Restoration conflict' }
    if (-not $conflict -or [IO.File]::ReadAllText($path) -ne 'external') {
        throw 'External change was not preserved.'
    }
    Restore-PtQuickAccentFileBaseline -Baseline $existing -ExpectedHash (Get-PtQuickAccentFileHash -Path $path) | Out-Null
    if (@(Compare-Object $bytes ([IO.File]::ReadAllBytes($path))).Count) { throw 'Bytes changed.' }

    $rejected = $false
    try { Invoke-PtQuickAccentGesture -WindowHandle -1 -KeyCode 0x41 -Observe { throw 'Must not run' } }
    catch { $rejected = $_ -match 'exact owned fixture HWND' }
    if (-not $rejected) { throw 'Invalid foreground was not rejected before input.' }
    'PASS: absent/existing byte-exact restoration, conflict preservation, foreground rejection.'
}
finally {
    if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) }
}

if ($Interactive) {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class PtQuickAccentTestWindow
{
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr window);
}
'@
    $originalForeground = [PtQuickAccentInput]::GetForegroundWindow()
    $identity = Join-Path ([IO.Path]::GetTempPath()) "pt-quick-accent-fixture-$([guid]::NewGuid().ToString('N')).json"
    $fixture = [IO.Path]::GetFullPath("$PSScriptRoot\..\fixtures\quick-accent-text.ps1")
    $hostPath = (Get-Process -Id $PID).Path
    $process = $null
    try {
        $process = Start-Process -FilePath $hostPath -PassThru -ArgumentList @(
            '-NoProfile', '-STA', '-File', "`"$fixture`"", '-OutputFile', "`"$identity`"",
            '-Title', '"Quick Accent helper check"')
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        while (-not (Test-Path -LiteralPath $identity) -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 100
        }
        $windows = @(Get-Content -LiteralPath $identity -Raw | ConvertFrom-Json)
        if ($windows.Count -ne 2 -or @($windows | Where-Object ProcessId -ne $process.Id).Count) {
            throw 'Owned fixture identity mismatch.'
        }
        $first = [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$windows[0].Hwnd)
        $edit = $first.FindFirst([Windows.Automation.TreeScope]::Descendants,
            [Windows.Automation.PropertyCondition]::new(
                [Windows.Automation.AutomationElement]::AutomationIdProperty, 'OwnedText1'))
        if (-not $edit) { throw 'Owned fixture edit is missing.' }
        [void][PtQuickAccentTestWindow]::SetForegroundWindow([IntPtr]$windows[0].Hwnd)
        $edit.SetFocus()
        Start-Sleep -Milliseconds 150
        $caught = $false
        try {
            Invoke-PtQuickAccentGesture -WindowHandle $windows[0].Hwnd -KeyCode 0x87 -DelayMs 1 -Observe {
                throw 'Synthetic held-input callback failure'
            }
        }

        catch { $caught = $_ -match 'Synthetic held-input callback failure' }
        if (-not $caught -or ([PtQuickAccentInput]::GetAsyncKeyState(0x87) -band 0x8000)) {
            throw 'F24 callback failure did not release the owned key.'
        }
        $rejected = $false
        try {
            Invoke-PtQuickAccentCharacterDialog -WindowHandle $windows[0].Hwnd `
                -ManageButtonName 'No such button' -Action { throw 'Must not run' }
        }
        catch { $rejected = $_ -match 'unique visible enabled' }
        if (-not $rejected) { throw 'Missing Manage button was not safely rejected.' }
        'PASS: owned fixture identity, callback-failure key release, wrong-surface dialog rejection.'
    }
    finally {
        try {
            if (Test-Path -LiteralPath $identity) {
                foreach ($window in (Get-Content -LiteralPath $identity -Raw | ConvertFrom-Json)) {
                    if ($window.ProcessId -eq $process.Id -and
                        [PtQuickAccentTestWindow]::IsWindow([IntPtr]$window.Hwnd)) {
                        $root = [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$window.Hwnd)
                        $root.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern).Close()
                        $deadline = [DateTime]::UtcNow.AddSeconds(5)
                        while ([PtQuickAccentTestWindow]::IsWindow([IntPtr]$window.Hwnd) -and
                            [DateTime]::UtcNow -lt $deadline) {
                            Start-Sleep -Milliseconds 100
                        }
                        if ([PtQuickAccentTestWindow]::IsWindow([IntPtr]$window.Hwnd)) {
                            throw 'Owned fixture window did not close.'
                        }
                    }
                }
                if (-not $process.WaitForExit(10000)) { throw 'Owned fixture did not exit after both windows closed.' }
                [IO.File]::Delete($identity)
            }
        }
        finally {
            if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id -ErrorAction Stop }
            [void][PtQuickAccentTestWindow]::SetForegroundWindow($originalForeground)
            Start-Sleep -Milliseconds 150
            if ([PtQuickAccentInput]::GetForegroundWindow() -ne $originalForeground) {
                throw 'Original foreground did not restore after the helper check.'
            }
        }
    }
}

if ($SurfaceWindowHandle) {
    $surface = Get-PtQuickAccentSurfaceState -WindowHandle $SurfaceWindowHandle
    $wrongOwner = [pscustomobject]@{
        WindowHandle = $surface.WindowHandle
        ProcessId = $surface.ProcessId + 1
        Entries = $surface.Entries
    }
    $rejected = $false
    try { Restore-PtQuickAccentSurfaceState -Baseline $wrongOwner }
    catch { $rejected = $_ -match 'Surface owner changed' }
    if (-not $rejected) { throw 'Changed surface owner was not rejected.' }
    try {
        $root = [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$SurfaceWindowHandle)
        $entry = @($surface.Entries | Where-Object { $_.Expansion -in @('Expanded', 'Collapsed') }) | Select-Object -First 1
        if (-not $entry -or -not $entry.AutomationId) { throw 'A unique expander with AutomationId is required for the surface check.' }
        $element = $root.FindFirst([Windows.Automation.TreeScope]::Descendants,
            [Windows.Automation.PropertyCondition]::new(
                [Windows.Automation.AutomationElement]::AutomationIdProperty, $entry.AutomationId))
        $pattern = $element.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern)
        if ($entry.Expansion -eq 'Expanded') { $pattern.Collapse() } else { $pattern.Expand() }
        if ($pattern.Current.ExpandCollapseState.ToString() -eq $entry.Expansion) { throw 'Expander did not change for the restoration check.' }
        $scroller = @($surface.Entries | Where-Object { $null -ne $_.Vertical -and $_.Vertical -ge 0 -and $_.AutomationId }) | Select-Object -First 1
        if (-not $scroller) { throw 'An actual scrollable surface is required for the restoration check.' }
        $element = $root.FindFirst([Windows.Automation.TreeScope]::Descendants,
            [Windows.Automation.PropertyCondition]::new(
                [Windows.Automation.AutomationElement]::AutomationIdProperty, $scroller.AutomationId))
        $pattern = $element.GetCurrentPattern([Windows.Automation.ScrollPattern]::Pattern)
        $target = if ($scroller.Vertical -lt 50) { 75 } else { 25 }
        $pattern.SetScrollPercent(-1, $target)
        Start-Sleep -Milliseconds 200
        if ([Math]::Abs($pattern.Current.VerticalScrollPercent - $scroller.Vertical) -lt 0.1) {
            throw 'Scroll position did not change for the restoration check.'
        }
    }
    finally {
        Restore-PtQuickAccentSurfaceState -Baseline $surface | Out-Null
    }
    'PASS: changed-owner rejection and live expander/scroll round-trip restoration.'
}
