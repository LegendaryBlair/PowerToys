# Registry Preview - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - standard-user coverage with the stated fixtures.
- `[ADMIN: COND]` - keep ordinary checks separate from authorized elevation.
- `[ID: ...]` - stable case identifier in the assertion inventory.

## Fixtures & conventions

- Use collision-checked, disposable `.reg` files containing one owned HKCU key, one
  string value and one binary value. HKLM is an additional authorized environment,
  not a reason to import into an unrelated existing key. Never import user files.
- Preserve module enablement, default-app registration, affected Settings UI,
  placement, editor/cache state and every owned file/window. Preserve original
  registry value kinds and absence; restore the baseline, not presumed defaults.
- Record the actual default `.reg` handler before changing its setting. Do not
  edit Windows UserChoice or accept an import prompt merely to test association.
- Retain editor text, tree and value-grid observations separately. Saved bytes,
  a window title or a parser tree alone do not establish visible editor content.
- Use the shared [session](../session-safety.md), [owned fixtures](../owned-fixtures.md),
  [Explorer flow](../explorer-context-menu-flow.md) and
  [directory preservation](../directory-snapshots.md) contracts. Registry Preview
  uses the classic `Preview` verb; a modern packaged-menu recipe is not equivalent.
- Locale, clean-install, fault-injection and diagnostic-data conditions need their
  stated environment. Missing conditions remain required, independently reported
  coverage; do not change the shared desktop's language or diagnostic consent silently.

## Registry Preview (19 items)

### Registry fixtures and files

- [ ] **Create and export an owned key** [ID: RP-FIXTURE] [ADMIN: COND]
  In Registry Editor, create a unique disposable HKCU key with `SampleString`
  (`REG_SZ`, `sample-value`) and `SampleBinary` (`REG_BINARY`, bytes `01 02 03 04`).
  Export that selected key through its context menu. Independently check both
  registry values and that the exported file contains only the intended key/data.
  Registry Editor must run under the same user; any required UAC consent is conditional.

- [ ] **Edit, save and save a copy** [ID: RP-EDIT] [ADMIN: NO]
  Open the owned file. Type a change to its leaf key and string value, and observe
  the visual tree update before saving. Press Save file and verify exact saved
  content. Press Edit file and verify the configured external editor (normally
  Notepad) displays that saved file/content. Use Save file as to a new owned path;
  verify its content and that Registry Preview switches to that destination.

- [ ] **Reload external changes** [ID: RP-RELOAD] [ADMIN: NO]
  Edit and save the owned file externally, changing its leaf key and string data.
  Press Reload from file. Both the visible editor and visual tree must show the
  new content, not stale data. A programmatically prepared external file change
  may exercise reload mechanics but does not replace the external-editor action.

- [ ] **Inspect string and binary values** [ID: RP-VALUES] [ADMIN: NO]
  Select the owned leaf key in the visual tree. In the bottom-right value grid,
  verify each value's name, type and data: `SampleString`, `REG_SZ`, `sample-value`;
  `SampleBinary`, `REG_BINARY`, `01 02 03 04`. Finding text only in Monaco is insufficient.

- [ ] **Open another file** [ID: RP-OPEN] [ADMIN: NO]
  Press Open file and select a different owned `.reg` file with a distinct key
  and string value. Verify the active filename, visible editor and tree all
  switch to the selected file.

- [ ] **Write the saved fixture to the registry** [ID: RP-WRITE] [ADMIN: COND]
  Manually delete the exported owned key in Registry Editor and independently
  establish its absence. With the reviewed saved fixture open, press Write to
  Registry and confirm only its specific import, when authorized. Verify the
  recreated string and binary values, including kinds and exact data. Delete
  only the test-created key afterward. An unsaved editor draft is not the import file.

### Settings and Explorer entry points

- [ ] **Disable the module** [ID: RP-DISABLE] [ADMIN: NO]
  Disable Registry Preview in Settings. Open the real classic context menu on an
  owned `.reg` file and verify Preview is absent from a correctly populated file
  menu. Attempt launch from the module's Welcome/OOBE page while disabled and
  verify no Registry Preview editor starts.

- [ ] **Enable and launch from Explorer** [ID: RP-ENABLE] [ADMIN: NO]
  Enable Registry Preview in Settings. On a fresh owned Explorer window, open the
  `.reg` file's classic menu, verify Preview is present and invoke it. Verify the
  resulting Registry Preview window displays that file's key/content.

