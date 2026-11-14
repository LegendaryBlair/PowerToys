# Reliable PR visual evidence

Produce evidence that a reviewer can understand without reading the PR description:
**what was wrong or changed, which real action was performed, and what the result is.**

This guide covers visual Scenario B evidence for PowerToys modules automated through
PowerShell. It composes the existing recorder, not a new capture framework.
For a PowerShell module with no UI, use functional tests, structured output and output
diffs instead of manufacturing a visual demonstration.

Follow [PR validation](scenarios/pr-validation.md), [pre-flight and restoration](pre-flight.md),
and the existing [recording/report workflow](recording-workflow.md). This guide adds
media selection, capture coordination, presentation and publication requirements.
It does not replace those documents' ownership rules, verdicts or evidence gates.

## Required sequence

1. Define the PR claim, expected result and independent observer.
2. Resolve the real binaries and the comparison conditions.
3. Choose the smallest sufficient media: screenshot, sequence or recording.
4. Declare ownership, preservation, capture region and cleanup before mutation.
5. Capture real actions, retaining original media and independent observations.
6. Restore and verify state at the end of live interaction.
7. Prepare a self-explanatory presentation; validate content, timing and provenance.
8. Archive locally for human review, then publish only explicitly approved assets.

**Command success, a valid PNG, or an MP4 that plays is not a product PASS.**
A static dummy-window recording proves capture capability, not a bugfix.

## 1. Define the claim and module-specific adapter

Derive cases from the PR description and diff; do not expand every PR into a full
module checklist. Read the relevant [module profile](modules/README.md), then discover
the current UI rather than treating an old caption or selector as authoritative.

For each case, declare the following in the existing run inputs and resource plan.
This is an adapter checklist, not a request for a new configuration schema.

| Field | Required information |
|---|---|
| Claim | Exact expected behavior, including the condition that triggers the bug/change |
| Entry and action | Actual UI, hotkey, named event, shell action or CLI route being tested |
| Runtime identity | Executable/DLL/package path, revision, hash and current process generation |
| Controls | Current typed/scoped selectors, supported patterns and physical coordinate space |
| Capture anchor | Exact HWND/control or fixed owned work-area region, including relevant popups |
| Observer | UIA state, native geometry, persisted values, output file, input events or another independent measurement |
| Preservation | Original files/existence, cached state, clipboard, windows, settings, input state and relevant providers |
| Cleanup | Normal exit/restore operations, dependencies, expected post-state and comparison method |
| Limitations | Missing hardware, permissions, capture support, observer resolution or unsupported restoration |

Use the [shared helpers](helper-workflow.md) for identity, input, state and capture.
Keep newly discovered locators and narrowly scoped adapters with the run. Do not edit
profiles or promote helpers as a side effect of verification; maintenance needs its
own scope.

## 2. Establish genuine comparison conditions

- Declare `BITS` before driving. Use installed bits only when inclusion of the change
  is confirmed. Otherwise follow the isolated build/deployment route.
- Verify actual build exit codes and outputs. A log message or stderr text alone is
  not the exit status. Preserve stdout, stderr, build logs and output identities.
- Identify the processes or loaded components that actually handle the action.
  Launching a local Runner does not prove that an installed singleton or shell DLL
  was replaced.
- For a before/after claim, run a genuine relevant pre-fix revision and the PR
  revision. Never simulate the old behavior, relabel an unrelated screenshot, or
  present two settings on the same build as two revisions.
- For a bugfix, establish that the baseline contradicts the valid expectation and
  the PR satisfies it. Different-looking pictures alone prove neither. For an
  intentional UI change, compare against the requested new behavior instead.
- Match the action, fixture data, starting window state, relevant settings, monitor,
  DPI, theme, locale, privilege and framing. Record intentional differences.
- Use a fixture only when it preserves the behavior under test. Document changes
  such as removing a fixture's maximize button to avoid an unrelated Shell overlay;
  apply them identically to both sides. Do not change global OS settings for aesthetics.
  If the claim concerns that Shell interaction or window capability, the fixture
  change is invalid.
