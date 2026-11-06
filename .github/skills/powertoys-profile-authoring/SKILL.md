---
name: powertoys-profile-authoring
description: "Create or refine PowerToys module verification checklists, profiles, helpers and visual references. Use when asked to author a module profile, expand missing coverage, or iterate from test results. Uses the published verification WIP and learns from repository UI tests where available. The current agent performs bounded R0 discovery, material revisions and full-inventory R1 sequentially, then exits. Independent Runner sessions are opt-in, never a default prerequisite. Retains input provenance, evidence, restoration and approved repair limits. R2 requires explicit authorization; no automatic R3. Makes scoped local commits. Profile authoring is not full-module signoff. Uses powertoys-verification, not a new orchestration framework."
license: Complete terms in LICENSE.txt
---

# Author a PowerToys verification profile

Use **the current agent** to prepare materials, execute R0, improve the profile and execute full R1 sequentially.
"Author" and "executor" are roles of that same agent, not separate processes. Do not launch a Runner subagent,
standalone CLI session, coordinator or two-turn identity handshake by default. Keep one live driver per desktop.
Use an independent Runner only when the user explicitly requests independent verification; label ordinary R1
as same-agent confirmation, not evidence of fresh-session reproducibility.

This skill defines the authoring workflow. `powertoys-verification` in the selected candidate worktree
remains the execution engine: controls, classification, evidence, restoration and per-run archive.
The directory hosting this authoring skill may be older; its sibling verification skill is not the
execution baseline. Resolve that baseline in Step 0, not from the Author's current working directory.
Do not create an orchestration framework merely to follow this workflow.

## When to use

- Create verification coverage for a module without a dedicated checklist/profile.
- Turn a release baseline and relevant merged PRs into reusable module knowledge.
- Improve a profile/helper using actual execution failures, then confirm the changed candidate.
- Produce or refine visual-reference candidates from recorded core user flows.

For a one-off module/PR verification with already-mature materials, use the verification engine directly.
This workflow produces reusable capabilities; it does not automatically fix product bugs, approve a release,
publish changes, or migrate product UI-test projects.

**If asked only to write/review this workflow, do not execute its tests, commits or loop.**
When the user asks to execute authoring, the scoped local checkpoints below are part of that workflow unless
the user says no commits. Push, PR creation, publishing media and CI require separate authorization.

### First-run authorization

An explicit request to execute this authoring workflow includes **bounded R0 discovery and full-inventory R1**:
verify inputs, perform the selected module's ordinary reversible UI checks and scoped captures in the current
agent, restore owned state and archive results. Do not request another routine agent/desktop
approval or CLI permission arguments merely to begin. Respect a user-requested narrower task, but label it
partial/scoped authoring rather than completion of the full workflow or R1.

The current agent works within the task scope and its effective runtime policy. This does not
override real tool/path denials, grant elevation, authorize installation/destructive operations, or imply
`--allow-all`. Surface an actual runtime approval request when necessary, with the operation and reason.
Unavailable conditional cases do not stop independent eligible coverage.

