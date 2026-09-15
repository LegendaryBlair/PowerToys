# Common Settings shortcut recorder

Use `scripts/pt-shortcut-recorder.ps1` for PowerToys' common WinUI shortcut editor.
The helper changes a setting through the shipped dialog; it does **not** prove that
the resulting shortcut activates a module. It never invokes a module, restarts the
runner, enables a module, writes application JSON, or uses Reset for restoration.

## Inputs and ownership

Keep an unlocked interactive desktop and serialize keyboard input. Explicitly navigate
to the intended Settings page and make its window visible before taking the snapshot.
Provide the exact HWND, selected navigation AutomationId, settings path and property
segments. If the page contains multiple `EditButton` controls, supply a unique
`-WithinAutomationId` container; distinct matching controls are an error.

| API | Contract |
|---|---|
| `Get-PtShortcutBinding -SettingsPath -PropertyPath` | Read the exact nested JSON object; property segments are literal, not a dotted expression. No writes. |
| `Get-PtShortcutSnapshot -Hwnd -PageAutomationId -SettingsPath -PropertyPath -Workspace [-AutomationId EditButton] [-WithinAutomationId]` | Verify UI HelpText against the persisted binding and save an ownership/original-value receipt in an existing local workspace. |
| `Set-PtShortcutBinding -Snapshot -Binding [-Mode Save/Cancel] [-TimeoutSeconds]` | Confirm recorder readiness, input the requested chord, read visible key labels, then save or cancel. Returns Before, Requested, Actual, HelpText, DialogKeys, Changed and the receipt path. |
| `Set-PtShortcutBinding ... [-CapturedObserver] [-ObserverArgumentList]` | Read-only observation hook before commit, receiving detached captured facts followed by explicit arguments. Exceptions cancel the owned dialog. Active recorder contexts retain the observer source and output. |
| `Restore-PtShortcutSnapshot -Snapshot` | Restore the captured original through the same UI operation, including custom modifiers, key code and original HelpText. Never substitutes a factory default. |

This adapter requires the complete six-field shape: Boolean `win`, `ctrl`, `alt`,
`shift`, integer `code`, and an empty-string `key`. Unknown fields, missing fields,
nonempty legacy `key` representations and empty/unassigned bindings are refused
before mutation because exact UI-only restoration is not established for them.
Reserved system gestures and modifier-only bindings are also refused.

Snapshots preserve HWND/PID/start-time/class, the selected page, control selector,
original binding/HelpText, and expected current binding. Changing `Original` in memory
is rejected against the persisted receipt. A persisted value changed by another writer
is not overwritten. Receipt updates replace a flushed temporary file atomically, retaining
the original if replacement fails. Receipts are trusted local recovery data, not security credentials.

## Usage

Module profiles supply the addressing and expected behavior; no module-specific defaults
belong in the helper:

```powershell
$snapshot = Get-PtShortcutSnapshot -Hwnd $settingsHwnd -PageAutomationId $pageId `
    -SettingsPath $settingsFile -PropertyPath $propertySegments -Workspace $workspace
$wanted = ConvertFrom-PtReportJson (ConvertTo-PtShortcutKey $snapshot.Original)
$wanted.win = $true
$wanted.ctrl = $true
$wanted.alt = $false
$wanted.shift = $true
$wanted.code = 123 # Example only: the case must choose an appropriate unused chord.

try {
    $actual = Set-PtShortcutBinding -Snapshot $snapshot -Binding $wanted
    # Verify the case-specific resulting behavior separately.
} finally {
    Restore-PtShortcutSnapshot -Snapshot $snapshot
}
```

In a recorded run, prefer `Invoke-PtVerificationCase`
with the assignment in `-Action` and `Restore-PtShortcutSnapshot` in `-Cleanup`. H10
retains the primary and restoration errors and always attempts owned cleanup. Pass
callback arguments explicitly rather than relying on generic outer variable names.
The shortcut helper automatically records its composed operation inside an active attempt.

For cancellation use `-Mode Cancel`. This still captures the requested chord, closes
only the owned dialog, and checks that both persisted fields and the displayed shortcut
remain unchanged. An existing dialog is not owned and is never dismissed by this helper.

After an interrupted script, load the receipt with `ConvertFrom-PtReportJson` and call
`Restore-PtShortcutSnapshot` once the same tracked Settings window/page is available.
An abruptly terminated process cannot execute `finally`: first confirm ownership and
cancel any leftover dialog explicitly. The helper refuses an existing dialog even for a
matching/no-op binding; it does not claim restoration while an unowned recorder remains open.
If the process/window changed, take a new target snapshot and explicitly reconcile the
old original values; do not replace the saved identity or treat another HWND as the same
target. An unexpected persisted value after a failed Save is a recovery conflict, not
permission to overwrite it. The exception retains the receipt path.

## Readiness and observation boundaries

The adapter does not guess a delay after opening. It presses and releases **Ctrl alone**
and requires the dialog to show exactly Ctrl with Save disabled. This establishes that
the capture hook is responding before sending a main key. Existing held modifiers are
rejected without releasing them; injected keys are released in `finally`.

The standard control's ordinary UIA tree omits key artwork. The adapter reads the bounded
raw dialog subtree and recognizes the exposed Shift glyph, but the Windows icon is
still absent from this provider. Consequently `DialogWindowsArtworkObservable=false`
is returned rather than claiming that UIA saw it. After Save, **complete edit-button
HelpText and all six persisted fields** must agree, including the Windows flag.
Use a passive screenshot when the case also asserts the icon's visual rendering.

UI/schema/provider or keyboard-label mismatches fail explicitly; unsupported layouts or
other shortcut editors are not silently driven through a guessed control or JSON fallback.
The polling timeout does not forcibly interrupt a hung UIA provider call.

## Restoration scope

The helper restores shortcut fields and displayed text, not page navigation, foreground,
pointer, module enablement or Settings window lifetime. The caller owns those surfaces.
If a module is disabled, prepare/restore its enablement explicitly as a test fixture;
the helper itself refuses its disabled editor.

The application may reserialize a pretty-printed settings file to compact JSON. Exact
field/document-value restoration is therefore distinct from byte restoration. Preserve a
`Get-PtFileSnapshot` before the run. If byte-exact rollback is required, first prove UI
and persisted values match the original, close only an owned Settings writer through
normal UI, then use the paired file restore for authorized cleanup. Never use file
restoration to disguise a failed shortcut assignment or unverified binding.

## Acceptance

```powershell
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtShortcutRecorder.ps1" -Workspace <new-folder>
pwsh -NoProfile -STA -File "$skill\scripts\tests\Test-PtShortcutRecorder.ps1" `
    -Workspace <new-folder> -Interactive -SettingsHwnd <existing-settings-hwnd>
```

Interactive acceptance exercises SG and Color Picker serially, temporarily enables a
disabled fixture through Settings and restores its flag, checks Save/Cancel and observer
failure, and preserves an existing custom original shortcut. It records positive
round trips through H09/H10 with passive captures. Its `recorded` run remains open for
the caller's final owned-window/exact-byte/desktop cleanup and fixed report finalization.
It is infrastructure acceptance, not completion of the SG release checklist.
