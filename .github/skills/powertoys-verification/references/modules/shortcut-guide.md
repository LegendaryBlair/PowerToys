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
Use the shared [paired snapshot helpers](../helper-workflow.md#pair-snapshots-with-restoration-before-changing-state)
for bytes, registry values and native placement; page/tab/IME state still needs explicit handling.

## Activation selection

| Assertion | Entry path |
|---|---|
| Downstream content/navigation | `Invoke-PtSharedEvent -Name 'ShortcutGuide.Trigger'`; does not prove a keyboard binding |
| Configured binding or excluded-app gate | `Send-PtChord -Hwnd <tracked-window> -Mods 0x5B,0x10 -Key 0xBF` for the default; use its no-delay activation default, not recorder-oriented dwell |
| Hold threshold or release | `Invoke-PtHeldKeys -Hwnd <tracked-window> -Keys 0x5B -Action { ... }`; repeat with `0x5C`, observing while held; release is guaranteed by `finally` during normal exception unwinding |
| Quick Access integration | Resolve the runner PID, open `Local\PowerToysQuickAccess_<RunnerPid>_Show`, inspect the current UIA tree, and invoke the Shortcut Guide tile |
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
| 2 | Activation binding | invoke recorder `EditButton`, guard Settings, send the chord, invoke `PrimaryButton`; `properties.open_shortcutguide` |
| 3 | Windows-key mode | `properties.win_key_action` (`0` off, `1` indicators, `2` full guide) |
| 4 | Hold threshold | hold-duration control; `properties.press_time` |
| 5 | Close on Windows-key release | `properties.close_on_windows_key_release` |
| 6 | Excluded applications | `properties.disabled_apps`; executable names, one per line |
| 7 | Theme and pane side | `properties.theme`; `properties.window_position` (`0` left, `1` right) |
| 8 | Application rail navigation | invoke runtime rail items; stable IDs include `Microsoft.PowerToys` and `+WindowsNT.Shell` |
| 9 | Search | `ShortcutGuide_SearchBox` / child `TextBox`; use real `Ctrl+F` when keyboard focus is asserted |
| 10 | Pin/unpin | shortcut-row context menu; discover the Pin/Unpin action and runtime `PinMenuItem` |
| 11 | Manifest regeneration | back up the per-user directory, remove it for the regeneration case, and invoke the module |
| 12 | Custom manifest reload | installed index generator; see cache refresh below |
| 13 | PowerToys shortcut reflection | representative module's shortcut control, then `Microsoft.PowerToys` rail page |
| 14 | Reuse/memory | warm the module, then run open/navigate/close cycles against one foreground fixture |
| 15 | Language override | PowerToys language control and runner restart; `%LOCALAPPDATA%\Microsoft\PowerToys\language.json` |

Read outcomes as follows:

- Read saved JSON and exercise the resulting behavior; a successful UIA invocation is not proof
  of persistence. Pin state is application-scoped in `Pinned.json`.
- Realize rows by scrolling or filtering before counting recommendations or assessing keyboard
  focus; an incomplete UIA tree is not evidence of missing rows.
- For no-results announcements, read native `UIA_LiveSettingPropertyId` (`30135`; `1` is Polite).
  Confirm rendered emptiness separately from the search value.
- For reuse, record the active PID and private working set, with warm-up, cycle count, idle time,
  and limit taken from the checklist rather than substituted process-private-byte measurements.

**Cached content refresh:** Application manifests and generated PowerToys shortcut pages are
process-cached. Observe the
checklist's requested reopen behavior first; a restart is not evidence that live refresh works.
For fixture setup/recovery, regenerate the index after manifest changes, then toggle Shortcut Guide
off/on through Settings. For representative shortcut changes, refresh the module before inspecting
the generated page if ordinary reopening still shows old data. Repeat the refresh after restoring
the original files/settings, and disclose any extra restart in the report.

Use these fixtures for the recipes above:

- Medium-integrity Notepad with a unique temp file for application-page, exclusion, and foreground tests.
- Modern Notepad may reuse a user process and add a tab. Track/close only the fixture tab, not its
  launcher PID or the user's process.
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
