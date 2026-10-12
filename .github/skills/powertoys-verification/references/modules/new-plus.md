# New+ — module verification profile

**PT module**: `NewPlus` (Explorer right-click → "New+" submenu that creates files/folders from a user templates folder)
**Source**: `<PT-repo>\src\modules\NewPlus\` (shell ext) + `<PT-repo>\src\settings-ui\Settings.UI\ViewModels\NewPlusViewModel.cs` (Settings UI)
**Module-owned settings file**: `%LOCALAPPDATA%\Microsoft\PowerToys\NewPlus\settings.json` — **folder is `NewPlus`, NOT `New`** (matches SKILL.md pitfall #12 table). Keys: `HideFileExtension`, `HideStartingDigits`, `TemplateLocation`, `ReplaceVariables`, `BuiltInNewHidePreference`.
**Templates folder (default)**: `%LOCALAPPDATA%\Microsoft\PowerToys\NewPlus\Templates` (per `TemplateLocation`)
**Default-templates source**: `%LOCALAPPDATA%\PowerToys\WinUI3Apps\Assets\NewPlus\Templates` (also `%ProgramFiles%\PowerToys\...` on machine installs)
**Logs**: `%LOCALAPPDATA%\Microsoft\PowerToys\NewPlus\NewPlus.ShellExtension\Logs\v<ver>\log_<date>.log`
**Packaged command**: sparse MSIX `Microsoft.PowerToys.NewPlusContextMenu`; modern command CLSID `{69824FC6-4660-4A09-9E7C-48DA63C6CC0F}`.
**Runtime/legacy command**: CLSID `{FF90D477-E32A-4BE8-8CC5-A502A97F5401}`; this is the HKCU registration reported by the Runner's registration log.
**Named Event**: none. **DSC**: n/a.

> Read **`..\explorer-context-menu-flow.md` first** — New+ is a Win11 packaged-IExplorerCommand context-menu module; the menu can only be eyeballed via a real synthetic right-click on an **unlocked interactive desktop**. On a locked/RDP-minimized desktop (`Test-PtDesktopInteractive=False`) all "menu appears / template appears / hidden-caption" assertions are BLK-ENV / BLK-VISUAL-RENDER, not product FAILs.

## Entry-paths (try in order)

### 1. Enable/disable + registration gate (menu presence/absence)
Drive enable/disable through the **Settings-UI toggle** (entry-path 2 / the shared helper) — it's the faithful user flow, runs the Settings→runner IPC path, and (uniquely for New+) triggers the enable-time `CopyTemplateExamples` that seeds the default templates. Observe the gate:
- Runtime/legacy CLSID registered ⇒ `Test-Path "HKCU:\Software\Classes\CLSID\{FF90D477-E32A-4BE8-8CC5-A502A97F5401}"` is `True` (enabled) / `False` (disabled).
- Log lines `New+ context menu registered` / `... unregistered` + `Runtime registration completed for CLSID ...`.
- Sparse package stays `Status Ok` even when disabled (hidden dynamically — SKILL.md pitfall #11).

Keep the two CLSIDs distinct: the HKCU probe corroborates runtime/legacy registration,
not activation of the modern packaged command. Read the installed package manifest when
checking its identity; only the actual modern menu proves that it rendered.

> The toggle needs an unlocked interactive desktop. If it's locked / RDP-minimized so the Settings UI can't be driven, mark the item `BLK-ENV` (`references/environment-setup.md`).

### 2. Settings UI toggle via the shared helper — **required for template auto-copy**
Use `Set-PtModuleEnabledViaSettingsUI -PageTag NewPlus -EnabledKey NewPlus` (`scripts/pt-explorer-contextmenu.ps1`; see `references/explorer-context-menu-flow.md` → "Enabling / disabling the module"). It opens `--open-settings=NewPlus`, finds the enable toggle by its `[on]/[off]` state, and flips it. Manual equivalent — `winapp ui invoke <btn> -w <settingsHwnd>`:
- Enable toggle: discover by state (e.g. `btn-new-XXXX` under `NewPlusEnableToggle`) — **the enable transition runs `CopyTemplateExamples`** (Settings-UI side, `NewPlusViewModel.IsEnabled` setter), so templates are seeded only when you flip the actual toggle.
- `btn-hidethefileexte-XXXX` (Hide file extension), `btn-hideleadingdigi-XXXX` (Hide leading digits). AutomationIds carry a per-session suffix — re-`inspect` to get the live id.

### 3. Synthetic right-click on the folder **BACKGROUND** (the menu-render observer) — needs unlocked desktop
New+ lives in the folder-background ("New") menu, **not** a file's context menu — so
`Open-PtExplorerContextMenu` (which right-clicks a *file item*) is the wrong entry. Use
**`Open-PtBackgroundContextMenu -ExplorerHwnd <h>`** (coordinate-free Shift+F10 with nothing selected;
validates it got the background menu), then expand the `New+` submenu with
**`Expand-PtModernSubmenu`** (the modern-menu sibling of `Open-PtShowMoreOptionsMenu`; both in
`scripts/pt-explorer-contextmenu.ps1`):
```powershell
$bg  = Open-PtBackgroundContextMenu -ExplorerHwnd $hwnd            # folder-background ("New") menu
$sub = Expand-PtModernSubmenu -MenuHwnd $bg -ItemName 'New+' `     # invokes New+, returns the child popup HWND
                              -ContainsItem 'Open templates'       # disambiguates parent vs child PopupWindowSiteBridge
Get-PtContextMenuItems -MenuHwnd $sub                              # templates are 1:1 with the Templates-folder entries
# Invoke-PtContextMenuItem -MenuHwnd $sub -ItemName '<template>'   # select a template (creates it in the current folder)
```
`Expand-PtModernSubmenu` reuses `Invoke-PtContextMenuItem` for the click and resolves the child
`PopupWindowSiteBridge` popup (preferring the one that contains `-ContainsItem`, else a newly-appeared
popup). Template items render with **caption transforms applied** (HideFileExtension strips `.txt`; HideStartingDigits strips `01. `). Selecting a template creates it in the current folder + enters rename mode. BLK-ENV only if `Test-PtDesktopInteractive` is False. **No Explorer restart needed** for setting A/B — the handler re-reads `NewPlus\settings.json` on each menu build.

