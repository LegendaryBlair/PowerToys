# Power Display - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - standard-user coverage with the stated fixtures.
- `[ADMIN: COND]` - keep ordinary and explicitly authorized elevated conditions separate.
- `[ID: ...]` - stable case identifier in the matching assertion inventory.

## Fixtures & conventions

- Preserve original monitor hardware values, module/general/Light Switch settings, profiles,
  discovery state, window ownership and desktop state. Restore the original values, not defaults.
  See [fixture boundaries](../power-display-fixtures.md) and the [shared recording workflow](../recording-workflow.md).
- Use collision-checked owned profiles/mappings. Do not expose existing profile names,
  monitor identifiers, clipboard content or unrelated desktop pixels in shared evidence.
- Real hardware readback is required for hardware effects; a slider, cached CLI value or
  saved JSON alone is insufficient. Keep DDC/CI, WMI, multi-monitor, mixed-DPI and touch
  conditions independently reportable.
- Input-source, color-temperature, power-state, rotation, hot-plug, sleep, crash recovery,
  policy and migration cases require an appropriate disposable setup and recovery authority.
  Never risk the only remote-control display, induce a crash, bypass a blacklist or seed
  crash flags on the ordinary shared desktop. Retain unavailable conditions as unexecuted.

## Power Display (33 items)

### Settings and entry points

- [ ] **Enable and disable** [ID: PD-ENABLE] [ADMIN: NO]
  In a clean authorized installation, Power Display starts disabled. From its Settings
  page, cancel the enable warning and check that it stays disabled; then explicitly
  accept the warning and check that the module starts. Disable it and confirm the resident
  process stops and the saved enabled state agrees. Restore the original enabled state.

- [ ] **Open the flyout** [ID: PD-ENTRY] [ADMIN: NO]
  With the module enabled and ready, independently open it from Settings, Quick Access,
  its tray icon and the current configured shortcut. Each route must show the flyout.
  Separately, when no module instance exists, launch the installed GUI without Runner
  arguments: standalone mode shows its window. Do not count standalone or a named event
  as proof of a Settings, tray, Quick Access or keyboard route.

- [ ] **Change the activation shortcut** [ID: PD-SHORTCUT] [ADMIN: NO]
  Cancel a shortcut draft, then save an unused valid binding. Check cancellation preserves
  the original, every saved modifier/key persists, the new binding toggles the flyout and
  the old binding no longer does. Restore the original and verify its actual activation.

- [ ] **Dismiss and reopen** [ID: PD-DISMISS] [ADMIN: NO]
  Press Escape in the foreground flyout and separately move focus to an owned ordinary
  window. Both hide the flyout without terminating the module. Reopen through the same
  tested trigger and check that the surface is usable, without accumulating instances.

- [ ] **Flyout and identify presentation** [ID: PD-PRESENTATION] [ADMIN: NO]
  Toggle tray-icon, profile-switcher and identify-button visibility in Settings, checking
  the corresponding surface and restoring each option. The profile button additionally
  requires saved profiles. With real monitors, identify them and check that each number
  appears on the matching display and the temporary overlays close. On two displays with
  different DPI, including a non-primary/negative-coordinate display, reopen the flyout:
  it stays within the target work area without covering the taskbar or clipping controls.

### Discovery and per-monitor controls

- [ ] **Refresh and display changes** [ID: PD-DISCOVERY] [ADMIN: NO]
  Use the flyout's refresh menu and observe a completed discovery rather than merely a
  successful click. With no controllable monitor, show the settled no-monitors state
  rather than fabricated controls. On an authorized hardware setup, unplug/reconnect and
  wake a display; stale controls are unavailable while discovery runs, then current
  displays return after the configured refresh delay. Stable device/port identities keep
  preferences associated with the right physical display, including identical models.

- [ ] **Built-in displays** [ID: PD-INTERNAL] [ADMIN: NO]
  With a WMI-brightness-capable panel, show the localized Built-in Display identity and
  adjust/read back brightness without duplicate DDC controls. Repeat on a dual-GPU laptop
  whose discrete GPU drives the internal panel; nominal connector classification must not
  prevent the WMI-capable panel from being controlled.

