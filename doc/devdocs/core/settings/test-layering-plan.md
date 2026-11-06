# Settings test layering: investigation and implementation plan

## 1. Scope and conclusion

Investigated on **2026-10-26**, against this worktree at `5521a7ae05`, not an
independently refreshed upstream branch. This is a source-based investigation and
plan, not a Settings test execution or release signoff.

Start with **General, Home, and Quick Access**, including their Settings/Runner IPC
and persistence paths. Settings is a more demanding second pilot than Image Resizer:
it coordinates shared state, separate processes, Windows integration, and rendered UI.

Use exactly three layers:

| Layer | Definition | Settings examples |
|---|---|---|
| Unit | No real external dependencies; pure inputs or mocked collaborators | Date formatting, sorting, state projection, JSON contracts, action selection |
| Component / Functional | A bounded product workflow with selected real dependencies | Production named pipes, native dispatch, temporary settings files, real watchers, live ViewModels |
| E2E | Actual installed/built product and real environment | Tray entry, real module activation, actual Settings/Quick Access windows, elevation and rendering |

The purpose is to remove repetitive logic/error matrices from the **agent verification
checklist**, not to create another comprehensive UI suite. Logical composition is
sufficient: tested components plus a few representative connections do not require
replaying every lower-layer case in E2E.

Constraints:

- Preserve business behavior, JSON contracts, defaults, side-effect ordering, and
  thread/lifetime assumptions during refactoring.
- Do not add, repair, remove, or reorganize existing C# UITests in this pilot.
- Do not use the local-VM skill or create VMs. Cases requiring reboot, installation,
  elevation, or policy changes remain conditional on separately authorized fixtures.
- Do not reduce the frozen Settings checklist until replacement evidence exists.
- Do not turn a discovered defect into an undocumented behavior-changing refactor.

**IPC can and should be tested at the Functional layer.** This checkout already
contains real-pipe tests. The missing Settings-specific connection is primarily
message generation -> native application -> persistence -> live-model refresh,
not the complete absence of transport tests.

## 2. Current baseline

### 2.1 Checklist and test inventory

The [Settings checklist](/.github/skills/powertoys-verification/references/release-checklist/settings.md)
contains **25 scenarios / 50 child observations**, inventory revision 4. Its normalized
source SHA-256 is
`3712DD59CF0F5DFEC0D8CAB155EFECE977B4353F290827064E092B1D6B98F912`.
The [module profile](/.github/skills/powertoys-verification/references/modules/settings.md)
defines the corresponding operating and preservation boundaries.

Counts below are source test methods unless otherwise specified. They are not pass
counts, unique business requirements, or code-coverage measurements.

| Existing location | Inventory | What the source establishes |
|---|---:|---|
| `src\settings-ui\Settings.UI.UnitTests` | 145 methods in 23 test files | Mostly module ViewModel/property/serialization tests; not 145 General tests or necessarily 145 isolated Unit tests |
| `ViewModelTests\General.cs` | 9 methods; 13 cases after its five-row parameterized method expands | Mainly defaults, property changes and outgoing JSON; no proof of actual startup, elevation, tray effects, or live cross-surface synchronization |
| `ModelsTests\SettingsUtilsTests.cs` | 4 methods | Mock-filesystem settings behavior |
| `ModelsTests\SettingsRepositoryTest.cs` | 2 methods | Singleton identity, including concurrent acquisition; not file-watcher delivery |
| `ShellViewModelTests` / `OobeShellViewModelTests` | 6 / 1 methods | Shell metadata/error-handler behavior and OOBE ordering |
| `ScoobeReleaseTests` | 3 methods | Release grouping and prerelease JSON behavior |
| `Settings.UITests` | 1 navigation method, 32 DynamicData rows | Next-framework navigation smoke; asserts process survival, not correct visible content |
| Legacy `UITest-Settings` | 1 module-state method and 2 OOBE methods | Module-state process assertions are commented out |
| `src\runner\UnitTests` | 1 method | Hotkey conflict detector; production general-settings/IPC dispatch is not in the test project's compilation graph |
| `src\common\updating\UnitTests` | 36 methods | Update decisions plus real-file updater backup/recovery tests; not General-page backup/restore |
| `src\common\interop\interop-tests` | 1 method | Two production managed IPC wrappers exchanging a real named-pipe message in one process |
| `UnitTests-CommonUtils\TwoWayPipeMessageIPC.Tests.cpp` | 18 methods | Native pipe lifecycle, cancellation, fault injection, ACL/QoS and listener ownership; includes one Workspaces-specific pipe case |
| `UnitTests-CommonUtils\PipeCallerAuth.Tests.cpp` | 7 methods | Mixed pass-through/version checks and real-pipe caller identity/cache checks |

The supporting Settings test rows are subsets of the 145, not additional methods.
Common IPC tests are shared infrastructure, not Settings business-coverage counts.
Many tests named `UnitTests` already belong to Functional under the definitions above.

### 2.2 Evidence strength and principal gaps

| Concern | Current evidence | Missing evidence for shrinking E2E |
|---|---|---|
| General preferences | Some sender-side JSON/value assertions | Real receiver application, persistence, unrelated-field preservation |
| Friendly dates and update display | Production formatter and separate Home/General readers | Boundary/culture tests, live refresh, update check preserving preferences |
| Home / Quick Access sorting | Production implementations | Sort/identity rules and propagation through the shared persisted preference |
| Module enablement | Module-specific ViewModel tests; sparse shell/UI smoke | Partial native updates, policy outcomes, persisted state and existing live consumers |
| Settings persistence | Mock-file operations and singleton identity | Real write -> watcher -> reload -> subscriber chain, cleanup and isolation |
| IPC transport | Substantial shared native tests; one managed send test | Settings payloads, receiver dispatch/application, representative reply handling |
| User backup/restore | Production implementation; no direct tests found in Settings suite | Actual archive round trip, merge/exclusion rules and errors using owned paths |
| Themes, accessibility, lifecycle | A little shell/release metadata coverage | Pure decision tests where useful; actual HWND/rendering/focus behavior remains E2E |

