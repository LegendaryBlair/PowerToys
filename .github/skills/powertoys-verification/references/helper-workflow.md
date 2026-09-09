# Reliable driving and paired restoration

Use PowerShell 7 on Windows. These are small reusable operations, not a scheduler or a
replacement for a module's checklist. Keep UI driving serial on one desktop.
Read the [recording workflow](recording-workflow.md) before discovery; wrap every native
winapp call with `Invoke-PtWinApp` and activate a recording attempt.

## Load and check the driver before mutation

```powershell
Get-ChildItem "$skill\scripts" -Filter '*.ps1' |
    Where-Object Name -ne 'pt-session-diagnose.ps1' | ForEach-Object { . $_.FullName }
foreach ($name in 'Wait-PtCondition','Invoke-PtWinApp','Save-PtPassiveScreenshot',
    'Invoke-PtHeldKeys','Get-PtDesktopSnapshot','Restore-PtDesktopSnapshot') {
    Get-Command $name -ErrorAction Stop | Out-Null
}
```

Run `pt-session-diagnose.ps1` as a recorded preflight step. Probe the actual module's
entry path and one normal open/close flow before a batch. Do not use a failed precondition
to continue sending input into subsequent cases. Readiness/driver errors are not product
assertions, and a diagnostic restart does not prove ordinary reopen behavior.

## Discover, wait, and invalidate

| Helper | Contract |
|---|---|
| `Get-PtNativeWindow [-Hwnd] [-ProcessId] [-ClassName] [-Visible]` | Fresh native top-level windows in physical screen coordinates. `-Hwnd 0` throws. Does not choose by English title or `MainWindowHandle`. |
| `Get-PtForegroundWindow` | Reads the actual foreground HWND directly. Shell surfaces can be absent from `EnumWindows` even while foreground; an empty enumeration is not proof they are closed. |
| `Wait-PtWindow -ProcessId [-ClassName] [-Visible] [-TimeoutSeconds]` | Waits for one matching window; ambiguity/process exit throws. |
| `Wait-PtCondition -Probe -Description [-TimeoutSeconds] [-PollMilliseconds]` | Returns the probe's first truthy result. Exceptions propagate; only absence should return false/null. Probes must themselves be bounded. |
| `Invoke-PtWinApp -Arguments [-TimeoutSeconds]` | Arguments follow `winapp ui`, not `winapp`. Captures raw output, throws on invalid target/nonzero exit/timeout, and stops only its own timed-out CLI process. Automatically records inside an active attempt. |
| `Get-PtUiElements -Tree` | Flattens a captured JSON tree without another inspect. |

Distinguish process existence, host readiness, visibility, and realized content. The
module profile supplies the required class/control predicates. Do not replace a content
predicate with a fixed sleep or treat a timeout as authorization to restart the product.
Re-discover after restart or UI reconstruction; do not persist selectors across those
boundaries. A surviving process may own multiple windows.
Empty argument elements are preserved, for example
`Invoke-PtWinApp -Arguments @('set-value','TextBox','','-w',"$hwnd")`.

```powershell
$window = Wait-PtWindow -ProcessId $process.Id -ClassName $expectedClass -Visible
$tree = Invoke-PtWinApp -Arguments @('inspect','--depth','8','-w',"$($window.Hwnd)",'--json') |
    ConvertFrom-Json
$nodes = @(Get-PtUiElements $tree)
# Select a realized control by its supported type and identifier from this tree.
```

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

## Pair snapshots with restoration before changing state

| Capture / restore | Scope and limits |
|---|---|
| `Get-PtFileSnapshot -Path` / `Restore-PtFileSnapshot -Snapshot` | Exact bytes and absence for one explicit file. JSON-round-trippable; restore is repeatable and retains the snapshot. Does not manage directories, metadata/ACLs, live writers or app caches. |
| `Get-PtRegistrySnapshot -SubKey -ValueNames` / `Restore-PtRegistrySnapshot` | Selected HKCU values with kinds and unexpanded raw values. No provider-object serialization. Other values/subkeys are untouched; conflicts preventing original key absence are surfaced. |
| `Get-PtWindowIdentity -Hwnd` / `Assert-PtWindowIdentity` | HWND, owner PID, process start ticks and native class. Reject recycled identities, including shared app hosts. |
| `Get-PtWindowSnapshot -Hwnd` / `Restore-PtWindowSnapshot` | Full WINDOWPLACEMENT and visibility, with whole-struct assignment and exact comparison. Only surviving windows; no title-based replacement. |
| `Get-PtDesktopSnapshot -WindowHwnd` / `Restore-PtDesktopSnapshot` | Explicitly affected windows plus original foreground identity and pointer. Attempts all restoration actions, then surfaces aggregated failures. |
| `Close-PtTrackedWindow -Identity` | Normal WM_CLOSE for an explicitly owned fixture, after identity checks. Does not terminate shared processes or discard unsaved documents. |

Persist snapshots before mutation. These helpers do not grant permission to modify
product files: the scenario's UI-only mutation rules still apply. Use file restoration
only for authorized rollback, and follow module-specific cache refresh rules afterward.
Stop live writers through normal documented UI when required. Never use Taskband registry
writes to restore taskbar pins/order.
Matching file/registry/window snapshots are not rewritten, avoiding unnecessary watcher
notifications or placement/DPI transitions on an untouched minimized window.

```powershell
$desktop = Get-PtDesktopSnapshot -WindowHwnd @($window.Hwnd)
$file = Get-PtFileSnapshot -Path $settingsPath
# Persist both objects as baseline evidence before the first mutation.
try {
    # Drive the documented user flow and record its original outcome.
} finally {
    try { Restore-PtFileSnapshot $file | Out-Null }
    finally { Restore-PtDesktopSnapshot $desktop | Out-Null }
}
```

Window snapshots do not include page/tab/selection, IME mode, scroll position or other
application-specific transient state. Capture and restore those explicitly when touched;
do not claim they were restored from a native window snapshot. Never close user windows
to obtain a single-instance fixture. On concurrent changes, preserve unrelated resources
and report the conflict instead of performing a broad reset.

## Targeted helper acceptance

The tests use the installed PowerShell runtime, without extra test packages:

```powershell
# File/registry/condition acceptance; no interactive desktop needed.
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtDesktopHelpers.ps1"

# Owned WinForms windows; requires an unlocked interactive desktop.
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtDesktopHelpers.ps1" -Interactive

# Also exercises installed SG in its existing indicator mode; does not change settings.
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtDesktopHelpers.ps1" -Interactive -ShortcutGuide

# Actual winapp --help wrapper integration, no UI access.
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtRecordingIntegration.ps1"

# Real cross-script/formatting/argument/artifact contracts, no product UI access.
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtInvocationContracts.ps1"
```

Each acceptance uses a new workspace and retains its results and restoration evidence.
Negative tests intentionally reject invalid targets/captures. These are infrastructure
acceptance results, not a complete module signoff or a substitute for the release checklist.
