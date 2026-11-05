# Always On Top - module verification profile

## Module facts

| Fact | Value |
|---|---|
| Module | `AlwaysOnTop`; source `src\modules\alwaysontop\`. |
| Runtime | Native resident `PowerToys.AlwaysOnTop.exe`; verify installation/PID/start/session. Settings is separate WinUI 3. |
| Configuration | `%LOCALAPPDATA%\Microsoft\PowerToys\AlwaysOnTop\settings.json`; root `settings.json` contains `enabled.AlwaysOnTop`. |
| Bindings | Defaults: Win+Ctrl+T, Win+Ctrl+OEM Plus/Minus. Discover all three current bindings and the actual layout. |
| Events | `AOT.Pin`, `AOT.IncreaseOpacity`, `AOT.DecreaseOpacity` bypass binding recognition, **not foreground targeting**. Existence is not listener readiness. |
| Surfaces | Tracking class `AlwaysOnTopWindow`; border `AlwaysOnTop_Border`, composed behind its target. |
| Readiness | Discovery-stage: ordinary target/appearance methods are available; shortcut scoping and specialist fixtures remain separate readiness requirements. Consult the actual round archive for supported scope. |

## Entry paths

Prepare [baselines](#fixtures-and-restoration) and a compatible-integrity owned target
before mutation. Never pin/change opacity on borrowed windows.

| Intent | Entry | Destination / guard |
|---|---|---|
| Configure | [Settings entry](settings.md#entry-paths), then `AutomationId=AlwaysOnTopNavItem` | Snapshot before navigation; confirm page content. |
| Configured binding | Foreground owned target; send complete current chord | Separate delivery, target state and composition. |
| Window menu | Enable option; open the owned target's real title-bar system menu | Verify that Alt+Space is not intercepted by another configured launcher; no guessed command IDs or client-area menu substitution. |
| Downstream diagnosis | Signal the matching shared event with the same foreground guard | Not a substitute for binding coverage. |
| Palette integration | Extension's Always On Top Settings command; [palette profile](command-palette.md) | Not pinning; preserve favorites/query/provider lifetime first. |

## UI state-transition map

Settings and target coexist independently. The three target states below apply only
while enabled. Observe structural arrival before continuing.

| Current state | Trigger / condition | Next state | State landmarks |
|---|---|---|---|
| Disabled | Enable; policy permits; target initially unpinned | Unpinned | Exact resident process and target available. |
| Unpinned | Pin; eligible target, no Game Mode block | Pinned visible | Same target and resident tracking window available. |
| Unpinned | Pin; excluded or Game Mode blocked | Unpinned | Same foreground target. |
| Pinned visible | Unpin | Unpinned | Same target HWND. |
| Pinned visible | Minimize the owned target | Pinned minimized | Target is iconic; module remains resident. |
| Pinned visible | Maximize/resize owned target | Pinned visible | Same target, refreshed placement/frame identities. |
| Pinned minimized | Restore owned target | Pinned visible | Non-iconic target; refreshed frame. |
| Any enabled target state | Disable; no affected borrowed pins | Disabled | Exact module exits; Settings remains. |
| Settings page | Open uniquely scoped shortcut editor | Shortcut draft | Owned dialog, key artwork, Save/Cancel. |
| Shortcut draft | Save valid binding | Settings page | Dialog closed; original page. |
| Shortcut draft | Cancel draft | Settings page | Dialog closed without Save. |
| Settings page | Open custom-color button in custom mode | Color flyout | ColorPicker channel/hex inputs. |
| Color flyout | Dismiss | Settings page | Flyout absent; preview remains. |

`Any enabled target state` spans all three. Exclusions/highlighting/opacity can change
without lifecycle transitions. Dismiss does not undo live color edits.

## Control locator and interaction index

Inspect exact HWND with `Invoke-PtWinApp`; retain actual type/name/ID/parent/pattern.
The card IDs below are exposed by the inspected WinUI provider; rediscover them on a
different build. `x:Uid` is not a selector. Re-resolve after transitions; never pick
the first repeated control or assume a ToggleSwitch has UIA type CheckBox.

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Select page | Navigation | `AutomationId=AlwaysOnTopNavItem`; actual type | Realize, supported Select/Invoke, inspect content. |
| Toggle enablement | Enable card | Owner `AutomationId=AlwaysOnTopEnableToggleControlHeaderText`; local `Button`, English `Name=Always On Top`, TogglePattern | Realize with ScrollItemPattern before [Resident lifecycle](../module-lifecycle.md), including cleanup after scrolling down. No kill/relaunch. |
| Expand activation | Enabled page | Owner `AutomationId=AlwaysOnTopActivationShortcut`; local Button with ExpandCollapsePattern | Expand before child discovery. Do not select its same-caption shortcut EditButton. |
| Edit shortcut | Specific pin/increase/decrease row | Row label; local `Button`, `AutomationId=EditButton` if exposed | [Recorder](../shortcut-recorder.md) with unique container: snapshot, record, Save/Cancel, read and drive bindings. |
| Toggle highlighting | Expanded border card | Owner `AutomationId=AlwaysOnTopFrameEnabled`; English `Button` Name `Show a border around the pinned window`; require TogglePattern | Same-caption expander is a different Button. Toggle/read once; retain the pinned target for live change. |
| Select color mode | Expanded border; highlighting on | Owner `AutomationId=AlwaysOnTopFrameColorMode`; `ComboBox`, English Name `Color mode` | `Select-PtComboBoxItem` with actual owner/name and `Custom color` / `Windows default` option; preserve original selection. |
| Set custom color | Custom mode | Owner `AutomationId=AlwaysOnTopFrameColor`; unique Button; then owned flyout hex `Edit` | Invoke, rediscover hex edit by actual Name/ID and use ValuePattern in its observed RGB/ARGB format. Changes are live; Escape dismisses, not undoes. Restore custom color while custom mode is visible, then restore original mode. |
| Set border slider | Expanded border; highlighting on | Owners `AlwaysOnTopFrameThickness` / `AlwaysOnTopFrameOpacity`; `Slider` Names `Thickness (px)` / `Opacity (%)` | Realize, read range, use RangeValuePattern and check persisted value; live, no Save. |
| Toggle checkbox option | Matching enabled corners/Game Mode/menu card | Localized label; unique `CheckBox` in actual composite parent | ToggleState/toggle/read. Corners: Windows 11; preference is not fullscreen proof. |
| Toggle sound | Enabled sound card | Localized card's ToggleSwitch | Actual TogglePattern/readback; audio is separate. |
| Edit exclusions | Expanded exclusions | Owner `AutomationId=AlwaysOnTopExcludedApps`; unique descendant multiline `Edit` | Preserve private original; ValuePattern/set-value, collision-checked owned executable only. Realize its viewport; live, no Save/paste. |
| Send configured command | Owned eligible foreground | Non-UI: complete window identity/current pin/opacity chord | Guarded `Send-PtChord`; diagnostic `Invoke-PtSharedEvent` keeps foreground guard. |
| Invoke window menu | Owned classic target's Alt+Space popup | Fresh owner; localized `MenuItem` | Inspect/invoke/reopen check state. No index/internal-message substitute. |
| Read target | Exact owned window | Non-UI: identity for `Get-PtAlwaysOnTopWindowState` | Marker/style/alpha availability/frame/DPI; not pixels/verdict. |
| Check ordinary execution | Before navigation or fixture input | `Assert-PtAlwaysOnTopExecutionReady` with exact target and peer PIDs | Measures session/integrity and desktop; use `-RequireInput` for input availability and `-RequireForeground` immediately before target-directed input. Does not establish ownership or support mixed-integrity variants. |
| Invoke palette Settings | Installed extension; baseline saved | Actual title/subtitle/Settings command | Palette profile; favorites/locale need separate observations. |
| Check updates | Enablement baseline saved | [Settings controls](settings.md#control-locator-and-interaction-index) | Check only, compare before cleanup; no download/install. |

### Read-out notes

- Read with `Read-PtSharedFileText`; missing/schema/read failures are not defaults.
  Scalar `properties` keys `frame-enabled`, `frame-thickness`, `frame-color`,
  `frame-accent-color`, `frame-opacity`, `round-corners-enabled`, `sound-enabled`,
  `show-in-system-menu`, `do-not-activate-on-game-mode` and `excluded-apps` use `.value`.
  The three binding objects are directly at `properties.hotkey.value`,
  `properties.increase-opacity-hotkey.value` and `properties.decrease-opacity-hotkey.value`.
  Compare every modifier/key field.
- Recorder needs unique `WithinAutomationId`; the activation expander has three
  EditButtons. Their immediate `LayoutRoot` owners repeat the ID but have distinct
  Names (`Activation shortcut`, `Increase opacity`, `Decrease opacity` in English).
  ID alone is insufficient; the current recorder cannot express that combined owner
  selector. Return the adapter gap before opening rather than choosing an ordinal.
- Pin marker, topmost, visible precedence and border pixels are independent. Associate
  border by module process, target frame/desktop and transition, not nearest distance.
- Use passive lossless composed border crop on an owned opaque backdrop. Layer-only
  capture can flatten transparency; foregrounding can alter state. Do not rescale physical coordinates.
- After editing Settings, bring the owned opaque backdrop above borrowed windows before
  capturing the still-pinned target. Focusing only the pinned window leaves Settings
  visible around it; the composed-capture ownership guard must reject that scene.
- Compare color values as explicit ARGB: opaque `#RRGGBB` and `#FFRRGGBB` represent
  the same color. Preserve original file bytes separately; do not confuse serializer
  normalization with a failed color change or relax alpha comparison.
