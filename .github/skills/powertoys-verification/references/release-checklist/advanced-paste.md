# Advanced Paste - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - standard-user coverage, subject to the stated fixtures.
- `[ADMIN: YES]` - requires an authorized elevated session.
- `[ADMIN: COND]` - retain ordinary and elevated variants independently.
- `[ID: ...]` - stable scenario identifier; retain every required child/input observation.

## Fixtures & conventions

- Use a disposable rich-text target and synthetic rich text, HTML, XML/CSV, images and selected text.
  Preserve the original clipboard, AP settings, shortcut bindings, custom actions and owned history changes.
- Re-copy fresh source for independent conversion attempts. The clipboard-after-paste case instead follows
  the plain-text conversion without copying again; it must observe the transformed clipboard.
- AI execution requires an authorized provider/endpoint and any necessary credentials; never put credentials
  or private prompts in evidence. Missing AI prerequisites do not block plain-text, Markdown or JSON coverage.
- Snapshot the original Windows clipboard-history setting and isolate owned entries; do not clear user history.
  Release any owned clipboard lock and restore the clipboard before stopping its preservation helper.
- Use isolated migration fixtures for old settings, close only owned windows and restore original settings,
  shortcuts and clipboard/history state rather than resetting defaults.
- See the [module profile](../modules/advanced-paste.md) for control interaction and restoration mechanics, and use the [frozen inventory](../assertion-inventories/advanced-paste.json) without run-local regrouping.

## Advanced Paste (29 items)

### Plain text

- [ ] **Unconverted rich-text control** [ID: AP-RICH-CONTROL] [ADMIN: NO]
  Copy rich text (mixed colors, bold, underline); paste with Ctrl+V into a rich editor - rich text pasted with colors/formatting intact

- [ ] **Plain-text shortcut** [ID: AP-PLAIN-HOTKEY] [ADMIN: NO]
  Copy rich text; paste with the Paste-as-Plain-Text hotkey - plain text pasted, formatting stripped

- [ ] **Clipboard after plain-text paste** [ID: AP-PLAIN-REPASTE] [ADMIN: NO]
  Immediately after the plain-text shortcut conversion, paste again with Ctrl+V without copying new source. Confirm it is still plain text: the clipboard retains plain UnicodeText and HTML/RTF are absent.

- [ ] **Plain-text menu action** [ID: AP-PLAIN-CLICK] [ADMIN: NO]
  Copy rich text; open AP, click "Paste as plain text" - plain text pasted, formatting stripped

- [ ] **Plain-text in-window shortcut** [ID: AP-PLAIN-KEY] [ADMIN: NO]
  Copy rich text; open AP, press Ctrl+1 - plain text pasted, formatting stripped

### Markdown and JSON

- [ ] **Configure and use the Markdown shortcut** [ID: AP-MARKDOWN-HOTKEY] [ADMIN: NO]
  Configure the Paste-as-Markdown direct shortcut in Settings and confirm the chord is saved. Copy Markdown-convertible HTML and use that shortcut; confirm the owned target receives converted Markdown.

- [ ] **Markdown menu action** [ID: AP-MARKDOWN-CLICK] [ADMIN: NO]
  Copy HTML; open AP, click "Paste as markdown" - converted to Markdown

- [ ] **Markdown in-window shortcut** [ID: AP-MARKDOWN-KEY] [ADMIN: NO]
  Copy HTML; open AP, press Ctrl+2 - converted to Markdown

- [ ] **Configure and use the JSON shortcut** [ID: AP-JSON-HOTKEY] [ADMIN: NO]
  Configure the Paste-as-JSON direct shortcut in Settings and confirm the chord is saved. Copy valid XML or CSV and use that shortcut; confirm the owned target receives converted JSON.

- [ ] **JSON menu action** [ID: AP-JSON-CLICK] [ADMIN: NO]
  Copy XML or CSV; open AP, click "Paste as JSON" - converted to JSON

- [ ] **JSON in-window shortcut** [ID: AP-JSON-KEY] [ADMIN: NO]
  Copy XML or CSV; open AP, press Ctrl+3 - converted to JSON

### AI providers and custom actions

- [ ] **Configure an AI provider** [ID: AP-AI-CONFIG] [ADMIN: NO]
  With an authorized OpenAI endpoint and credential, configure OpenAI in Settings. Confirm it reports configured, remains selected after reopening Settings, and is available for the following custom-prompt case. Do not expose the credential in observations or captures.

- [ ] **Custom prompt transformation** [ID: AP-AI-PROMPT] [ADMIN: NO]
  With an authorized configured AI provider, copy synthetic text such as `alpha beta`, open Advanced Paste and submit "Insert smiley after every word". Confirm the transformed result preserves both source words in order with a smiley after each, and can be pasted into the owned target.

