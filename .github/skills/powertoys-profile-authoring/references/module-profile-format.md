# Module profile format contract

This is the normative output format for `powertoys-profile-authoring`, including refinements.
Read it before drafting a profile and before reviewing every candidate. An older verification
README or example profile must not override this contract.

The aligned Workspaces, Shortcut Guide and Color Picker profiles establish the section roles
and four table schemas below. Reuse their structure, not their module-specific controls,
helpers, recorded verdicts or machine paths. Use only materials allowed by the current
authoring/comparison scope; do not retrieve an excluded profile to fill gaps.

Record this contract's path/hash with the Author's input record. Format compliance is an
Author review gate, not proof of executable readiness, a fresh Runner confirmation or product
correctness. It must not become a prerequisite for the authorized profile-absent R0 discovery.

## 1. File, headings and order

Write the profile to the selected verification engine's module directory, normally
`.github\skills\powertoys-verification\references\modules\<module>.md`.
Use an identifying H1 such as `# <Module> - module verification profile`.

Use these H2 sections, in this order. The first two are always first and second.

| Position | H2 heading | Presence rule |
|---|---|---|
| 1 | `Module facts` | Required |
| 2 | `Entry paths` | Required; immediately after Module facts |
| 3 | `UI state-transition map` | Required when modes, pages, popups or lifecycle transitions affect available actions; otherwise omit |
| 4 | `Control locator and interaction index` | Required |
| 5 | `Troubleshooting` | Required |
| 6 | `Fixtures and restoration` | Required when the scope creates resources, changes user/module state or needs cleanup; otherwise omit |
| Last | Reference container | Include when portable source/visual references need indexing; see section 8 |

Omitting a conditional section does not reorder the remaining sections. All three aligned
examples need both the state map and restoration section. Record a conditional omission and
its basis in the Author review record; do not insert empty tables or a `None` section.
If required knowledge is missing, retain it as discovery-stage/Author work rather than
inventing rows or treating the missing section as an optional omission.

Use the exact core heading spellings above. Do not substitute `Activation selection`,
`Entry-paths (try in order)`, `Recipes`, `BLOCKED traps` or `Fixtures & restoration`.
Do not insert a mixed observation/restoration H2 between the core sections. Supporting
observation guidance belongs under the interaction index, normally `### Read-out notes`
and, when needed, `### Observation rules`.

Module facts may use a compact key/value table or labeled facts, as the aligned examples do.
The final reference container also has the explicitly allowed variants in section 8.
These presentation variants do not relax the core heading or table-schema rules.

## 2. Module facts

Keep bootstrap identity and applicability here: module key/display name, source location,
configuration/data locations, executable/UI identity, relevant UI stack, entry events and
shortcut discovery, plus module-specific lifecycle facts when needed.

- Distinguish a default shortcut from the user's current configured binding.
- State how to rediscover runtime identities; do not freeze a run's HWND, PID, selector slug
  or user-specific absolute path into reusable instructions.
- Describe applicable behavior/build differences only when they change how to operate.
  Keep execution history and actual tested artifact identities in the archive/Author record.
  Never invent or advance a verification stamp because documentation was reformatted or
  source was inspected; a retained historical stamp is not proof for the current target.
- Omit inapplicable fields. Do not invent a DSC resource, event, path or helper to complete
  a uniform-looking metadata table.

## 3. Entry paths

Explain how to enter the module or relevant configuration surface, when each route applies,
and the destination/state-map reference. Use named subsections or an intent-to-entry table;
the aligned profiles do not prescribe one entry-table schema.

- Choose by the assertion, not a global fastest-first fallback order. Rank alternatives by
  reliability only when they exercise the same required behavior.
- Separate downstream activation, physical binding, held-key behavior, Settings navigation
  and external integration. A convenient event cannot replace a binding/entry-point claim.
- Retain essential safety/readiness prerequisites before the first action, with links to
  the detailed ownership, observation and restoration rules.
- Link detailed recorder/control mechanics to the interaction index. Put snapshot/rollback
  detail in Fixtures and restoration, not in the entry section.
- Put module-specific fixture-reuse/lifecycle scheduling suggestions in `Execution notes`;
  do not turn an entry list into a mandatory whole-suite execution order.

## 4. UI state-transition map

Use exactly these four columns, in this order:

```markdown
| Current state | Trigger / condition | Next state | State landmarks |
|---|---|---|---|
| <named state> | <event/control; applicable guard> | <one named destination> | <structural window/control/lifecycle cues> |
```

- Group rows by current state and use consistent state names. Define boundary/summary states,
  such as `Any enabled state`, and explain independent windows that can coexist.
- One row has one destination. Split conditional destinations; do not put "A or B" or
  "A then B" in Next state. Retain meaningful self-transitions.
- Put relevant mode, origin, query, selection and completion conditions beside the trigger.
  Keep Save/Cancel and Cancel/Dismiss distinct when their semantics differ, even if they
  return to the same surface.
