# Shortcut Guide — module verification profile

## Module facts

| Field | Value |
|---|---|
| **PT module** | `Shortcut Guide` (app-aware Windows and application shortcut overlay) |
| **Source** | `src\modules\ShortcutGuide\` |
| **Settings file** | `%LOCALAPPDATA%\Microsoft\PowerToys\Shortcut Guide\settings.json` |
| **Exe** | `%LOCALAPPDATA%\PowerToys\WinUI3Apps\PowerToys.ShortcutGuide.exe` |
| **Default hotkey** | `Win+Shift+/` (`properties.open_shortcutguide`) |
| **Named Event** | `ShortcutGuide.Trigger` (`Local\ShortcutGuide-TriggerEvent-d4275ad3-2531-4d19-9252-c0becbd9b496`) |
| **Per-user manifests** | `%LOCALAPPDATA%\Microsoft\WinGet\KeyboardShortcuts` |
| **Installed manifests** | `%LOCALAPPDATA%\PowerToys\WinUI3Apps\Assets\ShortcutGuide\Manifests` |
| **Index generator** | `%LOCALAPPDATA%\PowerToys\WinUI3Apps\PowerToys.ShortcutGuide.IndexYmlGenerator.exe` |

**Lifecycle profile**: use [module lifecycle](../module-lifecycle.md) with
`Model=Resident`, key `Shortcut Guide`, page `ShortcutGuideNavItem`, toggle name
`Shortcut Guide`, the executable path above and native class
`WinUIDesktopWin32WindowClass`. For `ShortcutGuide.Trigger`, use
`WhenEnabled=Present` and `WhenDisabled=Ignore`: Runner's DLL owns the event, so it
can survive disable. Process/host exit, not event absence, establishes the stop condition.

**Assertion inventory**: [frozen SG scenario/child mapping](../assertion-inventories/shortcut-guide.json);
load it with the [shared inventory contract](../assertion-inventories/README.md), not run-local regrouping.
Run through the common template with the [mandatory resource wiring](../session-safety.md#mandatory-wiring-for-aligned-module-runs);
old report-local bootstraps are not the current run entry.

## Entry paths

Choose the route that exercises the requested behavior, not a fixed fallback order.
Before entry, follow [Fixtures and restoration](#fixtures-and-restoration) for snapshots,
ownership and safe Show Desktop coverage, and [Observation rules](#observation-rules)
for host/content readiness. Establish the [recording context](../recording-workflow.md)
before discovery or activation.

Use the [owned composed flows](shortcut-guide/composed-flows.md) for full-guide
open/observe/close and callback-scoped Windows-key holds. Specify the entry and close
route explicitly. A failed physical-chord path must not be replaced by a named event
and credited as the same test; an already-hidden surface cannot pass a close-route assertion.

Use `Assert-PtForegroundOrAbort -Hwnd` when an app has multiple windows. For
keyboard-hook tests, compare runner and foreground integrity levels; apply the shared
[pre-flight policy](../pre-flight.md) to admin-required variants.
To prepare the configuration page, open `PowerToys.exe --open-settings=ShortcutGuide`;
this setup route does not prove navigation through the guide's Settings rail item.

| Assertion | Entry path |
|---|---|
| Downstream content/navigation | `Invoke-PtSharedEvent -Name 'ShortcutGuide.Trigger'`; does not prove a keyboard binding |
| Configured binding or excluded-app gate | `Send-PtChord -Hwnd <tracked-window> -Mods 0x5B,0x10 -Key 0xBF` for the default; use its no-delay activation default, not recorder-oriented dwell |
| Hold threshold or release | `Invoke-PtHeldKeys -Hwnd <tracked-window> -Keys 0x5B -Action { ... }`; repeat with `0x5C`, observing while held; release is guaranteed by `finally` during normal exception unwinding |
| Quick Access integration | After fresh SG startup completion, signal `Local\PowerToysQuickAccess_<RunnerPid>_Show` once; wait for actual QA foreground/uncloaked state and tile availability, then invoke the tile. See [entry transitions](shortcut-guide/entry-points.md). |
| Settings rail navigation | Click the actual Settings item, then wait for the existing Settings HWND foreground with SG selected; retain guide visibility separately, never force the destination or credit an already-selected background page. |
| Command Palette integration | Discover the actual PowerToys extension and its module commands; a **Search apps** result for PowerToys is not the command provider |

Confirm the arrival surface using the [state map](#ui-state-transition-map).
Shortcut assignment/restoration belongs to the [interaction index](#control-locator-and-interaction-index);
changing a binding and exercising that binding are separate operations.

## UI state-transition map

Read this as a state-to-actions index, not a fixed test sequence. Each row has one
destination; landmarks identify the surface, not a product PASS. `Enabled, hidden`
means a resident host without visible guide/indicators, not a disabled module.
`Any enabled state` means that hidden state, Taskbar indicators or Full guide.
Regular activation is a non-hold route selected in [Entry paths](#entry-paths).
Track whether the current guide was opened by Windows hold or regular activation;
the same rendered pane has different toggle/release behavior.

| Current state | Trigger / condition | Next state | State landmarks |
|---|---|---|---|
| Disabled | Enable through Settings; wait for host readiness | Enabled, hidden | Live module host with no visible pane/callouts; saved enablement observed separately |
| Enabled, hidden | Regular activation; foreground application not excluded | Full guide | Realized guide pane with search Edit and application rail |
| Enabled, hidden | Windows hold reaches configured threshold; indicator mode and foreground not excluded | Taskbar indicators | Taskbar callouts without the full guide pane |
| Enabled, hidden | Windows hold reaches configured threshold; full-guide mode and foreground not excluded | Full guide | Guide pane/search/rail; opening source recorded as Windows hold |
| Taskbar indicators | Press/release a taskbar number while Windows remains held | Taskbar indicators | Callout surface remains; foreground routing is read separately |
| Taskbar indicators | Release Windows, regardless of the full-guide release setting | Enabled, hidden | Indicator surface gone; resident host retained |
| Taskbar indicators | Regular activation | Full guide | Guide pane/search/rail; activation source is now regular |
| Full guide | Escape with a non-whitespace search query | Full guide | Pane remains; cleared search Edit establishes the next Escape branch |
| Full guide | Release Windows; opened by hold and close-on-release enabled | Enabled, hidden | Pane hidden; resident host retained |
| Full guide | Release Windows; opened by hold with close-on-release disabled, or opened by regular activation | Full guide | Guide pane remains available |
| Full guide | Regular activation while the current opening source is Windows hold | Full guide | Same pane, search focused; activation source changes to regular |
| Full guide | Regular activation while the current opening source is already regular | Enabled, hidden | Pane hidden; resident host retained |
| Full guide | Close button, Escape with an empty or whitespace-only query, outside-pane click, or deactivation in a Release build | Enabled, hidden | Guide pane gone; do not infer process exit |
| Any enabled state | Disable through Settings | Disabled | Tracked module process/host exits; Runner-owned named-event existence is not a landmark |

An excluded foreground app suppresses opening from the hidden state; Windows-key Off
mode has no hold-open transition. Do not replace a failed physical entry with a named
event and credit the same assertion. Use the [interaction index](#control-locator-and-interaction-index)
for scoped operations, [Observation rules](#observation-rules)
for readiness, and the [release checklist](../release-checklist/shortcut-guide.md) for
thresholds, Start suppression, routing and other behavioral assertions.

## Control locator and interaction index

Use shipped controls for UI/binding assertions. Resolve the current HWND, page and parent
before matching the stated UIA properties; English names are localization hints, and
XAML `x:Uid` resource names are not AutomationIds. Settings must be visible, non-minimized
and explicitly activated. Do not force disabled controls or infer permission to enable
a module. Test inputs and expected results remain in the checklist.

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Enable or disable Shortcut Guide | Settings HWND, Shortcut Guide page | Enable ToggleSwitch named **Shortcut Guide**, inside the enable card | Use the explicit UI operation in the [lifecycle contract](../module-lifecycle.md), changing only a differing state. Re-resolve the module host after a cycle. |
| Assign an activation shortcut | Settings HWND, `ShortcutGuideNavItem` selected; module enabled | Activation Shortcut card's Button `AutomationId=EditButton` | Use the [shortcut recorder](../shortcut-recorder.md): snapshot, set the requested binding with Save/Cancel, then restore the captured original. Supply the addressing below; do not use Reset. |
| Select Windows-key behavior | Settings, Shortcut Guide; module enabled | `ControlType=ComboBox`, `AutomationId=ShortcutGuide_WindowsKeyAction` | Use `Select-PtComboBoxItem` with the current HWND and requested option's observed name. Mode selection and physical hold/binding behavior are separate operations. |
| Set the hold duration | Settings, Windows-key action expander open; action is not Off | NumberBox `AutomationId=ShortcutGuide_PressTime`; its child Edit | Focus the child Edit, replace its text, then commit with Enter or focus loss inside Settings. Do not apply ValuePattern to the NumberBox wrapper or bypass its disabled state. |
| Set close-on-Windows-release | Same expanded group; **Open Shortcut Guide** mode selected | `ControlType=CheckBox`, `AutomationId=ShortcutGuide_CloseOnWindowsKeyRelease` | Read ToggleState and toggle only if needed. This control is hidden in other modes; selecting the full-guide mode is a prerequisite, not a locator fallback. |
| Edit excluded applications | Settings, Shortcut Guide, excluded-app expander open | Multiline Edit within that expander, located by the current localized excluded-app label | Set the requested executable-name list, one per line, through the Edit's ValuePattern. The Text binding updates on change; do not write JSON instead of exercising this control. |
| Select the guide theme | Settings, Shortcut Guide, Appearance & behavior | ComboBox named **Theme** in the current UI language | Use `Select-PtComboBoxItem` with `-ControlName`, current HWND and observed option name; preserve the original selection. |
| Select the pane side | Same Settings page and group | ComboBox named **Window position** in the current UI language | Use the same scoped selection helper for the requested Left/Right option; this changes the guide pane, not the Windows taskbar. |
| Select an application's shortcut page | Full-guide HWND, application navigation rail | Realized rail ListItem; IDs include `Microsoft.PowerToys` and `+WindowsNT.Shell` | Select the intended item through its supported selection/invoke pattern, or click that exact realized item. Re-resolve page controls after selection. Do not use the Settings footer item as an application page. |
| Enter or clear a search query | Full-guide HWND, current application page | Group `AutomationId=ShortcutGuide_SearchBox` containing Edit `AutomationId=TextBox` | Set the child Edit's value, including empty text to clear. Do not set the AutoSuggestBox wrapper or mistake its accessible name for text. |
| Focus search with the keyboard | Full guide foreground; no shortcut recorder active | Same search Edit, reached by the product accelerator | Send real Ctrl+F to the guarded guide HWND. Directly focusing the Edit is not a substitute when the accelerator is under test. |
| Pin or unpin a shortcut | Full guide, intended application/category and realized shortcut row | Row's context menu; Button/MenuItem `AutomationId=PinMenuItem`, with current Pin/Unpin caption | Right-click the exact row, then invoke its menu item only if its current action matches the requested change. Close an unused owned menu; do not blindly toggle pinned state. |
| Exercise startup manifest regeneration | Owned per-user manifest fixture; startup writes snapshotted | Not a UI control: per-user manifest directory; module enable toggle for a fresh process | Follow the directory ownership rules before removal. For a startup test, explicitly disable/enable via Settings and wait for copy/index completion; merely opening an already-running guide does not rerun startup copying. |
| Rebuild the custom-manifest index | Owned manifest edits prepared; original directory state captured | Not a UI control: installed `PowerToys.ShortcutGuide.IndexYmlGenerator.exe` | Run the generator without arguments and wait for exit code 0. Use the cached-content procedure below for setup/recovery; generating the index alone does not invalidate an existing process cache. |
| Change a shortcut reflected on the PowerToys page | Settings, representative module's shortcut card; guide observed separately | That module's scoped `EditButton`; guide rail ID `Microsoft.PowerToys` | Use the common recorder with that module's page/file/property addressing, then open/select the guide page separately. Preserve the requested ordinary-reopen path before any diagnostic refresh. |
| Repeat guide use in one process | Enabled host; one tracked foreground fixture | Entry/close controls from [composed flows](shortcut-guide/composed-flows.md), plus the application rail | Repeat explicit open, navigate and close operations without restarting the module. Take cycle count and warm-up from the checklist, not from this index. |
| Change the PowerToys display language | Settings HWND, General page; restart authorized and original language captured | ComboBox `AutomationId=Languages_ComboBox`; language-change InfoBar's Restart button | Select the requested language, then use the offered normal restart action. Do not use Restart as administrator. Re-discover all HWNDs and localized names after restart; restore the original language through the same path. |

ComboBox calls require both the exact window and the option name. This is a call template,
not a fixed test input; resolve `$itemName` from the current localized options:

```powershell
Select-PtComboBoxItem -Hwnd $settingsHwnd `
    -AutomationId 'ShortcutGuide_WindowsKeyAction' -ItemName $itemName
```

