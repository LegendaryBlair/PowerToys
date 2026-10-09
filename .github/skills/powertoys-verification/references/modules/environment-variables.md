# Environment Variables - module verification profile

## Module facts

| Fact | Value |
|---|---|
| Module / source | `EnvironmentVariables`; `src\modules\EnvironmentVariables\` |
| Executable / UI | `<install>\WinUI3Apps\PowerToys.EnvironmentVariables.exe`; WinUI 3. Resolve install root from the attested Runner/artifact, HWND/PID afresh. |
| Data | `%LOCALAPPDATA%\Microsoft\PowerToys\EnvironmentVariables\settings.json` and `profiles.json`; general enablement in parent `settings.json` |
| Events | `EnvVars.Show` / `EnvVars.ShowAdmin` in `pt-shared-events.ps1`; enabled Runner module required |
| Lifecycle / scope | Single-instance editor; Runner-launched editor watches its Runner PID. Repeated Runner launch foregrounds an existing editor, not a differently elevated instance; a second standalone instance exits. Profiles write User scope; direct System editing is elevation-gated. |
| Version gates | PATH deduplication: #50585. Startup/title fixes: #50027/#50688. Drag/drop #40105 was reverted by #44705; menu ordering remains. |

Keep expectations in the [checklist](../release-checklist/environment-variables.md);
actual build identities, live coverage and readiness in the run/authoring records.
This profile uses the WIP [run-local resource contract](../session-safety.md) and
[canonical recorder](../recording-workflow.md). The migrated module helper supplements
that baseline with private environment preservation; it does not replace the recorder,
Settings adapter or ownership checks. See [WIP integration](../environment-variables-fixtures.md#wip-run-integration).
Use the [frozen assertion inventory](../assertion-inventories/environment-variables.json)
through `Import-PtAssertionInventory`: 29 functional scenarios have fixed child definitions
in the JSON inventory, not an agent-generated grouping. Ordinary startup aliases
Settings launch and normal profile reopen. Applied-edit coverage always includes both
originally-absent and existing-value fixtures; companion and conditional matrices remain explicit.
Control-character input is split by non-admin/System scope. Settings persistence requires
saved flag/toggle readback, not closing a borrowed Settings window; OOBE is observed separately.
Use the [reusable UI adapters](../environment-variables-fixtures.md#reusable-ui-adapters)
for row/menu resolution, guarded draft operations and full Applied/native value reads.
Keep scenario expectations and fixture ownership in the case driver, not in these observers.

## Prerequisites

- **Singleton editor:** Before testing, either confirm no editor process is running and
  launch a fresh test-owned instance, or explicitly reuse the existing editor with its
  HWND/PID/start time, token, UI baseline and restoration plan recorded. A second EXE
  launch is not an independent editor. Reuse does not authorize closing a borrowed window
  or prove fresh startup/elevation changes. Cases requiring exit/relaunch or writer shutdown
  for rollback need the no-existing-instance setup; resolve this prerequisite before
  mutation, and continue other compatible checks if it is unmet.

Before mutation, use [fixture mechanics](../environment-variables-fixtures.md) to preserve
raw Path/TMP, owned names/backups and affected files. Observe original active profile,
process integrity and window ownership privately; never assume an empty environment.
Capture borrowed PowerToys Settings with `Get-PtSettingsUiSnapshot` before navigation.
Windows Settings is a different application: the PowerToys adapter cannot preserve its
internal page. Do not reuse a pre-existing Windows Settings window for a theme change
unless its original page and native state have an explicit, verifiable restore path.

## Entry paths

| Intent | Entry | Destination / boundary |
|---|---|---|
| Settings launch/elevation choice | Search/navigate to Environment Variables in existing Settings; use its launch card. | Module settings -> Editor; observe actual resulting token, not title alone. |
| Downstream activation | Dot-source the pinned `scripts\pt-shared-events.ps1`; `Invoke-PtSharedEvent -Name 'EnvVars.Show'`. | Editor; not proof of Settings/companion entry. Admin event requires elevation authority. |
| Standalone discovery | Start installed editor without Runner arguments. | Editor; does not verify Runner enablement/integration. |
| Native comparison | Launch `%WINDIR%\System32\rundll32.exe` with `sysdm.cpl,EditEnvironmentVariables`; resolve new owned `#32770` HWND/process. | Native environment dialog; do not select a pre-existing user dialog by caption. |
| Companion entry | Invoke the actual Command Palette/Quick Access module or Settings command. | Editor or Module settings according to command; preserve companion state separately. |

