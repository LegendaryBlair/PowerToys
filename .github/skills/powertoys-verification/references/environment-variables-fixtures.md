# Environment Variables fixture mechanics

Requires Windows and PowerShell 7. Dot-source
`scripts\pt-environment-variables-state.ps1` from the pinned verification skill.
No function launches the product or changes a setting to prepare a passing result.

## WIP run integration

Use the WIP `templates\verification-run.ps1` with explicit `Items`, `ResourcePlan` and
`CleanupPlan`; do not copy a prior report's run-local controller or its report generator.
Load the 29-scenario frozen inventory with `Import-PtAssertionInventory`; do not derive
children from old tables or reuse an archived run's grouping:

```powershell
$inventory = Import-PtAssertionInventory `
    -InventoryPath "$skill\references\assertion-inventories\environment-variables.json" `
    -ChecklistPath "$skill\references\release-checklist\environment-variables.md"
$items = $inventory.Items
```

The template rejects changed Items before run creation and snapshots the inventory/checklist.
All original source conditions remain, including separate originally-absent and existing-value
applied-edit variants. Old archives keep their original inventories/verdicts.

Keep all helper imports in the same pinned WIP skill root. `Get-PtVerificationInputs`
automatically includes `pt-environment-variables-state.ps1`; explicitly include this fixture
guide, the profile, checklist and actual driver in the run inputs. Use
`Invoke-PtVerificationCase`, `Add-PtVerificationObservation` and the normal cleanup evidence
APIs, not a second report format.

Use the common ownership and Settings adapters for process/window lifetimes:

| Resource | WIP integration |
|---|---|
| Borrowed PowerToys Settings | Declare `Kind=Settings` with its exact HWND in `ResourcePlan`, before navigation. The template captures/restores supported UI state and desktop placement. |
| Owned editor/native comparison windows | Register actual owned creations through the existing resource-session APIs before closing; launching a singleton does not confer ownership of a pre-existing editor. |
| Files and named HKCU values | Keep raw payloads in the module's private DPAPI journal. Declare each touched file as `Kind=File`, and variable state as `Kind=Other`, with the corresponding cleanup step. |
| Companion, theme and locale | Declare only the authorized resources actually touched, including their original enablement and UI state. The PowerToys Settings adapter does not restore Windows Settings navigation. |
| Public recording | Record sanitized resource IDs, existence/type/equality outcomes and reviewed synthetic crops. Never serialize a decrypted journal, raw PATH/TMP, full environment tree or private values as step arguments, output or artifacts. |

`Invoke-PtWinApp` normally archives its output and errors. For this module's sensitive
reads, use its `-SkipRecording` mode **only inside an outer recorded step** that keeps raw
output in memory, applies the allowlist below, and replaces any private error payload with
a sanitized explicit error. Record the actual source/operation and safe observations.
The migrated `Set-PtEnvOwnedVariableValue` already keeps its internal CLI responses private;
invoke it inside a recorded step with only owned synthetic input values. Assert the exact
window identity before the step. These privacy exceptions are not permission to omit actions
or failures from the run history.

The journal is a private backup, not an input/evidence artifact. The cleanup step below
connects it to the common plan; supply the referenced quiescence step and separate notification
and final verification steps for the run's full scope:

```powershell
$journalCleanup = @{
    Id='env-state'; Phase='Files'; DependsOn=@('owned-writers-stopped')
    Arguments=@($journal, $baselineReceipts)
    Action={
        param($privateJournal, $originalReceipts)
        Restore-PtEnvJournal -JournalPath $privateJournal | Out-Null
    }
    Verify={
        param($privateJournal, $originalReceipts)
        if (-not $originalReceipts.Count) { throw 'Missing original resource receipts.' }
        $matches = $true
        foreach ($baseline in $originalReceipts) {
            $current = Get-PtEnvResourceReceipt -JournalPath $privateJournal -Id $baseline.Id
            if ($current.Exists -ne $baseline.Exists -or
                $current.Fingerprint -cne $baseline.Fingerprint) { $matches = $false }
        }
        $matches
    }
}
```

