# Keyboard Manager - module verification profile

## Module facts

| Fact | Value |
|---|---|
| Module | `Keyboard Manager`; source: `src\modules\keyboardmanager`. |
| Processes | Resident `KeyboardManagerEngine\PowerToys.KeyboardManagerEngine.exe`; on-demand `WinUI3Apps\PowerToys.KeyboardManagerEditorUI.exe`. Resolve paths from the installed Runner. |
| UI | New editor: WinUI 3, class `WinUIDesktopWin32WindowClass`, unified list/dialog. Classic editor: separate Remap keys and Remap shortcuts windows. |
| State root | `%LOCALAPPDATA%\Microsoft\PowerToys\Keyboard Manager`; module `settings.json`, active profile JSON, `editorSettings.json`, `editorTransaction.lock`. Startup can reconcile stores. |
| Applicability | Type/hold-Enter/hold-Esc are classic-specific. Empty-field dropdowns and recording focus exit need a supporting build; current builds have no service-toggle shortcut. |

Use the [checklist](../release-checklist/keyboard-manager.md) for expectations and its
[inventory](../assertion-inventories/keyboard-manager.json) for independent conditions.
Rediscover HWNDs, PIDs, row UUIDs and runtime selectors after recreation.

## Entry paths

Capture files and borrowed Settings state before entry: editor startup is not read-only.
Establish ownership and input readiness using [Fixtures and restoration](#fixtures-and-restoration).

| Intent | Entry / destination |
|---|---|
| Settings | Snapshot main HWND; select `KeyboardManagerNavItem`, then new-mode `KeyboardManagerLaunchEditorButton` -> **List**. |
| Physical binding | Read `properties.EditorShortcut`; inject against a compatible owned foreground fixture -> **List**. No event substitution. |
| Downstream activation | `Invoke-PtSharedEvent -Name 'NewKeyboardManager.Open'` -> observe **List**. Not proof of a binding/navigation route. |
| Classic | Settings' Remap keys/Remap shortcuts -> **Classic draft**. Restore mode; switching cannot rescue a new-editor verdict. |
| Dashboard / CmdPal / Dock | Exercise actual listing/command/pin. Track extension processes and restore owned pins/companions. |

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

Use [typed scoped resolution](../helper-workflow.md#scoped-control-selection). Confirm patterns and
target-local captions; resource keys are not AutomationIds. Conditional routes need live discovery.

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Open editor | Settings module page, new mode, enabled | `AutomationId=KeyboardManagerLaunchEditorButton`, `Button` | Invoke; independently resolve resulting process/window. |
| Add mapping | List | `AutomationId=NewRemappingBtn`, `Button` | Invoke once; wait for fields and dialog controls. |
| Choose action | Mapping draft | `ActionTypeComboBox`, `ComboBox` | `Select-PtComboBoxItem` with actual localized option; observe dependent fields. |
| Pick trigger | Mapping draft, trigger field | `KeyButton`, `Button`, within `TriggerKeyToggleBtn` | Invoke unique dropdown. Multiple shortcut slots require identifying the requested slot. |
| Pick target | Mapping draft, key/shortcut action | `KeyButton`, `Button`, within `ActionKeyToggleBtn` | Invoke unique dropdown; do not select a window-global repeated ID. |
| Select key | Picker for known field/slot | `KeyListView` -> `ListItem`, exact key name | Wait for realization; supported ScrollItem then Invoke. Do not reopen the picker. |
| Search keys | Key picker | `KeySearchBox` -> current `Edit` | Discover inner ID, SetValue, observe filtering; keyboard selection needs guarded keys/readback. |
| Record field | Mapping draft, one field | `TriggerKeyToggleBtn` / `ActionKeyToggleBtn`, `Button` | Discover Toggle/Invoke; record physical keys, stop, observe unchecked state. Not the Settings shortcut recorder. |
| Save | Mapping draft | Dialog `PrimaryButton`, enabled `Button` | Invoke once; observe close versus validation; independently read both stores. |
| Cancel | Mapping draft | Current dialog-scoped localized cancel/close `Button` | Resolve from current tree and Invoke; process closure does not simulate Cancel. |
| Edit row | List, not Select mode | `RemappingsListView` -> owned `ListItem` | Identify by trigger/target and store identity, then Invoke; Name may be a model type. |
| Toggle row | Unique owned mapping row | Descendant `MappingEnabledToggle`, `Button` with TogglePattern | Read current state; Toggle only when needed. Compare editor IsActive and engine entry separately. |
| Delete row | Unique owned mapping row | Descendant `MappingMenuButton`, `Button`; current localized Delete `MenuItem` | Invoke menu, then Delete, then confirmation PrimaryButton. Cancel is independent. |
| Filter / select | List | `SearchBox` group, `FilterButton`, `SelectionModeButton` | Discover scoped edit/popup descendants; SetValue or Invoke. Re-resolve rows after filtering. |
| Drive text target | Owned focus, compatible integrity | Keyboard fixture `FixtureInput`, `Edit` | [Observer recipe](../owned-fixtures.md#keyboard-input-observer): explicit installed layout, ordinary-key control first, then shared source-VK input. |
| Close / reopen | Owned main and registered siblings | Exact PID/start/path creation identity | Normal tracked close, observed exit, then declared entry. Never adopt borrowed windows. |

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
- Use `Read-PtSharedFileText`; preserve parse/schema failures. Export only owned synthetic rows.
  Draft, both saved stores and actual TextPattern/ValuePattern output are separate evidence.
  Labels, input return counts and stored VKs do not prove delivery.

### Observation rules

Fit owned windows to measured physical work-area geometry before capture. Clipped images
cannot establish full-layout correctness. Exclude private tabs/mappings without hiding the
property tested; images remain candidates until accepted.

## Troubleshooting

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| New route absent | Check raw mode, module enablement and current Settings page; distinguish classic controls. | Different configuration is not missing installed functionality. |
| Saved row but no runtime effect | Observe validation/native-service availability, both stores and actual input. | UI/editor persistence alone does not establish remapping. |
| Option missing immediately after opening | Observe existing picker until its requested option is realized; scope field/slot. | No action replay or product verdict from a lookup race. |
| Neither mapped nor ordinary key yields text | Compare focused text/key events; PROCESSKEY is not the expected ordinary key. Use the owned observer's explicit installed layout. | Do not alter user IME state or claim IME/AltGr coverage. Establish ordinary delivery first. |
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
| [Keyboard input observer](../owned-fixtures.md#keyboard-input-observer) | Ordinary key output | Run-owned process/two windows/state directory; original thread and foreground-app layouts | Normal tracked main close; compare layout-restoration receipt; restore desktop | Balanced released keys, owned process/windows absent, original foreground layout unchanged |
| `New-PtNotepadFixture` | App-specific/document cases | Owned document; borrowed tabs and captured foreground lifetime | Paired removal with explicit owned-edit discard before foreground owner exits | Original tabs/selection/placement; owned tab/file absent |
| Clipboard session | Paste matrix | Supported private baseline and owned synthetic writes | Restore before owner/writer release | Original supported data restored without disclosure |
| App/browser/Shell fixture | Conditional actions | Exact owned tab/window/process and starting state | Scoped normal close and original-state restoration | No owned survivors; unrelated resources unchanged |

### Helper boundaries

Use [session safety](../session-safety.md) and the shared recorder/template; independent cleanup
steps have `DependsOn=@()`. Resume with the original persisted plan. IME composition is not preserved.

File guards require existing originals/expected files. Absence needs bounded quiescent directory
rollback; the module root includes live logs. Preserve lock existence and attributable
`editorSettings.<token>.tmp` sidecars. Snapshots grant no ownership; no blanket overwrite/restart.

### Restoration order

1. Establish the keyboard observer before editor activation and prove ordinary-key delivery.
   At cleanup, release input, cancel drafts, delete owned mappings through UI and observe
   ordinary source-key behavior before claiming runtime restoration.
2. Remove an owned Notepad fixture before its captured foreground owner exits. Put this in
   Ui phase before editor Quiesce, or create the fixture before editor activation.
3. Capture final attributable store post-states, close owned editor writers normally, then
   guarded-restore declared files to the immutable original bytes/existence.
4. Restore explicitly changed enablement/mode through UI and account for startup writes.
   The bounded mapping flow does not require Runner restart.
5. Close the keyboard observer normally and compare its layout-restoration receipt, then restore
   borrowed Settings/desktop and independently compare the original foreground application's layout.

### Restoration verification

After final writes, compare general/module settings, profile/editor/lock bytes and existence,
owned-resource absence, borrowed UI and input-layout baselines. Log growth is outside mapping-state
equality. Disk equality cannot replace runtime undo. Retain conflicts and private recovery.

## References

- [Recorder and immutable evidence](../recording-workflow.md)
- [Ownership, Settings and cleanup](../session-safety.md)
- [Input, UIA, files and lifecycle](../helper-workflow.md)