## Recipes — a control/observation map, NOT an answer key

| # | Capability | Drive (control / settings key) | Observe (where the result shows) |
|---|---|---|---|
| 1 | Menu entry present when enabled | enable via **Settings-UI toggle** (`Set-PtModuleEnabledViaSettingsUI -PageTag NewPlus`; locked desktop → `BLK-ENV`) | CLSID registered in `HKCU\…\CLSID`, log `context menu registered`; *visible submenu* = synthetic menu only (BLK-VISUAL-RENDER if locked) |
| 2 | Menu entry absent when disabled | disable | CLSID absent, log `context menu unregistered`; package still `Status Ok` |
| 3 | Templates folder created empty | shell ext `create_folder_if_not_exist(root)` on menu build (delete folder → right-click) | folder recreated **empty** — needs synthetic menu (BLK-ENV if locked) |
| 4 | Default templates copied when empty | `CopyTemplateExamples` on Settings-UI **enable** transition (`btn-new-248c` off→on) while folder empty | Templates folder repopulated from install Assets (filesystem — headless-safe) |
| 5 | A template (file/folder) shows + creates on select | put item in Templates folder; select it in the New+ submenu | submenu item (1:1 with dir entries) + `SHFileOperation FO_COPY` to target — synthetic menu only |
| 6 | Hide file extension | `HideFileExtension` / `btn-hidethefileexte-24a0` | strips ext from **menu caption only** (`get_menu_title`, `show_extension=false`); created file keeps ext — caption is BLK-VISUAL-RENDER if locked |
| 7 | Hide starting digits/spaces/dots | `HideStartingDigits` / `btn-hideleadingdigi-24a8` | strips leading digits+separator from **both** menu caption and **created filename** (`remove_starting_digits_from_filename` via `get_menu_title` + `copy_template`); needs a digit-prefixed template + render |

