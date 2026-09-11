# Explicitly owned directory snapshots

Dot-source `scripts\pt-directory-snapshot.ps1` in PowerShell 7.2+ on Windows. This standalone
helper imports no desktop, recorder or settings helpers. Use it only for explicitly
authorized, small, **quiescent** local test roots; snapshot capture is not authorization
to change product files. Pair rollback with the caller's existing `try`/`finally` workflow.

## API and ownership

```powershell
. "$skill\scripts\pt-directory-snapshot.ps1"
$root = 'D:\fixtures\unique-case'
$limits = @{ MaxFiles = 32; MaxBytes = 1MB; MaxDirectories = 16 }
$before = Get-PtDirectorySnapshot -Path $root @limits
# Persist $before before changing anything: ConvertTo-Json -Depth 8.
$expected = $before
try {
    # Perform only the authorized test's actions, then quiesce its writers.
    # Record the known post-mutation state, including app-regenerated file bytes.
    $expected = Get-PtDirectorySnapshot -Path $root @limits
} finally {
    $receipt = Restore-PtDirectorySnapshot -Snapshot $before -ExpectedState $expected `
        -OwnedRelativePaths @('fixture.bin', 'nested\created.bin') `
        -OwnedRelativeDirectories @('nested', 'empty-test-dir') -OwnRoot @limits
}
```

| Parameter | Contract |
|---|---|
| `Get-PtDirectorySnapshot -Path` | Required absolute local drive path. Root may be absent; its parent must exist. Captures the entire bounded root, not just owned paths. |
| `Restore-PtDirectorySnapshot -Snapshot` | Required original baseline returned by capture, or its `ConvertTo-Json -Depth 8` / `ConvertFrom-Json` round trip. |
| `-ExpectedState` | Required caller-recorded post-mutation snapshot of the same exact root. Do not replace it with a fresh snapshot of an unexplained conflict: that would authorize overwriting the conflict. If actions fail before it is captured, retain the last known expected state; rollback can correctly refuse the unexplained changes. |
| `-OwnedRelativePaths` | **Mandatory** explicit file paths, with exact captured spelling. Pass `@()` when no files are owned. No wildcard, subtree, inferred-diff or implicit parent ownership. |
| `-OwnedRelativeDirectories` | Optional explicit directory paths, default `@()`. Owns only each directory's existence, **not its descendants**. Required to recreate missing parents or remove test-created empty directories. |
| `-OwnRoot` | Optional explicit ownership of root existence. When the baseline root was absent, this declares the root was created for the test. Only removes it when now empty. Also required to recreate a baseline root removed by the test. Never grants ownership of children. |
| `-MaxFiles` | Both functions: default `256`, inclusive nonnegative maximum file count. |
| `-MaxBytes` | Both functions: default `16MB`, inclusive nonnegative maximum total raw file bytes, at most `Int32.MaxValue`. The same limit also bounds each file. |
| `-MaxDirectories` | Both functions: default `256`, inclusive nonnegative maximum descendant directory count (root excluded). |

Limits are caller-adjustable safety bounds, **not performance guarantees**. All three
snapshots (baseline, expected, actual) must fit restore's limits. Exceeding a bound throws;
capture never returns a truncated snapshot. Base64/JSON and in-memory copies use additional
space beyond `MaxBytes`. A zero byte limit supports empty files.

For no mutation, keep `$expected = $before` and explicitly pass
`-OwnedRelativePaths @()`. A matching tree returns an empty `Changes` array without writes.
Repeating a completed restore also performs no writes, even with the original post-state.
If only some owned paths already equal baseline, they are skipped while remaining
expected-post paths are restored.

## Snapshot and receipt shapes

The JSON-round-trippable snapshot is a `PSCustomObject` with exactly these properties:

```text
SchemaVersion: 1
Path: canonical absolute root, no trailing separator
Exists: boolean
Files: [{ RelativePath, Length, Sha256, Base64 }]
Directories: [relative directory path, ...]
```

`Directories` includes **all** descendant directories, so empty directories and the exact
relative file/directory set survive. Root existence is separate. File bytes, including
empty files and binary data, are stored as canonical Base64 with verified length and
SHA256. The schema is strict; dictionary/provider objects are not snapshot inputs.

Successful execution returns a receipt, not just a boolean:

