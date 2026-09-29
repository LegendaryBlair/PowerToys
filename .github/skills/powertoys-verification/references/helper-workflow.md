# Reliable driving and paired restoration

## Canonical capability inventory

Color Picker, Workspaces and Shortcut Guide use this same engine baseline. A profile move
does not align product versions or fixtures: still record the installed bits and run inputs.
Do not load helpers from another worktree to fill an unresolved dependency.

| Capability | Canonical WIP surface | Consolidation decision / boundary |
|---|---|---|
| Run, step and assertion records | `pt-verification-report.ps1`, operation/render helpers | Keep one recorder and explicit subassertion inventory; do not import CP `New-PtRecordedRun` or its second archive model. |
| Window identity and physical geometry | `pt-desktop.ps1`, `pt-state-snapshot.ps1` | Keep lowercase `hwnd/processId/processStartTicks/className`; a native window record has no `ProcessName` field. Identity is not ownership. |
| Controls, values and shortcut recording | `pt-uia.ps1`, `pt-ui-observation.ps1`, `pt-shortcut-recorder.ps1` | Keep typed scoped resolution and the existing recorder; no CP `Resolve-PtUiControl` / `Set-PtScopedToggle` wrapper. |
| Input and module lifecycle | existing chord/held-key/foreground/lifecycle helpers | Explicit operations, no automatic Runner restart; active-session clipboard dependencies gate disable/restart. |
| Live settings reads | `pt-file-io.ps1` | Shared read/write/delete handles prevent readers blocking normal writers; not a guarantee of an atomic, fully settled JSON document. |
| File and directory restoration | `pt-state-snapshot.ps1`, `pt-directory-snapshot.ps1` | Reuse snapshot shape. Explicit `-ExpectedState` adds guarded existing-file rollback; directory rollback handles owned existence changes. Legacy unguarded calls are not concurrency-safe. |
| Clipboard preservation | `pt-clipboard-guard.ps1`/`.cs`, `pt-clipboard-session.ps1` | Native preservation, sealed pending writes and a separate STA keeper across ordinary controller exit; no private payload on disk. Formats-only inspection is not backup. |
| Scoped passive capture | `Save-PtPassiveScreenshot -WindowIdentity` | Reuse capture API with an optional physical union for owner/popup identities; no separate CP capture wrapper. |
| Owned application/taskbar fixtures | existing owned-fixture and taskbar helpers | Keep module-specific adapters. Never adopt a user window because its PID/HWND can be observed. |
| Ownership, Settings and cleanup | `pt-session-safety.ps1`, `pt-settings-session.ps1`, `pt-cleanup-plan.ps1` | Persist borrowed/created resources, supported original Settings UI state and explicit cleanup dependencies; use the [session safety contract](session-safety.md). |
| Stable assertions | `pt-assertion-inventory.ps1` | [Reviewed source-bound inventories](assertion-inventories/README.md), not run-local child generation. |

`pt-state.ps1` remains a legacy convenience surface. New workflows use the strict lifecycle
reader for enablement, not `Test-PtModuleEnabled`'s missing-value fallback, and do not call
`Restart-PtRunner` or force-copy `Restore-PtModuleSettings` as generic recovery. Retaining
old callers is compatibility, not an endorsement of their weaker ownership/restore behavior.

The thin template enables resource protection before Preflight. Supply Settings HWNDs
**before navigation**, explicit cleanup dependencies and comparisons against this run's
original snapshots. Outside the template, open the resource session explicitly. IME, unsaved drafts,
unexposed controls and arbitrary direct native calls remain outside its guarantees.
Report unresolved cleanup resources explicitly and resolve them before subsequent dependent
work. Each module performs its own preflight and verified cleanup; there is no cross-run
state protocol. These are scoped common capabilities, not a second orchestration framework.

Use PowerShell 7 on Windows. These are small reusable operations, not a scheduler or a
replacement for a module's checklist. Keep UI driving serial on one desktop.
Read the [recording workflow](recording-workflow.md) before discovery; wrap every native
winapp call with `Invoke-PtWinApp` and activate a recording attempt.
Use `Get-PtVerificationReview` between groups of observations, not the full export/state
validator. Keep `Actual`/assertion `Reason` concise and attach large raw output with
`Add-PtVerificationObservation -Detail`; never serialize a whole UIA tree into report prose.

