# Color Picker - initial release checklist through 0.101

## Scope and provenance

- Baseline: the user-supplied 0.96 `tests-checklist-template.md`, SHA256
  `F7EBCF506EB07BA16774FAE4F606496CD23A72FEAAB33F9C0B44C5F6957EAAFA`.
  Preserve all 14 Color Picker checkboxes at source lines 85-98, plus its explicit localization checkbox at line 37.
- Product cutoff: stable `v0.101.2362.0`, commit `389b1a3827b2cf577723288df15437490ef0663a`.
  PR discovery starts after `v0.96.0`, commit `068cccc22b37fa11d521bedebd21b92280dbf12f`.
  A release-branch cherry-pick counts when the changed code is present; main-branch ancestry alone is insufficient.
- The worktree's newer main code is research material, not the identity of the installed product.
  #49174 belongs to milestone 0.102 and is absent from the stable cutoff. Do not credit this run as WinUI 3 migration verification.
- This is a module checklist, not a claim that every branch of every shared-library PR has been tested.
  Installation, whole-suite telemetry setup and other modules' general tests remain outside this module run.
- Items tagged `[CLARITY: REWRITTEN]` make the original action's observable outcome explicit.
  Source line numbers below refer to the baseline file, not this document.
- The baseline's three activation choices are now expressed by two activation choices plus mouse-button actions
  (`ColorPickerActivationAction` and `ColorPickerClickAction` at the stable tag). CP05 preserves the three user
  flows rather than requiring obsolete option captions.
- `[ADMIN: YES]` variants require an appropriately elevated runner/session. If unavailable, record only those
  variants as BLOCKED and continue non-admin coverage, following the user's requested execution policy.
- Record partial observations, exact blocked conditions and state restoration. A source diff is not a runtime PASS.
  Use a test-owned, known-color surface for picking; back up settings, history and clipboard before modifying them.

## Baseline (15 items)

- [ ] **CP01 [ADMIN: NO] [CLARITY: REWRITTEN]** With normally started, non-elevated PowerToys, enable Color Picker
  through Settings and use its configured shortcut. The selected activation surface opens. Record runner
  integrity, configured chord and actual surface. Source L84-L85.
- [ ] **CP02 [ADMIN: YES] [CLARITY: REWRITTEN]** Start PowerToys elevated, enable Color Picker and use its
  configured shortcut. The selected activation surface opens. Source L84/L86.
- [ ] **CP03 [ADMIN: YES] [CLARITY: REWRITTEN]** Use Settings' Restart as administrator action, then activate
  Color Picker with its configured shortcut. Record the new runner's integrity and actual surface. Source L84/L87.
- [ ] **CP04 [ADMIN: NO] [CLARITY: REWRITTEN]** Change the activation shortcut through the shortcut editor.
  The new chord activates Color Picker and the former chord does not; restore the original chord and confirm
  activation again. Do not substitute a named event for keyboard-binding observations. Source L88.
- [ ] **CP05 [ADMIN: NO] [CLARITY: REWRITTEN]** Configure and exercise all three baseline activation flows: picker followed by
  editor after selecting a color; editor directly; picker-only that copies the selected color and closes without
  opening the editor. Use activation and mouse-button settings as exposed by the installed version.
  Close each surface before the next activation and restore the original settings. Source L89.
- [ ] **CP06 [ADMIN: NO] [CLARITY: REWRITTEN]** Change Color format for clipboard in Settings and pick a known
  color. The actual clipboard text uses the selected format and represents the sampled color. Exercise two
  different formats and restore the original. Source L90.
- [ ] **CP07 [ADMIN: NO] [CLARITY: REWRITTEN]** Copy at least two displayed formats from the editor for the
  same selected color. Each actual clipboard value matches that row's representation and the selected color. Source L91.
- [ ] **CP08 [ADMIN: NO] [CLARITY: REWRITTEN]** Turn Show color name on, activate the picker and observe a
  name for the sampled color; turn it off and confirm the name is hidden. Restore the original value. Source L92.
