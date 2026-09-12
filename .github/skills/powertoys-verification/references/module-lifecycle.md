# Explicit module lifecycle

Use `scripts/pt-module-lifecycle.ps1` in PowerShell 7.2+. The helper reads native state
and changes only an explicitly addressed Settings module toggle. It does not kill
processes, restart Runner, activate a module, edit JSON or retry a failed transition.
Application code may itself terminate its child when a user disables it; the helper
does not replace that shipped UI flow with its own process control.

## Declare the model

Profiles are data, not per-run callbacks:

```powershell
$profile = @{
    Id = 'example-module'
    ModuleKey = '<exact enabled key>'
    PageAutomationId = '<selected Settings navigation ID>'
    ToggleName = '<observed toggle name>' # Or ToggleAutomationId, not both.
    Model = 'Resident'
    ProcessName = '<exe basename without extension>'
    ProcessPath = '<absolute installed exe path>'
    WindowClass = '<native host class>'
    Events = @(
        @{ Name='<catalog name or full Local\ event>'; WhenEnabled='Present'; WhenDisabled='Ignore' }
    )
}
```

Optional `WithinAutomationId` scopes duplicate toggle identifiers. Optional
`SettingsPath` selects another absolute general-settings file for an isolated fixture;
normal verification uses `%LOCALAPPDATA%\Microsoft\PowerToys\settings.json`.
Event rules require explicit `Present`, `Absent` or `Ignore` for both configured states.
An unknown/missing setting is an error, not `false`.

| Model | Meaning |
|---|---|
| `Resident` | One exact process name/path in Runner's session. Enabled requires that process and any declared host/events; disabled requires the process and declared host to exit. |
| `RunnerHosted` | No independent process. Requires a module-owned `WindowClass` under the same Runner; enabled/disabled waits for that host to appear/disappear and checks declared events. |
| `OnDemand` | Configuration-only lifecycle. Optional process/path observations do not imply that enabling starts a UI process. Results are `ConfiguredEnabled`/`ConfiguredDisabled`, never runtime Ready. Explicit restart is unsupported. |

`Ready` means **only the declared native contract**. It does not prove initialized
content, a working hotkey, a listening event consumer or rendered pixels. Use H07/H08
and the case's actual behavior assertions separately.

Kernel event existence is not listener liveness. For example, SG's Runner-loaded DLL
creates its trigger event in its constructor, so the event can survive module disable.
Its profile uses `WhenDisabled=Ignore`; process/host exit establishes the stop condition.
Event access errors and wrong object types throw instead of appearing as absence.

## APIs

| API | Contract |
|---|---|
| `Get-PtModuleLifecycleState -Profile` | Strict read of configured Boolean, Runner identity, matching processes/hosts and event observations. Returns Status, RuntimeReady, SatisfiesNativeContract, Scope and concrete Issues. |
| `Wait-PtModuleLifecycle -Profile -Enabled [-ExpectedRunner] [-TimeoutSeconds]` | Poll for configured state plus declared native conditions, requiring two consecutive stable process/host observations. Ambiguity/observation errors throw; timeout retains `LifecycleLastObservation`. |
| `Get-PtModuleLifecycleSnapshot -Profile -SettingsTarget -Workspace` | Verify selected Settings page, usable TogglePattern and UI/config agreement; persist original enabled/native state and exact targets before mutation. |
| `Set-PtModuleEnabled -Snapshot -Enabled [-TimeoutSeconds]` | Perform at most one UI toggle, then wait and read back. Matching configuration does not authorize a restart; unhealthy matching state still fails readiness. |
| `Restart-PtModuleLifecycle -Snapshot -Reason [-TimeoutSeconds]` | Explicit disabled/enabled cycle, allowed only in an active **Diagnostic** attempt and on an enabled, runtime-backed module. Never changes Runner identity. |
| `Restore-PtModuleLifecycleSnapshot -Snapshot/-ReceiptPath [-TimeoutSeconds]` | Restore the original enabled state, including a partially completed transition. ReceiptPath uses the lossless JSON reader internally. |

State labels include `Ready`, `Disabled`, `ConfiguredEnabled`, `ConfiguredDisabled`,
`TransitioningOrUnavailable` and `Ambiguous`. Use `SatisfiesNativeContract` and `Scope`
explicitly; never treat a nonnull state object or enabled flag as readiness.

Transitions return `Before`, `After`, `Changed`, `RequestedEnabled`,
`InvalidatePriorReferences` and the receipt path. Discard prior process/HWND/UIA
references after **every** transition, even if a handle value is later recycled.
Use returned identities for subsequent observations. A restored enabled module may
have a new process/window; restoring an old PID or private in-memory state is not claimed.

An access-denied error from `Process.HasExited` is a **probe failure**, not proof that
the UI toggle failed or the module crashed. Preserve the original error and inspect
the saved enabled flag before repeating a transition. A separate read-only CIM query
scoped to the recorded PID/session, together with native host observations, can establish
what actually changed. Record that alternative as Diagnostic evidence; do not silently
replace the lifecycle result, elevate the session, or restart unrelated utilities.
Cleanup must still restore the original enabled value through the shipped toggle and
record an explicit comparison even when the lifecycle probe cannot complete.

