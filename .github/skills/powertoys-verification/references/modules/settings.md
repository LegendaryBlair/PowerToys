# PowerToys Settings - module verification profile

## Module facts

| Fact | Value |
|---|---|
| Scope / source | Main Settings, Home, General, module pages, tray, Quick Access, Welcome/OOBE, What's New/SCOOBE and shortcut conflicts; `src\settings-ui\` and `src\runner\` |
| Main UI | `<install>\WinUI3Apps\PowerToys.Settings.exe`, WinUI 3. Resolve install root from the attested Runner and rediscover HWND/PID/start time after lifecycle changes. |
| Companion | `PowerToys.QuickAccess.exe` is a separate process. Its native host can remain alive and visible to Win32 while DWM-cloaked; neither process existence nor `IsWindowVisible` proves an open flyout. |
| Main lifetime | One main window can coexist with secondaries in the same process. Closing main with a secondary open hides main, retaining its HWND. Closing the last secondary can close the hidden main and exit Settings. |
| Files | Under `%LOCALAPPDATA%\Microsoft\PowerToys`: root `settings.json`, `language.json`, `settings-placement.json`, `UpdateState.json`, plus module files affected by toggles/restarts/restore |
| Backup | `HKCU\Software\Microsoft\PowerToys`, value `SettingsBackupAndRestoreDir`; absence uses Documents `PowerToys\Backup`. Archives are ZIP-compatible `settings_*.ptb`. |
| Shared state | Home and Quick Access share root `dashboard_sort_order`. Settings/Quick Access rendered language, PowerToys theme and effective Windows app theme are separate observations. |

Use the [checklist](../release-checklist/settings.md) and [frozen inventory](../assertion-inventories/settings.json)
unchanged: 28 scenarios / 50 children. This profile describes operations, not replacement expectations.
Follow the [toolchain](../winapp-toolchain.md) and [recording](../recording-workflow.md) contracts.
Source identifiers below must be confirmed against the installed UI; newer source is not installed-build evidence.

## Entry paths

