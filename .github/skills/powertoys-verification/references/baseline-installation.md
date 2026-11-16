# Scripted PR comparison baselines

Use `scripts\pt-baseline-installation.ps1` for **Scenario B bug comparisons**, not
Scenario A checklist execution or an installer-PR acceptance test. Dot-sourcing it
defines functions only. Resolve the baseline before recording either side:

- An explicit version wins. Otherwise choose the latest official stable release
  for stable/release fixes, or the latest official published main-line development
  preview for main-line fixes. Record the choice and why it is relevant.
- `Resolve-PtBaselineRelease` freezes the release/tag, immutable commit, exact
  architecture/scope asset, URL, size and available SHA-256 digest. Stable uses
  GitHub's latest non-prerelease release; preview searches the latest 100 published
  releases for a prerelease whose tag commit is an ancestor of `main`.
- A pinned version selects its exact official tag regardless of the latest-channel
  default; its actual channel is recorded. No eligible preview/package means
  **Unavailable**, not permission to substitute stable, a fork or an unsigned CI
  executable. Missing prerequisites, acquisition and reproduction are separate facts.

## Read-only discovery and plan

```powershell
. "$skill\scripts\pt-baseline-installation.ps1"
$installed = Get-PtBaselineInstallation
$scope = if ($installed.Installed) { $installed.Scope } else { 'PerUser' }
$selection = Resolve-PtBaselineRelease -Channel Stable -Architecture x64 -Scope $scope
# Add -Version '0.X.Y' only when explicitly pinned.
$plan = New-PtBaselineInstallationPlan -Baseline $selection
$plan
Get-PtBaselineBootState
```

Use the actual requested/host architecture, not `x64` unconditionally. Discovery
cross-checks the bundle registration, installed Runner file version, PE architecture
and hash. Shared HKCU registry views are deduplicated only for the same registration
and values; conflicting registrations, orphaned files and cross-scope switches
refuse automatic replacement. A matching install is reused, not reinstalled.

## State adapters are a prerequisite, not a restore promise

The installer manager composes the existing [resource sessions](session-safety.md),
[directory/selected-file preservation](directory-snapshots.md) and module-specific
state helpers. It cannot infer every module's files, Settings drafts, package data,
cached preferences, provider lifetime or original launch/token/window state.
Prepare and record these finite callbacks with the run **before entering**:

| Callback | Contract |
|---|---|
| `PreserveState($stateDirectory)` | Read-only capture of originals, existence and original runtime/absence. Return exactly one existing immutable receipt-file path inside this private directory. Preserve package/module stores and restartable Settings state, not only general `settings.json`. Keep mutable expected-state/cleanup progress separately. |
| `Quiesce($session)` | Normally close exact preserved/owned Runner, Settings and companions, respecting unsaved-state boundaries. No name-based kill or blanket Explorer restart. The helper independently refuses installers while PowerToys/Command Palette processes remain. |
| `StartRuntime($session)` | Open the selected installed Runner through the appropriate supported launch route/token, wait for readiness, return only its integer PID. The helper checks the actual path/version/hash/start time. Separately attest the module, loaded DLL or package handling the assertion. |
| `RestoreState($receipt,$session)` | Restore this run's attributed files/existence, cached state, original running/stopped state, logical UI and owned-resource absence through their existing guarded adapters. Never adopt the latest state as an expected original. |
| `VerifyState($receipt,$session)` | Independently compare the preserved originals and runtime/resource obligations; return one Boolean. A constant `true`, empty callback or merely successful restart is not valid verification. |

If this preservation boundary cannot be implemented safely, stop baseline preparation
**before installation** and continue eligible target work. Shared prerequisite/package
changes and installer-specific registrations must be included in the preservation
scope or reported as unsupported; this helper does not certify whole-machine rollback.
Preservation callbacks must not mutate product state while capturing originals.

## Enter, capture, restore, then capture the target

