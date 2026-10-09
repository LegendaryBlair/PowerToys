# Module checklist format contract

Use this format for every new or revised module checklist. It follows the Workspaces
structure: **Legend -> brief Fixtures & conventions -> cases grouped by function**.
This contract is self-contained; do not retrieve an excluded profile or another worktree's
engine merely to copy its presentation.

## 1. Keep the document roles separate

| Material | What belongs here |
|---|---|
| Checklist | What to prepare, what the user does, and what must be observed; concise per-case prerequisites |
| Assertion inventory | Stable scenario/child IDs, independently reportable expectations and matrix conditions |
| Module profile / fixture guide | How to drive controls, use helpers, establish ownership, observe safely and restore exact state |
| Author/run input records | Source wording/references/hashes, PR analysis, inclusion evidence, review decisions and historical comparisons |

Source analysis is still required. Retain it in the existing Author/input records, not as
another narrative the Runner must work through before reaching the cases. A short per-case
source reference is acceptable when useful; it is not a second test or a required history dump.

Do **not** generate checklist sections named or serving the purpose of:

- `Provenance and applicability`
- `Original baseline (unaltered wording)`
- `PR disposition map`
- `Coverage accounting`

Do not create a source appendix solely to relocate those sections. Preserve the unchanged
external source and its identity through the existing input-record mechanism. Actual
version/locale/elevation conditions remain beside the affected cases; removing the history
section must not remove an execution prerequisite.

## 2. Headings and readable cases

Write to the selected engine's checklist location, normally
`.github\skills\powertoys-verification\references\release-checklist\<module>.md`.

Use an identifying H1, `## Legend`, a short `## Fixtures & conventions`, then
`## <Module> (<N> items)` with H3 functional categories. Choose categories meaningful to
the module, such as Settings and entry points, Profiles, PATH, Input validation and limits,
Command Palette integration, or Appearance and localization. Omit irrelevant categories.

Do not use `Canonical execution inventory`, `Draft validation matrices`, or
`Entry points and conditional coverage` as the organizing headings. They are authoring
abstractions, not three execution stages. Group the underlying cases by user-visible function.
Functional order is a reading aid, not permission to ignore each case's starting state.

Each checkbox should read as a concise user flow with explicit outcomes:

```markdown
# <Module> - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - standard-user coverage, subject to the stated fixtures.
- `[ADMIN: YES]` - requires authorized elevation.
- `[ADMIN: COND]` - retain non-admin and elevated variants separately.
- `[ID: ...]` - stable case identifier used by the inventory and report.

## Fixtures & conventions

- Use disposable, collision-checked data and preserve the original affected state.
- Restore and verify that state afterward; do not close pre-existing user windows.
- See the module profile and fixture guide for the detailed operating and cleanup APIs.

## <Module> (<N> items)

### User variables

- [ ] **User variable CRUD** [ID: <MODULE>-USER-CRUD] [ADMIN: NO]
  Add an owned variable with value `one`, edit it to `two`, then delete it. After each
  transition, independently check its exact value or absence in every required UI/storage
  surface. Editing must not introduce duplicates; deletion means absent, not empty.
```

Retain stable case IDs for report lookup, using the candidate engine's supported notation.
Keep required recorder metadata, such as Clarity, in its supported inventory/input contract;
do not repeat default labels in the prose unless the engine requires them.
Avoid a separate `Sources` paragraph and a long child-ID list under every checkbox.

## 3. Summarize safety, do not duplicate the profile

Keep only the module's critical preparation conventions in the checklist: owned test data,
affected original state to preserve, required observation surfaces, privacy boundaries and
restoration obligations. Link the profile/fixture guide for the mechanics.

Do not copy helper API catalogs, snapshot code, complete file inventories, recovery recipes
or recorder instructions into this section. Conversely, do not remove safety requirements
merely to shorten the document. For a profile-absent R0, reference the available shared
guidance and provide the actual executable fixture plan in the neutral Runner packet;
do not link to a nonexistent mature profile.

## 4. Keep detailed assertions in the inventory

Follow the Workspaces split: readable case paragraphs in Markdown, explicit child IDs and
descriptions in a versioned assertion inventory. Do not print the full machine-oriented
child list a second time in the checklist.

Reuse the candidate engine's inventory schema/loader when available. The conventional
location is `references\assertion-inventories\<module>.json` under that engine. If the base
lacks an inventory loader, use its actual explicit-Items contract and prepare a minimal,
reviewed adapter for the same checked-in definitions. Do not invent an available API,
import a different WIP harness, or create another execution/reporting framework.

The prose must still express every requirement; the inventory is a decomposition, not a
place to hide additional tests. Preserve scenario/child IDs, distinct fixtures, prerequisites,
observation surfaces, expected outcomes and case membership when only reformatting.
Reorder the inventory consistently with the functional checklist. Update the supported
revision/hash metadata and verify the before/after mapping; do not reinterpret old archives.

For parameterized validation, keep one compact input/expectation table near its functional
cases. Define fields/surfaces, boundary pairs and exceptions explicitly. A child may aggregate
data rows only when every specified row is still observed; a representative sample cannot
replace a required matrix. Keep ordinary/elevated scopes and different initial-state
semantics independently reportable rather than allowing an unavailable variant to obscure
completed ordinary coverage.

## 5. Author review gate

Before the input checkpoint and after each checklist revision, confirm:

- The reader reaches functional cases after a short legend and critical fixture summary.
- The prohibited history/audit sections are absent, with no replacement source appendix.
- Every checkbox states action and expected behavior, with its actual prerequisites nearby.
- Detailed operating/restoration instructions are linked rather than duplicated.
- The Markdown and explicit inventory agree; no source requirement, condition or observation
  surface was lost or silently added during regrouping.
- Shared matrix rows remain concrete; no duplicate coverage or hidden optional assertions.
- Inventory IDs/descriptions and source hash/revision are consistent, and links resolve in
  the candidate worktree. Formatting alone does not advance a live-validation claim.

Retain the review result with existing Author round records. This is an automatic Author
check, not an additional human approval gate or proof that the Runner can execute the cases.