Keep original receipts across same-run recovery. The common plan records a failed restore
and withholds dependent steps; it must not delete the private journal on a conflict.
Only remove the exact journal after the final required comparisons and notification pass.
No cross-run state protocol is needed.

For a template `-Resume`, deserialize the saved `run-resource-plan.json` rather than
reconstructing its hashtables in a new process. The current template compares serialized
plan text, so a different property order can reject an otherwise equivalent plan. Retain
the original private journal and receipts; do not take replacement baselines to satisfy resume.

### Shared fixtures and distinct assertions

Reuse a journaled User variable across add/edit/delete and P1/P2 across related profile
transitions; recheck each scenario's starting state. Record each native/Applied/storage
observation at its own transition. Later cleanup or another surface does not fill a missing
assertion. Validation reuses a disabled fixture and resets each draft between input rows.
Keep every dialog/input row even when the frozen child covers a whole matrix.
Control-character matrices have separate non-admin and System scenarios: record the User/
profile rows even without elevation, and disposition only the System scenario for that
missing prerequisite. P13 persistence checks saved disabled/enabled flags against the
Settings toggle after each save; do not close borrowed Settings. OOBE still needs its own
owned-window setup and observations.

For `EV-APPLIED-EDIT`, register two source variables, absent rename destinations and every
prospective backup before writes. One source is absent before profile application; the other
is created through UI with `original` before being overridden. Preserve these **pre-profile**
expectations separately from the run's original cleanup baseline. Editing the absent-source
variant must not create a backup of its own old applied value; rename/unapply must not
resurrect that value. Record any residue before explicit cleanup. The existing-source variant
must retain and restore `original`. Neither variant is a substitute for the other.

Prepare Command Palette once for its entry/pin/fallback scenario and restore its original
enablement, pins/order/provider settings and UI state. A disabled companion can be enabled
through shipped UI when its full restoration is supported; if preparation is not safe,
state the missing preservation capability rather than reporting an unavoidable product limit.
Quick Access has its own scenario and does not depend on Command Palette preparation.

## Reusable UI adapters

Dot-source `scripts\pt-environment-variables-ui.ps1`. It reuses the common UIA, exact-window
identity and resource-session helpers plus the private journal. Imports never launch UI.
Use complete current `Get-PtWindowIdentity` targets, not saved HWNDs from an earlier process.

| API | Contract |
|---|---|
| `Resolve-PtEnvUiRow -Tree -Scope -Name [-ProfileName]` | Resolve User/System variable or profile/profile-variable within its actual owner subtree. Variable names use ordinal case-insensitive matching; profile identity stays exact. Missing/ambiguous controls throw, never choose the first. Tree and returned nodes are private. |
| `Open-PtEnvOwnedMenu -Target -JournalPath -ResourceId [-ProfileName]` | Open the registered variable's row menu once; no modal may still be active. Reveal an already resolved offscreen row once and re-resolve its control before invoking. Profile-only variant takes `-OwnedProfileName`, whose fixture ownership the caller establishes. |
| `Invoke-PtEnvMenuAction -Target -AutomationId` | Invoke only the unique visible enabled Edit/Remove variable/profile item. Use immediately after opening the exact owned menu; hidden cached peers do not count. |
| `Read-PtEnvDraft -Target -Kind -ExpectedName` | Check a live AddVariable/EditVariable/Profile/ProfileVariable/Confirmation surface and its own buttons; read actual ValuePattern text, including empty text without accessible-label fallback. Structural containers need not have interactive selectors. Confirmation is an exact-title Popup, not an invented dialog AutomationId. Output contains private text. |
| `Set-PtEnvDraftField -Target -Kind -ExpectedName -Field -Text` | Set Name or Value through ValuePattern once, then return actual input/readback and commit enabled state. Supports long input without command-line length limits; rejected/truncated input is not silently accepted. Does not Save. |
| `Complete-PtEnvDraft -Target -Kind -ExpectedName -Decision Commit/Cancel` | Re-read target and button state before one action. Refuse outer profile completion while its inner variable flyout remains open. No automatic dismissal, restart, or result judgment. |
| `Read-PtEnvAppliedVariable -Target -Name` | Read full managed UIA TextBlock pairs from the known nonvirtualized Applied ItemsControl. Match `PATH`/`Path` consistently; preserve actual value casing/order/empty text. Invalid/incomplete pair structure is an error, not absence. |
| `Read-PtEnvNativeVariable -Target -Creation -Name [-Scope User/System]` | Require the owned dedicated native-dialog creation and registered identity. Use winapp's native provider for lists `402` (User) / `400` (System). Even its Name property can clip generated backup names: for names beyond the 259-character authoring limit, independently check candidate prefixes in the native Edit name field. A prefix alone never proves identity. Read full text or ordered PATH entries, cancel every child without saving in `finally`. Missing properties, ambiguous names and unsupported providers do not prove absence. |
| `Compare-PtEnvUiValue -Observation -ExpectedPresent [-ExpectedValue]` | Produce only Status/Present/Complete/Matches/Method. Missing observation is not a mismatch; an observed different value remains a complete mismatch, not an infrastructure failure. |

