# Shortcut Guide - Calculator first-slot fixture

Use the installed Windows Calculator as the routing fixture, not a custom dummy app.
Read the shared [Calculator taskbar helper](../../taskbar-fixtures.md), the module's
[observation rules](../shortcut-guide.md#observation-rules), and its
[fixtures and restoration contract](../shortcut-guide.md#fixtures-and-restoration).

## Setup and slot mapping

1. Require Calculator to be installed and not already open. Preserve existing user windows;
   do not close or reset a user's Calculator. Choose a stable original foreground window
   that will survive the entire scenario and cleanup.
2. Call `New-PtTaskbarFixture -Workspace $workspace`. It captures the original taskbar,
   pins and desktop before opening one Calculator, and tracks its exact frame and content
   process identities. A shared ApplicationFrameHost is not an owned process to terminate.
3. Call `Move-PtTaskbarFixtureToSlot -Fixture $fixture -Slot 1`. Observe
   `Get-PtTaskbarSlots`: Calculator must be the first eligible app, excluding Start/Search.
   Identify at least two other existing app slots for the checklist's three-app layout;
   they need not be new fixtures and are not moved or closed.
4. Keep the foreign app set and relative order unchanged. A persistent conflict stops before
   further input and records expected/actual IDs; do not replace the baseline or restart Explorer.
   No pinning is required. A previously pinned Calculator retains its original pin and gets
   its original position restored during cleanup.

## Held Win+1

Use the original foreground window, not Calculator, to start each hold. Win+1 on an already
foreground Calculator could minimize it instead of proving routing.

`Invoke-PtShortcutGuideHold -Mode Indicators` owns Windows down/up. Inside its callback:

```powershell
Invoke-PtTaskbarSlot -Fixture $fixture -Slot 1 -WhileWindowsHeld `
    -WindowsKey $windowsKey -AllowedForegroundTarget $session.GuideTarget
```

The helper sends only the digit. Observe the exact Calculator HWND foreground, Windows still
held, indicator content visible and Start absent after releasing the digit. Then release
Windows and observe hidden indicators and Start absence. Repeat three cycles. Preserve the
separate no-digit hold/release checks; Win+1 itself suppresses Start.

Input acceptance is not delivery completion. Use the observed slot/foreground and passive
captures, not CLI success or a visible but unclassified SG host. Keep the pointer off the
taskbar so thumbnail hover does not interfere with indicator observations.
If exact Calculator routing succeeds and Windows is still held but the native SG host is
already hidden, retain that state as a product retention failure, not a fixture/setup blocker.

## Restore

In `finally`, release owned input and dismiss owned SG surfaces before
`Remove-PtTaskbarFixture -Fixture $fixture` (or `-ReceiptPath` after interruption).
The helper restores Calculator's original pinned slot if applicable, closes only its
new window, and compares the original taskbar/pins/foreground/pointer. Do not wait for or
kill the shared app host. Restore the parent-owned SG settings and fixtures separately.
Complete Calculator cleanup before closing/replacing the original foreground window.

No dummy-app fallback, registry rewrite, pin/unpin, or Explorer restart is part of this flow.
