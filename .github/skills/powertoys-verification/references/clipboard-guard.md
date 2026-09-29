# Shared clipboard guard

Use `scripts\pt-clipboard-session.ps1` for a shared-desktop run. It keeps the original
in memory in a separate STA **keeper process**, accessed through a current-user-only named
pipe. Ordinary controller exceptions/exits do not dispose that backup. It uses the native
primitive in `pt-clipboard-guard.ps1`/`.cs`, originally ported from the Color Picker branch
(commit `d2d38babc3`), not a second recorder or lifecycle framework.
The WIP recorder and [shared contracts](helper-workflow.md) remain authoritative.

Importing the helper does not access the clipboard. `Initialize-PtClipboardGuard` compiles
the local native source only. `New-PtClipboardSession -Workspace` starts the keeper,
checks its PID/start-time handshake and explicitly requests capture.

| API | Contract |
|---|---|
| `New-PtClipboardSession -Workspace` | Capture supported formats eagerly in a separate STA keeper. Persist only its identity, sequence/pending status and recovery endpoint; never clipboard payload. |
| `Connect-PtClipboardSession -ReceiptPath` | Reconnect to that still-live keeper and observe its status; reconnects matching release obligations after opening the original resource session. |
| `New-PtClipboardGuard -OwnerHwnd` | Low-level in-process primitive for disposable fixtures or an explicit keeper. It cannot survive its process exit. Unsupported formats/handles or oversized data fail before any write. |
| `$guard.AssertUnchanged()` | Check the current sequence against the last acknowledged write; does not grant ownership of new data. |
| `Invoke-PtClipboardWrite -Guard -WriterProcessId -WriterStartTicks -Action` | Prepare before the copy, execute once, seal the resulting sequence before reacquiring the lock, then confirm. No automatic action replay. |
| `$guard.ConfirmWrite()` | Retry confirmation of an already sealed action. Require the original sealed sequence and exact writer PID/start; do not replace them with a later observation. |
| `Register-PtClipboardWrite -Guard -BeforeSequence -WriterProcessId -WriterStartTicks` | Legacy just-observed acknowledgment. No pending-action recovery if its lock acquisition fails; use the composed write API for new runs. |
| `$guard.Restore()` | Confirm a sealed pending action if needed, then compare/restore/read back under the lock. Unknown writes fail rather than overwrite. Partial restore failures retain the original buffers. |
| `Assert-PtClipboardRestored -Guard` | Gate subsequent writer shutdown/disposal explicitly. Throws for false/unknown restoration; no implicit lifecycle action. |
| `$guard.Dispose()` | Free the original and close a keeper only after restoration. A keeper always refuses unresolved disposal, even outside a resource session. |

Inside a recorded case, use this pattern. Pass the actual application writer, not the
keeper PID. The action must wait for its copy to complete, without retrying the copy.
An asynchronously scheduled copy that has not yet written cannot be sealed as complete.

```powershell
$guard = New-PtClipboardSession -Workspace $workspace
$failure = $null
try {
    Invoke-PtClipboardWrite -Guard $guard -WriterProcessId $writerPid `
        -WriterStartTicks $writerStartTicks -Action $oneCopyAndCompletionObservation
} catch {
    $failure = $_
} finally {
    try {
        $guard.Restore()
        Assert-PtClipboardRestored -Guard $guard
        $guard.Dispose()
    } catch {
        if ($failure) { $failure.Exception.Data['ClipboardCleanupFailure'] = $_.Exception.Message }
        else { $failure = $_ }
        $failure.Exception.Data['ClipboardRecoveryReceipt'] = $guard.Path
    }
}
if ($failure) { throw $failure }
```

Retain the keeper/provider if restore fails; do not terminate it, delete its receipt,
rebaseline or force cleanup through the gate. Independent cleanup still runs. Reconnect
with `Connect-PtClipboardSession`, inspect `PendingWriteState` and try only the justified
confirmation/restoration; a record of failure is not permission to overwrite changed data.
An active [resource session](session-safety.md) registers the guard owner and original
provider automatically; `Close-PtTrackedWindow` and module disable/restart enforce its
release dependencies. `Assert-PtClipboardRestored` persists successful native restoration.
Every disable or restart that could destroy delayed clipboard data must follow this ordering,
not only the final cleanup. Declare companion writers too.

| Pending state | Recovery boundary |
|---|---|
| `None` | No unresolved action; restore only the known expected sequence. |
| `Prepared` | Action was authorized but has not sealed completion. If sequence is unchanged, original restoration is safe; a changed sequence is ambiguous. |
| `ConfirmationPending` | Action returned and its resulting sequence was sealed. Confirmation can retry against that exact sequence and writer lifetime; no copy replay. |
| `ActionFailed` | The action threw, possibly after writing. Never promote it to success or infer ownership from the PID alone; a changed sequence remains blocked. |

A keeper is **not durable crash recovery**. Forced termination of the keeper/process tree,
session logoff, host job teardown or reboot destroys its memory. No disk copy of private
clipboard data is created. A dead keeper's receipt cannot recover the original. This
mechanism cannot recover the original data lost by the earlier failed test.

Supported data includes Unicode/ANSI text, bitmap/DIB, file-list, locale and registered
HGLOBAL formats such as HTML/RTF/PNG. An unusable remote CF_BITMAP can be materialized
from the same sequence's PNG; `BitmapFromPng` records that conversion. Unsupported
handles, changed sequences or invalid PNG data are errors, never silent text-only backups.

Sequence and owner checks cannot detect every interleaving writer or distinguish writers
within the same process before sealing. A later same-PID write changes the sealed sequence
and is rejected. No guard authorizes sharing the clipboard concurrently with another
test/controller. Bytes are not serialized into the report; record only status, supported
format metadata, sequence provenance and sanitized case outputs.

Native lock acquisition retries only `ERROR_ACCESS_DENIED` contention for at most 500 ms.
It does not replay the copy action, acknowledge an unknown write or weaken sequence checks.
Other native errors fail immediately. Lock failures include the native error code and
best-effort lock-holder HWND/PID (zero means unknown); the lock holder is not necessarily
the clipboard data owner. Keeper responses/receipts preserve this metadata.

`Test-PtClipboardRecovery.ps1` substitutes **all** native clipboard entry points and
tests contention, sealed confirmation, foreign writes, action errors and partial restore.
`Test-PtClipboardKeeper.ps1` exercises actual controller exit/reconnection with a fake
native clipboard in the keeper. Neither accesses the system clipboard.
Live acceptance now requires explicit `-DisposableClipboard`; use an isolated disposable
session. `Test-PtSessionDesktop.ps1 -SkipClipboard` does not access clipboard data.
Keeper WinForms/message-pump behavior and real rich-format recovery still require that
isolated live acceptance; offline success is not a completed module sign-off.

When integrating with `Invoke-PtVerificationCase`, do not return or serialize the guard,
private original payloads or backup objects as observation artifacts. Register restoration
evidence only after the explicit comparison; a PASS covers this clipboard scope, not
the entire desktop or other modules.
