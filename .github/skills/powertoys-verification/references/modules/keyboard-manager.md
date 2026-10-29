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
| Enter replacement text | Mapping draft, Text action | `TextContentBox`, `Edit` | SetValue and read the complete value; preserve logical line breaks. Save/reopen and physical activation are separate observations. |
| Configure a program | Mapping draft, Run program action | `ProgramPathInput`, `ProgramArgsInput`, `StartInPathInput`, each `Edit` | SetValue separately, move focus before Save, then compare saved path/arguments/directory and the owned process's actual startup receipt. Blank Start in is intentional. |
| Browse program / directory | Program draft | `ProgramPathSelectButton` / `StartInSelectButton`, `Button` | Invoke one picker; resolve its owned HWND and current file/folder selection controls. Select only an owned fixture or cancel, then read the originating field. Elevation is a separate prerequisite. |
| Select launch context | Program draft | `ElevationComboBox`, `VisibilityComboBox`, `IfRunningComboBox`, each `ComboBox` | Enumerate target-local options and use `Select-PtComboBoxItem`; verify the actual selected option. Do not choose End task or affect an existing user process. |
| Enter URL | Mapping draft, Open URL action | `UrlPathInput`, `Edit` | SetValue, move focus, read back; distinguish accepted Save from validation. Activation needs an owned handler tab and exact URL observer, not merely Shell dispatch. |
| Select a condition | Single-key trigger, key/shortcut action | `ConditionComboBox`, `ComboBox` | Select the localized Always/Alone option with readback. After changing action category, rediscover visibility/enabled state; an offscreen retained node is not a usable condition control. |
| Restrict target application | Shortcut-trigger draft | `AppSpecificCheckBox`, `CheckBox`; `AppNameTextBox`, `Edit` | Toggle On only if Off; SetValue to the actual process basename without `.exe`. Confirm targetApp in the saved app-specific entry before the checklist's full per-application matrix. |
| Pick trigger | Mapping draft, trigger field | `KeyButton`, `Button`, within `TriggerKeyToggleBtn` | Invoke unique dropdown. Multiple shortcut slots require identifying the requested slot. |
| Pick target | Mapping draft, key/shortcut action | `KeyButton`, `Button`, within `ActionKeyToggleBtn` | Invoke unique dropdown; do not select a window-global repeated ID. |
| Select key | Picker for known field/slot | `KeyListView` -> `ListItem`, exact key name | Wait for realization; supported ScrollItem then Invoke. Do not reopen the picker. |
| Search keys | Key picker | `KeySearchBox` -> current `Edit` | Discover inner ID, SetValue, observe filtering; keyboard selection needs guarded keys/readback. |
| Record field | Mapping draft, one field | `TriggerKeyToggleBtn` / `ActionKeyToggleBtn`, `Button` | Discover Toggle/Invoke; record physical keys, stop, observe unchecked state. Not the Settings shortcut recorder. |
| Save | Mapping draft | Dialog `PrimaryButton`, enabled `Button` | Invoke once; observe close versus validation; independently read both stores. |
| Cancel | Mapping draft | Current dialog-scoped localized cancel/close `Button` | Resolve from current tree and Invoke; process closure does not simulate Cancel. |
| Edit row | List, not Select mode | `RemappingsListView` -> owned `ListItem` | Identify by trigger/target and store identity, then Invoke; Name may be a model type. |
| Toggle row | Unique owned mapping row | Descendant `MappingEnabledToggle`, `Button` with TogglePattern | Read current state; Toggle only when needed. Compare editor IsActive and engine entry separately. |
| Delete row | Unique owned mapping row | Descendant `MappingMenuButton`, `Button`; current localized Delete `MenuItem` | Invoke menu once, wait for its scoped Delete MenuItem, then Invoke and confirm PrimaryButton. Do not replay menu Invoke while waiting; cancel is independent. |
| Search / filter | List | `TextBox`, `Edit`, under `SearchBox`; `FilterButton`, `Button` | SetValue for search. Invoke FilterButton once; wait for `WinFilterToggle`/`CtrlFilterToggle`/`AltFilterToggle`/`ShiftFilterToggle` buttons, `AppFilterCombo` ComboBox and `ClearFiltersBtn` Button. Toggle/select with readback; re-resolve rows. |
| Select visible rows | List, Select mode | `SelectionModeButton`, `Button`; owned `ListItem` under the appropriate category list | Invoke mode; scroll the identified owned row into view, then SelectionItem.AddToSelection. Read actual selected rows and `DeleteSelectedBtn` count; selection must not open an edit dialog. |
| Delete selected rows | Select mode | `DeleteSelectedBtn`, `Button`; current confirmation PrimaryButton and localized cancel Button | Invoke once, wait for confirmation, then independently exercise cancel/confirm. Compare selected, hidden and unselected owned UUIDs in both stores; reentering mode is separate from canceling confirmation. |
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
- Category lists are `RemappingsListView`, `TextListView`, `ProgramsListView`, `UrlsListView`
  and `DisabledListView`. Match owned trigger/action text and its saved UUID, not ListItem.Name
  (which can be a model type), row index or the first repeated menu button.
