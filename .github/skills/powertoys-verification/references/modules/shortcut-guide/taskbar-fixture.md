# Shortcut Guide - controlled first-slot taskbar fixture

Read the main profile's
[observation and restoration rules](../shortcut-guide.md#observation-and-restoration-rules)
before driving this recipe.

For `Win+1`, temporary pinning/reordering of a harmless fixture and restoration are in scope unless
the caller prohibits them. Respect tool approvals and policy. Pinning/reordering is normally
per-user and does not require elevation.

## Fixed helper path

Prefer the shared [owned taskbar fixture](../../taskbar-fixtures.md) with three disposable
windows and distinct explicit AppUserModelIDs. This avoids Calculator's shared host and
pin/unpin mutations entirely. The taskbar captions can all say PowerShell; identify the
windows by AppID plus HWND/PID/start time, never by those captions.

Use `New-PtTaskbarFixture`, `Get-PtTaskbarSlots`,
`Move-PtTaskbarFixtureToSlot`, `Invoke-PtTaskbarSlot`, and
`Remove-PtTaskbarFixture`. Keep all foreign apps' relative order and compare the original
pin files/definitions. Closing the non-pinned owned windows removes their temporary slots.
Native drag is the default transport; WinApp drag remains explicit and must
not be credited merely because its command returned success.

H08's `Invoke-PtShortcutGuideHold -Mode Indicators` owns Windows down/up. Inside its
callback, call `Invoke-PtTaskbarSlot -WhileWindowsHeld -WindowsKey <same-key>
-AllowedForegroundTarget $session.GuideTarget` so only the digit is sent. The extra
identity explicitly authorizes the H08-owned overlay as foreground; it is not a
process-name-based exception for arbitrary windows. Use another owned fixture window as the initial foreground target;
pressing Win+1 when slot one is already foreground can minimize it. Observe the exact
slot-one HWND, still-held key and indicators before release, then hidden indicators and
unchanged routed foreground afterward. Repeat at least three cycles.

Input acceptance is not delivery completion. Preserve pending gesture/endpoint evidence
and wait for actual pointer/order state; do not confuse delayed movement with completed
reorder or silently adopt unexpected pointer coordinates. Keep the pointer away from
taskbar thumbnails for passive callout captures.

The Calculator recipe below is retained as an alternative, not a requirement or an
automatic fallback when the owned fixture reports an error.

## Setup, observation, and restoration

1. Save taskbar app identities, pin status, order, button rectangles, and a screenshot. Capture
   fixture ownership and the restoration baseline before mutation. Do not proceed unless the
   original order can be identified and restored.
2. If using the Calculator alternative, require no user-owned Calculator window. Track the new content HWND, owner PID,
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