- [ ] **CP09 [ADMIN: NO] [CLARITY: REWRITTEN]** Enable a previously disabled format, disable an enabled format,
  and reorder enabled formats through Settings. Reopen the editor and confirm presence, absence and ordering
  separately. Restore the original enabled set, format strings and order. Source L93.
- [ ] **CP10 [ADMIN: NO] [CLARITY: REWRITTEN]** Select a non-current color from editor history. The selected
  swatch and displayed values change to that entry, without removing other entries. Source L94.
- [ ] **CP11 [ADMIN: NO] [CLARITY: REWRITTEN]** Remove a test-owned color from editor history. That entry is
  absent and other entries remain; verify the history after reopening, then restore the original history. Source L95.
- [ ] **CP12 [ADMIN: NO] [CLARITY: REWRITTEN]** Use Pick color in the editor. The picker appears, can sample
  the controlled surface and returns the new color to the editor. Source L96.
- [ ] **CP13 [ADMIN: NO] [CLARITY: REWRITTEN]** Open Adjust color for the editor's selected color.
  The adjustment UI shows that color and exposes its editing controls; dismiss it without leaving an unintended
  color/history change. Source L97.
- [ ] **CP14 [ADMIN: NO] [CLARITY: REWRITTEN]** Examine Color Picker logs generated during this run.
  Report any new errors with timestamps and the responsible action; absence of historical errors is not required.
  An empty interval with no module execution is insufficient. Source L98.
- [ ] **CP15 [ADMIN: NO] [CLARITY: REWRITTEN]** In a supported non-English Windows display language, open
  Color Picker/editor and inspect their visible labels and tooltips for that language. Also inspect the Color
  Picker command titles, descriptions and saved-colors labels in Command Palette's PowerToys extension (#44520).
  Restore the original
  language if changed. If changing the language requires an unavailable language pack, sign-out or shared-session
  disruption, record that condition rather than claiming localization from English resources. Source L37.

## PR-derived coverage (10 items)

- [ ] **CP16 [ADMIN: NO] [CLARITY: CLEAR]** Edit a CIELAB format through Settings. For the same picked color,
  compare default `%Lc`, `%Ca`, `%Cb` with `%Lci`, `%Cai`, `%Cbi`: default values retain the existing two-decimal
  rounding, the `i` forms round to integers, and an integer-rounded zero is `0`, not `-0`. Confirm the Settings
  format help describes `i`; restore the original format. Source #42986.
- [ ] **CP17 [ADMIN: NO] [CLARITY: CLEAR]** In the Color Picker editor, inspect format labels such as HEX and
  RGB. Their foreground is legible against the rendered background, without the washed-out secondary-text
  appearance addressed by the change. Capture the actual image and state the theme tested. Source #45367.
- [ ] **CP18 [ADMIN: NO] [CLARITY: CLEAR]** Zoom into a known-color surface using the picker. The magnified
  image does not contain the picker's own UI corner; after zooming in/out, the picker remains visible in a normal
  screen capture. Observe the magnified pixels as well as the restored capture behavior. Source #48762.
- [ ] **CP19 [ADMIN: NO] [CLARITY: CLEAR]** Exercise display-frequency reports of `0` and `1`: both use the
  60 Hz fallback without overflow or one-second sampling. Valid reports greater than `1` retain their actual
  rate. Record which values the environment can supply. Ordinary picking at 60 Hz does not prove the sentinel
  branches; missing conditions remain explicitly blocked. Source #49973.
- [ ] **CP20 [ADMIN: NO] [CLARITY: CLEAR]** In Command Palette's PowerToys extension, open Color Picker,
  open its Settings page, and use saved colors to copy an existing history entry. When the module is disabled,
  the Settings command remains but picker/saved-color commands are absent. Restore module state and clipboard.
  Missing expected extension commands are an integration failure, not merely an assumed unavailable prerequisite.
  Sources #44006, #44520.
