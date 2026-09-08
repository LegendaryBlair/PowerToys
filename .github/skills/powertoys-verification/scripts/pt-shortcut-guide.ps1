# Module-specific observations. Expected lifecycle behavior stays in the checklist/profile.

function Get-PtShortcutGuideHost {
    <# .SYNOPSIS
    Resolve the current SG host by live process and native class, including its hidden state.
    #>
    [CmdletBinding()]
    param([switch]$Visible)
    $processes = @(Get-Process PowerToys.ShortcutGuide -ErrorAction SilentlyContinue)
    $hosts = @(foreach ($process in $processes) {
        Get-PtNativeWindow -ProcessId $process.Id -ClassName 'WinUIDesktopWin32WindowClass' -Visible:$Visible
    })
    if ($hosts.Count -gt 1) { throw 'Ambiguous Shortcut Guide hosts; inspect process/session identities before driving.' }
    if ($hosts.Count -eq 1) { $hosts[0] }
}

function Wait-PtShortcutGuideHost {
    <# .SYNOPSIS
    Wait for SG host readiness, independently of activation and populated pane content.
    #>
    param([switch]$Visible, [ValidateRange(0.1,300)][double]$TimeoutSeconds = 9)
    Wait-PtCondition -Description 'Shortcut Guide native host' -TimeoutSeconds $TimeoutSeconds -Probe {
        Get-PtShortcutGuideHost -Visible:$Visible
    }
}

function Wait-PtShortcutGuideContent {
    <# .SYNOPSIS
    Wait for mode-specific realized controls, not merely host visibility. Pixels still need review.
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('FullGuide','Indicators')][string]$Mode,
        [ValidateRange(0.1,300)][double]$TimeoutSeconds = 9
    )
    Wait-PtCondition -Description "Shortcut Guide $Mode content" -TimeoutSeconds $TimeoutSeconds -Probe {
        $window = Get-PtShortcutGuideHost -Visible
        if ($window) {
            $tree = Invoke-PtWinApp -Arguments @('inspect','--depth','12','-w',"$($window.Hwnd)",'--json') | ConvertFrom-Json
            $elements = @(Get-PtUiElements $tree)
            $pane = @($elements | Where-Object { $_.automationId -eq 'ShortcutGuide_SearchBox' -and -not $_.isOffscreen })
            $indicators = @($elements | Where-Object { $_.automationId -eq 'IndicatorText' -and -not $_.isOffscreen -and $_.name -match '^[0-9]$' })
            if (($Mode -eq 'FullGuide' -and $pane.Count -eq 1) -or
                ($Mode -eq 'Indicators' -and $pane.Count -eq 0 -and $indicators.Count -gt 0)) {
                [pscustomobject]@{ window = $window; tree = $tree; mode = $Mode }
            }
        }
    }
}

function Get-PtShortcutGuideTaskbarSnapshot {
    <#
    .SYNOPSIS
    Capture primary-taskbar app order, pin files and selected raw Taskband values without mutation.
    .NOTES
    Registry fields are evidence only. Restore pins/order through UI, never by importing Taskband.
    #>
    param()
    $taskbars = @(Get-PtNativeWindow -ClassName 'Shell_TrayWnd' -Visible)
    if ($taskbars.Count -ne 1) { throw 'Expected one visible primary taskbar; resolve the target display explicitly.' }
    $tree = Invoke-PtWinApp -Arguments @('inspect','--depth','16','-w',"$($taskbars[0].Hwnd)",'--json') | ConvertFrom-Json
    $buttons = @(Get-PtUiElements -Tree $tree | Where-Object {
        $_.type -eq 'Button' -and $_.automationId -like 'Appid:*' -and -not $_.isOffscreen
    } | Sort-Object x)
    if (-not $buttons.Count) { throw 'No taskbar application buttons were exposed; do not guess slot order.' }
    $pinDirectory = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
    [pscustomobject]@{
        taskbar = Get-PtWindowIdentity -Hwnd $taskbars[0].Hwnd
        apps = @($buttons | Select-Object automationId,name,selector,x,y,width,height)
        pinDirectoryExists = Test-Path -LiteralPath $pinDirectory
        pinFiles = @(if (Test-Path -LiteralPath $pinDirectory) {
            Get-ChildItem -LiteralPath $pinDirectory -File | Sort-Object Name | ForEach-Object {
                [pscustomobject]@{ name = $_.Name; sha256 = (Get-FileHash -LiteralPath $_.FullName).Hash }
            }
        })
        taskband = Get-PtRegistrySnapshot -SubKey 'Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband' -ValueNames @('Favorites','FavoritesResolve','FavoritesChanges')
    }
}

function Assert-PtShortcutGuideTaskbarRestored {
    <# .SYNOPSIS
    Compare restored app order and pin definitions, excluding FavoritesChanges bookkeeping.
    #>
    param([Parameter(Mandatory)]$Snapshot)
    $actual = Get-PtShortcutGuideTaskbarSnapshot
    if (($actual.apps.automationId -join '|') -cne ($Snapshot.apps.automationId -join '|')) { throw 'Taskbar app order differs from baseline.' }
    if ($actual.pinDirectoryExists -ne $Snapshot.pinDirectoryExists -or
        ($actual.pinFiles | ConvertTo-Json -Compress) -cne ($Snapshot.pinFiles | ConvertTo-Json -Compress)) {
        throw 'Taskbar pin files differ from baseline.'
    }
    $oldValues = @($Snapshot.taskband.values | Where-Object name -ne 'FavoritesChanges')
    $newValues = @($actual.taskband.values | Where-Object name -ne 'FavoritesChanges')
    if (($oldValues | ConvertTo-Json -Depth 8 -Compress) -cne ($newValues | ConvertTo-Json -Depth 8 -Compress)) {
        throw 'Taskbar pin definitions differ from baseline.'
    }
    $actual
}
