# ZoomIt - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - standard-user coverage, subject to the stated fixtures.
- `[ADMIN: YES]` - requires an authorized elevated session.
- `[ADMIN: COND]` - retain ordinary and elevated variants independently.
- `[ID: ...]` - stable scenario identifier; retain every required child/input observation.

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
- See the [module profile](../modules/zoomit.md) for control interaction and restoration mechanics, and use the [frozen inventory](../assertion-inventories/zoomit.json) without run-local regrouping.

## ZoomIt (39 items)

### Module state, tray icon and shortcuts

- [ ] **Tray icon visibility** [ID: ZI-TRAY-VISIBILITY] [ADMIN: NO]
  Enable ZoomIt with **Show tray icon** on and confirm exactly one ZoomIt icon appears. Turn the setting off and confirm the icon disappears without stopping the module, then turn it on and confirm one icon returns without duplication.

- [ ] **Tray menu actions** [ID: ZI-TRAY-ACTIONS] [ADMIN: NO]
  Left-click and right-click the tray icon and confirm each menu contains exactly **Break Timer**, **Draw**, **Zoom**, and **Record**. Invoke every entry and confirm it enters only the matching mode, can be dismissed or stopped normally, and leaves the tray menu and module responsive for the next action.

- [ ] **Module disable and re-enable** [ID: ZI-MODULE-STATE] [ADMIN: NO]
  Disable ZoomIt and confirm the tray icon disappears, the configured Zoom, Draw, Break, Live Zoom, Record, Snip, OCR, Demo Type, and Panorama shortcuts do not start a mode, and no ZoomIt mode process remains active. Re-enable it and confirm the tray icon and shortcuts recover without restarting Windows.

- [ ] **Default shortcut family** [ID: ZI-DEFAULT-SHORTCUTS] [ADMIN: NO]
  With default settings, confirm Settings displays the complete shortcut family: `Ctrl+1` Zoom, `Ctrl+2` Draw, `Ctrl+3` Break, `Ctrl+4` Live Zoom, `Ctrl+5` Record, `Ctrl+6` Snip, `Ctrl+Alt+6` OCR, `Ctrl+7` Demo Type, `Ctrl+8` Panorama, plus derived Live Draw, region/window Record, save Snip, reset Demo Type, and save Panorama shortcuts.

- [ ] **Record modifier edge cases** [ID: ZI-RECORD-MODIFIERS] [ADMIN: NO]
  Set Record to `Alt+5` and confirm Settings shows full-screen `Alt+5`, region `Alt+Shift+5`, and no bare-`5` window shortcut; pressing `5` in Notepad must type normally. Set Record to `Shift+5` and confirm Settings shows full-screen `Shift+5`, window `Alt+Shift+5`, and no bare-`5` region shortcut. Exercise the displayed shortcuts, then restore the original Record shortcut.

- [ ] **Rebind base and derived shortcuts** [ID: ZI-REBIND] [ADMIN: NO]
  Change representative base shortcuts for Zoom, Live Zoom, Break, Snip, Demo Type, and Panorama to unused chords. Close and reopen Settings and restart ZoomIt; confirm each new chord persists, starts only its matching mode, the previous chord is inert, and every derived shortcut label updates consistently. Restore the original shortcut values afterward.

- [ ] **Standalone Record shortcut** [ID: ZI-STANDALONE] [ADMIN: NO]
  Disable the PowerToys-hosted ZoomIt module, launch the v0.100 ZoomIt executable in standalone mode, open its Options dialog, assign Record an unused shortcut, and save. Confirm the new shortcut works immediately, the old shortcut stops working, and the change persists after restarting standalone ZoomIt.

- [ ] **Hosted shortcut conflict recovery** [ID: ZI-SHORTCUT-CONFLICT] [ADMIN: NO]
  Configure ZoomIt with an unusual unused shortcut, disable the module, reserve that shortcut in a controlled helper, and re-enable ZoomIt through PowerToys. Confirm hosted ZoomIt does not show a blocking native conflict MessageBox and instead directs the user to Settings or otherwise remains usable. Release the helper shortcut and restore ZoomIt settings.