No direct tests were found in the inspected Settings suite for `FriendlyDateHelper`,
`DashboardViewModel`, `AllAppsViewModel`, `QuickAccessViewModel`,
`RefreshUpdatingState`, `SettingsBackupAndRestoreUtils`, or `ThemeService`.

There is **no defensible overall coverage percentage** from these counts. The baseline
is partial lower-layer rule coverage, useful shared IPC coverage, and a weak
Settings-specific middle layer. No Settings or IPC suite was run for this report.

Two existing test names particularly need careful interpretation:

- `SettingsUtilsMustReturnDefaultItemWhenFileIsCorrupt` uses an empty mock filesystem,
  not a corrupt file: its current fixture proves missing-file fallback.
- `AllModulesAreEnabledByDefault` checks seven flags, including intentional false
  values; it does not establish every module's default.

## 3. Actual execution boundaries

```text
Settings General / Home                 Quick Access All apps
  ViewModel -> outgoing JSON              coordinator -> outgoing JSON
               \                           /
                production managed IPC wrapper
                             |
                 real Windows named pipes
                             |
          Runner caller authentication + receive callback
                             |
                 dispatch onto Runner UI thread
                             |
             production JSON dispatch / application
                  /                         \
       general settings / module state      action / response
                  |                         |
       save settings + OS/module effects    update work / reply
                  |
       actual settings file watcher / repository reload
                  |
       same living ViewModels -> rendered controls
```

This is not universally a request/reply protocol. In particular:

- General preferences and module-page toggles such as Color Picker send full
  `{"general": ...}` snapshots.
- Home and Quick Access All apps module toggles send
  `{"module_status": {"ModuleName": boolean}}`.
- Home and Quick Access sort changes send a full General snapshot.
- Runner also handles `powertoys`, `refresh`, `action`, and other message types.
  Use current production spelling, not a reconstructed protocol from older docs.
- General/module-state UI synchronization depends on saved files and subscribers;
  Quick Access's receive callback currently only logs messages.
- `Send()` queues work. A successful return, including Quick Access's `true` result,
  is **not an acknowledgement of Runner execution or disk persistence**.

The stages are compositional boundaries, not a requirement to introduce that many
interfaces, test projects, or architectural layers.

The final watcher-to-model edge is **consumer-specific**, not automatic for every
Settings ViewModel. The follow-up trace in section 10 identifies working subscription
paths and missing ones; the diagram is not evidence that all pages already synchronize.

### Shared state and lifecycle facts that must be preserved

**Home and Quick Access share one `GeneralSettings.DashboardSortOrder`.** Their
separate selection/reopen checks do not imply two independent stored preferences.
Both implement in-place collection movement, and sorting guards depend on dispatcher
scheduling. Do not replace collection identity or scheduling merely to simplify tests.

Quick Access's `AllAppsViewModel` is distinct from the shared launch-list
`Settings.UI.Controls.QuickAccess.QuickAccessViewModel`. Both need the appropriate
coverage; proving launch-tile visibility does not prove All apps sorting/live toggles.

Closing the main Settings window while a secondary is open hides the main window.
Closing the final secondary can then close the hidden main and terminate Settings.
A decision test cannot replace actual HWND/process-lifetime evidence.

## 4. Safe refactoring prerequisites

### 4.1 Isolate before running a General baseline

`GeneralViewModel` construction currently reads real update state, GPO, language and
diagnostic preferences, and **deletes diagnostic files older than 28 days** under the
user's LocalAppData/LocalLow PowerToys directories. The existing test subclass only
overrides dispatcher acquisition; it does not isolate those side effects.

Introduce narrowly scoped injectable collaborators/overloads for the actual required
dependencies: update-state loading, policy/diagnostic preferences, language/resource
access, clock, retention operation and dispatcher. Production defaults must perform
the same work at the same point; tests use fake collaborators or owned fixtures.
Do not move retention out of the production constructor as an incidental refactor.

`SettingsRepository<T>` also needs safe local-instance construction for tests:

- Its singleton and `SettingsUtils` are static per closed generic type; the first
  acquisition wins. Existing mocks do not make that process-global state local.
- Watcher construction uses real directories and `FileSystemWatcher`.
- Preserve the production singleton entry point. Add an internal scoped construction
  path rather than a public global reset switch.
- Own and dispose watchers/subscriptions; tests must not reuse a disposed singleton.
- Inject a deterministic queue for Unit tests, but exercise a real dispatcher in a
  focused Functional fixture where scheduling matters. No Settings window is needed.

A null dispatcher is not evidence that live notifications work.

### 4.2 Characterize coupled behavior, do not silently correct it

`GeneralViewModel.NotifyPropertyChanged` both raises a notification and sends a full
General snapshot. Update-state refresh uses this path. Runner's `check_for_updates`
action calls `apply_general_settings` before starting the update check.

This coupling warrants a regression test with non-default preferences, a nontrivial
enabled map, and an already-open consumer. It is a **source-observed risk**, not a
reproduced defect. Characterize message shape/order and persisted outcomes first.
Suppressing existing writes, adding acknowledgements, changing snapshots to patches,
or changing stale-update behavior would be a separate behavior change.

Likewise, keep native defaults, module-policy precedence, early returns and the
single-module update's actual handling of input intact. Do not make malformed input
stricter or broaden a single-module command into a batch under a testability refactor.

