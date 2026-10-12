# Workspaces — PowerToys release checklist

## Legend

Each item is annotated with an admin-requirement tag:

**Admin requirement**:
- `[ADMIN: NO]` - runnable from a standard (non-elevated) shell
- `[ADMIN: YES]` - requires an elevated session (clean install, elevated PowerToys, or UAC-approved launch)
- `[ADMIN: COND]` - basic case is non-admin, but the stated variant requires elevation
- `[ID: ...]` - stable scenario identifier; every frozen child remains required.

## Fixtures & conventions

- **Standard apps**: open one isolated unpackaged app (prefer `notepad.exe` with a unique temp
  file) and one packaged app (Calculator, Windows Terminal, or Settings). Avoid the user's existing
  VS Code and browser profiles, ODBC dialogs, and Control Panel pages: they reuse shared processes
  or create detached windows that can remain after the case.
- **Elevation fixture**: open a separate app with **Run as administrator**. Use an admin-capable
  Win32 app whose executable path is stable.
- **State fixture**: place the apps at visibly different coordinates; minimize one app and leave
  another restored. For position assertions, record each window rectangle before capture.
- **Multi-monitor fixtures**: the two-monitor items require two displays. The mixed-DPI item requires
  different scale factors (for example, 100% and 150%).
- **PWA fixture**: install an Edge or Chrome PWA in a non-default browser profile and record the
  profile and app identity.
- **State hygiene**: back up the Workspaces data and module settings before the run. For every case,
  record each exact fixture PID/HWND as it is launched, then close only those tracked fixtures in
  a `finally` block. Remove that case's temp files, shortcuts, and disposable workspace before
  moving on. Restore the activation shortcut and module state at final wrap-up.

- See the [module profile](../modules/workspaces.md) and [frozen inventory](../assertion-inventories/workspaces.json) for operating guidance and fixed assertions.

## Workspaces (38 items)

### Settings and entry points

- [ ] **Settings entry** [ID: WS01] [ADMIN: NO]
  Enable Workspaces, open Settings → Workspaces, click **Launch editor**, and confirm exactly one window titled **Workspaces Editor** opens and shows the workspace list.

- [ ] **Quick Access entry** [ID: WS02] [ADMIN: NO]
  Open PowerToys Quick Access, select **Workspaces**, and confirm the same **Workspaces Editor** window opens.

- [ ] **Default shortcut** [ID: WS03] [ADMIN: NO]
  With the default activation shortcut shown in Settings, close the editor, press that exact chord, and confirm **Workspaces Editor** opens.

- [ ] **Change the activation shortcut** [ID: WS04] [ADMIN: NO]
  Change the activation shortcut to an unused chord, save it, and confirm the new chord opens the editor while the previous chord no longer does. Restore the original chord afterward.

- [ ] **Disabled and re-enabled entry points** [ID: WS05] [ADMIN: NO]
  Disable Workspaces and confirm **Launch editor** is disabled, the activation shortcut does not open the editor, Quick Access has no usable Workspaces launch action, and Command Palette still exposes **Workspaces settings** but not **Open Workspaces editor** or per-workspace results. Re-enable Workspaces and confirm Settings, Quick Access, the configured shortcut, and Command Palette results work again without restarting Windows.

- [ ] **Clean-install default** [ID: WS06] [ADMIN: YES]
  On a clean installation or clean user profile with no existing PowerToys `settings.json`, start PowerToys and open Settings. Confirm Workspaces is **disabled from first render** and never briefly starts/enables before Settings persists its defaults.

### Snapshot and capture

- [ ] **Snapshot capture and save** [ID: WS07] [ADMIN: NO]
  Prepare two restored apps at recorded non-zero rectangles, one packaged app maximized, and one minimized app. Click **Create Workspace**, open one restored fixture only after Snapshot Creator is waiting, then click **Capture**. Confirm every app present at Capture time appears once; the late app is included; restored apps expose matching **Left**, **Top**, **Width**, and **Height** values; minimized/maximized states and the preview are correct. Save with a unique name and confirm one card appears with that name, the correct app count, and all app icons/previews.

- [ ] **Elevated application capture** [ID: WS08] [ADMIN: COND]
  With an elevated fixture app open, capture once with PowerToys non-elevated and once with PowerToys elevated. Confirm the elevated app is omitted from the non-elevated capture, but appears in the elevated capture with **Launch as administrator** checked.

