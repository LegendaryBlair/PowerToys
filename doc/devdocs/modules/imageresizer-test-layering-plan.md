# Image Resizer test-layering investigation and refactor plan

The [offline execution-flow and coverage diagram](imageresizer-test-layering.html)
visualizes the before/after boundaries, remaining agent E2E paths and the named-pipe
fixture limitation identified after the initial implementation pass.

## Status and decision

- Investigation date: 2026-10-24.
- Scope clarified: 2026-10-25. The reduction target is the agent verification skill's checklist, not the C# UI-test suite.
- Implementation pass: 2026-10-26. Unit/Functional changes and the two-scenario agent checklist are implemented; see section 10 for actual results and the remaining restoration-observer limitation.
- Source baseline: `e466450a791df4348416bea22ccb339d5dc1d69a`.
- Parent branch: `wip/powertoys-verification-20260819`.
- Investigation branch: `wip/image-resizer-test-layering-plan`.
- During the investigation, the branch advanced to `5521a7ae05` with the four pre-existing Settings verification edits. That commit changes none of the Image Resizer production/test sources or Image Resizer checklist/profile inputs analyzed here.
- Change scope: non-UI tests, the verification checklist/profile/inventory and this report. Production code and C# UITests are unchanged.
- Sections 1-9 preserve the investigation baseline and planned approach. Section 10 supersedes their prospective execution status with actual build, test and E2E evidence.

**Recommendation: add or improve Unit and Component/Functional tests, with behavior-preserving production refactoring only where needed, so the agent verification checklist can shrink to a small set of real E2E journeys. Leave the C# UITests unchanged.**

A new test framework or a new production engine assembly is not needed for the pilot. A small extraction of the resize calculation is an optional second step, not a prerequisite for removing repetitive resize matrices from agent verification.

### Exactly three test layers

| Layer | Definition for this pilot | Examples |
|---|---|---|
| Unit | No real external dependencies. Pure logic or mocks/fakes for external boundaries. | Unit conversion, geometry, option precedence, error aggregation with a fake operation. |
| Component / Functional | A bounded part of the product tested with real dependencies; the full user journey is not required. | Real decoder/encoder and temporary files; settings producer/consumer; real batch execution; pipe or CLI adapter tests. |
| E2E | The complete user path in a real product environment, without substituting the product dependencies on that path. | Agent drives Settings and Explorer, resizes owned fixtures, and observes actual output. |

There is no separate Integration layer or category. Tests of component connections and system adapters belong to Component/Functional. Classification follows the dependencies actually exercised, not the project name: a mock batch test that initializes a real settings watcher is not yet an isolated Unit test.

Existing C# UI tests are useful investigation evidence, but adding, repairing, reducing or reorganizing them is outside this pilot. Their repair is not a prerequisite for completing the lower-layer work or redesigning the agent checklist. E2E describes an execution boundary, not a requirement to write C# UI automation.

The goal is compositional confidence:

```text
Unit: rules and failure cases without external dependencies
    + Component/Functional: bounded behavior with real dependencies
    + E2E: a few real journeys in the agent verification skill
    = confidence in the composed feature
```

The old checklist is input for identifying behavior families, not a requirement to reproduce every historical observation in another layer. The projection below explains where confidence comes from and where it is still missing; it is not a claim of 100% execution or a permanent assertion-to-test accounting system.

## 1. Current production boundaries

All module-relative paths in this report are relative to `src\modules\imageresizer`.

| Boundary | Current implementation | Implication for testing |
|---|---|---|
| Settings producer | `src\settings-ui\Settings.UI.Library\ImageResizerSettings.cs:13-48` and the Settings Image Resizer ViewModel | Test the actual settings JSON contract, not only a hand-written approximation. |
| Settings consumer | `ui\Properties\Settings.cs`, including wrapper deserialization, selection recovery, lazy default instance, and watcher | Independent `Settings` instances already support ordinary component tests. Default/watcher behavior has process-global state. |
| Modern Explorer entry | `ImageResizerContextMenu\dllmain.cpp` | Image/type and enabled-state gates; launches the GUI and sends selected paths through a named pipe. |
| Classic Explorer entry | `dll\ContextMenuHandler.cpp` | Separate native adapter; passes selected paths through inherited standard input. |
| GUI | `ui\ImageResizerXAML\App.xaml.cs` -> `ResizeBatch.FromCommandLine` -> `InputViewModel.Resize` -> `ProgressViewModel.StartAsync` | Input saves settings; progress executes the batch, closes on success, or displays results on errors. |
| CLI | `ImageResizerCLI\Program.cs` -> `ImageResizerCliExecutor.Run` -> `CliSettingsApplier.Apply` -> `ResizeBatch.ProcessAsync` | Same ordinary processing engine, but different startup, override, console, and error-reporting adapters. |
| Batch | `ui\Models\ResizeBatch.cs:139-178` | Explicit-settings overload, parallel per-file operations, error aggregation, progress, cancellation. |
| Operation | `ui\Models\ResizeOperation.cs:54-158` | Real Windows decoder/encoder, geometry, file naming, timestamps, replacement and recycle-bin behavior. |

Important qualifications:

- The reusable C# engine currently lives inside `ImageResizerUI.csproj`, not in a UI-independent managed core project. `ImageResizerLib` is a native settings/Shell support library; its name does not identify the managed resize engine.
- "No UI automation" does not mean cross-platform or dependency-free. Current component tests use Windows imaging APIs and reference the WinUI application.
- Resize settings are read from `Image Resizer\settings.json`. The native `image-resizer-settings.json` is written as an empty object by `ImageResizerLib\Settings.cpp`; it is not the processing-option store.
- The GUI uses WinUI (`UseWinUI=true`). The older module overview still contains WPF descriptions; use the current project and source as the architectural evidence.
- AI-related types remain in the source, but normal GUI initialization explicitly selects `NotSupported` and a no-op service in `ui\ImageResizerXAML\App.xaml.cs:137-142`. This pilot must not enable AI, download models, or redefine AI behavior.

