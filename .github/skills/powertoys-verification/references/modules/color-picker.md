# Color Picker - module verification profile

## Module facts

**PT module**: `ColorPicker` / display name **Color Picker**
**Source**: `src\modules\colorPicker\`
**Settings**: `%LOCALAPPDATA%\Microsoft\PowerToys\ColorPicker\settings.json`
**History**: `%LOCALAPPDATA%\Microsoft\PowerToys\ColorPicker\colorHistory.json`
**WPF executable**: `<installed PowerToys directory>\PowerToys.ColorPickerUI.exe`
**Settings executable**: `<installed PowerToys directory>\WinUI3Apps\PowerToys.Settings.exe`
**Default shortcut**: `Win+Shift+C`; read the actual `properties.ActivationShortcut` before testing.
**Named event**: `ColorPicker.Show` in `scripts\pt-shared-events.ps1`
**Last verified**: installed `0.101.2362.0`, WPF, 2026-09-18; `winapp 0.6.1`, English UI, 200% DPI.
**Checklist**: [0.96 baseline plus changes through stable 0.101](../release-checklist/color-picker.md).

This map describes WPF (`HwndWrapper[...]` native classes). Main has the later WinUI migration (#49174,
milestone 0.102), not tested by running installed 0.101. Resolve the actual process path/version/UI stack;
rediscover controls for WinUI rather than carrying over WPF selectors.

## Entry-paths

### 1. Settings enablement and downstream activation

Open Settings with `PowerToys.exe --open-settings=ColorPicker` or select `ColorPickerNavItem`.
Use its Color Picker toggle and wait for the module process; do not replace this UI transition with JSON writes.

```powershell
. "$skill\scripts\pt-shared-events.ps1"
Invoke-PtSharedEvent -Name 'ColorPicker.Show'
winapp ui list-windows -a PowerToys.ColorPickerUI --json
```

The event follows the configured activation behavior, not the keyboard-binding path. Hidden residency is normal;
an enabled flag/event handle alone does not prove surface readiness. Disable exits the process: re-resolve identities.

### 2. Physical shortcut

Use `pt-sendinput-chord.ps1` with configured modifiers/key code. Establish foreground using
`pt-foreground-guard.ps1`, then check the specific HWND. Assign/restore through the shortcut dialog
(`EditButton`, `PrimaryButton`, `CloseButton`); verify saved fields and activation. Restore the original, not Reset.

### 3. Editor and Welcome controls

Discover **Pick color from screen** and **Open settings** by role/name. Test the Settings link from a different
Settings page, not an already-selected background destination.

Physically click Settings' `OOBENavItem` (Tapped, no InvokePattern). In Welcome's own HWND, select Color Picker,
then use `LaunchButton`. Re-enter after enablement changes: the guard runs on navigation.
Re-resolve Settings afterward; its original process/window disappeared during the recorded Welcome workflow.

### UI state transitions

| State | Action | Observation surface |
|---|---|---|
| Disabled | Enable in Settings | Module process; picker/editor can remain hidden |
| Enabled, hidden | Named event or configured chord | Picker when `activationaction=1`; editor when `activationaction=0` |
| Picker | Mouse action `0` | Clipboard and editor |
| Picker | Mouse action `1` | Clipboard; picker closes without editor |
| Picker | Mouse action `2` or Escape | Picker closes without selecting a color |
| Editor | Pick color from screen | Picker; subsequent mouse action controls the return |
| Editor | Selected-color control | Separate adjustment popup |
| Editor | Close | Hidden resident module |
| Enabled | Disable in Settings | Module process exits; old window/control identities expire |

The old three activation options are now two plus mouse-button actions. Preserve each original
`primaryclickaction`, `middleclickaction` and `secondaryclickaction`.

## Recipes - capability/control map

| Capability | Drive |
|---|---|
| Module enablement | Settings toggle; general `enabled.ColorPicker` |
| Activation shortcut | `ColorPickerNavItem` -> `EditButton`; `properties.ActivationShortcut` |
| Direct editor / picker | **Activation behavior** ComboBox; `properties.activationaction` |
| Mouse behavior | **Mouse actions** expander and button-action ComboBoxes |
| Sampling a known surface | `winapp ui hover <swatch-selector> -w <fixture-hwnd>`, then `click` on that swatch |
| Default copied format | Settings `ColorPicker_ComboBox`; `properties.copiedcolorrepresentation` |
| Color-name display | **Show color name** toggle; `properties.showcolorname.value` |
| Format enablement | Locate the named format row, then its own **Enable colorformat** toggle |
| Format ordering | The row's own **More options** -> **Move up** / **Move down** |
| Format editing | Physical row click; `NewColorFormatTextBox`, commit focus, `PrimaryButton` |
| Editor copying | Format DataItem's own **Copy to clipboard** button |
| History | `HistoryColors` ListItems; select/right-click entry -> current **Remove** MenuItem |
| Adjust color | Physical click on `CurrentColorButton`; discover the popup's RGB/HEX edits and HSV sliders |
| Magnifier | `winapp ui scroll <swatch-selector> --wheel <notches> -w <fixture-hwnd>` |
| Settings link | Editor **Open settings**; observe destination page/foreground |
| CmdPal integration | Enable companion through Settings; discover actual PowerToys-extension commands |

### Read-out notes

- Resolve the current process, then specific HWNDs. Accessible roots are **Color Picker** and **Color Picker
  editor**; native titles can be blank.
- Hidden `ColorHexAutomationPeer` exposes the selected representation, including RGB. Cross-check actual
  clipboard and pixels. With names off, `ColorTextBlock` can still expose a color name through UIA:
  compare screenshots to establish whether the name is rendered.
- Editor read-only fields/copy buttons repeat. Resolve the owning format row, not the first matching control.
  Use `get-value --json` for fields/selections and independently check persistence.
- Reorder/navigation can replace selectors: re-inspect. Keep popup discovery/action together; switching windows
  dismisses a history context menu.
- Adjust color uses a separate popup. Inspect all app windows and capture its composed-screen region passively;
  a window-only screenshot can omit the popup.
- Check zoom pixels and capture restoration separately. Window display affinity is only supporting evidence.
- WPF logs: `ColorPicker\Logs\<version>\`; native logs: `ColorPicker\ModuleInterface\Logs\v<version>\`.
  Review the run's interval, including startup/hotkey activity, not just historical errors.

## BLOCKED traps

- **Coordinate mismatch is not automatically a product defect.** At 200% DPI the run-local cursor path disagreed
  with UIA coordinates; CLI hover/click sampled correctly. Prefer those verbs and validate fixture pixels.
- **Check current CLI help.** `winapp 0.6.1` includes hover, wheel and send-keys omitted by older mechanics docs.
- **Button/ListItem does not imply InvokePattern.** Format rows, Welcome and Open Command Palette needed
  physical clicks. A second ExpandCollapse `invoke` also need not collapse an expanded header: inspect or click.
- **Do not infer unavailable variants.** Ordinary sampling does not cover `0/1` refresh-rate reports, and an
  inactive WMI adapter reporting `1` does not establish the active primary-display input. English rendering does
  not cover localization; elevation variants need an elevated runner/session.
- **Application search is not the PowerToys extension.** Require actual picker/settings/history commands.
  This run found none and logged fresh `Failed to find PowerToys: -2147467262` / `E_NOINTERFACE`, with zero
  started extensions. Report that integration failure, not an independently demonstrated pinning-logic failure.

## Fixtures and restoration

Use an owned opaque swatch window; sample away from borders using UIA bounds. Record its PID/HWND.

Preserve settings, history, enabled states, shortcut, Settings page/placement and clipboard.
History can evict entries at its limit: establish safe capacity and restore it after stopping the module.

The main clipboard helper only inspects formats. Eagerly preserve all original content until cleanup.
WinForms returned null for native Bitmap while WPF `Clipboard.GetImage()` worked; preserve PNG and clipboard-policy
streams too. Do not replace rich/image data with text or overwrite intervening user content.

Restore UI settings first. After original disabled states/process exit, restore file bytes and verify hashes,
checking for unowned changes first. Restore any touched CmdPal packaged-app settings/state after its process exits.
Close owned fixtures, restore foreground/pointer and preserve diagnostic logs.

## Source citations

Use the stable tag for the WPF implementation:

- `v0.101.2362.0:src\settings-ui\Settings.UI.Library\Enumerations\ColorPickerActivationAction.cs`
  and `ColorPickerClickAction.cs` - activation and mouse-action values.
- `v0.101.2362.0:src\modules\colorPicker\ColorPickerUI\Helpers\AppStateHandler.cs` -
  `StartUserSession`, picker/editor lifecycle.
- `v0.101.2362.0:src\modules\colorPicker\ColorPickerUI\Settings\UserSettings.cs` -
  `ColorHistory_CollectionChanged`, history persistence and settings loading.
- `v0.101.2362.0:src\modules\colorPicker\ColorPickerUI\Helpers\ZoomWindowHelper.cs` -
  capture exclusion/restoration; `Mouse\MouseInfoProvider.cs` - refresh-rate fallback.
- `v0.101.2362.0:src\settings-ui\Settings.UI\SettingsXAML\Views\ColorPickerPage.xaml` -
  Settings controls; `OOBE\Views\OobeColorPicker.xaml.cs` - navigation-time launch guard.
- `v0.101.2362.0:src\modules\cmdpal\ext\Microsoft.CmdPal.Ext.PowerToys\Modules\ColorPickerModuleCommandProvider.cs`
  - enablement-dependent command inventory and stable command IDs.