All live calls belong **inside an outer recorded step** with explicit operations and input
source snapshots. `Read-PtEnvPrivateTree`, draft results, and reader values must remain in
private memory; archive only sanitized comparisons and approved synthetic crops. Expected
values may not come from the same UI read being checked. No registry fallback supplies
missing native/Applied text. These helpers do not seal post-states or assign PASS/FAIL.

```powershell
# Inside the caller's recorded case step; identity and expected value already established.
$observed = Read-PtEnvAppliedVariable -Target $editorIdentity -Name $ownedName
$receipt = Compare-PtEnvUiValue -Observation $observed -ExpectedPresent $true -ExpectedValue $expected
$receipt # Safe for the outer recorder; do not output $observed.
```

For Add drafts start with `ExpectedName=''`; after setting Name, use its **actual readback**
for further draft operations. Commit only after the case has verified its intended name,
value and enabled state. Validation cases may deliberately leave commit disabled and Cancel.
The variable journal still needs Path/TMP and affected-file snapshots before mutations.
Profile fixture ownership, actual product postconditions and exact cleanup remain the
caller's responsibilities. No speculative replay is performed after an action error.

Run `scripts\tests\Test-PtEnvironmentVariablesUi.ps1` for synthetic provider coverage of
row scoping, hidden duplicates, modal guards, private errors and complete native values.
Synthetic tests cannot certify live provider behavior; retain explicit live-case results
and environment blockers separately.

## Private preservation

Create a unique recovery directory under local TEMP, **outside the report workspace**,
before the first mutation. Never take a post-incident snapshot and call it the baseline.
The following complete sample registers one file and one absent, collision-checked
synthetic User variable. Resolve `$skill` to the pinned skill root and `$ownedName` to
the run's synthetic variable name before using it.

