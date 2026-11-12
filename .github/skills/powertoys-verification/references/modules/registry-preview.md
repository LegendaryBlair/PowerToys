# Registry Preview - module verification profile

## Module facts

**Discovery-stage, not full-inventory execution-ready.** Explorer classic-menu, live
Windows-theme and CmdPal preservation/interaction paths still require confirmation.
Proven Regedit popup behavior does not establish Explorer behavior. Locale, first-run,
fault and diagnostics conditions remain required, not optional.

| Field | Value |
|---|---|
| Module / UI | `RegistryPreview`; WinUI 3 and WebView2/Monaco |
| Executable | Installed `WinUI3Apps\PowerToys.RegistryPreview.exe` |
| Data | `%LOCALAPPDATA%\Microsoft\PowerToys\RegistryPreview\settings.json` and `app-placement.json` |
| Cache | `%USERPROFILE%\AppData\LocalLow\Microsoft\PowerToys\RegistryPreview-Temp` |
| Settings | General `enabled.RegistryPreview`; module `properties.default_reg_app` is a plain Boolean |
| Identity | Rediscover `WinUIDesktopWin32WindowClass` under the exact editor image/PID/start time; title changes with file |

## Entry paths

Preserve [originals and ownership](#fixtures-and-restoration) before activation.
Record controller, Runner, editor and fixture integrity separately: elevated-shell
launch is not medium-integrity coverage. Existing windows/processes remain borrowed.

| Intent | Entry |
|---|---|
| Explorer menu | Owned file/window and populated classic Preview menu; `regfile\shell\preview\command`, not packaged `IExplorerCommand`. |
| File behavior | Observed Preview verb or quoted owned-file argument; not menu-presence evidence. |
| Settings | Preserved main window; Advanced / `RegistryPreviewNavItem`. |
| Welcome | `OOBENavItem`; identify the new secondary window, select its Registry Preview ListItem. |
| Downstream activation | `RegistryPreview.Trigger` through `Invoke-PtSharedEvent`; declared `Invoke-PtOwnedProcessActivation` tracking. |
| CmdPal | Actual PowerToys extension, not Search apps; requires the preservation baseline below. |

## UI state-transition map

Independent Settings, Welcome, Regedit and palette windows can coexist. Editor below
means blank or clean file; Dirty editor has unsaved changes. Observe arrival.

| Current state | Trigger / condition | Next state | State landmarks |
|---|---|---|---|
| No owned editor | Enabled launch, with/without file | Editor | Title, `commandBar`, content |
| Editor | Open or Save as | File dialog | Owned `#32770`, filename |
| File dialog | Commit | Editor | Dialog closed, active filename |
| File dialog | Cancel from clean origin | Editor | Original file/blank state |
| File dialog | Cancel from dirty origin | Dirty editor | Original draft |
| Editor | Type | Dirty editor | Save enabled |
| Dirty editor | Save succeeds | Editor | Save disabled |
| Editor | Reload external save | Editor | Same host/content surfaces |
| Dirty editor | Reload or Close | Confirmation | Operation-specific actions |
| Confirmation | Cancel | Dirty editor | Draft retained |
| Confirmation | Confirm reload | Editor | Editor controls |
| Confirmation | Save existing file, completing Close | No owned editor | Window/process exits |
| Confirmation | Discard owned draft, completing Close | No owned editor | Window/process exits |
| Editor | Normal close | No owned editor | Window/process exits |
| Owned Regedit key | Key context menu | Key popup | Fresh visible `#32768` |
| Key popup | Export | Export dialog | Selected branch, filename |
| Editor | Authorized Write | Import prompt | Same-user Regedit, specific file |
| Import prompt | Authorized Yes | Import result | Same-generation result dialog |

Dirty Open/Write/Save may add save/filename dialogs; inspect rather than bypass them.

## Control locator and interaction index

Use current identities with `Invoke-PtWinApp`; re-resolve after navigation/lifecycle
changes. IDs below are AutomationIds, not resource keys or reusable runtime slugs.

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Navigate Settings | Main rail | `RegistryPreviewNavItem` under `AdvancedNavItem` | Reveal/select. |
| Toggle module | `RegistryPreviewEnableRegistryPreview` | Toggle Name Registry Preview | Toggle; compare UI/config. |
| Settings launch | Enabled page | `RegistryPreviewLaunchButtonControl` | Invoke; track editor. |
| Welcome launch | Module page | Button `LaunchButton` | Read `IsEnabled`, physically target, observe process. |
| Default app | `RegistryPreviewDefaultRegApp` | Named toggle | Toggle; compare registration/effective default. |
| Open | `commandBar` | Button `openButton` | Physical click; owned picker. |
| Save as | `commandBar` | Button `saveAsButton` | Physical click; no unowned overwrite. |
| Reload | `commandBar` | Button `refreshButton` | Click; resolve dirty confirmation. |
| Save | Dirty editor | Button `saveButton` | Click; resolve filename; read disk. |
| Edit externally | Saved owned file | Button `editButton` | Physical click; preserved document below. |
| Edit Monaco | Realized WebView | `Browser`; fresh editor bounds | Guarded clipboard paste, small physical edits. |
| Select key | Right-hand Tree | `ListControl`, Class `ListView`; unique child Text | Click visible leaf; expand observed ancestors. |
| Enter path | Owned `#32770` | Observed filename field | Guarded Ctrl+A/Ctrl+V/Enter; verify destination. |
| Export | Regedit popup | MenuItem Export, fresh `#32768` | Inspect; supported action/access key. |
| Delete key | Exact owned address/selection | Tree `1`, Class `SysTreeView32` | Focus/Delete; specific confirmation; verify absence. |
| Import | Reviewed export; key absent | Button `writeButton` | Physical click; exact-file confirmation. |
| Close | Owned window/siblings | Tracked identities | `Stop-PtOwnedProcess` / `Close-PtTrackedWindow`. |

### Regedit export and import

Verify the selected owned key/address and capture existing menu identities before
right-clicking. Resolve exactly one new visible `#32768` with `Get-PtNativeWindow`,
bound to the current Regedit image/PID/start time; validate with `Get-PtWindowIdentity`.
Inspect Export under **that popup HWND**, not the main-window UIA scope. Stale/ambiguous
scope is not command absence and does not authorize another gesture.

Read the export dialog's selected-branch radio state and exact HKCU branch before saving
to an absent owned path. Review the complete file: header, sole intended key, value
kinds/data and no unrelated commands; retain its hash. Manually delete that selected
key through Regedit and independently establish absence before import.

Close only fixture-owned Regedit before tracking Write's new process; never adopt an
existing singleton. Verify generation, same user and exact saved-file argument with
Windows argument parsing, not quote-substring assumptions. Confirm only that authorized
file's import, observe success and independently read imported kinds/data. Extra
credentials/secure-desktop consent block that step, not independent work; no automatic
elevation/account switch. Generated files, `reg import` and cleanup deletion do not
replace the original UI workflow.

### External editor and Welcome

Before Edit, privately preserve windows, tab identities/order/selection and placement.
Identify the owned document by path/token and tab runtime identity, not launcher PID.
Select it, compare displayed/saved content, then edit/save in the external editor.
Reread disk before Reload; inspect Monaco and tree separately. Normalize Notepad
TextPattern CR-only line endings only for comparison. Close only the owned tab and
restore borrowed state; defer editors lacking preservation.

Re-enter Welcome's module page after enablement changes; `LaunchButton` refreshes on
navigation. Preserve a borrowed page or prove secondary-window ownership. Keep main
Settings visible during owned Welcome close, then restore its visibility/placement
and verify the original main identity survives.

### Read-out notes

- Runtime `ListControl` differs from XAML `treeView`; `dataGrid` is independent of Monaco.
  Wait for `Browser`, not merely the tree. Use `Read-PtSharedFileText` for live files.
  Bytes, visible text, tree and filename are separate; inspect capture pixels for occlusion.
- Query effective `.reg` association (for example `AssocQueryString`) and exercise actual
  default Open separately from registration. Both routes were observed with **no UserChoice
  override**; this proves neither an existing-override case nor a general defect. Never
  edit UserChoice or accept an association-only import prompt to force an outcome.
- Live caption checks change **Windows default app mode**, not PowerToys Settings' own
  theme. Its reversible Windows Settings path still needs confirmation; static pixels
  or a reopened editor do not prove a live transition.

## Troubleshooting

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| Browser absent | Bound readiness observation. | No cache deletion/restart until green. |
| Export lookup empty | Revalidate popup scope above. | No absence claim from main HWND. |
| Explorer menu unobserved | Establish selection, foreground, populated classic menu. | Preserve repair limits; no Regedit-fix transplantation. |
| Default on, other handler | Compare registration/default/UserChoice. | No registration-only PASS. |
| Open/Save Invoke stalls | Cancel owned picker, verify closure; physical click on authorized retry. | No repeated Invoke or uncontrolled folder capture. |
| CmdPal hidden/cloaked | Preserve query/navigation before activation. | No provider recycling or disk-only restoration. |
| Consent unavailable | Verify owned prompt/file/user. | No secure-desktop bypass/account switch. |

## Fixtures and restoration

### Resource inventory

| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| Files/editor/cache | File operations | Private snapshots; owned process/siblings | Quiesce; attributed rollback | Bytes/set/absence, exits |
| Settings/placement | Startup/settings | Durable originals/post-state | Placement adapter; UI-first settings restore | Live values, bytes |
| External editor | Edit/reload | Owned document; original tabs/placement | Close owned tab; restore borrowed state | Identities/order/selection |
| Settings/Welcome | Entry | Main snapshot; secondary ownership | Restore page/state; main visible during Welcome close | Original identity/state |
| Explorer | Menu | `New-PtExplorerFixture`; desktop baseline | Pointer before `Remove-PtExplorerFixture` | Owned window/folder absent |
| Regedit/key/preferences | Export/import | Same-user ownership; selected kinds/absence/containers | Close; guarded key/preferences restore | Exact baseline |
| Association | Default app | Selected HKCU Classes/ProgID/OpenWith and intermediate-key absence; effective default/UserChoice | Original UI value; attributed registry restore | Kinds/absence, handler |
| CmdPal/provider | Palette | Query/navigation/history, pins/order, provider lifetime | Proven live-state restoration before driving | Disk alone insufficient |
| Clipboard | Paste/copy | Shared keeper, private formats | Restore before writer/provider release | Payload-free receipt |
| Windows app mode | Theme | Mode; borrowed Windows Settings state | Proven reversible UI required | Mode/page/window |

### Helper boundaries

Reuse [session](../session-safety.md), [owned-fixture](../owned-fixtures.md) and
[file/directory](../directory-snapshots.md) contracts; persist private originals before
mutation. Notepad `.txt` fixture receipts cannot adopt Edit-opened `.reg` tabs.
Clipboard writes need the keeper and history/cloud exclusion formats.

`pt-registry-preview-state.ps1` **restores placement only**. Capture with
`New-PtRegistryPreviewFileState` using the resolved module directory and owned private
directory; retain its receipt privately. `Read-PtRegistryPreviewFileState` validates it.
After attributed writes quiesce, pass the receipt/post-state to
`Set-PtRegistryPreviewExpectedFiles`, then `Restore-PtRegistryPreviewFiles`.
Success does **not** restore settings.json, Settings UI, association, cache or clipboard;
unrelated settings differences are preserved/reported.

Before owned Regedit startup, snapshot selected values/kinds/absence under
`HKCU\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit` (`LastKey`, `View`,
`FindFlags`) and relevant containers. Remove a newly created empty `Favorites` only
when original absence, test ownership and current emptiness are established.
Unexpected contents are conflicts, not permission to delete the preference tree.

Restore the original default-app value through the real UI before settings.json byte
rollback. An observed UI write normalized version `1` to `1.0`; this is **not** permission
to normalize arbitrary user files. For attributed writes, use `Restore-PtFileSetSnapshot`
with immutable original, expected owned post-state and explicit owned filename after
final UI writes. Never relabel concurrent data as owned; verify live state separately.

### Restoration order

1. Release input; restore clipboard before writer/provider release.
2. Resolve owned drafts/modals and close owned editors/tabs/Regedit; restore borrowed
   tabs. Keep main Settings visible during owned Welcome closure. Restore pointer before
   owned Explorer closure; establish cache-writer exit.
3. Restore original module/default-app values and authorized, preservable Windows app mode
   through UI, then borrowed Settings navigation/placement. Finish UI/startup writes and
   verify live values **before** byte rollback.
4. With writers quiescent, restore owned keys, selected Regedit preferences/containers and
   attributed association values. Guard placement, owned settings serialization and
   cache/file rollback against original and expected state; preserve concurrent changes.
5. Restore foreground/pointer/layout; compare live state, files and effective association
   separately. Any further write-producing observation precedes final comparisons.

### Restoration verification

Compare live settings, exact files/cache, registry kinds/absence, effective default,
owned exits and borrowed UI/desktop separately. Preserve concurrent changes and historical
failures. CmdPal file backup is not live query/navigation/history/pin/provider restoration;
unsupported preservation blocks dependent work without waiving conditional coverage.

## References

- [Checklist](../release-checklist/registry-preview.md) and [assertions](../assertion-inventories/registry-preview.json).
- [Recorder](../recording-workflow.md), [UI observations](../ui-observations.md),
  [classic menus](../explorer-context-menu-flow.md), [CmdPal boundaries](command-palette.md).

No accepted visual reference is supplied. Immutable archives retain actual coverage;
documentation maintenance does not complete R1, certify independent reproducibility or
grant release signoff.
