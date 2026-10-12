# Shortcut Guide - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - standard-user coverage, subject to the stated fixtures.
- `[ADMIN: YES]` - requires an authorized elevated session or disposable installation fixture.
- `[ADMIN: COND]` - retain ordinary and elevated variants independently.
- `[ID: ...]` - stable scenario identifier; every frozen child and parameter row remains required.

## Fixtures & conventions

- Preserve module enablement, settings, `Pinned.json` and the complete per-user
  `%LOCALAPPDATA%\Microsoft\WinGet\KeyboardShortcuts` directory. Restore originals,
  including an original shortcut that differs from the factory default.
- Use an attached input desktop, owned Notepad/Explorer fixtures and a separately authorized
  elevated app. Track HWND/PID and send chords/holds only to the intended foreground.
- Manifest tests use uniquely named disposable manifests with exact process filters. Keep
  ordinary, search and invalid-key fixtures separate; restore directory/index state afterward.
- Record taskbar-button identities, order and pin state before taskbar tests. Only the first-slot
  routing target needs a test-controlled window; multi-monitor/mixed-DPI cases need that hardware.
- Preserve application/system theme, pane side, Windows-key mode/duration/release policy and
  exclusions. Release held keys, dismiss owned Start/overlays after observations and close only
  owned fixtures. Cleanup cannot substitute for a release/close assertion.
- Observe resulting state, content, theme and layout, not animation playback or frame-by-frame
  effects. Full focus traversal, visible-focus auditing and spoken screen-reader output are
  outside this checklist; the specified accessibility properties remain required.
- Use the [module profile](../modules/shortcut-guide.md) for interactions and restoration,
  and the [frozen inventory](../assertion-inventories/shortcut-guide.json) for detailed assertions.

## Shortcut Guide (19 items)

### Settings and entry points

- [ ] **Clean-install naming and default** [ID: L46] [ADMIN: YES]
  In a clean installation/disposable profile without PowerToys settings, start PowerToys and open Settings/OOBE. Confirm the name is Shortcut Guide and its description describes the current app-aware overlay, not V2. It must be disabled from first render without transient process/event activation; enabling persists after restarting PowerToys.

- [ ] **Quick Access enablement and launch** [ID: SG-QUICK-ACCESS] [ADMIN: NO]
  Enable Shortcut Guide and use its actual Quick Access entry to open one full overlay without duplicates. Dismiss, disable and confirm Quick Access has no usable launch action and cannot open the guide. Re-enable without restarting Windows and confirm that entry opens one full overlay again. This case does not require Command Palette; restore original enablement.

- [ ] **Command Palette enablement and launch** [ID: SG-COMMAND-PALETTE] [ADMIN: NO]
  Preserve both modules' states and make Command Palette available through an authorized reversible setup. With Shortcut Guide enabled, find and invoke its shipped Toggle Shortcut Guide command; it must open/toggle one full overlay without duplicates. Disable Shortcut Guide: Settings remains, the toggle action is absent and cannot open the guide. Re-enable without restarting Windows and confirm the toggle recovers. A generic app-search result is not this integration; a working palette missing the shipped integration is a failure, not an assumed prerequisite skip. Restore both states.

- [ ] **Default activation, navigation and Windows content** [ID: SG-BASIC] [ADMIN: NO]
  Preserve the original binding, select Win+Shift+/ and foreground owned non-elevated Notepad with ordinary shipped manifests, no query or open guide. Confirm Settings displays that binding and the physical chord opens exactly one full overlay, rendering key names/glyphs rather than raw virtual-key numbers. Notepad must initially be selected with its icon/name and app-specific shortcuts. Repeatedly switch among Notepad, Windows and PowerToys; selection/content must follow each page without closing, crashing or becoming blank. Indicators appear only on pages exposing them, including before any first switch. Inspect the Shortcut Guide binding on PowerToys. On Windows, each recommendation appears once under Recommended and once in its original category without extra copies; taskbar headings are localized, not literal `<TASKBAR1-9>`, Peek at desktop temporarily is Win+, and Open Click to Do is Win+Q. Clear temporary filters and restore the binding.

