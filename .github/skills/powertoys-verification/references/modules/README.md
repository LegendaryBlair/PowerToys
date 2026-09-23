# Per-module verification profiles (`references/modules/`)

This folder holds **one focused profile per PowerToys module**: bootstrap facts, entry paths, state/control maps, troubleshooting, ownership/restoration and source/visual references.

## When to read

When this skill runs for a specific module, check whether `references/modules/<module>.md` exists here. If yes: **read it BEFORE walking the SKILL.md drive-stack** — it supplies the module-specific routes, operations and diagnostic boundaries.

If no profile exists, fall back to SKILL.md + the helper scripts.

For the complete checklist -> fresh-session execution -> profile/local-commit -> improvement/confirmation
workflow, use [powertoys-profile-authoring](../../../powertoys-profile-authoring/SKILL.md).
In that workflow the Runner returns observations and gaps without editing the tested materials; the Author
owns profile/helper changes. A standalone verification request retains the normal maintenance guidance below.

## Shared cross-module flows

Some flows are common to several modules and live in their own top-level docs (not per-module):
- **`../references/explorer-context-menu-flow.md`** — driving the real Win11 Explorer right-click context menu end-to-end (open + assert present/absent + launch). Referenced by File Locksmith and any future **Image Resizer / PowerRename / New+** profiles.

## Why per-module (not just one big SKILL.md)

- Each module has its own quirks (Peek's `_isFromCli` guard, CmdPal's TextChanged-broken state, PT Run's mini-popup HWND, Workspaces' snapshot-elevation rules). Bundling all of them into the global SKILL.md bloats context and forces every verification to load 25+ KB of mostly-irrelevant text.
- A profile lets a focused verification run with only the relevant 5-10 KB.
- New gotchas discovered during a module verification round get added to that module's profile, not the global one — keeps the global doc stable.

## Profile catalog

| Module | Profile | Status |
|---|---|---|
| Peek | `peek.md` | ✅ written 2026-06-08 |
| File Locksmith | `file-locksmith.md` | ✅ written 2026-06-08 |
| Image Resizer | `image-resizer.md` | ✅ written 2026-06-09 |
| PowerRename | `power-rename.md` | ✅ written 2026-06-10; **reworked 2026-07-08** — recipe reduced to *capability → control* + a Read-out notes block, self-contradiction &amp; meta-hedges removed. Rows 4–12 are author-derived (control IDs discover-at-runtime); confirm on the next live run |
| New+ | `new-plus.md` | ✅ written 2026-06-18 (registration-gate for menu presence; Settings-UI toggle drives template auto-copy) |
| Command Palette | `command-palette.md` | ✅ written 2026-07-07 (CmdPal AppX foreground-lock / TextChanged-broken / alias-keystroke / Esc-filtered quirks — moved out of the global SKILL.md pitfalls) |
| (other modules to be added as we encounter sign-off needs) | — | — |

## For Explorer-context-menu modules: read the canonical flow doc first

If you're writing a profile for a module that registers an entry in Explorer's Win11 right-click menu (PowerRename, File Locksmith, Image Resizer, New+, Preview Pane, RegistryPreview), **read `../references/explorer-context-menu-flow.md` first**. It has the canonical synthetic-right-click + UIA-invoke recipe with:

- Which-approach-first decision rule (CLI back-door vs synthetic menu, with the false-positive trap warning)
- Stability rules (UIA InvokePattern, retry on first right-click)
- Recipe (robust 5-step flow)
- Multi-file selection notes
- Module captions table (per-module menu-item display names)
- Common failure modes
- The unlocked-desktop requirement (BLK-ENV gating)

The shared helper is `scripts/pt-explorer-contextmenu.ps1` (`Test-PtDesktopInteractive`, `Open-PtExplorerContextMenu`, `Invoke-PtContextMenuItem`, `Get-PtContextMenuItems`).

Your module profile then documents only the **module-specific** controls, settings read-outs, entry conditions, troubleshooting and source references.

Existing profiles such as `power-rename.md` can provide allowed behavioral examples, but legacy headings or
tables in them are not the output schema. Keep generic mechanics in the shared flow documentation.

## Profile template

The [module profile format contract](../../../powertoys-profile-authoring/references/module-profile-format.md)
is the single normative schema for new/refined profiles. Read its exact table headers, section boundaries,
conditional-presence rules and review gate; do not reconstruct a schema from an older profile or this catalog.

