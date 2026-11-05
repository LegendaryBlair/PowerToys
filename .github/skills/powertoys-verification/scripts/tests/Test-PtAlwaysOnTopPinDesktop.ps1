# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license. See LICENSE in the project root.
#requires -Version 7.2
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][long]$SettingsHwnd,
    [Parameter(Mandatory)][string]$WinAppPath,
    [string]$EnableToggleName = 'Always On Top',
    [switch]$InspectOnly
)
$ErrorActionPreference = 'Stop'
$skill = (Get-Item "$PSScriptRoot\..\..").FullName
foreach ($file in Get-ChildItem "$skill\scripts" -Filter '*.ps1' | Where-Object Name -ne 'pt-session-diagnose.ps1') { . $file.FullName }
$env:PATH = "$(Split-Path $WinAppPath);$env:PATH"
if ((Get-Command winapp).Source -ine $WinAppPath) { throw 'Pinned winapp resolution failed.' }
$install = Join-Path $env:LOCALAPPDATA 'PowerToys'
$settingsRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys'
$modulePath = Join-Path $install 'PowerToys.AlwaysOnTop.exe'
$fixtureExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$generalPath = Join-Path $settingsRoot 'settings.json'
$moduleSettingsPath = Join-Path $settingsRoot 'AlwaysOnTop\settings.json'
$general = Read-PtSharedFileText $generalPath | ConvertFrom-Json
if ($general.enabled.AlwaysOnTop -ne $false -or @(Get-PtResourceProcessCandidates $modulePath).Count) {
    throw 'This finite acceptance requires initially disabled Always On Top with no existing module process.'
}
$runner = Get-PtLifecycleRunner
$settingsIdentity = Get-PtWindowIdentity -Hwnd $SettingsHwnd
$settingsProcess = Get-PtLifecycleProcessProbe -ProcessId $settingsIdentity.processId
if ($settingsProcess.path -ine (Join-Path $install 'WinUI3Apps\PowerToys.Settings.exe')) { throw 'Wrong Settings executable.' }
$description = if ($InspectOnly) { 'Guarded Settings navigation and restoration only; no pin coverage.' } else { 'Finite guarded enable, native pin/unpin and selected-state restoration; not a product signoff.' }
$items = @(@{Id='AOT-DRIVER';Description=$description;Admin='NO';Clarity='CLEAR';UserVisible=$false;Assertions=@(@{Id='path';Description=$description})})
$inputs = @(Get-PtVerificationInputs -Skill $skill -Inputs @(
    @{Name='driver.ps1';Role='Other';Path=$PSCommandPath}
    @{Name='fixture.ps1';Role='Other';Path="$PSScriptRoot\Show-PtDesktopFixture.ps1"}
    @{Name='checklist.md';Role='Checklist';Path="$skill\references\release-checklist\always-on-top.md"}
    @{Name='profile.md';Role='Profile';Path="$skill\references\modules\always-on-top.md"}
))
$run = New-PtVerificationRun -Workspace $Workspace -Module AlwaysOnTop -Scenario InfrastructureAcceptance `
    -Bits "installed shipped artifact $((Get-Item $modulePath).VersionInfo.FileVersion) (read-only)" -Items $items -Inputs $inputs
$plan = @{Schema='PtRunResources.v1';Resources=@(
    @{Id='settings';Kind='Settings';Hwnd=$SettingsHwnd}
    @{Id='fixture';Kind='Process';Ownership='Owned';FilePath=$fixtureExe;RestoreStep='fixture-exit'}
    @{Id='module';Kind='Process';Ownership='Owned';FilePath=$modulePath;RestoreStep='module-exit'}
)}
New-PtResourceSession -Run $run -ResourcePlan $plan | Out-Null
$state = @{Desktop=$null;Settings=$null;Lifecycle=$null;Fixture=$null;Module=$null;Target=$null;Before=$null;Pinned=$null;Unpinned=$null;Controls=@();Hashes=@{};CleanupErrors=@();Error=$null}
$script:AotPinAcceptance = $state
function Check-Ready($target, [switch]$InputRequired, [switch]$Foreground) {
    $state = $script:AotPinAcceptance
    $peers = @($runner.processId)
    if ($state.Module) { $peers += $state.Module.ProcessId }
    Assert-PtAlwaysOnTopExecutionReady -Identity $target -PeerProcessId $peers -RequireInput:$InputRequired -RequireForeground:$Foreground | Out-Null
}
function Toggle-OwnedPin {
    $state = $script:AotPinAcceptance
    Assert-PtWindowIdentity -Identity $state.Target | Out-Null
    Check-Ready $state.Target -InputRequired
    Assert-PtForegroundOrAbort -Hwnd $state.Target.hwnd | Out-Null
    Check-Ready $state.Target -InputRequired -Foreground
    $binding = (Read-PtSharedFileText $moduleSettingsPath | ConvertFrom-Json).properties.hotkey.value
    $mods = @(if ($binding.win) { 0x5B }; if ($binding.ctrl) { 0x11 }; if ($binding.alt) { 0x12 }; if ($binding.shift) { 0x10 })
    Send-PtChord -Mods $mods -Key $binding.code | Out-Null
}
try {
    $case = Invoke-PtVerificationCase -Run $run -ItemId AOT-DRIVER -Name 'Finite guarded path' -Command $description -ArgumentList @($state) -Action {
        param($attempt, $state)
        Check-Ready $settingsIdentity -InputRequired:(-not $InspectOnly)
        if ([PtDesktop]::GetForegroundWindow() -ne [IntPtr]::Zero) { $state.Desktop = Get-PtDesktopSnapshot }
        $nativeSettings = Get-PtNativeWindow -Hwnd $SettingsHwnd
        if (-not $nativeSettings.Visible -or $nativeSettings.Minimized) { throw 'This finite path requires already visible Settings.' }
        $state.Settings = Get-PtSettingsUiSnapshot -Hwnd $SettingsHwnd -Workspace $Workspace
        $private = New-Item -ItemType Directory -Path (Join-Path $Workspace 'private')
        Add-Type -AssemblyName System.Security
        foreach ($path in @($generalPath, $moduleSettingsPath)) {
            $bytes = Read-PtSharedFileBytes $path
            $state.Hashes[$path] = Get-PtReportHash $bytes
            $name = if ($path -eq $generalPath) { 'general.dpapi' } else { 'module.dpapi' }
            [IO.File]::WriteAllBytes((Join-Path $private.FullName $name), [Security.Cryptography.ProtectedData]::Protect($bytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser))
        }
        Check-Ready $settingsIdentity
        Invoke-PtWinApp -Arguments @('invoke','AlwaysOnTopNavItem','-w',"$SettingsHwnd",'--action','select','--json') | Out-Null
        Wait-PtCondition -Description 'Always On Top Settings page' -TimeoutSeconds 8 -Probe {
            (Read-PtSettingsUiState -Hwnd $SettingsHwnd -AllowUnselected).PageAutomationId -ceq 'AlwaysOnTopNavItem'
        } | Out-Null
        $state.Controls = @(Get-PtSettingsUiElements $SettingsHwnd | Where-Object { $_.Current.ControlType -eq [Windows.Automation.ControlType]::Button } |
            ForEach-Object { [pscustomobject]@{Name=$_.Current.Name;AutomationId=$_.Current.AutomationId;Enabled=$_.Current.IsEnabled} })
        if ($InspectOnly) { return }
        $profile = @{Id='always-on-top';ModuleKey='AlwaysOnTop';PageAutomationId='AlwaysOnTopNavItem';ToggleName=$EnableToggleName;Model='Resident';ProcessName='PowerToys.AlwaysOnTop';ProcessPath=$modulePath;SettingsPath=$generalPath}
        $state.Lifecycle = Get-PtModuleLifecycleSnapshot -Profile $profile -Workspace $Workspace -SettingsTarget $settingsIdentity
        Check-Ready $settingsIdentity
        $state.Module = Invoke-PtOwnedProcessActivation -FilePath $modulePath -TimeoutSeconds 15 -ArgumentList @($state.Lifecycle) -Action {
            param($snapshot)
            Set-PtModuleEnabled -Snapshot $snapshot -Enabled $true -TimeoutSeconds 15 | Out-Null
        }
        Register-PtCreatedProcessWindows -Creation $state.Module | Out-Null
        $fixtureDir = (New-Item -ItemType Directory -Path (Join-Path $Workspace 'fixture')).FullName
        $state.Fixture = Start-PtOwnedProcess -FilePath $fixtureExe -Lifetime Run -ArgumentList @('-NoProfile','-STA','-WindowStyle','Hidden','-File',"`"$PSScriptRoot\Show-PtDesktopFixture.ps1`"",'-StateDirectory',"`"$fixtureDir`"")
        $ready = Wait-PtCondition -Description 'owned fixture readiness' -TimeoutSeconds 20 -Probe {
            $path = Join-Path $fixtureDir 'ready.json'
            if (Test-Path -LiteralPath $path) { Read-PtSharedFileText $path | ConvertFrom-Json }
        }
        if ($ready.processId -ne $state.Fixture.ProcessId) { throw 'Fixture ready receipt has the wrong process.' }
        Register-PtCreatedProcessWindows -Creation $state.Fixture | Out-Null
        $state.Target = Get-PtWindowIdentity -Hwnd $ready.hwnd
        Check-Ready $state.Target
        $state.Before = Get-PtAlwaysOnTopWindowState -Identity $state.Target
        if ($state.Before.Pinned -or $state.Before.Topmost) { throw 'Fixture was not initially ordinary and unpinned.' }
        if ((Get-PtAlwaysOnTopGameMode).RunningDirect3DFullScreen) { throw 'Exclusive fullscreen is not an eligible ordinary fixture.' }
        Toggle-OwnedPin
        $state.Pinned = Wait-PtCondition -Description 'native pin marker and topmost' -TimeoutSeconds 5 -Probe {
            $actual = Get-PtAlwaysOnTopWindowState -Identity $state.Target
            if ($actual.Pinned -and $actual.Topmost) { $actual }
        }
        Toggle-OwnedPin
        $state.Unpinned = Wait-PtCondition -Description 'native unpin marker and topmost removed' -TimeoutSeconds 5 -Probe {
            $actual = Get-PtAlwaysOnTopWindowState -Identity $state.Target
            if (-not $actual.Pinned -and -not $actual.Topmost) { $actual }
        }
    }
} catch { $state.Error = $_.Exception.Message }
finally {
    Invoke-PtVerificationCase -Run $run -Context Cleanup -Name 'Restore finite path' -Command 'Unpin only the owned fixture, restore enablement, close owned processes, restore Settings and desktop, compare selected file hashes' -ArgumentList @($state) -Action {
        param($attempt, $state)
        if ($state.Target) {
            try {
                if ((Get-PtAlwaysOnTopWindowState -Identity $state.Target).Pinned) {
                    Toggle-OwnedPin
                    Wait-PtCondition -Description 'cleanup unpin' -TimeoutSeconds 5 -Probe { -not (Get-PtAlwaysOnTopWindowState -Identity $state.Target).Pinned } | Out-Null
                }
                $actual = Get-PtAlwaysOnTopWindowState -Identity $state.Target
                if ($actual.Topmost -or $actual.Layered -ne $state.Before.Layered -or $actual.Alpha -ne $state.Before.Alpha) { throw 'Owned target native state was not restored.' }
            } catch { $state.CleanupErrors += $_.Exception.Message }
        }
        if ($state.Desktop -and $state.Target) {
            try {
                Check-Ready $state.Target -InputRequired
                Assert-PtForegroundOrAbort -Hwnd $state.Target.hwnd | Out-Null
                Check-Ready $state.Target -InputRequired -Foreground
                Restore-PtPointerPosition -Point $state.Desktop.pointer | Out-Null
            } catch { $state.CleanupErrors += $_.Exception.Message }
        }
        if ($state.Fixture) {
            try {
                Register-PtCreatedProcessWindows -Creation $state.Fixture | Out-Null
                Stop-PtOwnedProcess -Creation $state.Fixture -TimeoutSeconds 10 -RequestExit {
                    param($identity)
                    $main = Get-PtNativeWindow -ProcessId $identity.processId | Where-Object Title -like 'PowerToys helper fixture *'
                    if (@($main).Count -ne 1) { throw 'Owned fixture main window is not unique.' }
                    if (-not [PtDesktop]::PostMessage([IntPtr]$main.Hwnd, 0x10, [IntPtr]::Zero, [IntPtr]::Zero)) { throw 'Fixture close request failed.' }
                } | Out-Null
            } catch { $state.CleanupErrors += $_.Exception.Message }
        }
        if ($state.Lifecycle) {
            try {
                Check-Ready $settingsIdentity
                if ($state.Module) { Register-PtCreatedProcessWindows -Creation $state.Module | Out-Null }
                Restore-PtModuleLifecycleSnapshot -Snapshot $state.Lifecycle -TimeoutSeconds 15 | Out-Null
                if (@(Get-PtResourceProcessCandidates $modulePath).Count) { throw 'Test-started module still exists.' }
            } catch { $state.CleanupErrors += $_.Exception.Message }
        }
        if ($state.Settings) { try { Restore-PtSettingsUiSnapshot $state.Settings -NoActivate | Out-Null } catch { $state.CleanupErrors += $_.Exception.Message } }
        if ($state.Desktop) { try { Restore-PtDesktopSnapshot $state.Desktop | Out-Null } catch { $state.CleanupErrors += $_.Exception.Message } }
        foreach ($path in $state.Hashes.Keys) {
            try { if ((Get-PtReportHash (Read-PtSharedFileBytes $path)) -cne $state.Hashes[$path]) { throw "Selected file bytes changed: $path" } }
            catch { $state.CleanupErrors += $_.Exception.Message }
        }
        try { Complete-PtResourceSession -Attempt $attempt | Out-Null } catch { $state.CleanupErrors += $_.Exception.Message }
    } | Out-Null
}
$result = [pscustomobject]@{
    Scenario='InfrastructureAcceptance';InspectOnly=$InspectOnly.IsPresent
    Verdict=$(if ($state.Error -or $state.CleanupErrors.Count) {'BLOCKED'} else {'PASS'})
    Error=$state.Error;CleanupErrors=$state.CleanupErrors;Controls=$state.Controls
    Before=$state.Before;Pinned=$state.Pinned;Unpinned=$state.Unpinned;Workspace=$Workspace
}
Write-PtReportText (Join-Path $Workspace 'acceptance-result.json') (ConvertTo-Json $result -Depth 20)
$result | ConvertTo-Json -Depth 20
if ($state.Error -or $state.CleanupErrors.Count) { throw 'Finite acceptance did not complete cleanly; retain its evidence and private originals.' }
