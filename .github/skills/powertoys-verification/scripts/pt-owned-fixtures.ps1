# Explicitly owned UI fixtures; never treat a launcher PID as ownership of a shared host.
foreach ($dependency in 'pt-desktop','pt-state-snapshot','pt-foreground-guard','pt-uia','pt-sendinput-chord') {
    . "$PSScriptRoot\$dependency.ps1"
}
function Initialize-PtOwnedFixtures {
    Initialize-PtUiAutomation
}

function Get-PtNotepadTabs {
    param([Parameter(Mandatory)][long]$Hwnd)
    Initialize-PtUiAutomation
    $root = [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Hwnd)
    $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::TabItem)
    @($root.FindAll([Windows.Automation.TreeScope]::Descendants,$condition))
}

function Get-PtNotepadWindows {
    foreach ($process in @([Diagnostics.Process]::GetProcessesByName('notepad'))) {
        Get-PtNativeWindow -ProcessId $process.Id -ClassName Notepad
    }
}

function Save-PtOwnedFixture {
    param([Parameter(Mandatory)]$Fixture)
    ConvertTo-Json -InputObject $Fixture -Depth 20 | Set-Content -LiteralPath $Fixture.ReceiptPath -Encoding utf8 -ErrorAction Stop
}

function Assert-PtOwnedFixture {
    param([Parameter(Mandatory)]$Fixture,[Parameter(Mandatory)][string]$Kind)
    if ($Fixture.Kind -ne $Kind -or $Fixture.Id -notmatch '^[a-f0-9]{32}$' -or
        [IO.Path]::GetFileName($Fixture.ReceiptPath) -cne "fixture-$($Fixture.Id).json" -or
        [IO.Path]::GetDirectoryName($Fixture.ReceiptPath) -ine $Fixture.Workspace) { throw 'Invalid fixture ownership receipt.' }
    $suffix = if ($Kind -eq 'Notepad') { '.txt' } else { '' }
    if ($Fixture.Path -ine (Join-Path $Fixture.Workspace "pt-$($Kind.ToLowerInvariant())-$($Fixture.Id)$suffix")) {
        throw 'Fixture resource does not match its unique ownership token.'
    }
    foreach ($path in $Fixture.Workspace,$Fixture.Path) {
        if ((Test-Path -LiteralPath $path) -and ([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Fixture path became a reparse point: $path"
        }
    }
}

function Resolve-PtOwnedNotepadTarget {
    param([Parameter(Mandatory)]$Fixture,[int]$TimeoutSeconds=8)
    $token="pt-notepad-$($Fixture.Id)"
    $found=Wait-PtCondition -Description "owned Notepad file $token" -TimeoutSeconds $TimeoutSeconds -Probe {
        $matches=@(foreach($window in @(Get-PtNotepadWindows)){
            $allTabs=@(Get-PtNotepadTabs $window.Hwnd)
            foreach($tab in @($allTabs|Where-Object {$_.Current.Name.Contains($token)})){
                [pscustomobject]@{Window=$window;Tab=$tab}
            }
            if(-not $allTabs.Count -and $window.Hwnd -notin @($Fixture.Baseline.Identity.hwnd) -and $window.Title.Contains($token)){
                [pscustomobject]@{Window=$window;Tab=$null}
            }
        })
        if($matches.Count -gt 1){throw 'Owned Notepad fixture resolved to multiple windows/tabs.'}
        if($matches.Count -eq 1){$matches[0]}
    }
    $Fixture.Identity=Get-PtWindowIdentity $found.Window.Hwnd
    $Fixture.OwnsWindow=$found.Window.Hwnd -notin @($Fixture.Baseline.Identity.hwnd)
    if($found.Tab){$Fixture.TabRuntimeId=@($found.Tab.GetRuntimeId())}
    Save-PtOwnedFixture $Fixture
    $found
}

function New-PtNotepadFixture {
    <#
    .SYNOPSIS
    Open a unique file and track the actual Notepad tab/window; preserve pre-existing tabs.
    .NOTES
    Receipt is persisted before launch. If cleanup cannot finish, its path is in the exception.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Workspace,[string]$Content='Disposable PowerToys verification fixture',
        [ValidateRange(1,30)][int]$TimeoutSeconds=8)
    Initialize-PtOwnedFixtures
    $workspacePath = (Get-Item -LiteralPath $Workspace -ErrorAction Stop).FullName
    if (-not [IO.Directory]::Exists($workspacePath)) { throw 'Fixture workspace must be an existing directory.' }
    $baseline = @(foreach ($window in @(Get-PtNotepadWindows)) {
        [pscustomobject]@{
            Identity = Get-PtWindowIdentity $window.Hwnd
            Window = Get-PtWindowSnapshot $window.Hwnd
            Tabs = @(Get-PtNotepadTabs $window.Hwnd | ForEach-Object {
                [pscustomobject]@{ Name=$_.Current.Name; RuntimeId=@($_.GetRuntimeId())
                    Selected=$_.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected }
            })
        }
    })
    $id = [Guid]::NewGuid().ToString('N')
    $fixture = [pscustomobject]@{
        Kind='Notepad'; Id=$id; Workspace=$workspacePath; Path=(Join-Path $workspacePath "pt-notepad-$id.txt")
        ReceiptPath=(Join-Path $workspacePath "fixture-$id.json"); Baseline=$baseline
        Desktop=(Get-PtDesktopSnapshot); Identity=$null; TabRuntimeId=@(); OwnsWindow=$false; CloseRequested=$false; ContentClosed=$false; Closed=$false
    }
    Assert-PtOwnedFixture $fixture Notepad
    Save-PtOwnedFixture $fixture
    $stream = [IO.File]::Open($fixture.Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try { $bytes=[Text.Encoding]::UTF8.GetBytes($Content); $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
    try {
        Start-Process notepad.exe -ArgumentList "`"$($fixture.Path)`""
        $found = Resolve-PtOwnedNotepadTarget -Fixture $fixture -TimeoutSeconds $TimeoutSeconds
        if ($found.Tab) {
            $found.Tab.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select()
        }
        Save-PtOwnedFixture $fixture
        if(Get-PtActiveResourceSession){
            if($fixture.OwnsWindow){Register-PtFixtureWindowOwnership -Identity $fixture.Identity -ReceiptPath $fixture.ReceiptPath}
            else{Register-PtBorrowedWindow $fixture.Identity|Out-Null}
        }
        $fixture
    } catch {
        $original = $_
        $original.Exception.Data['FixtureReceipt'] = $fixture.ReceiptPath
        try {
            Remove-PtNotepadFixture -Fixture $fixture | Out-Null
        } catch {
            $original.Exception.Data['FixtureCleanupFailure']=$_.Exception.Message
            [Console]::Error.WriteLine("Notepad fixture cleanup failed: $($_.Exception.Message)")
        }
        try { Restore-PtDesktopSnapshot $fixture.Desktop | Out-Null }
        catch {
            $original.Exception.Data['DesktopRestoreFailure']=$_.Exception.Message
            [Console]::Error.WriteLine($_.Exception.Message)
        }
        throw $original
    }
}

function Remove-PtNotepadFixture {
    <#
    .SYNOPSIS
    Close only the owned tab/window and restore the original tab selection and window placement.
    .NOTES
    A save prompt is not silently accepted. Use DiscardFixtureEdits only for test-owned changes.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Fixture,[switch]$DiscardFixtureEdits)
    Initialize-PtOwnedFixtures
    Assert-PtOwnedFixture $Fixture Notepad
    if ($Fixture.Closed) { return $Fixture }
    if (-not $Fixture.Identity) { Resolve-PtOwnedNotepadTarget -Fixture $Fixture -TimeoutSeconds 2 | Out-Null }
    $cleanupError=$null
    try {
    $h = [long]$Fixture.Identity.hwnd
    if (-not $Fixture.ContentClosed) { Assert-PtWindowIdentity $Fixture.Identity }
    if(-not $Fixture.ContentClosed){Assert-PtProcessRelease -ProcessId $Fixture.Identity.processId}
    $tabs = if (-not $Fixture.ContentClosed) { @(Get-PtNotepadTabs $h) } else { @() }
    if (-not $Fixture.ContentClosed -and -not $Fixture.CloseRequested -and $Fixture.TabRuntimeId.Count) {
        $owned = @($tabs | Where-Object { (@($_.GetRuntimeId()) -join ',') -ceq ($Fixture.TabRuntimeId -join ',') })
        if ($owned.Count -ne 1 -or -not $owned[0].Current.Name.Contains("pt-notepad-$($Fixture.Id)")) {
            throw 'Owned Notepad tab identity changed; refusing to close another tab.'
        }
        $owned[0].GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select()
        if(-not $owned[0].Current.IsEnabled){throw 'Owned tab is disabled; refusing to send close input into a dialog.'}
        $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,'CloseButton')
        $buttons = @($owned[0].FindAll([Windows.Automation.TreeScope]::Descendants,$condition))
        if($buttons.Count){
            $close=Select-PtUniqueUiElement -Elements $buttons -Description 'CloseButton inside the owned Notepad tab'
            $close.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
        }else{
            Assert-PtForegroundOrAbort -Hwnd $h
            if(-not $owned[0].GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected){
                throw 'Owned tab did not remain selected; close chord refused.'
            }
            Send-PtChord -Hwnd $h -Mods 0x11 -Key 0x57|Out-Null
        }
        $Fixture.CloseRequested=$true
        Save-PtOwnedFixture $Fixture
    } elseif (-not $Fixture.ContentClosed -and -not $Fixture.CloseRequested -and $Fixture.OwnsWindow) {
        Register-PtFixtureWindowOwnership -Identity $Fixture.Identity -ReceiptPath $Fixture.ReceiptPath
        Close-PtTrackedWindow $Fixture.Identity
    } elseif (-not $Fixture.ContentClosed -and -not $Fixture.CloseRequested) { throw 'No owned tab and no owned window; cleanup refused.' }
    if (-not $Fixture.ContentClosed -and $Fixture.TabRuntimeId.Count) {
        Wait-PtCondition -Description 'owned Notepad tab closure (save prompts require explicit ownership consent)' -TimeoutSeconds 4 -Probe {
            if (-not [PtDesktop]::IsWindow([IntPtr]$h)) { return $true }
            $remaining = @(Get-PtNotepadTabs $h | Where-Object { (@($_.GetRuntimeId()) -join ',') -ceq ($Fixture.TabRuntimeId -join ',') })
            if (-not $remaining.Count) { return $true }
            if ($DiscardFixtureEdits) {
                $root = [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$h)
                $buttonCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,'SecondaryButton')
                $discard = @($root.FindAll([Windows.Automation.TreeScope]::Descendants,$buttonCondition) | Where-Object { -not $_.Current.IsOffscreen })
                if ($discard.Count -eq 1 -and $discard[0].Current.Name -eq "Don't save") {
                    $discard[0].GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
                }
            }
            $false
        } | Out-Null
    }
    $Fixture.ContentClosed=$true
    Save-PtOwnedFixture $Fixture
    $original = @($Fixture.Baseline | Where-Object { $_.Identity.hwnd -eq $h })
    if ($original.Count) {
        Assert-PtWindowIdentity $original[0].Identity
        $currentTabs = @(Get-PtNotepadTabs $h)
        foreach ($tab in $original[0].Tabs) {
            $match = @($currentTabs | Where-Object { (@($_.GetRuntimeId()) -join ',') -ceq ($tab.RuntimeId -join ',') })
            if ($match.Count -ne 1) { throw 'A pre-existing Notepad tab changed identity; do not overwrite user state.' }
            if ($tab.Selected) { $match[0].GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select() }
        }
        Wait-PtCondition -Description 'original Notepad tab selection' -TimeoutSeconds 2 -Probe {
            $current=@(Get-PtNotepadTabs $h)
            if($current.Count -ne $original[0].Tabs.Count){throw 'Notepad tab set differs from baseline; concurrent changes preserved.'}
            foreach($tab in $original[0].Tabs){
                $match=@($current|Where-Object{(@($_.GetRuntimeId()) -join ',') -ceq ($tab.RuntimeId -join ',')})
                if($match.Count -ne 1 -or $match[0].Current.Name -cne $tab.Name){throw 'Original Notepad tab changed; restoration cannot be certified.'}
                if($match[0].GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected -ne $tab.Selected){return $false}
            }
            $true
        }|Out-Null
        Restore-PtWindowSnapshot $original[0].Window | Out-Null
    }
    if($Fixture.OwnsWindow -and [PtDesktop]::IsWindow([IntPtr]$h)){throw 'Owned Notepad window still contains untracked state; preserved instead of closing other tabs.'}
    if ([IO.File]::Exists($Fixture.Path)) { Remove-Item -LiteralPath $Fixture.Path -ErrorAction Stop }
    } catch {$cleanupError=$_;$cleanupError.Exception.Data['FixtureReceipt']=$Fixture.ReceiptPath;throw}
    finally {
        try {Restore-PtDesktopSnapshot $Fixture.Desktop | Out-Null}
        catch {
            if($cleanupError){$cleanupError.Exception.Data['DesktopRestoreFailure']=$_.Exception.Message;[Console]::Error.WriteLine($_.Exception.Message)}
            else {throw}
        }
    }
    $Fixture.Closed = $true
    Save-PtOwnedFixture $Fixture
    $Fixture
}

function Get-PtExplorerFixtureWindows {
    $shell = New-Object -ComObject Shell.Application
    @($shell.Windows() | Where-Object { $_.FullName -match '(?i)\\explorer\.exe$' })
}

function New-PtExplorerFixture {
    <# .SYNOPSIS
    Open a unique empty directory in a new Explorer window; refuse ownership of reused windows.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Workspace,[ValidateRange(1,30)][int]$TimeoutSeconds=8)
    Initialize-PtOwnedFixtures
    $workspacePath = (Get-Item -LiteralPath $Workspace -ErrorAction Stop).FullName
    $id = [Guid]::NewGuid().ToString('N')
    $fixture = [pscustomobject]@{ Kind='Explorer';Id=$id;Workspace=$workspacePath
        Path=(Join-Path $workspacePath "pt-explorer-$id");ReceiptPath=(Join-Path $workspacePath "fixture-$id.json")
        BaselineHwnds=@(Get-PtExplorerFixtureWindows | ForEach-Object { [long]$_.HWND })
        Desktop=(Get-PtDesktopSnapshot);Identity=$null;ContentClosed=$false;Closed=$false }
    Assert-PtOwnedFixture $fixture Explorer
    Save-PtOwnedFixture $fixture
    [IO.Directory]::CreateDirectory($fixture.Path) | Out-Null
    try {
        Start-Process explorer.exe -ArgumentList "/n,`"$($fixture.Path)`""
        $window = Wait-PtCondition -Description "new Explorer fixture $id" -TimeoutSeconds $TimeoutSeconds -Probe {
            $matches = @(Get-PtExplorerFixtureWindows | Where-Object { $_.Document.Folder.Self.Path -ieq $fixture.Path })
            if ($matches.Count -gt 1) { throw 'Explorer fixture path is open in more than one window.' }
            if ($matches.Count -eq 1) {
                if ([long]$matches[0].HWND -in $fixture.BaselineHwnds) { throw 'Explorer reused a user window; ownership was not established.' }
                $matches[0]
            }
        }
        $fixture.Identity = Get-PtWindowIdentity ([long]$window.HWND)
        Save-PtOwnedFixture $fixture
        Register-PtFixtureWindowOwnership -Identity $fixture.Identity -ReceiptPath $fixture.ReceiptPath
        $fixture
    } catch {
        $original=$_
        $original.Exception.Data['FixtureReceipt']=$fixture.ReceiptPath
        try {Restore-PtDesktopSnapshot $fixture.Desktop|Out-Null}
        catch {$original.Exception.Data['DesktopRestoreFailure']=$_.Exception.Message;[Console]::Error.WriteLine($_.Exception.Message)}
        throw $original
    }
}

function Remove-PtExplorerFixture {
    <# .SYNOPSIS
    Close only the tracked Explorer window still showing its unique folder; never remove unknown files.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Fixture)
    Initialize-PtOwnedFixtures
    Assert-PtOwnedFixture $Fixture Explorer
    if ($Fixture.Closed) { return $Fixture }
    $cleanupError=$null
    try {
    if (-not $Fixture.ContentClosed) {
        Assert-PtWindowIdentity $Fixture.Identity
        $matches = @(Get-PtExplorerFixtureWindows | Where-Object { [long]$_.HWND -eq $Fixture.Identity.hwnd })
        if ($matches.Count -ne 1 -or $matches[0].Document.Folder.Self.Path -ine $Fixture.Path) {
            throw 'Explorer fixture navigated or changed identity; refusing to close unrelated state.'
        }
        Assert-PtProcessRelease -ProcessId $Fixture.Identity.processId
        $matches[0].Quit()
        Wait-PtCondition -Description 'owned Explorer window exit' -TimeoutSeconds 5 -Probe {
            -not [PtDesktop]::IsWindow([IntPtr][long]$Fixture.Identity.hwnd)
        } | Out-Null
        $Fixture.ContentClosed=$true
        Save-PtOwnedFixture $Fixture
    }
    if ([IO.Directory]::Exists($Fixture.Path) -and [IO.Directory]::EnumerateFileSystemEntries($Fixture.Path).GetEnumerator().MoveNext()) {
        throw 'Explorer fixture folder contains untracked contents; preserved for explicit cleanup.'
    }
    if ([IO.Directory]::Exists($Fixture.Path)) { [IO.Directory]::Delete($Fixture.Path, $false) }
    } catch {$cleanupError=$_;$cleanupError.Exception.Data['FixtureReceipt']=$Fixture.ReceiptPath;throw}
    finally {
        try {Restore-PtDesktopSnapshot $Fixture.Desktop | Out-Null}
        catch {
            if($cleanupError){$cleanupError.Exception.Data['DesktopRestoreFailure']=$_.Exception.Message;[Console]::Error.WriteLine($_.Exception.Message)}
            else {throw}
        }
    }
    $Fixture.Closed=$true
    Save-PtOwnedFixture $Fixture
    $Fixture
}
