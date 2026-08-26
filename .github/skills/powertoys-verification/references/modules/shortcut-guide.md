# Shortcut Guide — module verification profile

**PT module**: `Shortcut Guide` (app-aware Windows and application shortcut overlay)
**Source**: `src\modules\ShortcutGuide\`
**Settings file**: `%LOCALAPPDATA%\Microsoft\PowerToys\Shortcut Guide\settings.json`
**Exe**: `%LOCALAPPDATA%\PowerToys\WinUI3Apps\PowerToys.ShortcutGuide.exe`
**Default hotkey**: `Win+Shift+/` (`properties.open_shortcutguide`)
**Named Event**: `ShortcutGuide.Trigger` (`Local\ShortcutGuide-TriggerEvent-d4275ad3-2531-4d19-9252-c0becbd9b496`)
**Per-user manifests**: `%LOCALAPPDATA%\Microsoft\WinGet\KeyboardShortcuts`
**Installed manifests**: `%LOCALAPPDATA%\PowerToys\WinUI3Apps\Assets\ShortcutGuide\Manifests`
**Index generator**: `%LOCALAPPDATA%\PowerToys\WinUI3Apps\PowerToys.ShortcutGuide.IndexYmlGenerator.exe`
**Last verified**: `0.101.2323.0` · `2026-08-21`

## Entry-paths (try in order)

### 1. Named Event — downstream overlay behavior
```powershell
Invoke-PtSharedEvent -Name 'ShortcutGuide.Trigger'
```
Use for content, navigation, search, pinning, close routes, theme, positioning, and manifest checks where the configured chord is not the assertion.

### 2. Configured activation chord — binding and foreground compatibility
```powershell
Assert-PtForegroundOrAbort -AppId Notepad
Send-PtChord -Mods 0x5B,0x10 -Key 0xBF
```
Use guarded SendInput for default/custom binding, excluded-app, and elevated-foreground checks. A cold process can need several seconds to parse manifests and render; wait up to 9 seconds before failing.

### 3. Quick Access and Command Palette — launcher integration
Open Quick Access through `Local\PowerToysQuickAccess_<RunnerPid>_Show`, inspect its current UIA tree, and invoke the `Shortcut Guide` tile. For CmdPal, search for the real PowerToys command extension; do not confuse the `PowerToys (Preview)` **Search apps** result with the extension page.

### 4. Windows-key hold — threshold/release behavior
Use a 40-byte x64 `SendInput` structure to send key-down, wait across `press_time`, observe while the key remains down, then send key-up in `finally`. Test both `VK_LWIN (0x5B)` and `VK_RWIN (0x5C)`.

## Recipes — control map

| # | Capability | Drive (control / settings key) |
|---|---|---|
| 1 | Enable/disable lifecycle | top-level `enabled."Shortcut Guide"`; restart the runner after direct edits |
| 2 | Activation binding | `properties.open_shortcutguide` |
| 3 | Windows-key mode | `properties.win_key_action` (`0` off, `1` indicators, `2` full guide) |
| 4 | Hold threshold | `properties.press_time` (clamped to `100..5000`) |
| 5 | Close on Windows-key release | `properties.close_on_windows_key_release` |
| 6 | Excluded applications | `properties.disabled_apps`; use executable names such as `notepad.exe` |
| 7 | Theme and pane side | `properties.theme`; `properties.window_position` (`0` left, `1` right) |
| 8 | Application rail navigation | invoke runtime rail items; stable IDs include `Microsoft.PowerToys` and `+WindowsNT.Shell` |
| 9 | Search | `ShortcutGuide_SearchBox` / child `TextBox`; use real `Ctrl+F` when keyboard focus is asserted |
| 10 | Pin/unpin | open a shortcut row context menu and invoke runtime `PinMenuItem`; observe `Pinned.json` |
| 11 | Manifest regeneration | remove the backed-up per-user directory, restart the module, then validate YAML and `index.yml` |
| 12 | Custom manifest reload | regenerate the index **and restart the Shortcut Guide process** before expecting a new rail page |
| 13 | PowerToys shortcut reflection | change the representative module's shortcut, restart, select `Microsoft.PowerToys`, and page-search the module name |
| 14 | Reuse/memory | warm once, record active PID/private bytes, run cycles, idle two seconds, compare against 32 MiB |
| 15 | Language override | back up `%LOCALAPPDATA%\Microsoft\PowerToys\language.json`, set a supported tag, restart, and restore byte-for-byte |

**Read-out notes**
- Determine visibility from an active, non-exited process with a visible `MainWindowHandle`; capture with `winapp ui screenshot -w <hwnd>`.
- The overlay is one full-monitor tool window. `WS_EX_TOOLWINDOW` should be present and `WS_EX_APPWINDOW` absent.
- Use screenshot evidence for key-cap glyphs: Shift and Windows can be exposed as glyphs without useful UIA text names.
- Taskbar indicators share the overlay HWND and can be distinguished by the collapsed main pane plus numbered indicators along the taskbar edge.
- PowerToys Settings can be opened directly with `PowerToys.exe --open-settings=ShortcutGuide`.

## BLOCKED traps

- **Exited process objects can poison visibility probes after repeated runner restarts.** `Get-Process PowerToys.ShortcutGuide | Select-Object -First 1` can select a terminated/windowless instance in a long test process. Filter with `Where-Object { -not $_.HasExited }`, then prefer a nonzero visible `MainWindowHandle`.
- **The Settings hotkey recorder rejects synthetic input.** UIA invoke, `WM_KEYDOWN`, elevated SendInput, and medium-integrity SendInput can all leave the recorder empty. Verify binding behavior through the settings contract plus a non-elevated runner restart; a human keypress is required to validate the recorder control itself.
- **Cold full-guide rendering is slower than taskbar indicators.** Keep the Windows key down long enough for cold manifest parsing, and wait up to 9 seconds for a regular hotkey before declaring failure.
- **Application pages are cached for the process lifetime.** Regenerating `index.yml` alone does not add a new rail page; restart the module after changing manifests.
- **Initial taskbar indicators may be stale.** On build `0.101.2323.0`, an initial Notepad page displayed taskbar indicators despite no `<TASKBAR1-9>` section; navigating away and back hid them. Treat this as product evidence, not a UIA limitation.
- **CmdPal app search is not the PowerToys command provider.** The shortcut-arrow `PowerToys (Preview)` result launches the app. Require the extension page/module fallback commands before testing `Toggle Shortcut Guide`.
- **Side-docked taskbar and mixed-DPI topology need matching hardware/OS support.** A single-monitor Windows 11 session cannot prove same-side taskbar overlap or cross-monitor scaling.

## Fixtures

- Medium-integrity Notepad with a unique temp file for application-page, exclusion, and foreground tests.
- Elevated `/new` Notepad instance for the integrity case; verify with `Test-ProcessElevated`.
- Disposable per-user manifest with a unique package/process filter for key-token and page-local-search checks.
- Three existing or disposable taskbar apps whose slot rectangles/foreground results are recorded before `Win+1`.

## Source citations

- `src\common\interop\shared_constants.h` — `SHORTCUT_GUIDE_TRIGGER_EVENT`
- `src\modules\ShortcutGuide\ShortcutGuideModuleInterface\dllmain.cpp` — `GetHotkeyEx`, `milliseconds_win_key_must_be_pressed`, settings clamp
- `src\modules\ShortcutGuide\ShortcutGuide.Ui\ShortcutGuideXAML\App.xaml.cs` — activation event and Windows-key release handling
- `src\modules\ShortcutGuide\ShortcutGuide.Ui\ShortcutGuideXAML\OverlayWindow.xaml.cs` — overlay show/close and taskbar-pane layout
- `src\modules\ShortcutGuide\ShortcutGuide.Ui\ShortcutGuideXAML\Controls\MainPaneControl.xaml.cs` — navigation/page taskbar visibility