### Zoom, Draw, Type and Demo Type

- [ ] **Static Zoom lifecycle** [ID: ZI-ZOOM] [ADMIN: NO]
  Foreground the visual fixture, press the Zoom shortcut, and confirm static magnification opens around the pointer at the configured level. Pan to another area, then exit once with Escape and once with the same shortcut; confirm the normal desktop returns without stale magnification or blocked input.

- [ ] **Live Zoom lifecycle** [ID: ZI-LIVE-ZOOM] [ADMIN: NO]
  Press the Live Zoom shortcut and confirm the magnified desktop continues updating while the clock/counter and moving content change. Toggle it off with the same shortcut and confirm all desktop interaction and rendering return to normal.

- [ ] **Drawing without magnification** [ID: ZI-DRAW] [ADMIN: NO]
  Press Draw without first entering Zoom, draw multiple colors/shapes, and confirm annotation appears at 1x over the current desktop. Exit with Escape and confirm the marks disappear and input is restored.

- [ ] **Live Draw and derived binding** [ID: ZI-LIVE-DRAW] [ADMIN: NO]
  Use the derived Live Draw shortcut shown in Settings and confirm it combines live magnification with drawing rather than starting static Zoom or plain Draw. Change the Live Zoom base shortcut to include Shift and confirm the derived Live Draw label removes Shift instead of duplicating it, then exercise the updated chord.

- [ ] **Type font and special characters** [ID: ZI-TYPE] [ADMIN: NO]
  Select a different Type font, enter Draw → Type, and type `A&B -_!?`. Confirm every character renders in the selected font with no assertion, crash, or missing ampersand. Enter static Zoom without Draw/Type, press `&`, and confirm it does not create an annotation. Exit and confirm ZoomIt remains reusable.

- [ ] **Animation and initial magnification** [ID: ZI-ZOOM-OPTIONS] [ADMIN: NO]
  Toggle **Animate zoom in and zoom out** and test both transitions, then set two distinctive initial magnification levels and activate static Zoom after each change. Confirm animation and initial level follow the saved setting after closing/reopening Settings and restarting ZoomIt.

- [ ] **Demo Type file, speed and reset** [ID: ZI-DEMO-TYPE] [ADMIN: NO]
  Select a unique text file for Demo Type, focus Notepad, and invoke Demo Type. Confirm the file content is typed in order, Escape cancels before completion, and changing the typing-speed setting produces an observable speed difference. Invoke the displayed reset shortcut and confirm the next run restarts from the beginning.

### Break Timer

- [ ] **Countdown and dismissal** [ID: ZI-BREAK-DURATION] [ADMIN: NO]
  Set a one-minute Break duration, invoke Break with its shortcut, and confirm the countdown appears with the correct starting value, decreases once per second, and exits cleanly with Escape without leaving input blocked.

- [ ] **Opacity and monitor position** [ID: ZI-BREAK-POSITION] [ADMIN: NO]
  Set two clearly different timer opacities and representative corner/center positions. Invoke Break after each change and confirm the timer uses the selected opacity and location and remains fully visible inside the active monitor.

- [ ] **Background and image fitting** [ID: ZI-BREAK-BACKGROUND] [ADMIN: NO]
  Test Break with no background, faded desktop, and a custom image. Toggle image stretching and confirm each mode applies the selected background and the stretch setting changes image fitting without distorting the timer text.

- [ ] **Expiration sound** [ID: ZI-BREAK-SOUND] [ADMIN: NO]
  Enable **Play sound on expiration**, select a known WAV file, run a one-minute Break to completion, and confirm the sound plays exactly once. Disable the setting, repeat, and confirm no expiration sound plays.

