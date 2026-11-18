# Shared clipboard guard

Use `scripts\pt-clipboard-session.ps1`. Its default **Preserve** policy keeps the original
in memory in a separate STA **keeper process**, accessed through a current-user-only named
pipe. Ordinary controller exceptions/exits do not dispose that backup. It uses the native
primitive in `pt-clipboard-guard.ps1`/`.cs`, originally ported from the Color Picker branch
(commit `d2d38babc3`), not a second recorder or lifecycle framework.
The WIP recorder and [shared contracts](helper-workflow.md) remain authoritative.

Importing the helper does not access the clipboard. `Initialize-PtClipboardGuard` compiles
the local native source only. `New-PtClipboardSession -Workspace` starts the keeper,
checks its PID/start-time handshake and explicitly requests capture. **Disposable** policy
starts no keeper, captures no formats and requires no original-content restoration.

## Select the policy before clipboard access

When the caller explicitly says the target test session's clipboard is disposable, select
`Disposable` without asking again. Record that authority as `Reason`; a machine merely being
called a dev/test machine is not permission to discard other resources. Otherwise retain
the default `Preserve`. Neither mode authorizes changing unrelated windows, files, settings or GPO.
Clipboard restore/keeper recipes in module profiles describe Preserve mode; use policy-aware
cleanup for an explicitly Disposable session without weakening any other preservation requirement.

Declare one `Clipboard` resource with `Policy='Disposable'` and `Reason` in the original
resource plan; `New-PtClipboardSession` inherits it. Explicit arguments cannot override a
different frozen plan. Without a resource plan, use:

```powershell
$guard = New-PtClipboardSession -Workspace $workspace -Policy Disposable `
    -Reason 'Caller explicitly permits disposable clipboard contents for this test session'
