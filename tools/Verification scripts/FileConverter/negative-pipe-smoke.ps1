param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path,
    [int]$PipeConnectTimeoutMs = 1000,
    [int]$SendAttempts = 20,
    [switch]$LeavePowerToysRunning
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-PowerToysProcesses {
    Get-Process PowerToys, PowerToys.Settings, PowerToys.QuickAccess -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

function Start-PowerToys {
    param(
        [string]$ExePath
    )

    if (-not (Test-Path -LiteralPath $ExePath)) {
        throw "PowerToys executable not found at: $ExePath"
    }

    $proc = Start-Process -FilePath $ExePath -PassThru
    Start-Sleep -Milliseconds 250

    $running = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    if ($null -eq $running) {
        throw "PowerToys process exited before pipe checks."
    }

    return $running
}

function Send-PipePayload {
    param(
        [string]$PipeSimpleName,
        [string]$Payload,
        [int]$ConnectTimeoutMs,
        [int]$Attempts
    )

    $connected = $false
    $written = $false

    for ($i = 0; $i -lt $Attempts; $i++) {
        $client = [System.IO.Pipes.NamedPipeClientStream]::new(
            ".",
            $PipeSimpleName,
            [System.IO.Pipes.PipeDirection]::Out
        )

        try {
            $client.Connect($ConnectTimeoutMs)
            $connected = $true

            $bytes = [System.Text.Encoding]::UTF8.GetBytes($Payload)
            $client.Write($bytes, 0, $bytes.Length)
            $written = $true
        }
        catch {
            if (-not $connected -and $i -lt ($Attempts - 1)) {
                Start-Sleep -Milliseconds 100
            }
        }
        finally {
            $client.Dispose()
        }

        if ($connected) {
            break
        }
    }

    return [pscustomobject]@{
        Connected = $connected
        Written = $written
    }
}

function Get-NewLogContent {
    param(
        [string]$Path,
        [long]$Offset
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }

    $stream = [System.IO.FileStream]::new(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
    )

    try {
        if ($Offset -gt $stream.Length) {
            $Offset = 0
        }

        $null = $stream.Seek($Offset, [System.IO.SeekOrigin]::Begin)
        $reader = [System.IO.StreamReader]::new($stream)
        try {
            return $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Find-FileConverterModuleLog {
    param(
        [string]$LogRoot,
        [DateTime]$UpdatedAfterUtc,
        [int]$TimeoutMs = 5000
    )

    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    do {
        if (Test-Path -LiteralPath $LogRoot) {
            $logFile = Get-ChildItem -LiteralPath $LogRoot -Directory -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTimeUtc -Descending |
                ForEach-Object {
                    $candidate = Join-Path $_.FullName "log.log"
                    if (Test-Path -LiteralPath $candidate) {
                        $candidateFile = Get-Item -LiteralPath $candidate
                        if ($candidateFile.LastWriteTimeUtc -ge $UpdatedAfterUtc) {
                            $candidateFile
                        }
                    }
                } |
                Select-Object -First 1

            if ($null -ne $logFile) {
                return $logFile.FullName
            }
        }

        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "FileConverter ModuleInterface log was not updated under '$LogRoot'. Ensure File Converter is enabled in PowerToys Settings."
}

$powerToysExe = Join-Path $RepoRoot "x64\Debug\PowerToys.exe"
$sampleInput = Join-Path $RepoRoot "x64\Debug\WinUI3Apps\FileConverterSmokeTest\sample.bmp"
$outputFile = Join-Path $RepoRoot "x64\Debug\WinUI3Apps\FileConverterSmokeTest\sample_converted.png"
$moduleLogRoot = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\FileConverter\ModuleInterface\Logs"
$moduleLog = $null

if (-not (Test-Path -LiteralPath $sampleInput)) {
    throw "Sample input file not found at: $sampleInput"
}

$cases = @(
    [pscustomobject]@{
        Name = "untrusted-valid-request"
        Payload = ('{{"action":"FormatConvert","destination":"png","files":["{0}"]}}' -f ($sampleInput -replace "\\", "\\\\"))
    }
)

$results = @()

for ($caseIndex = 0; $caseIndex -lt $cases.Count; $caseIndex++) {
    $case = $cases[$caseIndex]

    Stop-PowerToysProcesses
    $powerToysStartUtc = [DateTime]::UtcNow.AddSeconds(-1)
    $pt = Start-PowerToys -ExePath $powerToysExe
    $pipeSimpleName = "powertoys_fileconverter_$($pt.SessionId)"
    $moduleLog = Find-FileConverterModuleLog -LogRoot $moduleLogRoot -UpdatedAfterUtc $powerToysStartUtc

    if (Test-Path -LiteralPath $outputFile) {
        Remove-Item -LiteralPath $outputFile -Force
    }

    $logOffset = if (Test-Path -LiteralPath $moduleLog) {
        (Get-Item -LiteralPath $moduleLog).Length
    }
    else {
        0
    }

    $sendResult = Send-PipePayload `
        -PipeSimpleName $pipeSimpleName `
        -Payload $case.Payload `
        -ConnectTimeoutMs $PipeConnectTimeoutMs `
        -Attempts $SendAttempts

    $rejectionObserved = $false
    $deadline = [DateTime]::UtcNow.AddSeconds(2)
    while ([DateTime]::UtcNow -lt $deadline) {
        $newLogContent = Get-NewLogContent -Path $moduleLog -Offset $logOffset
        $rejectionObserved = $newLogContent -match "Rejected unauthenticated File Converter pipe client"
        if ($rejectionObserved -or (Test-Path -LiteralPath $outputFile)) {
            break
        }

        Start-Sleep -Milliseconds 50
    }

    $createdOutput = Test-Path -LiteralPath $outputFile
    if ($createdOutput) {
        Remove-Item -LiteralPath $outputFile -Force
    }

    $results += [pscustomobject]@{
        Case = $case.Name
        PipeConnected = $sendResult.Connected
        PayloadWritten = $sendResult.Written
        RejectionLogged = $rejectionObserved
        OutputCreated = $createdOutput
        Passed = ($sendResult.Connected -and $rejectionObserved -and -not $createdOutput)
    }

    if (-not $LeavePowerToysRunning -or $caseIndex -lt ($cases.Count - 1)) {
        Stop-PowerToysProcesses
    }
}

"Untrusted FileConverter Pipe Client Results"
$results | Format-Table -AutoSize | Out-String

if ($null -ne $moduleLog -and (Test-Path -LiteralPath $moduleLog)) {
    $interesting = Select-String -LiteralPath $moduleLog -Pattern "File Converter|malformed request|skipped|conversion failed" -CaseSensitive:$false -ErrorAction SilentlyContinue
    if ($interesting) {
        "Recent listener diagnostics from the FileConverter ModuleInterface log"
        $interesting | Select-Object -Last 20 | ForEach-Object { $_.Line }
    }
    else {
        "No matching listener diagnostics found in the FileConverter ModuleInterface log."
    }
}
else {
    "FileConverter ModuleInterface log not found."
}

if (-not $LeavePowerToysRunning) {
    Stop-PowerToysProcesses
}

$failed = @($results | Where-Object { -not $_.Passed })
if ($failed.Count -gt 0) {
    Write-Error "The untrusted PowerShell pipe client did not connect or was not rejected."
    exit 1
}

"Untrusted PowerShell pipe client was rejected."
exit 0
