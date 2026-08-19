# Shortcut Guide — PowerToys release checklist

> Source: consolidated from the legacy Shortcut Guide baseline
> (`tests-checklist-template.md` L454-L465) and user-observable changes merged after PowerToys
> v0.96 through `origin/main` on 2026-08-17, including the latest 0.101-targeted work.
> Build-only changes and individual application-manifest additions are represented by consolidated
> behavioral checks rather than one item per pull request. One module per file.

## Legend

Each item is annotated with an admin-requirement tag:

**Admin requirement**:
- `[ADMIN: NO]` - runnable from a standard (non-elevated) shell
- `[ADMIN: YES]` - requires an elevated session, clean profile, or machine-level configuration
- `[ADMIN: COND]` - basic case is non-admin, but the stated variant requires elevation

## Fixtures & conventions

- **State backup**: record the initial Shortcut Guide enabled state and copy
  `%LOCALAPPDATA%\Microsoft\PowerToys\Shortcut Guide\settings.json`, `Pinned.json` if present,
  and `%LOCALAPPDATA%\Microsoft\WinGet\KeyboardShortcuts`. Restore the exact originals after the
  run rather than assuming default values.
- **Input desktop**: hotkey and Windows-key-hold cases require an attached interactive desktop.
  A Named Event proves only the downstream action; use guarded SendInput when the configured chord,
  hold duration, key release, or shortcut passthrough is the assertion.
- **Foreground fixtures**: use Notepad with a unique temp file for an unpackaged foreground app,
  Explorer for a shell page, and a separately launched elevated Notepad for the integrity case.
  Record each fixture PID/HWND and close only those fixtures.
- **Manifest fixture**: create disposable manifests only under the per-user
  `%LOCALAPPDATA%\Microsoft\WinGet\KeyboardShortcuts` directory. Back up the whole directory first,
  use a unique package name and process filter, and restore the directory in `finally`.
- **Taskbar fixture**: record taskbar-button UIA rectangles and open three isolated apps in known
  taskbar positions. Multi-monitor and mixed-DPI assertions require the corresponding hardware.
- **Visual state**: record the PowerToys theme, Windows app theme, Shortcut Guide side, Windows-key
  action, hold duration, close-on-release value, excluded-app list, and activation shortcut.
- **State hygiene**: dismiss the overlay after every item. Do not leave Start open, do not send an
  unguarded Windows-key chord, and do not close user-owned taskbar applications.

---

## Shortcut Guide (27 items)

### Settings and entry points

