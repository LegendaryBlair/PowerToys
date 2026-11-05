# Execution readiness is Author work

A profile saying "establish ownership" or "discover the operation" is not an implementation of that capability.
Turn requirements into usable, tested mechanics before asking a confirmation Runner to rely on them.
This is an **automatic Author work checklist, not another human permission gate**.

Use the existing recorder with finite, source-visible actions and `try/finally` restoration. Do not build a
run-local service that polls a request directory and executes unspecified future scripts merely to retain
PowerShell variables. Keep related stateful actions in one bounded invocation, or use the existing recorder's
documented reopen path between completed attempts. Unknown R0 controls can be inspected in short read-only
steps before composing the next concrete action; they do not require a general command dispatcher.

Wire prerequisite checks into the execution path, not just the brief: check actual target identity and the
required process/session/integrity conditions before mutation; check input desktop and exact foreground before
input delivery. A defined-but-unused guard is not protection. Use checks appropriate to the action rather than
requiring input-injection prerequisites for unrelated read-only work. First exercise one representative
operation/observation/restoration path, then continue the remaining round scope; this does not shrink R0 or R1.

## 1. Maintain a small capability map

Group assertions by the mechanics they share; do not create a framework or one adapter per checkbox.
Keep this map with the round's private authoring records, and put the resolved operational instructions in the
committed profile/helper/fixture. Send the Runner a neutral current plan, not the Author's diagnosis transcript.

| Field | Required content |
|---|---|
| Assertion IDs | Every affected ID, including distinct matrix conditions |
| Operation | Actual input path and observable effect; alternative supported routes |
| State touched | Files, clipboard, history, windows, enabled state, processes, pins, temporary outputs |
| Helper / fixture | Concrete implementation available at the candidate revision; no archived handles |
| UI-test discovery | Reviewed test/helper and source revision when available, or searched locations/revision/access limits; reuse or fallback decision kept in Author records |
| Validation | Test/probe receipt for the mechanism, including relevant failure/cleanup paths |
| Runtime checks | What the Runner must independently confirm before using it |
| Readiness | `ready`, `author-work`, `external-condition` or `spec-decision` |
| Next action | Who does what; an exact missing condition rather than "needs ownership" |

