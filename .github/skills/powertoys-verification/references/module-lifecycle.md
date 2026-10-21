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
Live settings reads use `Read-PtSharedFileText`, permitting product read/write/delete handles.
Sharing does not make the document atomic: parse/schema/read failures remain explicit, never
false disabled/ready state. Receipt-file reads retain their existing immutable-input contract.
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

Capture the [Settings UI baseline](session-safety.md#borrow-settings-before-navigation)
before navigating or making a borrowed Settings window visible. Then navigate/make Settings
visible for the lifecycle operation. The helper refuses a wrong page, minimized window,
disabled/policy-controlled toggle, UI/config mismatch or ambiguous native ownership.
Before a transition it also refuses visible UI owned by the module; the case must first
close only a surface it explicitly owns.
Under an active resource session, it also checks clipboard owner/writer release obligations
before Toggle. Runner-hosted modules check the Runner PID; restart uses the same disable gate.

```powershell
$snapshot = Get-PtModuleLifecycleSnapshot -Profile $profile `
    -SettingsTarget $settingsIdentity -Workspace $workspace
$case = Invoke-PtVerificationCase -Run $run -ItemId $itemId -Name 'Explicit module enable' `
    -Stage Drive -Command 'Enable the declared module through Settings' `
    -ArgumentList @($snapshot) -Action {
        param($attempt,$captured)
        Set-PtModuleEnabled -Snapshot $captured -Enabled $true
    } -CleanupArgumentList @($snapshot) -Cleanup {
        param($captured)
        Restore-PtModuleLifecycleSnapshot -Snapshot $captured
    }
```

Active recorder contexts retain transitions and their actual source/arguments. H10
preserves primary/cleanup errors and diagnostic history without cumulative failure/time
stops or label locks. A timeout does not automatically trigger `Restart-PtModuleLifecycle`.
Record recovery in a separate Diagnostic context; it cannot replace a Normal failure.
When the checklist itself requests an enable cycle, record its individual transitions
as Normal. A module disable/enable cycle is **not** a full PowerToys restart.

The receipt retains original fields and a pending desired state before toggling, using
atomic file replacement. Recover with `Restore-PtModuleLifecycleSnapshot -ReceiptPath`.
Do not deserialize captured timestamps with a lossy reader, alter original targets,
erase failure history or guess ownership after Runner/Settings has restarted.

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
Use this helper for module-local verification. AppX-specific recycling remains a separate
explicit adapter, not a fallback.

## Full PowerToys restart

`Restart-PtRunner` in `scripts/pt-state.ps1` is the **single full PowerToys restart API**.
Runner owns the tray, module loader and shutdown lifecycle; its normal exit also closes
Settings and stops its managed modules/Quick Access. This is not a Windows reboot and
does not promise to keep every module process alive. There is no separate runner-only
restart or `Restart-PowerToys` alias. Use module disable/enable when only that module
needs a lifecycle transition.

| Parameter | Contract |
|---|---|
| `Prepare` | Required callback receiving the captured installation/process/visible-window state and `ArgumentList`. Preserve affected files and logical UI state, settle actual drafts and clipboard dependencies, then return exactly Boolean true. A process being present/enabled does not itself establish an unsafe activity. |
| `VerifyReady` | Required read-only callback receiving the newly observed Runner identity and `ArgumentList`. Check the case's actual Settings/module readiness; return exactly Boolean true or false. False is polled, exceptions propagate. Native tray-host readiness alone does not certify all modules. |
| `RestartAction` | Optional real product action that performs its own complete restart, such as Settings Restart, language Restart or Restart as administrator. Invoked once; failure never falls back to a manual restart. |
| `Launch` | Optional launch adapter for the normal exit/relaunch route, receiving the original state and `ArgumentList`. Required when the driver and original Runner tokens differ; preserve the original user's session/token and executable path. It cannot be combined with `RestartAction`. |
| `OverflowButtonName` | Actual localized hidden-icons button name; defaults to the observed English `Show Hidden Icons`. `SystemTrayIcon` alone is not unique: input indicators and other Shell buttons share it. |
| `ExpectedElevation` | `Preserve` by default. `Elevated`/`NonElevated` require a product `RestartAction`; the helper validates the actual result, never approves UAC or silently elevates. |
| `TimeoutSeconds` | Bound for each exit/readiness observation, not a whole-run cutoff. A timeout does not permit force-kill, action replay or installing different bits. |

The default route is the actual user flow, implemented by `pt-runner-ui.ps1`:

1. Attest one current-session Runner and the installed Start menu shortcut that targets its
   executable, without extra arguments or the Shell Link run-as flag.
2. Resolve the actual `PowerToys v...` tray Button, not Awake or the Settings taskbar button.
   Invoke the typed hidden-icons query's returned selector, not its caption: a visible tooltip
   or text peer can share that caption and make an otherwise valid action ambiguous.
   Open the overflow only when needed. Guard a native right-click with unique live UIA bounds,
   a second bounds read and the exact native root hit receiver; always release the button.
3. Invoke the real Runner-owned menu item with AutomationId `40001` through winapp
   `--action invoke`. Its localized caption can be **Close**, not necessarily **Exit**.
   This ID is used for UIA lookup, never sent as a private window command.
4. Observe the old Runner and its recorded direct children finishing production shutdown.
   Open the attested shortcut through Windows Shell once, then verify the new path/hash,
   session, token and two stable caller-supplied readiness observations.

The current default adapter covers an interactive Windows 11 desktop with medium-integrity
driver/Runner, a visible or overflowed icon and one matching installed shortcut. It refuses
an already-open unowned popup and never changes tray visibility, startup policy or bindings
to manufacture prerequisites. Other taskbar providers/locales need their actual supported
locator; elevation-sensitive cases use the real product `RestartAction`.

winapp supplies discovery and menu Invoke; the gesture uses the existing native taskbar
input primitive. This avoids depending on a transient CLI slug or on UIA point lookup exposing
a child Button inside a composed Shell surface. Native input is outside winapp's arbitration:
keep UI driving serial, use the same workflow ID for cooperating CLI calls and retain hit
guards. There is no force-foreground trick, `WM_CLOSE`/`WM_COMMAND` exit shortcut, default
`Start-Process`, forced child shutdown, fixed installation path or fixed startup sleep.
Ordinary production exit can flush cached settings: apply preferences through supported UI
instead of using restart to conceal an ineffective direct edit to root JSON.

`Invoke-PtRunnerTrayCommand` also provides the actual Settings/Quick Access menu actions.
Its optional read-only `Observe` callback runs before owned overflow cleanup, because closing
that popup can deactivate Quick Access. An invoked command is not proof of its outcome.
Overflow cleanup uses the captured closed-button caption, current popup visibility and a
guarded physical chevron click. It skips input if the popup has already closed, checks the
live bounds/native hit receiver and verifies disappearance. Do not substitute an unconditional
second UIA Invoke or Escape focused on the taskbar: those were not reliable on the tested Shell.
Pointer cleanup is attempted independently even if popup dismissal fails.
Do not automatically acknowledge arbitrary startup dialogs; preserve and report them.

Supply real preparation/readiness callbacks, not constant success stubs. The operation belongs
inside the existing recorded case/step:

```powershell
# Both callbacks come from the case's declared preservation/readiness plan.
$restart = Restart-PtRunner -Prepare $prepareRestart -VerifyReady $observeRestartReadiness `
    -ArgumentList @($fixtureContext)
# For a specified UI route, add -RestartAction $invokeActualRestartControl instead.
```

The receipt records `Before`, `After`, route, action/launch progress and
`InvalidatePriorReferences`. On error, `Exception.Data['RunnerRestartReceipt']` preserves the
partial progress; keep it with the original error and perform the declared cleanup. Rediscover
module/Settings HWNDs and controls even if a numeric PID/HWND is reused. A successful restart
is not a file/draft restoration receipt or a product assertion.

For borrowed main Settings that must survive **logically**, opt in before capturing the run
baseline with a Settings resource's `AllowRunnerRestart=true` (or
`Get-PtSettingsUiSnapshot -AllowRunnerRestart` for a manual resource session). The common
operation records the authorized transition. In the declared cleanup, pass the independently
identified new main window to
`Restore-PtSettingsUiSnapshot -Snapshot $original -ReplacementIdentity $newMainIdentity`.
It verifies same installation/session and a new creation after the restart, restores supported
page/scroll/placement and records the replacement separately. The immutable original snapshot
is not rewritten. The template's subsequent restore/final comparison uses that replacement,
including original Settings foreground restoration.

