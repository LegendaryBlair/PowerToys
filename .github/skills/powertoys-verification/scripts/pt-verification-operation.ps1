#requires -Version 7.0
<#
.SYNOPSIS
Optional, synchronous error/cleanup boundaries backed only by the verification event journal.
Dot-source pt-verification-report.ps1 first. No desktop helpers are loaded.
#>

function Get-PtVerificationOperationStatus {
    <# .SYNOPSIS
    Read invocation history, optionally filtered by a legacy label. Never grants or denies execution.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Run,
        [AllowEmptyString()][string]$OperationKey
    )
    $filterByLabel = $PSBoundParameters.ContainsKey('OperationKey')
    $events = @(Read-PtReportEvents $Run | Where-Object {
        $_.Type -in 'OperationPolicyLocked','OperationStarted','OperationEnded','OperationRejected' -and
        (-not $filterByLabel -or [string]$_.Data.OperationKey -ceq $OperationKey)
    })
    $policies = @($events | Where-Object Type -eq 'OperationPolicyLocked')
    $starts = @($events | Where-Object Type -eq 'OperationStarted')
    $ends = @($events | Where-Object Type -eq 'OperationEnded')
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
        [pscustomobject]@{ OperationId=$_.Data.OperationId; AttemptId=$_.AttemptId; Stage=$_.Data.Stage; Start=$_.Data.Start; Reason='Interrupted' }
    })
    $uncertain = @($ends | Where-Object { $_.Data.RecordingFailed -and $_.Data.ActionStarted -ne $false } | ForEach-Object {
        [pscustomobject]@{ OperationId=$_.Data.OperationId; AttemptId=$_.AttemptId; Stage=$_.Data.Stage
            StepId=$_.Data.StepId; Reason='RecordingError'; ActionStarted=$_.Data.ActionStarted }
    })
    $seconds = [decimal]$ticks / [TimeSpan]::TicksPerSecond
    [pscustomobject]@{
        OperationKey=$OperationKey; InformationOnly=$true; InvocationCount=$starts.Count
        RecordedPolicies=@($policies | ForEach-Object { $_.Data })
        RecordedRejections=@($events | Where-Object Type -eq OperationRejected | ForEach-Object {
            [pscustomobject]@{ OperationId=$_.Data.OperationId; Reason=$_.Data.Reason; Timestamp=$_.Timestamp }
        })
        PolicyLocked=$false; BudgetEnforced=$false; MaxFailures=$null; MaxRecoverySeconds=$null
        FirstSeen=$(if ($events.Count) { $events[0].Timestamp } else { $null })
        FailureCount=$failures; ActiveRecoveryTicks=$ticks; ActiveRecoverySeconds=$seconds
        PendingOperations=$pending; UncertainOperations=$uncertain
        RecordingFailures=@($ends | Where-Object { $_.Data.RecordingFailed } | ForEach-Object { $_.Data })
        Blocked=$false; BlockReason=$null; Classification=$null
    }
}

function Invoke-PtVerificationOperation {
    [CmdletBinding(DefaultParameterSetName = 'Action')]
    param(
        [Parameter(Mandatory, Position = 0)]$Attempt,
        [Parameter(Position = 1)][AllowEmptyString()][string]$OperationKey = '',
        [Parameter(Mandatory, Position = 2)][ValidateSet('Drive','Observe','Record')][string]$Stage,
        [Parameter(Mandatory, Position = 3)][ValidateNotNullOrEmpty()][string]$Command,
        [Parameter(Mandatory, Position = 4, ParameterSetName = 'Action')][scriptblock]$Action,
        [Parameter(Mandatory, ParameterSetName = 'File')][ValidateNotNullOrEmpty()][string]$ScriptFile,
        [object[]]$ArgumentList = @(),
        [scriptblock]$Cleanup,
        [object[]]$CleanupArgumentList = @(),
        # Compatibility arguments for callers of the retired cumulative-limit API.
        [int]$MaxFailures,
        [int]$MaxRecoverySeconds
    )
    $ErrorActionPreference = 'Stop'
    $PSNativeCommandUseErrorActionPreference = $true
    $Stage = switch ($Stage) { Drive { 'Drive' }; Observe { 'Observe' }; Record { 'Record' } }
    $run = $Attempt.Run
    $operationId = [Guid]::NewGuid().ToString('N')
    $operationName = if ($OperationKey) { "${Stage}: $OperationKey" } else { "$Stage operation $operationId" }
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
        Assert-PtReportAttempt $Attempt
        if ($PSBoundParameters.ContainsKey('MaxFailures') -or $PSBoundParameters.ContainsKey('MaxRecoverySeconds')) {
            Write-Warning 'Cumulative operation limits are retired. MaxFailures/MaxRecoverySeconds are ignored, including when continuing legacy runs.'
        }
        Add-PtReportEvent $run 'OperationStarted' @{
            OperationKey=$OperationKey; OperationId=$operationId; Stage=$Stage; Command=$Command
            Start=[DateTimeOffset]::UtcNow.ToString('o'); Recovery=($Attempt.Kind -eq 'Diagnostic')
            Execution=$PSCmdlet.ParameterSetName
        } $Attempt
        $stepSequence = $run.Sequence
        try {
            $execution = if ($PSCmdlet.ParameterSetName -eq 'File') { @{ ScriptFile=$ScriptFile } }
                else { @{ Action=$callback; Implementation=$Action } }
            $output = @(Invoke-PtVerificationStep -Attempt $Attempt -Name $operationName `
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
            # Preserve the recorder's original-path execution and recorded interval.
            $stepEvents = @(Read-PtReportEvents $run | Where-Object {
                $_.Sequence -gt $stepSequence -and $_.AttemptId -ceq $Attempt.Id
            })
            $start = @($stepEvents | Where-Object Type -eq 'StepStarted' | Select-Object -First 1)
            $end = @($stepEvents | Where-Object { $_.Type -eq 'StepEnded' -and $start.Count -and $_.StepId -ceq $start[0].StepId })
            if ($start.Count) { $ptOperationState.StepId = $start[0].StepId }
            if ($end.Count -eq 1) {
                $ptOperationState.Started = if ($end[0].Data.PSObject.Properties['ActionStarted']) { $end[0].Data.ActionStarted } else { $true }
                $ptOperationState.Ticks = if ($ptOperationState.Started) {
                    [long][Math]::Round($end[0].Data.ActionDurationMs * [TimeSpan]::TicksPerMillisecond)
                } else { 0L }
                if ($root -and $end[0].Data.Status -eq 'Error' -and $ptOperationState.Started) {
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
                Invoke-PtVerificationStep -Attempt $Attempt -Name "Cleanup operation $operationId" `
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
