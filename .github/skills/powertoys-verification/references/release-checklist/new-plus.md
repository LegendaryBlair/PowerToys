# New+ - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - standard-user coverage, subject to the stated fixtures.
- `[ADMIN: YES]` - requires an authorized elevated session.
- `[ADMIN: COND]` - retain ordinary and elevated variants independently.
- `[ID: ...]` - stable scenario identifier; retain every required child/input observation.

## Fixtures & conventions

- Use a disposable destination folder and synthetic file/folder templates. Preserve the original template
  directory's complete files, bytes and directory structure, configured template path, enabled state and naming options.
- Missing/empty-directory checks require an owned template directory selected through supported Settings,
  or an explicitly authorized fully restorable baseline. Do not delete or empty the user's Templates folder
  without that preservation plan. Restore the exact original state, not example defaults.
- Test the Win11 modern folder-background menu, not the classic Show more options menu. Record each created
  file/folder and remove only owned outputs; close only test-opened Explorer windows.
- Directory absence, directory emptiness and Settings-driven example population are separate conditions.
- See the [module profile](../modules/new-plus.md) for control interaction and restoration mechanics, and use the [frozen inventory](../assertion-inventories/new-plus.json) without run-local regrouping.

## New+ (9 items)

### Shell entry and enablement

- [ ] **Enabled background-menu entry** [ID: NP-MENU-ENABLED] [ADMIN: NO]
  Enable New+ in Settings and open a folder's modern background menu. Confirm New+ is present and its submenu contains at least Open templates. Corroborate enabled shell registration and its registration log using the profile's read-out guidance; registration alone does not prove the menu rendered.

- [ ] **Disabled and re-enabled entry** [ID: NP-MENU-DISABLED] [ADMIN: NO]
  Disable New+ through Settings and confirm its background-menu entry is absent while the remaining menu still renders. Corroborate shell unregistration and its log, while the sparse package remains installed with Status Ok. Re-enable and confirm the entry reappears.

### Template directory lifecycle

- [ ] **Recreate an absent template directory** [ID: NP-MISSING-DIRECTORY] [ADMIN: NO]
  Remove the owned/restorable Templates directory prepared above, then open the submenu. Menu construction must recreate an empty directory (0 items), showing only Open templates. This is distinct from Settings-driven example population; do not toggle enablement to make this case pass.

- [ ] **Empty template directory** [ID: NP-EMPTY-DIRECTORY] [ADMIN: NO]
  **Empty** the owned/restorable Templates directory (remove only the prepared contents, keeping the directory). Open the New+ submenu and confirm **no template items** are listed — only the always-present **`Open templates`** command remains.

- [ ] **Populate default example templates** [ID: NP-DEFAULT-TEMPLATES] [ADMIN: NO]
  With the owned Templates directory empty as in NP-EMPTY-DIRECTORY, disable/re-enable New+ through Settings. Confirm it copies `Example folder\` containing `Example txt file.txt` and `Another example txt file.txt`, plus `Any files or folders placed in the template folder are available via New+.txt`, and these appear in the submenu. Population requires the empty-directory Settings enable transition; a Runner-only restart is not a substitute.

### Creating from templates

- [ ] **Create from a file template** [ID: NP-FILE] [ADMIN: NO]
  Copy a file template such as `MyTemplate.txt` into the owned Templates directory. Confirm its submenu caption is `MyTemplate` when Hide extension is on, otherwise `MyTemplate.txt`. Select it and confirm `MyTemplate.txt` is copied into the destination and enters inline rename mode.

- [ ] **Create a complete folder template** [ID: NP-FOLDER] [ADMIN: NO]
  Copy a **folder-with-files** template into the Templates folder (e.g. `MyFolder\` containing `fileA.txt` and `sub\fileB.txt`). Open the New+ submenu and confirm **`MyFolder`** appears. **Select** it and confirm the folder is created **whole and recursively** in the current folder — i.e. `MyFolder\fileA.txt` **and** `MyFolder\sub\fileB.txt` all exist.

### Template naming options

- [ ] **Hide template extensions** [ID: NP-EXTENSION] [ADMIN: NO]
  Toggle Hide template filename extension in Settings with a `MyTemplate.txt` template. On shows `MyTemplate`; off shows `MyTemplate.txt`. In both states the created file retains `.txt`: the setting affects only the caption and takes effect without an Explorer restart.

- [ ] **Hide leading digits and separators** [ID: NP-PREFIX] [ADMIN: NO]
  With Hide extension off, use `01. Digits.txt` and toggle Hide template filename starting digits, spaces and dots. On makes both caption and created filename `Digits.txt`; off preserves `01. Digits.txt` in both. Unlike hiding extensions, this option changes the created filename too.
