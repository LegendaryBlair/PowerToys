#requires -Version 7.0
<#
.SYNOPSIS
Optional, synchronous obstacle boundaries backed only by the verification event journal.
Dot-source pt-verification-report.ps1 first. No desktop helpers are loaded.
#>

function Get-PtVerificationOperationStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][ValidatePattern('(?-i)^[a-z0-9][a-z0-9._:-]{0,127}$')][string]$OperationKey
    )
    $events = @(Read-PtReportEvents $Run | Where-Object {
        $_.Type -in 'OperationPolicyLocked','OperationStarted','OperationEnded' -and
        $_.Data.OperationKey -ceq $OperationKey
    })
    $policies = @($events | Where-Object Type -eq 'OperationPolicyLocked')
    if ($policies.Count -gt 1) { throw "Duplicate operation policy: $OperationKey" }
    $policy = if ($policies.Count) { $policies[0].Data } else { $null }
    $starts = @($events | Where-Object Type -eq 'OperationStarted')
    $ends = @($events | Where-Object Type -eq 'OperationEnded')
    if (($starts.Count -or $ends.Count) -and -not $policy) { throw "Missing operation policy: $OperationKey" }
    $finished = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $failures = 0
    $ticks = 0L
    foreach ($end in $ends) {
        if (-not $finished.Add($end.Data.OperationId) -or
            @($starts | Where-Object { $_.Data.OperationId -ceq $end.Data.OperationId -and $_.Sequence -lt $end.Sequence }).Count -ne 1 -or
            $end.Data.RecoveryTicks -lt 0) { throw "Invalid operation completion: $OperationKey" }
        if ($end.Data.Failed) { $failures++ }
        $ticks += [long]$end.Data.RecoveryTicks
    }
    $pending = @($starts | Where-Object { -not $finished.Contains($_.Data.OperationId) } | ForEach-Object {
        [pscustomobject]@{ OperationId=$_.Data.OperationId; AttemptId=$_.AttemptId; Stage=$_.Data.Stage; Start=$_.Data.Start }
    })
    $seconds = [decimal]$ticks / [TimeSpan]::TicksPerSecond
    $reason = if ($pending.Count) { 'Interrupted' }
        elseif (@($ends | Where-Object { $_.Data.RecordingFailed }).Count) { 'RecordingError' }
        elseif ($policy -and $failures -ge $policy.MaxFailures) { 'MaxFailures' }
        elseif ($policy -and $seconds -ge $policy.MaxRecoverySeconds) { 'MaxRecoverySeconds' }
        else { $null }
    [pscustomobject]@{
        OperationKey=$OperationKey; PolicyLocked=[bool]$policy
        MaxFailures=$(if ($policy) { $policy.MaxFailures } else { $null })
        MaxRecoverySeconds=$(if ($policy) { $policy.MaxRecoverySeconds } else { $null })
        FirstSeen=$(if ($policies.Count) { $policies[0].Timestamp } else { $null })
        FailureCount=$failures; ActiveRecoveryTicks=$ticks; ActiveRecoverySeconds=$seconds
        PendingOperations=$pending; Blocked=[bool]$reason; BlockReason=$reason
        Classification=$(if ($reason) { 'BLK-INFRASTRUCTURE' } else { $null })
    }
}

