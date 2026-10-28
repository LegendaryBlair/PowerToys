# Keyboard Manager - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - standard-user coverage with compatible foreground integrity.
- `[ADMIN: YES]` - requires separately authorized elevation.
- `[ADMIN: COND]` - report ordinary and elevated conditions independently.
- `[ID: ...]` - stable case identity in the [assertion inventory](../assertion-inventories/keyboard-manager.json).

## Fixtures & conventions

- Use collision-checked, disposable mappings and owned text/application fixtures. Preserve original enablement, editor choice, shortcuts, active profile, engine mappings and editor-side enabled/disabled entries; do not capture private mapping text or application paths.
- Snapshot before opening an editor: startup can reconcile its store with the engine profile. Restore through the UI first, then verify both stores, owned process/window closure and original Settings/desktop state. Use [shared ownership](../session-safety.md), [file preservation](../helper-workflow.md) and [owned fixtures](../owned-fixtures.md); byte rollback is cleanup, never a way to create a passing mapping.
- For paste cases, preserve the complete supported clipboard with the [clipboard session](../clipboard-guard.md), then use synthetic text. Never send Close, task switching, shell shortcuts or modifier holds into user windows. Keep input serial and release every owned key in `finally`.
- The classic editor and WinUI editor have different commit/recording controls. Test classic-only behavior in classic mode; do not mistake new-editor validation for the old warning dialog. Restore the original mode. New-editor features below require a build containing them; recording/dropdown refinements require the changes shipped in preview 0.102.3001.
- For every remapping matrix row below, observe a press/release and a held/repeated press separately. Where modifiers participate, exercise modifier-first and action-first release orders, then verify ordinary typing is not left modified. A tap does not cover a hold. Use an input observer when visible text cannot distinguish the events.

## Keyboard Manager (24 items)

### Settings and entry points

- [ ] **Open the configured editor** [ID: KM-ENTRY] [ADMIN: NO]
  Open Keyboard Manager from its Settings page and confirm the configured editor is usable. With the new editor selected and module enabled, separately test the configured editor shortcut, its Dashboard shortcut listing, the Command Palette open command and its Dock pin/relaunch route when that integration is installed. Clear the editor shortcut through Settings and verify the old binding no longer opens it; restore and verify the original binding. Do not expect the removed independent service-toggle shortcut.

- [ ] **Choose the editor experience** [ID: KM-EDITOR-MODES] [ADMIN: NO]
  Switch between the new experience and classic Remap keys/Remap shortcuts through Settings and open each destination. Preserve existing mappings and the explicit preference across reopening. In a separately authorized clean/migration fixture, missing `useNewEditor` selects the new editor; an explicit false preference remains classic. Do not delete live settings to manufacture the missing-property condition.

### Mapping creation and validation

- [ ] **Create, cancel, save and reopen mappings** [ID: KM-DRAFT] [ADMIN: NO]
  In classic Remap keys, add and remove rows; OK with blank rows warns about invalid mappings. Save valid mappings with OK and reopen both classic windows to check their persisted entries. In the new editor, create a valid owned key mapping, save it and observe the list plus persisted engine/editor entries; reopen the editor and verify the entry is retained. Cancel an unsaved add/edit and confirm the original stored mapping is unchanged. Empty new-editor drafts must not commit an invalid mapping.

- [ ] **Record keys and shortcuts** [ID: KM-RECORDING] [ADMIN: NO]
  In both classic windows use only Type controls: the Remap keys source accepts keys, the Remap shortcuts source accepts shortcuts, and both targets accept keys and shortcuts. Verify hold-Enter acceptance and hold-Esc cancellation. In the new editor record trigger and action fields, including modifiers pressed out of order; display order is Win, Ctrl, Alt, Shift, action. While recording, type only owned text in a different foreground fixture and confirm it is not captured. Tab and Shift+Tab with no other keys held end recording and move focus forward/backward, retain captured keys and uncheck recording; stopping without a capture restores previous keys. Select lone Tab from the dropdown rather than recording it.

- [ ] **Select keys without recording** [ID: KM-DROPDOWNS] [ADMIN: NO]
  Build key-to-key, key-to-shortcut, shortcut-to-key and shortcut-to-shortcut mappings using dropdowns, once with mouse interaction and once with keyboard navigation. New empty trigger/action fields offer Select key; choose a media key without pressing it, and build a shortcut by selecting a modifier followed by its added empty slot. Search keys case-insensitively, select with Enter, observe the no-match state and reopen with cleared search. Reject invalid selections without breaking subsequent dropdown updates; placeholder/None entries must not persist as keys.