- [ ] **Launch from Settings and Welcome** [ID: RP-LAUNCH] [ADMIN: NO]
  With the module enabled, independently launch it from its Settings page and
  its Welcome/OOBE page. Each route must produce a usable Registry Preview
  editor. Close only editors owned by that launch between the two observations.

- [ ] **Default .reg application** [ID: RP-DEFAULT] [ADMIN: NO]
  Enable the Default app setting and verify that opening an owned `.reg` file
  by its default action opens Registry Preview. Disable the setting and verify
  Registry Editor becomes the default handler. Preserve the original association
  and distinguish OpenWith registration from the effective Windows default.
  If Windows UserChoice conflicts with this expectation, retain the discrepancy
  for specification review rather than counting registration alone as success.

### Window lifecycle and appearance

- [ ] **Start with a usable title** [ID: RP-STARTUP] [ADMIN: COND]
  On builds containing the nonempty-title fixes, open a blank editor and an owned
  file separately. Verify each remains usable, has a nonempty native title and
  the module icon, and shows the filename when applicable. In an affected CJK
  Windows-language environment with PowerToys language set to Windows Default,
  repeat startup/close and verify no title-bar startup failure. Record the actual
  locale and elevation; ordinary startup does not establish the affected-locale fix.

- [ ] **Close without a teardown failure** [ID: RP-CLOSE] [ADMIN: NO]
  Close a clean owned editor normally and verify its window/process exit without
  a crash. On an authorized fault-injection build containing the closing-handler
  guard, also exercise missing placement state or a teardown exception and verify
  no WinRT fail-fast escapes. Do not corrupt installed state to manufacture that condition.

- [ ] **Caption buttons follow the theme** [ID: RP-THEME] [ADMIN: NO]
  On a supported Windows version and build containing the preferred-title-bar-theme
  change, change Windows default app mode to Light and then Dark while an owned Registry
  Preview window is live. Observe visible, legible caption-button glyphs in each
  resulting theme; a reopened window alone does not prove the live change. Restore
  the original Windows app mode and verify the borrowed Windows Settings state.
  PowerToys Settings' own theme is not a substitute.

- [ ] **Localized module UI** [ID: RP-LOCALIZATION] [ADMIN: NO]
  With an installed, authorized non-English Windows display language, open Registry
  Preview and inspect its command labels, tooltips and dialogs. Verify the UI
  follows that language rather than remaining unexpectedly English. Record the
  language; an English-only run cannot satisfy this condition.

### Command Palette integration

- [ ] **Open the module and its Settings** [ID: RP-CMDPAL] [ADMIN: NO]
  On a build containing the PowerToys Command Palette extension, locate the actual
  extension's Registry Preview commands, not a Search apps PowerToys shortcut.
  Invoke Open Registry Preview and verify the editor appears; independently
  invoke the Settings command and verify the correct page. With the module
  disabled, verify the launch command is unavailable but Settings remains available.
  Preserve the original palette query/navigation, history and provider lifetime.

- [ ] **Pin the module commands** [ID: RP-CMDPAL-PIN] [ADMIN: NO]
  On a build containing stable PowerToys command IDs, pin the Registry Preview
  launch and Settings commands independently, reopen Command Palette, and verify
  each pin remains usable and routes correctly. Restore each original pinned
  state without removing unrelated pins or changing their order.

- [ ] **Localized extension labels** [ID: RP-CMDPAL-LOCALIZATION] [ADMIN: NO]
  With a supported non-English language and the localized PowerToys extension,
  verify Registry Preview launch title/subtitle and Settings subtitle use the
  expected translations. Preserve palette and language state.

### Conditional release integration

- [ ] **Fresh-install disabled default** [ID: RP-FIRST-RUN] [ADMIN: NO]
  On an authorized clean installation containing the default-enablement fix,
  observe first Runner startup before Settings writes its configuration.
  Registry Preview must remain disabled without transient activation; opening
  Settings must retain the same disabled state. Existing-user settings must not
  be deleted or reset to simulate first run.

- [ ] **Module diagnostic events** [ID: RP-TELEMETRY] [ADMIN: NO]
  When Diagnostic data and Enable viewing are authorized and enabled before the
  required PowerToys restart, exercise Registry Preview and open Diagnostic data
  viewer. Verify module event XML corresponds to those recorded actions. Do not
  disclose unrelated diagnostic payloads; restore original consent and viewing state.
