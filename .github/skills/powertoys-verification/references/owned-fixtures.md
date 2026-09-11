# Owned Notepad and Explorer fixtures

Load `scripts/pt-owned-fixtures.ps1` or the standard helper bootstrap. These operations
require an unlocked interactive desktop; keep input serial. Use a new local workspace,
not a user document directory. They never terminate a shared process or close a window
selected only by its title.

## Notepad

```powershell
$fixture = $null
try {
    $fixture = New-PtNotepadFixture -Workspace $workspace -Content 'Disposable fixture text'
    Assert-PtForegroundOrAbort -Hwnd $fixture.Identity.hwnd
    # Exercise the module against this target; it may be a tab in a pre-existing window.
} finally {
    if ($fixture) { Remove-PtNotepadFixture -Fixture $fixture }
}
```

Creation snapshots the existing tab identities/selection and native window placement,
creates a uniquely named file, then resolves the **actual** tab/window. The launcher PID
is not ownership. The JSON receipt is written before launch and updated with actual
HWND/PID/start time/class and tab runtime identity.

Removal selects only the owned tab, invokes its scoped close button or uses guarded
Ctrl+W when the modified-tab indicator replaces that button. It restores the original
tab set/selection, placement, foreground and pointer, with comparisons. A new window
containing untracked tabs is preserved rather than closed indiscriminately.

Unsaved content is **not** automatically discarded. For changes made by the test,
explicitly pass `-DiscardFixtureEdits`. The supported WinUI save dialog must expose the
expected `SecondaryButton` named `Don't save`; an unknown/localized dialog remains an
explicit cleanup error. The existing user's modified tabs are never discarded.

After an error, load the saved receipt and retry the same cleanup:

```powershell
$fixture = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
Remove-PtNotepadFixture -Fixture $fixture -DiscardFixtureEdits
```

A pending close or completed tab close is retained in the receipt, so a retry does not
close another tab. A launch that has not yet resolved can retry discovery using its
unique file token. If identity cannot be established, the receipt/file are preserved and
the failure is surfaced; do not kill Notepad or guess a user tab.

## Explorer

```powershell
$fixture = $null
try {
    $fixture = New-PtExplorerFixture -Workspace $workspace
    Assert-PtForegroundOrAbort -Hwnd $fixture.Identity.hwnd
    # This is a unique empty folder in a newly observed Explorer HWND.
} finally {
    if ($fixture) { Remove-PtExplorerFixture -Fixture $fixture }
}
```

Explorer creation uses `/n` and verifies a new HWND displaying the exact fixture path.
Unexpected reuse of a user window is rejected; it does not confer ownership. Cleanup
requires the same native identity and path, requests normal close, waits for that HWND
to disappear, and deletes only the empty owned folder.

If a test creates files in the folder, it must own and remove those explicit files before
folder cleanup, or use the [directory snapshot contract](directory-snapshots.md).
Unknown files are preserved and reported, never recursively deleted. The receipt records
completed window closure, permitting a later folder-cleanup retry without acting on
another Explorer window.

## Boundaries and evidence

Both APIs retain receipts after successful cleanup. `Closed=true` means the recorded
cleanup completed, not a live guarantee against subsequent user changes. Exceptions
retain the receipt path and any additional cleanup error; no failure becomes success.
Desktop restoration is attempted even when tab/file cleanup fails.

Run `scripts/tests/Test-PtOwnedFixtures.ps1 -Workspace <new-folder>` for the interactive
contract suite. It compares the pre-existing Notepad tabs and Explorer paths, exercises
an actual dirty document, and verifies refusal/retry for untracked folder contents.
Different Notepad versions/providers and unexpected Explorer reuse require explicit
evidence before extending these adapters; do not claim universal app/session restoration.
