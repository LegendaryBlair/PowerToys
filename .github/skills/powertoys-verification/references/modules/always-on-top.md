# Always On Top - module verification profile

## Module facts

| Fact | Value |
|---|---|
| Module | `AlwaysOnTop`; source `src\modules\alwaysontop\`. |
| Runtime | Native resident `PowerToys.AlwaysOnTop.exe`; verify path/PID/start/session. Settings is separate WinUI 3. |
| Configuration | `%LOCALAPPDATA%\Microsoft\PowerToys\AlwaysOnTop\settings.json`; root `settings.json`: `enabled.AlwaysOnTop`. |
| Bindings | Defaults: Win+Ctrl+T, Win+Ctrl+OEM Plus/Minus. Discover all three current bindings and the actual keyboard layout. |
| Events | `AOT.Pin`, `AOT.IncreaseOpacity`, `AOT.DecreaseOpacity` bypass binding recognition, **not foreground targeting**. |
| Surfaces | Tracking class `AlwaysOnTopWindow`; border `AlwaysOnTop_Border`, composed behind its target. |
| Readiness | Ordinary target/appearance, scoped shortcut, constant-alpha and attributed-audio methods are available. Specialist conditions need separate readiness evidence; the archive defines actual supported scope. |

## Entry paths

Prepare [baselines](#fixtures-and-restoration) and a compatible-integrity owned target.
Never pin or change opacity on borrowed windows.

| Intent | Entry | Destination / guard |
|---|---|---|
| Configure | [Settings entry](settings.md#entry-paths), `AutomationId=AlwaysOnTopNavItem` | Snapshot before navigation; confirm page content. |
| Configured binding | Foreground owned target; complete current chord | Separate delivery, native state and composition. |
| Window menu | Enable option; open target's real title-bar system menu | Check Alt+Space launcher conflicts; no guessed command IDs. |
| Downstream diagnosis | Matching shared event, same foreground guard | Not binding coverage or listener-readiness proof. |
| Palette integration | Extension's Always On Top Settings command; [palette profile](command-palette.md) | Preserve query/history/favorites/provider lifetime first; not a pin action. |

## UI state-transition map

Settings and target coexist. The three enabled target states below are independent of
highlighting, exclusions and alpha values.

| Current state | Trigger / condition | Next state | State landmarks |
|---|---|---|---|
| Disabled | Enable; policy permits | Unpinned | Exact resident and ordinary target available. |
| Unpinned | Pin eligible target | Pinned visible | Same target; resident tracking surface available. |
| Unpinned | Pin excluded or Game Mode-blocked target | Unpinned | Same foreground target. |
| Pinned visible | Unpin | Unpinned | Same target HWND. |
| Pinned visible | Minimize | Pinned minimized | Target iconic; resident remains. |
| Pinned visible | Maximize/resize | Pinned visible | Refreshed placement/frame identities. |
| Pinned minimized | Restore | Pinned visible | Non-iconic target and refreshed frame. |
| Any enabled target state | Disable; no borrowed pins affected | Disabled | Exact resident exits; Settings remains. |
| Settings page | Open uniquely scoped editor | Shortcut draft | Owned dialog, key artwork, Save/Cancel. |
| Shortcut draft | Save valid binding | Settings page | Dialog closed; original page. |
| Shortcut draft | Cancel draft | Settings page | Dialog closed without Save. |
| Settings page | Custom mode; open color button | Color flyout | ColorPicker channel/hex inputs. |
| Color flyout | Dismiss | Settings page | Flyout absent; live color edit remains. |

`Any enabled target state` spans all three. Observe arrival before continuing;
dismissal does not undo live edits.

## Control locator and interaction index

Inspect the exact HWND with `Invoke-PtWinApp`; rediscover type/Name/ID/parent/pattern
on other builds/locales. `x:Uid` is not a selector. Re-resolve after transitions and
never choose the first repeated control.

| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| Select page | Navigation | `AutomationId=AlwaysOnTopNavItem` | Realize; supported Select/Invoke; inspect content. |
| Toggle enablement | Enable card | Owner `AlwaysOnTopEnableToggleControlHeaderText`; `Button` Name `Always On Top`, TogglePattern | ScrollItemPattern before [Resident lifecycle](../module-lifecycle.md), including cleanup. No kill/relaunch. |
| Expand activation | Enabled page | Owner `AlwaysOnTopActivationShortcut`; local Button with ExpandCollapsePattern | Expand; distinguish the same-caption shortcut EditButton. |
| Edit shortcut | Pin/increase/decrease row | Owner ID `LayoutRoot` AND actual Name; child `Button` ID `EditButton` | [Recorder](../shortcut-recorder.md): both `WithinAutomationId` and `WithinName`; snapshot, Save/Cancel, read and drive bindings. |
| Toggle highlighting | Expanded border card | Owner `AlwaysOnTopFrameEnabled`; `Button` Name `Show a border around the pinned window`, TogglePattern | Distinguish the same-caption expander; retain pinned target for live change. |
| Select color mode | Highlighting on | Owner `AlwaysOnTopFrameColorMode`; `ComboBox` Name `Color mode` | `Select-PtComboBoxItem`: actual `Custom color` / `Windows default` option. |
| Set custom color | Custom mode | Owner `AlwaysOnTopFrameColor`; unique Button; flyout hex `Edit` | Invoke; rediscover hex Name/ID and ValuePattern. Live RGB/ARGB edit; Escape dismisses. |
| Set border slider | Highlighting on | Owners `AlwaysOnTopFrameThickness` / `AlwaysOnTopFrameOpacity`; Sliders `Thickness (px)` / `Opacity (%)` | Realize; RangeValuePattern within actual range; live, no Save. |
| Toggle option | Corners/Game Mode/menu card | Actual localized `CheckBox` Name | Toggle/read; corners require Windows 11; preference is not fullscreen proof. |
| Toggle sound | Enabled sound card | `Button` Name `Play a sound when pinning a window`, TogglePattern | Toggle/read; rediscover localized Name. Audio is a separate observation. |
| Edit exclusions | Expanded exclusions | Owner `AlwaysOnTopExcludedApps`; unique multiline `Edit` | ValuePattern; preserve private original; collision-checked owned executable only. |
| Send command | Owned eligible foreground | Non-UI: exact identity/current chord | Guarded `Send-PtChord`; events keep the foreground guard. |
| Invoke window menu | Real title-bar system menu | Fresh owner; localized `MenuItem` | Inspect/invoke/reopen check state; no index/internal-message substitute. |
| Read target | Owned window | Non-UI: `Get-PtAlwaysOnTopWindowState` identity | Marker/style/alpha availability/frame/DPI; not pixels or verdict. |
| Check execution | Before effects | `Assert-PtAlwaysOnTopExecutionReady`, exact target/peer PIDs | Session/integrity/desktop; `RequireInput` for input availability, `RequireForeground` before target-directed input. |
| Invoke palette Settings | Installed extension; baseline saved | Actual title/subtitle/Settings command | Palette profile; favorites and locale are distinct conditions. |
| Check updates | Enablement baseline saved | [Settings controls](settings.md#control-locator-and-interaction-index) | Check only; no install/download or automatic-update preference change. |

### Read-out notes

- Use `Read-PtSharedFileText`; missing/schema/read errors are not defaults. Scalar
  `properties` keys `frame-enabled`, `frame-thickness`, `frame-color`,
  `frame-accent-color`, `frame-opacity`, `round-corners-enabled`, `sound-enabled`,
  `show-in-system-menu`, `do-not-activate-on-game-mode`, `excluded-apps` use `.value`.
  Binding objects are at `properties.<hotkey|increase-opacity-hotkey|decrease-opacity-hotkey>.value`;
  compare every key/modifier field.
- `LayoutRoot` repeats. English owner Names are `Activation shortcut`, `Increase opacity`
  and `Decrease opacity`. Supply both owner predicates; the receipt binds both through
  restoration. Preflight temporary chords against current bindings, Windows registration
  and actual key-name mapping; registration cannot discover all third-party hooks.
- Marker, topmost, visible precedence and border pixels are independent. Associate borders
  by module process, target frame/desktop and transition, not nearest distance. Use passive
  lossless composed crops on an owned opaque backdrop, not flattened layer captures.
  After Settings edits, bring that backdrop above borrowed windows before capturing the
  pinned target. Focusing only the target leaves borrowed pixels around it.
- Native frame/capture coordinates are physical; do not scale twice. Compare colors as
  explicit ARGB: opaque `#RRGGBB` equals `#FFRRGGBB`, but preserve exact original bytes.
