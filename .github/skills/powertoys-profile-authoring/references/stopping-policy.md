# Round completion and stopping conditions

The initial workflow requires the R0/R1 coverage contract and exits after R1 by default. Diagnostic/repair
limits below are approved defaults, overridable by an explicit task instruction within runtime permissions.
R2 and later work require explicit authorization. Do not invent PASS/non-BLOCKED quotas, extra rounds or
larger allowances. Ending a run, meeting its completion gate and accepting a profile are separate decisions.
The current agent performs R0, revisions and R1 sequentially by default. Independent verification is opt-in,
not part of the ordinary completion gate.

## Separate three questions

1. **Material quality:** do the checklist/profile/helpers support trustworthy execution, observation and restoration?
2. **Product health:** does the actual product satisfy those expectations?
3. **Permission/investment:** may this run continue using the desktop, time, calls and resources?

A profile can be useful while exposing a real product FAIL. Repeated BLOCKED outcomes, an identical bad
screenshot or two agents agreeing do not establish material quality.

## Required round coverage

| Round | Scope | Completion boundary |
|---|---|---|
| R0: discovery | Keep the complete checklist/inventory; sample distinct core input, observation and restoration mechanisms | Obtain credible live operation/results and verified restoration, not merely a launch. Record untested IDs and known limits; unresolved core mechanics mean partial discovery. |
| R1: first full confirmation | Freeze the candidate and complete inventory, including every assertion's required matrix conditions | Process the full inventory and actually execute every safely available independent condition. Apply the completion gate below; a representative or repair-only selection is not R1 completion. |
| R2: authorized repair confirmation | A fixed repair list plus justified neighboring regressions, with explicit candidate/run identity | Perform one targeted confirmation, restore/archive and exit with confirmed or unresolved results. No automatic R3; a subset cannot complete unfinished R1 or certify a full final revision. |

A narrower task explicitly requested by the user remains valid, but is scoped/partial work, not completion of
the full authoring workflow. Respect permissions and safety boundaries in every round. Full R1 scope does not
authorize missing elevation, destructive operations, new installations or unsafe attempts merely for coverage.
An unset final convergence policy does not permit skipping or reducing R1.

### R1 completion gate

1. Reconcile all frozen inventory IDs and every required condition against recorded evidence. Sharing setup is
   allowed; a parent verdict or one representative matrix row does not cover unexecuted variants.
2. Actually execute all independent conditions whose prerequisites can be met safely within authorization.
   One failure or unavailable conditional fixture does not justify skipping unrelated work.
3. Explain every unexecuted condition with evidence and the needed remedy. Separate external prerequisites/
   authority/safety limits, authoring/infrastructure gaps, specification decisions and confirmed product
   dependencies. An untried selector or missing helper is not proof of an external limitation.