## 2. Existing test projects and execution

### Project inventory

| Project | Current role |
|---|---|
| `src\modules\imageresizer\tests\ImageResizer.UnitTests.csproj` | MSTest/Microsoft.Testing.Platform executable; assembly name **`ImageResizer.Test`**, not `ImageResizer.UnitTests`. Mixes pure/model tests with real file and Windows imaging component tests. References `ImageResizerUI.csproj`. |
| `src\modules\imageresizer\tests\ImageResizer.UITests\ImageResizer.UITests.csproj` | MSTest/MTP executable using `UITestAutomation.Next`; real Explorer and GUI tests. Explicitly excluded from the parent unit project's default items. |
| `src\settings-ui\Settings.UI.UnitTests\Settings.UI.UnitTests.csproj` | Additional Image Resizer settings-side tests in `ViewModelTests\ImageResizer.cs`: 18 methods, including data-driven compatibility coverage. These are outside the module totals below. |

There is no separate Image Resizer functional-test project or native Shell-test project in the inspected module tree. Functional testing already exists inside the unit project; creating another project is not required to give it a clear responsibility.

Both module test projects are registered in `PowerToys.slnx:527-534`. The shared props enable MTP; the main build can execute `Build;Test`, while UI tests execute in dedicated jobs. In particular, the native `*UnitTest*.dll` discovery rule is **not** the explanation for running `ImageResizer.Test`: its assembly name does not match that pattern.

Sources: `Directory.Build.props:26-41`, `.pipelines\v2\templates\job-build-project.yml:150-155`, `.pipelines\v2\templates\job-build-project.yml:510-531`, and `.pipelines\v2\templates\job-test-project.yml:253-307`.

### Static test inventory at the investigation baseline

Only tracked source files were counted; generated `obj` files and helper methods were excluded.

| File under `tests` | Test methods | Statically expanded cases | Existing responsibility |
|---|---:|---:|---|
| `Models\ResizeSizeTests.cs` | 20 | 31 | Unit conversion, auto dimensions, percentage height behavior, model notifications. |
| `Models\ResizeOperationTests.cs` | 30 | 30 | Real output dimensions, Fill/Stretch pixel probes, metadata, frame count, naming, timestamps and replacement. |
| `Models\ResizeBatchTests.cs` | 3 | 3 | Argument/stdin collection; mocked per-file error aggregation and progress. |
| `Models\CliOptionsTests.cs` | 26 | 26 | CLI parsing, aliases, flags, enum case, zero/omitted values. |
| `Cli\CliSettingsApplierTests.cs` | 23 | 23 | CLI overrides and custom-size versus preset precedence. |
| `Properties\SettingsTests.cs` | 32 | 36 | JSON, real save/reload, selection recovery, duplicate IDs, model notifications. |
| **Module unit/component total** | **134** | **149** | A substantial base to reuse, not 149 proven passes. |
| `ImageResizer.UITests\ImageResizerEndToEndTests.cs` | **11** | **16** | Shell, presets, single/batch resize, GIF warning and repeated processing matrices. |

The unit total contains six data-driven methods with 21 rows. The UI total contains two data-driven methods with seven rows. Expanded counts are source-derived, not test-runner discovery or executed-test results. No `Ignore` or `Inconclusive` was found in these module test sources; that alone does not establish correctness or reliability.

## 3. Checklist projection

Inputs:

- `.github\skills\powertoys-verification\references\release-checklist\image-resizer.md`
- `.github\skills\powertoys-verification\references\assertion-inventories\image-resizer.json`
- `.github\skills\powertoys-verification\references\modules\image-resizer.md`

At the investigation baseline the frozen inventory was revision 1: **12 scenarios / 18 children**. Its normalized source SHA256 was verified against that original checklist:

`C94D6ECAC7AC1BB7E87BD6974A0D633DF02CEA0DB455EED91C65C0AC3B57B064`

"Existing" below means meaningful source-level evidence, not a runtime PASS. Tests need not use the exact checklist image dimensions to establish the same rule. The C# UI column is a read-only inventory; proposed reductions apply only to agent checklist execution, not those C# tests.

