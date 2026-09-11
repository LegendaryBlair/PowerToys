# Optional operation boundaries

Dot-source `scripts\pt-verification-report.ps1`, then
`scripts\pt-verification-operation.ps1`. This is an opt-in synchronous wrapper, not a
scheduler, retry loop, product oracle, desktop bootstrap or replacement recorder.
Legacy step/case calls remain valid. Include both helpers in the run's input snapshots.

```powershell
Get-PtVerificationOperationStatus -Run $run -OperationKey 'explorer.context-menu-host'

Invoke-PtVerificationOperation -Attempt $attempt `
    -OperationKey 'explorer.context-menu-host' -Stage Drive `
    -Command $exactCommand -Action $drive -ArgumentList @($ownedFixture) `
    -Cleanup $restore -CleanupArgumentList @($baseline)
```

## APIs and budget

`Get-PtVerificationOperationStatus -Run -OperationKey` replays the existing journal
(using the recorder's validated read/cache). It returns `PolicyLocked`, `MaxFailures`,
`MaxRecoverySeconds`, `FirstSeen`, `FailureCount`, `ActiveRecoveryTicks`,
`ActiveRecoverySeconds`, `PendingOperations`, `Blocked`, `BlockReason` and
`Classification`, plus the key. An unused key has no policy or budget expenditure.
This is operation state, not archive-integrity or product-verdict validation.

`Invoke-PtVerificationOperation -Attempt -OperationKey -Stage -Command -Action/-ScriptFile
[-ArgumentList] [-Cleanup] [-CleanupArgumentList] [-MaxFailures 3]
[-MaxRecoverySeconds 300]` returns the action's original success objects only after
cleanup succeeds. Callbacks receive only their respective argument lists, not an
implicitly prepended attempt. Stages are `Drive`, `Observe`, `Record`; all are gated.
Use separate, non-nested operation boundaries; ordinary recorded steps may nest inside.
`-Action` and `-ScriptFile` are mutually exclusive. File mode passes `-ScriptFile` and
`-ArgumentList` directly to `Invoke-PtVerificationStep`: the recorder executes its immutable
snapshot, preserving the existing script-scope and `$PSScriptRoot` contract. No temporary
wrapper script, caller-local glue or `-Implementation` parameter is needed. For case
integration, the case wrapper continues to prepend its attempt to `ArgumentList`; the
operation wrapper itself does not prepend it.

`Invoke-PtVerificationCase` accepts optional `-OperationKey`, `-Stage Drive/Observe/Record`,
`-Cleanup`/`-CleanupArgumentList`, and `-MaxFailures`/`-MaxRecoverySeconds`. With a key it
uses this boundary for either Action or ScriptFile and forwards only explicitly supplied
limits. Without a key, legacy case execution remains unchanged.

Name the **shared obstacle**, not the script, attempt, item or Normal/Diagnostic context.
Keys are case-sensitive lowercase ASCII, 1-128 characters: first character alphanumeric,
then alphanumerics, `.`, `_`, `:`, `-`. Do not invent another key to evade a stop.
The first invocation appends `OperationPolicyLocked`. Limits are positive integer counts
and seconds. Later omitted limits **inherit the locked policy**; explicitly different
limits reject the call. This is the only refinement of the proposed default semantics.
Policy, failures and time survive new attempts and `Open-PtVerificationRun` in another
PowerShell process. Only `events.jsonl` holds state; there is no sidecar budget file.

For the same unresolved obstacle:

- Each failed action callback counts once, across all stages, scripts and contexts.
  Successful callbacks do not reset earlier failures and do not declare resolution.
- Charge the monotonic `Stopwatch` interval inside a failed callback, and inside every
  Diagnostic-kind callback (including successful recovery). Store elapsed TimeSpan ticks
  and sum them without rounding; `ActiveRecoverySeconds` is the exact decimal conversion.
  Successful Normal callbacks cost no recovery time. Callback time includes synchronous
  consumption of its output and any waits or nested work inside that callback.
- Exclude time between calls, independent cases, recorder setup/finalization and cleanup.
  Put only work addressing this obstacle inside its callback; do not enclose a whole run.
  Recorder failures outside the callback do not add driver failures. A recording-failed
  operation instead requires manual recovery because its completion is not trustworthy.
- Check `FailureCount >= MaxFailures` or `ActiveRecoverySeconds >= MaxRecoverySeconds`
  **before the next call**. A callback may cross the threshold and finish; there is no
  claim to interrupt a hung synchronous callback. There is no whole-run 30-minute cutoff.

For `-ScriptFile`, use the producing step's recorded `ActionDurationMs`, converted back
to TimeSpan ticks, rather than timing the outer recorder call. This interval includes the
recorder's synchronous stream processing, error formatting and formatter disposal, but
excludes source preparation, completion hashing/journal writing and operation cleanup.
`TimingSource` makes this distinction explicit. A completed error step counts as failed
execution (including errors in that execution's stream processing); it is infrastructure,
not evidence of a product failure. Without a step completion the file execution's result
and duration cannot be established: record no guessed failure/time charge and block the
key as `RecordingError`. If a step started, `ActionStarted` and `ActionDurationTicks` are
null (unknown); if recording failed before the step started, they are false and zero.
Either way the original recorder error is thrown and cleanup still runs, including at
`-Stage Record`.

## Errors and cleanup

Every admitted action uses `Invoke-PtVerificationStep`: exact command, arguments, wrapper
source, original callback implementation and output/error remain in the normal evidence.
`OperationStarted`, `OperationEnded`, `OperationRejected` and `OperationCleanupEnded`
append context to that same journal and survive the existing `Events` export. Rejections
also execute a recorded *throw-only* step, never the requested action, so the existing
reducer sees infrastructure rather than a product failure. The helper creates no
assertions, observations, item completions or restoration judgments.

## Journal contract for details and signoff integration

These are ordinary `Add-PtReportEvent` envelopes, retaining the recorder's `Sequence`,
`RunId`, `AttemptId`, `ItemId`, `Phase`, `Timestamp` and hash chain. Fields below are
inside `Data`. Only `OperationStarted` and `OperationEnded` form matched pairs;
rejections have their own invocation ID but deliberately no start/end pair.

| Event type | Data fields |
|---|---|
| `OperationPolicyLocked` | `OperationKey`, `MaxFailures`, `MaxRecoverySeconds` |
| `OperationStarted` | `OperationKey`, `OperationId`, `Stage`, `Command`, `Start` (UTC ISO string), `Recovery` (Diagnostic kind), `Execution` (`Action`/`File`) |
| `OperationEnded` | `OperationKey`, `OperationId`, `Stage`, `End` (UTC ISO string), `ActionStarted` (bool/null), `Failed` (bool), `ActionDurationTicks` (Int64/null), `RecoveryTicks` (Int64), `StepId` (producing step or empty), `TimingSource` (`CallbackStopwatch`/`StepActionDurationMs`), `RecordingFailed` (bool), `Outcome` (`Completed`/`Error`/`RecordingError`), `Error` (null or `Message`, `ErrorId`, `Category`) |
| `OperationRejected` | `OperationKey`, `OperationId`, `Stage`, `Command`, `Reason`, `Classification`, `FailureCount`, `ActiveRecoveryTicks` |
| `OperationCleanupEnded` | `OperationKey`, `OperationId`, `Stage` (`Cleanup`), `Outcome` (`Completed`/`Error`), `Error` (message/null), `RestorationVerified` (always false) |

Discover distinct keys from `OperationPolicyLocked` and call
`Get-PtVerificationOperationStatus -Run -OperationKey` for each; do not independently
reimplement budget accumulation or pending-operation matching in the renderer.
`Blocked` is operation-level infrastructure status, not a product judgment. Its
`BlockReason` is `Interrupted`, `RecordingError`, `MaxFailures` or `MaxRecoverySeconds`
(in that precedence), or null. An explicit policy-change rejection does not alter status
or limits; its event `Reason` is `PolicyChanged`. Other rejection reasons match the
status reason. `PendingOperations` supplies `OperationId`, `AttemptId`, `Stage`, `Start`.
An interrupted or recording-failed status withholds overall signoff without
changing product assertions or historical verdicts. Missing `Execution`, `StepId` or
`TimingSource` on older operation events does not affect the status reducer.

Full `Get-PtReportState` attaches `.Operations` using this status API and withholds signoff
for `Interrupted` or `RecordingError`, without changing item or child verdicts. Export
retains every operation event. `details.md` includes an Operation boundaries table and
event/error trace; the compact report adds only a short link/count when operations exist.
Successful archive validation proves integrity, not operation completion or product PASS.

## Exception contract

The primary exception is rethrown using its original `ErrorRecord`; its category,
identity, stack and invocation information are not replaced with a generic wrapper.
`Exception.Data['PtVerificationOperation']` carries `OperationKey`, `OperationId`,
requested `Stage`, `FailureStage` (`Drive`/`Observe`/`Record`/`Cleanup`),
`FailureKind`, and `Classification = BLK-INFRASTRUCTURE`.
Additional full ErrorRecords that the wrapper receives are attached in
`PtVerificationCleanupErrors` and `PtVerificationRecordingErrors`. Existing recorder
error-capture/recording-failure metadata is retained as-is, including when that recorder
version supplies only a message rather than a secondary ErrorRecord.

Generated stop errors have these stable ErrorId prefixes (PowerShell may append the
function name to `FullyQualifiedErrorId`); their `TargetObject` is the stable key:

| ErrorId | Category | Meaning |
|---|---|---|
| `PtVerificationOperationBudgetExceeded` | `LimitsExceeded` | Failure or active-time threshold reached. |
| `PtVerificationOperationPolicyChanged` | `InvalidArgument` | Explicit limits differ from the first-use policy. |
| `PtVerificationOperationRecoveryRequired` | `ResourceUnavailable` | Same key has an unfinished or recording-failed operation. |

Cleanup runs even on budget/policy rejection, driver error and recording failure. It is
normally a recorded step; if recording fails **before** entering the cleanup callback,
execute that callback directly exactly once. Never rerun a cleanup callback that started.
If the journal is unavailable, throw after this best-effort cleanup; successful fallback
output is retained on the primary exception as `PtVerificationUnrecordedCleanupOutput`
when available. ErrorActionPreference is Stop, including native nonzero exits on supported
PowerShell versions. Explicitly suppressed errors cannot be inferred by the wrapper.
Parameter-binding errors occur before the function body and cannot invoke cleanup.

Cleanup never charges or resets the driver budget. Exit zero is not restored-state proof:
`OperationCleanupEnded.RestorationVerified` is always false. Record actual comparisons
separately with the existing Normal Cleanup/restoration APIs. An exception from cleanup
is infrastructure, not an automatic restoration FAIL or product judgment.

## Interrupted operations and manual recovery

This inherits the recorder's **single-writer** contract. Close the previous writer before
opening another process; concurrent writers are unsupported. An `OperationStarted` without
its matching end is `Blocked / Interrupted`, even when the process merely stopped between
recording the start and entering the callback. Any recorded `RecordingFailed` completion
also blocks that key. No elapsed wall time is guessed for an interrupted callback.

Do not resume the old gesture, forge an end event, edit the journal, rename the obstacle,
or open a replacement assessment run to reset its budget. Identify the pending
`OperationId`/`AttemptId`, ensure the original writer is no longer acting, inspect owned
state, and perform necessary restoration in an explicit Normal Cleanup attempt with
baseline-comparison evidence. A rejected call's cleanup can perform the same necessary
restoration, but cannot clear the block. Record affected coverage as
`BLOCKED / BLK-INFRASTRUCTURE` using the existing judgment APIs and retain the interrupted
attempt and historical evidence. Continue only truly independent keys.

There is deliberately no reset/resume API: even successful manual cleanup does not prove
an interrupted action's missing result or erase an exhausted obstacle. Further dependent
driving is stopped for this assessment. The caller owns reviewing actual readiness,
affected coverage and cleanup evidence; final export may correctly remain WITHHELD.
Raw recorder calls remain available for restoration/reporting after an operation stop.