- Window alpha is not frame opacity. `Wait-PtAlwaysOnTopAlphaChange` compares against the
  **post-pin** observation and rejects unavailable/null/color-key-only samples. Keep the
  pre-pin alpha/flags/color-key separately for restoration; unsupported is not opaque.
- `Get-PtAlwaysOnTopDesktop` reads membership, not desktop ownership.
  `Get-PtAlwaysOnTopGameMode` reads actual exclusive-D3D notification state, not preference.
  In `scripts\tests\fixtures\AlwaysOnTopD3DFixture.cs`, construct `PtAotD3DFixture` with an
  owned WinForms Form and HAL (1) or reference (2) device on its UI thread. Independently
  recheck notification state before input. D3D itself can set topmost: establish the
  fixture baseline before testing the module. Never repeat a chord until a marker appears.
- `scripts\tests\fixtures\ProcessAudioMeter.cs` exposes a bounded `PtProcessAudioMeter`
  for exact PID/start-time and duration. Arm before input, finish, dispose in `finally`.
  It samples session peaks across active render endpoints and checks endpoint stability.
  Require exclusive non-system attribution, unmuted positive volume, initial silence,
  a complete post-input interval and a positive control before interpreting sound-off
  silence. No mixer mutation, PCM recording, sound-file proxy or physical-listening claim.

