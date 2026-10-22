# PowerToys Settings - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - standard-user coverage, subject to the stated fixtures.
- `[ADMIN: YES]` - requires an authorized elevated session.
- `[ADMIN: COND]` - retain ordinary and elevated variants independently.
- `[ID: ...]` - stable scenario identifier; retain every required child/input observation.

## Fixtures & conventions

- **State backup**: before the run, copy `%LOCALAPPDATA%\Microsoft\PowerToys\settings.json`, the
  Settings backup metadata, and every module settings file that a case will mutate. Record the
  initial enabled state of every module. Restore the exact original state, not an assumed
  "all enabled" state.
- **Representative module**: use one isolated, launchable module with a deterministic Named Event
  or visible process (for example Color Picker) for cross-surface enable/disable checks. Use
  **Find My Mouse** for the mouse-utility Quick Access case.
- **Quick Access**: distinguish the flyout launch page from **All apps**. Record the original
  Quick Access enabled state, shortcut, and sort order.
- **Elevation**: record the Runner and Settings process integrity levels before and after every
  restart. Never infer elevation only from the page text.
- **Isolated cases**: the reboot, clean-profile, and update-installation cases must run in
  a disposable VM or an explicitly approved machine state. Preserve the report across reboots.
- **Policy fixtures**: use an authorized policy scope, preserve its original state, and restore
  that baseline afterward. A user-controlled switch being Off does not establish policy enforcement.
- **Appearance and language**: record the original PowerToys theme, Windows app theme, display
  language, tray-icon options, and update-notification options; restore them in `finally`.
- **Build-dependent presentation**: establish expected localized labels and the new-feature
  badge set from the tested build's resources/release inputs before observing the UI.
- **State hygiene**: close only Settings, Quick Access, OOBE/SCOOBE, and fixture windows opened by
  the current case. Do not terminate unrelated user applications.
- See the [module profile](../modules/settings.md) for control interaction and restoration mechanics, and use the [frozen inventory](../assertion-inventories/settings.json) without run-local regrouping.

## PowerToys Settings (25 items)

### Settings shell and Dashboard

- [ ] **Main window and entry routes** [ID: SET-MAIN-WINDOW] [ADMIN: NO]
  Open **PowerToys Settings** from the tray context menu and confirm one window opens on **Home**. Invoke Settings again from the tray and from a module's **Open settings** action; confirm the existing single Settings window is focused and navigates to the requested page rather than creating duplicate main windows.

- [ ] **Navigation, page titles, and feature badges** [ID: SET-NAVIGATION] [ADMIN: NO]
  Expand every navigation group and open every visible module page once. Confirm matching page titles and navigation selection without a crash or blank page. Open General and expand the update-channel card; its description and choices must render without a navigation error. Confirm the File Explorer Add-ons rail label and page title agree in the selected language. Check module/group NEW badges against the tested build's declared new-feature set, including Window Hopper and Shortcut Guide, and confirm Home and Welcome agree with that set.

- [ ] **Home and Quick Access sorting and persistence** [ID: SET-DASHBOARD-SORT] [ADMIN: NO]
  On **Home**, switch the Utilities card between **Alphabetical** and **By status**. Confirm exactly one sort choice is checked, card order matches the selection, and the selected order persists after closing every Settings window and reopening.
  In Quick Access **All apps**, independently switch between **Alphabetical** and **By status**. Confirm the choices are mutually exclusive, each order is correct, and the selected order is retained after closing and reopening the flyout. Verify both surfaces and their distinct reopen boundaries; one surface's result does not substitute for the other.

- [ ] **Dashboard enablement propagation** [ID: SET-DASHBOARD-STATE] [ADMIN: NO]
  Open a representative module page and record its enabled state, leave Quick Access open on **All apps**, then return Settings to Home and toggle that module from the Utilities card. Reopen the module page and confirm its toggle, Quick Access, general `settings.json`, and the Runner's actual module state all match the new value. Re-enable it and confirm its deterministic action works again without restarting Windows.

- [ ] **Responsive dashboard layout** [ID: SET-DASHBOARD-LAYOUT] [ADMIN: NO]
  Resize Settings from wide to its minimum supported width and back while Home contains enough cards to scroll. Confirm the update/shortcut controls and Utilities card reflow below the main cards, no giant empty scroll region appears, and no card, toggle, or navigation content is horizontally clipped.

- [ ] **Dashboard keyboard and screen reader** [ID: SET-DASHBOARD-ACCESSIBILITY] [ADMIN: NO]
  Navigate Home with keyboard and a screen reader. Confirm heading navigation reaches the **Home** level-1 heading and each dashboard card level-2 heading, focus order follows the visual order, and every module toggle has an accessible name and state.

### Startup and administrator mode

