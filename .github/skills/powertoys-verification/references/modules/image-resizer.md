# Image Resizer - module verification profile

## Module facts

| Fact | Value |
|---|---|
| Source | `src\modules\imageresizer` |
| GUI | `<install>\WinUI3Apps\PowerToys.ImageResizer.exe` (WinUI 3) |
| CLI | `<install>\WinUI3Apps\PowerToys.ImageResizerCLI.exe` |
| Processing settings | `%LOCALAPPDATA%\Microsoft\PowerToys\Image Resizer\settings.json` |
| Enabled flag | General `settings.json`, `enabled."Image Resizer"`; change through Settings |
| Shell | Modern sparse-package command and classic `ImageResizerExt.dll`; selected image files |
| Activation | Explorer **Resize with Image Resizer**; no module hotkey or Named Event |

### Three-layer coverage

This module is a pilot for **Unit + Component/Functional + E2E**. The
[checklist](../release-checklist/image-resizer.md) now contains two real user journeys.
Its [inventory revision 2](../assertion-inventories/image-resizer.json) has new IDs;
it is intentionally narrower than the previous exhaustive checklist, not a regrouping
that retains every old matrix.

The lower-layer suite is `src\modules\imageresizer\tests\ImageResizer.UnitTests.csproj`
(MTP executable `ImageResizer.Test.exe`). Its directory name does not imply that every
test is isolated Unit coverage:

| Behavior | Lower-layer ownership |
|---|---|
| Unit conversions, auto/percent, CLI parsing/override rules | `ResizeSizeTests`, `CliOptionsTests`, `CliSettingsApplierTests` |
| Actual dimensions, Fill/Stretch content, orientation, rounding, DPI | `ResizeOperationTests` using real Windows imaging |
| Names, metadata, timestamps, replace and source preservation | `ResizeOperationTests`, `SettingsTests`, `ResizeFunctionalTests` |
| Real multiple-image and mixed success/failure batches | `ResizeFunctionalTests` |
| Settings UI serializer -> module consumer -> output | `ResizeFunctionalTests.SettingsUiJsonDrivesRealBatchOutput` |
| Native modern-menu selection -> real pipe -> pending batch (no processing) | `ResizeFunctionalTests.ShellSelectionCreatesExpectedPendingBatch` |
| Error aggregation, progress and pre-cancelled behavior | `ResizeBatchTests` with explicit settings and mocked operations |

Before relying on this smaller release scope, identify the relevant lower-layer run and
its source/artifact revision, failures and skips. Missing lower-layer evidence is a
release-confidence limitation, not an instruction to label unobserved UI PASS or silently
expand the agent run into the old checklist. The remaining E2E cases still need real
observations. Exact historical input-to-test mappings are not required.

Build the focused project with `tools\build\build.cmd -Path src\modules\imageresizer\tests`
and run the successfully built `ImageResizer.Test.exe --report-trx` from its output
directory so relative fixtures resolve. Use the repository's platform/configuration
options. The existing C# UITests are separate coverage and are not modified by this pilot.
See `doc\devdocs\modules\imageresizer-test-layering-plan.md` for the design and execution results.

## Entry paths

| Intent | Entry | Boundary |
|---|---|---|
| Create the representative preset | Existing Settings -> Image Resizer -> Add size -> explicit Save | Current versions use a dialog/working copy; do not assume an immediately committed inline row |
| Real selection/activation | Owned Explorer -> select image files -> context menu -> Resize with Image Resizer | Required for the E2E journey and Shell handoff |
| Classic entry on Windows 11 | Same selection -> Show more options -> Resize with Image Resizer | Different Shell adapter; observe separately from the modern entry |
| Engine diagnosis | CLI with owned inputs and output directory | Same batch/operation engine, but cannot substitute for the checklist's real UI entry |
| GUI diagnosis | Direct GUI launch with quoted file arguments | Does not prove Explorer registration or selected-file transfer |

Before navigating a borrowed Settings window, preserve it with
`Get-PtSettingsUiSnapshot` and establish the paired restoration path. Preserve original
enablement and processing settings before mutation. Use
[owned Explorer fixtures](../owned-fixtures.md) and the
[shared context-menu flow](../explorer-context-menu-flow.md); do not restart Explorer
or terminate unrelated windows.

Record the actual visible Settings page heading as well as the selected rail item.
A rail selection alone need not identify the displayed content page. If the baseline
and its page/scroll restoration cannot be identified unambiguously, stop before
navigation rather than discovering that mismatch during cleanup.

## Control locator and interaction index

Resolve one current, scoped and typed control before acting. Runtime slugs and localized
Names are not permanent IDs. The CLI syntax comes from the pinned tool's help.

