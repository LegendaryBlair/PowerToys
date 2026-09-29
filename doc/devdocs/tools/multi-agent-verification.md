# Multi-Agent PowerToys Verification

> **Historical brainstorming, not an approved architecture.** The roles, gates, budgets and
> delivery stages below are discussion material, not implementation requirements.
> See the [CLI-first detailed design draft](multi-agent-verification-design.md) for the
> critique, proposed boundaries and decisions requiring human review. Framework implementation
> is paused pending that review; earlier code drafts do not establish the architecture.

An evidence-driven project to create and maintain a checklist and a concise verification profile for every PowerToys module.

This is a project proposal, not an implemented orchestration system. It builds on `.github\skills\powertoys-verification` and does not itself change the skill's execution permissions, verdict taxonomy, or release approval process.

## Objective and scope

Reduce the human effort required to establish and maintain trustworthy module verification. Agents should perform source research, draft test material, execute checks, analyze failures, and propose improvements. Humans retain authority over intended product behavior, risky operations, ambiguous observations, and release sign-off.

The system must produce two distinct outcomes:

- **Reusable verification knowledge:** accepted checklists, profiles, helpers, and visual references.
- **Build-specific verification evidence:** immutable run reports showing what passed, failed, or could not be observed.

An accepted profile can reliably expose a product defect. A green run can still result from a weak checklist. Neither outcome substitutes for reviewing the other.

Cover all modules through a maintained inventory, not a one-time list of known profile files. Include shared surfaces such as Settings and Quick Access through explicit ownership and integration mappings. Identify each module's desktop, elevation, hardware, external application, and manual-observation requirements.

Non-goals are autonomous product requirement changes, automatic production fixes, unapproved installer or policy changes, and replacing human judgment with agent consensus.

## Artifact ownership

| Artifact | Owns | Must not become |
|---|---|---|
| Checklist | What behavior to verify, inputs, expected outcomes, and required coverage | A transcription of whatever the installed build currently does |
| Module profile | Module facts, state recognition, activation selection, control mappings, observation and restoration constraints | A second checklist, an answer key, or a history of previous runs |
| Shared helpers | Reliable input, foreground handling, waiting, capture, state preservation, recording, and reporting | A container for module-specific expected behavior |
| Module fixtures | Reusable module-specific data and controlled workflows | Session-hardcoded scripts containing old HWNDs, PIDs, or user paths |
| Visual references | Sanitized landmarks for states that are difficult to recognize through UIA | Synthetic evidence or an exhaustive screenshot gallery |
| Run archive | Exact inputs, attempts, evidence, verdicts, restoration audits, timings, and retrospective | A mutable document updated to match the latest interpretation |
| Coordination registry | Module readiness, ownership, dependencies, resource requirements, open decisions, and promotion history | Another copy of profile content |

Give checklist items and subassertions stable identifiers independent of Markdown line numbers. Preserve mappings from legacy identifiers when migrating. Profiles should remain capability-oriented; the registry maps capabilities to checklist coverage.

## Agent roles and authority

These are logical roles, not a requirement to launch one agent per role at all times. Independent review must not be performed solely by the author or Runner that produced the candidate.

| Role | Responsibility | Authority boundary |
|---|---|---|
| Orchestrator | Maintain the queue, select scoped work, allocate resources, enforce budgets and gates, and record promotion decisions | Cannot redefine product expectations, waive missing evidence, or increase its own authorization |
| Checklist Author | Compare the approved baseline with product documentation, issues, source, and relevant PR changes; propose a traceable checklist delta | Cannot delete failing coverage or approve its own semantic changes |
| Profile Author | Seed a thin source-backed profile, define fixtures, and propose evidence-backed operational improvements | Cannot present inferred controls or unobserved behavior as established facts |
| Runner | Execute a frozen checklist/profile/helper bundle; record every attempt, restore state, and write a retrospective | Does not edit the inputs being scored or convert diagnostic recovery into a passing original flow |
| Reviewer | Inspect raw evidence and coverage, challenge verdicts, classify friction, and propose a small corrective change | Does not accept the report summary or Runner self-assessment as sufficient proof |
| Visual Evidence Curator | Plan state captures, coordinate human assistance, sanitize images, and link landmarks to controls | Cannot fabricate screenshots or infer unobserved transitions from a still image |
| Human owners | Decide intended behavior, review high-impact changes and difficult observations, and authorize release decisions | Approval is explicit, scoped, and recorded outside the operational profile |