- [ ] **CP21 [ADMIN: NO] [CLARITY: CLEAR]** Pin a Color Picker PowerToys-extension command in Command Palette,
  leave and return to its start page, then use the pinned command. The command remains identifiable and performs
  its intended action. Remove only the pin created by the test. Source #45840.
- [ ] **CP22 [ADMIN: NO] [CLARITY: CLEAR]** Navigate to the Color Picker page in Welcome to PowerToys while
  the module is disabled: Launch is disabled. Enable the module and navigate to that page again: Launch is
  enabled and opens the configured surface. The claim is evaluated on page navigation, not an undocumented
  live-update requirement. Restore the original enabled state and close only the test-opened Welcome window.
  Source #44736.
- [ ] **CP23 [ADMIN: NO] [CLARITY: CLEAR]** At a supported narrow Settings window size, inspect the Color
  Picker activation shortcut control. Its edit action remains visible and usable rather than collapsing due to
  the removed page-level minimum width. Restore window placement. Source #46035; the width is supplied by
  the common shortcut control, not by every page.
- [ ] **CP24 [ADMIN: NO] [CLARITY: CLEAR]** In a supported non-English Settings language, inspect both Color
  Picker attribution links. Translatable wording is localized, contributor/product names remain intact and
  link targets are unchanged. English-only rendering or the existence of an `x:Uid` is not localization proof.
  Source #49690.
- [ ] **CP25 [ADMIN: NO] [CLARITY: REWRITTEN]** From the installed Color Picker editor, use Open settings
  while Settings is closed or showing another module. The Color Picker Settings page becomes the foreground
  destination in the same installation. This is the normal installed-path regression for #48905, not proof of
  missing/misdirected registry or elevated fallback branches; those require a separately authorized disposable
  environment. Restore the previous Settings page/visibility.

## PR disposition

| PR | Change | Checklist disposition |
|---|---|---|
| #44006 | PowerToys extension, picker/settings/saved-color commands | CP20 |
| #44520 | Localized extension labels | CP15 includes non-English command/history labels; CP20 covers the underlying command workflows |
| #45840 | Stable command IDs for pinning | CP21 |
| #44736 | Disabled-module Welcome launch guard | CP22 |
| #45367 | Format-label contrast | CP17 |
| #42986 | Optional CIELAB integer formatting | CP16 |
| #46035 | Shortcut-control minimum width moved into the shared control | CP23 |
| #48762 | Exclude picker UI during magnifier capture, then restore affinity | CP18; release history contains a cherry-pick, not two independent changes |
| #49690 | Localizable Settings attribution links | CP24 |
| #49973 | Refresh-rate sentinel handling | CP19; stable cherry-pick `e213200b5a` |
| #48905 | Resolve installed paths from the running executable first | CP25 installed-path smoke; stable cherry-pick `9ee025f2a7`; other callers/fallbacks outside this module |
| #48467 | New UI-test framework; hidden HEX observation field in picker | Observation aid, not a new end-user checklist item |
| #46679 | Color conversion unit tests | Supporting expected-format material; no independent shipped UX claim |
| #43505 | Command Palette theme/icon infrastructure | No separate Color Picker behavior; ordinary integration appearance in CP20 |
| #42644, #44064, #44331, #44721, #45542 | Settings serialization, services and common controls refactors | Existing activation/settings/format baseline covers module-facing regression; no invented new feature |
| #44304, #44639, #45420, #37651, #46712, #47119, #41280, #48842, #46729 | Build, dependency, spelling or test infrastructure | Not new installed-module UX assertions |
| #49161, #48891, #48027, #45606, #48085 | Mention Color Picker but modify another module or repository tooling | Excluded after path/diff review |
| #49174 | WPF to WinUI 3 migration, milestone 0.102 | Outside stable 0.101; future profile/UI-stack validation, not this run |

For each PR-derived result retain the PR description, relevant diff and actual release-code inclusion evidence
in the run archive. The baseline/PR origin survives grouping: do not silently drop a source requirement merely
because several items share setup.
