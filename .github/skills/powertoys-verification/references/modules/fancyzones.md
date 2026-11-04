# FancyZones - module verification profile

## Module facts

Operating guide, not full-module acceptance. Each run records its tested revision, actual
coverage, visual review and restoration; source-derived recipes do not establish a PASS.

| Fact | Value |
|---|---|
| Key | `FancyZones`; recorder aliases `FancyZones` and `FZ` |
| Sources/UI | `src\modules\fancyzones\`; native host, WPF editor, WinUI Settings |
| Binaries | Runner's installation: `PowerToys.FancyZones.exe`, `PowerToys.FancyZonesEditor.exe`, optionally `FancyZonesCLI.exe` |
| Data | `%LOCALAPPDATA%\Microsoft\PowerToys\FancyZones`; general settings `enabled.FancyZones` |
| Shortcut | Default Win+Shift+OEM3; rediscover the current binding |
| Event | `FancyZones.ToggleEditor`; toggles editor lifetime, not a physical-binding test |
| Native observations | Host-owned `FancyZones_ZonesOverlay`; assigned-window property `FancyZones_zones` |

Wheel, indicator, rotation and CLI controls are build-dependent. Match the installed artifact's
source, not necessarily the product source in the verification worktree.

## Entry paths

Complete [preservation and ownership](#fixtures-and-restoration) before activation.
Do not close a borrowed editor or seed configuration to obtain a convenient starting state.

| Intent | Route |
|---|---|
| Settings/editor button | Windowing & layouts -> FancyZones -> Launch layout editor |
| Physical binding | Current chord over an owned compatible-integrity foreground fixture |
| Downstream discovery | No editor present: signal `FancyZones.ToggleEditor` once |
| Quick Access | Visible, uncloaked tray flyout -> enabled FancyZones entry; preserve its state separately |
| CLI | Installed `open-editor`/`open-settings`; inspect actual help and aliases |
| Command Palette | Installed PowerToys extension; preserve provider, navigation and dock state |
| Snap/layout switch | Enabled host and owned window; actual drag/chord, not direct placement |
| Task View | `Invoke-PtTaskViewScope` over a tracked fixture; only a newly opened, identified Shell transition |

## UI state-transition map

Settings is independent. Editor main includes previews; geometry editing uses a separate
surface and Save/Cancel toolbar. Observe arrival before the next action.

| Current state | Trigger / condition | Next state | State landmarks |
|---|---|---|---|
| Disabled | Settings enable; startup observed | Enabled idle | Exact host and allocated overlay windows |
| Enabled idle | Editor entry; none present | Editor main | Main root, monitor selector, layout cards, New layout |
| Enabled idle | Begin drag; activation false | Drag inactive | Owned move loop, hidden overlays |
| Enabled idle | Begin drag; activation true | Drag active | Overlay visible during held gesture |
| Editor main | Select monitor or apply card | Editor main | Current monitor and selected card readback |
| Editor main | Right-click intended card | Editor main | Scoped layout context menu |
| Editor main | Duplicate through card/menu | Editor main | Layout list available |
| Editor main | New layout | New layout dialog | Name and grid/canvas choices |
| Editor main | Edit properties | Layout properties | Numeric/toggle controls, Save and Cancel |
| Editor main | Delete owned card | Delete confirmation | Scoped Delete/Cancel dialog |
| Editor main | Normal owned close | Enabled idle | Editor/previews absent, host retained |
| New layout dialog | Create grid | Geometry editor | Grid surface and toolbar |
| New layout dialog | Create canvas | Geometry editor | Canvas surface and toolbar |
| New layout dialog | Cancel | Editor main | Main list returns |
| Layout properties | Edit zones; grid | Geometry editor | Grid surface and toolbar |
| Layout properties | Edit zones; canvas | Geometry editor | Canvas surface and toolbar |
| Layout properties | Save | Editor main | Dialog closed |
| Layout properties | Cancel | Editor main | Dialog closed |
| Delete confirmation | Confirm owned deletion | Editor main | Confirmation dismissed |
| Delete confirmation | Cancel | Editor main | Confirmation dismissed, main list visible |
| Geometry editor | Save and apply | Editor main | Geometry surface closed |
| Geometry editor | Cancel | Editor main | Geometry surface closed |
| Drag inactive | Activation input | Drag active | Current overlays visible |
| Drag active | Deactivation input | Drag inactive | Overlays hidden while move loop continues |
| Drag active | Drop/cancel/owned target closes | Enabled idle | Held input released, overlays cleared |
| Drag inactive | Drop/cancel | Enabled idle | Move loop finished |
| Enabled idle | Disable; editor already closed | Disabled | Exact host exited, configuration off |
| Owned foreground | Real Win+Tab; Task View initially absent | Task View | Fresh Shell HWND/title/process identity |
| Task View | Scoped Escape or normal dismissal | Owned foreground | Original Shell surface hidden/absent, fixture foreground restored |

## Control locator and interaction index

Use [scoped typed resolution](../helper-workflow.md#scoped-control-selection). `x:Uid` is not
AutomationId. Re-resolve recreated peers, actual patterns and physical geometry.

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Navigate Settings | Borrowed rail | IDs `WindowingAndLayoutsNavItem`, `FancyZonesNavItem` | Expand/select; verify page |
| Enable/disable | FancyZones page | ID `EnableFancyZonesToggleSwitch`, TogglePattern | [Lifecycle adapter](../module-lifecycle.md); require actual process result |
| Launch editor | Enabled Settings page | Button ID `LaunchLayoutEditorButton` | Physical CLI click when InvokePattern is absent |
| Edit shortcut | Unique setting row | Scoped ShortcutControl button | [Recorder](../shortcut-recorder.md); Save/Cancel/Reset, then real binding |
| Set options | Intended expanded card | Typed toggle/combo/numeric peer | `Set-PtFancyZonesBoolean`; exclude nested cards; use supported pattern |
| Select monitor | Editor main | List ID `Monitors`, current child | `Select-PtFancyZonesMonitor`; native number maps to UI ordinal; verify selection |
| Apply layout | Selected monitor | Unique card Name and ListItem type | `Apply-PtFancyZonesCaseLayout`; click, observe selection and exact persisted device assignment |
| Create layout | New dialog | IDs `LayoutNameText`, `GridLayoutRadioButton`, `CanvasLayoutRadioButton` | Invoke `NewLayoutButton`, set name/type, scoped Create |
| Edit parameters | Actual layout properties | IDs `EditLayoutButton`, `TemplateZoneCount`, `Spacing`, `SensitivityInput`, `spaceAroundSetting` | Supported numeric/toggle input; Save/Cancel |
| Duplicate layout | Intended template/custom card | IDs `createFromTemplateLayoutButton`, `duplicateLayoutButton` or scoped menu | `Copy-PtFancyZonesCaseTemplate` for templates; verify a new UUID, not just a caption |
| Delete layout | Owned custom card | ID `deleteLayoutButton` or Delete menu | Verify UUID, then scoped confirmation |
| Assign digit | Custom layout properties, not template properties | ComboBox ID `quickKeySelectionComboBox` | Select a collision-free digit and Save |
| Set orientation default | Layout properties | IDs `SetLayoutAsHorizontalDefaultButton`, `SetLayoutAsVerticalDefaultButton` | Invoke and Save; selected controls have IDs `HorizontalDefaultLayoutButton`, `VerticalDefaultLayoutButton` |
| Observe default | Reopened owned custom properties | Actual visible selected/unselected default button | `Save-PtFancyZonesDefaultEvidence`; retain typed state and exact control crop |
| Enter geometry | Properties/card menu | ID `editZoneLayoutButton` or Edit zones menu item | Bind surface and toolbar separately |
| Edit canvas | Canvas surface | Class `CanvasZone`; IDs `NEResize`, `DeleteButton`, `newZoneButton` | Hit-checked drag/add/delete; toolbar Save/Cancel |
| Edit grid | Grid surface | Class `GridZone`, resize Thumb, Merge zones button | Split/drag/select/merge; toolbar Save/Cancel |
| Drag fixture | Exact owned foreground | Fresh physical caption hit | `Invoke-PtFancyZonesCaseDrag`; actual MoveBegin/MoveEnd; release in finally |
| Snap/cycle/switch | Owned foreground, current settings | Actual chord/mapping | `Send-PtChord` or continuous `Invoke-PtHeldKeys` |
| Inspect Task View | New Shell transition | Verified title, Explorer image and observed supported class | `Invoke-PtFancyZonesCaseTaskView`; no class-only adoption or closing an existing Task View |
| Invoke CLI | Installed executable | Current help/aliases, not UIA | Record arguments, exit and output independently |

### Read-out notes

- Read live files with `Read-PtSharedFileText`; preserve read/parse errors. Scalars usually use
  `properties.<setting>.value`; inspect hotkey object shape. Canvas uses capital `X`/`Y`;
  grids use percentages/cell-child maps. UI numbering and stored indices are different.
- Filter history by owned executable **and** work area. Owning one Explorer HWND does not
  own every Explorer history record. Pair zone stamps with physical frames and actual input.
- Entry and CLI/Palette queries can rewrite editor parameters; editor entry can also write
  assignments. Normal editor close serializes assignments, custom layouts, digits, templates
  and defaults even after draft Cancel. Cancel is not a byte-identical-file guarantee.
- Editing a template can also update orientation defaults referencing that template.
  `Set-PtFancyZonesCaseZoneCount` predicts those exact dependent writes. A layout click,
  file persistence, host refresh and moved-window geometry are separate observations.
  `Wait-PtFancyZonesPersistence` waits for declared readiness and stable selected bytes;
  it does not grant ownership, replace expected state or establish a writer lock.
- Spanning replaces separate monitor records with one combined work area. Its DPI field is
  unused (`0`); monitor dimensions are physical, work-area dimensions DPI-unaware. Do not
  preserve the former array shape or apply one scaling formula to both dimension types.
  WMI failure and a `Guid.Empty` fallback do not prove monitor serial/virtual-desktop identity.
- Relayout geometry is not the requested zone mask: a zones-1-2 window can fit the remaining
  zone while retaining its original indices. `Get-PtFancyZonesRelayoutObservation` compares
  the independently expected reduced rectangle and the restored rectangle/index set.
- With both startup options enabled, supported target versions search current, primary and
  other-monitor history before active-monitor fallback. Record both settings and initial
  histories. Preserve conflicting checklist expectations for review, not as product defects
  or automatic PASSes. Cross-monitor histories require distinct work areas.

### Input and visual observations

Coordinates require the exact surface `-w`, fresh `Rect.Left/Top/Right/Bottom` and a physical
hit check. Validate the owned modal move, not just SendInput's return. Pass callback data
through explicit `-ArgumentList` parameters; recorder variables can shadow captured names.
On winapp 0.7.1, `--root` scopes search/read, not `invoke`; use the pinned tool's actual help.

Use `Save-PtOwnedControlScreenshot` for controls: it rounds bounds outward and checks runtime
identity/geometry before and after capture. Default evidence must show the actual default
control, not New layout or Save/Cancel. The opaque editor client is source-verified; this is
not permission to capture translucent overlays without an owned opaque backdrop.

For overlays/transparency, use `Save-PtFancyZonesCaseOverlayCapture` over the authored fixture.
Its opaque checkerboard provides structure for before/during/after transparency comparison.
Keep zone boundaries/labels relevant to the assertion in the crop. Register all overlapping
owned siblings; never whitelist Shell classes or include unrelated windows/private names.
Native alpha/stamps and a flat crop alone do not prove rendered appearance. Review original
pixels and timestamped frames for timing; a valid PNG is not an accepted visual reference.

## Troubleshooting

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| Trigger closes editor | Check current lifetime before signaling | Toggle success is not launch/binding proof |
| Missing Save/geometry control | Distinguish main, preview, surface and toolbar; resolve fresh typed peer | Wrong HWND/pattern is not a product failure |
| Native monitor number not found in UI | Map through current host input to the editor ordinal | Do not hard-code local/RDP numbering |
| Drag starts without zones | Check caption hit, MoveBegin, integrity, foreground and options | Input submission is not delivery |
| Save succeeds then next action conflicts | Inspect declared template/default/history side effects and settlement | Do not adopt a fresh snapshot to clear the guard |
| Relayout mask remains multi-zone | Compare physical geometry and return transition separately | Retained requested indices alone are not a failure |
| Startup uses another monitor's history | Inspect both placement options and history precedence | Do not conflate active-monitor fallback with history override |
| Task View not found by legacy class | Match localized title, actual Explorer identity and supported current class | No class-only Shell ownership |
| Escape destroys the Shell HWND | `Test-PtTrackedWindowClosed` / `Wait-PtTrackedWindowClosed` accept verified absence | Reused identity/read denial is not absence |
| Blank/clipped/wrong-control image | Re-resolve the exact control or patterned owned scene | Capture validity is not visual correctness |
| Rollback refused | Retain originals and conflicts; stop dependent writes | No force overwrite or weakened expected state |
| Legacy index/bare-digit disagreement | Retain actual input and sourced expectation conflict | Do not manufacture a product verdict |

## Fixtures and restoration

### Resource inventory

| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| Selected FancyZones files | Host/editor/CLI | Private original bytes and absence; declared writes only | Quiesce writers; guarded file-set restore | Exact final bytes/existence |
| General files and Settings | Options/navigation | Original enable bit, files, page, scroll and placement | Disable owned host, restore UI, then files | Runtime/configuration and UI agree |
| Layouts/defaults/digits | Editing/switching | Creation-owned UUIDs and collision-free mappings | Restore only declared state | Originals preserved; test additions absent |
| `FancyZonesSurface.cs` fixture | Input, geometry, capture | `Start-PtOwnedProcess`; exact siblings; opaque patterned background | Normal exit marker; tracked shutdown | Owned windows/process absent |
| `New-PtExplorerFixture` | Real Explorer interaction | Owned folder/HWND; shared process borrowed | `Remove-PtExplorerFixture` | Only owned window/folder removed |
| Editor/geometry/previews | Editor flows | Declared activation; existing editor borrowed | Cancel owned draft; register siblings; normal exit | No owned preview/surface remains |
| Task View transition | Desktop/pin observations | Initially absent visible surface; exact opening receipt | Scoped finally dismissal before host/UI cleanup | Original surface hidden/absent, foreground restored |
| Owned virtual desktop/pins | Desktop-specific cases | Nonempty observed identity; original pin/current-desktop state | Unpin and remove only created desktop | Original desktop/pins retained |
| Quick Access/Palette/dock | Integration | Separate borrowed UI/provider and owned pin | Paired surface/provider recovery | Original navigation/dock; no owned survivor |
| Hardware/policy/upgrade fixture | Conditional matrices | Explicit authority and complete baseline | Fixture-specific recovery | Original topology, settings and installation |

Snapshot `settings.json`, `applied-layouts.json`, `custom-layouts.json`, `default-layouts.json`,
`layout-hotkeys.json`, `layout-templates.json`, `app-zone-history.json`, `editor-parameters.json`
and `last-used-virtual-desktop.json`. Capture general `settings.json`, `settings-ui.json` and
`settings-placement.json` before navigation. Logs are outside this selected-file claim.

### Helper boundaries

Use the [resource session](../session-safety.md), [owned fixtures](../owned-fixtures.md) and
[selected-file contract](../directory-snapshots.md#selected-file-preservation). Snapshots grant
no ownership; process tracking alone does not restore files, UI or virtual desktops.

`New-PtFancyZonesDriverContext` takes this run's expected selected-file snapshot, exact owned
host creation, preserved Settings identity, installed editor path and private recovery directory.
`Invoke-PtFancyZonesDriverAction` freezes record scope before input and privately retains
confirmed recovery state on errors. Add layout UUIDs, fixture paths and mappings only from
current-run ownership receipts. Native first-wins assignment identity and editor
monitor-number/last-match serialization are modeled separately.

Use `Invoke-PtFancyZonesFileAction` only for complete deterministic predeclared JSON predictions.
Do not make a desired business result a prerequisite for retaining an attributable failed
result. Unknown concurrent changes remain conflicts. No initial baseline is replaced.

The finite `scripts\tests\Test-PtFancyZonesCaseDesktop.ps1` recipe requires an initially
disabled host, existing Settings, a new workspace and the compiled owned fixture. Built-in
`Span`/`Child` flows are focused selections. Other supported runtime scenario IDs take `-CaseScript`
and frozen `-ConditionScope`; `Record-CaseCondition` preserves independent judgments in
the producing attempt. Use the existing recorder handle for same-runspace continuation.
Old scenario memberships must be mapped explicitly to the current inventory, not relabeled
inside historical reports. A stop marker blocks new actions while cleanup remains enabled.

### Restoration order

1. Release injected input and restore owned Shell transitions. Never send Escape to an
   unidentified foreground window or adopt a Task View that was already open.
2. Cancel owned drafts and normally close editor/siblings. Independently close owned
   fixtures; restore the pointer before required foreground/process changes.
3. Disable the exact owned host and observe exit. Settle the borrowed Settings UI before
   restoring its files. Use `New-PtFancyZonesCleanupPlan` with `Invoke-PtCleanupPlan`:
   unresolved Shell/editor/host dependencies block the corresponding file writes.
4. Guarded rollback restores module/general originals. Never restore an off enable bit
   while its host is still running. Independent safe cleanup still proceeds after a failure.
5. Restore original enablement where the fixture supports it, then desktop/input state.
   Any required startup is another mutation; compare again after the last writer.

### Restoration verification

Require actual file, enablement, Settings UI, pointer/input and owned-process comparisons.
Host exit, disk restoration and logical UI restoration are distinct receipts. Preserve private
recovery on conflict; do not loop restarts or move those payloads into reports/commits.

### Execution notes

The checklist's 35 scenarios retain 171 independent assertions. Reuse an owned fixture and
the same save/reopen, drag/drop, window creation or layout-switch action for all applicable
assertions only when their initial states match. Keep grid/canvas, Cancel, spanning modes,
history variants and conditional hardware scopes separate; do not invent cross-products.
Run unavailable conditional coverage as scoped limitations, not a reason to skip ordinary
paths. Source/format review and helper regressions do not certify every scenario live.

For bounded live helper acceptance, the same recipe supports `AcceptanceShell`,
`AcceptancePersistence` and `AcceptanceObservation` with the matching scripts under
`scripts\tests\cases` and `scripts\tests\fixtures\fancyzones-helper-acceptance.json`.
These three groups use `InfrastructureAcceptance`, not the module's 171-assertion signoff.
The Shell group uses `-ObservationOnly` to avoid activating FancyZones.

## References

- [Checklist](../release-checklist/fancyzones.md) and [inventory](../assertion-inventories/fancyzones.json).
- [Recorder/archive](../recording-workflow.md), [observations](../ui-observations.md),
  [lifecycle](../module-lifecycle.md), [toolchain](../winapp-toolchain.md).
