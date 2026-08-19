# ZoomIt — PowerToys release checklist

> Source: consolidated from the PowerToys v0.96 baseline (`tests-checklist-template.md`
> L984-L1012) and user-observable changes merged through PowerToys v0.100.
> Build-only and refactor-only changes are excluded. One module per file.

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

- **State backup**: record the initial ZoomIt enabled state and copy its settings before testing.
  Restore every shortcut, recording option, device selection, Break setting, input file, tray-icon
  setting, and module state afterward.
- **Interactive desktop**: ZoomIt modes capture or replace the interactive desktop and can block
  input. Run them only in an attached local/RDP session, dismiss each mode before continuing, and
  never send unguarded synthetic keys.
- **Visual fixture**: use a disposable window containing a clock/counter, high-contrast text,
  colored shapes, and moving content. Use a long static document for Panorama and a unique text
  file for Demo Type.
- **Recording fixture**: use short clips with visible start/middle/end markers. Record to a
  disposable writable folder and remove every generated MP4, GIF, PNG, and temporary clip.
- **Audio fixture**: use headphones, a short system tone, and a spoken microphone marker. Audio
  matrix and mono tests require microphone permission; asymmetric-channel testing requires a
  stereo or virtual microphone source.
- **Camera fixture**: webcam checks require camera permission. A second camera is useful for device
  persistence but is not required for the overlay-composition checks.
- **Break fixture**: back up the user's screensaver path, timeout, active, and secure values before
  testing authentication. Use a disposable account where locking the session is safe.
- **Rendered-output evidence**: most active ZoomIt surfaces use input blocking and capture
  exclusion. Prefer saved output, clipboard content, settings diffs, media metadata, and a manual
  observer rather than assuming UIA or screenshots can inspect the overlay.

---

## ZoomIt (39 items)

### Module state, tray icon, and shortcut registration

