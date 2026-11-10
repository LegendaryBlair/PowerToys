# Awake - module verification profile

## Module facts

| Fact | Value |
|---|---|
| Module / source | `Awake`; `src\modules\awake` |
| Runtime | `PowerToys.Awake.exe` beside the actual installed Runner; native notification icon/menu, managed background power-request thread |
| Settings UI | WinUI `PowerToys.Settings.exe`; navigation `AwakeNavItem`, under `SystemToolsNavItem` when collapsed |
| Preferences | `%LOCALAPPDATA%\Microsoft\PowerToys\Awake\settings.json`; general enablement is `enabled.Awake` in the parent `settings.json` |
| Lifecycle | Resident when enabled, including passive mode; disabling removes the runtime. Integrated and standalone instances share a singleton mutex |
| Entry distinction | Settings and notification icon configure integrated Awake. Standalone CLI uses arguments; `--use-pt-config` instead watches saved preferences. There is no module activation hotkey |
| Exit signal | `Local\PowerToysAwakeExitEvent-c0d5e305-35fc-4fb5-83ec-f6070cfaf7fe` is shutdown, not activation. Do not signal a borrowed integrated instance to create a CLI fixture |

Discovery-stage guidance, not acceptance. Use the [checklist](../release-checklist/awake.md)
and [inventory](../assertion-inventories/awake.json); source-derived routes still need live confirmation.

## Entry paths