> For Scenario A, drive these settings through the shipped Settings UI and read the
> **module-owned** `NewPlus\settings.json` as corroborating evidence. Do not edit it to
> bypass the UI; preserve and restore the original values.

## Common BLOCKED traps
- **Default templates are only seeded by the Settings-UI enable transition** (`NewPlusViewModel.IsEnabled` → `CopyTemplateExamples`) — always drive enable via the UIA toggle for any template-auto-copy item.
- **Menu render is invisible without a real right-click** — packaged command is not `CoCreate`-able (`REGDB_E_CLASSNOTREGISTERED`) and not in classic `Shell.Application.Verbs()`. Locked desktop ⇒ BLK-ENV; do not substitute a CLI/back-door (there isn't one, and it'd be a false PASS).
- **No template-count observable** — `saved_number_of_templates` is an in-memory static (`new_utilities.cpp`), not registry/log.
- Don't edit `…\PowerToys\New\settings.json` — wrong path; the file is under `NewPlus\`. Re-reads per menu build, so don't restart Explorer to apply a setting.
- Use the folder **background** ("New") menu, not `Open-PtExplorerContextMenu`; **expand the `New+` submenu** before enumerating templates. Locked desktop ⇒ menu-render items are BLK-ENV, not product FAIL.

- If a command-line-created Explorer fixture exposes only base background verbs, try a
  standard **Win+E** window as a distinct entry path before concluding New+ is absent.
  Prove its HWND is new before navigating it to the owned destination, and allow the
  modern menu to populate. Do not adopt or navigate a pre-existing user window.
- File existence is not proof of inline rename. The rename worker is asynchronous and
  currently polls for up to two seconds (`template_item.cpp`, `rename_on_other_thread_workaround`).
  Observe the actual `Edit` / `UIRenameTextElement` for the owned filename and take a
  passive screenshot before sending Escape. A focused `ListItem` or an early empty
  Explorer view does not establish rename mode; never press F2 to make the assertion pass.
- The Settings **Change** button opens a legacy **Browse For Folder** dialog. A synchronous
  UIA Invoke can time out while leaving that dialog open. Re-observe the owned dialog
  instead of replaying Change; preserve the original template path and tree before
  selecting an owned directory through the picker. If UIA is unavailable, use a reviewed
  passive capture and guarded native tree keyboard input. Do not send pointer-bearing
  `BFFM_SETSELECTION` messages across processes or bypass the picker with a settings write.

## Fixture files needed
- A plain file (e.g. `test.txt`) and a folder-with-files to drop into Templates (template-appears items).
- A digit-prefixed template (e.g. `01. Test.txt`) to exercise Hide-starting-digits.

## Source citations
- `src\modules\NewPlus\NewShellExtensionContextMenu\AppxManifest.xml` — modern packaged CLSID and directory/background declarations.
- `src\modules\NewPlus\NewShellExtensionContextMenu\RuntimeRegistration.h` and `src\modules\NewPlus\NewShellExtensionContextMenu.win10\shell_context_menu_win10.h` — runtime/legacy CLSID.
- `src/modules/NewPlus/NewShellExtensionContextMenu/template_item.cpp` — `get_menu_title` (hide-extension), `remove_starting_digits_from_filename`, `copy_object_to`.
- `src/modules/NewPlus/NewShellExtensionContextMenu/new_utilities.h` — `copy_template`, `create_folder_if_not_exist`, `get_newplus_setting_hide_*`, `register_msix_package`.
- `src/modules/NewPlus/NewShellExtensionContextMenu/shell_context_sub_menu.cpp` — `create_folder_if_not_exist(root)` + template enumeration.
- `src/settings-ui/Settings.UI/ViewModels/NewPlusViewModel.cs` — `CopyTemplateExamples` (creates dir; copies examples only when files==0 && dirs==0), called from `IsEnabled` setter / `OpenNewTemplateFolder` / `DashboardViewModel`.
