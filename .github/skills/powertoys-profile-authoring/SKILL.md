---
name: powertoys-profile-authoring
description: "Create or refine PowerToys module verification checklists, profiles, helpers and visual references. Use when asked to author a new module profile, bootstrap coverage, or iterate from test results. Enforces Workspaces-style functional checklists and aligned module-profile section/table contracts. Starts a branch/worktree from upstream main; normalizes baseline and merged-PR claims; prepares safe fixtures and restoration helpers; fixes shared execution blockers; tests committed candidates in fresh Runner sessions without Author context; makes scoped local commits. Supports evidence-based verdicts and uncontaminated regeneration comparisons. Uses powertoys-verification, not a new multi-agent framework."
license: Complete terms in LICENSE.txt
---

# Author a PowerToys verification profile

Use **one Author** to prepare, inspect results and improve materials sequentially. For each execution, start a
**fresh Runner session** with a neutral brief and an exact committed input revision. Do not require a permanent
Engineer/Runner/Reviewer team or parallel agents on a shared desktop.

This skill defines the authoring workflow. [powertoys-verification](../powertoys-verification/SKILL.md) remains
the execution engine: controls, classification, evidence, restoration and per-run archive. Do not create an
orchestration framework merely to follow this workflow.

## When to use

- Create verification coverage for a module without a dedicated checklist/profile.
- Turn a release baseline and relevant merged PRs into reusable module knowledge.
- Improve a profile/helper using actual execution failures, then confirm with a fresh Runner.
- Produce or refine visual-reference candidates from recorded core user flows.

For a one-off module/PR verification with already-mature materials, use the verification engine directly.
This workflow produces reusable capabilities; it does not automatically fix product bugs, approve a release,
publish changes, or migrate product UI-test projects.

**If asked only to write/review this workflow, do not execute its tests, commits or loop.**
When the user asks to execute authoring, the scoped local checkpoints below are part of that workflow unless
the user says no commits. Push, PR creation, publishing media and CI require separate authorization.

### First-run authorization

An explicit request to execute this authoring workflow authorizes **R0 without another workflow approval**:
launch a fresh Runner, verify its inputs, perform the selected module's ordinary reversible UI checks and
scoped captures, restore owned state and archive results. Respect any narrower scope the user specified.
Do not ask the user to approve the Runner/desktop again or supply CLI permission arguments merely to begin R0.

The Author prepares launch configuration from the task scope and effective runtime policy. This does not
override real tool/path denials, grant elevation, authorize installation/destructive operations, or imply
`--allow-all`. Surface an actual runtime approval request when necessary, with the operation and reason.
Unavailable conditional cases do not stop independent eligible coverage.

An unset convergence policy or absent new budget number does **not** block R0. Use existing runtime limits and
explicit user ceilings; do not invent a new budget questionnaire or an unlimited continuation policy.

## Required reads

1. Repository `AGENTS.md` and applicable instructions in the chosen worktree.
2. [Runner session contract](references/runner-contract.md): context isolation, exact skill selection and handoff.
3. [Checklist format](references/checklist-format.md): Workspaces-style functional cases, concise fixture
   conventions and separate detailed assertion definitions. Read before checklist generation and each revision.
4. [Module profile format](references/module-profile-format.md): the normative section order, exact table
   schemas, content boundaries and Author review gate. Read before profile generation and each revision.
5. The chosen revision's verification [router](../powertoys-verification/references/scenarios/index.md),
   matching scenario and [module catalog/guidance](../powertoys-verification/references/modules/README.md).
6. [Visual references](references/visual-references.md) before recording or promoting screenshots.
7. [Stopping-policy brainstorm](references/stopping-policy.md) before authorizing repeated iterations.
8. [Claims and verdicts](references/claims-and-verdicts.md) before finalizing the checklist or reviewing results.
9. [Execution readiness](references/execution-readiness.md) before dispatch and when repairing a run's blockers.

