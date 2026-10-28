# Keyboard Manager - module verification profile

## Module facts

| Fact | Value |
|---|---|
| Module | `Keyboard Manager`; source: `src\modules\keyboardmanager`. |
| Processes | Resident `KeyboardManagerEngine\PowerToys.KeyboardManagerEngine.exe`; on-demand `WinUI3Apps\PowerToys.KeyboardManagerEditorUI.exe`. Resolve paths from the installed Runner. |
| UI | New editor: WinUI 3, class `WinUIDesktopWin32WindowClass`, unified list/dialog. Classic editor: separate Remap keys and Remap shortcuts windows. |
| State root | `%LOCALAPPDATA%\Microsoft\PowerToys\Keyboard Manager`; module `settings.json`, active profile JSON, `editorSettings.json`, `editorTransaction.lock`. Startup can reconcile stores. |
| Activation | Settings entry, current `properties.EditorShortcut`, or shared `NewKeyboardManager.Open` event. Current builds have no separate service-toggle shortcut. |
| Applicability | Editor mode selects different controls/commit semantics. Type/hold-Enter/hold-Esc are classic-specific. Empty-field dropdowns and recording focus exit require a supporting build. |

Use the [checklist](../release-checklist/keyboard-manager.md) for expectations and its
[inventory](../assertion-inventories/keyboard-manager.json) for independent conditions.
Rediscover HWNDs, PIDs, row UUIDs and runtime selectors after recreation.

## Entry paths

