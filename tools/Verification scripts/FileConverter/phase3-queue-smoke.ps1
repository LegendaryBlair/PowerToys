param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path,
    [switch]$LeavePowerToysRunning
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Stop-PowerToysProcesses {
    Get-Process PowerToys, PowerToys.Settings, PowerToys.QuickAccess -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

$powerToysExe = Join-Path $RepoRoot "x64\Debug\PowerToys.exe"
$sampleDir = Join-Path $RepoRoot "x64\Debug\WinUI3Apps\FileConverterSmokeTest"
$shellVerbSmoke = Join-Path $RepoRoot "src\modules\FileConverter\FileConverterContextMenu\run-shell-verb-smoke.ps1"
$input1 = Join-Path $sampleDir "sample.bmp"
$input2 = Join-Path $sampleDir "sample2.bmp"
$output1 = Join-Path $sampleDir "sample_converted.png"
$output2 = Join-Path $sampleDir "sample2_converted.png"

if (-not (Test-Path -LiteralPath $powerToysExe)) {
    throw "PowerToys executable not found at: $powerToysExe"
}

if (-not (Test-Path -LiteralPath $input1)) {
    throw "Sample input file not found at: $input1"
}

if (-not (Test-Path -LiteralPath $shellVerbSmoke)) {
    throw "Shell verb smoke script not found at: $shellVerbSmoke"
}

Copy-Item -LiteralPath $input1 -Destination $input2 -Force
Remove-Item -LiteralPath $output1, $output2 -ErrorAction SilentlyContinue

Stop-PowerToysProcesses
$pt = Start-Process -FilePath $powerToysExe -PassThru
Start-Sleep -Milliseconds 250
$null = Get-Process -Id $pt.Id -ErrorAction Stop

$invocations = @(
    @{ Input = (Split-Path -Leaf $input1); Output = (Split-Path -Leaf $output1) },
    @{ Input = (Split-Path -Leaf $input2); Output = (Split-Path -Leaf $output2) }
)

$jobs = @(
    foreach ($invocation in $invocations) {
        Start-Job -ScriptBlock {
            param($ScriptPath, $TestDirectory, $InputName, $OutputName)
            & $ScriptPath `
                -TestDirectory $TestDirectory `
                -InputFileName $InputName `
                -ExpectedOutputFileName $OutputName `
                -VerbName "PNG"
        } -ArgumentList $shellVerbSmoke, $sampleDir, $invocation.Input, $invocation.Output
    }
)

try {
    $null = Wait-Job -Job $jobs -Timeout 45
    $jobErrors = @()
    $jobs | Receive-Job -ErrorAction SilentlyContinue -ErrorVariable +jobErrors | Write-Host

    $incomplete = @($jobs | Where-Object { $_.State -ne "Completed" })
    if ($incomplete.Count -gt 0 -or $jobErrors.Count -gt 0) {
        $details = @(
            $incomplete | ForEach-Object { "$($_.Name)=$($_.State): $($_.JobStateInfo.Reason)" }
            $jobErrors | ForEach-Object { $_.ToString() }
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        throw "One or more context-menu invocations failed: $($details -join '; ')"
    }
}
finally {
    $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
}

$ok1 = Test-Path -LiteralPath $output1
$ok2 = Test-Path -LiteralPath $output2

if (-not $LeavePowerToysRunning) {
    Stop-PowerToysProcesses
}

if (-not $ok1 -or -not $ok2) {
    throw "Phase 3 queue smoke failed. output1=$ok1 output2=$ok2"
}

"Phase 3 queue smoke passed. output1=$ok1 output2=$ok2"
exit 0