- [ ] **[ADMIN: YES]** (#48151, #48248, #48383) On a clean installation or disposable user profile with no existing PowerToys `settings.json`, start PowerToys and open Settings/OOBE. Confirm the module is named **Shortcut Guide**, its description matches the current app-aware overlay rather than referring to “V2,” it is **disabled from first render**, no Shortcut Guide process/event becomes active transiently, and enabling it persists after restarting PowerToys.
- [ ] **[ADMIN: NO]** (#40834, #44006) Enable Shortcut Guide and invoke it once from PowerToys Quick Access and once from Command Palette's **Toggle Shortcut Guide** command; confirm each entry path opens or toggles one full overlay without duplicate windows. Disable the module and confirm Quick Access has no usable launch action, Command Palette keeps **Shortcut Guide settings** but removes the toggle action, and neither entry path opens the overlay. Re-enable it and confirm both recover without restarting Windows.
- [ ] **[ADMIN: NO]** (L456, #48043) Restore the default activation shortcut and confirm Settings shows **Win+Shift+/**. With a normal foreground app, press that exact chord and confirm one full Shortcut Guide overlay opens and displays the chord with key names rather than raw virtual-key numbers.
- [ ] **[ADMIN: NO]** (L457, #48043) Change the activation shortcut to an unused chord, close and reopen Settings, and confirm the new chord opens Shortcut Guide while **Win+Shift+/** no longer does. Restart PowerToys, confirm the binding still works and the PowerToys shortcuts page shows the customized chord, then restore **Win+Shift+/**.

### Windows-key hold activation

- [ ] **[ADMIN: NO]** (L458, #49661) Set **Hold Windows key** to **Off**. Tap and hold both the left and right Windows keys separately; confirm neither taskbar indicators nor the full guide appears, normal short-press Start behavior remains available, and the independent configured activation shortcut still opens the full guide.
- [ ] **[ADMIN: NO]** (#48683, #49661) Set **Hold Windows key** to **Show taskbar indicators**, choose a distinctive duration within 100-5,000 ms, and persist Settings. For both Windows keys, confirm releasing before the threshold does not show indicators, holding beyond it shows only indicators aligned to taskbar buttons, releasing hides them, and an activated hold suppresses Start. Enter values below 100 and above 5,000 and confirm the control and saved JSON clamp to the documented limits.
- [ ] **[ADMIN: NO]** (L461, #49661) Set **Hold Windows key** to **Open Shortcut Guide** with **Close on Windows key release** enabled. Hold either Windows key beyond the configured duration and confirm the full guide opens; release it and confirm the overlay closes without leaving Start, taskbar indicators, or a second overlay visible.
- [ ] **[ADMIN: NO]** (#49661) Keep **Open Shortcut Guide** selected but turn **Close on Windows key release** off. Hold either Windows key until the full guide opens, release it, and confirm the guide remains. Close it with Escape, then confirm the regular activation shortcut still opens and toggles the guide independently of Windows-key-hold settings.

### Overlay lifecycle and application compatibility

- [ ] **[ADMIN: NO]** (L460-L461, #48043, #48683, #48950) Open the full guide separately for each close route: press Escape, press the configured activation chord again, click the title-bar Close button, click the transparent area outside the pane, and foreground another tracked app. Confirm each route dismisses the overlay once with its exit animation, leaves no visible/orphan overlay, and allows the next invocation to reuse the module normally.
- [ ] **[ADMIN: COND]** (L462-L464) Run PowerToys non-elevated, foreground an elevated Notepad fixture, and press the configured activation shortcut. Confirm the guide opens above the elevated app. Invoke a safe displayed Windows shortcut such as **Win+E** and confirm the expected Explorer fixture opens and the guide closes; then close only that Explorer fixture.
- [ ] **[ADMIN: NO]** Add `notepad.exe` to **Excluded apps**, foreground the tracked Notepad fixture, and invoke both the configured shortcut and the Windows-key action; confirm neither surface appears. Foreground Explorer and confirm Shortcut Guide still opens, then remove the exclusion and confirm Notepad works again without restarting Windows.
- [ ] **[ADMIN: NO]** (#48935) After one warm-up invocation, record the Shortcut Guide PID and private working set. Run ten open/navigate/close cycles against the same foreground app and confirm the PID remains reusable, no cycle creates more than one visible overlay, navigation/content remain functional, and the private-working-set increase after a two-second idle is no more than 32 MiB above the warm baseline.

### Navigation, manifests, and shortcut content

- [ ] **[ADMIN: NO]** (#40834, #48390, #49069) Open Shortcut Guide from the desktop and confirm it starts without a blank-title fault, the rail contains readable vector entries for **Windows** and **PowerToys**, one entry is selected, the selected page has **Pinned**, **Recommended** when applicable, normal category headings, and shortcut key caps, and the rail's Settings icon is fully visible. Invoke Settings from the rail and confirm the existing PowerToys Settings window opens directly to Shortcut Guide.
- [ ] **[ADMIN: NO]** (#48386, #48481) Foreground Notepad and open Shortcut Guide. Confirm the captured foreground application's page appears first and is selected with the Notepad icon/name and app-specific shortcuts. Switch repeatedly among Notepad, Windows, and PowerToys and confirm each page updates, selection follows the page, taskbar indicators appear only for a page that exposes them, and the overlay never flashes closed, crashes, or shows a blank page.
- [ ] **[ADMIN: NO]** (#48043) Assign a representative PowerToy such as Color Picker a distinctive unused shortcut, open Shortcut Guide's **PowerToys** page, and confirm the generated row shows the exact customized modifiers and key instead of its default. Reset the representative module's shortcut, reopen the guide, and confirm the displayed row returns to the restored value.
- [ ] **[ADMIN: NO]** (#40834, #48481) On one application page, open a shortcut row's context menu and choose **Pin**. Confirm the row appears once under **Pinned**, `Pinned.json` records it for that application, and it remains pinned after dismissing and reopening Shortcut Guide. Choose **Unpin**, confirm the pinned row is removed immediately and the localized empty-state text returns, then restore the original `Pinned.json`.
- [ ] **[ADMIN: NO]** (#48439, #49638) On the Windows page, confirm each recommended shortcut appears once under **Recommended** and once in its original category with no additional duplicates, meta-section names such as `<TASKBAR1-9>` are not rendered literally, and taskbar shortcuts are grouped under their localized heading. Confirm **Peek at desktop temporarily** renders as **Win+,** and **Open Click to Do** renders as **Win+Q**.
- [ ] **[ADMIN: NO]** (#40834, #48171; manifest additions #48652, #48793, #48821, #48959, #48960, #49062, #49143, #49245, #49407, and #49615) Back up and remove the per-user keyboard-shortcuts directory, then invoke Shortcut Guide. Confirm the directory and index are recreated, every bundled manifest shipped by the tested build is copied and referenced exactly once, every copied YAML file parses, and Windows, PowerToys, Explorer, and Notepad pages remain available without a launch crash. Restore the original directory afterward.
- [ ] **[ADMIN: NO]** (#48037, #48461, #48757, #49562) Add one disposable Notepad-filtered manifest containing virtual-key `65`, literal `<1>`, `<LessThan>`, `<GreaterThan>`, an arrow token, an empty key, and an unknown key. Regenerate the index and open Notepad's page; confirm valid values render as **A**, **1**, **<**, **>**, and the expected arrow glyph/name rather than raw numbers or tokens, while invalid/empty values neither crash the overlay nor prevent valid sibling shortcuts from rendering.

### Page-local search

- [ ] **[ADMIN: NO]** (#49639) On a page with a disposable uniquely named shortcut and description, search separately by name text, description text, modifier name, and displayed key label. Confirm matching is case-insensitive, only matching rows and their section headings remain, empty sections disappear, and the query filters only the selected application page. Switch to another app page and confirm the same query is retained and reapplied to that page.
- [ ] **[ADMIN: NO]** (#49639) Press **Ctrl+F** and confirm focus moves to the search box with an accessible name. Enter a no-match query and confirm a localized polite live-region message appears with no stale shortcut rows. Press Escape once and confirm it clears the query while keeping the overlay open; press Escape again and confirm the overlay closes. Reopen and confirm search starts empty.

### Appearance, localization, and accessibility

- [ ] **[ADMIN: NO]** (#40834, #48683) Switch Shortcut Guide through Light, Dark, and **Use Windows setting**, opening it twice in each mode. Confirm the pane, transparent host, key caps, selection indicators, icons, search, taskbar indicators, and text use one readable theme with no initial opposite-theme flash; change the Windows app theme in system mode and confirm the next open follows it.
- [ ] **[ADMIN: NO]** (#48390, #48683) Set the pane position to **Left** and then **Right**. Confirm each setting persists, the pane enters from and remains on the selected side, its shadow/rounded acrylic surface is not clipped, the full-monitor transparent host is the only overlay HWND, and Shortcut Guide creates no taskbar button or Alt+Tab entry. Confirm a taskbar docked on the same side does not overlap the pane.
- [ ] **[ADMIN: NO]** (legacy localization requirement, #48151, #48248, #49639, #49661) Change PowerToys to a supported non-English language and restart. Confirm Shortcut Guide Settings labels and core overlay chrome—including title, search, Close, Settings, Pinned, Recommended, Taskbar, Pin/Unpin, and no-results text—are localized with no resource keys or unintended English fallback. Treat application-manifest names/descriptions as allowed to remain English per the documented current limitation, then restore the original language.
- [ ] **[ADMIN: NO]** (#40834, #49639) Navigate the full guide using keyboard and a screen reader. Confirm focus reaches search, application rail items, Settings, Close, and realized shortcut rows in visual order; selected rail items expose their selected state; key combinations and shortcut names are announced coherently; the no-results message is announced once; and focus never escapes invisibly into the transparent host.

### Taskbar and monitor topology

- [ ] **[ADMIN: NO]** (L464, #48683, #49661) Open three tracked apps in known taskbar slots, select **Show taskbar indicators**, and hold a Windows key. Confirm one numbered indicator aligns with each eligible taskbar button without overlap and its tail points toward the current taskbar edge. While still holding Windows, press `1` and confirm the corresponding first app becomes foreground, the indicators close, and Start does not open.
- [ ] **[ADMIN: NO]** (#48683) On two monitors with different DPI scales, foreground the Notepad fixture on each monitor in turn and open both the full guide and taskbar-indicator mode. Confirm each surface appears on the foreground monitor, remains inside that monitor's work area, aligns with that monitor's taskbar buttons, and has no double scaling, gap, spill, or cross-monitor offset. On an OS/configuration that supports moving the taskbar, repeat on every available top, bottom, left, and right edge and confirm the pane/indicator ordering and arrow direction adapt correctly.
