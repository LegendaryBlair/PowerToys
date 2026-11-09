# Awake - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - ordinary-user coverage, subject to the stated fixtures.
- `[ADMIN: COND]` - keep ordinary and explicitly authorized privileged conditions separate.
- `[ID: ...]` - stable case identifier in the assertion inventory and report.

## Fixtures & conventions

- Preserve original Awake preferences, enablement, Settings navigation/placement, foreground and pointer.
  Use the shared [session safety](../session-safety.md) and [paired snapshots](../helper-workflow.md).
  Never replace user settings with a seeded UI-test configuration.
- Distinguish the requested mode, persisted settings, actual power requests and physical sleep/display
  behavior. System-wide execution flags need a controlled differential baseline; unrelated requests
  must not be attributed to Awake. Leave the selected Windows power plan unchanged.
- Standalone cases require the integrated instance to be disabled through Settings first, exact
  ownership of each new process, and verified restoration of the original integrated state.
  Use disposable terminal/PID fixtures, not a user's terminal or clipboard.
- Lock, sleep/resume, power-source changes, policy, OS-update and failure-injection cases require
  an appropriate authorized environment and independent recovery/observation. Do not disconnect
  or lock the shared desktop, replace installed binaries, or change policy merely to obtain coverage.

## Awake (17 items)

### Settings and power requests

- [ ] **Enablement and isolation** [ID: AWAKE-ENABLE] [ADMIN: NO]
  Disable Awake through its Settings page: the module process and notification icon disappear and
  behavior controls become unavailable. Enable it again: the process/icon return and the retained
  mode becomes active. Other modules' enabled values must remain unchanged.

- [ ] **Passive, indefinite and display behavior** [ID: AWAKE-MODES] [ADMIN: NO]
  Select "Keep using the selected power plan": Awake remains resident without its own system/display
  keep-awake requests, and "Keep screen on" is unavailable. Select indefinite mode, then switch
  "Keep screen on" off and on: observe system-only and system-plus-display requests respectively.
  Return to passive and verify release. Compare the active power plan and settings before/after.
  Physical idle/sleep prevention additionally needs a controlled idle interval and independent observer.

- [ ] **Duration editing and completion** [ID: AWAKE-TIMED] [ADMIN: NO]
  Select interval mode, set hours/minutes to 1/2, commit each field, and verify persisted values and
  active runtime state; expiration controls are hidden. Set 0/1 and measure a full one-minute run,
  toggling "Keep screen on" during the countdown. The display request changes without restarting
  the deadline. Completion returns Settings and runtime to passive while Awake remains resident.
  Start another interval and cancel by selecting passive; requests release without waiting for expiry.

- [ ] **Expiration date and time** [ID: AWAKE-EXPIRATION] [ADMIN: NO]
  Select expiration mode and use its date/time pickers to commit a future deadline. Check both edited
  values, absence of duration controls, and active system/display behavior. With a short future
  deadline, observe expiry returning to passive without exiting the integrated module. Preserve
  the original timestamp, including offset and precision, during restoration.

### Notification-area controls

- [ ] **Tray entry paths and live synchronization** [ID: AWAKE-TRAY] [ADMIN: NO]
  Open the real Awake notification icon by left click and right click independently. Both expose
  passive, indefinite, interval and screen controls; the expiration entry is informational/disabled,
  and integrated mode has no standalone Exit command. Select indefinite, toggle the screen option,
  then select passive; Settings, persisted values, tray status and runtime requests must agree.
  In a default-times fixture, inspect 30 minutes, 1 hour and 2 hours and select each, checking
  the corresponding duration before returning to passive.

- [ ] **Custom interval dispatch** [ID: AWAKE-CUSTOM-TRAY] [ADMIN: NO]
  With an independently prepared customTrayTimes fixture containing at least two distinct entries,
  select the first and last entries through the tray. Each starts its own configured duration,
  including the last entry rather than an invalid command. Preserve ordering, labels and values.
  Do not seed this fixture through direct JSON edits during installed-artifact UI verification.

- [ ] **Notification icon after OS servicing** [ID: AWAKE-TRAY-RECOVERY] [ADMIN: COND]
  On an authorized disposable post-Windows-update/session-start fixture, enable Awake and verify
  its real notification icon becomes available; disable it and verify removal. A normal tray
  observation is not evidence that the OS-servicing condition was exercised.

### Command-line operation