## 5. IPC Functional design

### 5.1 Reuse the existing transport, not an imitation

`TwoWayPipeMessageIPCManaged` delegates to the same native `TwoWayPipeMessageIPC`
implementation used by Runner. Its production framing is message-mode Windows pipes
carrying wide-character strings. The receiver reads in 1,024-byte blocks.

The existing managed test uses two real wrappers in one process, unique pipe names,
one short string, a startup sleep, and a bounded callback wait. That is already a
Functional transport test, but not Settings semantics or process-launch coverage.
Native tests compile the actual transport and caller-authentication implementation.

Extend those foundations rather than building another generic IPC framework:

| Functional slice | Real production parts | Controlled boundary | Claim / non-claim |
|---|---|---|---|
| F-IPC-TRANSPORT | Managed wrapper, native transport, Windows pipe, callback | Owned pipe names and endpoint lifetime | Unicode/escaped JSON, payload across read-block boundaries, representative bidirectional traffic; no Settings application claim |
| F-IPC-DISPATCH | Production Settings/Quick Access message producer, pipe, native JSON dispatcher | Recording handlers for selected actions; owned scheduling fixture | Actual message routes and arguments; recording a call does **not** prove it saves settings |
| F-IPC-APPLY | Above plus actual selected native application logic and actual file writer | Owned settings root, controlled module/policy inputs, fake OS/module side-effect adapters | Correct persisted state and unchanged unrelated settings for that route; no real module activation claim |
| F-IPC-REFRESH | Actual file, repository, watcher and living General/Home/Quick Access models | Owned paths/resources; actual dispatcher for the scheduling-sensitive slice | Notification and state convergence without reconstruction; no XAML rendering claim |
| F-IPC-PROCESS | Representative production managed/native endpoints in separate owned helper processes | Test-specific identity policy and temporary root | Cross-process lifetime/handle/transport behavior without full product startup; not installed binary/signature/elevation proof |

These are test slices inside the middle layer, **not five more testing layers**.
Not every case needs all stages or a second process. A few composed flows connect the
separately tested boundaries.

### 5.2 Small extraction needed on the native receiver

Today `dispatch_received_json` resides in `settings_window.cpp`, calls global Runner
services, and is reached through the Runner UI-thread dispatcher. Linking the entire
Runner and using a real user profile would defeat isolation.

First extract the existing parser/route selection with narrow handler callbacks,
keeping the production call site and behavior unchanged. Compile that same code into
Runner tests. This enables F-IPC-DISPATCH without pretending that a fake receiver
implements native application behavior.

Next expose only the dependencies needed for selected application routes: settings
read/write location, module lookup/state, policy values and OS action adapters.
Functional fixtures keep real JSON and disk I/O but record OS/module actions. Use the
real `apply_module_status_update` / selected General application code, not a test-side
reimplementation. If a route cannot yet be isolated safely, label it deferred.

Keep the production main-thread handoff. A deterministic executor can cover dispatch
contracts, but a focused real message-pump test must cover any extracted thread
adapter; a full installed E2E journey still establishes actual Runner wiring.

Use existing managed/native test projects first. Only add a minimal test-only helper
executable if a cross-process C#/native contract test cannot reuse existing hosts.
It must load the production components, not simulate the Runner algorithm. No
production hidden testing mode, general-purpose test service, or full Runner clone.

### 5.3 First Settings-specific cases

1. **General snapshot round trip:** serialize a non-default General configuration,
   transmit it, apply through the real receiver slice, read the owned file through
   the real repository, and verify selected values plus the complete enabled map.
2. **Quick Access partial update:** actual producer emits `module_status`; native
   application changes only the requested module state. Verify unrelated module and
   General values, including the shared sort preference, are preserved.
3. **Live cross-surface update:** keep original model instances alive while the
   watcher processes the previous write. Verify values, collection order/identity,
   checked sort selection and launch-list eligibility without manual refresh.
   Use separate scoped repositories over the same file to avoid accidentally proving
   only shared-object mutation inside one process. Start with subscribed Home/All apps
   consumers; do not assume existing module-page models subscribe (see section 10).
4. **Update-check isolation:** actual action envelope and selected native action
   handler, with only the network/check worker controlled. Write an owned
   `UpdateState.json`, verify date projection and unchanged preferences. Home's
   `CheckUpdateControl` currently loads state separately; a common formatter or
   recreated Home model alone cannot establish its live refresh.
5. **Representative response:** use the existing `bug_report_status` query and
   `bug_report_running` response, with controlled status and no report generation;
   exercise both directions and the extracted production response consumer. Do not
   invent a reply for `general` or `module_status`.

Run transport data cases below E2E: Unicode and escaping, payload just below/at/above
the actual read block size, multiple controlled messages, and shutdown while
read/write work is pending. Reuse existing cancellation/fault-injection coverage.
Characterize disconnect behavior; do not introduce or claim durable delivery,
automatic replay, global ordering, or exactly-once semantics that the protocol does
not promise. Test outcomes at the receiver/disk, never only `Send()` returning.

### 5.4 Authentication and environment boundaries

Both Settings and Quick Access Runner endpoints apply caller policies with expected
installation directory, executable basename, own version and Microsoft signature.
The source explicitly notes Debug's signature-check difference.

Existing caller-auth tests use real connected pipes and the test process's identity.
The matching-caller case skips version matching and disables signature requirements;
it does not prove acceptance of a shipping Settings binary. The managed `Start()`
wrapper uses the ungated overload.

Keep these distinctions:

- Transport fixtures may test transport alone with their existing ungated test server.
- Authentication fixtures test the real authentication implementation using an
  explicit test-host identity policy. Never weaken shipping policy to admit a helper
  or rename an unsigned helper to impersonate an installed executable.