- If baseline reproduction fails, retain that limitation and continue safe PR checks.
  Label the resulting media **after-only** or **baseline not reproduced**. Lack of
  baseline reproduction does not block unrelated target validation, but it does
  prevent a demonstrated before/after claim.

## 3. Select media and capture surface

| Claim | Preferred evidence |
|---|---|
| Static layout, text, style or final geometry | Matched PNGs, usually before and after |
| Several discrete states | A short, ordered screenshot sequence with captions |
| Dragging, animation, timing, flicker or transient UI | A short MP4 with timestamped frames and action observations |
| Non-visual output or internal behavior | Functional tests and structured results; visuals only when they add information |

A reviewed video alone can satisfy `UserVisible=true`; no extra screenshot is required.
Register a finalized MP4 as `Video`, not generic `Evidence`, and associate it with the
completed Normal producing step and reviewed assertion. The recorder checks MP4 box
structure (`ftyp`, `moov`, nonempty `mdat`), not codecs, decoded frames or behavioral truth.
Playback, privacy, timing and the independent observer remain the verifier's responsibility.

Keep the original capture separate from annotated/cropped presentation assets.
Capture audio only when required by the claim and authorized; do not record ambient
or system audio by default. A silent MP4 cannot prove an auditory behavior.

| Surface | Capture approach and boundary |
|---|---|
| Ordinary WPF/WinUI/Win32 window or control | Target an exact HWND or scoped element; verify provider behavior and screenshot bounds |
| Menus and owned popups | Check actual popup inclusion, clipping and capture side effects; use passive owned capture when necessary |
| Moving windows or cross-process overlays | Record a fixed, owned opaque backdrop/work-area region so position and overlays remain visible |
| Explorer integration | Use a test-owned window/folder and safe fixture names; establish the actual handler identity |
| Protected, capture-excluded, elevated or hardware-dependent surfaces | Confirm the prerequisite and observer; report a concrete limitation rather than weakening the test |

Do not assume window capture includes another process's overlay. Conversely,
screen-region capture includes whatever appears above that region. An HWND alone
does not establish privacy or ownership of all captured pixels.

## 4. Prepare tools and state before capture

Follow the [winapp toolchain policy](winapp-toolchain.md): resolve the permitted
version, inspect matching documentation and actual help/schema, record executable
identity/hash, and keep it fixed during the run. Check the same details for any
encoder. Do not assume a past flag, backend or installation path still applies.

Use [resource sessions](session-safety.md) and paired snapshots before navigation,
activation or input. Preserve module-specific file/reload boundaries; do not edit
JSON to bypass a Settings binding or user-flow failure. Preserve clipboard formats
when the flow can change them. Keep recovery payloads private, outside publishable media.

Check interactive-desktop availability and integrity levels before injected input.
Guard the exact target HWND immediately before the action. Resolve physical coordinates
from current bounds and hit-test them; do not reuse coordinates from another run.

Use a named event for a downstream-action claim, not as proof that a physical shortcut
is bound. Record actual key/gesture delivery when the input route is part of the claim.

Create a unique live workspace under `%TEMP%`. Do not overwrite a previous take.
Do not launch a full-module test batch until a small owned capture/drive/cleanup probe
establishes that the selected tool route works.

## 5. Capture while driving the UI

### Screenshots

Capture a settled, meaningful state, with the intended control fully visible.
Check capture quality immediately. A screenshot call can restore or foreground a
window; it is not automatically a passive observer.

Syntax example inside an already prepared, active verification attempt:

```powershell
$imagePath = New-PtVerificationArtifactPath -Attempt $attempt -Name 'after.png'
Invoke-PtWinApp -Arguments @(
    'screenshot', '-w', "$targetHwnd", '-o', $imagePath, '--json'
)
$image = Add-PtVerificationArtifact -Attempt $attempt -Path $imagePath `
    -Kind Screenshot -Description 'Observed PR state' -StepId $attempt.LastStepId
