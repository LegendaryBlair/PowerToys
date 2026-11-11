# Awake - module verification profile

## Module facts

| Fact | Value |
|---|---|
| Module / source | `Awake`; `src\modules\awake` |
| Runtime | `PowerToys.Awake.exe` beside installed Runner; native tray menu, managed power-request thread |
| Settings UI | WinUI `PowerToys.Settings.exe`; `AwakeNavItem` under `SystemToolsNavItem` |
| Preferences | `%LOCALAPPDATA%\Microsoft\PowerToys\Awake\settings.json`; parent `settings.json`: `enabled.Awake` |
| Lifecycle | Enabled: resident even when passive. Disabled: exits. Integrated and standalone share a singleton mutex |
| Entry distinction | Integrated: Settings/tray. Standalone: arguments, or `--use-pt-config` to watch preferences. No activation hotkey |
| Exit signal | `Local\PowerToysAwakeExitEvent-c0d5e305-35fc-4fb5-83ec-f6070cfaf7fe`: shutdown only; never use on borrowed integrated Awake to create a CLI fixture |

Discovery-stage guidance, not acceptance. Use the [checklist](../release-checklist/awake.md)
and [inventory](../assertion-inventories/awake.json); source-derived routes still need live confirmation.

## Entry paths

Complete [preflight](../pre-flight.md) and [preservation](#fixtures-and-restoration)
**before navigation**. Choose the route required by the assertion.

| Intent | Route / destination |
|---|---|
| Settings | Invoke `AwakeNavItem`; expand System Tools if needed |
| Notification area | Physically click Awake's icon, not Runner's |
| CLI | Disable integrated Awake and confirm absence before resident CLI launch; help/error parsing needs no disable |
| Command Palette | Preserve palette/provider state; use shipped PowerToys extension commands |

## UI state-transition map

Settings and tray/console surfaces can coexist. Landmarks do not prove effective power requests.

| Current state | Trigger / condition | Next state | State landmarks |
|---|---|---|---|
| Settings / disabled | Enable, policy permits | Settings / enabled | Usable behavior controls; resident process |
| Settings / enabled | Disable | Settings / disabled | Disabled behavior controls; process exits |
| Settings / enabled | Select passive | Passive integrated | Screen disabled; duration/date hidden |
| Settings / enabled | Select indefinite | Indefinite integrated | Usable mode/screen controls |
| Settings / enabled | Select interval | Timed integrated | Hours/Minutes card |
| Settings / enabled | Select expiration | Expiration integrated | Date/time picker cards |
| Timed integrated | Countdown completes | Passive integrated | Passive selector; process stays resident |
| Expiration integrated | Deadline completes | Passive integrated | Passive selector; process stays resident |
| Settings / enabled | Click Awake icon | Integrated tray menu | Awake-owned `#32768`; screen disabled when passive |
| Integrated tray menu | Select mode / guarded Escape | Settings / enabled | Menu absent |
| No Awake process | Owned valid CLI launch | Standalone active | Owned process; mode-dependent console/tray |
| Standalone active | Timer/deadline/target ends or user Exit | No Awake process | Exact generation gone |

## Control locator and interaction index

Use [shared helpers](../helper-workflow.md), exact HWNDs and fresh localized selectors.
`x:Uid` is not an AutomationId; persistence is not runtime evidence.

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Navigate | Preserved main Settings | `AutomationId=AwakeNavItem`; parent `SystemToolsNavItem` | Invoke; wait for `AwakeEnableSettingsCard` |
| Enable/disable | Awake page; menus closed | `ClassName=ToggleSwitch`, Name `Awake`, within `AwakeEnableSettingsCard` | Explicit on/off; Resident lifecycle adapter and fresh identity |
| Select mode | Enabled Awake page | `ControlType=ComboBox`, `Name=Mode`, owner `AwakeModeSettingsCard` | `Select-PtComboBoxItem`: `-Hwnd`, `-ControlName Mode`, `-WithinAutomationId AwakeModeSettingsCard`, `-ItemName` from live options |
| Change display | Enabled, non-passive | `ClassName=ToggleSwitch`, Name `Keep screen on` | Scoped `--action toggle-on` / `toggle-off`; reread |
| Edit interval | Timed integrated | `AwakeIntervalSettingsCard`; resolve NumberBox edits by Hours/Minutes labels | Supported SetValue; focus other edit to commit. Resolve numeric readback separately |
| Open picker | Expiration; rollback proven | `AwakeExpirationSettingsExpanderDate` / `AwakeExpirationSettingsExpanderTime`; unique `FlyoutButton` AutomationId | Invoke; rediscover popup |
| Commit picker | Owned date/time popup | `YearLoopingSelector` / `HourLoopingSelector`, `LoopingSelectorItem` class; `AcceptButton` | Discover day/month/minute parts; select, verify IsSelected, accept. Source-derived, not live-confirmed |
| Find tray icon | Taskbar / owned overflow | `ControlType=Button`, Name starts `PowerToys Awake`; `Shell_TrayWnd` / `TopLevelWindowForOverflowXamlIsland` | `Find-PtRunnerTrayControl` without `-RunnerIcon`; chevron only if needed |
| Open tray menu | Visible unoccluded icon | Exact Name/owner and Awake generation | `Invoke-PtRunnerTrayRightClick` / scoped left click; await owned `#32768` |
| Operate tray row | Awake menu/submenu | `ControlType=MenuItem` and current caption | Guarded physical click below; observed native Invoke failed. Rediscover submenu; no WM_COMMAND |
| Dismiss menu | Run-opened menu; same-generation foreground | Exact foreground HWND and owned visible `#32768` | Guard both; recheck foreground before `Send-PtChord -Key 0x1B`. Never activate hidden owner. Verify absence; close owned overflow; restore desktop |
| Run CLI | Resident singleton absent; text needs readable owned terminal | Installed executable and actual token | Distinguish direct/indirect tracking; see fixture limits |
| Read requests | Controlled inactive/active states | Native power query | `Get-PtAwakePowerObservation -ProcessIdentity` for live Awake; omit only for established absence |
| Use extension | PowerToys CmdPal page | Awake Settings/status/mode commands | Invoke, refresh, compare Settings/runtime; no service/JSON substitute |

### Read-out notes

- `Read-PtSharedFileText` preserves writer sharing. Plain fields under `properties` are `mode`,
  `keepDisplayOn`, `intervalHours`, `intervalMinutes`, `expirationDateTime`, `customTrayTimes`;
  there are no `.value` wrappers. Modes: passive 0, indefinite 1, timed 2, expiration 3.
- Tray text advertises state; flags are **system-wide**. Controlled inactive/active differences,
  not unrelated requests, support attribution. Neither proves physical sleep/display prevention.
- `powercfg /query` compares the power plan; `/requests` needs elevation.
- Timestamp commit/toggle/completion separately; do not reset the clock after toggling.
  Keep Settings/tray paths distinct. Integrated expiry stays resident.
- Capture scoped surfaces, menus passively (`-WindowIdentity`); check occlusion.
  Images are evidence candidates, not accepted visual references.
- An `Edit Hours`/`Minutes` numeric query can return Missing despite successful editing.
  Preserve that error; fresh readable Settings pixels plus file/runtime observations can establish
  the displayed duration, not a successful UIA read or an unperformed edit.

## Troubleshooting

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| CLI exits immediately | Check singleton; disable integrated through Settings | Duplicate rejection is not mode evidence |
| Native menu Invoke fails | Resolve fresh row bounds; verify menu/foreground generation and native hit-test to menu. Recheck identities, bounds, pointer, hit-test and held buttons before down/up; release in `finally` | Proven integrated row/submenu path; no hidden-owner activation or stale coordinates |
| Menu / hidden-target refusal | Hidden owner retains foreground; use guarded Escape above, not Settings focus | Stop input if exact identity/foreground changes |
| Config CLI controls disabled | Behavior binds to `ViewModel.IsEnabled`; standalone cannot enable it | Known checklist reload conflict; no JSON/singleton bypass |
| Screen toggle moves deadline | Compare recorded commit/toggle/completion with untouched countdown | Eventual expiry is insufficient |
| Files match but UI differs | State-dependent UI restoration below, then guarded bytes/cache readback | No borrowed-window restart loop |
| Picker loses seconds/offset | Prove exact file/cache rollback before editing | Missing restoration support; do not normalize originals |
| Passive flags remain set | Check independent baseline/other owners where permitted | Global flags are not per-process |
| Missing lock/resume/hardware | Preserve conditions; continue independent cases | Do not lock/suspend/detach shared desktop |
| Unknown provider lifetime | Establish installation/ownership before activation | No toast-only PASS or CmdPal recycling |

## Fixtures and restoration

### Resource inventory

| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| Settings ResourcePlan | Navigation | Original ownership/page/expansion/scroll/placement | Shared adapter; never close borrowed app | Fresh UI comparison |
| Awake snapshot | Preference edits | Private bytes; attributed post-state | UI, then `Restore-PtFileSnapshot -ExpectedState` | Bytes and UI/cache/runtime |
| General/lifecycle | Enablement, CLI | Original file/enabled map | Restore Awake only; reject unrelated changes | Original map and declared file comparison |
| Desktop/popups | Input | Original desktop; absent popup/overflow | Owned popups only; pointer before foreground | Absence and desktop match |
| Owned CLI/PID | CLI | Direct record or supported indirect scope; siblings | User exit/natural exit; `Stop-PtOwnedProcess` confirms | Owned generations gone; integrated restored |
| Plan/requests | Runtime | Read-only plan/differential baseline | End owned requests; no timeout writes | Original plan/active state |
| Conditional fixtures | Policy/diagnostics/hardware | Authorized originals; independent recovery | Exact approved rollback | Independent comparison |

### Helper boundaries

Use the [recorder](../recording-workflow.md), [resources](../session-safety.md) and
[lifecycle](../module-lifecycle.md) contracts. `scripts\pt-awake.ps1` is read-only, not a
driver/restorer; its regression is `scripts\tests\Test-PtAwake.ps1`.
Existing-file rollback cannot restore absence: use [directory/selected-file preservation](../directory-snapshots.md)
instead of pre-creating files. Include indirect startup writes; keep backups private and do not roll back logs.

Current CLI fixture limits:
- `Start-PtOwnedProcess` direct tracking does not establish parent-shell activation.
  `Invoke-PtOwnedProcessActivation` scopes require original generations to survive and reject
  untracked replacements, conflicting with integrated disable/restore. Parent binding needs a
  supported lifecycle composition; never delete scopes or rewrite baselines.
- Visible help/error assertions require an owned readable console frontend, not a zero-size
  `PseudoConsoleWindow` or redirected text. Headless lifetime observations cannot discharge them.
- Record the standalone token. Integrated tray success does not establish standalone Exit:
  elevated standalone menu entry remained unconfirmed, and non-elevated behavior was not tested.
  Exact-owned exit-event cleanup is not a passing user-facing Exit assertion.

### Restoration order

1. Release input, dismiss owned popups and settle drafts.
2. End owned CLI/target processes and verify singleton absence before re-enabling integrated Awake.
3. Restore changed preferences through usable Settings controls. If disabled, first restore original
   enablement or use explicitly planned temporary enablement. If neither is permitted, reject the
   preference-mutating case before it starts. Unchanged preferences need no temporary enablement.
4. Restore the original enabled flag after UI edits; account for startup/IPC writes, then normalize
   only attributed file changes with the guard. Verify bytes, timestamp precision and live cache/
   effective state (or process absence when originally disabled); file equality alone is insufficient.
5. Restore borrowed Settings and pointer/foreground; complete resource comparisons. Retain all failures.

### Restoration verification

Require declared file equality, enabled-map preservation, original mode/display readback,
owned-resource absence and borrowed UI/desktop comparisons. A new PID after an enable cycle is expected.
Retain conflicts and recovery copies; never turn a helper return count into restoration success.

## References

- [Awake checklist](../release-checklist/awake.md) and [assertion inventory](../assertion-inventories/awake.json).
- [Official Awake usage](https://learn.microsoft.com/windows/powertoys/awake).
- Source: `Awake.Program.BuildRootCommand` / `ProcessSettings`,
  `Awake.Core.Manager.SetTimedKeepAwake` / `HandleTimerCompletion`,
  `Awake.Core.TrayHelper`, `AwakePage.Settings_Changed`; freeze source/build identities per run.
- Disabled controls: `src\settings-ui\Settings.UI\SettingsXAML\Views\AwakePage.xaml`,
  Behavior `SettingsGroup.IsEnabled`. Process scopes: `scripts\pt-session-safety.ps1`,
  `Invoke-PtOwnedProcessActivation` and `Complete-PtResourceSession`.