- Real restricted-token/DACL tests already cover useful local boundaries without a
  full product UI. Do not duplicate them in every Settings scenario.
- Actual install path/version/signature composition and normal/elevated process
  startup remain a small number of real-environment checks. No claim that all ACL or
  authentication behavior must stay in E2E.

Fixture requirements: per-test GUID pipe names, bounded synchronization, callbacks
that capture results for assertion on the test thread, owned process IDs, deterministic
shutdown and explicit failure artifacts. Do not use live Settings/Runner pipe names.
One existing native test uses the fixed Workspaces Launcher/Arranger pipe name:
exclude it from unattended shared-host IPC runs unless that fixture is explicitly safe.

## 6. Implementation sequence and exit criteria

| Step | Changes | Evidence required before proceeding |
|---|---|---|
| 1. Isolate and establish baseline | Characterize constructors; inject only unsafe dependencies; scoped repositories, files, clocks/resources and cleanup | Existing relevant tests run without touching real settings, diagnostics, registry or active pipes; repeated execution has no fixture leakage |
| 2. Fill Unit rule gaps | Friendly-date boundaries/fallbacks; shared sort and stable-item rules; General update projection; shortcut clear/notification rules; module/policy input decisions | Focused cases fail for the missing/wrong behavior and pass through the same logic used by production; no pure-helper extraction left unwired |
| 3. Connect persistence and IPC | Real writer/watcher/live-model tests; extend shared transport only where missing; extract native dispatch then selected application seams | F-IPC-DISPATCH is distinguished from F-IPC-APPLY; one General and one partial-module path establish meaningful composed behavior |
| 4. Cover remaining local workflows | Actual user backup/archive/restore, resource/link contracts, lifecycle/theme decisions; reuse updater tests | Each case states real and fake boundaries; backup round trip proves actual file values, not merely callbacks |
| 5. Propose and execute reduced agent journeys | Retain real launch, visual, lifecycle and authorized OS boundaries; use safe owned Settings sessions | Successful lower-layer evidence plus representative live E2E and exact cleanup; preservation failures withhold signoff |
| 6. Publish the coverage projection | Update checklist, frozen inventory, profile and counts together, only after the preceding evidence | Old concern groups accounted for, residual conditional cases visible, no claim that renamed/grouped headings alone saved verification work |

The first implementation cut should be **steps 1-3**: General isolation,
shared-state persistence/live refresh, and the two main IPC payload types.
Backup is valuable but has enough unrelated state to deserve a subsequent atomic
change. Do not begin with a broad GeneralViewModel rewrite.

### Test placement

Keep General/persistence tests in `Settings.UI.UnitTests`, common transport cases in
the existing interop/common projects, and native Settings receiver cases in Runner's
test project. Classify Unit/Functional cases without requiring separate projects.

The current Settings test project does **not** reference the Quick Access executable.
Prototype a test reference to its real assembly with narrow internal visibility for
the relevant models/producer; resolve WinUI hosting and shared projections before
committing to the combined fixture. If the application dependency graph prevents
clean isolation, a small non-UI Quick Access test project is preferable to copying
its classes into a test implementation. Follow sibling shared-props imports and
solution/test-discovery conventions. Do not add a project solely to rename a layer.

### Backup and resource work in step 4

There are two different backup implementations:

- `SettingsBackupAndRestoreUtils`: user-triggered General backup/restore. It uses a
  singleton, HKCU metadata, working-directory configuration, actual files and archive
  extraction. Even `RestoreSettings(appBasePath, backupDir)` calls a helper that
  resolves the latest archive through global metadata. Passing temporary arguments
  alone is not sufficient isolation.
- `common\updating\configBackup.h`: updater protection. Existing tests already cover
  real-file backup/recovery. Its corruption predicate detects embedded NUL bytes,
  not all malformed JSON. These tests do not cover the General backup workflow.

Inject owned metadata/configuration/path access for the user-backup fixture; keep real
archive and merge code. Test distinctive General + module values, exclusions,
overwrite-versus-merge behavior, missing/corrupt archive and relevant I/O failures.
Characterize its return tuple: `Success == false` can accompany severity `"Success"`
when a restart is not required. Preserve that contract.

Current restoration writes files sequentially. Do not claim transactional rollback or
silently add it. A partial-write regression is a separate defect, not permission to
change behavior during extraction.

Resource/link contract tests can remove repetitive attribution target/key checking,
but they cannot prove translated words fit, controls bind the correct key, Markdown
uses the chosen theme, or a screen reader announces the correct live state.

## 7. Candidate residual agent checklist

**Current actual count remains 25 / 50. No Settings checklist was changed by this
investigation.** A possible later organization is eight routine journeys and four
conditional environment journeys. This is a planning partition, not an achieved
25 -> 12 reduction: repeated assertions must actually move down before that count
can represent less work.

| Proposed journey | Real E2E obligation retained |
|---|---|
| R1. Settings shell/lifetime | Tray/module entry, singleton navigation, real page rendering, main-hidden/secondary-return/final-exit boundaries |
| R2. Shared module state and sort | Home + existing Quick Access/representative module page, shared sort across reopen, actual module action; selected runtime archetypes remain distinct |
| R3. Quick Access/tray/shortcut | Actual launch, left/right tray routes, enable/disable, physical changed/cleared chord, icon visibility |
| R4. Update-check wiring | Actual check without install, non-default preferences unchanged, Home and General live/reopened display |
| R5. User backup/restore | Actual picker and long-path presentation, distinctive General/module values restored and any real restart |
| R6. Theme rendering | Settings/secondary content and caption buttons, live theme changes and adaptive tray icon |
| R7. Language wiring | Actual language restart, retained integrity, Settings + Quick Access localization and representative rendered attributions |
| R8. Layout/accessibility | Real narrow/wide Home and secondary layout, focus/keyboard/screen reader, actual conflict-window startup |
| C1. Elevation | Restart and retained administrator preference with actual process tokens |
| C2. Reboot/startup | Real automatic startup and integrity across reboot |
| C3. Install/update | Clean-profile first render; updater backup/recovery/relaunch; update-available badge through update |
| C4. Diagnostic policy | Actual authorized GPO, disabled managed diagnostics and successful independent package generation |

