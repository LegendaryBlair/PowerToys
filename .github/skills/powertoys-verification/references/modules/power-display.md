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
Entry paths, warning-aware enablement, shortcuts, visibility, mapping CRUD, OOBE and
read-only CLI have live observation support. Hardware and saved-monitor-profile guidance
remains conditional; configuration readback does not establish its downstream effect.

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
| Settings page | More > Delete on an owned mapping | Delete confirmation | Modal Yes/No buttons |
| Delete confirmation | Yes | Settings page | Dialog closes, mapping list available |
| Delete confirmation | No | Settings page | Dialog closes, mapping list available |
| Settings page | Welcome footer; no pre-existing secondary | Welcome window | New same-process HWND with module navigation |
| Welcome window | Select Power Display | Welcome window | Module content and Open Power Display button |

## Control locator and interaction index

Use recorded `Invoke-PtWinApp` inspect/search and `Get-PtUiElements`; reject incomplete or
ambiguous matches. Re-resolve after transitions. XAML `x:Uid` is not an AutomationId.
Names below are English observations; resolve localized counterparts in other locales.
Source-named hardware/profile controls still require exposed ID/type/pattern confirmation.

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Open refresh menu | Empty flyout footer | Unique unnamed Button beside `SettingsBtn` | Corroborate glyph/tree, then Invoke; never first-match selection. |
| Refresh | Open menu | MenuItem ID `RefreshButton` | Invoke once; observe scanning then settled content. |
| Identify | Refresh menu; hardware | MenuItem ID `IdentifyButton` | Invoke; separately observe overlays. |
| Dismiss | Actual foreground flyout | Exact HWND | Guard, then `Send-PtChord -Hwnd $hwnd -Key 0x1B`; check hidden/resident state. |
| Open from tray | Taskbar/owned overflow | Button Name `Power Display` | `Find-PtRunnerTrayControl`, physical Click, foreground check. |
| Open tray menu | Visible icon, flyout not covering it | Fresh Button | Guarded right-click; resolve module-owned `#32768` menu. |
| Exit | Owned native menu | MenuItem Name `Exit` | Supported Invoke inside `Stop-PtOwnedProcess`; register siblings first. |
| Open Settings | Flyout footer | Button ID `SettingsBtn` | Declare ownership/side effects before Invoke. |
| Enable/disable | Selected module page | Button Name `Enable Power Display`, TogglePattern | Snapshot; toggle; explicitly answer `PrimaryButton` Enable / `CloseButton` Cancel; wait lifecycle. |
| Change visibility | Settings flyout options | CheckBox Names `Show system tray icon`, `Show profile switcher button`, `Show identify monitors button` | Toggle; compare file/UI and actual tray/menu. Profiles add a saved-profile prerequisite. |
| Choose wheel option | Settings flyout options | ComboBox Names `Mouse wheel increment`, `Tray icon mouse wheel mode` | [Committed-choice recipe](../power-display-fixtures.md#committing-settings-choices), not selection-only readback. |
| Record shortcut | Activation card | Button ID `EditButton`, HelpText | [Recorder](../shortcut-recorder.md): `PowerDisplayNavItem`, segments `properties`, `activation_shortcut`; separately drive chords. |
| Change monitor controls | Exact expanded monitor | Local CheckBox | Toggle, handle warning; hiding is not disconnecting. |
| Set level | Exact monitor card | Brightness/contrast/volume Slider | Required physical input; settled commit and independent hardware read. |
| Choose discrete value | Enabled monitor feature | Local Button > ListItem | Open/Select only with physical recovery and hardware readback. |
| Link/exclude | Eligible monitor cards | `LinkLevelsToggle`, `IndividualDisplaysToggle`, local exclude ToggleButton | Confirm patterns; toggle/expand exact monitor. |
| Apply profile | Exact owned row | `ProfilesList` / `ProfilesListView` | Settings Apply invokes; flyout Select commits immediately. |
| Edit profile | Owned row More | Edit MenuItem; `ProfileNameTextBox` Edit | Save/Cancel distinctly; preserve unavailable saved fields. |
| Delete profile | Owned row More | Delete MenuItem and dialog | Confirm/cancel exact stable ID. |
| Reorder profile | Owned Settings row | Move up/down MenuItems or drag row | Menu commits; ordinary drag only. Elevated menu remains available. |
| Open mapping | `Custom name mappings` Group | `Add mapping` Text's Button ancestor | Expand/scroll, Invoke, wait for enabled Edit fields. |
| Fill mapping | Owned editor | `VcpCodeComboBox`, `ValueComboBox`, `CustomValueTextBox`, `CustomNameTextBox`, scope controls | Select/code/value/name; read actual Edit values; Save/Cancel. No monitor needed for manual-value CRUD. |
| Edit/delete mapping | Exact owned current card | Header Text > bounded two-Button Group | [Card recipe](../power-display-fixtures.md#resolving-owned-mapping-cards); Delete uses Yes/No, not editor Save/Cancel. |
| Copy capabilities | Exact Settings monitor | Details/copy Buttons | Complete clipboard guard; VCP list, not diagnostics. |
| Read CLI | Installed executable | Native path/current help | Separate streams/exit; typed JSON, sanitized data. |
| Open Welcome | Main footer > new secondary | `OOBENavItem`; ListItem `Power Display` | Select; wait for `Open Power Display` content; inspect shortcut pixels, not absent `HotkeyActivation` ID. |
| Read Light Switch warning | Power Display disabled | InfoBar Text starting `Enable PowerDisplay module` | Resolve unique full caption and actual visibility; no profile-apply claim. |

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
- Check missing-value errors with the flag in both positions: `--json set --brightness`
  versus `set --brightness --json`. A parser may consume the trailing flag as the missing
  value and emit human text. Preserve exact streams; exit 7 alone cannot establish JSON format.
- `get` without a selector reads all monitors; missing-selector rejection applies to
  `set`/`up`/`down`. Target resolution precedes range validation: an absent target may
  return exit 1 even for an out-of-range value. Exit 2 needs a valid target.
- An enabled Add profile button may produce no editor when discovery has no monitor rows.
  Observe that prerequisite; never create fake monitor/profile JSON to unlock it.
- PowerToys theme, effective Windows app theme and each rendered surface are separate.
  Changing PowerToys to Dark can recolor Settings without making the flyout or mapping
  dialog dark. Capture actual surfaces; a Windows-theme fixture needs its own preservation.

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
| Native popup reports no interactive desktop | Check InputDesktop/foreground separately; actual MenuItem Invoke can work while foreground is zero. | Preserve physical refusal; no assumed disconnect or direct menu message. |
| Stale tray entries after visibility change | Preserve counts; bounded product-only hover and fresh enumeration. | Stale duplicates alone do not establish a lifecycle defect. |
| Choice/row and file disagree | Use committed-choice/current-card recipes and realized fields. | Selection or recycled Group.Name is not persistence/identity. |
| Profile/feature unavailable | Check build, capability, exact row, protected option and policy. | No independent outcome for unreachable actions; never seed support in JSON. |
| Partial rollback | Inspect owned-path equality and unowned log differences; retain conflicts. | User-state equality is not whole-directory equality. |
| Whole-root snapshot hits an open interface log | Use the exact selected-file adapter while its selected writers are quiescent. | Never stop the borrowed logger or silently skip a failed whole-root read. |
| Explorer closes but fixture restoration fails | Inspect its immutable creation-time foreground; create future fixtures before transient WinUI control/modal interaction. | Gone window/folder does not prove the fixture's independent desktop restore; do not rewrite its receipt. |

## Fixtures and restoration

### Resource inventory

| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| `Start-PtOwnedProcess` | Standalone | Absent-instance launch, PID/start/path/siblings | Tracked tray Exit; event only as declared cleanup | Process/icon/service absent; original Runner state |
| Selected-file snapshot | Launch/edit with live siblings | Private bytes/existence; exact [paths](../power-display-fixtures.md#files-and-hardware) | Quiesce selected writers; `Restore-PtFileSetSnapshot` | Selected data hashes/existence; no whole-directory claim |
| Global/Light Switch snapshots | Enablement/migration | Private originals; attributable writes only | Semantic restore, guarded rollback | Original enablement/references/bytes |
| Settings snapshot/dialogs | Settings | Borrowed navigation/placement; owned creations | Cancel drafts, shared restore/owned close | Original supported state/identity |
| Desktop snapshot/overflow | Input/capture | Pre-input baseline, owned popup transition | Close owned popup, paired restore | Original foreground/placement/pointer |
| `New-PtExplorerFixture` | Hotkeys/focus dismissal | Create from stable original foreground before UI transitions; no generic `pwsh` scope | `Remove-PtExplorerFixture`; final original layout after UI/desktop | Owned window/folder absent; both fixture and run desktop baselines |
| Hardware baseline | Hardware cases | Case-owned edits; independent values/recovery | Restore while controls live | Original hardware, not cached values |
| Owned profiles/mappings; clipboard keeper | Editing/copy | Owned rows; complete private format backup | Restore order/references/formats before exit | Original semantics/bytes/hardware/formats |

### Helper boundaries

Use [fixture recipes](../power-display-fixtures.md) and shared resource/cleanup APIs.
Guarded single-file rollback requires existing files; selected-file rollback supports absence
without reading live sibling logs. Whole-directory rollback additionally preserves directories.
Neither restores hardware or owns a borrowed singleton. No fault/OSD rescue helper exists.
Resume loads the original persisted resource plan, not a reordered reconstruction.
Use the shared owned Explorer window when only ordinary foreground is needed. A generic
`pwsh.exe` Process scope also captures controller/reporter lifetimes and cannot be narrowed
after a run starts. Power Display hotkey/focus checks need no English-layout keyboard logger.

### Restoration order

1. Restore hardware/UI semantics while controls live; cancel drafts and restore clipboard.
2. Exit only owned writers; retain attributable post-state and unexpected recovery markers.
3. Guarded-restore data bytes/existence; restore original enablement/lifetime, accounting for startup writes.
4. Explicitly restore registered Settings snapshots and the original desktop in the cleanup
   plan before its final keyboard-layout step. For an originally visible, normal Settings
   main, the template's subsequent identical restoration is a checked no-op; verify that
   prerequisite rather than assuming it for hidden/minimized windows.
5. Guardedly restore the original thread layout from known owned post-layouts, then compare
   after all final writes. Keep private recovery outside archives.

### Restoration verification

Compare every touched resource against its original baseline after the final writer:
files/existence, enablement, hardware, process/popups, borrowed identities and desktop.
Separate retained logs; preserve conflicts rather than replacing the baseline.
