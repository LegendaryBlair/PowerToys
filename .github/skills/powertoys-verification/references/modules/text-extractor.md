# Text Extractor - module verification profile

## Module facts

| Fact | Value / discovery |
|---|---|
| Identity | Module key `TextExtractor`, display name Text Extractor, source family `src\modules\PowerOCR`. |
| Configuration | `%LOCALAPPDATA%\Microsoft\PowerToys\TextExtractor\settings.json`; `enabled.TextExtractor` in the parent `settings.json`. |
| Process | Resolve Runner's installation and exact `PowerToys.PowerOCR.exe` path/session/start time. WinUI builds use `WinUI3Apps`; do not start an arbitrary second executable. |
| Lifecycle | Runner-managed resident process while enabled; capture/cancel closes transient overlays, not the resident process. |
| WinUI identity | `WinUIDesktopWin32WindowClass` host, Pane `TextExtractorWindow`; popups use `Microsoft.UI.Content.PopupWindowSiteBridge`. Legacy WPF controls require separate discovery. |
| Shortcut | Default Win+Shift+T; use the actual `properties.ActivationShortcut`. An internal fallback string is not the configured binding. |
| Show event | Catalog `TextExtractor.Show` / alias `PowerOcr.Show`: `Local\PowerOCREvent-dc864e06-e1af-4ecc-9078-f98bee745e3a`. |
| Language | Installed Windows OCR languages, displayed by native name. Empty preference falls back to the input language, then the first supported language. |

## Entry paths

