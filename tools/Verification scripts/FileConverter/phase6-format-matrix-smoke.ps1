param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path,
    [int]$PerCaseTimeoutMs = 6000,
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
        throw "PowerToys process exited before context-menu checks."
    }

    return $running
}

$powerToysExe = Join-Path $RepoRoot "x64\Debug\PowerToys.exe"
$sampleDir = Join-Path $RepoRoot "x64\Debug\WinUI3Apps\FileConverterSmokeTest"
$shellVerbSmoke = Join-Path $RepoRoot "src\modules\FileConverter\FileConverterContextMenu\run-shell-verb-smoke.ps1"
$sourcePath = Join-Path $sampleDir "sample.bmp"
$baseName = "sample_converted"
$sourceFileName = Split-Path -Leaf $sourcePath

if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Sample input file not found at: $sourcePath"
}

if (-not (Test-Path -LiteralPath $shellVerbSmoke)) {
    throw "Shell verb smoke script not found at: $shellVerbSmoke"
}

$cases = @(
    @{ Name = "png";  Label = "PNG";  InputFileName = $sourceFileName; OutputFileName = "$baseName.png"; Required = $true },
    @{ Name = "jpeg"; Label = "JPEG"; InputFileName = $sourceFileName; OutputFileName = "$baseName.jpg"; Required = $true },
    @{ Name = "bmp";  Label = "BMP";  InputFileName = "$baseName.png"; OutputFileName = "${baseName}_converted.bmp"; Required = $true },
    @{ Name = "tiff"; Label = "TIFF"; InputFileName = $sourceFileName; OutputFileName = "$baseName.tiff"; Required = $true },
    @{ Name = "heif"; Label = "HEIF"; InputFileName = $sourceFileName; OutputFileName = "$baseName.heic"; Required = $false },
    @{ Name = "webp"; Label = "WebP"; InputFileName = $sourceFileName; OutputFileName = "$baseName.webp"; Required = $false }
)

$results = @()

foreach ($case in $cases) {
    Stop-PowerToysProcesses
    $pt = Start-PowerToys -ExePath $powerToysExe

    $caseSourcePath = Join-Path $sampleDir $case.InputFileName
    if (-not (Test-Path -LiteralPath $caseSourcePath)) {
        throw "Phase 6 matrix source was not created for '$($case.Label)': $caseSourcePath"
    }

    $outputPath = Join-Path $sampleDir $case.OutputFileName
    try {
        & $shellVerbSmoke `
            -TestDirectory $sampleDir `
            -InputFileName $case.InputFileName `
            -ExpectedOutputFileName (Split-Path -Leaf $outputPath) `
            -VerbName $case.Label `
            -OutputWaitTimeoutMs $PerCaseTimeoutMs
        $created = Test-Path -LiteralPath $outputPath
    }
    catch {
        $created = $false
        if ($case.Required) {
            if (-not $LeavePowerToysRunning) {
                Stop-PowerToysProcesses
            }

            throw
        }

        Write-Warning "Optional destination '$($case.Label)' is unavailable: $($_.Exception.Message)"
    }

    $results += [PSCustomObject]@{
        Name = $case.Name
        Destination = $case.Label
        Output = $outputPath
        Created = $created
        Required = $case.Required
    }

    if ($case.Required -and -not $created) {
        if (-not $LeavePowerToysRunning) {
            Stop-PowerToysProcesses
        }

        throw "Phase 6 matrix smoke failed for required destination '$($case.Label)'. Expected output '$outputPath'."
    }

    if (-not $LeavePowerToysRunning) {
        Stop-PowerToysProcesses
    }
}

Stop-PowerToysProcesses
$pt = Start-PowerToys -ExePath $powerToysExe
$unsupportedOutput = Join-Path $sampleDir ($baseName + ".gif")
Remove-Item -LiteralPath $unsupportedOutput -ErrorAction SilentlyContinue
$unsupportedRejected = $false
try {
    & $shellVerbSmoke `
        -TestDirectory $sampleDir `
        -InputFileName (Split-Path -Leaf $sourcePath) `
        -ExpectedOutputFileName (Split-Path -Leaf $unsupportedOutput) `
        -VerbName "GIF" `
        -OutputWaitTimeoutMs 1000
}
catch {
    if ($_.Exception.Message -match "Subcommand not found") {
        $unsupportedRejected = $true
    }
    else {
        throw "Unsupported destination check failed unexpectedly. $($_.Exception.Message)"
    }
}

if (-not $LeavePowerToysRunning) {
    Stop-PowerToysProcesses
}

if (-not $unsupportedRejected -or (Test-Path -LiteralPath $unsupportedOutput)) {
    throw "Phase 6 matrix smoke failed. Unsupported destination 'GIF' was available or created output."
}

$requiredPassed = ($results | Where-Object { $_.Required -and $_.Created }).Count
$requiredTotal = ($results | Where-Object { $_.Required }).Count
$optionalPassed = ($results | Where-Object { -not $_.Required -and $_.Created }).Count
$optionalTotal = ($results | Where-Object { -not $_.Required }).Count

"Phase 6 matrix smoke passed. Required=$requiredPassed/$requiredTotal Optional=$optionalPassed/$optionalTotal"
$results | ForEach-Object {
    " - $($_.Name): created=$($_.Created) output=$($_.Output)"
}

exit 0