## Troubleshooting

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| Shortcut ineffective | Identity/foreground/integrity, full binding, enablement, exclusions/fullscreen, lifecycle | Accepted input is not delivery; no automatic restart/elevation. |
| Border missing/flattened | Highlighting, minimize/desktop, association, composed capture | Wrong/occluded layer is not a visual defect. |
| Alpha unchanged/unavailable | Pin marker, root target, renderer, non-bound alpha; retain read errors | Unsupported renderer is not supported-window failure. |
| Repeated shortcut rows | Actual parent ID AND Name, HelpText, persisted binding | No ordinal or fabricated owner. |
| Menu command absent | Option, actual system menu, foreign command ID | Collision must survive; unavailable observer is not absence. |
| Color restore button absent | Restore custom color in custom mode, then original color mode | Accent mode hides the custom-color owner. |
| Specialist observer missing | Implement/validate fixture; continue independent cases | Authoring gap, not product inability. |
| Restoration disagreement | Stop dependent mutations; retain baseline/writer/conflict | Never replace originals with defaults or new snapshots. |

## Fixtures and restoration

### Resource inventory

| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| `scripts\tests\Show-PtDesktopFixture.ps1` | Ordinary pin/overlap/keys | `Start-PtOwnedProcess`; unique state directory, ready receipt and HWNDs | Unpin, compare alpha, normal tracked closure | Exact process/windows absent; selected thread-layout receipt agrees. |
| Settings/desktop | Navigation/input | Shared snapshots; borrowed identity remains borrowed | Shared restore; close only creation-proven Settings | Original page/expansion/scroll/placement/pointer; disclose draft/IME/focus limits. |
| Module/root files and placement | UI/lifecycle | Private named-file bytes/existence plus semantics | UI values first; conflict-guarded byte cleanup with quiescent owned writers | Original bytes/existence and runtime/cache after final writes/startup. |
| Sidecar/log namespace | Activation | Bounded original names/existence; existing logs product-owned | Only attributed new additions removable | Report deltas; no directory-wide cleanup/equality claim. |
| Layered/menu-collision target | Specialized conditions | Owned classic fixture; original alpha/flags or foreign caption/action | Restore before release | Original attributes/command behavior; generic target insufficient. |
| Virtual desktop | Desktop isolation | Owned GUID and complete pre-existing desktop identity set | Proven create/switch/remove path before mutation | Original membership/set; no adjacency-based deletion. |
| `AlwaysOnTopD3DFixture.cs` | Exclusive fullscreen | Owned Form/device; original style/bounds/topmost/display | Unpin, dispose on UI thread, restore fixture before baseline comparison | Original mode/placement/topmost; fullscreen notification ends. |
| `ProcessAudioMeter.cs` | Sound | Exact owned module; read-only endpoint/session meters | Finish worker; dispose interfaces/event | Completed valid observation; endpoint/volume/mute unchanged. |
| Elevated/clean/disposable session | Conditional cases | Separately authorized owned context | Scoped cleanup; never log off shared desktop | Original state; ordinary UI scope grants no extra authority. |
| Palette/query/history/favorites/provider | Integration | Private baseline; declare provider processes before activation | Restore UI/persistence/cache; stop only creation-proven providers | Original state and borrowed lifetime, not merely favorite removal. |

