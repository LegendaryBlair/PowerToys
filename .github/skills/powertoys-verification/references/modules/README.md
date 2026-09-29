# Per-module verification profiles (`references/modules/`)

This folder holds **one short profile per PowerToys module**. Each profile is self-contained guidance specific to that module — paths, entry-paths, capability/control recipes, troubleshooting, fixture lists, source citations.

## When to read

When this skill runs for a specific module, check whether `references/modules/<module>.md` exists here. If yes: **read it BEFORE walking the SKILL.md drive-stack** — it tells you which entry-paths actually work for this module's quirks and how to diagnose module-specific pitfalls.

If no profile exists, fall back to SKILL.md + the helper scripts.

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
| Color Picker | `color-picker.md` | Shared WIP harness baseline; WinUI profile and 25-assertion checklist migrated from the Color Picker branch |
| Workspaces | `workspaces.md` | ✅ written 2026-08-12 (bottom-up automation profile plus an embedded top-down human workflow and sanitized visual landmarks) |
| PowerToys Settings | `settings.md` | ✅ written 2026-08-14 (Settings/Quick Access state transitions, restart-safe recipes, backup picker flow, update/elevation blocks, and verified product quirks) |
| Shortcut Guide | `shortcut-guide.md` | ✅ written 2026-08-21 (app-aware manifests, Windows-key modes, overlay lifecycle, search/pinning, localization and CmdPal traps) |
| ZoomIt | `zoomit.md` | ✅ written 2026-08-19 (hosted events, registry-backed settings, recording flows, input-blocking overlays, and hardware/drag constraints) |
| Crop And Lock | `crop-and-lock.md` | ✅ written 2026-08-19 (mode events, selector lifecycle, shortcut persistence, crop creation, and real-drag constraints) |
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

Your module profile then only documents the **module-specific** quirks: settings.json schema keys, expected verb caption regex, capability/control recipes, source citations, ceiling.

`power-rename.md` is the model — ~9 KB despite covering 18 items because the generic mechanics live in the canonical flow doc.

## Profile template

A profile holds **only module-specific logic** an agent can't infer from the SKILL engine. It has **4 required sections + 3 optional**. Do NOT pad it with sections that have no content — omit them. No Ceiling/Don'ts sections: a PASS-rate number drifts every release; express actionable pitfalls with their conditions and interpretation boundaries in Troubleshooting.

**Required (always):** ① Module facts · ② Entry paths · ③ Control locator and interaction index · ④ Troubleshooting.
**Optional (include only if non-empty):** UI state-transition map · Fixtures and restoration · Source citations.

