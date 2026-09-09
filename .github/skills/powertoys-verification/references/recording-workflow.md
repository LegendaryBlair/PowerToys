# Recording and report workflow

Dot-source `scripts\pt-verification-report.ps1` in PowerShell 7. It only defines
functions: no desktop access, product changes, processes, downloads or module imports.
Use it alongside the driving and paired-state helpers, not instead of them. The
[reporting format](reporting-format.md) remains the report-shape contract.

This is a **single-writer, synchronous recorder**, not a test scheduler. Start recording
before discovery/preflight. Record every attempt, including failed probes and recovery.
An action completing or a native command returning zero **never assigns product PASS**.

## Initialize once, before driving

Pass a **nonexistent** workspace. Do not pre-create it, reuse an old archive or rely on
Git HEAD: the files actually supplied may contain uncommitted changes.

```powershell
. "$skill\scripts\pt-verification-report.ps1"
$run = New-PtVerificationRun -Workspace $workspace -Module $module -Bits $bits `
    -Scenario A -Inputs @(
        @{ Name = 'SKILL.md'; Role = 'Skill'; Path = "$skill\SKILL.md" }
        @{ Name = 'profile.md'; Role = 'Profile'; Path = $profilePath }
        @{ Name = 'checklist.md'; Role = 'Checklist'; Path = $checklistPath }
        @{ Name = 'pt-desktop.ps1'; Role = 'Helper'; Path = "$skill\scripts\pt-desktop.ps1" }
        @{ Name = 'recorder.ps1'; Role = 'Helper'; Path = "$skill\scripts\pt-verification-report.ps1" }
    ) -Items @(
        @{
            Id = 'L1'; Description = $verbatimChecklistDescription
            Admin = 'NO'; Clarity = 'CLEAR'; UserVisible = $true
            Assertions = @(
                @{ Id = 'opens'; Description = $verbatimOpeningAssertion; Required = $true }
                @{ Id = 'content'; Description = $verbatimContentAssertion; Required = $true }
            )
        }
    )