- [ ] **Cancel capture** [ID: WS09] [ADMIN: NO]
  Record the workspace count, click **Create Workspace**, then **Cancel** in Snapshot Creator. Confirm the editor returns to the list and the count and persisted Workspaces data are unchanged.

- [ ] **Mixed-DPI capture overlays** [ID: WS10] [ADMIN: NO]
  On two monitors with different DPI scale factors, click **Create Workspace** and inspect the capture overlays. Confirm each overlay exactly covers its monitor's bounds with no scaled offset, gap, overlap, or spill onto the other display.

### Workspace list

- [ ] **Workspace search** [ID: WS11] [ADMIN: NO]
  Create two workspaces with distinct names and app sets. Search by a substring of one workspace name and then by an application name contained in only one workspace; for each query confirm only the matching card remains, then clear Search and confirm the full list returns.

- [ ] **Sort order and persistence** [ID: WS12] [ADMIN: NO]
  Create workspaces with known names, creation order, and launch history. Confirm **Last launched** sorts newest-first, **Created** sorts newest-first, and **Name** sorts alphabetically ascending. Leave a non-default sort selected, close every editor window, reopen, and confirm the selection and card order persist.

- [ ] **Remove a workspace** [ID: WS13] [ADMIN: NO]
  Open a workspace card's **More** menu, choose **Remove**, and confirm the card is removed immediately without a confirmation prompt. Verify its record is removed from the Workspaces data while other workspaces remain.

- [ ] **Edit-page entry paths** [ID: WS14] [ADMIN: NO]
  For one workspace, choose More -> Edit and confirm its correct name and applications. Return to the list and click a different workspace card's body, not Launch or More; confirm that different workspace opens for editing. Observe both routes independently.

- [ ] **Workspace list layout** [ID: WS16] [ADMIN: NO]
  Resize the editor wide and narrow with enough workspaces to scroll. Confirm cards stretch to the available content width, their **Launch** and **More** actions remain reachable, and vertical scrolling does not clip card content or create an unusable nested horizontal scroll area.

### Editing page

- [ ] **Remove and restore an application** [ID: WS17] [ADMIN: NO]
  In a workspace with at least two apps, remove one and confirm its removed-app state and absence from the monitor preview while the other app is unchanged. Then use Add back and confirm the same app returns to its original monitor group and preview position with saved launch properties restored.

- [ ] **Minimized and maximized state** [ID: WS19] [ADMIN: NO]
  Set one restored app to **Minimized** and another to **Maximized**. Confirm their position fields and preview states update appropriately; save, reopen, and confirm both values persist.

- [ ] **Launch as administrator** [ID: WS20] [ADMIN: COND]
  For an admin-capable Win32 app, toggle **Launch as administrator**, save, launch the workspace, approve UAC, and confirm the process is elevated and arranged. Turn the option off, relaunch, and confirm the process is non-elevated and arranged.

- [ ] **Win32 command-line arguments** [ID: WS21] [ADMIN: NO]
  Configure a Win32 app with command-line arguments that open a unique temp file or folder. Save and reopen the workspace to confirm the arguments persist, then launch and confirm the correct process receives them and opens the requested target.

- [ ] **Custom geometry and launch** [ID: WS22] [ADMIN: NO]
  Set an app to **Custom** with known non-zero **Left**, **Top**, **Width**, and **Height** values. Confirm the preview updates immediately; save, close and reopen the editor, and confirm the values did not deserialize as `0,0`. Launch and confirm the real window rectangle matches within normal frame tolerance.

- [ ] **Save renamed workspace and properties** [ID: WS23] [ADMIN: NO]
  Rename a workspace to a unique name and change an app property, then click **Save**. Confirm the editor returns to the list, reopening shows both saved values, the card and existing desktop shortcut use the new name, and the obsolete shortcut name is removed.

- [ ] **Cancel editing** [ID: WS24] [ADMIN: NO]
  Change the name or an app property and click **Cancel**. Confirm the editor returns to the list and reopening the workspace shows the original value.

- [ ] **Discard through breadcrumb** [ID: WS25] [ADMIN: NO]
  Make an unsaved change, click the **Workspaces** breadcrumb, and confirm the editor returns to the main list without persisting the change.

