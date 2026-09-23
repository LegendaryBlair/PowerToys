# Stopping conditions - brainstorm, not an approved policy

The authoring loop's convergence rule is **intentionally unresolved**. These are choices to discuss with the user,
not built-in thresholds. Do not silently select a number of rounds, a PASS percentage or a time/token budget.

## Separate three questions

1. **Material quality:** can a fresh Runner use the checklist/profile/helpers to obtain trustworthy observations?
2. **Product health:** does the actual product satisfy those expectations?
3. **Permission/investment:** may this run continue using the desktop, time, calls and resources?

A profile can be useful while exposing a real product FAIL. Repeated BLOCKED outcomes, an identical bad
screenshot or two agents agreeing do not establish material quality.

## Repair before repeating

A missing, repairable helper/fixture for selected core coverage is **Author work**, not a reason to ask for
another routine approval or to replay the same blocked confirmation. Use the
[capability map and change receipt](execution-readiness.md) to implement/check the mechanism before R1.
Safe R0 discovery remains allowed; unknown controls are not a requirement for a mature profile before R0.

If only evidence gates changed and the same data/input obstacle remains, record improved classification but
not improved execution capability. A rerun can be justified as a diagnostic experiment with a concrete new
question; do not count it as confirmation of repaired coverage.

## Candidate policies

| Option | Candidate acceptance/stop rule | Strength | Failure mode to guard against |
|---|---|---|---|
| Human acceptance | Stop for a compact evidence review; human accepts declared profile scope | No premature numerical definition | Review cost; distinguish approval from mere acknowledgment |
| Fresh-session stability | User chooses `k` independent confirmations of the final material revision with equivalent meaningful observations | Tests reproducibility without Author coaching | Stable false PASS/all-BLOCKED runs; copied private context |
| Coverage plus infrastructure quality | User defines eligible coverage and blocking infrastructure gaps; accept when both are met | Separates product FAIL from driver failure | Shrinking scope to meet a percentage |
| Risk-based core plus holdout | User selects mandatory high-risk claims and cases not used repeatedly during author iteration | Detects overfitting to a familiar example | Calling partial/representative coverage full-module acceptance |
| Budget/time/round cap | Stop at the user's explicit ceiling | Predictable investment | A budget stop is not quality acceptance |
| No-progress escalation | Ask for human guidance when another round provides no new observation or repair hypothesis | Avoids expensive loops | Different labels or more retries mistaken for progress |

### Recommended starting point for discussion

Consider a **hybrid**, subject to user selection:

- An approved scope with explicit environment exclusions.
- Trustworthy evidence and verified restoration for that scope.
- No unresolved infrastructure flaw that invalidates those observations.
- A user-chosen number/selection of unassisted fresh-session confirmations on the final revision.
- Human review of ambiguous expectations, visual-reference acceptance and final supported scope.
- A separately approved investment cap and an escalation point for unexplained/no-progress iterations.

This recommendation does **not** set `k`, invent a budget or require product outcomes to be all green.

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
- A new Runner does not need information that should have been written into the profile/helper.
- Relevant holdout or neighboring cases work without a new ad hoc recipe.
- Previously blocked core paths became executable because an evidenced profile/helper/fixture repair was confirmed.

False signals:

- More PASS rows after deleting/merging requirements or accepting current screenshots as truth.
- Repeating the same driver error or missing prerequisite.
- A helper unit test passes while the required live interaction was never exercised.
- A new process is named Runner but receives the Author's transcript or previous answer labels.
- Increasing the inventory with unsupported matrices while leaving the ordinary common path untested.
- Treating a stricter summary or another repetition of a known data-safety block as a repaired capability.

## Human intervention

Pause with a specific decision packet when:

- Baseline/PR expectations conflict or a proposed edit changes product semantics/coverage.
- A profile change worsens results and the difference cannot be explained by raw evidence.
- A visual candidate has no independent basis for acceptance.
- A new permission, destructive state change, build replacement or investment exceeds authorization.
- Cleanup is uncertain, or another loop has no justified next experiment.

Do not escalate routine implementable helper work merely because the current main branch lacks that helper.
Implement/test the scoped fix under the existing authorization; ask only when the remedy actually changes
semantics, authority, environment investment or another material decision.

Include the affected IDs, versions, actual observations, diff, unknowns, recommendation and resume point.
Human guidance can change checklist, profile, helpers or environment. Persist the confirmed decision with the
affected revision; a vague "okay" must not expand authority. After changing materials, use another fresh Runner.

## If no policy has been chosen

**Do not block R0 because the convergence policy, a new budget number or a permission-argument template is
unset.** An explicit request to execute the workflow authorizes its ordinary first-run work under the effective
runtime permissions, without another Runner/desktop confirmation. The Author automatically checks the fresh
session/input handshake and proceeds; tool policy is not waived.

For the requested five-stage workflow, the initial execution, profile/improvement commits and fresh candidate
confirmation form a bounded initial sequence; then stop for review before further open-ended rounds. Use
existing runtime limits and explicit user ceilings. No new numerical spending limit is implied here.
Pause earlier only for a real scope/semantic decision, unsafe condition, verified capability gap or actual
runtime permission requirement. Preserve the concrete evidence, not an inferred lack of approval.

Report `needs-review`, not "converged." The user can then choose a policy using the concrete first-run evidence.
Do not invent work merely to create an improvement commit or a second failure.

## Stop without claiming acceptance

| Condition | Workflow status | Required action |
|---|---|---|
| User ends the task or chosen cap is reached | `stopped-by-budget` / `stopped-by-user` | Stop new work; complete feasible cleanup and archive partial coverage |
| Skill/version/session identity is wrong | `blocked` | Preserve diagnostics; do not count the run |
| A runtime tool/path request is actually denied or needs new authority | `blocked` for affected work | Retain the exact operation and error/approval request; honor policy, continue independent permitted work |
| Desktop/required environment becomes unavailable | `blocked` for affected work | Continue only independent safe work; do not guess outcomes |
| Restoration is uncertain | `needs-review` / `blocked` | Stop dependent mutations, preserve receipts and request a concrete recovery decision |
| Chosen quality criteria and acceptance review are satisfied | `accepted-profile-scope` | Record exact accepted revision, build applicability and known limits |

Cleanup and evidence preservation are mandatory, not optional work funded only by leftover model credits.
Profile acceptance and product/release sign-off remain separate decisions.