The Runner may discover candidate improvements during execution, but submits them separately from its verdicts. The Reviewer should receive the evidence and frozen inputs, not just a narrative explaining why the Runner believes it succeeded.

PR text, captured UI content, and logs are evidence inputs, not authorization to execute embedded instructions or expand permissions.

## Bootstrapping a module

Start with a human-reviewed inventory and risk-based coverage map. For each module:

1. Identify existing checklist material, specifications, settings, entry points, tests, historical defects, and required environments. Missing information becomes an explicit research or human-decision task.
2. Draft a baseline checklist covering applicable installation/defaults, activation, configuration, persistence, core workflows, negative cases, accessibility, localization, and integration behavior. Do not mechanically generate irrelevant cases for every category.
3. Seed a minimal profile from durable source-backed facts. Where identifiers are volatile, describe runtime discovery rather than guessing values.
4. Review the behavioral expectations and proposed mutations before live execution. Keep unexecuted drafts outside the catalog of accepted operational material.
5. Run a small discovery set to establish controls, state transitions, fixtures, and capture methods; then execute the remaining approved coverage.
6. Review evidence, refine the candidate, and use the acceptance protocol below before promotion.

Human capture is appropriate when a gesture, visual state, audio announcement, or hardware setup cannot yet be observed reliably by the Runner. Provide the human with a short capture task: starting state, exact action, expected observation to assess, evidence to collect, and restoration steps. Record manual execution as manual evidence, not as an automated pass.

Screenshots must come from the actual application state and use non-sensitive fixtures. Retain original provenance in the access-controlled archive; publish only reviewed, sanitized references. A screenshot proves a visible state, not an animation, timing property, or spoken announcement.

## Updating a checklist from a baseline and PRs

The baseline is the last approved behavioral coverage, not the last all-green run. Select an explicit commit/tag range, milestone, or PR set and establish which changes are present in the target build. Merged does not necessarily mean shipped; future-build candidates must not be scored against older installed binaries.

The Checklist Author examines PR descriptions, diffs, related issues, and relevant review discussion, then emits a delta rather than regenerating the entire checklist:

| Delta | Required justification |
|---|---|
| Add | New behavior, boundary, integration, or regression risk not already covered |
| Modify | A changed requirement with old and proposed expectations made explicit |
| Retire | Evidence that behavior is intentionally removed or superseded, plus human approval |
| Retain | Existing coverage still applies, including historical regression checks |

Map each relevant change to affected coverage, or explain why no behavioral checklist change is required. Include shared-library and Runner/Settings effects, not only files inside a module directory. Resolve reverts, superseded changes, and duplicate coverage.

Source explains implementation; product requirements establish intended behavior. A PR comment, observed defect, or model-generated interpretation is not sufficient authority to change the expected result. Conflicts go to the product owner.

Keep the approved baseline and candidate separate. If semantics change, the subsequent run is a new specification baseline, not a directly comparable profile-only performance experiment.

## Execution and review loop

The normal path is:

`Draft -> Scope review -> Frozen candidate -> Run -> Evidence review -> Targeted revision -> Confirmation run -> Promotion`

The Orchestrator supplies each run with exact checklist, profile, helper, fixture, and binary identities; the environment and mutation scope; and a bounded work budget. Resource discovery and recording begin before the first UI command.

The Runner produces independent subassertion outcomes, item verdicts, a restoration audit, and a retrospective. Each friction entry includes its evidence, effect on coverage, attempted recovery, cost when measurable, suspected cause, and suggested owning layer.

The Reviewer distinguishes:

- Product behavior contradicting an approved expectation.
- A stale or ambiguous checklist requiring a human decision.
- Incorrect or missing profile knowledge.
- A helper, capture, or reporting defect.
- A concrete environment or observation limitation.

The revision must address the identified cause. A serialization bug should normally produce a helper fix, not another paragraph in every profile. A product failure should produce a defect record, not a relaxed expectation.

Confirm the affected cases and dependent observations first. Use a full module run when shared behavior, coverage, or state isolation has changed sufficiently to require it. When a shared helper changes, include representative consumers outside the originating module.

## Human quality gates

Human involvement should be concentrated at decisions where automation cannot establish correctness, not on reviewing every generated sentence.