```text
Path
Status: Restored | Partial
WholeTreeMatchesBaseline: boolean
OwnedPathsMatchBaseline: boolean
Changes: [{ RelativePath, Action: WriteFile | RemoveFile | CreateDirectory | RemoveDirectory }]
UnownedDifferences: [{ RelativePath, BaselineKind, ActualKind }]
RetainedDirectories: [{ RelativePath, Reason }]
```

`.` identifies the root **in receipts only**, not in ownership arrays. Unowned additions,
edits, deletions and empty directories are preserved and listed in `UnownedDifferences`.
This includes unowned changes already present in `ExpectedState`; a snapshot diff never
grants ownership. An owned directory still containing unowned entries remains in place
and is listed in `RetainedDirectories`. Its existence mismatch makes
`OwnedPathsMatchBaseline` false. Any remaining difference makes `WholeTreeMatchesBaseline`
false and `Status` `Partial`; do not report a complete restoration from that receipt.

## Conflicts and safety limits

Validate both snapshot schemas, relative paths, Base64, lengths, hashes, ownership and
the current tree **before the first write**. Every owned path must equal baseline
(idempotent no-op) or expected-post state. Anything else is a conflict, including content,
existence, type or name changes. A missing required parent without explicit restoration
ownership is also a conflict. An expected-post directory's children are checked separately;
owning that directory never authorizes removing newly discovered contents.

Plan conflicts throw with **zero writes**, retaining the structured receipt in
`$_.Exception.Data['PtDirectorySnapshotReceipt']`: `Status = Conflict`, `Changes = @()`,
`Conflicts = @({ RelativePath, Reason })`, `WholeTreeMatchesBaseline = $false`, and `Path`.
Invalid/unsupported inputs and filesystem read errors throw useful errors directly.
Do not treat exceptions as success or silently select a fallback baseline.

Supported scope is **bytes, exact relative names, existence and empty directories only**.
Not captured/restored: ACLs, ownership, alternate data streams, timestamps, attributes,
compression, encryption, sparse layout, file identities, app caches or semantic state.
File/directory replacement at the same path and case-only renames between baseline and
expected snapshots are unsupported and rejected. Use ordinary stable-spelling Windows
paths shorter than 260 characters; relative paths are at most 255 characters.

Reject traversal, rooted relative names, invalid/reserved Windows names, trailing
dots/spaces, duplicate/case-duplicate entries or ownership, missing parent entries,
UNC/device/provider roots, drive roots, direct drive children, protected home/system/temp
directories and their ancestors, repository roots, and `.git` path components (including
nested repository markers). These checks do not make arbitrary
user folders safe: the caller must select a narrow authorized fixture root.

Reject **all reparse points**, symlinks, junctions (including dangling ones), files with
multiple hardlinks, and Cloud Files/offline/recall attributes in the root, descendants or
directory ancestors. Cloud Files support is deliberately conservative: even hydrated
reparse files are rejected; there is **no automatic hydration**. Ordinary local hydrated
files with none of those attributes are supported. Capture enumerates one checked
directory at a time without recursive link traversal; native file opens use
`OPEN_REPARSE_POINT` and verify link count before reading/writing bytes.

The helper is **not a filesystem-atomic transaction** and supplies no durable scheduler,
lock or automatic rollback of a failed rollback. Quiesce writers for capture, expected-state
recording and restore. It rechecks each planned path before acting and uses nonrecursive
directory deletion, but another process can still race between check/open/delete, replace
an ancestor, or change already-checked paths. I/O failures or races after the precheck can
leave partial restoration and throw; retain the original snapshots and inspect the failure
before retrying. Expected-state comparisons protect against pre-existing unexplained
changes, not hostile concurrent namespace changes.

## Offline acceptance

```powershell
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtDirectorySnapshot.ps1"
# Optional -Workspace <new-absolute-local-folder-with-existing-parent>
```

No installs or Pester. Tests use only new uniquely named fixture roots, remove those exact
roots, and retain `results.json` plus `evidence.json` in the new workspace. Evidence records
PowerShell version, source SHA256 hashes, per-group outcomes, restoration/conflict receipts
and fixture cleanup. Junction/hardlink tests use only owned local targets; Cloud Files
attribute masks are checked synthetically without opening a cloud location.
