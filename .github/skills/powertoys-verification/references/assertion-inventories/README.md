# Frozen module assertion inventories

Every supplied module checklist has a reviewed, versioned Scenario A inventory:

| Module | Revision | Scenarios | Required children |
|---|---|---|---|
| Advanced Paste | 1 | 29 | 32 |
| Color Picker | 2 | 17 | 25 |
| Crop And Lock | 1 | 13 | 14 |
| Environment Variables | 3 | 29 | 135 |
| File Locksmith | 2 | 10 | 10 |
| Image Resizer | 1 | 12 | 18 |
| Keyboard Manager | 2 | 24 | 135 |
| New+ | 1 | 9 | 9 |
| Peek | 1 | 18 | 18 |
| Power Display | 1 | 33 | 138 |
| PowerRename | 2 | 16 | 17 |
| PowerToys Settings | 4 | 25 | 50 |
| Quick Accent | 2 | 18 | 57 |
| Shortcut Guide | 3 | 19 | 96 |
| Workspaces | 2 | 38 | 72 |
| ZoomIt | 1 | 39 | 39 |

`Import-PtAssertionInventory` validates schema, revision, source SHA256, scenario coverage,
IDs, nonempty descriptions and retention of named source assertions. The hash is over
UTF-8 checklist text with CRLF normalized to LF, not over a generated run script.
The loader never creates IDs based on a driver's grouping. The full source block remains
each scenario's description, including parameter matrices, setup and restoration requirements.

All current definitions are explicit `{Id, Description}` objects. Legacy string children
remain readable for recorded old inputs, but new checklists do not repeat the detailed child
list in Markdown. A child covering several required inputs passes only after **all** those
inputs are observed. Keep individual parameter observations even when they share one child.
`Sources` on new definitions retains original requirement aliases where supplied; it is
provenance, not a substitute for observing the described behavior.

Quick Accent revision 2 groups arrow/Space activation under `QA-ARROWS` and short-list
descriptions/overflow visibility under `QA-DESCRIPTIONS`, with 18 scenarios and all 57
original child IDs and descriptions retained. `PreviousScenarioIds` records both mappings.
Trigger paths and description-off/on observations for each list size remain independent.
Historical reports are unchanged.
Each conditional prerequisite is part of that child's Description, not an optional flag.
The source hash binds the complete input/Unicode matrices; the shared template requires
the original Items, ResourcePlan and CleanupPlan.

Settings revision 4 groups Home/Quick Access sorting under `SET-DASHBOARD-SORT` and
secondary-window return/lifetime under `SET-WHATS-NEW-ENTRY`. Their original children and
descriptions remain independent, including both sorting surfaces, distinct reopen boundaries,
Home/General entry origins and process lifetime. The standalone `SET-RESTART-MEDIUM` scenario
is covered by its retained child in `SET-LOCALIZATION`, where the actual language-change
Restart supplies the entry path. `PreviousScenarioIds` records all three mappings;
all 50 child IDs remain.
The diagnostic-package policy case now names the visible Diagnostic data/Generate package
controls and restores the original policy state, rather than requiring an unmanaged result.
Historical reports are unchanged.

Settings reports navigation details, all 12
attribution pages, opposite/live theme conditions, immediate update-check isolation and
shortcut-conflict startup as independent children. Static/reopened theme observations and
final restoration cannot replace live-window transitions or pre-cleanup isolation evidence.

Color Picker revision 2 and Shortcut Guide revision 2 move the original named expectations
into JSON without changing child IDs or scenario membership. Workspaces revision 2 merges
WS14/WS15 and WS17/WS18 under WS14 and WS17, retaining all 72 child IDs/descriptions.
`PreviousScenarioIds` records those two case mappings. Other scenario IDs are not renumbered.
The nine new inventories retain each original checkbox as a required child, including the
independent constituents of merged workflows. Their initial counts are not comparable to
ad-hoc child groupings from earlier reports.

PowerRename revision 2 corrects unchanged Titlecase preview to an empty/no-op row.
File Locksmith revision 2 expects independently established locking PIDs rather than a
fixed installer process count. Shortcut Guide revision 3 expects the physical work-area
host rectangle, not full monitor bounds. IDs/counts are retained; these corrected
expectations apply to new run inputs and do not rescore old checklist failures.

Environment Variables follows the Workspaces layout: functional prose cases in Markdown,
explicit child IDs/descriptions here. Revision 3 changes presentation and order only:
all 29 scenario IDs, 135 child IDs and their expectations are retained from revision 2,
without Markdown label wrappers in child descriptions. The shared input table in the
checklist defines P01/P02/P04 matrix rows; each surface/input still needs an observation.
Non-admin/System input scopes and originally-absent/existing-value applied edits remain
separate. Historical reports are not relabeled or rescored.

The 72/96 counts are the first **checked-in mapping revision**, not inferred loss/improvement
relative to the old run-local 120/103/115 child groupings. Historical archives remain unchanged.
Compare old/new requirements by source text and actual observations, not child count or
ordinal correspondence. No old verdict/evidence is copied into the new inventories.

Keyboard Manager retains the classic editor's Type/hold-Enter/hold-Esc
conditions separately from the unified new editor. Its remapping matrices retain
tap/hold and modifier-release-order requirements; additional app, elevation, locale,
DSC and diagnostic conditions are not implied by a bounded ordinary-key run.
Revision 2 preserves all 135 IDs/descriptions and removes an unnecessary clipboard-backup
prerequisite only for builds independently established to insert text directly.
Actual paste and clipboard-based text paths still require complete preservation.

```powershell
$inventory = Import-PtAssertionInventory `
    -InventoryPath "$skill\references\assertion-inventories\workspaces.json" `
    -ChecklistPath "$skill\references\release-checklist\workspaces.md"
$items = $inventory.Items
# Pass Items to the existing run/template; record both input files.
```

Power Display revision 1 derives its 33 scenarios and 138 children from included merged
PR claims, not a missing release-baseline section. Hardware, recovery, migration,
policy and elevated conditions remain separate from bounded flyout/CLI discovery.
The inventory does not include unshipped VCP restrictions, the reverted diagnostics-copy
button or a proposed Command Palette integration. See the [fixture boundaries](../power-display-fixtures.md).

The thin template rejects different run-local Items for all 16 Scenario A modules
and snapshots both source files. Direct recorder callers must record both as inputs too.
Only Color Picker, Workspaces, Shortcut Guide, Environment Variables and Quick Accent currently require
the aligned `ResourcePlan`/`CleanupPlan` integration. Adding an inventory does not certify
another profile's ownership/restoration implementation or silently impose that adapter on it.
Change the mapping only through review: increment `Revision`, retain stable IDs where
meaning is unchanged, document semantic splits/merges, and update the source hash when
the checklist changes. Rebuilding an inventory to conceal missing coverage is not review.

`color-picker-cielab-fixture.json` supplies the independent CP16 near-gray input
`RGB(128,128,127)`. Its negative, greater-than-minus-half Lab `a` component rounds to
integer `0`, not `-0`; red/white-only samples cannot exercise that branch.
`Test-PtAssertionInventory.ps1` independently computes sRGB/D65 Lab to check the fixture
and checks deterministic IDs, counts, newline tolerance and invalid-input rejection.

Use the recorder's producing attempt and observation sequence for delayed review.
Inventories do not relax its cross-attempt evidence, diagnostic or archive-integrity gates.
