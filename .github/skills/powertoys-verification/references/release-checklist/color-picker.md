# Color Picker - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - standard-user coverage, subject to the stated fixtures.
- `[ADMIN: YES]` - requires an authorized elevated Runner/session.
- `[ID: ...]` - stable scenario identifier; all CP01-CP25 children remain independently reportable.
- `[CLARITY: REWRITTEN]` - an existing requirement has an explicit executable interpretation.

## Fixtures & conventions

- Use a test-owned known-color surface and disposable history colors. Preserve settings,
  history, clipboard, window placement and any companion state before mutation; restore
  the exact original values and close only test-owned surfaces.
- Confirm the installed UI stack and activation model. The three picker/editor user flows
  can be configured through activation and mouse-button settings, not necessarily three
  identically named options. A later WinUI artifact requires its migration inclusion to be
  recorded; an earlier WPF observation is not WinUI evidence.
- Missing elevation, a supported non-English language or controlled display-frequency input
  blocks only that condition. Do not install language packs, disrupt the shared session,
  or manufacture registry/elevation fallback conditions without authorization.
- Use the [module profile](../modules/color-picker.md) for interaction/restoration and the
  [frozen inventory](../assertion-inventories/color-picker.json) for detailed assertions.
  A missing integration command does not prove its dependent pin/history actions failed.

## Color Picker (17 items)

### Activation and entry points

- [ ] **Configured shortcut, rebinding and narrow Settings layout** [ID: CP-BINDINGS] [ADMIN: NO] [CLARITY: REWRITTEN]
  Start PowerToys normally and verify its non-elevated token. Enable Color Picker through Settings and use the displayed original shortcut; confirm the configured surface opens. Change to an unused chord, confirm it activates and the previous chord does not, then restore and exercise the original. At a supported narrow Settings width, confirm the shortcut edit control remains visible and usable; restore placement. Physical-key observations cannot be replaced by a Named Event.

- [ ] **Elevated startup** [ID: CP-ELEVATED-START] [ADMIN: YES] [CLARITY: REWRITTEN]
  Start PowerToys elevated, enable Color Picker and use its configured shortcut. Confirm the selected activation surface opens and record the actual Runner integrity.

- [ ] **Restart as administrator** [ID: CP-ELEVATION-RESTART] [ADMIN: YES] [CLARITY: REWRITTEN]
  Use Settings' Restart as administrator action, confirm the new Runner's integrity, and activate Color Picker with its configured shortcut. Confirm the selected surface opens; elevated startup alone does not prove this restart route.

- [ ] **Picker/editor transitions** [ID: CP-ACTIVATION-FLOWS] [ADMIN: NO] [CLARITY: REWRITTEN]
  On the controlled surface, separately exercise picker then editor after selection, direct editor, and picker-only copy then close without editor. Close each surface before the next activation. Also invoke the editor's actual Pick color action and confirm it samples the controlled surface and returns the new color to the editor. Restore the original activation/mouse-button settings.

- [ ] **Welcome launch guard** [ID: CP-WELCOME] [ADMIN: NO]
  Navigate to Color Picker in Welcome while the module is disabled and confirm Launch is disabled. Enable the module and navigate to that page again; Launch must be enabled and open the configured surface. Observe on page navigation, not an unspecified live-update condition. Restore enablement and close only owned Welcome windows.

- [ ] **Editor Settings link** [ID: CP-SETTINGS-LINK] [ADMIN: NO] [CLARITY: REWRITTEN]
  With Settings closed or showing another module, use the installed editor's Open settings action. Confirm the same installation's Settings becomes foreground on Color Picker, then restore its previous page/visibility. This covers normal installed-path resolution, not missing/misdirected registry or elevated fallback branches requiring a disposable environment.

### Clipboard and color formats

- [ ] **Picker and editor clipboard formats** [ID: CP-COPY-FORMATS] [ADMIN: NO] [CLARITY: REWRITTEN]
  Select each of two clipboard formats in Settings and pick a known color; independently compare actual clipboard text with that color's expected representation. In the editor, copy at least two displayed format rows for the same color and compare each actual clipboard value with its own row. Preserve both routes and restore the clipboard and original default format.

