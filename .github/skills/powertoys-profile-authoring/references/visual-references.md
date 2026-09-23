# AI-assisted visual references

AI can perform the core-case selection -> UI execution/recording -> frame review -> screenshot extraction
workflow. A person need not manually operate Steps Recorder for every module. The important distinction is
**automated capture versus authority to declare the captured UI correct**.
No accepted visual reference is required merely to collect candidate evidence or assess an unambiguous
checklist result. Only a genuinely undefined visual expectation needs a specification decision; do not turn
reference promotion into a prerequisite for every visual test.

## 1. Select a small, justified visual scope

Map selected assertion IDs to user-visible states, not merely a list of windows:

| State category | Why it can be valuable |
|---|---|
| Main activation and alternate mode | Identify the intended surface and navigation outcome |
| Core input/result | Show the real user-facing result, not only hidden UIA fields |
| Settings controlling behavior | Pair the selected setting with its actual effect |
| Popup/flyout/overlay | Capture composed surfaces omitted by window-only images |
| Empty/error/disabled condition | Document an important negative state |
| PR-specific UX change or high-risk boundary | Cover the new claim without recording every routine click |

Let the Author propose the selection and rationale from the checklist/PR claims. Keep user-specified core
cases. This selection is for reference assets, **not** permission to omit the rest of the functional checklist.
Choose approved test-owned content and define exactly what must remain visible.

## 2. Record while the Runner executes

Use the selected execution revision's capture helpers and inspect the installed CLI help first:

```powershell
winapp ui record --help
winapp ui screenshot --help
```

On winapp 0.6.1 the following options are available:

```powershell
winapp ui record -w $hwnd --duration-sec $duration --frames -o $capturePath
```

`--frames` writes timestamped JPEGs, `frames.ndjson` and a manifest under the output-name `.frames` directory.
Use ordinary `record` without `--frames` when MP4 is the selected output. Verify actual output files rather
than assuming every mode produces both formats.

`$duration`/frame rate/size are selected for the approved scenario and storage allowance, not hidden workflow
budgets. Timed or explicitly controlled attached recording must stop in cleanup. An asynchronous recorder may
run alongside the **one** UI driver; it does not justify another agent controlling the same desktop.
Verify recorder readiness before the action and final artifacts after stopping. Redirected stdin/EOF can end
recording; do not mistake an immediately exited recorder for a successful recording.

Steps Recorder is an optional acquisition tool when requested and available. Inspect local availability/help;
do not assume `psr.exe` or a particular export format exists everywhere. If using PSR output, keep its
step-to-image associations and original archive. Do not require PSR when scoped winapp recording already works.

### Capture caveats

- Use exact live HWND/process identity and record build, UI stack, theme, language, DPI and display geometry.
- Record action and settled-observation timestamps so frames can be related to assertions.
- Popup/overlay references may need composed-screen capture spanning more than the owner HWND.
- In winapp 0.6.1, `screenshot --capture-screen` implies focus. It can dismiss a popup or change the state being
  measured. Check recorder behavior too; use an available passive capture path when activation is unacceptable.
- Observe foreground, surface identity and visibility before/after capture. Keep unstable/occluded/wrong-window
  captures as diagnostics, not accepted reference evidence.
- Do not record passwords, user documents, notifications, personal clipboard content or unrelated desktop areas.
  Pause/redact or use clean owned fixtures when the capture region cannot be made safe.
- Prepare that safe visible state in the Author's fixture plan. Private local backup/restore can be necessary
  without disclosing the payload; do not assume all editor tests are impossible just because history is non-empty.
  Never crop out the feature under test or clear user data without authorization to manufacture a clean image.
- Captures excluded by display affinity or a detached desktop remain explicit limitations; do not fabricate pixels
  from UIA, reuse an unrelated screenshot, or silently bypass the tested interaction.

## 3. Analyze and extract candidates

The Author reviews the actual video/frames with their action receipts:

1. Locate the requested state and verify the correct application/surface and build.
2. Choose a settled frame; retain the preceding/following frames needed to rule out a transient or wrong transition.
3. Check real pixels for clipping, overlap, theme, labels, selected state and popup composition.
4. Crop to relevant content without concealing the property being tested. Retain the raw source and crop rectangle.
5. Describe what is visible, which assertion it supports and what the image cannot prove.

JPEG/video frames are lossy and may be downscaled. Use them to find a state, not to prove exact RGB values.
For exact-color/pixel criteria, use lossless native-resolution evidence and an independent fixture/value
observation. If replaying the state for a PNG, record it as a **new capture**, not a frame extracted from the old video.

An image cannot prove that a shortcut caused activation, persistence after restart, spoken output or held-key
timing by itself. Keep the relevant input/log/state evidence alongside it.

## 4. Separate candidate, accepted reference and defect evidence

| Status | Meaning | May be used as the expected visual reference? |
|---|---|---|
| `candidate` | Valid capture; correctness/coverage review pending | No |
| `accepted-reference` | Relevant state and expectations explicitly accepted, with provenance | Yes, within declared applicability |
| `defect-evidence` | Valid capture of a known/suspected product deviation | No |
| `invalid-capture` | Wrong state/window, occlusion or capture-induced change | No |

Default promotion requires human acceptance. If the user explicitly delegates reference acceptance, record that
policy and the independent expectation used; do not infer delegation from permission to record.
The Author can prepare all candidates and a compact review sheet automatically.

**Never make the current screenshot the expected baseline solely because it is repeatable or the Runner said
PASS.** In particular, do not overwrite an older accepted reference to erase a regression. A migration may
change toolkit styling without changing UX: distinguish semantic requirements from exact pixel equality and
record intentional differences before accepting replacement references.

## 5. Retain provenance and publish only scoped assets

For each candidate/reference retain at least:

```json
{
  "id": "<module-state-id>",
  "status": "candidate",
  "assertionIds": ["<stable-id>"],
  "sourceRunId": "<run-id>",
  "materialRevision": "<commit-and-manifest-hash>",
  "product": {"version": "<actual-version>", "commitOrTag": "<verified-identity>", "uiStack": "<stack>"},
  "environment": {"theme": "<theme>", "locale": "<locale>", "dpi": "<dpi>", "display": "<geometry>"},
  "sourceArtifact": "<run-relative-recording-or-frame-path>",
  "sourceSha256": "<hash>",
  "timestampOrFrame": "<locator>",
  "crop": "<rectangle-or-none>",
  "visibleState": "<factual-description>",
  "expectationSource": "<checklist/spec/manual-confirmation>",
  "approval": null
}
```

Keep raw recordings and private run state in the local verification archive, not the repository.
After acceptance/privacy review, commit only selected sanitized images and portable provenance/captions:

- `.github\skills\powertoys-verification\assets\<module>\...`
- `.github\skills\powertoys-verification\references\modules\<module>\visual-reference.md`

Use the current engine's asset layout if it differs. Link the visual index from the profile's final
[reference container](module-profile-format.md#8-references-and-accepted-presentation-variants); do not fill the
profile with every frame. Preserve hashes/relative artifact locators without committing machine-specific private
archive paths. Label any annotated/redacted derivative and retain its source privately.

The next fresh Runner receives only accepted references with their applicability, never candidate/failure images
disguised as an answer key. Refresh references when their build/UI-stack/theme/locale applicability changes.
