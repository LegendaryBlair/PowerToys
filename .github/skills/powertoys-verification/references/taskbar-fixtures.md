# Owned taskbar fixtures (H11)

`scripts\pt-taskbar-fixture.ps1` creates three harmless WinForms windows in three
dedicated `pwsh -STA` processes. Each process sets its explicit AppUserModelID before
creating its window: `PowerToys.Verification.H11.<32-hex-token>.<1-based-index>`.
Resolve the **exact** taskbar AutomationId `Appid: <AppUserModelID>`, not the accessible
caption (which can still say PowerShell7). No Calculator, shared app host, pin/unpin,
registry writes, settings changes, Explorer restart, process kill or installed-bit
replacement is involved.

## Public APIs

| API | Contract |
|---|---|
| `New-PtTaskbarFixture -Workspace [-Count 3]` | Existing local workspace; count 1-9. Returns the ownership receipt object, including `ReceiptPath`, `Apps[].AppId` and exact `Apps[].Identity`. |
| `Get-PtTaskbarSlots` | Fresh direct UIA observations: `Taskbar`, `CoordinateSpace`, `ObservedAtUtc`, `Bounds`, and shallow `Apps[]` with `Slot`, `AutomationId`, `AppId`, physical bounds and centers. No full UIA trees or caption-based inference. |
| `Move-PtTaskbarFixtureToSlot -Fixture [-AppIndex 1] [-Slot 1] [-DragMethod Native]` | `Native` or explicit `WinApp`. Moves only the selected owned app. Returns observed `Changed`, `AppId`, `Slot`, `Target`, `DragMethod`, changed-order identities, Native `Pointer` facts and `PointerCleanup` facts. Already-correct placement is a read-only no-op. |
| `Invoke-PtTaskbarSlot -Fixture [-Slot 1] [-WhileWindowsHeld] [-WindowsKey 0x5B] [-AllowedForegroundTarget <H02 identity>]` | Windows key is `0x5B` or `0x5C`. The optional foreground target is legal only while Windows is held. Returns observed mapping, exact target/foreground HWND, previous foreground and Windows-key facts, **not a product PASS**. |
| `Remove-PtTaskbarFixture -Fixture` or `-ReceiptPath` | Closes only identity-checked owned HWNDs, waits for their dedicated processes to exit normally, attempts every resource, restores a conflict-free desktop and always compares the original taskbar baseline. Retains receipts/state/evidence. |

Dot-source the library once. Use the standard H09 case/step recorder and optional H10
operation boundary around these calls; there is no second recorder. Slot observations
are direct read-only UIA calls, while WinApp drag uses the existing `Invoke-PtWinApp`
wrapper. The receipt retains the latest operation and pending mutation; the caller's
normal recorded steps retain earlier observations/errors. Capture pixels separately
with `Save-PtPassiveScreenshot` when the module's assertion requires rendered evidence.

```powershell
. "$skill\scripts\pt-taskbar-fixture.ps1"
$fixture = $null
try {
    $fixture = New-PtTaskbarFixture -Workspace $workspace
    Move-PtTaskbarFixtureToSlot -Fixture $fixture -AppIndex 1 -Slot 1
    # Parent owns SG setup, foreground baseline and all live observations.
    Invoke-PtTaskbarSlot -Fixture $fixture -Slot 1
} finally {
    if ($fixture) { Remove-PtTaskbarFixture -ReceiptPath $fixture.ReceiptPath }
}
```

For an existing left/right Windows-key hold, call
`Invoke-PtTaskbarSlot -Fixture $fixture -Slot 1 -WhileWindowsHeld -WindowsKey 0x5B`
inside that hold. It checks that exactly that Windows key is down, rejects other
held modifiers/buttons/digits, rechecks the owned slot immediately before sending,
and sends **only the digit**. It never releases the outer Windows key or forces
foreground after routing. Ordinary invocation uses `Invoke-PtHeldKeys` for its own
Windows-key scope. An already-foreground target is rejected because Win+digit could
minimize it instead of routing. Release the parent's hold and close parent-owned SG
surfaces before fixture cleanup.