- Window alpha differs from frame opacity. Preserve original layered flag/alpha/color-key;
  unsupported attributes are not opaque. `Get-PtAlwaysOnTopDesktop` reads membership,
  not ownership; `Get-PtAlwaysOnTopGameMode` reads actual exclusive-D3D notification
  state, not setup/preference. Sound-file access is not audio.

## Troubleshooting

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| Shortcut ineffective / process absent | Foreground, integrity/session, complete binding, enablement, exclusions/fullscreen, lifecycle; retain error before authorized recovery. | Accepted input is not delivery; absence is not disabled; no automatic restart. |
| Border missing/flattened | Highlighting, minimize/desktop, association, composed capture. | Occluded/wrong/flattened layer is not a visual defect. |
| Opacity unchanged | Pin marker, root target, renderer, non-bound alpha; retain read errors. | Unsupported renderer is not supported-window failure. |
| Shortcut rows ambiguous | Runtime parents/HelpText, saved bindings, recorder scope. | No ordinal/fabricated container. |
| Menu entry absent | Option, actual system menu, foreign command ID. | Foreign collision must survive; unavailable observer is not absence. |
| Color restoration cannot locate its button | Select custom mode before restoring the custom color; restore the original mode afterward. | Accent mode hides the custom-color owner. This is a restoration dependency, not product absence. |
| Specialist observer missing | Establish audio/D3D/owned-desktop fixture first; continue independent cases. | Missing implementation is authoring work, not product inability. |
| Restoration disagreement | Stop dependent mutation; retain baselines, writer and conflict. | UI/bytes/cache differ; never replace baseline with defaults/new snapshots. |