- [ ] **Restart and retain administrator choice** [ID: SET-RESTART-ADMIN] [ADMIN: COND]
  From a non-elevated run, click **Restart as administrator**, approve UAC, and confirm Runner and Settings are elevated. Check **Always run as administrator**, restart PowerToys, and confirm it returns elevated. Clear the checkbox, restart through the non-admin path, and confirm both processes return to medium integrity.

- [ ] **Automatic startup across reboots** [ID: SET-STARTUP] [ADMIN: YES]
  In a disposable VM, enable **Run at startup** and **Always run as administrator**, reboot, and confirm PowerToys starts elevated without a UAC prompt. Then clear **Always run as administrator**, reboot again, and confirm PowerToys starts automatically at medium integrity. Restore the original startup and elevation settings.

### Module enablement persistence

- [ ] **Persist every module state** [ID: SET-MODULE-STATES] [ADMIN: NO]
  Record every module's initial state, turn every available module off from Home, restart PowerToys, and confirm every toggle remains off, representative module processes/events/hotkeys are inactive, and the shortcut card empty state reads **No shortcuts to show.** with one period. Turn every module on, restart, confirm every toggle remains on and representative in-process, standalone, and shell-extension modules respond, then restore the recorded initial state.

### Quick Access

- [ ] **Quick Access enablement and entry routes** [ID: SET-QUICK-ACCESS-STATE] [ADMIN: NO]
  Enable Quick Access and confirm tray left-click opens the Quick Access flyout while tray right-click shows **Quick access** as the first command and opens the same flyout. Disable Quick Access and confirm tray left-click opens PowerToys Settings instead, the Quick Access shortcut control is disabled, the configured chord no longer opens the flyout, and the tray context-menu **Quick access** command is removed. Re-enable Quick Access and confirm the command and flyout entry points return.

- [ ] **Launch a module** [ID: SET-QUICK-ACCESS-LAUNCH] [ADMIN: NO]
  From the Quick Access launch page, invoke a representative launchable module and confirm its expected window/action appears exactly once. Close only the fixture window and confirm the flyout remains reusable.

- [ ] **Live Mouse Utilities state propagation** [ID: SET-QUICK-ACCESS-SYNC] [ADMIN: NO]
  Keep Settings open on the **Find My Mouse** page and Quick Access on **All apps**, choose **By status**, then disable Find My Mouse from Quick Access. **Without navigating away from or recreating the Mouse Utilities page**, confirm its open-page toggle and Home toggle update immediately, it moves to the disabled group without reopening the flyout, and its launch action disappears or becomes unavailable. Re-enable it and confirm the same existing page, Home, Quick Access, and the module action recover.

- [ ] **Change and reset the shortcut** [ID: SET-QUICK-ACCESS-BINDING] [ADMIN: NO]
  Assign Quick Access an unused shortcut and confirm the new chord opens the flyout while the old chord does not. Reopen the shortcut editor, click **Reset**, and confirm Settings does not crash, all shortcut key/modifier fields clear, the chord no longer opens Quick Access, and the cleared state persists after reopening Settings.

### Tray icon, appearance, and localization

- [ ] **Tray icon visibility** [ID: SET-TRAY-VISIBILITY] [ADMIN: NO]
  Toggle **Show system tray icon** off and confirm the PowerToys icon disappears while Runner remains active and Settings stays usable. Turn it on again and confirm exactly one icon returns and both left-click and right-click actions still work.

- [ ] **Theme-aware tray icon** [ID: SET-TRAY-THEME] [ADMIN: NO]
  Enable **Use theme-aware tray icon**, switch the Windows app theme between Light and Dark, and confirm the icon redraws to remain visible in each theme without restarting PowerToys or creating a duplicate icon. Disable the option and confirm theme changes no longer select the adaptive variant.

- [ ] **Coherent Settings themes** [ID: SET-THEME] [ADMIN: NO]
  Switch PowerToys Settings through Light, Dark, and **Use Windows setting**, checking Home, General, and What's New at narrow and wide sizes. Confirm navigation, cards, dialogs, imagery, text, focus states, and disabled controls remain readable and coherent. Explicitly check Windows Light / PowerToys Dark and Windows Dark / PowerToys Light, including What's New Markdown headings, links, body text, and caption buttons. With What's New kept open, switch PowerToys Light -> Dark while Windows stays Light, then Dark -> Light while Windows stays Dark; the same window's content and caption buttons must adopt the selected theme without reopening. Restore both original themes.

- [ ] **Settings, Quick Access, and attribution language** [ID: SET-LOCALIZATION] [ADMIN: NO]
  Start PowerToys non-elevated and record Runner and Settings integrity levels. Change the PowerToys language to a different, non-English supported language and click **Restart** in the language-change prompt. Confirm the new Runner and reopened Settings processes remain at medium integrity and General reports that PowerToys is running as the current user. Confirm Settings and Quick Access core chrome, sort labels, and actions use localized resources rather than missing-resource keys or unintended English fallback. Inspect every attribution link on Color Picker, Image Resizer, Mouse Utilities, Mouse Without Borders, New+, Quick Accent, PowerToys Run, Text Extractor, File Explorer Add-ons, PowerRename, Shortcut Guide, and ZoomIt: surrounding attribution wording is localized, author/product/format names are preserved, and each link retains its intended destination. Restore the original language through the same language-change flow.

