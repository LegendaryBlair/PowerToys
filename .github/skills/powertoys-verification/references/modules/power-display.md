# Power Display - module verification profile

## Module facts

| Key | Value |
|---|---|
| Module/source | `PowerDisplay` / **Power Display**; `src\modules\powerdisplay` |
| GUI | `<install>\WinUI3Apps\PowerToys.PowerDisplay.exe`, WinUI 3; multiple same-class hidden hosts can coexist. Resolve the content host, not the first HWND |
| CLI | GUI directory's `PowerToys.PowerDisplay.Cli.exe`; shim `<install>\bin\PowerToys.PowerDisplay.CLI.exe` |
| Data root | `%LOCALAPPDATA%\Microsoft\PowerToys\PowerDisplay`; startup writes settings/profiles/monitor state |
| Recovery markers | `discovery.lock`, `crash_detected.flag`; preserve existing markers, stop ordinary launch |
| Shortcut | Default Win+Ctrl+Shift+P; discover current `properties.activation_shortcut` |
| Events | Shared catalog `PowerDisplay.Toggle`, `PowerDisplay.Terminate`; not physical-entry proof |
| Lifetime | Runner-resident or standalone; Escape/deactivation/window Close hide, not exit |

The [checklist](../release-checklist/power-display.md) owns expectations.
Entry, Settings, WMI brightness and owned-profile operations have observation-backed
recipes below. DDC/native-range, touch, multi-monitor and fault conditions still require
their own fixtures. UI, persisted data and independent hardware observations are distinct.

## Entry paths