- [ ] **Monitor preferences and visibility** [ID: PD-PREFERENCES] [ADMIN: NO]
  In a monitor's Settings section, enable/disable its supported controls and hide/unhide
  that monitor; the flyout reflects the choices and unsupported feature options stay
  unavailable. Reopen Settings and rediscover the device to check preferences survive.
  With file-write/event instrumentation, verify only edits to the seven persisted monitor
  preferences cause save/notification, in save then IPC then module-event order; runtime
  readings, derived-property notifications and disk reloads do not write back.

- [ ] **Confirm potentially disruptive features** [ID: PD-GUARDED] [ADMIN: NO]
  For a newly discovered compatible monitor, input-source, color-temperature and power-state
  controls default off. For each feature separately, cancel its enable warning and check
  the option remains off; accept it and check the option persists and its supported control
  appears. Enabling a control is not permission to change the hardware. Restore all options.

- [ ] **Brightness, contrast and volume** [ID: PD-LEVELS] [ADMIN: NO]
  For each supported setting, read its real starting value, choose a distinct safe
  percentage, wait for the user edit to settle and independently read back the hardware.
  The intended monitor changes, other monitors do not, and the original value can be
  restored. Initial volume must reflect a successful device read rather than a placeholder.

- [ ] **Slider input and wheel increments** [ID: PD-SLIDER-INPUT] [ADMIN: NO]
  On each available brightness/contrast/volume slider, separately exercise mouse drag,
  keyboard arrows, touchscreen drag/tap-on-track, and wheel input. Each settled change
  reaches hardware; wheel input does not also scroll the parent. Select each advertised
  increment preset (1, 2, 5, 10, 15, 20, 25) and verify both wheel directions, with clamping
  at 0 and 100 on a safe instrumented fixture. Tray-wheel Off must not disable slider input.

- [ ] **Non-100 native ranges** [ID: PD-NATIVE-RANGE] [ADMIN: NO]
  On an instrumented DDC fixture advertising a maximum other than 100, test brightness,
  contrast and volume independently at 0%, 50% and 100%. The raw write/read uses that
  feature's native range while the UI and persistence remain percentages. Restore hardware;
  do not use unsafe physical brightness/volume extremes merely to cover this matrix.

- [ ] **Discrete monitor settings and orientation** [ID: PD-DISCRETE] [ADMIN: NO]
  With advertised capabilities and a physical recovery route, select an input source,
  color preset and power state, observing each actual hardware result separately.
  On hardware that supports DDC wake, select On after standby and verify the monitor wakes.
  Test 0/90/180/270 orientation through the shipped CLI on a disposable secondary display,
  checking Windows display configuration and restoring it. Do not require commented-out
  flyout rotation buttons on builds that expose orientation through the CLI instead.

- [ ] **Linked brightness** [ID: PD-LINKED] [ADMIN: NO]
  With two or more brightness-capable monitors, enable linking and check the master starts
  from the linked display with the lowest Windows display number. Changing it affects
  included monitors; exclude one and check its independent slider works without following
  the master. Check individual-card expansion, linked mode and exclusions survive reopening
  and restart. Apply a per-monitor profile: linking turns off before its distinct values
  are applied. A new monitor is included unless explicitly excluded.

- [ ] **Tray-wheel brightness** [ID: PD-TRAY-WHEEL] [ADMIN: NO]
  With a visible tray icon, compare Off, Primary display and All displays. Off leaves
  brightness and ordinary wheel delivery unchanged. Primary adjusts only the eligible
  primary monitor; All adjusts eligible visible brightness-capable monitors. Verify the
  configured increment and safe boundary clamping, exclusion of hidden/unreadable targets,
  and no flyout activation as feedback. Restore mode and all hardware values.

### Profiles and integration

- [ ] **Profile creation, editing and deletion** [ID: PD-PROFILES] [ADMIN: NO]
  With a controllable monitor, create an owned named profile with selected fields; reopen
  it and check exact selections/values. Cancel a new/edit draft without persisting it.
  Rename an existing owned profile without changing its ID or creation time. Create two
  profiles with the same name and check distinct stable IDs. Cancel deletion, then confirm
  deletion of only the selected owned ID. Invalid empty selections/names cannot be saved.