```powershell
. "$skill\scripts\pt-environment-variables-state.ps1"
$private = Join-Path $env:TEMP "pt-env-private-$([guid]::NewGuid().ToString('N'))"
[IO.Directory]::CreateDirectory($private) | Out-Null
$journal = Join-Path $private 'recovery.dpapi'
New-PtEnvJournal -JournalPath $journal
$baselineReceipts = @(
    Add-PtEnvTrackedResource -JournalPath $journal -Id 'profiles' `
        -FilePath "$env:LOCALAPPDATA\Microsoft\PowerToys\EnvironmentVariables\profiles.json"
    Add-PtEnvTrackedResource -JournalPath $journal -Id 'owned-variable' -UserVariableName $ownedName
    Add-PtEnvTrackedResource -JournalPath $journal -Id 'safety-user-path' -UserVariableName 'Path'
    Add-PtEnvTrackedResource -JournalPath $journal -Id 'safety-user-tmp' -UserVariableName 'TMP'
)
```

Retain these sanitized receipts in the run's evidence for final comparison. This sample
registers four resources only, not a complete suite footprint: append the initial receipts
for every additional registered file/name before changing it. Keep the encrypted journal
under the same Windows user for recovery; DPAPI does not make it a portable backup.

The Path/TMP snapshots are mandatory before any editor mutation, including ordinary
User-variable cases. They are not permission to edit either variable. Never use a
process-inherited expanded value as a substitute for a missing raw registry baseline.
When resuming, derive original-value expectations from the registered journal resource,
and assert that an existing string resource actually supplies a string. Windows variable
names are case-insensitive, but a recovered JSON dictionary can use case-sensitive keys:
an unchecked `Path` lookup can miss `PATH` and turn an existing baseline into a false
absence expectation. Treat that as an observer error, not a product failure.
Register every prospective owned variable, rename source/destination, generated backup name, Path override and
affected file before the first action. IDs are run-local labels, not product selectors.
Preserve the baseline across retries; duplicate registration throws. Read raw machine
Path/TMP privately for comparison only; this helper intentionally cannot restore HKLM.
Applying a test profile also unsets any currently applied profile. Capture that original
profile's variables and backup names, plus its metadata/enabled state, before allowing
this transition; otherwise use an isolated fixture or defer profile-application cases.

After a shipped UI action, independently validate the complete semantic diff: only
the expected profile/settings fields or tracked names changed. Then obtain and seal
the resource's receipt:

```powershell
$receipt = Get-PtEnvResourceReceipt -JournalPath $journal -Id 'profiles'
Set-PtEnvOwnedPostState -JournalPath $journal -Id 'profiles' `
    -Fingerprint $receipt.Fingerprint -ActionEvidence 'artifacts\action-001.json'
```

The action evidence must actually exist and describe the ownership check. Sealing a
hash is **not** proof of ownership; do not blindly seal every changed file after a run.
Interrupted/unexplained changes remain conflicts for review. Journals contain encrypted
original bytes/raw values using Windows current-user DPAPI; do not print decrypted
objects or copy journals to OneDrive/report/git. Encryption is not an OS sandbox.

## Exact row and dialog ownership

Expand the User group, capture a fresh private UI tree, then call
`Get-PtEnvUserVariableOptionsSelector -Tree $tree -JournalPath $journal -ResourceId
'owned-variable'`. It requires exactly one User expander, exactly one SettingsCard
containing the registered name as Text, and exactly one options button inside that card.
Invoke the returned selector, then `EditVariableMenuItem` in the same current HWND.
Never pick the first/last `VariableOptionsButton` from a flat tree.

Use `Set-PtEnvOwnedVariableValue -WindowHandle $hwnd -JournalPath $journal -ResourceId
'owned-variable' -Value $newValue` for value edits. It checks the dialog's actual name
before typing and again before Save, and refuses without registered Path/TMP baselines.
A mismatch means cancel; do not substitute another row or force Save. A successful
receipt proves guarded input only; independently observe persisted/UI results and seal
only verified writes. The helper supports value-only edits; rename and profile-row
operations must separately check their original and destination identities.

Before confirming Remove, verify the ContentDialog title is the exact owned name.
Resolve the current dialog and its PrimaryButton rather than reusing the last dialog's
selector. Re-resolve after scrolling, expansion, navigation and process recreation.

## Cleanup

Separate **product undo**, **exact persistent-state rollback**, and **consumer notification**.
The same visible path can have different raw text or registry kind; matching what a
process sees is not sufficient.

### Product undo and writer quiescence

In `finally`, cancel drafts, unapply the owned test profile and delete owned fixtures
through the shipped UI. If an original active profile was displaced, restore it only
under the complete baseline plan described above. Record actual product undo behavior
before any direct cleanup; manually recovering state must not turn a failed undo into PASS.

`ProfileVariablesSet.UnApply` restores the backed-up **text**, but the product model does
not preserve the original registry kind. `SetEnvironmentVariableFromRegistryWithoutNotify`
writes `ExpandString` when text contains `%`, otherwise `String`. Therefore neither
successful UI unapply nor a `<name>_PowerToys_<profile>` variable proves exact type recovery.

