<#
.SYNOPSIS
Dependency-free helper acceptance. Interactive mode uses owned WinForms windows, never user Notepad.
.EXAMPLE
pwsh -NoProfile -File .\Test-PtDesktopHelpers.ps1 -Interactive -ShortcutGuide
#>
param(
    [switch]$Interactive,
    [switch]$ShortcutGuide,
    [string]$Workspace = (Join-Path $env:TEMP "pt-helper-acceptance-$([Guid]::NewGuid().ToString('N'))")
)
$ErrorActionPreference = 'Stop'
$helpers = Split-Path $PSScriptRoot -Parent
foreach ($name in 'pt-desktop','pt-foreground-guard','pt-sendinput-chord','pt-state-snapshot','pt-shortcut-guide','pt-shared-events') {
    . "$helpers\$name.ps1"
}
if (Test-Path -LiteralPath $Workspace) { throw 'Use a new workspace for each acceptance attempt.' }
New-Item -ItemType Directory -Path $Workspace | Out-Null
New-Item -ItemType Directory -Path "$Workspace\inputs" | Out-Null
$sourceFiles = @($PSCommandPath, "$PSScriptRoot\Show-PtDesktopFixture.ps1") +
    @(Get-ChildItem -LiteralPath $helpers -Filter '*.ps1' -File | Select-Object -ExpandProperty FullName)
$sourceManifest = @(foreach ($sourceFile in $sourceFiles) {
    $destination = Join-Path "$Workspace\inputs" ([IO.Path]::GetFileName($sourceFile))
    Copy-Item -LiteralPath $sourceFile -Destination $destination -ErrorAction Stop
    [pscustomobject]@{ path = "inputs\$([IO.Path]::GetFileName($sourceFile))"; sha256 = (Get-FileHash -LiteralPath $destination).Hash }
})
$sourceManifest | ConvertTo-Json | Set-Content "$Workspace\input-manifest.json"
$results = [Collections.Generic.List[object]]::new()
function Check([string]$Name, [scriptblock]$Action) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        & $Action | Out-Null
        $results.Add([pscustomobject]@{ name = $Name; status = 'PASS'; milliseconds = $clock.ElapsedMilliseconds })
    } catch {
        $results.Add([pscustomobject]@{ name = $Name; status = 'FAIL'; milliseconds = $clock.ElapsedMilliseconds; error = $_.Exception.Message })
        throw
    } finally {
        $results | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath "$Workspace\results.json"
    }
}
function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Reject([scriptblock]$Action, [string]$Pattern) {
    try { & $Action | Out-Null }
    catch { if ($_.Exception.Message -notmatch $Pattern) { throw }; return }
    throw "Expected rejection matching: $Pattern"
}