Before navigation, record borrowed versus created main/secondary identities and the original
desktop. Capture a borrowed main with `Get-PtSettingsUiSnapshot`. Close/reopen tests require
an owned Settings session; full PowerToys restart uses the shared
[`Restart-PtRunner`](../module-lifecycle.md#full-powertoys-restart) with preservation of affected
state. A borrowed main may opt into supported logical-state restoration with an originally
declared `AllowRunnerRestart=true` Settings resource. Neither that opt-in nor a full-checklist
request grants permission to discard unknown drafts in other UI.
Continue independent cases when a lifecycle fixture is unavailable.

| Intent | Entry | Destination / boundary |
|---|---|---|
| Observe/configure existing main | Resolve Settings PID plus main-shell landmarks; reuse its recorded identity. | Current page; not fresh-start or entry-point evidence. |
| Tray entry | Actual PowerToys tray icon -> Settings command. | Main visible; check destination and singleton reuse separately. |
| Module entry | Representative module's real Open settings control. | Requested module page in the same installation; Runner CLI is not a substitute. |
| Normal startup / recovery | Installed `PowerToys.exe --open-settings`; track relay separately from resident Runner. | Main visible; do not launch Settings without Runner IPC arguments. Post-crash recovery is Diagnostic. |
| Quick Access | Actual tray left-click/Quick access command, or physical configured chord when specified. | Uncloaked companion; identify its actual page and language. |
| What's New / Welcome | Specified Home/General What's New entry or Welcome navigation. | Secondary in Settings PID; retain origin page and identify the added HWND. |
| Shortcut conflicts | Home shortcut-conflict card after its data is loaded. | Separate Settings HWND; a legitimate empty conflict list is sufficient. Do not manufacture a collision or alter Ignore settings for the startup check. |

Tray icon captions may contain a version. Discover the actual icon in the tray or overflow;
do not hardcode versioned names. Record whether this run opened overflow and close it per case.
An already-open popup is not automatically test-owned.

## UI state-transition map

Main and secondary windows can coexist. `Page` is the current main content; arrival does not
mean every virtualized control is realized. Dismissed Quick Access is not disabled or exited.

| Current state | Trigger / condition | Next state | State landmarks |
|---|---|---|---|
| No Settings process | Normal Runner/tray entry | Main visible | New Settings identity and main navigation shell |
| Main hidden | Normal main entry; secondary remains | Main visible | Same main HWND visible; inspect destination |
| Main visible | Select realized navigation item | Page | Selected rail item plus page-specific landmark |
| Page | Expand a local group | Page | Expanded state and realized children |
| Home | Open utilities sort | Sort menu | Two checkable choices in current popup |
| Page | Open Quick Access shortcut editor | Shortcut draft | Owned capture dialog and commit/cancel controls |
| Shortcut draft | Save supported binding | Page | Draft closed; actual field readback |
| Shortcut draft | Cancel | Page | Draft closed without committed edit |
| General | Select a different language | Restart pending | Language restart InfoBar |
| Restart pending | Authorized real Restart | Restarting | Old Runner/Settings identities exit |
| Restarting | Fresh process/window readiness | Main visible | New identities/tokens; companion resolved separately |
| General | Select backup directory | Folder picker | New owned classic `#32770`, tree and buttons |
| Folder picker | Confirm directory | General | Picker absent; persisted path readback |
| Folder picker | Cancel | General | Picker absent; original path retained |
| General | Back up | Backup result | Status and completed archive state |
| General | Restore; changes require restart | Restarting | Restore status and requested restart |
| General | Restore; no changes/error | Backup result | Explicit result message, no presumed restart |
| Main visible | Open What's New/Welcome | Secondary | Added HWND and secondary navigation/content |
| Home | Invoke loaded shortcut-conflict card | Conflict window | Separate HWND, native/visible titles and conflict list or empty-state content |
| Conflict window | Close owned window; main remains visible | Home | Conflict HWND gone, Settings/main survive; normal entry can reopen it |
| Main visible | Close; secondary remains | Main hidden | Main not user-visible; secondary/process alive |
| Main visible | Close; no secondary | Settings exited | Last window/process gone |
| Secondary | Actual Settings footer action | Main visible | Main foreground; independently inspect selected page |
| Secondary | Close; visible main remains | Main visible | Secondary gone; main/process survive |
| Secondary | Close last secondary; main hidden | Settings exited | Hidden main closes; process exits |
| Quick Access hidden | Entry with launch page retained | Quick Access launch | Uncloaked host, launch tiles and More |
| Quick Access hidden | Entry with All apps retained | Quick Access All apps | Uncloaked host, module toggles and sort |
| Quick Access launch | More | Quick Access All apps | Toggles and sort action |
| Quick Access All apps | Back | Quick Access launch | Launch tiles and footer |
| Quick Access visible | Normal dismissal | Quick Access hidden | DWM cloaked; no exit requirement |

## Control locator and interaction index

`Id` = observed AutomationId, `Type` = UIA ControlType, `Class` = provider className,
`Name` = exact accessible caption in **that window's** language. `x:Name` is a source seed
to confirm; `x:Uid` is a resource key, not an Id. Never infer `ToggleButton` from "button".
Use the [scoped/typed query contract](../winapp-ui-testing.md#scoped-and-typed-queries):
verified HWND, one match, `hasMore=false`, fresh selector. If a complete typed result set
has several substring matches, select exact Id or Name uniquely, then requery that selector.
Do not retain volatile selectors after navigation, sorting, language or lifecycle changes.

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Identify main/secondary | Attested Settings PID; include hidden windows | Main `DashboardNavItem`/`GeneralNavItem`; secondary navigation/content and separately tracked HWND | Enumerate PID/class, then landmarks. English title and "one visible same-process window" are insufficient. |
| Reveal main rail/group | Main, correct rail viewport | Group IDs `InputOutputNavItem`, `FileManagementNavItem`, `SystemToolsNavItem`, `WindowingAndLayoutsNavItem`, `AdvancedNavItem`; pane button seed `PART_PaneButton` | Read expansion/compact state; use supported ExpandCollapse. Toggle pane only when needed, never blindly reopen an expanded group. |
| Select main page | Realized rail item in its group | Exact `*NavItem`; ID/Tag/page mapping in `Views\ShellPage.xaml` and handler | Supported Invoke, otherwise separately recorded guarded Click. Confirm selected item plus page-specific landmark. |
| Read page arrival | Main content, not stale rail | Home: observed `DashboardUpdateButton` or `UtilitiesCard`; General: `Languages_ComboBox`; Mouse Utilities: `MouseUtils_FindMyMouseToggleId` | Resolve current page's actual title/control. Do not require universal `Header` or treat an unrealized tree as blank content. |
| Observe navigation labels/badges | Main rail, corresponding Home cards and owned Welcome | `PowerPreviewNavItem`, `AltWindowCycleNavItem`, `ShortcutGuideNavItem` and their actual group owners; page-title resources `FileExplorerPreview.ModuleTitle` / `Shell_PowerPreview.Content` | Freeze build-matched expected labels/new-feature set first. Read title/selection separately from badge rendering; expand groups and reveal each relevant item. A missing UIA badge property needs approved pixels, not an inferred absence. |
| Expand update-channel card | General, actual Updates owner | Localized Update channel expander; children `StableUpdateChannelRadioButton` and `InsiderUpdateChannelRadioButton` where exposed | Expand with supported pattern and inspect description/choice rendering. Do not select a channel to prove this navigation/layout observation. Managed disabled choices do not mean a blank page. |
| Scroll content | Current content versus rail | Home `MainScrollViewer`; ordinary page `PageScrollViewer` when exposed; rail has separate `MenuItemsScrollViewer`/`FooterItemsScrollViewer` | Use current ScrollPattern/CLI selector; reveal needed controls and recheck positive bounds. Never choose the first scroller globally. |
| Sort Home utilities | Home card and current popup | Exact localized Sort utilities Button; `Type=MenuItem` choices Alphabetically/By status in actual language | Invoke menu, select, read both checked states and order at both scroll ends; reopen popup as needed. |
| Toggle Home utility | Utilities repeater, exact module owner | Module-identified row, then its local `Class=ToggleSwitch` with observed Type | Read state, invoke supported Toggle once, re-resolve the moved row. No first-match toggle in sorted content. |
| Toggle module page | Exact module page/control owner | Module profile locator; Find My Mouse observed `Id=MouseUtils_FindMyMouseToggleId` | Read/toggle, then independent shared lifecycle observation. Do not recreate the page during live-sync assertions. |
| Use tray/overflow | Current taskbar and owned popup | `Shell_TrayWnd`; optional `TopLevelWindowForOverflowXamlIsland`; exact `PowerToys v...` Button and Runner-owned `#32768` menu | Use shared `Invoke-PtRunnerTrayCommand` for Settings/Quick Access menu actions. Observe an ephemeral flyout in its `Observe` callback before popup cleanup. Actual left-click coverage remains a separate gesture. Never confuse Awake with Runner or assume `SystemTrayIcon` is unique. |
| Navigate Quick Access | Uncloaked companion HWND | Launch More Button / All apps Back Button by exact localized Name; `MoreBtn`/`BackBtn` are source resource keys | Supported Invoke or guarded Click; confirm page. Focused-name traversal is a scoped fallback, not fixed Tab counts. |
| Launch Quick Access module | Launch list, exact module tile | `Type=Button`, exact localized module Name | Supported Invoke/Click; observe actual module identity/action, not a substitute Named Event. |
| Sort Quick Access | All apps and sort popup | Localized Sort utilities Button and checkable `Type=MenuItem` choices | Read both states/order; dismiss normally and confirm `Test-PtWindowCloaked -Hwnd $qaHwnd`, then reopen. Shared `dashboard_sort_order` must be restored. |
| Toggle Quick Access utility | All apps, exact module row | Observed `Type=Button`, `Class=ToggleSwitch`, exact module Name | Supported Toggle; reread after reordering. Preserve the same already-open main page when checking live propagation. |
| Enable Quick Access | General Quick Access owner | Query `<localized Quick Access flyout> --root GeneralPageEnableQuickAccess --type Button --class-name ToggleSwitch` | Search with HWND/JSON, invoke unique supported Toggle, reread. Tray, editor and physical chord outcomes remain separate. |
| Edit Quick Access shortcut | General, expanded `GeneralPageEnableQuickAccess` | `Id=EditButton`, `Type=Button`, scoped to that owner | `Get-PtShortcutSnapshot -Hwnd $hwnd -PageAutomationId GeneralNavItem -SettingsPath $generalFile -PropertyPath @('quick_access_shortcut') -Workspace $workspace -WithinAutomationId GeneralPageEnableQuickAccess`; read the empty-binding boundary below first. |
| Select language | General language card | `Id=Languages_ComboBox`, `Type=ComboBox`, actual option label | `Select-PtComboBoxItem` with HWND, AutomationId and observed ItemName; compare locale persistence separately from rendering. |
| Observe attribution text/links | Each inventory-listed module page, realized secondary-links area | Actual localized hyperlink control names; `PageLink` is a data model, and `Attribution_*.Text` keys in `Strings\en-us\Resources.resw` plus page XAML are source seeds, not AutomationIds | Scroll the current page, read every listed attribution and its actual URI when exposed. Otherwise invoke the real link into a tracked owned browser tab and observe its destination; account for legitimate redirects. Close only that tab. Source URLs alone do not prove live link wiring. Proper names remaining untranslated are expected. |
| Restart without elevation change | Visible General language restart InfoBar | Exact localized Restart Button within InfoBar; source `Click_LanguageRestart` | Supply the actual UI invocation as `Restart-PtRunner -RestartAction`, with preparation and module/Settings readiness predicates. Dismiss owned popups and check the receiver. Do not substitute manual exit/relaunch for this button test. |
| Change startup/admin preferences | General matching cards, policy permitting | Source keys `GeneralPage_RunAtStartUp`, `Admin_Mode_Running_As`, `GeneralSettings_AlwaysRunAsAdminText`; discover actual card/local ToggleSwitch, CheckBox or Button | Scope by localized label and type; read then invoke supported action. UAC/reboot require separate authorized fixtures; no synthesized secure-desktop consent. |
| Select Settings theme | General appearance | Owner seed `ColorModeHeader`; `Type=ComboBox`, localized Theme Name | `Select-PtComboBoxItem` with HWND, ControlName and actual ItemName. Discover Windows-default caption; read root `theme` independently. |
| Observe opposite/live themes | Main Home/General plus owned What's New with release body loaded | Recorded native secondary HWND; rendered Markdown headings/links/body and native caption buttons | Establish effective Windows theme independently. Capture each opposite OS/app pair at narrow/wide sizes. For each live transition retain the same secondary HWND and release content; query/capture after changing only PowerToys theme. Reopening or an empty/loading release pane cannot prove live recoloring. |
| Change tray visibility | General tray card | `Id=ShowSystemTrayIconCard`, local observed `Type=Button`, `Class=ToggleSwitch` | Toggle/read; observe icon count. Keep Settings available to restore a hidden icon without relying on that icon. |
| Change adaptive tray option | Expanded tray card, icon enabled | Seed `ShowThemeAdaptiveTrayIconCard`, local `Type=CheckBox`, exact Name | Invoke/read. This checkbox is not the Windows-theme stimulus; verify effective OS theme independently. |
| Open backup picker | General backup card | `Id=GeneralSettingsBackupAndRestore`; location owner `GeneralSettingsBackupAndRestoreLocationText`; `pathTextBlock`; localized Select folder Button | Expand/read. Issue possibly blocking Invoke once in an owned bounded child; discover its modal separately. |
| Confirm/cancel directory | New owned `#32770` picker | Actual tree, exact owned destination and local OK/Cancel | UIA focus/selection and real expansion keys as supported; verify path/unchanged path and worker exit. No pointer-bearing `BFFM_SETSELECTIONW` messages. |
| Back up / restore | General backup card, private fixture ready | Separate exact Back up / Restore Button Names under `GeneralSettingsBackupAndRestore` | Invoke once, observe result/archive and actual restored data. Restore may restart Runner; visible controls do not prove the round trip. |
| Check updates | Installed General/Home update layout; isolation baseline recorded | Observed `GeneralOpenUpdateSurfaceButton` / `DashboardUpdateButton`, then current exact Check for updates action | Open surface and inspect state before invoking; never select Install/Download as a check substitute. Before cleanup or corrective navigation/toggling, compare the full enabled map/preferences and selected module runtime. Then inspect both last-checked labels and `UpdateState.json`; display and isolation are separate children. |
| Open What's New/Welcome | Specified origin page | Home observed `Name=WhatsNewButton`; actual General entry; `OOBENavItem` / secondary `WhatIsNewNavItem` where exposed | Preserve origin, activate that route and identify added HWND. Do not navigate Home first for General-origin return. |
| Return from What's New | Secondary navigation footer | `Type=ListItem`, `Class=Microsoft.UI.Xaml.Controls.NavigationViewItem`, exact localized Settings Name | Filter complete typed results, requery unique selector, check hit point, Click/Tap (`OpenSettingsItem_Tapped`). View-model names containing Settings are not the footer. |
| Open/read shortcut conflicts | Home shortcut-conflict card, then separately tracked HWND | `Type=Button`, actual localized name seeded by `ShortcutConflictControl_Automation`; secondary `titleBar` and `ConflictItemsControl` are source names to confirm | Invoke only after card data is loaded, even when conflict count is zero. Pair native title/process observation with the actual visible title and list/empty state. Close/reopen only an owned conflict window, without editing bindings or Ignore controls; no Welcome/What's New footer assumption. |
| Close owned window | Main/secondary, all siblings accounted for | Tracked HWND or scoped Close action | Normal close once; observe main hiding if a secondary survives. Require process exit only at the final-window boundary. |
| Resize/check layout | Original placement recorded | Native HWND, monitor work area and installed `WM_GETMINMAXINFO` limits | Use actual minimum, not a guessed narrow width; settle layout and inspect both scroll ends. Record default placement before fitting an owned fixture for another case. |
| Observe accessibility | Home heading/module controls | UIA name/state, supported heading observer and real screen reader | Verify property support first; CLI rejection of HeadingLevel is not a missing product heading. Names do not establish focus order or speech. |
| Generate bug report | General diagnostics, policy fixture authorized | Localized Generate package/Create bug report Button in its own card | Invoke once; track `PowerToys.BugReportTool.exe` and private output. Ordinary enabled state does not cover the policy variant. |

### Read-out notes

- Root fields are unwrapped: `enabled.<ModuleKey>`, `dashboard_sort_order` (0 Alphabetical,
  1 ByStatus), `enable_quick_access`, `quick_access_shortcut`, `theme`, `system_theme`,
  `show_tray_icon`, `show_theme_adaptive_tray_icon`, `startup`, `run_elevated`,
  `download_updates_automatically`, `include_prerelease_updates`,
  `show_new_updates_toast_notification`, `show_whats_new_after_updates`. Read through shared
  file I/O; page text and saved `is_elevated` do not replace token probes.
- `language.json` identifies selection, not successful localization. Inspect Settings and
  Quick Access independently after the requested restart; do not force a shared caption language.
  Attribution children cover all 12 listed pages, including both links on Color Picker,
  Mouse Utilities and File Explorer Add-ons. Observe the installed language resources:
  translator comments in source do not establish a shipped translation.
- `system_theme` is a cache, not effective Windows-theme evidence. Use an authorized reversible
  Windows theme UI/verified effective-state observer. `AppsUseLightTheme` write plus broadcast
  alone does not establish tray adoption or authorize a redraw verdict.
- Backup export/merge can normalize or omit fields. Compare the requested preferences
  semantically for product behavior; use separate byte/existence baselines for cleanup.
  Manifest metadata includes updated/unchanged files, version/time and source information;
  do not publish private backup contents or machine metadata.
- For update isolation, preserve two authorized module fixtures with an explicit on/off
  combination that differs from defaults. Use actual Settings toggles, then establish the
  **pre-check** baseline after those deliberate changes settle. Compare the entire enabled map
  and persisted user preferences semantically, not just the two fixture flags. Distinguish
  documented runtime metadata/cache fields from preferences and retain unexplained changes.
  Observe lifecycle-appropriate active/inactive behavior for the selected modules; event
  existence alone is not runtime proof. No cleanup/restoration result replaces this comparison.

### Observation rules

Confirm native identity, structural readiness, current scope and positive bounds before input.
Foreground and `IsOffscreen=false` alone do not establish clickability: use a recorded read-only
native/UIA hit test at the intended physical point and compare its receiver with the target.
A secondary footer can lie below the work area and hit the taskbar. Preserve that default
placement evidence before repositioning an owned window for an independent continuation.

Capture only approved surfaces. Prefer narrow typed footer queries over full rich release-body
inspection. If input desktop disappears, continue only proven UIA/window-capture observations,
not clicks/chords; do not equate an Active RDP session with available input.
Read the same page instance for live synchronization before any diagnostic navigation.

## Troubleshooting

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| Main HWND survives Close | Observe visibility and secondary/process lifetime; normally reopen main, then close final owned secondary. | Expected hiding, not automatically a close failure. No Runner kill/restart to force HWND destruction. |
| Page/group lookup fails | Inspect actual page landmark, parent expansion/viewport and current bounds; requery exact ID/type. | Universal Header, substring and zero-size assumptions are driver bugs. For process exit, correlate PID/time with Application Error/WER before more UIA. |
| Secondary Settings query has many matches | Exact localized footer Name from a complete NavigationViewItem set, then unique-selector requery. | Release view-model class names are not valid alternate targets. |
| Secondary UIA searches time out although release content is painted | Review a fresh passive capture. If scoped UIA queries and point observations expose only host panes, use an explicitly recorded visual locator plus exact native-window hit testing; retain the producing image and geometry. Fit only an owned secondary before input when its footer is outside the work area. | UIA timeout does not prove blank product content. A historical image is a locator, not fresh PASS evidence; require current painted-target evidence and observe the actual foreground/destination after the click. |
| Restart/footer click has no effect | Close owned tray popup; inspect click receiver and work area, then record a valid attempt separately. | Injection success is not handler receipt; preserve faulty default placement and origin-page result. |
| Quick Access language differs | Resolve its own process/captions and compare actual rendering after restart. | Do not relabel a reproducible localization mismatch as a selector-only failure. |
| Module toggle stays stale | Read same open page, companion, root flag and native runtime before navigating. | Page recreation diagnoses but does not satisfy live sync. Home-origin and Quick Access-origin are independent directions. |
| Original shortcut is unassigned | Inspect all six fields; current shared snapshot refuses `code=0`/empty bindings. | Unresolved preservation capability, not permission to seed defaults. Non-chord enablement observations remain independent. |
| Heading/speech API unavailable | Establish supported observer and real keyboard/speech fixture before this case. | UIA Name or source attributes cannot prove headings, traversal or spoken output. |
| Folder picker Invoke blocks | Retain initiating worker and owned modal; navigate/cancel without replaying Invoke; wait for worker exit. Probe native control classes before assuming an editable address field. When picker/main UIA enumeration stalls, guarded Escape can cancel the exact owned modal without another tree scan. | Classic-picker adapter needs acceptance; a tree-only dialog without an Edit control or Ctrl+L address route is not a modern address picker. Do not bypass selection with a registry write or pointer-bearing cross-process messages. |
| Theme registry matches but tray is unchanged | Establish effective OS transition and actual icon capture, independently of Settings theme. | Registry readback alone proves neither redraw nor product failure. |
| What's New is loading or was recreated during theme change | Preserve the recorded HWND and wait for actual release content; collect before/after rendered evidence. | Theme selection/JSON alone is not Markdown/caption recoloring. Live-transition and static-theme children remain independent. |
| Attribution/NEW badge expectation is uncertain | Match the tested release's resource and feature inputs, then inspect the realized target surface. | Do not use a newer checkout or the observed UI to define its own expected result; block only the unresolved child. |
| Shortcut-conflict card does nothing | Confirm Home's conflict data is loaded and inspect the current card/entry target before a separate valid attempt. | Zero conflicts is a supported empty state, not a reason to mutate user shortcuts. Missing-resource fault injection is outside ordinary startup coverage. |
| All-module/backup flow remains controls-only | Establish its full resource plan before mutations. | One representative or visible Back up button is not the composite case; list missing work explicitly. |
| Update offers installation or is up to date | Record actual build/channel/state and split check observations from installation-dependent remainder. | No build replacement, fake offer or live JSON corruption to manufacture prerequisites. |
| Update activity remains over other pages | Discover the installed in-window `UpdateActivitySurface`; after a test-opened check, invoke its scoped `DismissUpdateActivityButton` and verify the surface is no longer visible. | No extra native window is required for this surface. Native popup absence or a restored selected page alone does not certify its dismissal. |
| Resize captures show stale layout or missing imagery | Native placement readback can precede XAML/compositor layout and asset completion. Allow rendering to settle, inspect the first capture and reobserve only affected conditions before judging clipping or theme contrast. | Keep transitional captures in history; do not score them as settled product layout. Confirm caption contrast with the intended window foreground and the correct OS/app pair. |
| Restart is refused despite Settings restart opt-in | Inspect every affected borrowed resource. Declare Quick Access as an originally restartable borrowed Window with exact HWND/path and logical-state cleanup; register its verified replacement after `Restart-PtRunner`. | Main Settings opt-in does not release another window's same-instance contract. Do not remove that record or rewrite the baseline. Restoration checks the companion's actual page/cloak/preferences, not just its new PID. |
| Scroll restoration differs after layout or command quantization | Use the shared final-placement/settled-extent restore and exact-or-float32 WinUI readback comparison; retain its transition receipt and original raw values. | A material difference is not quantization. Do not broaden tolerance, overwrite the baseline or ignore page/expansion differences. |
| Secondary-window flow leaves multiple main navigation items selected in UIA | Record item identities and the containing `SelectionPattern`. If the same container reports only the original page, disallows multiple selection and does not require selection, an explicitly recorded `RemoveFromSelection` on a contradictory stale item can be attempted. Then compare the complete unchanged original snapshot. Restore desktop state independently even if page restoration throws. | This is a supported UI operation, not permission to filter away an observation. If the owner is ambiguous or the full comparison fails, stop dependent mutations and retain the unresolved receipt; never replace the baseline or restart a borrowed process to manufacture cleanup success. |
| Recorder/API error or screenshot warning | Use producing-attempt evidence and documented parameter/taxonomy contracts. | Wrong Kind, `$HOME` collisions, deadline inversion and PASS-only screenshot diagnostics need driver/helper fixes, not additional product FAILs. |

## Fixtures and restoration

### Resource inventory

| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| Root/language/placement files | Preferences, navigation, close/reopen/restart | Original bytes/existence and full preference map before first write | UI reversal; guarded rollback after relevant writers settle | Exact bytes/absence plus intended runtime state |
| Main and every secondary HWND | Entries, layout, theme, lifetime | Borrowed/created identities, visibility, native placement and supported page/scroll/expansion | Borrowed windows survive; owned close follows hide/exit rules | No owned orphan; surviving borrowed identity/state preserved |
| Runner/resident/child processes | Restart, all-module matrix, backup restore | Original tokens/identities, authorized replacement, per-module model and indirect helper creation | Restore original enabled/runtime states; stop owned helpers | Correct executable/package, token and readiness, not process-name counts alone |
| Representative utility / Find My Mouse | Cross-surface changes | Owned target; original module files/state; original page instance and companion | Reverse UI transition and attributed file rewrites | Both propagation directions independently observed; unrelated modules unchanged |
| Complete module set | All-off/on restart matrix | Each flag, files/sidecars, lifecycle model and special policy/hardware conditions | Per-module reverse transitions/cleanup; no forced policy-managed enablement | Every required flag and representative runtime type; no hidden missing variants |
| Tray, overflow, Quick Access | Tray/sort/chord/enablement | Original icon option, popup/flyout state, shared sort, binding and process | Per-case owned popup dismissal; restore settings/cloak/page; release owned providers | No interception of later input or leaked headless helper |
| Shortcut dialog | Assignment/Reset | Original six-field binding; empty branch needs separately proven restoration | Shared same-UI restore for supported schema; cancel owned draft on failure | Original fields and actual old/new/restored chord as required |
| Shortcut-conflict window | Secondary startup/title | Borrowed/created HWND and current conflict/Ignore data; no shortcut mutation needed | Close only owned conflict HWND; preserve borrowed UI | Native/visible titles and startup observed before close; no altered bindings/Ignore state |
| Private backup directory and metadata | Long-path backup/restore | Unique directory outside settings root and evidence/sync; original registry kind/value/existence | Restore original location; remove only owned archive/staging/extraction paths | No user backups touched; private payload not archived as evidence |
| Full backup-selected file set | Actual Restore | Every file selected by tested export configuration, including original absence; not just two test values | Original preference restoration and guarded files after product restore/restart | Product values match backup; user baseline compared separately |
| `UpdateState.json` / channel preferences | Update checks | Original bytes/existence; current offer/install fixture distinct | Wait for check writer, restore attributed cache/preferences | Original state; no download/install disguised as a check |
| Update-isolation module pair | Last-checked/isolation case | Full original state plus a separate settled pre-check enabled/preference baseline after authorized fixture toggles | Preserve immediate post-check evidence first, then reverse fixture toggles and restore attributed files | Pre-check/post-check preference equality and actual module runtime; final baseline restoration is a separate result |
| Windows theme/language surface | Appearance/localization | App and effective OS state; independent Windows Settings page/placement if used | Reverse through authorized UI, required restart before final comparison | Separate rendered state, raw registry kind/existence and original navigation |
| Attribution-link browser tab | Localization when actual URI is not exposed | Original browser/tab set, exact test-created tab and observed destination | Close only the owned tab; preserve original browser/foreground | No user tab closed or left changed; a typed URL is not a substitute for the product link |
| Disposable install/reboot/update/GPO fixture | Conditional destructive cases | Explicit environment authority, full rollback and report persistence | Environment-specific restore; no deletion of live user settings | Actual conditional behavior, not current configured values |
| Bug report / product logs | Authorized diagnostics | Exact owned worker/archive; original policy; shared-read log offsets | Remove owned private package, retain legitimate log appends | Worker exit and policy restored; no private diagnostic payload disclosure |

### Helper boundaries

Use [session safety](../session-safety.md), [paired snapshots](../helper-workflow.md),
[directory snapshots](../directory-snapshots.md) and the [shortcut recorder](../shortcut-recorder.md).
The Settings inventory does not automatically provide the four-module aligned ResourcePlan
adapter. Wire actual Settings resources explicitly; a window snapshot is not an application backup.

The shared Settings UI snapshot normally restores the **same surviving** main window. With
original `AllowRunnerRestart` opt-in and a recorded `Restart-PtRunner` transition, use
`Restore-PtSettingsUiSnapshot -ReplacementIdentity` for the independently resolved new main.
Both routes restore supported page/scroll/expansion/placement, not Quick Access/OOBE, IME,
drafts or every module file. Original identities remain in the immutable receipt.

Empty shortcut/Reset rollback, bounded classic-picker handling, effective OS-theme observation
and heading/speech observation are capability gaps to resolve before their mutations.
This profile does not claim those shared adapters have been implemented.
Attribution-link activation likewise requires an actual owned-tab observer/cleanup plan;
an unavailable browser adapter blocks that link observation, not unrelated localized text.

For backup, choose the checklist's reversible General/module values, private directory and
complete affected-file baseline first. Execute real selection -> backup -> changes -> restore
-> restart/readback. Product retention and extraction can touch backup/temp directories;
do not use the user's populated backup location. Exported semantic equality does not waive
the separate exact cleanup baseline.

### Restoration order

1. Finish observations, cancel owned drafts/pickers and dismiss owned tray popups. Restore
   utility preferences, shared sort, supported bindings and original enablement through UI.
2. Restore language/theme/startup/elevation through authorized routes. Perform required final
   restart now; reattest identities/tokens and account for startup/module-sidecar writes.
3. Restore owned placement, then close windows by their actual lifetime and stop owned helpers.
   Restore pointer before its last ordinary interaction window closes or elevated foreground returns.
4. After relevant writers settle, compare attributed differences and apply guarded byte/kind/existence
   rollback, including placement/update/module sidecars. An explained `system_theme` cache change is
   not permission to ignore arbitrary preference differences or unknown external writes.
5. Independently compare files, registry, runtime, borrowed UI and owned-resource absence;
   restore foreground/pointer. Remove private recovery only after success. No restart/cache refresh
   follows final comparison.

### Restoration verification

Report exact storage, supported UI and runtime readiness separately. Authorized restarts change
PIDs but must preserve intended token/module state and executable identities. Without restart
authority, borrowed identities survive. Record expected log appends instead of restoring live logs.

### Execution notes

Map required observations before batching: Home-origin propagation is not Quick Access-origin
live sync, and all-utilities persistence is not a representative smoke test. Reuse compatible
fixtures without dropping composite conditions or changing frozen `Items`. Use
`Add-PtVerificationDispositions` for missing coverage and the recorded `-Report` callback for
source/statistics work, not empty artifact-only attempts.

## References

### Source citations

Paths are repository-relative; validate against the installed revision/provider before use.

- `src\settings-ui\Settings.UI\SettingsXAML\MainWindow.xaml.cs`: `Window_Closed`, `CloseHiddenWindow`;
  `SettingsXAML\App.xaml.cs`: `OpenSettingsWindow`, `IsSecondaryWindowOpen`, secondary closed handlers.
- `src\settings-ui\Settings.UI\SettingsXAML\Views\ShellPage.xaml` and `.xaml.cs`: navigation mapping;
  sibling `DashboardPage.xaml`: utilities/sort/layout; `GeneralPage.xaml` and `.xaml.cs`: preference controls,
  `Click_LanguageRestart`, backup picker and Windows-color entry.
- `src\settings-ui\Settings.UI\ViewModels\GeneralViewModel.cs`: preference/restart/backup commands;
  `src\settings-ui\QuickAccess.UI\QuickAccessXAML\Flyout\LaunchPage.xaml`, `AppsListPage.xaml`
  and `src\settings-ui\QuickAccess.UI\ViewModels\AllAppsViewModel.cs`: companion actions/shared sorting.
- `src\settings-ui\Settings.UI\SettingsXAML\ScoobeWindow.xaml` and `.xaml.cs`:
  `OpenSettingsItem_Tapped`, release navigation and placement; `OobeWindow.xaml` and `.xaml.cs`: Welcome lifetime.
- `src\settings-ui\Settings.UI\SettingsXAML\Controls\Dashboard\ShortcutConflictControl.xaml`
  and `.xaml.cs`: `ShortcutConflictBtn_Click`; `ShortcutConflictWindow.xaml` and `.xaml.cs`:
  constructor/title and conflict content; `App.xaml.cs`: `OpenShortcutConflictWindow`.
- `src\settings-ui\Settings.UI\SettingsXAML\OOBE\Views\ScoobeReleaseNotesPage.xaml.cs`:
  `OnActualThemeChanged`, `RefreshMarkdownTheme`; its XAML supplies the rendered Markdown.
- `src\settings-ui\Settings.UI\Strings\en-us\Resources.resw`: `Attribution_*.Text`,
  `FileExplorerPreview.ModuleTitle`, `Shell_PowerPreview.Content`; affected page XAML:
  `SettingsPageControl.SecondaryLinks`. `ViewModels\DashboardViewModel.cs` and
  `OOBE\ViewModel\OobeShellViewModel.cs`: corresponding new-feature badge definitions.
- `src\settings-ui\Settings.UI\ViewModels\UpdateViewModel.cs`: `CheckForUpdates`;
  `src\runner\settings_window.cpp`: `check_for_updates` action dispatch.
- `src\settings-ui\Settings.UI.Library\GeneralSettings.cs`: root schema;
  `SettingsBackupAndRestoreUtils.cs`: `BackupSettings`, `RestoreSettings`, `GetLatestSettingsFolder`,
  export/merge, manifest and retention.
- `src\settings-ui\Settings.UI\Helpers\WindowHelper.cs`: `settings-placement.json`;
  `src\runner\settings_window.cpp`: Settings/restart IPC; `src\runner\tray_icon.cpp`: tray gating/theme.