Wait for asynchronous apply/unapply and `SaveAsync` writes; observe and seal only verified
owned post-states, including UI reversals. Restore original Settings through UI, then close
only owned editor/comparison windows. Preserve originally running processes/windows and
check PID/start time before closing any owned process. Establish quiescence for each
tracked file/value; do not restore files underneath an uncontrolled writer.

### Exact persistent-state rollback

Use the original journal. Its underlying Windows/.NET operations are:

| Captured baseline | Required operation | Verification |
|---|---|---|
| Value existed as `String` or `ExpandString` | Read with `GetValue(name, null, DoNotExpandEnvironmentNames)` and `GetValueKind`; restore with the three-argument `SetValue(name, rawText, savedKind)` | Same existence, raw text and kind, including empty text and literal `%NAME%` references |
| Value was absent | Delete that owned value with `DeleteValue(name, false)`, not the containing key | Value name absent; an empty string is not equivalent |
| File existed | Restore captured bytes after writer quiescence | Same bytes; JSON equivalence alone does not restore formatting/order/encoding |
| File was absent | Delete only the attributed run-created file | Original absence; do not replace it with an empty object/array |

The existing helper implements these operations with conflict checks. After each UI
write/reversal, independently validate ownership before using `Set-PtEnvOwnedPostState`;
capture-and-seal is not an automatic approval of whatever is on disk.

At the cleanup point, with `$journal` from the original setup:

```powershell
$restorationReceipts = @(Restore-PtEnvJournal -JournalPath $journal)
```

Only states equal to the captured baseline or the sealed owned post-state are accepted.
An initial conflict aborts before any writes; each write is rechecked, but concurrent
changes can still race. Failures partway through may leave partial recovery; retain the
journal and original error. Receipts cover only registered resources, not all user state.
Never defeat a conflict by recreating the journal or sealing an unexplained current value.

Do not use `$env:TMP`, `$env:Path` or another process's environment as a raw backup.
`Environment.SetEnvironmentVariable` does not expose a registry-kind parameter.
`setx` is not an exact-restore tool: its documented behavior expands references and can
truncate assigned values at 1024 characters. Do not reimport an entire environment key
over concurrent changes to recover one owned value.

### Environment-change notification

`Restore-PtEnvJournal` does **not** broadcast changes. Product UI apply/unapply calls
`EnvironmentVariablesHelper.NotifyEnvironmentChange`, but a later raw registry rollback
requires its own notification after the last write. Do not assume opening and confirming
an unchanged native Environment Variables dialog sends that notification.

The documented native operation for a run-local notifier is `SendMessageTimeoutW`:

| Argument / result | Required handling |
|---|---|
| `hWnd` | `HWND_BROADCAST` (`0xffff`), not a cached editor HWND |
| `Msg` | `WM_SETTINGCHANGE` (`0x001a`) |
| `wParam` | Zero for an application-originated message; do not copy PowerToys' internal self-notification sentinel |
| `lParam` | Pointer to a live UTF-16 string `"Environment"` for the duration of the call |
| `fuFlags` / `uTimeout` | `SMTO_ABORTIFHUNG` (`0x0002`) with a recorded finite per-window timeout; the broadcast's total wait can exceed that timeout |
| Return / error | Clear last-error before calling; zero means failure/timeout even if last-error remains zero. Capture the return/error without discarding it. Nonzero does not provide a per-window delivery/refresh report. |

This is the Windows API contract, **not an existing function in the checked-in helper**.
A run requiring raw recovery must supply and check its notifier before mutation, or
explicitly retain notification as incomplete; do not fabricate a successful broadcast.
Do not write environment values again merely to trigger a notification. No elevation,
shell termination or reboot is authorized by this recipe.

A notification lets listening applications reload; it does not replace every existing
process's environment block. A child normally inherits its parent's block, so even a
new child of the old automation shell can carry stale values. Registry reads establish
persistent restoration. Consumer checks require a known refreshed parent or a deliberately
constructed environment; changing the test shell's environment alone proves neither.
Record notification failure separately from successful registry restoration.

