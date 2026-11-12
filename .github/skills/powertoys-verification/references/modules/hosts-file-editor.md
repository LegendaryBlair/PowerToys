# Hosts File Editor - module verification profile

## Module facts

Discovery-stage, not signoff. Build identities, coverage and history stay in archives.

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

Preserve [originals](#fixtures-and-restoration) before startup pruning. Borrowed drafts
stay untouched. Measure controller, Runner, Settings and editor tokens separately.
Never automate secure-desktop consent or change accounts.

| Intent | Entry |
|---|---|
| Settings | Preserved main window: `HostsNavItem`, then `HostsLaunchButtonControl`. |
| Warning | Set the real preference; launch a fresh owned editor. |
| Tray | Actual Quick Access Hosts launcher, not a shared event. |
| Downstream action | `Invoke-PtSharedEvent -Name 'Hosts.Show'` or `'Hosts.ShowAdmin'`; declared ownership. |
| Writer mechanics | Owned direct elevated launch; not Settings/UAC evidence. |
| Command Palette | PowerToys extension; preserved query/history/customization/provider. |

Missing consent blocks only dependent routes, not independent ordinary/read-only work.

## UI state-transition map

Settings, external editors and Hosts can coexist. Observe arrival before continuing.

| Current state | Trigger / condition | Next state | State landmarks |
|---|---|---|---|
| No editor | Launch, warning on | Startup warning | Accept / Quit |
| No editor | Launch, warning off | Entries | `Entries` List / New entry |
| Startup warning | Accept | Entries | Warning dismissed; toolbar usable |
| Startup warning | Quit | No editor | Owned process exits |
| Entries | New entry; no modal | Entry draft | Add new entry popup; field edits |
| Entry draft | Valid Add | Entries | Modal closes; list available |
| Entry draft | Cancel | Entries | Draft dismissed |
| Entries | Filters | Filter flyout | Filter edits / Clear filters |
| Filter flyout | Dismiss | Entries | Popup closed; query can remain |
| Entries | Additional content | Content draft | `AdditionalLines` / Save / Cancel |
| Content draft | Save | Entries | Modal closes |
| Content draft | Cancel | Entries | Draft dismissed |
| Entries | External change | Reload available | Change notice / Reload |
| Reload available | Reload | Entries | Loading finishes; list realized |
| Entries | Normal owned close | No editor | Tracked window/process exits |

Never invoke underlying New entry while another ContentDialog is open.

## Control locator and interaction index

Use shared identity/UIA helpers and `Invoke-PtWinApp`; reacquire after transitions.
Names below describe English.

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Navigate | Preserved Settings rail | AutomationId `HostsNavItem`, current parent group | Reveal group; Select; wait for launch card. |
| Launch | Enabled Hosts page | `HostsLaunchButtonControl` | Guarded click if Invoke throws; observe identity. |
| Set privilege | Hosts page | `ToggleSwitch` inside `HostsToggleLaunchAdministrator` | Set/read state; fresh launch establishes token/consent. |
| Set warning | Hosts page | `ToggleSwitch` inside `HostsToggleShowStartupWarning` | Toggle/read persistence; observe fresh launch. |
| Enable Hosts | Hosts page | `ToggleSwitch` inside `HostsEnableToggleControlHeaderText` | Toggle only Hosts; compare UI/storage/availability. |
| Accept / quit | Current warning | Exact Button Name Accept / Quit | Invoke; observe dismissal / process exit. |
| Open draft | Entries, no modal | Button Name New entry | Invoke once; wait for actual popup fields. |
| Enter draft | Current Add new entry popup | Exact Edit Names Address, Hosts, Comment | ValuePattern.SetValue and actual readback; no clipboard needed. |
| Commit / cancel | Same modal | Button Add / Cancel; `PrimaryButton` / `CloseButton` if exposed | Unique Invoke; observe closure/file separately. |
| Locate row | `Entries` List | Complete tagged hostname token in TextBlock; ListItem ancestor | One runtime identity; hostname/comment may share text. |
| Change Active | Exact owned ListItem | `ToggleSwitch`, Name Active | Read/toggle once if needed; reacquire; compare UI/file. |
| Filter | Current flyout | Filters; popup Edits Address / Hosts / Comment; Clear filters | Resolve popup/owner; set, observe, clear/dismiss. |
| Reload | Change notification | Button Name Reload | Invoke once; wait for list readiness before checking results. |
| Additional content | Current content modal | Edit `AdditionalLines`; Save / Cancel | Privately retain original value; append owned comment; set/commit. |
| Content position | Hosts Settings | ComboBox inside `HostsAdditionalLinesPosition` | Resolve current Top/Bottom popup item; Select/read back; editor commit separately. |
| Backups | Backup expander | Toggle, browse Button, retention ComboBox, NumberBox edits | Scope cards; real picker/numeric commit; observe lifecycle. |
| Open externally | Entries toolbar | Button Name Open hosts file | Operate control; identify resulting document/tab before closure. |
| Close editor | Creation/siblings | Exact PID/start/path and HWND | Register siblings; `Stop-PtOwnedProcess` / `Close-PtTrackedWindow`; verify exit. |

### Read-out notes

- `x:Name="EntryDialog"` need not be an AutomationId. The actual modal can be a
  Window named Add new entry, Class Popup, under the main tree; its separate
  `Microsoft.UI.Content.PopupWindowSiteBridge` may have an empty subtree.
  Query actual scopes and deduplicate runtime IDs with `Select-PtUniqueUiElement`.
- If CLI `--root` remains ambiguous despite one native runtime identity, preserve
  the error and use that identity-checked element's supported UIA pattern.
- Boolean `.value` fields: `ShowStartupWarning`, `LaunchAdministrator`,
  `LoopbackDuplicates`, `NoLeadingSpaces`, `BackupHosts`. Unwrapped fields:
  `AdditionalLinesPosition`, `Encoding`, `DeleteBackupsMode`, `DeleteBackupsDays`,
  `DeleteBackupsCount`, `BackupPath`. Storage paths are not UI selectors.
- Read live files privately with `Read-PtSharedFileBytes/Text`; expose only synthetic
  data/hashes. Drafts/settings are not writes; file reads are not editor auto-refresh.
- Fixed-Notepad builds ignore the default-editor association for Open hosts file.
- Capture only synthetic rows/fields, notices or titles. Use passive physical
  bounds and foreground checks; refocusing the main HWND can dismiss a popup.

## Troubleshooting

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| SettingsCard Invoke throws | Query current card; guarded click if supported. | Provider failure is not product launch failure. |
| Draft/row lookup fails | Inspect actual modal state, popup identities, combined hostname/comment text and realization. | Repeating a failing observer does not prove absence. |
| Save error | Check actual token, attributes and permissions; retain unchanged-file evidence. | No Make writable, ownership changes or ACL weakening for coverage. |
| Post-state guard refuses | Stop mutations; compare privately with original plus recorded operation. | Never adopt unexplained fresh bytes; predictor errors are not product defects. |
| Retention seems ineffective | Check real path, policy, creation times/count and fresh elevated startup. | Reused processes do not rerun startup pruning. |
| Capture dismisses dialog | Retain invalid capture; observe without activation. | Capture-induced transitions are not user behavior. |
| Activation unresolved | Check executable candidates/original state; retain ledger failure. | Current restoration differs from historical uncertainty. |
| Borrowed state unsupported | Identify missing draft/tab/query/cache preservation before action. | Nonempty alone is not a blocker; infrastructure gaps are not product FAILs. |

## Fixtures and restoration

### Resource inventory

| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| Live hosts | Potential writes | Shared original bytes/existence, BOM/newlines, attributes and security descriptor | Quiesce owned writers; guarded existing-file rollback | Exact originals; unknown changes retained |
| Preferences | Settings/startup | Private module/general originals; only declared UI changes attributed | Real UI/cache first; guarded bytes after last writer | Original controls/cache and files |
| Backups | Before elevated launch | Explicit existing names/bytes/metadata; no ownership inferred | Preserve unowned files; remove attributable new backups only | Original set/content/metadata |
| Retention folder | Policy cases | New owned folder, explicit fixtures/times/sentinel | Restore location/policy; remove owned fixtures | Original backup location and sentinel unaffected |
| Editor/popups | Core operations | Exact creation and native siblings; borrowed drafts untouched | Cancel owned drafts; normal close | Original absence or borrowed state retained |
| PowerToys Settings | Navigation | Shared snapshot before navigation | Shared page/expansion/scroll/placement adapter | Fresh supported UI comparison |
| External document | Open/auto-refresh | New document; original tabs/selection/drafts | Close new document; restore selection/placement | Original tabs/process unchanged |
| Palette/provider | Extension | Private query/page/history/customization and identity baseline | UI/cache restoration, attributable files, owned lifetime cleanup | Original behavior, not hashes alone |
| Desktop/clipboard | Input/capture | Original foreground/pointer; private keeper if writing clipboard | Pointer before foreground; clipboard before owner release | Fresh comparisons; no private payload |

### Helper boundaries

Use the [shared resource plan](../session-safety.md), not a module orchestrator.
`Get-PtFileSnapshot` captures bytes/existence, not permissions or caches. Guarded
`Restore-PtFileSnapshot -ExpectedState` requires existing regular files and uses one
exclusive handle. It cannot safely restore original absence. Do not bypass directory
helpers' system-root refusals or create a missing file just to satisfy that API.

Privately predict the exact post-state from original data and intended synthetic
operations, or provide another proven attribution method. Account for normalization
without accepting unrelated changes. Keep single-host collections as arrays:
PowerShell string indexing must not truncate original hostnames. The attribution
model authorizes rollback, not product PASS.

Notepad's helper owns its generated fixture, not an arbitrary hosts document; never
forge its receipt. New tabs need before/after runtime identities and restoration.
An isolated real editor tests auto-refresh, not the product's Notepad entry.

### Restoration order

1. Stop input; cancel owned drafts. Restore Settings values through real UI,
   retaining original cache values and byte guards.
2. Normally close owned documents/writers; register siblings. Do not terminate
   borrowed singletons or select processes only by name.
3. Guardedly restore files and authorized metadata without weakening protection;
   remove only owned new backups.
4. Restore navigation/placement, pointer and foreground. Verify after the last
   startup/UI operation; no cache refresh after declaring completion.

### Restoration verification

Report file/metadata, backup-set, editor/cache, supported Settings UI and desktop
comparisons separately. Original editor absence requires all owned editors to exit.
Retain conflicts and historical failed cleanup after current recovery. Keep private
originals until dependent restoration is verified.

## References

[Checklist](../release-checklist/hosts-file-editor.md) |
[Inventory](../assertion-inventories/hosts-file-editor.json) |
[Recorder](../recording-workflow.md) |
[UI observations](../ui-observations.md) |
[Owned fixtures](../owned-fixtures.md) |
[File boundaries](../directory-snapshots.md).
