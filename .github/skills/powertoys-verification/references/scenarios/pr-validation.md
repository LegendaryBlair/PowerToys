# Scenario B — PR validation

**Use when:** you're asked to validate **one or more PRs** by deriving each PR's checklist from its
own description + diff, then driving it. This one scenario covers all the PR shapes:

- a single **open / unmerged** PR ("validate PR #N", "review this fix before merge"),
- a single **merged** PR ("check that #N actually works"),
- a whole **release / hotfix set** of merged PRs ("sign off 0.100.1", "verify the 14 PRs in this draft release").

The *hard, interesting* part — turning a PR into concrete, drivable claims — is identical for all of
them. They differ on only one thing: **what bits you run.**

---

## The bits sub-decision (the only real fork)

Resolve this from the PR and build provenance up front and **echo the answer in the report header**:

> **Is the PR's code already in the build under test?**

| Answer | Bits under test | `BITS:` line |
|---|---|---|
| **Yes** — merged **and** present in the installed / shipped build you're testing | Drive the **installed** bits, **read-only** | `BITS: installed shipped artifact <version> (read-only)` |
| **No / not confirmed** — unmerged/open, **or** merged but not confirmed in the preinstalled build | Fresh worktree; **build runner + Settings + related module(s)** and required dependencies | `BITS: local build of <Module> @ <sha/branch>, sideloaded` |

> **"Merged" is not the deciding word — "in the build under test" is.** A PR that merged into `main`
> but hasn't shipped in the installed build is still the **build + sideload** case (e.g. validating
> a fix ahead of the next release — PR #45242 was exactly this). Only drive the installed bits when
> the code you're validating is genuinely in them.

This is the default local route, not another environment-selection question. Use the existing
worktree/build conventions and [build scripts](../../../../../tools/build/BUILD-GUIDELINES.md).
Do not require or provision a VM. A missing hardware/privilege or unsafe registration condition
blocks only its dependent checks; it does not justify adding a new environment dependency.

Retain the PR identity/state, reviewed head SHA, intended tested revision and any comparison
revision. For the preinstalled route, record its version/path/hash and the source/release evidence
that includes the relevant change; merged status or a version string alone is not inclusion proof.
For local builds, retain the worktree revision/dirty-state evidence, platform/configuration,
build result and actual output identities. Store these in existing input/artifact records, not a
new reporting system.

- **Installed path — the artifact is immutable.** Forbidden: copying source-built files into the
  install or `%LOCALAPPDATA%\...\PowerToys\...`, editing module `settings.json` to bypass a
  Settings-UI step, registering/unregistering COM/MSIX, killing helpers except as a documented user
  action. Allowed: anything a real user does through the shipped UI, read-only probes, screenshots —
  capture pre-state and restore in `finally{}`. If the documented user flow doesn't produce the
  claimed outcome, that's **FAIL** — never "rescue" it by editing install state.
- **Build + sideload path — building unreleased code is the whole point,** so the immutability rule
  does **not** apply to *your* build. It still applies to *unrelated* installed bits you didn't
  build. **Restore the machine to the shipped build when done** (Step 4b).

> A run that mutates the wrong `BITS` (sideloads when the code is already installed, or drives the
> stale installed binary when validating unreleased code) is **invalid regardless of the verdict.**
> Set `BITS` before the first drive command. Full forbidden/allowed list: `index.md` → bits contract
> and `../pre-flight.md` §Hard rules.

---

## Step 0 — Acquire the PR set (discovery model)

For a **single PR**, `N = 1` — skip straight to Step 1. For a **release / hotfix**, a full release
can carry ~100 PRs and a hotfix ~10–25; blindly looping 100 is the wrong default. Resolve the set
with the **smallest, most explicit source available**, then apply the size gate.

### Input modes (prefer the most explicit one the caller gave you)

| Mode | Source | How to enumerate |
|---|---|---|
| **1. Explicit set** *(preferred)* | PR numbers, a sign-off doc, or a draft/published release whose notes list the PRs | Parse the PR numbers directly. For a release: `gh api repos/microsoft/PowerToys/releases/<id>` → extract `#NNNNN` from `.body`. |
| **2. Discoverable source** | A milestone, a release tag, or a commit/tag range | `gh pr list --repo microsoft/PowerToys --search "milestone:0.X" --state merged --limit 200 --json number,title,labels,files` · or for a range: `git log <tagA>..<tagB> --oneline` then extract `(#NNNNN)` merge refs. |
| **3. Caller defers entirely** | "verify the latest release" with no list | Resolve to a concrete release/milestone first (mode 1/2). If you cannot, **ask** rather than guess. |

