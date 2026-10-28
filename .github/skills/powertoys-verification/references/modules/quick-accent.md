# Quick Accent - module verification profile

## Module facts

| Fact | Value |
|---|---|
| Identity | **Quick Accent**, key `QuickAccent`; source `src\modules\poweraccent`. |
| Runtime | `<install>\WinUI3Apps\PowerToys.PowerAccent.exe`; resident while enabled. Toolbar title `Quick Accent`; a surviving HWND can be DWM-cloaked. Refresh identity after lifecycle changes. |
| Storage | `%LOCALAPPDATA%\Microsoft\PowerToys\QuickAccent\settings.json` and `UsageInfo.json`; general enablement is `enabled.QuickAccent`. |
| Usage side effects | Opening a list with frequency sorting off can clear history; shutdown can save it. Preserve bytes/existence before the first gesture. |
| Activation | Held letter plus Left/Right/Space, or press-and-hold. No named show event substitutes for this sequence. |

Use the [checklist](../release-checklist/quick-accent.md) and [inventory](../assertion-inventories/quick-accent.json).

## Entry paths

Capture [baselines](../quick-accent-fixtures.md) first; verify the owned editor's foreground/focus.

| Intent | Entry / destination |
|---|---|
| Configure | Expand `InputOutputNavItem`, invoke `QuickAccentNavItem`, not `PowerAccentNavItem`. |
| Trigger-key activation | Select a permitted trigger mode; hold letter, tap trigger, observe, release. |
| Press-and-hold | Select hold mode; hold letter alone. Pre-threshold trigger cancels; post-threshold input navigates. |
| Select sets | Expand Character sets; invoke Manage character sets once. Changes are drafts until Save. |
| Browse guide | Activate `ReferenceGuideCard`; resolve the new Settings-owned window. Copy requires clipboard preservation. |

Do not substitute a standalone worker for Runner ownership.

## UI state-transition map

Settings and runtime are independent. **Enabled** means Resident, Pending or Toolbar.

| Current state | Trigger / condition | Next state | State landmarks |
|---|---|---|---|
| Disabled | Settings enable | Resident | Current module PID; toolbar can be cloaked |
| Resident | Allowed trigger with held letter | Pending | Editor foreground; toolbar hidden |
| Resident | Mapped letter down in hold mode | Pending | Editor focused; no legacy trigger |
| Pending | Display delay elapses | Toolbar | Uncloaked host; `QuickAccentCharacterList` |
| Pending | Owner released before threshold | Resident | Hidden toolbar, surviving process |
| Pending | Hold-mode early trigger/different letter | Resident | Pending display canceled |
| Pending | Foreground leaves owner HWND | Resident | New foreground, no toolbar |
| Toolbar | Space/arrows/Shift+Space | Toolbar | Same list and current selection peer |
| Toolbar | Owner release | Resident | Toolbar cloaked, editor foreground |
| Toolbar | Foreground leaves owner HWND | Resident | Toolbar cloaked, new foreground |
| Enabled | Settings disable | Disabled | Recorded module PID exits |
| Settings page | Manage character sets; no prior modal | Set draft | Search, selectable list, Save/Cancel |
| Set draft | Filter or selection | Set draft | Current query and realized rows |
| Set draft | Save with selection | Settings page | Draft disappears |
| Set draft | Cancel | Settings page | Draft disappears |
| Settings page | Reference guide card | Guide | Separate window, SearchBox/LanguagesListView |
| Guide | Search/clear | Guide | Realized groups or empty-state landmark |
| Guide | Owned Close/back | Settings page | Main surface returns |

## Control locator and interaction index