4. Address known fixable gaps within the [repair limits](#diagnostic-and-repair-limits) and reobserve affected
   behavior. If a gap or unresolved expectation remains, report R1 incomplete rather than extending the loop.
   The incomplete label is not a command to keep repairing until it disappears.
   Preserve genuine product FAILs and their dependent unobserved work; do not fix the product or weaken
   expectations to improve authoring metrics.
5. Verify final restoration and archive/input integrity. Unprocessed IDs, unexplained unobserved conditions,
   invalid evidence or unresolved cleanup prevent a completed R1 claim.

If only evidenced external limits or confirmed product dependencies leave conditions unexecuted, report
**full assessment with limits**, together with actual execution counts and causes. Do not say every item ran
or the profile is fully supported. Use the existing engine verdicts; these are workflow/reporting distinctions,
not new per-item statuses. An actual stop/permission/budget limit can end a run, but cannot make partial R1
complete. Keep the remaining work explicit. Follow the
[coverage accounting rules](claims-and-verdicts.md#6-report-and-compare-like-for-like).

## Finite exit policy

- **R1:** finish the full inventory pass, restore, archive and return by default. Remaining FAIL/BLOCKED
  findings do not authorize another repair round. Report whether coverage met the gate or remains incomplete.
- **R2:** authorization may be given in advance or as a later request. Record the chosen root causes, affected
  IDs, neighboring regressions and repair allowance before work. Make bounded repairs, then one targeted
  confirmation; finish restoration/reporting and exit whether fixes passed, still failed or could not be verified.
  If no meaningful repair can be made within the allowance, return that finding instead of executing an
  unchanged test merely to reproduce known failures.
- **R3 or further repair work after the authorized round:** require explicit authorization, never inferred from an unresolved R2 result,
  a higher desired PASS rate or an unmet acceptance gate. An existing explicit authorization is sufficient;
  this does not add routine per-action approval prompts.
- **Early stop:** unsafe conditions, unavailable authority/environment, exhausted applicable limits or no
  justified new experiment allow an incomplete exit. Preserve evidence and remaining IDs. A local repair limit
  stops that repair, not independent R1 coverage; a task-wide stop ends new work with truthful partial status.

R1 prioritizes traversal over deep debugging: after a bounded supported correction, record the root gap and
move to other independent cases. Do not turn verification into unbounded helper development or keep restarting
one troublesome case. A round can end without its quality gate passing; it cannot then be called accepted.

## Diagnostic and repair limits

Use these defaults unless an explicit task instruction changes them. More restrictive runtime/user limits
still apply; never infer permission to exceed them.

| Scope | Default limit | At the limit |
|---|---|---|
| One root cause | At most 2 materially different diagnostic/repair approaches or 20 minutes of accumulated diagnostic/repair time, whichever is reached first | Stop work on that cause, preserve evidence and remedy/backlog; continue independent cases |

There is **no default cumulative repair-time cap** for a module or the R0-to-R1 sequence, and no mandatory
timed progress checkpoint or replacement time budget. Explicit user/runtime limits still apply.
Legacy cumulative-batch balances remain historical records, not an active stopping condition under this
policy. Removing that cap does not reset root-specific counters, erase failures or waive a separate explicit limit.

Charge execution-configuration fixes, preflight/receipt diagnosis and driver corrections to the relevant
root's allowance, even before the first product action. Ordinary successful setup is not repair time.
Track time spent investigating, editing and
validating a repair, including waits for its probes/commands, rather than only tool-call counts. Ordinary
planned discovery/test execution and idle time waiting for the user are not repair time; repeated attempts
to overcome a known obstacle are. These are not limits on the duration or size of the full R1 checklist.
Use bounded command/observation timeouts and the remaining allowance for diagnostic probes.

An approach requires a concrete hypothesis, a materially different diagnostic or change, and an observation
that can distinguish it. Replaying the same gesture, lengthening a sleep or restarting without a new hypothesis
is not progress or a fresh allowance. Stop earlier when there is no justified next experiment. Do not reset
attempt/time accounting by renaming a root cause or changing sessions/agents.
Record root-specific attempts, consumed time, evidence and the stop reason in existing authoring records/execution
journals; do not add a batch ledger, checkpoint mechanism or coordinator.

Prioritize safety and invalid observations, then shared blockers/core paths that unlock substantial coverage.
Defer isolated low-value edge cases, cosmetic wording and report polish. A repair budget stop remains an
authoring gap, not an external-environment exemption or evidence that the underlying feature is unsupported.

Reserve cleanup separately. Reaching a root limit stops further diagnosis/repair for that root, not
planned restoration or independent normal coverage. Execute the planned bounded cleanup; if it fails,
stop other mutations, preserve recovery evidence
and necessary backup owners, and report/escalate the unresolved state. Do not hide cleanup failures, destroy
the only recovery copy or launch unbounded speculative recovery experiments.

## Repair before repeating

A missing, repairable helper/fixture remains **Author work within the approved limits**, not a reason to ask
for routine approval, replay a blocked confirmation or repair indefinitely. Use the
[capability map and change receipt](execution-readiness.md) to prioritize and check repairs before R1.
When an allowance is exhausted, retain the unresolved gap and continue independent safe coverage. If a shared
gap prevents all trustworthy work, return incomplete instead of repeatedly executing the same setup.
Safe R0 discovery remains allowed; unknown controls are not a requirement for a mature profile before R0.

If only evidence gates changed and the same data/input obstacle remains, record improved classification but
not improved execution capability. A rerun can be justified as a diagnostic experiment with a concrete new
question; do not count it as confirmation of repaired coverage.

## Candidate policies

These choices may refine acceptance or explicitly authorize later work. They do not replace the required
first full R1, default exit or repair limits without an explicit user decision.

| Option | Candidate acceptance/stop rule | Strength | Failure mode to guard against |
|---|---|---|---|
| Human acceptance | Stop for a compact evidence review; human accepts declared profile scope | No premature numerical definition | Review cost; distinguish approval from mere acknowledgment |
| Fresh-session stability | User chooses `k` independent confirmations of the final material revision with equivalent meaningful observations | Tests reproducibility without Author coaching | Stable false PASS/all-BLOCKED runs; copied private context |
| Coverage plus infrastructure quality | User defines eligible coverage and blocking infrastructure gaps; accept when both are met | Separates product FAIL from driver failure | Shrinking scope to meet a percentage |
| Risk-based core plus holdout | User selects mandatory high-risk claims and cases not used repeatedly during author iteration | Detects overfitting to a familiar example | Calling partial/representative coverage full-module acceptance |
| Budget/time/round cap | Apply approved defaults and explicit task overrides | Predictable investment | A budget stop is not quality acceptance or permission to omit independent R1 cases |
| No-progress escalation | Ask for human guidance when another round provides no new observation or repair hypothesis | Avoids expensive loops | Different labels or more retries mistaken for progress |

### Recommended starting point for discussion

Consider a **hybrid**, subject to user selection:

- An approved scope with explicit environment exclusions.
- Trustworthy evidence and verified restoration for that scope.
- No unresolved infrastructure flaw that invalidates those observations.
- Independent confirmation only if the user explicitly selects that additional evidence.
- Human review of ambiguous expectations, visual-reference acceptance and final supported scope.
- A separately approved investment cap and an escalation point for unexplained/no-progress iterations.

This recommendation does not set `k`, supersede the approved repair limits or require all-green product outcomes.

## What "stable" should compare

Fix or explicitly stratify material revision, product artifact, assertion selection, fixture inputs and relevant
environment dimensions. Compare behavior/observations and explained result categories, not HWNDs, timestamps,
raw file ordering or screenshot hashes that legitimately vary.

Changing checklist expectations, helpers, profile or accepted visual references starts a new candidate.
A build/environment change also changes comparability. Do not combine different revisions into an unexplained
stability streak. An assisted diagnosis does not count as an independent confirmation.

Useful signals:

- Required eligible assertions have valid evidence; unavailable conditions are not silently reclassified eligible.
- Product findings reproduce under valid expectations, including counterexamples that earlier runs missed.
- Fewer run-local repairs, stale-selector errors, unexplained retries or author interventions.
- Original state is restored and restoration is verified, including interrupted/failed attempts.
- Operating knowledge is recorded in the profile/helper rather than left only in the author's memory.
- Relevant holdout or neighboring cases work without a new ad hoc recipe.
- Previously blocked core paths became executable because an evidenced profile/helper/fixture repair was confirmed.

False signals:

- More PASS rows after deleting/merging requirements or accepting current screenshots as truth.
- Repeating the same driver error or missing prerequisite.
- A helper unit test passes while the required live interaction was never exercised.
- Same-agent execution or a coached worker is mislabeled independent confirmation.
- Increasing the inventory with unsupported matrices while leaving the ordinary common path untested.
- Treating a stricter summary or another repetition of a known data-safety block as a repaired capability.

## Human intervention

Pause with a specific decision packet when:

- Baseline/PR expectations conflict or a proposed edit changes product semantics/coverage.
- A profile change worsens results and the difference cannot be explained by raw evidence.
- A visual candidate has no independent basis for acceptance.
- A new permission, destructive state change, build replacement or investment exceeds authorization.
- Cleanup is uncertain, or another loop has no justified next experiment.

Do not mistake an old authoring/main checkout for the current verification baseline. Correct that selection first.
For a genuine shared-layer gap, attempt the scoped fix within the approved allowance. Request a decision only
when the remedy changes semantics, authority, environment investment or requires work beyond the authorized
round or explicit task limit; otherwise retain the affected gap and continue independent work rather than
demanding approval for ordinary actions.

Include the affected IDs, versions, actual observations, diff, unknowns, recommendation and resume point.
Human guidance can change checklist, profile, helpers or environment. Persist the confirmed decision with the
affected revision; a vague "okay" must not expand authority. A separately authorized confirmation after a
material change uses the updated recorded inputs; a fresh agent is needed only for explicitly requested
independence. The change itself does not authorize another round.

## If no policy has been chosen

**Do not block R0 because the convergence policy, a new budget number or a permission-argument template is
unset.** An explicit request to execute the workflow authorizes its ordinary first-run work under the effective
runtime permissions, without another agent/desktop confirmation. The current agent checks the selected
inputs and actual prerequisites, then proceeds directly; tool policy is not waived.

The initial sequence comprises R0 discovery, bounded profile/improvement work and same-agent full-inventory R1.
Restore, archive and exit after R1; do not automatically repair the remaining findings or start R2. Use the
approved limits above, existing runtime limits and explicit task overrides, not a new budget questionnaire.
A focused confirmation does not satisfy full R1 coverage.
Earlier exits follow the finite exit policy, including actual limits, unsafe conditions and no-progress stops.
A local repair stop still leaves independent coverage eligible. Preserve the concrete evidence and remaining
work, not an inferred lack of approval or a false completion claim.

Report `needs-review`, not "converged," and state whether R1 is complete, fully assessed with limits or incomplete.
The user can choose further acceptance criteria using that evidence; the minimum R1 scope is already defined.
Do not invent work merely to create an improvement commit or a second failure.

## Stop without claiming acceptance

| Condition | Workflow status | Required action |
|---|---|---|
| User ends the task or task-wide cap is reached | `stopped-by-budget` / `stopped-by-user` | Stop new work; complete feasible cleanup and archive partial coverage |
| A root repair limit is reached or no new experiment is justified | `needs-review` for the unresolved repair | Stop that repair, retain evidence and continue independent permitted coverage; do not silently reset the allowance |
| Skill/version/session identity is wrong | `blocked` | Preserve diagnostics; do not count the run |
| A runtime tool/path request is actually denied or needs new authority | `blocked` for affected work | Retain the exact operation and error/approval request; honor policy, continue independent permitted work |
| Desktop/required environment becomes unavailable | `blocked` for affected work | Continue only independent safe work; do not guess outcomes |
| R1 leaves unprocessed conditions or unresolved authoring/specification gaps | `needs-review` / `blocked`, R1 incomplete | State remaining IDs and evidence; repair within authorization or name the concrete limit, never claim full completion |
| R1 fully assesses the inventory but evidenced external/product limits prevent some execution | `needs-review`, full assessment with limits | Report actual execution coverage and causes separately; do not claim all requirements ran or full supported scope |
| Restoration is uncertain | `needs-review` / `blocked` | Stop dependent mutations, preserve receipts and request a concrete recovery decision |
| R1 or an authorized R2 pass reaches its exit boundary | `needs-review` unless separately accepted | Restore/archive and return confirmed/unresolved results; no automatic next round, regardless of verdict colors |
| Chosen quality criteria and acceptance review are satisfied | `accepted-profile-scope` | Record exact accepted revision, build applicability and known limits |

Cleanup and evidence preservation are mandatory, not optional work funded only by leftover model credits.
Profile acceptance and product/release sign-off remain separate decisions.
