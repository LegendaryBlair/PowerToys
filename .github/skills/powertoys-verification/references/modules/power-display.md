# Power Display - module verification profile

## Module facts

| Key | Value |
|---|---|
| Module/source | `PowerDisplay` / **Power Display**; `src\modules\powerdisplay` |
| GUI | `<install>\WinUI3Apps\PowerToys.PowerDisplay.exe`, WinUI 3; rediscover PID/start/HWND |
| CLI | GUI directory's `PowerToys.PowerDisplay.Cli.exe`; shim `<install>\bin\PowerToys.PowerDisplay.CLI.exe` |
| Data root | `%LOCALAPPDATA%\Microsoft\PowerToys\PowerDisplay`; startup writes settings/profiles/monitor state |
| Recovery markers | `discovery.lock`, `crash_detected.flag`; preserve existing markers, stop ordinary launch |
| Shortcut | Default Win+Ctrl+Shift+P; discover current `properties.activation_shortcut` |
| Events | Shared catalog `PowerDisplay.Toggle`, `PowerDisplay.Terminate`; not physical-entry proof |
| Lifetime | Runner-resident or standalone; Escape/deactivation/window Close hide, not exit |

The [checklist](../release-checklist/power-display.md) owns expectations.
Standalone empty-state/refresh/dismissal/tray/CLI mechanics have live observation support.
Settings/profile/hardware guidance remains source-grounded, not fully live-confirmed.

## Entry paths

