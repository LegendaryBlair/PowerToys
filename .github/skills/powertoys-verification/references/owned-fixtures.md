# Owned desktop fixtures

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
expected enabled `SecondaryButton` with the Button role. Its expected name defaults to
`Don't save`; for another UI language, explicitly pass the localized label you verified
in the actual owned-document save dialog:

```powershell
Remove-PtNotepadFixture -Fixture $fixture -DiscardFixtureEdits `
    -DiscardButtonName $verifiedLocalizedDiscardLabel
```

Do not automatically accept whatever text is on `SecondaryButton`. The expected label
does not itself grant discard consent: `-DiscardFixtureEdits` is still required, and the
pending close must retain the exact owned tab identity/name and selection. Unknown,
disabled, ambiguous or mismatched controls remain cleanup errors. The existing user's
modified tabs are never discarded.

After an error, load the saved receipt and retry the same cleanup:

```powershell
$fixture = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
Remove-PtNotepadFixture -Fixture $fixture -DiscardFixtureEdits `
    -DiscardButtonName $verifiedLocalizedDiscardLabel
```

A pending close or completed tab close is retained in the receipt, so a retry does not
close another tab. `DiscardRequested` records dispatch before invoking the discard action;
retries observe completion without replaying it. After the owned tab disappears, cleanup
also waits for its owned window to disappear, checking identity while it remains. A
surviving window is preserved, not force-closed. A launch that has not yet resolved can retry discovery using its
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
requires the same native identity and path, restores the saved pointer while the owned
Explorer is still foregroundable, requests normal close, waits for that HWND
to disappear, and deletes only the empty owned folder.

The ordering matters for a medium-integrity worker returning to an elevated caller:
closing Explorer first can reactivate that caller, after which `SetCursorPos` may return
false even for the current coordinates. The final desktop comparison restores foreground
only after the pointer and skips a pointer write when its position already matches.
Refused movement and mismatched readback still fail cleanup; no elevation or forced
process restart is used to bypass the boundary.

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

Run `scripts/tests/Test-PtNotepadCleanup.ps1` in a fresh PowerShell process for synthetic
UIA/window tests of localized consent, asynchronous closure, no replay and refusal paths.
It does not open Notepad or interact with the desktop.

Run `scripts/tests/Test-PtOwnedFixtures.ps1 -Workspace <new-folder>` for the interactive
contract suite. It compares the pre-existing Notepad tabs and Explorer paths, exercises
an actual dirty document, and verifies refusal/retry for untracked folder contents.
Supply `-DiscardButtonName` when the observed Notepad discard label is not English.
Different Notepad versions/providers and unexpected Explorer reuse require explicit
evidence before extending these adapters; do not claim universal app/session restoration.

## Keyboard input observer

For ordinary key/remap observations that need a controlled text and key-event oracle,
reuse `scripts\tests\Show-PtDesktopFixture.ps1`. It creates a dedicated WinForms input
window plus a second same-process window. It does not configure PowerToys. Its
`FixtureInput` Edit control exposes UIA text; `keys.jsonl` records actual KeyDown/KeyUp,
and `text.txt` is written on KeyUp. These are owned synthetic data, not global input logs.

The optional `-InputLanguage <culture>` selects exactly one **already installed** layout
on the fixture thread after activation. Missing/ambiguous cultures fail before window
creation; no layout is installed and the default behavior remains unchanged. This is
for an ordinary-character oracle, not coverage of IME/AltGr behavior. `ImeMode=Disable`
alone does not establish that physical letters will become document text under every
input method: prove ordinary input before configuring a remap.

Declare a Process resource for the resolved `pwsh` executable and a Quiesce cleanup step
before launch. Use a new local state directory, retain the actual returned creation, and
include the fixture script as a recorded input:

```powershell
$fixtureExe = (Get-Command pwsh).Source
$fixtureScript = Join-Path $skill 'scripts\tests\Show-PtDesktopFixture.ps1'
# $stateDirectory is a new absolute run-owned directory outside private user content.
# $culture is the explicitly selected, uniquely installed culture, e.g. en-US.
$creation = Start-PtOwnedProcess -FilePath $fixtureExe -ArgumentList @(
    '-NoProfile', '-STA', '-File', "`"$fixtureScript`"",
    '-StateDirectory', "`"$stateDirectory`"", '-InputLanguage', $culture)
$ready = Wait-PtCondition -Description 'owned keyboard fixture ready' -TimeoutSeconds 20 -Probe {
    if (Test-Path "$stateDirectory\ready.json") {
        ConvertFrom-PtReportJson ([IO.File]::ReadAllText("$stateDirectory\ready.json"))
    }
}
if ($ready.processId -ne $creation.ProcessId) { throw 'Fixture launch identity mismatch.' }
$main = Get-PtWindowIdentity -Hwnd $ready.hwnd
foreach ($window in @(Get-PtNativeWindow -ProcessId $creation.ProcessId)) {
    Register-PtCreatedWindow -Identity (Get-PtWindowIdentity $window.Hwnd) -Creation $creation
}
```

Verify actual process integrity, exact foreground and `FixtureInput` keyboard focus.
Use `Send-PtChord`/`Invoke-PtHeldKeys` and independently observe both UIA text and balanced
key events. Never use SetValue, Unicode literal-text injection or posted character messages
as evidence that a physical source key was remapped. Inspect current Caps/Shift state rather
than silently changing it. Preserve all unsuccessful input observations.

Close the actual main window normally with `Stop-PtOwnedProcess -Creation $creation`,
whose `-RequestExit` callback receives the process identity and the caller's `-ArgumentList
@($main)`; call `Close-PtTrackedWindow -Identity $main`. Register any additional native
siblings before this process-wide closure. Do not terminate an arbitrary pwsh process or
adopt another process started after the baseline.

On normal exit, the fixture restores its original thread layout and writes
`input-language-restored.json` (`original`, `actual`); compare both to
`ready.originalInputLanguage`, not only to each other. Verify process/window absence and
restore the run's original physical desktop. Independently compare the original foreground
application's layout before/after using read-only `GetWindowThreadProcessId` and
`GetKeyboardLayout`; desktop snapshots do not include input-layout or IME state.
The fixture does not change an existing user application's composition mode.

Selecting a layout in an owned fixture can nevertheless affect another application's
thread when Windows applies a shared input-method choice. The fixture's own exit receipt
therefore does **not** certify the original foreground application.
Capture that exact HWND/PID/start identity before any fixture activation with
`Get-PtKeyboardLayoutSnapshot -Target $originalForeground` from `pt-input-layout.ps1`.
After all fixture exits and Settings/desktop restoration, call
`Restore-PtKeyboardLayoutSnapshot -Snapshot $originalLayout -ExpectedLayout @($ownedLayoutHandle)`.
The original target must be foreground for a change; the helper sends one normal layout
request only if its current layout equals the declared test-owned post-state. An unchanged
original is a no-op; unknown layouts, stale identities, held modifiers and uninstalled
originals are refused. No language is installed and IME composition/conversion is not restored.

Record a fresh layout/desktop comparison **after** the last Settings/resource-completion
observation and before sealing. For modules using the generic recorder lifecycle, keep this
in the final Normal Cleanup attempt after `Complete-PtResourceSession`; that adapter can
temporarily surface Settings. Do not put restoration into the reporting-only callback or
seal a PASS before a later independent layout check.

Run `scripts\tests\Test-PtKeyboardInputFixture.ps1 -InputLanguage en-US` where that single
layout is already installed. It exercises inherited behavior, explicit physical text/key
delivery, unavailable-layout rejection, normal exit and original-foreground layout checks.
With a second installed layout it also exercises an actual layout transition and guarded
restoration on a test-owned window, including conflict refusal and idempotence.
