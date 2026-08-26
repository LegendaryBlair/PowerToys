# ZoomIt — module verification profile

**PT module**: `ZoomIt` (screen magnification, annotation, break timer, screenshot/OCR, DemoType, and recording)
**Source**: `src\modules\ZoomIt\`
**Settings store**: `HKCU\Software\Sysinternals\ZoomIt`
**Exe**: `%LOCALAPPDATA%\PowerToys\PowerToys.ZoomIt.exe`
**Default hotkeys**: Ctrl+1 Zoom, Ctrl+2 Draw, Ctrl+3 Break, Ctrl+4 Live Zoom, Ctrl+5 Record, Ctrl+6 Snip, Ctrl+Alt+6 OCR, Ctrl+7 DemoType, Ctrl+8 Panorama
**Named Events**: `ZoomIt.Zoom`, `ZoomIt.Draw`, `ZoomIt.Break`, `ZoomIt.LiveZoom`, `ZoomIt.Snip`, `ZoomIt.SnipOcr`, `ZoomIt.Record`, `ZoomIt.Exit`
**Last verified**: `0.101.2293.0` · `2026-08-19`

## Entry-paths (try in order)

### 1. Hosted named event

Use the event matching the action when the item tests downstream mode behavior rather than the
physical shortcut:

```powershell
Invoke-PtSharedEvent -Name 'ZoomIt.Zoom'
Invoke-PtSharedEvent -Name 'ZoomIt.Draw'
Invoke-PtSharedEvent -Name 'ZoomIt.Break'
Invoke-PtSharedEvent -Name 'ZoomIt.LiveZoom'
Invoke-PtSharedEvent -Name 'ZoomIt.Snip'
Invoke-PtSharedEvent -Name 'ZoomIt.SnipOcr'
Invoke-PtSharedEvent -Name 'ZoomIt.Record'
```

The hosted process creates these events in `Zoomit.cpp` during PowerToys startup. If all action
events are absent, first inspect for a native hotkey-conflict MessageBox: ZoomIt creates the events
only after shortcut registration succeeds far enough to reach the hosted event-listener setup.

### 2. Physical shortcut

Use `Send-PtChord` only when the item explicitly tests the configured chord or a derived chord.
Guard the interactive desktop first. The foreground fixture must run at Medium IL when the tested
path depends on ZoomIt's low-level keyboard input:

```powershell
Assert-PtForegroundOrAbort -AppId '<fixture-app-id>'
Send-PtChord -Mods 0x11 -Key 0x35
```

### 3. Tray menu

Open the hidden-icons overflow, locate the single ZoomIt icon, and use its left/right menus for
Break Timer, Draw, Zoom, and Record. Capture menu evidence before invoking an overlay because active
ZoomIt modes can take exclusive input and exclude themselves from screen capture.

### 4. Settings UI

Target an explicit Settings HWND when multiple Settings processes exist. Discover volatile selectors
at runtime by label and role. ZoomIt values are stored in the Sysinternals registry key, not a module
`settings.json`.

## Recipes — capability/control map

| # | Capability | Drive (control / settings key) |
|---|---|---|
| 1 | Hosted lifecycle | global `enabled.ZoomIt` toggle; observe `PowerToys.ZoomIt` and the hosted named events |
| 2 | Tray visibility | `ShowTrayIcon` / Settings **Show tray icon** toggle |
| 3 | Base and derived shortcuts | shortcut edit buttons; registry keys such as `ToggleKey`, `LiveZoomToggleKey`, `RecordToggleKey`, `SnipPanoramaToggleKey` |
| 4 | DemoType file and speed | native file picker; `DemoTypeFile`, `DemoTypeSpeedSlider`, `DemoTypeUserDrivenMode` |
| 5 | Break configuration | `BreakTimeout`, `BreakOpacity`, `BreakTimerPosition`, background/sound/lock registry values |
| 6 | Recording format and scaling | `RecordingFormat`, `RecordScalingGIF`, `RecordScalingMP4` |
| 7 | Recording audio | `CaptureAudio`, `CaptureSystemAudio`, `MicMonoMix`, `MicrophoneDeviceId` |
| 8 | Webcam composition | `WebcamOverlay`, `WebcamDeviceSymLink`, `WebcamPosition`, `WebcamSize`, `WebcamShape` |
| 9 | Saved recording output | full-screen Ctrl+5; region Ctrl+Shift+5; window Ctrl+Alt+5; native Save dialog |
| 10 | Snip/OCR/Panorama | hosted event or configured shortcut, followed by a real selection drag |
| 11 | Command Palette actions | query the exact titles `ZoomIt: Zoom`, `ZoomIt: Draw`, `ZoomIt: Break`, `ZoomIt: Live Zoom`, `ZoomIt: Snip`, `ZoomIt: Record`, and `ZoomIt` Settings |

**Read-out notes**

- For shortcut derivation, inspect the visible keycaps after the edit dialog settles and again after
  navigating away/back to the page.
- For DemoType, assert exact fixture text in a Medium-IL edit control and record elapsed time for two
  widely separated speed values.
- For recording, validate saved media outside ZoomIt using metadata and playback. Full-screen and
  window scope can be automated; region scope still needs a real drag.
- For device selectors, enumerate OS devices independently with `Get-PnpDevice -PresentOnly` so
  duplicates or disconnected entries can be distinguished from legitimate endpoints.
- Before classifying missing Command Palette results, confirm both
  `Microsoft.CmdPal.Ext.PowerToys` and the enabled flag exist. Query the search box directly if the
  CmdPal helper has reset to Home.

## BLOCKED traps

- **Active Zoom/Draw/Break surfaces are not ordinary windows.** They can own input and exclude the
  rendered surface from capture. Use saved output for recording/screenshot assertions; classify
  visual-only overlay assertions `BLK-OVERLAY-INPUT-BLOCK` when two entry paths reach the same
  uncapturable surface.
- **Selection modes require a real drag.** Snip, OCR, Panorama, region recording, and aspect-ratio
  selection are `BLK-DRAG-REQUIRED` when the run cannot supply a trustworthy pointer drag.
- **A startup conflict can hide all hosted events.** Inspect and capture native dialogs before
  concluding the module failed to launch. Dismissing the dialog does not prove the required
  non-blocking hosted behavior.
- **Higher-integrity foreground fixtures break DemoType/input checks.** Launch disposable fixtures
  with `Start-PtNonElevated` and verify their token with `Test-ProcessElevated`.
- **Native Open/Save dialogs may resist elevated UIA Invoke.** Enumerate child HWNDs, set the filename
  Edit with `WM_SETTEXT`, and click Open/Save/Cancel with `BM_CLICK`.
- **Registry import does not remove values created during the run.** For exact restoration, stop the
  hosted process, delete only `HKCU\Software\Sysinternals\ZoomIt`, import the saved `.reg`, re-export,
  and compare the text.
- **Audio/camera matrix checks need real controlled devices.** RDP Remote Audio alone cannot prove
  isolated system/microphone content or asymmetric stereo folding; no camera means webcam items are
  `BLK-HARDWARE`.
- **Clean-profile and lock/authentication items are destructive.** Do not delete the user's profile
  or lock the active automation session in an installed-bits run.

## Fixtures

- Medium-IL WinForms edit fixture for DemoType exact-text, cancel, reset, and speed assertions.
- Medium-IL moving counter/clock fixture for full-screen and window recording.
- Long textured document plus manual drag for Panorama.
- Controlled WAV/system-tone and microphone marker with physical monitoring for audio matrix checks.
- Camera with permission for webcam selector/composition checks.

## Source citations

- `src\modules\ZoomIt\ZoomIt\Zoomit.cpp` — hosted event creation and event-listener startup.
- `src\modules\ZoomIt\ZoomIt\ZoomItSettings.h` — registry-backed settings and recording format enum.
- `src\modules\ZoomIt\ZoomIt\DemoType.cpp` — file loading and DemoType input behavior.
- `src\modules\ZoomIt\ZoomIt\VideoRecordingSession.cpp` — save/trim and append flows.
- `src\modules\ZoomIt\ZoomIt\SelectRectangle.cpp` — capture-excluded selection border.
- `src\modules\ZoomIt\ZoomIt\WebcamPreviewWindow.cpp` — capture-excluded webcam preview.
- `src\modules\cmdpal\ext\Microsoft.CmdPal.Ext.PowerToys\Modules\ZoomItModuleCommandProvider.cs` — six actions and Settings result.