- [ ] **Format list and label rendering** [ID: CP-FORMAT-LIST] [ADMIN: NO] [CLARITY: REWRITTEN]
  Enable one disabled format, disable an enabled format and reorder enabled formats through Settings. Reopen the editor and separately confirm presence, absence and order. Inspect rendered HEX/RGB labels for legibility rather than washed-out secondary text; capture the actual image and record its theme. Restore the original enabled set, format strings and order.

- [ ] **CIELAB rounding** [ID: CP-CIELAB] [ADMIN: NO]
  Edit a CIELAB format through Settings. For the same known picked color, compare `%Lc`, `%Ca`, `%Cb` with `%Lci`, `%Cai`, `%Cbi`: defaults retain two-decimal rounding, `i` forms round to integers, and a negative fraction rounding to zero produces `0`, not `-0`. Use the independently defined near-gray fixture where needed. Confirm format help describes `i` and restore the original format.

### Picker display and sampling

- [ ] **Color name and magnifier** [ID: CP-PICKER-VISUALS] [ADMIN: NO] [CLARITY: REWRITTEN]
  Over one controlled surface, toggle Show color name on/off and confirm the sampled color's name appears/is hidden. Zoom in and inspect the magnified pixels: the picker's own UI corner must not be included. After zooming in/out, confirm the picker is visible in a normal screen capture. Restore the original setting.

- [ ] **Display-frequency edge cases** [ID: CP-REFRESH-RATE] [ADMIN: NO]
  With controlled frequency inputs, exercise reports `0` and `1`; both must use the 60 Hz fallback without overflow or one-second sampling. Reports greater than `1` retain their actual rate. Record which values were supplied: ordinary 60 Hz picking does not cover the sentinel branches.

### History and adjustment

- [ ] **Select, remove and reopen history** [ID: CP-HISTORY] [ADMIN: NO] [CLARITY: REWRITTEN]
  Select a non-current owned history color and confirm the swatch and displayed values change without removing other entries. Remove an owned color, confirm it is absent and unrelated entries remain, then reopen and verify persistence. Restore the original history.

- [ ] **Adjustment popup** [ID: CP-ADJUST] [ADMIN: NO] [CLARITY: REWRITTEN]
  Open Adjust color for the editor's selected color. Confirm the popup shows that color and its editing controls; dismiss without leaving an unintended color/history change.

### Command Palette integration

- [ ] **Commands, disabled filtering and pinning** [ID: CP-CMDPAL] [ADMIN: NO]
  In the PowerToys extension, invoke Color Picker, its Settings command and a saved color that copies the expected history value. Pin a discovered command, leave and return to Home, and confirm the identifiable pin still performs its action. With Color Picker disabled, Settings remains but picker/saved-color commands are absent. Restore module/clipboard state and remove only the owned pin. Observe command availability before its dependent actions; missing shipped commands are an integration failure.

### Localization

- [ ] **Module and extension language** [ID: CP-LOCALIZATION] [ADMIN: NO] [CLARITY: REWRITTEN]
  In a supported non-English Windows display language, inspect picker/editor labels and tooltips, plus Command Palette's Color Picker titles, descriptions and saved-color labels. Confirm the selected translations rather than English resource presence. Restore the original language; unavailable packs or disruptive sign-out requirements remain explicit blockers.

- [ ] **Settings attribution language** [ID: CP-ATTRIBUTION] [ADMIN: NO]
  In a supported non-English Settings language, inspect both attribution links. Translatable wording must be localized, contributor/product names preserved and link targets unchanged. English-only rendering or an `x:Uid` is not proof.

### Diagnostics

- [ ] **Run-scoped logs** [ID: CP-LOGS] [ADMIN: NO] [CLARITY: REWRITTEN]
  After actual Color Picker execution, examine logs generated during this run and report new errors with timestamps and responsible actions. Historical errors are not new failures; an empty interval without module execution is insufficient.