### Settings backup and restore

- [ ] **Backup and restore through a long directory path** [ID: SET-BACKUP-RESTORE] [ADMIN: NO]
  Select a deeply nested backup directory whose full path exceeds the General-page card width. Confirm the path persists, wraps or trims without overlap, and is fully recoverable through text selection or tooltip. Set one distinctive General value and one module value, create a backup there, then change both. Restore that backup and confirm both Settings surfaces and their persisted JSON return to the backed-up state without partial restoration.

### Updates

- [ ] **Update-check display and settings isolation** [ID: SET-LAST-CHECKED] [ADMIN: NO]
  Establish a reversible non-default module on/off combination and record the full enabled map and General preferences. Trigger **Check for updates** without downloading or installing. Before cleanup or compensating changes, confirm the enabled map and all General preferences remain unchanged, the selected modules' toggles and runtime state still match, and Home and General show the same last-checked value using **Today at ...** or **Yesterday at ...** for recent checks rather than a raw timestamp. Confirm the display remains correct after reopening Settings, then restore the original state. Update-status cache changes are expected; preference resets are not.

- [ ] **Clean-install automatic-download default** [ID: SET-CLEAN-UPDATE-DEFAULT] [ADMIN: YES]
  On a clean installation or clean user profile with no existing general `settings.json`, open General and confirm **Download updates automatically** is enabled on first render and remains enabled after restarting PowerToys.

- [ ] **Recover configuration during update** [ID: SET-UPDATE-RECOVERY] [ADMIN: YES]
  In a disposable VM with an older updateable build, record valid root and module JSON settings and start the offered update. Confirm `%LOCALAPPDATA%\Microsoft\PowerToys\ConfigBackup` contains their pre-update copies. Using an updater fixture that pauses after backup creation but before Runner relaunch, corrupt one designated live JSON file, resume the update, and confirm PowerToys restores that file from the backup, relaunches automatically, reports successful restart, and preserves the other settings.

- [ ] **Update-available badge** [ID: SET-UPDATE-BADGE] [ADMIN: NO]
  On a build for which a newer version is available, complete an update check and confirm the tray icon gains one update-available badge while General/Home show the matching available-version state. Confirm opening the update surface does not create duplicate badges and the badge clears after updating to the current version.

### Secondary windows and lifecycle

- [ ] **Secondary-window return and process lifetime** [ID: SET-WHATS-NEW-ENTRY] [ADMIN: NO]
  Open **What's New** from Home and General, then choose **Open Settings**. Confirm the existing main Settings window returns to **Home**, not a blank or stale module page, and repeated invocation does not create duplicate main windows.
  With What's New or OOBE/SCOOBE open, close the main Settings window and confirm `PowerToys.Settings.exe` remains alive while the secondary window stays functional. Use **Open Settings** to restore the main window, close it again, then close the last secondary window and confirm the Settings process exits cleanly. Retain separate observations for both entry origins and for the main-hidden, main-restored and final-process-exit boundaries.

- [ ] **Secondary-window layout and startup** [ID: SET-SECONDARY-LAYOUT] [ADMIN: NO]
  Resize What's New and OOBE/SCOOBE wide and narrow. Confirm page content remains within the shared maximum width, PowerToys imagery loads without broken placeholders, release text remains readable, and primary navigation/actions stay reachable without horizontal scrolling. Separately open the shortcut-conflict window from Home without changing any shortcuts. Confirm a nonempty native title and readable visible title appear with usable conflict-list or empty-state content, Settings stays alive through initial layout, and the owned window can be closed and reopened normally.

### Policy regression

- [ ] **Generate a bug report package when Diagnostic data is disabled by policy** [ID: SET-BUG-REPORT-POLICY] [ADMIN: YES]
  In an authorized policy fixture, disable **Diagnostic data** by organization policy, then fully close and reopen the fixture's Settings windows to reload the policy. In General's **Diagnostics & feedback** section, confirm **Diagnostic data** shows **Off**, its switch cannot be changed, and **This setting is managed by your organization.** is displayed. Confirm **Generate package** in the separate **Generate bug report package** card remains enabled. Click it once and confirm the generation workflow shows progress and completes successfully with a newly generated local diagnostic package; no upload or GitHub issue submission is required. Restore the original policy and diagnostic-data preference, reopen Settings, and confirm the switch value, editability and management notice match the pre-test baseline. Remove only the package generated by this case; do not require an originally managed setting to become unmanaged.
