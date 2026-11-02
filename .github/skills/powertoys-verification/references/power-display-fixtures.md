# Power Display fixture boundaries

Use the [shared template](../templates/verification-run.ps1), candidate's frozen
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

## Module data read-outs

Module `settings.json` fields under `properties` include `activation_shortcut`,
`monitor_refresh_delay`, `mouse_wheel_increment`, `mouse_wheel_control_mode`,
`restore_settings_on_startup`, `max_compatibility_mode`, `show_system_tray_icon`,
`show_profile_switcher`, `show_identify_monitors_button`, `linked_levels_active`,
`excluded_from_sync_monitor_ids`, `monitors` and `custom_vcp_mappings`.
Use actual typed shapes, not assumed `.value` wrappers.

CLI `list --json` exposes `monitors`, including `[]`; "No monitors detected" in the
flyout and "No monitors discovered." in CLI are equivalent empty-state captions.
Neither establishes physical discovery completeness. `get` without a selector reads
all monitors; selector-missing rejection applies to set/up/down. Target resolution
precedes range validation, so an absent target can return exit 1 instead of range exit 2.
Provider absence is exit 10, parse rejection exit 7; JSON errors belong on stderr.
Keep exact streams for both missing-value flag positions in the checklist: an exit code
alone does not establish structured output. Help/version remain human-readable.

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