- [ ] **Reject conflicting and forbidden mappings** [ID: KM-VALIDATION] [ADMIN: NO]
  Create an owned duplicate, then edit another entry into a duplicate/conflict; each must be rejected without changing the saved original. Distinguish the same key's Always and Alone conditions. Allow separate Left/Right modifier mappings but reject conflicting generic-versus-specific variants. Disable actions obey trigger validation too. Using dropdowns only, attempt Win+L and Win+Ctrl+L as source and target; both must be rejected without sending a workstation-lock gesture.

### Key and shortcut behavior

- [ ] **Remap keys to keys or disable them** [ID: KM-KEY-KEY] [ADMIN: NO]
  Test every row with the press/release, held-input and release-order conventions above. Observe the target event/action, suppression of the original and normal input afterward. Win conversions must not open Start accidentally; distinguish any deliberate target-Win behavior from an extra source-key side effect.

  | Source | Target | Observation fixture |
  |---|---|---|
  | A | B | Owned text editor: B replaces A |
  | Ctrl | A | Owned text editor: A, without residual Ctrl |
  | A | Ctrl | Owned text/key observer: target Ctrl participates normally |
  | Win | B | Owned text editor and Start-state observer |
  | B | Win | Owned key/Start-state observer |
  | A | Disable | Owned text/key observer: no A effect |
  | Win | Disable | Owned key/Start-state observer: no Start effect |

- [ ] **Remap keys to shortcuts** [ID: KM-KEY-SHORTCUT] [ADMIN: NO]
  Test A to Ctrl+V with protected synthetic clipboard text, and B to Win+A with a supported Quick Settings observer. Each target action replaces the source, including held-input/release conditions, and leaves no stuck modifiers. Close only the shell surface opened by the case.

- [ ] **Remap shortcuts to shortcuts** [ID: KM-SHORTCUT-SHORTCUT] [ADMIN: NO]
  Test Ctrl+A to Ctrl+V, Win+A to Ctrl+V, Ctrl+V to Win+A, and Win+A to Win+F. Observe paste or the intended Windows surface instead of the original action for every tap/hold and both modifier-release orders. Win+F needs an installed Feedback Hub and owned launch/closure plan; its absence must not obscure the other rows.

- [ ] **Remap shortcuts to single keys** [ID: KM-SHORTCUT-KEY] [ADMIN: NO]
  Test Ctrl+A to B, Ctrl+A to Win, and Win+A to B. Verify the target text/key behavior, original shortcut suppression and modifier release for each tap/hold and both release orders; use the owned key/Start observer for the Win target.

- [ ] **Restrict shortcuts to applications** [ID: KM-APP-SCOPE] [ADMIN: COND]
  Repeat the applicable shortcut remapping rows above in owned Edge (`msedge`), VS Code (`code`) and cmd hosted by Windows Terminal (`windowsterminal`) fixtures. Verify the target app receives the remap and an unrelated foreground fixture retains ordinary input. Keep non-admin Terminal and authorized admin Terminal with elevated PowerToys separate. Also map to Alt+Tab and Alt+F4 in owned windows: focus loss/closure must not leave modifiers stuck or route subsequent remaps to the wrong application.

- [ ] **Switch remaps while keeping a modifier held** [ID: KM-MODIFIER-CHAIN] [ADMIN: NO]
  Configure Ctrl+D to Ctrl+A and Ctrl+E to Ctrl+V. Hold Ctrl, press/release D then E in an owned text editor; all fixture text is selected then replaced by synthetic clipboard text. Repeat an equivalent Windows-key source pair (Win+D to Ctrl+A, Win+E to Ctrl+V) while holding Win. Release the modifier and verify ordinary typing and no unintended source shell action.

- [ ] **Enable, disable and remove mappings** [ID: KM-ENABLEMENT] [ADMIN: NO]
  Disable/re-enable the module through Settings and observe mapping behavior stop/resume without losing saved rows. For each new-editor category (key/shortcut remap, text, program and URL), toggle an owned row off/on, observe its action stop/resume, then delete it while disabled and confirm it stays absent after reopen. Deleting an enabled owned key mapping also restores ordinary input immediately. Other entries and their enabled states must remain unchanged.

### Text, program and URL actions

- [ ] **Replace input with text** [ID: KM-TEXT] [ADMIN: NO]
  Create key-to-text and shortcut-to-text mappings with synthetic content; verify exact text in an owned editor and after save/reopen. Exercise single-line, multiline and whitespace-only replacements, plus consecutive activations without dropping or duplicating replacements or crashing the engine. With an owned chat-style fixture, newlines must not submit the message. Activate single-key text replacement while Alt, Win, Ctrl and Shift are held, independently: text still arrives, no accidental menu/Start activation occurs and released modifiers do not remain stuck. Preserve clipboard even when the target's current text implementation does not need it.