```

For overlays or held input, prefer the existing `Save-PtPassiveScreenshot`,
`Save-PtOwnedScreenshot` or `Save-PtOwnedControlScreenshot` contract as appropriate.
Observe state before and after capture; reject a capture that changed the state
whose appearance it was meant to prove.

### Concurrent recording and input

On winapp versions supporting workflow coordination, use **one identical
`WINAPP_UI_WORKFLOW_ID` for the recorder and every cooperating UI command**.
Without that identity, a recording can block input from another invocation.
A screenshot is an exclusive operation; do not assume it can overlap a gesture
just because a shared recording can.
Generate a fresh ID for each logical workflow. Do not share it across unrelated
agents or modules to bypass coordination. Run one interactive case at a time on
the desktop; concurrent capture/input is one cooperating case, not parallel module testing.

Capture argument example after ownership and framing are established:

```powershell
$workflowId = [guid]::NewGuid().ToString()
$env:WINAPP_UI_WORKFLOW_ID = $workflowId
$videoPath = New-PtVerificationArtifactPath -Attempt $attempt -Name 'after-raw.mp4'
$captureArguments = @(
    'record', '-w', "$captureHwnd",
    '--duration-sec', '12', '--fps', '10', '--max-edge', '1600',
    '--frames', '--cursor', '-o', $videoPath, '--json'
)
# Add '--capture-screen' only for a verified, owned composed region.
```

These are syntax examples, not a complete ownership or asynchronous driver.
Compose execution with these requirements:

- Start the bounded recorder in a separate worker/process, passing the same workflow
  ID explicitly; PowerShell 7 `Start-ThreadJob` is one option. Make recorder completion
  a cleanup dependency of its target/backdrop. Fresh PowerShell processes do not inherit
  variables from an earlier tool invocation unless passed through their actual environment/arguments.
  Give `Invoke-PtWinApp` an explicit timeout covering startup, recording and finalization
  (for example 45 seconds for this 12-second take, within its 120-second limit).
- Keep the verification journal **single-writer**. The parent records the exact
  capture command, arguments, source, start/completion and worker result. A recorder
  worker can use `Invoke-PtWinApp -SkipRecording`, but must not concurrently append to that journal.
  Read-only scene observers must not mutate resource receipts.
- Establish recorder readiness through supported runtime evidence. A live process or
  a sleep alone does not prove frames are being captured. Independently confirm
  afterward that the action occurred between capture start/end and appears in frames.
- Drive through scoped UIA or guarded input. Use documented key-hold helpers with
  release in `finally` when the action needs a modifier; do not invent a CLI drag flag.
- Record action timestamps and independent outcomes, not only command return values.
- Use intentional pauses for viewer comprehension, not as readiness assertions.
- Observe the owned capture region throughout a composed recording. If an unknown
  surface appears, reject that take; never whitelist a Shell class or arbitrary
  same-caption window to make the privacy check pass.
- Await and finalize the recorder before closing its backdrop or target. Keep the
  backdrop alive during error cleanup so remaining frames cannot expose the desktop.
- Propagate worker errors and actual exit codes. Bound waits and terminate only
  specifically owned operations when necessary; no name-based process killing.
- After all cooperating calls finish, release the workflow turn with the supported
  `yield` command. Preserve any pre-existing process-local environment value.

Check the reported backend. A fallback that holds exclusive desktop access can
prevent interleaving even with a shared workflow ID. Diagnose it before switching
tools; do not silently substitute an untested capture route.

### Snipping Tool fallback

Use Snipping Tool only when a specific CLI limitation remains and the fallback can
preserve the same scene, timing, privacy and restoration contract. It does not remove
secure-desktop, capture-exclusion or hardware restrictions.

The [documented modern Snipping Tool protocol](https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-snipping-tool)
requires a packaged caller and registered redirect URI for capture responses.
Do not assume launching a URI from PowerShell returns a saved file. Interactive
Snipping Tool automation also needs ownership, clipboard and save-location handling.
Do not register packages/protocols or change user capture settings without authority.

## 6. Validate raw evidence and restore live state

For each take, retain:

- Actual revision and runtime identity; matched input/settings/display conditions.
- Exact commands, tool versions, timestamps, case/attempt IDs and observer results.
- Original PNG/MP4, recording JSON, frame manifest, `frames.ndjson` and referenced frames.
- Original file sizes and SHA-256 hashes, plus capture warnings/errors.

Check that the intended action and outcome are visible, relevant overlays are included,
and no private or unrelated content is exposed. Verify complete frame bundles and
successful MP4 finalization. Review the timeline, not just its first or last image.
One repeated static frame is valid encoding output, not proof of an interaction.

Compare capture elapsed time, sample count, achieved cadence, frame timestamps and
decoded MP4 duration. **Requested FPS is not proof of achieved FPS or real-time
playback.** If the observer is too slow for the claim, leave that claim unverified.

If playback timing differs materially, preserve the original. A presentation may
replay genuine samples using differences between their recorded `elapsedMs` values,
rebased to the first sample. Disclose that reconstruction and output-frame quantization.
Do not invent intermediate product frames or use edited footage as an independent
timing/performance measurement.

### Register a completed video and its frame bundle

Run this inside the still-open Normal case after its recorded capture/drive step completes.
`$actualObservation` describes the observed action/outcome, not simply successful encoding.
The recording itself is visual evidence; no frame needs to be relabeled as a screenshot.

```powershell
$producerStep = $attempt.LastStepId
$video = Add-PtVerificationArtifact -Attempt $attempt -Path $videoPath `
    -Kind Video -Description 'Original PR recording' -StepId $producerStep
$frameRoot = Join-Path ([IO.Path]::GetDirectoryName($videoPath)) (
    [IO.Path]::GetFileNameWithoutExtension($videoPath) + '.frames'
)
$bundle = Add-PtVerificationArtifactBundle -Attempt $attempt -Path $frameRoot `
    -Name 'after.frames' -Description 'Original timestamped recording bundle' -StepId $producerStep
