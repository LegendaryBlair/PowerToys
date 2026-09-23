# Color Picker - module verification profile

## Module facts

**PT module**: `ColorPicker` / **Color Picker**
**Source**: `src\modules\colorPicker\`
**Settings/history**: `%LOCALAPPDATA%\Microsoft\PowerToys\ColorPicker\settings.json`, `colorHistory.json`
**WinUI executable**: `<installed PowerToys directory>\WinUI3Apps\PowerToys.ColorPickerUI.exe`
**Settings executable**: `<installed PowerToys directory>\WinUI3Apps\PowerToys.Settings.exe`
**Default shortcut**: `Win+Shift+C`; read `properties.ActivationShortcut` for the actual binding.
**Named event**: `ColorPicker.Show` in `scripts\pt-shared-events.ps1`
**Last verified**: WinUI Preview `0.101.2572.0`, 2026-09-18; winapp 0.6.1, English UI, 200% DPI.
**Checklist**: [17 scenarios retaining 25 assertions](../release-checklist/color-picker.md).

The grouped checklist was exercised on WinUI (`WinUIDesktopWin32WindowClass`). Earlier WPF 0.101.2362.0 used
root-level binaries. Migration `cd7f82c22d` (#49174, milestone 0.102) is dated 2026-09-04 23:27:39 +08:00;
Preview 0.101.2572.0 contains it. Check actual bits, not only the 0.101 prefix.

## Entry paths

Choose the route that exercises the requested behavior, not a fixed fallback order.
Before entry or mutation, complete the snapshots and ownership setup in
[Fixtures and restoration](#fixtures-and-restoration). Module-specific planning suggestions
are in [Execution notes](#execution-notes), not part of the entry sequence.

Skip only unavailable elevated variants, per this checklist; this overrides the old common pre-flight's
whole-module admin stop.

### 1. Settings and downstream activation

Open `PowerToys.exe --open-settings=ColorPicker` or expand `SystemToolsNavItem` before `ColorPickerNavItem`.
The child is absent when collapsed. Read before toggling; observe saved state and matching process separately.

```powershell
. "$skill\scripts\pt-shared-events.ps1"
Invoke-PtSharedEvent -Name 'ColorPicker.Show'
winapp ui list-windows -a PowerToys.ColorPickerUI --json
```

Wait for a visible HWND before scoped UIA waits: the helper rejects hidden targets immediately.
Then observe `ColorTextBlock` (picker) or `PickColorButton`/`HistoryColors` (editor). Empty history is valid.
The event does not prove keyboard binding.

### 2. Physical shortcut

Use `Get-PtWindowIdentity` and `Assert-PtWindowIdentity -Foreground` from the
[small harness](../verification-harness.md) before `pt-sendinput-chord.ps1`. Do not use the old app-scoped
foreground helper to choose among multiple surfaces.
Background coordinators may need explicit interactive-caller focus setup; never inject after refusal.

For shortcut assignment/restoration, use the [interaction index](#control-locator-and-interaction-index);
changing the binding does not prove physical activation.
Require the full input count, clean up incomplete injection and use fresh observations, not an old log tail.

### 3. Editor and external entry points

Use `PickColorButton` / `OpenSettingsButton`. Start from a different Settings page, then rediscover all Settings
windows. With a separate What's new process, the link can open a new Settings HWND there. Observe its actual
page/foreground; watching only the former HWND falsely reports failure. Preserve all pre-existing windows.

Physically click `OOBENavItem` (Tapped, no InvokePattern), select Color Picker in Welcome's HWND, use `LaunchButton`.
Re-enter after enablement changes: the guard runs on navigation. Re-resolve Settings after lifecycle work.

## UI state-transition map

Read this as a state-to-actions index, not a fixed test sequence. Each row has one
destination; landmarks identify the active surface, not a product PASS. These are
Runner-managed states: `Enabled, hidden` retains the process, whereas `Disabled` does
not. `Any enabled state` means Enabled, hidden, Picker, Editor or Color adjustment.
The adjustment flyout is a child surface of the editor, not another module process.

| Current state | Trigger / condition | Next state | State landmarks |
|---|---|---|---|
| Disabled | Enable through Settings; wait for the resident process | Enabled, hidden | Module process present; picker/editor not visibly open |
| Enabled, hidden | Selected event/chord entry; activation behavior is **Pick a color** (`1`) | Picker | Visible picker overlay with `ColorTextBlock`; do not mistake its tooltip for the editor |
| Enabled, hidden | Selected event/chord entry; activation behavior is **Open editor** (`0`) | Editor | Editor HWND with `PickColorButton`; history can be empty |
| Picker | Sampling input; resolved action is `PickColorThenEditor` (`0`) | Editor | Picker hidden; editor and its history surface available |
| Picker | Sampling input; resolved action is `PickColorAndClose` (`1`) | Enabled, hidden | Picker hidden without opening the editor; resident process retained |
| Picker | Sampling input; resolved action is `Close` (`2`) | Enabled, hidden | Picker hidden; clipboard/history effects are not inferred from disappearance |
| Picker | Escape | Enabled, hidden | Picker surface hidden; resident process retained |
| Editor | `PickColorButton` | Picker | Picker overlay visible; editor hidden |
| Editor | `CurrentColorButton`; a history color is selected | Color adjustment | Owned Details flyout with RGB/HEX edits, HSV sliders and `OKButton` |
| Editor | Native Close, or Escape while editor is active and no adjustment flyout is open | Enabled, hidden | Editor hidden, not destroyed; no visible picker/editor surface |
| Color adjustment | `OKButton` / **Select** | Editor | Flyout gone; editor's history/format controls available |
| Color adjustment | Escape within the flyout or dismiss it without Select | Editor | Same editor landmarks; popup disappearance alone does not distinguish apply from cancel |
| Any enabled state | Disable through Settings | Disabled | Tracked module process exits; previous HWNDs/selectors invalid |

Sampling input means the requested physical mouse button, or Enter (which uses the
primary-button action). Resolve that button's `primaryclickaction`, `middleclickaction`
or `secondaryclickaction`; do not assume every click follows the primary setting.
Preserve these settings: the two activation choices plus separate mouse actions replace
the baseline's three old activation captions.

Use the [interaction index](#control-locator-and-interaction-index) to drive the controls.
Clipboard/history changes, the selected color and applied adjustment values belong to
[read-out notes](#read-out-notes) and checklist assertions, not state-recognition landmarks.
Observe the destination before continuing; an input call succeeding does not establish it.

## Control locator and interaction index

Resolve the actual HWND and page before matching controls. English names are localization
hints; confirm the stated AutomationIds/types in a fresh UIA tree. XAML `x:Uid` names are
resource keys, not selectors. Use the [small harness](../verification-harness.md) for
window/row-scoped resolution and recorded commands; input-moving verbs need the exact
foreground identity. Table verbs are operations, not complete standalone CLI commands.
Test inputs and expected results come from the checklist.

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Enable or disable Color Picker | Settings HWND, Color Picker page | ToggleSwitch `AutomationId=Toggle_ColorPicker` | Use `Set-PtScopedToggle` with the recorded run, window identity, resolved selector and desired Boolean. Read before changing; observe process state separately and restore original enablement. |
| Assign an activation shortcut | Settings, `ColorPickerNavItem` selected; module enabled | Activation Shortcut card's `EditButton`; owned dialog's `PrimaryButton` / `CloseButton` | Invoke Edit, establish recorder/input readiness, then send the requested physical chord. Invoke Save or Cancel as requested; restore the original chord through the same dialog, not Reset. |
| Select activation behavior | Settings, Color Picker; module enabled | ComboBox in the **Activation behavior** card | Expand and select the observed localized **Open editor** or **Pick a color** option using SelectionItemPattern or a targeted physical click; do not use the obsolete three-option model. |
| Configure a mouse button's action | Settings, Color Picker, **Mouse actions** expanded | ComboBox in the requested Primary/Middle/Secondary click card | Expand the target button's ComboBox, then select its requested option. Scope by the button card: the same option captions occur in all three ComboBoxes. |
| Sample an owned swatch | Picker active; owned opaque fixture visible and foreground | Current swatch selector/bounds in the fixture HWND, not the picker tooltip | Use recorded `hover` on the swatch, then a physical `click` for primary-button sampling. InvokePattern on the fixture does not exercise the picker's mouse hook; the configured primary action controls what follows. |
| Select the copied color format | Settings, Color Picker | `ControlType=ComboBox`, `AutomationId=ColorPicker_ComboBox` | Expand and select the requested current format option; use its displayed label, which can include a preview, rather than guessing an index. |
| Show or hide the color name | Settings, Color Picker | ToggleSwitch in **Show color name** card | Read the toggle state and use `Set-PtScopedToggle` only to reach the requested state. This is not the module enable toggle. |
| Enable or disable an editor format | Settings, target named row within **Color formats** | Row's **Enable colorformat** ToggleSwitch; HelpText identifies the format | Resolve within that row and set its desired toggle state. Re-discover after list changes; do not choose the first repeated toggle caption. |
| Reorder an editor format | Settings, target format row | Row's **More options** Button; owned flyout's **Move up** / **Move down** MenuItem | Open that row's menu and invoke the requested enabled move action. Re-resolve the row after each move; dragging is disabled. |
| Edit a format definition | Settings, target format row, then its ContentDialog | Clickable format card; dialog Edit `AutomationId=NewColorFormatTextBox`, Button `AutomationId=PrimaryButton` | Physically click the row body, not its toggle/menu. Set the format text, move focus within the dialog, and invoke the enabled Update button. Closing without the primary action restores the prior definition. |
| Copy a formatted color value | Editor HWND, current color and target format entry | Format label, value Text and Copy Button siblings in the actual ItemsRepeater parent | Resolve that entry's Copy Button and invoke it under the clipboard ownership guard. Do not invoke a copy button found outside the target entry. |
| Select a history color | Editor HWND, `HistoryColors` list | Live ListItem matched to the owned history entry using saved order and visible swatches | Select only the intended item through SelectionItemPattern or an unmodified physical click. Do not assume items have ARGB accessible names. |
| Remove a history color | Editor, intended history item selected exclusively | `HistoryColors` context flyout; `AutomationId=RemoveMenuItem` | Right-click the intended entry, confirm the intended selection and invoke Remove in the owned popup. The command removes the selected set, not necessarily only the right-clicked item. |
| Open color adjustment | Editor HWND with a selected history color | Button `AutomationId=CurrentColorButton` | Invoke the selected-color button, then resolve its owned Details flyout/popup and controls without switching foreground away. |
| Edit RGB or HEX components | Current color's Details flyout | `ControlType=Edit`; `RNumberBox`, `GNumberBox`, `BNumberBox`, `HexCode` AutomationIds | Set requested text values; these RGB controls are TextBoxes, not NumberBox/RangeValue controls. Commit focus within the flyout as needed, then use Select below to apply the edit. |
| Adjust hue, saturation or value | Same Details flyout | Sliders `HueGradientSlider`, `SaturationGradientSlider`, `ValueGradientSlider` | Use the supported RangeValue pattern, or focus the exact slider and use its keyboard interaction. Keep within its observed range; use Select to apply the edit. |
| Apply an adjusted color | Same Details flyout after editing | Button `AutomationId=OKButton`, displayed as **Select** | Invoke Select to normalize inputs and execute the selected-color change command. Merely editing a field or dismissing the flyout does not commit the adjusted color. |
| Change picker magnification | Picker active over the owned swatch, not the editor history strip | Swatch's current selector in the foreground fixture HWND | Send recorded `scroll` with `--wheel <notches>` over the swatch. This is real wheel input; ordinary ScrollPattern on a container does not exercise picker zoom. |
| Open Color Picker Settings | Editor HWND; Settings starts on another page for navigation checks | Button `AutomationId=OpenSettingsButton` | Invoke the button, then rediscover Settings HWNDs and the selected destination page. Do not force the old Settings HWND or pre-navigate it to manufacture success. |
| Use Color Picker through Command Palette | Current CmdPal HWND, actual PowerToys extension; module/companion enablement tracked | Runtime extension commands for Open Color Picker, Saved colors or Settings | Discover the provider's actual command, then execute its supported default action/Enter. Application-search results are not these commands; report a missing provider rather than substituting direct activation. |

### Read-out notes

- For shortcut changes, use `EditButton`, `PrimaryButton`, `CloseButton` as described in
  the interaction index; verify saved fields and old/new/restored activation separately.
- Keep CIELAB expectations independent of the product's reported conversion.
- General enablement is `enabled.ColorPicker` in the root PowerToys settings file. In
  `ColorPicker\settings.json`, read `properties.ActivationShortcut` as the complete binding;
  `properties.activationaction`, `properties.primaryclickaction`,
  `properties.middleclickaction`, `properties.secondaryclickaction` and
  `properties.copiedcolorrepresentation` as scalar fields; and
  `properties.showcolorname.value` as the wrapped Boolean. Format definitions/order are
  in `properties.visiblecolorformats`; history is in `colorHistory.json`. These are
  persistence readouts, not UI selectors or substitutes for control interactions.
- Main surfaces are **Color Picker** / **Color Picker editor**. Tooltip `PopupHost` windows are not extra editors;
  track them separately. Resolve duplicate Close buttons within the actual caption pane.
- WinUI `ColorTextBlock` is the representation; `ColorNameTextBlock` is a separate raw-view node.
  WPF's hidden `ColorHexAutomationPeer` no longer applies. Use actual pixels and clipboard values.
- Values are Text nodes, not WPF Edit/DataItems. If UIA flattens ItemsRepeater rows, find the format label in
  its parent's children and validate the following value Text and Copy Button; do not choose the first copy button.
- History items can have empty names. Match current saved order with visible swatches/count before selecting;
  do not assume an ARGB caption. Re-resolve selectors after reorder/navigation/recreation.
- Act immediately after popup discovery; switching windows dismisses history menus. Use `Save-PtWindowCapture`
  with editor and popup identities; inspect the image. Invalidated captures cannot PASS.
- Zoom pixels and restored capture visibility need separate observations; display affinity is only supporting data.
- Review UI `ColorPicker\Logs\<version>\` and native `ColorPicker\ModuleInterface\Logs\v<version>\` from the run's
  start boundary. UIA completion and persistence can settle separately: poll expected saved state within a bound.
- Observe clipboard text with a bounded wait after the recorded copy, then acknowledge the
  identified writer using the [clipboard contract](../verification-harness.md#4-clipboard-ownership-and-restoration).
  A sequence change can precede text materialization. Preserve timeout/ownership evidence;
  do not repeat the copy or replace the guard baseline merely to obtain a matching value.
- For a DIP-based layout check, read the current target DPI, convert the requested size with
  `pixels = dips * dpi / 96`, and verify the relevant actual window/client dimensions. This
  size conversion is not a rule for rescaling already-physical input/capture coordinates.
- Ordinary sampling does not cover the refresh-rate `0/1` fallback. Identify the module's
  primary-display refresh input; an inactive WMI adapter reporting `1` is not that fixture.
- For declared semantic JSON comparisons, ignore root-property serialization order but preserve
  behavioral format/history order. This does not waive a byte-level guard conflict; restoration
  still uses the original bytes and known test-written state.

## Troubleshooting

Preserve the original action and observations. Recovery must be authorized, preserve the
assertion's entry path and have a restoration plan; diagnostic recovery cannot erase an
earlier failure. These rows are diagnostic branches, not automatic verdicts. Apply the
[shared taxonomy](../../SKILL.md#step-3--classification-taxonomy) and the
[harness assertion contract](../verification-harness.md#6-independent-assertions-and-archive):
NOT-OBSERVED means an assertion lacks observation, not automatically a BLOCKED verdict.

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| Sampling or a fallback click targets the wrong pixel | Confirm the owned swatch, live bounds, current DPI and [window/coordinate contract](../verification-harness.md#2-exact-window-and-row-scope). Prefer the recorded selector-based hover/click path; consult current CLI help. | A misrouted input is not a color-conversion failure. Historical DPI values or an extra scale correction do not establish current coordinates. |
| A narrow-layout check uses the wrong size | Apply the DIP sizing/readback rule in [Read-out notes](#read-out-notes) using the current window's DPI and the dimension specified by the case. | Requested outer pixels do not by themselves prove the intended client/layout width. Do not reuse an earlier session's DPI. |
| A visible row/control does not respond to Invoke | Inspect its supported pattern and current state. Use the physical-click paths in the [interaction index](#control-locator-and-interaction-index) for format rows and the documented Welcome/CmdPal entry; guard the exact foreground. | Button/ListItem type does not imply InvokePattern. A second expand action is not necessarily collapse, and a driver no-op is not a product action. |
| Recorder is empty, a modifier is missing, or Shell owns focus | Wait for dialog controls and input readiness, verify every saved modifier, and follow [physical entry](#entry-paths). Recover only an identified test-opened Search flyout before more input. | A partial/undelivered chord is not proof of a broken binding. Keep the incomplete attempt; never dismiss unowned UI or substitute a named event for the binding assertion. |
| CmdPal commands are missing or provider initialization reports an error | Inspect provider configuration, effective module enablement/policy, actual query results and fresh logs. Attribute errors such as `E_NOINTERFACE` to their actual component. See the command conditions below; app search is not this provider. | Required availability can fail once premises and observation are established; missing prerequisites/driver errors require their own cause. An HRESULT alone does not locate the defect, and downstream unexecuted actions remain NOT-OBSERVED. |
| Named-event helper lookup fails in a driver phase | Apply [per-phase helper initialization](../verification-harness.md#shared-helper-initialization) and check the requested friendly-name mapping before signaling. | A script-scope/import failure is not evidence that Color Picker is unavailable. Establish driver readiness without automatically restarting the product. |
| Clipboard sequence changes but text is still empty/unavailable | Observe the same recorded copy with the bounded read-out and [clipboard ownership contract](../verification-harness.md#4-clipboard-ownership-and-restoration); retain actual data/owner/timing. | Sequence change is not materialized or correct text. Empty data is neither copy success nor permission to bypass the guard or repeat the action blindly. |
| Saved JSON differs after serialization | Compare at the predeclared semantic/byte level using [Read-out notes](#read-out-notes) and [restoration rules](#fixtures-and-restoration). Identify the writer and preserve original guard bytes. | Root-property reordering alone is not a semantic regression; behavioral array/format order still matters. Semantic equality does not cancel a byte-guard conflict. |
| CmdPal reappears or its flag changes during cleanup | Follow the companion ordering in [Restoration order](#restoration-order), observe both flags and stable writer shutdown, and keep the conflict evidence. | A transient zero-process count is not quiescence. Attribute the lifecycle/write failure separately from the command or color assertion; do not automatically recycle AppX. |

Once the PowerToys provider is loaded, `ColorPickerModuleCommandProvider.BuildCommands`
supplies Settings regardless of module enablement; effective enablement gates Open Color
Picker and Saved colors. Check current policy/settings and supported build before deciding
whether an absent command is expected, failed availability or an observation/prerequisite
obstacle. Do not invent a downstream pin/history defect from a command that was never reached.

## Fixtures and restoration

Prepare only resources required by the selected assertions. Before entry or writes, record
original existence/values, ownership and **case-owned** or shared **run-owned** lifetime.
Keep the original baseline across retries. Declare semantic or byte-exact file verification
before mutation; clipboard and user-window data stay local.

### Resource inventory

| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| Opaque swatch window | Sampling, copy and magnifier cases | Owned fixture with declared colors, live bounds/DPI and exact PID/start/path/HWND | Close only the owned fixture after any foreground/clipboard dependencies are finished | Owned window/process gone; user windows retained |
| Color Picker settings and history | Shortcut, behavior, formats, selection or history writes | Original `settings.json`, `colorHistory.json`, chord and format/history order; known test-written file state | Use the existing-file guards below after writers stop; do not register these user files as disposable fixtures | Original existence/contents at the declared comparison level; order preserved where behavioral |
| Clipboard and guard owner | Any action that can copy | Original supported formats plus sequence/owner tracking in one live STA guard; acknowledge each known product write | Restore the clipboard while its data providers and guard owner remain alive, then dispose the guard | Guard restoration verified; empty text or a successful click is not proof |
| Color Picker enablement and touched Settings UI | Activation, settings or lifecycle checks | Original enabled state, Settings page/window identity/placement, foreground and pointer | Use explicit UI state changes and the supplied lifecycle callbacks; retain pre-existing Settings/What's new windows | Original enabled state and touched UI state observed after the final lifecycle operation |
| CmdPal companion state | Only selected integration checks | Original companion enablement, touched configuration files and window identities; separate from Color Picker ownership | Restore the declared companion resources with their own writer/lifecycle accounting; no automatic AppX recycle | Both original enable flags and relevant configuration/UI state verified; no unintended revival |

### Helper boundaries

Use the [harness contracts](../verification-harness.md). `New-PtFileGuard` and
`Restore-PtFileGuard` cover **existing regular files only**. Restore requires an explicitly
known expected-current hash, checks it under an exclusive handle, and refuses unknown
changes; do not adopt an arbitrary latest hash to bypass a conflict.

Record absent paths in the resource inventory before any action that could create them.
The current harness has no owned-absence rollback for a previously missing settings/history
file. Until such a method is available, do not execute the affected write-producing variant;
record the restoration-capability limitation and continue independent eligible work.
Do not pre-create a missing file merely to satisfy the guard, or pass a fabricated guard for
it: that would lose the original absence baseline. This is not a product failure.

`Invoke-PtRestoredState` coordinates the supplied `ReadEnabled`, `SetEnabled`, `Quiesce`,
`Restore` and `Verify` callbacks around `Action`; it does not automatically restore CmdPal,
files, window placement or clipboard. `Set-PtScopedToggle` changes the explicitly selected
toggle only. Attribute each affected writer and companion to its own restoration plan.
Clipboard backup is in memory: a crashed guard process is not a persisted recovery receipt.
The wrapper attempts `SetEnabled(false)` even after an `Action` error. The supplied callback
must refuse shutdown if a failed clipboard restoration still requires a live data provider;
the wrapper does not supply that clipboard-safety gate automatically.

### Restoration order

1. Inside `Action`'s `finally`, restore the clipboard before writer shutdown and before
   destroying the STA guard owner; dispose the guard after successful restoration. On failure,
   retain any still-needed guard/owner/provider for explicit recovery and gate destructive
   cleanup as above. Do not treat an unexpected sequence/owner change as an authorized copy.
2. End owned picker/editor activity and restore UI-only properties, such as the captured
   shortcut, while the required controls are available. `Invoke-PtRestoredState` then
   disables its controlled module and calls `Quiesce`; wait for actual writer shutdown.
   If both modules were changed and both writers must stop, disable/quiesce Color Picker
   before the CmdPal companion; recheck both saved enable flags and stable process quiescence
   after the last change. A momentary zero-process observation is insufficient for rollback.
3. In `Restore`, roll back the guarded files over their known post-state. Preserve history
   and format order and all original guard bytes across failed phases. Do not overwrite a
   conflict or close an unowned window to manufacture quiescence.
4. Only after successful rollback, return to the original enabled states and run `Verify`.
   Account for startup writes before the final file/UI comparison. Restore user page,
   placement, foreground and pointer, then release owned fixtures when their dependencies
   are finished. Case-owned resources end with the case; declared shared fixtures end with
   the run, with case mutations reset between uses.

### Restoration verification

- Confirm the original clipboard through the guard, original file existence/required
  contents, complete shortcut fields and behavioral history/format order.
- Confirm Color Picker and any touched CmdPal companion return to their original enablement
  and lifecycle state after the last enable/disable/startup operation.
- Confirm owned swatches/new windows are gone and pre-existing Settings/What's new windows,
  page/placement and foreground/pointer are preserved or restored as recorded.
- Record action and cleanup failures separately; conflicts or incomplete restoration cannot
  produce a successful cleanup receipt. Dependent assertions remain NOT-OBSERVED.

### Execution notes

These are planning suggestions when the relevant checks are selected, not a mandatory
whole-module test order. Respect the checklist and each operation's prerequisites.

- Prefer binding/layout checks before sharing fixtures across activation, copy, visuals,
  formats and history. Reuse owned setup, not observations or outcomes.
- Leave Settings-link and Welcome/CmdPal lifecycle checks late when practical, because
  navigation and lifecycle changes can invalidate earlier window identities. Re-resolve
  windows afterward, review run logs and perform the restoration above.
- For localization coverage, record Windows display language and the PowerToys language
  override separately. One does not establish the other prerequisite; any authorized language
  change needs its own captured baseline and restoration plan.

## Source citations

For this WinUI run, use tag `v0.101.2572.0`:

- `src\settings-ui\Settings.UI.Library\Enumerations\ColorPickerActivationAction.cs` and
  `ColorPickerClickAction.cs` - enum values.
- `src\modules\colorPicker\ColorPickerUI\Helpers\AppStateHandler.cs` - `StartUserSession`,
  `EndUserSession`, `OpenColorEditor`, `ColorEditorViewModel_OpenColorPickerRequested`,
  `HandleEnterPressed` and `HandleEscPressed`.
- `src\modules\colorPicker\ColorPickerUI\ColorPickerXAML\ColorEditorWindow.xaml.cs`
  `AppWindow_Closing` - editor Close hides the session instead of destroying the window.
- `src\modules\colorPicker\ColorPickerUI\Settings\UserSettings.cs` - `ColorHistory_CollectionChanged`, loading.
- `src\modules\colorPicker\ColorPickerUI\Views\ColorEditorView.xaml`, `ColorPickerView.xaml` - WinUI mapping.
- `src\modules\colorPicker\ColorPickerUI\Views\ColorEditorView.xaml.cs`
  `HistoryContextFlyout_Opening` - menu commands snapshot the selected history set.
- `src\modules\colorPicker\ColorPickerUI\Controls\ColorPickerControl.xaml` and `.xaml.cs`
  `RGBNumberBox_TextChanged`, `HexCode_TextChanged`, slider ValueChanged handlers and
  `OKButton_Click` - draft adjustment and explicit Select commit.
- `src\modules\colorPicker\ColorPickerUI\ViewModels\MainViewModel.cs`
  `HandleMouseClickAction`, `MouseInfoProvider_OnMouseWheel` and
  `ViewModels\ColorEditorViewModel.cs` `CopyColorText` - sampling, wheel input and copying.
- `src\modules\colorPicker\ColorPickerUI\Helpers\ZoomWindowHelper.cs` and `Mouse\MouseInfoProvider.cs` -
  capture restoration and refresh fallback.
- `src\settings-ui\Settings.UI\SettingsXAML\Views\ColorPickerPage.xaml` and
  `SettingsXAML\OOBE\Views\OobeColorPicker.xaml.cs` - controls and navigation-time launch guard.
- `src\settings-ui\Settings.UI\SettingsXAML\Views\ColorPickerPage.xaml.cs`
  `EditButton_Click`, `ReorderButtonUp_Click`, `ReorderButtonDown_Click`,
  `ColorFormatDialog_Closed`, and `SettingsXAML\Controls\ColorFormatEditor.xaml`
  - format editing, reordering and dialog commit/cancel.
- `src\settings-ui\Settings.UI.Library\ColorPickerProperties.cs` - persisted field shapes.
- `src\settings-ui\Settings.UI\SettingsXAML\Controls\ShortcutControl\ShortcutControl.xaml.cs`
  `OpenDialogButton_Click` and `ShortcutDialog_PrimaryButtonClick` - physical shortcut capture and Save.
- `scripts\pt-verification-ui.ps1` `Resolve-PtUiControl`, `Set-PtScopedToggle`,
  `Invoke-PtWindowCommand` - scoped mechanical operations, not product verdicts.
- `src\modules\cmdpal\ext\Microsoft.CmdPal.Ext.PowerToys\Modules\ColorPickerModuleCommandProvider.cs` -
  command inventory and IDs.
- `src\modules\cmdpal\ext\Microsoft.CmdPal.Ext.PowerToys\Helpers\ModuleEnablementService.cs`
  `IsKeyEnabled` - effective policy/settings enablement.