## UI state-transition map

Settings, Editor and Native environment dialog can coexist. `Editor` is the main surface
without a modal; expanded groups remain in this state. `Editor closed` is not disabled.
Profile routes follow source handlers; discover live provider/arrival landmarks before
claiming their confirmation. One route's success does not replace another entry assertion.

| Current state | Trigger / condition | Next state | State landmarks |
|---|---|---|---|
| Module settings | Enable/disable | Module settings | Toggle and activation group |
| Module settings | Launch; enabled and token available | Editor | Titled editor, User/System groups |
| Editor closed | Supported launch; no existing instance | Editor | New owned process/window |
| Editor | Repeated launch; instance alive | Editor | Same window foreground |
| Editor | Expand User/System | Editor | Group child cards exposed |
| Editor | Permitted default-scope Add | Default draft | Name/Value, Save/Cancel |
| Default draft | Save valid input | Editor | Modal absent |
| Default draft | Cancel | Editor | Modal absent |
| Editor | Exact owned variable menu -> Edit | Variable draft | Edit name/value controls |
| Variable draft | PATH row options | PATH menu | Move/Delete/Insert items |
| PATH menu | Entry operation | Variable draft | List/text editor |
| PATH menu | Dismiss | Variable draft | Menu absent |
| Variable draft | Save valid input | Editor | Modal absent |
| Variable draft | Cancel | Editor | Modal absent |
| Editor | New profile / exact profile menu -> Edit | Profile draft | Name, enabled switch, Add variable |
| Profile draft | Add variable | Profile-variable flyout | New/Existing choices, Add/Cancel |
| Profile-variable flyout | Add eligible input/selection | Profile draft | Flyout closed; outer dialog open |
| Profile-variable flyout | Cancel | Profile draft | Flyout closed; outer dialog open |
| Profile-variable flyout | Dismiss | Profile draft | Flyout closed; outer dialog open |
| Profile draft | Outer Add/Save | Editor | Modal absent |
| Profile draft | Outer Cancel | Editor | Modal absent |
| Editor | Profile enabled switch | Editor | Main controls remain |
| Editor | Owned profile/variable Remove | Delete confirmation | Owned target title, Yes/No |
| Delete confirmation | Yes | Editor | Confirmation absent |
| Delete confirmation | No | Editor | Confirmation absent |
| Delete confirmation | Dismiss | Editor | Confirmation absent |
| Editor | Close owned window | Editor closed | Recorded window/process exits |

## Control locator and interaction index