Names below are localized examples.

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Enable/disable | Module Settings page | `Toggle_QuickAccent`, Button/TogglePattern | Shared Resident lifecycle, actual worker path/PID. |
| Activation mode | Expanded Activation key section | Local ComboBox named Activation key | `Select-PtComboBoxItem`; not the section Button. |
| Input/hold duration | Current mode | Labeled Spinner; child Edit `InputBox` | RangeValue or edit/focus commit; rediscover after mode change. |
| Game prevention | Activation section | Do not activate when Game Mode is on CheckBox | Toggle/read; game eligibility is independent. |
| Set draft | Character sets section | Manage character sets Button | `Invoke-PtQuickAccentCharacterDialog`; owned lifetime only. |
| Search sets | Owned draft | `CharacterSetsSearchBox` / Edit `TextBox` | Physical text; SetValue can bypass UserInput. Read query/filter. |
| Select set | `AvailableCharacterSetsList` | Named descendant's owning ListItem | Realize; AddToSelection/RemoveFromSelection. Select can clear other sets. |
| Select visible sets | Owned draft | `SelectAllCharacterSetsCheckBox` | Tri-state Toggle/Invoke; filtered rows only. |
| Save/cancel | Same draft | Buttons `PrimaryButton` / `CloseButton` | Invoke once; observe closure. |
| Position/description/order | Matching module section | Toolbar position ComboBox; labeled description/frequency/initial-selection toggles | Select/toggle, then observe an actual gesture. |
| Exclusions | Excluded apps expanded | Local multiline Edit | SetValue/focus commit; retain unrelated lines. |
| Held input | Owned foreground editor | Physical VK | `Invoke-PtQuickAccentGesture`; callback during shared held-key lifetime. |
| Navigate toolbar | Owner editor foreground | `QuickAccentCharacterList` ListItems | Physical arrows/Space; Shift+Space reverses. Read selected peer and pixels. |
| Open guide | Character sets section | `ReferenceGuideCard` | Invoke or guarded fresh-bounds click; register new secondary. |
| Filter/browse guide | Guide HWND | `SearchBox` / `TextBox`; `LanguagesListView` | SetValue/read binding; scroll and rediscover virtualized rows. |
| Hover | Guide set/key row | Character Button's Unicode name | Observe fresh associated tooltip/pixels, not just Name. |
| Copy | Guide row; clipboard preserved | Character Button | `Invoke-PtClipboardWrite`, actual Settings writer, one completed copy. |
| Close guide | Owned secondary | Close/back or WindowPattern | Shared ownership checks; preserve borrowed siblings. |

### Read-out notes

- Under `properties`, `activation_key`, `do_not_activate_on_game_mode`, `show_description`,
  `sort_by_usage_frequency`, `start_selection_from_the_left` are scalars; `toolbar_position`,
  `input_time_ms`, `hold_duration_ms`, `selected_lang`, `excluded_apps` use `.value`.
- Read exact inserted Unicode from the same editor that received input, without clipboard.
  Keep Notepad's IME/layout condition distinct from an owned Latin fixture.
- Combine identity, DWM cloak, list structure and owner foreground. Selection is not painted
  highlight evidence; first-frame claims need timestamped captures.
- The guide filters sets containing the query and retains their other mappings. Selected sets
  come first; remaining language/special groups sort within each group. Dotted circles are display
  aids, not copied characters. Scroll all realized headings and compare against the available-set
  catalog, not one viewport.

## Troubleshooting

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| No visible toolbar | Check mode, sets, owner focus/token, held input and cloak | Process/input success is not activation. |
| Unexpected Notepad Space text | Record IME/layout; separately compare owned Latin input | Do not substitute fixture results. |
| Search does not filter | Verify physical UserInput in the draft | Guide binding differs; SetValue alone is insufficient. |
| Missing set/heading | Filter/scroll, rediscover, compare pixels | Virtualization is not absence. |
| Draft survives error | Cancel only the same owned draft | No duplicate ContentDialog or unowned replacement close. |
| HWND/process disappears | Stop dependent input; retain identity/logs/crash events | Last input is not root-cause proof; no restart loop. |
| Guide retains other mappings | Inspect matching sets | Filtering is set-level. |
| Main hides with guide | Track both Settings windows | Hidden is not exited. |
| Cleanup differs | Retain originals and attributed post-state | No rebaseline, defaults or arbitrary tolerance. |

## Fixtures and restoration

### Resource inventory

| Resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| Text fixtures | Entry/focus/exclusion | Shared Notepad tab or tracked two-window Latin host | Owned tab/form close; verify host exit | Unrelated windows preserved |
| Settings/usage files | Before first gesture | Private bytes/existence and known post-state | Shared guarded rollback after worker exit | Exact after final startup |
| Settings/guide | Navigation/configuration | Shared snapshot; separate borrowed/owned identities | Restore main; close owned draft/guide | Supported page/placement/scroll |
| Clipboard | Guide copy | Shared keeper; history considered separately | Restore before provider exit | Supported formats/payloads preserved |
| Desktop/input/recorder | Input/capture | Original desktop; owned keys/process | Pointer before final owned close/high-IL foreground | Final readback; owned absence |

### Helper boundaries

The [fixture guide](../quick-accent-fixtures.md) owns API wiring. `pt-quick-accent.ps1` only
composes held input and draft lifetime; preservation and recording remain shared.

### Restoration order

1. Release input/capture, cancel owned drafts; restore clipboard before guide/provider exit.
2. Reverse settings through UI; disable Quick Accent through shared lifecycle and observe exit.
   Navigate away from its cached page before exact file rollback.
3. Roll back owned files against known post-state; restore enablement and compare after startup.
4. Restore Settings snapshot, pointer before final owned-window closure, then foreground.
   No gesture/write/startup follows final usage restoration.

### Restoration verification

Compare settings/usage bytes/existence, enabled/runtime state, unrelated General fields,
supported UI, desktop and owned absence. Keep the original baseline, conflicts and normal logs.