- Distinguish hidden/resident from disabled/exited, and a draft from a committed/closed surface
  where that distinction changes available actions. Do not create a separate state for
  every data value or copy the entire interaction index into this table.
- Landmarks identify a surface: controls, windows, visibility or lifecycle. They are not
  clipboard/file answers, exact layout outcomes, business-row counts or timing acceptance
  criteria. Do not use the expected business result as observation readiness.
- The map is a route index, not a fixed test sequence. Observe arrival before continuing;
  successful input or a fixed sleep does not prove the destination.

Corroborate branching behavior with source symbols and/or trustworthy live observations.
Keep source-based understanding distinct from live verification; do not claim a rendered
state was observed just because an event handler appears to produce it.

## 5. Control locator and interaction index

Use exactly these four columns, in this order:

```markdown
| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| <verb + target> | <window/page/parent; local prerequisites> | <typed locator or discovery recipe> | <supported operation/helper recipe> |
```

- **Interaction:** one reusable operation, not a checklist item or complete test. Name the
  intent with a verb; split a broad capability when its actions have different controls.
- **UI state & scope:** identify the current window/page and actual parent row, group or
  popup. Include local prerequisites such as expansion or a mode that enables the control.
  Link the state map for the full navigation path instead of duplicating it.
- **Control locator:** distinguish `AutomationId`, `ControlType`, accessible `Name` and
  parent relationships. An AutomationId is not a globally unique CSS selector; repeated
  templates still need a unique owner. XAML `x:Uid` resource keys are not AutomationIds.
  Confirm which source names are actually exposed in the runtime UIA tree.
- **How to interact:** distinguish Invoke, Select, SetValue, physical click/key input and
  commit/cancel steps. A control's type/name alone does not prove a supported UIA pattern.
  Include an exact runtime-discovery method where needed, not simply "find a control".

Verify each operation against the applicable control/handler and the helper/CLI contract
actually available at the candidate revision. Use live observations to establish provider
behavior where source alone is insufficient; record remaining discovery work honestly.
Do not import another worktree's APIs merely because an example uses them.

Use prose/helper names plus a linked recipe for complex operations. Any shown executable
call template must include required parameters and explain how runtime variables are
resolved. Do not present a partial command as runnable. For non-UI operations, explicitly
identify the actual file/process/event target rather than inventing a UI locator.

Input parameters such as the requested width/format are allowed; fixed test inputs and
expected outcomes belong in the checklist. Re-resolve identities after navigation,
reordering, popup recreation or lifecycle changes.

### Read-out notes and observation rules

Keep result-reading methods and persisted-field mappings below the table, not in an
additional `Observe` column. JSON paths such as `properties.<key>.value` are data addresses,
not UI selectors; check each property's actual shape rather than assuming a wrapper.

Separate accessible labels from actual values, UI drafts from persistence, and stored
settings from downstream behavior. State how to establish usable observations and retain
missing/ambiguous/unsupported/read-error evidence without substituting empty/false defaults.
Link shared capture/input contracts; do not duplicate complete generic harness mechanics.

## 6. Troubleshooting

Use exactly these three columns, in this order:

```markdown
| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| <observed symptom and context> | <scoped checks; authorized recovery or link> | <what the evidence does and does not establish> |
```

- Diagnose from a concrete symptom and its applicable state, build, provider and fixture
  conditions. Do not make a permanent BLOCKED list from one run's unavailable environment.
- Preserve original actions, errors and observations. Recovery needs authorization and a
  restoration plan; restart, elevation, re-navigation or an alternate trigger must not
  silently replace the assertion or erase its original result.
- Distinguish expected absence, missing prerequisites, unavailable observation and observed
  incorrect behavior. Required availability can fail only with a valid claim, established
  premises and trustworthy observation. Unexecuted dependent actions have no independent
  product outcome; `NOT-OBSERVED` is not automatically the same as `BLOCKED`.
- Keep verdict vocabulary/mapping in the selected engine/harness. A row or an error code
  alone must not predetermine FAIL/BLOCKED or authorize repeated mutation.
- Link detailed interaction, read-out and restoration recipes to their owning sections.
  Put generic import/driver mechanics in shared helper documentation.
- Retain durable conditions and source references, not historical HWNDs, DPI measurements,
  tool-version anecdotes or a copied troubleshooting transcript. Distinguish DIP sizing
  from physical screen-coordinate contracts; do not invent a universal scale correction.

## 7. Fixtures and restoration

Use these H3 subsections:

- `Resource inventory` - required.
- `Helper boundaries` - include when an API's actual coverage or limitations matter.
- `Restoration order` - required.
- `Restoration verification` - required.
- `Execution notes` - optional module-specific planning guidance.

Resource inventory uses exactly these five columns, in this order:

```markdown
| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| <resource; preparation helper/recipe> | <selected cases> | <owner/lifetime/original state> | <release or restore procedure> | <baseline-relative completion evidence> |
```

- Inventory only resources needed by the selected scope, including indirectly changed
  sidecars, directories, companions and startup writes. Give a preparation/helper reference,
  not only a noun such as "test window".
- Declare case-owned versus shared run-owned lifetimes. Capture original existence,
  contents/values and actual identities before mutation; keep the original run baseline
  across retries and reset case mutations between uses of shared setup.
- Delete only owned new resources; restore existing resources to the captured state, not
  factory defaults, unchecked controls or a presumed integrity level. Never infer ownership
  from a snapshot, filename, familiar content or a process name.
- Declare semantic versus byte-exact comparison before mutation. Preserve behavioral order
  where relevant; semantic equality does not waive a byte-level guard conflict.
- Describe real helper coverage and caller obligations. A process tracker is not a settings
  restore; a snapshot is not an atomic conflict guard; an existing-file guard cannot restore
  original absence. Do not fabricate a receipt/API or pre-create a missing file to bypass
  that boundary. Return repairable core gaps to Author work under execution readiness.
- State the module's ordering dependencies: owned input, clipboard/provider lifetime,
  quiescent writers, rollback, original enablement, required startup and final UI restoration.
  Do not apply a universal kill/restore/restart sequence.
- Treat any required final restart as a mutation with owned effects. Verify after the last
  writer/startup operation; do not refresh a cache after declaring final restoration.
  If disk baseline and required running/cache state cannot both be restored, report the
  limitation rather than looping restarts or weakening the baseline.
- Completion requires actual baseline-relative evidence, not just helper return counts.
  Preserve unknown external changes and report conflicts, partial restoration and retained
  differences. The Verification column checks cleanup, not product-test answers.

Execution notes can explain fixture reuse and module-specific dependencies, but are not
a fixed test order. Observation/capture mechanics stay under the interaction index or in
shared references rather than being mixed into this top-level restoration section.

## 8. References and accepted presentation variants

Keep reference material last. Prefer `## References` for a new combined container with
`### Source citations` and, when present, `### Visual references`.
The aligned source-only `## Source citations` and existing combined
`## Source citations and visual references` forms are also accepted. Use only one final
container; do not invent further aliases or move it between operating sections.

Cite source by file plus symbol, normally repository-relative. Module-relative or skill-relative
paths are also valid when their root is explicitly identified; avoid ambiguous bare filenames.
A line is only a revision-specific hint. Use portable links to approved visual indexes/assets,
not private archive paths.
Visual landmarks help recognize a state; they do not prove timing, persistence or exact
pixels. Follow [visual-reference acceptance](visual-references.md) separately; absence of
an accepted image does not itself prohibit collecting observations or testing a clear claim.

Do not copy a full historical run, PASS labels, raw settings, clipboard payloads, transcripts
or machine-specific recovery data into the profile. Keep those in the appropriate private
run/authoring records.

## 9. Author review gate

Run this review on the actual candidate, not an older example. Do not label a candidate
conforming or ready for confirmation until all applicable checks are satisfied:

- [ ] Exact core H2 names and order; Entry paths is second; conditional omissions justified.
- [ ] Every applicable contracted table has the exact header/order, nonempty grounded rows and no added
      row-number, checklist-line, expected-result or control-index Observe columns.
- [ ] State names/guards are coherent; each transition has one destination and structural landmarks.
- [ ] Control operations have usable scopes/locators and corroborated actions/commit semantics;
      helper APIs and required parameters exist in the selected candidate.
- [ ] Read-out paths are separated from UI locators and distinguish draft/persisted/runtime facts.
- [ ] Troubleshooting preserves original evidence and uses conditional interpretation, not canned verdicts.
- [ ] Restoration inventories ownership/lifetimes and indirect writes, states actual helper limits,
      defines safe ordering and checks the original baseline after final writes/startup.
- [ ] References, anchors and helper/recipe links resolve; no stale heading aliases remain.
- [ ] No unfilled scaffold, fabricated selectors/APIs, copied private/run-specific data or claimed
      live validation based only on source/format checks.
- [ ] Changes to helpers or behavioral advice have the relevant mechanical/observation evidence;
      format conformance is recorded separately from execution readiness and product outcomes.

Retain a short review receipt with the Author's round records, not in the module profile:

```text
Candidate profile path and SHA256:
Format contract path and SHA256:
Conditional omissions and basis:
Structure/table/link checks:
Locator/action corroboration and helper validation:
Restoration and diagnostic-boundary review:
Remaining format/content/readiness gaps:
Format result: conforming / needs-author-work
```

A conforming document can still expose a product failure or lack execution readiness.
A discovery-stage commit is not an accepted profile. Preserve those distinctions and use
[execution readiness](execution-readiness.md) before dispatching a confirmation.