```markdown
# <Module> — module verification profile

## Module facts                    # ① REQUIRED — bootstrap facts; omit inapplicable fields
**PT module**: `<ModuleKey>` (one-line description)
**Source**: `src\modules\<dir>\`
**Settings file**: `%LOCALAPPDATA%\Microsoft\PowerToys\<dir>\settings.json`
**Exe**: `<full path>`
**Default hotkey**: `<keys>` (+ settings ActivationShortcut path)
**Named Event**: `Local\<name>` (friendly name in pt-shared-events.ps1 catalog)
**DSC resource**: `Microsoft.PowerToys/<Name>Settings`

## Entry paths                     # ② REQUIRED — immediately after Module facts
Before entry/mutation, complete the module's snapshot and ownership prerequisites.
Link to the detailed fixture/restoration rules rather than repeating them here.
### <assertion type>  <code + when to use + source citation>
# Order alternatives by reliability within the same assertion; do not replace a keyboard-binding
# test with a Named Event that bypasses the binding.

## UI state-transition map            # OPTIONAL — only for a multi-screen/non-obvious state machine
| Current state | Trigger / condition | Next state | State landmarks |
|---|---|---|---|
| <named source state> | <event/control; applicable condition> | <one named destination> | <window/control/lifecycle cues identifying that state> |

> Choose a row from the observed current state; this is not a fixed test sequence.
> Split conditional destinations into separate rows. Detailed actions belong in the interaction index.

## Control locator and interaction index   # ③ REQUIRED — an operating map, not an answer key
| Interaction | UI state & scope | Control locator | How to interact |
|---|---|---|---|
| <verb + target> | <window/page/parent and local prerequisites> | <typed UIA properties or runtime discovery recipe> | <supported operation or linked helper recipe> |

> Mapping: read item → find interaction → establish scope → resolve control → act.
> Test values and expected results come from the checklist, not this index.

### Read-out notes
- <where/how to read current or persisted state; settings field paths are data, not UI selectors>

## Troubleshooting                   # ④ REQUIRED — diagnose without predetermining the verdict
Preserve the original action/observations. Recovery needs authorization and restoration,
and must not silently change the assertion's entry path or erase a prior failure.

| Symptom / condition | Diagnose / recover | Interpretation boundary |
|---|---|---|
| <observable symptom and relevant context> | <scoped checks, applicable recovery or recipe link> | <what these observations establish or cannot establish; missing prerequisites vs behavior/observer failure> |

## Fixtures and restoration           # OPTIONAL — when cases create resources or mutate state
Declare case-owned versus shared run-owned lifetimes and the original existence/values
before mutation. Specify semantic or byte-exact file comparison up front.

### Resource inventory
| Fixture / resource | When needed | Ownership & baseline | Cleanup / restore | Verification |
|---|---|---|---|---|
| <resource and preparation helper/recipe> | <selected cases that need it> | <owner, lifetime, original existence/value/identity> | <release new resources or restore existing ones> | <baseline-relative completion evidence> |

### Helper boundaries
<What the actual helpers restore; caller responsibilities, conflicts and unsupported resources.>

### Restoration order
1. <Module-specific ordering: owned input, clipboard providers, writers, rollback, required startup and UI state.>

### Restoration verification
- <Original resources match their declared baseline; owned new resources are gone; conflicts/partial cleanup remain explicit.>

### Execution notes                  # OPTIONAL — omit if no module-specific planning guidance
<Reuse preparation only within declared lifetimes, not observations or outcomes.>

## Source citations                   # OPTIONAL — PT-repo file:line for surprising behavior (else inline in traps)
```

## Hygiene

- **4 required + 3 optional sections only** (Module facts · Entry paths · control/interaction index · Troubleshooting; UI state-transition map, fixtures, and source citations if non-empty). No Ceiling, no Don'ts — fold actionable pitfalls into Troubleshooting. Omit empty sections rather than writing "None".
- **Put `Entry paths` second, immediately after `Module facts`.** Explain when/how to use each entry and its destination or state-map reference. Choose by the behavior under test, not a global fastest-first order. Keep essential safety/readiness reminders here with links to detailed rules; put recorder mechanics in the interaction index and snapshot/rollback details in restoration guidance. Module-specific execution suggestions belong with fixtures, not in the entry sequence.
- **Keep each profile under ~10 KB, or ~12 KB when it includes a visual workflow.** If it grows beyond that, remove duplication or escalate to maintainer review of the upstream checklist.
- **Use four columns for the interaction index:** `Interaction | UI state & scope | Control locator | How to interact`. Each row describes a reusable operation, not a complete test. Keep window/page/parent scope and local prerequisites separate from typed UIA identifiers and the supported action. Use runtime-discovery instructions for volatile controls; do not present XAML resource keys as AutomationIds. Explicitly identify non-UI targets rather than inventing a selector.
- **Verify how to interact against the actual control/handler and helper contract.** Distinguish Invoke, Select, SetValue, physical input and commit actions. A source control name alone does not establish its runtime UIA pattern. Link complex recipes; label command templates and include required parameters. Shared mechanics stay in shared helpers.
- **Do not add fixed test inputs, expected outputs or an `Observe` column.** Operation parameters and prerequisites are allowed; the checklist owns test values and assertions. Put settings-field mappings and where/how to read outcomes in **Read-out notes**, not the UI locator. A UI readback is not proof of persistence or downstream behavior.
- **Tables are interaction-keyed, NOT line-keyed.** Upstream checklist line numbers (`L<n>`) **must not appear** — they drift between releases. PT-source-code citations should prefer **file + symbol** (a line number is fine only as an *as-of-build* hint).
- **Cite source by file + symbol** (e.g. `Settings.cpp CSettings::Load`) where module behavior surprises (CLI guards, debounce timings, fallback chains) so reviewers can verify — symbols survive refactors, bare line numbers rot.
- **Update the profile after every verification round**; promote any new technique into the right helper script if it generalizes beyond this module.

