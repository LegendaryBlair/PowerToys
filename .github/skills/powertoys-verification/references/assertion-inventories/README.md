# Frozen module assertion inventories

New Scenario A runs for the three aligned profiles use these reviewed, versioned files:

| Module | Revision | Scenarios | Required children |
|---|---|---|---|
| Color Picker | 1 | 17 | 25 |
| Workspaces | 1 | 40 | 72 |
| Shortcut Guide | 1 | 19 | 96 |

`Import-PtAssertionInventory` validates schema, revision, source SHA256, scenario coverage,
IDs, nonempty descriptions and retention of named source assertions. The hash is over
UTF-8 checklist text with CRLF normalized to LF, not over a generated run script.
The loader never creates IDs based on a driver's grouping. The full source block remains
each scenario's description, including parameter matrices, setup and restoration requirements.

String children resolve exact named checklist assertions; object children explicitly split
legacy prose. A child covering several required inputs passes only after **all** those inputs
are observed. Keep individual parameter observations even when they share one source child.
Color Picker CP01-CP25 and the existing named SG assertions retain their source IDs.
Workspaces and SG prose children now have explicit descriptive IDs.

The 72/96 counts are the first **checked-in mapping revision**, not inferred loss/improvement
relative to the old run-local 120/103/115 child groupings. Historical archives remain unchanged.
Compare old/new requirements by source text and actual observations, not child count or
ordinal correspondence. No old verdict/evidence is copied into the new inventories.

```powershell
$inventory = Import-PtAssertionInventory `
    -InventoryPath "$skill\references\assertion-inventories\workspaces.json" `
    -ChecklistPath "$skill\references\release-checklist\workspaces.md"
$items = $inventory.Items
# Pass Items to the existing run/template; record both input files.
```

The thin template rejects different run-local Items for these three Scenario A modules
and snapshots both source files. Direct recorder callers must record both as inputs too.
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