| Interaction | UI state and scope | Locator | Action |
|---|---|---|---|
| Navigate to Image Resizer | Settings main window | `ImageResizerNavItem`, under `FileManagementNavItem` | Expand group if needed, select destination |
| Enable/disable | Image Resizer Settings page | Scoped module ToggleSwitch | Toggle once and observe persisted flag; preserve original value |
| Add preset | Image sizes card | `AddSizeButton` | Invoke, inspect the actual modal editor |
| Edit draft fields | Current add/edit dialog | Scoped Name, fit, dimensions and unit controls | Set values/select options; read back before commit |
| Save preset | Same dialog | Localized primary Save/Update button | Invoke once; wait for dialog dismissal and committed preset |
| Remove owned preset | Exact uniquely named preset row | Row menu and Delete/Remove action | Invoke and confirm only that preset's deletion |
| Select Explorer inputs | Owned Explorer window and folder | Exact fixture paths | Shell selection helper; verify selection before opening menu |
| Launch from menu | Actual modern/classic menu | Exact localized Resize with Image Resizer MenuItem | Invoke; observe one usable GUI receiving selection |
| Choose preset | Image Resizer input page | `SizeComboBox` | Expand, select the exact temporary preset and read back |
| Copy rather than replace | Same input page | Localized overwrite/replace CheckBox | Set Off and observe actual state |
| GIF warning | Input page with GIF selected | InfoBar/text for GIF animation warning | Read visible text; do not infer warning from file extension alone |
| Process | Input page | Localized Resize Button | Invoke once; wait for actual completion or results/error page |
| Cancel | Owned resize window | Localized Cancel or window Close | Close without processing; verify owned window exit |

### Read-out notes

- Processing settings use wrapped `properties.imageresizer_*` fields in `settings.json`.
  The native `image-resizer-settings.json` is an empty legacy/support store, not the
  processing-options source. A legacy `sizes.json` may exist; preserve it if touched.
- Defaults and algorithms are not inferred from the observed UI. Establish known fixture
  dimensions/DPI and calculate the selected preset's expected output independently.
- For Fit, expect the fitted image dimensions, not a padded canvas. Half-pixel dimensions
  follow the current rounding rule; do not change the fixture oracle to conceal a mismatch.
- Compare the exact output file set, names and decoded dimensions, plus original bytes.
  A missing window or a zero CLI exit code alone is not proof of correct images.
- The GIF warning is extension-based. Use an actual animated fixture for this user journey;
  animation/frame correctness is covered separately below E2E.
- Module enablement does not mean package registration is removed. Observe actual menu
  presence/absence; the installed package can remain registered while its command is hidden.

## Troubleshooting

| Symptom | Diagnose/recover | Interpretation boundary |
|---|---|---|
| Preset does not appear | Check explicit Save, committed settings, actual module file, and exact dialog/selection | Direct JSON seeding cannot rescue a failed UI-to-module connection |
| Old inline edit selectors fail | Inspect the current ContentDialog and its primary action | Adapt the agent interaction, not production behavior or C# UITests |
| Menu absent | Confirm image selection, native menu readiness, module enabled state and correct menu tier | A direct GUI/CLI launch is diagnostic, not menu PASS |
| Absence query exits with code 1 | Use `Invoke-PtWinApp -AllowNoMatches` with an explicit search | Accept only the helper's validated complete zero-match response, not arbitrary command failures |
| Duplicate modern menu matches | Scope to the full observed popup rather than all Explorer windows; deduplicate identical UIA runtime identities | The toolbar popup can expose the same menu descendants; never choose an arbitrary caption match |
| Classic menu missing in process-scoped discovery | Observe the exact Show more options transition and find its visible `#32768` window | The classic menu can be hosted outside the owned Explorer process; do not assume the original PID |
| Can't inject input | Record foreground and session attachment; try a supported UIA entry where equivalent | Concrete environment blocker, not a resize defect |
| Only one output or wrong name | Compare actual selection, original files and output set before cleanup | Do not repeat Resize blindly or infer selection from the expected result |
| Settings restoration unsupported | Preserve the baseline and report the exact missing observer/restore capability | Do not navigate or overwrite unrelated user state to simplify the run |

## Fixtures and restoration

Use a uniquely owned image folder and preset name. Record Settings navigation/placement,
module enabled state, all processing settings that the GUI may save, source bytes and
owned window identities. Preserve the desktop state required by the shared helpers.

Restore in this order: finish/dismiss any owned modal or processing window; remove the
owned preset and restore changed options/enablement; verify settings against the original
baseline; close the owned Explorer and remove fixture files; restore borrowed Settings
navigation/placement and foreground/pointer. Use guarded snapshots if exact rollback is
needed, never an unconditional overwrite of unexplained concurrent edits.

## Source citations

- `ui\ImageResizerXAML\App.xaml.cs`, `InputViewModel.Resize`, `ProgressViewModel.StartAsync`:
  GUI entry, settings commit, batch invocation and success/error projection.
- `ui\Cli\ImageResizerCliExecutor.cs`, `ui\Models\ResizeBatch.cs`:
  shared processing engine, stdin/named-pipe inputs and explicit-settings overload.
- `ui\Models\ResizeOperation.cs`, `ui\Models\ResizeSize.cs`: actual image and conversion rules.
- `ImageResizerContextMenu\dllmain.cpp`, `dll\ContextMenuHandler.cpp`:
  modern/classic gate and selected-file handoff.
- `src\settings-ui\Settings.UI\SettingsXAML\Views\ImageResizerPage.xaml.cs`:
  working-copy Add/Edit dialog and explicit commit.
