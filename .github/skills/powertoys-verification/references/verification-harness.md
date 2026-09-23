# Small verification harness

These helpers support the Color Picker iteration without importing the WIP Shortcut Guide harness.
They are mechanical primitives, not another agent framework or a complete module test suite.
Use **PowerShell 7.4+ on Windows**; clipboard operations require **`pwsh -STA`**.
No package installation is required.

| Script | Responsibility |
|---|---|
| `scripts\pt-verification-state.ps1` | Existing-file snapshots, conflict-checked rollback, native clipboard guard, original-enablement cleanup |
| `scripts\pt-verification-ui.ps1` | Exact HWND/process identity, row-scoped unique controls, idempotent toggles, passive composed capture |
| `scripts\pt-verification-run.ps1` | Command records, assertion inventory/history, cleanup evidence, summary and archive integrity |
| `scripts\pt-verification-native.cs` | Window observations and locked clipboard handle/data copying; loaded by state/UI helpers |

Old helper APIs remain unchanged. New code should use these explicit APIs rather than the old first-window
foreground selection or unconditional `Restore-PtModuleSettings` overwrite.

## Shared helper initialization

Initialize a shared helper in the script scope of the driver/phase that will call it,
before any product mutation. A fresh PowerShell process has no parent's imports; a helper
function being visible to a separately executed phase does not prove its script-scoped data
is initialized there. For the named-event helper, set `$skill` to this skill's folder and
run this inside each executing phase that needs it:

```powershell
. "$skill\scripts\pt-shared-events.ps1"
Get-PtSharedEventCatalog
```

Check that the requested friendly name maps to the intended event before signaling.
`Invoke-PtSharedEvent` reads `$script:PtSharedEvents`; a null/missing catalog is a driver
initialization error, not a module-availability verdict. Preserve the error and establish
driver readiness rather than restarting the product or blindly replaying an uncertain action.
Catalog enumeration is read-only and does not prove a live consumer or a keyboard binding.

## 1. Record first; never treat a command exit as a product verdict

```powershell
. "$skill\scripts\pt-verification-run.ps1"
$run = New-PtRecordedRun -Workspace $newWorkspace -Bits $actualArtifactIdentity -Scenarios @(
    @{ Id = 'CP-COPY-FORMATS'; AssertionIds = @('CP06', 'CP07') }
) -InputPath @($checklistPath, $profilePath, $driverPath)

$call = Invoke-PtRecordedCommand -Run $run -Name 'Read current windows' `
    -FilePath $winappPath -Arguments @('ui', 'list-windows', '--json')
```

The workspace must not exist. Supply the **selected** scenario/assertion inventory explicitly; a subset is not
a full module run. Each command gets a new GUID directory, even when labels repeat. The record preserves exact
argument arrays (including empty strings), start/end times, exit code, UTF-8 stdout/stderr and the original error.
UTF-8 decoding assumes the invoked command emits UTF-8; configure other child tools accordingly.

Nonzero exit/spawn failure throws **after recording**. The exception's `Data['EvidencePath']` identifies the
failed invocation. A timeout kills only the process tree started by that invocation and records uncertainty;
it does not replay an input gesture. A descendant keeping output pipes open is an explicit error, not an
unbounded wait or successful completion. Do not use this wrapper to launch detached/background services.

Run scripts at their original path (`pwsh -File <driver>`), with explicit working directory and input snapshots.
Do not execute an evidence snapshot from another directory or copy its archived HWNDs.
The run is single-writer: no concurrent controllers may mutate the same workspace.

## 2. Exact window and row scope

```powershell
. "$skill\scripts\pt-verification-ui.ps1"
$window = Get-PtWindowIdentity -Hwnd $resolvedHwnd
$observation = Invoke-PtWindowCommand -Run $run -Window $window -Name 'Read editor' `
    -Verb inspect -Arguments @('--depth', '14', '--json')
$tree = $observation.Stdout | ConvertFrom-Json
$row = Resolve-PtUiControl -Root $tree -Type Group -Name $observedUniqueRowName
$copy = Resolve-PtUiControl -Root $row -Type Button -Name $localizedCopyName
```

