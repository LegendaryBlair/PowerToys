#Requires -Version 7.4
# Single-writer, local run records; no agent orchestration or automatic action retries.

function Save-PtRunJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value)
    $ErrorActionPreference = 'Stop'
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        ConvertTo-Json -InputObject $Value -Depth 30 | Set-Content -LiteralPath $temporary -Encoding utf8 -ErrorAction Stop
        [IO.File]::Move($temporary, $Path, $true)
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function New-PtRecordedRun {
    <#.SYNOPSIS
    Create a fresh run with explicit scenario/assertion inventory and snapshots of its input files.
    #>
    param([Parameter(Mandatory)][string]$Workspace, [Parameter(Mandatory)][string]$Bits,
        [Parameter(Mandatory)][object[]]$Scenarios, [string[]]$InputPath = @())
    $ErrorActionPreference = 'Stop'
    $root = [IO.Path]::GetFullPath($Workspace)
    if (Test-Path -LiteralPath $root) { throw "Run path already exists: $root" }
    if (-not $Scenarios.Count) { throw 'Scenario inventory is empty.' }
    $scenarioIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $assertionIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $inventory = foreach ($scenario in $Scenarios) {
        if (-not $scenario.Id -or -not $scenarioIds.Add($scenario.Id)) { throw 'Missing/duplicate scenario ID.' }
        if (-not $scenario.AssertionIds.Count) { throw "Empty scenario: $($scenario.Id)" }
        foreach ($id in $scenario.AssertionIds) {
            if (-not $id -or -not $assertionIds.Add($id)) { throw 'Missing/duplicate assertion ID.' }
            [pscustomobject]@{ Id = $id; Scenario = $scenario.Id; Verdict = 'NOT-OBSERVED'; Reason = 'Not executed'; Evidence = @() }
        }
    }
    foreach ($file in $InputPath) {
        if (-not [IO.File]::Exists($file)) { throw "Input file missing: $file" }
    }
    [IO.Directory]::CreateDirectory($root) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $root 'commands')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $root 'inputs')) | Out-Null
    $inputs = foreach ($file in $InputPath) {
        $name = [guid]::NewGuid().ToString('N') + [IO.Path]::GetExtension($file)
        $destination = Join-Path $root "inputs\$name"
        Copy-Item -LiteralPath $file -Destination $destination -ErrorAction Stop
        [pscustomobject]@{ Source = [IO.Path]::GetFullPath($file); Path = "inputs\$name"; Hash = (Get-FileHash -LiteralPath $destination).Hash }
    }
    $run = [pscustomobject]@{
        Id = [guid]::NewGuid().ToString('N'); Workspace = $root; Bits = $Bits
        Created = [DateTime]::UtcNow.ToString('o'); Inputs = @($inputs); Assertions = @($inventory)
        Cleanup = [pscustomobject]@{ Restored = $false; Reason = 'Not verified'; Evidence = @() }
    }
    Save-PtRunJson (Join-Path $root 'run.json') $run
    return $run
}

function Assert-PtRunCurrent {
    param([Parameter(Mandatory)]$Run)
    $ErrorActionPreference = 'Stop'
    $stored = Get-Content -LiteralPath (Join-Path $Run.Workspace 'run.json') -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($stored.Id -cne $Run.Id) { throw 'Run identity mismatch.' }
    if (Test-Path -LiteralPath (Join-Path $Run.Workspace 'manifest.json')) { throw 'Run already finalized.' }
    foreach ($inputFile in $stored.Inputs) {
        if ((Get-FileHash -LiteralPath (Join-Path $Run.Workspace $inputFile.Path)).Hash -cne $inputFile.Hash) {
            throw "Run input snapshot changed: $($inputFile.Path)"
        }
    }
    return $stored
}