| Scenario | Existing lower-layer evidence | Current UI coverage / limitation | Proposed disposition |
|---|---|---|---|
| `IR-MENU-STATE` | Settings-side enablement test; no module-native test for the two Shell adapters. | `ContextMenuTracksModuleEnabledState` checks the native OS menu: modern on Win11, classic on Win10. It does not check both tiers on Win11, icons, or sibling-command preservation. | Keep a small real Shell gate/selection/launch check. Do not claim a direct engine invocation proves registration. |
| `IR-PRESETS` | `SettingsTests` save/reload, selection-by-ID recovery and deletion fallback; Settings-side create/commit/update/delete tests. | `RemovedAndAddedPresetsPopulateResizeWindow` represents the connection, but its editing flow is stale against this source baseline. | Use the current Settings dialog in the retained agent journey; add a producer-JSON -> consumer -> batch functional test. Leave the C# UI test unchanged. |
| `IR-SINGLE` | Many `ResizeOperationTests` execute real single-file transformations and inspect output. | `ResizesSingleAndMultipleImages` verifies dimensions and output count, not original-file byte preservation. | Lower-layer output/source-preservation assertions; one representative resize in the retained UX. |
| `IR-BATCH` | `ResizeBatchTests` uses real input paths but mocks execution for errors/progress; operation tests cover one operation at a time. | Real multi-file GUI resize exists. | Add a real multi-file `ProcessAsync` component test and a mixed success/failure case. A batch can be the retained UX example. |
| `IR-GIF` | Frame processing is tested by `ExecuteTransformsEachFrame`; no dedicated `HasGifFiles` test. | `GifSelectionShowsAnimationWarning` checks the warning. Its fixture is a single-frame GIF; this is enough for the extension-based warning, not evidence of animation preservation. | Observe warning binding once, preferably within the main journey; keep frame semantics below UI. |
| `IR-FIT-MODES` | `TransformHonorsFitWhenFit/Fill/Stretch` checks dimensions and first-pixel differences; further Fill/ShrinkOnly tests exist. | Three UI data rows, with additional striped-image content probes. | Keep geometry/content cases below UI; retain or strengthen the existing real codec probes rather than repeating all modes in Explorer. |
| `IR-UNITS` | `ResizeSizeTests` exercises every unit; `TransformHonorsUnit` checks real inch conversion. | Four UI data rows at 96 DPI. | Parameterize pure conversions and add a small real-operation non-96/asymmetric-DPI connection check; omit the repeated unit matrix from agent verification. |
| `IR-FILENAME` | `FileNameFormatWorks`, `GetDestinationPathUsesFileNameFormat`, collision, directory and sanitization tests. | UI repeats all six tokens. | Lower-layer ownership; a normal output-name assertion in the main journey is sufficient wiring coverage. |
| `IR-TIMESTAMP` | Real copy and replacement cases with `KeepDateModified=true`. | UI exercises replacement with preservation, not the unchecked control. | Add one false/control case using bounded timestamps and a deliberately old source date. No separate timestamp UI journey. |
| `IR-SHRINK-ONLY` | Upscale prevention, auto width/height, percent exception and Fill interactions are already tested. | UI checks a small image is not enlarged. | Reuse lower cases; add a shrinking-positive case only if the selected existing cases leave that connection unverified. |
| `IR-REPLACE` | `ExecuteReplacesOriginals` uses real replacement; the single-file output helper also constrains residual file count. | UI checks output dimensions and no extra copy. | Keep real file/side-effect component coverage. Do not abstract away replacement and then call the feature verified. |
| `IR-ORIENTATION` | Both direction swaps and auto/percent exclusions have operation tests. | UI covers true and false using Stretch. | Add an explicit false case below UI and preserve Fit rounding; remove the redundant matrix from the agent checklist. |

The main opportunity is not missing arithmetic tests. It is **repeated engine verification in the agent checklist**, a missing real batch connection, and an incomplete settings-producer/consumer connection. Repetition also exists in the C# UI suite, but changing that suite is not the requested work.

Scope not represented by the 12-item checklist must remain visible: CLI process/exit-code behavior, error results and cancellation, encoder options, metadata handling, and dormant AI branches. Existing tests for these must not be deleted merely because they lack checklist IDs.

## 4. Findings that affect confidence

### 4.1 Metadata tests can swallow their own failed assertion

In `src\modules\imageresizer\tests\Models\ResizeOperationTests.cs:548-605`, both metadata-removal tests put `Assert.IsFalse(...)` inside `try` followed by `catch (Exception)`. A failed MSTest assertion can therefore be swallowed as if metadata were unavailable.

This is a test-code confidence problem, not a demonstrated product defect. Before relying on these tests, move assertions outside exception handling and distinguish documented unsupported-metadata results from genuine failures. If the repaired test exposes a product problem, record it separately; do not change production behavior or weaken the test as part of a nominally mechanical refactor.

### 4.2 The preset UX test targets an older UI

The test at `src\modules\imageresizer\tests\ImageResizer.UITests\ImageResizerEndToEndTests.cs:145-209` expects removal/edit buttons and an immediately committed "New size 1" row with an inline editor.

Current production instead creates a working copy and opens `EditSizeDialog`; Add/Update commits it and Cancel does not. See `src\settings-ui\Settings.UI\SettingsXAML\Views\ImageResizerPage.xaml.cs:85-138` and the corresponding XAML.

This is a source-observed mismatch, not a recorded live failure. Record it as an out-of-scope C# UI-test issue. The agent's retained E2E journey should use the current dialog and commit actions; neither repairing this C# test nor restoring the old production interaction is part of the pilot.

### 4.3 Unit fixtures can touch global settings state

- `SettingsTests` changes static `Settings.SettingsPath` to a fixed relative filename and deletes that file during cleanup, without restoring the previous path.
- The two mocked batch tests call the overload that evaluates `Settings.Default`. That can load/create settings and initialize a watcher despite mocked image execution.
- Several tests replace the static resource lookup delegate without restoration.
- `Settings.Reload` contains a legacy-directory migration before loading a file.

Sources: `src\modules\imageresizer\tests\Properties\SettingsTests.cs:32-40`, `src\modules\imageresizer\tests\Properties\SettingsTests.cs:699-707`, `src\modules\imageresizer\tests\Models\ResizeBatchTests.cs:54-103`, `src\modules\imageresizer\ui\Properties\Settings.cs:411-423`, and `src\modules\imageresizer\ui\Properties\Settings.cs:630-640`.

Prefer the existing explicit-settings batch overload. Scope any unavoidable static changes to an owned, already-created directory and restore them; serialize such tests. Test `Settings.Default`/watcher initialization in a dedicated process or disposable profile, with the owned path set before first access. Do not add a public "reset singleton for tests" product API.

### 4.4 Most UI matrix rows configure JSON rather than the corresponding controls

