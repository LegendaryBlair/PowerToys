# Recording and report workflow

Dot-source `scripts\pt-verification-report.ps1` in PowerShell 7. It only defines
functions: no desktop access, product changes, processes, downloads or module imports.
Use it alongside the driving and paired-state helpers, not instead of them. The
[reporting format](reporting-format.md) remains the report-shape contract.

This is a **single-writer, synchronous recorder**, not a test scheduler. Start recording
before discovery/preflight. Record every attempt, including failed probes and recovery.
An action completing or a native command returning zero **never assigns product PASS**.

## Smallest execution loop

Keep one run for one checklist assessment. Do not start replacement full runs to repair a
local observation or make the report cleaner. Use
[`templates\verification-run.ps1`](../templates/verification-run.ps1) for the common
initialize/preflight/cases/finally-cleanup/export lifecycle. Supply actual callbacks and
include the template, caller script and every loaded helper in the input snapshots.
The template does not invent case steps or restoration claims.

`Invoke-PtVerificationCase` handles attempt creation, nested command recording and closure.
Its callback receives the attempt first. Review in groups of 3-5 cases; a successful callback
only means data was collected. The returned handle supports review after the attempt closes:

```powershell
$case = Invoke-PtVerificationCase -Run $run -ItemId L1 -Name 'Normal reopen' `
    -Command 'Run the documented normal reopen and record its actual observation' -Action {
        param($attempt)
        # Perform the actual case, register evidence, and inspect capture quality.
        Add-PtVerificationObservation -Attempt $attempt -AssertionId opens `
            -Actual $actualObservation -Evidence @($proof)
    }
# After reviewing the recorded observation/pixels, not merely the exit code:
Add-PtVerificationAssertion -Attempt $case.Attempt -AssertionId opens `
    -ObservationSequence $case.Output[0] -Verdict PASS -Category 'Reviewed normal reopen' `
    -Reason $reviewedReason
Complete-PtVerificationItem -Run $run -ItemId L1 -Reason $itemReason
```

Use `Get-PtVerificationReview -Run $run [-ItemId L1,L2]` for daily review, not
`Get-PtReportState`. It consumes newly appended events and reprojects only changed items
through the same verdict logic as export. The returned `Sequence`, `ProcessedEvents` and
`RecomputedItems` expose what was updated. `IntegrityValidated=false` is intentional:
this view does not reread artifact bytes and must never be used as archive approval.
Export and `Test-PtVerificationArchive` still replay and validate the complete evidence.

Review text uses `ActualPreview`/`ReasonPreview` with an explicit `Truncated` flag;
the default is 512 characters (`-MaxTextCharacters` adjusts it). At most two evidence
references are shown, with the full count and observation sequence. Full observations
and all references remain in the journal/export. The view does not return nested raw
UIA trees, run handles or a signoff value.

Use `-ScriptFile` instead of `-Action` for an existing case script; do not serialize/rebuild
attempt handles or invent evidence-transfer scripts. On error, the wrapper closes the attempt
and rethrows the original error. Decide whether a bounded local recovery is justified; do not
turn every exception into another module restart. `Open-PtVerificationRun` reloads the run
in another process; start a new attempt for the affected item, never resume mid-gesture.
For post-capture review after the driving process exits, retrieve its stopped handle with
`Get-PtVerificationAttempt -Run $run -AttemptId <recorded-id>`; it cannot execute new steps.
The thin template's `-Resume` continues only an unsealed run with the same frozen inventory
and stopped attempts. It reruns the supplied preflight/cases/cleanup callbacks, not an interrupted
gesture. Supply only the intended remaining/local cases; it is not a checkpoint scheduler.

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
| `Invoke-PtVerificationCase -Run -ItemId/-Context -Name -Command -Action/-ScriptFile [-ArgumentList] [-Kind] [-OperationKey]` | Thin lifecycle; callback gets the attempt first. Optional stable-key operation boundary adds Stage, Cleanup/CleanupArgumentList and explicit budget limits. Returns Attempt and Output, closes on errors and never infers verdicts. |
| `Open-PtVerificationRun -Workspace [-JournalName]` | Reloads a run after interruption or moving it. A nondefault journal is a read-only partial-export snapshot. It does not recreate or complete interrupted attempts. |
| `Get-PtVerificationReview -Run [-ItemId] [-MaxTextCharacters]` | Cheap incremental item/child projection with bounded previews and pending review sequences; no artifact rehash or signoff. Uses the same verdict rules as full export. |
| `Get-PtVerificationAttempt -Run -AttemptId` | Returns a recorded stopped attempt for later review; no new driving or resumption of interrupted steps. |
| `Start-PtVerificationAttempt -Run -ItemId -Kind -Name [-Activate]` | Starts a UUID item attempt, `Kind Normal` or `Diagnostic`; returns its handle. No default path kind. |
| `Start-PtVerificationAttempt -Run -Context -Kind -Name [-Activate]` | Non-item `Preflight`, `Cleanup` or `Diagnostic`; does not add invented checklist items. Diagnostic context requires Diagnostic kind. |
| `Get-PtActiveVerificationAttempt` / `Set-PtActiveVerificationAttempt -Attempt` | Runspace-local ambient context across script boundaries. Use `-Activate`/the setter for top-level calls, or `$null` to clear. Each recorded step temporarily selects its explicit attempt and restores the caller context afterward. |
| `Stop-PtVerificationAttempt -Attempt -Reason` | Records the end and clears this attempt if active. Does not assert product success. Cannot stop a running step. |
| `Invoke-PtVerificationStep -Attempt -Name -Command -Action [-ArgumentList] [-Implementation]` | Writes exact command/action/arguments before execution, records raw streams and completion/error, returns original success-stream objects. Records failure and rethrows the original error. |
| `Invoke-PtVerificationStep -Attempt -Name -Command -ScriptFile [-ArgumentList]` | Executes the **snapshot**, not the mutable original. Identical script/implementation bytes share a hash-addressed source; revisions get distinct snapshots. |
| `New-PtVerificationArtifactPath -Attempt -Name` | Reserves a unique nonexistent absolute output path; returns it. Reusing a friendly name never reuses its path. |
| `Add-PtVerificationArtifact -Attempt -Path -Kind -Description [-StepId] [-Synthetic] [-Name]` | Registers evidence or reuses an unchanged same-attempt reference. Cross-attempt files are linked as ReferenceOnly with original attempt/step provenance, never fresh PASS proof. |
| `Add-PtVerificationObservation -Attempt -AssertionId -Actual [-Evidence] [-Detail]` | Records a concise observation without a verdict; `Detail` stores full text or JSON as immutable evidence rather than embedding it in the journal. Returns the observation sequence. |
| `Add-PtVerificationAssertion -Attempt -AssertionId -Verdict -Category -Reason [-Evidence] [-ObservationSequence]` | Commits a reviewed judgment, including on a closed attempt. With ObservationSequence, defaults to that raw observation's evidence. Unreviewed latest-attempt observations withhold PASS. |
| `Complete-PtVerificationItem -Run -ItemId -Reason [-Caveats]` | Records reviewed item completion. Unfinished coverage still blocks. |
| `Reopen-PtVerificationItem -Run -ItemId -Reason` | Reopens only one completed item in an unsealed run; does not erase observations or failures. |
| `Invalidate-PtVerificationAssertion -Attempt -Sequence -Cause -Reason -Evidence` | Marks an earlier same-item judgment invalid with fresh Normal evidence; cause is InvalidObservation or IncorrectJudgment. Does not assign replacement PASS. |
| `Add-PtVerificationRestoration -Attempt -Verdict -Reason [-Evidence]` | Only a Normal Cleanup context can record restoration. PASS requires registered `Restoration` evidence. |
| `Export-PtVerificationReport -Run` | Writes uniquely named compact report/full details/results/manifest/journal snapshot without completing the run. Returns Report, Details, Results, Manifest and Signoff. |
| `Complete-PtVerificationRun -Run -Retrospective` / `-NoFriction` | Validates evidence, explicitly ends the run, writes `report.md`, `details.md`, `results.json`, `artifact-manifest.json`; returns export paths and Signoff. May finalize a **WITHHELD** run. |
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

Script/implementation sources are stored under `sources\<SHA256>\executed.ps1` or
`implementation.ps1` and referenced by every producing step. Reuse saves copies, not
history: commands, arguments and output streams remain per-step. A shared source is
checked before reuse/execution and again at final validation. Source reuse never
converts another attempt's observation artifact into fresh evidence.

Run/attempt objects passed as callback arguments are recorded as explicit
`VerificationRun`/`VerificationAttempt` identities, not recursive copies of their mutable
event/review caches. The callback still receives the original objects. Other argument
values remain recorded; unsupported JSON depth errors are surfaced rather than silently
truncated. Refer to the journal for the state at that step's sequence.

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

Keep `Actual` and reviewed assertion `Reason` within **4096 UTF-8 bytes**. Oversized
values throw before the observation/judgment is appended; they are never silently
shortened. Write the fact relevant to the assertion, not an entire serialized UIA tree.
Use an existing registered evidence file, or let the helper retain full detail:

```powershell
$sequence = Add-PtVerificationObservation -Attempt $attempt -AssertionId content `
    -Actual 'The realized list contains the two expected rows.' -Detail $rawInspectText
```

String detail is stored byte-for-byte as UTF-8 text; object detail is JSON with explicit
serialization-depth failure handling. The resulting artifact is registered in the same
attempt and attached to the observation. It is not another product judgment. Prefer the
original single tree over a flattened array whose nodes still contain nested children.
Old archived observations are read unchanged; this limit applies only to new writes.

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
not when sealing it. An unchanged same-attempt file reuses the first sealed reference, including
its original metadata. Changed bytes under a sealed path are still an error. An external source
that changes gets a new immutable copy. Cross-attempt reuse links the original file with
`OriginAttemptId`, `OriginStepId` and `ReferenceOnly=true`; it is historical/contextual evidence,
not proof that a new Normal path ran. Never make temporary copies to erase that provenance.

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
Valid Normal product/checklist failures remain failures even if another attempt passes.
Diagnostic recovery cannot replace Normal behavior. A product/checklist change belongs to a
new run with new inputs; a faulty observer or mistaken judgment does not require repeating
unrelated items.

For a demonstrated observation/judgment error, reopen only the affected completed item with
`Reopen-PtVerificationItem`. Repeat its required coverage in a fresh Normal attempt, register
evidence explaining why the old observation was invalid, then use
`Invalidate-PtVerificationAssertion -Sequence <old-judgment-sequence>` with an explicit cause
and reason. All original data/judgments and the correction remain in the journal/details.
Invalidation never grants PASS: the new Normal attempt must independently satisfy every
required assertion and screenshot gate. Diagnostic evidence, another item's evidence and
ReferenceOnly imports cannot justify invalidation. Do not misuse InvalidObservation to
discard an inconvenient real failure; inspect the original observation against the correction
evidence. Frozen archives remain immutable.

Driver errors are different: stop the failed attempt with its reason, repair the driver,
then start a new **Normal** attempt and repeat the item's complete required coverage.
Only that latest Normal attempt supplies passing observations; assertions cannot be pieced
together across stale attempts. Earlier closed driver failures and diagnostic probe errors
remain in the report but do not permanently block a successful Normal rerun. Open attempts,
interrupted steps and unresolved latest-Normal errors still withhold signoff.

For operations sharing an obstacle across scripts/items, use the
[operation boundary](operation-boundaries.md) rather than writing a retry/cleanup wrapper
inside each run. A budget is not permission to invent another entry path or product verdict.

```powershell
$case = Invoke-PtVerificationCase -Run $run -ItemId L1 -Name 'Observe the shared host' `
    -OperationKey module-host-observation -Stage Observe -Command 'Run supplied observation helper' `
    -ArgumentList @($target) -Action {
        param($attempt,$trackedTarget)
        # Use the fixed driver and record concise facts/evidence here.
    } -CleanupArgumentList @($baseline) -Cleanup {
        param($capturedBaseline)
        # Restore the specifically owned state even if driving was rejected.
    }
```

`OperationKey` identifies the shared obstacle, not a script filename or attempt UUID.
The first invocation locks its policy; omitted limits inherit that policy and explicit
changes are rejected. Defaults are three cumulative failed callbacks and 300 seconds
of active failed/recovery work. Successful Normal work and time on unrelated keys do not
consume recovery time; Diagnostic recovery does. Neither success nor reopening the run
resets counters. Cleanup has separate arguments, runs on rejection/failure and does not
consume the drive budget. An action returning successfully never proves restoration.
Supplying stage/cleanup/limits without an operation key is rejected before a case starts.

The fixed report includes an operation-status/event table in `details.md` and a short
link in `report.md`. An interrupted operation or recorder failure with uncertain completion
withholds signoff independently of product verdicts. A budget stop is an infrastructure
fact; report the actual affected coverage rather than automatically marking every item.

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
link their snapshots in `details.md`. `report.md` is the compact review view: every item and
child remains visible, with key evidence and a link to the complete trace. `results.json`
retains exact unescaped strings and every observation,
including unobserved children of a failed item. The fixed report is rendered from records,
not a new per-run generator. No raw inspect dumps are stuffed into Markdown.

`artifact-manifest.json` hashes inputs, evidence, source/output files, the journal, report, details
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
