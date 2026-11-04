# FancyZones - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - ordinary standard-user coverage.
- `[ADMIN: YES]` - requires separately authorized elevation.
- `[ADMIN: COND]` - retain ordinary and elevated conditions independently.
- `[ID: ...]` - stable case identifier in the frozen assertion inventory.

## Fixtures & conventions

- Use uniquely named disposable layouts and owned windows, never user documents. Preserve
  original enablement, settings, layout assignments, templates, defaults, hotkeys and history,
  including original absence and editor-generated files. Restore and verify after final writes.
- Use the [shared ownership](../owned-fixtures.md), [selected-file preservation](../directory-snapshots.md#selected-file-preservation)
  and [lifecycle](../module-lifecycle.md) contracts. Establish a normal-integrity foreground
  fixture before keyboard or drag judgments. Native zone stamps/history corroborate snapping;
  they do not prove overlay colors, visibility, opacity or label placement.
- Read only owned history entries into evidence. The legacy clean-history prerequisite needs
  an isolated, authorized empty-history environment; do not clear live user history to obtain it.
  Keep the ordinary owned-window checks independently executable.
- Share fixtures and one action's observations only when initial state, settings, input order
  and spanning mode match. Evaluate each retained assertion separately. Reuse a save/reopen,
  drag/drop or window creation for its applicable observations; do not repeat it solely for
  another assertion, or invent a Cartesian product of otherwise independent option matrices.
- Run the Dragging, Snapping, Snapped window behavior, Window switching, Windows Snap,
  Layout switching/application and Layout reset cases with spanning **off and on**.
  Each child in those categories has two required conditions, not one representative run.
  Spanning-on requires at least two compatible displays; mixed-DPI coverage is separate.
- Display reconnection, resolution/scaling changes, lock/wake/RDP, restart, registry-reset,
  installation, policy, telemetry and locale variants require their stated fixtures and authority.
  Do not interrupt this shared desktop or move unrelated windows merely to satisfy a matrix.
  Missing conditions remain individually reported, not removed from the inventory.

## FancyZones (35 items)

### Settings and editor entry

- [ ] **Open and disable the editor** [ID: FZ-ENTRY] [ADMIN: NO]
  Open the editor from Settings and from the current configured keyboard shortcut, closing
  only the owned editor between routes. Verify the monitor/layout surface appears.
  Launch it through Quick Access as a separate route. Disable FancyZones through Settings;
  verify its process exits, shortcuts do not activate it, and Quick Access removes the
  launch entry and updates its enabled grouping. Re-enable and verify the entry returns.

- [ ] **Edit activation shortcuts** [ID: FZ-SHORTCUT] [ADMIN: NO]
  Save a collision-checked editor shortcut and verify the new binding activates the editor
  while the old one does not. Cancel another draft and verify the saved binding is unchanged.
  In Quick Access reset the shortcut, save it and verify default activation without a crash.
  Hold a non-modifier and then the Windows key in the recorder; it must remain stable.
  Repeatedly open/dismiss the recorder, including an authorized theme transition when available;
  no duplicate dialog or parent crash is expected. Restore the original binding and theme.

### Layout authoring

- [ ] **Create, edit and commit owned layouts** [ID: FZ-CREATE] [ADMIN: NO]
  Create one owned grid and one owned canvas layout, with distinct Unicode names.
  Use those fixtures for their geometry and commit checks. On canvas, independently move,
  resize, add and delete a zone; on grid, independently split, merge and resize zones.
  Save and reopen after each geometry operation to verify its particular change persists.
  The same Save and apply/reopen also verifies the layout's name, type, geometry and
  selected-work-area assignment. For both types, separately Cancel a draft and verify the
  previous geometry and assignment remain. Finally delete owned layouts and verify their
  cards and definitions disappear without deleting unrelated layouts.

- [ ] **Duplicate the intended layout** [ID: FZ-DUPLICATE] [ADMIN: NO]
  Duplicate a template and a custom layout and verify independent custom copies retain
  their geometry. Select X, right-click a different Y, and duplicate Y; verify Y rather
  than X was copied for all four template/custom combinations of X and Y.

- [ ] **Edit template parameters** [ID: FZ-TEMPLATE] [ADMIN: NO]
  Change zone count, spacing and highlight distance on a template. Save, reopen the editor,
  and independently verify each setting is retained and reflected in the layout.

- [ ] **Assign monitors and orientation defaults** [ID: FZ-ASSIGN] [ADMIN: NO]
  With two or more monitors, apply a distinct layout to each and verify independent
  assignments after reopening. Set horizontal and vertical defaults and verify both selections
  persist. On a mixed-DPI multi-monitor fixture, inspect each editor overlay against its
  actual work area: it must not shift, clip or spill onto the wrong monitor.

- [ ] **Apply custom edits live** [ID: FZ-LIVE-EDIT] [ADMIN: NO]
  On builds including the live-custom-edit fix, apply an owned layout and snap a window.
  Edit grid spacing, highlight distance and canvas zone count separately. Without restarting
  or reapplying, verify each affects the existing work area's snapping/highlight behavior;
  enable the layout-change window movement option when observing snapped-window geometry.

### Appearance and exclusions

- [ ] **Configure zone appearance** [ID: FZ-APPEARANCE] [ADMIN: NO]
  Change highlight, inactive-zone and border colors independently, change opacity, and test
  Show zone number off/on. Observe an active drag overlay for each change, not only saved
  settings. Restore every original value.

- [ ] **Exclude applications** [ID: FZ-EXCLUDE] [ADMIN: NO]
  Add an owned fixture executable to Excluded apps, verify it no longer snaps, then remove
  the owned exclusion and verify snapping returns. Scroll to and edit the Excluded apps
  field; the Settings page must remain usable without repeated scroll bounce.

### Dragging

For each row, use a real title-bar drag, observe the overlay during the gesture, then
observe the drop/unsnap result. Release owned buttons and modifiers even after failure.

| Shift to activate | Non-primary toggle | Input sequence and expected behavior |
|---|---|---|
| On | Off | Start drag, press Shift: zones appear; release Shift: hide; drop in an active zone snaps and hides them. |
| On | Off | Hold Shift before starting drag: zones appear; releasing Shift or completing a snap hides them. |
| Off | On | Start drag: zones appear; non-primary click or Shift deactivates them; test both inputs separately. |
| Off | Off | Start drag: zones appear; press Shift: zones hide. |
| On | On | Start drag without Shift: zones hidden; Shift activates; non-primary click toggles the active state. |

- [ ] **Drag activation, display and release behavior** [ID: FZ-DRAG] [ADMIN: NO]
  Exercise every row of the drag matrix in both spanning modes, preserving input order
  and separate observations of activation, deactivation and release. On compatible
  gestures, also observe the actual overlay and window opacity before, during and after
  the action instead of repeating the same drag just to collect another assertion.
  On two monitors, independently test Show zones on all monitors off/on. Create overlapping canvas
  zones of unequal sizes and test every exposed overlap selection option against those
  geometries. Test dragged-window transparency off/on and verify opacity is restored
  after drop and cancellation. These display-option variants remain independently observed;
  they do not require multiplying every activation row by every display-option combination.

### Snapping

- [ ] **Snap and unsnap: history and original size** [ID: FZ-HISTORY] [ADMIN: NO]
  Record an owned window's unsnapped size before arranging each condition.
  In an isolated clean-history fixture, snap an owned window by drag and by keyboard and
  check the corresponding app/work-area/zone entries. Snap to multiple zones and verify
  all indices. Snap the same app on two monitors and on two virtual desktops in separate
  conditions; unsnap one assignment and verify only that work-area record is removed.
  Unsnap a single assignment and verify its record disappears. Ordinary owned-entry
  observations remain useful but do not claim the empty-history setup was exercised.
  On the same snap/unsnap transitions when their starting conditions match, independently
  inspect history and window size. Test restore-size enabled throughout, disabled
  throughout, and disabled at snap time but enabled before unsnap. Only the first
  condition restores the original size; the other two retain the snapped size.
  The size checks do not require clearing user history.

- [ ] **Respect elevated-window boundaries** [ID: FZ-ELEVATION] [ADMIN: COND]
  With an authorized elevated owned window, an unelevated PowerToys drag must show the
  privilege notification rather than silently claiming a successful snap. With an
  authorized elevated PowerToys instance, verify the elevated window can be assigned.

- [ ] **Allow or reject child-window snapping** [ID: FZ-CHILD] [ADMIN: NO]
  Use an owned application with a genuine child/tool window, not a second unrelated
  top-level window. Enable Allow child windows snapping and verify snapping, then disable
  it and verify that the same class of window is not snapped.

- [ ] **Snap windows shared across virtual desktops** [ID: FZ-PINNED] [ADMIN: NO]
  In Task View set Show this window on all desktops on an owned window and verify snapping.
  Separately set Show windows from this app on all desktops and verify snapping.
  Restore both original pin states and remove only owned virtual desktops.

### Snapped window behavior

- [ ] **Respond to display changes** [ID: FZ-DISPLAY] [ADMIN: NO]
  With authorized display reconfiguration and complete placement recovery, test resolution
  and scaling changes separately with Keep windows in their zones on and off: on follows
  the zone's new bounds; off leaves the window size/position unchanged. With a secondary
  monitor, disconnect and reconnect it while enabled and verify the window returns to its zone.

- [ ] **Follow changed zone geometry** [ID: FZ-RELAYOUT] [ADMIN: NO]
  Prepare layouts with one and three differently sized/positioned zones. With layout-change
  window movement enabled, verify zone 1 follows new geometry, zone 3 stays put when its
  index is absent, zones 1-2 reduce to zone 1, and returning to the three-zone layout restores
  the 1-2 assignment. Judge the reduced window's geometry, not an assumed intermediate
  native stamp value; the requested index set may be retained for the return transition.
  With the option off, an assigned zone-1 window stays put.

- [ ] **Reopen windows: history, active monitor and special windows** [ID: FZ-LAST-ZONE] [ADMIN: NO]
  Enable Move newly created windows to their last known zone. Verify close/reopen on the
  primary monitor; with history on both monitors, reopen on the active monitor; with only
  secondary history, reopen in that secondary zone. Snap, disable FancyZones, move the
  window and re-enable: it returns to its zone. Switch away and back between owned virtual
  desktops: an unsnapped secondary-monitor window retains position/size, and a manually
  resized snapped window retains its resized size. For an owned genuine popup, close/reopen
  returns it to its zone. In a separate owned VS Code window, snap and open a menu: the
  menu stays anchored to its control, not the zone's top-left corner.
  On two monitors enable Move newly created windows to the current active monitor.
  A never-snapped window opens on the active monitor; same-desktop/same-monitor history
  restores its zone; same-desktop/other-monitor and other-desktop histories open on the
  active monitor. Keep the four initial-history conditions and both placement settings
  explicit; share a window creation only where those prerequisites match. Retain the
  other-monitor/active-monitor precedence requirement for specification review when
  last-zone placement is also enabled and the target searches history first. Do not
  reinterpret a conflicting prerequisite combination as an established product defect.

### Window switching

- [ ] **Cycle windows within a zone** [ID: FZ-CYCLE] [ADMIN: NO]
  Place several owned windows in one zone and use the configured previous/next shortcuts
  (defaults Win+PgUp/PgDown). Verify both directions; switch virtual desktop and return,
  then repeat. Disable window switching and verify the shortcuts no longer cycle these windows.

### Windows Snap

- [ ] **Move by zone index** [ID: FZ-INDEX] [ADMIN: NO]
  With Override Windows Snap off, verify Windows snapping is not replaced by a FancyZones
  assignment. Enable it and select Zone index. From an unsnapped window, Right enters
  the first zone and Left the last; subsequent Left/Right moves to previous/next indices.
  Up/Down keep their ordinary Windows behavior. With one monitor, test wraparound with
  cross-monitor movement both on and off. With multiple monitors and the option on,
  Left at the first zone wraps to the preceding monitor's last zone, and Right at the
  last wraps to the following monitor's first zone, including outermost-monitor wraparound.
  Retain the legacy cross-monitor-off boundary expectations (Left at first and Right at
  last do not move to a zone) as **unresolved specification conditions**: they conflict
  with the same baseline's one-monitor cycling requirement and the target's cycling path.
  Record actual behavior without declaring either contradictory expectation authoritative.

- [ ] **Move and extend by relative position** [ID: FZ-POSITION] [ADMIN: NO]
  Enable Override Windows Snap and Relative position. From an unsnapped window, test
  each Win+arrow direction. Extend using Ctrl+Alt+Win+arrows until all zones are included;
  while holding the modifiers, use opposite arrows to reverse the extension. With
  cross-monitor movement off, each of Left/Right/Up/Down wraps within the current monitor;
  with it on, exercise every direction across a multi-monitor arrangement.

### Layout switching and application

- [ ] **Assign and use quick-layout keys** [ID: FZ-QUICK] [ADMIN: NO]
  Assign distinct digits to custom layouts and verify persisted mappings. Enable quick
  switching and use Win+Ctrl+Alt+digit while idle and during a drag; both apply the chosen
  layout. Test flash-zones on/off and verify the visible flash, then disable quick switching
  and verify bindings do not switch layouts. Preserve the legacy bare-digit-during-drag
  expectation as a separate **specification-review condition** on builds containing the
  intentional modifier requirement; do not silently substitute the chord for that claim.

- [ ] **Apply layouts across desktop changes** [ID: FZ-LAYOUT] [ADMIN: NO]
  Disable spacing on a grid and verify adjacent zones have no gap while dragging.
  Create an owned virtual desktop: it starts with the previous desktop's assignments.
  Change its layout and separately edit its applied layout; verify the other desktop's
  assignment/geometry is unchanged. Delete an applied owned custom layout and verify
  No layout replaces it. With authorized resolution and scaling changes, verify an applied
  grid fits the work area; do not impose grid scaling expectations on an absolute canvas.

### Layout reset

- [ ] **Retain and recover layout assignments** [ID: FZ-RESET] [ADMIN: NO]
  Use an isolated disposable desktop with explicit lock/reboot/registry authority.
  Remove its virtual desktops and the captured CurrentVirtualDesktop/VirtualDesktopIDs
  values as the reset prerequisite, never the shared user's values. Set custom layouts
  on each monitor, lock and disconnect/reconnect a display, unlock and verify assignments
  were not reset. Separately reboot and verify persistence. Set horizontal/vertical defaults,
  remove the isolated applied-layouts.json and verify each orientation uses its chosen default.

### Spanning and input recovery

- [ ] **Switch the spanning model** [ID: FZ-SPAN] [ADMIN: NO]
  With two compatible monitors, switch Allow zones to span across monitors off/on and
  verify separate versus combined work-area assignments and overlays. Execute every
  required off/on child condition in the repeated categories above; merely toggling this
  setting is not the repeated functional coverage.

- [ ] **Recover from interrupted input and session transitions** [ID: FZ-RECOVERY] [ADMIN: NO]
  On builds with drag-abort handling, normally close an owned fixture during an active
  drag: overlays/transparency clear, subsequent digits reach an owned input fixture, and
  another drag works. Shift+other-key input must not be swallowed as bare Shift.
  With authorized RDP return, wake and unlock fixtures, separately verify the first
  no-Shift drag does not activate zones and a held-Shift drag does.
  Observe ordinary module disable/enable and authorized display/span reconfiguration
  during a drag for clean teardown, no crash and usable subsequent input. Session-ending
  behavior requires a real authorized logoff/shutdown fixture; a posted message is not a reboot.

### Wheel switching and layout label

- [ ] **Switch layouts during drag and observe the name indicator** [ID: FZ-WHEEL] [ADMIN: NO]
  On builds exposing Mouse wheel layout switch, enable it and drag with zones visible.
  Wheel down selects next and up previous, including both wraparounds, on the monitor
  under the cursor; dropping uses the newly selected layout. With at least two assigned
  digits, order follows the digits; with fewer than two, it follows custom-layout order.
  With the setting off, hidden zones, or fewer than two eligible layouts, no switch occurs
  and ordinary wheel input is not consumed. Preserve zero/one/two-layout conditions separately.
  On builds exposing the name indicator, observe the selected layout and its displayed
  name on the same wheel transitions; independently exercise the quick-switch-key entry.
  Verify disabling the label suppresses it and ending the
  drag clears it. Exercise all seven offered positions, text/background colors, size,
  padding and display duration through Settings and observe live changes without restart.
  Rapid switching resets the display timer. Use timestamped frames for duration behavior,
  not a settled screenshot or an invented millisecond tolerance.

- [ ] **Rotate windows between monitors** [ID: FZ-ROTATION] [ADMIN: NO]
  Requires two monitors and a desktop where every processable window is owned or explicitly
  authorized for movement. Enable monitor rotation, hold the configured chord, and verify
  numbered content previews. Left and Right rotate in opposite directions, retaining
  work-area-relative placement and coherent content numbers; release dismisses the preview.
  Change the chord and verify the new binding, then disable and verify no rotation.
  Do not test this on a shared desktop by moving unknown windows.

### Command-line and Command Palette integration

- [ ] **Read CLI information and help** [ID: FZ-CLI-READ] [ADMIN: NO]
  On builds with FancyZonesCLI, exercise root and per-command help, monitor enumeration,
  layout enumeration including template/custom ASCII previews, active-layout and hotkey
  queries. Verify observations agree with independently read UI/data. Exercise each documented
  alias as well as canonical commands. With an installed non-English locale, verify
  localized help/errors while command/option literals remain usable.

- [ ] **Apply layouts and hotkeys through the CLI** [ID: FZ-CLI-WRITE] [ADMIN: NO]
  Apply a template and an owned custom layout, targeting a specific monitor and all
  monitors separately. Pass custom GUIDs both quoted-with-braces and bare in PowerShell.
  Verify live applied geometry and persisted assignment. Assign a digit to an owned custom
  layout, verify the physical shortcut, then remove it and verify it no longer applies.
  Invalid GUIDs, unknown layouts, invalid monitor indices, out-of-range digits and attempts
  to assign a template hotkey must report errors without modifying unrelated state.
  Use CLI editor and Settings launch commands as separate entry assertions.

- [ ] **Use the PowerToys Command Palette extension** [ID: FZ-CMDPAL] [ADMIN: NO]
  With the installed extension enabled, find FancyZones editor, Settings and layout
  commands. Open each destination; apply owned grid and canvas layouts to one monitor
  and all monitors independently. Verify layout previews and monitor identities agree
  with live configuration. After an owned layout edit or authorized monitor change,
  revisit the page and verify refreshed data; retain the first observation because refresh
  is best-effort. Pin an owned layout command to the dock, reopen and invoke it, then
  remove only that pin and verify prior dock state is restored.

### Localization, servicing and policy

- [ ] **Localize the editor** [ID: FZ-LOCALIZATION] [ADMIN: NO]
  With a supported installed non-English Windows language and authorized language
  switching, reopen the editor and verify labels/dialogs are localized without breaking
  Unicode layout names. Restore the original language; English-only observations do not cover this.

- [ ] **Preserve configuration during upgrade** [ID: FZ-UPGRADE] [ADMIN: COND]
  Requires an authorized isolated previous-version installation. Create a two-zone canvas
  with a Unicode name and a four-zone grid with one zone split. Apply canvas on the primary
  desktop, grid on a second desktop and, with two monitors, distinct templates per
  monitor/desktop. Upgrade and verify all settings, names, geometry and assignments survive.

- [ ] **Honor forced module policy** [ID: FZ-POLICY] [ADMIN: YES]
  In an authorized policy fixture, force FancyZones disabled and restart PowerToys:
  the module stays off, Settings and Quick Access cannot enable it, Quick Access cannot
  launch it, and direct editor launch is refused with a policy log message. Force enabled:
  it runs and neither surface can disable it. With conflicting computer/user policy,
  computer policy wins. Restore captured values and existence, not an assumed Not Configured state.

- [ ] **Apply declarative FancyZones settings** [ID: FZ-DSC] [ADMIN: COND]
  In an isolated authorized DSC environment with required PowerShell, DSC and WinGet
  versions, apply the supplied configuration.winget sample and verify FancyZones enabled
  with Shift+Ctrl+Alt+F editor activation. Keep the sample's other module mutations
  isolated and restore them too. With PowerToys initially running it restarts after
  configuration; when initially stopped it remains stopped.

- [ ] **Observe diagnostics and shutdown** [ID: FZ-DIAGNOSTICS] [ADMIN: COND]
  With explicit telemetry-setting consent, enable diagnostics and viewing before a run,
  perform owned editor/CLI/snapping actions, then inspect generated utility events for
  correspondence with those actions. Independently inspect new FancyZones errors from
  the run interval. In an authorized real session-ending fixture, verify FancyZones exits
  without a quiesce hang. Do not equate an offline source review with any of these observations.
