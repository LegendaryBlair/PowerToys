# Registry Preview - module verification profile

## Module facts

| Field | Value |
|---|---|
| Module key | `RegistryPreview` |
| Editor | Installed `WinUI3Apps\PowerToys.RegistryPreview.exe`; WinUI 3 plus WebView2/Monaco |
| Data | `%LOCALAPPDATA%\Microsoft\PowerToys\RegistryPreview\settings.json` and `app-placement.json` |
| Cache | `%USERPROFILE%\AppData\LocalLow\Microsoft\PowerToys\RegistryPreview-Temp` |
| Enablement | General `enabled.RegistryPreview`; separate from module `properties.default_reg_app` |
| Event | `RegistryPreview.Trigger` in the shared catalog |
| File entry | Quoted file argument; classic Classes `regfile\shell\preview\command`, not a packaged `IExplorerCommand` |
| Window | Rediscover `WinUIDesktopWin32WindowClass` under the exact editor PID/start-time/path; titles change with the file |

## Entry paths

Preserve resources before activation; an existing editor remains borrowed.
See [restoration](#fixtures-and-restoration).

| Intent | Entry |
|---|---|
| Menu presence/launch | New owned Explorer, select the owned `.reg` file, open its real classic menu (Show more options on Windows 11), then invoke the observed Preview caption. Verify menu type and selection, not registration alone. |
| File behavior | `Get-PtShellVerbs -Path $file` on the owned file; require one Preview caption before invocation. This classic-verb route does not prove visible menu presence. |
| Settings launch | Preserve Settings, reveal Advanced / `RegistryPreviewNavItem`, then invoke `RegistryPreviewLaunchButtonControl` while enabled. |
| Welcome/OOBE | Preserve the original page/window. Inspect its navigation for Registry Preview and its local launch action; observe a newly activated editor. Do not replace this route with Settings launch. |
| Downstream activation | `Invoke-PtSharedEvent -Name 'RegistryPreview.Trigger'` with the intended enabled Runner/consumer; track the resulting process with `Invoke-PtOwnedProcessActivation`. |
| Command Palette | Use the actual PowerToys extension commands, not a Search apps shortcut. Preserve query/navigation, pins/history and provider lifetime first. |

Record automation, Runner, editor and foreground-fixture integrity separately. Launching
the executable directly from an elevated shell is not ordinary medium-integrity coverage.

## UI state-transition map

Settings, Welcome and palette windows can coexist independently with the editor.
Observe arrival; this is a route index, not a fixed test order.

| Current state | Trigger / condition | Next state | State landmarks |
|---|---|---|---|
| No owned editor | Enabled launch without file | Blank editor | Title, `commandBar`, loading/content surface |
| No owned editor | Preview owned file | File editor | Filename title, tree and editor |
| Blank editor | Open button | File dialog | Editor-owned `#32770` |
| File editor | Open or Save as button | File dialog | Filename field, Open/Save and Cancel |
| File dialog | Successful file selection/save | File editor | Dialog closes; active filename |
| File dialog | Cancel; opened from Blank editor | Blank editor | No file selected |
| File dialog | Cancel; opened from File editor | File editor | Original active file remains |
| File dialog | Cancel; opened from Dirty editor | Dirty editor | Original draft remains |
| File editor | Type in Monaco | Dirty editor | Save enabled |
| Dirty editor | Successful Save | File editor | Save disabled |
| File editor | Reload after external save | File editor | Same host, refreshed content |
| Dirty editor | Reload | Reload confirmation | Reload/Cancel actions |
| Reload confirmation | Cancel | Dirty editor | Draft retained |
| Reload confirmation | Confirm reload | File editor | Normal editor controls return |
| Dirty editor | Close | Save confirmation | Save / Don't save / Cancel |
| Save confirmation | Cancel | Dirty editor | Owned editor remains |
| Save confirmation | Save existing file succeeds | No owned editor | Original HWND/process disappears |
| Save confirmation | Don't save owned edits | No owned editor | Original HWND/process disappears |
| File editor | Normal close | No owned editor | Original HWND/process disappears |
| File editor | Authorized Write to Registry | Import prompt | Same-user Registry Editor confirmation; possible UAC |

Dirty Open/Write/Save can require additional save/filename dialogs. Inspect the actual
modal; cancellation is not a successful file operation.

## Control locator and interaction index

Use `Invoke-PtWinApp` with the exact current HWND. Query unique typed targets and their
supported patterns; never reuse a runtime slug after a tree change.

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Navigate Settings | Borrowed navigation rail | AutomationId `RegistryPreviewNavItem`, within `AdvancedNavItem` when collapsed | Reveal the parent; select/invoke the item and observe the module card. |
| Toggle module | Module Settings card | Parent `RegistryPreviewEnableRegistryPreview`; toggle Name Registry Preview | Read Toggle pattern, change only when needed, read general enablement separately. |
| Launch editor | Enabled Settings page | AutomationId `RegistryPreviewLaunchButtonControl` | Invoke; resolve the new process/window. |
| Toggle default app | Enabled Settings page | Parent `RegistryPreviewDefaultRegApp`; named default-app toggle | Use Toggle pattern; distinguish registration from effective handler. |
| Open file | `commandBar` | Button AutomationId `openButton` | Invoke; resolve owned file dialog. |
| Reload file | `commandBar` | Button AutomationId `refreshButton` | Invoke once; handle the actual dirty confirmation. |
| Save | `commandBar`, dirty editor | Button AutomationId `saveButton` | Invoke; handle filename if needed, then independently read disk. |
| Save a copy | `commandBar` | Button AutomationId `saveAsButton` | Invoke and select an owned destination; reject unowned overwrite. |
| Edit externally | Saved owned file | Button AutomationId `editButton` | Invoke Edit verb only after establishing external-document/tab preservation. |
| Type in Monaco | WebView initialized | AutomationId `Browser` when exposed; current editor descendants/bounds | Guard foreground, focus actual editor, use physical text/chords. Preserve clipboard if choosing paste. |
| Select key | Right-hand Tree | AutomationId `ListControl`, ClassName `ListView`; exact child Text name | Require unique visible leaf; click fresh bounds or invoke its TreeItem's supported action. Expand only observed collapsed ancestors. |
| Enter file path | Owned `#32770` dialog | Freshly inspect filename Edit/ComboBox and Open/Save Button | Set filename and confirm; keyboard entry additionally needs exact foreground. |
| Import saved file | Reviewed same-user owned fixture | Button AutomationId `writeButton` | Invoke only after registry/consent preconditions; handle that specific import prompt. |
| Close editor | Owned clean window | Exact identity plus registered native siblings | Compose `Stop-PtOwnedProcess` and `Close-PtTrackedWindow`; handle only owned dirty-document prompts. |

### Read-out notes

- `treeView` is a XAML name, not the observed runtime locator. TreeItems may share a CLR
  type name; use the child label scoped under `ListControl`, not the first TreeItem.
- Read `dataGrid` after key selection. Name/type/data there are independent of Monaco text.
- A populated tree can precede `Browser`: a Busy ring may still occupy the editor.
  Wait for actual content before typing; a launch or fixed sleep is not readiness.
- `Read-PtSharedFileText` permits live writers. Declare encoding/newline comparison;
  saved bytes, visible editor, tree and filename are separate observations.
- The module's `properties.default_reg_app` is a Boolean, without `.value`.
  OpenWith/ProgID registration does not override Windows UserChoice.
- Capture owned content only. Native rectangles can include surrounding shadow margins;
  use a scoped capture and inspect pixels/identity/geometry before accepting evidence.

## Troubleshooting

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| Visible keys but `treeView` search misses | Inspect current Tree / `ListControl`; scope the leaf there. | Locator mismatch is not missing product data. |
| Tree ready, Browser absent | Observe Busy/WebView initialization with a bound, then a grounded input path. | Do not delete existing cache or restart until green. |
| Preview missing | Check selected `.reg`, enablement and classic menu; establish a populated file menu for absence claims. | Other modules' packaged-menu advice does not apply. |
| Default app on, another handler selected | Compare registration with original effective default/UserChoice. | Retain the checklist conflict; registration alone cannot satisfy default-open. |
| Edit reuses Notepad | Preserve existing tabs/selection/geometry and identify the newly opened document. | Launcher PID is not tab ownership; no blanket close. |
| Close leaves modal/cache writers | Inspect owned identities; resolve only the owned draft, then observe exit. | No process-name killing or cache removal with live writers. |
| Import requires different credentials | Verify user/token and HKCU destination before consent. | Do not switch user or infer authorization from an elevation prompt. |

## Fixtures and restoration

### Resource inventory

| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| `.reg` and Save-as files | File/menu cases | Collision-checked owned directory, known bytes/absence | Shared directory rollback, explicit relative paths, after users close | Original file set/bytes/existence |
| Editor and siblings | Launch | Declare exact Process resource; track indirect activation; reject borrowed singleton | Shared normal owned-window/process close | Exact original process gone; borrowed windows remain |
| Settings/placement files | Launch/settings | `Get-PtFileSetSnapshot` for selected filenames; private bytes/absence | Quiesce editor; guarded attributed placement rollback; UI restoration for settings | Selected byte baseline and original option values |
| Monaco cache | Launch | Snapshot exact root before activation; establish writer absence | Three-way rollback of attributed paths after all cache writers exit | Original bytes/file set/existence; conflicts explicit |
| Settings/Welcome/palette | Their entry checks | Original logical state, geometry, query/history/pins and providers as affected | Shared Settings adapter; separately proven Welcome/palette rollback | Fresh logical comparison after final action |
| Explorer | Real menus | `New-PtExplorerFixture` receipt and desktop baseline | Remove owned files; restore pointer before `Remove-PtExplorerFixture` | Exact window/folder absent; original desktop |
| Registry Editor/key | Export/import | Same-user unique key; original Regedit UI/LastKey/placement, kinds/absence | Close only owned Regedit; restore selected values; remove only owned new key | Exact registry/UI baseline |
| Association | Default-app case | Affected Classes values and original effective handler | Restore original option via Settings; never write UserChoice | Registration and handler independently |
| Clipboard | Paste/copy only | Shared keeper before writes; private formats | Restore before writer/provider release | Shared receipt, no disclosed payload |

### Helper boundaries

Use the existing [template/recorder](../recording-workflow.md), [session adapters](../session-safety.md),
[owned fixtures](../owned-fixtures.md) and [directory snapshots](../directory-snapshots.md).
A snapshot does not confer ownership. File-set snapshots need an existing parent;
directory snapshots preserve absence but not ACLs, streams or timestamps.

The Notepad fixture adapter owns its generated `.txt` document. Do not fabricate a receipt
to adopt a `.reg` tab opened by Edit; establish its tab-specific preservation first.

### Restoration order

1. Release owned input; restore clipboard before releasing its writer/provider.
2. Resolve owned drafts/modals, close owned editor/companions normally, and observe cache
   writer exit. Restore pointer before closing the last owned interaction window.
3. Roll back attributed placement/cache/files against original and expected snapshots.
   Preserve unknown concurrent changes; remove only owned new data.
4. Restore original module/default-app/theme values via UI, then borrowed logical/window
   state. Close owned Explorer with its adapter, restore foreground, and compare afterward.

### Restoration verification

Require separate receipts for files/cache, owned process/window absence, changed registry/
association values, borrowed UI and desktop. Snapshot/helper success alone is not complete
restoration. Missing preservation blocks dependent mutations, not independent safe checks.

## References

- [Checklist](../release-checklist/registry-preview.md) and [assertions](../assertion-inventories/registry-preview.json).
- [UI observations](../ui-observations.md), [classic menus](../explorer-context-menu-flow.md),
  and [Command Palette boundaries](command-palette.md).

No accepted visual reference is supplied. Discovery provenance and actual coverage remain
in the Author record/run archive, not a reusable success stamp.