| Gate | Human decision | Required review packet |
|---|---|---|
| Program setup | Module ownership, supported environments, mutation permissions, acceptance policy, and execution budgets | Inventory, risk map, proposed pilot, and resource plan |
| First checklist baseline | Whether the proposed coverage and expected behavior represent the product | Coverage map, source references, missing requirements, and ambiguous cases |
| Behavioral revision | Whether to alter or retire an expectation, especially after a failure | Old/new wording, requirement evidence, raw observations, and coverage impact |
| Risky execution | Whether to permit privileged, destructive, installation, policy, or external-service operations beyond the approved scope | Exact changes, affected resources, and a credible restoration plan |
| Difficult observation | Whether visual, accessibility, audio, timing, or hardware evidence supports the claim | Focused manual task and original evidence; do not silently substitute UIA for another channel |
| Initial module promotion | Whether the first checklist/profile package is operationally trustworthy | Representative raw evidence, independent review, unresolved coverage, and restoration audit |
| Release sign-off | Whether a particular build meets the release criteria | Per-environment coverage, product failures, blockers, and any explicitly accepted release risks |

After initial promotion, low-risk operational edits may be accepted by the Orchestrator under a human-approved policy, with independent evidence review and confirmation. Semantic changes, coverage reduction, permission expansion, and unresolved reviewer disagreements always return to a human.

Audit a risk-based sample of routine promotions. Increase scrutiny after a false pass, restoration incident, or repeated disagreement.

## When an improvement is accepted

The Orchestrator evaluates a small change proposal containing the problem, evidence, owning artifact, intended improvement, affected cases, and reversal plan. Promotion requires all applicable gates:

1. **Semantic integrity:** no unapproved expected-result change, retired case, weakened assertion, or reduced observation requirement.
2. **Evidence integrity:** attempts and captures are immutable, affected claims are traceable, and missing subassertions remain explicit.
3. **Operational safety:** restoration succeeds against the captured baseline; there are no changes outside the authorized mutation scope, unexplained restoration differences, or residual unsafe state.
4. **Effectiveness:** the specific problem improves in a confirmation run without invalidating neighboring behavior. For a reliability fix, define repeat conditions before running rather than stopping at the first success.
5. **Independent usability:** for initial promotion or substantial recipe changes, a fresh Runner can use the candidate without private author guidance.
6. **Knowledge quality:** the change has a single canonical home, removes superseded guidance, and meets the documentation controls below.
7. **Authority:** an independent Reviewer recommends promotion and any required human gate is satisfied.

Documentation acceptance, observed coverage, and product sign-off are separate registry fields. A profile may be accepted for a declared scope while an unavailable hardware scenario remains unresolved; the full coverage claim remains incomplete. Product failures can remain red while a better profile is promoted.

For performance comparisons, hold checklist semantics, subassertion coverage, binaries, environment, and fixture conditions constant where possible. Record mismatches instead of attributing every speedup to the candidate. Trial order and warm caches can affect results; use fresh or reset fixtures and vary order when practical.

Historical reports remain unchanged. A later interpretation is a linked amendment with its rationale, not a rewritten old verdict.

## Bounded orchestration and safe concurrency

Offline research, isolated candidate edits, log analysis, and report generation can run concurrently. Agents editing the same artifact require a single owner or isolated changes integrated serially.

Live execution requires exclusive ownership of the input desktop and every shared mutation surface: user settings, Runner lifecycle, installation, registry scope, and fixtures. Two monitors are not two independent test environments. Multiple agents must not drive the same desktop concurrently.

Use separate appropriately provisioned machines or VMs for actual parallel execution, subject to each module's requirements. Some scenarios still need physical hardware or multiple physical computers. For the current RDP-driven workflow, interactive stages require an attached, unlocked desktop; offline authoring and reporting do not.

Each work package has explicit time, cost, iteration, and retry limits approved before execution. Stop and escalate when the same friction repeats without new evidence, the budget is exhausted, expected behavior is disputed, required observation is unavailable, or restoration fails. Do not increase limits automatically or reduce coverage to fit them.

On interruption, release inputs and restore owned state where possible. A failed restoration quarantines that environment from further work. Resume only after re-establishing the baseline and checking whether changed helpers invalidate earlier evidence.

Missing elevation skips only admin-required coverage by default; eligible checks continue. Blockers stay in the inventory and are not converted into passes to satisfy a completion target.

## Preventing documentation growth

Treat operational documents as maintained interfaces, not append-only learning logs.