```

`Scenario` is `A`, `B`, or `InfrastructureAcceptance`. Supply the complete BITS contract
as text, not merely a checkout revision. The last scenario is **verification-infrastructure
acceptance only** (including synthetic fixtures), never a product signoff. Supply **all** checklist items and individually
identifiable subassertions, preserving their original descriptions, Admin and Clarity.
IDs must be unique within their item/run, respectively. The recorder does not parse or
invent a checklist from prose; the caller owns completeness of this initial inventory.

Inputs are real files, not directories or guessed paths. `Skill`, `Checklist` and at
least one `Helper` are required roles; include the `Profile` when one applies, all helpers
actually used, PR description/diff files for scenario B, and other source inputs as `Other`.
Each gets an immediate byte snapshot and SHA256. Input names must be unique, ASCII-safe
basenames; identifiers and generated paths reject traversal, reserved device names and
redirecting reparse points (symlinks/junctions). Cloud Files placeholders used by OneDrive
are allowed because they hydrate in place rather than redirecting the path.
Original source paths are informational; reports reference snapshots.
Changing a source later cannot change the snapshot. Runtime revisions need new step source
snapshots, not replacement files. Run timestamps and source hashes live in the artifacts,
not in reusable skill/profile content.

## Public API

Use named parameters in automation. Functions other than `Invoke-PtVerificationStep`
that return objects are noted below; mutation-only functions emit no success output.
`Get/Read/Write/Assert/Convert/Format/Add-PtReport*` functions are implementation details.

| API | Contract |
|---|---|
| `New-PtVerificationRun -Workspace -Module -Bits -Scenario -Items -Inputs` | Creates immutable inventory/input snapshots and an append-only journal; returns a run handle. |
| `Open-PtVerificationRun -Workspace [-JournalName]` | Reloads a run after interruption or moving it. A nondefault journal is a read-only partial-export snapshot. It does not recreate or complete interrupted attempts. |
| `Start-PtVerificationAttempt -Run -ItemId -Kind -Name [-Activate]` | Starts a UUID item attempt, `Kind Normal` or `Diagnostic`; returns its handle. No default path kind. |
| `Start-PtVerificationAttempt -Run -Context -Kind -Name [-Activate]` | Non-item `Preflight`, `Cleanup` or `Diagnostic`; does not add invented checklist items. Diagnostic context requires Diagnostic kind. |
| `Get-PtActiveVerificationAttempt` / `Set-PtActiveVerificationAttempt -Attempt` | Runspace-local ambient context across script boundaries. Use `-Activate`/the setter for top-level calls, or `$null` to clear. Each recorded step temporarily selects its explicit attempt and restores the caller context afterward. |
| `Stop-PtVerificationAttempt -Attempt -Reason` | Records the end and clears this attempt if active. Does not assert product success. Cannot stop a running step. |
| `Invoke-PtVerificationStep -Attempt -Name -Command -Action [-ArgumentList] [-Implementation]` | Writes exact command/action/arguments before execution, records raw streams and completion/error, returns original success-stream objects. Records failure and rethrows the original error. |
| `Invoke-PtVerificationStep -Attempt -Name -Command -ScriptFile [-ArgumentList]` | Copies and executes the **snapshot**, not the mutable original file. Revisions get separate snapshots/hashes. |
| `New-PtVerificationArtifactPath -Attempt -Name` | Reserves a unique nonexistent absolute output path; returns it. Reusing a friendly name never reuses its path. |
| `Add-PtVerificationArtifact -Attempt -Path -Kind -Description [-StepId] [-Synthetic] [-Name]` | Seals a reserved output or imports a real file using a safe bounded alias; returns a file reference including `OriginalName`. Optional `-Name` selects an explicit safe alias for an import. Kind is `Evidence`, `Screenshot` or `Restoration`. |
| `Add-PtVerificationAssertion -Attempt -AssertionId -Verdict -Category -Reason [-Evidence]` | Appends an explicit observation against the registered child ID. Evidence is an array of file-reference objects returned by artifact registration, from **this same attempt**. |
| `Complete-PtVerificationItem -Run -ItemId -Reason [-Caveats]` | Records the analyst's completion/reasoning, not a supplied final verdict. Subsequent attempts need a new run. Unfinished coverage still blocks. |
| `Add-PtVerificationRestoration -Attempt -Verdict -Reason [-Evidence]` | Only a Normal Cleanup context can record restoration. PASS requires registered `Restoration` evidence. |
| `Export-PtVerificationReport -Run` | Writes a uniquely named partial report/results/manifest/journal snapshot without completing the run. Returns Report, Results, Manifest and Signoff. |
| `Complete-PtVerificationRun -Run -Retrospective` / `-NoFriction` | Validates evidence, explicitly ends the run, writes `report.md`, `results.json`, `artifact-manifest.json`; returns export paths and Signoff. May finalize a **WITHHELD** run. |
| `Export-PtVerificationReport -Run -Final` | Final export only after recorded completion; refuses to overwrite any final file. Useful if completion was recorded but no final files were written. |
| `Test-PtVerificationArchive -Workspace [-ManifestName]` | Replays the recorded journal and verifies required manifest coverage, relative paths, every file's size/SHA256 and input snapshots. Throws on invalidity; returns Valid, RunId, FileCount and Signoff. |

`Admin` accepts `NO`, `COND`, `YES`; `Clarity` accepts `CLEAR`, `REWRITTEN`, `VAGUE-*`.
Every child has an explicit boolean `Required`. Required children gate item PASS; even an
optional NOT-OBSERVED child is visible and withholds overall signoff. No child disappears
because another child failed.

## Automatically record every winapp call

`Invoke-PtWinApp` in `pt-desktop.ps1` already integrates the recorder. Pass arguments
**after** `winapp ui`: `@('inspect','--depth','8','-w',"$hwnd",'--json')`, not
`@('ui','inspect',...)`. It records the exact command, loaded wrapper implementation,
arguments and raw output before returning or rethrowing. `-SkipRecording` is internal:
it prevents only
the wrapper's recursive self-call; **do not clear ambient context** while a helper runs.
Consequently nested discovery, list-windows, readiness, internal inspect probes and failed
winapp calls each get their own command row/source/output files. An outer script alone
is insufficient. Do not call the native `winapp` executable directly during a recorded run.
This recorder cannot intercept arbitrary native calls, another process/runspace, or
uninstrumented legacy helpers; route those through the wrapper or explicit steps.

Use non-item contexts for bootstrap and cleanup too:

```powershell
$preflight = Start-PtVerificationAttempt -Run $run -Context Preflight `
    -Kind Normal -Name 'Environment and input discovery' -Activate
# Invoke-PtWinApp calls, including those inside helpers, are now recorded automatically.
# Record non-winapp probes with Invoke-PtVerificationStep as well.
Stop-PtVerificationAttempt -Attempt $preflight -Reason 'Preflight probes recorded'
```