- [ ] **Regenerate and paste a preview** [ID: AP-AI-REGENERATE] [ADMIN: NO]
  With an authorized configured AI provider, enter a prompt for synthetic clipboard text and generate a preview. Regenerate, select the resulting preview and paste it. Confirm regeneration completes and the target receives the selected current result, not a stale earlier preview.

- [ ] **Custom action management** [ID: AP-CUSTOM-ACTIONS] [ADMIN: NO]
  With an authorized configured provider, create two owned actions with distinguishable transformations. Assign and exercise a direct shortcut and each displayed Ctrl+number action. Confirm the matching transformation is pasted, disabling an action makes it unavailable, re-enabling restores it, and reordering changes the displayed action order consistently. Restore the original actions/bindings.

- [ ] **Paste without custom preview** [ID: AP-AI-PREVIEW] [ADMIN: NO]
  Disable Custom format preview - result pasted right away

- [ ] **AI service availability** [ID: AP-AI-ENABLED] [ADMIN: NO]
  With AI allowed by existing policy, keep **Show the AI paste input box** on and disable **Paste with AI** in Settings. Confirm the visible custom input/provider section cannot accept an AI operation. Re-enable with an authorized configured provider and supported clipboard input; confirm the section becomes usable. This tests AI service availability, not the independent visibility checkbox.

- [ ] **Image input** [ID: AP-IMAGE-INPUT] [ADMIN: NO]
  Copy an image to the clipboard, open AP - image is accepted as input (image-input handling); a custom/AI action can run on it (image preview shown, no error)

- [ ] **Auto-copy selected text** [ID: AP-AUTO-COPY] [ADMIN: NO]
  Select text in an editor and invoke a custom-action hotkey WITHOUT pressing Ctrl+C first - AP auto-copies the selection and acts on it; clipboard is preserved

- [ ] **Electron and Chromium auto-copy** [ID: AP-AUTO-COPY-ELECTRON] [ADMIN: NO]
  Repeat the auto-copy custom-action hotkey in an Electron/Chromium app (VS Code / Chrome) - selection is still auto-copied (no longer fails on those apps)

- [ ] **AI input section visibility** [ID: AP-AI-VISIBILITY] [ADMIN: NO]
  With AI service/provider prerequisites satisfied, toggle **Show the AI paste input box** off/on in Settings. Confirm the custom-input and provider section hides/appears accordingly, without changing the AI-service enablement setting. Keep this visibility result distinct from disabling **Paste with AI**. Applies to the visibility setting introduced by #45242; attest its inclusion in the installed build.

- [ ] **Provider-specific configuration** [ID: AP-PROVIDER-SWITCH] [ADMIN: NO]
  With an authorized configured AI provider/endpoint, settings: switch AI provider (OpenAI / Azure OpenAI / Gemini / Foundry Local) - the configured endpoint persists per provider (Gemini does not keep an Azure placeholder; Foundry local port change is picked up on the fly)

### Clipboard history

- [ ] **Delete a history entry** [ID: AP-HISTORY-DELETE] [ADMIN: NO]
  Open AP, click Clipboard history, delete entry, verify gone from Win+V

- [ ] **Select and reselect a history entry** [ID: AP-HISTORY-SELECT] [ADMIN: NO]
  Select an owned entry in AP Clipboard history and confirm it moves to the top of Win+V. Select it again and confirm the history contains no duplicate entry.

- [ ] **Windows history disabled** [ID: AP-HISTORY-DISABLED] [ADMIN: NO]
  Disable Windows clipboard history (Settings > System > Clipboard) - the Clipboard history button in AP is disabled/hidden

- [ ] **Color history preview** [ID: AP-COLOR-SWATCH] [ADMIN: NO]
  Copy a hex color string (e.g. `#3478F6`), open Clipboard history in AP - that entry shows an RGB color-swatch preview next to the value

### Module lifecycle and recovery

- [ ] **Module disabled** [ID: AP-MODULE-DISABLED] [ADMIN: NO]
  Disable Advanced Paste, then press its hotkeys - nothing happens (AP window does not open; no process spawned)

- [ ] **Older settings migration** [ID: AP-SETTINGS-UPGRADE] [ADMIN: NO]
  Open the Advanced Paste Settings page after upgrading from an older settings.json - page loads without crashing (settings upgraded safely)

- [ ] **Locked clipboard recovery** [ID: AP-CLIPBOARD-RECOVERY] [ADMIN: NO]
  With an unreadable/locked clipboard (e.g. another app holds an open clipboard handle), trigger Paste as JSON - AP fails gracefully (no crash, error toast/no-op); then copy valid XML/CSV and confirm Paste as JSON converts correctly again
