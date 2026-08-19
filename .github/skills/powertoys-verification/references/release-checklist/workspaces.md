# Workspaces — PowerToys release checklist

> Source: consolidated from the earlier Workspaces baseline and current user-observable behavior.
> One module per file.

## Legend

Each item is annotated with an admin-requirement tag:

**Admin requirement**:
- `[ADMIN: NO]` - runnable from a standard (non-elevated) shell
- `[ADMIN: YES]` - requires an elevated session (clean install, elevated PowerToys, or UAC-approved launch)
- `[ADMIN: COND]` - basic case is non-admin, but the stated variant requires elevation

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

---

## Workspaces (40 items)

### Settings and entry points

- [ ] **[ADMIN: NO]** (L905) Enable Workspaces, open Settings → Workspaces, click **Launch editor**, and confirm exactly one window titled **Workspaces Editor** opens and shows the workspace list.
- [ ] **[ADMIN: NO]** (L906) Open PowerToys Quick Access, select **Workspaces**, and confirm the same **Workspaces Editor** window opens.
- [ ] **[ADMIN: NO]** (L907) With the default activation shortcut shown in Settings, close the editor, press that exact chord, and confirm **Workspaces Editor** opens.
- [ ] **[ADMIN: NO]** (L907) Change the activation shortcut to an unused chord, save it, and confirm the new chord opens the editor while the previous chord no longer does. Restore the original chord afterward.
- [ ] **[ADMIN: NO]** (L908, #44006) Disable Workspaces and confirm **Launch editor** is disabled, the activation shortcut does not open the editor, Quick Access has no usable Workspaces launch action, and Command Palette still exposes **Workspaces settings** but not **Open Workspaces editor** or per-workspace results. Re-enable Workspaces and confirm Settings, Quick Access, the configured shortcut, and Command Palette results work again without restarting Windows.
- [ ] **[ADMIN: YES]** (#47144) On a clean installation or clean user profile with no existing PowerToys `settings.json`, start PowerToys and open Settings. Confirm Workspaces is **disabled from first render** and never briefly starts/enables before Settings persists its defaults.

### Snapshot and capture

- [ ] **[ADMIN: NO]** (L910-L919, L923) Prepare two restored apps at recorded non-zero rectangles, one packaged app maximized, and one minimized app. Click **Create Workspace**, open one restored fixture only after Snapshot Creator is waiting, then click **Capture**. Confirm every app present at Capture time appears once; the late app is included; restored apps expose matching **Left**, **Top**, **Width**, and **Height** values; minimized/maximized states and the preview are correct. Save with a unique name and confirm one card appears with that name, the correct app count, and all app icons/previews.
- [ ] **[ADMIN: COND]** (L910-L920) With an elevated fixture app open, capture once with PowerToys non-elevated and once with PowerToys elevated. Confirm the elevated app is omitted from the non-elevated capture, but appears in the elevated capture with **Launch as administrator** checked.
- [ ] **[ADMIN: NO]** (L924) Record the workspace count, click **Create Workspace**, then **Cancel** in Snapshot Creator. Confirm the editor returns to the list and the count and persisted Workspaces data are unchanged.
- [ ] **[ADMIN: NO]** (#45183) On two monitors with different DPI scale factors, click **Create Workspace** and inspect the capture overlays. Confirm each overlay exactly covers its monitor's bounds with no scaled offset, gap, overlap, or spill onto the other display.

### Workspace list

- [ ] **[ADMIN: NO]** (L925) Create two workspaces with distinct names and app sets. Search by a substring of one workspace name and then by an application name contained in only one workspace; for each query confirm only the matching card remains, then clear Search and confirm the full list returns.
- [ ] **[ADMIN: NO]** (L926-L927) Create workspaces with known names, creation order, and launch history. Confirm **Last launched** sorts newest-first, **Created** sorts newest-first, and **Name** sorts alphabetically ascending. Leave a non-default sort selected, close every editor window, reopen, and confirm the selection and card order persist.
- [ ] **[ADMIN: NO]** (L928) Open a workspace card's **More** menu, choose **Remove**, and confirm the card is removed immediately without a confirmation prompt. Verify its record is removed from the Workspaces data while other workspaces remain.
- [ ] **[ADMIN: NO]** (L929) Open a workspace card's **More** menu and choose **Edit**. Confirm the editing page opens for the selected workspace and shows its correct name and applications.
- [ ] **[ADMIN: NO]** (L930) Click the body of a different workspace card, not its Launch or More buttons. Confirm the editing page opens for that card's workspace.
- [ ] **[ADMIN: NO]** (#46172) Resize the editor wide and narrow with enough workspaces to scroll. Confirm cards stretch to the available content width, their **Launch** and **More** actions remain reachable, and vertical scrolling does not clip card content or create an unusable nested horizontal scroll area.

### Editing page

- [ ] **[ADMIN: NO]** (L933) In a workspace containing at least two apps, click **Remove** for one app. Confirm it moves to the removed-app state and disappears from the monitor preview while the other app remains unchanged.
- [ ] **[ADMIN: NO]** (L934) Click **Add back** for the removed app. Confirm it returns to its original monitor group and position in the preview with its saved launch properties restored.
- [ ] **[ADMIN: NO]** (L935-L936) Set one restored app to **Minimized** and another to **Maximized**. Confirm their position fields and preview states update appropriately; save, reopen, and confirm both values persist.
- [ ] **[ADMIN: COND]** (L937, L956) For an admin-capable Win32 app, toggle **Launch as administrator**, save, launch the workspace, approve UAC, and confirm the process is elevated and arranged. Turn the option off, relaunch, and confirm the process is non-elevated and arranged.
- [ ] **[ADMIN: NO]** (L938, L957) Configure a Win32 app with command-line arguments that open a unique temp file or folder. Save and reopen the workspace to confirm the arguments persist, then launch and confirm the correct process receives them and opens the requested target.
- [ ] **[ADMIN: NO]** (L939, #44704) Set an app to **Custom** with known non-zero **Left**, **Top**, **Width**, and **Height** values. Confirm the preview updates immediately; save, close and reopen the editor, and confirm the values did not deserialize as `0,0`. Launch and confirm the real window rectangle matches within normal frame tolerance.
- [ ] **[ADMIN: NO]** (L940-L941) Rename a workspace to a unique name and change an app property, then click **Save**. Confirm the editor returns to the list, reopening shows both saved values, the card and existing desktop shortcut use the new name, and the obsolete shortcut name is removed.
- [ ] **[ADMIN: NO]** (L941) Change the name or an app property and click **Cancel**. Confirm the editor returns to the list and reopening the workspace shows the original value.
- [ ] **[ADMIN: NO]** (L942) Make an unsaved change, click the **Workspaces** breadcrumb, and confirm the editor returns to the main list without persisting the change.
- [ ] **[ADMIN: NO]** (L943-L944, L949) Check **Create desktop shortcut**, save, and confirm `<workspace name>.lnk` appears and the checkbox is checked after reopening. Close the fixture apps, invoke the shortcut, and confirm it launches the same app set and placement as the editor's **Launch** button. Delete the shortcut, reopen again, and confirm the checkbox is unchecked.
- [ ] **[ADMIN: NO]** (L945, #46172) Use a workspace with enough applications to scroll. Click **Launch and edit**, wait for its apps, open one additional fixture, and click **Capture**. Confirm the additional app is added and existing apps remain represented once each. Resize the editing page wide and narrow and confirm **Save**, **Cancel**, the preview, project properties, and expanded app controls remain reachable without horizontal clipping.
- [ ] **[ADMIN: NO]** Toggle **Move existing windows**, save, leave a matching app open at the wrong coordinates, and launch. Confirm the existing window moves to the saved rectangle when enabled and remains in place when disabled.

### Launcher

- [ ] **[ADMIN: NO]** (L948, L955, L959) Use a workspace containing an isolated unpackaged Win32 app and a packaged app. Close both, click **Launch**, and confirm each configured app starts exactly once, the correct executable/package identity is used, neither is duplicated, and both windows are moved to their saved states and monitors.
- [ ] **[ADMIN: NO]** (L950) Launch a workspace containing at least one valid and one intentionally invalid app entry. Confirm **Workspaces Launcher** lists every app and transitions each row through the correct **launching**, **launched**, or **failed/not launched** state.
- [ ] **[ADMIN: NO]** (L951) Launch a multi-app workspace and click **Cancel launch** before completion. Confirm no further apps start, already-opened apps remain open, and the launcher window closes.
- [ ] **[ADMIN: NO]** (L952) Launch a multi-app workspace and click **Dismiss** before completion. Confirm the launcher window closes but the remaining apps continue launching to completion.

### Application compatibility

- [ ] **[ADMIN: NO]** (L958) Capture an Edge or Chrome PWA installed in a non-default browser profile, close it, and launch the workspace. Confirm the same PWA and profile open, not a generic browser window or the PWA from another profile.
- [ ] **[ADMIN: COND]** (L960) For a packaged app that supports elevation, enable **Launch as administrator**, launch it, approve UAC, and confirm the elevated process/window is associated with the correct workspace entry.
- [ ] **[ADMIN: NO]** (L961) For a packaged app that accepts command-line arguments, configure an observable argument and confirm the launched app applies it.

### Monitor topology

- [ ] **[ADMIN: NO]** (L964) Capture a workspace while only monitor 1 is connected, then connect monitor 2 and launch. Confirm every app remains on monitor 1 at the captured relative position.
- [ ] **[ADMIN: NO]** (L965) Capture apps across two monitors, disconnect one monitor, then launch. Confirm every app is recovered onto the remaining monitor and no window is left off-screen.

### Command Palette integration

- [ ] **[ADMIN: NO]** (#44006) With Workspaces enabled, open Command Palette's PowerToys extension and select **Open Workspaces editor**. Confirm exactly one **Workspaces Editor** window opens.
- [ ] **[ADMIN: NO]** (#44006, #44704) Create a workspace with a unique name and two positioned apps, then reopen Command Palette. Confirm a result with that workspace name appears, reports the correct app count/last-launched state, and its details list both apps; invoking it launches the saved workspace with the persisted positions.

### Fluent UI regression

- [ ] **[ADMIN: NO]** (#46172) Switch Windows between Light, Dark, and a High Contrast theme, reopening **Workspaces Editor** and **Workspaces Launcher** after each change. Confirm both use the current system theme, readable Fluent control states, and a Mica/system backdrop where supported, with no legacy ModernWpf/ControlzEx-styled islands or unreadable text.