When a caller-owned overlay is foreground during that hold, explicitly pass its H02
window identity with `-AllowedForegroundTarget` (for H08, `$session.GuideTarget`).
The helper validates the exact live identity and requires that it is current foreground
both on admission and immediately before the digit. Only this routing operation's
pre-input guards admit it; no process-name discovery, focus forcing, fixture ownership
or global foreground permission is inferred. Slot ownership and already-foreground
rejection remain unchanged. After routing, only the exact owned slot HWND can satisfy
the foreground observation. The parent retains overlay cleanup responsibility.

## Ownership, guards and recovery

Creation captures `Get-PtDesktopSnapshot` and `Get-PtShortcutGuideTaskbarSnapshot`
**before launching**. The latter includes app identity order, pin-file hashes and
read-only raw Taskband evidence. An immutable hashed marker holds these baselines.
Same-directory atomic JSON writes persist the receipt and each launch/drag/route/close
intent before its mutation. The child waits for its exact PID/start-time launch
permission in that receipt before creating a window and atomically publishes its
actual HWND/PID/start time/AppUserModelID after showing it.

Every mutation validates the receipt, marker, exact native identities and fresh app
mapping. Mutation from a stale/edited in-memory object is rejected; reload the saved
receipt for recovery. Marker hashes catch accidental mismatch/tampering; these local
files are not a security boundary against someone who can rewrite both the marker
and receipt. Local canonical paths and no reparse points are required. Do not move or
edit the workspace/receipt while the fixture exists.

Only a fully exposed, **single-row horizontal primary taskbar** is supported.
App slots are sorted by physical X, excluding Start/Search and other non-Appid buttons.
Zero/non-finite/overlapping/outside/offscreen rectangles, duplicate/wrong app identities,
secondary/vertical taskbars and unsupported geometry fail closed. Auto-hide, overflow,
virtual desktops, grouped extra windows and providers that omit app buttons are not
supported: a valid exposed tree is not proof that an inaccessible overflow is complete.
The caller must establish that all primary app slots are exposed before live use.
All owned apps must have exactly one actual visible window and one exact app button.
UIA calls are synchronous; polling deadlines do not interrupt a hung provider COM call.
Prepare the intended original foreground before creation. Unexpected foreground,
pointer or original-window changes are checked before further driving as well as
before restoration; these are not silently adopted as fixture-owned changes.

Before and after dragging, filtering out owned IDs must leave the **same foreign app
set and relative order** as the baseline. The source is the fresh owned button center.
For slot 1 the destination is the physical pixel immediately before the first app's
left edge, still inside the taskbar; unavailable space fails before input. Other
destinations use the fresh button's left quarter when moving left, or right quarter
when moving right, clamped to a physical pixel inside that button.
The insertion side, destination identity and coordinates are recorded; no center-drop
retry or alternate gesture is issued. Source identity and geometry are rechecked after persisting intent.
The complete expected order is observed after dragging. A successful CLI exit without
that order is an error, never a setup success.
On failure, `LastOperation.ExpectedOrder`, `ActualOrder` and `OrderObservedAtUtc` retain
the latest successful order observation through cleanup, including a timeout.
The original error also carries these facts in `Exception.Data['PtTaskbarOrder']`.
`ActualOrder` remains null when no post-drag order observation was obtained.
Persisted observation timestamps are typed UTC values before JSON serialization, so
trimming trailing fractional zeros on reload cannot create a false stale-receipt error.