## Load and check the driver before mutation

```powershell
Get-ChildItem "$skill\scripts" -Filter '*.ps1' |
    Where-Object Name -ne 'pt-session-diagnose.ps1' | ForEach-Object { . $_.FullName }
foreach ($name in 'Wait-PtCondition','Invoke-PtWinApp','Save-PtPassiveScreenshot',
    'Invoke-PtHeldKeys','Get-PtDesktopSnapshot','Restore-PtDesktopSnapshot') {
    Get-Command $name -ErrorAction Stop | Out-Null
}
```

Initialize helpers in the actual driver script/runspace; another process does not inherit
imports. If a separately invoked phase needs named events, dot-source `pt-shared-events.ps1`
there and inspect `Get-PtSharedEventCatalog` before signaling. A script-scope catalog failure
is a driver initialization error, not a missing module.

Use `Get-PtVerificationInputs -Skill $skill -Inputs $explicitInputs` when creating the
run. It includes the real `SKILL.md`, every top-level `.ps1`/`.cs` helper source and
the keeper's `scripts\hosts\clipboard-keeper.ps1` entry point
loaded by this bootstrap; native companion files must not be omitted. Supply the checklist,
profile, driver and actually used reference/asset files in `$explicitInputs`. The thin
run template calls this helper automatically. Keep inputs immutable during the run.
Use `ConvertFrom-PtReportJson` for identity/receipt JSON so timestamps and Int64 fields
retain the engine's agreed representation.

Run `pt-session-diagnose.ps1` as a recorded preflight step. Probe the actual module's
entry path and one normal open/close flow before a batch. Do not use a failed precondition
to continue sending input into subsequent cases. Readiness/driver errors are not product
assertions, and a diagnostic restart does not prove ordinary reopen behavior.

## Discover, wait, and invalidate

| Helper | Contract |
|---|---|
| `Get-PtNativeWindow [-Hwnd] [-ProcessId] [-ClassName] [-Visible]` | Filters PID/class before reading full native properties. Disappearing-window error 1400 is skipped only during enumeration; explicit stale HWNDs and other errors throw. `-Hwnd 0` and explicitly supplied `-ProcessId 0` throw. |
| `Get-PtForegroundWindow` | Reads the actual foreground HWND directly. Shell surfaces can be absent from `EnumWindows` even while foreground; an empty enumeration is not proof they are closed. |
| `Wait-PtWindow -ProcessId [-ClassName] [-Visible] [-TimeoutSeconds]` | Waits for one matching window; ambiguity, process exit or PID reuse throws. |
| `Wait-PtCondition -Probe -Description [-TimeoutSeconds] [-PollMilliseconds]` | Returns the probe's first truthy result. Exceptions propagate; only absence should return false/null. Probes must themselves be bounded. |
| `Invoke-PtWinApp -Arguments [-TimeoutSeconds]` | Arguments follow `winapp ui`, not `winapp`. Captures raw output, throws on invalid target/nonzero exit/timeout, and stops only its own timed-out CLI process. Automatically records inside an active attempt. |
| `Get-PtUiElements -Tree` | Flattens a captured JSON tree without another inspect. |
| `Get-PtUiObservation -Target -Property [-AutomationId/-Name -ControlType -WithinAutomationId]` | Read a supported typed property from an identity-checked target. Empty/false/zero remain values; unavailable observations throw structured errors. |
| `Test-PtUiSnapshot -Tree -RequiredLandmarks [-WindowHwnd]` | Offline structural assessment. Inspect `usableForContract`; it does not prove full enumeration or evaluate expected business results. |

Distinguish process existence, host readiness, visibility, and realized content. The
module profile supplies the required class/control predicates. Do not replace a content
predicate with a fixed sleep or treat a timeout as authorization to restart the product.
Use the [module lifecycle helper](module-lifecycle.md) for explicit UI enable/disable and
Diagnostic recovery. It returns fresh native observations; never reuse old handles after
a cycle, infer process readiness from an on-demand enabled flag, or treat event existence
alone as a live consumer.
Re-discover after restart or UI reconstruction; do not persist selectors across those
boundaries. A surviving process may own multiple windows.
Empty argument elements are preserved, for example
`Invoke-PtWinApp -Arguments @('set-value','TextBox','','-w',"$hwnd")`.
Native rectangles, WINDOWPLACEMENT and pointer capture/restore use a consistent
physical-coordinate DPI context, including when UIA changes the caller's default
awareness. Desktop snapshots carry `coordinateSpace: Physical`; restoration rejects
older snapshots with unspecified units rather than silently scaling the pointer.