`ready` means the method exists and its mechanical contract has been checked, not that the product will PASS.
An available helper name is insufficient: inspect what it actually preserves, observes and restores.
For example, enumerating clipboard formats is not a clipboard backup, and backing up one settings file does
not restore history, clipboard or user windows.
Keep this execution-capability map separate from the [profile format review](module-profile-format.md#9-author-review-gate).
Correct headings/table shapes do not make a missing operation ready; a source-based recipe is not a live
observation. The profile must still conform to the format contract before a confirmation uses it.

### Learn from existing UI tests

Not every module has UI tests, and an existing suite may cover only some operations. Before designing profile
recipes, adding input/observer helpers or declaring an operation unsupported, perform a bounded search and
review relevant tests when available. Discovery is required; the existence of a suite is not.

If none is found, record the searched locations/revision and continue from the baseline/PR requirements,
target-product inspection, shared verification helpers and bounded live discovery. An unavailable source lookup
is a different limitation, not proof that no tests exist. Neither case by itself makes module behavior BLOCKED
or requires creating a UI-test project. For partial suites, reuse the covered flows and use this fallback for
the remaining operations without dropping checklist coverage.

1. Find the module's `*UITests*` projects, including sibling editor projects and `Tests` subdirectories.
   Prefer current tests using `src\common\UITestAutomation.Next`, but inspect project references rather than
   trusting the `.Next` suffix: some unsuffixed projects use it, while legacy suites use WinAppDriver/Appium.
   If the candidate's product tree is older, also check current upstream read-only for newer or migrated suites.
   Pin the inspected source SHA separately; do not merge newer product code into the verification baseline.
   Distinguish no relevant test found from an unavailable lookup.
2. Where relevant tests exist, follow their helper calls through setup, drive, readiness, result assertion and cleanup.
   Identify which building blocks are winapp/UIA and which use native input, Win32 window queries or Shell APIs;
   a winapp-based harness does not mean every action is a CLI command. Record useful fixtures, locators,
   HWND/foreground/integrity/DPI guards, held-input ordering, waits, retries and observation limits in the
   capability map. Keep source paths/symbols/revisions in Author inputs, not as required runtime fixture files.
3. Reuse the operating technique through supported winapp commands and the candidate's shared verification
   helpers. Do not copy a second generic input/recording framework or transplant C# wrappers as assumed APIs.
   Translate isolated-CI assumptions into owned fixtures and verified restoration: process-name kills,
   closing all Explorer windows, deleting user configuration, restoring defaults or assuming elevation are
   not safe cleanup recipes on a shared desktop. Preserve declared regeneration/comparison exclusions.
4. Match observations to the actual checklist claim and installed product. A UI test's cached value, zone
   assignment or native property may prove less than a visible-output or timing assertion; inspect its limits.
   Check any product fixes or tool-version assumptions the test relies on against the selected target.
   Existing UI tests supply implementation knowledge, not a complete acceptance specification: retain the
   baseline/PR requirements and conditional matrices even when the automated suite covers only a subset.
5. Confirm the adapted entry/operation/observation/restoration path in its declared round: bounded R0 discovery,
   full-inventory R1, or later targeted regression.
   Distinguish source implementation, an executed suite and repeatability evidence. Separate readiness polling
   from repeated gestures or process resets; retain available first-attempt outcomes, retries and cleanup
   failures. A green build or eventual test PASS is not proof of reliable first-attempt execution in this
   environment. Do not import retry-until-green behavior or past PASS labels into a profile.

For example, a window-drag test can teach controlled-window selection, grab-point ownership, mouse/modifier
ordering and drop-result observation. Reuse those mechanics rather than declaring all dragging unsupported
or substituting direct window placement for the input path the checklist actually requires.

### R0 versus confirmation

Use the [required round coverage and completion gate](stopping-policy.md#required-round-coverage);
bounded discovery does not limit R1 to the same selection.

- **Base check first:** use the published verification WIP and inspect existing module coverage.
  Missing shared recorder/inventory APIs in an old checkout are a baseline-selection problem,
  not a request to recreate the harness. Product-source freshness is checked independently.
- **Before R0:** handle predictable cross-cutting requirements from the checklist: safe fixtures/data, cleanup,
  actual bits, desktop access and input integrity. A mature module profile is not required. Let R0 discover
  unknown controls/behavior through the generic engine; ordinary discovery must not become a new startup gate.
- **R0 scope and exit:** sample the distinct core input, observation and restoration mechanisms. Obtain real
  operation/result evidence and verify restoration; opening the module alone is insufficient. Retain the full
  inventory, record unexecuted conditions and known limits, and report partial discovery when core mechanics
  remain unproven. Valid product FAIL evidence is useful; successful product behavior is not a prerequisite.
- **When R0 finds a gap:** continue independent safe assertions, return the affected IDs and evidence, and let
  the Author prioritize repairs within the [approved limits](stopping-policy.md#diagnostic-and-repair-limits).
  Do not make the Runner rewrite tracked materials or develop a new helper framework.
- **Before R1:** review readiness across the entire frozen inventory, including conditional matrices outside
  R0's sample. Address known fixture/helper/observer gaps within the repair allowance. Retain exhausted gaps
  and continue safe independent cases, rather than making one small unresolved issue prevent all R1 coverage.
  Do not send the same broken path again merely to repeat its BLOCKED result.
- **R1 scope and exit:** process every assertion and matrix condition, actually execute all safely available
  independent conditions, and verify restoration. Unprocessed work or unresolved infrastructure/specification
  gaps means incomplete R1, not a completed full confirmation. Cite concrete evidence for external limits
  and confirmed product dependencies; these remain assessed but unexecuted coverage.
  Restore/archive and exit after the full pass by default, even if its completion gate was not satisfied.
- **R2 scope and exit:** only when explicitly authorized, fix a selected issue batch within its allowance and
  run one targeted confirmation with neighboring regressions. Restore/archive and exit with fixed, unresolved
  or incomplete results; do not start R3 automatically or treat an all-green result as a prerequisite to stop.
- A genuine external condition can remain deferred. Record it without deleting its assertion or silently
  declaring complete coverage. A specifically authorized diagnostic rerun can investigate a remaining gap,
  but is not proof that the profile is ready.

If a repair cannot be completed safely or within the task's limits, return a concrete partial/needs-review
result. Do not invent readiness, expand authority, or indefinitely develop a general testing platform.

## 2. Distinguish confidentiality from preservation

**Non-empty is not the same as untestable.** Clipboard/history may contain pre-existing data and still support
authorized reversible tests, provided an implementation can preserve and restore it safely.

Separate two boundaries in the task packet:

- **Disclosure:** do not expose private payloads to model context, terminal dumps, screenshots, shared reports
  or repository commits.
- **Handling:** within the authorized local test, code may need to read/copy original bytes or native data into
  protected temporary storage/in-memory guards for restoration. Return hashes/status, not private content.

Do not silently reinterpret "no private payload in evidence" as "no programmatic backup is permitted."
Conversely, a backup API is not permission to read/mutate data that policy or the user explicitly forbids.

Before a mutation, provide:

1. A complete snapshot of the supported state types, preserving absence, order and limits where meaningful.
   Unsupported clipboard formats must be rejected before writing; plain text backup is not enough for images.
2. A known owned post-state or write receipt, with checks for intervening changes. Empty text, a familiar color
   or a small history file is not ownership evidence.
3. Paired cleanup for success and failure; verify original enabled/disabled state, bytes/content and relevant
   window/process state. Retain failed restoration evidence.
4. A clean synthetic scene for screenshots and output assertions. Protect existing history from capture through
   a valid crop or owned test context; a crop must not hide the feature under test.

Encode the resolved plan in the profile's [restoration inventory and ordering](module-profile-format.md#7-fixtures-and-restoration).
Declare case/run ownership and indirect startup/companion writes. Distinguish helpers that preserve only
existing files from absence-capable rollback, and snapshots from conflict-aware guards. Complete final
verification after the last required restart/write; restoring defaults is not restoring the captured baseline.
If the helper lacks a required guarantee, repair/test that capability or state the concrete scoped limitation,
not a fictional API or a generic instruction for the Runner to "ensure restoration".

If an empty-history/destructive fixture cannot be obtained safely, use an already authorized isolated context,
request the specific additional environment/authority if genuinely needed, or defer that condition. Never
delete user data merely to satisfy the checklist. Continue other work.

Keep private backups out of public run artifacts and commits. Keep them only as long as recovery needs them.
An in-memory guard does not promise recovery after its owning process is killed.

## 3. Match input conditions before diagnosing a hotkey defect

Record **actual process identity and elevation/integrity** for:

- Automation host/shell.
- PowerToys Runner and relevant module.
- The foreground fixture/application receiving input.

Check the input mechanism in the target version. Low-level-hook behavior and `RegisterHotKey` are not
interchangeable. A lower-integrity hook can fail to observe a higher-integrity foreground target.
An elevated shell normally creates elevated children: ordinary `Start-Process` is not de-elevation.

For normal non-elevated coverage, establish an appropriately non-elevated owned fixture using a supported,
authorized launch method, or run the automation at matching integrity. Do not elevate the product simply to
make a normal-user check pass, and do not bypass a denied elevation policy.

Verify the exact foreground HWND/owner and input desktop. Record complete injected-input counts and cleanup,
then observe fresh module/Runner activity and the actual resulting surface. Queued input does not prove
delivery to the product; named-event success proves only the downstream action.

If fixture integrity, focus or delivery is unknown/incompatible, the hotkey outcome is not yet a product FAIL.
Retain the failed observation and request a valid controlled confirmation. Keep genuine elevated variants
separate from accidentally running an ordinary fixture elevated.

## 4. Provide actual control and observation recipes

Use source and live discovery together to establish supported user-facing routes. Write them in the
contracted [four-column interaction index](module-profile-format.md#5-control-locator-and-interaction-index),
with result-reading methods below it rather than an Observe column or settings paths presented as selectors.

- A disabled drag-reorder flag does not prove that menu/keyboard reordering is absent. Inspect the whole
  relevant control and handlers, and try the alternate documented operation before declaring a missing feature.
- Replace "discover format ordering" with the confirmed operation and a runtime discovery method for its
  current owner/selector. Do not replace a volatile handle with another hard-coded handle.
- Verify JSON value shapes instead of assuming every setting uses a `.value` wrapper.
- Scope repeated controls to their real owner. Re-resolve after navigation, reorder or process recreation.
- Measure current DPI and distinguish DIP sizing from physical screen-coordinate contracts. Do not rescale
  already-physical helper coordinates or carry a prior session's scale into a size claim.
- Separate structural readiness from expected results. UIA invocation, persisted settings and rendered state
  can settle independently; use bounded observations without silently repeating the action.
- Check before/after foreground, surface identity and capture behavior. A screenshot command can change the
  popup it was intended to observe.

A checked-in helper should have parameterized inputs, explicit errors and focused regression coverage for the
mechanics it promises. Scratch scripts can teach the Author, but scripts tied to one run's HWND/PID/private
paths are not reusable capability. Reuse existing CLI operations instead of writing redundant input machinery.

Reuse shared held input, UIA resolution, capture, file/clipboard preservation, Settings snapshots and resource
completion. Keep a module wrapper only for genuinely module-specific composition. Do not bypass a shared guard,
invent a wider restoration tolerance, or duplicate the resource model to make a local case pass. A necessary
common-layer change needs focused regression evidence and must stay within the authorized task.

## 5. Bind improvements to the observed gap

Before the next confirmation, record a short change receipt:

```text
Affected assertion IDs:
Observed problem and evidence:
Layer: expectation / profile / helper / fixture / environment / report
Concrete change and candidate commit:
Profile format review: <profile/contract identities, conformance and remaining gaps>
Mechanical checks completed:
Repair batch/root IDs, approaches and diagnostic/repair time consumed:
Remaining allowance, stop reason and deferred lower-value work:
Fresh Runner round/scope: <R1: full frozen inventory; R2+: affected IDs and neighboring regressions>
Remaining external conditions or decisions:
```

Prioritize shared blockers by the actual core paths they prevent. If many assertions stopped at the same
clipboard/history prerequisite, one safe fixture/restore capability is more useful than repeating that warning
in every recipe.

Tightening an evidence rule can correctly turn false PASS results into incomplete coverage. Keep that
correction, but do not call it resolution of the underlying execution gap. A commit that only adds evidence
gates is insufficient while a known, repairable core mechanism remains absent.

If a new group of failures appears, compare conditions and raw observations before changing expectations.
Profile/refactoring changes may expose earlier false positives; they may also introduce bad advice.
Product failures remain findings, not Author fix-to-green tasks.

## 6. Regression questions for the workflow

Use these to review an authoring iteration; they are not claims that this workflow has been live-validated.

| Situation | Expected workflow response |
|---|---|
| Clipboard contains text/image; history is non-empty | Establish supported private backup + owned test data, or state the concrete unsatisfied condition; no blanket environment failure |
| Old checkout lacks the current common helpers | Correct the verification baseline before authoring; do not reproduce the missing framework |
| Current shared helper lacks a required guarantee | Improve that shared mechanism minimally with focused regressions; no module-local duplicate or guard bypass |
| Target already has a profile/checklist/inventory | Refine gaps and retain existing IDs instead of generating replacement coverage |
| No relevant module UI tests are found | Record searched locations/revision; continue source/shared-helper/live discovery without blocking authoring or requiring a new UI-test project |
| Module UI tests already implement a difficult gesture | Trace the fixture/input/observer/cleanup chain and adapt it through shared verification helpers before adding another driver or declaring it unsupported |
| Old product checkout lacks a newer UI-test suite | Inspect current upstream read-only and pin its source identity without changing the execution baseline |
| Existing UI tests cover only part of the manual requirements | Reuse their operating knowledge without shrinking the full checklist/inventory |
| A UI test is green after action retries or process resets | Keep retry/reset evidence separate; confirm the adapted flow rather than inheriting a reliability claim |
| High-integrity fixture, medium-integrity Runner | Repair/validate the normal-user setup; do not conclude product hotkey failure |
| Drag-reorder is disabled but a Move menu exists | Test the menu and put that recipe in the profile |
| Settings value saved, but downstream action never observed | Preserve the partial observation; do not PASS the compound requirement |
| No accepted reference image exists | Capture candidate evidence; reference promotion and behavioral verification are separate |
| R0 repeats one fixable blocker across many IDs | Prioritize the shared repair within its allowance; retain remaining gaps and continue independent R1 conditions |
| R1 selects only R0 failures or representative cases | Reject the reduced scope as full R1; retain the complete inventory and required matrices |
| Every R1 row has a verdict but many conditions were never driven | Separate assessed from executed coverage and inspect blocker evidence; verdict assignment alone does not satisfy the completion gate |
| A known fixture/observer defect leaves R1 cases blocked | Repair within the approved allowance or exit with incomplete authoring; do not relabel it as external or loop until green |
| One minor point consumes the root/batch repair allowance | Stop that repair, preserve evidence and process other independent R1 conditions; no fresh allowance by renaming the issue |
| R2 still reports a failure or blocked condition | Restore/archive and return the unresolved result; do not automatically modify again or dispatch R3 |
| Child operation is unreachable after a valid upstream product failure | Retain the root finding and explicit unexecuted dependency; continue independent conditions without inventing extra product failures |
| Profile has correct headings but mixes JSON paths with UI locators | Repair the contracted interaction/read-out separation before confirmation |
| File helper cannot restore a required absent baseline | Implement/test suitable ownership-safe mechanics or keep the affected scope incomplete; do not fabricate a guard or pre-create the file to bypass the gap |