Capture `winapp ui inspect --depth 14 -w $hwnd --json` into private memory inside a recorded
step, where `$hwnd` is the verified current window. Follow the
[private recording boundary](../environment-variables-fixtures.md#wip-run-integration)
instead of letting raw environment output enter the recorder. `selector` values expire
after UI changes. Explicit AutomationIds below come from XAML; `x:Name` seeds require
live discovery. Resource `x:Uid` is not an AutomationId.
Scoped CLI query arguments below use Control View and the selected tool's
[documented query support](../winapp-ui-testing.md#scoped-and-typed-queries). Supply the
current HWND with `-w`; adapt displayed text to the actual UI language.

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Navigate Settings | Settings | Search's child Edit; module result by accessible Name/role | SetValue; inspect result and its supported Invoke/Select pattern. |
| Toggle module | Module settings | Card seed `EnvironmentVariablesEnableToggleControlHeaderText`; local ToggleSwitch | Read state, Toggle/Invoke child, re-observe. |
| Choose admin launch | Enabled Module settings; Settings unelevated | Card seed `EnvironmentVariablesToggleLaunchAdministrator`; local ToggleSwitch | Toggle/read state; observe persistence separately. |
| Launch editor | Enabled Module settings | Card seed `EnvironmentVariablesLaunchButtonControl` | Try supported Invoke; retain ineffective attempt before foreground-guarded Click on current card. Observe editor arrival. |
| Locate User header | Current editor; card may be collapsed or expanded; CLI scoped-query support | CLI query arguments: `User --root UserVariablesExpander --type Button --class-name Microsoft.UI.Xaml.Controls.Expander` (`User` is the en-US text) | Run read-only `search` with `-w $hwnd --json`; require exactly one result with `hasMore=false`, then use its fresh selector. This identifies the header, not an expansion operation. |
| Locate System header | Current editor; card may be collapsed or expanded; CLI scoped-query support | CLI query arguments: `System --root SystemVariablesExpander --type Button --class-name Microsoft.UI.Xaml.Controls.Expander` (`System` is the en-US text) | Use the same scoped-query procedure and independently confirm a unique current match. Reading Add availability does not require expansion; row inspection and any expansion action need their own observation. |
| Read Add availability | Editor group header, collapsed or expanded | `type=Button`, `automationId=AddDefaultVariableUserBtn` / `AddDefaultVariableSystemBtn` | Read `IsEnabled` and record each result independently; no card expansion or input is required. |
| Add default variable | Editor group header, collapsed or expanded | `type=Button`, `automationId=AddDefaultVariableUserBtn` / `AddDefaultVariableSystemBtn` | Invoke only the permitted enabled scope; verify the resulting draft. |
| Fill default draft | Default draft only | AutomationIds `DefaultVariableNameTextBox`, `DefaultVariableValueTextBox`; local `PrimaryButton`/`SecondaryButton` | SetValue, read both fields/commit state, then Save or Cancel. |
| Open User variable menu | Expanded User group; registered owned name | Exact SettingsCard containing owned-name Text and its `VariableOptionsButton` | Use `Get-PtEnvUserVariableOptionsSelector` with fresh tree/journal/resource ID; Invoke returned selector. No flat first/last button. |
| Edit owned value | Variable menu -> Variable draft | `EditVariableMenuItem`; runtime `EditVariableDialogNameTxtBox` / `EditVariableDialogValueTxtBox` | Invoke Edit, then `Set-PtEnvOwnedVariableValue` with HWND/journal/resource ID/value. It guards target before input and Save. |
| Rename owned variable | Variable draft; both names registered/collision-checked | Current name Edit | Verify original before input and destination before Save. Value-only helper does not implement rename. |
| Remove variable | Exact variable menu | `RemoveVariableMenuItem`; confirmation title and local Primary/Close button | Invoke Remove; exact owned title required before Yes. No/dismiss is not deletion. |
| Open profile draft | Editor, exact profile owner | `NewProfileButton`; or local `ProfileOptionsButton` -> `EditProfileMenuItem` | Invoke; inspect intended profile/dialog before editing. Discover provider patterns live. |
| Fill/commit profile | Profile draft | `ProfileNameTextBox`, `ProfileEnabledToggle`; local Primary/Secondary buttons | SetValue/Toggle; outer Add/Save commits, outer Cancel does not. |
| Add profile variable | Profile draft | `AddProfileVariableButton`; flyout New/Existing segmented choices | Invoke; inspect current flyout and Select/Invoke the desired segment. |
| Fill/commit flyout | Profile-variable flyout | Source seeds `AddNewVariableName`, `AddNewVariableValue`, `ConfirmAddVariableBtn`, `CancelAddVariableBtn`; exact owned Existing-list row | Discover current IDs/patterns; SetValue or Select owned entry, Add/Cancel. Outer profile commit remains required. |
| Toggle profile | Editor, exact profile expander | Its local ToggleSwitch | Read state, Toggle and observe application separately. |
| Delete profile | Editor, exact profile expander | Local `ProfileOptionsButton` -> `RemoveProfileMenuItem` | Invoke; verify confirmation title before Yes. |
| Edit PATH entry | Variable draft, verified PATH owner | Row-local `VariableListEntryValueTextBox`, `PathEntryOptionsButton` | SetValue then move focus for LostFocus commit; re-resolve after each change. |
| Reorder/delete/insert PATH entry | Selected row's PATH menu | `MoveUpPathEntryMenuItem`, `MoveDownPathEntryMenuItem`, `DeletePathEntryMenuItem`, `InsertBeforePathEntryMenuItem`, `InsertAfterPathEntryMenuItem` | Invoke intended item; outer Save commits. No drag/drop assumption. |
| Remove PATH duplicates | Variable draft; included build, PATH owner | `RemoveDuplicatePathEntriesButton` | Discover availability, Invoke, then Save/Cancel separately. |
| Close owned surface | Tracked editor/native dialog | Current Close/Cancel or owned HWND close action | Normal close, wait for owned identity to exit. Editor close does not unapply profiles. |

### Read-out notes

- General `enabled.EnvironmentVariables` is boolean; module
  `properties.LaunchAdministrator.value` is serialized through `BoolPropertyJsonConverter`.
  Confirm shape on target; a missing/read-error field is not false. No JSON writes instead
  of Settings interaction.
- `profiles.json` is an array: `Id`, `Name`, `IsEnabled`, `Variables`, variable `Name`/`Values`.
  Async profile Save and registry application settle independently; poll boundedly rather
  than repeating Toggle.
- Read `HKCU\Environment` and
  `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment` with
  `DoNotExpandEnvironmentNames`, preserving kind. Inherited process environment is not
  fresh storage evidence or a raw rollback baseline.
- In `AppliedVariablesScrollViewer`, privately match owned-name Text/value within one
  row. Display expands references; storage can retain `%NAME%`. Compare private PATH
  composition locally and emit equality/hash receipts only.
- In native `#32770`, scope owned ListItem/value to User/System list. Raw storage does
  not replace either UI observation. Refresh only the owned comparison dialog if stale.

### Observation rules

Await structural arrival, then independently await the result. Record actual token,
foreground, DPI and geometry before physical input. Input/event success alone proves
neither entry route nor commit. Use only [scoped synthetic captures](../environment-variables-fixtures.md#privacy-safe-discovery-and-evidence);
never dump/capture full environment panels. Candidate images are not accepted references.

## Troubleshooting

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| Settings Invoke produces no editor | Inspect launch card/state/process; record foreground-guarded Click separately. | Event fallback cannot prove Settings launch. |
| Settings Click succeeds but no editor appears | Check for a Settings update notification covering the launch card; dismiss that notification through UI, then retry the unobstructed card. | A successful injected click does not prove the launch handler received it. |
| Enabled but activation controls stale | Preserve observation, navigate away/back, re-inspect. | UI refresh differs from persistence/Runner behavior. |
| Ambiguous row / mismatched edit name | Exact card ancestry plus pre-input/pre-save guard; Cancel mismatch. | Repeated ID is not unique; unowned write is a driver incident. |
| A persisted owned profile is missing from the scoped row resolver | Privately check whether its expander is offscreen. Reveal the left profile/default-variable viewport (the ScrollPattern containing `UserVariablesExpander`, not `AppliedVariablesScrollViewer`), then take a fresh tree before resolving the row/menu. | The profile resolver requires a visible owner; zero matches after scrolling elsewhere does not prove deletion. Never expand a hidden group merely to bypass the visibility guard. |
| Existing-variable segment has no Invoke/Selection pattern | Retain the failed Invoke, foreground-guard the exact editor HWND, click `AddExistingVariableSegmentedItem`, then independently observe `ExistingVariablesListView`. | A visible ListItem is not necessarily programmatically selectable. |
| A case ends with a profile dialog or variable flyout open | Cancel the owned inner flyout and outer draft, then verify the main `NewProfileButton` is available before another case starts. | Do not drive a background Add control or treat a subsequent modal-state error as an independent product failure. |
| Delete confirmation cannot be found by XAML class name | The live provider can expose it as a `Window` with class `Popup`, named by the exact owned target. Resolve Yes/No inside that popup and await its complete structure without repeating the gesture. | `ContentDialog` and an invented dialog AutomationId are not reliable live selectors. |
| A repeated Remove menu ID selects a hidden or stale item | After opening the exact owned row's menu, select the unique visible, enabled MenuItem by runtime identity before invoking it. | A flat AutomationId lookup can include cached menus from other rows. |
| PATH's named ItemsControl has no automation peer | Inspect the actual ScrollViewer children; pair each `VariableListEntryValueTextBox` with its adjacent `PathEntryOptionsButton`. Read empty entries through ValuePattern. | Do not require `EditVariableValuesList` to exist as an AutomationId or select a repeated row button globally. |
| Expected confirmation disappears or its tree is missing | Check the recorded editor PID/start time and HWND before another inspection. Correlate Application Error/Windows Error Reporting events, retaining timestamp, PID, faulting module and exception code. | A terminated editor is not merely a missing selector; recover explicitly as Diagnostic and preserve the originating Normal evidence. |
| Edited name lacks raw baseline | Stop mutations, retain journal; recover from known original raw value/type. | Inherited expanded-value equality cannot establish restoration. |
| Absent profiles file becomes `[]` | Validate complete owned transition using fixture procedure; quiesce editor before absence rollback. | Default `EditVariable` also saves profiles; this alone is not a product defect. |
| Launch choice seems ignored | Identify existing editor; interface foregrounds rather than changes token. | Do not kill user's instance or infer elevation from title. |
| Profile/UI/storage differ | Observe async settling, scope and external-change InfoBar before authorized reload. | Unobserved dependent actions have no independent product outcome. |
| System edit unavailable | Probe editor token/policy; ordinary User mode is read-only for System. | No implicit elevation/policy-change authorization. |
| Startup fault / missing deduplication | Verify bits, PR inclusion, locale/ACP and process evidence. | New main source does not change old-build applicability. |
| Restore conflict | Preserve data/journal; privately check baseline and owned receipt. | Do not blindly seal current state or overwrite external changes. |

## Fixtures and restoration

### Resource inventory

Preparation APIs and exact calls are in [fixture mechanics](../environment-variables-fixtures.md).

| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| Synthetic namespace via fixture helper | Profile/variable operations | Run-owned names/backups; register source/destination names on rename and any original active profile's affected variables before writes | UI undo, then guarded raw rollback if necessary; delete only names absent at baseline | Original absence/value/kind; each backup/profile compared to its own baseline |
| User Path/TMP; private machine Path/TMP | Before editor mutations | Raw text via `DoNotExpandEnvironmentNames`, `GetValueKind`, existence; no ordinary TMP writes | UI unapply first; typed HKCU rollback from snapshot if needed; no HKLM restore API | Exact raw text/kind, preserving empty versus absent; not inherited value |
| Module settings/profiles | Editor/Settings | Original bytes/absence, indirect `[]` write included | Close owned writer after UI undo; guarded restore | Exact bytes or original absence |
| Global settings/UI sidecars in fixture guide | Settings/OOBE | Original enabled map, placement, language/window state; only owned changes | UI restore and settling, then guarded bytes | Compare after last writer; preserve original Runner/Settings |
| Windows/processes and logs | Live checks | Original HWND/PID/start time/visibility; new logs distinguished from existing | Close owned windows; restore visibility; exact new-file/empty-directory cleanup only | Original processes survive; diagnostic appends reported separately |
| Companion/theme/locale fixture | Conditional matrix | Original pins/order/provider/theme/language; explicit authority | Reverse specific changes, never blanket reset | Original semantics plus byte guards |
| Encrypted local journal | Mutation | Run-owned TEMP directory outside evidence/archive | Delete exact journal only after final verification; retain on uncertainty | Sanitized receipts retained; no private payload in git/archive |

### Helper boundaries

The helper preserves registered files and HKCU string/expandable-string values, including
absence. It is not atomic and does not manage processes, clipboard, HKLM, directories,
timestamps or notifications. Scoped resolver/value-edit guards do not implement profile
rename/delete ownership. `Backup-PtModuleSettings` alone misses absence and profiles.

Use `New-PtEnvJournal` once before mutation; `Add-PtEnvTrackedResource` captures the original
state and returns a baseline fingerprint. After independently checking each owned UI change,
`Set-PtEnvOwnedPostState` records its current fingerprint and evidence. With writers
quiescent, `Restore-PtEnvJournal -JournalPath $journal` restores only baseline/owned states;
`Get-PtEnvResourceReceipt -JournalPath $journal -Id $resourceId` provides a read-only final
comparison. Resolve `$journal` and resource IDs from the original run, not a new snapshot.
See [complete calls and recovery branches](../environment-variables-fixtures.md#cleanup).
The caller must check the affected-resource inventory against the journal: this helper
cannot detect or reconstruct the original state of an unregistered write. Successful
receipts for registered resources do not settle an untracked incident.

Do not equate UI unapply with exact rollback: the product reads raw text into `Variable`
without retaining registry kind, then writes `ExpandString` when the text contains `%`,
otherwise `String`. A PowerToys backup variable therefore is not an independent record of
the original type. Exact restoration uses the captured raw text **and** kind with
`RegistryKey.SetValue(name, value, kind)`; original absence requires `DeleteValue`, not
an empty string. Do not substitute `$env:TMP`, `$env:Path`, `setx`, or guessed defaults.

### Restoration order

1. Cancel drafts; UI-unapply the owned test profile, then delete owned fixtures. Restore any
   originally active profile only if its full affected-variable/backup footprint was captured.
   Otherwise do not displace that profile in the first place. Record this product behavior
   before cleanup; recovery is not a substitute PASS.
2. Await asynchronous environment and profile-file writes. Observe and seal each verified
   owned transition, including UI undo and incidental `profiles.json` creation. Restore
   Settings through UI and close only owned editor/comparison windows; establish quiescence.
3. Call `Restore-PtEnvJournal` with the original journal. It restores raw value/type/existence
   and file bytes/absence. Missing baselines, unknown writes or conflicts stop recovery;
   never adopt current values as the original baseline or bypass its guard.
4. If raw rollback wrote persistent environment values after the last UI notification, send
   the documented `WM_SETTINGCHANGE` broadcast with Unicode `"Environment"` **after** those
   writes, using [the notification contract](../environment-variables-fixtures.md#environment-change-notification).
   This is separate from the existing helper; do not assume opening/confirming an unchanged
   Windows dialog performs it. Record failure separately from restored registry state.
5. Restore original visibility/foreground. Any required authorized restart or reload precedes
   final read-only comparison; account for its writes. Do not kill/restart user processes
   to manufacture a fresh environment or loop restarts after declaring cleanup complete.

Express this order in the common `CleanupPlan`: owned UI undo/quiescence before the journal
rollback, then notification and final comparison. Borrowed PowerToys Settings and desktop
state are restored by the common template; the journal does not own those surfaces.

### Restoration verification

After the final writer, compare every registered resource's receipt with its saved baseline:
existence, case-sensitive raw text and kind for values; byte identity/absence for files.
Keep empty strings distinct from missing values and PATH text/order unchanged. Check
profile IDs/content/enablement, backup baselines, original process state and owned-process
exit separately. Helper counts or row disappearance are insufficient.

Report persistent-state restoration, notification result and any required consumer refresh
separately. A broadcast does not rewrite every running process's environment block; a new
child of an old shell can still inherit stale values. Use registry reads for the storage
oracle and a known refreshed parent or explicitly constructed environment for consumer
checks. With no trustworthy pre-change raw baseline, retain recovery evidence and report
exact restoration as unproven; defaults or expanded-path equality cannot repair that gap.
Delete the private journal only after the required verification succeeds.

## References

### Source citations

Repository-relative paths; symbols anchor behavior across line movement:

- `src\modules\EnvironmentVariables\EnvironmentVariables\Program.cs`:
  `Main`, `AppInstance.FindOrRegisterForKey("PowerToys_EnvironmentVariables_Instance")`;
  a second standalone instance exits instead of creating an independent editor.
- `src\modules\EnvironmentVariables\EnvironmentVariablesModuleInterface\dllmain.cpp`:
  `launch_process`, event waiters, `bring_process_to_front`.
- `src\settings-ui\Settings.UI\ViewModels\EnvironmentVariablesViewModel.cs`:
  `Launch`, `LaunchAdministratorEnabled`; page at `SettingsXAML\Views\EnvironmentVariablesPage.xaml`.
  `src\settings-ui\Settings.UI.Library\BoolPropertyJsonConverter.cs`: `Read`/`Write`.
- `src\modules\EnvironmentVariables\EnvironmentVariables\EnvironmentVariablesXAML\App.xaml.cs`:
  `OnLaunched`; sibling `MainWindow.xaml.cs`: constructor/`WndProc`.
- Under `src\modules\EnvironmentVariables\EnvironmentVariablesUILib\`:
  `EnvironmentVariablesMainPage.xaml`/`.xaml.cs` (dialogs, menus, commit handlers);
  `ViewModels\MainViewModel.cs` (`PopulateAppliedVariables`, `EditVariable`, `SaveAsync`);
  `Models\ProfileVariablesSet.cs` (`Apply`, `UnApply`);
  `Helpers\EnvironmentVariablesHelper.cs` (raw registry, validation, backups);
  `Helpers\EnvironmentVariablesService.cs` (profile array persistence).
- [Checklist](../release-checklist/environment-variables.md),
  [fixture API/regressions](../environment-variables-fixtures.md),
  [shared UI mechanics](../winapp-ui-testing.md).

### Windows restoration references

- [Raw reads without expanding references](https://learn.microsoft.com/en-us/dotnet/api/microsoft.win32.registryvalueoptions?view=net-10.0),
  [registry value kinds](https://learn.microsoft.com/en-us/dotnet/api/microsoft.win32.registrykey.getvaluekind?view=net-10.0),
  [explicitly typed writes](https://learn.microsoft.com/en-us/dotnet/api/microsoft.win32.registrykey.setvalue?view=net-10.0),
  [value deletion](https://learn.microsoft.com/en-us/dotnet/api/microsoft.win32.registrykey.deletevalue?view=net-10.0).
- [Process environment inheritance](https://learn.microsoft.com/en-us/windows/win32/procthread/environment-variables),
  [WM_SETTINGCHANGE](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-settingchange),
  [SendMessageTimeoutW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendmessagetimeoutw).
- [Why setx is unsuitable for exact rollback](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/setx):
  reference expansion and documented value truncation.