$canonicalRoot = Resolve-PtReportPath $attempt.Run $bundle.Path
foreach ($line in [IO.File]::ReadAllLines((Join-Path $canonicalRoot 'frames.ndjson'))) {
    $sample = ConvertFrom-PtReportJson $line
    $relative = "$($bundle.Path)\$($sample.file.Replace('/', '\'))"
    $frame = Resolve-PtReportPath $attempt.Run $relative
    if ($relative -cnotin $bundle.Files.Path -or -not [IO.File]::Exists($frame)) {
        throw 'Frame index references unregistered or missing evidence.'
    }
}
$sequence = Add-PtVerificationObservation -Attempt $attempt -AssertionId $assertionId `
    -Actual $actualObservation -Evidence (@($video) + $bundle.Files)
```

The bundle helper creates a unique canonical root while retaining every internal directory
and filename, including `frames.ndjson` references. Use its returned `Path` in local media
indexes; do not link the unregistered source tree or flatten files into independent aliases.
Use the registered `$video.Path` for playback. Absolute paths inside the unchanged capture
JSON describe the original capture location, not portable links after archival.
Its registered files are included in `Test-PtVerificationArchive` hash checks after relocation.
Validate the recording manifest's status/counts and its frame-index relationship too;
96 samples can reference six stored images and are not 96 distinct product states.
Review the observation before assigning a verdict. Do not relabel sealed legacy MP4
`Evidence` references or import old captures as fresh Normal observations.

Release injected keys/buttons, finish recording, close owned UI normally, quiesce
writers, restore only attributed changes and independently compare originals.
Restore the pointer before losing the owned interaction surface or returning to a
higher-integrity foreground. Include test-started helper/provider exit verification.

Record Normal Cleanup and close the live-execution interval **before offline
presentation work**. Rendering a video is not a reason to rewind the user's desktop
again much later. If a later probe sees drift, preserve unrelated activity, record
the limitation and do not claim final equality that was not observed. Retain private
recovery if restoration is unresolved; never replace the original baseline.

## 7. Make the presentation understandable alone

A reviewer watching muted must understand the following without the PR body:

| Part | Required content |
|---|---|
| Context | Module, PR/change, and the expected behavior or visible problem |
| Before | Genuine baseline label/revision, relevant starting state, action and observed result |
| After | PR label/revision, matching action/conditions and observed result |
| Conclusion | A held result or aligned comparison showing the actual difference |

For after-only evidence, replace the before section with an explicit limitation.
For a new feature with no equivalent old flow, show the real prior UI/behavior or
document its absence; do not fabricate a comparison.

- Use readable captions, a visible pointer/action cue and enough time to inspect results.
  Usually a short focused clip is better than a long recording of setup.
- Keep framing and scale matched. Show the final outcome, not only a successful click.
- Label annotations, expected-region outlines, fixture backdrops and intentional crops.
  Never crop away a failure or redraw product UI as if it were captured.
- Distinguish observation channels in captions and summaries. For example, no separate
  UIA Text node named `Del` does not mean the shortcut hint is visually absent:
  report the UIA query, AcceleratorKey and reviewed pixels separately.
- Preserve raw media. Give each derived version a new name and retain its input hashes,
  encoder version/hash, filters, captions, timing edits and source-to-output mapping.
- Reuse an available encoder such as FFmpeg. Use session-local tooling when preparation
  is needed, verify downloaded packages, and never disable TLS/signature checks or
  alter product dependencies just to edit evidence.
- Decode the entire final video; inspect exact frames covering the introduction,
  action, transient state, final outcome and comparison. Verify duration, dimensions,
  codec, legibility, privacy and local playback. Check every local review-page link.

FFmpeg filters such as `drawtext`, `drawbox`, `trim`, `setpts`, `scale` and `pad` can
prepare labeled segments. Use options supported by the actual encoder version.
After making segments with compatible codecs, dimensions, time bases and pixel formats,
the final assembly can use:

```powershell
& $ffmpeg -f concat -safe 1 -i $playlistPath `
    -c copy -map_metadata -1 -movflags +faststart $presentationPath
if ($LASTEXITCODE -ne 0) { throw 'Presentation assembly failed.' }
```

Stream-copy concatenation does not itself fix timing or add captions; those operations
must already be present in the segments. Preserve encoder stderr and exit status.
With verified local tool paths, inspect metadata and decode the complete presentation:

```powershell
& $ffprobe -v error -show_entries `
    'format=duration,size:stream=codec_name,width,height,r_frame_rate,nb_frames' `
    -of json $presentationPath
if ($LASTEXITCODE -ne 0) { throw 'Media metadata inspection failed.' }
& $ffmpeg -v error -i $presentationPath -f null -
if ($LASTEXITCODE -ne 0) { throw 'Presentation decoding failed.' }
```

## 8. Archive, review and publish

Use two explicit artifacts, not one archive that is edited after hashing:

| Artifact | Contents and validation |
|---|---|
| Private canonical archive | Original journal, source snapshots, reports and registered raw evidence. Validate with `Test-PtVerificationArchive`; never redact or rewrite sealed files/hashes. Keep recovery payloads separately private. |
| Reviewed delivery bundle | Only approved material, with redaction/presentation changes explicitly identified. Record each delivered relative path, length/hash, source path/hash when applicable, transformation/exclusion reason and source-archive identity. Validate this separate delivery manifest, not unchanged canonical hashes against changed files. |

Register video/bundle observations during the producing Normal attempt. Use the existing
exporter for canonical `report.md`, `details.md`, `results.json` and the artifact manifest;
do not replace verdict generation. An HTML review page is a derived presentation.

Privacy review includes commands, arguments, stdout/stderr, JSON/JSONL, UIA metadata,
logs and source snapshots as well as pixels/audio. Token-pattern matching alone is not
a privacy guarantee. A clean screenshot does not make the raw diagnostic archive publishable.
Reject unsafe captures and retain only safe rejection metadata in the delivery.
Do not put sensitive originals into a synced/public location merely because it is the
default archive path.

When preparing a redacted copy, keep original manifests as clearly labeled provenance.
It is expected that the canonical validator rejects modified diagnostic files in that copy;
do not rewrite the original journal to conceal this. A new delivery manifest protects
all delivered files, including frame paths actually used by playback and review links.
Do not hard-code a past run's redaction count or silently omit unexpected matches.
Identify each derivative as a redacted/corrected delivery, not an immutable original.
Later wording corrections belong in a new delivery/assessment, leaving sealed results intact.

Collect the required [agent-origin statistics](reporting-format.md#agent-origin-execution-statistics)
from closed live-execution/cleanup intervals. Do not count helper-internal loops as
agent calls or charge offline presentation/report work to product-case driving.
Additional live recovery requires another explicit interval.

Validate the canonical archive in its authorized private location. Validate the delivery's
own manifest, media and links before and after moving it to the approved review location
(normally `PowerToys\Module-Signoff`). Do not overwrite a sealed archive or earlier delivery;
use a new version with a transformation receipt and a link to its source.

**Capture approval is not publication approval.** Obtain explicit human approval for
the exact repository/PR, comment text and final media version/hashes. If the user is
unavailable, leave publication pending. A later edit to approved media needs renewed
review.

Prefer a new PR comment, including on an already merged PR. Do not edit the PR
description unless requested; follow its template and applicable human-authorship rules.
Use the `github-pr-media` skill when available and confirm actual CLI support:

```powershell
gh --version
gh pr comment --help
```

After approval and a final hash check, the video form is:

```powershell
gh pr comment $prNumber --repo $repository `
    --body $approvedComment --attach $approvedVideoPath
```