Check 'Readiness returns evidence and propagates errors' {
    Get-Command Get-PtForegroundWindow,Restore-PtForegroundAfterShell -ErrorAction Stop | Out-Null
    Require ((Wait-PtCondition -Description ready -Probe { 'ready' }) -eq 'ready') 'Probe result lost'
    Reject { Wait-PtCondition -Description absent -TimeoutSeconds 0.15 -Probe { $false } } 'Timed out'
    Reject { Wait-PtCondition -Description broken -Probe { throw 'probe failure' } } 'probe failure'
    Reject { Invoke-PtWinApp -Arguments @('inspect','-w','0') } 'nonzero'
    Reject { Get-PtNativeWindow -Hwnd 0 } 'HWND=0'
}
Check 'Legacy AppId foreground APIs use the bounded command wrapper' {
    $original = ${function:Invoke-PtWinApp}
    try {
        Set-Item Function:Invoke-PtWinApp -Value {
            param([string[]]$Arguments)
            if (($Arguments -join '|') -ne 'list-windows|-a|offline-fixture') { throw 'Unexpected legacy wrapper arguments' }
            'HWND 123: "fixture" (foreground)'
        }
        Require ((Get-PtHwnd -AppId offline-fixture).ToInt64() -eq 123) 'Legacy HWND parser changed'
        Require (Test-PtForeground -AppId offline-fixture) 'Legacy foreground parser changed'
        Set-Item Function:Invoke-PtWinApp -Value { throw 'bounded command failure' }
        Reject { Get-PtHwnd -AppId offline-fixture } 'bounded command failure'
    } finally { Set-Item Function:Invoke-PtWinApp -Value $original }
}
Check 'File bytes, absence, JSON round-trip and idempotent restoration' {
    $path = Join-Path $Workspace 'file-fixture.bin'
    $absent = Get-PtFileSnapshot -Path $path
    [IO.File]::WriteAllBytes($path, [byte[]]@(0,255,13,10,239,187,191))
    $original = Get-PtFileSnapshot -Path $path | ConvertTo-Json | ConvertFrom-Json
    try {
        [IO.File]::WriteAllText($path, 'changed')
        Restore-PtFileSnapshot $original
        $restoredTime = [IO.File]::GetLastWriteTimeUtc($path)
        Restore-PtFileSnapshot $original
        Require ([IO.File]::GetLastWriteTimeUtc($path) -eq $restoredTime) 'Unchanged restore unnecessarily rewrote the file'
        Require ((Get-PtFileSnapshot $path).base64 -ceq $original.base64) 'Byte mismatch'
    } finally { Restore-PtFileSnapshot $absent | Out-Null }
    Require (-not (Test-Path $path)) 'Absent file remained'
}
Check 'Registry scalar/binary/multi-string kinds and raw expansion round-trip' {
    $subKey = "Software\PowerToysVerificationHelperTests-$([Guid]::NewGuid().ToString('N'))"
    $names = @('binary','emptyBinary','dword','qword','multi','single','expand','missing')
    $absent = Get-PtRegistrySnapshot -SubKey $subKey -ValueNames $names
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($subKey)
    try {
        $key.SetValue('binary', [byte[]]@(0,255,2), 'Binary')
        $key.SetValue('emptyBinary', [byte[]]@(), 'Binary')
        $key.SetValue('dword', [int]-1, 'DWord')
        $key.SetValue('qword', [long]9223372036854775806, 'QWord')
        $key.SetValue('multi', [string[]]@('one','two'), 'MultiString')
        $key.SetValue('single', [string[]]@('one'), 'MultiString')
        $key.SetValue('expand', '%TEMP%\fixture', 'ExpandString')
        $original = Get-PtRegistrySnapshot -SubKey $subKey -ValueNames $names | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $key.SetValue('binary', 'incorrect kind', 'String')
        $key.SetValue('missing', 'added', 'String')
        Restore-PtRegistrySnapshot $original
        Restore-PtRegistrySnapshot $original
    } finally {
        $key.Dispose()
        Restore-PtRegistrySnapshot $absent | Out-Null
    }
}
if (-not $Interactive) {
    if ($ShortcutGuide) { throw '-ShortcutGuide also requires -Interactive.' }
    "PASS: $($results.Count) offline groups. Evidence: $Workspace"
    return
}