An unset final acceptance policy does **not** block R0. Use the approved
[diagnostic and repair limits](references/stopping-policy.md#diagnostic-and-repair-limits), existing runtime
limits and explicit task overrides; do not require a new budget questionnaire or assume unlimited continuation.

For rapid coverage expansion, R0 samples the distinct core input, observation and restoration mechanisms,
not just module launch. Retain the complete inventory and identify unexecuted conditions. After Author repairs,
R1 must address every item, assertion and required matrix condition and actually execute all safely available
conditions; it is not another sample. Restore, archive and exit after R1 by default, even with unresolved findings.
R2 requires explicit authorization and a fixed repair/regression scope; it ends without automatically starting R3.
Use the [round completion contract](references/stopping-policy.md#required-round-coverage). Full assessment,
actual execution, profile acceptance and product sign-off remain separate; no PASS/non-BLOCKED quota is implied.

## Required reads

1. Repository `AGENTS.md` and applicable instructions in the chosen worktree.
2. [Execution contract](references/runner-contract.md): single-agent execution, exact inputs and optional independent verification.
3. [Checklist format](references/checklist-format.md): Workspaces-style functional cases, concise fixture
   conventions and separate detailed assertion definitions. Read before checklist generation and each revision.
4. [Module profile format](references/module-profile-format.md): the normative section order, exact table
   schemas, content boundaries and Author review gate. Read before profile generation and each revision.
5. After Step 0, read the candidate's `powertoys-verification\references\scenarios\index.md`,
   matching scenario, `references\modules\README.md` and `references\assertion-inventories\README.md`.
   Resolve all these under the candidate worktree, not the directory hosting this authoring skill.
6. [Visual references](references/visual-references.md) before recording or promoting screenshots.
7. [Round completion and stopping conditions](references/stopping-policy.md): required R0/R1 scope and
   optional acceptance/further-iteration policy.
8. [Claims and verdicts](references/claims-and-verdicts.md) before finalizing the checklist or reviewing results.
9. [Execution readiness](references/execution-readiness.md), including
   [UI-test discovery and conditional reuse](references/execution-readiness.md#learn-from-existing-ui-tests) before designing
   recipes/helpers; revisit before execution and when repairing a run's blockers.

The verification skill cached in the current chat is **not evidence** of the candidate's actual version.
Read the selected worktree files and record the sources actually used.
Record this authoring skill's path/revision/hash separately from the candidate's execution inputs.
If the proposed execution base lacks the current shared loader, recorder or template, correct the base
selection before authoring; do not recreate those capabilities or copy an old verification tree into it.
Keep this skill's format contract and the selected WIP guidance consistent; resolve a real conflict explicitly.

## Inputs and decisions

| Input | Required information (discover/derive unless a user decision changes scope) |
|---|---|
| Module | Exact key/slug; existing profile/checklist/inventory/helper coverage and create-versus-refine decision |
| Baseline | Checklist source, version/date, hash and original item references |
| PR range | Explicit start/end tags or commits; merged PR claims, not unbounded history |
| Product target | Installed artifact or authorized build/sideload; actual version/path/hash and inclusion proof |
| Verification base | Refreshed published verification-WIP remote/ref/full SHA, author branch/worktree |
| Product evidence base | Tested artifact identity plus matching source tag/commit and relevant PR cutoff; independent of the verification base |
| UI-test discovery | Reviewed tests/helpers and reuse limits when available; otherwise searched locations/revision or access limits and the source/live-discovery fallback |
| Checklist format | Loaded checklist-format contract path/hash; functional prose and matching assertion inventory |
| Profile format | Loaded format-contract path/hash and applicability of its conditional sections |
| Execution scope | Round and inventory identity/counts; all IDs and matrix conditions for R1, explicit selections for R0/R2+; environment, authorized state changes and artifacts |
| Visual scope | Core states and scoped capture plan; reference-promotion approval is separate from R0 execution |
| Exit/repair policy | Default exit after R1; per-root repair limits and any explicit user/runtime limits; no default cumulative cap or timed checkpoints; explicit authorization/scope for R2 or later work |
| Regeneration/comparison | From-scratch or reuse; allowed prior materials, fixed baseline/build/helper conditions and fresh Author context where needed |

Ask only about choices that materially change expectations, scope, permissions, visual authority or investment.
Discover ordinary paths/control IDs and prepare finite execution steps yourself. Complete the authorized initial
sequence through full R1 assessment, then return `needs-review`; further work requires explicit authorization.
If a genuine limit prevents it, report the round incomplete with exact remaining work, not a completed R1.
Do not convert silence into an unlimited loop or an invented convergence threshold.

## Workflow

```text
fresh published-verification-WIP author branch
  -> existing-coverage check: create missing material or refine existing material
  -> UI-test discovery: reuse relevant tests if present; otherwise source/live discovery
  -> checklist/inventory + input checkpoint
  -> current agent executes R0 (representative core mechanisms, observations and restoration)
  -> initial evidence-derived profile + local commit
  -> bounded, prioritized improvements + local commit
  -> same agent executes R1 on that commit (full frozen inventory and all matrix conditions)
  -> restore + archive + review -> EXIT by default

only when explicitly authorized:
  fixed repair scope/budget -> bounded repair + commit -> same-agent R2 (targeted regression)
  -> restore + archive + report fixed/unresolved/incomplete -> EXIT (no automatic R3)
```

### 0. Start from the published verification WIP

Inspect status, worktrees and remotes; preserve dirty trees and stashes. The default framework baseline is
the freshly fetched `fork/wip/powertoys-verification-20260819`. Verify which remote owns the published branch;
the remote may have another name. An explicit user-selected verification ref overrides this default.
Do not use `origin/main`, the old profile-authoring branch or whichever feature branch happens to be checked out.

Example shape (substitute inspected remote, module and new paths; check every native exit code):

```powershell
$verificationRemote = 'fork'
$verificationBranch = 'wip/powertoys-verification-20260819'
git fetch --no-tags $verificationRemote $verificationBranch
if ($LASTEXITCODE -ne 0) { throw 'Verification base fetch failed.' }
$base = git rev-parse "$verificationRemote/$verificationBranch"
if ($LASTEXITCODE -ne 0) { throw 'Verification base is unresolved.' }
git worktree add -b "verification/profile-$module-$suffix" $authorWorktree $base
if ($LASTEXITCODE -ne 0) { throw 'Author worktree creation failed.' }
$verificationSkill = Join-Path $authorWorktree '.github\skills\powertoys-verification'
```

Verify that this tree contains the shared inventory loader, recorder, resource/cleanup adapters and
`templates\verification-run.ps1`. Load their actual contracts. Do not stash, clean, reset, overwrite unrelated
changes or silently import helpers from another worktree. The Author may use this authoring skill as a
separately recorded guidance input; execution uses only the candidate's declared engine.

Before creating files, check the module catalog, profile, checklist, assertion inventory, helper scripts,
specialist references and relevant stashed drafts read-only. Distinguish:

| Existing material | Action |
|---|---|
| No module coverage | Create an evidence-derived profile/checklist on the shared baseline |
| Existing profile/checklist/inventory | Refine confirmed gaps; retain stable IDs and useful operating knowledge |
| Stashed or unmerged draft | Treat as a candidate, not accepted coverage; import only with explicit scope and provenance |
| Requested from-scratch comparison | Follow the declared exclusion rules; do not delete/recover excluded material |

Pin the verification base during this module's run. A later update is a new recorded candidate, not an
invisible refresh. A current harness does not imply current product source: inspect the installed UI and its
matching source/PR inputs separately. Source from a newer build cannot define the installed build's behavior.
Keep that provenance in Author/run inputs, not as a required source-path list in reusable fixture instructions.

Before designing module operations or declaring an automation path unsupported, perform bounded
[UI-test discovery](references/execution-readiness.md#learn-from-existing-ui-tests). Not every module has UI tests:
review relevant suites when available; otherwise record the search and continue with source inspection,
shared helpers and bounded live discovery. Existing tests are neither a prerequisite for authoring nor a
replacement for the full checklist or proof of current readiness.

**Output:** verification ref/SHA, author branch/worktree, initial status, create/refine decision and separate
product/UI-test evidence identities and reuse decisions. Start the next module from the then-current
published WIP, not this module's branch.

### 1. Generate the checklist

For refinement, start from the existing committed checklist/inventory and add or correct only supported gaps.
Do not regenerate covered modules from a legacy release baseline or renumber unchanged assertions.
For a new module, extract the supplied **full-release base checklist**, not expectations inferred from
another module's profile. The default location for the supplied 0.96 baseline is:

```text
%OneDrive%\PowerToys\WinappCLI-UIA\tests-checklist-template.md
```

Resolve `%OneDrive%` from `$env:OneDrive`; use an explicit baseline path if the caller supplies one.
This is an external input, not a repository file. If the location is unavailable, ask for the file/path rather
than silently substituting another checklist. Keep the source unchanged and record its resolved path,
declared baseline version, SHA256 and original line references in the run inputs.

**When using that external baseline, extract the requested module's complete section before adding PR coverage:**

1. Locate the module heading and take its complete section, ending at the next heading of the same or higher
   level. Retain the original extract in the Author input records; preserve the requirements in every checkbox,
   nested variant, setup condition and expected outcome.
2. Inspect cross-cutting sections for entries explicitly naming the module, such as its localization checkbox.
   Include those entries and applicable shared prerequisites with their source references; do not copy other
   modules' tests or the entire release checklist into the module inventory.
3. Normalize the extracted requirements and relevant PR-derived assertions into functional cases using
   [the checklist format](references/checklist-format.md). Do not paste a second, verbatim baseline checklist
   into the generated document; source identity and the original wording stay in the input records.

Inventory relevant PRs through the explicit cutoff using descriptions **and diffs**: include direct module
changes and applicable Settings, shared-code and entry-point changes. Separate user-facing claims from
test/build-only changes.

- Check release inclusion, including cherry-picks, superseded/reverted changes and preview tags.
  A milestone, merge date or common major/minor version is not proof that installed bits contain a change.
- Give assertions stable IDs, explicit expectations, prerequisites and observation requirements; retain
  source links in the Author/input mapping or supported inventory provenance, not runtime recipes.
  Mark unresolved expectations for human review rather than deriving truth from the current output.
- Merge obvious shared setup/actions if useful, retaining **every assertion and distinct condition**. Execution
  experience can justify further grouping later. Fewer scenario rows is not reduced coverage or higher quality.
- State actual product/version prerequisites beside the affected cases. Summarize critical fixture/restoration
  requirements in the checklist and link the profile/fixture guide for implementation detail.
- Keep PR dispositions (included, baseline-covered, infrastructure-only, out of range or deferred) in the
  existing Author analysis records, not in the checklist or a newly created source appendix.

Apply [claim normalization](references/claims-and-verdicts.md): preserve original wording/provenance in input records while
mapping clearly equivalent behavior to the target's current controls. Do not leave a caption-only change
permanently ambiguous or duplicate the old requirement and its current equivalent.
Separate core eligible checks from additional conditional matrices without dropping either. Do not turn every
implementation constant or PR validation anecdote into a mandatory test without an applicable acceptance basis.
Report subconditions independently so a missing specialist fixture does not obscure an observed normal path.

Use the engine's checklist location, normally
`.github\skills\powertoys-verification\references\release-checklist\<module>.md`.
The generated document has **Legend -> brief Fixtures & conventions -> functionally grouped cases**,
with concise action/expectation paragraphs and detailed stable children in the supported assertion inventory.
Do not include provenance/applicability essays, a verbatim original baseline, PR disposition or coverage-history
sections. Do not organize it under `Canonical execution inventory`, `Draft validation matrices` or
`Entry points and conditional coverage`; use actual functional categories instead.
Complete the [checklist review gate](references/checklist-format.md#5-author-review-gate) before checkpointing.
Review the initial scope/ambiguous expectations with the user as needed.

Create a **local input checkpoint commit** for the checklist and any approved supporting changes. This extra
checkpoint makes the first no-profile run reproducible; it is not a claim that a profile already exists.
If commits are prohibited, pause to agree an explicit hashed-snapshot alternative to the commit-based input
contract; do not label dirty material with its base commit and pretend it is the tested revision.

**Output:** functional checklist, matching stable assertion inventory and testable input revision;
source/PR mapping retained in the Author/input records.

### 1a. Prepare executable foundations

Where relevant UI tests exist, use their reviewed flows to select fixtures, input sequences, readiness signals
and result observers. Otherwise derive these from target-product inspection and bounded live discovery.
Use the candidate engine's ownership/restoration contracts in either case, not a second test harness.
Build the small [capability map](references/execution-readiness.md) for the round's scope (the full inventory
before R1): affected IDs, actual helper/fixture, state touched, validation receipt and remaining runtime
conditions. This is **Author work, not a new user approval gate**. Inspect and reuse the candidate's common input, UIA, capture, file,
clipboard, Settings-state, lifecycle, resource and report APIs before adding any module helper.
A module helper should compose module-specific operations, not implement parallel generic infrastructure.
If a shared guarantee is genuinely missing, make a minimal change in that shared layer with focused regressions
and explicit affected callers; keep it separate from product fixes and unrelated cleanup.

Prepare predictable data/cleanup/input prerequisites before R0; leave unknown module controls for its discovery.
Non-empty clipboard/history is not automatically untestable. Protect private payloads from model/evidence
exposure while using permitted local programmatic backup/restoration. If preservation or authority is genuinely
unavailable, defer only the dependent conditions and continue independent coverage.

Record actual automation-host/PowerToys-runner/module/foreground-fixture integrity, not merely IsAdmin for
the shell. Normal-user hotkey checks must not accidentally target an elevated fixture. Measure DPI/geometry and use fresh observations.
Do not infer delivery from a successful SendInput call or a previous log line.
Checkpoint any added helper/fixture with focused mechanical checks before using that revision for confirmation.
Validate inventory import, exact counts/IDs, required parameters, links and cleanup contracts before the
bounded real-user-flow check. Missing hardware or blocked observation remains scoped evidence, not proof
that a profile is complete; offline contract tests do not establish live restoration.
Select R0 examples by distinct core input/observer/restoration mechanisms in the existing capability map,
not by the easiest assertions. Before R1, distinguish a mechanically checked helper from a module path
actually exercised and restored; keep remaining gaps explicit without blocking unrelated safe work.

### 2. Execute R0 in the current agent

Follow [the execution contract](references/runner-contract.md). Use the selected committed module worktree,
the candidate's verification engine and the existing recorder's input snapshots. Pause material edits while
driving that candidate. There is no child dispatch, neutral handoff packet or separate approval acknowledgment
in the default workflow. Check actual prerequisites and proceed directly to the permitted finite actions.
Keep the resolved fixture/restoration plan and remaining runtime checks with the run's ordinary inputs.
Use the candidate engine's supported template/case wrappers and reporting helper instead of rebuilding
their lifecycle. Preflight checks must precede any potentially activating preparation; preserve the original
Settings state before navigation. Prefer its non-activating adapter for already-visible UIA-only work.

For a new-profile R0, explicitly declare `profile: absent`. Use the candidate's generic engine to discover
controls and write execution artifacts; do not invent a mature profile before trying the UI.
For refinement/reuse, supply the existing committed profile as an explicit input instead. Do not delete it
merely to fit the new-profile path or describe that run as from-scratch generation.
State the round's coverage mode explicitly. A focused discovery/repair run cannot stand in for full R1;
unavailable conditions remain in the frozen inventory with evidence, not silently filtered from the scope.

Run one live driver per shared desktop. The current agent records
raw actions/observations/errors, per-assertion results, restoration and retrospective; unavailable conditional
coverage does not stop unrelated eligible cases. Scripts failing are not automatically environment/product failures.
Apply [evidence-based verdicts](references/claims-and-verdicts.md): setup/integrity failures cannot establish
a product defect, and unavailable dependent actions do not become additional product failures.

Write finite, recorded run-local driving code when needed. Do not hot-edit the tested checklist/profile/shared
helpers or write product fixes while a candidate is executing. Restore affected state and close its attempts
before revising formal materials; checkpoint and record changed inputs for later execution. The same agent
performs this transition without a role handoff or a reset of repair counters.

**Output:** archived run, actual session/input identities, observations, round completion status,
assessed versus executed coverage, remaining IDs/causes and restoration status.

Do not stop at the input checkpoint with a generic "approval unavailable" claim. If R0 cannot start,
retain the actual denied operation/error or the verified missing runtime capability and identify what is needed;
an absent child-session configuration is not a default prerequisite or evidence of a denial.

### 3. Generate the module profile and make a local commit

The Author reads raw evidence, not only the summary. Build the initial profile from confirmed module facts and
the successful/failed operating paths. Follow the [module profile format](references/module-profile-format.md)
as the output contract; an allowed existing profile is an example, not an alternative schema or a source of
nonexistent helper APIs.

Use the contracted order: **Module facts -> Entry paths -> UI state-transition map ->
Control locator and interaction index -> Troubleshooting -> Fixtures and restoration -> references**.
The format contract defines conditional sections and the accepted metadata/reference presentation variants.
Entry paths is always second; detailed observation guidance stays below the interaction index.

Use the exact schemas for the four operating tables: state transitions (four columns), interactions (four),
troubleshooting (three) and resource inventory (five). Separate typed locators from actions and JSON read-outs;
corroborate How to interact against actual control/handler and available helper contracts. Include local
scope, commit semantics, conditional diagnostics and baseline-relative restoration rather than a test answer key.

Keep expectations in the checklist, not a profile answer key. Use discovery instructions for volatile selectors
instead of archived HWNDs/runtime slugs. Reuse existing helpers; test any new or changed mechanics. Keep the
profile concise by linking detailed shared mechanics and secondary references without dropping required contracts.
Describe known traps conditionally; do not embed prior verdicts as instructions to reproduce a desired answer.
Keep actual run/build validation in the archived run and Author record; a source/format review cannot advance
a live-verification claim.

Follow [the visual-reference workflow](references/visual-references.md) for candidate assets. Recording pixels is
not sufficient to approve those pixels as correct.

Complete the [Author format review gate](references/module-profile-format.md#9-author-review-gate) on the
candidate and retain its receipt with the round records. Fix structural/content violations before calling
the profile conforming. Incomplete discovery material may be checkpointed with its gaps explicitly recorded,
but must not be represented as accepted or ready for confirmation merely because it has the right headings.

Review the staged diff and **local commit** the initial profile and its directly related files.
No raw runs, private settings, clipboard backups, temporary scripts or unreviewed recordings enter that commit.

**Output:** initial profile commit, supported scope and evidence references.
If major core paths were not executable, label this a discovery-stage profile in the authoring record;
the existence of a committed Markdown file is not evidence that its declared scope is ready.

### 4. Improve from the run and make a local commit

Assign each friction to the correct layer:

| Finding | Author action |
|---|---|
| Missing module knowledge / wrong discovery advice | Improve profile |
| Input, identity, waits, state restoration or recording flaw | Improve the relevant helper and add focused regressions |
| Repeated setup/poor execution order | Group/reorder scenarios without dropping assertions |
| Stale/ambiguous expectation or proposed scope reduction | Seek a sourced/human decision; preserve the former expectation |
| Product contradicts a valid claim | Keep the finding; do not weaken tests or modify the product to reach green |
| Missing environment/capability | State affected coverage and required condition; continue independent work |
| Candidate screenshot is wrong/uncertain | Keep as finding/candidate, not accepted visual reference |

Cluster blockers by shared root capability and prioritize safety, trustworthy observations and high-impact
shared/core repairs. Defer isolated low-value edge cases and cosmetic refinements. Apply the
[diagnostic and repair limits](references/stopping-policy.md#diagnostic-and-repair-limits); "repairable" is
not an instruction to keep working indefinitely or to block the rest of R1 on one minor issue.
Use the [change receipt](references/execution-readiness.md#5-bind-improvements-to-the-observed-gap) to connect
the evidence, implementation, checks and intended confirmation IDs. When helpers/fixtures are missing, adding
warnings or stricter evidence gates alone is not completion of this improvement step.

For every change retain: original problem/evidence, chosen layer, diff, affected assertion IDs, confirmation plan
and completed helper checks, including root-cause attempts/time and any explicit task limits.
A static selector replacement or renamed failure category alone is not proof of improvement.
Reapply the checklist/profile format review gates to the corresponding revised materials and update
candidate/contract hashes. Checklist reformatting must preserve assertion semantics and distinct conditions.
Formatting changes alone do not resolve missing execution or restoration capability.
If results worsen, compare actual evidence: the old run may have been falsely passing. Escalate unresolved
contradictions instead of automatically reverting expectations or expanding permissions.

Make a second **local commit** for real improvements. If no separate improvement is justified after initial
profile generation, record that fact and test the initial-profile commit; do not manufacture an empty commit.

**Output:** candidate commit and the full frozen inventory for R1; later rounds may select affected assertions
and neighboring regressions only when authorized. Address known repairable gaps across R1's safely available
conditions within the repair allowance, not only R0's sample. At a limit, retain the gap and continue independent
safe coverage; do not rerun the same broken path just to repeat its failure. Unresolved gaps remain Author
work and prevent a ready/full-completion claim, but do not require an endless repair loop.

### 5. Execute full R1 in the same agent; repeat only as authorized

Keep the current agent and module worktree. Start the R1 execution record against the committed candidate,
using the engine's actual input snapshots and fresh product observations. R0 knowledge may guide operation,
but previous PASS labels and expectations are not evidence of the R1 outcome. Independent verification is
optional and requires an explicit request; absence of a fresh Runner does not make ordinary R1 incomplete.

Before R1, prioritize known infrastructure gaps across the full safely available inventory and check profile
format conformance within the repair allowance. Keep exhausted gaps explicit and continue safe independent
cases; if none can run safely, stop with R1 incomplete. Do not repeatedly execute unchanged broken paths.
This profile gate does not apply to profile-absent R0. No routine human "approve R1" prompt is needed.
Before R2, require an explicit authorized repair list, regression selection and allowance, then perform one
targeted confirmation on the committed candidate. Do not add unrelated fixes or retry the round until green.

R1 covers the entire frozen checklist/inventory, including every required condition inside an assertion.
Execute independent safely available conditions even when another condition fails or is blocked. Apply the
[R1 completion gate](references/stopping-policy.md#r1-completion-gate), not merely a count of assigned verdicts.
Only explicitly authorized later rounds use affected assertions plus neighboring regressions. A focused repair
does not retroactively complete unfinished R1. Full final-revision confirmation, if needed for full-scope
acceptance, is separately authorized work, not an automatic next round or a union of unrelated old runs.
A test-local correction retains both attempts; changing formal materials starts a new candidate/run.

After each run:

1. Verify session, material/build identity, source integrity, coverage and restoration.
2. Compare observations and explanations, not just PASS counts; review the tested snapshots and distinct
   subconditions, not later-edited profiles or different coverage denominators.
3. Check required round completion separately from the chosen [acceptance/further-iteration policy](references/stopping-policy.md).
4. Proceed from completed R0 through revisions to the authorized R1. Restore/archive and exit after R1 or
   an authorized R2; do not start an extra round without explicit authorization.

The [finite exit policy](references/stopping-policy.md#finite-exit-policy) governs R1 and authorized R2:
PASS is not an exit prerequisite. Return confirmed repairs, unresolved findings, actual coverage and restoration.
Report incomplete work honestly rather than continuing automatically or weakening the completion gate.

## Local commit and delivery discipline

Stage explicit paths and inspect the index; never `git add .` across a shared/dirty tree. Commit only the module
checklist/profile, justified helpers/tests, indexes and approved sanitized visual assets. Follow repository title,
license and session-trailer rules. Do not amend or publish without authorization.

Do not copy an old skill tree, raw report workspace or product-source refresh into a module-authoring commit.
When integration/push is authorized, review the module-only diff and necessary shared changes against the
current published verification WIP, resolve catalog/schema conflicts using its current contracts, and verify
the resulting content and relevant regressions. Publish only the intended changes, not unrelated local-only
history. Keep historical reports immutable and state unresolved live coverage. The next module starts only
from the newly fetched published baseline; a permanently reused authoring branch is not the source of truth.

Deliver:

- Base/branch and checkpoint commits; actual execution session IDs, mode and material/build identities.
- Checklist/profile/helper paths and what the latest run actually supports.
- Checklist/profile format-contract identities and review receipts, separate from execution readiness.
- Immutable report locations, per-assertion gaps and separate product findings.
- Round coverage/completion, actual execution counts, unprocessed conditions and blocker causes; never just verdict totals.
- Repair attempts/time, exhausted allowances and prioritized remaining work; no automatic continuation.
- Visual candidates/accepted references with provenance and approval state.
- Current workflow status and the selected stopping rule, or the unresolved decision.

Distinguish `accepted-profile-scope`, `needs-review`, `blocked` and `stopped-by-budget`.
None of these automatically means product/release sign-off. Preserve each run archive; do not rewrite history
to make the latest profile appear better.

For an intentional regeneration comparison, follow
[the comparison input rules](references/claims-and-verdicts.md#regenerating-a-profile-for-comparison).
Deleting one profile does not reset its surrounding context. Do not remove existing profiles in response to
a request merely to improve this skill, and do not quietly reconstruct excluded module recipes from history.