The fit, units, filename and other cases call `ConfigureResizeSettings`, then reopen Explorer and click Resize. They exercise engine behavior through the Shell, but are not complete control-editing matrices for those settings.

The retained agent journey should establish the actual wiring: **change a setting in the real UI and verify that the resulting file reflects it**. The rest of the value matrix belongs in Unit/Functional tests, not repeated agent operations. The existing C# tests remain unchanged.

The current C# helper also restarts Explorer and closes Explorer file windows. Do not execute it on a shared user desktop or copy its cleanup into the agent skill. Agent E2E follows the skill's owned-resource and restoration rules.

Sources: `src\modules\imageresizer\tests\ImageResizer.UITests\ImageResizerEndToEndTests.cs:255-302`, `src\modules\imageresizer\tests\ImageResizer.UITests\ImageResizerEndToEndTests.cs:697-760`.

### 4.5 Preserve actual semantics, including non-obvious exceptions

The checklist's "Fit/letterbox" wording must not be interpreted as a requirement to add padding: the current implementation returns the smaller fitted bitmap. Likewise, `NoTransformNeeded` still passes through encoding; it is not a promise of byte-identical output.

Do not "clean up" either behavior while extracting calculations.

## 5. Target test design

### Lower layers

Keep `ImageResizer.UnitTests.csproj` and its current assembly identity. It can host both Unit and Component/Functional tests. Where useful, use `Unit` and `Functional` categories to distinguish dependency boundaries; these are proposed, not currently available filters. No separate Integration category or C# UI-test project change is planned.

Add only a few focused connections:

1. **Real batch:** multiple owned input files -> explicit `Settings` -> production `ProcessAsync` -> independently decoded outputs, source preservation and no unexpected files.
2. **Mixed failure:** one valid input and one existing corrupt image -> successful output retained, failed input represented by `ResizeError`, no ordering assumption for the concurrent error collection. Also characterize pre-cancelled behavior without inventing rollback of already-completed work.
3. **Settings contract:** serialize a non-default preset/options using the actual `Settings.UI.Library.ImageResizerSettings` producer; load through the module consumer; execute a batch and inspect output. Reuse Settings-side tests for draft/commit/cancel rules.
4. **Selected boundary cases:** unchecked orientation, timestamp false/control, rounding ties and non-96/asymmetric DPI, only where the current suite lacks useful evidence.
5. **Adapter checks:** a small argv/stdin/named-pipe fixture and representative CLI success/failure/exit-code checks. Use synthetic Unicode/space-containing paths and existing production adapters; do not drive Explorer for every input.

A test-only reference to the existing `Settings.UI.Library` may be needed for the producer contract. Do not introduce a production dependency from the engine to Settings UI or duplicate serializer logic in tests.

Use `AssertEx.ImageAsync`, the existing fixture assets and owned-directory helpers where suitable. Strengthen cleanup failures rather than silently ignoring them. For low-level codec checks, compare dimensions, stable pixel landmarks, metadata and file sets; do not require byte-identical re-encoded JPEGs.

### Retained agent E2E checklist

These are proposed verification-skill scenarios, not new or replacement C# `[TestMethod]` methods. They execute the real product path with owned fixtures and the skill's restoration discipline.

**E1 - settings-to-resize business journey**

Create/edit a preset through the current Settings dialog, explicitly commit it, open a real Explorer selection, select the preset in Image Resizer, change a representative resize control if needed, and execute one batch. Verify actual outputs and untouched source files. A GIF can be included to observe warning binding once; animation details stay in the component suite.

This joins producer, consumer, Shell handoff, controls, command, batch and output. It must not pre-seed the very setting whose UI propagation it claims to verify.

**E2 - Shell enabled-state/entry contract**

Disable and re-enable Image Resizer through Settings and observe the actual menu and its selected-file handoff. Cover the distinct modern/classic adapters in the platform compatibility matrix, rather than rerunning all resizing parameters through each adapter. Check command identity/icon at this boundary where practical.

Normally this is modern on Win11 and classic on Win10. The existing C# suite does not establish Win11 classic registration: include a focused agent check for Win11 classic when that deployment path is the compatibility risk being evaluated. A Win10 classic pass alone must not be described as direct Win11-classic execution.

If error-to-results-page wiring cannot be established below E2E, retain **one representative agent error journey**, not one case per exception. Do not force it into an oversized happy-path test merely to improve counts or add a C# UI test for it.

### What the reduction means

The reduction denominator is the verification skill's **12 scenarios / 18 children**, not the 16 statically expanded C# UI cases. The current candidate is one normal business journey plus one Shell scenario, with a representative error journey only if needed. Two agent scenarios versus 12 is approximately 16.7%, before any additional required variants; it is a candidate design, not measured coverage or runtime savings.

An exact 10% quota is not an acceptance condition. Do not conceal Shell/error work outside the count or merge independent failures merely to reach it. The useful outcome is that another fit/unit/error input no longer requires another agent-driven Explorer/UI run. Existing C# UI method counts are unchanged and are not a pilot success metric.

## 6. Behavior-preserving refactor constraints