Capture files and borrowed Settings state before entry: editor startup is not read-only.
Establish ownership and input readiness using [Fixtures and restoration](#fixtures-and-restoration).

| Intent | Entry / destination |
|---|---|
| Settings | Snapshot existing main HWND before navigation. Select `KeyboardManagerNavItem`, then new-mode `KeyboardManagerLaunchEditorButton` -> **List**. Read current mode first. |
| Physical binding | Read `properties.EditorShortcut`; inject its keys against a compatible owned foreground fixture -> **List**. Do not substitute an event. |
| Downstream activation | `Invoke-PtSharedEvent -Name 'NewKeyboardManager.Open'`; independently observe the correct editor -> **List**. This does not cover Settings/Dashboard/CmdPal navigation. |
| Classic | Settings classic mode exposes Remap keys and Remap shortcuts -> **Classic draft**. Restore original mode; switching is not recovery for a new-editor failure. |
| Dashboard / CmdPal / Dock | Exercise the requested listing, command or owned pin. Declare indirectly activated extension processes and restore companions/pins under their shared contracts. |

## UI state-transition map

The engine is independent of the editor. **Closed** means editor absence, not module disablement.
Observe structural arrival; a successful Invoke is not evidence that the next surface is ready.

| Current state | Trigger / condition | Next state | State landmarks |
|---|---|---|---|
| Closed | Eligible new-editor entry | List | New editor HWND; `NewRemappingBtn`, search/filter controls |
| List | New | Mapping draft | Trigger/action fields and dialog PrimaryButton |
| List | Invoke owned row outside Select mode | Mapping draft | Existing trigger/action fields in edit dialog |
| Mapping draft | Open a field's key dropdown | Key picker | Current popup with KeyListView and search |
| Key picker | Invoke a realized key option | Mapping draft | Picker dismissed; field controls visible |
| Mapping draft | Start recording a field | Recording | Corresponding recording toggle checked |
| Recording | Stop or supported Tab/Shift+Tab exit | Mapping draft | Toggle unchecked; dialog focus observable |
| Mapping draft | Save accepted | List | Draft dialog gone; list surface available |
| Mapping draft | Save rejected | Mapping draft | Dialog remains; validation or disabled Save |
| Mapping draft | Cancel | List | Draft dialog gone; list surface available |
| List | Owned row menu Delete | Delete confirmation | Confirmation Primary/Close buttons |
| Delete confirmation | Confirm | List | Confirmation gone; list surface available |
| Delete confirmation | Cancel | List | Confirmation gone; list surface available |
| List | Normal owned close | Closed | Owned editor HWND/process exit |
| Classic draft | OK with invalid rows | Classic warning | Classic invalid-mapping dialog |
| Classic warning | Return to editing | Classic draft | Classic rows and Type/dropdown controls |
| Classic draft | Accept valid changes | Closed | Classic editor closes; persistence read separately |

## Control locator and interaction index

Use [typed scoped resolution](../helper-workflow.md#scoped-control-selection) and current supported
patterns. XAML resource keys are not AutomationIds. Captions follow the target window's locale;
source-informed conditional routes require live provider discovery before use.

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Open editor | Settings module page, new mode, enabled | `AutomationId=KeyboardManagerLaunchEditorButton`, `Button` | Invoke; independently resolve resulting process/window. |
| Add mapping | List | `AutomationId=NewRemappingBtn`, `Button` | Invoke once; wait for fields and dialog controls. |
| Choose action | Mapping draft | `AutomationId=ActionTypeComboBox`, `ComboBox` | `Select-PtComboBoxItem` with actual localized item name; observe dependent controls. |
| Pick trigger | Mapping draft, trigger field | `KeyButton`, `Button`, within `TriggerKeyToggleBtn` | Invoke unique dropdown. Multiple shortcut slots require identifying the requested slot. |
| Pick target | Mapping draft, key/shortcut action | `KeyButton`, `Button`, within `ActionKeyToggleBtn` | Invoke unique dropdown; do not select a window-global repeated ID. |
| Select key | Current picker for known field/slot | `KeyListView` descendant `ListItem`, exact displayed key name | Wait for option realization; supported ScrollItem then Invoke on that identity. Do not reopen an already-open picker. |
| Search keys | Key picker | `KeySearchBox` group -> current `Edit` descendant | Discover inner ID, SetValue, observe filtered list; keyboard selection needs actual guarded keys and readback. |
| Record field | Mapping draft, one field | `TriggerKeyToggleBtn` or `ActionKeyToggleBtn`, exposed as `Button` | Discover Toggle/Invoke pattern; enter recording, deliver physical keys, stop and observe unchecked state. This is not the Settings shortcut-recorder dialog. |
| Save | Mapping draft | Dialog `PrimaryButton`, enabled `Button` | Invoke once; observe close versus validation; independently read both stores. |
| Cancel | Mapping draft | Current dialog-scoped localized cancel/close `Button` | Resolve from current tree and Invoke; process closure does not simulate Cancel. |
| Edit row | List, not Select mode | `RemappingsListView` -> unique owned `ListItem` | Identify by owned trigger/target and store identity, then Invoke. Accessible Name may be only a model type. |
| Toggle row | Unique owned mapping row | Descendant `MappingEnabledToggle`, `Button` with TogglePattern | Read current state; Toggle only when needed. Compare editor IsActive and engine entry separately. |
| Delete row | Unique owned mapping row | Descendant `MappingMenuButton`, `Button`; current localized Delete `MenuItem` | Invoke menu, then Delete, then confirmation PrimaryButton. Cancel is independent. |
| Filter / select | List | `SearchBox` group, `FilterButton`, `SelectionModeButton` | Discover scoped edit/popup descendants; SetValue or Invoke. Re-resolve rows after filtering. |
| Drive text target | Owned focused input, compatible integrity | Owned Notepad `Document`, or shared fixture `FixtureInput` `Edit` | Prove ordinary physical-key delivery before remapping; inject source VK using shared input, never direct text/value writes. |
| Close / reopen | Owned main HWND and registered sibling windows | Exact PID/start/path creation identity | Normal tracked close, observed exit, then case-declared entry again. Rediscovery does not confer ownership of borrowed windows. |

### Read-out notes

- General enablement is `enabled["Keyboard Manager"]`. Module `properties.useNewEditor`
  is a raw Boolean, not `.value`; `EditorShortcut` is a hotkey object.
  `activeConfiguration.value` names the profile; reject traversal/separators/non-leaf filenames.
- Engine arrays: `remapKeys.inProcess`, `remapKeysToText.inProcess`,
  `remapShortcuts.global/appSpecific`, `remapShortcutsToText.global/appSpecific`.
  Key identifiers are serialized VK strings.
- Editor UUID-keyed `ShortcutSettingsDictionary` entries contain `Shortcut`, `Profiles`, `IsActive`.
  `ProfileDictionary`, `ShortcutsByOperationType` and `ActiveProfile` are companion state.
  Disabled editor rows can legitimately be absent from active engine mappings.
- Use `Read-PtSharedFileText` with explicit parse/schema errors, never empty fallback values.
  Draft, editor persistence, engine persistence and actual output are distinct observations.
  Export only owned synthetic rows, not original private text/paths.
- Read actual TextPattern/ValuePattern content, not accessible labels. Input return counts
  and matching stored VKs do not establish delivery.

### Observation rules

At high DPI the editor can extend beyond the work area: measure physical geometry and make
the owned window visible before capture. Clipped images can support a visible row, not full
layout. Capture only synthetic content; exclude private Notepad tab titles without cropping
away the property under test. Images remain candidates until separately accepted.

## Troubleshooting

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| New route absent | Check raw mode, module enablement and current Settings page; distinguish classic controls. | Different configuration is not missing installed functionality. |
| Saved row but no runtime effect | Observe validation/native-service availability, both stores and actual input. | UI/editor persistence alone does not establish remapping. |
| Option missing immediately after opening | Observe existing picker until its requested option is realized; scope field/slot. | No action replay or product verdict from a lookup race. |
| Neither mapped nor ordinary key yields text | Check exact focus, tokens, key events, layout/composition without changing user input state; diagnose in an owned observer. | Require ordinary delivery before remap judgments; do not assume an IME/RDP cause. |
| Directory snapshot hits live log | Use guarded existing-file preservation for declared existing stores; retain error. Absence still needs suitable bounded rollback. | Log capture failure does not authorize access bypass or log deletion. |
| Fixture cleanup targets closed editor | Remove the fixture while its captured foreground owner lives, or create fixture before editor activation. | Original-run desktop restoration does not erase the failed fixture receipt. |
| Captions differ from Settings | Discover target-local captions; prefer proven AutomationIds. | English Settings does not imply English editor UI. |
| Unexpected file delta | Retain original and last attributable post-state; stop dependent writes. | Do not refresh ExpectedState to bless external changes or overwrite defaults. |

## Fixtures and restoration

### Resource inventory

| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| Settings snapshot | Before Settings navigation | Run baseline; HWND borrowed | Template Settings adapter | Original identity/page/expansion/scroll/placement/visibility |
| `Get-PtFileSnapshot` stores | Before editor startup/mapping changes | Private original bytes/existence; exact case-owned rows | UI undo/delete, quiescent guarded rollback | Both stores and original settings byte/existence comparisons; runtime undo separately |
| Owned editor activation | Launch/reopen | Declare exact executable before `Invoke-PtOwnedProcessActivation`; register new PID/start/path and sibling HWNDs | `Stop-PtOwnedProcess` with normal tracked close | Owned processes/windows absent; existing editor untouched |
| `New-PtNotepadFixture` or `Show-PtDesktopFixture.ps1` | Keyboard output | Synthetic owned document or dedicated key observer; preserve borrowed Notepad tabs | Paired Notepad removal with owned-edit discard, or normal tracked process exit | Original tabs/selection/placement; owned resources absent; keys released |
| Clipboard session | Paste matrix | Supported private baseline and owned synthetic writes | Restore before owner/writer release | Original supported data restored without disclosure |
| App/browser/Shell fixture | Conditional actions | Exact owned tab/window/process and starting state | Scoped normal close and original-state restoration | No owned survivors; unrelated resources unchanged |

### Helper boundaries

Reuse [session safety](../session-safety.md), template and recorder. Explicitly set `DependsOn=@()`
for independent steps; resume with the original persisted resource plan. These helpers do not
preserve arbitrary IME composition.

Guarded file rollback requires existing original/expected files. For absence, directory rollback
needs a small quiescent root with exact ownership; the whole module root contains live logs.
Preserve transaction-lock existence and attributable `editorSettings.<token>.tmp` sidecars.
A snapshot grants no ownership. Do not overwrite unrelated settings or restart Runner as cleanup.

### Restoration order

1. Release owned input, cancel owned drafts, delete owned mappings through UI; observe ordinary
   source-key behavior before claiming runtime restoration.
2. Remove an owned Notepad fixture before its captured foreground owner exits. Put this in
   Ui phase before editor Quiesce, or create the fixture before editor activation.
3. Capture final attributable store post-states, close owned editor writers normally, then
   guarded-restore declared files to the immutable original bytes/existence.
4. Restore explicitly changed enablement/mode through UI and account for startup writes.
   The bounded mapping flow does not require Runner restart.
5. Close remaining owned fixtures; restore borrowed Settings and physical desktop.

### Restoration verification

Freshly compare general/module settings, active profile, editor store and lock after the final
writer/activation. Unrelated log growth is outside mapping-state equality. Check owned-resource
absence and borrowed Settings/Notepad baseline state. Disk equality cannot replace runtime
ordinary-input restoration. Retain conflicts, partial receipts and private recovery until resolved.

## References

- [Recorder and immutable evidence](../recording-workflow.md)
- [Ownership, Settings and cleanup](../session-safety.md)
- [Shared input, UIA and file mechanics](../helper-workflow.md)
- [Owned Notepad fixtures](../owned-fixtures.md)
- [Module lifecycle](../module-lifecycle.md)