### Helper boundaries

`scripts\tests\Test-PtAlwaysOnTopPinDesktop.ps1` is finite infrastructure acceptance,
not full R0/R1. It requires initially disabled/absent module and already-visible Settings.
`InspectOnly` navigates/restores without input or pin claims; full mode adds guarded owned
pin/unpin. Rediscover its localized enable-toggle Name. Native state alone proves neither
pixels nor sound.

[Tracking](../session-safety.md) is not restoration; [byte rollback](../directory-snapshots.md)
is not cache restoration. Respect absence-capable guards and keep recovery originals on conflict.
Desktop identity, menu collision, mixed-integrity and borrowed palette preservation need
their own validated mechanics; warnings are not capabilities.

Legacy documents can omit opacity bindings/menu state and serialize loaded defaults or
normalize ARGB after an ordinary UI edit. Preserve exact originals. Before snapshotting
an omitted binding, read all three editor HelpTexts, perform a reversible UI serialization
and require unchanged displayed bindings. Do not seed JSON or infer missing values.

Restore UI semantics first, then validate every original field and version-confirmed
default addition. Shortcut IPC can normalize root version `0.0.1` to native `1.0`;
only that source-confirmed transition is eligible for cleanup-only
`Restore-PtFileSnapshot -ExpectedState`, after the owned writer stops and expected bytes
remain stable. Reject unexplained fields/concurrent changes. Pass callback state explicitly
or use unique script-scoped names; recorder callbacks can shadow generic `$original`.

### Restoration order

1. Release input/dialogs; restore bindings, appearance and exact exclusions. Restore
   custom color while custom mode is visible, then original color mode.
2. Unpin; release exclusive devices/restore fixture style before comparing original
   topmost/layered state. Reset case mutations before closing targets.
3. Realize enable toggle; restore enablement without borrowed pins. Quiesce owned
   writers before guarded byte rollback; later startup requires another final comparison.
4. Restore pointer while an owned target remains foregroundable, then close tracked
   fixtures and release specialist/provider resources in dependency order.
5. Restore borrowed Settings/desktop after the last operation; preserve recovery data
   on conflict or incomplete cleanup.

### Restoration verification

Compare enablement/runtime, fields/bindings, bytes/existence, Settings/desktop and resource
absence after final writes/startup. Preserve external changes; disclose retained sidecars,
cache divergence and partial cleanup. Matching pointer coordinates need no second write.

## References

- [Checklist](../release-checklist/always-on-top.md) and [assertions](../assertion-inventories/always-on-top.json).
- [Owned fixtures](../owned-fixtures.md), [lifecycle](../module-lifecycle.md),
  [observations](../ui-observations.md), [recording](../recording-workflow.md).