| Area | Behavior that must remain unchanged |
|---|---|
| Geometry | `Math.Round` behavior, minimum-one-pixel clamp, centered-crop offsets/casts, calculation order and Fit's unpadded output. |
| Auto/percent | Zero/NaN auto handling; Fit uses positive infinity for auto dimensions; non-Stretch percent height follows width. |
| Orientation | Swap only for the existing landscape/portrait mismatch when IgnoreOrientation is true, dimensions are not auto and units are not percent. |
| ShrinkOnly | Existing percent exemption, early no-transform decisions and Fill/crop interactions. |
| Codec/metadata | Fresh versus transcode routing, JPEG quality and other encoder options, frame handling, fallback extension, best-effort metadata and rendering-critical metadata preservation. |
| Naming/output | CurrentCulture token formatting, six-token meanings, sanitization, directory support, collision suffixes, timestamps, replacement and recycle-bin behavior. |
| Settings | JSON property names/types, defaults, preset IDs, first-load versus later selection recovery, watcher timing and dispatch, and legacy migration. |
| Batch/CLI | Same accepted inputs/overrides, one shared settings reference per existing batch call, parallel error aggregation, progress/cancellation and exit-code behavior. A shared reference is not an immutable settings snapshot. |
| Product boundaries | No Shell registration, packaging, elevation, GPO, AI enablement, public API, or module IPC contract changes. |

The relevant geometry source is `src\modules\imageresizer\ui\Models\ResizeOperation.cs:414-502`; conversion is `src\modules\imageresizer\ui\Models\ResizeSize.cs:73-125`. Encoding and side effects remain in `ResizeOperation`.

New validation, atomic rollback, altered retries, a different resampling algorithm, changed defaults, stronger cancellation, or "fixing" an odd existing rule are behavior changes, not this refactor. Any discovered product defect needs a separate decision and change.

## 7. Implementation sequence

| Phase | Changes | Completion evidence |
|---|---|---|
| P0 - baseline and trustworthy lower-layer tests | Record Unit/Functional builds/runs; repair the assertion-swallowing tests; isolate settings/resource fixtures; use the explicit-settings batch overload in mocked tests. C# UI issues remain recorded and out of scope. | Lower-layer failures are visible and attributable. Known baseline failures are recorded, not relabeled as refactor regressions or hidden by weaker assertions. |
| P1 - Unit/Functional additions | Add the real batch, mixed-failure, producer/consumer and selected boundary cases above. Keep existing meaningful codec tests. Classify by actual dependencies, with no separate Integration tier. | The composed resize result is tested without Explorer. A deliberately incorrect expected output or broken error path is caught during development. |
| P2 - optional geometry extraction | Move the existing calculation into one internal helper in the current UI assembly, called from the same point in `ResizeOperation`. Preserve inputs, arithmetic and result semantics. Reuse the existing test access granted to `ImageResizer.Test`. | Characterization cases agree before/after; existing real decoder/encoder output tests still pass. Skip extraction if the pilot gains no meaningful testability or execution benefit. |
| P3 - smaller agent checklist | Redesign the verification skill checklist around E1/E2 and any necessary distinct risk. Remove repeated rule/error matrices on the basis of Unit/Functional coverage and a reasoned composition argument, not one-to-one replacement records. | The remaining real-product paths are clear and the proposed agent workload is smaller. No C# UITests are added, repaired or removed. |
| P4 - agent verification rollout | Run the retained agent E2E paths, then publish the reviewed checklist/profile and matching inventory revision with supporting lower-layer test commands. Update recorder inputs together rather than silently skipping frozen children. | Actual control edits, Shell handoff and final output are observed; review can explain the composition without replaying every old assertion. Historical reports are unchanged. |

### Deliberately deferred changes

- Do not split out `ImageResizer.Core` merely to make the dependency graph look cleaner.
- Do not replace every file operation with mocks or add a new general-purpose test host.
- Do not redesign the settings singleton/watcher in the initial pilot. The existing explicit-settings overload and isolated process tests should be tried first.
- Do not extract the entire progress workflow. If deterministic testing of error/cancel projection is blocked specifically by its dispatcher, consider only a narrow internal dispatch seam with the unchanged production default; otherwise use one error UX.
- Do not add, repair, remove or reorganize C# UITests, including the stale preset test, or change the Next framework.
- Do not expand the pilot into AI, installer, GPO or unrelated Settings refactors.

Likely implementation changes are in the module's non-UI test files/project, optionally Settings-side unit tests, and optionally `ui\Models\ResizeOperation.cs` plus one internal geometry helper. A producer-contract test may add a test-only project reference. The reduction deliverables are the verification skill's Image Resizer checklist/profile and matching assertion inventory. The C# UI-test source and project are excluded. Any production refactor must preserve the business behavior in section 6.

The initial investigation did not implement P0-P4. The subsequent implementation status is recorded in section 10.

## 8. Planned validation, not executed results

Use repository build scripts and then the produced MTP executables; do not substitute `dotnet test`. Build to exit code 0 before execution. Install/restore missing dependencies only when required by manifest changes or an actual missing-dependency failure.

From the repository root, the focused build command for Unit/Functional implementation is:

```powershell
.\tools\build\build.cmd -Path src\modules\imageresizer\tests -Platform x64 -Configuration Debug
```

Build the Settings unit project only if its tests or dependency graph change:

```powershell
.\tools\build\build.cmd -Path src\settings-ui\Settings.UI.UnitTests -Platform x64 -Configuration Debug
```

Resolve the exact output produced by the successful build, rather than guessing its TFM/RID directory. Run `ImageResizer.Test.exe` from its output directory: several existing tests use relative fixture paths. Example after setting `$testExe` to that attested executable and `$results` to an absolute owned results directory:

```powershell
Push-Location (Split-Path -Parent $testExe)
try {
    & $testExe --report-trx --report-trx-filename image-resizer.trx --results-directory $results
    if ($LASTEXITCODE -ne 0) { throw "Image Resizer tests failed: $LASTEXITCODE" }
}
finally {
    Pop-Location
}
```

New `Unit`/`Functional` categories must actually be added before they are used as filters. Check discovered/executed counts, failures and skips in TRX; an empty filtered run is not evidence. No C# UI-test build, repair or execution is a prerequisite for this pilot; those tests remain separate existing coverage.