- [ ] **Authentication and screensaver restoration** [ID: ZI-BREAK-AUTH] [ADMIN: NO]
  Back up the user's screensaver configuration, enable Break authentication/lock, and invoke Break. Confirm ordinary input cannot dismiss to the desktop without Windows account authentication; authenticate, confirm the session returns normally, and verify the original screensaver path, timeout, active, and secure settings are restored. Repeat once to detect stale restoration state.

### Snip, OCR and Panorama

- [ ] **Snip clipboard and saved output** [ID: ZI-SNIP] [ADMIN: NO]
  Invoke Snip, select a distinctive region, and paste into Paint; confirm the clipboard image matches the selection. Invoke the displayed save-Snip shortcut and confirm Save As suggests `ZoomIt YYYY-MM-DD HHMMSS.png` using the current local time and saves a valid PNG to the chosen path.

- [ ] **Timestamped screenshot names** [ID: ZI-SCREENSHOT-NAME] [ADMIN: NO]
  From static Zoom or Draw, save a screenshot twice at least one second apart. Confirm each Save As dialog suggests the timestamped `ZoomIt YYYY-MM-DD HHMMSS.png` pattern, the names differ, and both saved PNG files open with the expected annotated or magnified content.

- [ ] **OCR text and repeat invocation** [ID: ZI-OCR] [ADMIN: NO]
  Display known high-contrast text in an installed Windows OCR language, invoke OCR, select only that text, and paste the clipboard into Notepad. Confirm the recognized text substantially matches the source, allowing minor whitespace differences, and the next OCR invocation works without stale selection UI.

- [ ] **Continuous scrolling capture** [ID: ZI-PANORAMA] [ADMIN: NO]
  Open a long, textured, non-animated document, invoke Panorama, select its viewport, scroll slowly through several screens, and stop with the Panorama shortcut. Paste the clipboard result and confirm one continuous image is taller than the viewport with no missing, duplicated, or badly misaligned bands. Repeat with the displayed save-Panorama shortcut and confirm a valid image is written.

- [ ] **Capture settings grouping and derived shortcuts** [ID: ZI-CAPTURE-SETTINGS] [ADMIN: NO]
  Open ZoomIt Settings and confirm **Snip**, **Text recognition and extraction**, and **Scrolling screenshot** are grouped together; Snip and OCR have no empty expansion area, while Panorama expands to show its save shortcut. Change Panorama's base shortcut and confirm the displayed save shortcut toggles Shift immediately and persists after reopening Settings.

### Recording scope and output

- [ ] **Basic recording lifecycle** [ID: ZI-RECORD] [ADMIN: NO]
  Foreground moving content, start full-screen Record with its configured shortcut, capture a short clip, and press the shortcut again. Confirm recording stops once, Save As completes, the MP4 opens with the expected desktop motion, and another recording can start without restarting ZoomIt.

- [ ] **Full-screen, region and window recording** [ID: ZI-RECORD-SCOPE] [ADMIN: NO]
  Exercise the displayed full-screen, region, and window Record shortcuts. Confirm full-screen captures the active display, region captures only the selected rectangle, window captures the intended foreground window, and each mode produces one playable output without switching to a different recording scope.

- [ ] **Formats, scaling and frame rates** [ID: ZI-RECORD-FORMAT] [ADMIN: NO]
  On a clean/reset ZoomIt profile, confirm MP4 is the default format. Record moving content as MP4 and GIF with 100% and 50% scaling, save each to a custom name/folder, and confirm the correct `.mp4`/`.gif` extension, playable animation, approximately 30 fps MP4 and 15 fps GIF when inspected, and roughly half-sized dimensions at 50% without severe corruption or encoder failure.

- [ ] **Region aspect-ratio lock** [ID: ZI-REGION-ASPECT] [ADMIN: NO]
  Enable **Lock region selection to 16:9 aspect ratio**, start region recording, and drag both landscape and portrait selections. Confirm saved dimensions approximate 16:9 and 9:16 respectively. Disable the setting and confirm an arbitrary non-16:9 region can be selected and recorded.

