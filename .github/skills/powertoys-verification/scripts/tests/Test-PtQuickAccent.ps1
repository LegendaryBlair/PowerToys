# Copyright (c) Microsoft Corporation.
# The Microsoft Corporation licenses this file to you under the MIT license.
# See the LICENSE file in the project root for more information.

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