`-ScriptFile` runs in a new PowerShell script scope. Load the required helper functions
once in the caller: the Named Event catalog no longer depends on caller `$script:` data,
and each recorded step binds its attempt across nested script invocations. Re-loading
helpers or manually setting the attempt inside every script is unnecessary. This is
runspace-local state, not cross-process persistence; a new PowerShell process still needs
normal initialization. The recorded script's relative-path dependencies must be passed
explicitly because its `$PSScriptRoot` is the snapshot directory.

The recorder accepts actual `Format-Table`/`Format-List` streams from the diagnostic
without an `Out-String` workaround. It renders formatting packets through one stateful
pipeline while retaining their serialized data and returning the original output objects.
Use caller-side `Out-String` only when the caller intentionally wants text.

Record meaningful names, exact commands with resolved arguments, and actual probe output
(including admin/runner/settings/desktop evidence required by the reporting format).
Do not reconstruct missing commands from memory afterward. Prefer parameterized `-Action`
and `-ArgumentList` to reliance on caller-local variables. `-Implementation` captures the
loaded helper function body; initial helper snapshots alone do not identify a later edited
or reloaded implementation.

## Evidence and explicit observations

Allocate screenshot destinations before capture. Register evidence immediately, never
overwrite a sealed artifact. A screenshot must be associated with its producing step:
registration inside an action uses that step automatically; registration afterward uses
the attempt's `LastStepId` explicitly.

Output reservations still require safe logical names. Imported files may have real Windows
basenames such as `+Package.en-US.yml` or a long generated `.png.state.json` suffix:
the recorder chooses a bounded ASCII storage alias, keeps `OriginalName` in the sealed
reference, and copies bytes without renaming the source. Long names retain a name hash and
short extension. Use `-Name 'token-fixture.yml'` for an explicit import alias; traversal and
device names remain invalid aliases. Choose a reserved output's name when allocating it,
not when sealing it. Repeated imports always get new paths.

```powershell
$attempt = Start-PtVerificationAttempt -Run $run -ItemId L1 -Kind Normal `
    -Name 'Normal reopen without recovery' -Activate
$imagePath = New-PtVerificationArtifactPath -Attempt $attempt -Name 'opened.png'
$quotedImagePath = $imagePath.Replace("'", "''")
Invoke-PtVerificationStep -Attempt $attempt -Name 'Passive observation' `
    -Command "Save-PtPassiveScreenshot -Path '$quotedImagePath' -Observe { (Get-PtNativeWindow -Hwnd $hwnd).Visible }" `
    -Implementation ${function:Save-PtPassiveScreenshot} -ArgumentList @($imagePath,$hwnd) -Action {
        param($capturePath, $targetHwnd)
        Save-PtPassiveScreenshot -Path $capturePath -Observe {
            (Get-PtNativeWindow -Hwnd $targetHwnd).Visible
        }
    } | Out-Null
$image = Add-PtVerificationArtifact -Attempt $attempt -Path $imagePath `
    -Kind Screenshot -Description 'Describe the behavior actually visible' `
    -StepId $attempt.LastStepId
Add-PtVerificationArtifact -Attempt $attempt -Path "$imagePath.state.json" `
    -Kind Evidence -Description 'Capture before/after state comparison' `
    -StepId $attempt.LastStepId | Out-Null

# Only after inspecting the capture and corresponding behavior:
Add-PtVerificationAssertion -Attempt $attempt -AssertionId opens -Verdict PASS `
    -Category 'Normal reopen + inspected screenshot' `
    -Reason $observedOpeningReason -Evidence @($image)
# Record content separately. If not observed:
Add-PtVerificationAssertion -Attempt $attempt -AssertionId content `
    -Verdict NOT-OBSERVED -Category not-observed -Reason $specificCoverageGap
Stop-PtVerificationAttempt -Attempt $attempt -Reason 'Opening observed; content remains unobserved'
Complete-PtVerificationItem -Run $run -ItemId L1 -Reason 'Partial coverage; cannot pass'
```

PASS requires explicit evidence; user-visible PASS additionally requires a Normal-path
PNG/JPEG reference attached to a completed producing step and a PASS observation.
Image header checks reject text masquerading as screenshots, but do not analyze pixels:
the verifier still owns the behavioral judgment. Use `-Synthetic` for generated fixtures.
Synthetic images cannot satisfy a user-visible product PASS; they only exercise that gate
in `InfrastructureAcceptance`, conspicuously labeled as **not product signoff**.