Other borrowed windows and explicit same-process-lifetime resources still need their actual
preservation contract; this opt-in does not discard unknown drafts, waive clipboard ownership
or turn all new module processes into disposable owned fixtures. Prefer a logical `Other`
resource with paired cleanup for processes expected to change, rather than a declaration that
the old process must remain alive. Do not label restart itself destructive or skip an entire
module because unrelated ordinary PowerToys processes exist. Report the specific unresolved
state/permission instead. Windows reboot, installer replacement and corruption fixtures remain
separate boundaries.

For a restartable borrowed companion, declare its exact HWND/path and a real logical-state
cleanup step **before capture**:

```powershell
@{Id='quick-access';Kind='Window';Ownership='Borrowed';Hwnd=$qaIdentity.hwnd
  FilePath=$qaExecutable;AllowRunnerRestart=$true;RestoreStep='restore-qa-logical-state'}
```

`Register-PtBorrowedWindow` records that original contract. After the common restart,
`Register-PtRestartedWindow -OriginalIdentity $qaIdentity -ReplacementIdentity $newQaIdentity`
verifies the authorized installation/session/creation transition. The window remains borrowed,
not disposable; its plan's cleanup must separately restore and verify page, cloak/visibility,
preferences and any other declared state. Existing verified replacements remain usable after
a later failed restart attempt; an unknown new HWND still requires fresh transition evidence.

`scripts\tests\Test-PtRunnerRestart.ps1` covers the contract with failure injection and an
actual hidden native fixture supplied through `RestartAction`. It does not exercise a real
tray or restart the installed product. `Test-PtRunnerTray.ps1` checks the tray command protocol;
live acceptance must additionally prove the real gesture/menu/shortcut sequence and cleanup.
Session/resource/template tests cover Settings/companion replacement authorization, immutable
baselines and logical restoration.
