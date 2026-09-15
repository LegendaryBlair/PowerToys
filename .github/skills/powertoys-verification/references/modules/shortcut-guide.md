# Shortcut Guide — module verification profile

## Module facts

**PT module**: `Shortcut Guide` (app-aware Windows and application shortcut overlay)
**Source**: `src\modules\ShortcutGuide\`
**Settings file**: `%LOCALAPPDATA%\Microsoft\PowerToys\Shortcut Guide\settings.json`
**Exe**: `%LOCALAPPDATA%\PowerToys\WinUI3Apps\PowerToys.ShortcutGuide.exe`
**Default hotkey**: `Win+Shift+/` (`properties.open_shortcutguide`)
**Named Event**: `ShortcutGuide.Trigger` (`Local\ShortcutGuide-TriggerEvent-d4275ad3-2531-4d19-9252-c0becbd9b496`)
**Per-user manifests**: `%LOCALAPPDATA%\Microsoft\WinGet\KeyboardShortcuts`
**Installed manifests**: `%LOCALAPPDATA%\PowerToys\WinUI3Apps\Assets\ShortcutGuide\Manifests`
**Index generator**: `%LOCALAPPDATA%\PowerToys\WinUI3Apps\PowerToys.ShortcutGuide.IndexYmlGenerator.exe`

**Lifecycle profile**: use [module lifecycle](../module-lifecycle.md) with
`Model=Resident`, key `Shortcut Guide`, page `ShortcutGuideNavItem`, toggle name
`Shortcut Guide`, the executable path above and native class
`WinUIDesktopWin32WindowClass`. For `ShortcutGuide.Trigger`, use
`WhenEnabled=Present` and `WhenDisabled=Ignore`: Runner's DLL owns the event, so it
can survive disable. Process/host exit, not event absence, establishes the stop condition.

## UI state-transition map

This map covers overlay lifecycle only. Use the recipe table for controls and the
[release checklist](../release-checklist/shortcut-guide.md) for the complete assertions.

| Current state | Trigger / control | Next state | Observable side effect |
|---|---|---|---|
| Disabled | Enable in Settings | Enabled, hidden host | Wait for the saved enable state and live host separately |
| Enabled, hidden host | Named event, configured chord, or launcher action | Full guide | Pane opens for the captured foreground application |
| Enabled, hidden host | Windows-key hold in indicator mode | Taskbar indicators | Numbered callouts appear without the full pane |
| Taskbar indicators | Press and release a taskbar number while Windows stays held | Taskbar indicators | Target app becomes foreground; indicators remain visible |
| Taskbar indicators | Release Windows | Hidden host | Indicators close without opening Start |
| Enabled, hidden host | Windows-key hold in full-guide mode | Full guide | Pane opens after the hold threshold |
| Hold-opened full guide | Release Windows | Hidden host if close-on-release is enabled; otherwise full guide | The release setting applies to the full guide, not indicator mode |
| Full guide with a search query | Escape | Full guide | Query clears before another Escape can close the guide |
| Full guide | Escape with an empty query, configured chord, Close, outside-pane click, or deactivation | Hidden host | Overlay closes; process remains reusable |
| Enabled | Disable in Settings | Disabled | Module exits and activation paths become inert |

## Observation and restoration rules

- Use `Get-PtShortcutGuideHost` / `Wait-PtShortcutGuideHost` from `pt-shortcut-guide.ps1` to
  resolve a live Shortcut Guide PID, then its native host HWND by owner PID and class
  (`WinUIDesktopWin32WindowClass`). Exclude tooltip/`PopupHost` windows; confirm full-monitor bounds
  after showing the host. `MainWindowHandle` is only a hint, and English titles are not identifiers.
  Re-resolve after enable cycles or restarts; do not retain exited process objects.
- Poll saved enable state, host readiness, and populated content separately.
  H06 observes native lifecycle; H07/content checks establish the next case's observation
  surface. A diagnostic cycle invalidates old PID/HWND/UIA references and is not Normal reopen.
  `Wait-PtShortcutGuideContent -Mode FullGuide|Indicators` checks realized mode-specific controls,
  not just visibility. Start the activation
  timeout after host readiness; allow up to 9 seconds for cold full-guide content. A held-key
  observation must keep the key down until captured; measure threshold behavior separately.
- Use `Save-PtPassiveScreenshot -Path <unique-path> -Observe <stable-state-probe>` for menus,
  overlays and held-key observations. Even `winapp ui screenshot -w` without `--capture-screen`
  can change focus. A changed foreground/observation invalidates that capture, which is retained
  with its state sidecar. Review actual pixels after the content-ready probe.
- The full guide and indicators share one host. Inspect pane/callout content as well as native
  visibility; process existence alone proves neither mode. The host should have `WS_EX_TOOLWINDOW`,
  not `WS_EX_APPWINDOW`. Review actual pixels for theme, localization, glyphs, and clipping.
- After a short Windows press opens Start, read `Get-PtForegroundWindow` directly and use
  `Restore-PtForegroundAfterShell -Hwnd <tracked-target>` for the test-owned transition.
  Start/Search and even the taskbar can be absent from `EnumWindows` during this state.
  Verify the target again before the next chord; do not infer closure from an empty enumeration.

Before any mutation, capture settings/files and each touched window's page, placement, foreground,
and pointer position. Restore in `finally` and compare with that baseline; report any unrecorded
transient state rather than claiming exact rollback. Track test-created resources separately from
user-owned resources; use the corresponding fixture's cleanup procedure.
Every new SG process can copy shipped `*.yml` files, regenerate `index.yml`, and rewrite
the generated PowerToys manifest. Before enable/restart cycles, capture the per-user
directory's exact bytes and declare the shipped manifest basenames plus `index.yml` as
startup-write ownership. Native host readiness does not prove the copy/index writer has
finished. Observe writer completion/stable file state before H04 rollback and recompare
afterward; do not restart the module again after restoring files merely to refresh a cache.
Use the shared [paired snapshot helpers](../helper-workflow.md#pair-snapshots-with-restoration-before-changing-state)
for bytes, registry values and native placement; page/tab/IME state still needs explicit handling.

## Activation selection

Use the [owned composed flows](shortcut-guide/composed-flows.md) for full-guide
open/observe/close and callback-scoped Windows-key holds. Specify the entry and close
route explicitly. A failed physical-chord path must not be replaced by a named event
and credited as the same test; an already-hidden surface cannot pass a close-route assertion.

Use the shared [shortcut recorder](../shortcut-recorder.md) for assignment/restoration.
Its Ctrl-only readiness handshake establishes that the capture hook responds before the
main chord, rather than assuming visible dialog controls mean the hook is ready.
It compares complete saved fields and edit-button HelpText after assignment/restoration;
the dialog's Windows artwork is not exposed by UIA. Do not use **Reset** as a substitute
for restoring the captured original.

An inspect result containing only the native host and a `PopupHost` is not an empty shortcut
page. Use the shared [UI observation contract](../ui-observations.md) to assess the captured
structure; retain insufficient snapshots and report observer limitations rather than zero rows.
Collect raw observations and review them against screenshots and exact settings fields before
committing either successful restoration or a product FAIL. A proven
observer mistake can reopen only the affected item using the shared recording workflow; do not
repeat the other checklist items or replace the entire run to correct that judgment.

Before desktop-entry coverage, identify all windows affected by Show Desktop and whether they
can be restored at the current integrity level. On a shared desktop, block this variant rather
than minimizing an elevated/user window without a viable restore path. Native snapshots do not
grant that capability. Declare temporal/speech observers before theme, animation and Narrator
cases; do not substitute settled images for those assertions.

| Assertion | Entry path |
|---|---|
| Downstream content/navigation | `Invoke-PtSharedEvent -Name 'ShortcutGuide.Trigger'`; does not prove a keyboard binding |
| Configured binding or excluded-app gate | `Send-PtChord -Hwnd <tracked-window> -Mods 0x5B,0x10 -Key 0xBF` for the default; use its no-delay activation default, not recorder-oriented dwell |
| Hold threshold or release | `Invoke-PtHeldKeys -Hwnd <tracked-window> -Keys 0x5B -Action { ... }`; repeat with `0x5C`, observing while held; release is guaranteed by `finally` during normal exception unwinding |
| Quick Access integration | After fresh SG startup completion, signal `Local\PowerToysQuickAccess_<RunnerPid>_Show` once; wait for actual QA foreground/uncloaked state and tile availability, then invoke the tile. See [entry transitions](shortcut-guide/entry-points.md). |
| Settings rail navigation | Click the actual Settings item, then wait for the existing Settings HWND foreground with SG selected; retain guide visibility separately, never force the destination or credit an already-selected background page. |
| Command Palette integration | Discover the actual PowerToys extension and its module commands; a **Search apps** result for PowerToys is not the command provider |

Use `Assert-PtForegroundOrAbort -Hwnd` when an app has multiple windows. For
keyboard-hook tests, compare runner and foreground integrity levels; apply the shared
[pre-flight policy](../pre-flight.md) to admin-required variants.
Open Settings with `PowerToys.exe --open-settings=ShortcutGuide`.
During recorded attempts, route winapp operations through `Invoke-PtWinApp`; its internal
readiness and taskbar probes are recorded too. See the shared [recording workflow](../recording-workflow.md).

## Recipes — control map

Use shipped Settings controls for UI/binding assertions; JSON keys below identify persisted state,
not a substitute for driving the control. Follow the selected scenario's mutation contract.

| # | Capability | Drive (control / settings key) |
|---|---|---|
| 1 | Enable/disable lifecycle | Settings enable toggle; top-level `enabled."Shortcut Guide"` |
| 2 | Activation binding | common shortcut helper: page `ShortcutGuideNavItem`, control `EditButton`, property segments `properties,open_shortcutguide` |
| 3 | Windows-key mode | `Select-PtComboBoxItem -AutomationId ShortcutGuide_WindowsKeyAction`; `properties.win_key_action` (`0` off, `1` indicators, `2` full guide) |
| 4 | Hold threshold | hold-duration control; `properties.press_time` |
| 5 | Close on Windows-key release | `properties.close_on_windows_key_release` |
| 6 | Excluded applications | `properties.disabled_apps`; executable names, one per line |
| 7 | Theme and pane side | `Select-PtComboBoxItem -ControlName 'Theme'` / `-ControlName 'Window position'`; `properties.theme`; `properties.window_position` (`0` left, `1` right) |
| 8 | Application rail navigation | invoke runtime rail items; stable IDs include `Microsoft.PowerToys` and `+WindowsNT.Shell` |
| 9 | Search | `ShortcutGuide_SearchBox` / child `TextBox`; use real `Ctrl+F` when keyboard focus is asserted |
| 10 | Pin/unpin | shortcut-row context menu; discover the Pin/Unpin action and runtime `PinMenuItem` |
| 11 | Manifest regeneration | capture directory bytes/file set with `Get-PtDirectorySnapshot` before removal; invoke the module, capture expected post-state, then use explicit-owned rollback |
| 12 | Custom manifest reload | installed index generator; see cache refresh below |
| 13 | PowerToys shortcut reflection | common shortcut helper on a representative module, then separately assert the `Microsoft.PowerToys` rail page |
| 14 | Reuse/memory | warm the module, then run open/navigate/close cycles against one foreground fixture |
| 15 | Language override | PowerToys language control and runner restart; `%LOCALAPPDATA%\Microsoft\PowerToys\language.json` |

Read outcomes as follows:

- Read saved JSON and exercise the resulting behavior; a successful UIA invocation is not proof
  of persistence. Pin state is application-scoped in `Pinned.json`.
- For L48/L49, supply the SG settings file and addressing above. For L69's Color Picker
  fixture, supply `ColorPickerNavItem`, `ColorPicker\settings.json`, and
  `properties,ActivationShortcut`. The helper changes/restores the setting; actual binding
  behavior and SG row updates remain separate case assertions. Final cleanup restores the
  user's captured original, even when a case temporarily requires the factory default.
- Supply the exact Settings HWND and observed `-ItemName` to the ComboBox helper; preserve
  and restore the original selected value. It deduplicates runtime identities, not captions.
  Activate Settings explicitly before selection; minimized WinUI controls may report
  `IsOffscreen=false`. See [scoped control selection](../helper-workflow.md#scoped-control-selection).
- Realize rows by scrolling or filtering before counting recommendations or assessing keyboard
  focus; an incomplete UIA tree is not evidence of missing rows.
- For no-results announcements, read native `UIA_LiveSettingPropertyId` (`30135`; `1` is Polite).
  Use `Get-PtUiObservation -Property LiveSetting` on `ShortcutGuide_NoSearchResults`
  (type `Text`). Its value does not prove actual speech; confirm rendered emptiness separately.
- For L77/L78, read `-Property Text` from the `TextBox` edit within
  `ShortcutGuide_SearchBox`. `-Property Name` is the separate accessible label; the
  placeholder `Search shortcuts` is not an empty query's value.
- For L68/L85, read `IsSelected` on the application rail's `ListItem` identifiers and
  `HasKeyboardFocus` on the exact intended control. These facts do not prove visual
  order, coherent spoken output or exactly-once announcements.
- A search/navigation snapshot contract can require the `ShortcutGuide_SearchBox`
  Group, its `TextBox` Edit, and `MenuItemsHost` Group. It must not require
  `ShortcutGuide_NoSearchResults`, recommended rows or pinned rows to exist. L70/L71
  counting/absence assertions require a separately established content observation scope.
- For reuse, record the active PID and private working set, with warm-up, cycle count, idle time,
  and limit taken from the checklist rather than substituted process-private-byte measurements.

**Cached content refresh:** Application manifests and generated PowerToys shortcut pages are
process-cached. Observe the
checklist's requested reopen behavior first; a restart is not evidence that live refresh works.
Use the shared [directory snapshot contract](../directory-snapshots.md) for manifest mutations:
hash lists alone are not a backup. Declare owned relative files, directories and root existence
explicitly. A conflict or `WholeTreeMatchesBaseline=false` is not successful full restoration.
For fixture setup/recovery, regenerate the index after manifest changes, then toggle Shortcut Guide
off/on through Settings. For representative shortcut changes, refresh the module before inspecting
the generated page if ordinary reopening still shows old data. Repeat the refresh after restoring
the original files/settings, and disclose any extra restart in the report.

Use these fixtures for the recipes above:

- Use `New-PtNotepadFixture` / `Remove-PtNotepadFixture` for application-page, exclusion and
  foreground tests; use `New-PtExplorerFixture` / `Remove-PtExplorerFixture` for an isolated
  Explorer target. Follow the shared [ownership and cleanup contract](../owned-fixtures.md).
  Do not recreate shared-tab ownership from a launcher PID inside the run.
- Elevated Notepad only for eligible integrity variants; verify with `Test-ProcessElevated`.
- Disposable per-user manifest with a unique package/process filter for key-token and page-local-search checks.
- Three tracked taskbar apps; use the controlled first-slot fixture without closing other user windows.

**Controlled first-slot taskbar fixture:** For `Win+1`, follow the
[taskbar fixture recipe](shortcut-guide/taskbar-fixture.md) before changing
pins or order. It owns Calculator discovery, guarded dragging, repeated observations, and rollback.
A grouped first-slot app is not a blocker by itself.

## Troubleshooting

Use the shared taxonomy and entry-path discipline. Recovery instructions are not reasons to mark
a working feature BLOCKED; a reproducible mismatch with a valid checklist remains a product FAIL.

| Symptom | Recovery | Evidence / classification boundary |
|---|---|---|
| Empty recorder or failed chord | Follow the activation-binding recipe; recheck focus and input desktop | Capture recorder contents and persisted chord. A failed attempt alone establishes neither a version dependency nor a physical-input blocker |
| Start/Search retains foreground after early Windows release | Recover the test-owned Shell transition using the actual foreground HWND, then verify the exact target | Preserve the initial state and recovery evidence; do not drop the guard or classify every dependent case as an unrelated environment failure |
| Missing host or capture dismisses the overlay | Apply **Observation and restoration rules** before repeating input | Log PID/HWND, readiness and foreground before/after capture; name the remaining tool/environment obstacle if blocked |
| Old manifest/generated shortcut content | Follow **Cached content refresh** | Retain before/after content and disclose the refresh; never credit a restart as a live-update PASS |
| Empty search reports `Search shortcuts`, or a property returns null | Inspect cleared content and read the supported native UIA property | Accessible-name fallback is not text content; unsupported-property null is not false |
| Initial page shows unexpected indicators | Capture the initial page, selected manifest and a page-away/back comparison | A repeatable layout mismatch is product evidence, not a UIA blocker; recovery does not erase the initial result |
| Theme/localization looks wrong despite saved settings | Compare rendered pane/chrome with the selected setting | Saved JSON or `visible=true` is insufficient; retain actual pixel evidence |
| Taskbar routing is ambiguous | Use the controlled first-slot fixture | Record exact HWND/class/content, not just `explorer.exe`; classify unresolved setup separately from product behavior |
| No CmdPal module commands | Use the provider discovery in **Activation selection** | Record provider-list/query evidence; if absent, block that portion only and continue Quick Access |
| No mixed-DPI display pair | Inspect active display topology | `BLK-HARDWARE` for cross-monitor coverage only. Taskbar relocation is not required to test pane Left/Right |

## Source citations and visual references

- `src\common\interop\shared_constants.h` — `SHORTCUT_GUIDE_TRIGGER_EVENT`
- `src\modules\ShortcutGuide\ShortcutGuideModuleInterface\dllmain.cpp` — `GetHotkeyEx`, `milliseconds_win_key_must_be_pressed`, settings clamp
- `src\modules\ShortcutGuide\ShortcutGuide.Ui\ShortcutGuideXAML\App.xaml.cs` — activation event and Windows-key release handling
- `src\modules\ShortcutGuide\ShortcutGuide.Ui\ShortcutGuideXAML\OverlayWindow.xaml.cs` — overlay show/close and taskbar-pane layout
- `src\modules\ShortcutGuide\ShortcutGuide.Ui\ShortcutGuideXAML\Controls\MainPaneControl.xaml.cs` — navigation/page taskbar visibility

See the [visual reference](shortcut-guide/visual-reference.md) for cropped UI landmarks.
Screenshots are not timing evidence or pixel baselines.