### Size gate (the guardrail)

Let `N` = enumerated candidate count, `MAX_AUTO = 25` (hotfix-sized; tune per request).

- **`N ≤ MAX_AUTO`** → proceed: derive + verify each PR (this is the single-PR and hotfix case).
- **`N > MAX_AUTO`** → **STOP. Do not blind-loop.** Present the candidate list grouped by
  module/area with counts, and require the caller to **scope** before deep-verifying: by module, by
  label (e.g. `Needs-Verification`, priority), or an explicit subset. Confirm, then verify the scoped
  set. **Depth beats throughput** — deeply verifying 20 PRs and leaving a clear queue of the rest
  beats 100 shallow "source-verified" reports.

### Select validation by the change, not the label

Identify changes with no relevant interactive surface.
List those as exempt from UI driving, not as verified or exempt from all validation; state which
build, unit, functional or CLI checks apply and what was actually performed. PRs requiring deep
runtime validation still count against the batch-size gate even when their checks do not use UI.

Do not automatically exclude dependency, localization or installer changes: they can affect runtime
loading, rendered text/layout or registration. Use the description, diff and affected behavior to
choose the relevant evidence. UI claims still require the actual user route and its observation.

---

## Step 1 — Per PR: derive the checklist

For each PR in the (possibly scoped) set:

```powershell
gh pr view  <N> --repo microsoft/PowerToys --json title,body,files,labels,state,mergedAt,headRefOid,baseRefOid,mergeCommit
gh pr diff  <N> --repo microsoft/PowerToys      # read the diff — it tells you what actually changed
```

Derive concrete checks for the PR's observable claims and directly affected regression risks.
There is no fixed item count and no automatic full-module checklist expansion. Identify each
precondition, action, expected outcome and observer; reuse relevant existing tests when they
exercise that boundary. Drive interactive checks with the `SKILL.md` §2 bucket selector and
classify with §3. Identify the affected `.csproj`/`.vcxproj` files and required dependencies for
Step 2b. If the description, diff and relevant source still do not define a verifiable claim,
record **FAIL (cause=checklist)** with the ambiguity rather than inventing the expectation.

You may `grep`/`view` a **read-only** local clone/worktree for source context (XAML AutomationIds,
the `.cs`/`.cpp` the PR touched). On the **installed path** you must not run that code against the
install; on the **build + sideload path**, building it is exactly the point (Step 2b).

### Use existing knowledge, then discover the current UI

Use the module profile and existing tests for entry paths, preservation needs and likely controls,
not as an answer key for a new revision. After recording and preservation are established, inspect
the actual target's scoped UIA tree, supported patterns and state. Reconcile changed controls with
the tested revision's XAML/handlers; distinguish structural readiness from the expected outcome.

A missing old locator is an observation problem to investigate, not an automatic product FAIL.
Record the resolved target and actual action, then independently read back the result. Use pixels
for rendered claims that UIA cannot establish. Retain unexpected findings without silently changing
the frozen checklist or treating unrelated discovery as completed PR coverage.

Missing/stale profile knowledge does not require authoring a complete profile before continuing.
Keep discoveries and run-local adapters with this run's evidence; do not automatically edit the
profile, promote helpers or create permanent regression tests during verification. Those are
separate maintenance tasks requiring explicit scope.

### Evidence for the claimed behavior

Exercise the claimed user action and independently observe its outcome; source inspection,
command success and extra discovery calls do not substitute for that evidence. Use the existing
recorder for UI actions, native/CLI probes and observations. There is no minimum winapp-command
count: four discovery calls do not prove a behavior, and a valid composed helper need not be split
into artificial steps.

For `UserVisible=true` items, retain Normal-path `Screenshot` or `Video` evidence as required by
the [reporting contract](../reporting-format.md). A reviewed recording can satisfy this requirement
without an additional screenshot. Read [PR visual evidence](../visual-evidence.md) for media
registration, frame-bundle paths, timing and separate private/redacted-delivery integrity.
Readback proves the requested property; pixels prove rendered content, not input delivery or
persistence. A UI path left unexecuted is not validated merely because its source was reviewed.

---

## Step 2 — Get the bits under test

Follow **2a or 2b** per the bits sub-decision above.

### 2a — Installed path (code already in the build under test)

Nothing to deploy: the shipped runner/modules are already installed. Confirm the module is present
(`../pre-flight.md`), then drive the **installed** bits read-only. This is the path for a merged PR
that has shipped, and for a release/hotfix sign-off where you're validating the released artifact.

### 2b — Build + sideload path (code not in the build under test)