For agent E2E, select the intended installed or built/sideloaded product through the verification skill's bits-under-test contract. Use the current product's real Settings dialog, not the stale C# test flow. Shell validation needs a registered/signed compatible package; registration is gated by build configuration in `src\modules\imageresizer\dll\dllmain.cpp:51-58`. Do not repair missing registration by mutating the shared host.

Use isolated real Windows environments for the retained agent E2E paths, covering the relevant modern/classic Shell and architecture risks. Record which environments were actually exercised rather than inferring a full platform matrix. The shared props disable ordinary ARM64 test-target execution, so "ARM64 built" does not mean "ARM64 tested."

During implementation, retain old meaningful component outcomes, compare before/after decoded outputs on identical fixtures, and confirm the production diff does not change the invariants in section 6. This is behavioral-equivalence validation, not a demand for one test per old checklist child.

## 9. Original investigation outcome (before implementation)

| Check | Result |
|---|---|
| Branch created from the requested current branch | Created `wip/image-resizer-test-layering-plan` at the recorded baseline. |
| Pre-existing verification work | Left untouched by this task; now present in commit `5521a7ae05` on the investigation branch. |
| Test and production project XML inspected | Four module project files parsed successfully. |
| Static test inventory | 134 module unit/component methods; 11 UI methods; separate 18 Settings-side methods. |
| Checklist projection | All 12 scenario families analyzed; 18-child revision/hash verified. No runtime verdicts assigned. |
| Build, unit/component execution, live UI and CI run | Not run: this deliverable is the requested investigation/plan, with no product/test implementation. |
| Production refactor | Not started. The bounded, behavior-preserving options and their prerequisites are documented above. |
| 2026-10-25 scope clarification | Exactly three layers; add/improve Unit and Component/Functional tests, reduce the agent skill checklist, and leave C# UITests unchanged. |

The investigation recommended P0/P1 before deciding whether P2 was worth doing. The following implementation pass followed that ordering.

## 10. Implementation results - 2026-10-26

This section records the first implementation pass. Section 11 supersedes its
named-pipe fixture and current test totals; the archived E2E results remain unchanged.

### Delivered changes

- Reused `ImageResizer.UnitTests.csproj`; added a test-only, aliased reference to the actual Settings serialization library. The alias prevents the producer assembly's global `Settings` namespace from colliding with the module's `Settings` type.
- Removed the broad exception handlers that could swallow metadata assertions.
- Added an assembly-owned mock resource provider and serialized test execution; replaced the fixed settings filename with a unique, existing directory whose original static path is restored after each scoped test.
- Changed mock batch tests to pass explicit settings, so they do not initialize the real default settings/watcher. Made owned-directory cleanup failures visible.
- Added four Functional methods: real multiple-image batch/source preservation, mixed successful/corrupt input, actual Settings producer JSON driving real output, and named-pipe Unicode selection driving processing.
- Added pre-cancelled batch coverage, unchecked timestamp preservation, independent X/Y image DPI, and two half-pixel rounding cases. The settings-contract test also exercises `IgnoreOrientation=false` with a portrait target.
- No production extraction was needed. No production algorithm, settings contract, dependency version or C# UI-test source was changed.

Named-pipe boundary clarification: that first Functional fixture used a byte-mode pipe
and a BOM-writing `StreamWriter`, whereas the native modern-menu sender uses message mode
and raw UTF-16/CRLF without a BOM. It sends one path and directly supplies `CliOptions`,
so this is a receiver-side functional smoke, not full native protocol or startup coverage.
At that point, the stronger no-BOM/multiple-path/`FromCommandLine` variant was only a
recommendation. It is now implemented with the pending-task boundary described below.

This adds eight test methods / nine expanded cases: the full non-UI suite now has
**142 methods / 158 cases**, compared with the original 134 / 149. Existing meaningful
tests were retained. `Functional` identifies the real-image operation and new composition
classes; the three mock batch cases use `Unit`. Older mixed classes are not falsely
classified wholesale, and the unfiltered run remains the complete suite.

### Build and dependency blockers resolved

The default build initially failed before test execution. The local VS 18 Build Tools
installation lacked the managed SDK resolver; the complete VS 2022 installation selected
.NET 9 and lacked its own Spectre libraries. Explicit SDK resolution plus the installed
VS 18 native toolset allowed the existing repository build script to run without disabling
Spectre mitigation or changing repository build files.

The process-local build configuration used:

- An official .NET SDK 10.0.100 installed under this session's artifact directory.
- VS 2022's developer environment/MSBuild host and VS 18's v145 native targets/tools
  (`14.51.36231`, including its existing x64 Spectre libraries).
- `DOTNET_MSBUILD_SDK_RESOLVER_SDKS_DIR`, `DOTNET_MSBUILD_SDK_RESOLVER_SDKS_VER` and
  `MSBuildEnableWorkloadResolver=false`, limited to the build process.
- The documented `/p:SkipLongPathsCheck=true` option; no machine registry setting was changed.
- Explicit `SolutionDir` and native-tool paths in the session-only `ir-build.rsp`.

The original PowerToys feed returned 401 for `System.Text.Json` 10.0.10; direct NuGet.org
access failed TLS negotiation. A session-only NuGet configuration mapped that exact
package to Microsoft's `dotnet-public` feed, where the same version was available.
Other dependencies continued using the original PowerToys feed. Repository sources,
version pins, TLS verification and credentials were not changed.

An initial VM availability probe found no configured VM root. The user then explicitly
excluded that skill/backend; no VM was created or used. All tests and E2E execution
described here ran on the existing local Windows host.

### Actual validation