Preserve the [resources below](#fixtures-and-restoration) before entry. Require no
pre-existing OCR overlay and cover the intended capture area with an owned synthetic
scene **before** activation: the module caches screen pixels as it opens.

| Intent | Route / destination |
|---|---|
| Binding | `Send-PtChord -Mods <configured-modifier-VKs> -Key <configured-code> -Hwnd <owned-fixture-hwnd>`, then observe Overlay idle. Match actual host/Runner/module/fixture integrity. |
| Downstream integration | `Invoke-PtSharedEvent -Name TextExtractor.Show`, then observe Overlay idle. Event success is not shortcut evidence. |
| Settings navigation | Preserve borrowed Settings first. Resolve `TextExtractorNavItem` (`ListItem`), expand `SystemToolsNavItem` if needed, then select the page. Observe the enable switch. |
| Overlay Settings | Invoke toolbar `SettingsButton` or popup `SettingsMenuItem`. Both request `PowerToys.exe --open-settings=PowerOcr`; observe Settings page and overlay disappearance. |
| Command Palette | Resolve the installed extension's localized commands with IDs `com.microsoft.powertoys.textExtractor.toggle` / `.openSettings`. Declare provider ownership first; the [palette reference](command-palette.md) does not authorize automatic recycling or closing borrowed hosts. |

## UI state-transition map

Settings can coexist with the resident module; multiple displays can have sibling
overlays. Observe arrival before continuing. This is not a fixed execution order.

| Current state | Trigger / condition | Next state | State landmarks |
|---|---|---|---|
| Disabled | Enable through Settings | Enabled resident | Enabled switch/configuration; resident process. |
| Enabled resident | Current shortcut / show event | Overlay idle | New full-display host, language ComboBox and toolbar. |
| Enabled resident | Disable through Settings | Disabled | Switch off; resident process exits. |
| Overlay idle | Left drag on selection interior | Selecting | Toolbar hidden; masks and selection border. |
| Overlay idle | Click recognizable word; processing completes | Enabled resident | Overlay HWNDs disappear. |
| Overlay idle | Right-click selection surface | Context menu | New PopupHost, `ContextMenuFlyout`, `CancelMenuItem`. |
| Overlay idle | Escape / toolbar Cancel | Enabled resident | All overlay HWNDs disappear. |
| Overlay idle | Toolbar Settings | Settings page | Text Extractor navigation selected; overlays absent. |
| Selecting | Release over recognizable text; processing completes | Enabled resident | Overlay HWNDs disappear. |
| Selecting | Release over blank content | Error overlay | `ErrorInfoBar` and toolbar remain visible. |
| Selecting | Escape | Enabled resident | Selection and overlays disappear. |
| Context menu | Select language / formatting | Overlay idle | Popup closes; toolbar remains. |
| Context menu | Cancel | Enabled resident | All overlay HWNDs disappear. |
| Context menu | Settings | Settings page | Text Extractor navigation selected; overlays absent. |
| Error overlay | Successful new capture | Enabled resident | Error and overlays disappear. |
| Error overlay | Escape / Cancel | Enabled resident | Error and overlays disappear. |

## Control locator and interaction index

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Enable/disable | Text Extractor Settings page | AutomationId `EnableTextExtractorToggleSwitch`, Button with TogglePattern | Shared Resident lifecycle snapshot/transition APIs; restore clipboard and dismiss owned overlays before disable. |
| Edit shortcut | Settings; enabled module | Group `TextExtractorActivationShortcut` -> Button `EditButton` (AutomationIds) | Shared shortcut recorder: page `TextExtractorNavItem`, property segments `@('properties','ActivationShortcut')`, `-WithinAutomationId TextExtractorActivationShortcut`. Save/restore through the dialog; test activation separately. |
| Set preference | Settings; enabled module; durable original captured before navigation | ComboBox AutomationId `TextExtractorLanguageComboBox` | Wrap `Select-PtComboBoxItem` in `Invoke-PtTextExtractorPreferenceChange` with the intended native name and wait for persistence in the callback. Restore with the [state adapter](#helper-boundaries), not a nonexistent default-language option. |
| Capture region | Overlay idle; owned scene on one display | Fresh overlay/scene physical bounds | `winapp ui drag <x,y> <x,y> -w <overlay-hwnd> --json`. Keep endpoints inside the display and pad glyph bounds. Observe copy/error completion. |
| Capture word | Overlay idle; desired glyph | Fresh physical point inside the word | Zero-distance `drag` supplies coordinate press/release. `click` accepts a selector, not an `x,y` string. |
| Translate selection | Selecting; owned mouse-down | Current selection and pointer | Keep mouse-down paired with release; hold Shift using `Invoke-PtHeldKeys` during movement. Retain before/after border observations; setting geometry is not a drag. |
| Open context menu | Overlay idle; below toolbar | Fresh physical interior point | Zero-distance `drag ... --right`. Shift+F10 from toolbar focus is a separate keyboard route, not right-click evidence. |
| Select context language | Fresh popup belonging to exact OCR PID | MenuItem `OCRLanguageMenuItem_<index>` plus current native Name | Inspect names/indices, invoke one item, then read toolbar and newly opened menu state. Order is not fixed. |
| Select toolbar language | Overlay idle | ComboBox `OCROverlayLanguagesComboBox` | `Select-PtComboBoxItem` with current native name. For popup readback, query Name plus ClassName `ComboBoxItem` and IsSelected in the exact popup HWND; never cache a runtime slug. |
| Toggle formatting | Overlay idle / Error overlay | Buttons `SingleLineToggleButton`, `TableToggleButton`, class ToggleButton | Supported Toggle, or guarded S/T for key assertions; read ToggleState. Popup counterparts: `SingleLineMenuItem`, `TableMenuItem`. |
| Select numbered language | Overlay idle / Error overlay; popup closed | Current language-index/name mapping | Send 1-9 to the exact overlay and read selection afresh. Do not refocus before testing post-error keyboard recovery. |
| Cancel | Overlay idle / Error overlay / Context menu | Button `CancelButton` / popup MenuItem `CancelMenuItem` | Invoke the required control or send guarded Escape; observe all owned overlays absent. Escape with a popup open may dismiss only the popup. |
| Open Settings | Overlay idle / Context menu | Button `SettingsButton` / MenuItem `SettingsMenuItem` | Invoke on the correct owner; re-resolve Settings and its selected navigation item. |
| Read error | Error overlay | AutomationId `ErrorInfoBar`, exposed text and bounds | Inspect descendants and capture passively; compare error rectangle with every toolbar control. |

### Read-out notes

- `properties.ActivationShortcut` directly contains `win`, `ctrl`, `alt`, `shift`,
  `code`, `key`; `properties.PreferredLanguage` is a direct native-name string.
  Use shared live-file readers, not exclusive file reads.
- Overlay language is session-only. A changed Settings preference needs a **new**
  overlay and independent selected-value/OCR observations.
- The displayed preferred-language selection can represent an empty persisted
  preference. Selecting that same language after a change writes its explicit name,
  not the original empty string. Settings can also reserialize the module version.
  Do not infer full-document or cached-model restoration from matching visible text.
- The state adapter leaves the stale page before exact file rollback, recreates the
  page after file-watcher settlement, and commits the **unchanged** shortcut through
  the shared recorder. Only a full-document writeback retaining the original
  preference establishes its Settings-cache result. It then restores original bytes
  again and leaves the page; the caller restores the run's original Settings UI.
- Wrap OCR copies with `Invoke-PtClipboardWrite`, using actual writer PID/start time
  and waiting for completion inside its action. Only then read attributed synthetic
  output. Retain exact spaces, line breaks and tabs; overlay closure is not accuracy.
- Clipboard `Restore()` is terminal, not idempotent. Once `Restored=true`, assert and
  dispose; do not AssertUnchanged, restore or write again on that guard. Retain one
  live guard for a capture group, or create another only after verified restoration.
- Fixture and WinUI bounds are physical pixels. DPI-unaware `Screen.AllScreens` may
  be virtualized; never mix its geometry or multiply physical coordinates by scale.
- Use `Save-PtPassiveScreenshot` with current `-WindowIdentity` and a contained
  `-Region` when needed. Full-overlay scope is safe only when all underlying pixels
  are confirmed synthetic. Captures remain candidates until accepted separately.

## Troubleshooting

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| Resident but no overlay | Check current binding, enablement, foreground/integrity and fresh event response separately. | Liveness/event existence is not activation; no automatic Runner restart. |
| Coordinate click is element-not-found | Check CLI help; use its coordinate drag press/release. | Parser error, not OCR failure. |
| Capture truncates text | Compare glyph bounds, padding, endpoint and DPI; preserve original output. A separately recorded padded/dwell experiment can distinguish selection delivery. | Do not delete missing characters from the oracle or silently accept changed whitespace. |
| Stale/missing language | Resolve live ComboBox/popup; query current Name + `ComboBoxItem` class and IsSelected. | Stale runtime identity is not empty selection. |
| Clipboard already restored | Inspect metadata; gate and dispose without a second Restore. Keep recovery owner if unresolved. | Caller-lifetime error, not authority to replay capture. |
| Keys inactive after blank capture | Retain error/focus/input receipts and test S/T/numbers before toolbar refocus. | Refocusing would conceal the behavior under test. |
| Conditional fixture unavailable | Record actual display/language/authority; continue independent cases. | One monitor is not mixed-DPI coverage; language labels are not recognition evidence. |
| Settings rollback conflict | Preserve original receipt and unknown changes; stop dependent mutations. | Snapshot existence is not restoration; never close borrowed Settings. |
| Original preference is empty | Capture with `New-PtTextExtractorState`; use `Restore-PtTextExtractorState` for guarded bytes plus recreated-page writeback. Preserve the private journal if any stage fails. | No default option restores empty. File equality alone is not a cache result; cleanup is not a product language-selection assertion. |

## Fixtures and restoration

### Resource inventory

| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| Owned OCR scene | Selection / capture / overlay images | Launch `Show-PtTextExtractorFixture.ps1` through `Start-PtOwnedProcess`; new local directory, exact PID/start and ready HWND. | Register every native sibling; normal main-window close through `Stop-PtOwnedProcess` / `Close-PtTrackedWindow`. | Exact process/windows absent; no untracked sibling remains. |
| OCR overlays | Activation | No pre-existing overlay; track newly observed identities under borrowed resident process. | Owned Cancel/Escape, not process kill. | All owned overlays absent; original enablement restored. |
| Clipboard keeper | Capture / cancellation | Complete supported formats captured privately; original provider retained. | Restore once, assert, dispose before provider shutdown. | Native readback, no pending write, keeper exited. History is separate. |
| Borrowed Settings | Navigation / configuration | Snapshot page, expansion, scroll and native placement before navigation. | Shared Settings UI restore; never close borrowed window. | Fresh original-state comparison after final navigation. |
| General/module settings | Enablement / shortcut / preference | Preserve general settings separately. The OCR state adapter encrypts the complete existing module file, including empty preference, version and original formatting, before navigation. | Restore enablement separately; the state adapter composes selected-file rollback and unchanged-shortcut UI writeback without closing Settings/Runner. | Byte hash equals the durable original after final UI operations; cache writeback matches all declared fields. Unknown changes are conflicts, not new baselines. |
| Input / desktop | Physical gestures | Desktop/layout snapshots and original cursor clip; actual process integrity. | Release owned input; pointer before scene close; final Settings, foreground and layout restoration. | Fresh physical pointer, original foreground/layout and clip rectangle after all writes. |
| External provider / tab | Palette / attribution | Declare exact executable before activation; preserve borrowed UI and own only new tabs/windows. | Supported normal close after clipboard dependencies. | No owned provider/tab survives; borrowed hosts remain. |

### Helper boundaries

The [scene helper](../../scripts/tests/Show-PtTextExtractorFixture.ps1) renders region,
line/table text and blank space. Pass an existing new absolute `-StateDirectory` and
optional zero-based `-MonitorIndex` to a dedicated `pwsh -STA` launch. Supply
`-LanguageSample` with independently known text for an installed non-Latin OCR
language when needed; read its `Language` region from the receipt. Wait for
`ready.json`, check its PID against the creation receipt and inspect real bounds/pixels
before input. It does not drive OCR, preserve state or assert results.

Use the shared [recorder/template](../recording-workflow.md),
[resource plan](../session-safety.md), [lifecycle](../module-lifecycle.md),
[clipboard](../clipboard-guard.md) and [shortcut recorder](../shortcut-recorder.md).
The keeper does not preserve clipboard history/cloud sync; establish separate safe
handling if enabled. These helpers do not authorize policy, diagnostic-data, theme or
language changes. Settings snapshots do not preserve unexposed drafts/IME composition.
For preference changes, `scripts\pt-text-extractor-state.ps1` provides:

| API | Contract |
|---|---|
| `New-PtTextExtractorState -SettingsPath -RecoveryPath` | Before navigation, capture the existing `settings.json` with the shared selected-file snapshot. Persist a current-user DPAPI-encrypted original in an existing private directory **outside** evidence. Returns metadata only; never replaces an existing baseline. |
| `Invoke-PtTextExtractorPreferenceChange -RecoveryPath -PreferredLanguage -Action [-ArgumentList]` | Persist intent, execute one supplied UI action, then validate the complete document: only the requested preference and known serialization version may differ. The callback waits for persistence. Errors retain recoverable intent/owned writes without replay. |
| `Restore-PtTextExtractorState -RecoveryPath -SettingsTarget -Workspace` | Use the exact borrowed Settings identity and run workspace. Navigate to General, restore original bytes, recreate OCR, verify unchanged-shortcut Save retains the original preference, and restore bytes again. Caller still owns final page/desktop/runtime observation. |
| `Restore-PtTextExtractorFile -RecoveryPath` | File-only recovery stage for a quiescent writer. Supports process-boundary recovery and idempotence, but does **not** certify cache/UI restoration. |

Do not record decrypted recovery objects or place the journal in a run archive.
Selected-file rollback is conflict-aware, not a filesystem transaction; quiesce
selected writers and preserve the journal on errors. Missing originals, unsupported
shortcut schemas, disabled controls and unknown concurrent writes are refused rather
than normalized. Full restoration intentionally performs a real unchanged-value Save;
it is not a read-only operation or the shortcut helper's default no-op.

### Restoration order

1. Release owned input, cancel owned overlays/popups and compare cursor clipping.
2. Restore clipboard before module disable/provider exit; dispose only after the gate.
3. Restore preference with the state adapter while the module is enabled; observe a
   new overlay's selected language independently. Restore other shortcut/enablement
   changes separately and account for startup-written sidecars.
4. Restore pointer while the owned scene is usable; close owned scenes/companions.
   Perform any authorized byte rollback only with quiescent writers.
5. Restore borrowed Settings, original foreground/layout, then compare all resources
   and full semantic settings after the last navigation/startup operation.

### Restoration verification

Require fresh baseline-relative receipts, not successful calls. Preserve unknown
concurrent changes and recovery owners on conflict. Product logs/telemetry are evidence,
not rollback targets; never delete their trees. No ordinary OCR result file is expected,
but an observed extra write must be accounted for before claiming complete restoration.

## References

- [Checklist](../release-checklist/text-extractor.md) and
  [assertions](../assertion-inventories/text-extractor.json).
- [Typed observations](../ui-observations.md), [capture/input](../helper-workflow.md)
  and [tool-version contract](../winapp-toolchain.md).
- Visual candidates remain in immutable run archives; this profile has no accepted
  screenshot baseline.
