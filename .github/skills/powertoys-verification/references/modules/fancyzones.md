# FancyZones - module verification profile

## Module facts

**Maturity:** initial discovery profile; entry paths observed, broader flows need confirmation.

| Fact | Value |
|---|---|
| Key | `FancyZones`; recorder aliases `FancyZones` and `FZ` |
| Sources/UI | `src\modules\fancyzones\`; native host, WPF editor, WinUI Settings |
| Binaries | Runner's installation: `PowerToys.FancyZones.exe`, `PowerToys.FancyZonesEditor.exe`, optionally `FancyZonesCLI.exe` |
| Data | `%LOCALAPPDATA%\Microsoft\PowerToys\FancyZones`; general settings `enabled.FancyZones` |
| Shortcut | Default Win+Shift+OEM3; rediscover the current binding |
| Event | `FancyZones.ToggleEditor` in the shared event catalog; toggles lifetime, not a binding test |
| Observation | Host-owned `FancyZones_ZonesOverlay`; assigned-window property `FancyZones_zones` |

Wheel/label/rotation/CLI availability is build-dependent. Rediscover identities and physical
geometry; enabled configuration alone is not overlay readiness.

## Entry paths

Complete [preservation and ownership](#fixtures-and-restoration) before activation.
Do not close a borrowed editor or seed configuration to obtain a convenient starting state.

| Intent | Route |
|---|---|
| Settings/editor button | Windowing & layouts -> FancyZones -> Launch layout editor -> Editor main |
| Physical binding | Current chord over an owned compatible-integrity foreground fixture |
| Downstream discovery | No editor present: signal `FancyZones.ToggleEditor` once; a repeat can terminate it |
| Quick Access | Visible/uncloaked tray flyout -> enabled FancyZones entry |
| CLI | Installed `open-editor`/`open-settings`; inspect actual help first |
| Command Palette | Installed PowerToys extension; preserve navigation, dock and companions |
| Snap/layout switch | Enabled host and owned window; actual drag/chord, not direct placement |

## UI state-transition map

Settings is independent. **Enabled idle** has no drag; **Editor main** includes previews;
**Geometry editor** has grid/canvas mode. These routes are source-derived, not live receipts.

| Current state | Trigger / condition | Next state | State landmarks |
|---|---|---|---|
| Disabled | Settings enable; startup observed | Enabled idle | Exact host and allocated overlay windows |
| Enabled idle | Editor entry; no editor present | Editor main | Main root, Monitors, layout cards, New layout |
| Enabled idle | Begin drag; activation false | Drag inactive | Owned move loop; overlays hidden |
| Enabled idle | Begin drag; activation true | Drag active | Native overlay visible during held gesture |
| Editor main | Select monitor or apply card | Editor main | Main list and selected monitor remain |
| Editor main | Right-click intended card | Editor main | Scoped layout context menu visible |
| Editor main | Duplicate through card/menu | Editor main | Layout list available; menu dismissed |
| Editor main | New layout | New layout dialog | Name and grid/canvas choices |
| Editor main | Scoped Edit | Layout properties | Parameters, Save and Cancel |
| Editor main | Scoped Delete | Delete confirmation | Delete/Cancel dialog |
| Editor main | Close owned main | Enabled idle | Editor/previews gone; host remains |
| New layout dialog | Create grid | Geometry editor | Grid surface and control window |
| New layout dialog | Create canvas | Geometry editor | Canvas surface and control window |
| New layout dialog | Cancel | Editor main | Main list available |
| Layout properties | Edit zones; grid | Geometry editor | Grid surface and Save/Cancel |
| Layout properties | Edit zones; canvas | Geometry editor | Canvas surface and add-zone/Save/Cancel |
| Layout properties | Save | Editor main | Dialog gone |
| Layout properties | Cancel | Editor main | Dialog gone |
| Delete confirmation | Confirm owned deletion | Editor main | Confirmation gone |
| Delete confirmation | Cancel | Editor main | Confirmation gone |
| Geometry editor | Save | Editor main | Editing controls gone; main visible |
| Geometry editor | Cancel | Editor main | Editing controls gone; main visible |
| Drag inactive | Applicable activation input | Drag active | Overlay visible |
| Drag active | Applicable deactivation input | Drag inactive | Overlay hidden; drag continues |
| Drag active | Drop/cancel/owned-window destruction | Enabled idle | Overlay hidden; injected inputs released |
| Drag inactive | Drop/cancel | Enabled idle | Move loop finished |
| Enabled idle | Settings disable; owned editor closed | Disabled | Exact host exited; configuration off |

Card-menu Edit zones uses the corresponding geometry route directly. Observe arrival,
not expected business results, before continuing.

## Control locator and interaction index

Confirm these source/UI-test locator candidates through [scoped resolution](../helper-workflow.md#scoped-control-selection).
Check runtime patterns/parents; `x:Uid` is not AutomationId. Re-resolve recreated peers.

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Navigate Settings | Borrowed rail | AutomationIds `WindowingAndLayoutsNavItem`, `FancyZonesNavItem` | Expand/select; verify page |
| Set enablement | FancyZones page | AutomationId `EnableFancyZonesToggleSwitch`, TogglePattern | Resident [lifecycle adapter](../module-lifecycle.md) |
| Launch editor | Enabled page | Button AutomationId `LaunchLayoutEditorButton` | Physical CLI click; this Settings peer may lack InvokePattern. Observe main landmarks |
| Edit shortcut | Unique setting row | Scoped ShortcutControl button | [Recorder](../shortcut-recorder.md): Save/Cancel/Reset, then physical binding |
| Set options | Expanded setting row | Typed toggle/combo/edit/numeric peer in fresh tree | Supported Toggle/Select/SetValue; commit focus-dependent edits |
| Select monitor | Editor main | AutomationId `Monitors`, actual monitor child | Click; read selection |
| Apply layout | Selected monitor | Unique owned card Name/type | Click or focused Enter/Space; focus alone is insufficient |
| Create layout | New dialog | IDs `LayoutNameText`, `GridLayoutRadioButton`, `CanvasLayoutRadioButton` | Invoke `NewLayoutButton`, set name/type, scoped Create |
| Edit parameters | Owned card/properties | IDs `EditLayoutButton`, `TemplateZoneCount`, `Spacing`, `SensitivityInput`, `spaceAroundSetting` | Supported numeric/toggle action; Save commits, Cancel rolls back |
| Duplicate layout | Intended card/menu | Menu Name Create custom layout/Duplicate; IDs `createFromTemplateLayoutButton`/`duplicateLayoutButton` | Scoped Invoke; persists immediately |
| Delete layout | Owned custom card | ID `deleteLayoutButton` or Delete menu | Verify UUID, then confirmation PrimaryButton; Cancel separately |
| Assign digit | Custom properties | ComboBox ID `quickKeySelectionComboBox` | Select digit, Save |
| Set default | Properties | IDs `SetLayoutAsHorizontalDefaultButton`/`SetLayoutAsVerticalDefaultButton` | Invoke, Save; selected IDs are `HorizontalDefaultLayoutButton`/`VerticalDefaultLayoutButton` |
| Edit geometry | Properties/card menu | ID `editZoneLayoutButton` or MenuItem Edit zones | Bind separate surface and toolbar HWNDs |
| Edit canvas | Canvas mode | Class `CanvasZone`; IDs `NEResize`, `DeleteButton`, `newZoneButton` | Scoped drag/add/delete; toolbar Save/Cancel |
| Edit grid | Grid mode | Class `GridZone`, resize Thumb, Merge zones button | Split/drag fresh geometry; select zones then Merge; Save/Cancel |
| Drag fixture | Owned foreground Explorer | Exact HWND, fresh title-bar hit | Recorded CLI drag; pre-held Shift via `Invoke-PtHeldKeys`; validate mid-drag release |
| Snap/cycle/switch | Owned foreground | Physical target; current options/mapping | `Send-PtChord` or `Invoke-PtHeldKeys` |
| Invoke CLI | Installed executable | Current help, not UIA | Record arguments/exit/output; rediscover aliases |

### Read-out notes

- `Read-PtSharedFileText` preserves read/parse failures. Scalars use
  `properties.<setting>.value`; inspect hotkey object shape rather than assuming it.
- Separate definitions, device/desktop assignments, defaults and digits. Canvas has capital
  `X`/`Y`; grid has percentages/cell-child maps. UI numbers and stored indices differ.
- Filter history by owned executable **and** work area; one Explorer HWND does not own all
  Explorer history. Pair native `FancyZones_zones` bits (0-63) with physical bounds/history.
- PID/class establishes overlay identity, not appearance. Use scoped pixels and timed frames;
  GDI can omit layered content. Check capture-induced focus changes and privacy.
- CLI/Palette queries can write `editor-parameters.json`. Persistence is not runtime behavior.
- Editor entry can also write `applied-layouts.json`; it is not a parameters-only operation.
  Spanning rebuilds the editor input from separate monitor records to one combined work area.
  Its DPI field is unused (`0`); monitor dimensions are physical, while work-area dimensions
  use DPI-unaware coordinates. Do not compare this model to the previous separate-monitor
  array after merely ignoring the spanning/selection flags.
- Normal editor close serializes assignments, custom layouts, digits, templates and defaults,
  even after canceling a draft. Do not equate Cancel with byte-identical files. Preserve the
  original selection, compare just before close, then attribute any close-time writes before
  guarded rollback after writer exit; unknown concurrent changes remain conflicts.

### Interaction recipes

- On winapp 0.7.1, `--root` scopes search/read operations, not `invoke`. Resolve a unique
  typed control through `Resolve-PtUiElement` (optionally `-WithinAutomationId`), then use
  its actual UIA pattern, or search for the unique runtime selector before a CLI action.
  New-layout PrimaryButton/SecondaryButton are exposed under the main HWND; the source
  dialog name is not necessarily a realized UIA container.
- Every coordinate click/drag needs its exact surface `-w` target. Native window bounds
  are `Rect.Left/Top/Right/Bottom`, not `Left/Width`; compute size and hit-test the actual
  owned geometry surface. Do not copy previous-run coordinates or monitor-size thresholds.
- Pass callback data with `Invoke-PtVerificationCase -ArgumentList` and explicit callback
  parameters. Do not close over `$kind`: the recorder's `Kind=Normal` can shadow that
  variable and turn a grid/canvas control ID into `NormalLayoutRadioButton`.
- Before normal editor/fixture exit, use `Register-PtCreatedProcessWindows -Creation`
  to discover later siblings without duplicate registration. Cancel the owned geometry
  draft on its separate toolbar first. An activation that fails before dispatch must
  not be represented as a successful process creation.
- For scoped capture, resolve an actual typed element and fresh unique selector first.
  Never accept whole-editor fallback when the requested region was an owned dialog/control.
  Keep rejected captures as private diagnostics, not accepted visual evidence.
- For composed overlays, use `Save-PtOwnedScreenshot` with recorded owned target identities
  and a known-opaque owned background covering the entire requested physical region.
  Arrange only owned windows so targets are above that background; do not close or hide
  borrowed Shell surfaces. The helper checks native z-order/ownership before and after
  capture and publishes only stable pixels from private staging. It never exempts
  `XamlExplorerHostIslandWindow` or another class. A rejected scene requires a safe
  arrangement, not a whitelist. Use `-Region` for a contained owned-content crop and
  inspect actual pixels; ownership alone does not make private layout names publishable.
- Invoke recorded driver files with `pwsh -NoProfile -File` and explicit arguments.
  Keep CLI identity probes simple; comma-separated argument expressions and call-operator
  commands can require manual parser review. This does not authorize bypassing a denial.

## Troubleshooting

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| Trigger closes editor | Check existing lifetime before signaling | Toggle success is not launch/binding proof |
| Main/Save controls missing | Distinguish main, preview, surface and toolbar HWNDs; resolve fresh typed UIA peers | Wrong-window lookup or unsupported CLI options are not product failure |
| Drag without zones | Check move loop, token/foreground, exclusions/options; use owned Explorer | Input acceptance is not delivery |
| Saved but inactive layout | Compare definition, assignment and geometry before restart | Storage and runtime are separate |
| Bare digit fails | Check version and legacy-review condition | Conflicting claims need resolution |
| Span result differs | Establish combined topology/DPI applicability | Combined evidence cannot prove separate histories |
| Blank overlay image | Check composition, focus, occlusion, physical bounds | Stamps/UIA cannot replace pixels |
| Rollback refused | Retain snapshots/error; stop dependent writes | No overwrite or expected-state bypass |

## Fixtures and restoration

### Resource inventory

| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| Selected files; `Get-PtFileSetSnapshot` | Host/editor/CLI | Run-owned writes; private original bytes/existence | Quiesce; guarded `Restore-PtFileSetSnapshot` | Exact bytes/existence after final startup |
| General files/Settings; shared snapshots | Navigation/options | Original enabled value, bytes and UI state | Restore options/page/scroll/placement | Fresh baseline comparison |
| Owned layouts/defaults/digits | Authoring/switching | Unique UUIDs; original assignments | UI semantics then guarded files | Additions absent; originals retained |
| `New-PtExplorerFixture` | Drag/snap | Case-owned folder/HWND; process borrowed | `Remove-PtExplorerFixture` | HWND/folder gone; desktop restored |
| `Show-PtDesktopFixture.ps1` | Input/multiple windows | `Start-PtOwnedProcess`; register siblings | Normal `Stop-PtOwnedProcess` | Process/windows absent; layout restored |
| Editor/previews | Editor flows | Declared activation; existing editor borrowed | Cancel draft; register new siblings once; owned normal close | Owned process/previews absent |
| Palette/provider/dock | Extension | Existing provider borrowed; test pin owned | Restore navigation/pin; owned normal exit | Original dock/identities; no survivor |
| Opaque capture background | Composed screenshot | Dedicated owned fixture paints its whole client area opaquely; target HWNDs and any overlapping siblings registered | Normal fixture exit; restore foreground/pointer | Exact process/windows absent; no rejected pixels published |
| Isolated specialist fixture | Display/desktop/policy/upgrade | Authority and complete baseline | Fixture-specific recovery | Original topology/desktop/registry |

Capture these direct children: `settings.json`, `applied-layouts.json`, `custom-layouts.json`,
`default-layouts.json`, `layout-hotkeys.json`, `layout-templates.json`, `app-zone-history.json`
and `editor-parameters.json`. Inspect additional sidecars before mutation; unrelated logs
are outside this selected-file claim.
Include `last-used-virtual-desktop.json` before host activation or desktop changes: the
native module can rewrite it independently of the editor.

### Helper boundaries

Use the [resource session](../session-safety.md), [owned fixtures](../owned-fixtures.md)
and [selected-file contract](../directory-snapshots.md#selected-file-preservation).
Snapshots grant no ownership. Lifecycle does not restore files/caches/drafts. File-set
rollback supports absence but requires an existing root and quiescent writers.

The `pt-fancyzones-displays.ps1` adapter reads physical and DPI-unaware rectangles, native
monitor identities and the current virtual desktop without changing them. Use
`New-PtFancyZonesEditorParameters` to construct the current separate/combined input model.
Retain WMI failures; an empty serial fallback needs comparison with the actual host.

Use `pt-fancyzones-driver.ps1` inside shared recorded attempts. Create a
`New-PtFancyZonesDriverContext` with this run's selected-file snapshot, exact owned host
creation, preserved Settings identity, installed editor path and private recovery directory.
`Open/Close-PtFancyZonesEditor` track both entry and close writes.
`Set-PtFancyZonesBoolean` resolves the actual supported toggle under a specific container.
For spanning it waits for the host's generated editor-input reply, not just Settings
persistence. This cache query is not an activation/hotkey or layout-update substitute.

`Invoke-PtFancyZonesDriverAction` freezes an explicit record scope before input and privately
persists confirmed recovery state even on errors. Add layout UUIDs, fixture executable paths,
digits and default orientations only from the current run's creation/ownership receipts.
The underlying `Invoke-PtFancyZonesScopedAction` preserves unowned records while allowing an
incorrect result inside an owned record to remain observable and restorable as a product
finding. Native assignment serialization uses first-wins identity matching; editor
serialization uses monitor numbers and last matching records. The layout-plan helper models
these separately. Neither normalization nor a snapshot grants write authority.

Use `Invoke-PtFancyZonesFileAction` with predeclared complete `-ExpectedJson` only when exact
deterministic outputs are appropriate. Do not require a product to produce the desired
business result merely to retain rollback evidence. Existing pre-action/restore conflicts
remain conflicts; never refresh an expected snapshot from arbitrary current files.

Every cleanup step declares `DependsOn`, using `@()` when independent. To resume an
interrupted controller in the same runspace, use the original plan and `-Resume -ResumeRun $run`;
the template retains the same recorder cursor and validated active resource session.
Do not reopen a second recorder handle while callbacks still hold the old one.
Declare helper process scopes before first activation, including headless/indirect companions.
Final process-query errors remain BLOCKED but must not suppress comparisons of other resources.

Quick Access is a separate borrowed UI owner, not part of a Settings-window snapshot.
Before touching it, establish its actual original UI/shortcut state and a paired restoration
adapter. Otherwise defer that entry path. A later baseline or successful new helper acceptance
cannot certify missing historical Quick Access state or overwrite the sealed R1 restoration gap.

Drag/wheel/rotation/desktop/Palette compositions are not live-certified. Missing adapters
are Author work. Never transplant CI seeding, process-name kills or close-all-window cleanup.

### Restoration order

1. Release injected input; cancel owned drafts; restore options/mappings. Retain the initial baseline.
2. Normally close owned editor/fixtures; pointer before Explorer closure. Disable FancyZones
   through Settings and observe writer exit.
3. Guarded rollback uses original/attributable expected state; settle general-file writers too.
   Preserve unknown changes.
4. Restore original enablement. Compare generated files after required startup; report
   disk/cache conflicts, never loop restarts.
5. Restore borrowed UI, desktop/pointer/input layout; complete resources and final comparisons.

### Restoration verification

After final writes compare bytes/existence, enablement, borrowed UI and owned-resource
absence. Files alone cannot certify desktops, placement or companion exit. Retain private
recovery on conflict; never commit it.

## References

- [Checklist](../release-checklist/fancyzones.md) and [inventory](../assertion-inventories/fancyzones.json).
- [Recorder/archive](../recording-workflow.md), [observations](../ui-observations.md),
  [lifecycle](../module-lifecycle.md), [toolchain](../winapp-toolchain.md).
- Source identities and corroborating symbols stay in authoring records, not runtime dependencies.