`Native` is the default; `WinApp` remains an explicitly chosen alternative. Neither
method automatically retries or falls back to the other. Native input uses the SDK INPUT union (40 bytes on
64-bit Windows), per-monitor-v2 physical coordinates normalized over the entire virtual
desktop, verified source pointer/left-button down, 60 movement steps at 25 ms, and
release of only an accepted owned left-button down in `finally`. Original errors retain
additional release failures. WinApp owns its own drag injection/release; this helper
checks idle input afterward and does not issue a blind button-up after CLI failure.
Native drag holds the owned button after arriving and polls the requested app order
before releasing. Every observation retains actual order/time and checks foreign order,
owned identities and exact endpoint delivery with the button still down. The order
wait and its endpoint probes are each bounded to four seconds under the standard
polling contract. `OrderVerifiedWhileHeld` records the observation; release and
post-release order are still checked separately. Timeout/error releases in `finally`
and retains diagnostics, without corrective motion or another gesture.
Only the typed `PtTaskbarGeometryUnavailable` error (zero/overlapping/offscreen/outside
app-button rectangles) is deferred inside this already-running held-layout wait.
It increments `GeometryUnavailableCount` and retains `LastGeometryError`, without
replacing the last valid order, using invalid coordinates, or resetting the deadline.
The next valid snapshot must still satisfy all order/identity checks. Ordinary slot
reads and pre-action geometry remain strict; all other errors propagate.
Absolute coordinates target the center of each physical pixel's normalized cell;
virtual dimensions above 65,536 pixels are rejected as not exactly addressable.
Every accepted Native movement is observed at its exact requested point before the
next movement. `Pending.Pointer` retains source/destination, last accepted/observed/read
positions, step and button-acceptance facts. Each verified point updates
`Pending.Pointer.LastObserved`, not the committed desktop baseline. After release
injection, a bounded four-second delivery wait requires the last accepted endpoint
and left-button-up together in two consecutive samples, 25 ms apart. Intermediate
samples on the planned 60-step path remain pending delivery, not foreign-user errors.
Off-path samples and delivery timeouts remain explicit errors. Only settled delivery
advances `LastDesktop.pointer`; `Settled`, `SettleSamples` and `SettlementError` retain
the outcome. Source, destination and final/failed gesture state are atomically
persisted independently of later order/foreground checks.
The movement loop does not perform per-step disk writes. An interrupted process
between these receipt boundaries may still require explicit conflict recovery.
Unexpected coordinates are recorded as observations, never adopted as owned positions
and never accepted using an arbitrary distance tolerance. Use a fresh PowerShell
process after updating the helper so its compiled native type is not stale.
All gestures require exclusive serial desktop ownership: input APIs cannot distinguish
an overlapping physical press of the same key/button during an injected hold.

After a verified drop/release and observed app order, pointer-only cleanup leaves the
taskbar before returning to the SG caller. It restores the captured pre-drag pointer
unless that position is on the taskbar. In that case it uses the current foreground
owned fixture's interior (or the last-created owned fixture when foreground is not
owned), requiring fresh visible/non-minimized bounds and an exact native root-HWND
hit test. An occluded/unavailable interior fails rather than activating another window.
No click, modifier, button release or foreground forcing is added by this cleanup.
Both pre-parking guards revalidate the persisted pending receipt and reuse the Native
endpoint/button settlement wait when that same completed drag still owns the endpoint
baseline and parking has not started. Late points on its recorded 60-step path remain
pending observations; off-path points still fail. This wait neither adopts an
intermediate point nor resets `LastDesktop`, and the ordinary desktop/input guards
still run before parking. `SettleSamples` includes these additional observations.
The single physical `PtDesktop.SetCursorPos` call has its own persisted intent and
bounded four-second, two-sample exact-destination/button-up check. Intermediate cursor
positions remain pending observations, not evidence of user input, and are never
adopted. Failure to settle times out explicitly; pre-action unknown desktop changes
still fail before movement. `LastDesktop` advances only after delivery,
and app order is checked again. `PointerCleanup` records target, actual position and
completion. No-op placement does not move the pointer. Final removal still restores
the original desktop pointer, including a baseline pointer originally on the taskbar.
This removes the hover trigger; the parent still observes thumbnail/indicator pixels.