The verification skill loaded from the current chat is **not evidence** that a later Runner loads the same
version. Read and attest the actual Runner worktree files.
An older base may still contain a two-column/Observe recipe template or `BLOCKED traps` heading.
Use this skill's format contract for authoring rather than adopting that legacy schema; record its path/hash
as an Author input. This does not authorize importing the originating worktree's helpers or changing the
candidate execution engine's verdict vocabulary.

## Inputs and decisions

| Input | Required information (discover/derive unless a user decision changes scope) |
|---|---|
| Module | Exact module key and filename slug; check for existing materials |
| Baseline | Checklist source, version/date, hash and original item references |
| PR range | Explicit start/end tags or commits; merged PR claims, not unbounded history |
| Product target | Installed artifact or authorized build/sideload; actual version/path/hash and inclusion proof |
| Development base | Upstream remote's refreshed main SHA, author branch/worktree |
| Checklist format | Loaded checklist-format contract path/hash; functional prose and matching assertion inventory |
| Profile format | Loaded format-contract path/hash and applicability of its conditional sections |
| Runner scope | Assertion IDs, environment, task-authorized fixture/state changes and artifact location |
| Visual scope | Core states and scoped capture plan; reference-promotion approval is separate from R0 execution |
| Loop policy | Authorized work/budget and selected acceptance/stop rule; **unset unless chosen** |
| Regeneration/comparison | From-scratch or reuse; allowed prior materials, fixed baseline/build/helper conditions and fresh Author context where needed |

Ask only about choices that materially change expectations, scope, permissions, visual authority or investment.
Discover ordinary paths/control IDs and prepare Runner configuration yourself. If the stopping policy is unset,
do the authorized initial sequence, including R0, before returning `needs-review` for further iteration.
Do not convert silence into an unlimited loop or an invented convergence threshold.

## Workflow

```text
fresh main-based author branch
  -> checklist + input checkpoint
  -> fresh Runner R0 (generic engine; no module profile required)
  -> initial evidence-derived profile + local commit
  -> evidence-driven improvements + local commit
  -> fresh Runner R1 on that commit
  -> Author review -> improve/commit -> fresh Runner R2 ...
                      or human decision / accepted scope / explicit stop
```

### 0. Start from main, not the current WIP branch

Inspect current status/worktrees and identify the intended upstream remote. Preserve existing dirty trees.
Fetch **main** without updating unrelated refs, record its full SHA, and create a new named author branch in a
new worktree. Do not branch from a possibly stale local main or from the current feature branch.

Example shape (substitute inspected paths/remote/module; check names do not already exist):

```powershell
git fetch --no-tags origin main
$base = git rev-parse origin/main
git worktree add -b "verification/profile-$module-$suffix" $authorWorktree $base
```

Do not stash, clean, reset, move unrelated changes, import another branch's harness, or silently cherry-pick.
Reuse the helpers actually present at this base. If a needed capability is absent, author/test a small scoped
helper or report the gap; proposed/imported changes need explicit provenance and review.

Pin this base for the experiment. Updating main midway changes the comparison and requires a recorded new base,
not an invisible refresh of a stability streak. Product build identity is a separate version axis.

**Output:** base SHA, author branch/worktree and initial clean status.

### 1. Generate the checklist

Start from the supplied **full-release base checklist**, not from a previously generated module profile.
The default location for the supplied 0.96 baseline is:

```text
%OneDrive%\PowerToys\WinappCLI-UIA\tests-checklist-template.md
```

Resolve `%OneDrive%` from `$env:OneDrive`; use an explicit baseline path if the caller supplies one.
This is an external input, not a repository file. If the location is unavailable, ask for the file/path rather
than silently substituting another checklist. Keep the source unchanged and record its resolved path,
declared baseline version, SHA256 and original line references in the run inputs.