```powershell
$window = Wait-PtWindow -ProcessId $process.Id -ClassName $expectedClass -Visible
$tree = Invoke-PtWinApp -Arguments @('inspect','--depth','8','-w',"$($window.Hwnd)",'--json') |
    ConvertFrom-Json
$nodes = @(Get-PtUiElements $tree)
# Select a realized control by its supported type and identifier from this tree.
```

## Scoped control selection

Use `Resolve-PtUiElement -Hwnd -ControlType` with **one** exact `-AutomationId` or `-Name`.
If the same identifier occurs in different containers, supply `-WithinAutomationId`.
Multiple exposures of the same runtime ID are one element; two distinct identities with
the same caption are an error, never a reason to select the first match.

```powershell
$before = @(Get-PtComboBoxSelection (Resolve-PtUiElement -Hwnd $hwnd `
    -AutomationId $controlId -ControlType ComboBox))
try {
    Assert-PtForegroundOrAbort -Hwnd $hwnd
    $result = Select-PtComboBoxItem -Hwnd $hwnd -AutomationId $controlId -ItemName $option
    # Requested / Before / Actual are observed values, not a product verdict.
} finally {
    Select-PtComboBoxItem -Hwnd $hwnd -AutomationId $controlId -ItemName $before[0]
}
```

For controls with no AutomationId use `-ControlName` on `Select-PtComboBoxItem`, not a
window-wide option-caption search. Read actual option labels from the installed UI.
The helper checks native visibility/minimization as well as UIA enablement/offscreen state,
scopes the option to its ComboBox, reads SelectionPattern or ValuePattern, and collapses
only the popup it opened. A matching current selection is a no-op. Active recorder
attempts capture the composed operation automatically.

These are synchronous UIA calls: the timeout bounds polling, not a hung provider's COM call.
The caller captures/restores selection, window placement and foreground around its own
mutation. Do not inspect or expand controls in a minimized window merely because its
UIA tree claims they are onscreen.

For PowerToys shortcut editors, use the [common shortcut recorder](shortcut-recorder.md).
It owns dialog readiness, modifier capture and field restoration; module profiles supply
control/property addressing and keep activation/content assertions separate.
For actual text, selection, focus, geometry and live-region properties, use the
[read-only observation helpers](ui-observations.md). Never substitute accessible names
for input values or unsupported-property defaults for observed values.

## Input ownership and observation

Prefer UIA invoke for controls and Named Events for downstream activation. To prove a
physical binding, guard the exact visible HWND:

```powershell
Send-PtChord -Hwnd $window.Hwnd -Mods 0x5B,0x10 -Key 0xBF
```

`Send-PtChord` defaults to no artificial dwell or inter-key delay. Opt into pacing when
the specific UI needs it, for example `-KeyDownMilliseconds 90 -ModifierDelayMilliseconds 40`
for a shortcut recorder. Delaying every activation chord can let a module observe a
held Windows key and close its newly opened surface on release. These delays are not
the module's long-hold threshold.
Existing calls still return the accepted input count. `-Hwnd` is optional for legacy
callers, which must continue to guard foreground themselves.

`Invoke-PtHeldKeys -Keys -Action [-Hwnd] [-KeyDownDelayMilliseconds]` observes while
keys remain down and releases injected keys in reverse order in `finally`. Already-held
keys and duplicate codes are rejected, so it never releases a user's key or a key owned
by an outer hold. Left/right Windows and extended navigation modifiers are supported.
For Win+1, keep Windows in the outer hold and send only `1` in the inner chord.
Do not force the old foreground after routing changes it.

For a **test-opened** Start/Search transition, use
`Restore-PtForegroundAfterShell -Hwnd <tracked-target>`. It identifies the actual foreground
owner, sends guarded Escape only to Start/Search, waits for foreground to leave that surface,
and rechecks the original target identity. It rejects held modifiers and never terminates
Shell processes. This is an explicit recovery action, not part of the ordinary foreground
guard: do not use it to dismiss user-owned UI or to hide a product's failed close assertion.
Review a passive capture too; Shell `WS_VISIBLE` can stay set after the surface is dismissed.

Use `Save-PtPassiveScreenshot -Path [-Observe]` for menus, overlays, held-key observations
and other focus-sensitive surfaces. Even ordinary `winapp ui screenshot -w` can affect
focus; omitting `--capture-screen` does not guarantee a passive capture.

`-Observe` is a read-only probe of stable invariants, such as menu presence, native
visibility and key state. Foreground is always checked. A mismatch retains the PNG and
`.state.json` diagnostics but throws: do not credit that capture as valid evidence.
Use unique paths from the recorder; existing images/sidecars are never overwritten.
Native visibility alone does not prove rendered content or absence of first-frame flash.

For an owner plus popup, pass `-WindowIdentity @($ownerIdentity,$popupIdentity)` to the
same capture helper. It resolves their current physical bounding union and checks the
identities/bounds again afterward. Explicit empty scope, minimized/hidden targets or changed
scope fail rather than falling back to a full-desktop capture. The rectangular union may
still include intervening/overlaid user content: use owned clean surfaces and review privacy.
Unscoped legacy calls continue to capture the virtual desktop.

## Pair snapshots with restoration before changing state

| Capture / restore | Scope and limits |
|---|---|
| `Get-PtFileSnapshot -Path` / `Restore-PtFileSnapshot -Snapshot [-ExpectedState]` | Shared-read bytes/existence. Supplying an existing-file expected snapshot holds an exclusive handle for compare/write/readback and rejects unknown changes. The legacy no-ExpectedState path is unguarded; use directory rollback for owned absence changes. |
| `Get-PtDirectorySnapshot -Path` / `Restore-PtDirectorySnapshot -Snapshot -ExpectedState -OwnedRelativePaths` | Exact bytes, file set and empty directories; explicit file/directory/root ownership and conflict-aware rollback. See [directory snapshots](directory-snapshots.md) for bounds and partial receipts. |
| `Get-PtRegistrySnapshot -SubKey -ValueNames` / `Restore-PtRegistrySnapshot` | Selected HKCU values with kinds and unexpanded raw values. No provider-object serialization. Other values/subkeys are untouched; conflicts preventing original key absence are surfaced. |
| `Get-PtWindowIdentity -Hwnd` / `Assert-PtWindowIdentity` | HWND, owner PID, process start ticks and native class. Reject recycled identities, including shared app hosts. |
| `Get-PtWindowSnapshot -Hwnd` / `Restore-PtWindowSnapshot` | Full WINDOWPLACEMENT and visibility, with whole-struct assignment and exact comparison. Only surviving windows; no title-based replacement. |
| `Get-PtDesktopSnapshot -WindowHwnd` / `Restore-PtDesktopSnapshot` | Explicitly affected windows plus original foreground identity and pointer. Attempts all restoration actions, then surfaces aggregated failures. |
| `Close-PtTrackedWindow -Identity` | Normal WM_CLOSE for an explicitly owned fixture, after identity checks. Does not terminate shared processes or discard unsaved documents. |

Persist snapshots before mutation; keep private payloads out of observation output.
`Get-PtFileSnapshot` does not make concurrent writes atomic; establish a stable baseline
and a known test-written expected state, not a fresh snapshot of unexplained changes.
Guarded file rollback requires original/expected files to exist and rejects reparse paths.
Unknown content or a sharing violation throws without deliberately replacing a writer's data.
These helpers do not grant permission to modify
product files: the scenario's UI-only mutation rules still apply. Use file restoration
only for authorized rollback. Any necessary startup/cache refresh belongs inside the
restoration plan before final verification, never after declaring cleanup complete.
Stop live writers through normal documented UI when required. Never use Taskband registry
writes to restore taskbar pins/order.
Matching file/registry/window snapshots are not rewritten, avoiding unnecessary watcher
notifications or placement/DPI transitions on an untouched minimized window.

```powershell
$desktop = Get-PtDesktopSnapshot -WindowHwnd @($window.Hwnd)
$file = Get-PtFileSnapshot -Path $settingsPath
$expected = $file
# Persist both objects as baseline evidence before the first mutation.
try {
    # Drive the documented user flow and record its original outcome.
    # Update $expected only from the known owned post-state, before dependent work.
} finally {
    try { Restore-PtFileSnapshot -Snapshot $file -ExpectedState $expected | Out-Null }
    finally { Restore-PtDesktopSnapshot $desktop | Out-Null }
}
```

Window snapshots do not include page/tab/selection, IME mode, scroll position or other
application-specific transient state. Capture and restore those explicitly when touched;
do not claim they were restored from a native window snapshot. Never close user windows
to obtain a single-instance fixture. On concurrent changes, preserve unrelated resources
and report the conflict instead of performing a broad reset.

For shared Notepad and disposable Explorer foreground targets, use the
[owned fixture helpers](owned-fixtures.md); do not rebuild tab ownership and cleanup
inside each run.
For taskbar slot routing use the [non-pinned taskbar fixtures](taskbar-fixtures.md).
For SG use its [composed flows](modules/shortcut-guide/composed-flows.md), keeping
the chosen entry/close route and input ownership explicit.
For copy/paste/sampling use the [clipboard guard](clipboard-guard.md). Restore and check
`Assert-PtClipboardRestored` before **every** writer/guard-owner shutdown. This is an explicit
caller gate, not an automatic feature of module lifecycle; retain the provider after a
failed clipboard restore rather than hiding the failure with a process restart.

## Targeted helper acceptance

The tests use the installed PowerShell runtime, without extra test packages:

```powershell
# Shared reads, guarded rollback, capture scope, input inventory and clipboard gate; no desktop mutation.
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtSharedContracts.ps1"