- [ ] **Custom binding and generated shortcut rows** [ID: SG-BINDINGS] [ADMIN: NO]
  Preserve Shortcut Guide and a representative module's bindings/enablement. Make that module's row available and observe baseline rows on an ordinary guide opening; a still-valid SG-BASIC observation may be reused. Assign distinct unused custom chords through Settings, close/reopen only test-owned Settings and confirm the SG binding persisted. Before any restart, use the new SG chord, confirm the old Win+Shift+/ is inactive and the representative module's row shows its exact custom modifiers/key. Reset that module and reopen the guide normally; its restored row must update without restarting. Only then restart PowerToys, confirm the custom SG chord still activates and its own generated row is correct. Restore Win+Shift+/ for the test and both originally captured bindings/states for final cleanup.

### Windows-key hold activation

- [ ] **Off and full-guide mode matrix** [ID: SG-HOLD-MODES] [ADMIN: NO]
  Preserve mode, duration and release policy. Use one tracked non-elevated foreground app and a known valid duration. Start each row with guide and owned Start dismissed; exercise left and right Windows keys separately.

  | Windows-key mode | Close on release | Required observations |
  |---|---|---|
  | Off | Not applicable | The setting persists. Neither tap nor long hold shows indicators/full guide; short-press Start still works and the independent activation chord opens the full guide. |
  | Open Shortcut Guide | On | The setting persists. Beyond-duration holds open the full guide for either key; release closes it without Start, lingering indicators or a second overlay. |
  | Open Shortcut Guide | Off | The setting persists. After opening by hold, release retains the same guide; Escape closes that retained guide before cleanup. Independently open/toggle it with the activation chord. |

  Restore the original mode/duration/release policy and release all held keys.

- [ ] **Indicator thresholds, layout and held Win+1** [ID: SG-INDICATORS] [ADMIN: NO]
  Preserve taskbar order/pins and prepare three identified apps in known slots, with an owned first-slot routing target. Select Show taskbar indicators and persist a distinctive duration within 100-5,000 ms. For each Windows key independently, release before the threshold and confirm no indicators; then hold beyond it without a digit, confirm only indicators (not the full guide), and release with no Start or lingering indicators. Observe one non-overlapping numbered indicator per eligible button with its tail toward the taskbar edge. In an additional hold starting from another foreground app, observe the same layout, press/release 1 while Windows stays held, and confirm the exact first-slot app becomes foreground while indicators remain and Start stays closed. Release Windows and confirm indicators close without Start. Separately enter below-100 and above-5,000 durations and confirm both control and persisted values clamp to those bounds. Win+1's own Start suppression cannot replace the no-digit holds. A failed routing fixture does not block independently observable threshold/release/limit checks after partial setup is restored. Restore taskbar and settings state.

### Overlay lifecycle and application compatibility

- [ ] **Independent close routes** [ID: L60] [ADMIN: NO]
  Open a fresh full guide for each route: Escape, configured chord again, title-bar Close, transparent area outside the pane and foregrounding another tracked app. Each must dismiss once, leave no visible/orphan overlay and permit the next normal invocation.

- [ ] **Elevated foreground and shortcut passthrough** [ID: L61] [ADMIN: COND]
  With PowerToys non-elevated, foreground an authorized elevated Notepad fixture and use the configured chord. Confirm the guide opens above it. Invoke a safe displayed Windows shortcut such as Win+E; confirm the expected Explorer fixture opens and the guide closes. Close only the owned Explorer.

- [ ] **Excluded application** [ID: L62] [ADMIN: NO]
  Add `notepad.exe` to exclusions and foreground the tracked Notepad. Neither the configured chord nor Windows-key action may show a guide surface. With the exclusion still present, foreground Explorer and confirm activation works. Remove the exclusion and confirm Notepad works again without restarting Windows; restore the original list.

- [ ] **Repeated invocation and memory** [ID: L63] [ADMIN: NO]
  After one warm-up, record PID/private working set. Run ten open/navigate/close cycles against the same app: PID remains reusable, each cycle has at most one visible overlay and navigation/content remain functional. After two seconds idle, private working set must be no more than 32 MiB above the warm baseline.

### Navigation, manifests and content

- [ ] **Desktop page and Settings entry** [ID: L67] [ADMIN: NO]
  Open from the desktop without a blank-title fault. Confirm readable vector Windows/PowerToys rail entries, one selected page with Pinned, Recommended where applicable, normal categories and key caps, and a fully visible Settings icon. Invoke it and confirm the existing PowerToys Settings opens directly to Shortcut Guide.

