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

## Scenario IDs and assertion coverage

The 19 execution scenarios below map to the previous 27 legacy requirement groups.
Each scenario has an explicit ID. Merged and split scenarios list their legacy requirements in **Covers**;
assertion IDs such as `L48.activation` retain that traceability. Legacy `Lnn` labels identify
requirements, not physical line numbers in this file. L47's Quick Access and Command Palette
entry paths are separate scenarios with independent outcomes.

Focus on functional outcomes rather than exhaustive visual effects. Animation playback,
transition direction, and frame-by-frame flashing or flicker are outside this checklist's scope.
Verify the resulting open/closed state, content, theme and layout instead.

Share setup, actions and observations within a scenario, but record each named assertion
separately. Parameter rows remain distinct required actions. A failed assertion does not
invalidate other observations whose prerequisites still hold; an unavailable observation
channel affects only assertions needing that channel. Do not replace a requested action with
cleanup or recovery. These scenarios specify behavior, inputs and expected results without
depending on a particular automation tool, helper API or report implementation.

## Fixtures & conventions

- **State backup**: record the initial Shortcut Guide enabled state and copy
  `%LOCALAPPDATA%\Microsoft\PowerToys\Shortcut Guide\settings.json`, `Pinned.json` if present,
  and `%LOCALAPPDATA%\Microsoft\WinGet\KeyboardShortcuts`. Restore the exact originals after the
  run rather than assuming default values.
- **Input desktop**: hotkey and Windows-key-hold cases require an attached interactive desktop.
  Deliver the specified keys to the intended foreground window when testing a chord, hold,
  release or shortcut passthrough. Opening through another entry point does not prove the binding.
- **Foreground fixtures**: use Notepad with a unique temp file for an unpackaged foreground app,
  Explorer for a shell page, and a separately launched elevated Notepad for the integrity case.
  Record each fixture PID/HWND and close only those fixtures.
- **Manifest fixture**: create disposable manifests only under the per-user
  `%LOCALAPPDATA%\Microsoft\WinGet\KeyboardShortcuts` directory. Back up the whole directory first,
  use a unique package name and process filter, and restore the directory on every exit path.
- **Taskbar fixture**: record taskbar-button identities and physical rectangles, and open three
  isolated apps in known taskbar positions. Multi-monitor and mixed-DPI assertions require the
  corresponding hardware.
- **Visual state**: record the PowerToys theme, Windows app theme, Shortcut Guide side, Windows-key
  action, hold duration, close-on-release value, excluded-app list, and activation shortcut.
- **State hygiene**: dismiss the overlay after every scenario or mode row, but not before its
  release/close assertions. Do not leave test-opened Start visible, do not send keys to an
  unintended window, and do not close user-owned taskbar applications.

---

## Shortcut Guide (19 scenarios, 27 legacy requirements)

### Settings and entry points