- [ ] **Run programs with the selected context** [ID: KM-PROGRAM] [ADMIN: COND]
  Map a shortcut to an owned harmless executable; verify actual launch, requested arguments and working directory, not just Shell dispatch. Separately test a `.lnk`, app execution alias and associated owned file with their installed handlers. An empty Start in uses an executable's containing directory; an explicit valid directory is honored and an invalid one is rejected. Under separately authorized elevated PowerToys, Normal visible launches remain non-elevated and both program/folder browse dialogs open and support selection/cancel. Explicit Elevated and Different user require their own authorized accounts/prompts; Hidden retains its intended hidden launch behavior. Do not infer these conditional results from the ordinary executable route.

- [ ] **Open URLs** [ID: KM-URI] [ADMIN: NO]
  Map an owned shortcut to an approved non-sensitive URL, save/reopen and activate it. The intended URL opens in the configured handler; an invalid/empty URL cannot be committed as a valid mapping. Own only the resulting test tab/window and restore it without closing unrelated browser content.

### Conditions and list management

- [ ] **Use an Alone tap condition** [ID: KM-ALONE] [ADMIN: NO]
  With the new editor's single-key to key/shortcut action, select Alone (tap), save and reopen; the condition and Alone badge persist. A solo release fires the target once, including after a long hold (there is no hold-timeout contract). Combining the held source with another key, mouse button or wheel preserves the original modifier combination and does not fire the solo action. Mouse movement alone must not cancel the tap. The condition control is unavailable for unsupported text/program/URL actions. Preserve separate Left/Right mappings and distinguish an Always sibling on the same key.

- [ ] **Search and filter the mapping list** [ID: KM-FILTER] [ADMIN: NO]
  Use owned rows spanning key names, replacement text, URL, program path and target app. Case-insensitive substring search matches each field. Win/Ctrl/Alt/Shift filters use trigger modifiers, multiple modifier filters combine with OR, app choices distinguish All apps, Global only and a named app, and different filter categories combine with AND. A no-match view offers Clear filters and is distinct from an actually empty configuration. Clearing restores rows; filtering does not change saved mappings or persist as configuration.

- [ ] **Delete only selected visible rows** [ID: KM-BULK] [ADMIN: NO]
  Enter Select mode on a filtered owned list, select multiple rows across sections and verify the selected count. Cancel selection and separately cancel the delete confirmation: both retain all rows. Confirm deletion and verify only selected visible rows disappear from UI and both stores; hidden/unselected entries survive. Reopen to check persistence, then restore the owned fixture.

### Modifier compatibility and presentation

- [ ] **Release AltGr without a sticky Ctrl** [ID: KM-ALTGR] [ADMIN: NO]
  With an installed AltGr layout and owned text fixture, configure LCtrl+Y to Backspace, press/release AltGr without invoking a remap, then invoke the LCtrl remap and type normally. Ctrl must not remain stuck. Separately verify an AltGr-based shortcut and the layout's ordinary AltGr character (for example German AltGr+Q). Preserve the original input layout and composition state.

- [ ] **Remap a modifier without system-key side effects** [ID: KM-MODIFIER-OUTPUT] [ADMIN: NO]
  Map Left Alt to Backspace in an owned editor with known text. Tapping deletes one character, not an Alt+Backspace action/whole word; holding repeats the intended deletion and releasing leaves no Alt/menu state. Where a message-level observer is used, distinguish normal target-key input from unintended system-key delivery.

- [ ] **Localize and theme the editors** [ID: KM-APPEARANCE] [ADMIN: NO]
  In an already provisioned non-English Windows-language fixture, open both applicable editor experiences and verify translated controls, dialogs and tooltips rather than only the window title. Preserve the original Windows/PowerToys language. With the new editor open, switch an authorized light/dark theme through UI and confirm the title bar follows the selected theme without corrupting the current mapping; restore it. Language installation and sign-out are separate environmental work.

### Deployment and diagnostics

- [ ] **Deploy a declarative profile** [ID: KM-DSC] [ADMIN: NO]
  Only in a separately authorized isolated configuration fixture with DSC v3 available, use Microsoft.PowerToys/KeyboardManagerProfile get/test/export/schema/manifest and set a replacement profile containing key, Disable, text, chord, app-specific and exact-match entries. Friendly layout-invariant key names round-trip; test becomes true, the engine reloads without a PowerToys restart, and editor/engine stores agree. Replace-whole-profile semantics must not be exercised on private live remaps. This explicit deployment case is not permission to bypass editor UI assertions.

- [ ] **Inspect module diagnostics** [ID: KM-TELEMETRY] [ADMIN: NO]
  When diagnostic collection/viewing is already authorized, enable Diagnostic data and Enable viewing through General settings, restart via the normal user flow, exercise the selected module actions, then open Diagnostic data viewer. Keyboard Manager XML events must correspond to those actions. Preserve original diagnostic settings, restart-dependent UI and owned files. If consent, observer or restart preservation is unavailable, retain this condition unexecuted without enabling collection.
