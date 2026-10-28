# Quick Accent fixture integration

Use the [profile](modules/quick-accent.md), [checklist](release-checklist/quick-accent.md) and
existing [recorder](recording-workflow.md). These adapters do not establish product outcomes.

## Run and resource wiring

Load `Import-PtAssertionInventory` from `scripts\pt-assertion-inventory.ps1`:

```powershell
$inventory = Import-PtAssertionInventory `
    -InventoryPath "$skill\references\assertion-inventories\quick-accent.json" `
    -ChecklistPath "$skill\references\release-checklist\quick-accent.md"
# Pass $inventory.Items unchanged to templates\verification-run.ps1, -Module 'Quick Accent'.
```

Declare `ResourcePlan` and real `CleanupPlan` steps before mutation, using
[session safety](session-safety.md). The template records both inventory inputs, captures
declared Settings windows and rejects run-local regrouping. Conditional requirements remain
in the child descriptions; missing fixtures affect those children, not independent observations.
Keep all 20 scenarios and 57 children in a full Scenario A run.

Declare only resources actually needed:

| Resource kind | Declaration / operation |
|---|---|
| Settings | Original main `Hwnd`; shared snapshot before any navigation. |
| File | Explicit restore step for Quick Accent settings/usage and attributed General changes. |
| Window | Owned Notepad/guide/text windows, or borrowed originals; actual identity registration required. |
| Process | Dedicated Latin fixture/recorder executable with an actual Quiesce step. |
| Clipboard | Only for copy cases; Clipboard-phase restore before releasing Settings/provider. |
| Other | Module logical lifecycle and desktop comparison, with explicit cleanup. |

Use `Invoke-PtVerificationCase` for execution, including the module helper. Its callback is
the recorded boundary; `Invoke-PtWinApp` records nested CLI calls. Freeze the fixture source
as an extra input, since top-level helper capture does not include `scripts\fixtures`.
Keep private baseline payloads outside report artifacts and recorder arguments. Pass private
recovery file paths, not deserialized originals, into recorded callbacks.

## Owned input

Use `New-PtNotepadFixture` / `Remove-PtNotepadFixture` from the
[owned-fixture helpers](owned-fixtures.md), including exact tab ownership and explicit localized
discard consent. Modern Notepad can reuse a process; do not close its other tabs.

For Latin, same-process/different-window and exclusion comparisons, the checked-in
`scripts\fixtures\quick-accent-text.ps1` supplies two WinForms TextBoxes with IME disabled
only in those owned controls. Launch a declared dedicated PowerShell process through
`Start-PtOwnedProcess`, using `-NoProfile -STA -File`, a unique `-Title` and a new
`-OutputFile` in the run workspace. Observe the identity receipt and both responsive HWNDs;
verify PID/start time and medium integrity, then register every created native sibling.
Resolve `OwnedText1`/`OwnedText2` beneath the corresponding form.

Close the two forms normally using the tracked-window/owned-process contract. A failed
normal close is not permission to force-kill the host. Verify process exit and remove only
its owned receipt. Synthetic Latin observations never replace baseline Notepad observations.

The module-specific gesture uses shared `Invoke-PtHeldKeys` and `Send-PtChord`:

```powershell
Invoke-PtQuickAccentGesture -WindowHandle $ownedEditorHwnd -KeyCode 0x41 `
    -TriggerCode 0x20 -DelayMs $observationDelay -Observe {
        param($editorIdentity)
        # Observe/navigation while the letter is held; exact editor text is read afterward.
    }