- Use `Read-PtSharedFileText`; preserve parse/schema failures. Export only owned synthetic rows.
  Draft, both saved stores and actual TextPattern/ValuePattern output are separate evidence.
  Labels, input return counts and stored VKs do not prove delivery.
- For modifier-first versus action-first release matrices, use `Invoke-PtHeldKeys -Keys`
  with an explicit `-ReleaseOrder` permutation; omitted order releases in reverse.
  The helper releases only accepted key-downs even after failure. Record each order separately.
- Distinguish actual Ctrl+V remaps from text replacement. Builds using `Helpers::SendTextInput`
  emit Unicode input and Shift+Enter directly; text-only cases need no clipboard read/write.
  Clipboard-based builds and actual paste actions still require complete preservation.

### Observation rules

Fit owned windows to measured physical work-area geometry before capture. Clipped images
cannot establish full-layout correctness. Exclude private tabs/mappings without hiding the
property tested; images remain candidates until accepted.

For theme coverage, use Windows Settings' `ms-settings:colors` page, not the PowerToys
General theme selector. Capture its initial page/window and app/Windows mode first. If
needed, choose Custom to expose the default app mode while retaining Windows mode.
Confirm the editor client surface changed theme before judging caption glyphs. Capture the
same active HWND with the pointer away from caption buttons; inspect glyph foreground and
background together, not just a whole-title-bar brightness statistic.

For direct DSC reads, resolve `PowerToys.DSC.exe` beside the installed Runner and inspect
its actual help. Invoke `get`, `export`, `schema` and `manifest` with
`--resource profile --module KeyboardManager`; supply the just-read JSON to `test` via
`--input`. Keep raw get/export/test data private; record operation exits, resource/schema
identity, content equality and desired-state Boolean. Compare both stores before/after.
The isolated `set`/reload fixture and friendly-key round trip remain separate requirements.

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
| Fixture restored its own layout but terminal changed | Compare the separately captured original foreground layout after final window activation; use the shared guarded layout restore. | A fixture-thread receipt is not a cross-application restoration guarantee. Unknown changes remain conflicts. |

## Fixtures and restoration

### Resource inventory

| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| Settings snapshot | Before Settings navigation | Run baseline; HWND borrowed | Template Settings adapter | Original identity/page/expansion/scroll/placement/visibility |
| `Get-PtFileSnapshot` stores | Before editor startup/mapping changes | Private original bytes/existence; exact case-owned rows | UI undo/delete, quiescent guarded rollback | Both stores and original settings byte/existence comparisons; runtime undo separately |
| Owned editor activation | Launch/reopen | Declare exact executable before `Invoke-PtOwnedProcessActivation`; register new PID/start/path and sibling HWNDs | `Stop-PtOwnedProcess` with normal tracked close | Owned processes/windows absent; existing editor untouched |
| [Keyboard input observer](../owned-fixtures.md#keyboard-input-observer) | Ordinary key output | Run-owned process/windows; separately capture original foreground with `Get-PtKeyboardLayoutSnapshot` | Normal exit, then guarded `Restore-PtKeyboardLayoutSnapshot` after desktop restoration | Released keys, owned resources absent, original foreground layout freshly matches |
| `New-PtNotepadFixture` | App-specific/document cases | Owned document; borrowed tabs and captured foreground lifetime | Paired removal with explicit owned-edit discard before foreground owner exits | Original tabs/selection/placement; owned tab/file absent |
| Clipboard session | Paste matrix | Supported private baseline and owned synthetic writes | Restore before owner/writer release | Original supported data restored without disclosure |
| App/browser/Shell fixture | Conditional actions | Exact owned tab/window/process and starting state | Scoped normal close and original-state restoration | No owned survivors; unrelated resources unchanged |
| Windows app theme | Theme assertion only | Original app/Windows mode, affected personalization values, Windows Settings page/window and editor mapping state | Restore through Colors UI before closing owned Settings; then restore borrowed windows | Original personalization values/kinds/existence, editor theme/mappings and Settings state; no Settings-only theme substitution |

### Helper boundaries

Use [session safety](../session-safety.md) and the shared recorder/template; independent cleanup
steps have `DependsOn=@()`. Resume with the original persisted plan. IME composition is not preserved.

Declare console/browser companion executable scopes before their first indirect activation,
including hosts started by the keyboard observer. A late scope can otherwise capture an
already-created test helper as borrowed and incorrectly require its survival after cleanup.

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
5. After owned fixture exit, restore borrowed Settings/desktop and complete resource observations.
   Then restore the original foreground layout with `Restore-PtKeyboardLayoutSnapshot` against
   the declared owned post-layout and compare desktop/layout again before sealing the report.
   Use the supported generic recorder lifecycle if template ordering cannot put this last;
   never perform cleanup in the reporting-only callback or after final export.

### Restoration verification

After final writes, compare general/module settings, profile/editor/lock bytes and existence,
owned-resource absence, borrowed UI and input-layout baselines. Log growth is outside mapping-state
equality. Disk equality cannot replace runtime undo. Retain conflicts and private recovery.

## References

- [Recorder and immutable evidence](../recording-workflow.md)
- [Ownership, Settings and cleanup](../session-safety.md)
- [Input, UIA, files and lifecycle](../helper-workflow.md)