- [ ] **Desktop shortcut lifecycle** [ID: WS26] [ADMIN: NO]
  Check **Create desktop shortcut**, save, and confirm `<workspace name>.lnk` appears and the checkbox is checked after reopening. Close the fixture apps, invoke the shortcut, and confirm it launches the same app set and placement as the editor's **Launch** button. Delete the shortcut, reopen again, and confirm the checkbox is unchecked.

- [ ] **Launch, edit and recapture** [ID: WS27] [ADMIN: NO]
  Use a workspace with enough applications to scroll. Click **Launch and edit**, wait for its apps, open one additional fixture, and click **Capture**. Confirm the additional app is added and existing apps remain represented once each. Resize the editing page wide and narrow and confirm **Save**, **Cancel**, the preview, project properties, and expanded app controls remain reachable without horizontal clipping.

- [ ] **Move existing windows** [ID: WS28] [ADMIN: NO]
  Toggle **Move existing windows**, save, leave a matching app open at the wrong coordinates, and launch. Confirm the existing window moves to the saved rectangle when enabled and remains in place when disabled.

### Launcher

- [ ] **Launch app identities and placement** [ID: WS29] [ADMIN: NO]
  Use a workspace containing an isolated unpackaged Win32 app and a packaged app. Close both, click **Launch**, and confirm each configured app starts exactly once, the correct executable/package identity is used, neither is duplicated, and both windows are moved to their saved states and monitors.

- [ ] **Per-app launch status** [ID: WS30] [ADMIN: NO]
  Launch a workspace containing at least one valid and one intentionally invalid app entry. Confirm **Workspaces Launcher** lists every app and transitions each row through the correct **launching**, **launched**, or **failed/not launched** state.

- [ ] **Cancel launching** [ID: WS31] [ADMIN: NO]
  Launch a multi-app workspace and click **Cancel launch** before completion. Confirm no further apps start, already-opened apps remain open, and the launcher window closes.

- [ ] **Dismiss launcher** [ID: WS32] [ADMIN: NO]
  Launch a multi-app workspace and click **Dismiss** before completion. Confirm the launcher window closes but the remaining apps continue launching to completion.

### Application compatibility

- [ ] **Browser-profile PWA** [ID: WS33] [ADMIN: NO]
  Capture an Edge or Chrome PWA installed in a non-default browser profile, close it, and launch the workspace. Confirm the same PWA and profile open, not a generic browser window or the PWA from another profile.

- [ ] **Elevated packaged app** [ID: WS34] [ADMIN: COND]
  For a packaged app that supports elevation, enable **Launch as administrator**, launch it, approve UAC, and confirm the elevated process/window is associated with the correct workspace entry.

- [ ] **Packaged-app arguments** [ID: WS35] [ADMIN: NO]
  For a packaged app that accepts command-line arguments, configure an observable argument and confirm the launched app applies it.

### Monitor topology

- [ ] **Connect another monitor** [ID: WS36] [ADMIN: NO]
  Capture a workspace while only monitor 1 is connected, then connect monitor 2 and launch. Confirm every app remains on monitor 1 at the captured relative position.

- [ ] **Disconnect a captured monitor** [ID: WS37] [ADMIN: NO]
  Capture apps across two monitors, disconnect one monitor, then launch. Confirm every app is recovered onto the remaining monitor and no window is left off-screen.

### Command Palette integration

- [ ] **Command Palette editor entry** [ID: WS38] [ADMIN: NO]
  With Workspaces enabled, open Command Palette's PowerToys extension and select **Open Workspaces editor**. Confirm exactly one **Workspaces Editor** window opens.

- [ ] **Command Palette workspace result** [ID: WS39] [ADMIN: NO]
  Create a workspace with a unique name and two positioned apps, then reopen Command Palette. Confirm a result with that workspace name appears, reports the correct app count/last-launched state, and its details list both apps; invoking it launches the saved workspace with the persisted positions.

### Fluent UI regression

- [ ] **Fluent themes and layout** [ID: WS40] [ADMIN: NO]
  Switch Windows between Light, Dark, and a High Contrast theme, reopening **Workspaces Editor** and **Workspaces Launcher** after each change. Confirm both use the current system theme, readable Fluent control states, and a Mica/system backdrop where supported, with no legacy ModernWpf/ControlzEx-styled islands or unreadable text.
