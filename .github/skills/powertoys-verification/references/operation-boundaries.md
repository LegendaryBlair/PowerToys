# Recorded operations and cleanup

Dot-source `scripts\pt-verification-report.ps1`, then
`scripts\pt-verification-operation.ps1`. This is an opt-in synchronous wrapper, not a
scheduler, retry loop, product oracle, desktop bootstrap or replacement recorder.
Legacy step/case calls remain valid. Include both helpers in the run's input snapshots.
**Operations have no key-based execution controls.** Every call has its own `OperationId`.
Neither a label, an earlier recording error, an interrupted record nor a legacy policy
locks later invocations. This does not bypass real target/input checks or make unknown
execution evidence trustworthy.

```powershell
Get-PtVerificationOperationStatus -Run $run

Invoke-PtVerificationOperation -Attempt $attempt `
    -Stage Drive `
    -Command $exactCommand -Action $drive -ArgumentList @($ownedFixture) `
    -Cleanup $restore -CleanupArgumentList @($baseline)
```

## APIs and diagnostic accounting

`Get-PtVerificationOperationStatus -Run [-OperationKey]` reads all invocation history, or
filters it by an old label when explicitly supplied. It returns `InformationOnly=true`,
`InvocationCount`, `FirstSeen`, `FailureCount`, `ActiveRecoveryTicks`,
`ActiveRecoverySeconds`, `PendingOperations`, `UncertainOperations`, `RecordingFailures`,
`RecordedPolicies` and `RecordedRejections`. The execution path does not consult this view.

Compatibility fields `Blocked`, `PolicyLocked` and `BudgetEnforced` are always false;
`BlockReason`, `Classification`, `MaxFailures` and `MaxRecoverySeconds` are null.
They are not a permission or readiness check. Old policy values and rejected calls
remain available under `RecordedPolicies` and `RecordedRejections`, not as live rules.

`Invoke-PtVerificationOperation -Attempt -Stage -Command -Action/-ScriptFile
[-ArgumentList] [-Cleanup] [-CleanupArgumentList]` returns the action's original success objects only after
cleanup succeeds. Callbacks receive only their respective argument lists, not an
implicitly prepended attempt. Stages are `Drive`, `Observe`, `Record`.
Use separate, non-nested operation boundaries; ordinary recorded steps may nest inside.
`-Action` and `-ScriptFile` are mutually exclusive. File mode passes `-ScriptFile` and
`-ArgumentList` directly to `Invoke-PtVerificationStep`: the recorder snapshots the source,
then runs its original path with a matching hash and a read lease for that call. Original
script scope, `$PSScriptRoot` and `$PSCommandPath` are preserved. No temporary
wrapper script, caller-local glue or `-Implementation` parameter is needed. For case
integration, the case wrapper continues to prepend its attempt to `ArgumentList`; the
operation wrapper itself does not prepend it.

`Invoke-PtVerificationCase` accepts `-Stage Drive/Observe/Record` and
`-Cleanup`/`-CleanupArgumentList` without an operation key. Supplying these options selects
the recorded operation/cleanup boundary. A case without operation options remains a
normal recorded step.

`OperationKey` is accepted only as an optional legacy label; omit it in new callers.
It is never used for admission, dependency grouping, retries or state recovery.
There is no replacement classification key. Calls without it record an empty label and
are distinguished by `OperationId`, attempt and step IDs. No new `OperationPolicyLocked`
or `OperationRejected` events are generated.

`MaxFailures` and `MaxRecoverySeconds` remain accepted only for caller compatibility.
Supplying them emits a warning that they are retired and ignored;
changing their values cannot create a stop or policy-change error.

Continuing an old unsealed run does not reactivate its limits or label locks.
Historical policy/rejection events and archived reports are not rewritten. A finished
run remains immutable under the recorder's normal completion rules.

For diagnostic accounting:

- Each failed action callback counts once, across all stages, scripts and contexts.
  Successful callbacks do not erase earlier failures or declare a product fix.
- Record the monotonic `Stopwatch` interval inside a failed callback, and inside every
  Diagnostic-kind callback (including successful recovery). Store elapsed TimeSpan ticks
  and sum them without rounding; `ActiveRecoverySeconds` is the exact decimal conversion.
  Successful Normal callbacks add no failed/Diagnostic time. Callback time includes synchronous
  consumption of its output and any waits or nested work inside that callback.
- Exclude time between calls, independent cases, recorder setup/finalization and cleanup.
  Recorder failures outside the callback do not add driver failures. A recording-failed
  invocation is retained as evidence, with its own known/unknown execution state.
- There is no cumulative-count/time cutoff and no automatic retry. Each explicit call
  executes at most once. Keep per-call driver timeouts and exact target/input-ownership
  checks; diagnostic counters are not evidence that a live target is safe or ready.
  These boundaries cannot interrupt a hung synchronous provider call.

For `-ScriptFile`, use the producing step's recorded `ActionDurationMs`, converted back
to TimeSpan ticks, rather than timing the outer recorder call. This interval includes the
recorder's source identity check, synchronous stream processing, error formatting and cleanup, but
excludes source preparation, completion hashing/journal writing and operation cleanup.
`TimingSource` makes this distinction explicit. A completed error step counts as failed
execution (including errors in that execution's stream processing); it is infrastructure,
not evidence of a product failure. Without a step completion the file execution's result
and duration cannot be established: record no guessed failure/time charge and mark that
invocation's evidence as uncertain when execution may have started. A completed
pre-execution source rejection records `ActionStarted=false`, zero action/recovery ticks,
and no driver failure; cleanup still runs. If a step started but has no completion, `ActionStarted` and `ActionDurationTicks` are
null (unknown); if recording failed before the step started, they are false and zero.
Either way the original recorder error is thrown and cleanup still runs, including at
`-Stage Record`. A missing script that never started remains a recorded error, but does
not create an uncertain-execution hold or prevent a corrected invocation.

## Errors and cleanup

Every admitted action uses `Invoke-PtVerificationStep`: exact command, arguments, wrapper
source, original callback implementation and output/error remain in the normal evidence.
`OperationStarted`, `OperationEnded` and `OperationCleanupEnded` append context to that
same journal and survive the existing `Events` export. Legacy rejection/policy events
remain readable, but no rejected-call placeholder step is generated. The helper creates no
assertions, observations, item completions or restoration judgments.

## Journal contract for details and signoff integration

These are ordinary `Add-PtReportEvent` envelopes, retaining the recorder's `Sequence`,
`RunId`, `AttemptId`, `ItemId`, `Phase`, `Timestamp` and hash chain. Fields below are
inside `Data`. Only `OperationStarted` and `OperationEnded` form matched pairs;
rejections have their own invocation ID but deliberately no start/end pair.

| Event type | Data fields |
|---|---|
| `OperationPolicyLocked` | Legacy only; original policy fields are preserved as history. |
| `OperationStarted` | `OperationKey` (empty or legacy label), `OperationId`, `Stage`, `Command`, `Start` (UTC ISO string), `Recovery` (Diagnostic kind), `Execution` (`Action`/`File`) |
| `OperationEnded` | `OperationKey` (empty or legacy label), `OperationId`, `Stage`, `End` (UTC ISO string), `ActionStarted` (bool/null), `Failed` (bool), `ActionDurationTicks` (Int64/null), `RecoveryTicks` (Int64), `StepId` (producing step or empty), `TimingSource` (`CallbackStopwatch`/`StepActionDurationMs`), `RecordingFailed` (bool), `Outcome` (`Completed`/`Error`/`RecordingError`), `Error` (null or `Message`, `ErrorId`, `Category`) |
| `OperationRejected` | Legacy only; original rejection reason and invocation identity are preserved as history. |
| `OperationCleanupEnded` | `OperationKey`, `OperationId`, `Stage` (`Cleanup`), `Outcome` (`Completed`/`Error`), `Error` (message/null), `RestorationVerified` (always false) |

Use the history API to match invocation starts/ends. `PendingOperations` identifies
started invocations with no end. `UncertainOperations` identifies recorded failures
where `ActionStarted` is true or unknown. `RecordingFailures` also includes known
pre-execution errors, which are not execution uncertainty. Missing legacy execution
metadata is treated as unknown, never guessed as success or safe state.

Full `Get-PtReportState` attaches `.Operations` using this status API and withholds signoff
for specific pending/uncertain invocation IDs, without changing item or child verdicts. Export
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

The former budget/policy/recovery-required key rejection errors are no longer generated.
An invalid or completed run, an unavailable recorder, or a real driver/resource guard can
still reject the actual call with its original error.

Cleanup runs on driver error and recording failure. It is
normally a recorded step; if recording fails **before** entering the cleanup callback,
execute that callback directly exactly once. Never rerun a cleanup callback that started.
If the journal is unavailable, throw after this best-effort cleanup; successful fallback
output is retained on the primary exception as `PtVerificationUnrecordedCleanupOutput`
when available. ErrorActionPreference is Stop, including native nonzero exits on supported
PowerShell versions. Explicitly suppressed errors cannot be inferred by the wrapper.
Parameter-binding errors occur before the function body and cannot invoke cleanup.

Cleanup never increments or resets driver-failure history. Exit zero is not restored-state proof:
`OperationCleanupEnded.RestorationVerified` is always false. Record actual comparisons
separately with the existing Normal Cleanup/restoration APIs. An exception from cleanup
is infrastructure, not an automatic restoration FAIL or product judgment.

## Interrupted operations and manual recovery

This inherits the recorder's **single-writer** contract. Close the previous writer before
opening another process; concurrent writers are unsupported. An `OperationStarted` without
its matching end remains incomplete evidence, even when the process merely stopped between
recording the start and entering the callback. No elapsed wall time or result is guessed.

Do not replay the old gesture, forge an end event, edit the journal,
or open a replacement assessment to hide missing execution evidence. Identify the pending
`OperationId`/`AttemptId`, ensure the original writer is no longer acting, inspect owned
state, and perform necessary restoration in an explicit Normal Cleanup attempt with
baseline-comparison evidence. The existing target/input/ownership guards govern each
new action; lack of a label lock is not proof that the desktop or resource is ready.
Keep affected missing coverage explicit and retain the original attempt and evidence.

No label reset is needed: after actual state is checked/restored, a new explicitly
requested invocation gets a new ID and may proceed, including with the same legacy label.
This does not fill the old evidence gap or imply automatic retries. Final signoff can
remain WITHHELD for that missing evidence even though subsequent execution is allowed.