```

Before calling, resolve the exact focused editor, prepare the required activation mode and
confirm no pre-existing gesture. Omit TriggerCode for press-and-hold. DelayMs is a driving
interval, not a readiness oracle; timing cases need timestamped input and observations.
The helper does not foreground a window or replay a failed gesture. The callback may deliberately
change focus for a cancellation case; shared finally releases owned keys regardless of that change.
Guard the exact foreground before any additional input inside the callback.

## Character-dialog ownership

Call `Invoke-PtQuickAccentCharacterDialog -WindowHandle $settingsHwnd
-ManageButtonName $actualLocalizedName -Action $dialogAction`. It refuses an existing modal,
invokes Manage once and observes `CharacterSetsSearchBox`. The callback receives that search
element and Settings identity; resolve sibling controls within the same owned draft.
On return/error it cancels only the same surviving draft, never an unidentified replacement.
Ambiguity/provider failures propagate; cleanup errors retain the originating action error.

For this dialog's search, physically edit the TextBox under CharacterSetsSearchBox and
observe both query and filtered rows. Select each language's owning ListItem through
AddToSelection/RemoveFromSelection, not Select. Virtualized rows still require realization.
Save/Cancel are explicit callback operations; neither helper return nor selected count is
a product judgment.

## Files, lifecycle and Settings restoration

Preserve module settings and usage before the first gesture, including original absence.
Use `Get-PtFileSnapshot` for shared-access, stable byte reads and
`Restore-PtFileSnapshot -ExpectedState` for existing-file guarded rollback.
For original absence or product deletion (sorting off can delete UsageInfo.json), use the
shared [directory snapshot](directory-snapshots.md) on the bounded QuickAccent directory,
with explicit `OwnedRelativePaths @('settings.json','UsageInfo.json')`.
Do not pass an absent file to existing-file guarded restore or pre-create it to satisfy that API.

The directory adapter requires a quiescent bounded root. Establish that condition before capture;
do not disable the module first and call its shutdown-rewritten usage the original baseline.
If there is an active gesture/writer or unsupported root, preserve it and defer affected mutations.
Record root/directory existence too; OwnRoot applies only when this fixture owns its creation.
Private snapshots are not permission to overwrite unexplained external changes.

Use `Get-PtModuleLifecycleSnapshot` with Resident model, key `QuickAccent`, page
`QuickAccentNavItem`, toggle `Toggle_QuickAccent`, actual installed process name/path and
no invented activation event. Its native Ready is not toolbar readiness.
Restore UI settings first, then disable through `Set-PtModuleEnabled` to quiesce the actual
worker. Navigate away from the cached Quick Accent page before exact file rollback.
Record the known owned post-state after attributed writes, not after an unexplained conflict.
Restore original enablement through `Restore-PtModuleLifecycleSnapshot`, then compare storage
again after final startup. Preserve normal product logs; do not loop restarts to hide drift.

Use `Get-PtSettingsUiSnapshot` / `Restore-PtSettingsUiSnapshot` for the original main page,
placement and supported named controls. On first entry to Quick Accent, preserve its local
`Read-PtSettingsUiState` if its expanders/scroll will be changed; restore that page's state with
`Set-PtSettingsUiState` and compare with `Test-PtSettingsUiStateMatch -AllowWinUiFloatReadback`
before the original main snapshot is restored. Preserve its native placement with the shared
window snapshot before applying scroll. Unsupported unnamed state remains a real limitation.
There is no Quick Accent-specific scroll tolerance or substitute surface snapshot.

Restore pointer while an owned ordinary interaction window remains available, before its
closure can reactivate an elevated app. Then close owned text fixtures, restore original foreground
and perform read-only final comparisons. No test gesture follows final usage rollback.

## Clipboard copy

Use the [shared clipboard keeper](clipboard-guard.md), not a module-specific guard:
`New-PtClipboardSession`, `Invoke-PtClipboardWrite`, Restore, `Assert-PtClipboardRestored`,
then Dispose. Identify the actual Settings writer PID/start time; observe the copy's completion
inside its one action before sealing. Keep originals/private formats out of evidence.

Capture supported payloads before clicking either guide character. Independently account for
history/cloud stores; the keeper does not restore those. Unsupported formats or unavailable
history preservation require an authorized isolated fixture or a child-specific limitation.
Restore before closing the guide/Settings provider. On failure retain the keeper and recovery
receipt, do not clear clipboard, rebaseline or replay the copy. Browsing/filtering/hover remain
independently executable.

## Module source contracts

Paths are repository-relative; use the tested build's corresponding source inputs.

- `src\modules\poweraccent\PowerAccentModuleInterface\dllmain.cpp`: `launch_process`, `enable`, `disable`.
- `src\modules\poweraccent\PowerAccentKeyboardService\KeyboardListener.cpp`: `OnKeyDown`, `OnKeyUp`,
  `ForegroundEventProc`, `ForceReset` define activation, cancellation and ownership.
- `src\modules\poweraccent\PowerAccent.Core\PowerAccent.cs`: `GetCharacters`, `ProcessNextChar`,
  `SendInputAndHideToolbar`; `PowerAccent.Core\Tools\CharactersUsageInfo.cs`: `Clear`, `Save`
  (beneath the same module root) define ordering and usage side effects.
- `src\settings-ui\Settings.UI.Library\PowerAccentProperties.cs`: serialized fields.
- `src\settings-ui\Settings.UI\SettingsXAML\Views\PowerAccentPage.xaml.cs`:
  `CharacterSetsSearchBox_TextChanged`, `SelectAllCharacterSetsCheckBox_Click`,
  `CharacterSetsDialog_PrimaryButtonClick` define draft selection and filtering.
- `src\settings-ui\Settings.UI\ViewModels\PowerAccentReferenceGuideViewModel.cs`:
  `UpdateFilteredGroups`, `BuildGroups` define guide set-level filtering/order.
- `src\settings-ui\Settings.UI\SettingsXAML\Views\PowerAccentReferenceGuideWindow.xaml.cs`:
  `CharacterButton_Click` copies underlying text, not the dotted-circle display aid.