try {
    # Seed known fixture contents; do not rely on whatever was already on the clipboard.
    Invoke-PtClipboardWrite -Guard $guard -WriterProcessId $writerPid `
        -WriterStartTicks $writerStartTicks -Action $publishAndWaitForCompletion `
        -Observe $verifyTargetAndRecordEvidence
} finally {
    Complete-PtClipboardSession -Guard $guard
}
```

Disposable cleanup leaves the current clipboard untouched. Its disposition is `NotPreserved`,
not `Restored`; failed actions remain failures but create no preservation dependency on
writer shutdown. A new case gets a new guard and known fixture data, not a replay of an
uncertain action.

| API | Contract |
|---|---|
| `New-PtClipboardSession -Workspace [-Policy Preserve/Disposable -Reason ...]` | Preserve by default through an STA keeper. Explicit Disposable policy creates an in-process sequence guard only; no payload capture, owner window or keeper. |
| `Connect-PtClipboardSession -ReceiptPath` | Reconnect to that still-live keeper and observe its status; reconnects matching release obligations after opening the original resource session. |
| `New-PtClipboardGuard -OwnerHwnd` | Low-level preserving primitive for an owned window or keeper. It cannot survive its process exit. Unsupported formats/handles or oversized data fail before any write. |
| `$guard.AssertUnchanged()` | Check the current sequence against the last acknowledged write; does not grant ownership of new data. |
| `Invoke-PtClipboardWrite -Guard -WriterProcessId -WriterStartTicks -Action [-Observe -ObservationArgumentList]` | Publish once, seal and confirm, then invoke optional observation outside the transaction. Returns action output followed by observer output; no action replay. |
| `$guard.ConfirmWrite()` | Retry confirmation of an already sealed action. Require the original sealed sequence and exact writer PID/start; do not replace them with a later observation. |
| `Register-PtClipboardWrite -Guard -BeforeSequence -WriterProcessId -WriterStartTicks` | Legacy just-observed acknowledgment. No pending-action recovery if its lock acquisition fails; use the composed write API for new runs. |
| `$guard.Restore()` | Confirm a sealed pending action if needed, then compare/restore/read back under the lock. Unknown writes fail rather than overwrite. Partial restore failures retain the original buffers. |
| `Assert-PtClipboardRestored -Guard` | Gate subsequent writer shutdown/disposal explicitly. Throws for false/unknown restoration; no implicit lifecycle action. |
| `Assert-PtClipboardResolved -Guard` | Accept actual restoration, explicit `DiscardedByPolicy`, or declared Disposable `NotPreserved`. This does not certify restored bytes. |
| `Complete-PtClipboardSession -Guard` | Restore in Preserve mode; skip restoration in Disposable mode. Dispose and verify keeper exit when present. |
| `Complete-PtClipboardSession -Guard -DiscardOriginal -Reason ...` | Explicitly discard a saved original without writing the current clipboard, record the reason, resolve only its release dependency, and close its keeper. |
| `$guard.Dispose()` | Free the snapshot after restoration or explicit discard; Disposable guards have no snapshot. Preserving keepers refuse unresolved disposal, even outside a resource session. |

Inside a recorded case, use this pattern. Pass the actual application writer, not the
keeper PID. `Action` must contain only publication and the minimum completion handshake.
An asynchronously scheduled copy that has not yet written cannot be sealed as complete.
Put target UIA assertions, screenshots and reporting in `Observe` or a later recorded step.
An observer exception then propagates without calling `FailWrite` on an already confirmed write.

```powershell
$guard = New-PtClipboardSession -Workspace $workspace
$failure = $null
try {
    Invoke-PtClipboardWrite -Guard $guard -WriterProcessId $writerPid `
        -WriterStartTicks $writerStartTicks -Action $oneCopyAndCompletionHandshake `
        -Observe $verifyTargetAndRecordEvidence
} catch {
    $failure = $_
} finally {
    try {
        Complete-PtClipboardSession -Guard $guard
    } catch {
        if ($failure) { $failure.Exception.Data['ClipboardCleanupFailure'] = $_.Exception.Message }
        else { $failure = $_ }
        $failure.Exception.Data['ClipboardRecoveryReceipt'] = $guard.Path
    }
}
if ($failure) { throw $failure }
```

In Preserve mode, retain the keeper/provider if restore fails unless the caller explicitly
authorizes discarding that original. Do not delete its receipt, silently rebaseline or force
cleanup through the gate. Independent cleanup still runs. Reconnect
with `Connect-PtClipboardSession`, inspect `PendingWriteState` and try only the justified
confirmation/restoration; a record of failure is not permission to overwrite changed data.
An active [resource session](session-safety.md) registers the guard owner and original
provider automatically; `Close-PtTrackedWindow` and module disable/restart enforce its
release dependencies. `Assert-PtClipboardRestored` persists successful native restoration.
Every disable or restart that actually affects a protected owner/writer must follow this
ordering, not only final cleanup. A historical receipt alone does not block unrelated Runner
startup; identify the live process/resource dependency. Declare companion writers too.

## Explicitly retire an unwanted backup

For an existing preserving keeper, reconnect to its exact receipt and use
`Complete-PtClipboardSession -Guard $guard -DiscardOriginal -Reason $callerAuthority`.
Both the switch and a nonblank reason are required. This operation drops only the saved
snapshot; it neither clears the current clipboard nor terminates application writers.
The receipt and resource completion retain `Restored=false`, `Disposition=DiscardedByPolicy`,
the reason and the original pending/error state. Do not relabel an earlier failed test as PASS.

Older live keepers do not gain commands when their script file is updated. If one rejects
`Discard`, retain that compatibility limitation: no forced-termination fallback is performed.
Any retirement of that old process needs its own explicitly authorized, identity-checked
shutdown. This limitation still does not establish a conflict with unrelated verification.

These states constrain write replay and Preserve-mode restoration, not Disposable cleanup
or an explicitly authorized discard.

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
`Test-PtClipboardKeeper.ps1` exercises actual controller exit/reconnection, explicit discard,
keeper exit and public Disposable creation with fake native clipboard calls. The recovery
suite also covers post-publication observer failure, foreign writes and independent next-case
execution after disposable failures. Neither accesses the system clipboard.
Live acceptance now requires explicit `-DisposableClipboard`; use an isolated disposable
session. `Test-PtSessionDesktop.ps1 -SkipClipboard` does not access clipboard data.
Keeper WinForms/message-pump behavior and real rich-format recovery still require that
isolated live acceptance; offline success is not a completed module sign-off.

When integrating with `Invoke-PtVerificationCase`, do not return or serialize the guard,
private original payloads or backup objects as observation artifacts. Certify restored bytes
only after the explicit comparison. Record `NotPreserved` or `DiscardedByPolicy` as cleanup
dispositions instead; a cleanup PASS covers only that policy, not restored contents,
the entire desktop or other modules.
