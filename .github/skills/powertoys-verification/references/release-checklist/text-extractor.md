# Text Extractor - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - standard-user coverage with the stated fixtures.
- `[ADMIN: COND]` - retain ordinary and authorized policy variants separately.
- `[ID: ...]` - stable case identifier in the matching assertion inventory.

## Fixtures & conventions

- Use a disposable, clearly rendered text/blank scene. Preserve the complete supported clipboard privately before capture; restore and verify it before stopping any clipboard provider.
- Preserve original module enablement, shortcut, preferred language, Settings page/placement, pointer and foreground. Restore originals, not defaults; leave unrelated user windows and settings untouched.
- Measure physical display bounds and DPI. Mixed-DPI, negative-origin, additional OCR-language and non-English UI conditions require those actual environments; do not install languages or rearrange displays to manufacture coverage.
- Use the shared [session-safety](../session-safety.md), [clipboard](../clipboard-guard.md), [shortcut](../shortcut-recorder.md) and [capture](../helper-workflow.md) contracts. Keep per-condition observations even when cases share setup.
- WinUI-specific cases require a build containing the Text Extractor WinUI migration. Do not use legacy WPF control names or a named event as proof of a physical shortcut.

## Text Extractor (17 items)

### Activation and dismissal

- [ ] **Activate, cancel and reactivate** [ID: TE-ACTIVATION] [ADMIN: NO]
  Enable Text Extractor through Settings. From a normal-user owned foreground scene, press its current shortcut and observe the overlay. Press Escape and observe dismissal, activate again, then right-click the selection surface and choose Cancel. All overlays must disappear after each cancellation without changing the clipboard.

- [ ] **Disable and restore activation** [ID: TE-DISABLE] [ADMIN: NO]
  First establish successful shortcut activation. Disable the module through Settings, verify the switch and persisted enabled state are off, and verify that the same shortcut no longer opens an overlay. Re-enable it and verify activation works again; restore the original enablement.

- [ ] **Named-event activation** [ID: TE-EVENT] [ADMIN: NO]
  With the module enabled and no overlay open, signal its existing show event. Observe the overlay and dismiss it. This checks the integration route, not the keyboard binding.

### Text capture and formatting

- [ ] **Region, word and empty capture** [ID: TE-CAPTURE] [ADMIN: NO]
  Render `PowerToys Text Extractor` at a readable size on a plain background and select the text region. The clipboard must contain the fixture's words in order and the overlay must close. Reopen over the same fixture and click the word `PowerToys`; only that word must be copied. Over an owned blank region, capture must leave the clipboard unchanged and display a recoverable no-text message with the overlay still open.

- [ ] **Formatting modes** [ID: TE-FORMAT] [ADMIN: NO]
  Capture two distinct rendered lines in single-line mode and verify their words are joined without a line break. Capture a clearly spaced two-row, two-column table in table mode and verify row order and tab-separated columns. Independently press S and T twice and verify each corresponding toolbar toggle changes and returns to its initial state.

- [ ] **Selection interaction and release** [ID: TE-SELECTION] [ADMIN: NO]
  Drag an owned selection, hold Shift while moving it, and verify that it translates without resizing before capture. During a separate drag, cancel with Escape and verify all overlays close, no text is copied, and cursor clipping returns to its original bounds. Move the pointer across the selection interior and verify the crosshair stays visible; exclude toolbar and display edges from this check.

- [ ] **Recovery after empty capture** [ID: TE-ERROR] [ADMIN: NO]
  On WinUI builds, capture an owned blank region. The error message must appear below, not over, the language/mode/Settings/Cancel controls. Without refocusing the toolbar, exercise S, T and each available numbered language shortcut (up to nine), observing their state changes, then cancel.

### OCR language and displays

- [ ] **Overlay language selection** [ID: TE-LANGUAGE] [ADMIN: NO]
  With at least two installed OCR languages, right-click and select a different language; verify the checked menu item and toolbar selection agree and capture a known readable sample in that language. Independently choose a language from the toolbar and verify the menu agrees. For every installed language among the first nine, press its displayed number shortcut and verify the corresponding selection.

- [ ] **Capture across displays** [ID: TE-DISPLAYS] [ADMIN: NO]
  In a multi-monitor environment, capture an owned text sample separately on every display and verify its words. Repeat across displays with different DPI, retaining each display's physical bounds and scale; if a display has a negative virtual-desktop origin, verify capture there too. While overlays coexist, change language and formatting on one display and verify the state is synchronized on the others.

### Settings and entry points

- [ ] **Change the activation shortcut** [ID: TE-SHORTCUT] [ADMIN: NO]
  Choose a collision-checked temporary binding through the Settings shortcut recorder and Save. Verify the persisted key and all modifiers, activation by the new binding, and nonactivation by the old binding. Restore the exact original shortcut through the recorder and verify it activates again.

- [ ] **Set the preferred OCR language** [ID: TE-PREFERRED] [ADMIN: NO]
  With a second OCR language available, change the preferred language through Settings and verify its persisted native name. Open a new overlay and verify it starts in that language and captures a known sample correctly. Restore the original preference and verify a fresh overlay uses the original preference or its documented input-language fallback.

- [ ] **Open Settings from the overlay** [ID: TE-SETTINGS-ENTRY] [ADMIN: NO]
  On WinUI builds, activate and use the toolbar Settings button; verify the Text Extractor Settings page opens and overlays close. Repeat using the right-click Settings item. Preserve the original Settings window's page, expansion, scroll and placement.

- [ ] **Command Palette integration** [ID: TE-CMDPAL] [ADMIN: NO]
  With the installed PowerToys extension available, run its Text Extractor activation command and observe the overlay. Use its Text Extractor settings command and verify the correct Settings page. Disable Text Extractor through Settings and verify the activation command is unavailable while the settings command remains available; restore original state.

- [ ] **Localized attribution link** [ID: TE-ATTRIBUTION] [ADMIN: NO]
  On builds with localizable Settings attribution links, inspect Text Extractor's attribution label in an available non-English UI and activate it in an owned browser tab. Verify it reaches the Text-Grab project; close only the owned tab and restore the original language/Settings state.

### Appearance and conditional release checks

- [ ] **Theme and translated overlay** [ID: TE-APPEARANCE] [ADMIN: NO]
  In light and dark Windows app themes, independently inspect the overlay toolbar, menu and error message for readable labels/icons and unclipped, nonoverlapping controls. In an installed non-English UI, verify the overlay labels/tooltips/error text are translated rather than resource keys. Theme/language transitions require a reversible UI route and original-state restoration.

- [ ] **Diagnostic events** [ID: TE-TELEMETRY] [ADMIN: NO]
  In an authorized diagnostic-data environment, enable Diagnostic data and Enable viewing before a controlled PowerToys restart. Activate, cancel, then capture owned text. Open Diagnostic data viewer and verify Text Extractor invocation, cancellation and capture events correspond to these actions. Restore the original diagnostic settings; do not expose unrelated event payloads.

- [ ] **Managed enablement** [ID: TE-POLICY] [ADMIN: COND]
  In an authorized disposable policy fixture, verify forced-disabled Text Extractor cannot be enabled or activated, and forced-enabled Text Extractor cannot be disabled and still activates. Retain these as separate conditions; preserve exact original policy presence, type and value. Do not modify organization-managed policy on a shared machine.