Commands below describe the executed operations; the environment setup and response file
above were applied to the build/restore calls. Complete command lines and logs are retained
as session artifacts, including `ir-build.rsp`, `ir-nuget.config`, `ir-mirror-restore.log`
and `ir-build.log`.

| Operation | Result |
|---|---|
| `tools\build\build.cmd -Path src\modules\imageresizer\tests -Platform x64 -Configuration Debug @<session>\files\ir-build.rsp /t:Restore /p:RestorePackagesConfig=true /p:RestoreConfigFile=<session>\files\ir-nuget.config` | Passed, exit 0, after resolving the feed issue. |
| `tools\build\build.cmd -Path src\modules\imageresizer\tests -Platform x64 -Configuration Debug @<session>\files\ir-build.rsp` | Passed, exit 0, with existing build analyzers enabled. |
| `ImageResizer.Test.exe --filter TestCategory=Functional --report-trx --report-trx-filename functional.trx --results-directory <results> --timeout 3m` | First run: 37/38 passed. The new mixed-input test had incorrectly required a nonempty native exception message. That additional requirement was removed; failure identity, successful output and source-preservation assertions remain. |
| `ImageResizer.Test.exe --report-trx --report-trx-filename full.trx --results-directory <results> --timeout 4m` | Passed: **158 executed, 158 passed, 0 failed, 0 skipped**; approximately 3 seconds reported by MTP. |
| `.github\skills\powertoys-verification\scripts\tests\Test-PtAssertionInventory.ps1 -Workspace <owned-results>` | Passed: reduced Image Resizer inventory and all other module inventory contracts. |
| `dotnet format whitespace . --folder --include Models\ResizeBatchTests.cs Models\ResizeOperationTests.cs Models\ResizeSizeTests.cs Models\ResizeFunctionalTests.cs Properties\SettingsTests.cs Test\TestDirectory.cs Test\TestEnvironment.cs Test\SettingsTestScope.cs --verify-no-changes --verbosity diagnostic` from the test directory | Passed: all eight selected C# files already formatted; no changes required. |
| `git diff --check` and scoped production/C# UITests diff inspection | Passed; no production or C# UI-test changes. |

The actual test executable was built under
`x64\Debug\tests\ImageResizer.Test\net10.0-windows10.0.26100.0\win-x64`.
It ran from that directory so existing relative fixture paths resolved.
This is a validated post-isolation suite, not a claim that an untouched pre-change
baseline was executed: the original baseline attempt was blocked by the toolchain.

### Revised agent checklist and live E2E

Inventory revision 2 reduces **12 scenarios / 18 children to 2 scenarios / 5 observations**.
That is an 83.3% scenario-count reduction and a 72.2% child-count reduction; neither is
code coverage or measured execution-time reduction. New IDs explicitly distinguish the
narrower E2E scope from historical exhaustive reports.

The agent ran the revised checklist against **installed PowerToys 0.102.2933.0**, using
official stable **winapp 0.7.1**, without replacing installed binaries:

| Agent E2E | Observed outcome |
|---|---|
| Settings-created preset -> actual Explorer PNG/GIF selection -> resize | **PASS**, all three observations. A temporary Fit 100 x 100 preset created through the current dialog appeared in the module; the GIF warning was visible; one Resize action produced exactly PNG 100 x 50 and GIF 100 x 100 copies with the expected names. Both originals retained their SHA256. |
| Live disable/enable -> modern/classic Shell menus -> launch | **PASS**, both observations. The entry disappeared on both menus when disabled, returned with its icon when enabled, and the classic entry launched a usable module window that Cancel closed. No Explorer or Runner restart was used. |

These installed-build observations and the locally built lower-layer suite have distinct
artifact identities. They are not represented as a source-identical installed build.

### Restoration limitation and release status

**Overall E2E signoff is WITHHELD, despite all five behavior observations passing.**

Exact original bytes/existence were verified for general settings, Image Resizer settings
and `sizes.json`; original disabled state was restored. The temporary preset, image files
and owned windows were removed. Original navigation-group expansion, native placement,
foreground and pointer were restored.

Full Settings content-page/scroll restoration could not be certified. The original helper
snapshot recorded `DashboardNavItem` together with `PageScrollViewer`; the subsequently
displayed Home page exposed `MainScrollViewer`, and UIA also returned duplicated
`SuggestionsList` entries with the same runtime ID. The agent attempted normal snapshot
restoration, physical Home navigation and transient-popup dismissal, then stopped rather
than rewriting the original baseline or concealing the mismatch.

The remaining issue is in the Settings preservation/observation boundary, not the resize
engine. Fixing the generic helper retrospectively cannot prove an original content-page
identity that was not captured. The module profile now calls for recording the actual
visible heading and validating the restoration baseline before navigation. Generic helper
changes and C# UI-test repairs were not included in this pilot.

### Persistent evidence and cost

The validated archive is:

`%OneDrive%\PowerToys\Module-Signoff\verify-ImageResizer-layering-8fdaf669bf23404d9c949c9fcae085c5`

It contains `report.md`, `details.md`, results, screenshots, original input snapshots,
the lower-layer TRX, and inline agent-origin statistics. Archive integrity validation
passed before and after moving it: **617 registered files**, run
`f05a61c14e7941f7a3aeb7d830a4ed36`, signoff **WITHHELD**.

The closed E2E execution segments contain 46 direct agent tool requests and approximately
1,038 seconds of lifecycle wall time, excluding identified reporting gaps. Recorded outer
driver work was 23.265 seconds for the main journey and 44.999 seconds for Shell checks;
Shell discovery/absence handling caused three recorded driver errors before successful
observations. These are exploratory pilot costs, not a steady-state benchmark. No old
12-scenario run was executed for a runtime comparison.