Resolve the actual window from current discovery; never choose the first process window. The identity includes
HWND, PID, process start time/path and owner thread. Each scoped call rejects stale ownership, hidden/cloaked
targets and attempts to override `-w`/`-a`. Input-moving verbs require the exact HWND already foreground; the
helper does not steal focus to make a test pass. Read-only observations also recheck identity afterward.

Selectors are matched by exact type plus AutomationId/name **inside the supplied root**. Missing/ambiguous
matches throw. Repeated projections of an identical selector are deduplicated; conflicting projections throw.
Old UIA trees are not freshness tokens: inspect again after reorder/navigation/lifecycle changes.

`Set-PtScopedToggle -Run $run -Window $window -Selector $toggle -Enabled $wanted` reads the current value,
invokes only if different and waits for readback. Its default `On`/`Off` values can be explicitly localized.
Unknown values throw; persisted settings and process readiness still need separate observations.

```powershell
$capture = Save-PtWindowCapture -Run $run -Windows @($editorIdentity, $popupIdentity) -Name 'Adjust color'
```

Capture uses the physical-pixel union of current native window bounds, without activation, and retains a PNG
plus state sidecar. Identity/visibility/geometry/foreground changes invalidate it and throw. DPI context is
restored in `finally`. The helper does not decide whether pixels satisfy an expectation: inspect the actual
image for clipping, occlusion, content and colors. Include the popup HWND explicitly.

## 3. File restoration is compare-before-write, not a force copy

```powershell
. "$skill\scripts\pt-verification-state.ps1"
$snapshot = New-PtFileGuard -Path $settingsPath
# Perform and verify an authorized UI change.
# Derive this hash from the declared expected post-state, not an arbitrary current file.
$expectedHash = Get-PtFileHashBytes -Bytes $expectedOwnedBytes
# Stop the relevant writer through its normal UI/lifecycle before rollback.
$receipt = Restore-PtFileGuard -Guard $snapshot -ExpectedCurrentHash $expectedHash
```

Snapshots use read/write/delete sharing and reject changing reads. Rollback opens an exclusive handle, checks
the current hash against the baseline or explicitly expected owned post-state, writes and verifies under that
same handle. Unknown changes, missing files, edited snapshot bytes and unavailable locks throw.

This API covers **existing files**. It does not create/delete trees, merge concurrent JSON edits, infer ownership
from matching color strings, or promise crash-atomic multi-file rollback. Keep baseline bytes until all checks
are complete. An expected-current hash authorizes a particular state; do not blindly hash an unknown file and
pass that value as consent to overwrite it.

## 4. Clipboard ownership and restoration

Keep a hidden owner window alive in the **same STA process** as the guard. Snapshot before any copy:

