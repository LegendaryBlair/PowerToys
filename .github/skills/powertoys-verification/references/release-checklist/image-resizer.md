# Image Resizer - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - standard-user coverage, subject to the stated fixtures.
- `[ADMIN: YES]` - requires an authorized elevated session.
- `[ADMIN: COND]` - retain ordinary and elevated variants independently.
- `[ID: ...]` - stable scenario identifier; retain every required child/input observation.

## Fixtures & conventions

- Prepare test images at a **known DPI** (the pixel outputs below assume **96 DPI**): `landscape 1200×800`, `portrait 800×1200`, `small 100×100`, `square 400×400`, `anim.gif` (animated), and three `batch*` images `1000×1000`.
- Default presets are **Small 854×480, Medium 1366×768, Large 1920×1080, Phone 320×568** — all **Fit**, unit **Pixel**.
- Fit modes: **Fit** = scale by `min(scaleX,scaleY)` (letterbox, no crop); **Fill** = scale by `max(scaleX,scaleY)` then centered-crop to the box; **Stretch** = apply scaleX and scaleY independently (distorts).
- Unit → pixels: **Pixel** = literal value; **Percent** = `value/100 × original` (DPI-independent); **Inch** = `value × DPI`; **Centimeter** = `value × DPI / 2.54`.
- Always resize **copies** in a disposable folder unless the item is specifically testing in-place replace.
- Preserve the original enabled state, presets, filename format and resize options. Restore those values and
  remove only owned outputs; the in-place case must also use a disposable source.
- See the [module profile](../modules/image-resizer.md) for control interaction and restoration mechanics, and use the [frozen inventory](../assertion-inventories/image-resizer.json) without run-local regrouping.

## Image Resizer (12 items)

### Entry points and presets

- [ ] **Disabled and enabled shell entry** [ID: IR-MENU-STATE] [ADMIN: NO]
  In PowerToys Settings, **disable** Image Resizer. Right-click an image and confirm `Resize with Image Resizer` is **absent** from **both** the Win11 tier-1 (modern) menu **and** the classic "Show more options" (`#32768`) menu, while sibling PowerToys entries (e.g. `Rename with PowerRename`, `Unlock with File Locksmith`) **remain present** — proving the menu still renders and only the Image Resizer command was gated out (not a render failure).

  **Enable** Image Resizer. Right-click an image and confirm `Resize with Image Resizer` is **present, with its icon**, in **both** the Win11 tier-1 (modern) menu **and** the classic "Show more options" (`#32768`) menu. Invoking the entry launches `PowerToys.ImageResizer.exe` on the selection (window titled "Image Resizer").

- [ ] **Preset editing round-trip** [ID: IR-PRESETS] [ADMIN: NO]
  In Settings → Image Resizer → *Image sizes*, **remove** a built-in preset (e.g. `Phone`) and **add** a custom size (e.g. `Web` = 1024×768 px, Fit). Open the Image Resizer window from the context menu and open the size selector; confirm the removed preset (`Phone`) is **gone** and the added preset (`Web`) is **listed** — the presets round-trip from settings to the window.

### Resize operations

- [ ] **Single-image preset resize** [ID: IR-SINGLE] [ADMIN: NO]
  Select a **single** `1200×800` image and resize with the **Small** preset (854×480, Fit). Confirm exactly one output `<name> (Small).jpg` is produced at **720×480** (Fit scale = min(854/1200, 480/800) = 0.6 → 720×480) and the source file is untouched.

- [ ] **Batch preset resize** [ID: IR-BATCH] [ADMIN: NO]
  Select **three** `1000×1000` images and resize them in **one** operation with the **Small** preset (854×480, Fit). Confirm all three outputs `<name> (Small).jpg` are produced, each at **480×480** (Fit = min(854/1000, 480/1000) = 0.48 → 480×480).

- [ ] **Animated GIF warning** [ID: IR-GIF] [ADMIN: NO]
  Open Image Resizer on an **animated `.gif`** and confirm the yellow InfoBar warning **"Gif files with animations may not be correctly resized."** appears (shown whenever any selected file has a `.gif` extension).

### Resize modes and units

- [ ] **Fill, Fit and Stretch matrix** [ID: IR-FIT-MODES] [ADMIN: NO]
  Independently resize fresh copies of the same `1200×800` source to a custom `400×400` target in every mode. Observe dimensions and content, not dimensions alone.

  | Mode | Expected output and transformation |
  |---|---|
  | Fill | `400×400`: max scale 0.5 produces `600×400`, then centered crop fills the box without letterboxing. |
  | Fit | `400×267`: min scale 1/3 preserves aspect ratio, fitting/letterboxing within the target box without cropping. |
  | Stretch | `400×400`: independent X=1/3 and Y=0.5 scales distort the image, unlike Fill's crop. |

- [ ] **Unit conversion matrix** [ID: IR-UNITS] [ADMIN: NO]
  Use fresh `1200×800` copies and record their DPI. Execute every unit row against independently calculated output; a representative unit does not cover the others.

  | Unit / input | Expected output |
  |---|---|
  | Centimeters, `10×5`, Stretch | `378×189` at 96 DPI (`value × DPI / 2.54`); `472×236` at 120 DPI. |
  | Inches, `4×3`, Stretch | `384×288` at 96 DPI (`value × DPI`); `480×360` at 120 DPI. |
  | Percent, width 50% | `600×400`, with both dimensions halved independently of DPI. |
  | Pixels, `500×300`, Stretch | Exactly `500×300`; dimensions are literal. |

### Output and preservation options

- [ ] **Filename format tokens** [ID: IR-FILENAME] [ADMIN: NO]
  Set Filename format to `%1 - %2 - %3 - %4 - %5 - %6` and resize a `1200×800` image with the **Small** preset. Confirm the output filename is `<orig-name> - Small - 854 - 480 - 720 - 480.jpg`, where **%1**=original filename, **%2**=size/preset name, **%3**=selected width, **%4**=selected height, **%5**=actual output width, **%6**=actual output height.

- [ ] **Original modification time** [ID: IR-TIMESTAMP] [ADMIN: NO]
  Check **Use original date modified**. Set a source image's last-modified time to a known past date (e.g. `2020-01-15 08:30`), resize it, and confirm the **output's** modified date **equals the source's** (`2020-01-15 08:30`). Control: with the option **unchecked**, the output's modified date is the **current** time instead.

- [ ] **Prevent enlargement** [ID: IR-SHRINK-ONLY] [ADMIN: NO]
  Check **Make pictures smaller but not larger**. Resize a **100×100** image with a target larger than it (e.g. Small 854×480) and confirm the output stays **100×100** (never enlarged). Control: a larger `1200×800` image with the same target is **still shrunk** (→720×480).

- [ ] **Replace original images** [ID: IR-REPLACE] [ADMIN: NO]
  Check **Resize the original pictures (don't create copies)**. Resize a `1200×800` image with the **Small** preset and confirm the original file is **overwritten in place** at **720×480** and **no** separate `(Small)` copy is created — the folder still holds exactly one file with the original name.

- [ ] **Orientation-aware target dimensions** [ID: IR-ORIENTATION] [ADMIN: NO]
  **Uncheck** "Ignore the orientation of pictures" and resize a **landscape** `1200×800` image with a **portrait** target `100×200` (Fit, Pixel): confirm the target is applied **as-is** → **100×67** (no swap). Then **check** the option and repeat: the target is **swapped to 200×100** to match the source orientation → **150×100**.
