# Shortcut Guide — module verification profile

| Bootstrap fact | Value |
|---|---|
| PT module | `Shortcut Guide` — app-aware shortcut pages plus Windows taskbar indicators |
| Source | `src\modules\ShortcutGuide\` |
| Settings | `%LOCALAPPDATA%\Microsoft\PowerToys\Shortcut Guide\settings.json` |
| Pinned rows | `%LOCALAPPDATA%\Microsoft\PowerToys\Shortcut Guide\Pinned.json` |
| User manifests | `%LOCALAPPDATA%\Microsoft\WinGet\KeyboardShortcuts\` |
| Bundled manifests | `%LOCALAPPDATA%\PowerToys\WinUI3Apps\Assets\ShortcutGuide\Manifests\` |
| Exe | `%LOCALAPPDATA%\PowerToys\WinUI3Apps\PowerToys.ShortcutGuide.exe` |
| Default hotkey | <kbd>Win</kbd> + <kbd>Shift</kbd> + <kbd>/</kbd> · `properties.open_shortcutguide` |
| Named Events | `ShortcutGuide.Trigger` · `ShortcutGuide.Exit` |
| Last verified | `0.101.2282.0` · 2026-08-18 |

## UI state-transition map

| Current state | Trigger / control | Next state | Observable side effect |
|---|---|---|---|
| Module process with hidden host | `ShortcutGuide.Trigger`, configured chord, Quick Access, or Command Palette | Full overlay | One full-monitor transparent host becomes visible and its main pane opens |
| Module process with hidden host while a Windows key is down | Runner long-press signal | Configured hold action | **Off** does nothing; **Show taskbar indicators** shows numbered taskbar markers; **Open Shortcut Guide** shows the main pane |
| Full overlay | Application rail item | Selected application page | Selection follows the page; its manifest rows replace the prior page |
| Application page | Search query or <kbd>Ctrl</kbd>+<kbd>F</kbd> | Filtered page | Matching rows and section headings remain; the query is retained when switching pages |
| Application page | Shortcut-row context menu → **Pin** / **Unpin** | Updated Pinned section | The row and `Pinned.json` update without closing the overlay |
| Full overlay | Rail **Settings** item | PowerToys Settings → Shortcut Guide | Existing Settings singleton opens or navigates to the module page |
| Visible overlay | Escape, configured chord, Close, deactivation, or transparent host click | Hidden host | The same process and HWND remain reusable; `IsWindowVisible` becomes false |
| Module startup | Copy thread + index generator + PowerToys populator | Ready hidden host | Bundled manifests are copied, `index.yml` is regenerated, and PowerToys rows are populated |

## Entry-paths (try in order)

### 1. Named Event

Use `Invoke-PtSharedEvent -Name 'ShortcutGuide.Trigger'` for downstream overlay behavior.
Use `ShortcutGuide.Exit` only for process cleanup. A Named Event does not prove the
configured chord or excluded-app gate.

### 2. Configured activation chord or Windows-key hold

Use real SendInput only when the binding or hold behavior is the assertion. Guard the
foreground app immediately before injection. For a hold, send Windows-key down, wait
the configured duration, perform the assertion, then always send Windows-key up in
`finally`.

### 3. Quick Access and Command Palette

Quick Access launches the module action. Command Palette exposes **Toggle Shortcut
Guide** while enabled and keeps only **Shortcut Guide settings** while disabled.
Use those paths only when the integration itself is under test.

### 4. Direct module relaunch

Use the installed executable only for startup-sensitive settings or manifest work:

```powershell
Start-PtNonElevated `
  -Exe "$env:LOCALAPPDATA\PowerToys\WinUI3Apps\PowerToys.ShortcutGuide.exe" `
  -Arguments '<runner-pid>' `
  -MatchProcessName 'PowerToys.ShortcutGuide'
```

Pass a real Runner PID. Direct launch is not evidence for Runner hotkey binding or
Quick Access/Command Palette integration.

## Recipes — capability/control index