## Optional UI state-transition section

Use the same heading and four columns as the template: `Current state | Trigger / condition |
Next state | State landmarks`. Put this optional section after entry paths and before the
interaction index when authoring a new profile. Build it from source, product documentation,
recordings and live observations, not from a desired PASS path.

- **Name states consistently within a profile.** Group rows by current state. A state describes
  an actionable surface/lifecycle, not each data value; ordinary field edits stay in the
  interaction index. Hidden/resident is not disabled/exited. Define boundary states and any
  summary such as `Any enabled state` explicitly; independent windows can coexist.
- **One guarded transition per row.** Put mode, origin, query, selection or completion
  conditions beside the trigger. Split different destinations into separate rows, not
  "A or B" or "A then B" in the Next state cell. Retain meaningful self-transitions and
  keep Save/Cancel or Cancel/Dismiss distinct even if their destinations match.
- **Landmarks identify the destination, not success of the test.** Use scoped windows,
  controls, visibility and lifecycle cues. Put file/clipboard contents, layout correctness,
  counts and timing acceptance criteria in read-out notes/the checklist. Do not use the
  expected business result as the condition that makes an observation ready.
- **Keep mechanics in the interaction index.** The map chooses the route; the index locates
  and operates its controls. Cite source symbols or actual observations for branching behavior.
  Wait for the destination to be observed; a successful action call or fixed delay is not
  proof of arrival, and failure does not authorize forcing that destination.
- **Visual references remain subordinate.** Crop/redact to module UI, excluding unrelated
  desktop/account/document content. Images recognize states when UIA is insufficient;
  they are not pixel baselines or a substitute for the transition table.

The profile combines the bottom-up **automation map** and top-down **UI state-transition
map**; the release checklist remains the behavioral specification.

## Optional fixtures and restoration section

Use `Fixtures and restoration` with **Resource inventory**, **Restoration order** and
**Restoration verification**; add **Helper boundaries** and **Execution notes** when useful.
The inventory uses the five columns in the template. Its Verification column describes
cleanup evidence, not canned expected results for the product checklist.

- Record only resources required by selected cases. Distinguish case-owned and shared
  run-owned lifetimes, original existence/content/state, actual window/process identity and
  explicitly authorized changes. Keep the initial run baseline across retries.
- Delete only owned new resources; restore pre-existing resources to their original values,
  not factory defaults, unchecked controls or a presumed integrity level. Include generated
  sidecars and resources changed indirectly by startup or companion modules.
- Name the real helper/recipe and its limits. A process tracker is not a settings restore;
  a byte snapshot is not an atomic conflict guard; an existing-file guard does not restore
  absence. If required restoration is unsupported, stop that mutation before it happens
  and continue independent eligible work rather than inventing an API or forcing a write.
- Preserve module-specific ordering. Account for clipboard providers, quiescent writers and
  every required final start/restart; do not standardize on kill/restore/restart. Necessary
  lifecycle restoration is part of the mutation plan, not an action after cleanup is declared.
- Verify after the last planned write/startup/UI restoration against the predeclared semantic
  or byte-level baseline. Retain unknown external changes, conflicts and partial receipts;
  do not weaken the comparison or take a new baseline to turn them into success. Helper
  return counts alone do not establish complete restoration.
