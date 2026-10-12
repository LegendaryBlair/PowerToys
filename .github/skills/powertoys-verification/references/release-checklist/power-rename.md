# PowerRename - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - standard-user coverage, subject to the stated fixtures.
- `[ADMIN: YES]` - requires an authorized elevated session.
- `[ADMIN: COND]` - retain ordinary and elevated variants independently.
- `[ID: ...]` - stable scenario identifier; retain every required child/input observation.

## Fixtures & conventions

- Use disposable files and a folder with a known nested file; record original names/content, extensions and
  timestamps. Set known creation times for date-token checks and retain every required parameter row.
- Preserve module settings, search/replace history, last-used fields and Explorer/window state. Exercise
  changes through Settings and restore their original values, not defaults.
- Preview-only checks must not rename files. Apply only to owned selections and verify the resulting disk
  names/content; remove only owned output fixtures during cleanup.
- Observe modern/classic shell entries independently and use a fresh owned selection when a relaunch is required.
- See the [module profile](../modules/power-rename.md) for control interaction and restoration mechanics, and use the [frozen inventory](../assertion-inventories/power-rename.json) without run-local regrouping.

## PowerRename (16 items)

### Shell integration

- [ ] **Module enablement and shell entry** [ID: PR-MENU-STATE] [ADMIN: NO]
  Toggle the PowerRename enable switch **off**, then **on**, in PowerToys Settings. Confirm the `Rename with PowerRename` context-menu entry **disappears** when the module is disabled and **reappears** when it is enabled. (On Win11) With the module enabled, confirm `Rename with PowerRename` is present in **both** the Win11 tier-1 (modern) context menu **and** the classic "Show more options" (`#32768`) context menu.

- [ ] **Menu location and icon matrix** [ID: PR-MENU-OPTIONS] [ADMIN: NO]
  In Settings' Shell integration section, test all four combinations of Show PowerRename in and Hide icon in context menu. Observe the icon setting in both modern and legacy/extended menus; use the profile for expanding/locating the controls.

  | Menu choice | Hide icon | Expected shell entry |
  |---|---|---|
  | Default and extended | Off | Present in the default modern menu with its icon. |
  | Default and extended | On | Present in the default modern menu without its icon. |
  | Extended only | Off | Absent from default; present under Shift + right-click with its icon. |
  | Extended only | On | Absent from default; present under Shift + right-click without its icon. |

### History and persistence

- [ ] **Search autocomplete** [ID: PR-AUTOCOMPLETE] [ADMIN: NO]
  With owned prior search history, enable auto-complete through Settings, launch PowerRename and type a matching Search prefix such as `p`. Confirm matching prior terms appear as suggestions. Disable auto-complete, relaunch and type the same prefix; no suggestions popup should appear.

- [ ] **Recently used field values** [ID: PR-LAST-VALUES] [ADMIN: NO]
  Enable Show recently used strings, use Search=`persist`, Replace=`KEPT` and Apply on owned files. Relaunch on a fresh file: both values are pre-populated and the preview auto-applies. Disable the option and confirm subsequent launches start with empty Search/Replace fields.

### Name transformations

- [ ] **Case conversion** [ID: PR-CASE] [ADMIN: NO]
  With the owned file `Hi World.txt` selected and a Replace producing `Hi World`, exercise each case toggle independently. Uppercase previews `HI WORLD.TXT`; Lowercase previews `hi world.txt`. Titlecase leaves this already title-cased name unchanged, so its Renamed cell is empty and Apply is disabled for this single-file no-op. Confirm the case buttons are mutually exclusive: selecting one deselects the previously active button. Do not interpret an intentionally blank unchanged-name preview as a missing conversion result.

- [ ] **Filename and extension scope** [ID: PR-NAME-SCOPE] [ADMIN: NO]
  File `aaa.aaa`, Search `aaa` → Replace `zzz`, Match-all on. Using the **Apply to** selector (single-select), confirm each scope changes only the targeted part of the name: **Filename + extension** (default) → `aaa.aaa → zzz.zzz`; **Filename only** → `aaa.aaa → zzz.aaa`; **Extension only** → `aaa.aaa → aaa.zzz`. Only **one** option can be selected at a time.

- [ ] **Advanced enumeration** [ID: PR-ENUMERATION] [ADMIN: NO]
  Enumerate Items. Test advanced enumeration using different values for every field `${start=10,increment=2,padding=4}`. With Enumerate items on and Replace = `item_${start=10,increment=2,padding=4}` applied to a 5-file selection, the preview **Renamed** column must show `item_0010`, `item_0012`, `item_0014`, `item_0016`, `item_0018` (counter = `start + index*increment` for 0-based index, zero-padded to `padding` digits; verify each field independently: `start=10` → first value 0010 not 0, `increment=2` → step of 2 not 1, `padding=4` → 4-digit zero-pad not unpadded).

