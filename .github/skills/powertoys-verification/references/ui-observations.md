# Read-only UI observations

H07 separates observed values from unavailable observations. It does not activate,
focus, scroll, expand, set values, retry, restart applications or assign product verdicts.
Use the existing H01/H02 target and selector conventions, H09 evidence recording, and
H10 operation boundaries around the case's actual actions.

## Read one semantic property

Load `scripts/pt-ui-observation.ps1`.

```powershell
$identity = Get-PtWindowIdentity -Hwnd $hwnd
$observation = Get-PtUiObservation -Target $identity `
    -AutomationId TextBox -ControlType Edit `
    -WithinAutomationId ShortcutGuide_SearchBox -Property Text
```

`Target` is the complete HWND/PID/process-start/class identity, not just a HWND. It is
checked before and after the read. Supply an exact `-AutomationId` or `-Name` plus
`-ControlType`; add `-WithinAutomationId` when necessary. With neither selector, the
target window itself is observed. Duplicate exposures of the same runtime ID are
deduplicated; distinct matching identities are not selected arbitrarily.

Supported properties:

| Property | Observation channel |
|---|---|
| `Text` | ValuePattern.Value, otherwise TextPattern.DocumentRange when ValuePattern is unsupported; never Name, HelpText or placeholder |
| `Name`, `HelpText` | The explicitly requested UIA property |
| `IsEnabled`, `HasKeyboardFocus`, `IsOffscreen` | UIA Boolean property with default substitution disabled |
| `IsSelected` | SelectionItemPattern.IsSelected; not inferred from a caption or visual color |
| `RangeValue` | RangeValuePattern.Value, only when supported |
| `BoundingRectangle` | UIA geometry in a physical-DPI context; zero dimensions and an empty rectangle remain distinct |
| `LiveSetting` | Native UIA property 30135 with `ignoreDefaultValue=true`; numeric 0/1/2, not a speech observation |

The native LiveSetting bridge is necessary because the managed identifier registry
does not expose that property. It uses the public SDK COM interfaces and compares
the reserved NotSupported identity rather than treating a default 0 as observed Off.
No SDK installation, private API reflection or external interop package is needed.

Successful results have `Status=Observed`, the typed `Value`, `Source`, target/runtime
identity, selector and capture timestamp. `Value=""`, `false`, or numeric `0` can be
genuine observations. `Observed` does not mean the value meets the test's expectation
or proves pixels are visible.

`IsOffscreen` is accompanying metadata. If that metadata is unsupported,
`IsOffscreenObserved=false` and `IsOffscreen=null`; no false visibility value is invented.
A requested unsupported primary property still fails.

Failures throw an ErrorRecord with ID `PtUiObservation.<status>` and a structured
`Exception.Data['UiObservation']` containing Status, Property, Target, Selector, Reason
and `Classification=BLK-INFRASTRUCTURE`:

| Status | Meaning |
|---|---|
| `Missing` | Required control/container did not resolve |
| `Ambiguous` | More than one distinct runtime identity matched |
| `Unsupported` | Required pattern/property is not exposed, or text is protected/its non-password state is unverified |
| `Stale` | Target process/window or resolved element became invalid |
| `ReadError` | Provider/interop failure, invalid type/geometry, oversized value or malformed target |

These failures are not product FAILs and never become successful null/empty results.
`-MaxTextLength` defaults to 16,384 characters. Larger values fail explicitly rather than
being trimmed; raise the bound deliberately when appropriate and retain large data with
H09's `-Detail`. Password content is not read. Text whitespace is not normalized.
UIA calls remain synchronous: the observation helper does not claim a hard timeout for
a hung provider.

## Assess a captured tree

Load `scripts/pt-ui-snapshot.ps1`. This assessment is offline: it reads the supplied
winapp tree and does not query or mutate the desktop. It requires PowerShell 7.2+.

```powershell
$contract = @(
    @{ Id='search'; ControlType='Group'; AutomationId='ShortcutGuide_SearchBox' }
    @{ Id='editor'; ControlType='Edit'; AutomationId='TextBox'; WithinAutomationId='ShortcutGuide_SearchBox' }
    @{ Id='rail'; ControlType='Group'; AutomationId='MenuItemsHost' }
)
$quality = Test-PtUiSnapshot -Tree $tree -RequiredLandmarks $contract -WindowHwnd $hwnd
if (-not $quality.usableForContract) {
    # Retain the capture and the explicit quality diagnosis. Do not count missing rows as zero.
}
```

Input is the parsed `windows[].elements[]` tree with nested `children[]`.
`WindowHwnd` is optional for a single-window capture; multiple windows require it.
It checks captured HWND metadata, not a live process identity or capture freshness.
Live identity checks belong to `Get-PtUiObservation` and the capture's recorded context.
The default `MaxNodes` bound is 20,000 captured occurrences.

Check `usableForContract`, not the truthiness of the returned object. A usable result
applies only to the supplied structural contract. `dataScope=RealizedElementsOnly`
does not prove a complete tree, all virtualized rows, visual rendering or absence.
Host-only captures, malformed children and insufficient declared structure are not
business-result observations.

Completed assessment statuses are `Usable` and `MissingLandmarks`. Malformed,
unsupported, explicitly incomplete, ambiguous/missing-window, cyclic and over-budget
captures return explicit unusable diagnoses. On incomplete assessment, landmark counts
are **null**, not zero; an empty `missingLandmarks` array makes no absence claim.
`landmarkCounts` distinguishes raw occurrences, deduplicated known runtime identities
and identityless occurrences. These are capture counts, never a product row count.
Unknown contract fields are rejected rather than becoming hidden expected-value gates.

Landmarks describe observer access, such as a search control or list container. They
must not require expected business rows, text values or result counts. A valid observable
empty list can satisfy the same structural contract as a populated list; the case
evaluates its contents afterward. A contract sufficient for search/navigation is not
automatically sufficient for counting every shortcut row.

## Recording and acceptance

Live property reads automatically become recorded steps in an active attempt. Use
`Invoke-PtVerificationCase -OperationKey ... -Stage Observe` for shared observer failures.
Store concise facts in `Actual` and the result/tree in `-Detail` or a registered file.
Do not serialize a tree into every observation or treat a supported LiveSetting property
as evidence that Narrator actually spoke.

```powershell
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtUiObservation.ps1" -Workspace <new-folder>
pwsh -NoProfile -STA -File "$skill\scripts\tests\Test-PtUiObservation.ps1" -Workspace <new-folder> -Interactive
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtUiSnapshot.ps1" -Workspace <new-folder>
```

`Test-PtInstalledUiObservation.ps1 -Workspace <new-folder> -SettingsHwnd <owned-hwnd>`
adds a bounded installed Settings/SG check. It changes only a temporary SG query/focus,
restores the query, closes the test-opened SG surface and restores its captured desktop.
The caller owns Settings window lifetime, original file-byte checks and final report
cleanup. It is not a complete SG case or module signoff.

Native references:
- [GetCurrentPropertyValueEx](https://learn.microsoft.com/windows/win32/api/uiautomationclient/nf-uiautomationclient-iuiautomationelement-getcurrentpropertyvalueex)
- [Reserved NotSupported value](https://learn.microsoft.com/windows/win32/api/uiautomationcoreapi/nf-uiautomationcoreapi-uiagetreservednotsupportedvalue)
