# Execution readiness is Author work

A profile saying "establish ownership" or "discover the operation" is not an implementation of that capability.
Turn requirements into usable, tested mechanics before asking a confirmation Runner to rely on them.
This is an **automatic Author work checklist, not another human permission gate**.

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

### R0 versus confirmation

- **Before R0:** handle predictable cross-cutting requirements from the checklist: safe fixtures/data, cleanup,
  actual bits, desktop access and input integrity. A mature module profile is not required. Let R0 discover
  unknown controls/behavior through the generic engine; ordinary discovery must not become a new startup gate.
- **When R0 finds a gap:** continue independent safe assertions, return the affected IDs and evidence, and let
  the Author implement the missing reusable capability. Do not make the Runner rewrite tracked materials.
- **Before R1 or a later confirmation:** address known, repairable blockers for the selected core scope.
  Do not send the same incapable setup again and call repeated BLOCKED results "confirmation."
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

## 5. Bind improvements to the observed gap

Before the next confirmation, record a short change receipt:

```text
Affected assertion IDs:
Observed problem and evidence:
Layer: expectation / profile / helper / fixture / environment / report
Concrete change and candidate commit:
Profile format review: <profile/contract identities, conformance and remaining gaps>
Mechanical checks completed:
Fresh Runner confirmation scope:
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
| No backup/restore helper exists at main | Author implements/tests a minimal scoped capability; do not silently import a WIP harness |
| High-integrity fixture, medium-integrity Runner | Repair/validate the normal-user setup; do not conclude product hotkey failure |
| Drag-reorder is disabled but a Move menu exists | Test the menu and put that recipe in the profile |
| Settings value saved, but downstream action never observed | Preserve the partial observation; do not PASS the compound requirement |
| No accepted reference image exists | Capture candidate evidence; reference promotion and behavioral verification are separate |
| R0 repeats one fixable blocker across many IDs | Fix that shared capability before R1 confirmation of those IDs |
| Child operation is unreachable after a valid upstream product failure | Report one root finding and unobserved dependent coverage, not invented additional defects |
| Profile has correct headings but mixes JSON paths with UI locators | Repair the contracted interaction/read-out separation before confirmation |
| File helper cannot restore a required absent baseline | Implement/test suitable ownership-safe mechanics or keep the affected scope incomplete; do not fabricate a guard or pre-create the file to bypass the gap |
