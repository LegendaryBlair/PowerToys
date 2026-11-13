# Hosts File Editor - module verification profile

## Module facts

Discovery-stage / needs-review, not signoff. Build identities and results stay in archives.

| Field | Value |
|---|---|
| Module / stack | `Hosts` / Hosts File Editor; WinUI 3 |
| Executable / window | Installed `WinUI3Apps\PowerToys.Hosts.exe`; `WinUIDesktopWin32WindowClass` |
| Preferences | `%LOCALAPPDATA%\Microsoft\PowerToys\Hosts\settings.json`; general `enabled.Hosts` |
| File | Product targets `%WinDir%\System32\drivers\etc\hosts`; compare with expanded TCP/IP `DataBasePath` |
| Events | `Hosts.Show`, `Hosts.ShowAdmin`; downstream activation only |
| Backups | Configured `BackupPath`; `hosts_PowerToysBackup_<timestamp>`; elevated startup applies retention |
| Lifetime | On-demand; reusing an editor does not establish a new privilege transition |

## Entry paths

Preserve [originals](#fixtures-and-restoration) before startup pruning and borrowed
drafts before entry. Check controller, Runner, Settings and editor tokens.
Never automate UAC or change accounts; missing consent blocks only dependent routes.

| Intent | Entry |
|---|---|
| Settings | Preserved main window: `HostsNavItem`, then `HostsLaunchButtonControl`. |
| Warning | Set the real preference; launch a fresh owned editor. |
| Tray | Actual localized Quick Access launcher; its Apps toggle is a different control. |
| Downstream action | `Invoke-PtSharedEvent -Name 'Hosts.Show'` or `'Hosts.ShowAdmin'`; declared ownership. |
| Writer mechanics | Owned direct elevated launch; not Settings/UAC evidence. |
| Command Palette | PowerToys extension; same-kind history undo required before invocation (see restoration). |

## UI state-transition map

Settings, external editors and Hosts can coexist. Observe arrival before continuing.

| Current state | Trigger / condition | Next state | State landmarks |
|---|---|---|---|
| No editor | Launch, warning on | Startup warning | Accept / Quit |
| No editor | Launch, warning off | Entries | `Entries` List; New entry |
| Startup warning | Accept | Entries | Warning gone; toolbar ready |
| Startup warning | Quit | No editor | Process exits |
| Entries | New entry; no modal | Entry draft | Popup field Edits |
| Entry draft | Valid Add | Entries | Modal closes |
| Entry draft | Cancel | Entries | Draft dismissed |
| Entries | Filters | Filter flyout | Filter Edits; Clear filters |
| Filter flyout | Dismiss | Entries | Popup closed; query retained |
| Entries | Additional content | Content draft | `AdditionalLines`; Save / Cancel |
| Content draft | Save | Entries | Modal closes |
| Content draft | Cancel | Entries | Draft dismissed |
| Entries | External change | Reload available | Notice; Reload |
| Reload available | Reload | Entries | List realized |
| Entries | Normal owned close | No editor | Tracked process exits |
| Hosts Settings | Browse; no borrowed modal | Folder picker | Owned `#32770` |
| Folder picker | Select and OK | Hosts Settings | Picker closes; Location card |
| Folder picker | Cancel | Hosts Settings | Picker closes without selection |
| Quick Access launcher | Localized More | Apps | Back; module toggles |
| Apps | Localized Back | Quick Access launcher | Launchers; `DocsBtn` |

Never invoke underlying New entry while another ContentDialog is open.

## Control locator and interaction index

Use shared identity/UIA helpers and `Invoke-PtWinApp`; reacquire after transitions.
English labels below are discovery hints, not locale-independent selectors.

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Navigate | Settings rail | AutomationId `HostsNavItem` | Reveal/Select; await launch card. |
| Launch | Enabled Hosts page | AutomationId `HostsLaunchButtonControl` | Invoke or guarded click; attest process/token. |
| Set launch option | Hosts page | Class `ToggleSwitch` in `HostsToggleLaunchAdministrator` / `HostsToggleShowStartupWarning` | Toggle/read persistence; fresh launch. |
| Enable Hosts | Hosts page | Class `ToggleSwitch` in `HostsEnableToggleControlHeaderText` | Toggle only Hosts; observe each surface separately. |
| Accept / quit | Warning | Accept / Quit Buttons | Invoke; await dismissal / exit. |
| Open draft | Entries; no modal | New entry Button | Invoke; await actual popup. |
| Fill draft | Entry popup | Address / Hosts / Comment Edits | ValuePattern.SetValue/readback; no clipboard. |
| Commit / cancel | Entry popup | Add / Cancel; `PrimaryButton` / `CloseButton` if exposed | Unique Invoke; observe closure and file separately. |
| Change Active | Owned `Entries` row | Tagged hostname TextBlock, ListItem ancestor, Active ToggleSwitch | Deduplicate identities; toggle/read UI and file. |
| Filter / clear | Filters flyout | Address / Hosts / Comment Edits; Clear filters | Scope popup; set/read, clear or dismiss. |
| Reload | Change notice | Reload Button | Invoke; await entries. |
| Edit additional content | Content modal | `AdditionalLines` Edit; Save / Cancel | Preserve original; append owned comment; commit/cancel. |
| Set content position | Hosts Settings | ComboBox in `HostsAdditionalLinesPosition` | Select/read Top/Bottom; editor commit separately. |
| Set backup policy | Backups expander | Backup toggle; Automatically delete backups ComboBox | Toggle/Select; verify persistence before startup. |
| Browse | Location SettingsCard | Button; new `#32770`, matching PID/native Settings owner | Nonblocking real click; synchronous modal Invoke blocks. Prove Cancel first. |
| Select / cancel folder | Owned picker | Tree/TreeItems; Button-class Cancel `2` / OK `1` | Native CLI expand/select fresh parent-scoped items; click. No assumed address Edit. |
| Set retention number | Active count/age/Days card | Spinner, Class `Microsoft.UI.Xaml.Controls.NumberBox` | RangeValuePattern.SetValue; verify value and persistence. |
| Launch in Quick Access | Launcher page | Localized Hosts Name; ControlType/Class `Button` | Unique Invoke; attest editor. |
| Toggle in Quick Access | Apps page | Localized Hosts Name; ControlType `Button`, Class `ToggleSwitch` | TogglePattern; More/Back changes scope. |
| Dismiss Quick Access | Current surface | Attested HWND | Foreground preserved window; await cloak, then dismiss owned overflow. Do not assume Escape. |
| Change app mode | Windows Colors page | ComboBox `SystemSettings_Personalize_Color_AppsTheme_ComboBox` | Select Light/Dark; same live Hosts PID; restore modes/UI. |
| Open externally | Entries toolbar | Open hosts file Button | Identify owned document/tab; opening is not auto-refresh. |
| Close editor | Owned creation/siblings | PID/start/path and HWND | Normal tracked close; verify exit. |

### Read-out notes

- EntryDialog's XAML name may be absent; inspect the main-tree popup, not its empty
  bridge. Deduplicate with `Select-PtUniqueUiElement`.
- Count cards expose `BackupsCountInputSettingsCard` or `BackupsCountInputAgeSettingsCard`;
  scope Days separately. Combined hostname/comment text still identifies one row.
- `.value` booleans: `ShowStartupWarning`, `LaunchAdministrator`,
  `LoopbackDuplicates`, `NoLeadingSpaces`, `BackupHosts`. Unwrapped fields:
  `AdditionalLinesPosition`, `Encoding`, `DeleteBackupsMode`, `DeleteBackupsDays`,
  `DeleteBackupsCount`, `BackupPath`. These are not selectors.
- Use private `Read-PtSharedFileBytes/Text`. Fixed-Notepad builds ignore editor association.
- Observe Quick Access, storage and open Settings before re-navigation. CmdPal availability
  needs the matching selected-action caption; enabled actions do not prove disabled launch.
- Use passive, physically bounded synthetic/caption captures; refocusing dismisses popups.

## Troubleshooting

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| Lookup fails | Inspect owner/tree/patterns. | Failed observers do not prove absence. |
| Picker exposes Panes | Use native CLI Tree/TreeItem/Button discovery. | Not a browse failure. |
| Browse point covered | Preserve, dismiss/reopen update activity. | Never click Install now. |
| Save/guard error | Check token, ACL, attributes, attribution. | No weakened permissions or conflicting rollback. |
| Retention ineffective | Check folder, creation times, policy, fresh startup. | Reuse does not rerun pruning. |
| Windows Settings empty | Restore outer ApplicationFrameHost frame; await inner CoreWindow. | Cloak is not missing theme support. |
| File/cache mismatch | Restore live state; check writeback. | Bytes alone are insufficient. |
| Borrowed state unsupported | Identify draft/navigation/cache gap. | Nonempty alone is not a blocker. |

## Fixtures and restoration

### Resource inventory

| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| Live hosts | Writes | Bytes/existence, encoding/newlines, ACL, attributes/times | Quiesce owned writers; guarded rollback | Exact originals; preserve conflicts |
| Preferences | UI/startup | Private module/general originals and post-states | Restore UI/cache and guarded bytes | Live values and writeback |
| Original backups | Before startup | Unowned names/bytes/metadata | Remove only attributed new files | Original set/content/metadata |
| Retention folder | Policies | Owned folder, creation-time fixtures, sentinel | Restore path/policy; remove owned files | Original folder and sentinel intact |
| Editor/popups | Editing | Exact creation/siblings; borrowed drafts untouched | Cancel owned drafts; normal close | Original absence/state |
| Settings windows | UI/theme | Page/back stack, expansion/scroll, modes, placement | Logical state, then native placement | Fresh UI/mode/placement |
| External document | Auto-refresh | Owned document; borrowed tabs/drafts | Normal close; restore selection | Original tabs/process |
| CmdPal/provider | Extension | History, pins, preferences, query/page/selection/scroll, identities | Same-kind undo; approved lifecycle only | Live/cache/files; unrelated history |
| Desktop/clipboard | Input | Foreground/pointer; private keeper if used | Pointer before focus; keeper last | Compare privately |

### Helper boundaries

Use the [shared resource plan](../session-safety.md). Snapshots omit ACLs/caches.
Guarded `Restore-PtFileSnapshot -ExpectedState` handles existing regular files, not
absence. Never bypass system-root guards.

Keep single-host collections as arrays. Attribute normalization; use collision-checked owned
`.invalid`/`.test` names and loopback/documentation addresses. Never alter real mappings
or substitute a canned hosts file.
Notepad's fixture receipt cannot own an arbitrary document.

### Restoration order

1. Stop input and cancel owned drafts. Restore Settings values, path and policy.
2. Normally close owned writers/documents; register siblings, never borrow process ownership.
3. Guardedly restore files/metadata; remove only owned backups and fixtures.
4. Restore navigation/placement, pointer and foreground; verify after the last writer/startup.

### Restoration verification

Compare files/metadata, backups, cache, UI and desktop separately. Retain private originals
until all obligations are verified; never erase historical unresolved ownership.

### Execution notes

- **Backups:** select an owned folder through Settings before startup pruning. Compare
  first content with pre-edit bytes and second-edit file sets within one PID; backup-off
  needs a fresh editor. Isolate retention by creation times and a non-backup sentinel,
  including protected-expired/recent-beyond-count conditions. Never seed the original folder.
- **Settings cache:** picker casing can change. After guarded bytes, allow the repository
  watcher and actual General-to-Hosts navigation. Verify live path/preferences and a
  reversible warning-toggle writeback; restore navigation. Never re-navigate before
  judging synchronization.
- **CmdPal:** pins/generic Recent removal do not prove fallback-history undo. Without
  same-kind live undo, obtain specific normal shutdown/reopen approval. Quiesce writers;
  remove only the unchanged attributed record from current state, preserving newer activity.
  No clearing history, force-killing or old whole-state replay. Close saves
  `LastWindowPosition`; account for it before cold reopening. Verify cache/files, UI/providers
  and any later writeback. This is not a generic recycling policy.
- **Theme:** capture same-PID caption legibility; preserve both Windows modes, back stack,
  expansion/scroll and minimized frame. Use the shared WinUI float-readback rule.
- **Conditional:** external auto-refresh remains unverified; it needs an isolated real editor and normal close.
  Notepad opening, disk reads/manual reload are not substitutes. Consent, full-Runner/
  borrowed-state lifecycle, CmdPal routes/pins, locale/CJK, clean install, faults and
  diagnostics retain their prerequisites/preservation gaps.

## References

[Checklist](../release-checklist/hosts-file-editor.md) |
[Inventory](../assertion-inventories/hosts-file-editor.json) |
[Recorder](../recording-workflow.md) |
[UI observations](../ui-observations.md) |
[Owned fixtures](../owned-fixtures.md) |
[File boundaries](../directory-snapshots.md).
