<#
.SYNOPSIS
Reproduce real verification invocation contracts without driving product UI.
.DESCRIPTION
Uses actual formatting commands, original script scope, CLI help, and owned local event/files.
#>
param([string]$Workspace = (Join-Path $env:TEMP "pt-invocation-contracts-$([Guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference = 'Stop'
$helpers = Split-Path $PSScriptRoot -Parent
foreach ($name in 'pt-verification-report','pt-desktop','pt-shared-events','pt-admin-probe') { . "$helpers\$name.ps1" }
if (Test-Path -LiteralPath $Workspace) { throw 'Use a new acceptance workspace.' }
[IO.Directory]::CreateDirectory($Workspace) | Out-Null
$results = [Collections.Generic.List[object]]::new()
function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Reject([scriptblock]$Action, [string]$Pattern) {
    try { & $Action | Out-Null }
    catch { if ($_.Exception.Message -notmatch $Pattern) { throw }; return }
    throw "Expected rejection: $Pattern"
}
function NewRun([string]$Name) {
    New-PtVerificationRun -Workspace "$Workspace\$Name" -Module 'Invocation contract acceptance' `
        -Bits 'Infrastructure only: CLI help, local fixture files/events, read-only session diagnostic' `
        -Scenario InfrastructureAcceptance -Inputs @(
            @{ Name = 'SKILL.md'; Role = 'Skill'; Path = "$helpers\..\SKILL.md" }
            @{ Name = 'contracts.ps1'; Role = 'Checklist'; Path = $PSCommandPath }
            @{ Name = 'recorder.ps1'; Role = 'Helper'; Path = "$helpers\pt-verification-report.ps1" }
            @{ Name = 'desktop.ps1'; Role = 'Helper'; Path = "$helpers\pt-desktop.ps1" }
            @{ Name = 'events.ps1'; Role = 'Helper'; Path = "$helpers\pt-shared-events.ps1" }
        ) -Items @(@{ Id = 'I1'; Description = $Name; Admin = 'NO'; Clarity = 'CLEAR'; UserVisible = $false
            Assertions = @(@{ Id = 'contract'; Description = $Name }) })
}
function Check([string]$Name, [scriptblock]$Action) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        & $Action | Out-Null
        $results.Add([pscustomobject]@{ Name = $Name; Status = 'PASS'; Milliseconds = $clock.ElapsedMilliseconds })
    } catch {
        $results.Add([pscustomobject]@{ Name = $Name; Status = 'FAIL'; Error = $_.Exception.Message; Stack = $_.ScriptStackTrace })
    } finally {
        Set-PtActiveVerificationAttempt -Attempt $null
        $results | ConvertTo-Json -Depth 6 | Set-Content "$Workspace\results.json"
    }
}
Check 'Formatting stream preserves complete tables and original output records' {
    $run = NewRun 'formatting'
    $attempt = Start-PtVerificationAttempt $run -ItemId I1 -Kind Normal -Name formatting
    $values = @([pscustomobject]@{ Name = 'table-first'; Value = 17 }, [pscustomobject]@{ Name = 'table-second'; Value = 23 })
    $records = @(Invoke-PtVerificationStep $attempt -Name 'Actual grouped formatting' -Command 'Format-Table; Format-List; return original object' `
        -ArgumentList @(,$values) -Action {
            param($rows)
            'before-table'
            $rows | Format-Table -GroupBy Value -AutoSize
            $rows | Format-List
            'after-table'
            $rows[0]
        })
    Require (@($records | Where-Object { $_.GetType().FullName -like 'Microsoft.PowerShell.Commands.Internal.Format.*' }).Count -gt 0) 'Formatting records were coerced instead of returned'
    Require ([object]::ReferenceEquals($values[0], $records[-1])) 'Original object return identity changed'
    $text = Get-Content "$($run.Workspace)\attempts\$($attempt.Id)\$($attempt.LastStepId)\stdout.txt" -Raw
    Require ($text.Contains('table-first') -and $text.Contains('table-second') -and $text.IndexOf('before-table') -lt $text.IndexOf('table-first') -and
        $text.IndexOf('after-table') -gt $text.IndexOf('table-second')) 'Rendered formatting output or order was lost'
}
Check 'Formatted output before an exception retains the original error and resets context' {
    $run = NewRun 'formatting-error'
    $attempt = Start-PtVerificationAttempt $run -ItemId I1 -Kind Normal -Name formatting
    Reject {
        Invoke-PtVerificationStep $attempt -Name 'Format then fail' -Command 'Format-Table; throw original' -Action {
            [pscustomobject]@{ Name = 'recorded-before-error'; Value = 7 } | Format-Table
            throw 'original failure after formatted output'
        }
    } 'original failure after formatted output'
    Require ($null -eq (Get-PtActiveVerificationAttempt)) 'A failed step leaked its active context'
    $path = "$($run.Workspace)\attempts\$($attempt.Id)\$($attempt.LastStepId)"
    Require ((Get-Content "$path\streams.jsonl" -Raw).Contains('recorded-before-error')) 'Formatting packets were lost on failure'
    Require ((Get-Content "$path\error.txt" -Raw).Contains('original failure after formatted output')) 'Root error was replaced by formatter cleanup'
}
Check 'Documented preflight runs without a caller Out-String workaround' {
    $run = NewRun 'preflight'
    $attempt = Start-PtVerificationAttempt $run -Context Preflight -Kind Normal -Name 'Real read-only preflight'
    $data = @(Invoke-PtVerificationStep $attempt -Name 'Official bootstrap probes' -Command 'pt-session-diagnose.ps1; Test-PtAdmin; Test-PtRunnerAdmin' `
        -ArgumentList @($helpers) -Action {
            param($root)
            & "$root\pt-session-diagnose.ps1"
            Test-PtAdmin
            Test-PtRunnerAdmin
        })
    Require (@($data | Where-Object { $_ -is [bool] }).Count -eq 1) 'Formatting interrupted the later admin probe'
    Require (@($data | Where-Object { $_.PSObject.Properties['Found'] }).Count -eq 1) 'Runner probe was lost'
}
Check 'Original-path ScriptFile inherits helpers and automatically records its internal CLI call' {
    $run = NewRun 'script-scope'
    $prior = Start-PtVerificationAttempt $run -Context Preflight -Kind Normal -Name caller -Activate
    $attempt = Start-PtVerificationAttempt $run -ItemId I1 -Kind Normal -Name child
    $eventName = "Local\PowerToysVerificationContract-$([Guid]::NewGuid().ToString('N'))"
    $owned = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::AutoReset, $eventName)
    try {
        $result = Invoke-PtVerificationStep $attempt -Name 'Recorded probe' -Command 'Invoke-PtRecordedProbeFixture.ps1' `
            -ScriptFile "$PSScriptRoot\Invoke-PtRecordedProbeFixture.ps1" -ArgumentList @($eventName,$attempt.Id)
        Require ($owned.WaitOne(0)) 'The recorded script did not signal the owned test event'
        Require ($result.AttemptId -eq $attempt.Id -and $result.Help -match 'inspect') 'Script invocation contract failed'
        Require ((Get-PtActiveVerificationAttempt).Id -eq $prior.Id) 'Caller recording context was not restored'
        $steps = @(Read-PtReportEvents $run | Where-Object Type -eq StepStarted)
        Require ($steps.Count -eq 2 -and $steps[1].AttemptId -eq $attempt.Id -and $steps[1].Data.ParentStepId -eq $steps[0].StepId) 'Internal CLI call was unrecorded or attached to the wrong attempt'
        $caught = $null
        try { Invoke-PtVerificationStep $attempt -Name 'Throwing child' -Command 'throw original' -Action { throw 'original child error' } }
        catch { $caught = $_ }
        Require ($caught.Exception.Message -eq 'original child error' -and (Get-PtActiveVerificationAttempt).Id -eq $prior.Id) 'Exception handling lost the caller context'
    } finally { $owned.Dispose() }
}
Check 'Empty native argument survives binding and the recorded argument round-trip' {
    $run = NewRun 'empty-argument'
    $attempt = Start-PtVerificationAttempt $run -ItemId I1 -Kind Normal -Name empty -Activate
    $help = Invoke-PtWinApp -Arguments @('--help','')
    Require ($help -match 'inspect') 'CLI help did not execute with its empty argument'
    $step = @(Read-PtReportEvents $run | Where-Object Type -eq StepStarted)[0]
    $arguments = Get-Content "$($run.Workspace)\attempts\$($attempt.Id)\$($step.StepId)\arguments.json" -Raw | ConvertFrom-Json
    Require ($arguments[0].Count -eq 2 -and $arguments[0][1] -ceq '') 'Empty argument was removed from the execution record'
}
Check 'Real +Package basename imports without manual renaming and preserves source identity' {
    $run = NewRun 'manifest-name'
    $attempt = Start-PtVerificationAttempt $run -ItemId I1 -Kind Normal -Name manifest
    $name = '+Copilot.ShortcutGuideQA9a3d45f1.en-US.yml'
    $source = Join-Path $Workspace $name
    [IO.File]::WriteAllText($source, 'PackageName: +Copilot.ShortcutGuideQA9a3d45f1')
    $proof = Add-PtVerificationArtifact $attempt $source Evidence 'Real module filename'
    Require ($proof.OriginalName -ceq $name) 'Original manifest filename was lost'
    Require ((Get-FileHash (Join-Path $run.Workspace $proof.Path)).Hash -ceq (Get-FileHash $source).Hash) 'Aliasing changed evidence bytes'
    $named = Add-PtVerificationArtifact $attempt $source Evidence 'Explicit safe alias' -Name 'token-fixture.yml'
    Require ($named.Path.EndsWith('-token-fixture.yml') -and $named.OriginalName -ceq $name) 'Explicit alias did not preserve provenance'
    Reject { Add-PtVerificationArtifact $attempt $source Evidence 'Bad alias' -Name '..\escape.yml' } 'Unsafe name'
    $tampered = $proof | ConvertTo-Json | ConvertFrom-Json
    $tampered.OriginalName = 'different-source.yml'
    Reject {
        Add-PtVerificationAssertion $attempt contract PASS 'fixture comparison' 'Attempted provenance relabel' -Evidence @($tampered)
    } 'metadata differs'
}
Check 'Generated long screenshot sidecar imports with a bounded immutable name' {
    $run = NewRun 'sidecar-name'
    $attempt = Start-PtVerificationAttempt $run -ItemId I1 -Kind Normal -Name sidecar
    $image = New-PtVerificationArtifactPath $attempt 'diagnostic-recovered-host-not-normal-regeneration-proof.png'
    [IO.File]::WriteAllBytes($image, [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWZkAAAAASUVORK5CYII='))
    Add-PtVerificationArtifact $attempt $image Screenshot 'Synthetic file, no desktop capture' -Synthetic | Out-Null
    [IO.File]::WriteAllText("$image.state.json", '{"before":true,"after":true}')
    $proof = Add-PtVerificationArtifact $attempt "$image.state.json" Evidence 'Long generated sidecar'
    Require ($proof.OriginalName -ceq [IO.Path]::GetFileName("$image.state.json")) 'Sidecar source name was lost'
    Require ([IO.Path]::GetFileName($proof.Path).Length -le 134) 'Allocated artifact basename exceeded its bounded budget'
    $duplicate = Add-PtVerificationArtifact $attempt "$image.state.json" Evidence 'Same source, new immutable copy'
    Require ($proof.Path -ceq $duplicate.Path -and $proof.Sha256 -ceq $duplicate.Sha256) 'Repeat import did not reuse immutable evidence'
    $maximum = New-PtVerificationArtifactPath $attempt (('a' * 97) + '.png')
    [IO.File]::WriteAllText("$maximum.state.json", '{"before":false,"after":false}')
    $maximumProof = Add-PtVerificationArtifact $attempt "$maximum.state.json" Evidence 'Maximum allocated-name sidecar'
    Require ([IO.Path]::GetFileName($maximumProof.Path).Length -le 134) 'Maximum-name sidecar exceeded its storage budget'
}
$results | Format-Table Name,Status -AutoSize
if (@($results | Where-Object Status -eq 'FAIL').Count) { throw "Invocation-contract regressions failed. Evidence: $Workspace" }
"PASS: $($results.Count) real invocation contract groups. Evidence: $Workspace"