### Final verification and missing baselines

After notification and any already-required authorized restart/reload have finished,
compare the saved **initial** receipts without writing state again:

```powershell
foreach ($baseline in $baselineReceipts) {
    $current = Get-PtEnvResourceReceipt -JournalPath $journal -Id $baseline.Id
    if ($current.Exists -ne $baseline.Exists -or $current.Fingerprint -cne $baseline.Fingerprint) {
        throw "Final restoration mismatch for resource '$($baseline.Id)'; retain the journal."
    }
}
```

`$baselineReceipts` must include every registered resource; the four-resource setup sample
alone cannot cover later additions. The fingerprint covers existence plus raw text/kind
or file bytes. Verify original profile identities/content/enablement, expected backup
presence and owned-window/process cleanup separately. Report persistent-state equality,
notification outcome and required consumer observations independently.

If an original raw value/type was never captured, stop dependent mutations and retain
evidence. An independently attributable pre-change backup may support recovery after
checking for intervening changes; a current value, common default, expanded inherited
path or product-generated backup without its original kind does not. Explicit user
acceptance of a replacement establishes a **new baseline**, not proof of historical
restoration. Do not claim exact recovery or resume confirmation on an unreviewed baseline.

Track directories, new logs, language/theme, companion state and window/process ownership
separately. Files present before the run are never removed because they look test-related.
Delete only exact run-created files; remove new directories only when empty. Preserve
pre-existing logs and report append-only operational logging separately from restored
configuration. After final baseline verification, delete the exact private journal and
empty private directory. Keep recovery material if required notification or cleanup is
uncertain; do not restart merely to refresh a cache after declaring final restoration.

Editing a default variable can create `profiles.json` containing an empty array even
when no profile was added (`MainViewModel.EditVariable` writes profiles). If the captured
baseline was absent, the current bytes are an empty array, the file's creation falls
inside the owned editor lifetime and no intervening writer exists, record that complete
owned transition, seal its fingerprint, and restore absence after closing the editor.
Absence and `[]` are not byte-equivalent; never call them unchanged or create `[]` before
the run just to avoid handling original absence.

## Privacy-safe discovery and evidence

Capture `winapp ui inspect --depth 12 -w $hwnd --json` into an in-memory string, check
its exit code, and parse locally. Do not emit raw output or conversion exception text
containing its payload. Use `ConvertTo-PtEnvSafeUiInventory -Tree $tree -AllowedNames
$approvedNames -AllowedAutomationIds $approvedIds` to print only static control labels,
source-corroborated IDs and exact synthetic names. It strips arbitrary value/text/help
fields and slugs derived from unapproved names, retaining structural index paths.

The projection is an allowlist, not a secret detector. Do not populate its allowlists
from all observed environment rows. Keep raw trees in memory or private storage outside
the archive. Assert private PATH composition locally and report equality/hash receipts.
Read exact owned row values only after resolving their parent. General UI mechanics are
in [winapp-ui-testing.md](winapp-ui-testing.md).

The Applied list can flatten every row into adjacent Name/Values `TextBlock` siblings
under one ScrollViewer. That shared parent is not one variable's row. Match the exact
name and verify the immediately following value sibling against the live structure and
the page's data template; do not collect every Text descendant of the parent. In
particular, Applied PATH is one Values string, not a concatenation of all panel text.
Fail explicitly on ambiguous names or a missing sibling, and keep private values local.

Windows environment names are case-insensitive. The merged Applied PATH row can retain
the System spelling (`Path`) while the User registry entry is spelled `PATH`; do not use
the User spelling in a case-sensitive Applied-row lookup. Resolve one case-insensitive
match and independently compare its value. A missed lookup is not a value mismatch.

For candidate images use `winapp ui screenshot <current-dialog-or-control-selector>
-w $hwnd -o <run-artifact.png>` only after establishing the region contains synthetic
content and no unrelated Applied variables. Record geometry, HWND ownership and DPI;
do not archive the full editor as a convenient default. A caption-only crop cannot prove
the Applied list; use a separate private comparison receipt for that observation.