- [ ] **Creation-date tokens** [ID: PR-DATE-TOKENS] [ADMIN: NO]
  File `orig.txt` with a known creation time (e.g. `07/02/2026 11:54:54`). With regex on, Search = `.*\.txt$`, Replace = `$YYYY_$MMMM_$DD__$hh-$mm-$ss.txt`. Confirm each token expands from the file's creation date/time so the preview exactly matches the expected string `2026_July_02__11-54-54.txt` (`$YYYY`→`2026`, `$MMMM`→`July`, `$DD`→`02`, `$hh`→`11`, `$mm`→`54`, `$ss`→`54`; also verify `$fff` milliseconds).

### Selection and execution

- [ ] **Files, folders and descendants** [ID: PR-INCLUDE-TYPES] [ADMIN: NO]
  Selection = one file (`aaa_file.txt`) + one folder (`aaa_folder` containing `aaa_inner.txt`); Search `aaa` → Replace `zzz`. Toggle **Include Files**, **Include Folders**, and **Include Subfolder Items** independently and confirm each gates only its row type in the preview:
    - **All include on** → all three renamed (`zzz_file.txt`, `zzz_folder`, `zzz_inner.txt`).
    - **Files off** → files' Renamed column empty; only `aaa_folder → zzz_folder`.
    - **Folders off** → folder unchanged; both files renamed.
    - **Subfolder Items off** → inner file excluded; top-level file + folder renamed.

    Confirm the toggles **combine** (several can be off simultaneously).

- [ ] **Apply only checked rows** [ID: PR-CHECKED-ROWS] [ADMIN: NO]
  Files `file1.txt, file2.txt, file3.txt`; Search `file` → Replace `done`. Uncheck the `file2.txt` row in the preview (row shows `[ ]`), then **Apply**. Confirm on disk that only the checked rows were renamed: `done1.txt, done3.txt, file2.txt` — the unchecked file is **left untouched**.

- [ ] **Filter preview rows** [ID: PR-FILTER] [ADMIN: NO]
  Files `match1.txt, match2.txt, keepme.txt`; Search `match` → Replace `X` (`keepme.txt` does not match). Use the **Filter** (funnel) button above the file list: choosing **"Only show files that will be renamed"** hides the non-matching `keepme.txt` (only `match1.txt`, `match2.txt` visible); choosing **"Show all files"** restores all 3 rows.

- [ ] **Select or deselect all rows** [ID: PR-SELECT-ALL] [ADMIN: NO]
  With a 3-file list all initially checked, use the **Select/deselect all** checkbox (header "Select or deselect all") above the file list: one click **deselects all** (all rows `[ ]`); clicking again **selects all** (all rows `[x]`) — toggling every row in a single action.

### Matching and regular expressions

- [ ] **Case-sensitive matching** [ID: PR-CASE-SENSITIVE] [ADMIN: NO]
  File `MixedCase.txt`, Search `mixed` → Replace `XXX`. With **Case sensitive OFF** (default) → `mixed` matches `Mixed`, preview `MixedCase.txt → XXXCase.txt`. With **Case sensitive ON** → no match: the Renamed column is **empty** and the **Apply** button is **disabled**.

- [ ] **First or all occurrences** [ID: PR-MATCH-ALL] [ADMIN: NO]
  File `Foo_A_A_A.txt`, Search `A` → Replace `B`. With **Match all occurrences unchecked** (default) → only the **first** (left-to-right) match is replaced: `Foo_A_A_A.txt → Foo_B_A_A.txt`. With it **checked** → **all** occurrences are replaced: `Foo_A_A_A.txt → Foo_B_B_B.txt`.

- [ ] **Regular expression matching and capture groups** [ID: PR-REGEX] [ADMIN: NO]
  On `IMG_001.png` through `IMG_003.png`, enable regular expressions, search `(.*).png` and replace with `foo_$1.png`. Confirm every filename matches and `$1` expands to its own captured stem: `foo_IMG_001.png`, `foo_IMG_002.png`, `foo_IMG_003.png`. With regex off, `$1` is literal rather than a capture-group substitution.

- [ ] **Boost-specific regex syntax** [ID: PR-BOOST] [ADMIN: NO]
  Enable **Use Boost library** (settings key `UseBoostLib`, read at PR launch — relaunch after toggling). Files `test.txt` and `nest.txt`; with regex on, Search = `(?<=t)est` (Perl lookbehind, unsupported by the default std::regex engine), Replace = `X`. Confirm the lookbehind evaluates without error and matches **only** where `est` is preceded by `t`: `test.txt → tX.txt`, while `nest.txt` is **unchanged**.
