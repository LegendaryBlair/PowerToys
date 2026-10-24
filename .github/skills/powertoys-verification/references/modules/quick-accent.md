# Quick Accent - module verification profile

## Module facts

| Field | Value |
|---|---|
| Identity | Display name **Quick Accent**; module/settings key `QuickAccent`; source root `src\modules\poweraccent`. |
| Runtime | `WinUI3Apps\PowerToys.PowerAccent.exe` beneath the running PowerToys installation. Resolve path/PID from the actual process. The WinUI toolbar has window title `Quick Accent`; rediscover its HWND after enablement or process recreation. |
| Settings | `%LOCALAPPDATA%\Microsoft\PowerToys\QuickAccent\settings.json`; general enablement is `enabled.QuickAccent` in the parent `settings.json`. |
| Usage | `QuickAccent\UsageInfo.json` stores counters/timestamps. Opening a list with sorting off can delete history; orderly module shutdown saves it. Preserve before the first gesture, not only frequency tests. |
| Activation | Physical accent-capable letter plus Left/Right/Space, or opt-in press-and-hold. Discover the user's selected mode/delay; there is no activation shortcut chord or named show event equivalent to the held-letter path. |
| Lifecycle | Enabled module is resident even while the toolbar is DWM-cloaked. Disabling through Settings signals its exit and may invoke a fallback termination. A resident HWND is not proof of a visible toolbar. |
| Applicability | These operating routes describe the WinUI toolbar and searchable character-set dialog/reference guide. On older builds, discover the corresponding UI instead of assuming the old inline language list or WPF selector still applies. |

## Entry paths