Build the minimum coherent local set: **runner + Settings + related module(s) + required
dependencies**, using the existing essentials/targeted-build scripts below. Do not build the whole
solution merely to populate unrelated modules. This route applies automatically when the PR is
unmerged or the preinstalled artifact does not have confirmed coverage of its changes.

Do not run `gh pr checkout` in the user's working directory before creating a worktree.
`New-WorktreeFromBranch.ps1` reuses a worktree already bound to that branch; it does not guarantee
a new isolated directory. For an open PR, fetch the reviewed head without switching the caller's
branch, then create a new detached worktree:

```powershell
$repo = '<absolute existing repository path>'
$worktree = '<new absolute worktree path>'
$prNumber = [int]'<PR number>'
$headSha = '<reviewed headRefOid from Step 1>'
if (-not [IO.Path]::IsPathFullyQualified($repo) -or
    -not [IO.Path]::IsPathFullyQualified($worktree) -or
    (Test-Path -LiteralPath $worktree) -or $headSha -notmatch '^[0-9a-fA-F]{40}$') {
    throw 'Supply an existing repository, a new absolute worktree path and the reviewed commit.'
}
git -C $repo fetch https://github.com/microsoft/PowerToys.git "pull/$prNumber/head"
if ($LASTEXITCODE -ne 0) { throw 'PR fetch failed.' }
$fetchedSha = git -C $repo rev-parse FETCH_HEAD
if ($LASTEXITCODE -ne 0 -or $fetchedSha -cne $headSha) { throw 'PR head changed; review the new revision first.' }
git -C $repo worktree add --detach $worktree $headSha
if ($LASTEXITCODE -ne 0) { throw 'Worktree creation failed.' }
git -C $worktree submodule update --init --recursive
if ($LASTEXITCODE -ne 0) { throw 'Submodule initialization failed.' }
```

For a merged-but-unreleased PR, resolve and review the intended merge revision instead of assuming
the PR head is the integrated result; create the same kind of detached worktree at that revision.

**Before building**, inspect restore/build/post-build targets for registration, packaging or install
side effects. A worktree isolates source, not the user's configuration or COM/MSIX registration.
For example, `ImageResizerExt.vcxproj` enables `RegisterOutput`. Preserve affected state and use a
supported no-registration build option or an explicitly authorized fixture before running such targets.
If that boundary is not established, block the affected build rather than discover the effect afterward.

Use the same explicit platform/configuration for essentials, the affected project and its dependencies.
After reviewing the build side effects, run in one terminal:

```powershell
$platform = 'x64' # Select the intended supported architecture.
$configuration = 'Release'
$projectDirectory = Join-Path $worktree '<affected project directory>'
$projectFile = Join-Path $projectDirectory '<actual project filename.csproj or .vcxproj>'
if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) { throw 'Affected project was not resolved.' }
Set-Location -LiteralPath $projectDirectory
& "$worktree\tools\build\build-essentials.cmd" -Platform $platform -Configuration $configuration
if ($LASTEXITCODE -ne 0) { throw 'Essentials build failed; read its errors log.' }
& "$worktree\tools\build\build.ps1" -Path $projectDirectory -Platform $platform -Configuration $configuration
if ($LASTEXITCODE -ne 0) { throw 'Affected-project build failed; read its errors log.' }
```

Non-zero means failure: read `build.<config>.<platform>.errors.log` next to the project. Exit zero
alone does not prove that the intended project was built: the wrapper also returns zero when no
project is found. Check the actual build targets/logs and expected outputs for this revision,
configuration and architecture before launch; do not adopt stale output from an earlier build.
If the required toolchain or outputs are unavailable, record **BLOCKED (`BLK-ENV`)**, not PASS.

**Deploy only through a declared, restorable instance transition:**

- **Unpackaged module:** identify the current Runner and affected companions, preserve their original
  paths/session/token and state, and close them through their normal user-facing lifecycle. Launch
  only the explicitly selected build-output instance, then identify the actual target module/host.
  Do not force-kill name-matched processes, select the first PID, or reuse an installed singleton
  as proof that the built module ran. `Restart-PtRunner` preserves the original executable path;
  it is not an installed-to-build switch API. A build switch needs its own declared launch/restore
  actions and observations; without those, stop before closing the original instance.
- **Packaged module:** do not remove the shipped package or change Developer Mode as generic setup.
  Registration/replacement requires a separately authorized fixture, exact package identity,
  retained reinstall material and a verified data/registration rollback. A manifest path may not
  survive uninstall. If this preparation is unavailable, block that deployment rather than assume
  that re-registering the former path will recover the installed app and its data.
