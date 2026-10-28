# Image Resizer - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - standard-user coverage with owned fixtures.
- `[ID: ...]` - stable E2E scenario identifier; retain the required observations in the matching inventory.
- Unit tests cover rules without external dependencies. Component/Functional tests exercise bounded
  production behavior with real dependencies. This checklist covers the remaining real user journeys.

## Fixtures & conventions

- Use an owned folder with a PNG of known dimensions and a small animated GIF. Record each image's
  dimensions and original bytes before resizing; never use personal pictures or replace originals.
- Preserve module enablement, Image Resizer settings and the existing Settings window's navigation
  and placement. Add only one uniquely named temporary preset; do not remove a user's preset.
- Change the preset and processing controls through the shipped UI. JSON reads are observations,
  not a substitute for the Settings-to-module connection under test.
- Use known Fit/Pixel dimensions for the representative preset and calculate expected output sizes
  independently. Unit, fit-mode, naming, timestamp and error matrices belong to the lower-layer suite,
  not repeated agent operations.
- Restore the original settings and enabled state, close only owned windows, and remove owned files.
  Preserve unrelated concurrent changes rather than overwriting an unexplained current state.
- Use the [module profile](../modules/image-resizer.md) and
  [frozen inventory](../assertion-inventories/image-resizer.json). The profile explains the lower-layer
  coverage and the distinction between this E2E scope and the older exhaustive checklist.

## Image Resizer (2 items)

### Settings-to-output user journey

- [ ] **Create a preset and resize a real selection** [ID: IR-E2E-RESIZE] [ADMIN: NO]
  Enable Image Resizer if necessary. In Settings, create one uniquely named preset with distinctive
  Fit/Pixel dimensions and explicitly Save it. Select the owned PNG and animated GIF in Explorer and
  invoke **Resize with Image Resizer**. Confirm the Image Resizer window receives the selection and
  lists the exact preset created in Settings; select it through the UI. Confirm the GIF warning is
  visible. Use copy-output mode, not overwrite, and click **Resize** once. Confirm processing completes,
  exactly one resized copy exists for each selected image with the expected preset-based name and
  dimensions, and both original files are byte-for-byte unchanged. Restore the original configuration
  and remove the temporary preset and fixtures. This journey does not repeat every processing option.

### Shell entry and module enablement

- [ ] **Disable and restore the Explorer entry** [ID: IR-E2E-SHELL] [ADMIN: NO]
  Disable Image Resizer through Settings. On a selected owned image, confirm Explorer's context menu
  is present but **Resize with Image Resizer** is absent. Re-enable Image Resizer and confirm the command
  and its icon return; invoke it and confirm one usable Image Resizer window receives the selected
  image. On Windows 11 observe both the modern menu and classic **Show more options** entry; on Windows
  10 observe the classic menu. Do not restart Explorer or PowerToys to hide a failed live transition.
  Close the owned resize window without processing and restore the original enabled state.
