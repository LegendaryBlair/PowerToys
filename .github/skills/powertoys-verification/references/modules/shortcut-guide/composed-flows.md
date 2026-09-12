# Owned Shortcut Guide flows

Load `scripts/pt-shortcut-guide-flow.ps1`. These operations compose the existing
identity, input, observation and recording helpers. They do not enable/restart SG,
change settings, retry activation or substitute a named event for a physical chord.
The caller owns its foreground fixture and final desktop/settings restoration.

## Explicit operations

| API | Contract |
|---|---|
| `Get-PtShortcutGuidePresentation -GuideTarget` | Read `Hidden`, `FullGuide`, `Indicators` or `VisibleUnclassified`, with native identity, foreground and exposed control/indicator facts. No product verdict or visual-completeness claim. |
| `Open-PtShortcutGuide -ForegroundTarget -Workspace -Entry NamedEvent/Chord` | Require enabled/native-ready SG and an initially hidden host. Send exactly one chosen entry and observe stable full-guide structure. Return a persisted ownership session. |
| `Close-PtShortcutGuide -Session -Route CloseButton/Escape/Chord/OutsidePane` | Require the owned full guide to be visible, perform exactly the selected route and observe hidden state. Already-hidden state is not a passed close test. |
| `Invoke-PtShortcutGuideCycle ... -Entry -CloseRoute -Action [-ArgumentList]` | Open, run the caller's observation/action, require the guide to survive it, then apply the chosen close route. Cleanup still runs after an error. |
| `Invoke-PtShortcutGuideHold -ForegroundTarget -Workspace -Mode Indicators/FullGuide -Action [-ArgumentList] [-WindowsKey 91/92]` | Keep one Windows key scoped while the callback observes/drives the actual configured hold mode; release in `finally`, then observe the configured release outcome. |
| `Restore-PtShortcutGuideSession -Session/-ReceiptPath` | Cleanup only: close an owned full guide if needed, or confirm it is already hidden. It is not evidence that a normal close route ran. |
| `Set-PtShortcutGuideCloseOnRelease -SettingsTarget -Enabled` | Use the exact installed CheckBox and TogglePattern; return `Before`, `Requested`, `Actual`, `Changed` after matching UI and saved readback. Caller restores `Before` through the same helper. |

Use `Get-PtWindowIdentity` for the foreground target and an existing local workspace.
No unowned already-open guide or Shell surface is adopted. Runtime identity changes
are errors, not a reason to choose another process or restart it.