| # | Capability | Preferred control / drive |
|---|---|---|
| 1 | Enable or disable the module | Root `settings.json` → `enabled.Shortcut Guide`; restart Runner |
| 2 | Change the activation chord | Module settings → `properties.open_shortcutguide` |
| 3 | Open or toggle the full overlay | `ShortcutGuide.Trigger` or the configured chord when binding is the assertion |
| 4 | Exercise close routes | `CloseButton`, Escape, repeat activation chord, transparent host pointer input, foreground change |
| 5 | Exclude foreground applications | Settings **Excluded apps** editor / `properties.disabled_apps.value`; restart the module before judging the gate |
| 6 | Configure Windows-key hold | Settings **Hold Windows key** (`0` off, `1` indicators, `2` guide), `press_time` (100-5,000 ms), and `close_on_windows_key_release` |
| 7 | Change theme | Settings **Theme** / `properties.theme.value` (`light`, `dark`, `system`); relaunch only when the item explicitly permits startup-only application |
| 8 | Change pane side | Settings **Window position** / `properties.window_position.value` (`0` left, `1` right); assert the next open without relaunch |
| 9 | Search the selected page | `ShortcutGuide_SearchBox` / child `TextBox`; use <kbd>Ctrl</kbd>+<kbd>F</kbd>, query text, and `ShortcutGuide_NoSearchResults` |
| 10 | Select an application page | Runtime `NavigationViewItem` whose AutomationId is the manifest package name |
| 11 | Pin or unpin a shortcut | Right-click a realized shortcut row; invoke **Pin** or **Unpin** in the context menu |
| 12 | Rebuild manifest inventory | Per-user manifest directory + `PowerToys.ShortcutGuide.IndexYmlGenerator.exe` |
| 13 | Validate key-token rendering | Disposable `+`-prefixed manifest filtered to a tracked foreground fixture |
| 14 | Refresh generated PowerToys rows | Relaunch the module so `PowerToysShortcutsPopulator.Populate()` runs |
| 15 | Drive taskbar indicators | Real left- and right-Windows-key holds; press a number while still holding for activation |
| 16 | Open module settings | Rail item named **Settings** |
| 17 | Change localization | Root `language.json`; restart Runner and module |
| 18 | Audit keyboard/UIA accessibility | Tab/arrow traversal plus `winapp ui inspect/search/get-focused` |

### Read-out notes

- Resolve the current Shortcut Guide HWND at runtime. The persistent WinUI host remains
  enumerated while hidden; use Win32 `IsWindowVisible`, not window-list presence.
- The visible overlay is one full-monitor `WinUIDesktopWin32WindowClass` tool window.
  `WS_EX_TOOLWINDOW` and no `WS_EX_APPWINDOW` are the durable Alt+Tab/taskbar read-outs.
- Application rows are custom-rendered and virtualized. Use UIA for row names and
  screenshots for key caps, glyphs, pane side, taskbar arrows, and visual theme.
- Search UIA uses `ShortcutGuide_SearchBox`, child `TextBox`, and
  `ShortcutGuide_NoSearchResults`. An empty TextBox can read as the placeholder
  `Search shortcuts`; confirm clearing by restored rows and inspect output, not only
  `get-value`.
- `index.yml` maps each process filter to package names. Exclude `index.yml` when
  counting manifests; compare the flattened index `Apps` multiset to manifest
  `PackageName` values.
- Startup overwrites bundled manifest filenames but preserves uniquely named custom
  manifests. `Microsoft.PowerToys.en-US.yml` is intentionally rewritten with current
  enabled-module hotkeys.
- `Pinned.json` is created on first pin/unpin. If it did not exist at pre-flight,
  remove an empty generated file during cleanup instead of retaining it.

## BLOCKED traps

- **The installed schema defines the available feature set.** Builds before
  `0.101.2262.0` do not contain page search or configurable Windows-key actions.
  Build `0.101.2282.0` contains both. Version-gate those checklist assertions before
  driving them.
- **Named Events bypass Runner gates.** They do not prove hotkey rebinding, disabled
  state, excluded-app behavior, or Windows-key timing.
- **Hot reload is setting-specific in `0.101.2282.0`.** Pane-side changes apply on the
  next open without relaunch. Theme and excluded-app changes remain stale in the
  persistent process, and generated PowerToys rows are still startup-only. Do not
  relaunch when the checklist explicitly asserts live application; a required
  relaunch is the failure evidence.
- **The default chord and left-Windows hold share one signal.** On `0.101.2222.0`,
  `App.ListenForLaunchedEvents` checks the live left-Windows key state; a real
  <kbd>Win</kbd>+<kbd>Shift</kbd>+<kbd>/</kbd> can therefore take the taskbar-only
  branch. `0.101.2282.0` remains foreground/timing dependent: one automated sample
  opened the full guide, while physical-keyboard confirmation closed the Notepad
  panel on key release and showed only taskbar numbers over Visual Studio Code.
  Require repeated real-chord checks over at least two foreground apps; one
  successful sample is insufficient to PASS.
- **Windows-key holds have two separate `0.101.2282.0` defects.** Real holds can emit
  paired `OnHotkeyEx` callbacks. Indicator mode masks the duplicate, but full-guide
  mode opens and immediately toggles closed; the duplicate can also call
  `MainPaneControl.Hide()` while `_getAppIdsTask` is incomplete and log
  `InvalidOperationException: A task may only be disposed if it is in a completion
  state`. Separately, the key-up hook filters only `VK_LWIN` (`91`), so releasing
  `VK_RWIN` (`92`) can leave indicators visible and open Start.
