# PowerToys Settings — release checklist

> Source: consolidated from the legacy **General Settings** baseline
> (`tests-checklist-template.md` L52-L81) and user-observable Settings application changes
> merged through PowerToys v0.100. One application per file.

## Legend

Each item is annotated with an admin-requirement tag:

**Admin requirement**:
- `[ADMIN: NO]` - runnable from a standard (non-elevated) shell
- `[ADMIN: YES]` - requires an elevated session, machine restart, update installation, or policy change
- `[ADMIN: COND]` - basic case is non-admin, but the stated variant requires elevation

## Fixtures & conventions

- **State backup**: before the run, copy `%LOCALAPPDATA%\Microsoft\PowerToys\settings.json`, the
  Settings backup metadata, and every module settings file that a case will mutate. Record the
  initial enabled state of every module. Restore the exact original state, not an assumed
  "all enabled" state.
- **Representative module**: use one isolated, launchable module with a deterministic Named Event
  or visible process (for example Color Picker) for cross-surface enable/disable checks. Use
  **Find My Mouse** for the legacy mouse-utility Quick Access case.
- **Quick Access**: distinguish the flyout launch page from **All apps**. Record the original
  Quick Access enabled state, shortcut, and sort order.
- **Elevation**: record the Runner and Settings process integrity levels before and after every
  restart. Never infer elevation only from the page text.
- **Destructive cases**: the reboot, clean-profile, update-installation, and GPO cases must run in
  a disposable VM or an explicitly approved machine state. Preserve the report across reboots.
- **Appearance and language**: record the original PowerToys theme, Windows app theme, display
  language, tray-icon options, and update-notification options; restore them in `finally`.
- **State hygiene**: close only Settings, Quick Access, OOBE/SCOOBE, and fixture windows opened by
  the current case. Do not terminate unrelated user applications.

---

## PowerToys Settings (29 items)

### Settings shell and Dashboard

