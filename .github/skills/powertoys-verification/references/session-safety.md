# Run-local resource safety and cleanup

This is a layer over the existing recorder, identities and module adapters, not a second
engine, scheduler or OS sandbox. Use it in the **same runspace** as UI driving. Imports do
not capture the desktop. `New-PtResourceSession -Run` captures pre-existing native windows
and process IDs; `Open-PtResourceSession -Run` resumes its original receipt, not a new baseline.
The thin run template opens this layer before Preflight and completes it during Cleanup.

## Mandatory wiring for aligned module runs

Color Picker, Workspaces, Shortcut Guide and Environment Variables Scenario A entry requires `-ResourcePlan`
and `-CleanupPlan`; the legacy free-form `-Cleanup` callback is rejected for these runs.
This validation happens **before run creation or driving**. Declare only resources actually
used by the selected work; a non-clipboard scope does not need a clipboard fixture.

```powershell
$resources = @{
    Schema = 'PtRunResources.v1'
    Resources = @(
        @{ Id='settings-ui'; Kind='Settings'; Hwnd=$settingsHwnd }
        @{ Id='module-file'; Kind='File'
           RestoreStep='module-file-restore' }
        @{ Id='editor'; Kind='Window'; Ownership='Owned'
           RestoreStep='owned-editor-close' }
    )
}
```

Each resource has a unique `Id` and a `Kind` (`Settings`, `Window`, `Process`, `File`, `Clipboard`, `Other`).
Every non-Settings resource maps `RestoreStep` to a real cleanup step with both `Action`
and `Verify`; Clipboard requires phase `Clipboard`, and Window requires explicit
`Ownership=Borrowed/Owned`. A Settings resource requires its known positive HWND and
uses the template's built-in adapter, not a substitute cleanup callback.
For a case that explicitly restarts PowerToys, a main Settings resource can declare
`AllowRunnerRestart=$true` before capture. This preserves supported logical UI state across
the authorized replacement instead of promising that the original HWND survives. It does
not preserve arbitrary drafts; settle those in the restart preparation.
Headless/helper processes use `Kind='Process'`, `Ownership='Owned'`, an absolute `FilePath`,
and a `Quiesce` cleanup step. Pass the plan to `New-PtResourceSession -ResourcePlan` when not
using the template, so the original process identities are captured before activation.

The template derives Settings targets from this plan. If `-SettingsHwnd` is also supplied,
it must match exactly. Resume retains the same saved plan and original snapshots.
Undeclared clipboard capture and dedicated owned-process launch are refused.
Identity checks and fixture-specific ownership validators still apply; a declaration alone
does not grant window ownership or prove that an arbitrary callback restores state.

Use the same template for the actual module driver, not only its smoke test.
`Test-PtRunResourcePlan.ps1` covers missing/mismatched wiring without accessing Settings
or clipboard. `Test-PtInstalledSettingsSession.ps1` exercises this entry with the installed
Settings HWND and run-local file/UI comparisons.

## Ownership and release

| API | Required contract |
|---|---|
| `Register-PtBorrowedWindow -Identity` | Existing Settings/Editor/Welcome windows remain borrowed. Identity proves which object, not permission to close it. |
| `Register-PtRestartedWindow -OriginalIdentity -ReplacementIdentity` | Only an originally restartable borrowed Window resource with exact HWND/path and logical cleanup can bind a new same-installation/session instance after the recorded Runner transition. Does not grant termination ownership or certify logical restoration. |
| `Start-PtOwnedProcess -FilePath -ArgumentList [-Lifetime Case/Run]` | Persist launch intent before starting a dedicated fixture process. Require a new PID and its actual start time; shared-host or broker launches need a dedicated adapter. Arguments follow `Start-Process` quoting rules. |
| `Invoke-PtOwnedProcessActivation -FilePath -Action [-ArgumentList]` | For a declared Process executable, run one explicit broker/COM activation and record the new exact identity. Refuse an existing singleton and ambiguous multiple processes. No activation retry or ownership by name alone. |
| `Stop-PtOwnedProcess -Creation -RequestExit [-ArgumentList]` | Check recorded PID/start time/image path, clipboard dependencies and every native sibling before calling the supplied shutdown protocol once. Wait for actual exit; protocol errors or timeout remain failures. No automatic force-kill fallback. |
| `Register-PtCreatedWindow -Identity -Creation` | Exact PID/start match to a recorded launch; baseline HWNDs cannot become owned. Register every owned native sibling that a process-wide close might affect, including hidden helper windows. |
| `Close-PtTrackedWindow -Identity` | In an active resource session, require explicit ownership and satisfied clipboard dependencies before WM_CLOSE. Reject an unowned same-process sibling. |
| `Invoke-PtOwnedWindowReopen -Identity -Creation -ResolveHwnd` | Close a launch-owned window, observe process exit, launch a new instance and resolve its new HWND. Does not close/recreate borrowed Settings or adopt a packaged shared host. |
| `Assert-PtProcessRelease -ProcessId` | Refuse owner/writer release while a registered clipboard obligation is unresolved. The lifecycle helper checks before disable; restart passes through the same check. |
| `Complete-PtResourceSession -Attempt` | Record actual owned-window/process absence, borrowed identity preservation, clipboard status and fresh Settings comparison in Normal Cleanup. No automatic close, kill or full-desktop success claim. |

