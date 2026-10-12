# File Locksmith - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - standard-user coverage, subject to the stated fixtures.
- `[ADMIN: YES]` - requires an authorized elevated session.
- `[ADMIN: COND]` - retain ordinary and elevated variants independently.
- `[ID: ...]` - stable scenario identifier; retain every required child/input observation.

## Fixtures & conventions

- Prepare a disposable PowerToys installer fixture at a known path, record the processes it starts and
  cancel before installation. End task is permitted only for those exact owned processes, never an unrelated
  application discovered by a directory or drive scan.
- Establish expected locking PIDs from the fixture's executable/module/handle relationships before
  inspecting File Locksmith's result. Total installer process count is not the selected file's locker count.
  A separate `wixstdba.exe` bootstrapper does not count unless it also uses the selected installer image.
- Preserve the original module state and Explorer/window state. Use isolated file/directory fixtures and close
  owned File Locksmith, Explorer and installer windows after the case.
- Record Runner, target and File Locksmith integrity for the elevated visibility pair. Missing authorized
  elevation blocks only that variant; do not terminate or elevate the user's Runner to manufacture a fixture.
- Preserve independent outcomes for file/directory/drive scope, Reload, automatic delisting and both menu tiers.
- See the [module profile](../modules/file-locksmith.md) for control interaction and restoration mechanics, and use the [frozen inventory](../assertion-inventories/file-locksmith.json) without run-local regrouping.

## File Locksmith (10 items)

### Entry points and scan scope

- [ ] **File context-menu entry** [ID: FL-FILE-ENTRY] [ADMIN: COND]
  Start the owned installer fixture, right-click its executable and select Unlock with File Locksmith. Confirm the entry launches a window titled File Locksmith and lists the independently established locking PIDs, each with the correct process name and End task button, without duplicate rows. Do not require two entries merely because the installer starts two processes: if only the installer process uses the selected image and `wixstdba.exe` uses a separate image, expect only the installer row. Do not derive the expected PID set from File Locksmith's own output.

- [ ] **Recursive directory scan** [ID: FL-DIRECTORY] [ADMIN: COND]
  **Right-click the directory** containing the executable and select `Unlock with File Locksmith`. Confirm the entry appears and the UI lists the locking process(es) found **recursively** inside that directory tree.

- [ ] **Drive scan** [ID: FL-DRIVE] [ADMIN: COND]
  **Right-click the drive** where the executable is located and select `Unlock with File Locksmith`. Confirm the entry appears and the UI lists the locking process(es) on that volume. (You can close the PowerToys installer now.)

### Process list lifecycle

- [ ] **End an owned locking process** [ID: FL-END-TASK] [ADMIN: COND]
  Click **End task** on each listed installer process in the File Locksmith UI. Confirm each **End task** terminates that process (the installer window closes) and its **row is removed** from the list.

- [ ] **Reload newly started processes** [ID: FL-RELOAD] [ADMIN: COND]
  **Start the installer executable again**, then click the **Reload** button (top-right refresh) in the File Locksmith UI. Confirm the newly-started process(es) using the file are **rediscovered and added** to the list.

- [ ] **Remove exited processes automatically** [ID: FL-AUTO-REMOVE] [ADMIN: COND]
  **Close the installer window** (let its process exit) **without** pressing Reload. Confirm File Locksmith **auto-delists** the exited process(es) within ~1–2 s (no manual refresh), and close the window.

### Elevation and visibility

- [ ] **Non-elevated process visibility** [ID: FL-MEDIUM-VISIBILITY] [ADMIN: COND]
  With File Locksmith launched **non-elevated**, **right-click "Program Files"** (the folder holding the elevated PowerToys runner) and select `Unlock with File Locksmith`. Confirm **`PowerToys.exe` does NOT appear** in the list — a non-elevated File Locksmith cannot read the higher-integrity (elevated) runner process.

- [ ] **Restart as administrator** [ID: FL-RESTART-ADMIN] [ADMIN: YES]
  In that same non-elevated File Locksmith window, click **Restart as an administrator** (shield button, shown only when non-elevated) and approve the UAC prompt. Confirm that after relaunching **elevated** (title becomes **Administrator: File Locksmith**), **`PowerToys.exe` now appears** in the list — the elevated File Locksmith can see higher-integrity processes.

- [ ] **Large process list rendering** [ID: FL-LARGE-LIST] [ADMIN: YES]
  **Right-click the drive where Windows is installed** and select `Unlock with File Locksmith`. With the (large) process list shown, **scroll all the way down and back up** and confirm File Locksmith **does not crash** while rendering all those entries. **Repeat** after clicking **Restart as an administrator**, and confirm no crash in the elevated view either.

### Module enablement

- [ ] **Disabled and re-enabled shell entry** [ID: FL-MENU-STATE] [ADMIN: COND]
  **Disable** File Locksmith in PowerToys Settings. Right-click a file and confirm `Unlock with File Locksmith` is **absent** from **both** the Win11 tier-1 (modern) menu **and** the classic "Show more options" (`#32768`) menu, while sibling PowerToys entries (e.g. `Rename with PowerRename`) **remain present** — proving the menu still renders and only File Locksmith was gated out (not a render failure). **Re-enable** and confirm the entry **reappears** in both menus.