function Invoke-PtRecordedCommand {
    <#.SYNOPSIS
    Record a native command's exact arguments, output and failure. A timeout kills only its owned process tree.
    #>
    param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$FilePath,
        [AllowEmptyString()][string[]]$Arguments = @(),
        [string]$WorkingDirectory = (Get-Location).Path,
        [ValidateRange(1, 600)][int]$TimeoutSeconds = 30)
    $ErrorActionPreference = 'Stop'
    $null = Assert-PtRunCurrent $Run
    $id = [guid]::NewGuid().ToString('N')
    $directory = Join-Path $Run.Workspace "commands\$id"
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $record = [ordered]@{
        Id = $id; RunId = $Run.Id; Name = $Name; FilePath = $FilePath; Arguments = $Arguments
        WorkingDirectory = [IO.Path]::GetFullPath($WorkingDirectory); Started = [DateTime]::UtcNow.ToString('o')
        Status = 'Running'; ExitCode = $null; Error = $null
    }
    Save-PtRunJson "$directory\invocation.json" $record
    $process = [Diagnostics.Process]::new()
    $stdout = ''; $stderr = ''; $failure = $null; $started = $false
    $outputTask = $null; $errorTask = $null
    try {
        $process.StartInfo = [Diagnostics.ProcessStartInfo]::new()
        $process.StartInfo.FileName = $FilePath
        $process.StartInfo.WorkingDirectory = $record.WorkingDirectory
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        $process.StartInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
        $process.StartInfo.StandardErrorEncoding = [Text.Encoding]::UTF8
        foreach ($argument in $Arguments) { $process.StartInfo.ArgumentList.Add($argument) }
        $started = $process.Start()
        if (-not $started) { throw 'Process did not start.' }
        $record.ProcessId = $process.Id
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $record.Status = 'Timeout'
            $process.Kill($true)
            $process.WaitForExit()
            throw "Command timed out after $TimeoutSeconds seconds; delivery/side effects may be incomplete."
        }
        $record.ExitCode = $process.ExitCode
        if ($process.ExitCode -ne 0) { throw "Command exited with code $($process.ExitCode)." }
        $record.Status = 'Completed'
    } catch {
        $failure = $_
        if ($record.Status -ne 'Timeout') { $record.Status = 'Error' }
        $record.Error = $_.ToString()
    } finally {
        if ($started -and -not $process.HasExited) {
            $process.Kill($true)
            $process.WaitForExit()
        }
        # A detached descendant can keep redirected pipes open after its parent exits.
        $pipes = @()
        if ($outputTask) { $pipes += @{Task=$outputTask;Reader=$process.StandardOutput;Name='stdout'} }
        if ($errorTask) { $pipes += @{Task=$errorTask;Reader=$process.StandardError;Name='stderr'} }
        foreach ($pipe in $pipes) {
            try {
                if (-not $pipe.Task.Wait(2000)) {
                    $pipe.Reader.Dispose()
                    throw [TimeoutException]::new("Output pipe $($pipe.Name) did not close; a descendant may still be alive.")
                }
                if ($pipe.Name -eq 'stdout') { $stdout = $pipe.Task.GetAwaiter().GetResult() }
                else { $stderr = $pipe.Task.GetAwaiter().GetResult() }
            } catch {
                $record.Status = 'Error'
                $record.Error = "$($record.Error) $($_.ToString())"
                if (-not $failure) { $failure = $_ }
            }
        }
        [IO.File]::WriteAllText("$directory\stdout.txt", $stdout)
        [IO.File]::WriteAllText("$directory\stderr.txt", $stderr)
        $record.Ended = [DateTime]::UtcNow.ToString('o')
        Save-PtRunJson "$directory\invocation.json" $record
        $process.Dispose()
    }
    if ($failure) {
        $failure.Exception.Data['InvocationId'] = $id
        $failure.Exception.Data['EvidencePath'] = "commands\$id\invocation.json"
        throw $failure
    }
    [pscustomobject]@{ Id = $id; Stdout = $stdout; Stderr = $stderr; ExitCode = $record.ExitCode; EvidencePath = "commands\$id\invocation.json" }
}