function Invoke-PtVerificationOperation {
    [CmdletBinding(DefaultParameterSetName = 'Action')]
    param(
        [Parameter(Mandatory, Position = 0)]$Attempt,
        [Parameter(Mandatory, Position = 1)][ValidatePattern('(?-i)^[a-z0-9][a-z0-9._:-]{0,127}$')][string]$OperationKey,
        [Parameter(Mandatory, Position = 2)][ValidateSet('Drive','Observe','Record')][string]$Stage,
        [Parameter(Mandatory, Position = 3)][ValidateNotNullOrEmpty()][string]$Command,
        [Parameter(Mandatory, Position = 4, ParameterSetName = 'Action')][scriptblock]$Action,
        [Parameter(Mandatory, ParameterSetName = 'File')][ValidateNotNullOrEmpty()][string]$ScriptFile,
        [object[]]$ArgumentList = @(),
        [scriptblock]$Cleanup,
        [object[]]$CleanupArgumentList = @(),
        [ValidateRange(1,2147483647)][int]$MaxFailures = 3,
        [ValidateRange(1,2147483647)][int]$MaxRecoverySeconds = 300
    )
    $ErrorActionPreference = 'Stop'
    $PSNativeCommandUseErrorActionPreference = $true
    $Stage = switch ($Stage) { Drive { 'Drive' }; Observe { 'Observe' }; Record { 'Record' } }
    $run = $Attempt.Run
    $operationId = [Guid]::NewGuid().ToString('N')
    $root = $null
    $failureStage = 'Record'
    $failureKind = 'Recording'
    $recordingErrors = [Collections.Generic.List[object]]::new()
    $cleanupErrors = [Collections.Generic.List[object]]::new()
    $output = @()
    $ptOperationState = @{ Started=$false; Error=$null; Ticks=0L; StepId='' }
    $ptOperationAction = $Action
    # Unique names let the recorded callback share state without serializing mutable handles.
    $callback = {
        $ptOperationState.Started = $true
        $ptOperationState.StepId = $Attempt.StepStack[-1]
        $ptOperationClock = [Diagnostics.Stopwatch]::StartNew()
        try { & $ptOperationAction @args }
        catch { $ptOperationState.Error = $_; throw }
        finally { $ptOperationClock.Stop(); $ptOperationState.Ticks = $ptOperationClock.Elapsed.Ticks }
    }
    try {
        $status = Get-PtVerificationOperationStatus -Run $run -OperationKey $OperationKey
        if ($Attempt.Closed -or $run.IsCompleted) { throw 'An open verification run and attempt are required.' }
        $rejection = $null
        if ($status.PolicyLocked -and (
            ($PSBoundParameters.ContainsKey('MaxFailures') -and $MaxFailures -ne $status.MaxFailures) -or
            ($PSBoundParameters.ContainsKey('MaxRecoverySeconds') -and $MaxRecoverySeconds -ne $status.MaxRecoverySeconds))) {
            $rejection = 'PolicyChanged'
        } elseif ($status.Blocked) { $rejection = $status.BlockReason }
        if (-not $status.PolicyLocked) {
            Add-PtReportEvent $run 'OperationPolicyLocked' @{
                OperationKey=$OperationKey; MaxFailures=$MaxFailures; MaxRecoverySeconds=$MaxRecoverySeconds
            } $Attempt
        }
        if ($rejection) {
            $failureKind = $rejection
            $failureStage = $Stage
            $id = switch ($rejection) {
                PolicyChanged { 'PtVerificationOperationPolicyChanged' }
                { $_ -in 'Interrupted','RecordingError' } { 'PtVerificationOperationRecoveryRequired' }
                default { 'PtVerificationOperationBudgetExceeded' }
            }
            $category = if ($rejection -eq 'PolicyChanged') { [Management.Automation.ErrorCategory]::InvalidArgument }
                elseif ($rejection -in 'Interrupted','RecordingError') { [Management.Automation.ErrorCategory]::ResourceUnavailable }
                else { [Management.Automation.ErrorCategory]::LimitsExceeded }
            $root = [Management.Automation.ErrorRecord]::new(
                [InvalidOperationException]::new("BLK-INFRASTRUCTURE: operation '$OperationKey' rejected at ${Stage}: $rejection. Cleanup remains required."),
                $id, $category, $OperationKey)
            Add-PtReportEvent $run 'OperationRejected' @{
                OperationKey=$OperationKey; OperationId=$operationId; Stage=$Stage; Command=$Command
                Reason=$rejection; Classification='BLK-INFRASTRUCTURE'
                FailureCount=$status.FailureCount; ActiveRecoveryTicks=$status.ActiveRecoveryTicks
            } $Attempt
            # A real error step makes rejection visible to the existing infrastructure reducer.
            $ptOperationRejection = $root
            Invoke-PtVerificationStep -Attempt $Attempt -Name "$Stage rejected: $OperationKey" `
                -Command "Rejected before execution: $Command" -Action { throw $ptOperationRejection } | Out-Null
        } else {
            Add-PtReportEvent $run 'OperationStarted' @{
                OperationKey=$OperationKey; OperationId=$operationId; Stage=$Stage; Command=$Command
                Start=[DateTimeOffset]::UtcNow.ToString('o'); Recovery=($Attempt.Kind -eq 'Diagnostic')
                Execution=$PSCmdlet.ParameterSetName
            } $Attempt
            $stepSequence = $run.Sequence
            try {
                $execution = if ($PSCmdlet.ParameterSetName -eq 'File') { @{ ScriptFile=$ScriptFile } }
                    else { @{ Action=$callback; Implementation=$Action } }
                $output = @(Invoke-PtVerificationStep -Attempt $Attempt -Name "${Stage}: $OperationKey" `
                    -Command $Command @execution -ArgumentList $ArgumentList)
            } catch {
                if ($ptOperationState.Error) {
                    $root = $ptOperationState.Error
                    $failureStage = $Stage
                    $failureKind = 'Action'
                    if (-not [object]::ReferenceEquals($_.Exception, $root.Exception)) { $recordingErrors.Add($_) }
                } else {
                    $root = $_
                    if ($PSCmdlet.ParameterSetName -ne 'File') { $recordingErrors.Add($_) }
                }
            }
            if ($PSCmdlet.ParameterSetName -eq 'File') {
                # Execute the recorder's immutable snapshot unchanged; use its execution interval.
                $stepEvents = @(Read-PtReportEvents $run | Where-Object {
                    $_.Sequence -gt $stepSequence -and $_.AttemptId -ceq $Attempt.Id
                })
                $start = @($stepEvents | Where-Object Type -eq 'StepStarted' | Select-Object -First 1)
                $end = @($stepEvents | Where-Object { $_.Type -eq 'StepEnded' -and $start.Count -and $_.StepId -ceq $start[0].StepId })
                if ($start.Count) { $ptOperationState.StepId = $start[0].StepId }
                if ($end.Count -eq 1) {
                    $ptOperationState.Started = $true
                    $ptOperationState.Ticks = [long][Math]::Round($end[0].Data.ActionDurationMs * [TimeSpan]::TicksPerMillisecond)
                    if ($root -and $end[0].Data.Status -eq 'Error') {
                        $ptOperationState.Error = $root; $failureStage = $Stage; $failureKind = 'Action'
                    } elseif ($root) { $recordingErrors.Add($root) }
                } else {
                    if (-not $root) { throw 'File execution lacks a recorded step completion.' }
                    $ptOperationState.Started = if ($start.Count) { $null } else { $false }
                    $ptOperationState.Ticks = if ($start.Count) { $null } else { 0L }
                    $recordingErrors.Add($root)
                }
            }
            $recordingFailed = $recordingErrors.Count -gt 0 -or
                ($root -and $root.Exception.Data.Contains('PtVerificationRecordingFailure')) -or
                ($root -and $root.Exception.Data.Contains('PtVerificationErrorCaptureFailure'))
            $charge = $ptOperationState.Error -or $Attempt.Kind -eq 'Diagnostic'
            Add-PtReportEvent $run 'OperationEnded' @{
                OperationKey=$OperationKey; OperationId=$operationId; Stage=$Stage; End=[DateTimeOffset]::UtcNow.ToString('o')
                ActionStarted=$ptOperationState.Started; Failed=[bool]$ptOperationState.Error
                ActionDurationTicks=$ptOperationState.Ticks
                RecoveryTicks=$(if ($charge -and $null -ne $ptOperationState.Ticks) { $ptOperationState.Ticks } else { 0L })
                StepId=$ptOperationState.StepId
                TimingSource=$(if ($PSCmdlet.ParameterSetName -eq 'File') { 'StepActionDurationMs' } else { 'CallbackStopwatch' })
                RecordingFailed=[bool]$recordingFailed
                Outcome=$(if ($recordingFailed) { 'RecordingError' } elseif ($root) { 'Error' } else { 'Completed' })
                Error=$(if ($root) { @{ Message=$root.Exception.Message; ErrorId=$root.FullyQualifiedErrorId; Category=[string]$root.CategoryInfo.Category } } else { $null })
            } $Attempt
        }
    } catch {
        if (-not $root) { $root = $_ }
        if (-not [object]::ReferenceEquals($_.Exception, $root.Exception) -or $failureKind -eq 'Recording') {
            $recordingErrors.Add($_)
        }
    } finally {
        if ($Cleanup) {
            $ptOperationCleanupState = @{ Started=$false; Error=$null }
            $ptOperationCleanupAction = $Cleanup
            $cleanupCallback = {
                $ptOperationCleanupState.Started = $true
                try { & $ptOperationCleanupAction @args }
                catch { $ptOperationCleanupState.Error = $_; throw }
            }
            $unrecordedOutput = @()
            try {
                Invoke-PtVerificationStep -Attempt $Attempt -Name "Cleanup: $OperationKey" `
                    -Command $Cleanup.ToString() -Action $cleanupCallback -Implementation $Cleanup `
                    -ArgumentList $CleanupArgumentList | Out-Null
            } catch {
                if ($ptOperationCleanupState.Error) {
                    $cleanupErrors.Add($ptOperationCleanupState.Error)
                    if (-not $root) {
                        $root = $ptOperationCleanupState.Error; $failureStage = 'Cleanup'; $failureKind = 'Cleanup'
                    }
                    if (-not [object]::ReferenceEquals($_.Exception, $ptOperationCleanupState.Error.Exception)) { $recordingErrors.Add($_) }
                } else {
                    $recordingErrors.Add($_)
                    if (-not $root) { $root = $_; $failureStage = 'Record'; $failureKind = 'Recording' }
                }
                if (-not $ptOperationCleanupState.Started) {
                    # Only a pre-execution recorder failure permits this unrecorded, once-only fallback.
                    try { $unrecordedOutput = @(& $cleanupCallback @CleanupArgumentList) }
                    catch { $cleanupErrors.Add($_) }
                }
            }
            try {
                Add-PtReportEvent $run 'OperationCleanupEnded' @{
                    OperationKey=$OperationKey; OperationId=$operationId; Stage='Cleanup'
                    Outcome=$(if ($cleanupErrors.Count) { 'Error' } else { 'Completed' })
                    Error=$(if ($cleanupErrors.Count) { $cleanupErrors[0].Exception.Message } else { $null })
                    RestorationVerified=$false
                } $Attempt
            } catch {
                $recordingErrors.Add($_)
                if (-not $root) { $root = $_; $failureStage = 'Record'; $failureKind = 'Recording' }
            }
            if ($root -and $unrecordedOutput.Count) { $root.Exception.Data['PtVerificationUnrecordedCleanupOutput'] = $unrecordedOutput }
        }
    }
    if ($root) {
        $root.Exception.Data['PtVerificationOperation'] = @{
            OperationKey=$OperationKey; OperationId=$operationId; Stage=$Stage
            FailureStage=$failureStage; FailureKind=$failureKind; Classification='BLK-INFRASTRUCTURE'
        }
        $root.Exception.Data['PtVerificationCleanupErrors'] = @($cleanupErrors | Where-Object {
            -not [object]::ReferenceEquals($_.Exception, $root.Exception)
        })
        $root.Exception.Data['PtVerificationRecordingErrors'] = @($recordingErrors | Where-Object {
            -not [object]::ReferenceEquals($_.Exception, $root.Exception)
        })
        $PSCmdlet.ThrowTerminatingError($root)
    }
    foreach ($value in $output) { $PSCmdlet.WriteObject($value, $false) }
}
