# Executable claims and evidence-based verdicts

Preserving every source requirement does not mean preserving stale wording as an unresolved test forever.
Build an executable interpretation without losing the original intent or provenance.

## 1. Normalize baseline wording against the target

For renamed controls, changed mode layouts or migrated UI, retain:

| Field | Example of the distinction |
|---|---|
| Original source wording/reference | Historical option name and baseline location |
| User-visible intent | What the user does and what must happen |
| Current control sequence | Target-version route that realizes that intent |
| Basis for the mapping | Versioned source/PR/spec evidence plus runtime observation |
| Stable assertion ID | One canonical requirement, with former names/source aliases retained |

When evidence establishes the same observable behavior through renamed/reorganized controls, the Author can
record that mapping without an extra human approval solely for the caption change. If semantics actually
conflict or several interpretations remain reasonable, ask for that specific decision and defer only the
affected expectation.

Do not keep an obsolete option as an automatic checklist FAIL while also counting its well-defined current
equivalent as a separate feature. Nor silently delete the old intent. A failed lookup of an old caption proves
neither feature removal nor a product defect.

## 2. Separate claims from implementation details and validation anecdotes

Use PR descriptions and diffs to identify user-facing promises and relevant regressions. A source constant,
an author's test log or a statement that a particular stress run passed is not automatically a new mandatory
end-user acceptance criterion.

- Include explicit functional claims with observable outcomes and independent fixture expectations.
- Mark exact timing/easing, stress/leak thresholds, corruption behavior and other specialist criteria as
  requiring the corresponding oracle/instrumentation/context. Resolve their scope from the source/owner;
  do not invent arbitrary counts or thresholds.
- Keep installer, telemetry, registry-negative and other disruptive conditions explicit where applicable,
  without interpreting their presence as permission to perform them.
- Avoid multiplying the same behavior into baseline, migration and shared-refactor rows with no distinct
  observation. Use source aliases or distinct subconditions instead.

Keep a **core eligible** selection and an **additional conditional** matrix in the inventory. This is an
execution grouping, not scope deletion: preserve all original IDs/conditions and their reasons for deferral.
Readiness status belongs to the round's capability map; do not bake today's missing environment into the
permanent product expectation.

## 3. Make each condition independently observable

A condition needs an action, result, prerequisites, evidence method and restoration plan.
Examples of conditions that must not be collapsed:

- Saved shortcut versus actual new/old/restored hotkey activation.
- Opening a picker versus selecting, copying and returning to the editor.
- Changing a Settings toggle versus seeing its effect in the module.
- A normal installed path versus elevated/per-machine/missing-registry paths.
- One zoom level versus repeated zoom entry/exit and capture restoration.

If only some conditions execute, retain their individual observations. The parent remains incomplete when
required conditions lack evidence, but do not hide a successful ordinary path under one opaque BLOCKED label.
Do not average unavailable variants into a misleading improvement/degradation percentage.

## 4. Apply verdicts only after checking the observation

Keep the candidate engine's public verdict vocabulary. Where an older engine lacks a suitable subtype, retain
explicit `cause`, `dependency` and `observed/not-observed` metadata instead of inventing product outcomes.

| Evidence state | Meaning |
|---|---|
| Valid setup/action; observed behavior contradicts a sourced expectation | Product FAIL, scoped to what was actually demonstrated |
| Broken/ambiguous expectation after the Author's mapping work | Checklist issue/decision; not a product failure |
| Driver error, wrong window/integrity/DPI or untrusted observation | Infrastructure/setup gap; product outcome not established |
| Required hardware/locale/elevation condition unavailable | Environment/capability block for that condition |
| Eligible action not completed | Incomplete/unobserved work, not automatically a visual/environment inability |
| Dependent action unreachable after an upstream failure | Explicit dependency and not observed; do not assert its own defect |
| Complete expected behavior observed | PASS with the supporting method/evidence |

An absent provider may validly fail command availability; pin persistence cannot be independently diagnosed
if there was no command to pin. A parent scenario can therefore FAIL while dependent subconditions remain
NOT-OBSERVED. Do not inflate the number of product defects by propagating the same prerequisite failure.

Similarly, a settled screenshot cannot prove timing, but failing to perform another zoom cycle is not proof
that visual capture is impossible. Report the actual missing work.

## 5. Visual evidence is not the same as an accepted reference

The absence of an approved visual baseline does not prohibit observing the current UI, collecting candidate
images or verifying unambiguous content/state. Assess those claims using the checklist/spec and valid captures.

Only conditions that genuinely require an undefined visual oracle/threshold need that decision. Do not add
"an accepted reference must already exist" to every visual assertion; that creates a circular dependency in
new-profile authoring. Keep screenshot promotion governed by [visual-references.md](visual-references.md).
Never use the current output alone to define the expected output or hide private content by cropping away
the property under test.

## 6. Report and compare like-for-like

Report total retained requirements, selected/eligible conditions, actual executed coverage and unresolved
dependencies separately. Show scenario and assertion/subcondition denominators when grouping differs.
Compare overlapping semantics before comparing raw PASS percentages.

Use the **archived tested input**, not merely the latest working profile. A profile edited after a run did not
cause that run's outcome. Record both runtime and material differences: product hash, main base, helpers/fixtures,
privileges, desktop/DPI/locale, model/runtime, permitted evidence and any author assistance.

Retain corrected classifications alongside their original observations. Improved honesty can reduce PASS count;
improved executable coverage requires completing previously missing trustworthy observations.

### Regenerating a profile for comparison

Before a from-scratch comparison, agree and record the experiment inputs:

- Start a new authoring branch/worktree from the chosen main base, with the same baseline source, PR cutoff,
  installed artifact and comparison conditions where possible. Record any difference instead of assuming equivalence.
- Keep old profiles/reports/commits as comparison evidence. Deleting a Markdown file does not remove chat
  context, sibling helpers, fixtures, screenshots or prior checklist decisions.
- Use a fresh Author session for a from-scratch generation when the existing Author has read the competing
  profile. Give it the revised authoring skill and declared source inputs, not the old module recipes/results.
- Keep both the Author and Runner from recovering the excluded profile through old branches, Git history,
  archives or session memory. The Runner is always fresh and receives only its current neutral packet.
- Declare permitted generic helpers/templates and whether the checklist is regenerated or held fixed. Reusing
  a stronger module's profile/harness is a valid engineering choice, but label it reuse rather than from-scratch success.
- After the candidate is committed and run, compare independently using the exact archived revisions and
  shared assertions. A model/runtime change is another experimental factor, not proof that the skill caused a difference.

Do not delete or overwrite a competing profile/branch merely because this skill is being improved. Removal
and regeneration are separate user actions with their own scope.
