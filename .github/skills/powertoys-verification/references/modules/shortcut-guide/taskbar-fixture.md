# Shortcut Guide - controlled first-slot taskbar fixture

Read the main profile's
[observation and restoration rules](../shortcut-guide.md#observation-and-restoration-rules)
before driving this recipe.

For `Win+1`, temporary pinning/reordering of a harmless fixture and restoration are in scope unless
the caller prohibits them. Respect tool approvals and policy. Pinning/reordering is normally
per-user and does not require elevation.

## Setup, observation, and restoration

1. Save taskbar app identities, pin status, order, button rectangles, and a screenshot. Capture
   fixture ownership and the restoration baseline before mutation. Do not proceed unless the
   original order can be identified and restored.
2. Prefer installed Calculator with no user-owned window. Track the new content HWND, owner PID,
   and start time; never close user windows to make an app single-instance.
3. Pin/reorder through normal taskbar UI, trying UIA before guarded mouse gestures. Re-enumerate
   after layout changes and before each cycle: exactly one fixture window must occupy slot one;
   Start/Search are not app slots. Preserve other apps' relative order.
4. From a consistent foreground window with the guide hidden, drive indicator mode and sample the
   exact fixture HWND, Windows-key state, and callout visibility through number input and release.
   Use the [lifecycle map](../shortcut-guide.md#ui-state-transition-map)'s separate held/released
   assertions and repeat at least three cycles. Record the observation timeout and passive images.
5. In `finally`, release input, dismiss test surfaces, unpin only a newly added fixture pin, close
   only the fixture window, and restore its position if previously pinned. Restore the captured
   settings, window/page state, foreground, and pointer. Compare original app identities/order and
   pin state; preserve unrelated concurrent changes and report conflicts. Restore immediately if
   setup fails.

Do not rewrite Taskband registry data, unpin unrelated apps, or restart Explorer to force ordering.

Use `Get-PtShortcutGuideTaskbarSnapshot` **before launching any fixture app** and
`Assert-PtShortcutGuideTaskbarRestored` after closing it. They capture/compare app identities,
order, pin-file hashes and selected Taskband values; pin/unpin/reordering remains a UI operation.
Never serialize the registry provider object: `Get-PtRegistrySnapshot` captures named values,
types and raw data only. The helper's comparison excludes `FavoritesChanges` bookkeeping.
Record the full jump-list pin status separately when deciding whether a fixture pin is new.

For each held cycle, use `Invoke-PtHeldKeys -Keys 0x5B -Action { ... }`, send only the number
inside that scope, and persist the completed cycle immediately. Wait for indicator **content**
before capture, not only a visible native host. After release, observe settled hidden state and
the foreground identity; an immediate hidden sample alone does not exclude a delayed Start popup.

## Calculator and taskbar mechanics

- Locate `Appid: Microsoft.WindowsCalculator_8wekyb3d8bbwe!App`, right-click, and inspect the current
  jump-list HWND. Invoke `TaskbarPin` only when its label means **Pin to taskbar**; discover the
  **Unpin from taskbar** action for cleanup. Re-resolve popup/button identities after changes.
- If `winapp ui drag` succeeds without moving the icon, use guarded 40-byte x64 mouse `SendInput`
  with DPI-aware absolute virtual-desktop coordinates
  (`MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK`), left-button down verified
  before movement, 60 steps at 25 ms intervals, and button-up in `finally`. Both endpoints must
  belong to the taskbar; use actual button order, not command success, as the setup assertion.
- Calculator's content window can belong to shared `ApplicationFrameHost`. Close only the tracked
  HWND after confirming its owner; never terminate that shared process.
- Compare pinned shortcut files and pin definitions, not Windows' `FavoritesChanges` bookkeeping
  counter. UI restoration can advance that counter; disclose it rather than rewriting the registry.