For a module root containing an unrelated live Runner log, use
[`Get-PtFileSetSnapshot`](directory-snapshots.md#selected-file-preservation) with the exact
data file names before activation, then an attributed post-state after selected writers
quiesce. Pass the original snapshot, known `ExpectedState` and explicit `OwnedFileNames`
to `Restore-PtFileSetSnapshot`; unrelated log contents are not read.
For an ordinary module-only run the candidate owned data paths are exactly
`settings.json`, `profiles.json`, `monitor_state.json`; declare them before launch.
Ownership covers only effects attributable to the selected run, not arbitrary concurrent
edits. Include a known created temporary sidecar only after identifying its writer/path.
Do not grant ownership to recovery markers, logs or every changed file.

This supports originally absent files without pre-creating them. Keep raw snapshots private
and check size/reparse limits. Verify `OwnedFilesMatchBaseline` and
`SelectedFilesMatchBaseline`; logs outside the selection are not part of that comparison.
Use the existing whole-directory helper only when the whole root is actually quiescent,
or when root/directory existence must be preserved. Do not suppress its sharing violation,
stop a borrowed log writer or reinterpret selected-file equality as whole-tree restoration.
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

## WMI brightness

Load `scripts\pt-power-display.ps1` from this candidate. Its read-only
`Get-PtPowerDisplayWmiBrightness -MonitorId $monitorId` queries `root\WMI`,
`WmiMonitorBrightness`; it does not read the app's cache or change hardware.
Resolve `$monitorId` privately from the actual CLI `list --json` WMI entry and the
corresponding UI monitor. The helper maps the complete WMI instance, including its PnP
UID, to the device-path identity. Same EDID/model is not enough. Missing, inactive,
ambiguous or failed reads stop dependent hardware input; zero is a valid observation.

1. Before module activation, capture all potentially affected hardware independently.
   If the app is stopped, enumerate WMI privately and use
   `ConvertTo-PtPowerDisplayMonitorId -InstanceName $instanceName` for each actual instance;
   bind it to app discovery after launch. Do not select the first panel.
2. Keep the returned baseline and advertised `Levels` privately. Choose a safe distinct
   supported level, not a hard-coded initial value. Record linking/exclusions and restore
   any changes to them; a linked or hidden individual slider is not an eligible target.
3. In the exact monitor card, resolve the local Brightness Slider and current bounds.
   For keyboard coverage, focus that slider and send an arrow through the shared guarded
   input route. Mouse coverage uses the supported winapp drag syntax from the pinned
   tool help. Release the gesture before observing the commit; RangeValuePattern writes
   do not substitute for mouse, keyboard or touch input assertions.
4. Sample the same WMI instance after the action, with timestamps and the actual UI value.
   Preserve readings when the requested value is not reached, not just an expectation
   timeout. Bound observation without repeating the gesture. A stable old value remains
   an actual observation, not an instruction to keep trying until success.
5. Restore the original level through the supported UI while the control is available;
   independently reread the same instance. If this path fails, stop further mutations
   and retain the recovery record; this helper provides no hardware-write rescue.

Inside a recorded step, assign private results rather than emitting them. Here `$skill`
is the candidate engine, `$monitorId` the privately resolved identity, and `$panelAlias`
an owned report label:

```powershell
. "$skill\scripts\pt-power-display.ps1"
$hardwareOriginal = Get-PtPowerDisplayWmiBrightness -MonitorId $monitorId
# Persist hardwareOriginal privately before the first hardware-affecting action.
$hardwareAfter = Get-PtPowerDisplayWmiBrightness -MonitorId $monitorId `
    -ExpectedInstanceName $hardwareOriginal.InstanceName
[pscustomobject]@{
    Panel = $panelAlias
    Before = $hardwareOriginal.Brightness
    After = $hardwareAfter.Brightness
    ObservedUtc = $hardwareAfter.ObservedUtc
}
```

The two reads bracket an explicitly recorded action; the snippet itself performs none.
Keep monitor IDs/instance names out of command transcripts and shared detail objects.
DDC contrast/volume/native-range checks need a different independent oracle, including
the feature's native range and quantization. WMI percent readings cannot certify them.

## Flyout footer and hidden owner

Resolve the visible content HWND with `SettingsBtn`, not the first same-class WinUI host.
The refresh opener is the ordinary Button immediately left of `SettingsBtn` in the
right-side footer. Corroborate current tree, nonoverlapping physical bounds and refresh
glyph/tooltip. Exclude the `LinkLevelsToggle` ToggleButton and left-side `ProfilesButton`.
The empty-flyout shortcut of finding a unique unnamed Button is not valid window-wide
once other controls exist. Invoke only after the scoped candidate is unique, then confirm
the popup contains `RefreshButton` before invoking Refresh once.

Discovery can finish while focus loss has hidden the main window. Check process identity,
native visibility and settled CLI discovery separately. If resident, reopen through the
chosen ordinary entry route and resolve current controls; do not restart or refresh again.
After selecting a profile, similarly observe picker closure and actual parent visibility
instead of assuming the parent remains visible. Passive capture must not refocus it.

## Owned monitor profiles

Prepare file/hardware baselines, a real discovered monitor and collision-checked owned
names. Expand the Settings Profiles section. Resolve the Add profile Button from its
actual Text/Button relationship; an enabled button alone does not establish editor
availability. Wait for the owned modal, enabled `ProfileNameTextBox` Edit and its monitor
rows. A missing monitor list is not permission to synthesize profiles.json.

For a new draft, set the name through the exposed Edit ValuePattern, read it back, and
select the exact monitor ToggleSwitch. Within that monitor's field card, toggle the
Brightness inclusion CheckBox and set its enabled Slider; monitor selection, field
inclusion and numeric value are separate controls. Resolve other supported fields within
their own cards rather than choosing a window-wide Slider. Inspect Save enablement after
the edits. Save uses the owned dialog's `PrimaryButton`; Cancel uses `CloseButton`.
Wait for dialog closure, then read the file through `Read-PtSharedFileText`.

The persisted shape is `profiles[]`, with `id`, `name`, `createdDate`, `lastModified` and
`monitorSettings[]` (`monitorId`, nullable brightness/contrast/volume/colorTemperature).
Display order is **array order**, not an `order` property. Capture pre/post IDs around one
UI creation; attribute only its new positive ID to the run. Preserve `nextId` as part of
the private file baseline, not a counter to reset during product testing.

Use the read-only selector on a fresh parsed file, with `$ownedIds` from those creation
receipts, `$profileId` the requested owned ID and `$profilesPath` the installed data path:

```powershell
$profileFile = ConvertFrom-PtReportJson (Read-PtSharedFileText -Path $profilesPath)
$ownedProfile = Get-PtPowerDisplayOwnedProfile -Profiles @($profileFile.profiles) `
    -Id $profileId -OwnedIds $ownedIds
$displayName = '{0} (#{1})' -f $ownedProfile.name, $ownedProfile.id
```

Resolve that full current display label inside `ProfilesList`, corroborating
`ProfileApplyButton`/`ProfileMoreButton` HelpText on the same row. The formatter above is
for the observed positive-ID label; inspect the current localized label before input.
Do not locate by bare name or array index. After rename/reorder, discard the previous
UIA element/selector and read the row again.

| Operation | Drive and commit | Independent read-out |
|---|---|---|
| Edit/rename | Owned row More > Edit; confirm prefilled editor; Save or Cancel | Same `id`/`createdDate`; compare all selected fields, not just the visible name |
| New/edit Cancel | Change an owned draft, then editor Cancel | Original file existence/content and no committed draft; retain unrelated concurrent writes as conflicts |
| Duplicate names | Create a second owned row with the same name | Distinct positive IDs and two full display labels |
| Delete | Owned row More > Delete; confirm dialog identifies that full label | Profile dialog uses Delete/Cancel, not mapping Yes/No; cancellation preserves it, confirmation removes only that ID |
| Settings apply | Invoke `ProfileApplyButton` in the owned row | Independent included-field hardware read, plus omitted/unrelated targets where available |
| Flyout apply | `ProfilesButton` > `ProfilesListView`; select exact full label | Selection applies immediately; no second Save. Observe popup/host separately from physical effect |

Empty-name/no-included-field validation uses the editor's actual disabled Save state;
do not force Invoke on a disabled button. Included-field success on one WMI panel does
not cover omitted supported fields, unrelated monitors or preserved unavailable contents.

## Profile order and consumers

Create three owned profiles through the preceding recipe. Record the full original array
order privately and compare each owned profile's ID, creation time and monitor contents.
Resolve the middle owned row More > Move up/Move down; verify enabled menu state, invoke
once, then wait for persisted array order. There is no separate Save action.

For ordinary-process drag, use the same row's realized drag-handle bounds and an observed
destination inside `ProfilesList`. Check the pinned winapp drag command before input;
do not invent flags or use menu movement as drag evidence. Reopen the page and re-read
both ordered IDs and unchanged contents. Keep the elevated menu/disabled-drag condition
separate; do not elevate Settings to obtain an ordinary-input result.

Read consumer order independently from the flyout, CLI `profiles`, and both Light Switch
pickers. Disabled companion pickers leave their rows unobserved, not implied by the other
consumers. Restore original associations before deleting owned profiles and restore the
relative order of all original rows, not just the owned subset.

## Conditional integration recipes

The following recipes define source-grounded preparation and observation, not completed
live confirmation. Use them only when their original-state and recovery requirements can
be met with the existing helpers. Otherwise retain the exact missing condition; do not
add a module-local replacement for a missing shared capability.

### Light Switch integration

Preserve original companion enablement/process/window state, Settings navigation,
`LightSwitch\settings.json`, its schedule, shortcut, profile enable flags/IDs, Windows
app/system themes and Power Display hardware before enabling or configuring anything.
An active schedule or other theme writer needs an authorized, reversible isolation plan.
Do not stop unrelated utilities or claim a full companion baseline from one JSON snapshot.

1. Create two owned profiles with independently attainable, distinct safe hardware values.
   In Light Switch's Apply monitor settings expander, locate the dark/light CheckBoxes
   and each adjacent ComboBox in its own card. The source property names are not
   AutomationIds; inspect actual captions and supported patterns.
2. Enable the two associations through UI and select the owned full display labels.
   Confirm `properties.enableDarkModeProfile.value`, `enableLightModeProfile.value`,
   `darkModeProfileId.value` and `lightModeProfileId.value` in the private file.
   Legacy name properties are not the current identity oracle.
3. Read the actual current theme and configured Light Switch shortcut. Drive two successive
   physical shortcut transitions with compatible foreground/integrity; after each, read the
   theme and exact panel hardware. A direct named event is only downstream diagnosis.
4. Rename/reorder an associated owned ID, re-resolve both pickers, then repeat the relevant
   transition. For deletion coverage, delete only an assigned owned ID and observe reference
   clearing; never assign/delete a user's existing profile as the fixture.
5. Restore associations and profile-enable flags before removing other owned profiles.
   Restore schedule, shortcut, original companion lifetime and themes; then verify hardware
   again because theme restoration itself can apply a profile. Restore original files only
   through attributed, quiescent guarded rollback.

### Differential startup restoration

Preserve independent hardware originals before starting the module and include the actual
module lifecycle and sidecar files in the resource plan. Select a safe supported field;
configure the restore option through Settings, not JSON.

1. Through Power Display set a safe value A, confirm it independently, and wait for the
   same monitor's `monitor_state.json` entry to contain A. Exit through the actual tray
   Exit route and confirm that process is gone and the saved value remains A.
2. With the module stopped, set a distinct safe value B through Windows brightness UI
   for a WMI panel, or the authorized physical OSD route for the selected DDC fixture.
   Independently read B and confirm the stored A has not changed. Do not use the Power
   Display CLI/UI for this step: it can update the very saved value being tested.
3. Start through the declared entry route. Observe independent hardware over discovery
   and settling, retaining timestamps. Evaluate the off/on conditions from the checklist;
   do not use initial UI placeholders as the observation.
4. Re-establish A and B independently for the other option. Keep the run-original baseline
   separate from these case baselines, and finish by restoring the original option,
   hardware, logical lifetime and guarded file state after all final startup writes.

For final-save coverage, make the final edit and use tray Exit without deliberately
waiting for a debounce save first; inspect storage after exit. A termination event or
forced kill does not prove the normal shutdown flush. Null/zero and failed-initial-read
conditions still need their isolated/instrumented fixtures; A-versus-B alone cannot cover them.

### Theme surfaces

Keep a table of PowerToys General theme, Windows app theme, Windows system theme and actual
Settings/flyout/profile-editor/mapping-dialog presentation. Preserve the affected original
values and windows before using their ordinary UI controls; no registry-write shortcut
substitutes for the Settings operation.

For each required light/dark surface, change the relevant theme source, observe existing
and freshly opened owned surfaces, and record which source actually affected it. Keep
PowerToys theme changes separate from Windows app-theme changes. A Settings recolor is
not flyout/dialog coverage; source inference is not proof of rendered colors.
If Light Switch is active, use its separately preserved fixture or defer the affected
condition to avoid unintended profile/hardware changes. Cancel owned dialogs, restore
both theme sources and re-observe original surfaces/hardware. Locale changes require the
separate full-Runner/companion preservation contract; do not bundle them into this recipe.

## Condition recording

Use the compact matrices in the [checklist](release-checklist/power-display.md) as the fixed
row definitions. Expand only their declared dimensions, with report-local monitor aliases.
Record each row under its existing child ID using `Add-PtVerificationObservation -Attempt
$attempt -AssertionId $assertionId -Actual $summary -Detail $row`; `$attempt` must belong to
that child's current item and actual producing attempt.

`$row` is a privacy-safe observation object with a matrix row key, dimensions, actual
pre/action/post observations, observer, unmet prerequisites and evidence references. It is
not an inventory schema extension or a second verdict engine. Keep preflight and cleanup
observations in their proper contexts; never attach one item's action to another child.
Review all declared conditions before the existing child judgment. Missing rows remain
explicit; partial WMI coverage cannot pass a compound clamp, scroll or consumer requirement.
Retain an upstream failure and unobserved dependent conditions separately.

## Process and UI ownership

### Borrowed Runner and Settings

Native window geometry is `Rect.Left/Top/Right/Bottom`, not top-level Width/Height.
Compute dimensions from those edges. If launching Settings, record actual brokered
activation: the initial Settings launcher may exit and Runner create another PID.
That launcher is not proof of ownership of the resulting Settings main.

For adaptive navigation at the current DPI, preserve native placement before paired
widening/maximization, capture the realized Settings snapshot before navigation, and
restore placement after Settings cleanup. A collapsed/unexposed rail is not a missing page.
When the coordinator is elevated, prepare an owned ordinary foreground before the Medium
worker and verify token, guarded activation and pointer round trip. Do not elevate the
worker, bypass guards or infer that CLI autopilot changes Windows foreground/UIPI rules.

For a broader run, discover current lifetimes again: an earlier stopped baseline does not
authorize stopping a Runner or module the user has since started. Declare the actual main
Settings HWND as a `Settings` resource in the shared template before navigation. Preserve
its page/expansion/scroll/placement and the original desktop; keep existing windows borrowed.
Record the module's original enabled state, process identity and visible/hidden state
separately. A module-only disable/enable case may replace the module process, but must
restore its logical lifetime and visibility without restarting Runner or closing Settings.
Declare this lifecycle obligation as an `Other` resource with explicit Action/Verify;
do not falsely promise same-HWND preservation across an intentional module transition.

Predeclare the owned focus window, Welcome secondary and standalone surface when selected,
each as a `Window` resource with explicit ownership and cleanup. In a borrowed-module run,
the standalone surface can have the exact GUI `FilePath` on its Window resource: continue
using `Start-PtOwnedProcess` and its exact launch/exit receipt, while the separate logical
lifecycle obligation accounts for the final Runner-started replacement. Do not add a
blanket same-executable Process scope that would misclassify that expected replacement.
Do not append predictable resources after input checkpoints or rewrite an old plan.

Use `Get-PtModuleLifecycleSnapshot` for the selected page and a runtime-resolved Resident
profile. Power Display enablement opens a warning: the generic `Set-PtModuleEnabled`
toggle-and-wait operation does not supply the dialog decision. For this case record the
actual Toggle, discover the owned warning, Invoke its Enable/Cancel button, then use
`Wait-PtModuleLifecycle` to observe the resulting state. Restoration uses the same explicit
warning-aware UI route when needed. Do not turn a wait on an unanswered warning into a
product failure, bypass confirmation with JSON, or use an owned-process shutdown API on
a borrowed singleton. Hide only the run-opened flyout before a lifecycle transition.

Non-hardware Settings checks can use the running borrowed session: shortcut Save/Cancel,
tray/identify visibility, custom-name mapping drafts/CRUD, module entry paths and theme.
Use the shared shortcut recorder and `New-PtExplorerFixture -Workspace $workspace` for
ordinary input/focus; declare its `Window` resource with `Ownership=Owned` and pair it
with `Remove-PtExplorerFixture -Fixture $fixture`. No text/event logger or deliberate
English layout is needed to observe Power Display activation and focus dismissal.
Create this fixture as the first UI-producing preparation, from the run's stable original
top-level foreground, before Settings navigation, modal input or module replacement.
Explicitly foreground-check that original HWND first. The fixture independently captures
its creation-time desktop: a transient WinUI `InputSiteWindowClass` captured after control
interaction may no longer be activatable at removal. Do not overwrite that fixture
baseline or mark it Closed when its restore guard fails.
Do not declare generic `pwsh.exe` as the fixture's Process scope: that would also retain
unrelated pre-existing controllers and later reporter processes. The Explorer adapter
tracks only its new exact-folder HWND, not ownership of the shared Explorer process.
Restore exact original bindings and fixture lifetime. Custom mappings may use a manually
entered value and an owned name without inventing a monitor, but their downstream naming
effect still requires a real matching capability. Do not seed profiles or monitor JSON
to make disabled hardware-dependent controls available.

Keep private module/global/Light Switch file baselines before the first edit. Restore
semantic UI values first and compare original bytes/existence. If rollback is still needed,
use the existing guarded helpers only while the corresponding writers are quiescent.
Do not close borrowed Settings or stop unrelated utilities merely to force byte equality.
Account for every final module startup and reread both UI/cache-visible values and files
after it; a later write can invalidate an earlier restoration receipt.

An application-language test needs a real full-Runner restart and preservation of all
affected companions, not just this module. Use the shared `Restart-PtRunner` contract
only after its `Prepare`/logical-window/affected-file obligations are concretely satisfied.
Otherwise retain that exact prerequisite and continue module-local checks. No UAC,
policy editing, installation, physical disconnection, crash injection or unsafe monitor
input/power change is implied by a request to maximize safe coverage.

### Committing Settings choices

For `Mouse wheel increment` and `Tray icon mouse wheel mode`, preserve both the original
selected label and typed persisted value. Resolve the exact named ComboBox, expand it,
and find the exact desired ListItem under that owner. A substring query for `1` also
matches `10` and `15`; duplicate provider representations must be deduplicated by actual
UIA runtime identity with `Select-PtUniqueUiElement`.

Match the live option bounds to its exact-name winapp search result, require a complete
query and one distinct selector, then use a normal scoped `click`. Verify both
`Get-PtComboBoxSelection` and the corresponding `properties.mouse_wheel_increment` or
`properties.mouse_wheel_control_mode` before continuing. Keep a selection-only failure:
Select-then-Collapse can show a new label without committing the installed control.
Restore through the same committed path, rejecting intervening values outside the
original and explicitly requested states. This exercises configuration, not wheel
delivery or hardware clamping.

### Resolving owned mapping cards

Expand/scroll the exact `Custom name mappings` Group. Its `Add mapping` Text belongs to
the actual Button ancestor. After Invoke, wait for the required enabled Edit controls
and read back their values; modal existence alone is insufficient.

For an existing owned mapping, construct its current header from the actual saved value
and owned name: `('0x{0:X2} {1} {2}' -f $value, [char]0x2192, $ownedName)`.
Find that exact Text, then walk to the bounded Group containing exactly two action
Buttons. Do not target the Group's accessible Name after a rename; virtualization can
leave it stale. Prefer the unique action Name/HelpText. If both actions are unnamed,
corroborate the current nonoverlapping left Edit/right Delete geometry with scoped pixels
before choosing; ambiguity stops input.

Editing retains the code/value/scope unless explicitly changed. Save/Cancel on the editor
are distinct from the deletion dialog's Yes/No. After either closes, observe disappearance
before resolving another row. Confirm actual persisted owned data after each commit;
do not capture unrelated names or infer that a manual mapping changed absent hardware.

### Module restoration receipts

The module driver must persist its original receipts before the first UI/input operation,
not only keep them in controller variables. Use a private, non-synced recovery directory
outside the shareable run/archive. Keep its file identities/hashes and phase in the
declared resource plan; do not put private snapshots in `Add-PtVerificationObservation`.

For the original foreground layout, after loading the existing desktop/layout/report
helpers, `$privateRecoveryRoot` is that already prepared private directory:

```powershell
$layoutPath = Join-Path $privateRecoveryRoot 'power-display-original-layout.json'
if (Test-Path -LiteralPath $layoutPath) { throw 'Existing baseline: resume from it, do not recapture.' }
$originalTarget = Get-PtWindowIdentity -Hwnd (Get-PtForegroundWindow).hwnd
$originalLayout = Get-PtKeyboardLayoutSnapshot -Target $originalTarget
Write-PtReportText -Path $layoutPath -Text (ConvertTo-Json $originalLayout -Depth 10)
$savedLayout = ConvertFrom-PtReportJson ([IO.File]::ReadAllText($layoutPath))
if ($savedLayout.Layout -ne $originalLayout.Layout -or
    $savedLayout.Target.processStartTicks -ne $originalLayout.Target.processStartTicks) {
    throw 'Original layout receipt did not round-trip.'
}
```

Persist actually observed owned post-layouts separately when they occur. On continuation,
verify receipt hashes and original identity, then load with `ConvertFrom-PtReportJson`;
do not replace a missing original with the current layout. Outer coordinator, focus
fixture and Runner baselines have distinct owners and must not overwrite one another.
This is caller wiring, not a generic controller-recovery implementation; unknown IME
state or a vanished target remains outside the shared thread-layout guarantee.

Restore the shortcut through `Restore-PtShortcutSnapshot` while the page/editor is enabled,
including its UI HelpText comparison. Verify its actual activation before returning the
module to an originally disabled state. Do not schedule another shortcut UI restore after
disable; later file comparison is read-only. If a changed binding can no longer be restored
through an authorized live editor, retain that failure rather than bypassing shared checks.

### Launch-owned standalone instance

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
2. Restore profile associations/order, shortcut binding/UI and other option/mapping semantics
   before disabling their controls. Restore complete clipboard formats
   before releasing its owner if a copy case ran; use the [shared keeper](clipboard-guard.md).
3. Exit only owned writers through their shipped shutdown action, then capture their
   attributable post-state. Retain all launch/exit errors and unexpected recovery markers.
4. Perform selected-file or quiescent-directory guarded rollback for declared data paths. Restore
   original enablement/lifetime if the chosen scope changed it, accounting for restart writes.
5. In the cleanup plan, load each registered original Settings snapshot from
   `(Get-PtActiveResourceSession).Settings` with `ConvertFrom-PtReportJson`, restore it with
   `Restore-PtSettingsUiSnapshot`, then restore the original desktop. For a normal visible
   original Settings window, the template later checks the same state without refocusing.
   Require that no-op condition; hidden/minimized originals need separate preservation work.
6. After these last UI/foreground writes, load the original from its private receipt and call
   `Restore-PtKeyboardLayoutSnapshot -Snapshot $originalLayout -ExpectedLayout $knownOwnedLayouts`.
   Independently read it back again. A lost original cannot be reconstructed at cleanup;
   never accept an unexplained current layout as an owned expected value. Do not use the
   reporting-only callback to mutate state.
7. Compare after the last writer/restart: data bytes/existence, enabled state, owned-process
   absence, borrowed identities, native placement, pointer and layout. Report unowned logs
   and conflicts separately. A departed generic script host cannot be recreated or erased
   from a frozen scope to turn a historical resource failure into success.

Keep the original baseline across retries. A template success, cleanup callback or settings
hash alone cannot certify hardware, process, clipboard and desktop restoration together.
