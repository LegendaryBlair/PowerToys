# Quick Accent - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - standard-user coverage with an owned, non-elevated text fixture.
- `[ADMIN: COND]` - retain ordinary and conditional environment variants separately.
- `[ID: ...]` - stable case identifier; report the children in the [assertion inventory](../assertion-inventories/quick-accent.json) independently.
- Clarity is recorded in the inventory. A configured value alone does not establish its effect.

## Fixtures & conventions

- Use an owned Notepad document, never an existing user tab. Record its exact window/process and keyboard layout. Keep a second owned text window for focus-transfer checks.
- Preserve original enablement, all Quick Accent settings, and the existence/bytes of `UsageInfo.json` before activation: opening the toolbar with frequency sorting off can clear usage history. Restore after the last module shutdown/startup.
- Change settings through the shipped Settings UI. Keep clipboard payloads private; reference-guide copying requires the supported preservation guard, not a text-only backup of arbitrary formats.
- Capture only owned text, the Quick Accent toolbar and its Settings surfaces. Keep screenshots as candidates, not accepted visual baselines. See the [fixture guide](../quick-accent-fixtures.md) for input, preservation and cleanup.
- PR-added cases require a build containing their changes. The 0.102.2933.0 preview contains the covered WinUI toolbar, press-and-hold and reference-guide changes; a matching major/minor version alone is insufficient.

## Quick Accent (20 items)

### Activation and text entry

- [ ] **Arrow activation and insertion** [ID: QA-ARROWS] [ADMIN: NO]
  Enable Quick Accent, select French with frequency sorting off, and hold `a` in the owned Notepad document. Activate separately with Left and Right; the toolbar appears without taking text focus. Cycle in both directions, including wrapping, and release `a`. Exactly the selected accented letter replaces the base letter, and the toolbar disappears.

- [ ] **Space navigation** [ID: QA-SPACE] [ADMIN: NO]
  Hold `a` and activate with Space. Navigate forward with Space and backward with Shift+Space, including both wrap boundaries. Release the letter; insert the selected character exactly once and leave no held Shift state.

- [ ] **Enablement and activation choices** [ID: QA-MODES] [ADMIN: NO]
  Disable Quick Accent and verify ordinary letters/triggers no longer produce its toolbar or accented insertion. Re-enable and check Arrows only, Space only, and Either: each permitted trigger opens the toolbar, each disallowed trigger behaves normally. Revisit Settings and verify the selected mode persists.

- [ ] **Input delay and false starts** [ID: QA-DELAY] [ADMIN: NO]
  For trigger-key activation, compare input delays of 300 ms and 900 ms. Use timestamped input/observation well below and above each configured threshold, not a tight timing tolerance. An early release leaves normal text and passes the Space/arrow action through; a sustained gesture opens the toolbar. Rapid canceled gestures must not reveal a stale toolbar. Subsequent ordinary typing must not behave as if the owner letter were still down.

- [ ] **Press-and-hold activation** [ID: QA-HOLD] [ADMIN: NO]
  On builds containing #48937 and #49701, choose Press and hold the letter and compare hold durations of 500 ms and 1000 ms. A quick tap produces one base letter; a sustained hold opens the toolbar without a trigger. Release without selecting to keep the base letter; navigate with Space/arrows and release to replace it. Ordinary Ctrl+A must remain a shortcut. A pre-threshold Space, Left or Right, or a different supported letter cancels the pending gesture; it must not reappear later or replace intervening text. A fresh gesture must still work.

- [ ] **Focus loss and repeated gestures** [ID: QA-FOCUS] [ADMIN: NO]
  With a visible toolbar, move focus to the second owned text window before releasing the letter. The toolbar cancels without inserting an accent in either window; return and activate again successfully. Repeat with a pending, not-yet-visible gesture. Test a different HWND in the same process separately from a different process when those owned fixtures are available.

### Character sets and ordering

- [ ] **Character-set selection** [ID: QA-LANGUAGES] [ADMIN: NO]
  Select Currency alone: `a` has no toolbar while `s` offers currency characters. Select French and verify its `e` accents, then All available and verify both French `e` accents and a non-French mapping are available. Reopen the picker and verify persistence. In the character-set dialog, search for a set, change a selection, clear the search and verify hidden selections survive. Cancel must preserve the previous selection; Save commits it. With zero sets selected, Save is disabled rather than committing an unusable configuration.

- [ ] **Recent character mappings** [ID: QA-MAPPINGS] [ADMIN: NO]
  Select each set in the matrix below independently. For every row, verify the stated characters in the toolbar and insert one stated character into owned text, comparing Unicode code points rather than glyph similarity. These are explicit regression probes, not a claim of exhaustively verifying every language/key mapping.

  | Set | Physical key | Required characters / condition |
  |---|---|---|
  | Currency | P; Z | P includes U+20B1; Z has no plain `z` pseudo-accent |
  | Icelandic | I | U+00ED |
  | Pitjantjatjara | L, N, R, T | U+1E3B, U+1E49, U+1E5F, U+1E6F respectively |
  | Belarusian Latin; Belarusian Cyrillic | U | U+016D; U+045E respectively |
  | Bulgarian | I, E, comma | U+045D (not U+0439); U+20AC; U+201E and U+201C |
  | Greek; Hebrew; Vietnamese | E; N; D | U+20AC; U+20AA; U+20AB respectively |
  | Greek polytonic | A | U+03B1 and U+1F00 |
  | Spanish; Catalan | 1, slash | U+00A1 and U+00BF in each set; record layout and Shift state |
  | Special characters | minus; N; Shift+N | U+2013 before U+2014; U+207F; U+1D3A |
  | Special characters | A; 9; P; slash; comma | U+1D43 and U+2090; U+208D and U+207D; U+2030 and U+2031; U+203D and U+2E18; U+27E8 and U+27E9 |
  | International Phonetic Alphabet | M; E; period | U+0271; U+025A; U+0361 and U+035C |
  | German | comma | U+201E and U+201C; no math-operator substitutions |

