# PowerToys Settings — module verification profile

| Bootstrap fact | Value |
|---|---|
| Surface | Settings shell, Home dashboard, General page, module pages, Quick Access, What's New, and OOBE/SCOOBE |
| Source | `src\settings-ui\` and `src\runner\settings_window.cpp` |
| General settings | `%LOCALAPPDATA%\Microsoft\PowerToys\settings.json` |
| Language override | `%LOCALAPPDATA%\Microsoft\PowerToys\language.json` |
| Main UI | `PowerToys.Settings.exe` · UIA app ID `PowerToys.Settings` |
| Quick Access | `PowerToys.QuickAccess.exe` · UIA app ID `PowerToys.QuickAccess` |
| Backup metadata | `HKCU\Software\Microsoft\PowerToys` |
| Last verified | `0.101.2222.0` · 2026-08-17 |

## UI state-transition map

| Current state | Trigger / control | Next state | Observable side effect |
|---|---|---|---|
| No Settings window | Tray **Settings**, `PowerToys.exe --open-settings`, or a module's **Open settings** action | Main Settings window | One Settings process and one main window exist; the requested page is selected |
| Main window | Navigation item | Home, General, category, or module page | Page-specific heading/control appears and navigation selection follows |
| Home | `Sort utilities` | Alphabetical or By status | Utility order changes; `dashboard_sort_order` persists |
| Home or module page | Utility/module toggle | Updated module state | General JSON, Home, module page, Quick Access, and the module process/event converge |
| Quick Access launch page | `More` | All apps | Sort control and module toggles become available |
| Quick Access All apps | `Back` | Launch page | Pinned launch actions return |
| General | `Activation shortcut` / `EditButton` | Shortcut dialog | Save, Cancel, Reset, and captured key visuals are available |
| General | Language selection | Restart info bar | `language.json` changes; **Restart** restarts Runner and Settings at the same integrity level |
| General | **Back up** | Backup result state | A `settings_*.ptb` archive and manifest are written |
| General | **Restore** | Runner/Settings restart | The newest archive is applied before Settings reopens |
| Home or General | What's New entry | What's New window | A secondary Settings-owned window opens |
| Welcome navigation | Welcome/OOBE window | OOBE/SCOOBE surface | Secondary window can outlive the main window |

## Entry-paths (try in order)

### 1. Existing Settings window

Resolve the current HWND from `winapp ui list-windows --json`; the JSON result is an
array directly. Reuse the existing window rather than launching another process.

### 2. Tray and module entry points

Use the tray context-menu **Settings** command for the canonical shell entry. Use a
module's **Open settings** action when the item asserts requested-page navigation.
Both paths must reuse the singleton main Settings window.

### 3. Runner command line

Run the installed `PowerToys.exe --open-settings` only when no Settings window exists.
It signals the existing Runner; do not launch `PowerToys.Settings.exe` directly because
the normal IPC and lifecycle arguments come from Runner.

### 4. Quick Access

Left-click the tray icon when Quick Access is enabled. The flyout's UIA tree can be
empty; use `get-focused` plus Tab/Shift+Tab/arrow traversal and verify the resulting
JSON/process state.

## Recipes — capability/control index

| # | Capability | Preferred control / drive |
|---|---|---|
| 1 | Navigate the main shell | Runtime navigation AutomationIds such as `DashboardNavItem`, `GeneralNavItem`, and module `*NavItem` |
| 2 | Change Home utility sorting | `Sort utilities` → Alphabetical or By status |
| 3 | Toggle a module across surfaces | Home utility row, module-page toggle, or Quick Access All apps toggle |
| 4 | Open and traverse Quick Access | Tray icon → `More` / `Back`; use focused control names and arrow keys when inspection is empty |
| 5 | Edit the Quick Access shortcut | `EditButton` named `Activation shortcut`; `PrimaryButton`; `ResetBtn` |
| 6 | Change application language | `Languages_ComboBox`; restart info-bar button named `Restart` |
| 7 | Change Settings appearance | Theme ComboBox; **Show system tray icon**; **Show a monochrome icon that matches the Windows theme** |
| 8 | Change elevation/startup state | **Running as user/administrator** expander, restart-elevation action, run-at-startup and always-admin controls |
| 9 | Back up and restore settings | Backup expander; exact runtime buttons **Back up**, **Restore**, and **Select folder** |
| 10 | Inspect update state | Home update card, General update expander, last-checked label, and tray badge |
| 11 | Exercise secondary windows | `WhatIsNewNavItem`, `OOBENavItem`, and each secondary window's **Open Settings** action |
| 12 | Generate a bug report | **Generate package** button; observe `PowerToys.BugReportTool.exe` and the output archive |

### Read-out notes

- Read Home sorting, Quick Access state/shortcut, theme, elevation preference, and module
  enablement from the root `settings.json`.
- Read the selected application language from `language.json`; process restart alone is
  not proof that localization loaded.
- Validate actual integrity with `Test-ProcessElevated`; page text is only a UI assertion.
- Quick Access is hidden by DWM cloaking. Use `DwmGetWindowAttribute` with
  `DWMWA_CLOAKED` (`14`), not `IsWindowVisible`, to distinguish shown and dismissed states.
- Backup archives are ZIP-compatible `.ptb` files. Inspect `manifest.json` and compare
  selected settings-file hashes before mutation and after restore.
- The backup path is `SettingsBackupAndRestoreDir` under
  `HKCU\Software\Microsoft\PowerToys`; absence means the Documents-based default.
- For bug reports, record process creation/exit and archive metadata, extract only the
  specific non-sensitive evidence needed, then delete the generated report archive.

## BLOCKED traps

- **Navigation selection is unreliable through InvokePattern.** Prefer foreground `click`.
  When the input desktop is detached, focus the navigation item and post Enter, then confirm
  a page-specific control appeared; never assume the posted key reached WinUI.
- **Quick Access UIA is intermittent.** Full inspection can return zero elements while
  `get-focused` still works. Traverse by focused names and assert settings/process side effects
  rather than retaining generated selectors across virtualization changes.
- **Detached RDP blocks shortcut verification.** `GetForegroundWindow() == 0` makes SendInput
  fail with access denied. Continue UIA/PostMessage cases, but classify hotkey-binding checks
  `BLK-ENV` unless an attached desktop returns.
- **UAC consent is on the secure desktop.** If no human can approve it, the restart-as-admin
  round trip is `BLK-ENV`; do not synthesize input toward an unknown foreground.
- **The classic backup folder picker blocks UIA invoke.** Start the invoke in a child process,
  navigate the `#32770` tree with UIA focus plus Right-arrow expansion, select the target item,
  and invoke OK. Do not send `BFFM_SETSELECTIONW`; it can crash Settings in
  `windows.storage.dll`.