The lower-layer/checklist work is implemented and validated. Unqualified release signoff
remains blocked on trustworthy Settings page/scroll preservation, and Windows 10/ARM64
execution and CLI process-exit cases remain outside this local validation evidence.

## 11. Shell selection -> pending batch - 2026-10-27

### Semantic contract and implementation

Replaced `NamedPipeSelectionPreservesUnicodePathsAndProcessesImages` with
`ShellSelectionCreatesExpectedPendingBatch`, with two data rows: 2 and 128 real PNGs.
Both include paths with spaces, Chinese text, an accented character and a surrogate
pair, plus a corrupt `.png` and an unsupported `.txt`.

The test ends at the **pending task**, before user confirmation:

```text
Owned files
  -> small native test process constructs a real IShellItemArray
  -> production CreateSelectionPipe / WaitForSelectionPipeClient / WriteShellSelection
  -> message-mode named pipe, raw BOM-free UTF-16 paths + CRLF
  -> production ResizeBatch.FromCommandLine (full pipe argument)
  -> pending Files and DestinationDirectory
```

The exact supported file set must arrive, without loss or extra entries. The `.txt`
is filtered; the corrupt `.png` remains because this stage checks existence and
extension, not image decoding. The ordinary modern-menu input has no destination
override. No extra files appear and source bytes remain unchanged. The 128-image
case transfers more than the native pipe's 16 KiB buffer capacity in aggregate.
It does not claim that an individual Windows file path exceeds that buffer size.

Production changes only extract the existing pipe creation, connection and selection
write operations into `ImageResizerContextMenu\ShellSelection.h`. The real modern
command calls those same functions. Per-item Shell interfaces and allocated paths
are now scoped to the iteration. Message format, selection rules, pipe flags, GUI
launch, elevation behavior and resize algorithms are unchanged.

`tests\NativeTests\ImageResizer.NativeTests.vcxproj` builds one small console helper,
not a second test suite or general-purpose service. The existing managed test project
builds/copies it, and `PowerToys.slnx` includes it. It creates its pipe before reporting
readiness; the test uses bounded waits and terminates only its owned child on failure.
Neither process loads the Shell module's settings singleton or registers a COM server.

### Covered and deliberately not covered

- Covered: real Shell selection objects, native path enumeration/framing, production
  message-mode pipe setup, cross-process file-list delivery, real command-line parsing,
  filtering and pending-task contents.
- Not covered: Explorer/MSIX/COM activation, menu visibility/icons, the actual `Invoke`
  wrapper, GUI process launch via `RunNonElevatedEx`, permission/elevation variants,
  classic anonymous-pipe/stdin inheritance or `/d` handling, option rendering or user
  confirmation. No `ProcessAsync` call is made by this test.
- Missing-after-selection and connection-failure matrices are not claimed. The helper's
  arguments construct its fixture; they do not substitute for real Explorer activation.

The existing agent checklist stays at **2 scenarios / 5 observations**. This strengthens
the evidence under it; it does not justify deleting the remaining Shell/GUI journeys.

### Validation

Current source inventory is **142 methods / 159 expanded cases**. The test remains in
the `Functional` class; replacing one case with two adds one expanded case, not a new
test layer. The complete non-UI suite passed **159/159**, with no failures or skips.

| Command / operation | Result |
|---|---|
| `tools\build\build.ps1 -Path src\modules\imageresizer\tests\NativeTests -Platform x64 -Configuration Debug @<session>\files\ir-build.rsp` using VS 18 | Passed, exit 0, with native code analysis/warnings-as-errors. |
| `tools\build\build.ps1 -Path src\modules\imageresizer\ImageResizerContextMenu -Platform x64 -Configuration Debug /p:PostBuildEventUseInBuild=false @<session>\files\ir-build.rsp` using VS 18 | Passed, exit 0; actual production DLL compiled/linked. Sparse-MSIX packaging was excluded, not claimed successful. |
| `tools\build\build.ps1 -Path src\modules\imageresizer\tests -Platform x64 -Configuration Debug /p:BuildProjectReferences=false @<session>\files\ir-build.rsp` using VS 2022 and the session SDK overrides | Passed, exit 0, against separately built native artifacts and existing managed dependencies. |
| `ImageResizer.Test.exe --filter FullyQualifiedName~ShellSelectionCreatesExpectedPendingBatch --report-trx --report-trx-filename pending-batch.trx --results-directory <results> --timeout 1m` | Passed, 2/2. |
| Negative control: temporarily skip the first selected item in the shared native sender, rebuild the helper and run the same filter | Both cases failed on the missing pending file (expected 3/129, actual 2/128). The mutation was removed and final native/managed artifacts rebuilt. |
| `ImageResizer.Test.exe --report-trx --report-trx-filename full.trx --results-directory <results> --timeout 4m` | Final pass: 159 executed/passed, 0 failed/skipped; approximately 9 seconds. |

The split toolchain is an environment workaround: the VS 2022 host could not load
the VS 18 compiler task's `System.Text.Json` dependency, while the VS 18 installation
lacks complete managed SDK resolution/dependencies. No repository SDK/package pins,
security flags or machine installation were changed. The default modern-menu build
also failed in MakeAppx with sharing violation `0x80070020`; only its packaging
post-build event was disabled for native-code validation. Packaging/install behavior
is outside this test's scope.

Final TRX and negative-control evidence are retained in session artifact directories
`ir-selection-full-results`, `ir-pending-batch-results` and `ir-pending-batch-negative`;
build logs use the `ir-selection-*` prefix. These new local results do not change the
earlier installed-build E2E signoff/restoration limitation.