- Keep observation mechanics in read-out notes or a supporting observation subsection.
  Execution notes may explain fixture reuse/dependencies, but are not a mandatory full-suite
  schedule. Shared resources still need per-case mutation reset and final release.

## Troubleshooting section

Use `Troubleshooting` after the interaction index and before fixtures, with the three
columns in the template. This is a diagnostic map, not a BLOCKED inventory or answer key.

- Start each row with a concrete symptom/condition. Check current window, state, supported
  build, provider configuration and required fixtures before choosing recovery.
- Preserve original observations and errors. Recovery must be authorized and respect the
  tested route; record diagnostic changes separately. Restart, elevation, re-navigation or
  a different trigger cannot silently replace the assertion or erase its original result.
- Distinguish expected absence, missing prerequisites, unavailable observation and observed
  incorrect behavior. Only valid requirements plus established premises and trustworthy
  observations support a product failure. Limit confirmed obstacles to affected assertions;
  report formats/taxonomy remain owned by the shared engine/harness.
- Link detailed interactions, read-out methods and restoration ordering to their single
  authoritative sections. Put generic driver/import mechanics in shared helper documentation,
  keeping only the module's symptom and link here.
- State durable conditions, not a past run's DPI, HWND, build-specific incident or blanket
  inability. Record current error provenance; an error code alone is not a defect diagnosis.
  Keep coordinate spaces and helper contracts explicit instead of sharing a universal DPI formula.

## Filling a profile: provenance & keeping it fresh

Profiles are written by an agent and may sit unreviewed, so a hallucination can read exactly like a verified truth (that's how `power-rename.md` ended up telling agents to read a non-existent HKCR `Icon` value, contradicting its own "modern-menu-only on Win11" thesis). Guard against that with **content discipline, not hedges.**

**1. State a fact, or give the discovery instruction — never hedge.** If a value is confirmed, state it plainly. If it's a guess or *volatile* (changes per launch/build — e.g. PowerRename's per-launch `txt-textbox-XXXX` IDs), **don't write the guessed value at all** — write the runtime-discovery instruction instead ("discover the AutomationId at runtime by name/role"). **Do NOT** add `[UNVERIFIED] — confirm yourself` tags, "review notes", or any commentary about the doc's own reliability: it doesn't help the consuming agent (which re-checks at runtime anyway) and makes it distrust otherwise-good content. If something's wrong, fix it; if it's uncertain, turn it into a discovery instruction.

**2. Fill from evidence, not speculation.** Don't AI-generate a whole profile up front (that's what produced the HKCR hallucination). **Seed** a thin one (metadata + a source scan for durable facts), then let **each run add** the controls/keys it actually confirmed, correct anything that failed, and promote durable troubleshooting guidance from that run's §G retrospective. The profile grows *out of* runs.

**3. Durable vs volatile.** Durable facts (settings-file path, "modern-menu-only on Win11", the two-settings-files gotcha) belong here as plain statements. Volatile facts (per-launch/per-build IDs, layout) are **discovered at runtime**, never pinned.

**4. State each fact once.** Duplication is the #1 staleness amplifier: when a fact lives in the recipe table, an entry-path, and three troubleshooting rows, one edit leaves the others stale → contradiction. Shared mechanics go in the cross-flow doc; module facts once; everything else cross-references.

**5. Prefer symbol over line for source citations.** `Settings.cpp CSettings::Load` survives a refactor; `Settings.cpp:307` rots on the next edit. A line number is fine only as an *as-of-build* hint.

**6. Content validity.** Do not add last-verification dates, tested-build markers, or per-fact age tags to a profile. Keep run history, build details, and verdicts in the archived verification report. Maintain the profile by correcting or removing instructions that no longer match the controls, settings, or behavior; elapsed time or release count alone does not establish staleness. Runtime discovery (do the named control IDs resolve? do the settings keys exist?) can flag content that needs review.