Establish [ownership/baselines](#fixtures-and-restoration) before activation.
Check recovery markers and startup flags: launch itself can probe/restore hardware.

| Intent | Route |
|---|---|
| Settings | Snapshot before navigation; realize/select `PowerDisplayNavItem`, then use the module switch/warning or **Open Power Display** button. |
| Quick Access | Actual module entry with Runner active, not direct launch. |
| Shortcut | Compatible foreground, current chord, observed visibility change. |
| Tray | Exact Power Display Button in taskbar/overflow; click and verify foreground. |
| Standalone | Absent instance, owned GUI launch without arguments; no Runner startup. |
| Diagnosis | `PowerDisplay.Toggle`, not a physical-entry substitute. |
| CLI | Installed executable/current help; unavailable provider is not auto-started. |

## UI state-transition map

Settings can coexist independently. `Visible flyout` includes settled empty/monitor content;
`Resident` means hidden, not exited. Observe each destination; this is not a fixed sequence.

| Current state | Trigger / condition | Next state | State landmarks |
|---|---|---|---|
| Exited | Standalone launch, permitted startup | Scanning | Owned WinUI host, progress/scanning content |
| Resident | Tray click/current shortcut/toggle route | Visible flyout | Visible uncloaked host, content and footer |
| Visible flyout | Open refresh chevron | Refresh menu | MenuItems within the flyout popup |
| Refresh menu | Invoke Refresh | Scanning | `ScanningMonitorsTextBlock`/ProgressBar |
| Scanning | Discovery completes after the host lost activation | Resident | Same process; hidden host, settled discovery readable through CLI |
| Scanning | Discovery finishes with no available controls | Empty flyout | `NoMonitorsInfoBar`, footer buttons |
| Scanning | Discovery finishes with available monitors | Monitor flyout | Monitor cards and applicable controls |
| Visible flyout | Escape, deactivation or window Close | Resident | Host hidden, same process still present |
| Visible flyout | Open saved-profile switcher | Profile picker | Profile ListView in popup |
| Profile picker | Select a profile; host stays visible | Visible flyout | Picker closes; re-resolved visible content host |
| Profile picker | Select a profile; host loses activation | Resident | Picker closes; same process, hidden host |
| Resident | Right-click actual tray icon | Tray menu | Module-owned native `#32768` menu |
| Tray menu | Invoke Exit | Exited | Exact process and native siblings disappear |
| Settings page | Request protected enablement | Warning dialog | Modal warning with Enable/Cancel |
| Warning dialog | Enable | Settings page | Dialog dismissed, page operable |
| Warning dialog | Cancel | Settings page | Dialog dismissed, page operable |
| Settings page | Add/edit profile or custom mapping | Editor draft | Modal named fields and Save/Cancel |
| Editor draft | Save valid draft | Settings page | Dialog closes, owning list available |
| Editor draft | Cancel | Settings page | Dialog closes without committing draft |
| Settings page | More > Delete on an owned row | Delete confirmation | Mapping Yes/No or profile Delete/Cancel modal |
| Delete confirmation | Confirm owned row | Settings page | Dialog closes, owning list available |
| Delete confirmation | Cancel | Settings page | Dialog closes, owning list available |
| Settings page | Welcome footer; no pre-existing secondary | Welcome window | New same-process HWND with module navigation |
| Welcome window | Select Power Display | Welcome window | Module content and Open Power Display button |

## Control locator and interaction index

Use recorded inspect/search and `Get-PtUiElements`; reject incomplete/ambiguous matches.
Re-resolve after transitions. Confirm runtime IDs/types/patterns; `x:Uid` is not an ID.
Names below are English observations. See [Settings readiness](../power-display-fixtures.md#borrowed-runner-and-settings)
for native geometry, brokered ownership, foreground integrity and adaptive navigation.

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Open refresh menu | Settled host, right footer | Button left of `SettingsBtn`; not Link/Profile controls | [Footer recipe](../power-display-fixtures.md#flyout-footer-and-hidden-owner), scoped Invoke. |
| Refresh | Open menu | MenuItem ID `RefreshButton` | Invoke once; observe settled discovery. Reopen a hidden resident host without repeating Refresh. |
| Identify | Refresh menu; hardware | MenuItem ID `IdentifyButton` | Invoke; separately observe overlays. |
| Dismiss | Actual foreground flyout | Exact HWND | Guard, then `Send-PtChord -Hwnd $hwnd -Key 0x1B`; check hidden/resident state. |
| Open from tray | Taskbar/owned overflow | Button Name `Power Display` | `Find-PtRunnerTrayControl`, physical Click, foreground check. |
| Open tray menu | Visible icon, flyout not covering it | Fresh Button | Guarded right-click; resolve module-owned `#32768` menu. |
| Exit | Owned native menu | MenuItem Name `Exit` | Supported Invoke inside `Stop-PtOwnedProcess`; register siblings first. |
| Open Settings | Flyout footer | Button ID `SettingsBtn` | Declare ownership/side effects before Invoke. |
| Enable/disable | Selected module page | `Enable Power Display` Button, TogglePattern | Toggle; answer warning Enable/Cancel; wait lifecycle. |
| Change visibility | Settings flyout options | CheckBox Names `Show system tray icon`, `Show profile switcher button`, `Show identify monitors button` | Toggle; compare file/UI and actual tray/menu. Profiles add a saved-profile prerequisite. |
| Choose wheel option | Settings flyout options | ComboBox Names `Mouse wheel increment`, `Tray icon mouse wheel mode` | [Committed-choice recipe](../power-display-fixtures.md#committing-settings-choices), not selection-only readback. |
| Record shortcut | Activation card | Button ID `EditButton`, HelpText | [Recorder](../shortcut-recorder.md): `PowerDisplayNavItem`, segments `properties`, `activation_shortcut`; separately drive chords. |
| Change monitor controls | Exact expanded monitor | Local CheckBox | Toggle, handle warning; hiding is not disconnecting. |
| Set level | Exact monitor card; linking accounted for | Local feature Slider | [WMI recipe](../power-display-fixtures.md#wmi-brightness); physical input and independent read. |
| Choose discrete value | Enabled monitor feature | Local Button > ListItem | Open/Select only with physical recovery and hardware readback. |
| Link/exclude | Eligible monitor cards | `LinkLevelsToggle`, `IndividualDisplaysToggle`, local exclude ToggleButton | Confirm patterns; toggle/expand exact monitor. |
| Create profile | Settings Profiles; real monitors | Add profile Button; `ProfileNameTextBox` Edit | [Editor recipe](../power-display-fixtures.md#owned-monitor-profiles), Save/Cancel. |
| Apply profile | Exact owned ID | Settings row `ProfileApplyButton`; popup `ProfilesListView` ListItem | Invoke Apply or Select the exact popup item; no extra Save. Independently read hardware. |
| Edit profile | Owned row More | Edit MenuItem; name Edit | Editor recipe; Save/Cancel; re-resolve by ID. |
| Delete profile | Owned row More | Delete MenuItem; profile Delete/Cancel modal | Confirm caption/selected ID; do not reuse mapping Yes/No locators. |
| Reorder profile | `ProfilesList`, owned row by current display name/ID | Move up/down MenuItems or row drag handle | [Ordering recipe](../power-display-fixtures.md#profile-order-and-consumers); menus commit immediately, drag uses live bounds. |
| Open mapping | `Custom name mappings` Group | `Add mapping` Text's Button ancestor | Expand/scroll, Invoke, wait for enabled Edit fields. |
| Fill mapping | Owned editor | `VcpCodeComboBox`, `ValueComboBox`, `CustomValueTextBox`, `CustomNameTextBox` | Select/fill/read back; Save/Cancel. Manual values need no monitor. |
| Edit/delete mapping | Exact owned current card | Header Text > bounded two-Button Group | [Card recipe](../power-display-fixtures.md#resolving-owned-mapping-cards); Delete uses Yes/No, not editor Save/Cancel. |
| Copy capabilities | Exact Settings monitor | Details/copy Buttons | Complete clipboard guard; VCP list, not diagnostics. |
| Read CLI | Installed executable | Native path/current help | Separate streams/exit; typed JSON, sanitized data. |
| Open Welcome | Footer > owned secondary | `OOBENavItem`; `Power Display` ListItem | Select; wait for Open button; inspect shortcut pixels, not an assumed `HotkeyActivation` ID. |
| Read Light Switch warning | Power Display disabled | InfoBar Text starting `Enable PowerDisplay module` | Resolve unique full caption and actual visibility; no profile-apply claim. |
| Associate Light Switch | Prepared companion | Light/dark ComboBoxes and CheckBoxes | [Integration recipe](../power-display-fixtures.md#light-switch-integration), owned IDs/actual shortcut. |
| Compare startup restore | Prepared hardware/lifecycle | Startup restore CheckBox; entry/Exit | [Differential recipe](../power-display-fixtures.md#differential-startup-restoration), saved A versus physical B. |
| Observe themes | Prepared theme fixture | General / Windows Personalization | [Surface recipe](../power-display-fixtures.md#theme-surfaces), each actual surface. |

### Read-out notes

- Read live files with `Read-PtSharedFileText` and strict JSON; [field shapes](../power-display-fixtures.md#module-data-read-outs)
  are data paths, not UI selectors. Null/unread is not zero.
- Profiles use positive `id`, `createdDate`, `monitorSettings` and **array order**,
  not a per-profile `order` property. The owned-ID helper never selects by name/position.
- WMI reads use complete canonical monitor identity, not EDID/model alone. Keep IDs
  private and project only owned aliases, numeric values and timestamps into evidence.
- [CLI matrices](../release-checklist/power-display.md#command-line) distinguish parse,
  target, capability and confirmation-guard failures; retain stdout/stderr/exit separately.
- Configuration, cached CLI state, pixels and independent hardware are separate observations.
  Theme sources and each actual surface also require separate read-outs.

### Observation rules

Poll structural readiness separately from expected results. Missing a fast scanning state
is not proof of failure. Use the [condition recording recipe](../power-display-fixtures.md#condition-recording)
to retain each matrix row without adding inventory fields or auto-generating verdicts.
[Passive scoped capture](../helper-workflow.md) avoids refocusing popups; check
foreground/geometry before and after. Images remain candidates until accepted.

## Troubleshooting

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| No process/monitor/editor | Check entry scope, recovery markers and actual capability. Add profile needs monitor rows. | Enabled state is not readiness; never seed support in JSON. |
| Input guard or navigation fails | Use [Settings readiness](../power-display-fixtures.md#borrowed-runner-and-settings) and fresh physical bounds. | No forced activation/elevation or assumed RDP cause. |
| Tray popup has zero foreground | Preserve physical refusal; inspect native owned MenuItem separately. | Invoke may work, but is not physical input proof. |
| Stale tray entries | Retain counts, bounded product-only hover, re-enumerate. | Stale duplicates alone do not prove a lifecycle defect. |
| UI/file/hardware disagree | Keep all readings; use committed choices and exact target/observer. | Accepted input/cache values are not hardware success; do not repeat until favorable. |
| Refresh/picker hides parent | Same-process visibility check, ordinary reopen, fresh controls. | Hidden is not exited or failed discovery. |
| Duplicate/stale row name | Resolve current owned numeric ID/full label and row HelpText. | Bare name, ordinal or recycled Group.Name is not identity. |
| Disabled shortcut editor at cleanup | Restore/verify before disable; no redundant late UI restore. | JSON equality alone does not certify UI restoration. |
| Snapshot/restore fails | [Selected paths](../power-display-fixtures.md#files-and-hardware), attributed writers and original receipts. | No live-log shutdown, conflict overwrite or retrospective PASS. |

## Fixtures and restoration

### Resource inventory

| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| Owned process | Standalone | Exact launch/sibling receipt | Tracked tray Exit | Exact process/icon/service gone |
| Selected files/global state | Launch/edit | [Private originals](../power-display-fixtures.md#files-and-hardware), existence and owned effects | Quiescent guarded rollback | Original bytes/existence/enablement |
| Settings/desktop | Any UI | Borrowed snapshots before navigation/input | Existing paired restore; close only owned windows | Original identity/page/placement/pointer |
| Owned Explorer | Focus/hotkeys | Stable creation-time foreground before WinUI interaction | `Remove-PtExplorerFixture` | Both creation/run desktop baselines; owned folder/window absent |
| Hardware | Hardware cases | [Independent pre-startup values](../power-display-fixtures.md#wmi-brightness) | Restore while controls live | Same instance's original readings |
| Profiles/mappings | CRUD/application | Owned IDs, original order/references | Associations before owned-row deletion; guarded file restore | Original semantics/bytes/hardware |
| Light Switch/theme | Integration | [Companion baseline](../power-display-fixtures.md#light-switch-integration) | Restore bindings/schedule/IDs/themes/lifetime | Original state and final hardware |
| Layout receipt | Input | [Persisted original](../power-display-fixtures.md#module-restoration-receipts) | Guarded restore after desktop | Same target/numeric layout; no IME claim |
| Clipboard keeper | Capability copy | Complete original formats | Shared keeper before release | Every original format |

### Helper boundaries

Use the [fixture guide](../power-display-fixtures.md) and unchanged shared resource APIs.
The module adapter only reads WMI/selects owned IDs; it neither writes hardware nor owns
resources. File rollback cannot restore physical values. No fault/OSD rescue is supplied.

### Restoration order

1. Restore hardware, associations/order, shortcut/UI and options while controls are enabled;
   cancel drafts and restore clipboard.
2. Quiesce authorized writers, retain attributed post-state, guardedly restore files and
   original lifetime/enablement; account for final startup/theme writes.
3. Explicitly restore registered Settings and desktop, then the persisted original layout
   from known owned post-layouts. Require the template's later Settings restore to be a
   checked no-op. Follow [release order](../power-display-fixtures.md#release-and-verify).

### Restoration verification

Compare every touched resource against its original baseline after the final writer:
files/existence, enablement, hardware, process/popups, borrowed identities and desktop.
Separate retained logs; preserve conflicts rather than replacing the baseline.