**Extract the requested module's checklist from that file before adding PR coverage:**

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
  source links in the Author/input mapping, with short per-case references only when useful.
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
If commits are prohibited, pause to agree an explicit hashed-snapshot alternative to the commit-based Runner
contract; do not label dirty material with its base commit and pretend it is the tested revision.

**Output:** functional checklist, matching stable assertion inventory and testable input revision;
source/PR mapping retained in the Author/input records.

### 1a. Prepare executable foundations

Build the small [capability map](references/execution-readiness.md) for the selected scope: affected IDs,
actual helper/fixture, state touched, validation receipt and remaining runtime conditions. This is **Author
work, not a new user approval gate**. Reuse what main really provides; implement/test a minimal missing
mechanism within the authorized scope instead of forwarding a repeated "needs ownership" instruction.

Prepare predictable data/cleanup/input prerequisites before R0; leave unknown module controls for its discovery.
Non-empty clipboard/history is not automatically untestable. Protect private payloads from model/evidence
exposure while using permitted local programmatic backup/restoration. If preservation or authority is genuinely
unavailable, defer only the dependent conditions and continue independent coverage.

Record actual host/Runner/module/foreground-fixture integrity, not merely IsAdmin for the shell. Normal-user
hotkey checks must not accidentally target an elevated fixture. Measure DPI/geometry and use fresh observations.
Do not infer delivery from a successful SendInput call or a previous log line.
Checkpoint any added helper/fixture with focused mechanical checks before giving its revision to the Runner.

### 2. Run the checklist in a fresh session

Follow [the Runner contract](references/runner-contract.md). Use the clean, committed author worktree while
the Author pauses all edits; a separate detached execution worktree is optional. Start a new session at the
exact candidate commit, not a fork/resume of the Author or a previous round's Runner.

Provide only the neutral task packet: scope, expected behaviors from the checklist, exact engine/material paths
and hashes, product identity, permissions and artifact destinations. Do not provide the Author's reasoning,
desired verdicts, previous PASS labels, troubleshooting transcript or private notes.
Include the resolved fixture/restoration plan and remaining runtime checks from the capability map, not a
promise that the Runner can somehow establish them without an implementation.

For a new-profile R0, explicitly declare `profile: absent`. The Runner uses the candidate's generic engine,
discovers controls and writes execution artifacts; it must not invent a mature profile before trying the UI.
For refinement/reuse, supply the existing committed profile as an explicit input instead. Do not delete it
merely to fit the new-profile path or describe that run as from-scratch generation.

Use an identity-only first turn. The Author **automatically** verifies its handshake and sends execution
authorization in that same new Runner session; this is an input-consistency check, not a human approval gate.
The acknowledgment contains no troubleshooting/coaching. Run one live driver per shared desktop. The Runner records
raw actions/observations/errors, per-assertion results, restoration and retrospective; unavailable conditional
coverage does not stop unrelated eligible cases. Scripts failing are not automatically environment/product failures.
Apply [evidence-based verdicts](references/claims-and-verdicts.md): setup/integrity failures cannot establish
a product defect, and unavailable dependent actions do not become additional product failures.

The Runner may write recorded, run-local driving code. It may not hot-edit the tested checklist/profile/shared
helpers, write product fixes, commit changes or launch another authoring loop. This task-level split overrides
the execution skill's normal instruction to update profiles after a run: return discoveries/gaps to the Author.

**Output:** archived run, actual session/input identities, observations, coverage and restoration status.

Do not stop at the input checkpoint with a generic "Runner approval unavailable" claim. If R0 cannot start,
retain the actual denied operation/error or the verified missing runtime capability and identify what is needed;
an unfilled permission-template variable is configuration work for the Author, not evidence of a denial.

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