C3 still contains **three separately accountable fixture-dependent cases**; a grouped
heading is not evidence of their elimination. Routine journeys also retain multiple
observations. Report scenario counts, retained observations, conditional runs and
actual effort separately.

The following projection accounts for all 25 existing scenarios without demanding
one new test per old child:

| Existing scenario ID | Lower-layer destination | Residual journey |
|---|---|---|
| SET-MAIN-WINDOW | Route/lifetime decisions | R1 |
| SET-NAVIGATION | Page/resource/title/new-feature metadata consistency | R1; retain all-page render sweep until composition evidence justifies narrowing |
| SET-DASHBOARD-SORT | Sort rules, shared persistence and live model refresh | R2 |
| SET-DASHBOARD-STATE | Partial/full message application and watcher propagation | R2 |
| SET-DASHBOARD-LAYOUT | Only any extracted pure layout rules | R8 |
| SET-DASHBOARD-ACCESSIBILITY | Resource/metadata contracts only | R8 |
| SET-RESTART-ADMIN | Command/elevation decision inputs | C1 |
| SET-STARTUP | Startup/policy decisions and command contracts | C2 |
| SET-MODULE-STATES | Full enabled-map matrix, persistence, empty-state rules | R2; retain distinct in-process, standalone and shell runtime connections |
| SET-QUICK-ACCESS-STATE | Enablement/launch-route decisions | R3 |
| SET-QUICK-ACCESS-LAUNCH | Module-to-launch-action mapping | R3 |
| SET-QUICK-ACCESS-SYNC | Existing model instances, real file notification and sort/eligibility | R2 |
| SET-QUICK-ACCESS-BINDING | Clear/reset contract and subscription behavior | R3 |
| SET-TRAY-VISIBILITY | Preference serialization and tray-action decisions | R3 |
| SET-TRAY-THEME | Theme-to-icon selection | R6 |
| SET-THEME | Theme selection/notification decisions | R6 |
| SET-LOCALIZATION | Resource/attribution target contracts | R7; do not equate key existence with correct translation/rendering |
| SET-BACKUP-RESTORE | Real archive, merge and file round trip | R5 |
| SET-LAST-CHECKED | Date matrix, actual IPC application and preference isolation | R4 |
| SET-CLEAN-UPDATE-DEFAULT | Absent-file defaults through production load/application | C3: first-render/clean-profile connection |
| SET-UPDATE-RECOVERY | Existing updater backup/recovery plus missing local cases | C3: actual installer/relaunch |
| SET-UPDATE-BADGE | Availability/badge state decisions | C3: actual tray/update lifecycle |
| SET-WHATS-NEW-ENTRY | Return-route and lifetime state decisions | R1 |
| SET-SECONDARY-LAYOUT | Content/resource metadata | R8 |
| SET-BUG-REPORT-POLICY | Policy inputs, independent command eligibility/dispatch | C4 |

Keeping only two or three Settings E2E cases would presently discard unrelated real
Windows/rendering risks. The approximately 10% goal should guide elimination of
duplicated logic assertions, not dictate an unsupported whole-Settings signoff.

Before borrowed-window E2E, capture visible content landmarks as well as selected
navigation, actual scroll owners and deduplicated UIA identities. The Image Resizer
pilot exposed an uncertifiable original Settings content/scroll baseline; its
functional successes do not resolve that preservation issue. Prefer owned sessions
when lifecycle changes are required.

## 8. Planned validation and reporting

This change is documentation-only. **The following are proposed execution commands,
not executed/passed results.** General tests first require step 1 isolation. Common
native tests also need the fixed-name pipe case handled as described above.

Use the repository build scripts, wait for exit code 0, then execute the produced
test binary or VS Test runner. Do not use `dotnet test`.

```powershell
# From the repository root; run the relevant project, not all five by default.
.\tools\build\build.ps1 -Path .\src\settings-ui\Settings.UI.UnitTests -Platform x64 -Configuration Debug
.\tools\build\build.ps1 -Path .\src\common\interop\interop-tests -Platform x64 -Configuration Debug
.\tools\build\build.ps1 -Path .\src\common\UnitTests-CommonUtils -Platform x64 -Configuration Debug
.\tools\build\build.ps1 -Path .\src\runner\UnitTests -Platform x64 -Configuration Debug
.\tools\build\build.ps1 -Path .\src\common\updating\UnitTests -Platform x64 -Configuration Debug
```

For managed projects, the repository enables the MSTest executable runner. Resolve the
single built executable from the project's output, inspect `--help`, and select the
relevant tests before widening. For example, after safe isolation:

```powershell
$settingsTests = @(Get-ChildItem .\Debug\x64\tests\SettingsTests `
    -Filter Settings.UI.UnitTests.exe -Recurse)