Declare the PowerToys extension executable before a Command Palette test that can activate it,
not only the visible palette window. The final comparison also detects new surviving processes
of that exact declared executable which lack a creation record. Such a gap blocks restoration;
it does not authorize adopting or killing them. Existing singleton processes remain borrowed.
Do not claim whole-run restoration from a subset of file/window receipts, or delete private
recovery material while an owned helper still has an unresolved cleanup obligation.

```powershell
@{Id='companion-provider';Kind='Process';Ownership='Owned'
  FilePath=$providerExecutable;RestoreStep='provider-exit'}
# The Quiesce step uses the verified creation plus the provider's authorized shutdown protocol:
Stop-PtOwnedProcess -Creation $providerCreation -RequestExit $requestProviderExit
```

Run `scripts\tests\Test-PtOwnedProcess.ps1` for actual no-window fixture launch/exit coverage
without an interactive desktop. Synthetic contract tests also cover stale identities,
clipboard/sibling guards, failed shutdown, indirect activation and unregistered survivors.

Notepad, Explorer and Calculator retain their existing ownership validators. Their receipt
bridge cannot adopt a pre-run HWND. Explorer/Calculator adapters authorize **window-only**
closure; they do not own Explorer/ApplicationFrameHost processes. A modern Notepad tab
continues to use its tab-specific adapter. Never replace these contracts with `Get-Process`
by name, blanket close or `Stop-Process`.

No active resource session preserves legacy helper behavior; that is compatibility, not
equivalent protection. Direct native calls or raw UIA Close are outside these guards.
Do not bypass a refusal. Restore prerequisites or block only the dependent operation.

## Borrow Settings before navigation

Pass explicit `-SettingsHwnd` values to the run template, or call
`Get-PtSettingsUiSnapshot -Hwnd -Workspace` **before the first page change**. It records
native identity, full WINDOWPLACEMENT (including minimized normal placement), visibility,
selected `*NavItem`, uniquely named expansion states and uniquely named ScrollPatterns.
`Restore-PtSettingsUiSnapshot` restores and reads back the same window, without launching
or closing Settings. The first snapshot per HWND remains the run baseline across retries.

`Invoke-PtSettingsScope -Hwnd -Workspace -Action` is the small paired borrow/restore driver.
The action receives the exact Settings identity. It preserves action errors and reports
restoration errors separately. Foreground/pointer remain the enclosing desktop scope's
responsibility; the template captures/restores them when `-SettingsHwnd` is supplied.

Missing/ambiguous selected pages or duplicate stable control IDs refuse the baseline,
before navigation. Unnamed/unexposed scroll or expansion state, IME composition/conversion,
keyboard focus and unsaved drafts are explicitly **unsupported**, not silently restored.
If a case requires preserving such state, defer that mutation or supply separately proven
evidence. Synchronous UIA provider calls are not made timeout-safe by polling.

Installed WinUI can unload its automation subtree after minimize/restore. Missing selection
is therefore polled for bounded readiness during an authorized observation; ambiguity still
throws. The adapter restores the navigation viewport before resolving virtualized items and
avoids redundant Expand/Collapse calls. It restores original native layout before applying
the saved scroll percentages.
Minimized-from-maximized placement is surfaced as maximized, not at the saved normal
rectangle. The read path reacquires the same identity-checked HWND at most twice on the
specific `ElementNotAvailableException`, recording a warning each time; access denial and
other provider errors still propagate. This retries observation only, never the UI action.

`Get-PtSettingsCurrentState -Hwnd -AllowTemporaryRestore` explicitly surfaces a minimized
or hidden borrowed Settings window for a fresh observation, then restores its full native
placement, foreground and pointer in `finally`. This is **not visually side-effect-free**:
it temporarily shows Settings, but must leave no net desktop change. Snapshot/restoration
and the final resource comparison use this paired operation rather than claiming that
missing minimized UIA data matches a stale receipt.

Completion re-reads supported Settings state after the last lifecycle operation. A prior
successful receipt does not cover a later navigation. Settings close/reopen assertions
require a genuinely owned launch; an existing Settings window is not expendable.