Complete [preflight](../pre-flight.md) and [preservation](#fixtures-and-restoration)
**before navigation**. Choose the route required by the assertion.

| Intent | Route / destination |
|---|---|
| Settings | Invoke `AwakeNavItem`, expanding System Tools if needed; arrive at enabled/disabled Settings |
| Notification area | Physically click the actual Awake icon; inspect its menu, not Runner's |
| CLI | Disable integrated Awake and verify absence before an owned resident CLI launch; help/error parsing does not require disabling |
| Command Palette | Preserve palette/provider state, then use the shipped PowerToys extension's Awake commands |

## UI state-transition map

Settings can coexist with tray/console surfaces. `Settings / enabled` includes all four modes;
`Active integrated` excludes passive. Landmarks establish surfaces, not effective power requests.

| Current state | Trigger / condition | Next state | State landmarks |
|---|---|---|---|
| Settings / disabled | Enable switch, policy permits | Settings / enabled | Enabled behavior controls and resident Awake process |
| Settings / enabled | Disable switch | Settings / disabled | Behavior controls disabled; resident process exits |
| Settings / enabled | Select passive | Passive integrated | Mode selector; screen control disabled; no duration/date controls |
| Settings / enabled | Select indefinite | Indefinite integrated | Mode selector and usable screen control |
| Settings / enabled | Select interval | Timed integrated | Hours and Minutes edits inside interval card |
| Settings / enabled | Select expiration | Expiration integrated | Date/time picker cards in expiration expander |
| Timed integrated | Countdown completes | Passive integrated | Selector changes to passive; process remains resident |
| Expiration integrated | Deadline completes | Passive integrated | Selector changes to passive; process remains resident |
| Settings / enabled | Click real notification icon | Integrated tray menu | Awake-owned `#32768`; screen row unavailable in passive |
| Integrated tray menu | Select a mode or dismiss with guarded Escape | Settings / enabled | Native menu gone; Settings remains available |
| No Awake process | Owned standalone launch, valid arguments | Standalone active | Owned process and mode-dependent console/tray surface |
| Standalone active | Timer/deadline/target exits, or user-facing Exit | No Awake process | Exact process generation gone |

## Control locator and interaction index

Use [shared helpers](../helper-workflow.md), exact HWNDs and fresh selectors. Rediscover localized
Names; `x:Uid` is not an AutomationId. Persistence does not prove runtime effect.

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Navigate | Borrowed main Settings | `AutomationId=AwakeNavItem`; parent `SystemToolsNavItem` | Invoke rail; wait for `AwakeEnableSettingsCard` |
| Enable/disable | Awake page, no open menu | `ClassName=ToggleSwitch`, `Name=Awake`, owner `AwakeEnableSettingsCard` | Explicit Toggle on/off; use Resident lifecycle adapter and fresh process identity |
| Select mode | Enabled Awake page | `ControlType=ComboBox`, `Name=Mode`, owner `AwakeModeSettingsCard` | `Select-PtComboBoxItem`: `-Hwnd`, `-ControlName Mode`, `-WithinAutomationId AwakeModeSettingsCard`, `-ItemName` from live options |
| Change display | Enabled non-passive mode | `ClassName=ToggleSwitch`, `Name=Keep screen on` | Scoped CLI invoke with `--action toggle-on` / `toggle-off`; reread state |
| Edit interval | Timed integrated | `ControlType=Edit`, Names `Hours` / `Minutes`, owner `AwakeIntervalSettingsCard` | SetValue, then focus the other edit to commit; verify persistence |
| Open picker | Expiration integrated; rollback proven | Owners `AwakeExpirationSettingsExpanderDate` / `AwakeExpirationSettingsExpanderTime`; unique child `AutomationId=FlyoutButton` | Inspect owner, invoke button and rediscover popup |
| Commit picker | Owned date/time popup | `YearLoopingSelector` / `HourLoopingSelector`, descendant `ClassName=LoopingSelectorItem`; `AcceptButton` | Select, verify IsSelected, accept; discover day/month/minute parts. Source/test-derived route needs live confirmation |
| Find tray icon | Primary taskbar or owned new overflow | `ControlType=Button`, Name starts `PowerToys Awake`; `Shell_TrayWnd` / `TopLevelWindowForOverflowXamlIsland` | `Find-PtRunnerTrayControl` without `-RunnerIcon`; open observed chevron only if needed |
| Open tray menu | Visible unoccluded icon | Exact icon Name/owner, current Awake generation | `Invoke-PtRunnerTrayRightClick` or scoped CLI left click; wait for Awake-owned `#32768` |
| Operate tray row | Awake menu/submenu | `ControlType=MenuItem`, actual caption | Invoke supported pattern without focusing popup; rediscover interval submenu. No WM_COMMAND substitution |
| Dismiss menu | Run-opened menu; exact current foreground belongs to the same Awake generation | Current foreground HWND plus owned visible `#32768` menu | Guard both identities and recheck the foreground HWND immediately before `Send-PtChord -Key 0x1B`; do not activate the hidden owner. Verify menu absence, close only owned overflow, then restore pointer/foreground |
| Run CLI | Owned terminal; resident Awake absent | Exact installed executable, documented arguments | Preserve visible console text, stdout and exit status separately |
| Read requests | Controlled baseline/active states | Native power-information query | `Get-PtAwakePowerObservation` with optional `-ProcessIdentity` from `Get-PtLifecycleProcessProbe` |
| Use extension | Shipped PowerToys CmdPal page | Actual Awake Settings/status/mode commands | Invoke, refresh status, compare Settings/runtime; no direct service/JSON substitute |

### Read-out notes

- `Read-PtSharedFileText` preserves writer sharing. Plain fields under `properties` are `mode`,
  `keepDisplayOn`, `intervalHours`, `intervalMinutes`, `expirationDateTime`, `customTrayTimes`;
  there are no `.value` wrappers. Modes: passive 0, indefinite 1, timed 2, expiration 3.
- Tray text is advertised state. The helper's flags are **system-wide**, not process-attributed.
  Compare controlled inactive/active states; unrelated requests invalidate attribution.
- `powercfg /query` compares the power plan. `/requests` requires elevation. Neither UI nor kernel
  flags prove physical sleep/display prevention.
- Timestamp duration commit, display toggle and completion independently. Keep Settings and tray
  routes distinct; never reset the clock after toggling. Integrated expiry stays resident.
- Scope captures to owned/module surfaces. Menus need passive capture (`-WindowIdentity`).
  Check spinner popups/update notifications for occlusion; images remain unaccepted candidates.

## Troubleshooting

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| CLI exits immediately | Check resident singleton; disable integrated Awake through Settings | Duplicate-instance rejection is not mode evidence |
| Menu disappears / hidden-target refusal | Native menus retain a hidden foreground owner. Use the same-generation/exact-HWND guarded Escape path above; focusing Settings is not a reliable dismissal | Do not activate popup/hidden owner or send input after the guard changes |
| Screen toggle moves deadline | Retain commit/toggle/completion times; compare untouched countdown | Eventual expiry does not prove deadline preservation |
| File restored but UI/runtime differs | Restore UI values first, then guarded bytes; reobserve cache | File equality alone is insufficient; no borrowed-window close/restart loop |
| Picker cannot represent original seconds/offset | Prove exact file/cache rollback before editing | Missing rollback is Author work, not permission to normalize data |
| Passive global flags remain set | Inspect independent baseline and other request owners where permitted | No process attribution from global flags alone |
| Lock/resume/hardware unavailable | Retain condition and recovery prerequisites; continue ordinary cases | Do not lock/suspend/detach the shared desktop |
| Extension/provider lifetime unclear | Inspect installation, route and ownership before activation | No toast-only PASS or automatic CmdPal recycling |

## Fixtures and restoration

### Resource inventory

| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| Settings ResourcePlan | Navigation | Borrowed HWND; original page/expansion/scroll/placement | Shared Settings adapter; never close borrowed app | Fresh final UI comparison |
| Awake file snapshot | Preference edits | Run-private original bytes; attributed expected post-state | UI restoration, then guarded `Restore-PtFileSnapshot -ExpectedState` | Original bytes and UI/cache/runtime readback |
| General file / lifecycle snapshot | Enablement, CLI | Original file and enabled map; unrelated values preserved | Restore original Awake enablement; reject unexplained changes | Original enabled map and declared byte/semantic comparison |
| Desktop / tray popup | Physical input | Desktop snapshot; initially absent popup/overflow | Dismiss only owned popup; pointer before foreground | Menu absent; desktop matches |
| Owned CLI / PID fixture | Console cases | `Start-PtOwnedProcess` or activation receipt; all siblings | User-facing close/natural exit, checked by `Stop-PtOwnedProcess` | Exact owned generations gone |
| Power plan / requests | Runtime | Read-only plan and differential baseline | End owned requests; no timeout changes | Plan unchanged; original active state restored |
| Policy/diagnostic/hardware fixture | Conditional cases | Authorized originals and independent recovery | Approved exact rollback | Original state independently observed |

### Helper boundaries

Use the [recorder](../recording-workflow.md), [resources](../session-safety.md) and
[lifecycle](../module-lifecycle.md) contracts. `scripts\pt-awake.ps1` is read-only, not a
driver/restorer; its regression is `scripts\tests\Test-PtAwake.ps1`.
Existing-file rollback cannot restore absence: use [directory/selected-file preservation](../directory-snapshots.md)
instead of pre-creating files. Include indirect startup writes; keep backups private and do not roll back logs.

### Restoration order

1. Release input, dismiss owned popups and settle drafts.
2. End owned CLI/target processes; restore original duration/display/mode through Settings.
3. Normalize only attributed file changes with the guard; verify timestamp precision and cache.
4. Restore original enablement, account for startup writes, then compare files/runtime again.
5. Restore borrowed Settings and pointer/foreground; complete resource comparisons. Retain all failures.

### Restoration verification

Require declared file equality, enabled-map preservation, original mode/display readback,
owned-resource absence and borrowed UI/desktop comparisons. A new PID after an enable cycle is expected.
Retain conflicts and recovery copies; never turn a helper return count into restoration success.

## References

- [Awake checklist](../release-checklist/awake.md) and [assertion inventory](../assertion-inventories/awake.json).
- [Official Awake usage](https://learn.microsoft.com/windows/powertoys/awake).
- Source symbols: `Awake.Program.BuildRootCommand` / `ProcessSettings`,
  `Awake.Core.Manager.SetTimedKeepAwake` / `HandleTimerCompletion`,
  `Awake.Core.TrayHelper`, and `AwakePage.Settings_Changed`.
  Versioned source, UI-test reuse decisions and actual execution identities belong in the Author/run inputs.