function Get-PtRunEvidence {
    param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)][string[]]$Path)
    $ErrorActionPreference = 'Stop'
    foreach ($relative in $Path) {
        if ([IO.Path]::IsPathRooted($relative)) { throw 'Evidence paths must be relative.' }
        $full = [IO.Path]::GetFullPath((Join-Path $Run.Workspace $relative))
        if (-not $full.StartsWith($Run.Workspace + '\', [StringComparison]::OrdinalIgnoreCase) -or -not [IO.File]::Exists($full)) {
            throw "Evidence missing or outside run: $relative"
        }
        $cursor = $full
        while ($cursor -ne $Run.Workspace) {
            if ((Get-Item -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Evidence cannot traverse reparse points.' }
            $cursor = [IO.Path]::GetDirectoryName($cursor)
        }
        [pscustomobject]@{ Path = [IO.Path]::GetRelativePath($Run.Workspace, $full); Hash = (Get-FileHash -LiteralPath $full).Hash }
    }
}

function Set-PtRecordedAssertion {
    <#.SYNOPSIS
    Record one assertion with evidence; retain previous judgments and require explicit correction of a FAIL.
    #>
    param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][ValidateSet('PASS','FAIL','BLOCKED','NOT-OBSERVED')][string]$Verdict,
        [Parameter(Mandatory)][string]$Reason, [Parameter(Mandatory)][string[]]$Evidence,
        [string]$CorrectionReason)
    $ErrorActionPreference = 'Stop'
    $state = Assert-PtRunCurrent $Run
    $item = @($state.Assertions | Where-Object Id -CEQ $Id)
    if ($item.Count -ne 1) { throw "Unknown assertion: $Id" }
    if ([string]::IsNullOrWhiteSpace($Reason) -or -not $Evidence.Count) { throw 'Reason and evidence are required.' }
    $refs = @(Get-PtRunEvidence $Run $Evidence)
    if ($item[0].Verdict -eq 'FAIL' -and $Verdict -ne 'FAIL' -and [string]::IsNullOrWhiteSpace($CorrectionReason)) {
        throw 'A valid FAIL cannot be silently replaced; provide an evidenced correction.'
    }
    $judgment = [pscustomobject]@{ Id=$Id; Verdict=$Verdict; Reason=$Reason; Evidence=$refs; Correction=$CorrectionReason; Time=[DateTime]::UtcNow.ToString('o') }
    $judgment | ConvertTo-Json -Depth 12 -Compress | Add-Content -LiteralPath (Join-Path $Run.Workspace 'judgments.jsonl') -ErrorAction Stop
    $item[0].Verdict = $Verdict; $item[0].Reason = $Reason; $item[0].Evidence = $refs
    Save-PtRunJson (Join-Path $Run.Workspace 'run.json') $state
}

function Set-PtRecordedCleanup {
    param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)][bool]$Restored,
        [Parameter(Mandatory)][string]$Reason, [Parameter(Mandatory)][string[]]$Evidence)
    $ErrorActionPreference = 'Stop'
    $state = Assert-PtRunCurrent $Run
    if ([string]::IsNullOrWhiteSpace($Reason) -or -not $Evidence.Count) { throw 'Cleanup requires reason and evidence.' }
    $state.Cleanup = [pscustomobject]@{ Restored=$Restored; Reason=$Reason; Evidence=@(Get-PtRunEvidence $Run $Evidence) }
    $state.Cleanup | ConvertTo-Json -Depth 12 -Compress | Add-Content -LiteralPath (Join-Path $Run.Workspace 'cleanup.jsonl')
    Save-PtRunJson (Join-Path $Run.Workspace 'run.json') $state
}