Do not include video image-markdown such as `![](demo.mp4)`: a bare uploaded URL in its
own paragraph is needed for an inline player. Image attachments can use descriptive
alt text. Keep paths in quoted variables; never interpolate untrusted filenames into
shell commands.

Capture stdout, stderr and the actual exit status, even on failure. Partial attachment
failure can still create a comment: locate that exact comment and retry only a known
failed asset, never blindly repeat the whole write.

Read back the exact returned comment URL/ID, not the newest comment. Verify all expected
asset URLs, correct text and absence of local paths. When the host serves original
asset bytes, download and compare SHA-256 with the approved file. Record any documented
transcoding rather than asserting byte equality. Preserve a publication receipt with
comment URL, asset URLs, hashes and verification time beside the unchanged archive.

## Completion gates

- [ ] Claim, real runtime identity and comparison scope are explicit.
- [ ] Media proves the intended action/result; independent observations support the verdict.
- [ ] Before/after conditions match, or limitations are visibly labeled.
- [ ] Capture framing, privacy, cadence and timing were checked.
- [ ] Input and recording overlap is demonstrated when concurrency is required.
- [ ] Cleanup is independently verified; unresolved resources/drift remain explicit.
- [ ] Final media is understandable alone, and raw evidence/provenance remains available.
- [ ] Canonical archive and derivative delivery each pass their own integrity checks.
- [ ] Registered video/frame-bundle paths and local review links survive archival.
- [ ] Human approval precedes publication of the exact reviewed assets.
- [ ] The actual posted comment and attachments are verified; no partial success is hidden.

Do not describe this workflow as universally supported. Permission, hardware, provider,
capture and restoration limitations remain case-specific. Use the existing
PASS / FAIL / BLOCKED taxonomy and continue independent eligible checks.

## Adoption before making this a shared default

Broader capture-adapter acceptance remains separate from these recorder contracts.
Pilot representative module families: a single-window Settings/editor flow, a
cross-process overlay or moving-window flow, an Explorer integration, and a
clipboard-sensitive flow. Confirm their distinct adapters, repeated-run cleanup and
local review artifacts; one FancyZones success does not establish support for all modules.

Exercise missing foreground, a rejected private overlay, incomplete recording and
restore conflict as infrastructure checks, not synthetic product signoff. Verify that
errors preserve evidence and originals, dependent work stops safely, and no publication
occurs without approval. Further reusable capture code or broader default behavior
requires a separately scoped, reviewed maintenance change.
