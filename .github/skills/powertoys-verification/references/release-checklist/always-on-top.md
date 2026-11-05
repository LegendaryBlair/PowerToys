# Always On Top - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - standard-user coverage with the stated fixtures.
- `[ADMIN: COND]` - retain ordinary and authorized elevated conditions separately.
- `[ID: ...]` - stable case identifier used by the assertion inventory.

## Fixtures & conventions

- Use identity-tracked, disposable top-level windows with an opaque synthetic backdrop.
  Never pin, exclude, change opacity on, or close a pre-existing user window.
- Preserve module settings, original enablement, borrowed Settings navigation/placement,
  foreground and pointer. Restore through the UI, verify persistence and runtime state,
  and unpin owned windows before closing them. Do not replace installed binaries or seed
  product settings to reach a test state.
- Match actual Runner/module/fixture integrity before shortcut input. Border pixels and
  topmost/opacity properties are different observations; a settings readback proves neither.
- See [shared fixture ownership](../owned-fixtures.md),
  [session restoration](../session-safety.md) and
  [shortcut recording](../shortcut-recorder.md) for the operating contracts.
  Sound, Game Mode, new-profile defaults, localization and session-end cases retain their
  stated prerequisites; unavailable conditions do not cancel ordinary coverage.

## Always On Top (17 items)

### Activation and window lifetime

- [ ] **Pin, unpin and highlight** [ID: AOT-PIN] [ADMIN: NO]
  Focus an ordinary owned window and use the configured pin shortcut. Verify its
  topmost state and visible highlight independently; focus an overlapping ordinary
  owned window and confirm the pinned window remains above it. Repeat the shortcut,
  verifying that topmost and highlight are removed and normal overlap resumes.

- [ ] **Minimize, restore and maximize** [ID: AOT-WINDOW-STATE] [ADMIN: NO]
  Pin the owned window with highlighting enabled. Minimize it: no border remains
  floating onscreen. Restore it: pinning and the surrounding border return. Maximize
  it and verify the border follows the visible frame rather than its former rectangle.
  Restore normal placement before releasing the fixture.

- [ ] **Virtual desktop isolation** [ID: AOT-VIRTUAL-DESKTOP] [ADMIN: NO]
  With an identity-checked original desktop and a safely owned temporary desktop,
  pin the fixture and switch away. Its border must not appear on the other desktop.
  Return to the original desktop and verify the fixture is still pinned with its
  surrounding border. Remove only the desktop created by this case.

- [ ] **Enablement and Settings controls** [ID: AOT-ENABLE] [ADMIN: NO]
  With no user-owned pinned windows affected, disable Always On Top through Settings.
  Verify the module stops and its dependent activation/appearance controls are disabled.
  Re-enable it, verify controls and module readiness return, and perform an ordinary
  pin/unpin. Navigating away and back must retain configured values and enablement.

- [ ] **Pin shortcut editing** [ID: AOT-PIN-SHORTCUT] [ADMIN: NO]
  Record a collision-checked temporary shortcut in the pin shortcut editor. Save and
  verify its complete persisted binding, actual activation, and that the former binding
  no longer pins the fixture. Cancel a different draft and verify the saved binding
  remains unchanged. Restore the original binding and demonstrate pin/unpin with it.
  The editor must show its shortcut and Save/Cancel controls without clipping.

### Border appearance

- [ ] **Live border customization** [ID: AOT-BORDER] [ADMIN: NO]
  Keep the same ordinary fixture pinned throughout the live settings changes, without
  restarting the module. Turn highlighting off and on: the border disappears/returns
  while the fixture stays topmost. Select custom color, change it from `#00CC66` to
  `#FF00FF`, and change thickness from 4 to 18; independently observe the saved values
  and changed composed border pixels/geometry. Compare custom color with Windows
  accent mode using the current accent as the independent reference.
  At 100% frame opacity the straight border interior is solid, not mottled or
  translucent; at 50% it blends with the known backdrop without filling the target's
  interior. On Windows 11 compare rounded corners on/off, retaining the surrounding
  frame and transparent interior. Assess available monitor/DPI conditions individually.

- [ ] **Fresh and existing border defaults** [ID: AOT-DEFAULTS] [ADMIN: NO]
  On a separately authorized clean user/profile with no previous Always On Top
  settings, verify the initial thickness is 4 and the UI agrees with the saved value.
  Separately, retain an existing non-default thickness through ordinary module
  disable/enable and Settings reopen/navigation; it must not reset to 4.
  Do not delete or rename this user's configuration to simulate a clean install.

### Exclusions, sound and Game Mode

- [ ] **Excluded applications** [ID: AOT-EXCLUDE] [ADMIN: NO]
  Add only the collision-checked fixture executable to the existing exclusion list.
  Attempt pinning: the fixture must stay unpinned without a border. Remove that entry
  and pin it, then add the entry while it is pinned: topmost and border must be removed
  without another shortcut or module restart. Restore the exact original list.