Failed drags retain the original message, error ID and stack in `Pending.Error` and
`LastOperation.Error`. The latter survives successful cleanup clearing `Pending`, so
cleanup does not erase the original cause if a caller's `finally` also throws.
Failed drive operations retain their pending intent and fault the fixture. Clean it up
before trying a newly created fixture with a different explicit drag method. No hidden
retry, guessed slot, keyboard substitution or product-verdict inference is performed.
Cleanup can restore a persisted, exactly observed and released intermediate Native
point after a partial failure. An unverified movement, unexpected pointer or interrupted receipt
write remains a conflict rather than permission to move a possibly user-controlled cursor.

Cleanup tries every owned window even if another close fails. No shared/name-selected
process is killed, and no unknown window is closed. Process exit, missing state,
recycled PID/HWND, multiple windows, missing launch identity or failed receipt writes
remain explicit errors; unresolved creation and partial cleanup can be retried via
`-ReceiptPath`. A child without persisted launch permission times out without creating
a window. Normal WM_CLOSE has no unsaved-document prompt in this purpose-built host.

Unknown/concurrent foreign order, pins, foreground, original foreground-window
placement/visibility or pointer changes survive with
cleanup conflict errors. Cleanup does not reorder user apps or restore raw Taskband.
The original foreground identity and pointer are restored only when the current
desktop is attributable to the fixture/baseline; already-matching desktop state is
not rewritten. The original foreground window's native snapshot is a conflict guard,
not permission to overwrite a user placement change. This does not restore arbitrary user document content,
window/page state, virtual desktops or user changes made concurrently. Surviving
user windows are never moved, minimized or closed by fixture cleanup.
Windows may choose the original foreground after closing an owned foreground window;
that exact baseline identity with the last owned pointer position is already allowed,
including a `Cleaning` receipt reload. No general foreign-foreground exemption is made.
Cleanup also permits the immutable marker's exact primary-taskbar HWND/PID/start-time/
class identity as the resulting Shell foreground, with live identity validation before
both cleanup guards. This exception is cleanup-local; other Explorer/Shell windows,
recycled identities and unrelated pointer changes remain conflicts.
Guard failures include actual/expected pointer coordinates and foreground-match facts
in the error text retained by cleanup, with full shallow identities in
`Exception.Data['PtTaskbarDesktopConflict']` on the original guard error.

The final `Assert-PtShortcutGuideTaskbarRestored` comparison is mandatory on success,
partial cleanup and repeat removal. It compares original app order and pin definitions,
excluding the existing `FavoritesChanges` bookkeeping exception. After a cleanup
conflict, preserve the receipt and let the desktop owner resolve only the documented
conflict before retrying. Receipts and child state files are retained; no broad delete
or archive operation is performed.

## Offline acceptance and live boundary

```powershell
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtTaskbarFixture.ps1" -Workspace <new-local-folder>
```

The dependency-free offline suite uses fake process/window/UIA/CLI/mouse boundaries and
a fake native keyboard type, never a live desktop or real SendInput call. It checks the
actual INPUT ABI layout without invoking native functions, malformed slots, identity
guards, pre-mutation receipts, no-op/idempotent state, observed reorder requirements,
held/ordinary Windows routing, partial input cleanup, receipt/marker validity and
partial cleanup/conflict retry. `results.json` and `source-hashes.json` are retained.

**Live acceptance belongs to the parent desktop driver.** Offline acceptance does not
prove WinApp/native drag behavior, Windows slot routing, taskbar grouping, timing,
integrity-level compatibility or original-state restoration on an installed desktop.
Parent must observe all three distinct app IDs, establish the requested slots, verify
guarded Win+1 against the exact owned HWND, and compare taskbar/pin/desktop baselines
after removal before crediting the approved H11 behavior.