- [ ] **[ADMIN: NO]** (L984-L987) Enable ZoomIt with **Show tray icon** on and confirm exactly one ZoomIt icon appears. Turn the setting off and confirm the icon disappears without stopping the module, then turn it on and confirm one icon returns without duplication.
- [ ] **[ADMIN: NO]** (L985, L1009-L1012) Left-click and right-click the tray icon and confirm each menu contains exactly **Break Timer**, **Draw**, **Zoom**, and **Record**. Invoke every entry and confirm it enters only the matching mode, can be dismissed or stopped normally, and leaves the tray menu and module responsive for the next action.
- [ ] **[ADMIN: NO]** Disable ZoomIt and confirm the tray icon disappears, the configured Zoom, Draw, Break, Live Zoom, Record, Snip, OCR, Demo Type, and Panorama shortcuts do not start a mode, and no ZoomIt mode process remains active. Re-enable it and confirm the tray icon and shortcuts recover without restarting Windows.
- [ ] **[ADMIN: NO]** (#43073) With default settings, confirm Settings displays the complete shortcut family: `Ctrl+1` Zoom, `Ctrl+2` Draw, `Ctrl+3` Break, `Ctrl+4` Live Zoom, `Ctrl+5` Record, `Ctrl+6` Snip, `Ctrl+Alt+6` OCR, `Ctrl+7` Demo Type, `Ctrl+8` Panorama, plus derived Live Draw, region/window Record, save Snip, reset Demo Type, and save Panorama shortcuts.
- [ ] **[ADMIN: NO]** (#43073, #47388) Set Record to `Alt+5` and confirm Settings shows full-screen `Alt+5`, region `Alt+Shift+5`, and no bare-`5` window shortcut; pressing `5` in Notepad must type normally. Set Record to `Shift+5` and confirm Settings shows full-screen `Shift+5`, window `Alt+Shift+5`, and no bare-`5` region shortcut. Exercise the displayed shortcuts, then restore `Ctrl+5`.
- [ ] **[ADMIN: NO]** Change representative base shortcuts for Zoom, Live Zoom, Break, Snip, Demo Type, and Panorama to unused chords. Close and reopen Settings and restart ZoomIt; confirm each new chord persists, starts only its matching mode, the previous chord is inert, and every derived shortcut label updates consistently. Restore the defaults afterward.
- [ ] **[ADMIN: NO]** (#48401) Disable the PowerToys-hosted ZoomIt module, launch the v0.100 ZoomIt executable in standalone mode, open its Options dialog, assign Record an unused shortcut, and save. Confirm the new shortcut works immediately, the old shortcut stops working, and the change persists after restarting standalone ZoomIt.
- [ ] **[ADMIN: NO]** (#47215) Configure ZoomIt with an unusual unused shortcut, disable the module, reserve that shortcut in a controlled helper, and re-enable ZoomIt through PowerToys. Confirm hosted ZoomIt does not show a blocking native conflict MessageBox and instead directs the user to Settings or otherwise remains usable. Release the helper shortcut and restore ZoomIt settings.

### Zoom, Draw, Type, and Demo Type

- [ ] **[ADMIN: NO]** (L989) Foreground the visual fixture, press the Zoom shortcut, and confirm static magnification opens around the pointer at the configured level. Pan to another area, then exit once with Escape and once with the same shortcut; confirm the normal desktop returns without stale magnification or blocked input.
- [ ] **[ADMIN: NO]** (L990) Press the Live Zoom shortcut and confirm the magnified desktop continues updating while the clock/counter and moving content change. Toggle it off with the same shortcut and confirm all desktop interaction and rendering return to normal.
- [ ] **[ADMIN: NO]** (L991) Press Draw without first entering Zoom, draw multiple colors/shapes, and confirm annotation appears at 1x over the current desktop. Exit with Escape and confirm the marks disappear and input is restored.
- [ ] **[ADMIN: NO]** (#43073) Use the derived Live Draw shortcut shown in Settings and confirm it combines live magnification with drawing rather than starting static Zoom or plain Draw. Change the Live Zoom base shortcut to include Shift and confirm the derived Live Draw label removes Shift instead of duplicating it, then exercise the updated chord.
- [ ] **[ADMIN: NO]** (L999, #43679) Select a different Type font, enter Draw → Type, and type `A&B -_!?`. Confirm every character renders in the selected font with no assertion, crash, or missing ampersand. Enter static Zoom without Draw/Type, press `&`, and confirm it does not create an annotation. Exit and confirm ZoomIt remains reusable.
- [ ] **[ADMIN: NO]** (L997-L998) Toggle **Animate zoom in and zoom out** and test both transitions, then set two distinctive initial magnification levels and activate static Zoom after each change. Confirm animation and initial level follow the saved setting after closing/reopening Settings and restarting ZoomIt.
- [ ] **[ADMIN: NO]** (L992, L1000, #43073) Select a unique text file for Demo Type, focus Notepad, and invoke Demo Type. Confirm the file content is typed in order, Escape cancels before completion, and changing the typing-speed setting produces an observable speed difference. Invoke the displayed reset shortcut and confirm the next run restarts from the beginning.

### Break Timer

- [ ] **[ADMIN: NO]** (L993) Set a one-minute Break duration, invoke Break with its shortcut, and confirm the countdown appears with the correct starting value, decreases once per second, and exits cleanly with Escape without leaving input blocked.
- [ ] **[ADMIN: NO]** (L1001-L1002) Set two clearly different timer opacities and representative corner/center positions. Invoke Break after each change and confirm the timer uses the selected opacity and location and remains fully visible inside the active monitor.
- [ ] **[ADMIN: NO]** (L1003) Test Break with no background, faded desktop, and a custom image. Toggle image stretching and confirm each mode applies the selected background and the stretch setting changes image fitting without distorting the timer text.
- [ ] **[ADMIN: NO]** (L1004) Enable **Play sound on expiration**, select a known WAV file, run a one-minute Break to completion, and confirm the sound plays exactly once. Disable the setting, repeat, and confirm no expiration sound plays.
- [ ] **[ADMIN: NO]** (#46506) Back up the user's screensaver configuration, enable Break authentication/lock, and invoke Break. Confirm ordinary input cannot dismiss to the desktop without Windows account authentication; authenticate, confirm the session returns normally, and verify the original screensaver path, timeout, active, and secure settings are restored. Repeat once to detect stale restoration state.

### Snip, OCR, Panorama, and screenshot output

- [ ] **[ADMIN: NO]** (L995, #43073, #43172) Invoke Snip, select a distinctive region, and paste into Paint; confirm the clipboard image matches the selection. Invoke the displayed save-Snip shortcut and confirm Save As suggests `ZoomIt YYYY-MM-DD HHMMSS.png` using the current local time and saves a valid PNG to the chosen path.
- [ ] **[ADMIN: NO]** (#43172) From static Zoom or Draw, save a screenshot twice at least one second apart. Confirm each Save As dialog suggests the timestamped `ZoomIt YYYY-MM-DD HHMMSS.png` pattern, the names differ, and both saved PNG files open with the expected annotated or magnified content.
- [ ] **[ADMIN: NO]** (#46506) Display known high-contrast text in an installed Windows OCR language, invoke OCR, select only that text, and paste the clipboard into Notepad. Confirm the recognized text substantially matches the source, allowing minor whitespace differences, and the next OCR invocation works without stale selection UI.
- [ ] **[ADMIN: NO]** (#46506) Open a long, textured, non-animated document, invoke Panorama, select its viewport, scroll slowly through several screens, and stop with the Panorama shortcut. Paste the clipboard result and confirm one continuous image is taller than the viewport with no missing, duplicated, or badly misaligned bands. Repeat with the displayed save-Panorama shortcut and confirm a valid image is written.
- [ ] **[ADMIN: NO]** (#47132, #47197) Open ZoomIt Settings and confirm **Snip**, **Text recognition and extraction**, and **Scrolling screenshot** are grouped together; Snip and OCR have no empty expansion area, while Panorama expands to show its save shortcut. Change Panorama's base shortcut and confirm the displayed save shortcut toggles Shift immediately and persists after reopening Settings.

### Screen recording, audio, camera, and post-processing

- [ ] **[ADMIN: NO]** (L994) Foreground moving content, start full-screen Record with its configured shortcut, capture a short clip, and press the shortcut again. Confirm recording stops once, Save As completes, the MP4 opens with the expected desktop motion, and another recording can start without restarting ZoomIt.
- [ ] **[ADMIN: NO]** (#43073) Exercise the displayed full-screen, region, and window Record shortcuts. Confirm full-screen captures the active display, region captures only the selected rectangle, window captures the intended foreground window, and each mode produces one playable output without switching to a different recording scope.
- [ ] **[ADMIN: NO]** (#43589) On a clean/reset ZoomIt profile, confirm MP4 is the default format. Record moving content as MP4 and GIF with 100% and 50% scaling, save each to a custom name/folder, and confirm the correct `.mp4`/`.gif` extension, playable animation, approximately 30 fps MP4 and 15 fps GIF when inspected, and roughly half-sized dimensions at 50% without severe corruption or encoder failure.
- [ ] **[ADMIN: NO]** (L1005, #47529) Open the microphone and camera selectors and confirm every currently available permitted device appears once. Select non-default devices where available, close/reopen Settings and restart ZoomIt, and confirm the selections persist without retaining a disconnected duplicate.
- [ ] **[ADMIN: NO]** (#45700) Record four short MP4 clips with audio set to: neither source, system only, microphone only, and both. Confirm the first output has no audio stream, system-only contains the played tone but not speech, microphone-only contains speech but not the tone, and both contains both sources.
- [ ] **[ADMIN: NO]** (#45386, #45387) During microphone recording, confirm Windows reports microphone use. Stop recording and confirm ZoomIt releases the microphone before the save/trim flow completes. With an asymmetric stereo microphone source, compare Mono off/on and confirm Mono on folds the microphone signal equally into both output channels without preventing playback.
- [ ] **[ADMIN: NO]** (#45334, #46034) Record an MP4 with visible start, middle, and end markers, stop, and open Trim. Confirm preview, play/pause/seek, and start/end controls work; trim away both outer markers, save, and confirm duration/content match the selected interval. Immediately record and save a second clip and confirm no stale trim/session state blocks it.
- [ ] **[ADMIN: NO]** (#47529) Select a camera, start MP4 recording, and confirm one live topmost webcam preview appears. Close/reopen Settings and restart ZoomIt, then confirm the selected camera remains selected and a new recording can initialize the same device without a stale handle or duplicate preview.
- [ ] **[ADMIN: NO]** (#47529) Across short recordings, exercise all webcam positions, sizes, and shapes; drag and resize the preview while recording and toggle it with Ctrl+C. Confirm the saved MP4 contains one composited overlay at the final visible position/size, hidden intervals are absent, the preview itself is not captured as a duplicate, and Full Screen shape forces a rectangle.
- [ ] **[ADMIN: NO]** (#47529) Create distinct compatible MP4 clips A and B and append B to A using **None**, **Fade to black**, and **Fade to white**. Confirm every output plays A then B, includes both durations, shows only the selected transition without corrupt frames, and Save or Cancel leaves ZoomIt ready for another recording.
- [ ] **[ADMIN: NO]** (#47695) Enable **Lock region selection to 16:9 aspect ratio**, start region recording, and drag both landscape and portrait selections. Confirm saved dimensions approximate 16:9 and 9:16 respectively. Disable the setting and confirm an arbitrary non-16:9 region can be selected and recorded.

### Command Palette integration

- [ ] **[ADMIN: NO]** (#44006) With ZoomIt enabled, search Command Palette and confirm distinct actions for **Zoom**, **Draw**, **Break**, **Live Zoom**, **Snip**, and **Record**, plus **ZoomIt settings**. Disable ZoomIt and confirm the six mode actions disappear while Settings remains and opens the correct page; re-enable it and confirm the actions return.
- [ ] **[ADMIN: NO]** (#44006) Invoke each of the six ZoomIt mode actions from Command Palette and confirm the palette dismisses before ZoomIt captures or magnifies the desktop and each action starts only its named mode. With ZoomIt enabled but its process unavailable, invoke an action and confirm Command Palette shows a **ZoomIt is not running** error rather than crashing or silently leaving a stale overlay.
- [ ] **[ADMIN: NO]** (#45840) Pin all six ZoomIt actions and the Settings result to Command Palette Home, restart Command Palette or PowerToys, and confirm all seven entries remain pinned with distinct identities and still invoke the correct mode or Settings page.