- [ ] **Pin, reopen and unpin** [ID: L70] [ADMIN: NO]
  Pin an owned row from its application-page context menu. Confirm exactly one Pinned row and the correct application's entry in `Pinned.json`, retained after dismiss/reopen. Unpin: the row disappears immediately and localized empty-state text returns. Restore original pins.

- [ ] **Bundled manifest initialization** [ID: L72] [ADMIN: NO]
  With a complete restorable baseline, remove the per-user keyboard-shortcuts directory and invoke the guide. Confirm directory/index recreation, every bundled manifest shipped in this build copied/referenced exactly once, every copied YAML parsing, and available Windows, PowerToys, Explorer and Notepad pages without a launch crash. Restore the original directory.

- [ ] **Manifest key rendering and invalid siblings** [ID: L73] [ADMIN: NO]
  Add a disposable Notepad-filtered manifest containing virtual-key 65, literal `<1>`, `<LessThan>`, `<GreaterThan>`, an arrow token, an empty key and an unknown key. Regenerate the index and open Notepad: valid values render as A, 1, <, > and the expected arrow glyph/name, not raw numbers/tokens. Empty/unknown keys must not crash or suppress valid sibling shortcuts; restore manifest/index state.

### Page-local search and keyboard actions

- [ ] **Search fields, selection, Ctrl+F and Escape** [ID: SG-SEARCH] [ADMIN: NO]
  Prepare a valid disposable Notepad manifest with separately searchable name, description, modifier and displayed-key values; a key-only F11 probe must not occur in name/description. Exclude invalid-key robustness inputs and start unfiltered. Select its page and verify the rail's selected state. In the same guide, independently apply mixed-case name, description, modifier and key probes; matching is case-insensitive and only matching rows/nonempty section headings remain. Retain a distinctive query while switching pages and back: filtering is page-local and the query is retained/reapplied. From another focus target, Ctrl+F must focus the accessibly named search box. Enter no-match text and observe the localized polite live-region message with no stale rows. Press Escape once to clear while retaining the guide, then immediately again to close it; normal reopen starts empty. Restore the disposable manifest/index and dismiss owned surfaces.

### Appearance and localization

- [ ] **Themes, pane side, layout and shell presence** [ID: SG-APPEARANCE] [ADMIN: NO]
  Preserve PowerToys/Windows app themes and pane side, and reuse the same foreground app and ordinary entry path. Dismiss normally between openings; do not restart to force theme refresh. Use this complete schedule:

  | Theme | Side | Normal openings / change |
  |---|---|---|
  | Light | Left | Open twice with fixed settings. |
  | Light | Right | Change only the side, then open. |
  | Dark | Right | Open twice with fixed settings. |
  | Use Windows setting | Right | Open twice with fixed settings. |
  | Use Windows setting | Right | Change only Windows app theme, then open again. |

  Every opening must use one readable theme across pane, transparent host, key caps, selection indicators, icons, search, taskbar indicators and text; the final opening follows the changed Windows theme. Both side choices persist and place the pane correctly, without clipping its shadow/rounded acrylic. Confirm one transparent guide host covers the selected monitor's work area (excluding the taskbar/reserved desktop area), measured in physical virtual-screen coordinates; do not require the full monitor bounds or apply DPI scaling a second time. The guide creates neither taskbar button nor Alt+Tab entry; a pane screenshot alone is insufficient. Restore original themes/side.

- [ ] **Localized Settings and overlay chrome** [ID: L84] [ADMIN: NO]
  Change PowerToys to a supported non-English language and restart. Confirm Settings labels and overlay title, search, Close, Settings, Pinned, Recommended, Taskbar, Pin/Unpin and no-results text are localized without resource keys or unintended English fallback. Manifest names/descriptions may remain English under the documented limitation. Restore the original language.

### Taskbar and monitor topology

- [ ] **Mixed-DPI foreground monitor** [ID: L90] [ADMIN: NO]
  On two differently scaled monitors, foreground Notepad on each in turn and open both full guide and indicator mode. Each surface must appear on the foreground monitor within its work area, align with that taskbar's buttons and have no double scaling, gap, spill or cross-monitor offset.