```powershell
$guard = New-PtClipboardGuard -OwnerHwnd $ownedForm.Handle.ToInt64()
try {
    $guard.AssertUnchanged()
    $beforeSequence = $guard.ExpectedSequence
    # Perform exactly one recorded product copy action; observe its actual clipboard result.
    Register-PtClipboardWrite -Guard $guard -BeforeSequence $beforeSequence `
        -WriterProcessId $writer.ProcessId -WriterStartTicks $writer.StartTicks
    # Further copies use a fresh AssertUnchanged/beforeSequence pair.
} finally {
    try { $guard.Restore() }
    finally { $guard.Dispose() }
}
```

The snapshot eagerly copies native text, bitmap/DIB, file-list, locale and registered HGLOBAL formats
(including PNG and clipboard-policy streams). Unsupported handles/formats or oversized entries fail **before
mutation**. Data stays in memory, not an archive. If a remote provider's Bitmap is unusable but PNG can be
decoded, the guard materializes Bitmap from that same sequence's PNG and exposes `BitmapFromPng=true`;
it retains the original PNG bytes. Invalid PNG or a concurrent change aborts the snapshot.

`Register-PtClipboardWrite` checks the declared writer's process start time and the current clipboard-owner PID.
Only call it immediately after a known copy. Sequence/owner checks detect unacknowledged changes; they do not
prove that no intermediate external write occurred during the action, or distinguish two writers inside the
same process. Shared-desktop interference still requires stopping and reporting a conflict.

Restoration holds the clipboard lock while comparing the accepted sequence and restoring/verifying data.
It never treats empty text, a known color or a destroyed producer as ownership. Restore the clipboard **before**
terminating a process that owns delayed clipboard data. An unacknowledged clear on shutdown is a conflict.
`Dispose()` frees the snapshot; it does not restore. A process crash loses an in-memory backup, so this is not
a crash-recovery service. Do not forcibly kill the guard process during a live test.

## 5. Preserve original enabled state, including failure paths

`Invoke-PtRestoredState` accepts six narrowly scoped scriptblocks:

| Callback | Contract |
|---|---|
| `ReadEnabled` | Exactly one Boolean, from actual observed state |
| `SetEnabled($value)` | Set desired state through the real UI, not blindly toggle |
| `Action` | The selected test work; do not swallow its errors |
| `Quiesce` | Verify all file writers have stopped after disable; timeout/access errors must throw |
| `Restore` | Restore the explicitly owned file state; reject conflicts |
| `Verify` | Exactly one Boolean: check file/content/readiness after returning to original enabled state |

It captures initial enablement, runs Action, then disables/quiesces/restores in `finally`, returns to the
original enabled state and verifies. Both original-on and original-off paths are supported. Action and cleanup
exceptions are aggregated rather than replacing one another.

If restore conflicts, it does **not** restart a writer over unresolved files. That is incomplete cleanup,
explicitly reported, not a restored receipt. Use an inner clipboard `try/finally` inside Action so clipboard
restoration precedes writer shutdown. Preserve pre-existing user UI or decline a destructive test.
The callback contract is not a built-in PowerToys restart policy; no blanket Runner restart/process kill occurs.

## 6. Independent assertions and archive

```powershell
Set-PtRecordedAssertion -Run $run -Id CP06 -Verdict PASS -Reason $observedComparison `
    -Evidence @($call.EvidencePath, $clipboardReceipt)
Set-PtRecordedAssertion -Run $run -Id CP07 -Verdict NOT-OBSERVED -Reason $dependency `
    -Evidence @($failedCallReceipt)
Set-PtRecordedCleanup -Run $run -Restored $restored -Reason $cleanupDescription -Evidence @($cleanupReceipt)
$summary = Complete-PtRecordedRun $run
Move-PtRecordedArchive -Run $run -Destination $newArchiveDirectory
```

Evidence must exist inside the run (no traversal/reparse links). Hashes are checked again at completion.
Updating one assertion retains other results; all judgments are appended to history. Replacing a FAIL with
another outcome requires an explicit correction reason and evidence. Untouched assertions remain NOT-OBSERVED.

Scenario verdicts aggregate their retained assertions; a valid FAIL dominates, otherwise incomplete coverage
is BLOCKED. Sign-off is WITHHELD for non-PASS coverage, unverified cleanup, any recorded command error/timeout,
or invalid capture. This small implementation deliberately does not adjudicate superseded infrastructure
failures automatically: use a new confirmation run linked to the earlier evidence, not removal of failures.

`report.md` is a mechanical evidence index, **not** the full release-sign-off narrative. Add the scenario's
per-item step explanations and retrospective required by [reporting-format.md](reporting-format.md) before
finalizing. The manifest covers every file, detects missing/added/changed entries, and is rechecked after move.
Archives are never overwritten. Hashes establish local integrity, not authenticity against malicious rewriting.

## Regression commands

From the skill directory:

```powershell
pwsh -NoProfile -File scripts\tests\Test-PtVerificationHarness.ps1
pwsh -NoProfile -STA -File scripts\tests\Test-PtVerificationDesktop.ps1
```

The first covers file conflicts, lifecycle failures, scoped selectors, argv/Unicode, error/timeout recording,
partial coverage, corrections and archive integrity. The second uses only test-owned windows, exercises actual
winapp controls, captures a main window plus popup, preserves rich clipboard content, rejects conflicting writes
and verifies both original enablement states through real fixture toggles. It does not run or modify PowerToys.
Each creates a fresh output directory and retains diagnostic artifacts; no package restore/build is needed.