- [ ] **Apply saved profiles** [ID: PD-PROFILE-APPLY] [ADMIN: NO]
  Apply an owned profile independently from Settings and from the flyout switcher.
  Verify the included monitor fields against hardware; omitted fields and unrelated
  monitors remain unchanged. Preserve per-monitor values rather than treating a profile
  as a linked master level, and restore the pre-test hardware values.

- [ ] **Preserve unavailable profile contents** [ID: PD-PROFILE-PRESERVE] [ADMIN: NO]
  Using an owned existing profile, make one referenced monitor unavailable, then rename
  and save: retain its row, fields, ID and creation time. Repeat with temporarily unavailable
  capabilities and unsupported saved color presets. Explicitly deselecting a preserved
  monitor/field removes only that selection. Capability names/values changing without a
  list-size change refresh the editor; cleared selections, restored support and selected
  color values stay consistent. Newly chosen unsupported values cannot be saved.

- [ ] **Reorder profiles** [ID: PD-PROFILE-ORDER] [ADMIN: COND]
  Create three owned profiles. Move the middle one up/down through its menu and, in an
  ordinary process, drag it to another position. Reopen and verify persisted order with
  IDs, creation times and monitor settings unchanged. The flyout, CLI list and Light Switch
  pickers use the same order. In an authorized elevated Settings session, dragging is
  disabled with guidance while menu reordering remains available. Restore original order.

- [ ] **Custom VCP names** [ID: PD-MAPPINGS] [ADMIN: NO]
  Add, edit and delete owned input-source/color-preset name mappings; cancel drafts without
  saving. Verify the exact code/value/name persists. On matching hardware, global mappings
  rename the advertised value across applicable monitors, and monitor-specific mappings
  affect only the targeted identity. Remove the mapping and check the normal label returns;
  naming must not change the underlying VCP value.

- [ ] **Light Switch profiles** [ID: PD-LIGHT-SWITCH] [ADMIN: NO]
  With authorized theme changes and two owned monitor profiles, configure distinct light
  and dark profile IDs. Exercise successive Light Switch transitions in both directions;
  each applies the corresponding hardware values, including the second hotkey transition.
  Renaming/reordering retains the association; deleting an assigned owned profile clears
  its reference. When Power Display is disabled, show the configuration warning rather
  than implying a successful apply. Restore theme, bindings, profiles and hardware.

### Persistence, compatibility and recovery

- [ ] **Startup restoration** [ID: PD-STARTUP] [ADMIN: NO]
  On a recoverable hardware fixture, compare startup restoration off and on. Off must not
  replay saved monitor values; on restores saved supported values. Null/unread settings
  are not treated as zero, while a genuine saved zero is retained. With a failed initial
  read and a saved value equal to the displayed placeholder, restore still sends the write.
  Make a final edit and cooperatively exit/reopen: the last change survives in valid state
  storage. Restore original startup behavior and hardware before ending the run.

- [ ] **Maximum compatibility mode** [ID: PD-COMPATIBILITY] [ADMIN: NO]
  Cancel and then accept the compatibility warning; only acceptance enables the setting
  and triggers rediscovery. With an instrumented monitor whose capabilities are empty or
  unparsable, recover supported continuous controls without exposing unsupported brightness.
  On transient read failure, bounded retries can recover and successful probe readings
  initialize the UI without being replaced by failed rereads. A previously valid cached
  value for the same stable identity can support later compatibility discovery; a monitor
  that never supplied a valid value must not acquire fabricated support from another device.

- [ ] **Retain preferences and migrate identities** [ID: PD-MIGRATION] [ADMIN: NO]
  In an isolated upgrade fixture, migrate legacy monitor IDs only to the exact matching
  EDID/display-number identity; ambiguous/unmatched entries must not attach to another
  monitor. Cover Settings, profiles and monitor-state sidecars. Upgrade name-addressed
  profiles/Light Switch references to stable numeric IDs without losing valid associations.
  Under an instrumented clock/discovery fixture, temporarily absent recent monitor entries
  retain preferences; stale entries expire under the retention rule and hidden entries remain.