function Complete-PtRecordedRun {
    <#.SYNOPSIS
    Finalize a complete evidence package; partial/failed coverage is retained with WITHHELD sign-off.
    #>
    param([Parameter(Mandatory)]$Run)
    $ErrorActionPreference = 'Stop'
    $state = Assert-PtRunCurrent $Run
    foreach ($reference in @($state.Assertions.Evidence) + @($state.Cleanup.Evidence)) {
        if ($reference -and (Get-FileHash -LiteralPath (Join-Path $Run.Workspace $reference.Path)).Hash -cne $reference.Hash) {
            throw "Evidence changed after judgment: $($reference.Path)"
        }
    }
    $scenarios = foreach ($group in $state.Assertions | Group-Object Scenario) {
        $outcomes = @($group.Group.Verdict)
        $verdict = if ('FAIL' -in $outcomes) { 'FAIL' } elseif (@($outcomes | Where-Object { $_ -ne 'PASS' }).Count) { 'BLOCKED' } else { 'PASS' }
        [pscustomobject]@{ Id=$group.Name; Verdict=$verdict; Assertions=@($group.Group.Id) }
    }
    $unfinished = @(Get-ChildItem -LiteralPath (Join-Path $Run.Workspace 'commands') -Filter 'invocation.json' -Recurse | ForEach-Object {
        Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
    } | Where-Object Status -In @('Running','Timeout','Error'))
    $invalidCaptures = @(Get-ChildItem -LiteralPath $Run.Workspace -Filter '*.capture.json' | ForEach-Object {
        Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
    } | Where-Object { -not $_.Valid })
    $signoff = if ($state.Cleanup.Restored -and -not $unfinished.Count -and -not $invalidCaptures.Count -and -not @($state.Assertions | Where-Object Verdict -NE 'PASS').Count) { 'APPROVED' } else { 'WITHHELD' }
    $summary = [pscustomobject]@{ RunId=$state.Id; Bits=$state.Bits; Signoff=$signoff; Scenarios=@($scenarios); Assertions=$state.Assertions; Cleanup=$state.Cleanup; CommandFailures=$unfinished.Count; InvalidCaptures=$invalidCaptures.Count }
    Save-PtRunJson (Join-Path $Run.Workspace 'summary.json') $summary
    $lines = @("# Verification run $($state.Id)", '', "BITS: $($state.Bits)", '', "Sign-off: **$signoff**", '', '| Assertion | Scenario | Verdict | Reason | Evidence |', '|---|---|---|---|---|')
    foreach ($item in $state.Assertions) {
        $reason = $item.Reason.Replace('|','\|').Replace("`n",' ').Replace("`r",' ')
        $links = @($item.Evidence | ForEach-Object { $url=$_.Path.Replace('\','/'); "[$url]($url)" }) -join ', '
        $lines += "| $($item.Id) | $($item.Scenario) | $($item.Verdict) | $reason | $links |"
    }
    $lines += @('', "Restoration: $($state.Cleanup.Restored) - $($state.Cleanup.Reason)", '', 'See commands for exact arguments/stdout/stderr and judgments.jsonl for history.')
    $lines | Set-Content -LiteralPath (Join-Path $Run.Workspace 'report.md') -Encoding utf8
    $manifest = foreach ($file in Get-ChildItem -LiteralPath $Run.Workspace -File -Recurse) {
        $ref = Get-PtRunEvidence $Run @([IO.Path]::GetRelativePath($Run.Workspace, $file.FullName))
        [pscustomobject]@{ Path=$ref.Path; Hash=$ref.Hash; Length=$file.Length }
    }
    Save-PtRunJson (Join-Path $Run.Workspace 'manifest.json') @($manifest)
    return $summary
}

function Test-PtRecordedArchive {
    param([Parameter(Mandatory)][string]$Workspace)
    $ErrorActionPreference = 'Stop'
    $manifest = @(Get-Content -LiteralPath (Join-Path $Workspace 'manifest.json') -Raw -ErrorAction Stop | ConvertFrom-Json)
    $files = @(Get-ChildItem -LiteralPath $Workspace -File -Recurse | Where-Object FullName -NE (Join-Path $Workspace 'manifest.json'))
    if ($files.Count -ne $manifest.Count) { throw 'Archive file count differs from manifest.' }
    $run = [pscustomobject]@{ Workspace=[IO.Path]::GetFullPath($Workspace) }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $manifest) {
        $reference = Get-PtRunEvidence $run @($entry.Path)
        if (-not $seen.Add($reference.Path)) { throw 'Duplicate manifest entry.' }
        if ($reference.Hash -cne $entry.Hash -or (Get-Item -LiteralPath (Join-Path $Workspace $entry.Path)).Length -ne $entry.Length) { throw "Archive mismatch: $($entry.Path)" }
    }
    [pscustomobject]@{ Valid=$true; Files=$manifest.Count }
}

function Move-PtRecordedArchive {
    param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)][string]$Destination)
    $ErrorActionPreference = 'Stop'
    $null = Test-PtRecordedArchive $Run.Workspace
    $fullDestination = [IO.Path]::GetFullPath($Destination)
    if ($fullDestination.StartsWith($Run.Workspace + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Archive cannot be inside its source run.' }
    if (Test-Path -LiteralPath $fullDestination) { throw 'Archive destination exists; no overwrite allowed.' }
    if (-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($fullDestination))) { throw 'Create the archive parent directory explicitly first.' }
    Move-Item -LiteralPath $Run.Workspace -Destination $fullDestination -ErrorAction Stop
    $Run.Workspace = $fullDestination
    Test-PtRecordedArchive $Run.Workspace
}