- [ ] **[ADMIN: NO]** Open **PowerToys Settings** from the tray context menu and confirm one window opens on **Home**. Invoke Settings again from the tray and from a module's **Open settings** action; confirm the existing single Settings window is focused and navigates to the requested page rather than creating duplicate main windows.
- [ ] **[ADMIN: NO]** Expand every navigation group and open every visible module page once. Confirm each selection shows the matching page title, the navigation selection follows the page, and `PowerToys.Settings.exe` remains alive without a navigation failure or blank page.
- [ ] **[ADMIN: NO]** (#43626, #44734) On **Home**, switch the Utilities card between **Alphabetical** and **By status**. Confirm exactly one sort choice is checked, card order matches the selection, and the selected order persists after closing every Settings window and reopening.
- [ ] **[ADMIN: NO]** (#44699, #44734) Open a representative module page and record its enabled state, leave Quick Access open on **All apps**, then return Settings to Home and toggle that module from the Utilities card. Reopen the module page and confirm its toggle, Quick Access, general `settings.json`, and the Runner's actual module state all match the new value. Re-enable it and confirm its deterministic action works again without restarting Windows.
- [ ] **[ADMIN: NO]** (#46922) Resize Settings from wide to its minimum supported width and back while Home contains enough cards to scroll. Confirm the update/shortcut controls and Utilities card reflow below the main cards, no giant empty scroll region appears, and no card, toggle, or navigation content is horizontally clipped.
- [ ] **[ADMIN: NO]** (#42438) Navigate Home with keyboard and a screen reader. Confirm heading navigation reaches the **Home** level-1 heading and each dashboard card level-2 heading, focus order follows the visual order, and every module toggle has an accessible name and state.

### Startup and administrator mode

- [ ] **[ADMIN: NO]** (L53) Start PowerToys non-elevated, use the General page restart action, and confirm the restarted Runner and Settings processes remain at medium integrity and General reports that PowerToys is running as the current user.
- [ ] **[ADMIN: COND]** (L54-L56, #48024) From a non-elevated run, click **Restart as administrator**, approve UAC, and confirm Runner and Settings are elevated. Check **Always run as administrator**, restart PowerToys, and confirm it returns elevated. Clear the checkbox, restart through the non-admin path, and confirm both processes return to medium integrity.
- [ ] **[ADMIN: YES]** (L57-L61) In a disposable VM, enable **Run at startup** and **Always run as administrator**, reboot, and confirm PowerToys starts elevated without a UAC prompt. Then clear **Always run as administrator**, reboot again, and confirm PowerToys starts automatically at medium integrity. Restore the original startup and elevation settings.

### Module enable/disable persistence

- [ ] **[ADMIN: NO]** (L64-L67, #47287) Record every module's initial state, turn every available module off from Home, restart PowerToys, and confirm every toggle remains off, representative module processes/events/hotkeys are inactive, and the shortcut card empty state reads **No shortcuts to show.** with one period. Turn every module on, restart, confirm every toggle remains on and representative in-process, standalone, and shell-extension modules respond, then restore the recorded initial state.

### Quick Access

- [ ] **[ADMIN: NO]** (L70, #42676, #43840) Enable Quick Access and confirm tray left-click opens the Quick Access flyout while tray right-click shows **Quick access** as the first command and opens the same flyout. Disable Quick Access and confirm tray left-click opens PowerToys Settings instead, the Quick Access shortcut control is disabled, the configured chord no longer opens the flyout, and the tray context-menu **Quick access** command is removed. Re-enable Quick Access and confirm the command and flyout entry points return.
- [ ] **[ADMIN: NO]** (L71) From the Quick Access launch page, invoke a representative launchable module and confirm its expected window/action appears exactly once. Close only the fixture window and confirm the flyout remains reusable.
- [ ] **[ADMIN: NO]** (L71-L74, #43840, #44699, #44734) Keep Settings open on the **Find My Mouse** page and Quick Access on **All apps**, choose **By status**, then disable Find My Mouse from Quick Access. **Without navigating away from or recreating the Mouse Utilities page**, confirm its open-page toggle and Home toggle update immediately, it moves to the disabled group without reopening the flyout, and its launch action disappears or becomes unavailable. Re-enable it and confirm the same existing page, Home, Quick Access, and the module action recover.
- [ ] **[ADMIN: NO]** (#44734) Switch Quick Access **All apps** between **Alphabetical** and **By status**. Confirm the choices are mutually exclusive, each order is correct, and the selected order is retained after closing and reopening the flyout.
- [ ] **[ADMIN: NO]** (#43840, #47407) Assign Quick Access an unused shortcut and confirm the new chord opens the flyout while the old chord does not. Reopen the shortcut editor, click **Reset**, and confirm Settings does not crash, all shortcut key/modifier fields clear, the chord no longer opens Quick Access, and the cleared state persists after reopening Settings.
- [ ] **[ADMIN: NO]** (#44626) Change the PowerToys language to a non-English supported language and use the page's restart action. Confirm Settings and Quick Access core chrome, sort labels, and actions use localized resources rather than missing-resource keys or unintended English fallback. Restore the original language.

### Tray icon and appearance

- [ ] **[ADMIN: NO]** (L80-L81) Toggle **Show system tray icon** off and confirm the PowerToys icon disappears while Runner remains active and Settings stays usable. Turn it on again and confirm exactly one icon returns and both left-click and right-click actions still work.
- [ ] **[ADMIN: NO]** (#33321) Enable **Use theme-aware tray icon**, switch the Windows app theme between Light and Dark, and confirm the icon redraws to remain visible in each theme without restarting PowerToys or creating a duplicate icon. Disable the option and confirm theme changes no longer select the adaptive variant.
- [ ] **[ADMIN: NO]** (#46922, #48024) Switch PowerToys Settings through Light, Dark, and **Use Windows setting**, reopening Home, General, and What's New after each change. Confirm navigation, cards, dialogs, imagery, text, focus states, and disabled controls remain readable and use one coherent theme at narrow and wide window sizes.

### Settings backup and restore

- [ ] **[ADMIN: NO]** (L77-L78) Set one distinctive General value and one distinctive module value, create a Settings backup, then change both values. Restore the backup and confirm both Settings surfaces and their persisted JSON values return to the backed-up state without leaving PowerToys in a partially restored state.
- [ ] **[ADMIN: NO]** (#46920) Select a deeply nested backup directory whose full path exceeds the General-page card width. Confirm the path persists, wraps or trims without overlapping adjacent controls, and the complete value is recoverable through text selection or the tooltip before running Backup and Restore successfully from that location.

### Updates

- [ ] **[ADMIN: NO]** (#46923) Trigger **Check for updates**, then inspect both Home and General. Confirm they show the same last-checked value using **Today at ...** or **Yesterday at ...** for recent checks instead of a raw timestamp, and that the value remains correct after reopening Settings.
- [ ] **[ADMIN: YES]** (#46889) On a clean installation or clean user profile with no existing general `settings.json`, open General and confirm **Download updates automatically** is enabled on first render and remains enabled after restarting PowerToys.
- [ ] **[ADMIN: YES]** (#46889) In a disposable VM with an older updateable build, record valid root and module JSON settings and start the offered update. Confirm `%LOCALAPPDATA%\Microsoft\PowerToys\ConfigBackup` contains their pre-update copies. Using an updater fixture that pauses after backup creation but before Runner relaunch, corrupt one designated live JSON file, resume the update, and confirm PowerToys restores that file from the backup, relaunches automatically, reports successful restart, and preserves the other settings.
- [ ] **[ADMIN: NO]** (#47030) On a build for which a newer version is available, complete an update check and confirm the tray icon gains one update-available badge while General/Home show the matching available-version state. Confirm opening the update surface does not create duplicate badges and the badge clears after updating to the current version.

### What's New, OOBE, and secondary-window lifecycle

- [ ] **[ADMIN: NO]** (#44638, #45775, #46203) Open **What's New** from Home and General, then choose **Open Settings**. Confirm the existing main Settings window returns to **Home**, not a blank or stale module page, and repeated invocation does not create duplicate main windows.
- [ ] **[ADMIN: NO]** (#48024) Resize What's New and OOBE/SCOOBE wide and narrow. Confirm page content remains within the shared maximum width, refreshed PowerToys imagery loads without broken placeholders, release text remains readable, and primary navigation/actions stay reachable without horizontal scrolling.
- [ ] **[ADMIN: NO]** (#45787) Open What's New or OOBE/SCOOBE, close the main Settings window, and confirm `PowerToys.Settings.exe` remains alive while the secondary window stays functional. Use **Open Settings** to restore the main window, close it again, then close the last secondary window and confirm the Settings process exits cleanly.

### Policy regression

- [ ] **[ADMIN: YES]** (#45033) Apply the policy that disables PowerToys telemetry, restart PowerToys, and open General. Confirm **Create bug report** remains enabled, invokes the bug-report workflow once, and reports progress/completion normally. Remove the policy, restart, and confirm the General page returns to its unmanaged state.