## Fixtures and restoration

### Resource inventory

| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| `scripts\tests\Show-PtDesktopFixture.ps1` | Pin/overlap/opacity/keys | Run-owned `Start-PtOwnedProcess`; unique state directory, ready receipt, sibling HWNDs, marker/style/alpha | Unpin/compare alpha, tracked normal closure | Exact PID/siblings gone; selected thread-layout restore receipt agrees. |
| Settings/desktop snapshots | Navigation/input | Shared snapshots before mutation; borrowed identity stays borrowed | Shared restore; close only creation-proven owned Settings | Compare navigation/expansion/scroll/placement/desktop; disclose drafts/IME/focus limits. |
| Module/root settings, placement | UI/lifecycle changes | Private named-file bytes/existence and semantic baseline; exclude live logs | UI fields/bindings/enablement first; guarded rollback only with quiescent owned writers | Bytes/existence and runtime/cache after final writes/startup; retain conflicts. |
| Sidecar/log namespace | Activation | Bounded original filenames/existence; existing logs product-owned | Preserve existing; only attributed owned additions removable | Report deltas; no directory-wide cleanup/equality claim. |
| Layered/menu-collision target | Specialized conditions | Case-owned classic fixture; original alpha/flags or foreign caption/action | Validate setup; restore before release | Original attributes/command behavior; generic fixture insufficient. |
| Desktop/D3D/audio fixture | Isolation/Game Mode/sound | Case-owned ID/device/window; original state, attributed audio | Proven identity-safe creation/switch/release before mutation | Original desktop/display/endpoint; only owned resources released; no adjacency/file-access proof. |
| Elevated/clean/disposable session | Conditional cases | Separately authorized owned target/session | Scoped cleanup first; never log off shared desktop | Original state; ordinary UI scope grants no extra authority. |
| Palette/query/favorites/provider | Palette integration | Private baseline; declare provider Process before activation | Restore favorites/query/files; shutdown only recorded new provider | No added favorite/provider; preserve borrowed singleton. |