- [ ] **[ADMIN: YES]** **[ID: L46]** (#48151, #48248, #48383) On a clean installation or disposable user profile with no existing PowerToys `settings.json`, start PowerToys and open Settings/OOBE. Confirm the module is named **Shortcut Guide**, its description matches the current app-aware overlay rather than referring to “V2,” it is **disabled from first render**, no Shortcut Guide process/event becomes active transiently, and enabling it persists after restarting PowerToys.

- [ ] **[ADMIN: NO]** **[ID: SG-QUICK-ACCESS]** Quick Access entry across enable, disable and re-enable. (#40834, #44006)

  **Covers:** L47 (Quick Access).

  **Arrange:** Record the original Shortcut Guide enabled state. Use the actual Quick Access
  launch entry; this scenario does not require Command Palette.

  **Act:** Enable Shortcut Guide and launch it from Quick Access. Dismiss it, disable the module,
  and inspect Quick Access. Re-enable the module and launch it from Quick Access again,
  without restarting Windows.

  **Assert:**
  - **L47.quick-access:** The enabled Quick Access entry opens one full overlay without duplicate windows.
  - **L47.disabled-quick:** While disabled, Quick Access has no usable launch action and cannot open the overlay.
  - **L47.reenable-quick:** Re-enabling restores the Quick Access entry and its ability to open one full overlay.

  **Restore:** Dismiss test-opened surfaces and restore the original Shortcut Guide enabled state.

- [ ] **[ADMIN: NO]** **[ID: SG-COMMAND-PALETTE]** Command Palette entry across enable, disable and re-enable. (#40834, #44006)

  **Covers:** L47 (Command Palette).

  **Arrange:** Record the original Shortcut Guide and Command Palette enabled states. Open
  Command Palette, enabling it if needed. The shipped PowerToys command integration is part
  of the behavior under test, not a prerequisite that may be skipped if it fails to load.

  **Act:** Enable Shortcut Guide, find and execute **Toggle Shortcut Guide** in Command Palette.
  Dismiss the guide, disable Shortcut Guide and inspect its Command Palette entries.
  Re-enable Shortcut Guide and execute its toggle command again without restarting Windows.

  **Assert:**
  - **L47.command-palette:** Command Palette exposes the enabled module's **Toggle Shortcut Guide** command, which opens or toggles one full overlay without duplicate windows.
  - **L47.disabled-palette:** While Shortcut Guide is disabled, its settings entry remains, its toggle action is absent, and Command Palette cannot open the overlay.
  - **L47.reenable-palette:** Re-enabling restores the toggle entry and its ability to open or toggle the guide.

  **Boundary:** An app-search result that merely launches PowerToys does not satisfy these
  assertions. If Command Palette is operable but its shipped PowerToys integration is missing
  or fails to load, this entry path has failed; Quick Access is evaluated independently.

  **Restore:** Dismiss test-opened surfaces and restore both modules' original enabled states.

- [ ] **[ADMIN: NO]** **[ID: SG-BASIC]** Default activation, application navigation, and Windows content. (L456, #48043, #48386, #48481, #48439, #49638)

  **Covers:** L48, L68, L71.

  **Arrange:** Capture the activation binding, restore **Win+Shift+/**, and foreground the tracked
  non-elevated Notepad fixture. Start with no open guide or search query. Use ordinary shipped
  manifests, not the custom or invalid-key fixtures from other scenarios.

  **Act:** Press the exact default chord. Observe the initial Notepad page before navigating.
  In that same overlay, switch repeatedly among Notepad, Windows, and PowerToys. During a Windows
  visit, inspect the recommendations, their original categories, the Taskbar section and corrected
  key caps. During a PowerToys visit, inspect the Shortcut Guide binding. Clear any temporary
  filter before comparing ordinary page content again; do not reopen just to repeat an assertion
  available in the current visit.

  **Assert:**
  - **L48.binding:** Settings displays **Win+Shift+/**.
  - **L48.activation:** That physical chord opens exactly one full overlay from the normal app.
  - **L48.key-names:** The overlay displays the activation chord as key names/glyphs, not raw virtual-key numbers.
  - **L68.initial-page:** The captured Notepad page appears first and is selected, with its icon/name and app-specific shortcuts.
  - **L68.navigation:** Each repeated page switch updates content and selection to the chosen application.
  - **L68.indicators:** Taskbar indicators appear only on a page exposing them, including on the initial page before any switch.
  - **L68.stability:** After each page switch, the overlay remains open with the selected page's content, without a crash or a blank page.
  - **L71.duplicates:** Each Windows recommendation appears once under **Recommended** and once in its original category, with no additional copies.
  - **L71.headings:** Meta-section names such as `<TASKBAR1-9>` are not rendered literally; taskbar shortcuts have their localized heading.
  - **L71.peek:** **Peek at desktop temporarily** renders as **Win+,**.
  - **L71.click-to-do:** **Open Click to Do** renders as **Win+Q**.

  **Restore:** Dismiss the guide and restore the captured activation binding.

- [ ] **[ADMIN: NO]** **[ID: SG-BINDINGS]** Custom activation binding and generated PowerToys shortcuts. (L457, #48043)

  **Covers:** L49, L69.

  **Arrange:** Capture the bindings and enabled states of Shortcut Guide and a separate
  representative PowerToy such as Color Picker. Make the representative row available, prepare
  the default SG binding, and choose distinct unused custom chords for the two modules. Keep
  the tracked foreground app independent of the Settings window that will be closed/reopened.
  Observe the baseline rows in an ordinary guide opening before changing bindings; reuse the
  SG-BASIC observation if its process and settings still match. Keep that SG process for the
  ordinary-reopen checks until the explicitly requested restart.

  **Act:**
  1. Assign both custom chords through Settings, then close/reopen Settings and read the SG
     custom binding. Before any PowerToys/module restart, use the new SG chord to open the guide
     and inspect the representative module's row on the PowerToys page. Dismiss the guide and
     try **Win+Shift+/** to check that the old default is inactive.
  2. Reset the representative module's shortcut and reopen the guide normally to inspect the
     restored row. Complete both representative-row observations before restarting anything;
     a restart must not refresh stale content on behalf of these assertions.
  3. Restart PowerToys, invoke the custom SG chord again, and inspect the SG row on the PowerToys page.

  **Assert:**
  - **L49.settings-reopen:** The unused custom SG chord persists across Settings close/reopen.
  - **L49.activation:** After Settings close/reopen, the new chord opens the guide; the old **Win+Shift+/** chord no longer opens it.
  - **L49.restart:** The custom binding still works after the explicit PowerToys restart.
  - **L49.generated-row:** After restart, the PowerToys page displays the exact customized SG chord.
  - **L69.custom-row:** Before any restart, ordinary opening displays the representative module's exact custom modifiers/key instead of its default.
  - **L69.reset-row:** Ordinary reopening after resetting that module displays the restored binding, without requiring a restart.
  - **L49.restore:** Restore **Win+Shift+/** for the test, and preserve the captured original binding for final state restoration.

  **Restore:** Restore both modules' captured bindings and enabled states, including an original
  user binding that differs from a factory default. Dismiss the guide and close only test-owned windows.

### Windows-key hold activation

- [ ] **[ADMIN: NO]** **[ID: SG-HOLD-MODES]** Off and full-guide Windows-key mode matrix. (L458, L461, #49661)

  **Covers:** L53, L55, L56.

  **Arrange:** Capture the Windows-key action, hold duration and close-on-release setting.
  Reuse one tracked non-elevated foreground app and one known valid duration. Each row begins
  with the guide and any test-opened Start dismissed. Execute the left and right Windows keys
  separately; these parameter rows are not interchangeable observations.

  **Act and expected state:**

  | Windows-key action | Close on release | Required actions |
  |---|---|---|
  | **Off** | Not applicable | Tap and hold each Windows key separately, then use the independent activation chord. |
  | **Open Shortcut Guide** | On | Hold each Windows key beyond the duration, observe the full guide, then release. |
  | **Open Shortcut Guide** | Off | Hold each Windows key until the guide opens, release, observe the same retained guide, and close that guide with Escape. Then open and toggle it with the independent chord. |

  **Assert:**
  - **L53.setting:** **Off** persists in Settings.
  - **L53.surfaces:** Neither indicators nor the full guide appears for either key's tap or long hold in Off mode.
  - **L53.start:** Normal short-press Start behavior remains available in Off mode.
  - **L53.chord:** The independent configured activation chord still opens the full guide in Off mode.
  - **L55.settings:** Full-guide mode with close-on-release enabled persists.
  - **L55.open:** A beyond-duration hold opens the full guide for either Windows key.
  - **L55.release:** Release closes it without leaving Start, taskbar indicators or a second overlay visible.
  - **L56.settings:** Full-guide mode with close-on-release disabled persists.
  - **L56.retained:** The hold-opened guide remains after release.
  - **L56.escape:** Escape closes that same retained guide, before any cleanup closes it.
  - **L56.chord:** The independent configured chord opens and toggles the guide with close-on-release off.

  **Restore:** Restore the original mode, duration and release policy; release all test-held keys
  and dismiss test-opened surfaces.

- [ ] **[ADMIN: NO]** **[ID: SG-INDICATORS]** Indicator thresholds, layout, and held Win+1 routing. (L464, #48683, #49661)

  **Covers:** L54, L89.

  **Arrange:** Capture taskbar order and pin state; prepare three tracked apps in known taskbar
  slots; existing applications may supply the non-routing slots, and only the first-slot
  routing target needs a test-controlled window. Select **Show taskbar indicators**, choose a distinctive duration within 100-5,000 ms,
  and persist it. Begin routing from an app other than the first-slot target so Win+1 is not
  merely minimizing an already-active target.

  **Act:**
  1. For both Windows keys, release before the configured threshold and observe absence of
     indicators. Dismiss any test-opened Start before the next input.
  2. For both keys, hold beyond the threshold **without pressing a digit**, observe the indicator
     layout, and release. These plain holds must independently establish Start suppression.
  3. In an additional hold, observe the same indicator/layout properties, then press and release
     `1` while keeping Windows down. Observe the target app and indicators before releasing Windows;
     then observe the final hidden state and absence of Start.
  4. Enter a value below 100 and another above 5,000; read the control and saved values after each.

  **Assert:**
  - **L54.settings:** Indicator mode and the distinctive valid duration persist.
  - **L54.threshold:** Both keys show no indicators before the threshold and show only indicators, not the full guide, beyond it.
  - **L54.plain-release:** Releasing each activated plain hold hides indicators without opening Start.
  - **L54.limits:** Both the control and saved JSON clamp below-range input to 100 and above-range input to 5,000.
  - **L89.slots:** The three tracked apps occupy the observed known slots.
  - **L89.layout:** One numbered indicator aligns with each eligible taskbar button without overlap, with its tail pointing toward the current taskbar edge.
  - **L89.routing:** Held Win+1 brings the exact first-slot app foreground.
  - **L89.retention:** After releasing `1`, Windows is still held, indicators remain visible, and Start stays closed.
  - **L89.release:** Releasing Windows closes the indicators without opening Start.

  **Boundary:** Win+1 itself suppresses Start; its release result cannot replace the no-digit
  holds in step 2. A fixture prerequisite failure affects only checks that need that fixture,
  not unrelated modes or independently observable duration limits. Once any partial fixture
  setup is restored, plain threshold/release checks can use the existing observed taskbar;
  do not attempt routing without the identified first-slot target.

  **Restore:** Restore duration/mode, taskbar order and pin state, and close only the tracked apps.

### Overlay lifecycle and application compatibility

- [ ] **[ADMIN: NO]** **[ID: L60]** (L460-L461, #48043, #48683, #48950) Open the full guide separately for each close route: press Escape, press the configured activation chord again, click the title-bar Close button, click the transparent area outside the pane, and foreground another tracked app. Confirm each route dismisses the overlay once, leaves no visible/orphan overlay, and allows the next invocation to reuse the module normally.
- [ ] **[ADMIN: COND]** **[ID: L61]** (L462-L464) Run PowerToys non-elevated, foreground an elevated Notepad fixture, and press the configured activation shortcut. Confirm the guide opens above the elevated app. Invoke a safe displayed Windows shortcut such as **Win+E** and confirm the expected Explorer fixture opens and the guide closes; then close only that Explorer fixture.
- [ ] **[ADMIN: NO]** **[ID: L62]** Add `notepad.exe` to **Excluded apps**, foreground the tracked Notepad fixture, and invoke both the configured shortcut and the Windows-key action; confirm neither surface appears. Foreground Explorer and confirm Shortcut Guide still opens, then remove the exclusion and confirm Notepad works again without restarting Windows.
- [ ] **[ADMIN: NO]** **[ID: L63]** (#48935) After one warm-up invocation, record the Shortcut Guide PID and private working set. Run ten open/navigate/close cycles against the same foreground app and confirm the PID remains reusable, no cycle creates more than one visible overlay, navigation/content remain functional, and the private-working-set increase after a two-second idle is no more than 32 MiB above the warm baseline.

### Navigation, manifests, and shortcut content

- [ ] **[ADMIN: NO]** **[ID: L67]** (#40834, #48390, #49069) Open Shortcut Guide from the desktop and confirm it starts without a blank-title fault, the rail contains readable vector entries for **Windows** and **PowerToys**, one entry is selected, the selected page has **Pinned**, **Recommended** when applicable, normal category headings, and shortcut key caps, and the rail's Settings icon is fully visible. Invoke Settings from the rail and confirm the existing PowerToys Settings window opens directly to Shortcut Guide.
- [ ] **[ADMIN: NO]** **[ID: L70]** (#40834, #48481) On one application page, open a shortcut row's context menu and choose **Pin**. Confirm the row appears once under **Pinned**, `Pinned.json` records it for that application, and it remains pinned after dismissing and reopening Shortcut Guide. Choose **Unpin**, confirm the pinned row is removed immediately and the localized empty-state text returns, then restore the original `Pinned.json`.
- [ ] **[ADMIN: NO]** **[ID: L72]** (#40834, #48171; manifest additions #48652, #48793, #48821, #48959, #48960, #49062, #49143, #49245, #49407, and #49615) Back up and remove the per-user keyboard-shortcuts directory, then invoke Shortcut Guide. Confirm the directory and index are recreated, every bundled manifest shipped by the tested build is copied and referenced exactly once, every copied YAML file parses, and Windows, PowerToys, Explorer, and Notepad pages remain available without a launch crash. Restore the original directory afterward.
- [ ] **[ADMIN: NO]** **[ID: L73]** (#48037, #48461, #48757, #49562) Add one disposable Notepad-filtered manifest containing virtual-key `65`, literal `<1>`, `<LessThan>`, `<GreaterThan>`, an arrow token, an empty key, and an unknown key. Regenerate the index and open Notepad's page; confirm valid values render as **A**, **1**, **<**, **>**, and the expected arrow glyph/name rather than raw numbers or tokens, while invalid/empty values neither crash the overlay nor prevent valid sibling shortcuts from rendering.

### Page-local search and keyboard actions

- [ ] **[ADMIN: NO]** **[ID: SG-SEARCH]** Page-local search, selection, Ctrl+F, and Escape. (#40834, #49639)

  **Covers:** L77, L78, L85 (selected-state exposure only).

  **Scope:** Full keyboard focus traversal, visible-focus auditing and screen-reader speech
  are outside this core scenario. Accessible-name, selected-state and live-region property
  checks below remain in scope; they do not establish spoken output.

  **Arrange:** Prepare a valid disposable Notepad-filtered fixture with independently searchable
  name, description, modifier and displayed-key values. For example, a key-only **F11** probe
  must not also occur in its row's name or description. Keep empty/unknown-key robustness inputs
  out of this scenario. Start on the unfiltered page.

  **Act:**
  1. Select the fixture's application page in the open full guide and observe the rail item's
     selected state.
  2. In the same guide, replace the search text separately with mixed-case name, description,
     modifier and displayed-key probes. Inspect matching rows/sections. Retain a distinctive
     query while switching to another application page and back.
  3. From a non-search focus target, press **Ctrl+F** and enter a no-match query. Use this one
     query change to observe the visible message, live-region properties and stale-row absence.
  4. Press Escape once, observe the cleared query with the guide still open, then press Escape
     again without interposing another interaction. Reopen normally and inspect the query.

  **Assert:**
  - **L77.name:** A name-text probe matches case-insensitively.
  - **L77.description:** A separate description-text probe matches case-insensitively.
  - **L77.modifier:** A modifier-name probe matches case-insensitively.
  - **L77.key-label:** An isolated displayed-key-label probe matches case-insensitively.
  - **L77.sections:** Only matching rows and their section headings remain; empty sections disappear.
  - **L77.page-scope:** The query filters only the selected application page and is retained/reapplied when switching pages.
  - **L78.focus:** Ctrl+F moves focus to the search box, which has an accessible name.
  - **L78.no-match:** No-match input shows a localized polite live-region message with no stale shortcut rows.
  - **L78.clear:** The first Escape clears the query without closing the guide.
  - **L78.close:** The next Escape closes that guide.
  - **L78.reopen:** Normal reopening starts with an empty query.
  - **L85.selection:** Selected rail items expose their selected state.

  **Restore:** Remove only the disposable fixture, restore its original directory/index state,
  and dismiss test-opened surfaces.

### Appearance, localization, and accessibility

- [ ] **[ADMIN: NO]** **[ID: SG-APPEARANCE]** Themes, pane position, surface layout, and shell presence. (#40834, #48390, #48683)

  **Covers:** L82, L83.

  **Arrange:** Capture the PowerToys theme, Windows app theme and pane side. Reuse one tracked
  foreground app and the same normal opening path. Observe the resulting theme, persisted
  settings and settled geometry after each opening.

  **Act:**
  1. Use the shared opening schedule below. At every opening, observe theme, pane geometry,
     surface edges and native window/shell presence together. Keep settings fixed within each
     two-opening pair; the separate Light/Right opening isolates the position change. Dismiss
     normally between openings, without restarting to force a theme update.

     | SG theme | Side | Normal openings / change |
     |---|---|---|
     | Light | Left | Open twice; also collect the Left persistence, position and surface assertions. |
     | Light | Right | Change only the side, then open; collect the Right assertions without repeating Left setup. |
     | Dark | Right | Open twice with the same settings. |
     | **Use Windows setting** | Right | Open twice with the same settings. |
     | **Use Windows setting** | Right | Change only the Windows app theme, then observe the next opening. |

  2. Observe both the taskbar and Alt+Tab behavior while testing the open guide; a static pane
     screenshot alone does not establish absence from those surfaces.

  **Assert:**
  - **L82.themes:** Each opening, including the two repeated openings per mode, uses one readable theme across the pane, transparent host, key caps, selection indicators, icons, search, taskbar indicators and text.
  - **L82.system-follow:** After a Windows app-theme change in system mode, the next opening follows that theme.
  - **L83.persistence:** Both Left and Right settings persist.
  - **L83.position:** After opening, the pane is on the selected side.
  - **L83.surface:** Its shadow and rounded acrylic surface are not clipped.
  - **L83.host:** The full-monitor transparent host is the only overlay HWND.
  - **L83.taskbar:** Shortcut Guide creates no taskbar button.
  - **L83.alt-tab:** Shortcut Guide creates no Alt+Tab entry.

  **Restore:** Restore the original application/system themes and pane side, and dismiss the guide.

- [ ] **[ADMIN: NO]** **[ID: L84]** (legacy localization requirement, #48151, #48248, #49639, #49661) Change PowerToys to a supported non-English language and restart. Confirm Shortcut Guide Settings labels and core overlay chrome—including title, search, Close, Settings, Pinned, Recommended, Taskbar, Pin/Unpin, and no-results text—are localized with no resource keys or unintended English fallback. Treat application-manifest names/descriptions as allowed to remain English per the documented current limitation, then restore the original language.

### Taskbar and monitor topology

- [ ] **[ADMIN: NO]** **[ID: L90]** (#48683) On two monitors with different DPI scales, foreground the Notepad fixture on each monitor in turn and open both the full guide and taskbar-indicator mode. Confirm each surface appears on the foreground monitor, remains inside that monitor's work area, aligns with that monitor's taskbar buttons, and has no double scaling, gap, spill, or cross-monitor offset.