For declared full PowerToys restarts, use the existing
[`Restart-PtRunner`](module-lifecycle.md#full-powertoys-restart), not a direct kill/relaunch.
The original Settings snapshot remains immutable. An opted-in snapshot can be restored with
`Restore-PtSettingsUiSnapshot -Snapshot $snapshot -ReplacementIdentity $newMainIdentity`
after independently resolving the new main. The helper checks its executable/session,
creation time and class against the recorded transition; completion then checks logical
state on that replacement. The template also remaps an originally foreground Settings
window to that verified replacement without altering the original desktop baseline.
Without the original opt-in, same-instance preservation remains mandatory.

Quick Access and other companions can use an originally declared borrowed Window resource
with `AllowRunnerRestart=true`, exact `Hwnd`/`FilePath` and a real `RestoreStep`; see the
[full restart contract](module-lifecycle.md#full-powertoys-restart). Do not register a cloaked
companion as permanently same-instance when the case explicitly tests a complete restart.
Retain original and replacement identities separately and verify the companion's logical
state in that step. A successful identity handover alone is not a page/state comparison.

Settings restoration reveals an unrealized rail only for an authorized replacement, then
restores navigation/expansion and final placement before applying percentages to the settled
scroll extent. A changed extent can require one explicit reapplication; an unchanged extent
never triggers a blind replay. An already-correct visible window is compared without refocusing
or rewriting it. WinUI scroll comparison accepts the original raw percentage or exactly its
float32 command readback, not a decimal tolerance or a rounded bucket. Real scroll drift and
every other UI difference still fail, and the immutable original percentages remain intact.

## Cleanup dependencies

Prefer `-CleanupPlan` to the legacy template `-Cleanup` callback. They are mutually exclusive.
Each step has `Id`, `Phase`, `DependsOn`, `Action`, `Verify` and optional `Arguments`.
Arguments are passed to both blocks. Supply complete explicit dependencies for shared
resources; a successful callback alone cannot establish restoration.

Phases are ordered:
`Input -> Clipboard -> Ui -> Quiesce -> Files -> Lifecycle -> Windows -> Verify`.
Every dependency must identify an earlier step. A failed action/comparison blocks dependent
steps, but independent steps still run. `Verify` must return **exactly Boolean true**;
strings, empty output and truthy objects fail. Each step produces its own restoration row
and evidence; the plan throws after collecting all outcomes if anything remains unresolved.

```powershell
$plan = @(
    @{ Id='clipboard'; Phase='Clipboard'; DependsOn=@(); Arguments=@($guard)
       Action={param($g) $g.Restore(); Assert-PtClipboardRestored $g}
       Verify={param($g) $g.Restored -is [bool] -and $g.Restored} }
    @{ Id='writer'; Phase='Quiesce'; DependsOn=@('clipboard'); Arguments=@($lifecycle)
       Action={param($s) Set-PtModuleEnabled $s $false | Out-Null}
       Verify={param($s) (Get-PtModuleLifecycleState $s.Profile).Status -eq 'Disabled'} }
)
# Add module-specific guarded file rollback, original enablement, owned-window cleanup,
# and final comparisons; the two steps alone are not a complete restoration plan.
```

Live clipboard payload stays in memory; only obligation metadata is persisted. Register
intended writers **before** copying with `Invoke-PtClipboardWrite`. Shared-desktop runs
use `New-PtClipboardSession`'s separate STA keeper and sealed-action confirmation.
Disposal is refused until restoration. After ordinary controller exit, open the original
resource session and reconnect with `Connect-PtClipboardSession -ReceiptPath`; only a
still-live keeper can supply the original. A receipt alone cannot resurrect memory lost
when the keeper itself was terminated. See the [clipboard contract](clipboard-guard.md).

## Independent runs and interrupted work

Each module run captures the actual starting state of **every resource it will touch**,
including borrowed/shared Settings, clipboard, foreground and fixtures, not only its own
settings file. Its cleanup must restore that baseline and produce fresh comparisons.
Returning from `finally` without an error is not proof of restoration.

If cleanup fails, preserve the original snapshots and identify the unresolved resource in
that run's report/error. The sequential caller must resolve it before further work that
depends on the resource; independent work need not be blocked. The next module performs
its own normal preflight. It does not read another run's state digests, import its baseline
or automatically roll back changes made between runs. Earlier reports remain unchanged.

Within one run, use per-case cleanup and incremental review between groups. Do not throw
an exception merely to pause for screenshot review: that exits the template and triggers
final cleanup/export. `-Resume` is for an actual interruption of the **same** unsealed run,
and must retain its original resource plan and baselines rather than snapshotting dirty
current state as a replacement.

## Acceptance scope

`Test-PtSessionContracts.ps1` exercises ownership refusal, stale/tampered receipts,
clipboard dependencies, missing live backups on resume, Settings failure cleanup and
dependency continuation with synthetic objects.
`Test-PtRunTemplate.ps1` covers recorder/template cleanup, independent run baselines,
same-run recovery, preservation of foreign changes, errors and export.
`Test-PtSessionDesktop.ps1` uses owned WPF Settings/Welcome-like windows to exercise real
navigation, expansion, scrolling, minimized placement, clipboard gates and owned reopen.
`Test-PtPrimitiveDesktop.ps1` covers multi-format clipboard and physical scoped capture.
Both live clipboard suites require explicit `-DisposableClipboard` in a disposable session;
use `-SkipClipboard` for Settings-only acceptance. Native fault injection and controller
exit/reconnection are tested offline by `Test-PtClipboardRecovery.ps1` and
`Test-PtClipboardKeeper.ps1`.

These tests are harness acceptance, **not Color Picker, Workspaces or Shortcut Guide
verification**. They do not establish a heterogeneous-monitor/DPI matrix, IME restoration,
all native clipboard allocation failures, crash recovery or real WinUI-provider compatibility.