### Helper boundaries

`scripts\tests\Test-PtAlwaysOnTopPinDesktop.ps1` is a finite infrastructure-acceptance entry, not a controller
or full R0/R1. It requires initially disabled Always On Top and already-visible Settings. `-InspectOnly`
exercises guarded page navigation and restores unchanged visible placement through
`Restore-PtSettingsUiSnapshot -NoActivate`; it sends no keyboard input and does not claim pin coverage.
Full mode additionally requires attached input and creation-proven fixtures for a single native pin/unpin
cycle. Its default enable-toggle name is English; confirm the actual localized name before supplying it.
Native marker/topmost evidence does not establish border pixels, audio or the full checklist.

[Tracking](../session-safety.md) is not settings restore; [byte rollback](../directory-snapshots.md)
is not cache restore. Existing-file guards cannot restore absence; never pre-create
product files to bypass this. Specialist fixtures/recorder scoping need implementation
and checks before confirmation; warnings are not capabilities.

An older settings document can omit the two opacity bindings and system-menu field.
An ordinary Settings edit can serialize those loaded defaults and normalize color to
ARGB. Preserve the exact original first. Restore actual UI values and mode dependencies,
then verify every original semantic field and any version-confirmed default additions
before cleanup-only `Restore-PtFileSnapshot -ExpectedState`. Stop the owned module
writer and establish stable serialization; reject unexplained fields/concurrent changes.
Do not silently remove new fields or replace a missing binding with an assumed default.
When using run-local callbacks, pass state explicitly or use a unique script-scoped name:
generic variables such as `$original` can be shadowed inside recorder callbacks.

### Restoration order

1. Release owned input/dialogs; restore bindings, appearance, exact exclusions and UI values.
   Restore custom color in custom mode before returning to the original accent/custom mode.
2. Unpin owned targets; compare original layered state before closing; reset case mutations.
3. Realize the enable toggle and restore enablement without affecting borrowed pins. Quiesce owned writers before
   guarded byte rollback; any subsequent required startup needs a new final comparison.
4. Restore pointer while an owned fixture is foregroundable, then close tracked fixtures
   and release owned specialist/provider resources in their proven dependency order.
5. Restore borrowed Settings/desktop after the last operation; preserve recovery originals
   on conflict or incomplete cleanup.

### Restoration verification

After final writes/startup compare enablement/runtime, fields/bindings, bytes/existence,
Settings/desktop and resource absence. Preserve external changes; disclose retained
sidecars, cache divergence and partial cleanup.

## References

- [Functional checklist](../release-checklist/always-on-top.md) and
  [frozen assertions](../assertion-inventories/always-on-top.json).
- [Owned fixtures](../owned-fixtures.md), [lifecycle](../module-lifecycle.md),
  [typed observations](../ui-observations.md) and
  [recording workflow](../recording-workflow.md).