- [ ] **Visible help and parse errors** [ID: AWAKE-CLI-TEXT] [ADMIN: NO]
  In an owned real terminal, run `--help`, `-h` and `-?` independently. Each visibly lists the
  documented options and returns zero without starting a resident instance. Independently run
  `--time-limit -1`, `--pid not-a-pid` and `--expire-at not-a-date`; each visibly explains the
  invalid argument, returns nonzero and leaves no new resident process or power request.
  Redirected output alone does not establish text visibility in a parent console.

- [ ] **Standalone modes and precedence** [ID: AWAKE-CLI-MODES] [ADMIN: NO]
  With integrated Awake disabled, launch without arguments: system sleep is inhibited but display
  sleep is not. Separately exercise `--display-on` and `--display-on false`. End each owned session
  using its user-facing Exit/console-close path and verify request release. Run `-t 20 -d` and
  observe actual expiry/exit after the requested interval. Run `--expire-at` with a deadline about
  30 seconds ahead together with `--time-limit 300`; the absolute deadline wins and the process exits.
  Standalone arguments must not overwrite integrated preferences or the Windows power plan.

- [ ] **Process-bound lifetime** [ID: AWAKE-PID] [ADMIN: NO]
  Bind Awake with `--pid` to an owned finite-lived process and separately use `--use-parent-pid`
  from an owned parent shell. Observe active requests while each target lives and Awake's own
  exit/request release after that target exits; do not terminate Awake to simulate the outcome.

- [ ] **Configuration-bound CLI** [ID: AWAKE-CLI-CONFIG] [ADMIN: NO]
  With the integrated instance disabled and a preserved existing configuration, launch
  `--use-pt-config --display-on --time-limit 1`. Saved mode/display values take precedence over
  conflicting standalone arguments. Change mode/display through Settings and observe live reload
  without replacing that process. Return it to passive, close the owned CLI session and restore
  original enablement/preferences; do not write JSON to create a passing observation.

### Session and power transitions

- [ ] **Lock-state behavior** [ID: AWAKE-LOCK] [ADMIN: NO]
  On a recoverable dedicated session, test startup while already locked, then unlocked-to-locked
  and locked-to-unlocked transitions with keep-screen-on selected. Locked state releases Awake's
  display request while retaining its active system request; unlock reapplies the configured
  display request. Observe each condition independently without confusing an RDP disconnect
  with a workstation lock. Requires a build containing the lock-state change.

- [ ] **Resume, power source and API failure** [ID: AWAKE-POWER] [ADMIN: COND]
  In a dedicated recoverable fixture, resume from actual sleep and separately transition AC to
  battery and back: active Awake state is reapplied and Settings remains functional. With authorized
  failure instrumentation, make SetThreadExecutionState fail: verify an error and passive/tray
  fallback rather than silently advertising an effective request. Do not modify the installed
  artifact or synthesize a broadcast as a substitute for real resume/power-source coverage.

### Integrations and diagnostics

- [ ] **Command Palette Awake commands** [ID: AWAKE-CMDPAL] [ADMIN: NO]
  With the shipped PowerToys extension available and its UI/provider state preserved, open Awake
  Settings through Command Palette. When Awake is enabled, exercise indefinite, 30-minute,
  1-hour, 2-hour and Turn off commands, independently comparing refreshed status, Settings and
  runtime behavior. When disabled, the Settings command remains but active-mode commands are absent.
  A toast alone is not proof of the requested state.

- [ ] **Shared Settings state preservation** [ID: AWAKE-SHARED] [ADMIN: NO]
  Check for updates through Settings with Awake enabled and separately disabled, retaining each
  state and other module enablement values. Do not install an offered update. On a separately
  authorized disposable missing-module/shutdown fixture, verify a disabled Awake choice survives
  unavailable-module persistence and shutdown/restart; do not remove installed files or restart
  the shared machine for this condition.

- [ ] **Policy and diagnostic events** [ID: AWAKE-DIAGNOSTICS] [ADMIN: COND]
  With authorized policy control, force Awake disabled: Settings cannot enable it and standalone
  activation is rejected, but `--help` remains visible and succeeds. Restore the exact policy.
  With consented diagnostic viewing already available (or separately authorized setup/restart),
  associate mode-change events and successful/failed CLI command events with this run's actions.
  Do not enable telemetry, expose unrelated event payloads, or infer emission from source alone.

### Exploratory coverage

- [ ] **Open-ended baseline exploration** [ID: AWAKE-EXPLORATORY] [ADMIN: NO]
  Explore additional Awake features and record concrete actions/findings. The supplied baseline
  has no feature list or acceptance oracle for this request; retain that unresolved expectation
  for review. Passing the concrete cases above must not silently convert open-ended exploration
  into a complete, objectively verified requirement.