- **Shell extension/shared host:** a build-output Runner does not select the DLL already registered
  or loaded by Explorer or another host. Establish the exact registration/loading and restoration
  boundary on this machine before changing it, then identify the component that actually handled
  the action. If that cannot be done safely, retain the build evidence and block only the dependent
  live checks; do not create a VM or infer that the installed handler exercised the PR.

Missing unrelated module dialogs can occur with a partial build. Record and identify each dialog
and its origin before any explicitly scoped dismissal. Missing target dependencies/resources are
not expected success, and neither blind dialog-closing nor a full-solution build is a default remedy.
Never overlay a partial build onto the installed layout.

**Prove it's your bits** before driving: correlate the actual Runner, Settings, module/provider
or loaded DLL/package used by the claim with the recorded outputs. Use exact paths and available
hashes/package identities, process generation and readiness; a development version string or the
Runner path alone is insufficient. Report an identity limitation instead of crediting a possibly
installed singleton/handler as the PR build.

### Baseline comparison is not an execution gate

For a fix, use a relevant baseline and matched inputs when practical. Keep its tested revision,
conditions and observations distinct from the PR-target evidence; a much older installed build
is not automatically a controlled base comparison. Do not revert the user's checkout to make one.

If the baseline does not reproduce the bug, record the attempted conditions and **continue the
target flow**. Difficult reproduction is not a reason to block later safe checks, require another
baseline build, or keep retrying indefinitely. Baseline reproduction is not a mandatory scored
assertion or a prerequisite for the PR run by default. This does not waive cleanup/readiness
after a baseline attempt.

Judge target checks from their actual evidence and state the comparison limitation in the report.
Do not claim a demonstrated before/after fix without that contrast; if a target check itself needs
an unavailable trigger, leave that condition unverified while continuing independent checks.

---

## Step 3 — Drive + classify

Same engine as everything else: per item pick the `SKILL.md` §2 bucket, drive, classify with
`SKILL.md` §3. The claim-specific evidence requirements in Step 1 apply.

## Step 4 — Artifacts, report, restore

**Artifacts + report.** One folder per PR: `{Module}-PR{Number}/` (e.g. `CmdPal-PR48689/`,
`AdvancedPaste-PR45242/`). Use the existing recorder/exporter and
[reporting format](../reporting-format.md): compact `report.md`, exhaustive `details.md` and the
structured evidence archive. Record actual UI, CLI and probe commands in the shared command column;
do not reconstruct a separate `winapp invoke` column or invent extra UI calls.
The header carries the `BITS:` line (incl. the sha/branch + proof-of-your-bits path on the
build path) and, on 2b, a build summary identifying the project, platform/configuration, result
and inspected outputs. Archive through the shared final wrap-up rather than overwriting an older PR run.
Use the [minimal Scenario B composition](../recording-workflow.md#minimal-scenario-b-composition)
with PR-derived items, not the module's full Scenario A inventory. Include baseline non-reproduction
as a scoped limitation, not a blanket hold on unrelated target results or on producing the report.

**Roll-up** (multi-PR sets): top-level summary table — PR · Module · verdict · one-line evidence —
plus the `exempt` list and (if `N > MAX_AUTO`) the un-scoped **queue** of PRs not yet verified.
Include a §G retrospective (run friction).

**Restore (Step 4b / build path only).** Normally close the exact owned build instances and wait for
their writers/providers to finish. Restore only attributed changes against the original baseline,
including any authorized registration/package changes. If an installed instance was originally
running, restore it using its captured launch target, session/token and declared logical UI state;
do not guess a per-user install path or start a previously absent Runner as cleanup.

Verify the original selected files, relevant cached/runtime state, owned-instance absence and
original installation readiness. Restarting the installed executable alone is not restoration.
Keep replacement process identities and unresolved state explicit in the report. The shared
same-installation restart/Settings adapters must not be used to claim a cross-build transition
they do not support.

---

## Worked references

These are historical execution examples, not current deployment or recovery recipes.

- **Single unmerged/unreleased PR, build + sideload:** PR #45242 (Advanced Paste "Show AI paste
  section") — derived 3 claims from the diff, built only the AdvancedPaste project, sideloaded the
  dev `v0.0.1` runner (dismissed the partial-build dialogs), drove Settings + the AP window + a GPO
  gate, then restored the shipped build. 3/3 PASS.
- **Release/hotfix set, installed bits:** the 0.100.1 14-PR sign-off (8 PASS / 6 BLOCKED) — derived
  each PR's checklist from its release-notes line + diff, drove the installed bits, and blocked the
  hardware/visual-only items (DDC/CI, dual-GPU, audio, capture-excluded overlays) with named reasons.