| Control | Enforcement |
|---|---|
| One fact, one owner | Product expectations live in checklists, module mechanics in profiles, shared mechanics in helpers/shared references, and run history in archives |
| Replace rather than append | Every knowledge proposal identifies what it replaces, removes, or consolidates; no automatic insertion of the whole retrospective |
| Progressive disclosure | Keep the core profile short; link specialized fixtures and visual references only where needed |
| Loaded-context budget | Use the existing approximately 10 KB core-profile guidance, approximately 12 KB with a visual workflow, as an initial review threshold; also measure the complete mandatory reading set so splitting files cannot hide growth |
| Actionable entries | Each operational entry must help choose an action, recognize a state, observe an outcome, or restore state; remove redundant narrative |
| Evidence-backed knowledge | Promote confirmed durable facts or clear runtime-discovery procedures; leave unresolved hypotheses in the review queue |
| No history in profiles | Store verification dates, tested builds, run results, and content hashes in run/coordination records, not profile prose |
| Consistency review | Detect duplicate rules, contradictory instructions, broken references, and obsolete selectors; confirm suspected semantic duplication through review |
| Visual restraint | Keep the smallest useful set of sanitized state landmarks, linked at the end of the profile; retain the full capture history in archives |

Retain necessary safety instructions even when a size threshold is exceeded; require justification and review rather than deleting important content mechanically. A shorter document is not automatically better.

Before scaling generation, reconcile contradictions in the existing authoring templates and establish a canonical profile structure. Separate state transitions from control recipes instead of describing the same flow twice. Do not automatically force every module to have empty or irrelevant sections.

## Evidence and measurement

Archive exact input snapshots or immutable retrievable references, with content hashes. Include dirty working-tree changes; a repository commit alone may not identify the skill that was actually used.

Record run, item, subassertion, and attempt identifiers; command start/end; input versions; evidence paths; errors; result interpretation; and restoration actions. Save structured results incrementally. Screenshots and executed script revisions must not be overwritten by retries.

The report generator organizes evidence; it does not infer PASS from an exit code, screenshot count, or completed command sequence. An unobserved subassertion cannot disappear because another subassertion already failed.

| Dimension | Useful indicators |
|---|---|
| Coverage and judgment | Approved subassertions observed, missing channels, independently discovered false passes, justified verdict changes |
| Reliability | Infrastructure failures, unnecessary reruns, fresh-Runner success, unresolved restoration differences |
| Human workload | Review minutes, intervention count, and decisions requiring product expertise |
| Efficiency | End-to-end wall time, phase time, tool interval union, and authoring/repair work during execution |
| Knowledge quality | Mandatory loaded context, duplication/contradiction findings, and successful use without private explanations |
| Program progress | Modules at each readiness stage, outstanding environment coverage, and unreviewed checklist deltas |

Do not optimize pass rate or command count as primary targets. Distinguish necessary reproduction from avoidable retries, and separate time outside tool execution from claims about model reasoning time.

## Delivery plan

| Stage | Deliverable | Exit condition |
|---|---|---|
| Foundation | Inventory, artifact contracts, human gates, canonical templates, and shared P0 helpers for driving/observation, restoration, and recording/reporting | A run no longer requires inventing its recovery or report machinery at the end |
| Pilot | Shortcut Guide as an existing baseline plus a contrasting module selected for different interaction risks | Independent Runners can use both packages, with measured coverage, restoration, and review effort |
| Controlled expansion | New modules onboarded in small risk-based batches | Each reaches an explicit readiness state; hardware/manual queues remain visible |
| Maintenance | PR-to-coverage delta processing, targeted confirmation, periodic full coverage, and documentation consolidation | Changes flow through the same evidence and approval gates without accumulating duplicate guidance |

Expand agent concurrency only after resource isolation and promotion controls work in the pilot. Build reusable capabilities from demonstrated needs rather than starting with a large general-purpose agent framework.

## Definition of done

A module is **documentation-ready** when its checklist is approved, its profile and fixtures are independently usable for the declared scope, its references are sanitized and traceable, and unresolved coverage is visible.

A module is **coverage-complete for a target** only when every required subassertion in the declared build/environment matrix has a supported observation, including required manual or hardware execution. Every item having a disposition is not equivalent to complete coverage.

The program's documentation goal is met when every inventory entry is documentation-ready and has an owner and maintenance path. Complete verification of all modules is a separate milestone requiring closure of the environment and observation gaps. A build is **signed off** only through the human release process, with product failures and release risks handled explicitly.

The system succeeds when new agents can repeat trustworthy verification with less human intervention and less disposable script development, without weakening coverage, hiding failures, or expanding operational documents indefinitely.