if ($settingsTests.Count -ne 1) { throw 'Expected exactly one Settings test executable.' }
# $results is an explicitly owned artifact directory.
& $settingsTests[0].FullName --report-trx --results-directory $results --timeout 5m
```

For native shared IPC tests, use the `vstest.console.exe` from the selected Visual
Studio installation. A focused shared-host filter excludes the fixed Workspaces pipe:

```powershell
# $vstest is the resolved absolute path to the selected VS test runner.
& $vstest .\x64\Debug\tests\UnitTestsCommonUtils\Common.Utils.UnitTests.dll `
    '/TestCaseFilter:(FullyQualifiedName~TwoWayPipeMessageIPCTests|FullyQualifiedName~PipeCallerAuthTests)&FullyQualifiedName!~WorkspacesLauncherArrangerClientUsesIdentificationQos' `
    /Logger:trx
```

Discover native test names first if the adapter's reported qualified names differ.
Runner tests output under `x64\Debug\tests\Runner`; updater tests under
`x64\Debug\tests\UpdatingUnitTests`. Use their actual built DLLs and targeted filters.
The skipped fixed-name test remains unverified in this host slice; do not report
the filter result as the complete native suite.

Restore dependencies only after a missing-dependency failure (or manifest change);
use the existing essentials/restore workflow. Prior Image Resizer SDK/feed overrides
were session workarounds, not assumed Settings prerequisites.

Acceptance evidence must include:

- Build exit codes, discovered/executed/passed/failed/skipped counts and assertion-bearing TRX.
- Unit versus Functional classification by dependency, even inside the same project.
- Actual producer/consumer code, real/fake boundaries, owned paths and payloads for
  each composed workflow.
- Negative cases that preserve existing behavior; explicit separate defects if
  intended invariants fail.
- No leftover owned processes, watchers, pipe endpoints, files, subscriptions or
  modified user state.
- Reduced agent observations only after lower-layer evidence is available; no
  conversion of pass rate or heading-count reduction into business coverage.

## 9. Primary source anchors

Line numbers describe the inspected snapshot; follow symbols if later edits move them.

| Source | Relevant evidence |
|---|---|
| [General tests](/src/settings-ui/Settings.UI.UnitTests/ViewModelTests/General.cs) | Existing sender/property tests and test subclass |
| [GeneralViewModel](/src/settings-ui/Settings.UI/ViewModels/GeneralViewModel.cs) | Constructor 99-226; notification/send coupling 1221-1233; update command 1332-1340; refresh 1426-1474; retention 1534-1558 |
| [SettingsRepository](/src/settings-ui/Settings.UI.Library/SettingsRepository%601.cs) | Singleton/watcher/reload/lifetime, 15-155 |
| [DashboardViewModel](/src/settings-ui/Settings.UI/ViewModels/DashboardViewModel.cs) | Shared sort 84-105; production dependency assembly 111-133 |
| [AllAppsViewModel](/src/settings-ui/QuickAccess.UI/ViewModels/AllAppsViewModel.cs) | Shared sort 39-49; singleton/dispatcher acquisition 54-68; live callback 84-100 |
| [QuickAccessCoordinator](/src/settings-ui/QuickAccess.UI/Services/QuickAccessCoordinator.cs) | Actual message producers, IPC initialization, queued send and logging-only receive |
| [MainWindow](/src/settings-ui/Settings.UI/SettingsXAML/MainWindow.xaml.cs) | IPC delegate/response wiring 57-130; close behavior 159-174 |
| [Runner settings IPC](/src/runner/settings_window.cpp) | Actions 67-143; routes 195-357; main-thread handoff 360-371; authenticated endpoint 585-605 |
| [Runner General application](/src/runner/general_settings.cpp) | Partial update 200-295; full application 297 onward |
| [Quick Access native host](/src/runner/quick_access_host.cpp) | Separate authenticated endpoint 175-205 |
| [Managed IPC wrapper](/src/common/interop/TwoWayPipeMessageIPCManaged.cpp) | Delegation to native transport and ungated managed Start |
| [Native IPC implementation](/src/common/interop/two_way_pipe_message_ipc.cpp) | Send framing 438-458; authentication/read/dispatch 748-813 |
| [Managed pipe test](/src/common/interop/interop-tests/InteropTests.cs) | Same-process real send, unique names and bounded wait |
| [Native pipe tests](/src/common/UnitTests-CommonUtils/TwoWayPipeMessageIPC.Tests.cpp) | 18 methods; fixed Workspaces pipe at 575-601 |
| [Caller-auth tests](/src/common/UnitTests-CommonUtils/PipeCallerAuth.Tests.cpp) | Real-pipe helper 33-93; explicit test identity/version/signature boundaries 122-140 |
| [Native common test project](/src/common/UnitTests-CommonUtils/UnitTests-CommonUtils.vcxproj) | Compiles production transport/auth implementations |
| [Backup/restore](/src/settings-ui/Settings.UI.Library/SettingsBackupAndRestoreUtils.cs) | Restore 272-389; global archive lookup 414 onward; working-directory config 804-819 |
| [Updater tests](/src/common/updating/UnitTests/UpdatingTests.cpp) and [backup implementation](/src/common/updating/configBackup.h) | Separate updater protection and embedded-NUL corruption criterion |
| [FriendlyDateHelper](/src/settings-ui/Settings.UI/Helpers/FriendlyDateHelper.cs) and [Home update control](/src/settings-ui/Settings.UI/SettingsXAML/Controls/Dashboard/CheckUpdateControl.xaml.cs) | Clock/culture/resource formatting and separate Home load |
| [Navigation smoke](/src/settings-ui/Settings.UITests/SettingsNavigationSmokeTests.cs) | Dynamic navigation rows and process-survival assertion |
| [Legacy module UI test](/src/settings-ui/UITest-Settings/SettingsTests.cs) | Commented process assertions 77-81 |
| [Build guidance](/tools/build/BUILD-GUIDELINES.md) and [shared build props](/Directory.Build.props) | Build scripts and MSTest executable runner |

## 10. Follow-up: can a module-enable message reach an existing ViewModel?

### 10.1 Feasibility verdict (2026-10-27)

**Yes as a bounded Functional design, but not as an unchanged, already-proven test
of every Settings page.** The production transport, native partial-update algorithm,
file I/O and watcher exist. Isolated hosting requires dependency seams. The last edge
also has actual subscription gaps for some module-page consumers.

This follow-up traced source only; it did not execute the composed chain or modify
production behavior. In particular, no passing live-module-page result is claimed.

### 10.2 Concrete first case: enable Color Picker

Use Color Picker as an illustrative module key (`ColorPicker`), with no configured
policy. Do not launch its real DLL: its `enable()` launches a process, and its
`disable()` can terminate that process. The fixture controls that external boundary.

Start with an existing, valid, non-default root `settings.json`:

```json
{
  "enabled": {
    "ColorPicker": false,
    "FancyZones": true,
    "Image Resizer": false
  },
  "theme": "dark",
  "dashboard_sort_order": 1
}
```

This is an abbreviated illustration, not the complete fixture. Seed a complete current
General document so missing defaults/migrations cannot mask resets. The fake module's
runtime state must also start disabled. Create receiving repositories/models and wait
for their initial dispatcher work to complete **before** triggering the message.

Invoke the actual production message producer, for example the isolated
`QuickAccessCoordinator.UpdateModuleEnabled(ModuleType.ColorPicker, true)`, yielding:

```json
{"module_status":{"ColorPicker":true}}
```

Its public method is the entry boundary; no XAML click is required. Do not copy its
serialization into the main positive test. Hand-authored messages are appropriate
for native receiver/error cases, but then sender coverage is explicitly excluded.
The coordinator needs an isolated construction path for non-IPC window actions;
passing a null production window is not the proposed fixture design.

The native pipe callback reaches production dispatch, then
`apply_module_status_update`. That algorithm validates the entry, checks module
runtime state and policy, invokes enable/hotkey actions, loads the root General file,
changes the target enabled entry if needed, and saves. It does not edit
`ColorPicker\settings.json` for this command.

The root-file write must then reach the real repository's `Watcher_Changed`,
`ReloadSettings`, `SettingsChanged(newSettings)` and the receiver's queued refresh.
The observer receives a newly deserialized configuration, not the sender's object.

### 10.3 Assert both disk and the original consumer, not one instead of the other

| Assertion point | Required observation | Why it is needed |
|---|---|---|
| Native action boundary | Controlled Color Picker module receives enable; target/hotkey action ordering follows production | Separates application dispatch from merely accepting a JSON string; does not claim actual module launch |
| Owned root `settings.json` | `enabled.ColorPicker == true`; every unrelated enabled entry and General field remains unchanged | Proves native persistence and prevents a reset of other preferences from passing |
| Receiving repository | A successful watcher-driven reload exposes the new value | Locates notification/deserialization failures; `Send()` returning is insufficient |
| Existing All apps/Home row | Same model and row instances; `IsEnabled == true`, an observable property notification, correct By status group/order | Proves live model propagation, rather than reading the file or reconstructing a model |
| Existing launch-list item, when included | Color Picker item becomes eligible/visible without executing its command | Proves launch-list state projection, not a rendered tile or actual module execution |

For the smallest first composed test, use **disk + one existing All apps observer**;
then add Home and the launch-list consumer. They need additional resource/module-data
isolation, but the native send/application path is shared.

The test must not:

- Treat the originating row's optimistic `IsEnabled = true` as receiver evidence.
  Home also mutates its local General object after sending.
- Share the sender's General object with the receiving repository, manually invoke
  `SettingsChanged`/`RefreshSettings`/`RefreshEnabledState`, or write the expected
  file after the message. Only fixture setup may seed the initial file.
- Recreate the observing ViewModel during a live-update assertion.
- Require exactly one `FileSystemWatcher` event, or use a fixed sleep as success.
  Await the desired state within a deadline, preserve event/error evidence, and
  separately observe the file and consumer.

Read evidence files using short-lived streams that permit concurrent read/write/delete;
the assertion reader must not introduce file-sharing failures into the native writer.
Compare JSON structurally, not formatting or property order.

### 10.4 The last edge is not wired uniformly today

| Consumer | Current source path after an external root-file write |
|---|---|
| `DashboardViewModel` | Subscribes to `SettingsChanged`; replaces `generalSettingsConfig`, queues onto its dispatcher, refreshes module rows and shortcuts |
| Quick Access `AllAppsViewModel` | Subscribes; replaces `_generalSettings`, queues refresh, updates existing rows using `UpdateStatus`, and sorts |
| Shared launch-list `QuickAccessViewModel` | Subscribes; replaces `_generalSettings`, refreshes item visibility on its dispatcher |
| `GeneralViewModel` | Subscribes, but its callback explicitly refreshes `EnableQuickAccess`, not every General property; not a universal module-toggle assertion target |
| `ColorPickerViewModel` | Captures `settingsRepository.SettingsConfig` at construction; no repository-change subscription. `RefreshEnabledState()` reads the captured object |
| `MouseUtilsViewModel` | Likewise captures the original General object and does not subscribe; refreshing enabled fields still reads that object |

`SettingsRepository.ReloadSettings` replaces the configuration object rather than
mutating the previous one in place. Thus a bare existing Color Picker/Mouse Utilities
model cannot acquire the new value just because its repository reloaded.
`PageViewModelBase` handles hotkey conflicts, not General repository subscriptions.
`ShellPage.SignalGeneralDataUpdate` is a separate explicit current-page refresh path;
it is not a generic bridge from this watcher callback to those models.

Consequently, the invariant "Quick Access toggles Find My Mouse and the already-open
Mouse Utilities page updates" needs its own regression test. Within the directly
traced file-to-model slice, the subscription/object-replacement gap is source-visible.
Do not label this an installed-build reproduction. If fixing it requires adding a
subscription or replacing a stored configuration reference, that is a separately
identified behavior fix, not just dependency injection. Do not repair the test by
manually supplying the missing production notification.

### 10.5 Minimum isolation work and boundaries

| Area | Necessary work for this specific path |
|---|---|
| Native dispatch/application | Extract the existing route and partial-update algorithm from Runner-global dependencies. Keep actual parsing, policy/early-return decisions and JSON merge; control module, hotkey, AI and telemetry/OS adapters |
| Native disk location | Thread an owned settings path into the selected real load/save implementation. `PTSettingsHelper` currently uses `SHGetKnownFolderPath`; changing the process environment is not reliable path isolation |
| Managed disk location | Supply an owned root consistently to `SettingPath` existence/create/read/write operations; keep a real filesystem and the actual deserializer |
| Managed repositories | Scoped instances with instance-owned dependencies instead of the static singleton's first-writer-wins `SettingsUtils`; preserve production singleton callers |
| ViewModel hosting | A real DispatcherQueue without a Settings window; controlled GPO/resource/module metadata. Drain initial low-priority sorting work before triggering a row action |
| Producer and cross-language hosting | Reuse managed transport and extracted native production code in a bounded helper or test bridge. Merely running separate C# and native unit tests is not the composed chain |

A concrete initial topology is a managed test process owning the producer, receiving
repository and ViewModels, plus a small native test helper owning the production pipe,
extracted dispatcher/application slice and controlled module state. Pass only owned
pipe names and the owned settings root to that helper. Keep its control/readiness
channel separate from the production message path. No Settings window or full Runner
startup is involved; a test-host caller policy must not be reported as shipping
identity-policy coverage. A native bridge in the managed host is also viable, but
the current IPC wrapper does not itself expose Runner's application functions.

Only the selected root-file writer is redirected; no change to the shipping schema,
message shape or pipe authorization is needed. Preserve the native algorithm's
existing early return when runtime already equals target. Its later persistence
check also skips a write if disk already equals target, so not every command generates
a watcher event. A duplicate-command case must not wait for a new event unconditionally.

The partial-update path is the first slice because full General application additionally
touches startup tasks, Quick Access lifecycle, tray settings and more cached state.
It is not necessary to isolate the whole General page, update workflow or backup
system before building this narrower test.

### 10.6 Focused scenario set

| Priority | Scenario | Expected scope |
|---|---|---|
| First | Disabled -> enabled through actual partial-update producer | Native application, target-only disk change, existing observer notification/value |
| First | Enabled -> disabled through the same path | Symmetric disk/model convergence; launch eligibility disappears if included |
| First | Preserve non-default unrelated settings | Embedded in both transitions, not a separate E2E matrix |
| Next | Repeat an already-applied command | No second module enable/disable; no assumed write or watcher event |
| Next | Unknown module / non-Boolean entry / empty module map | Receiver rejects without state changes; small native cases rather than repeating every case through UI |
| Next | Forced policy state | Controlled policy inputs preserve current decisions; real registry/GPO installation remains outside this fixture |
| Regression | Existing Color Picker or Mouse Utilities page observes external toggle | Exposes the current subscription/reference gap; do not claim this passes before a separate fix |
| Later | Module-page full `general` snapshot | A different receiver route; partial-update success does not establish its full-snapshot behavior |

One passing partial-update case would establish the feasibility of the proposed
composed fixture, not coverage of all routes. Real module activation, physical hotkeys,
XAML binding/rendering, actual process startup and shipping identity policies remain
the representative E2E connections.

### 10.7 Follow-up source anchors

- `src\settings-ui\QuickAccess.UI\Services\QuickAccessCoordinator.cs:58-59`:
  production partial-update message; `:100-103` is logging-only receive.
- `src\settings-ui\Settings.UI\ViewModels\DashboardViewModel.cs:137-161,333-375`:
  watcher subscriber versus optimistic sender behavior.
- `src\settings-ui\QuickAccess.UI\ViewModels\AllAppsViewModel.cs:54-66,87-126,178-198`:
  repository subscription, refresh and toggle path.
- `src\settings-ui\Settings.UI.Controls\ModuleList\ModuleListItem.cs:25-36,90-105`:
  observer updates suppress outbound toggle callbacks.
- `src\runner\settings_window.cpp:195-226` and
  `src\runner\general_settings.cpp:200-295`: production dispatch and partial application.
- `src\common\SettingsAPI\settings_helpers.cpp:14-28,64-92` and
  `src\common\utils\json.h:14-36`: real user-path resolution and real file I/O.
- `src\settings-ui\Settings.UI.Library\SettingPath.cs:31-68` and
  `SettingsRepository` in section 9: managed path resolution, replacement and events.
- `src\settings-ui\Settings.UI\ViewModels\ColorPickerViewModel.cs:48-86,418-422` and
  `MouseUtilsViewModel.cs:33-41,1316-1324`: captured configurations and explicit refresh.
- `src\settings-ui\Settings.UI\ViewModels\GeneralViewModel.cs:1602-1614`:
  limited General live-refresh projection.
- `src\settings-ui\Settings.UI\SettingsXAML\Views\ShellPage.xaml.cs:236-243`:
  explicit current-page refresh, not a repository subscription.
- `src\modules\colorPicker\ColorPicker\dllmain.cpp:238-264` and
  `src\runner\powertoy_module.cpp:40-56,79-110`: module/process and hotkey side effects
  that the Functional fixture must not execute against the user's environment.