Establish [ownership/baselines](#fixtures-and-restoration) before activation.
Check recovery markers and startup flags: launch itself can probe/restore hardware.

| Intent | Route |
|---|---|
| Settings | Snapshot before navigation; Power Display switch/warning or launch button. |
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
| Scanning | Discovery finishes with no available controls | Empty flyout | `NoMonitorsInfoBar`, footer buttons |
| Scanning | Discovery finishes with available monitors | Monitor flyout | Monitor cards and applicable controls |
| Visible flyout | Escape, deactivation or window Close | Resident | Host hidden, same process still present |
| Visible flyout | Open saved-profile switcher | Profile picker | Profile ListView in popup |
| Profile picker | Select a profile | Visible flyout | Picker closes; host remains available |
| Resident | Right-click actual tray icon | Tray menu | Module-owned native `#32768` menu |
| Tray menu | Invoke Exit | Exited | Exact process and native siblings disappear |
| Settings page | Request protected enablement | Warning dialog | Modal warning with Enable/Cancel |
| Warning dialog | Enable | Settings page | Dialog dismissed, page operable |
| Warning dialog | Cancel | Settings page | Dialog dismissed, page operable |
| Settings page | Add/edit profile or custom mapping | Editor draft | Modal named fields and Save/Cancel |
| Editor draft | Save valid draft | Settings page | Dialog closes, owning list available |
| Editor draft | Cancel | Settings page | Dialog closes without committing draft |

## Control locator and interaction index

Use recorded `Invoke-PtWinApp` inspect/search and `Get-PtUiElements`; reject incomplete or
ambiguous matches. Re-resolve after transitions. XAML `x:Uid` is not an AutomationId.
For source-named Settings controls below, confirm the exposed ID/type/pattern before acting.

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Open refresh menu | Flyout footer | Button with refresh/chevron glyph beside `SettingsBtn` | Inspect pixels/tree. Empty-state UI exposes one unnamed non-Settings Button: require uniqueness, then Invoke. |
| Refresh monitors | Open refresh menu | MenuItem, `AutomationId=RefreshButton` | Unique search within flyout HWND; Invoke once, observe scanning then settled content. |
| Identify monitors | Refresh menu; hardware | MenuItem, source `IdentifyButton` | Confirm pattern, Invoke, observe overlays. |
| Dismiss flyout | Exact foreground host | Current native HWND | `Assert-PtForegroundOrAbort`, then `Send-PtChord -Hwnd $hwnd -Key 0x1B`; observe hidden/resident state. |
| Open from tray | Taskbar/owned overflow | Button, Name `Power Display` | `Find-PtRunnerTrayControl`; scoped `click`, then foreground check. |
| Open tray menu | Visible tray icon | Freshly resolved Button | Check container foreground/target; scoped `click --right`; resolve new module-owned `#32768` HWND. |
| Exit module | Owned native tray menu | MenuItem, localized Name `Exit` | Verify Invoke support; register siblings; use `Stop-PtOwnedProcess` callback. Rediscover numeric menu IDs. |
| Open Settings | Flyout footer | Button, `AutomationId=SettingsBtn` | Declare Settings/Runner side effects before Invoke. |
| Change options | Settings labeled card | Card-local switch/CheckBox/ComboBox | Confirm patterns; Toggle or `Select-PtComboBoxItem`. Protected changes require Enable/Cancel. |
| Record shortcut | Settings activation card | Current shortcut edit button | [Shared recorder](../shortcut-recorder.md) with actual targets; Save/Cancel separately. |
| Change monitor controls | Expanded Settings monitor | Exact identity's CheckBox | Toggle; handle confirmation. Hide is not disconnect. |
| Set monitor level | Correct flyout monitor card | Local brightness/contrast/volume Slider | Use required mouse/touch/wheel/arrows; wait for settled commit. RangeValue cannot prove physical input. |
| Choose discrete value | Enabled monitor feature | Local Button, popup ListItem | Open/Select; independent hardware read and physical recovery. |
| Link/exclude | Eligible monitor cards | Source names `LinkLevelsToggle`, `IndividualDisplaysToggle`; local exclude ToggleButton | Confirm exposed patterns; Toggle linking, expand cards, act on the exact monitor. |
| Apply profile | Settings row/flyout picker | Owned ID/display name in `ProfilesList` / `ProfilesListView` | Settings Apply invokes; flyout selection commits immediately. Keep private rows out of captures. |
| Edit profile | Owned row's More menu | Edit MenuItem; modal `ProfileNameTextBox` Edit | Invoke, inspect fields/capabilities, edit; Save commits, Cancel discards. Preserve unavailable saved fields. |
| Delete profile | Owned Settings row | More > Delete; dialog | Invoke, confirm/cancel; target stable ID. |
| Reorder profile | Owned Settings row | More > Move up/down; current drag row | Menu commits order; drag needs ordinary Settings. Elevated drag absence does not remove menu actions. |
| Edit mapping | Settings custom-name dialog | Source names `VcpCodeComboBox`, `ValueComboBox`, `CustomValueTextBox`, `CustomNameTextBox`, `ApplyToAllToggle`, `MonitorComboBox` | Confirm types/patterns; select code/value/scope, enter name; Save/Cancel. Delete has confirmation. |
| Copy capabilities | Exact Settings monitor | VCP-details/copy Buttons | Invoke inside complete clipboard guard; not diagnostics copy. |
| Read CLI | Installed executable | Native path/current help, no UI locator | Separate stdout/stderr/exit; parse typed JSON and expose only sanitized/owned data. |

### Read-out notes

- Data under `properties`: `activation_shortcut`, `monitor_refresh_delay`, `mouse_wheel_increment`,
  `mouse_wheel_control_mode`, `restore_settings_on_startup`, `max_compatibility_mode`,
  `show_system_tray_icon`, `show_profile_switcher`, `show_identify_monitors_button`,
  `linked_levels_active`, `excluded_from_sync_monitor_ids`, `monitors`, `custom_vcp_mappings`.
- Use `Read-PtSharedFileText`, strict JSON and actual types: scalar Booleans need no `.value`.
  An explicit legacy wrapper must have Boolean `value`; missing/other types are errors.
- `profiles.json`: stable `id`, display `order`, selected fields; `monitor_state.json`:
  runtime/read cache. IDs are not positions. Draft, persistence and hardware are distinct.
- CLI `list --json` exposes `monitors`, including `[]`. Flyout "No monitors detected" and
  CLI "No monitors discovered." are equivalent, not identical captions. Agreement does
  not independently prove physical discovery completeness or a DDC write.
- Preserve null/unread values. Provider absence is exit 10; parse rejection exit 7.
  JSON errors use stderr; help/version remain text with `--json`.

### Observation rules

Poll structural readiness separately from expected results. Missing a fast scanning state
is not proof of failure. [Passive scoped capture](../helper-workflow.md) avoids refocusing
popups; check foreground/geometry before and after. Images remain candidates until accepted.

## Troubleshooting

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| Enabled flag, no process | Check Runner, standalone scope and recovery markers. | Configuration is not readiness. |
| No monitor cards | Observe settled InfoBar/CLI; establish DDC/WMI prerequisites independently. | RDP/display surfaces are not controllable hardware; empty-path evidence is not brightness coverage. |
| Foreground guard refuses Escape after tray Invoke | Preserve error; rediscover icon, physically click, verify exact foreground before keys. | No delivered key means no dismissal outcome; never disable the guard. |
| Covered tray icon/disappearing menu | Refresh overflow ownership, foreground and live bounds before a scoped click. | Stale selectors are invalid targets; termination event cannot pass tray Exit. |
| Profile/feature unavailable | Check build, capability, exact row, protected option and policy. | No independent outcome for unreachable actions; never seed support in JSON. |
| Partial rollback | Inspect owned-path equality and unowned log differences; retain conflicts. | User-state equality is not whole-directory equality. |

## Fixtures and restoration

### Resource inventory

| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| `Start-PtOwnedProcess` | Standalone | Absent-instance launch, PID/start/path/siblings | Tracked tray Exit; event only as declared cleanup | Process/icon/service absent; original Runner state |
| Directory snapshot | Launch/edit | Private bytes/existence; exact [paths](../power-display-fixtures.md#files-and-hardware) | Quiesce, guard post-state, rollback | Original data hashes/existence; separate logs |
| Global/Light Switch snapshots | Enablement/migration | Private originals; attributable writes only | Semantic restore, guarded rollback | Original enablement/references/bytes |
| Settings snapshot/dialogs | Settings | Borrowed navigation/placement; owned creations | Cancel drafts, shared restore/owned close | Original supported state/identity |
| Desktop snapshot/overflow | Input/capture | Pre-input baseline, owned popup transition | Close owned popup, paired restore | Original foreground/placement/pointer |
| Hardware baseline | Hardware cases | Case-owned edits; independent values/recovery | Restore while controls live | Original hardware, not cached values |
| Owned profiles/mappings; clipboard keeper | Editing/copy | Owned rows; complete private format backup | Restore order/references/formats before exit | Original semantics/bytes/hardware/formats |

### Helper boundaries

Use [fixture recipes](../power-display-fixtures.md) and shared resource/cleanup APIs.
Guarded file rollback requires existing files; directory rollback supports absence.
Neither restores hardware or owns a borrowed singleton. No fault/OSD rescue helper exists.
Resume loads the original persisted resource plan, not a reordered reconstruction.

### Restoration order

1. Restore hardware/UI semantics while controls live; cancel drafts and restore clipboard.
2. Exit only owned writers; retain attributable post-state and unexpected recovery markers.
3. Guarded-restore data bytes/existence; restore original enablement/lifetime, accounting for startup writes.
4. Restore Settings/popups/desktop; compare after all final writes. Keep private recovery outside archives.

### Restoration verification

Compare every touched resource against its original baseline after the final writer:
files/existence, enablement, hardware, process/popups, borrowed identities and desktop.
Separate retained logs; preserve conflicts rather than replacing the baseline.