- [ ] **Sound follows the setting and result** [ID: AOT-SOUND] [ADMIN: COND]
  With a usable audio endpoint and a process-attributed audio observer or human listener,
  enable sound and verify feedback for successful pin and successful unpin separately.
  Disable sound and repeat both actions, verifying no feedback.
  With an explicitly authorized elevated owned target and a non-elevated module,
  establish that the requested state change failed and verify there is no success
  sound. A sound-file open or a log statement alone is not proof of audible output.

- [ ] **Game Mode blocking** [ID: AOT-GAME] [ADMIN: NO]
  Use an owned exclusive Direct3D fullscreen fixture and independently confirm Windows
  reports `QUNS_RUNNING_D3D_FULL_SCREEN`; enabling Windows' Game Mode preference alone
  is not this prerequisite. With blocking enabled, the shortcut must not mark the
  fixture pinned. With blocking disabled under the same detected condition, it must
  pin. Exit fullscreen and verify normal pin/unpin with blocking enabled.
  Restore fullscreen/device state and the original setting even when a condition fails.

### Window opacity and shortcut independence

- [ ] **Pinned-window opacity** [ID: AOT-OPACITY] [ADMIN: NO]
  On a layered-alpha-compatible owned window, pin and decrease opacity, then increase
  it with the configured shortcuts. Check actual alpha and visible composition, not
  just shortcut delivery. Unpin and verify the original non-layered state returns.
  Repeat restoration on a fixture that was already layered with a known non-default
  alpha before pinning; preserve its original alpha/flags rather than forcing opacity.
  On an unpinned key-observing fixture, both opacity shortcuts must leave opacity
  unchanged and pass their keys to the application. Special renderer incompatibility
  is conditional, not a failure of the supported ordinary-window path.

- [ ] **Independent opacity shortcuts** [ID: AOT-OPACITY-SHORTCUTS] [ADMIN: NO]
  Give increase and decrease distinct collision-checked shortcuts with modifiers
  different from the pin binding. For each, Save, verify the complete stored binding,
  drive its effect on a pinned compatible fixture and confirm its former binding no
  longer changes alpha. Editing either must not change the other or the pin binding.
  Cancel a draft and verify all saved bindings remain. Restore all three originals
  and observe increase/decrease again. Keep increases away from maximum opacity so
  an unchanged alpha is not mistaken for a failed shortcut.

### Window menu and external entry points

- [ ] **Window system menu** [ID: AOT-SYSTEM-MENU] [ADMIN: NO]
  On an owned classic top-level window, turn the system-menu option off and verify
  Always On Top is absent; turn it on and open the real title-bar system menu.
  Verify exactly one command appears, including after reopening the menu.
  Invoke it to pin and unpin, checking actual state and the menu checkmark each time.
  With a separate owned fixture whose existing command uses the same command ID,
  verify its original caption/action is preserved and no replacement Always On Top
  command is injected. Restore the option before closing the fixtures.

- [ ] **Command Palette Settings command** [ID: AOT-CMDPAL] [ADMIN: NO]
  When the installed PowerToys extension is available, find Always On Top in Command
  Palette and invoke its Settings command; it must open the Always On Top page, not
  pin the palette or another window. With owned/restorable palette favorites, pin
  that command, reopen the palette and verify the command persists; unpin and verify
  removal. In an already available non-English test locale, verify the command's
  title/subtitle are localized. Preserve palette query/navigation, settings and any
  newly activated extension-process lifetime; do not re-register packages.

- [ ] **Read-only Settings refresh** [ID: AOT-REFRESH] [ADMIN: NO]
  With an explicitly recorded non-default Always On Top enabled state, use Check for
  updates without downloading/installing an update. Verify the module's enabled
  value and runtime state remain unchanged through the check. Restore navigation;
  do not change update-channel or automatic-update settings to manufacture this case.

### Conditional release integration

- [ ] **Windows session ending** [ID: AOT-SESSION-END] [ADMIN: NO]
  In a separately authorized disposable Windows session, cancel a session-end attempt
  and verify Always On Top remains usable. In a distinct confirmed logoff/shutdown,
  verify its message loop exits without a quiesce hang. Preserve the two conditions
  separately. Ordinary module disable is not a substitute; do not log off this shared
  desktop or inject shutdown messages into its borrowed processes.

- [ ] **Diagnostic event collection** [ID: AOT-TELEMETRY] [ADMIN: NO]
  Where diagnostic collection/viewing is already consented and a normal restart is
  authorized with complete restoration, enable Diagnostic data and Enable viewing
  through General settings before the flows. After pin/unpin, open the Diagnostic
  data viewer and confirm Always On Top events correspond to those actions.
  Do not enable data collection without consent, publish raw diagnostics, or infer
  emitted events solely from source. Restore the original diagnostic settings.