Preserve the resources in [Fixtures and restoration](#fixtures-and-restoration) first. Use only an owned text
document at compatible integrity; verify its exact foreground HWND and focused editor before held input.

| Intent | Entry and destination |
|---|---|
| Configure Quick Accent | In the shipped Settings window, expand `AutomationId=InputOutputNavItem` if necessary, then invoke `AutomationId=QuickAccentNavItem`. Destination: **Settings page**. `PowerAccentNavItem` is not the module's navigation ID. |
| Exercise trigger-key activation | With the current mode permitting the trigger, hold the physical base-letter key and tap the trigger. Keep the letter held through observations/navigation. Destination: **Pending gesture**, then **Toolbar visible**. Release commits/dismisses. |
| Exercise press-and-hold | Select that mode through Settings; hold the physical letter without a legacy trigger. Destination: **Pending gesture**. Pre-threshold trigger keys cancel; after the threshold they navigate the visible toolbar. |
| Manage languages | Invoke the Settings page's **Manage character sets** button exactly once. Destination: **Character-set draft**. Search/selection changes are draft-only until Save. |
| Browse mappings | Invoke **Open reference guide** in the expanded Character sets section. Destination: **Reference guide** in a separate Settings-owned window. Do not click character buttons without clipboard preservation. |

There is no reason to launch the module executable directly for these user-entry assertions: doing so changes
Runner ownership/lifecycle. The reference guide is configuration UI, not a replacement for actual insertion.

## UI state-transition map

Settings and the resident module are independent surfaces. **Any enabled state** means Resident, Pending gesture
or Toolbar visible. The guide can coexist with the module; Settings may hide its main window while a secondary
window is open. Arrival requires fresh window/control observations, not a successful input call.

| Current state | Trigger / condition | Next state | State landmarks |
|---|---|---|---|
| Disabled | Enable through Settings | Resident | New module PID; cloaked toolbar HWND can exist |
| Resident | Allowed trigger with mapped letter held | Pending gesture | Owned editor remains foreground; toolbar not yet revealed |
| Resident | Mapped letter down in press-and-hold mode | Pending gesture | Owned editor focused; no separate trigger required |
| Pending gesture | Active gesture reaches its configured display delay | Toolbar visible | Uncloaked `Quick Accent` HWND; `QuickAccentCharacterList` |
| Pending gesture | Owner released before threshold | Resident | No visible toolbar; resident process remains |
| Pending gesture | Pre-threshold Space/arrow or different supported letter in hold mode | Resident | No visible toolbar; fresh owner press required to re-arm |
| Pending gesture | Foreground changes away from the owner HWND | Resident | Pending display canceled; new foreground owner |
| Toolbar visible | Space/arrows, including Shift+Space | Toolbar visible | Same list scope, changed selection peer |
| Toolbar visible | Owner-letter release | Resident | Toolbar cloaked; editor retains focus |
| Toolbar visible | Foreground moves to another HWND | Resident | Toolbar cloaked; receiving HWND is foreground |
| Any enabled state | Disable through Settings | Disabled | Recorded module PID exits; no live toolbar |
| Settings page | Manage character sets; no existing modal | Character-set draft | Search box, selected-count text, Save and Cancel |
| Character-set draft | Search or toggle selection | Character-set draft | Filtered list and updated selection count |
| Character-set draft | Save with at least one selection | Settings page | Dialog closed; selected-set summary visible |
| Character-set draft | Cancel | Settings page | Dialog closed; committed selection unchanged |
| Settings page | Open reference guide | Reference guide | Separate window with SearchBox and LanguagesListView |
| Reference guide | Change/clear search query | Reference guide | Set groups or explicit no-results content |
| Reference guide | Close/back control, when offered | Settings page | Main Settings surface returns |

## Control locator and interaction index

Use `winapp ui inspect --depth 12 -w $settingsHwnd --json` to discover the current tree; `$settingsHwnd` must be
resolved from the live Settings process. Scope repeated IDs to their parent, inspect supported patterns and
deduplicate peers by runtime ID. Accessible names below are English examples, not localization-independent IDs.

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Toggle module | Settings page | `AutomationId=Toggle_QuickAccent`; exposed as Button with TogglePattern | Read ToggleState; toggle only if needed. Observe actual PID exit/start before subsequent actions; refresh toolbar identity. |
| Expand activation | Settings page, Activation key section | Button `Name=Activation key`; not its ComboBox | Invoke/ExpandCollapse when collapsed, then inspect descendants. |
| Select activation mode | Expanded activation section | ComboBox `Name=Activation key` | Expand, then select the unique ListItem: `Left/Right Arrow`, `Space`, `Left, Right or Space`, or `Press and hold the letter`. Verify `SelectionPattern.Current.GetSelection()` and persistence. |
| Set input/hold delay | Trigger mode: Input delay; hold mode: Hold duration | Spinner/NumberBox scoped by accessible label; child Edit often `AutomationId=InputBox` | Use RangeValuePattern on the spinner where supported, otherwise edit its child and commit by moving focus. Reinspect because mode changes replace visible controls. |
| Toggle game prevention | Expanded activation section | CheckBox `Name=Do not activate when Game Mode is on` | Read TogglePattern, toggle to target state. This does not establish actual game-mode eligibility. |
| Open language draft | Settings page, Character sets expanded | Button `Name=Manage character sets` | Use the [owned dialog scope](../quick-accent-fixtures.md#character-dialog-ownership): reject a pre-existing modal, Invoke once, and cancel any remaining owned draft in finally. |
| Search character sets | Character-set draft | Group `AutomationId=CharacterSetsSearchBox`, child Edit `AutomationId=TextBox` | Focus that edit, replace its text with physical input and verify actual query/filter. ValuePattern alone can bypass the handler's UserInput condition. |
| Change one set | Character-set draft; `AutomationId=AvailableCharacterSetsList` | Accessible language-name descendant; walk to its owning ListItem | Use SelectionItemPattern AddToSelection/RemoveFromSelection, not Select which can clear other selections. Filter first; realize/scroll and rediscover if virtualized. Require one exact owner. |
| Select visible sets | Character-set draft | `AutomationId=SelectAllCharacterSetsCheckBox` | Inspect tri-state and Invoke/Toggle. It operates on the currently filtered sets; clear search first when intending all sets. |
| Commit/cancel draft | Character-set draft | Buttons `AutomationId=PrimaryButton` / `CloseButton`, scoped to the owned draft | Invoke Save only when enabled; Cancel discards. Wait for draft controls to disappear. Never re-open while they remain. |
| Select toolbar position | Settings page | ComboBox `Name=Toolbar position` | Expand/select the desired localized ListItem; observe the next real gesture at the active monitor. |
| Toggle description | Settings page, toolbar section | Button/ToggleSwitch `Name=Show the Unicode code and name of the currently selected character` | TogglePattern, then observe a new toolbar and selection. Do not interpret the accessible name as the toggle's value. |
| Toggle frequency sorting | Settings page, toolbar section | Button `Name=Sort characters by usage frequency` | TogglePattern with private usage baseline already captured. Observe actual order on a subsequent gesture. |
| Toggle initial selection | Settings page, toolbar section | Button `Name=Start selection from the left` | TogglePattern, then exercise Left and Right independently. |
| Edit exclusions | Settings page; expanded Excluded apps | Button `Name=Excluded apps`, then its multiline Edit | Expand first. SetValue replaces the whole field; preserve existing lines, add/remove only the owned fixture entry, move focus and verify persistence. |
| Hold/commit a letter | Exact owned foreground text editor | Physical VK in that editor, not a toolbar control | Use `Invoke-PtQuickAccentGesture` from the [fixture guide](../quick-accent-fixtures.md#owned-input); Observe callback runs with the letter held, and `finally` releases keys. Read the same editor afterward. |
| Navigate accent list | Toolbar visible; owner editor stays foreground | `AutomationId=QuickAccentCharacterList`; ListItems expose character Names and SelectionItemPattern | Send guarded physical arrows/Space; Shift+Space reverses. Read selected peers and pixels; do not use UIA Select to stand in for keyboard navigation. |
| Open guide | Settings page, Character sets expanded | Clickable card `Name=Open reference guide` | Invoke the discovered card. Resolve the new Settings-owned HWND by title/structural controls, not an old PID/HWND. |
| Filter guide | Reference guide | Group `AutomationId=SearchBox`, child Edit `AutomationId=TextBox` | SetValue can update this binding; verify actual query and rendered set membership. Use physical text input if binding does not react. Keep observers bound to this HWND. |
| Browse guide rows | Reference guide; `AutomationId=LanguagesListView` | Set-heading Text, key-row label, character Button | Scroll the owning list and re-resolve descendants. A single UIA enumeration may expose only realized headings, not the entire guide. |
| Inspect description | Reference guide, visible character row | Character Button Name is its Unicode description; scope by set/key row | Hover without clicking. Associate the actual tooltip/popup and its bounds with that target; the button's Name alone does not prove a hover tooltip appeared. |
| Copy a guide character | Reference guide; preserved/isolated clipboard required | Same row-owned character Button | Invoke copies its underlying value. The current fixture guide provides no accepted clipboard guard: do not execute this operation in an unpreserved user clipboard. |
| Close guide | Reference guide only | Its window Close/back control; or WindowPattern.Close | Close only the owned secondary window, then rediscover the main Settings surface. Do not kill Settings. |

### Read-out notes

Settings fields are not UI selectors. Under `properties`, `activation_key`, `do_not_activate_on_game_mode`,
`show_description`, `sort_by_usage_frequency` and `start_selection_from_the_left` are direct scalar values.
`toolbar_position`, `input_time_ms`, `hold_duration_ms`, `selected_lang` and `excluded_apps` use `.value`.
Older files can omit newer fields: preserve original bytes and distinguish omitted values from defaults.
Read live files with sharing that permits concurrent writes/deletion; retain parse/read errors rather than
substituting false/empty. A Settings draft, persisted value and runtime watcher application are separate facts.

For the toolbar, combine fresh PID/HWND validity, DWM cloaking, visible list structure, exact foreground and
selected character. The title/HWND can persist while hidden. Read inserted text as Unicode code points from
the owned editor, not via clipboard. IME composition can turn a Latin Space gesture into a different text
operation: retain Notepad's actual layout/IME condition and use a separate owned Latin fixture for that variant.

The guide filters **sets containing the query**, retaining all mappings inside those sets. Selected sets form
the first group; remaining language/special groups retain their own alphabetical order. The rendered dotted
circle is a display aid, distinct from the underlying combining character. Do not infer copy behavior from it.

### Observation rules

Use passive, owned-HWND screenshots and record foreground/cloaking before and after capture. A capture that
activates the toolbar can cancel the gesture. Composed captures must exclude unrelated desktop content.
SelectionPattern does not prove a highlight is painted; virtualized missing rows do not prove feature absence.
Measure physical work-area/window bounds and actual DPI in a consistent awareness context; do not multiply
already-physical `winapp` coordinates by the scale factor. First-frame claims need a ready recorder with
timestamped frames, not a settled image. Keep unique capture filenames per attempt.

## Troubleshooting

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| Module process exists but no toolbar is seen | Check configured mode, selected sets, owner-key state, exact foreground, token integrity and DWM cloak. Validate delivery with a fresh gesture and read-out. | Resident/cloaked is normal. SendInput acceptance or a stale log line does not prove activation. |
| Space produces unexpected text in Notepad | Record per-window keyboard layout and IME composition; compare a separately owned Latin TextBox without changing user input configuration. | A synthetic Latin result does not replace the baseline Notepad condition. Do not label IME-generated text an accent defect. |
| Search value changed but list did not filter | Confirm correct SearchBox/child and actual physical user-input event for the character-set dialog. | SetValue success alone is not a product filtering failure. The guide has a different binding. |
| Set name/guide heading is missing from UIA | Filter, realize/scroll the owning list, then inspect again; correlate set/key row and pixels. | Partial virtualization is unavailable observation, not proof that a language or mapping is absent. |
| Character dialog remains after an error | Cancel the owned draft and wait for its search/buttons to disappear before retrying Manage character sets. | A second ContentDialog can terminate Settings. Preserve the original error; do not attribute the driver's duplicate open to a normal product flow. |
| Toolbar HWND becomes invalid or process exits | Stop dependent input; retain PID/time, module logs and matching Windows Application events. Restore through Settings only when safe. | Process termination is a finding; the last input is not proof of root cause. Unreached assertions have no independent defect outcome. |
| Guide contains other characters after filtering | Read the set-level filter contract and inspect resulting set membership. | Remaining characters inside a matching set are not a filtering defect. |
| Settings main window disappears with the guide | Enumerate current Settings-owned windows; close the owned guide to return. | Hidden main window is not equivalent to a terminated Settings process. |
| Cleanup hashes differ or another actor changed state | Stop writes, retain private originals and known-owned receipts; report exact differences. | UI defaults/semantic equality cannot establish byte restoration. Do not overwrite unexplained external changes. |

## Fixtures and restoration

### Resource inventory

| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| Unique empty Notepad document; [preparation](../quick-accent-fixtures.md#owned-input) | Baseline activation/text insertion | Run-owned file and tab; record pre-existing tabs/PIDs and localized app controls | Discard only that tab using its observed prompt; delete only the owned file | Owned document gone; unrelated tabs remain |
| Two synthetic Latin windows; `scripts\fixtures\quick-accent-text.ps1` via [preparation](../quick-accent-fixtures.md#owned-input) | IME-independent pass-through, focus transfer and exclusion comparison | Run-owned host/PID/HWNDs; no clipboard, same medium integrity | Close both owned forms, then verify host exit | Both HWNDs absent; no injected participating keys held |
| Module settings and usage sidecar; file-baseline helper | Before any activation or settings change | Run-owned private snapshot of original existence/bytes; per-action owned hashes | Quiesce module, leave page, guarded exact rollback, restore original enablement | Both hashes/existence after final startup and settling |
| General enablement and Settings/guide UI | All mutation cases | Preserve general state semantically, current page/search, geometry and existing window identities | Restore only Quick Accent enablement through UI; close owned draft/guide; restore navigation/geometry | Unrelated general fields unchanged; report any replaced process identity |
| Foreground, pointer and injected keys | Input, hover or capture | Run baseline; track only keys pressed by the driver | Release owned keys in finally; restore pointer and original foreground after owned-window cleanup | Observe final foreground/coordinates and key-up state without another correction |
| Clipboard and independent history/cloud stores | Guide-copy assertions only | Requires separately validated private native-format preservation or isolated context | No copy operation without that prerequisite | Exact supported payloads/formats and side effects accounted for; no payload in evidence |
| Candidate capture/recorder | Visual claims | Run-owned scoped files and recorder PID | Stop recorder; archive sanitized files with timestamps, crop and hashes | Artifacts exist; no recorder remains; references still labeled candidates |

### Helper boundaries

`pt-quick-accent.ps1` provides held input, owned character-dialog lifetime and existing/absent file rollback, not a full test runner, clipboard
guard, Settings cache reset or ownership oracle. Consult the [fixture guide](../quick-accent-fixtures.md) for
required arguments, expected-hash guards and callback lifetime. Product logs are normal diagnostic side effects;
do not delete unrelated logs to manufacture a pristine environment.

### Restoration order

Release owned keys and stop capture; close the owned draft/guide. Restore original module controls through UI,
then disable through Settings and confirm the recorded module PID exits. Navigate away from Quick Accent
before exact file rollback. Restore usage/settings only against a known owned post-state, then restore original
enablement through UI. Observe files again after final startup. Close owned text fixtures, restore Settings
navigation/geometry and original pointer/foreground. Do not run another test gesture after that final rollback.

### Restoration verification

Verify original settings bytes, usage existence/bytes, enabled state, unrelated general fields, owned-window
absence and no held injected keys. Keep the original run baseline across retries. A crashed/recreated Settings
process cannot be restored to its original PID: report that difference even if page and geometry are restored.
Keep private recovery copies outside public archives until cleanup is confirmed; report retained conflicts.

### Execution notes

Reuse one owned text host across ordinary cases, resetting only its text between cases; keep Notepad coverage
distinct. Group toolbar observations while one set is selected, but do not skip language transitions required
by the checklist. A process exit stops dependent observations; it does not authorize repeated crash/restart
loops or weakening assertions. Ordinary coverage remains separate from clipboard, multi-monitor and specialist
conditions in the [inventory](../assertion-inventories/quick-accent.json).

## References

### Source citations

Paths below are repository-relative; symbols identify the operating contracts rather than a historical run.

- `src\modules\poweraccent\PowerAccentModuleInterface\dllmain.cpp`: `PowerAccent::launch_process`, `enable`, `disable`.
- `src\modules\poweraccent\PowerAccentKeyboardService\KeyboardListener.cpp`: `OnKeyDown`, `OnKeyUp`, `ForegroundEventProc`, `ForceReset`.
- `src\modules\poweraccent\PowerAccent.Core\PowerAccent.cs`: `PrepareCharacters`, `GetCharacters`, `ProcessNextChar`, `SendInputAndHideToolbar`.
- `src\modules\poweraccent\PowerAccent.Core\Tools\CharactersUsageInfo.cs`: `Clear`, `Save`, `GetUsageInfoData`.
- `src\modules\poweraccent\PowerAccent.UI\PowerAccentXAML\MainWindow.xaml.cs`: `PowerAccent_OnChangeDisplay`, `SizeAndPosition`, `Dispose`.
- `src\modules\poweraccent\PowerAccent.UI\PowerAccentXAML\SelectorControl.xaml`: `QuickAccentCharacterList`; code-behind `ScrollSelectedIntoView`.
- `src\settings-ui\Settings.UI.Library\PowerAccentProperties.cs`: serialized scalar/wrapper shapes.
- `src\settings-ui\Settings.UI\SettingsXAML\Views\PowerAccentPage.xaml.cs`: `ApplyCharacterSetsFilter`, `SelectAllCharacterSetsCheckBox_Click`, `CharacterSetsDialog_PrimaryButtonClick`.
- `src\settings-ui\Settings.UI\ViewModels\PowerAccentReferenceGuideViewModel.cs`: `UpdateFilteredGroups`, `BuildGroups`.
- `src\settings-ui\Settings.UI\SettingsXAML\Views\PowerAccentReferenceGuideWindow.xaml.cs`: `CharacterButton_Click`, `SearchBox_PreviewKeyDown`.
- [Release checklist](../release-checklist/quick-accent.md), [fixture guide](../quick-accent-fixtures.md), [generic capture/input mechanics](../winapp-ui-testing.md).