For theme/position, use `-ControlName $controlName` instead of `-AutomationId`.
The helper deduplicates runtime identities, reads the actual selection and closes only
its own popup; the caller restores the original value. See [scoped control selection](../helper-workflow.md#scoped-control-selection).
For shortcut recording, supply the current HWND, `PageAutomationId=ShortcutGuideNavItem`,
`AutomationId=EditButton`, SG settings file, literal property segments
`@('properties','open_shortcutguide')` and the run workspace to `Get-PtShortcutSnapshot`.

Use the shared [shortcut recorder](../shortcut-recorder.md) for assignment/restoration.
Its Ctrl-only readiness handshake establishes that the capture hook responds before the
main chord, rather than assuming visible dialog controls mean the hook is ready.
It compares complete saved fields and edit-button HelpText after assignment/restoration;
the dialog's Windows artwork is not exposed by UIA. Do not use **Reset** as a substitute
for restoring the captured original.

### Read-out notes

- Read saved JSON and exercise the resulting behavior; a successful UIA invocation is not proof
  of persistence. Pin state is application-scoped in `Pinned.json`.
- General enablement is `enabled."Shortcut Guide"` in the root PowerToys settings file.
  In the SG file, the scalar readout paths are `properties.win_key_action.value`
  (`0` Off, `1` indicators, `2` full guide), `properties.press_time.value`,
  `properties.close_on_windows_key_release.value`, `properties.disabled_apps.value`,
  `properties.theme.value` and `properties.window_position.value` (`0` Left, `1` Right).
  `properties.open_shortcutguide` is the complete binding object. These are data paths,
  not UI selectors or permission to replace the control with a JSON write.
- For a Color Picker shortcut-reflection fixture, supply `ColorPickerNavItem`,
  `ColorPicker\settings.json`, and `@('properties','ActivationShortcut')` to the recorder.
  The helper changes/restores the setting; actual binding
  behavior and SG row updates remain separate case assertions. Final cleanup restores the
  user's captured original, even when a case temporarily requires the factory default.
- Realize rows by scrolling or filtering before counting recommendations or assessing keyboard
  focus; an incomplete UIA tree is not evidence of missing rows.
- For no-results announcements, read native `UIA_LiveSettingPropertyId` (`30135`; `1` is Polite).
  Use `Get-PtUiObservation -Property LiveSetting` on `ShortcutGuide_NoSearchResults`
  (type `Text`). Its value does not prove actual speech; confirm rendered emptiness separately.
- For search text, read `-Property Text` from the `TextBox` edit within
  `ShortcutGuide_SearchBox`. `-Property Name` is the separate accessible label; the
  placeholder `Search shortcuts` is not an empty query's value.
- For selection/focus, read `IsSelected` on the application rail's `ListItem` identifiers and
  `HasKeyboardFocus` on the exact intended control. These facts do not prove visual
  order, coherent spoken output or exactly-once announcements.
- A search/navigation snapshot contract can require the `ShortcutGuide_SearchBox`
  Group, its `TextBox` Edit, and `MenuItemsHost` Group. It must not require
  `ShortcutGuide_NoSearchResults`, recommended rows or pinned rows to exist.
  Counting/absence assertions require a separately established content observation scope.
- For reuse, record the active PID and private working set, with warm-up, cycle count, idle time,
  and limit taken from the checklist rather than substituted process-private-byte measurements.

### Observation rules

- Use `Get-PtShortcutGuideHost` / `Wait-PtShortcutGuideHost` from `pt-shortcut-guide.ps1` to
  resolve a live Shortcut Guide PID, then its native host HWND by owner PID and class
  (`WinUIDesktopWin32WindowClass`). Exclude tooltip/`PopupHost` windows; confirm full-monitor bounds
  after showing the host. `MainWindowHandle` is only a hint, and English titles are not identifiers.
  Re-resolve after enable cycles or restarts; do not retain exited process objects.
- Poll saved enable state, host readiness, and populated content separately.
  H06 observes native lifecycle; H07/content checks establish the next case's observation
  surface. A diagnostic cycle invalidates old PID/HWND/UIA references and is not Normal reopen.
  `Wait-PtShortcutGuideContent -Mode FullGuide|Indicators` checks realized mode-specific controls,
  not just visibility. Start the activation
  timeout after host readiness; allow up to 9 seconds for cold full-guide content. A held-key
  observation must keep the key down until captured; measure threshold behavior separately.
- Use `Save-PtPassiveScreenshot -Path <unique-path> -Observe <stable-state-probe>` for menus,
  overlays and held-key observations. Even `winapp ui screenshot -w` without `--capture-screen`
  can change focus. A changed foreground/observation invalidates that capture, which is retained
  with its state sidecar. Review actual pixels after the content-ready probe.
- The full guide and indicators share one host. Inspect pane/callout content as well as native
  visibility; process existence alone proves neither mode. The host should have `WS_EX_TOOLWINDOW`,
  not `WS_EX_APPWINDOW`. Review actual pixels for theme, localization, glyphs, and clipping.
- After a short Windows press opens Start, read `Get-PtForegroundWindow` directly and use
  `Restore-PtForegroundAfterShell -Hwnd <tracked-target>` for the test-owned transition.
  Start/Search and even the taskbar can be absent from `EnumWindows` during this state.
  Verify the target again before the next chord; do not infer closure from an empty enumeration.

An inspect result containing only the native host and a `PopupHost` is not an empty shortcut
page. Use the shared [UI observation contract](../ui-observations.md) to assess the captured
structure; retain insufficient snapshots and report observer limitations rather than zero rows.
Collect raw observations and review them against screenshots and exact settings fields before
committing either successful restoration or a product FAIL. A proven
observer mistake can reopen only the affected item using the shared recording workflow; do not
repeat the other checklist items or replace the entire run to correct that judgment.

Declare temporal/speech observers before theme, animation and Narrator cases; do not
substitute settled images for those assertions.
During recorded attempts, route winapp operations through `Invoke-PtWinApp`; its internal
readiness and taskbar probes are recorded too. See the shared [recording workflow](../recording-workflow.md).

## Troubleshooting

Preserve the original action and observations. Recovery must be authorized, preserve the
assertion's entry path and have a restoration plan; diagnostic recovery cannot erase an
earlier failure. These rows are diagnostic branches, not automatic verdicts. Apply the
[shared taxonomy](../../SKILL.md#step-3--classification-taxonomy) to the actual prerequisite,
observation or behavior failure, and continue independent eligible checks.

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| Recorder is empty, or the assigned chord does not activate | Follow the [shortcut recorder](../shortcut-recorder.md) readiness/field checks, then the selected [physical entry](#entry-paths) with exact foreground and integrity observations. | A recorder failure, an undelivered chord and a delivered-but-ineffective chord are different facts. A named event cannot prove the binding. |
| Start/Search retains foreground after Windows release | Recover only the test-owned Shell transition with the actual foreground HWND under [Observation rules](#observation-rules), then recheck the target. | Do not drop the guard, dismiss unowned UI or count every later input failure as a separate environment blocker. |
| Host is absent, UIA exposes only a host/PopupHost, or capture hides the guide | Check saved enablement, current PID/host identity, mode-specific content and foreground/capture sidecars separately. Use the passive-capture and structural-observation rules before any authorized retry. | Host existence is not visible content; an incomplete tree is not zero shortcuts. An observer-invalid capture cannot establish a product absence or retention failure. |
| Manifest or generated shortcut content stays old after normal reopen | Preserve that reopen observation before using [cached-content recovery](#cached-content-refresh), including its file/restore ownership. | Refresh/restart is a diagnostic operation, not evidence that ordinary reopen or live refresh worked. |
| Search text is reported as `Search shortcuts`, or a property is unavailable | Use the exact child Edit and supported property from [Read-out notes](#read-out-notes) / [UI observations](../ui-observations.md). Retain typed missing/unsupported/read-error evidence. | Accessible Name is not query text, and unavailable is not empty/false. Do not manufacture a no-results observation from either. |
| Escape closes instead of clearing the search | Read the actual query before the key event. The [state map](#ui-state-transition-map) distinguishes non-whitespace from empty/whitespace-only queries. | `TryClearSearch` uses `IsNullOrWhiteSpace`; spaces alone follow the close path. Do not infer a failed clear from that case. |
| Full-guide initial page shows unexpected taskbar callouts | Identify Full guide versus Indicators mode, selected application and its `<TASKBAR1-9>` section. Capture initial state before an authorized page-away/back diagnostic; see the visibility paths below. | Full guide may legitimately include taskbar content. Compare with the matched page/spec; a page-switch correction does not erase an initial rendering mismatch. |
| Theme or localization looks wrong despite saved settings | Compare the requested setting, current process identity and actual pixels on the required opening path. Distinguish core chrome from application-manifest text and PowerToys language from Windows language. | Saved JSON/visibility is insufficient. Allowed English manifest text is not a core-localization defect; an extra restart cannot silently replace the tested path. |
| Win+number target is ambiguous | Use the [first-slot fixture](shortcut-guide/taskbar-fixture.md); record exact frame/content HWNDs, held keys and foreground before/after the digit. | `explorer.exe` or a successful input call alone does not identify the routed app. Separate fixture failure from observed routing/retention behavior. |
| CmdPal module commands are absent | Inspect the real PowerToys provider, effective SG enablement/policy and fresh query/provider errors using [Entry paths](#entry-paths). Check the command conditions below. | Disabled-state toggle absence can be correct. Confirmed absence of required shipped integration is availability evidence, not automatically a prerequisite skip; unexecuted dependent actions have no product outcome. |
| Required mixed-DPI display pair is absent | Inspect active topology against the selected assertion and record the actual missing displays/scales. | Limit the prerequisite restriction to cross-monitor coverage. Pane Left/Right does not require relocating the Windows taskbar. |

Module-specific conditions for interpreting command availability and initial-page taskbar content:

- `ShortcutGuideModuleCommandProvider.BuildCommands` supplies Settings even when SG is
  disabled; its Toggle command is gated by effective enablement, including policy. This
  assumes the PowerToys provider itself is loaded. An app-search result or a missing settings
  file does not establish provider availability/disablement.
- Taskbar visibility has two writers in the profiled implementation:
  `MainPaneControl.WindowSelector_SelectionChanged` checks for `<TASKBAR1-9>` and can collapse
  the pane, while `OverlayWindow.UpdateTaskbarPaneLayout` makes a non-null layout visible.
  `App.HandleActivationAsync` calls the latter again after `MainPane.Open`. Preserve the
  initial frame and selected manifest before comparing page-away/back behavior; do not
  pre-navigate to hide the initial-state discrepancy or attribute it to UIA without evidence.

## Fixtures and restoration

Use the [shared session contract](../session-safety.md) before mutation: borrow Settings,
record owned foreground fixtures and declare cleanup dependencies. Settings close/reopen
requires an owned launch; the UI adapter preserves supported original state without replacing
a borrowed process. Report unresolved cleanup resources and retain this run's original baseline.

Prepare only resources required by the selected assertions. Before mutation, capture original
existence/values and declare ownership and **case-owned** or shared **run-owned** lifetime.
Keep the original run baseline across retries. Declare semantic or byte-exact file restoration
up front, including whether runtime cached content is part of the required baseline.

### Resource inventory

| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| Settings, shortcut binding and lifecycle | Mode, timing, appearance, exclusion, binding or enablement checks | Original SG settings, complete chord, enabled state and touched general/representative-module settings; include `language.json` when changing language | Restore settings/bindings through their scoped UI helpers; plan any required original-state restart before final verification | Original fields and enabled state observed; byte-level comparison only when declared and writers are quiescent |
| `Shortcut Guide\Pinned.json` and pinned UI state | Pin/unpin cases | Original file existence/contents and application-scoped pinned entries; the live in-memory list is separate state | Reverse owned pin changes through UI where possible; reconcile owned file state with a suitable guarded rollback | Original file state and relevant pinned UI agree; file restoration alone does not repair a stale in-memory list |
| Per-user manifest directory | Manifest/index/generated-shortcut cases and every process start | Full bounded baseline plus exact owned filenames: test manifests, shipped copies, `index.yml` and active `Microsoft.PowerToys.<language>.yml`; declare directory/root existence separately | Use the [directory contract](../directory-snapshots.md) and the startup-aware order below; preserve unowned entries | Receipt's owned paths match; disclose partial/whole-tree differences and check required cached content separately |
| Foreground application fixtures | Application pages, exclusions and foreground/integrity cases | Receipts from `New-PtNotepadFixture` or `New-PtExplorerFixture`; preserve user tabs/windows | Use the matching Remove helper under the [owned-fixture contract](../owned-fixtures.md), not a launcher-PID kill | Owned tabs/windows/files removed; unrelated application state preserved |
| Calculator and taskbar layout | Win+number routing cases | [First-slot fixture](shortcut-guide/taskbar-fixture.md) receipt: original taskbar/pins, owned Calculator identity, stable original foreground target | Release owned input/guide surface, then `Remove-PtTaskbarFixture`; keep its foreground target alive until cleanup finishes | Original taskbar/pins/foreground/pointer compared; user apps remain open |
| Touched windows, input and desktop state | Navigation, overlays, Show Desktop or language cases | Original identity/page/tab/IME/placement, foreground and pointer; track injected keys and newly opened surfaces | Release only owned input; restore touched state and close only owned windows after dependent fixtures finish | Compare recorded UI/desktop state; native placement snapshots do not restore page/tab/IME state automatically |

### Helper boundaries

Use [paired snapshots](../helper-workflow.md#pair-snapshots-with-restoration-before-changing-state)
for the supported file/registry/native-window facts, and explicit UI operations for the rest.
`Restore-PtFileSnapshot` without `-ExpectedState` is the legacy unguarded byte/existence restore.
Use its guarded expected-state path for existing files after quiescing writers; use directory
rollback for owned absence changes. Refuse unknown content rather than treating the backup
or a fresh snapshot of unexplained changes as authority.

Directory rollback requires quiescent writers, explicit owned paths and an expected
post-mutation snapshot. A hash list is not a backup; a captured directory is not wholly owned.
Preserve unknown changes and report the receipt's conflicts/partial state, rather than
adopting a fresh snapshot to bypass them.

Every SG process start can copy shipped manifests, regenerate the index and rewrite the
generated PowerToys manifest. Declare these writes before enable/restart, including language-
dependent filenames. Native host readiness alone does not establish writer completion.
Before Show Desktop, establish that all affected windows can be restored at the current
integrity level; block only that variant if not. A native snapshot grants no extra authority.

### Restoration order

1. In `finally`, release injected keys and dismiss owned guide/popups. Restore taskbar routing
   fixtures before closing their original foreground target; do not close user apps, change
   taskbar pins, rewrite registry state or restart Explorer as a cleanup shortcut.
2. Restore original UI settings, bindings and pinned selections while the needed controls are
   available. Quiesce relevant writers before raw file/directory rollback, then restore only
   declared owned state over its known post-state. Keep conflicting data and the baseline.
3. Restore the original lifecycle state. If originally disabled, do not start SG just to
   refresh a cache. If returning to the original enabled state requires a start/restart,
   treat it as a recorded mutation with declared startup-write ownership, not a harmless
   post-cleanup action. Do not start a writer over unresolved rollback conflicts.
4. Wait for copy/index/generated-manifest writers to finish after that last required start.
   Compare disk state and required runtime content again. Any additional owned rollback
   needs quiescent writers and a compatible cache-restoration plan. If the original file
   baseline and required running state cannot both be restored, report incomplete restoration;
   do not loop restarts or claim success from the pre-restart comparison.
5. Restore remaining page/tab/IME/placement, foreground and pointer, and release fixtures at
   their declared lifetime boundary. Perform final verification after all planned writes,
   restarts and UI restoration. Do not restart afterward merely to refresh a cache.

Check restoration feasibility before the case: if a required restart cannot coexist with
the declared original disk/cache state, do not begin that variant without a viable plan.
An unexpected limitation during cleanup remains explicit incomplete restoration.

### Restoration verification

- Original settings, complete shortcut, pin state, language and enabled state are restored;
  restored enablement is observed separately from native host and content readiness.
- Owned manifest/file/directory existence and required contents match after the last writer
  finishes. `WholeTreeMatchesBaseline=false` is not a whole-tree restoration, even when
  owned paths match; retain and report unowned differences.
- Required runtime cached pages/pins agree with the declared baseline. Restoring bytes alone,
  or reopening after an unrecorded restart, is insufficient.
- Owned application/taskbar fixtures and injected keys are released, and recorded user UI,
  taskbar and desktop state are restored. Conflicts, partial cleanup and unrecorded transient
  state prevent an unqualified **Baseline restored** claim.

### Execution notes

Use elevated Notepad only for eligible integrity variants and verify with `Test-ProcessElevated`.
Use a unique package/process filter for a disposable manifest. For three-app taskbar coverage,
track the required existing slots without closing user apps; the first-slot recipe handles
Calculator ownership and rollback. A grouped app is not itself a blocker.

#### Cached content refresh

This is **test setup or diagnostic recovery**, not an automatic final cleanup step.
Observe the requested ordinary-reopen behavior first; a restart cannot prove live refresh.
For authorized recovery, regenerate the index after manifest edits and cycle SG through
Settings if needed; for representative shortcut changes, refresh only after retaining any
ordinary-reopen mismatch. Record the restart and its file effects under the same ownership
contract. Final cleanup follows the restoration order above, not an unconditional
restore-files-then-refresh sequence.

## Source citations and visual references

- `src\common\interop\shared_constants.h` — `SHORTCUT_GUIDE_TRIGGER_EVENT`
- `src\modules\ShortcutGuide\ShortcutGuideModuleInterface\dllmain.cpp` — `GetHotkeyEx`, `milliseconds_win_key_must_be_pressed`, settings clamp
- `src\modules\ShortcutGuide\ShortcutGuide.Ui\ShortcutGuideXAML\App.xaml.cs` — activation event and Windows-key release handling
- `src\modules\ShortcutGuide\ShortcutGuide.Ui\Helpers\ShortcutGuideActivationPolicy.cs`
  — `GetActivationAction`, `ShouldCloseOnWindowsKeyRelease`; opening-source-dependent transitions.
- `src\modules\ShortcutGuide\ShortcutGuide.Ui\ShortcutGuideXAML\OverlayWindow.xaml.cs` — overlay show/close and taskbar-pane layout
- `src\modules\ShortcutGuide\ShortcutGuide.Ui\ShortcutGuideXAML\Controls\MainPaneControl.xaml.cs`
  — `WindowSelector_SelectionChanged`, `TryClearSearch`; taskbar sections and whitespace handling.
- `src\settings-ui\Settings.UI\SettingsXAML\Views\ShortcutGuidePage.xaml` and
  `ViewModels\ShortcutGuideViewModel.cs` — `WindowsKeyActionIndex`, `PressTime`,
  `IsOpenShortcutGuideWindowsKeyAction`, `DisabledApps`, theme and position bindings.
- `src\settings-ui\Settings.UI.Library\ShortcutGuideProperties.cs` — wrapped scalar
  settings and the unwrapped `OpenShortcutGuide` binding.
- `src\modules\ShortcutGuide\ShortcutGuide.Ui\ShortcutGuideXAML\Controls\ShortcutItemView.xaml.cs`
  — `PinFlyout_Opening` and `Pin_Click`.
- `src\modules\ShortcutGuide\ShortcutGuide.Ui\Program.cs` — startup copy/index thread;
  `ShortcutGuide.IndexYmlGenerator\IndexYmlGenerator.cs` — parameterless `Main`.
- `src\modules\ShortcutGuide\ShortcutGuide.Ui\Helpers\PowerToysShortcutsPopulator.cs`
  — `Populate` writes the language-specific PowerToys manifest;
  `Helpers\PinnedShortcutsHelper.cs` — `Save` persists `Pinned.json` separately from live pin state.
- `src\settings-ui\Settings.UI\SettingsXAML\Views\GeneralPage.xaml` and `.xaml.cs`
  — `Languages_ComboBox` and `Click_LanguageRestart`.
- `scripts\pt-uia.ps1` — `Select-PtComboBoxItem`; `scripts\pt-shortcut-recorder.ps1`
  — `Get-PtShortcutSnapshot`, `Set-PtShortcutBinding`, `Restore-PtShortcutSnapshot`.
- `src\modules\cmdpal\ext\Microsoft.CmdPal.Ext.PowerToys\Modules\ShortcutGuideModuleCommandProvider.cs`
  — `BuildCommands`; `Helpers\ModuleEnablementService.cs` — effective policy/settings enablement.

See the [visual reference](shortcut-guide/visual-reference.md) for cropped UI landmarks.
Screenshots are not timing evidence or pixel baselines.