The process probe now opens one `PROCESS_QUERY_LIMITED_INFORMATION` (`0x1000`)
handle per candidate. It reads creation time and the full executable path on that
handle, not `Process.HasExited` (which additionally requests `SYNCHRONIZE`) or
`MainModule` (module enumeration requests query/VM-read rights). Fresh process
enumeration supplies the session and confirms presence while the handle pins the PID.
An actual exit code other than `STILL_ACTIVE`, or confirmed absence from enumeration,
is exit evidence; `STILL_ACTIVE` alone is not, since a process can also exit with code
259. A disappearing image (native error 31) requires independent exit confirmation.
Access denied is never converted to exit, including during that confirmation.

Required same-name/current-session candidates that cannot be queried stop observation
with `PtLifecycleProcess.ReadError`. `Exception.Data['LifecycleProcessObservation']`
records the stage, native error code, candidate PID/session, observed start/path/session
when available, expected path and requested access. The original exception remains in
the inner-exception chain; a failed secondary exit confirmation is retained on the
native exception as `LifecycleExitConfirmationFailure`. No partial process set or
ready/disabled state is returned. A same-name candidate with an unreadable path cannot
be assumed unrelated. Readable wrong-path/other-session instances are excluded; all
exact matches are retained so ambiguity still fails. A new start time resets the
existing two-observation stability check even when the PID is reused.

## Paired use and error boundaries

Navigate/make Settings visible first. The helper refuses a wrong page, minimized window,
disabled/policy-controlled toggle, UI/config mismatch or ambiguous native ownership.
Before a transition it also refuses visible UI owned by the module; the case must first
close only a surface it explicitly owns.

```powershell
$snapshot = Get-PtModuleLifecycleSnapshot -Profile $profile `
    -SettingsTarget $settingsIdentity -Workspace $workspace
$case = Invoke-PtVerificationCase -Run $run -ItemId $itemId -Name 'Explicit module enable' `
    -OperationKey "lifecycle-$($profile.Id)" -Stage Drive -Command 'Enable the declared module through Settings' `
    -ArgumentList @($snapshot) -Action {
        param($attempt,$captured)
        Set-PtModuleEnabled -Snapshot $captured -Enabled $true
    } -CleanupArgumentList @($snapshot) -Cleanup {
        param($captured)
        Restore-PtModuleLifecycleSnapshot -Snapshot $captured
    }
```

Active recorder contexts retain transitions and their actual source/arguments. H10
owns shared failure budgets and primary/cleanup error preservation; cleanup is not
budget-gated. A timeout does not automatically trigger `Restart-PtModuleLifecycle`.
Record recovery in a separate Diagnostic context; it cannot replace a Normal failure.
When the checklist itself requests an enable cycle, record its individual transitions
as Normal. A module disable/enable cycle is **not** a full PowerToys restart.

The receipt retains original fields and a pending desired state before toggling, using
atomic file replacement. Recover with `Restore-PtModuleLifecycleSnapshot -ReceiptPath`.
Do not deserialize captured timestamps with a lossy reader, alter original targets,
reset budgets or guess ownership after Runner/Settings has restarted.

## Restoration scope and acceptance

The helper restores the configured enabled state and observes the current native
contract. Caller-owned cleanup includes Settings navigation/window lifetime, original
file bytes, native desktop state and module-specific startup side effects.

Module profiles must identify startup-written files. Capture directory **bytes**,
declare exact relative-path ownership and use H04 conflict-aware rollback after the
writers finish; see the [SG profile](modules/shortcut-guide.md) for its manifest/index
side effects. Unchanged user settings do not imply unchanged generated files.
Opening a Settings page may also serialize away retired fields; retain the original
files and perform authorized byte rollback only after preserving current semantics/
classifying the exact migration and closing the owned writer.

```powershell
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtModuleLifecycle.ps1" -Workspace <new-folder>
pwsh -NoProfile -STA -File "$skill\scripts\tests\Test-PtInstalledModuleLifecycle.ps1" `
    -Workspace <new-folder> -SettingsHwnd <owned-settings-hwnd>
```

The first command is offline with respect to PowerToys and the desktop. It includes
one short-lived, no-window child with a temporarily restricted process DACL, reproduces
the old `HasExited` access denial, verifies limited-rights identity and structured
required-access denial, and restores the DACL before the child exits. It also covers
exiting candidates, PID reuse, path/session filtering, ambiguity and error provenance;
`results.json` and `native-probe-evidence.json` are written to the new workspace.

The installed acceptance uses SG (`Resident`) and Find My Mouse (`RunnerHosted`),
does not invoke either module's feature, and leaves its recorded run open for the
caller's final file/directory/desktop cleanup and fixed report finalization.
Use this helper instead of the legacy force-killing `Restart-PtRunner` for module-local
verification. AppX-specific recycling remains a separate explicit adapter, not a fallback.