- [ ] **Frequency ordering** [ID: QA-FREQUENCY] [ADMIN: NO]
  With preserved usage history and French selected, enable frequency ordering, select one accent repeatedly enough to exceed its measured baseline count, and reopen the toolbar. Its order must reflect usage; compare counters privately and actual displayed ordering. Disable sorting and verify the language's normal order returns. Do not erase existing usage data to create the fixture.

- [ ] **Initial arrow selection** [ID: QA-INITIAL] [ADMIN: NO]
  With a multi-character French list, turn Always start on the first character on. Both Left and Right activation must initially select the first item. Turn it off and verify Left and Right resume their respective middle-adjacent starting positions. Check the visible selection and committed character independently.

### Toolbar layout and appearance

- [ ] **Every toolbar position** [ID: QA-POSITIONS] [ADMIN: COND]
  Exercise Top center, Bottom center, Left, Right, Top right corner, Top left corner, Bottom right corner, Bottom left corner and Center. Each toolbar must appear at the chosen location within the active monitor's work area without clipping. Record geometry/DPI. Repeat on a second monitor with different DPI if available; keep that condition separate from the ordinary nine-position matrix.

- [ ] **Descriptions and short-list sizing** [ID: QA-DESCRIPTIONS] [ADMIN: NO]
  Toggle Unicode descriptions off and on for a short list. All character cells, including the last selection, remain fully visible without unnecessary horizontal scrolling. With descriptions on, select a single-code-point accent and the Special `C` entry U+00B0 U+0043; the code-point/name description must correspond to the selected text and remain readable.

- [ ] **Overflow and selection visibility** [ID: QA-OVERFLOW] [ADMIN: NO]
  Use All available and a key whose list is wider than the current work area. Navigate to the last item and back to the first, with descriptions both off and on. The horizontal scrollbar appears only for overflow; the selected item scrolls into view and its highlight is actually painted at each boundary. Verify insertion of the final selected character. A selected UIA flag alone is not proof of a visible highlight.

- [ ] **First frame and theme** [ID: QA-RENDER] [ADMIN: COND]
  Record activation of different short and overflowing lists, dismiss, then reactivate. The first visible toolbar must show the current list rather than blank/stale contents or a clipped intermediate layout. Check ordinary light/dark appearance where a reversible supported theme control is available. Record frame cadence; a settled screenshot cannot establish first-frame behavior. An additional RTL/fractional-DPI condition requires that actual environment.

### Exclusions and integration

- [ ] **Application exclusion** [ID: QA-EXCLUSIONS] [ADMIN: NO]
  Add the owned Notepad executable to exclusions through Settings. Activation must be suppressed there but continue in a different, unexcluded owned text process. Remove only the test entry and verify Notepad activation returns. Preserve pre-existing exclusions and report both applications independently.

- [ ] **Game-mode suppression** [ID: QA-GAME] [ADMIN: COND]
  When an authorized game-mode foreground fixture is available, enable prevention in game mode and verify no toolbar there; disable prevention and verify activation. Outside game mode, normal activation must still work. Do not install a game or change system gaming policy to manufacture this condition.

- [ ] **Downstream shortcut state** [ID: QA-HOOKS] [ADMIN: COND]
  With an already-authorized disposable Keyboard Manager remap and input-event observer, perform a false-start Quick Accent gesture, then the remapped shortcut. The owner key-up must reach the observer and the remap must still work; inserted replacement/arrow events must not retrigger unrelated centralized shortcuts. Without that isolated cross-module fixture, retain these conditions as unexecuted rather than inferring them from ordinary typing.

### Reference guide and Settings

- [ ] **Reference-guide browsing** [ID: QA-GUIDE] [ADMIN: NO]
  On builds containing #49394, open the guide from Quick Accent Settings. Selected sets appear first, other sets beneath alphabetically within their language/special groups. Filter by a single character and the sequence U+00B0 U+0043; only sets containing that query remain, with their other mappings retained. A query with no mappings shows the empty state, and clearing it restores the list. Hover a character for its Unicode description; combining marks use a dotted-circle display aid. Closing/back navigation returns to the originating Settings surface.

- [ ] **Reference-guide copying** [ID: QA-COPY] [ADMIN: NO]
  With the supported private clipboard guard, click an ordinary character and then a combining mark in the guide. Each copies its exact underlying text; the dotted-circle display aid is not copied. Restore and verify the original clipboard formats and payloads without exposing them in evidence.

- [ ] **Settings sizing and localization** [ID: QA-SETTINGS] [ADMIN: COND]
  Resize the owned/reversibly positioned Settings surface smaller and larger. Character-set selection, search and Save/Cancel remain reachable without the old clipped fixed-column layout. In an existing non-English Windows/app locale, verify the module's Settings labels, set names and attribution wording are localized where translations ship; proper names remain intact. Do not change Windows language or sign out as part of ordinary coverage.