### Audio and camera

- [ ] **Device discovery and persistence** [ID: ZI-DEVICES] [ADMIN: NO]
  Open the microphone and camera selectors and confirm every currently available permitted device appears once. Select non-default devices where available, close/reopen Settings and restart ZoomIt, and confirm the selections persist without retaining a disconnected duplicate.

- [ ] **System and microphone source matrix** [ID: ZI-AUDIO-SOURCES] [ADMIN: NO]
  Record four short MP4 clips with audio set to: neither source, system only, microphone only, and both. Confirm the first output has no audio stream, system-only contains the played tone but not speech, microphone-only contains speech but not the tone, and both contains both sources.

- [ ] **Microphone lifetime and mono mixdown** [ID: ZI-MICROPHONE] [ADMIN: NO]
  During microphone recording, confirm Windows reports microphone use. Stop recording and confirm ZoomIt releases the microphone before the save/trim flow completes. With an asymmetric stereo microphone source, compare Mono off/on and confirm Mono on folds the microphone signal equally into both output channels without preventing playback.

- [ ] **Camera selection and repeated initialization** [ID: ZI-CAMERA-LIFETIME] [ADMIN: NO]
  Select a camera, start MP4 recording, and confirm one live topmost webcam preview appears. Close/reopen Settings and restart ZoomIt, then confirm the selected camera remains selected and a new recording can initialize the same device without a stale handle or duplicate preview.

- [ ] **Camera overlay composition** [ID: ZI-CAMERA-OVERLAY] [ADMIN: NO]
  Across short recordings, exercise all webcam positions, sizes, and shapes; drag and resize the preview while recording and toggle it with Ctrl+C. Confirm the saved MP4 contains one composited overlay at the final visible position/size, hidden intervals are absent, the preview itself is not captured as a duplicate, and Full Screen shape forces a rectangle.

### Recording post-processing

- [ ] **Trim and subsequent recording** [ID: ZI-TRIM] [ADMIN: NO]
  Record an MP4 with visible start, middle, and end markers, stop, and open Trim. Confirm preview, play/pause/seek, and start/end controls work; trim away both outer markers, save, and confirm duration/content match the selected interval. Immediately record and save a second clip and confirm no stale trim/session state blocks it.

- [ ] **Append transitions and recovery** [ID: ZI-APPEND] [ADMIN: NO]
  Create distinct compatible MP4 clips A and B and append B to A using **None**, **Fade to black**, and **Fade to white**. Confirm every output plays A then B, includes both durations, shows only the selected transition without corrupt frames, and Save or Cancel leaves ZoomIt ready for another recording.

### Command Palette integration

- [ ] **Enabled and disabled command availability** [ID: ZI-CMDPAL-STATE] [ADMIN: NO]
  With ZoomIt enabled, search Command Palette and confirm distinct actions for **Zoom**, **Draw**, **Break**, **Live Zoom**, **Snip**, and **Record**, plus **ZoomIt settings**. Disable ZoomIt and confirm the six mode actions disappear while Settings remains and opens the correct page; re-enable it and confirm the actions return.

- [ ] **Mode invocation and missing-process error** [ID: ZI-CMDPAL-INVOKE] [ADMIN: NO]
  Invoke each of the six ZoomIt mode actions from Command Palette and confirm the palette dismisses before ZoomIt captures or magnifies the desktop and each action starts only its named mode. With ZoomIt enabled but its process unavailable, invoke an action and confirm Command Palette shows a **ZoomIt is not running** error rather than crashing or silently leaving a stale overlay.

- [ ] **Pinned command persistence** [ID: ZI-CMDPAL-PINS] [ADMIN: NO]
  Pin all six ZoomIt actions and the Settings result to Command Palette Home, restart Command Palette or PowerToys, and confirm all seven entries remain pinned with distinct identities and still invoke the correct mode or Settings page.