- [ ] **Crash protection and cooperative exit** [ID: PD-RECOVERY] [ADMIN: NO]
  In a disposable, explicitly authorized fault fixture, an orphan capability-discovery
  marker causes auto-disable and a locked Settings warning before new DDC queries. Ignore
  clears the warning but does not silently re-enable the module. With an instrumented
  blacklisted identity, discovery must skip it before capability access; do not attach
  known-bad hardware merely for this check. Separately use normal tray Exit: process,
  tray icon and CLI service are released, and a cooperative exit during discovery must
  not leave a false crash marker on the next launch.

### Command line

- [ ] **CLI discovery and read-out** [ID: PD-CLI-READ] [ADMIN: NO]
  Use the installed CLI's help/version and list/get/capabilities/profiles commands.
  Check list identities/transports against actual discovery, get's supported/unread
  distinctions, capability values against the advertised device, and profile IDs/order
  against saved owned profiles. Exercise selectors by display number and stable ID;
  when both are supplied the stable ID takes precedence. The installed native shim
  forwards arguments and the exit code to the same CLI.

- [ ] **CLI hardware and profile actions** [ID: PD-CLI-WRITE] [ADMIN: NO]
  On recoverable hardware, set each supported continuous/discrete setting and orientation,
  observing the actual target rather than trusting stdout. Exercise up/down with an
  explicit step and the configured wheel increment, including zero-step no-op and clamping.
  Select multiple monitor numbers with duplicates and verify each target once; retain
  per-target successes/failures. Apply an owned profile by numeric ID. Standby/off requires
  `--confirm-power-off`; omitting it must not change power state.

- [ ] **CLI errors** [ID: PD-CLI-ERRORS] [ADMIN: NO]
  Check the matrix below with safe invalid inputs and appropriate observer/IPC fixtures.
  A rejected request must not change hardware; keep timeout/hardware/internal failures
  conditional rather than causing real faults. With the provider absent, a command reports
  unavailability instead of starting it or claiming success.

  | Condition | Exit code |
  |---|---:|
  | Unknown monitor | 1 |
  | Continuous value outside 0..100 | 2 |
  | Discrete value not advertised | 3 |
  | Unsupported feature | 4 |
  | Controlled hardware failure | 5 |
  | Missing required monitor selector | 6 |
  | Parse error, negative step, malformed number list or multiple setting options | 7 |
  | Controlled request timeout | 8 |
  | Controlled internal error | 9 |
  | Provider unavailable | 10 |

- [ ] **CLI JSON Lines** [ID: PD-CLI-JSON] [ADMIN: NO]
  Compare default text output with `--json` on read commands and an authorized mutation.
  Each structured result is compact JSON Lines on stdout; structured parse/IPC errors go
  to stderr with the matching exit code, not mixed human text. Verify `--json` works as
  a global presence flag before/after a subcommand without swallowing its argument.
  Help/version retain their documented human-readable behavior.

### Policy and appearance

- [ ] **Group Policy** [ID: PD-POLICY] [ADMIN: COND]
  In an authorized isolated policy fixture, force disabled and check Settings cannot
  enable the module and direct GUI activation cannot bypass policy. Force enabled and
  check the policy-controlled Settings state; return to Not configured and recover normal
  user control. Restore exact policy value existence/kind and original runtime state.

- [ ] **Appearance and localization** [ID: PD-APPEARANCE] [ADMIN: NO]
  With authorized theme/language changes, inspect light/dark flyout, Settings and dialogs
  for readable controls and unclipped content. In another installed locale, user-facing
  labels and Built-in Display are localized while the Power Display product name and CLI
  command/option literals remain intact. Check OOBE identity and shortcut presentation
  against current Settings. Restore the original theme/language and visible UI.

- [ ] **VCP capability details** [ID: PD-CAPABILITIES] [ADMIN: NO]
  With a monitor advertising VCP capabilities, open its Settings details and compare code
  names/values with the independently captured capability string. Copy the VCP list and
  verify the selected monitor's text using a private clipboard guard, then restore every
  original format. This is not the separately introduced diagnostics-copy feature.

- [ ] **Settings navigation while active** [ID: PD-SETTINGS-LIVE] [ADMIN: NO]
  Open the Power Display page while its module is running, navigate away and return,
  then change an owned non-hardware option. The current controls and persistence remain
  usable without duplicate saves caused by runtime monitor notifications. Verify the
  flyout receives the option change and restore it; report process/resource leak claims
  only with suitable instrumentation, not a single successful navigation.
