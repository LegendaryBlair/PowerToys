# pt-workspaces-fixtures.ps1
# Exact-process and temp-file lifecycle helpers for Workspaces verification fixtures.

function Assert-PtWorkspacesFixtureSession {
    param([Parameter(Mandatory)]$Session)

    if ($Session.PSTypeNames -notcontains 'PowerToys.WorkspacesFixtureSession') {
        throw 'Expected a session created by New-PtWorkspacesFixtureSession.'
    }
}

function New-PtWorkspacesFixtureSession {
    <#
    .SYNOPSIS
    Create an empty per-test-case tracker for exact fixture processes and temp files.

    .EXAMPLE
    $fixtures = New-PtWorkspacesFixtureSession
    try {
        $notepad = Start-PtWorkspacesNotepadFixture -Session $fixtures
        # Drive the test case.
    } finally {
        Stop-PtWorkspacesFixtureSession -Session $fixtures
    }
    #>
    [CmdletBinding()]
    param()

    $session = [pscustomobject]@{
        BaselinePids = [System.Collections.Generic.HashSet[int]]::new()
        Processes = [System.Collections.Generic.List[object]]::new()
        Files = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }
    foreach ($process in Get-Process) {
        $null = $session.BaselinePids.Add($process.Id)
    }

    $session.PSTypeNames.Insert(0, 'PowerToys.WorkspacesFixtureSession')
    return $session
}

function Add-PtWorkspacesFixtureProcess {
    <#
    .SYNOPSIS
    Register an exact fixture PID and its start time, preventing accidental cleanup after PID reuse.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][int]$Id
    )

    Assert-PtWorkspacesFixtureSession -Session $Session
    $process = Get-Process -Id $Id -ErrorAction Stop
    if ($Session.BaselinePids.Contains($process.Id)) {
        throw "Refusing to register pre-existing process PID $($process.Id) as a disposable fixture."
    }

    $record = [pscustomobject]@{
        Id = $process.Id
        StartTimeUtc = $process.StartTime.ToUniversalTime()
    }

    $alreadyTracked = $Session.Processes | Where-Object {
        $_.Id -eq $record.Id -and $_.StartTimeUtc -eq $record.StartTimeUtc
    }
    if (-not $alreadyTracked) {
        $Session.Processes.Add($record)
    }

    return $process
}

function Add-PtWorkspacesFixtureFile {
    <#
    .SYNOPSIS
    Register one exact disposable file for removal during case cleanup.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$Path
    )

    Assert-PtWorkspacesFixtureSession -Session $Session
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $null = $Session.Files.Add($fullPath)
    return $fullPath
}

function Start-PtWorkspacesNotepadFixture {
    <#
    .SYNOPSIS
    Create a uniquely named temp file, open it in Notepad, and register both for exact cleanup.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [string]$Content = 'PowerToys Workspaces fixture'
    )

    Assert-PtWorkspacesFixtureSession -Session $Session
    if (Get-Process -Name notepad -ErrorAction SilentlyContinue) {
        throw 'Notepad is already running. Use a different isolated fixture rather than sharing a user process.'
    }

    $path = Join-Path $env:TEMP "ptws-$([guid]::NewGuid()).txt"
    Set-Content -LiteralPath $path -Value $Content
    Add-PtWorkspacesFixtureFile -Session $Session -Path $path | Out-Null

    $process = Start-Process notepad.exe -ArgumentList "`"$path`"" -PassThru
    Start-Sleep -Milliseconds 500
    if ($process.HasExited) {
        $fileName = [System.IO.Path]::GetFileName($path)
        $matches = @(Get-Process -Name notepad -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowTitle -like "*$fileName*" })
        if ($matches.Count -ne 1) {
            throw "Could not resolve exactly one Notepad process for fixture '$fileName'."
        }

        $process = $matches[0]
    }

    Add-PtWorkspacesFixtureProcess -Session $Session -Id $process.Id | Out-Null
    return [pscustomobject]@{
        Path = $path
        ProcessId = $process.Id
        Hwnd = $process.MainWindowHandle
    }
}

function Stop-PtWorkspacesFixtureSession {
    <#
    .SYNOPSIS
    Gracefully close only registered processes, force exact survivors, and remove registered files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [int]$GracePeriodMilliseconds = 2000
    )

    Assert-PtWorkspacesFixtureSession -Session $Session
    $closed = 0
    $forced = 0
    $removedFiles = 0

    foreach ($record in @($Session.Processes)) {
        $process = Get-Process -Id $record.Id -ErrorAction SilentlyContinue
        if (-not $process -or $process.StartTime.ToUniversalTime() -ne $record.StartTimeUtc) {
            continue
        }

        if ($process.MainWindowHandle) {
            $null = $process.CloseMainWindow()
            $null = $process.WaitForExit($GracePeriodMilliseconds)
        }

        $survivor = Get-Process -Id $record.Id -ErrorAction SilentlyContinue
        if ($survivor -and $survivor.StartTime.ToUniversalTime() -eq $record.StartTimeUtc) {
            $survivor.Kill()
            $survivor.WaitForExit()
            $forced++
        } else {
            $closed++
        }
    }

    foreach ($path in @($Session.Files)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force
            $removedFiles++
        }
    }

    $Session.Processes.Clear()
    $Session.Files.Clear()
    $Session.BaselinePids.Clear()
    return [pscustomobject]@{
        ClosedProcesses = $closed
        ForcedProcesses = $forced
        RemovedFiles = $removedFiles
    }
}
