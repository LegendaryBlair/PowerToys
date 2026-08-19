# Crop And Lock — PowerToys release checklist

> Source: consolidated from the PowerToys v0.96 baseline (`tests-checklist-template.md`
> L780-L786) and user-observable changes merged through PowerToys v0.100.
> Build-only changes are excluded. One module per file.

## Legend

Each item is annotated with two metadata tags:

**Admin requirement**:
- `[ADMIN: NO]` - runnable from a standard (non-elevated) shell
- `[ADMIN: YES]` - requires an elevated session, clean profile, installation/upgrade, or machine-level configuration
- `[ADMIN: COND]` - basic case is non-admin, but the stated variant requires elevation

**Clarity**:
- (no marker) - clear, with explicit setup and expected behavior
- `[CLARITY: VAGUE-NO-STEPS]` - original wording has no procedural steps
- `[CLARITY: VAGUE-NO-ASSERT]` - original wording has no expected result
- `[CLARITY: VAGUE-AMBIGUOUS]` - original wording has no measurable pass/fail criterion
- `[REWRITTEN]` - a vague baseline item was rewritten into a concrete check

## Fixtures & conventions

- **State backup**: record the initial module-enabled state and copy the Crop And Lock settings
  before testing. Restore all three activation shortcuts and the enabled state afterward.
- **Win32 fixture**: use an isolated, non-maximized Win32 window with a visible clock, counter, or
  other changing content. Record its PID, HWND, rectangle, and initial window styles.
- **Packaged fixture**: use a single-window packaged app with changing content. Use a fixture already
  known to support Reparent mode; test Calculator only as a documented compatibility observation.
- **Selection**: foreground the intended source immediately before activation and select a non-empty
  rectangle inside its client area. Close only cropped windows and fixtures created by the test.
- **Compatibility**: Reparent mode is not expected to work with every application. Maximized or
  full-screen windows, Calculator, and apps with tabs or child windows can be incompatible; Thumbnail
  is the fallback. Do not classify a documented incompatible app as a product failure.
- **Visual evidence**: record the original and cropped content before and after the source changes.
  Crop surfaces are primarily rendered output, so use screenshots or a short recording when UIA
  cannot expose the pixels.

---

## Crop And Lock (14 items)

### Settings, defaults, and shortcuts

- [ ] **[ADMIN: YES]** (#47027, #47144) On a clean installation or disposable user profile with no existing PowerToys `settings.json` and no Crop And Lock policy, start PowerToys and open Settings. Confirm Crop And Lock is **off from first render**, its process does not transiently start, and the Reparent, Thumbnail, and Screenshot shortcuts are inert until the module is enabled.
- [ ] **[ADMIN: NO]** (#40720) Enable Crop And Lock and confirm Settings exposes three distinct shortcuts: **Reparent** (`Win+Ctrl+Shift+R` by default), **Thumbnail** (`Win+Ctrl+Shift+T`), and **Screenshot** (`Win+Ctrl+Shift+S`). Change each to a different unused chord, close and reopen Settings, and confirm only the saved chord starts its matching mode. Restore all defaults afterward.
- [ ] **[ADMIN: NO]** With the module enabled, activate each mode and press Escape before completing a selection. Confirm the selection overlay closes, no cropped window is created, the source app remains unchanged, and the next activation works normally. Disable the module and confirm all three shortcuts stop opening the overlay; re-enable it and confirm they recover without restarting Windows.

### Thumbnail mode

- [ ] **[ADMIN: NO]** [REWRITTEN] (L781, #40720) Foreground the changing Win32 fixture, invoke Thumbnail mode, and select part of its live content. Confirm one topmost cropped window appears, updates as the source changes, preserves the selected aspect ratio when resized, does not forward interaction through the thumbnail, and can be closed without closing or modifying the source.
- [ ] **[ADMIN: NO]** [REWRITTEN] (L782) Repeat Thumbnail mode with the packaged fixture. Confirm the crop targets that exact app, remains live and topmost, preserves aspect ratio through wide and tall resizes, and leaves the packaged source usable after the cropped window closes.

### Reparent mode

- [ ] **[ADMIN: NO]** [REWRITTEN] (L785) Record the Win32 fixture's rectangle and window state, invoke Reparent mode, and select a region containing an interactive control. Confirm the cropped window replaces the visible original, exposes only the selected region, remains topmost, and sends interaction to the real app. Close the crop and confirm the original parent, styles, controls, rectangle, and interaction are restored.
- [ ] **[ADMIN: NO]** [REWRITTEN] (L786) Repeat Reparent mode with a known-compatible, non-maximized packaged fixture. Confirm the selected region remains interactive and closing the crop restores the source. Separately try Calculator if installed and confirm an incompatibility does not damage the app and Thumbnail mode still works as the documented fallback.

### Screenshot mode

- [ ] **[ADMIN: NO]** (#40720) Display a changing value **A** in the Win32 fixture, invoke Screenshot mode, and select it. Let the source advance to **B** and confirm the cropped window remains frozen on **A**, stays topmost, and does not reparent, close, or otherwise modify the source.
- [ ] **[ADMIN: NO]** (#40720) Resize the Win32 screenshot crop to wide and tall shapes. Confirm the captured bitmap remains correctly proportioned and centered, with unused space letterboxed rather than stretched, and closing it leaves the source app unchanged.
- [ ] **[ADMIN: NO]** (#40720) Repeat Screenshot mode with the packaged fixture. Confirm it captures the intended app once, remains frozen when the packaged source changes, preserves aspect ratio while resizing, and closes independently of the source. Use ordinary app content rather than protected video or hardware-overlay surfaces.

### Command Palette integration

- [ ] **[ADMIN: NO]** (#44006, #40720) Disable Crop And Lock, open Command Palette, and search for the module. Confirm **Crop And Lock settings** remains available and opens the correct Settings page, while the Reparent, Thumbnail, and Screenshot actions are absent. Enable the module, reopen Command Palette, and confirm all three mode actions appear.
- [ ] **[ADMIN: NO]** (#44006, #40720) With the controlled Win32 fixture foreground before opening Command Palette, invoke each Crop And Lock mode result in turn. Confirm Command Palette dismisses, the selector targets the original fixture rather than Command Palette, and the resulting crop has the corresponding Reparent, live Thumbnail, or frozen Screenshot behavior.
- [ ] **[ADMIN: NO]** (#45840) Pin the Reparent, Thumbnail, Screenshot, and Settings results to Command Palette Home. Restart Command Palette or PowerToys and confirm all four entries remain pinned, retain distinct identities, and still invoke the correct mode or Settings page.

### Upgrade persistence

- [ ] **[ADMIN: YES]** (#47027, #47144) Starting from a v0.96 installation where Crop And Lock was explicitly enabled, upgrade to v0.100 without deleting PowerToys settings. Confirm the module remains enabled and all configured shortcuts still work; the new clean-install default must not overwrite an explicit persisted state.