```powershell
$result = Invoke-PtShortcutGuideCycle -ForegroundTarget $fixture.Identity `
    -Workspace $workspace -Entry Chord -CloseRoute Escape -Action {
        param($session)
        Get-PtUiObservation -Target $session.GuideTarget -AutomationId TextBox `
            -ControlType Edit -WithinAutomationId ShortcutGuide_SearchBox -Property Text
    }
```

NamedEvent demonstrates only the downstream action. Chord reads the complete current
activation binding and uses the ordinary no-dwell input helper. The close-chord route
rejects a binding changed since open. Escape refuses a nonempty query rather than
silently clearing it or sending a second Escape to make a close assertion pass.

The flow verifies initially released modifiers. It does not force the guide foreground
after activation to conceal a focus failure. Native visibility and the declared
search/rail/close structures must persist through the bounded readiness observation.
This does not prove animation quality, absence of earlier/later flashes or arbitrary
long-term visibility; the supplied action and case still own those assertions.

Both cycle and hold return callback results as the **`Output` array**, including empty
and single-result arrays. Cycle retains `Observation` as a compatibility alias to that
same array. New callers use `Output` consistently; check expected output counts before
attaching evidence. A missing property is not an empty successful observation.
A hold's `AfterRelease` is captured before its cleanup, so a
screenshot taken after the function returns cannot prove that the guide stayed visible
between release and cleanup.

`OutsidePane` measures `WindowSelector` (Custom), the full navigation/content region.
`PaneRoot` is only the narrow navigation rail, and clicking the center of
`WindowSelector` clicks inside the guide, not outside it. The helper selects an
inset point horizontally outside the full content, inside the host and the original
caller-owned foreground window. It rejects occlusion or changed foreground, uses the
existing H11 native pointer primitives, releases its button in `finally`, restores its
pointer and then verifies hidden state. It never substitutes deactivation or the close
button when no safe outside point exists. This proves settled dismissal, not animation.

## Holds and taskbar routing

The requested hold mode must already match Settings; configure/restore it explicitly.
For the release policy, first select `Open Shortcut Guide` with the scoped ComboBox
helper. Then use `Set-PtShortcutGuideCloseOnRelease`: the control is
`CheckBox / ShortcutGuide_CloseOnWindowsKeyRelease`, not an English-named Button.
The CheckBox lives inside `Group / ShortcutGuideWindowsKeyAction`. The setter finds
that group's unique expand/collapse Button by its supported pattern, opens it only
when collapsed, waits for the CheckBox to become visible, then restores the original
expander state. It refuses disabled/indeterminate controls or an initial UI/JSON
mismatch; it does not silently change the hold mode.

The timeout incorporates the actual configured hold duration. The callback receives the
session first, then the supplied arguments:

```powershell
$held = Invoke-PtShortcutGuideHold -ForegroundTarget $foregroundIdentity `
    -Workspace $workspace -Mode Indicators -WindowsKey 91 -ArgumentList @($taskbarFixture) `
    -Action {
        param($session,$ownedTaskbar)
        # Observe indicators, route only the number key through H11, then observe again.
    }
```

Do not send another Windows down/up pair inside the callback. Indicator mode must
hide after release. Full-guide hold uses the observed `CloseOnRelease` setting:
the returned `AfterRelease` can legitimately be `FullGuide`, after which cleanup
closes the owned surface. A settled observation is not proof of an animation.
Recorded holds pass callbacks and arguments through the recorder, rather than expanding
them into the command string. `arguments.json` records callback source and nested
run/attempt identities; the invoked callback still receives the original objects.

After digit routing, `VisibleUnclassified` means the native host remains visible
but UIA does not establish its content. It is neither `Hidden` nor proof that the
indicator numbers remain rendered. Preserve the exact routed HWND, held-key state,
presentation and passive capture before judging retention. The composed desktop
test leaves a successful capture pending explicit visual review; native routing
alone cannot pass the indicator-retention assertion.

## Failures, receipts and I01

Receipts retain exact guide/foreground identities, chosen entry, settings, phase and a
bounded transition timeline. A visibility loss before readiness or during the caller's
observation is an error; no activation retry, sleep workaround or trigger substitution
is performed. Root errors retain `SgFlowReceipt` and additional cleanup failures.
Receipt updates are atomic. A read-back receipt can be used only with the same identity.

Use H10 case boundaries for retries/recovery decisions and H09 for observations/evidence.
Normal and Diagnostic results remain separate. Cleanup of a test-opened Start/Search
transition uses the explicit Shell recovery helper, never process termination.
Cleanup waits boundedly through the typed `NoForeground` transition before making
that decision. A transient zero foreground HWND alone is not proof of a locked or
detached desktop; unrelated foreground-read errors still propagate.

The intermittent early-hide investigation **I01 remains separate**. A passing warm
cycle does not invalidate an earlier failure or prove a batching/delay fix. Retain the
entry type and timeline, including failures observed with a named event and no injected
chord. Controlled native-only/UIA or cold/warm comparisons are Diagnostic evidence,
not replacement Normal passes or a license to restart during checklist execution.

## Acceptance

```powershell
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtShortcutGuideFlow.ps1" -Workspace <new-folder>
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtShortcutGuideInteractions.ps1" -Workspace <new-folder>
pwsh -NoProfile -STA -File "$skill\scripts\tests\Test-PtShortcutGuideFlowDesktop.ps1" `
    -Workspace <new-folder> -Cycles 3 -HoldMode Indicators
```

The desktop suite uses only owned foreground windows, explicit entry/close routes and
both Windows keys. `-HoldMode FullGuide` requires explicitly prepared matching settings;
the caller restores them afterward. These are helper acceptance flows, not the complete
27-item SG checklist.
The offline flow suite includes eight consecutive holds inside real recording contexts
with nested run/attempt arguments and journal/command size limits. The interaction suite
also accepts `-SettingsHwnd <existing-SG-settings-page>` for an installed CheckBox round
trip; it restores the original hold mode, policy, file bytes and desktop snapshot.
Use `-SkipOffline` with `-SettingsHwnd` when recording only the installed-control case,
so intentionally failing mock contracts are not mistaken for product-path failures.
For an isolated outside-click regression, use the desktop suite with
`-Cycles 1 -CloseRoute OutsidePane -SkipHolds`.