Allowed observation taxonomy:

| Verdict | Category |
|---|---|
| PASS | Nonempty verification method, as in the reporting format; no PASS subtype. |
| FAIL | `product`, `checklist-stale`, `checklist-ambiguous` only. |
| BLOCKED | `BLK-ENV`, `BLK-HARDWARE`, `BLK-DRAG-REQUIRED`, `BLK-DESTRUCTIVE`, `BLK-VISUAL-RENDER`, `BLK-OVERLAY-INPUT-BLOCK`, `BLK-EXTERNAL-APP`, `BLK-INFRASTRUCTURE`. |
| NOT-OBSERVED | `not-observed`, with a specific reason. This is child coverage, not a new product verdict. |

Unfinished inventory is reported as item **BLOCKED / BLK-INCOMPLETE**. Script/command
errors are execution **Error / BLK-INFRASTRUCTURE**, never inferred product FAILs.
Normal product/checklist failures are **sticky for this run**, even if another Normal
attempt subsequently passes. There is no within-run waiver/resolution mechanism: preserve
the run and start a new one after a product/checklist fix. Diagnostic success (especially restart/recovery)
cannot replace Normal reopen coverage or supply its evidence. All attempts remain visible.

Driver errors are different: stop the failed attempt with its reason, repair the driver,
then start a new **Normal** attempt and repeat the item's complete required coverage.
Only that latest Normal attempt supplies passing observations; assertions cannot be pieced
together across stale attempts. Earlier closed driver failures and diagnostic probe errors
remain in the report but do not permanently block a successful Normal rerun. Open attempts,
interrupted steps and unresolved latest-Normal errors still withhold signoff.

## Cleanup, failure handling and final export

Record baseline/restoration comparisons from the paired-state helpers as artifacts in a
Normal Cleanup context. A cleanup function returning successfully is not restoration
evidence. The receipt must explicitly describe the mutations and matching restore results;
for no mutations, attach a baseline comparison proving that claim. A failed receipt or
missing receipt withholds signoff. The recorder does not restore state itself or infer
which mutations an uninstrumented helper made.
After a cleanup driver failure, a new Normal Cleanup attempt must supply its own successful
restoration evidence. Earlier PASS receipts remain history, not proof of the retry's final state.

Preserve the root exception across cleanup **and recording** errors:

```powershell
$rootError = $null
try {
    # Recorded driving and observations.
} catch {
    $rootError = $_
} finally {
    try {
        # Start a Normal Cleanup context; perform paired restoration in recorded steps.
        # Register restoration artifacts, Add-PtVerificationRestoration, stop the context.
    } catch {
        if ($rootError) {
            $rootError.Exception.Data['CleanupFailure'] = $_.Exception.Message
            [Console]::Error.WriteLine("Cleanup failed: $($_.Exception.Message)")
        } else { $rootError = $_ }
    }
    Set-PtActiveVerificationAttempt -Attempt $null
}
# Export even on failure, without inventing observations or successful restoration.
try { $partial = Export-PtVerificationReport -Run $run }
catch {
    if (-not $rootError) { throw }
    $rootError.Exception.Data['ReportFailure'] = $_.Exception.Message
    [Console]::Error.WriteLine("Report failed: $($_.Exception.Message)")
}
if ($rootError) { throw $rootError }
```

`Invoke-PtVerificationStep` makes nonterminating errors terminating and records before
rethrowing. Native failures must throw (the winapp wrapper already does); on runtimes
supporting it, the step also enables `PSNativeCommandUseErrorActionPreference`. On older
PowerShell 7 runtimes, explicitly check native `$LASTEXITCODE` in custom actions.
Use synchronous actions; do not launch unawaited child work. Avoid passing secrets:
commands, arguments, streams, source text and exception details are intentionally retained.

For normal completion, supply actual retrospective rows with `Friction`, `Source`,
`Severity`, `Cost`, `SuggestedFix` per reporting-format section G, or explicitly
`-NoFriction`. Do not default to a frictionless claim. Complete every item and stop every
attempt before finalization. Finalizing incomplete/failed coverage is permitted, but
signoff remains **WITHHELD**. Signoff is also withheld for unresolved command errors, pending artifacts,
missing recorded preflight, cleanup failure, and interrupted steps/attempts.
Non-passing Diagnostic observations also withhold overall signoff even when all Normal
observations passed; they remain separate from the Normal item verdict.