# File/registry/condition acceptance; no interactive desktop needed.
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtDesktopHelpers.ps1"

# Owned WinForms windows; requires an unlocked interactive desktop.
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtDesktopHelpers.ps1" -Interactive

# H01/H02: scoped ComboBoxes, ambiguity, native visibility and window churn.
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtUiContracts.ps1" -Interactive

# H03: shared tabs, real unsaved edits, isolated Explorer, cleanup conflict/retry.
pwsh -NoProfile -STA -File "$skill\scripts\tests\Test-PtOwnedFixtures.ps1" -Workspace <new-folder>

# Pointer and window units across three DPI contexts; moves/restores only the pointer.
pwsh -NoProfile -STA -File "$skill\scripts\tests\Test-PtCoordinateContracts.ps1" -Workspace <new-folder>

# H04 byte-exact directory rollback and concurrent-conflict cases; no desktop needed.
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtDirectorySnapshot.ps1" -Workspace <new-folder>

# Actual SG Settings controls; supply the existing Shortcut Guide page's HWND.
# Preserves the existing window, settings bytes, foreground and pointer.
pwsh -NoProfile -STA -File "$skill\scripts\tests\Test-PtSettingsComboBox.ps1" -Hwnd <settings-hwnd> -Workspace <new-folder>

# Also exercises installed SG in its existing indicator mode; does not change settings.
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtDesktopHelpers.ps1" -Interactive -ShortcutGuide