Use the orchestrator inside the existing recorded Scenario B execution boundary,
after resource preparation (never in the template's read-only `Preflight`).
The variables below are the run's real, source-snapshotted callbacks:

```powershell
$comparison = Invoke-PtBaselineComparison `
    -AcquirePlan { New-PtBaselineInstallationPlan -Baseline $selection } `
    -Directory (Join-Path $env:LOCALAPPDATA (
        'PowerToys-Verification\baseline-' + [guid]::NewGuid().ToString('N'))) `
    -PreserveState $preserveState -Quiesce $quiesce -StartRuntime $startRuntime `
    -CaptureBaseline $captureBaseline -RestoreState $restoreState -VerifyState $verifyState `
    -CaptureTarget $captureTarget -AllowInstall
```

`CaptureBaseline($session)` returns `{ Status; Evidence; ... }`, with status
`Reproduced`, `NotReproduced` or `Unavailable`. It records the actual conditions and
observations through the shared recorder; the manager does not assign product verdicts.
`CaptureTarget($comparison)` establishes its own PR-build identity, matched fixtures
and observations. It runs after restoration even when acquisition or reproduction
failed. Its error is retained separately in `TargetError`; neither callback's return
value replaces review of the assertion evidence.

`-AllowInstall` is explicit authority to install/uninstall for this preparation, not
permission to bypass UAC, reboot or alter unrelated state. Per-machine replacement
additionally requires `-AllowMachineScope` and an already elevated session with a
preservation boundary covering its impact. Do not supply either switch when authority
is missing. Permission denial is a baseline limitation; never synthesize elevation.

For a different or absent version, the script:

1. Rechecks the original identity and pending-reboot state.
2. Caches the **exact baseline and original rollback installers before removal**.
   Valid Microsoft Authenticode, actual file version, exact asset size and hash are
   checked; the release digest is checked when available. Cached installers are
   rechecked before execution. Missing rollback material prevents uninstallation.
3. Persists private originals and a recovery receipt, then normally quiesces.
4. Uses supported `/uninstall`, `/install` and recovery `/repair`, always
   `/quiet /norestart`, preserving the original custom `InstallFolder`.
   It never executes a registry-supplied uninstall command.
5. Checks the actual installed version/scope/architecture and real Runner process,
   not just exit zero, a registry value or file existence.
6. Restores the exact original installation (or original absence), then invokes
   state restoration and independent verification before permitting target capture.

Closing Runner does not release Explorer/COM shell-extension locks. Exit `3010`,
`1641` or a pending reboot stops dependent mutation; no reboot or forced shell closure
is automatic. Installer waits are bounded at ten minutes. A still-running or
interrupted installer retains its receipt and blocks another installer.

## Recovery and reporting

`receipt-*.json` is an append-only, hash-linked private checkpoint sequence. The
directory is newly created under `LOCALAPPDATA`, with inheritance removed and access
limited to the current user and SYSTEM. Retain installers, logs, original state and
callbacks there while recovery is unresolved; never move it into a public report or
silently adopt an earlier run's directory. Register only sanitized metadata in reports.

For the **same** interrupted comparison, inspect `Get-PtBaselineSession`, then use:

```powershell
$recovery = Restore-PtBaselineInstallation -Directory $recoveryDirectory `
    -Quiesce $quiesce -RestoreState $restoreState -VerifyState $verifyState
```

Ordinary failed installs roll back through the cached original. Completed restoration
is idempotent. Unexpected installations, changed original receipts, unverified
configuration or missing installer exit status require explicit recovery; do not remove
foreign installations or guess that an interrupted installer succeeded. After a required,
separately authorized reboot, restoration rechecks the boot identity and pending state.
This is not automatic recovery of another run or a general Windows repair utility.

Always produce the PR report, keeping these dimensions separate:

| Dimension | Report |
|---|---|
| Baseline | Exact selection/runtime, `Reproduced` / `NotReproduced` / `Unavailable`, attempted conditions and evidence |
| Target | Independent PASS / FAIL / BLOCKED assertions, even when the baseline was unavailable |
| Recovery | Verified restoration or unresolved obligations and private recovery location |

Only an unsafe partial switch/restoration gates dependent target mutations
(`SafeForTarget=false`); independent offline checks and report generation continue.
Do not turn baseline non-reproduction into a target failure, omit after-fix video, or
claim a demonstrated fix without a genuine contrast.

## Focused acceptance

```powershell
& "$skill\scripts\tests\Test-PtBaselineInstallation.ps1"
```

The offline suite simulates release metadata and installation/process mutations.
It exercises real package-validation logic with controlled signature responses,
private receipts, failure/rollback/reboot gates and nonblocking target continuation.
Run `Get-PtBaselineInstallation`, `Get-PtBaselineBootState` and release resolution
separately for read-only local checks. These tests do **not** claim a live
install/uninstall matrix or authorize replacing the user's current installation.
