<#
.SYNOPSIS
Offline failure-path acceptance with a fake native input boundary. Run in a fresh pwsh process.
#>
$ErrorActionPreference = 'Stop'
if ('PtChord' -as [type]) { throw 'Run this test in a fresh process; never replace a loaded native input type.' }
Add-Type @'
using System.Collections.Generic;
public static class PtChord {
    public static bool FailUp;
    public static ushort FailDown;
    public static List<ushort> Releases = new List<ushort>();
    public static short GetAsyncKeyState(int key) { return 0; }
    public static uint Key(ushort key, bool up) {
        if (up) { Releases.Add(key); return FailUp ? 0u : 1u; }
        return key == FailDown ? 0u : 1u;
    }
}
'@
. "$PSScriptRoot\..\pt-sendinput-chord.ps1"
[PtChord]::FailUp = $true
$caught = $null
try {
    Invoke-PtHeldKeys -Keys @(0x11,0x10) -KeyDownDelayMilliseconds 0 -Action { throw 'original observation error' }
} catch { $caught = $_ }
if (-not $caught -or $caught.Exception.Message -ne 'original observation error' -or
    -not $caught.Exception.Data.Contains('InputCleanupFailure')) { throw 'Cleanup masked the original error or lost cleanup diagnostics.' }
if (([PtChord]::Releases -join ',') -ne '16,17') { throw 'Not all keys were released in reverse order.' }
[PtChord]::Releases.Clear()
[PtChord]::FailUp = $false
[PtChord]::FailDown = 0x10
$caught = $null
try {
    Invoke-PtHeldKeys -Keys @(0x11,0x10) -KeyDownDelayMilliseconds 0 -Action { throw 'Must not execute after failed key-down' }
} catch { $caught = $_ }
if (-not $caught -or $caught.Exception.Message -notmatch 'key-down 16 failed' -or
    ([PtChord]::Releases -join ',') -ne '17') { throw 'Partial injection did not release exactly the accepted keys.' }
[PtChord]::FailDown = 0
function Start-Sleep { throw 'Default activation must not add artificial dwell.' }
$sent = Send-PtChord -Mods @(0x5B,0x10) -Key 0xBF
if ($sent -ne 6) { throw 'Default chord input count changed.' }
'PASS: original error preservation, release-all on failure, and partial injection cleanup (fake native boundary).'
