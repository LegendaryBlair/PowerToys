# Power Display fixture boundaries

Use the [shared template](../templates/verification-run.ps1), unchanged frozen
[inventory](assertion-inventories/power-display.json), [resource session](session-safety.md)
and [cleanup plan](session-safety.md#cleanup-dependencies). This guide supplies preparation,
not a hardware simulator, lifecycle replacement or preassigned verdict.

## Select a safe scope

A standalone entry/refresh/dismiss/CLI-read flow does not require starting Runner when
Runner is originally stopped. Launch the installed `WinUI3Apps\PowerToys.PowerDisplay.exe`
without arguments only for that explicit entry condition. It starts discovery and may
write state even when no hardware edit is requested. Do not equate this with enabling
the module through Settings or proving Runner integration.

Before any GUI launch, inspect original existence of `discovery.lock` and
`crash_detected.flag`. If either exists, preserve it and stop launch-dependent work;
do not clear it to obtain a healthy test. Read `restore_settings_on_startup` and
`max_compatibility_mode` from the actual module settings. If startup can replay hardware
or perform aggressive probes, establish the corresponding hardware baseline/recovery
first; do not silently disable the user's option. Existing Settings/profile data is
private: local code may preserve it, but emit only metadata/hashes and owned-row results.

Inspect the JSON value shape before testing these flags. Accept a scalar Boolean, or an
explicit legacy object whose `value` is Boolean; reject missing/unexpected shapes rather
than treating them as false. Current scalar fields do not require a `.value` suffix.

For normal interactive checks, independently probe host, module and foreground-fixture
integrity with `Test-PtAdmin`/`Test-ProcessElevated`. Verify exact HWND/path/session
and current geometry with the [desktop/input helpers](helper-workflow.md).
Remote display presence is not DDC/CI or WMI capability evidence.

## Files and hardware

Capture before launch, not after discovery. `%LOCALAPPDATA%\Microsoft\PowerToys` contains:

| Scope | Paths / state | Preparation |
|---|---|---|
| Module state | `PowerDisplay\settings.json`, `profiles.json`, `monitor_state.json` | Private byte/existence baseline; startup can update monitor inventory, migrate profile IDs and create the state file. |
| Recovery | `PowerDisplay\discovery.lock`, `crash_detected.flag` | Read-only presence gate for ordinary runs. A new surviving marker is a finding, not authorized cleanup by filename. |
| Global state | `settings.json` | Existing-file private snapshot plus enabled-state readback. Unexpected auto-disable is not an owned ordinary edit. |
| Integration | `LightSwitch\settings.json` | Preserve before profile migration/deletion or theme integration; migrations can update references indirectly. |
| Hardware | Brightness/contrast/volume, input, color preset, power and orientation | Independently read exact originals and record a safe restore action before selecting the case. File rollback cannot restore a physical monitor. |
| Diagnostics | Module logs and telemetry | Record run-created diagnostic effects separately; never delete pre-existing logs or claim whole-directory byte equality while retaining new logs. |

For bounded quiescent module roots, use
[`Get-PtDirectorySnapshot`](directory-snapshots.md) before activation and an attributed
post-state after the exact owned writer exits. Pass the original snapshot, known
`ExpectedState`, and explicit `OwnedRelativePaths` to `Restore-PtDirectorySnapshot`.
For an ordinary module-only run the candidate owned data paths are exactly
`settings.json`, `profiles.json`, `monitor_state.json`; declare them before launch.
Ownership covers only effects attributable to the selected run, not arbitrary concurrent
edits. Include a known created temporary sidecar only after identifying its writer/path.
Do not grant ownership to recovery markers, logs or every changed file.

This helper supports originally absent files without pre-creating them. It captures the
entire bounded root, so keep raw snapshots private and check size/reparse limits first.
Its `Partial` result can legitimately retain unowned diagnostic logs: report that fact,
check `OwnedPathsMatchBaseline` and independently compare all declared user-state files.
Do not relabel `WholeTreeMatchesBaseline=false` as whole-tree restoration.
An unexplained change is a conflict, not a reason to take a new expected snapshot.

For an existing global or Light Switch file, `Get-PtFileSnapshot -Path` and
`Restore-PtFileSnapshot -Snapshot -ExpectedState` supply an existing-file guarded pair.
For original absence use a separately bounded Light Switch directory snapshot with exact
file ownership; never pre-create the file to satisfy the existing-file API.
If the selected scope cannot justify a write, compare without restoring it.

Hardware matrices need real controllable monitors and independent reads/physical
observations. The product CLI reports app-known state and may return cached values;
it is not a universal independent DDC oracle. The shared harness has no automatic monitor
OSD, safe input-switch rescue, fault injection or hardware rollback adapter. Defer those
conditions until the actual fixture exists. Do not write settings to simulate support.

## Process and UI ownership

Declare the exact installed GUI as an owned `Process` resource with a `Quiesce` restore
step **before** its launch. When absent, use `Start-PtOwnedProcess -FilePath $guiPath`;
keep the returned PID/start-time/path receipt. Register each created native sibling with
`Register-PtCreatedWindow -Identity $identity -Creation $creation` after resolving it.
Existing singleton instances remain borrowed; a second launch redirects to the first.

Escape, focus loss and WM_CLOSE hide the flyout; they do not prove process exit.
For a launch-owned instance, the user-facing tray **Exit** invokes its shutdown path.
Use `Stop-PtOwnedProcess -Creation $creation -RequestExit $exitAction` around that
one observed tray action, registering native siblings first. Resolve the real tray
icon/menu at runtime and retain the original interaction error if it fails.
The existing `PowerDisplay.Terminate` shared event is a separate cooperative shutdown
route for authorized cleanup, not evidence that tray Exit works. Do not replace a failed
tray assertion with an event PASS or a force kill. Verify the exact process is gone and
the service is unavailable; a hidden window alone is insufficient.

Borrowed Settings requires its original snapshot before navigation; owned Settings needs
an actual creation receipt. Use [Settings restoration](session-safety.md#borrow-settings-before-navigation)
and do not close a pre-existing window. Capture the desktop before the first focus/input
change; pair `Get-PtDesktopSnapshot` with `Restore-PtDesktopSnapshot` after other UI cleanup.
Use that canonical execution snapshot for physical geometry, not coordinates from a
DPI-unaware identity probe. On template Resume, reload the original persisted resource
plan instead of rebuilding a semantically similar hashtable with different property order.

## Release and verify

1. Finish/cancel owned drafts. Restore hardware through the same safe user-facing route
   while its controls are available; independently verify the original physical values.
2. Restore UI options and profile/mapping semantics. Restore complete clipboard formats
   before releasing its owner if a copy case ran; use the [shared keeper](clipboard-guard.md).
3. Exit only owned writers through their shipped shutdown action, then capture their
   attributable post-state. Retain all launch/exit errors and unexpected recovery markers.
4. Perform conflict-guarded byte/existence rollback for declared data paths. Restore
   original enablement/lifetime if the chosen scope changed it, accounting for restart writes.
5. Restore borrowed Settings and the original desktop. Compare again after the last writer
   or restart: data bytes/existence, enabled state, owned-process absence, borrowed identities,
   native placement and pointer. Report unowned logs and any conflicts separately.

Keep the original baseline across retries. A template success, cleanup callback or settings
hash alone cannot certify hardware, process, clipboard and desktop restoration together.