- **An offered update suppresses a fresh check.** When **Install now** replaces
  **Check for updates**, badge clearing and a new timestamp require installation; classify the
  installation-dependent remainder `BLK-DESTRUCTIVE`.
- **Adaptive tray icon follows the Windows app theme, not the PowerToys Settings theme.**
  Change the Windows Personalize values for that assertion and restore them afterward.
- **Disabled Quick Access removes its tray command.** Tray left-click opens Settings and the
  tray context-menu **Quick access** command is deleted until Quick Access is re-enabled.
- **Open module pages can retain a stale toggle.** For the synchronization assertion, keep the
  target module page open and visible before changing the state elsewhere; foregrounding it is not
  a refresh. Record the existing page first, then separately navigate away/back to distinguish a
  stale page instance from incorrect persisted/module state. On `0.101.2222.0`, Find My Mouse was
  deterministic in both directions: the existing page stayed stale, while Home and a recreated
  Mouse Utilities page showed the updated value. Do not treat page recreation as satisfying the
  live-update assertion: the v0.96 baseline explicitly required the already-open module page to
  update, and the old in-process flyout implemented that through
  `UpdateGeneralSettingsCallback` -> `SignalGeneralDataUpdate`. The separate Quick Access process
  introduced by PR `#43840` no longer has that callback path.

## Fixtures

- One representative module with a deterministic Named Event for cross-surface toggles.
- Find My Mouse for legacy Mouse Utilities and Quick Access synchronization.
- Two unused, non-reserved shortcut chords when proving that rebinding disables the old chord.
- A uniquely named nested folder under Downloads for backup/restore; remove it and restore the
  original registry metadata after the case.
- A disposable policy value under `HKLM\Software\Policies\PowerToys`; back up the exact prior
  key/value state and restore it after Runner restarts.

## Source citations

- `SettingsXAML\Views\GeneralPage.xaml` — language, appearance, Quick Access, backup, diagnostics,
  and bug-report controls.
- `SettingsXAML\Views\GeneralPage.xaml.cs` — folder picker and bug-report IPC.
- `ViewModels\GeneralViewModel.cs` — restart, language, backup/restore, policy, and appearance state.
- `Settings.UI.Library\SettingsBackupAndRestoreUtils.cs` — registry metadata, archive selection,
  manifest creation, and restore behavior.
- `SettingsXAML\App.xaml.cs` `App()` — application-language override before XAML initialization.
- `src\runner\settings_window.cpp` `dispatch_json_action_to_module` — same-elevation and
  elevation-changing restart actions.
- `src\runner\tray_icon.cpp` — Quick Access command gating and adaptive tray-icon selection.