Cluster blockers by shared root capability and address the high-impact, repairable ones first.
Use the [change receipt](references/execution-readiness.md#5-bind-improvements-to-the-observed-gap) to connect
the evidence, implementation, checks and intended confirmation IDs. When helpers/fixtures are missing, adding
warnings or stricter evidence gates alone is not completion of this improvement step.

For every change retain: original problem/evidence, chosen layer, diff, affected assertion IDs, confirmation plan
and completed helper checks. A static selector replacement or renamed failure category alone is not proof of improvement.
Reapply the checklist/profile format review gates to the corresponding revised materials and update
candidate/contract hashes. Checklist reformatting must preserve assertion semantics and distinct conditions.
Formatting changes alone do not resolve missing execution or restoration capability.
If results worsen, compare actual evidence: the old run may have been falsely passing. Escalate unresolved
contradictions instead of automatically reverting expectations or expanding permissions.

Make a second **local commit** for real improvements. If no separate improvement is justified after initial
profile generation, record that fact and test the initial-profile commit; do not manufacture an empty commit.

**Output:** candidate commit and a bounded confirmation selection, with baseline coverage still accounted for.
Known external conditions or real decisions may remain deferred, but known repairable core gaps stay Author
work. If a diagnostic rerun is needed before a repair, label it diagnosis rather than profile confirmation.

### 5. Start another fresh Runner on the candidate; repeat only as authorized

Start a new Runner session at the next committed candidate and repeat the full identity handshake.
The same clean worktree can be reused after the preceding run ends; the new Runner gets the new materials,
not the Author's explanation of why they should now pass.

Before calling this a confirmation, ensure its selected core paths have concrete mechanics and relevant
validation, and its profile has a conforming format-review receipt; do not dispatch unchanged infrastructure
merely to reproduce the same BLOCKED inventory. This profile gate does not apply to profile-absent R0.
If not ready, continue the scoped Author repair or report a genuine limit. Do not add a human "approve R1"
prompt as a substitute for doing that work.

Select affected assertions plus justified neighboring regressions for fast iteration. Before accepting the
complete declared scope, obtain a fresh-session confirmation of that scope on the final revision, not a union
of unrelated old runs. A test-local correction retains both attempts; changing formal materials starts a new
candidate/confirmation run.

After each run:

1. Verify session, material/build identity, source integrity, coverage and restoration.
2. Compare observations and explanations, not just PASS counts; review the tested snapshots and distinct
   subconditions, not later-edited profiles or different coverage denominators.
3. Apply the explicitly chosen [stop/acceptance policy](references/stopping-policy.md).
4. Either improve/commit and start a fresh Runner, ask for a concrete human decision, or stop with a truthful status.

If no convergence policy is selected, finish the authorized initial generation/improvement/confirmation sequence
and return `needs-review` before starting further open-ended rounds. This pause is **not** profile acceptance.

## Local commit and delivery discipline

Stage explicit paths and inspect the index; never `git add .` across a shared/dirty tree. Commit only the module
checklist/profile, justified helpers/tests, indexes and approved sanitized visual assets. Follow repository title,
license and session-trailer rules. Do not amend or publish without authorization.

Deliver:

- Base/branch and checkpoint commits; actual Runner session IDs and material/build identities.
- Checklist/profile/helper paths and what the latest fresh run actually supports.
- Checklist/profile format-contract identities and review receipts, separate from execution readiness.
- Immutable report locations, per-assertion gaps and separate product findings.
- Visual candidates/accepted references with provenance and approval state.
- Current workflow status and the selected stopping rule, or the unresolved decision.

Distinguish `accepted-profile-scope`, `needs-review`, `blocked` and `stopped-by-budget`.
None of these automatically means product/release sign-off. Preserve each run archive; do not rewrite history
to make the latest profile appear better.

For an intentional regeneration comparison, follow
[the comparison input rules](references/claims-and-verdicts.md#regenerating-a-profile-for-comparison).
Deleting one profile does not reset its surrounding context. Do not remove existing profiles in response to
a request merely to improve this skill, and do not quietly reconstruct excluded module recipes from history.
