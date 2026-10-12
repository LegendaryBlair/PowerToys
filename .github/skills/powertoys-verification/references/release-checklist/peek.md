# Peek - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - standard-user coverage, subject to the stated fixtures.
- `[ADMIN: YES]` - requires an authorized elevated session.
- `[ADMIN: COND]` - retain ordinary and elevated variants independently.
- `[ID: ...]` - stable scenario identifier; retain every required child/input observation.

## Fixtures & conventions

- **Opening Peek**: select a file in Explorer and press **Ctrl+Space** (default); Peek opens a window
  titled **`<file> - Peek`**.
- **Prepare a fixtures folder** with one file per previewer type, each carrying an in-file marker so you
  can confirm the *content* rendered (not just that a pane appeared): an **image** (PNG), a **source/text**
  file (e.g. `.cs`), a **markdown** file (H1 + bold + bullet list), a **PDF** with known marker text, an
  **HTML** file with an `<h1>` marker, a **`.zip`** containing ≥1 file, and an **unsupported** file
  (e.g. `.xyz` of random bytes). For the pin/position items also prepare **3 differently-sized images**
  (e.g. 320×240, 800×600, 1920×1080).
- Preserve module settings, shortcut, pin/placement state and original windows. Track owned Peek,
  Explorer and default-app windows separately; do not close a user's shared app after an Open with action.
- See the [module profile](../modules/peek.md) for control interaction and restoration mechanics, and use the [frozen inventory](../assertion-inventories/peek.json) without run-local regrouping.

## Peek (18 items)

### Previewers

- [ ] **Image preview** [ID: PEEK-IMAGE] [ADMIN: NO]
  **Image** — Peek an image (e.g. `small-image.png`, 200×150). Confirm the **image previewer** renders the bitmap, sized to the source, with the pin + "Open with" buttons visible.

- [ ] **Syntax-highlighted text preview** [ID: PEEK-TEXT] [ADMIN: NO]
  **Text or dev file** — Peek a source file (e.g. `Program.cs`). Confirm the **developer/text previewer** renders the code with **syntax highlighting and line numbers** (not raw plain text, not blank).

- [ ] **Rendered Markdown** [ID: PEEK-MARKDOWN] [ADMIN: NO]
  **Markdown file** — Peek a `.md` file containing an H1, bold text, and a bullet list. Confirm the preview renders **formatted markdown** (H1 styled, bold applied, list bulleted) — not the raw `#`/`**` source.

- [ ] **PDF preview** [ID: PEEK-PDF] [ADMIN: NO]
  **PDF** — Peek a 1-page PDF with known marker text. Confirm the **PDF page renders** with the marker text visible and a PDF toolbar (zoom / page nav), not an error.

- [ ] **Rendered HTML** [ID: PEEK-HTML] [ADMIN: NO]
  **HTML** — Peek an `.html` file whose `<h1>` contains a marker. Confirm the HTML is **rendered** (heading shown as a styled heading), not shown as raw markup.

- [ ] **Archive contents** [ID: PEEK-ARCHIVE] [ADMIN: NO]
  **Archive files (.zip, .tar, .rar)** — Peek a `.zip` containing ≥1 file. Confirm the **archive previewer** lists the entries in a tree and shows directory/file counts + sizes (e.g. `0 directories | 1 files | … bytes`). The same previewer handles `.tar`/`.rar`.

- [ ] **Unsupported-file metadata** [ID: PEEK-UNSUPPORTED] [ADMIN: NO]
  **Unsupported file** — Peek a file of an unhandled type (e.g. `unsupported.xyz` / `.exe`). Confirm the **unsupported-file view** is shown with **File Type / Size / Date Modified** metadata (and a generic icon) instead of a previewer, and Peek does not crash.

### Pinning and window placement

- [ ] **Pinned placement across files** [ID: PEEK-PIN-SWITCH] [ADMIN: NO]
  **Pin, switch between different-sized images** — Open Peek on the 3-image selection, **pin** the window (pin toggle), move it to a known position/size, then switch between the images. Confirm the window stays at the **same position and size** across every switch (does not re-center/resize to each image).

- [ ] **Pinned placement after reopen** [ID: PEEK-PIN-REOPEN] [ADMIN: NO]
  **Pin, close and reopen** — With the window pinned at a known place/size, close Peek (`Esc`) and reopen it on the same selection. Confirm the new window opens at the **same pinned place and size**.

- [ ] **Unpinned placement across files** [ID: PEEK-UNPIN-SWITCH] [ADMIN: NO]
  **Unpin, switch file** — From the pinned window, **unpin**, then switch to a different file. Confirm the window **moves to the default placement** (leaves the pinned coordinates and re-centers/sizes to the new file).

- [ ] **Unpinned placement after reopen** [ID: PEEK-UNPIN-REOPEN] [ADMIN: NO]
  **Unpin, close and reopen** — With the window unpinned, close (`Esc`) and reopen Peek. Confirm the new window opens at the **default place/size**, not the previously-pinned coordinates.

### Opening the default application

- [ ] **Open through the button** [ID: PEEK-OPEN-CLICK] [ADMIN: NO]
  **By clicking a button** — With a file peeked, click the **"Open with <default app>"** button. Confirm the file opens in its default application (a new app process/window for that file appears; match by the file's window title).

- [ ] **Open through Enter** [ID: PEEK-OPEN-ENTER] [ADMIN: NO]
  **By pressing Enter** — With the Peek window focused, press **Enter**. Confirm the file opens in its default application (same result as L712).

### Activation and sessions

- [ ] **Command-line entry** [ID: PEEK-CLI] [ADMIN: NO]
  **Peek via command** — Run `PowerToys.Peek.UI.exe <file>`. Confirm it opens a `<file> - Peek` window previewing that file (the CLI accepts a file-path argument and shows the previewer).

- [ ] **Multiple open sessions** [ID: PEEK-CONCURRENT] [ADMIN: NO]
  **Peek works while a session is already on** — Open several Peek sessions on different files, leaving prior windows open. Confirm each launch opens its own window and previews correctly with the others still open (no crash/hang, no fatal errors in `Peek\Logs`).

- [ ] **Change the activation shortcut** [ID: PEEK-REBIND] [ADMIN: NO]
  **Change the activation shortcut** — In Settings → Peek, change the activation shortcut (e.g. `Ctrl+Space` → `Ctrl+Shift+Space`). After the change takes effect (the runner re-registers the hook — it is **not** hot-reloaded), confirm the **new** chord opens Peek and the **old** chord no longer does. Restore the original shortcut afterward.

### File navigation

- [ ] **Folder-wide navigation** [ID: PEEK-FOLDER-NAVIGATION] [ADMIN: NO]
  **Folder navigation with Left/Right arrows** — With a **single** file selected in a folder, open Peek and press `RightArrow` / `LeftArrow`. Confirm you can cycle through **all files in the folder** (in order, wrapping at the ends).

- [ ] **Selection-scoped navigation** [ID: PEEK-SELECTION-NAVIGATION] [ADMIN: NO]
  **Selection-scoped navigation** — Select **multiple** files (a subset of a folder), open Peek and press `RightArrow` / `LeftArrow`. Confirm navigation cycles **only among the selected files** and never escapes into the folder's other files.