```powershell
$export = Complete-PtVerificationRun -Run $run -Retrospective $frictionRows
Test-PtVerificationArchive -Workspace $run.Workspace
# Move the entire folder using the parent's archive workflow; do not merge/overwrite archives.
Test-PtVerificationArchive -Workspace $movedWorkspace
```

## On-disk contract and limitations

`run.json` is the mandatory verbatim inventory/metadata. `inputs\` contains byte snapshots.
`events.jsonl` contains append-only, sequenced, hash-chained event envelopes with run,
item/attempt/step IDs, phase, timestamps, command, duration, errors and artifact references.
`DurationMs` spans start/end; `ActionDurationMs` separately measures the invoked action,
excluding source preparation and completion hashing.
Each `StepStarted` is durable before executing the action; absent `StepEnded` is visibly
**INCOMPLETE**, with null end/duration, not silently omitted. After interruption, reopen
the run and export it; do not fabricate completion of the lost attempt.

UUID attempt/step/artifact paths prevent friendly-name collisions. Each step retains
`command.txt`, `executed.ps1`, `arguments.json`, optional `implementation.ps1`,
`stdout.txt`, `streams.jsonl` and `error.txt`. String stdout is retained without newline
rewriting; `streams.jsonl` preserves record boundaries/type/stream for multiple outputs.
Non-string objects use PowerShell's textual representation for the raw log, while the
wrapper returns the original objects. Binary commands need an explicit binary output
file registered as evidence, not a PowerShell text pipeline.
For PowerShell formatting packets, `streams.jsonl` retains CLIXML in `Text` with the original
packet type; `stdout.txt` contains the rendered table/list. Formatting does not replace
ordinary return objects with strings, and caller context is restored on exceptions too.

Markdown uses encoded code spans for unsafe command characters and `<br>` for line
breaks; its adjacent raw-command link is authoritative for exact copy/paste. Long scripts
link their snapshots. `results.json` retains exact unescaped strings and every observation,
including unobserved children of a failed item. The fixed report is rendered from records,
not a new per-run generator. No raw inspect dumps are stuffed into Markdown.

`artifact-manifest.json` hashes inputs, evidence, source/output files, the journal, report
and results; it never hashes itself or other hash-dependent manifests. A partial export
has unique root filenames and its own journal snapshot, so later journal appends do not
invalidate it. Unsealed interrupted outputs are labeled as such and never become PASS
evidence. Do not export while an action is still writing its outputs. All evidence links
are relative to the workspace, so moving the whole folder preserves them.
Validation with a partial manifest reads only that manifest's frozen journal; later corruption
or loss of the live journal does not invalidate an intact partial export.

Exports/finalization reject missing or changed referenced files. Existing raw records
remain intact, and a unique `export-failure-*.txt` or `finalization-failure-*.txt` preserves
the failure when storage is writable. Secondary recording failures are attached to the
original exception and surfaced, never substituted for it. Final output files are
create-new only; a report without its valid manifest is **not** a completed deliverable.

Hashes detect accidental corruption, not malicious rewriting of both files and hashes;
this is not a signed audit ledger. Do not concurrently write a workspace from multiple
handles/processes, edit sealed evidence, resume a completed item, or use the ambient
context across runspaces. `-ScriptFile` executes under the snapshot's `$PSScriptRoot`;
pass dependency/fixture directories explicitly rather than relying on original relative
paths. Unknown/unrecorded external commands cannot be recovered automatically.
The live single-writer handle caches already-parsed events and detects journal size/time
changes. Export and archive validation always bypass that cache and replay every event/hash.

## Offline acceptance

No Pester, installs, desktop session, PowerToys process or settings access is required.
The standalone script creates only its own named workspace and preserves it as evidence:

```powershell
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtVerificationReport.ps1" `
    -Workspace "$env:TEMP\pt-report-acceptance-$([Guid]::NewGuid().ToString('N'))"
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtInvocationContracts.ps1"
```

The fixtures include a clearly synthetic PNG, mixed verdicts, interrupted child PowerShell,
throw/rethrow and recorder-finally failures, nested fake winapp discovery/probes, script
revisions, corrupt evidence/journals, Markdown/Unicode, input edits and moved archives.
Expected injected errors/warnings are recorded; the script fails immediately on an
unexpected result and writes `acceptance-results.json`. It never runs historical scripts.
The invocation-contract suite additionally exercises grouped formatting, the documented
read-only preflight, inherited helpers in a copied script, a uniquely owned local kernel
event, real CLI help with an empty argument, and module-style evidence names. It does not
signal PowerToys events or drive product UI.