$baseline = Get-PtDesktopSnapshot
$baseline | ConvertTo-Json -Depth 10 | Set-Content "$Workspace\desktop-baseline.json"
$fixture = $null
$identity = $null
$sgSnapshot = $null
$sgIdentity = $null
$taskbar = $null
try {
    if ($ShortcutGuide) {
        $sg = Wait-PtShortcutGuideHost
        if ($sg.Visible) { throw 'Shortcut Guide is already visible; do not replace user state.' }
        $sgIdentity = Get-PtWindowIdentity $sg.Hwnd
        $sgPath = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys\Shortcut Guide\settings.json'
        $sgSnapshot = Get-PtFileSnapshot $sgPath
        $sgSnapshot | ConvertTo-Json | Set-Content "$Workspace\sg-settings-baseline.json"
        $settings = Get-Content $sgPath -Raw | ConvertFrom-Json
        if ($settings.properties.win_key_action.value -ne 1) { throw 'This focused smoke requires pre-existing SG indicator mode; no settings are changed.' }
        Check 'Taskbar baseline bounded raw serialization and no-change comparison' {
            $script:taskbar = Get-PtShortcutGuideTaskbarSnapshot
            $taskbar | ConvertTo-Json -Depth 12 | Set-Content "$Workspace\taskbar-baseline.json"
            Assert-PtShortcutGuideTaskbarRestored $taskbar
        }
    }
    $startInfo = [Diagnostics.ProcessStartInfo]::new((Get-Command pwsh).Source)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    foreach ($argument in @('-NoProfile','-STA','-File',"$PSScriptRoot\Show-PtDesktopFixture.ps1",'-StateDirectory',$Workspace)) {
        $startInfo.ArgumentList.Add($argument)
    }
    $fixture = [Diagnostics.Process]::Start($startInfo)
    $ready = Wait-PtCondition -Description 'owned fixture startup' -Probe {
        if (Test-Path "$Workspace\ready.json") { Get-Content "$Workspace\ready.json" -Raw | ConvertFrom-Json }
    }
    $identity = Get-PtWindowIdentity -Hwnd $ready.hwnd
    Require ([PtDesktop]::IsWindowVisible([IntPtr]$ready.hwnd)) 'Fixture must be visibly rendered before input'
    Check 'Exact foreground distinguishes two windows in the same process' {
        Assert-PtForegroundOrAbort -Hwnd $ready.otherHwnd
        Require (-not (Test-PtForeground -Hwnd $ready.hwnd)) 'Wrong same-process window accepted'
        Assert-PtForegroundOrAbort -Hwnd $ready.hwnd
        Require (Test-PtForeground -Hwnd $ready.hwnd) 'Exact foreground was not established'
        $wrong = $identity | ConvertTo-Json | ConvertFrom-Json
        $wrong.processStartTicks--
        Reject { Assert-PtWindowIdentity $wrong } 'identity changed'
        [void][PtDesktop]::ShowWindow([IntPtr]$ready.otherHwnd, 0)
        try { Reject { Assert-PtForegroundOrAbort -Hwnd $ready.otherHwnd -WarningAction SilentlyContinue } 'ABORT' }
        finally { [void][PtDesktop]::ShowWindow([IntPtr]$ready.otherHwnd, 5) }
        Assert-PtForegroundOrAbort -Hwnd $ready.hwnd
    }
    Check 'Paced key reaches actual input control with measurable dwell' {
        Send-PtChord -Hwnd $ready.hwnd -Key 0x58 -KeyDownMilliseconds 120
        $keys = Wait-PtCondition -Description 'fixture key-up event' -Probe {
            if (Test-Path "$Workspace\keys.jsonl") {
                $events = @(Get-Content "$Workspace\keys.jsonl" | ConvertFrom-Json)
                if (@($events | Where-Object { $_.key -eq 0x58 -and -not $_.down }).Count) { ,$events }
            }
        }
        $down = $keys | Where-Object { $_.key -eq 0x58 -and $_.down } | Select-Object -First 1
        $up = $keys | Where-Object { $_.key -eq 0x58 -and -not $_.down } | Select-Object -First 1
        Require ($null -ne $down -and $null -ne $up) 'Both physical key events must be observed'
        $dwell = ($up.ticks - $down.ticks) * 1000.0 / $ready.stopwatchFrequency
        Require ($dwell -ge 100) "Observed dwell too short: $dwell ms"
        Require ((Get-Content "$Workspace\text.txt" -Raw) -ceq 'x') 'Input did not reach the fixture text control'
        $tree = Invoke-PtWinApp -Arguments @('inspect','--depth','5','-w',"$($ready.hwnd)",'--json')
        $tree | Set-Content "$Workspace\fixture-tree.json"
        Save-PtPassiveScreenshot -Path "$Workspace\typed-key.png"
    }
    Check 'Held keys release when observation throws' {
        Reject {
            Invoke-PtHeldKeys -Hwnd $ready.hwnd -Keys @(0x11,0x10) -Action {
                Require (([PtChord]::GetAsyncKeyState(0x11) -band 0x8000) -ne 0) 'Control was not held'
                throw 'intentional observation error'
            }
        } 'intentional observation error'
        Require (([PtChord]::GetAsyncKeyState(0x11) -band 0x8000) -eq 0 -and
            ([PtChord]::GetAsyncKeyState(0x10) -band 0x8000) -eq 0) 'Modifier remained held'
    }
    Check 'Passive capture preserves a real context menu and rejects overwrite' {
        Send-PtChord -Hwnd $ready.hwnd -Mods 0x10 -Key 0x79
        Wait-PtCondition -Description 'fixture context menu' -Probe {
            (Test-Path "$Workspace\menu.txt") -and (Get-Content "$Workspace\menu.txt" -Raw) -eq 'open'
        }
        $observe = { Get-Content "$Workspace\menu.txt" -Raw }
        Save-PtPassiveScreenshot -Path "$Workspace\menu-passive.png" -Observe $observe
        Require ((& $observe) -eq 'open') 'Capture dismissed menu'
        Reject { Save-PtPassiveScreenshot -Path "$Workspace\menu-passive.png" -Observe $observe } 'exist'
        Send-PtChord -Key 0x1B
    }
    Check 'Changed observation is retained but rejected as evidence' {
        $script:observations = 0
        Reject {
            Save-PtPassiveScreenshot -Path "$Workspace\invalid-observation.png" -Observe {
                $script:observations++
                $script:observations
            }
        } 'evidence is invalid'
        Require (Test-Path "$Workspace\invalid-observation.png.state.json") 'Invalid observation lost its diagnostic sidecar'
    }
    Check 'Full window placement JSON round-trip, minimized state, repeated restoration' {
        foreach ($show in 1,2,3) {
            [void][PtDesktop]::ShowWindow([IntPtr]$ready.hwnd, $show)
            Start-Sleep -Milliseconds 200
            $snapshot = Get-PtWindowSnapshot -Hwnd $ready.hwnd | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $snapshot | ConvertTo-Json -Depth 10 | Set-Content "$Workspace\placement-$show.json"
            try {
                [void][PtDesktop]::ShowWindow([IntPtr]$ready.hwnd, 9)
                $changed = [PtDesktop]::Placement([IntPtr]$ready.hwnd)
                $changed.rcNormalPosition = [PtDesktop+RECT]@{ Left = 350; Top = 350; Right = 950; Bottom = 750 }
                [PtDesktop]::Place([IntPtr]$ready.hwnd, $changed)
            } finally {
                Restore-PtWindowSnapshot $snapshot
                Restore-PtWindowSnapshot $snapshot
            }
        }
        [void][PtDesktop]::ShowWindow([IntPtr]$ready.hwnd, 9)
    }
    if ($ShortcutGuide) {
        Check 'Actual SG left/right Windows hold and passive capture through release' {
            foreach ($winKey in 0x5B,0x5C) {
                Invoke-PtHeldKeys -Hwnd $ready.hwnd -Keys @($winKey) -Action {
                    $content = Wait-PtShortcutGuideContent -Mode Indicators
                    $content.tree | ConvertTo-Json -Depth 40 | Set-Content "$Workspace\sg-held-$winKey-tree.json"
                    Save-PtPassiveScreenshot -Path "$Workspace\sg-held-$winKey.png" -Observe {
                        [ordered]@{
                            visible = [bool](Get-PtShortcutGuideHost -Visible)
                            held = ([PtChord]::GetAsyncKeyState($winKey) -band 0x8000) -ne 0
                        }
                    }
                }
                Wait-PtCondition -Description 'SG hidden after Windows release' -Probe { -not (Get-PtShortcutGuideHost -Visible) }
                Start-Sleep -Milliseconds 500
                Require (Test-PtForeground -Hwnd $ready.hwnd) 'Windows release did not return to the fixture foreground'
                Save-PtPassiveScreenshot -Path "$Workspace\sg-released-$winKey.png"
            }
        }
        Check 'Actual SG configured chord, populated guide and close' {
            $chord = $settings.properties.open_shortcutguide
            $mods = @()
            if ($chord.win) { $mods += 0x5B }; if ($chord.ctrl) { $mods += 0x11 }
            if ($chord.alt) { $mods += 0x12 }; if ($chord.shift) { $mods += 0x10 }
            Send-PtChord -Hwnd $ready.hwnd -Mods $mods -Key $chord.code
            $hostWindow = Wait-PtShortcutGuideHost -Visible
            $content = Wait-PtShortcutGuideContent -Mode FullGuide
            $content.tree | ConvertTo-Json -Depth 40 | Set-Content "$Workspace\sg-guide-tree.json"
            Save-PtPassiveScreenshot -Path "$Workspace\sg-guide.png" -Observe { [bool](Get-PtShortcutGuideHost -Visible) }
            Send-PtChord -Hwnd $hostWindow.Hwnd -Key 0x1B
            Wait-PtCondition -Description 'SG closed after Escape' -Probe { -not (Get-PtShortcutGuideHost -Visible) }
        }
    }
} finally {
    $cleanupErrors = [Collections.Generic.List[string]]::new()
    foreach ($cleanup in @(
        {
          if ($sgIdentity) {
            $foreground = [PtDesktop]::GetForegroundWindow().ToInt64()
            $owner = Get-Process -Id (Get-PtNativeWindow -Hwnd $foreground).ProcessId
            if ($owner.ProcessName -in 'SearchHost','StartMenuExperienceHost' -and $foreground -ne $baseline.foreground.hwnd) {
                Send-PtChord -Hwnd $foreground -Key 0x1B | Out-Null
            }
          }
        },
        {
          if ($sgIdentity) {
            Assert-PtWindowIdentity $sgIdentity
            if (Get-PtShortcutGuideHost -Visible) {
                Send-PtChord -Hwnd $sgIdentity.hwnd -Key 0x1B
                Wait-PtCondition -Description 'SG cleanup' -Probe { -not (Get-PtShortcutGuideHost -Visible) } | Out-Null
            }
          }
        },
        { if ($sgSnapshot) { Restore-PtFileSnapshot $sgSnapshot | Out-Null } },
        { if ($identity -and [PtDesktop]::IsWindow([IntPtr]$identity.hwnd)) { Close-PtTrackedWindow $identity } },
        { if ($fixture -and -not $fixture.HasExited) {
            if (-not $identity) { [void]$fixture.CloseMainWindow() }
            if (-not $fixture.WaitForExit(5000)) { throw "Owned fixture PID $($fixture.Id) did not exit." }
        } },
        { if ($taskbar) { Assert-PtShortcutGuideTaskbarRestored $taskbar | ConvertTo-Json -Depth 12 | Set-Content "$Workspace\taskbar-restored.json" } },
        { Restore-PtDesktopSnapshot $baseline | ConvertTo-Json -Depth 12 | Set-Content "$Workspace\desktop-restored.json" }
    )) {
        try { & $cleanup } catch { $cleanupErrors.Add($_.Exception.Message) }
    }
    if ($cleanupErrors.Count) { throw "Acceptance cleanup incomplete: $($cleanupErrors -join '; ')" }
}
"PASS: $($results.Count) groups. Evidence: $Workspace"