Required core sections are **Module facts**, **Entry paths**, **Control locator and interaction index** and
**Troubleshooting**. Add **UI state-transition map**, **Fixtures and restoration** and a final reference
container whenever their contract conditions apply. Entry paths is always second; state maps precede the
interaction index, troubleshooting follows it, and restoration/reference sections come afterward.

The contract supplies the state (four-column), interaction (four-column), troubleshooting (three-column)
and resource-inventory (five-column) schemas. Bootstrap facts and final reference containers retain only
the presentation variants explicitly allowed there.

Use the [Author review gate](../../../powertoys-profile-authoring/references/module-profile-format.md#9-author-review-gate)
before calling an authored/refined candidate conforming. This does not add a profile requirement to the
initial profile-absent discovery run or turn format checks into proof of runtime behavior.

## Hygiene

- **Follow the format contract, not legacy aliases.** Omit only genuinely inapplicable conditional sections; do not insert empty `None` sections or invent rows to fill a table. Record unresolved discovery work separately.
- **Keep the profile focused.** Link shared mechanics, detailed helper recipes and visual indexes instead of copying them. Do not remove ownership, diagnostic boundaries or scoped operations merely to meet an arbitrary byte target.
- **Keep claims separate from operating knowledge.** The checklist owns test inputs and expected outcomes. Put UI locators/actions in the interaction index, data/read-out mappings below it, and baseline-relative cleanup checks in restoration.
- **Use interaction/state/resource keys, not checklist line numbers.** Upstream `L<n>` references drift; source citations should prefer file plus symbol. Runtime identities must be rediscovered.
- **Cite source by file + symbol** (e.g. `Settings.cpp CSettings::Load`) where module behavior surprises (CLI guards, debounce timings, fallback chains) so reviewers can verify — symbols survive refactors, bare line numbers rot.
- **Update the profile after every verification round**; promote any new technique into the right helper script if it generalizes beyond this module.

## Filling a profile: provenance & keeping it fresh

Profiles are written by an agent and may sit unreviewed, so a hallucination can read exactly like a verified truth (that's how `power-rename.md` ended up telling agents to read a non-existent HKCR `Icon` value, contradicting its own "modern-menu-only on Win11" thesis). Guard against that with **content discipline, not hedges.**

**1. State a fact, or give the discovery instruction — never hedge.** If a value is confirmed, state it plainly. If it's a guess or *volatile* (changes per launch/build — e.g. PowerRename's per-launch `txt-textbox-XXXX` IDs), **don't write the guessed value at all** — write the runtime-discovery instruction instead ("discover the AutomationId at runtime by name/role"). **Do NOT** add `[UNVERIFIED] — confirm yourself` tags, "review notes", or any commentary about the doc's own reliability: it doesn't help the consuming agent (which re-checks at runtime anyway) and makes it distrust otherwise-good content. If something's wrong, fix it; if it's uncertain, turn it into a discovery instruction.

**2. Fill from evidence, not speculation.** Don't AI-generate a whole profile up front (that's what produced the HKCR hallucination). **Seed** a thin one (metadata + a source scan for durable facts), then let **each run add** the controls/keys it actually confirmed, correct anything that failed, and promote durable troubleshooting guidance from that run's retrospective. The profile grows *out of* runs.

**3. Durable vs volatile.** Durable facts (settings-file path, "modern-menu-only on Win11", the two-settings-files gotcha) belong here as plain statements. Volatile facts (per-launch/per-build IDs, layout) are **discovered at runtime**, never pinned.

**4. State each fact once.** Duplication is the #1 staleness amplifier: when a fact lives in the interaction table, an entry path and several troubleshooting rows, one edit leaves the others stale. Shared mechanics belong in the shared flow doc; everything else cross-references its owning section.

**5. Prefer symbol over line for source citations.** `Settings.cpp CSettings::Load` survives a refactor; `Settings.cpp:307` rots on the next edit. A line number is fine only as an *as-of-build* hint.

**6. Content validity.** Maintain instructions against current controls, settings, helpers and relevant UI-stack differences. A date or release count alone proves neither validity nor staleness. Keep actual tested artifact identities and run history in the archive/Author record; never advance a live-verification stamp after only a source or formatting review, or copy another run's stamp into a new profile. Runtime discovery can flag content that needs review.