Check the selected element's bounds before capture: a WinUI ContentDialog's automation
root can span the entire editor, including the dimmed environment panels. Selecting
`AddDefaultVariableDialog` or `AddProfileDialog` is therefore not sufficient isolation.
Prefer a verified synthetic child such as `DefaultVariableNameTextBox` or
`ProfileNameTextBox`, or an exact owned variable card. Inspect candidate dimensions and
content locally before accepting the image into the archive.

For empty-input assertions, `winapp ui get-value` can fall back to the accessible Name
(`Name`) when ValuePattern contains an empty string. Read ValuePattern directly to
establish actual emptiness; compare commit availability separately. Likewise, the native
environment dialog's ListView subitem can truncate a long value. Select the exact owned
row, open its native Edit dialog, compare the complete value or ordered PATH entries
privately, then Cancel. Neither a fallback label nor a truncated list caption establishes
a product validation or restoration failure.

The 32766/32767 total-entry boundary fixtures can exceed Windows' process command-line
limit when passed as a `winapp ui set-value` argument: the executable, selector and flags
also consume that limit. Keep the exact fixture lengths. Inside a recorded step, resolve
the owned draft's Edit control and call its UIA `ValuePattern.SetValue` in-process, then
read back the actual value and commit availability. Do not shorten the fixture to make
the CLI launch succeed. Use a fresh draft for subsequent control-character checks;
large values can change scrolling and control exposure, and a missing UIA element is
an observer failure, not evidence of input rejection.

After rapid input changes, observe a bounded sequence of actual field text and commit
enabled state until that signature settles. Do not use the expected enabled state as
readiness. An immediate read can still reflect the previous valid input while WinUI
processes validation; retain that timing-sensitive sample, but do not report it as a
product failure without a settled observation. Keep provider filtering/truncation
distinct from a control character that actually reaches the model.

In the native dialog, a ListItem's Invoke pattern can open its default Edit action.
Do not then invoke Edit a second time. For selection followed by Edit, use a
foreground-guarded single click and verify `IsSelected` before invoking the scoped
User Edit button. Register the resulting owned child dialog and cancel it in `finally`.
Resolve PATH rows using their actual registry spelling: Windows names are
case-insensitive, but an exact UIA caption comparison distinguishes `Path` from `PATH`.

Native Cancel has a destruction postcondition. `Read-PtEnvNativeVariable` checks the
owned child identity immediately before a single private Cancel, then waits for that
HWND to disappear, including hidden children. A surviving child or failed invocation
remains a cleanup error; an earlier read failure retains the secondary cleanup failure.
Use this shared reader rather than a run-local Cancel workaround. Ordinary
`Invoke-PtEnvPrivateAction` calls still require their target to survive the action.

For a short synthetic name/value pair, an alternative read-only observer may use the
two actual Text subitems of its uniquely scoped native User ListView row. Read their
complete `Name` properties, verify the first cell is the exact owned variable, and
compare the second independently. Do not use a rendered/truncated caption, substitute
registry data, or generalize this shortcut to long values, PATH or clipped backup names.

Opening native Edit can create additional HWNDs, including hidden helper windows, after
the initial native-dialog snapshot. Register those siblings against the original dedicated
rundll32 PID/start-time creation before guarded closure; cancel child dialogs before the
parent. Do not relax the ownership guard or adopt a pre-existing native dialog.

A native row can expose its complete text while its capture bounds are offscreen or zero.
Use `scroll-into-view` for the exact owned row, then reacquire its selector and bounds before
the scoped screenshot. Missing capture geometry is not evidence that the variable is absent.
Likewise, failure to resolve a generated long backup by its complete ListItem name does not
establish a product write failure when storage and Applied observations match. Investigate
native name truncation and a uniquely owned Edit dialog, or retain the native observation
as incomplete rather than assigning a PowerToys defect.