# Actual winapp --help wrapper integration, no UI access.
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtRecordingIntegration.ps1"

# Real cross-script/formatting/argument/artifact contracts, no product UI access.
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtInvocationContracts.ps1"

# H09 incremental review, source reuse, bounded observations and optional archive parity.
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtLightweightRecording.ps1" -Workspace <new-folder>

# H10 cross-process error history, cleanup and interrupted-operation contracts.
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtVerificationOperation.ps1" -Workspace <new-folder>

# Partial assertions, verified cleanup recovery and original script context; offline only.
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtVerificationContinuations.ps1" -Workspace <new-folder>

# H05 schema/receipt contracts; add -Interactive -SettingsHwnd for two-module UI acceptance.
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtShortcutRecorder.ps1" -Workspace <new-folder>

# H06 model, identity, partial-transition and explicit-recovery contracts.
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtModuleLifecycle.ps1" -Workspace <new-folder>

# H08/H11 offline ownership, flow, drag-delivery and cleanup contracts.
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtShortcutGuideFlow.ps1" -Workspace <new-folder>
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtTaskbarFixture.ps1" -Workspace <new-folder>

# SG entry readiness, physical Settings action and rejected-capture retention; offline.
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtShortcutGuideEntryContracts.ps1" -Workspace <new-folder>
```

Each acceptance uses a new workspace and retains its results and restoration evidence.
Negative tests intentionally reject invalid targets/captures. These are infrastructure
acceptance results, not a complete module signoff or a substitute for the release checklist.
