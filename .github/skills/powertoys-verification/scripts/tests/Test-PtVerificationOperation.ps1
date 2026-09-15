#requires -Version 7.0
<#
.SYNOPSIS
Standalone offline H10 contracts. Creates only synthetic runs in a new workspace; no Pester.
#>
param(
    [Parameter(Mandatory)][string]$Workspace,
    [ValidateSet('Suite','FreshProcess','PendingProcess')][string]$Mode = 'Suite',
    [string]$Recorder = (Join-Path (Split-Path $PSScriptRoot -Parent) 'pt-verification-report.ps1'),
    [string]$OperationHelper = (Join-Path (Split-Path $PSScriptRoot -Parent) 'pt-verification-operation.ps1')
)
$ErrorActionPreference = 'Stop'
. $Recorder
. $OperationHelper
function Require([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
function Capture([scriptblock]$Action, [string]$Pattern) {
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        return $_
    }
    throw "Expected rejection: $Pattern"
}
function Attempt($Run, [string]$Kind = 'Normal', [string]$Item = 'L1') {
    Start-PtVerificationAttempt -Run $Run -ItemId $Item -Kind $Kind -Name "$Kind offline fixture"
}

if ($Mode -ne 'Suite') {
    $run = Open-PtVerificationRun -Workspace $Workspace
    $key = if ($Mode -eq 'PendingProcess') { 'pending-host' } else { 'shared-host' }
    $before = Get-PtVerificationOperationStatus -Run $run -OperationKey $key
    $a = Attempt $run
    if ($Mode -eq 'FreshProcess') {
        Require ($before.FailureCount -eq 2 -and -not $before.BudgetEnforced) 'Fresh process lost diagnostic history or enabled a limit'
        Capture { Invoke-PtVerificationOperation $a $key Drive 'third script' { throw 'third obstacle error' } } 'third obstacle error' | Out-Null
    } else {
        Require (-not $before.Blocked -and $before.PendingOperations.Count -eq 1) 'Reopen lost pending history or recreated a label lock'
    }
    $counter = @{ Drives=0; Cleanups=0; ResourceReady=$false }
    $errorRecord = $null
    if ($Mode -eq 'FreshProcess') {
        Invoke-PtVerificationOperation $a $key Drive 'later operation still executes' `
            -Action { param($c) $c.Drives++ } -ArgumentList @($counter) `
            -Cleanup { param($c) $c.Cleanups++ } -CleanupArgumentList @($counter) | Out-Null
        Require ($counter.Drives -eq 1 -and $counter.Cleanups -eq 1) 'Completed failures still stopped a later operation'
    } else {
        $errorRecord = Capture {
            Invoke-PtVerificationOperation $a $key Drive 'check actual resource readiness' `
                -Action { param($c) if(-not $c.ResourceReady){throw 'Owned resource is not restored'};$c.Drives++ } -ArgumentList @($counter) `
                -Cleanup { param($c) $c.Cleanups++;$c.ResourceReady=$true } -CleanupArgumentList @($counter)
        } 'Owned resource is not restored'
        Require ($counter.Drives -eq 0 -and $counter.Cleanups -eq 1) 'Resource guard or cleanup was bypassed'
        Invoke-PtVerificationOperation $a $key Drive 'new operation after actual resource restoration' `
            -Action {param($c) if(-not $c.ResourceReady){throw 'Owned resource is not restored'};$c.Drives++} -ArgumentList @($counter) `
            -Cleanup {param($c) $c.Cleanups++} -CleanupArgumentList @($counter)|Out-Null
        Require ($counter.Drives -eq 1 -and $counter.Cleanups -eq 2) 'Pending history permanently prevented a new safe operation'
    }
    $independent = Invoke-PtVerificationOperation $a 'independent-host' Observe 'independent probe' { 'independent-output' }
    Require ($independent -ceq 'independent-output') 'Independent key was stopped'
    Stop-PtVerificationAttempt $a -Reason 'Offline reopened process finished'
    [pscustomobject]@{
        Before=$before; After=(Get-PtVerificationOperationStatus $run $key)
        ErrorId=$(if($errorRecord){$errorRecord.FullyQualifiedErrorId}else{$null})
        Drives=$counter.Drives; Cleanups=$counter.Cleanups; Independent=$independent
    } | ConvertTo-Json -Depth 12 -Compress
    return
}

if (Test-Path -LiteralPath $Workspace) { throw 'Use a new workspace.' }
[IO.Directory]::CreateDirectory($Workspace) | Out-Null
$proof = Join-Path $Workspace 'fixture.txt'
[IO.File]::WriteAllText($proof, 'Synthetic H10 evidence only. No product, desktop or historical archive access.')
$boundariesPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'references\operation-boundaries.md'
$inputs = @(
    @{ Name='fixture.txt'; Role='Skill'; Path=$proof }
    @{ Name='contracts.ps1'; Role='Checklist'; Path=$PSCommandPath }
    @{ Name='recorder.ps1'; Role='Helper'; Path=$Recorder }
    @{ Name='operation.ps1'; Role='Helper'; Path=$OperationHelper }
    @{ Name='operation-boundaries.md'; Role='Other'; Path=$boundariesPath }
)
$sourceHashes = @(Get-FileHash -Algorithm SHA256 -LiteralPath $Recorder,$OperationHelper,$PSCommandPath,$boundariesPath)
$sourceHashes | Select-Object Path,Hash | ConvertTo-Json | Set-Content "$Workspace\source-hashes.json"
function NewRun([string]$Name) {
    $items = @(foreach ($id in 'L1','L2') {
        @{ Id=$id; Description="Synthetic $id"; Admin='NO'; Clarity='CLEAR'; UserVisible=$false
            Assertions=@(@{ Id='value'; Description='Explicit observation required' }) }
    })
    New-PtVerificationRun -Workspace "$Workspace\$Name" -Module 'H10 offline acceptance' `
        -Bits 'Synthetic only; no PowerToys signoff' -Scenario InfrastructureAcceptance -Items $items -Inputs $inputs
}
$results = [Collections.Generic.List[object]]::new()
function Check([string]$Name, [scriptblock]$Action) {
    try { & $Action | Out-Null; $results.Add(@{ Name=$Name; Status='PASS' }); Write-Host "PASS $Name" }
    catch { $results.Add(@{ Name=$Name; Status='FAIL'; Error=$_.Exception.Message; Stack=$_.ScriptStackTrace }); throw }
    finally { $results | ConvertTo-Json -Depth 10 | Set-Content "$Workspace\results.json" }
}
function FreshProcess($Run, [string]$ChildMode) {
    $text = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -NonInteractive -File $PSCommandPath `
        -Workspace $Run.Workspace -Mode $ChildMode -Recorder $Recorder -OperationHelper $OperationHelper
    Require ($LASTEXITCODE -eq 0) "Fresh process failed: $text"
    $text | Set-Content "$Workspace\$ChildMode.json"
    $text | ConvertFrom-Json
}
function SyntheticEnd($Run, $Attempt, [string]$Key, [long]$Ticks) {
    $id = [Guid]::NewGuid().ToString('N')
    Add-PtReportEvent $Run OperationStarted @{
        OperationKey=$Key; OperationId=$id; Stage='Observe'; Command='Synthetic timestamp fixture'
        Start='2001-01-01T00:00:00Z'; Recovery=$true
    } $Attempt
    Add-PtReportEvent $Run OperationEnded @{
        OperationKey=$Key; OperationId=$id; Stage='Observe'; End='2026-01-01T00:00:00Z'
        ActionStarted=$true; Failed=$true; ActionDurationTicks=$Ticks; RecoveryTicks=$Ticks
        RecordingFailed=$false; Outcome='Error'; Error=@{ Message='Synthetic elapsed fixture' }
    } $Attempt
}

Check 'Original objects, arguments, exact command and callback sources are recorded without verdicts' {
    $run = NewRun success
    $a = Attempt $run
    $value = [pscustomobject]@{ Value=42 }
    $cleanup = @{ Count=0 }
    $unused = Get-PtVerificationOperationStatus $run 'host'
    Require (-not $unused.PolicyLocked -and -not $unused.Blocked -and $unused.FailureCount -eq 0) 'Unused key has invented state'
    $actual = Invoke-PtVerificationOperation $a host Observe 'read fixture --value 42' `
        -Action { param($v) $v } -ArgumentList @($value) `
        -Cleanup { param($c) $c.Count++ } -CleanupArgumentList @($cleanup)
    Require ([object]::ReferenceEquals($value, $actual) -and $cleanup.Count -eq 1) 'Callback identity/arguments or cleanup changed'
    $state = Get-PtReportState $run
    Require ($state.Steps.Count -eq 2 -and $state.Steps[0].Command -ceq 'read fixture --value 42') 'Missing action/cleanup step'
    Require ($state.Steps[0].Sources.Count -eq 4) 'Missing command, arguments, wrapper or implementation'
    $stdout = @($state.Steps[0].Outputs | Where-Object { $_.Path.EndsWith('\stdout.txt') })[0]
    Require ([IO.File]::ReadAllText((Join-Path $run.Workspace $stdout.Path)).Contains('42')) 'Output was not recorded'
    Require (@($state.Events | Where-Object Type -in 'AssertionObserved','RestorationObserved').Count -eq 0) 'Exit zero invented a judgment'
    Require ($state.Items[0].Verdict -eq 'BLOCKED' -and $state.Signoff -eq 'WITHHELD') 'Exit zero became a product PASS'
    $status = Get-PtVerificationOperationStatus $run host
    Require (-not $status.BudgetEnforced -and $null -eq $status.MaxFailures -and $null -eq $status.MaxRecoverySeconds -and
        $status.ActiveRecoveryTicks -eq 0) 'New operations still configure cumulative stops or charge successful Normal time'
}
Check 'ScriptFile preserves original path and arguments while recording immutable source and active time' {
    $run = NewRun script-file
    $file = Join-Path $Workspace 'case-fixture.ps1'
    [IO.File]::WriteAllText($file, 'param($attempt,$value) [pscustomobject]@{RunId=$attempt.Run.Id;Value=$value;Source=$PSCommandPath}')
    foreach ($kind in 'Normal','Diagnostic') {
        $a = Attempt $run $kind
        $actual = Invoke-PtVerificationOperation -Attempt $a -OperationKey file-host -Stage Observe `
            -Command "case-fixture --value 42 ($kind)" -ScriptFile $file -ArgumentList @($a,42)
        Require ($actual.RunId -ceq $run.Id -and $actual.Value -eq 42 -and
            $actual.Source -ceq $file) 'Script lost its original path or attempt/arguments'
        $events = @(Read-PtReportEvents $run)
        $fileStep=@($events|Where-Object Type -eq StepStarted)[-1]
        $source=@($fileStep.Data.Sources|Where-Object {$_.Path.EndsWith('\executed.ps1')})[0]
        Require ((Get-FileHash $actual.Source).Hash -ceq $source.Sha256) 'Executed script bytes differ from their snapshot'
        $start = @($events | Where-Object Type -eq OperationStarted)[-1].Data
        $end = @($events | Where-Object Type -eq OperationEnded)[-1].Data
        $step = @($events | Where-Object { $_.Type -eq 'StepEnded' -and $_.StepId -ceq $end.StepId })[0].Data
        Require ($start.Execution -ceq 'File' -and $end.TimingSource -ceq 'StepActionDurationMs' -and $end.ActionStarted) 'File execution/timing provenance missing'
        Require ($end.ActionDurationTicks -eq [long][Math]::Round($step.ActionDurationMs * [TimeSpan]::TicksPerMillisecond)) 'File execution interval differs from recorder timing'
        if ($kind -eq 'Diagnostic') {
            Require ($end.RecoveryTicks -gt 0 -and $end.RecoveryTicks -eq $end.ActionDurationTicks) 'Diagnostic file recovery time was omitted'
        } else { Require ($end.RecoveryTicks -eq 0) 'Normal file success was counted as failed/diagnostic time' }
        Stop-PtVerificationAttempt $a -Reason 'Recorded script fixture'
    }
}
Check 'ScriptFile driver error preserves its ErrorRecord; Record-stage missing file still cleans up without a driver charge' {
    $run = NewRun script-errors
    $file = Join-Path $Workspace 'failing-fixture.ps1'
    [IO.File]::WriteAllText($file, @'
param($holder)
$holder.Error = [Management.Automation.ErrorRecord]::new(
    [IO.FileNotFoundException]::new('script driver failure'), 'FileDriver',
    [Management.Automation.ErrorCategory]::ObjectNotFound, 'script-target')
throw $holder.Error
'@)
    $a = Attempt $run
    $holder = @{ Error=$null }
    $counter = @{ Count=0 }
    $e = Capture {
        Invoke-PtVerificationOperation -Attempt $a -OperationKey file-error -Stage Drive -Command 'failing-fixture' `
            -ScriptFile $file -ArgumentList @($holder) `
            -Cleanup { param($c) $c.Count++ } -CleanupArgumentList @($counter)
    } 'script driver failure'
    Require ([object]::ReferenceEquals($e.Exception,$holder.Error.Exception) -and $e.CategoryInfo.Category -eq 'ObjectNotFound' -and
        $e.TargetObject -ceq 'script-target' -and $e.Exception.Data['PtVerificationOperation'].FailureStage -eq 'Drive') 'File ErrorRecord or stage was replaced'
    $status = Get-PtVerificationOperationStatus $run file-error
    Require ($status.FailureCount -eq 1 -and $status.ActiveRecoveryTicks -gt 0 -and $counter.Count -eq 1) 'File driver failure was not charged once with cleanup'
    $e = Capture {
        Invoke-PtVerificationOperation -Attempt $a -OperationKey missing-file -Stage Record -Command 'missing-fixture' `
            -ScriptFile (Join-Path $Workspace 'nonexistent.ps1') `
            -Cleanup { param($c) $c.Count++ } -CleanupArgumentList @($counter)
    } 'nonexistent\.ps1'
    $end = @(Read-PtReportEvents $run | Where-Object Type -eq OperationEnded)[-1].Data
    $status = Get-PtVerificationOperationStatus $run missing-file
    Require ($end.ActionStarted -eq $false -and $end.ActionDurationTicks -eq 0 -and $status.FailureCount -eq 0 -and
        $status.ActiveRecoveryTicks -eq 0 -and -not $status.Blocked -and $status.UncertainOperations.Count -eq 0 -and
        $status.RecordingFailures.Count -eq 1 -and $counter.Count -eq 2) 'Known non-execution was lost, locked the label or skipped cleanup'
    Require ($e.Exception.Data['PtVerificationOperation'].FailureStage -ceq 'Record') 'Pre-execution recording stage lost'
    $fixed=Invoke-PtVerificationOperation -Attempt $a -OperationKey missing-file -Stage Record -Command corrected `
        -Action {'corrected-output'} -Cleanup {param($c) $c.Count++} -CleanupArgumentList @($counter)
    Require ($fixed -ceq 'corrected-output' -and $counter.Count -eq 3) 'Corrected callback remained locked after a pre-execution error'
}
Check 'ScriptFile missing completion retains per-invocation uncertainty without locking a label' {
    $run = NewRun script-recording-error
    $file = Join-Path $Workspace 'completed-fixture.ps1'
    [IO.File]::WriteAllText($file, 'param($counter) $counter.Drives++; "file output"')
    $a = Attempt $run Diagnostic
    $counter = @{ Drives=0; Cleanups=0 }
    $savedAppend = (Get-Command Add-PtReportEvent).ScriptBlock
    $fault = @{ Once=$true }
    function Add-PtReportEvent {
        param($Run, [string]$Type, $Data, $Attempt=$null, [string]$StepId='')
        if ($Type -eq 'StepEnded' -and $fault.Once) { $fault.Once=$false; throw 'file completion journal failure' }
        & $savedAppend $Run $Type $Data $Attempt $StepId
    }
    try {
        Capture {
            Invoke-PtVerificationOperation -Attempt $a -OperationKey file-journal -Stage Record -Command 'completed-fixture' `
                -ScriptFile $file -ArgumentList @($counter) `
                -Cleanup { param($c) $c.Cleanups++ } -CleanupArgumentList @($counter)
        } 'file completion journal failure' | Out-Null
    } finally { Set-Item Function:\Add-PtReportEvent $savedAppend }
    $end = @(Read-PtReportEvents $run | Where-Object Type -eq OperationEnded)[-1].Data
    $status = Get-PtVerificationOperationStatus $run file-journal
    Require ($counter.Drives -eq 1 -and $counter.Cleanups -eq 1 -and $null -eq $end.ActionStarted -and
        $null -eq $end.ActionDurationTicks -and $end.RecoveryTicks -eq 0 -and -not $status.Blocked -and
        $status.UncertainOperations.Count -eq 1 -and $status.UncertainOperations[0].OperationId -eq $end.OperationId) 'Unrecorded file completion guessed timing/result, locked a label or skipped cleanup'
}
Check 'Cross-attempt and fresh-process failure history never locks a new operation label' {
    $run = NewRun persistence
    foreach ($kind in 'Normal','Diagnostic') {
        $a = Attempt $run $kind
        Capture { Invoke-PtVerificationOperation $a shared-host Drive "different $kind script" { throw 'shared obstacle' } } 'shared obstacle' | Out-Null
        Stop-PtVerificationAttempt $a -Reason 'Retain failed attempt'
    }
    $fresh = FreshProcess $run FreshProcess
    Require ($fresh.After.FailureCount -eq 3 -and -not $fresh.After.Blocked -and -not $fresh.After.BudgetEnforced) 'History was reset or a failure limit was enforced'
    Require ($null -eq $fresh.ErrorId -and $fresh.Drives -eq 1 -and $fresh.Cleanups -eq 1) 'Later operation did not execute and clean up exactly once'
    $reopened = Open-PtVerificationRun $run.Workspace
    $ends = @(Read-PtReportEvents $reopened | Where-Object Type -eq OperationEnded | Where-Object { $_.Data.OperationKey -eq 'shared-host' })
    $failedEnds=@($ends|Where-Object {$_.Data.Failed})
    Require ($ends.Count -eq 4 -and $failedEnds.Count -eq 3 -and @($failedEnds | Where-Object { $_.Data.RecoveryTicks -le 0 -or $_.Data.RecoveryTicks -ne $_.Data.ActionDurationTicks }).Count -eq 0) 'Failed callback history was not retained'
}
Check 'Deprecated limit arguments warn but cannot impose or change cumulative stops' {
    $run = NewRun policy
    $a = Attempt $run
    $warnings=@()
    Invoke-PtVerificationOperation $a fixed-host Record initialize { 'initialize trace' } -MaxFailures 1 -MaxRecoverySeconds 1 `
        -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null
    Require (($warnings -join '|').Contains('Cumulative operation limits are retired')) 'Ignored compatibility limits were not surfaced'
    Capture { Invoke-PtVerificationOperation $a fixed-host Record first { throw 'first error' } } 'first error' | Out-Null
    $before = Get-PtVerificationOperationStatus $run fixed-host
    Invoke-PtVerificationOperation $a fixed-host Observe inherited { 'ok' } | Out-Null
    $counter = @{ Count=0 }
    foreach ($limits in @(@{ MaxFailures=3 }, @{ MaxRecoverySeconds=300 })) {
        $e = Capture {
            Invoke-PtVerificationOperation $a fixed-host Drive changed { throw 'another driver error' } @limits `
                -Cleanup { param($c) $c.Count++ } -CleanupArgumentList @($counter)
        } 'another driver error'
        Require ($e.Exception.Data['PtVerificationOperation'].FailureKind -eq 'Action') 'A compatibility parameter was treated as policy rejection'
    }
    $after = Get-PtVerificationOperationStatus $run fixed-host
    Require ($null -eq $after.MaxFailures -and $null -eq $after.MaxRecoverySeconds -and $after.FailureCount -eq 3 -and
        $after.ActiveRecoveryTicks -ge $before.ActiveRecoveryTicks -and $counter.Count -eq 2 -and -not $after.Blocked) 'Compatibility arguments enabled a limit, lost errors or skipped cleanup'
    Require (@(Read-PtReportEvents $run | Where-Object Type -eq OperationPolicyLocked).Count -eq 0) 'New operations still create policies'
}
Check 'Failed/diagnostic elapsed time remains exact but crossing 300 seconds does not stop execution' {
    $run = NewRun active-time
    $a = Attempt $run
    Invoke-PtVerificationOperation $a slow-host Observe init { 'initialize trace' } | Out-Null
    SyntheticEnd $run $a slow-host 2999999999
    $before = Get-PtVerificationOperationStatus $run slow-host
    Require ($before.ActiveRecoverySeconds -eq [decimal]'299.9999999' -and -not $before.Blocked) 'Active interval was rounded or wall time was charged'
    Invoke-PtVerificationOperation $a slow-host Record 'Normal success is not resolution' { 'ok' } | Out-Null
    SyntheticEnd $run $a slow-host 1
    $counter = @{ Count=0; Drives=0 }
    Invoke-PtVerificationOperation $a slow-host Drive 'elapsed time is not a stop condition' `
        -Action { param($c) $c.Drives++ } -ArgumentList @($counter) `
        -Cleanup { param($c) $c.Count++ } -CleanupArgumentList @($counter) | Out-Null
    $after = Get-PtVerificationOperationStatus $run slow-host
    Require ($after.ActiveRecoveryTicks -eq 3000000000 -and $after.ActiveRecoverySeconds -eq 300 -and $after.FailureCount -eq 2) 'Threshold/reset arithmetic changed'
    Require ($counter.Count -eq 1 -and $counter.Drives -eq 1 -and -not $after.Blocked) 'Elapsed time stopped a callback or skipped cleanup'
}
Check 'Legacy limits and rejections remain history and never control continued execution' {
    $run=NewRun legacy-policy
    $a=Attempt $run
    Add-PtReportEvent $run OperationPolicyLocked @{OperationKey='legacy-count';MaxFailures=1;MaxRecoverySeconds=300} $a
    SyntheticEnd $run $a legacy-count 1
    $status=Get-PtVerificationOperationStatus $run legacy-count
    Require (-not $status.BudgetEnforced -and -not $status.Blocked -and $status.RecordedPolicies[0].MaxFailures -eq 1) 'Legacy policy was lost or still controls execution'
    Add-PtReportEvent $run OperationRejected @{OperationKey='legacy-count';OperationId='old-rejection';Reason='MaxFailures';Stage='Drive'} $a
    Add-PtReportEvent $run OperationPolicyLocked @{OperationKey='legacy-time';MaxFailures=3;MaxRecoverySeconds=300} $a
    SyntheticEnd $run $a legacy-time 3000000000
    $status=Get-PtVerificationOperationStatus $run legacy-time
    Require (-not $status.BudgetEnforced -and -not $status.Blocked -and $status.RecordedPolicies[0].MaxRecoverySeconds -eq 300) 'Legacy time policy was lost or still controls execution'
    $reopened=Open-PtVerificationRun $run.Workspace
    $next=Attempt $reopened
    foreach($key in 'legacy-count','legacy-time'){
        $result=Invoke-PtVerificationOperation $next $key Drive 'continue old run without old limits' {'continued'} -MaxFailures 0 -MaxRecoverySeconds 0
        Require ($result -ceq 'continued') 'An old policy still blocked a new invocation'
    }
    $status=Get-PtVerificationOperationStatus $reopened legacy-count
    Require ($status.RecordedRejections.Count -eq 1 -and $status.RecordedRejections[0].Reason -eq 'MaxFailures' -and -not $status.Blocked) 'Historical rejection was erased or used as a new lock'
}
Check 'Successful Diagnostic recovery charges callback time, not cleanup, and never resets failures' {
    $run = NewRun recovery
    $a = Attempt $run Diagnostic
    Capture { Invoke-PtVerificationOperation $a host Drive first { throw 'unresolved' } } unresolved | Out-Null
    $before = Get-PtVerificationOperationStatus $run host
    Invoke-PtVerificationOperation $a host Observe recovery { 'recovery observed' } -Cleanup { 'cleanup executed' } | Out-Null
    $end = @(Read-PtReportEvents $run | Where-Object Type -eq OperationEnded)[-1].Data
    $after = Get-PtVerificationOperationStatus $run host
    Require (-not $end.Failed -and $end.RecoveryTicks -gt 0 -and $end.RecoveryTicks -eq $end.ActionDurationTicks) 'Diagnostic recovery time was omitted'
    Require ($after.FailureCount -eq 1 -and $after.ActiveRecoveryTicks -eq $before.ActiveRecoveryTicks + $end.RecoveryTicks) 'Cleanup charged time or recovery reset failures'
}
Check 'Original ErrorRecord survives simultaneous action, cleanup and recorder failures' {
    $run = NewRun triple-error
    $a = Attempt $run
    $holder = @{ Error=$null }
    $savedAppend = (Get-Command Add-PtReportEvent).ScriptBlock
    function Add-PtReportEvent {
        param($Run, [string]$Type, $Data, $Attempt=$null, [string]$StepId='')
        if ($Type -in 'StepEnded','OperationEnded','OperationCleanupEnded') { throw [IO.IOException]::new("injected recorder $Type") }
        & $savedAppend $Run $Type $Data $Attempt $StepId
    }
    try {
        $e = Capture {
            Invoke-PtVerificationOperation $a triple-host Drive 'original failing driver' `
                -Action {
                    param($h)
                    $h.Error = [Management.Automation.ErrorRecord]::new([IO.FileNotFoundException]::new('original driver'),
                        'OriginalDriver', [Management.Automation.ErrorCategory]::ObjectNotFound, 'fixture-target')
                    throw $h.Error
                } -ArgumentList @($holder) -Cleanup { throw [InvalidOperationException]::new('cleanup error') }
        } 'original driver'
    } finally { Set-Item Function:\Add-PtReportEvent $savedAppend }
    Require ([object]::ReferenceEquals($e.Exception, $holder.Error.Exception) -and $e.CategoryInfo.Category -eq 'ObjectNotFound' -and
        $e.TargetObject -ceq 'fixture-target' -and $e.FullyQualifiedErrorId -like 'OriginalDriver*') 'Root ErrorRecord was replaced'
    $data = $e.Exception.Data
    Require ($data['PtVerificationOperation'].Classification -eq 'BLK-INFRASTRUCTURE' -and $data['PtVerificationOperation'].FailureStage -eq 'Drive') 'Root metadata lost'
    Require ($data['PtVerificationCleanupErrors'].Count -eq 1 -and
        $data['PtVerificationCleanupErrors'][0] -is [Management.Automation.ErrorRecord]) 'Full cleanup ErrorRecord lost'
    Require ($data['PtVerificationRecordingErrors'].Count -ge 2 -and
        $data['PtVerificationRecordingErrors'][0] -is [Management.Automation.ErrorRecord]) 'Full surfaced recorder errors lost'
    Require ($data.Contains('PtVerificationRecordingFailure')) 'Existing recorder secondary metadata was erased'
    $history=Get-PtVerificationOperationStatus $run triple-host
    Require ($history.PendingOperations.Count -eq 1 -and -not $history.Blocked) 'Unwritten completion history was lost or became a label lock'
}
Check 'Completely unavailable recorder still runs cleanup once, never drives, and throws its original error' {
    $run = NewRun unavailable-recorder
    $a = Attempt $run
    $counter = @{ Drives=0; Cleanups=0 }
    $savedAppend = (Get-Command Add-PtReportEvent).ScriptBlock
    function Add-PtReportEvent { throw [IO.IOException]::new('journal unavailable') }
    try {
        $e = Capture {
            Invoke-PtVerificationOperation $a unavailable-host Drive command `
                -Action { param($c) $c.Drives++ } -ArgumentList @($counter) `
                -Cleanup { param($c) $c.Cleanups++; 'fallback-cleanup-output' } -CleanupArgumentList @($counter)
        } 'journal unavailable'
    } finally { Set-Item Function:\Add-PtReportEvent $savedAppend }
    Require ($counter.Drives -eq 0 -and $counter.Cleanups -eq 1) 'Unavailable recorder skipped/repeated cleanup or drove'
    Require ($e.Exception.Data['PtVerificationUnrecordedCleanupOutput'][0] -ceq 'fallback-cleanup-output') 'Fallback output lost'
    Require ($e.Exception.Data['PtVerificationRecordingErrors'].Count -ge 2) 'Cleanup recording failures lost'
}
Check 'Recorder failure after a callback remains uncertain evidence, not a permanent key lock' {
    $run = NewRun recording-end
    $a = Attempt $run
    $counter = @{ Count=0 }
    $savedAppend = (Get-Command Add-PtReportEvent).ScriptBlock
    $fault = @{ Once=$true }
    function Add-PtReportEvent {
        param($Run, [string]$Type, $Data, $Attempt=$null, [string]$StepId='')
        if ($Type -eq 'StepEnded' -and $fault.Once) { $fault.Once=$false; throw 'injected end recording failure' }
        & $savedAppend $Run $Type $Data $Attempt $StepId
    }
    try {
        Capture {
            Invoke-PtVerificationOperation $a recording-host Observe command { 'action completed' } `
                -Cleanup { param($c) $c.Count++ } -CleanupArgumentList @($counter)
        } 'injected end recording failure' | Out-Null
    } finally { Set-Item Function:\Add-PtReportEvent $savedAppend }
    $status = Get-PtVerificationOperationStatus $run recording-host
    Require ($counter.Count -eq 1 -and -not $status.Blocked -and $status.UncertainOperations.Count -eq 1 -and $status.FailureCount -eq 0 -and
        $status.ActiveRecoveryTicks -eq 0 -and $status.PendingOperations.Count -eq 0) 'Recorder failure lost its invocation identity or became a label lock'
    $result=Invoke-PtVerificationOperation $a recording-host Observe 'fresh observation, not replay of uncertain action' {'fresh-output'}
    Require ($result -ceq 'fresh-output' -and (Get-PtVerificationOperationStatus $run recording-host).UncertainOperations.Count -eq 1) 'Fresh invocation was blocked or uncertain history was erased'
    Require ((Get-PtReportState $run).Signoff -eq 'WITHHELD') 'Unknown prior execution was silently approved'
}
Check 'Cleanup-only failure never becomes a driver failure, retries cleanup, or invents restoration judgments' {
    $run = NewRun cleanup-error
    $a = Attempt $run
    $counter = @{ Count=0 }
    $e = Capture {
        Invoke-PtVerificationOperation $a host Observe command { 'success' } `
            -Cleanup { param($c) $c.Count++; throw 'cleanup-only failure' } -CleanupArgumentList @($counter)
    } 'cleanup-only failure'
    $status = Get-PtVerificationOperationStatus $run host
    Require ($counter.Count -eq 1 -and $status.FailureCount -eq 0 -and $status.ActiveRecoveryTicks -eq 0) 'Cleanup retried or charged budget'
    Require ($e.Exception.Data['PtVerificationOperation'].FailureStage -eq 'Cleanup') 'Cleanup stage metadata missing'
    $state = Get-PtReportState $run
    Require ($state.Items[0].Category -ceq 'BLK-INFRASTRUCTURE' -and $state.Restoration.Count -eq 0) 'Cleanup became product/restoration judgment'
}
Check 'Pending history survives process reload; actual resource guards control new invocations' {
    $run = NewRun pending
    $a = Attempt $run
    Add-PtReportEvent $run OperationPolicyLocked @{ OperationKey='pending-host'; BudgetEnforced=$false; MaxFailures=$null; MaxRecoverySeconds=$null } $a
    Add-PtReportEvent $run OperationStarted @{
        OperationKey='pending-host'; OperationId='synthetic-interrupted'; Stage='Drive'; Command='Synthetic process interruption'
        Start='2001-01-01T00:00:00Z'; Recovery=$false
    } $a
    $fresh = FreshProcess $run PendingProcess
    Require (-not $fresh.After.Blocked -and $fresh.Drives -eq 1 -and $fresh.Cleanups -eq 2) 'Pending history locked a new operation or bypassed real resource checks'
    Require ($fresh.ErrorId -like '*Owned resource is not restored*' -and
        $fresh.After.PendingOperations[0].OperationId -ceq 'synthetic-interrupted') 'Pending identity or actual guard error was lost'
}
Check 'Final fixed export retains operation events, historical product FAIL and infrastructure classification' {
    $run = NewRun final-export
    $a = Attempt $run
    Capture { Invoke-PtVerificationOperation $a host Drive fail { throw 'driver infrastructure' } } 'driver infrastructure' | Out-Null
    Stop-PtVerificationAttempt $a -Reason 'Preserve driver error'
    $a = Attempt $run
    Invoke-PtVerificationOperation $a host Drive repaired { 'current observation after driver repair' } -Cleanup { 'cleanup exit zero' } | Out-Null
    $evidence=Add-PtVerificationArtifact $a $proof Evidence 'Actual synthetic fixture observed after repair'
    Add-PtVerificationAssertion $a value PASS 'Synthetic fixture comparison' 'Explicit current observation; no counter-based stop.' -Evidence @($evidence)
    Stop-PtVerificationAttempt $a -Reason 'Later same-label observation completed'
    Complete-PtVerificationItem $run L1 -Reason 'Observed after driver repair'
    $b = Attempt $run Normal L2
    Add-PtVerificationAssertion $b value FAIL product 'Synthetic historical product failure; do not erase'
    Invoke-PtVerificationOperation $b independent-host Observe observation { 'successful callback cannot clear a product FAIL' } | Out-Null
    $exportScript = Join-Path $Workspace 'export-script.ps1'
    [IO.File]::WriteAllText($exportScript, '"file execution retained in archive"')
    Invoke-PtVerificationOperation -Attempt $b -OperationKey independent-host -Stage Record `
        -Command 'export-script fixture' -ScriptFile $exportScript | Out-Null
    Stop-PtVerificationAttempt $b -Reason 'Preserve historical judgment'
    $state = Get-PtReportState $run
    Require ($state.Items[0].Verdict -eq 'PASS' -and -not $state.Operations[0].BudgetEnforced) 'Historical driver failure blocked an explicitly observed current result'
    Require ($state.Items[1].Category -eq 'product' -and $state.Items[1].Verdict -eq 'FAIL') 'Operation changed historical product FAIL'
    $export = Complete-PtVerificationRun $run -Retrospective @(@{
        Source='HELPER-FLAW'; Severity='LOW'; Friction='Synthetic H10 error fixtures'
        Cost='Offline deterministic contracts'; SuggestedFix='No product claim; preserve fixture evidence'
    })
    $archive = Test-PtVerificationArchive -Workspace $run.Workspace
    Require ($archive.Valid -and $export.Signoff -eq 'WITHHELD') 'Final synthetic export failed integrity or falsely signed off'
    $saved = ConvertFrom-PtReportJson ([IO.File]::ReadAllText($export.Results))
    Require (-not $saved.Operations[0].Blocked -and $saved.Operations[0].InformationOnly -and
        ([IO.File]::ReadAllText($export.Details)).Contains('No label-based execution locks')) 'Export suggests labels still control execution'
    $operations = @($state.Events | Where-Object Type -like 'Operation*')
    $savedOperations = @($saved.Events | Where-Object Type -like 'Operation*')
    Require ($savedOperations.Count -eq $operations.Count -and
        ($operations | ConvertTo-Json -Depth 30 -Compress) -ceq ($savedOperations | ConvertTo-Json -Depth 30 -Compress)) 'Final export lost or changed operation events'
    Require (@($savedOperations | Where-Object { $_.Type -eq 'OperationEnded' -and $_.Data.TimingSource -eq 'StepActionDurationMs' }).Count -eq 1) 'Final export lost file execution provenance'
    Require ((Get-PtVerificationOperationStatus (Open-PtVerificationRun $run.Workspace) host).FailureCount -eq 1) 'Sealed run lost operation status'
    [pscustomobject]@{ Report=$export.Report; Results=$export.Results; Valid=$archive.Valid; FileCount=$archive.FileCount; OperationEvents=$operations.Count } |
        ConvertTo-Json | Set-Content "$Workspace\archive-validation.json"
}
Check 'Recorder, operation helper, contracts and documentation stayed stable throughout this offline execution' {
    foreach ($source in $sourceHashes) {
        Require ((Get-FileHash -Algorithm SHA256 -LiteralPath $source.Path).Hash -ceq $source.Hash) "Source changed during suite: $($source.Path)"
    }
}
Write-Host "$($results.Count) PASS, 0 FAIL"
Write-Host "Results: $Workspace\results.json"