- **Close-route behavior is mixed in `0.101.2282.0`.** Escape, repeat chord, Close,
  and a real click on the transparent host dismiss correctly. Alt+Tab can move
  foreground away while the overlay remains visible; record foreground HWND and
  `IsWindowVisible` together for the focus-loss assertion.
- **Taskbar-section visibility can be stale.** The Notepad page can expose numbered
  taskbar indicators inherited from the Windows page. Inspect the selected page and
  screenshot the visible `1`-`0` strip rather than assuming page navigation reset it.
- **Do not infer screen-reader announcements from XAML alone.** In `0.101.2282.0`,
  the no-results text is present in UIA, but direct subscriptions observed neither
  `LiveRegionChangedEvent` nor `NotificationEvent`, and `LiveSettingProperty` was
  unsupported. Tab traversal also reached unnamed pane elements. Capture UIA events
  and focused element names when judging accessibility.
- **Hidden does not mean closed.** Close routes hide the host and preserve the process
  and HWND for reuse. Conversely, a stale hidden HWND in `list-windows` is not a
  visible orphan.
- **Application capture occurs at process startup and each full open.** Foreground the
  tracked fixture with the AttachThreadInput helper before triggering. Direct
  `SetForegroundWindow` commonly fails under Windows foreground lock.
- **Manifest generation is not transactional.** The generator deletes `index.yml`
  before parsing all manifests. A malformed YAML file can terminate generation and
  leave the index missing; isolate malformed-input probes and restore the directory
  immediately.
- **Do not parse all manifests with a stricter generic YAML parser.** Shipped files
  contain plain scalar forms accepted by YamlDotNet but rejected by some YAML 1.1
  parsers. Use the shipped generator exit code for parse validity.
- **Taskbar and Start windows can be DWM-cloaked.** Use `DWMWA_CLOAKED` in addition to
  `IsWindowVisible` when asserting that Start stayed closed after Windows+number.
- **Page rows can disappear from UIA while offscreen.** Scroll the main content pane,
  search after each scroll step, and capture the visible row. Do not infer a missing
  manifest entry from one virtualized tree.
- **Multi-monitor and movable-taskbar assertions need the stated topology.** A
  single-monitor session is `BLK-HARDWARE`, not a product result.
- **Clean-profile UI needs a genuinely interactive disposable session.**
  Same-session `CreateProcessWithLogonW` can create/load the profile while the child
  blocks on the current window-station desktop. A headless installed-library probe
  can confirm defaults but cannot replace Settings/OOBE first-render evidence; use a
  disposable VM/user session for a PASS.

## Fixtures

- One uniquely tracked Notepad window for app-page, exclusion, token-rendering, and
  foreground-capture cases. Preserve pre-existing Notepad processes.
- One fresh Explorer window opened at a unique temporary directory; close only that
  Shell window after the case.
- One disposable custom manifest with a unique package name and `Notepad.exe` filter.
- Three known eligible taskbar slots for indicator alignment and Windows+number tests.
- An elevated Paint or Notepad fixture for the cross-integrity activation case.

## Source citations

- `ShortcutGuide.Ui\Program.cs` `Main` — foreground capture, exclusion gate, manifest
  copy, index generation, and startup PowerToys-row population.
- `ShortcutGuide.Ui\ShortcutGuideXAML\App.xaml.cs` `ListenForLaunchedEvents` — shared
  trigger signal, Windows-key branch, left-only key-up filter, toggle behavior, and
  persistent host reuse.
- `ShortcutGuide.Ui\ShortcutGuideXAML\OverlayWindow.xaml.cs` — theme, close routes,
  animation/hide lifecycle, pane positioning, and taskbar layout.
- `ShortcutGuide.Ui\ShortcutGuideXAML\Controls\MainPaneControl.xaml.cs` — application
  rail, page selection, Settings deep link, taskbar-section detection, and hide-time
  task disposal.
- `ShortcutGuide.Ui\ShortcutGuideXAML\Pages\ShortcutsPage.xaml` and `.xaml.cs` —
  page-local search, no-results live region, Escape behavior, and query filtering.
- `ShortcutGuide.Ui\Helpers\ManifestInterpreter.cs` — manifest path, fixed `en-US`
  language, index cache, foreground/background process matching.
- `ShortcutGuide.Ui\Helpers\PowerToysShortcutsPopulator.cs` `Populate` — generated
  PowerToys rows and startup-only refresh behavior.
- `ShortcutGuide.IndexYmlGenerator\IndexYmlGenerator.cs` `CreateIndexYmlFile` —
  destructive index rebuild and duplicate package handling.
- `ShortcutGuide.Ui\ShortcutGuideXAML\Controls\KeyVisual.xaml.cs` `Update` — key-token
  glyph/text rendering.
