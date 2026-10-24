# Quick Accent fixture mechanics

Use with the [checklist](release-checklist/quick-accent.md). This guide supplies preservation/input mechanics even when no module profile exists. It does not assert that controls have been discovered or product behavior has passed.

## Owned input

Create a collision-checked empty `.txt` file in the run workspace and open it in Notepad. Record pre-existing Notepad windows/tabs first. Resolve the new document by its unique filename, not just process name; modern Notepad can reuse a process. Close only the owned document without saving and verify its tab/window is gone. Do not terminate a process containing user tabs.

For exclusions/focus changes, a run-local WinForms TextBox host is an acceptable second synthetic text application, but does not replace the baseline's Notepad assertion. Give it a unique title and retain its script/PID. Two forms in that host provide the same-process/different-HWND condition. Launch at the same medium integrity as the installed Runner/module and verify actual tokens with `pt-admin-probe.ps1`. No clipboard is needed to set/read owned editor text through UIA.

The checked-in `scripts\fixtures\quick-accent-text.ps1` supplies two such windows, with `ImeMode.Disable` confined to their owned TextBoxes. Launch it in a separate `pwsh -NoProfile -STA -File` process with `-OutputFile` pointing to a new run-workspace JSON file and `-Title` set to a collision-checked run tag. Its JSON records exact titles, HWNDs and ProcessId. Wait for this receipt and both responsive HWNDs, verify their actual token, and use `OwnedText1`/`OwnedText2` only beneath the corresponding form. Close those forms with WindowPattern.Close, waiting for each HWND to disappear before closing the next; the process exits after both close. Remove the owned identity file after cleanup. It does not alter Notepad's IME or user keyboard layout.

Dot-source `scripts\pt-quick-accent.ps1` in a 64-bit `pwsh` process. Use the existing foreground helper or `winapp ui focus` and verify the exact fixture HWND and focused edit before the gesture. This helper deliberately does not focus a target on the caller's behalf.

```powershell
# Resolve $fixtureHwnd from the unique owned document window.
# $observe is a scriptblock containing bounded toolbar observations/navigation.
Invoke-PtQuickAccentGesture -WindowHandle $fixtureHwnd -KeyCode 0x41 `
    -TriggerCode 0x20 -DelayMs 1000 -Observe $observe
```

Omit `-TriggerCode` for press-and-hold. `-DelayMs` is a driving interval, not a readiness assertion or timing oracle. The callback runs while the letter remains down; the helper releases injected keys in `finally`, including callback failure. It rejects already-held participating keys. Each native event checks the complete SendInput return count. Record requested keys, start/end times and errors. Navigation inside the callback can use the existing `Send-PtChord` after rechecking exact foreground. Do not focus the toolbar or use a foregrounding capture: that can cancel the gesture. Never substitute PostMessage, SetValue or a named event for physical held-key activation.

Bind every result observer to the same editor selected for input. A Notepad read-out cannot judge text sent to a synthetic form. Check the active IME/layout before asserting Latin pass-through in Notepad; report conditions separately instead of silently swapping fixtures.

## Character-dialog ownership

Use `Invoke-PtQuickAccentCharacterDialog -WindowHandle $settingsHwnd -ManageButtonName $localizedButtonName -Action $dialogAction`. Resolve the HWND from the shipped Settings process and the exact accessible button name from its expanded Character sets section. The helper rejects a pre-existing modal, opens once, waits for the dialog, and calls `$dialogAction` with the Settings UIA root. The callback can manipulate the uniquely scoped dialog and invoke its Save (`PrimaryButton`) or Cancel (`CloseButton`). If it leaves the same dialog open, including on error, `finally` cancels that draft and waits for closure. It does not close a replacement dialog or retry a failed open.

Within the draft, scope `TextBox` to `CharacterSetsSearchBox`. Physical text entry triggers the user-input filter; inspect its actual value and the resulting `AvailableCharacterSetsList`. A language's accessible name may be a child of its selectable ListItem: walk to that owner, use AddToSelection/RemoveFromSelection, then re-resolve after filtering. The helper does not implement full virtualized-language enumeration. Do not use a success flag from an unrelated row as evidence of the selected set.

## File baseline and writer ordering

Before any gesture, privately capture `QuickAccent\settings.json` and `QuickAccent\UsageInfo.json` under `%LOCALAPPDATA%\Microsoft\PowerToys` with `New-PtQuickAccentFileBaseline -Path $path`. Its returned object contains original bytes: keep it in the owning driver/in protected recovery storage, never print or archive it with public observations. Record hashes/existence only. Snapshot general `enabled.QuickAccent`, module PID, Settings page/window geometry, foreground and pointer separately.

The file helper supports original absence as well as byte-exact content. It is not a lock, ownership detector, process tracker or settings cache restore. Before `Restore-PtQuickAccentFileBaseline -Baseline $baseline -ExpectedHash $ownedPostHash`, establish quiescent writers and a known post-state from the run's own action receipts. An unexplained file change is a conflict, not a new owned baseline. Keep backups for recovery rather than overwriting external changes.

Change test settings through Settings UI; do not pre-seed JSON to pass a case. Capture each owned write's hashes and compare unrelated fields against the run baseline. Usage counters can be read programmatically to choose a bounded frequency fixture, but emit only the synthetic character's counter/delta, not private history.

Cleanup order:

1. Release all injected keys; dismiss owned dialogs/guide and end recording.
2. Restore original Quick Accent controls through UI, then disable Quick Accent through UI to quiesce it. Confirm that particular module PID exits. `PowerAccent.Dispose` saves usage even at shutdown.
3. Navigate Settings away from Quick Accent so its old ViewModel is not reused. Compare observed files against known owned writes; restore exact original module settings and usage bytes/existence. Do not restore the entire general settings file over unrelated changes.
4. Restore original module enablement through UI. Reload the Quick Accent page only if needed for original UI state, then check file hashes/existence again after startup/watcher settling. Do not activate another test gesture after restoring usage.
5. Close only owned editor documents/hosts; restore Settings geometry/navigation, pointer and original foreground without disturbing user windows. Verify after the final writer/startup, not before it.

If UI restore/startup rewrites a sparse baseline, retain that exact difference as incomplete restoration; do not claim byte equality from semantic settings equivalence. Do not loop module restarts to hide it. Keep logs generated by normal product operation; report them as diagnostic side effects, not owned user data to delete.

## Clipboard copy checks

This candidate supplies no clipboard preservation API. Copy assertions require a separately validated native-format guard with private recovery storage, or an authorized isolated clipboard context. Text-only or WinForms multi-format round-tripping must not be assumed lossless: ANSI/OEM text conversion can disagree with Unicode text. Preserve original formats, raw payloads, history/cloud metadata, and any independently active history manager before invoking a guide character button.

Without that capability, retain QA-COPY-ORDINARY and QA-COPY-COMBINING as unexecuted setup gaps; do not click character buttons or clear user clipboard/history. Browsing, filtering and hover remain independent. Stop dependent clipboard mutations on any restoration mismatch and retain the actual error; a source-level copy handler is not runtime verification.

## Inventory consumption

This engine revision has no recorder/inventory-loader API. Read the checked-in JSON directly with `Get-Content -Raw | ConvertFrom-Json`; `items` are the 20 checklist cases and `items.assertions` their stable children. Iterate explicit children in the engine's ordinary per-item report, retaining case IDs, Clarity, exact actions, observed/not-observed status, dependencies and conditional reasons. This is data for the existing loop, not another reporting framework.