A semicolon-valued backup can also open the native ordered-entry editor, even though
its name is not exactly PATH. Establish the exact selected row before invoking the
scoped User Edit button. Read each exposed entry through the native `get-value --json`
provider and compare the complete ordered sequence privately; do not assume every
non-PATH variable opens a two-field name/value dialog, or that `inspect` includes
classic Edit values. Cancel the owned editor without saving.

If managed PowerShell UIA exposes classic Win32 controls only as `Pane` without their
patterns while winapp exposes the full controls, use winapp's native provider for that
observation. Keep complete Edit values and ordered entry lists inside the private
recording boundary; publish only comparison results. A missing managed pattern is an
observer limitation, not evidence that the product control or value is missing.

For `get-property --json`, read the named member under `properties`, for example
`$result.properties.IsSelected`, not `$result.value`. Values can be strings (`"True"` /
`"False"`); compare explicitly rather than casting a nonempty string to Boolean. In the
Existing-variable duplicate check, verify selection before acting and leave an already
selected row selected. A disabled Add button with nothing selected does not prove
duplicate prevention.

## Mechanical regression

Run `scripts\tests\Test-PtEnvironmentVariablesState.ps1`. It uses temporary files and
an isolated `HKCU\Software\PowerToysVerificationTests\<guid>` subkey, never real
environment variables. It checks byte-exact/absence restore, raw expandable/empty values,
unsupported kinds, duplicate registration, encryption, unsealed/intervening conflicts,
idempotence and privacy projection. These checks validate the helper, not module behavior.
It also uses mocked CLI responses to check repeated-row scope, duplicate/missing targets,
mandatory safety snapshots and dialog identity before input and commit; no live editor
is launched by these regressions.

`scripts\tests\Test-PtEnvironmentVariablesIntegration.ps1` additionally imports the WIP
bootstrap and checks the frozen mapping, source aliases, input manifest, common cleanup/recorder integration,
conflict reporting and exclusion of private payloads from a synthetic archive. It uses
only disposable files, not live environment variables or product UI.

## Restoration sources

Windows contracts:

- [RegistryValueOptions.DoNotExpandEnvironmentNames](https://learn.microsoft.com/en-us/dotnet/api/microsoft.win32.registryvalueoptions?view=net-10.0)
  and [RegistryKey.GetValueKind](https://learn.microsoft.com/en-us/dotnet/api/microsoft.win32.registrykey.getvaluekind?view=net-10.0):
  capture unexpanded text separately from the registry type.
- [RegistryKey.SetValue overloads](https://learn.microsoft.com/en-us/dotnet/api/microsoft.win32.registrykey.setvalue?view=net-10.0)
  and [DeleteValue](https://learn.microsoft.com/en-us/dotnet/api/microsoft.win32.registrykey.deletevalue?view=net-10.0):
  explicitly typed restore and restoring absence.
- [Environment.SetEnvironmentVariable overloads](https://learn.microsoft.com/en-us/dotnet/api/system.environment.setenvironmentvariable?view=net-10.0)
  and [setx limitations](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/setx):
  not substitutes for raw text/type preservation.
- [Environment blocks and inheritance](https://learn.microsoft.com/en-us/windows/win32/procthread/environment-variables),
  [WM_SETTINGCHANGE](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-settingchange)
  and [SendMessageTimeoutW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendmessagetimeoutw):
  persistence, notification and running-process state are distinct.

Repository-relative source corroboration:
`src\modules\EnvironmentVariables\EnvironmentVariablesUILib\Models\ProfileVariablesSet.cs`
(`Apply`, `UnApply`, `UnapplyVariable`);
`Helpers\EnvironmentVariablesHelper.cs` under the same library root
(`GetVariables`, `SetEnvironmentVariableFromRegistryWithoutNotify`, `NotifyEnvironmentChange`);
`ViewModels\MainViewModel.cs` (`UnsetAppliedProfile`, `EditVariable`, `SaveAsync`);
`Helpers\EnvironmentVariablesService.cs` (`WriteAsync`).
These explain product undo/type inference/asynchronous persistence; they do not prove a
particular live recovery. Helper implementation: `scripts\pt-environment-variables-state.ps1`
relative to the verification skill root.
