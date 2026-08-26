# Crop And Lock — module verification profile

**PT module**: `CropAndLock` (live Thumbnail, interactive Reparent, and frozen Screenshot crops)
**Source**: `src\modules\CropAndLock\`
**Settings file**: `%LOCALAPPDATA%\Microsoft\PowerToys\CropAndLock\settings.json`
**Exe**: `%LOCALAPPDATA%\PowerToys\PowerToys.CropAndLock.exe`
**Default hotkeys**: Win+Ctrl+Shift+R Reparent, Win+Ctrl+Shift+T Thumbnail, Win+Ctrl+Shift+S Screenshot
**Named Events**: `CropAndLock.Reparent`, `CropAndLock.Thumbnail`, `CropAndLock.Screenshot`, `CropAndLock.Exit`
**Last verified**: `0.101.2293.0` · `2026-08-19`

## UI state-transition map

| Current state | Trigger | Next state | Observable side effect |
|---|---|---|---|
| Enabled, idle | mode named event or registered hotkey | Selecting | One topmost full-display window with class `CropAndLock.OverlayWindow` |
| Selecting | Escape key-up | Enabled, idle | Overlay HWND is destroyed; no cropped window is created |
| Selecting | Complete a non-empty real drag | Cropped | Reparent, Thumbnail, or Screenshot crop window is created for the foreground source |
| Disabled | mode event signal | Disabled | Event handle may exist, but no process/window side effect occurs |

## Entry-paths (try in order)

### 1. Hosted named event

Use the mode-specific event when the item tests downstream selector/crop behavior:

```powershell
Invoke-PtSharedEvent -Name 'CropAndLock.Reparent'
Invoke-PtSharedEvent -Name 'CropAndLock.Thumbnail'
Invoke-PtSharedEvent -Name 'CropAndLock.Screenshot'
```

Identify the selector by class, not title:

```powershell
winapp ui list-windows -a PowerToys.CropAndLock --json |
    ConvertFrom-Json |
    Where-Object className -eq 'CropAndLock.OverlayWindow'
```

### 2. Physical shortcut

Use `Send-PtChord` when the configured binding or persistence is the assertion. Foreground the
intended source immediately before the chord. Cancel a selector without completing the crop by
posting Escape to its HWND:

```powershell
Send-PtChord -Mods 0x5B,0x11,0x10 -Key 0x54
winapp ui send-keys esc -w <overlay-hwnd> --via post-message
```

### 3. Settings UI

Open **Windowing & Layouts → Crop And Lock** in an explicit Settings HWND. Discover each volatile
shortcut edit selector at runtime from the named container (`Thumbnail shortcut`, `Reparent
shortcut`, `Screenshot shortcut`). The shortcut dialog uses `PrimaryButton` to save.

## Recipes — capability/control map

| # | Capability | Drive (control / settings key) |
|---|---|---|
| 1 | Module lifecycle | global `enabled.CropAndLock` / page toggle; process `PowerToys.CropAndLock` |
| 2 | Reparent activation | `reparent-hotkey` or `CropAndLock.Reparent` |
| 3 | Thumbnail activation | `thumbnail-hotkey` or `CropAndLock.Thumbnail` |
| 4 | Screenshot activation | `screenshot-hotkey` or `CropAndLock.Screenshot` |
| 5 | Selector cancellation | `winapp ui send-keys esc -w <overlay-hwnd> --via post-message` |
| 6 | Shortcut persistence | Settings shortcut dialog, then navigate away/back and exercise both new and old physical chords |
| 7 | Crop creation | foreground source + mode activation + non-empty real drag inside source client area |
| 8 | Command Palette integration | exact module query; three mode commands plus Settings result |

**Read-out notes**

- A successful pre-selection activation is one `CropAndLock.OverlayWindow` spanning the display.
- After Escape, assert zero Crop And Lock windows and an unchanged source HWND/rectangle.
- After disabling, do not use named-event existence as the assertion. Signal each event and assert
  there is no process/window side effect.
- For a completed crop, inspect topmost style, crop/source HWNDs, source liveness, aspect behavior,
  and mode-specific pixel/interaction behavior.

## BLOCKED traps

- **Every content-behavior item needs a real drag.** Named events and physical hotkeys prove selector
  entry, but no crop exists until `OverlayWindow::OnLeftButtonDown/Move/Up` receives a non-empty
  selection. Use `BLK-DRAG-REQUIRED` when a trustworthy real pointer drag is unavailable.
- **The mode events outlive the module process.** The module interface creates all four event handles
  in its constructor, so `Test-PtSharedEvent` can stay true while Crop And Lock is disabled. Assert
  process/window side effects, not event existence.
- **Older settings files can omit `screenshot-hotkey`.** The module keeps the compiled Win+Ctrl+Shift+S
  default when parsing that key fails. Editing any shortcut in Settings materializes the missing key
  and may update the file version.
- **Copying the settings file does not necessarily update registered hotkeys already held by the
  module interface.** For exact restoration: restore the file, push one complete default shortcut
  object through Settings so all three runtime registrations update, verify all three physical
  defaults, then copy the original backup bytes back without another mutation.
- **Reset in the shortcut dialog can clear an assignment.** Capture the current dialog state and use
  a guarded physical chord plus Save when restoring a Win-key default.
- **Multiple Settings windows make app-id targeting ambiguous.** Use an explicit HWND and rediscover
  runtime selectors after navigating away/back.
- **Command Palette absence is not a module failure.** Confirm the direct named events work and inspect
  `Microsoft.CmdPal.Ext.PowerToys` before isolating a missing-provider defect to CmdPal integration.

## Fixtures

- Non-maximized Medium-IL Win32 window with changing content and an interactive control.
- Known-compatible packaged app with changing ordinary content.
- Calculator only as the documented Reparent incompatibility/fallback observation.

## Source citations

- `src\modules\CropAndLock\CropAndLockModuleInterface\dllmain.cpp` —
  `is_enabled_by_default`, constructor event creation, three default hotkeys, and settings fallback.
- `src\modules\CropAndLock\CropAndLock\main.cpp` — `ProcessCommand` mode dispatch and event listeners.
- `src\modules\CropAndLock\CropAndLock\OverlayWindow.cpp` — selector class, Escape cancellation, and
  mouse-drag state machine.
- `src\common\interop\shared_constants.h` — all four Crop And Lock event names.
- `src\modules\cmdpal\ext\Microsoft.CmdPal.Ext.PowerToys\Modules\CropAndLockModuleCommandProvider.cs`
  — Reparent, Thumbnail, Screenshot, and Settings Command Palette results.
