# Hosts File Editor - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - standard-user coverage with the stated fixtures.
- `[ADMIN: YES]` - requires an authorized elevated writer.
- `[ADMIN: COND]` - retain ordinary and elevated conditions independently.
- `[ID: ...]` - stable case identifier in the frozen assertion inventory.

## Fixtures & conventions

- Resolve the system hosts path and the product's actual target. Privately preserve
  original bytes, encoding/newlines, existence, attributes, permissions, module
  preferences and affected backups before launching a writer. Elevated startup
  can prune backups before any entry is edited.
- Use collision-checked, uniquely tagged names below `.invalid` or `.test`, with
  loopback or documentation addresses. Never replace the hosts file with a canned
  fixture, remove unrelated entries, weaken permissions or take ownership.
- Establish attributed post-states and conflict-aware restoration before mutation.
  Preserve borrowed windows/drafts, Settings navigation, clipboard and desktop
  state. Verify disk restoration and live UI/cache restoration separately.
- Observe only synthetic content; keep original hosts contents and clipboard
  payloads private. An external editor must be a real, safely owned text editor.
- Use the shared [session](../session-safety.md), [recording](../recording-workflow.md),
  [paired-state](../helper-workflow.md#pair-snapshots-with-restoration-before-changing-state)
  and [selected-file](../directory-snapshots.md#selected-file-preservation) contracts.
  The run inputs supply the concrete preservation plan for profile-absent discovery.
- Missing elevation/consent blocks only dependent conditions. Locale, clean-install,
  failure-injection, full-Runner-restart and diagnostic-consent fixtures are
  conditional; do not manufacture them by damaging this shared installation.

## Hosts File Editor (21 items)

### Settings and entry points

- [ ] **Launch at the requested privilege** [ID: HFE-LAUNCH] [ADMIN: COND]
  With the module enabled and no borrowed editor to replace, turn Open as
  administrator off in Settings and use Open Hosts File Editor. Verify a usable
  standard-user editor; an attempted synthetic save reports the non-admin error
  and leaves the hosts file unchanged. Separately turn the option on and launch
  from Settings with authorized consent, verifying the new editor's elevated
  token and ability to save. Direct elevated launch or a named event does not
  establish the Settings entry or consent behavior.

- [ ] **Startup warning and dismissal** [ID: HFE-WARNING] [ADMIN: NO]
  Enable Show a warning at startup through Settings. Launch and choose Quit;
  verify the owned editor exits. Relaunch and choose Accept; verify the warning
  closes but the editor stays usable. Turn the setting off, relaunch and verify
  the warning is absent. Restore the original preference.

- [ ] **Enablement and restart persistence** [ID: HFE-ENABLE] [ADMIN: COND]
  Disable Hosts in Settings and verify its launch action is unavailable and no
  editor is activated. Enable it and verify launch works again. When a full
  PowerToys restart can preserve all affected borrowed state, independently
  verify disabled and enabled states survive restart and retain their behavior.
  Do not disable other modules or restart borrowed applications to simplify setup.

- [ ] **Quick Access and Settings stay synchronized** [ID: HFE-QUICKACCESS] [ADMIN: NO]
  Open the real tray Quick Access surface and launch enabled Hosts from its
  launcher. Disable Hosts in its apps list; verify it disappears from the
  launcher and the open Hosts Settings page becomes disabled. Re-enable there;
  verify the launcher entry and Settings state both return. Preserve the
  flyout's original visibility/navigation and do not substitute a shared event.

### Entries, validation and file observation

- [ ] **Add an entry and observe the write** [ID: HFE-ADD] [ADMIN: YES]
  Open a safely owned auto-refreshing text editor on the actual hosts file.
  In Hosts File Editor, create one tagged entry with address, hosts and comment.
  Verify the new row, the independently read file and the external editor all
  show the same committed synthetic mapping without a manual reload. Retain
  each observation separately; a file read alone cannot prove editor refresh.

- [ ] **Validate the host-count boundary** [ID: HFE-LIMIT] [ADMIN: NO]
  Open a new-entry draft with a valid loopback address. Nine unique synthetic
  hostnames must permit Add; ten must disable Add. Cancel the draft and verify
  it did not write the file. Do not copy the disposable UI suite's delete-all setup.

- [ ] **Disable and re-enable an owned line** [ID: HFE-ACTIVE] [ADMIN: YES]
  Toggle only the synthetic row's Active control off and on. Independently
  verify the row state and the file's commented/uncommented mapping after each
  transition. Keep other entries and comments intact.

- [ ] **Load an overlong externally authored line** [ID: HFE-SPLIT] [ADMIN: YES]
  Append one tagged line containing ten unique hosts to the preserved file,
  retaining all original bytes before that append. Use the product's Reload
  action after its external-change notification. Verify the line becomes a
  nine-host row plus a one-host row without loss, and the too-many-hosts
  teaching tip/info message is shown. Restore the append and refresh live state.

- [ ] **Find and clear filtered entries** [ID: HFE-FILTER] [ADMIN: COND]
  With owned distinguishable entries present, open Filters and independently
  find the intended rows by address, hostname and comment. A collision-checked
  nonmatching query must show no matching entries. Clear filters and verify
  the original visible entry set returns. Preparing committed rows requires
  elevation; filtering itself does not. Do not expose unrelated row content.

- [ ] **Open the hosts document externally** [ID: HFE-OPEN] [ADMIN: NO]
  Click Open hosts file and verify the actual document opens in Windows Notepad
  on builds containing the fixed-Notepad change. For older builds, verify the
  configured default editor instead. Establish ownership of the new document
  or tab before closing it; do not kill or overwrite existing editor sessions.

### Additional content and backups

- [ ] **Place additional content above and below entries** [ID: HFE-ADDITIONAL] [ADMIN: YES]
  Preserve all existing additional content and append one tagged comment in
  the product dialog. Select Top in Settings, commit through the editor, and
  verify the comment precedes the synthetic entry in the file. Repeat with
  Bottom and verify it follows the entry. Observe both persisted setting and
  resulting file order, then restore original content and preference.

- [ ] **Create or suppress backups** [ID: HFE-BACKUP] [ADMIN: YES]
  Select a new owned backup folder through Settings. With backup enabled, make
  the first synthetic edit in a fresh owned editor and verify the backup has
  the pre-edit bytes. A second edit in that editor must not create another
  backup. With backup disabled, a fresh editor's edit must create none.
  Preserve the original backup location, enablement and existing files.

- [ ] **Apply backup retention settings** [ID: HFE-RETENTION] [ADMIN: YES]
  In the isolated selected backup folder, prepare harmless tagged backup files
  with distinct creation times plus a non-backup sentinel. Configure each
  policy through Settings and launch a fresh elevated editor to apply it:
  Never retains all; count-based retains the newest configured count;
  age-and-count removes only expired files beyond the protected newest count.
  Verify exact surviving names and unchanged sentinel. Do not age, delete or
  relocate unrelated backups to create this fixture.

### Appearance and language

- [ ] **Start with a usable title** [ID: HFE-TITLE] [ADMIN: COND]
  Verify ordinary and elevated editors start with nonempty appropriate titles
  and remain usable. On a build containing the CJK startup fix, repeat ordinary
  and elevated startup in an affected installed CJK Windows display language,
  with PowerToys language set to Windows Default. Keep those conditions
  separate; English startup alone cannot establish the affected-locale fix.

- [ ] **Caption buttons follow live Windows app mode** [ID: HFE-THEME] [ADMIN: NO]
  On supported Windows and builds containing the preferred-title-bar-theme
  change, use Windows Settings to select Light and Dark default app mode while
  an owned Hosts editor remains open. Verify caption-button glyphs are visible
  and legible after each live transition. Restore Windows app mode and its
  Settings window state. PowerToys' own theme or reopening alone is not equivalent.

- [ ] **Localized editor and extension labels** [ID: HFE-LOCALIZATION] [ADMIN: NO]
  With an installed, authorized non-English Windows display language, verify
  Hosts commands, warning, tooltips and dialogs follow that language.
  Independently, on builds containing the localized PowerToys extension,
  verify Hosts launch titles/subtitles and Settings subtitle in Command Palette.
  Preserve original language, palette and Settings state.

### Command Palette integration

- [ ] **Invoke actual Hosts extension commands** [ID: HFE-CMDPAL] [ADMIN: COND]
  In the PowerToys Command Palette extension, independently invoke ordinary
  Hosts launch, administrator launch with authorized consent, and Hosts Settings.
  Verify the actual destination and privilege, not merely event delivery.
  With Hosts disabled, both launch commands must be unavailable while Settings
  remains available. On builds with the administrator-shortcut change, select
  ordinary Open Hosts File Editor and press Ctrl+Shift+Enter; verify the
  administrator action, separately from menu invocation.

- [ ] **Persist independent command customization** [ID: HFE-CMDPAL-CUSTOM] [ADMIN: COND]
  On builds with stable command IDs, separately pin ordinary launch,
  administrator launch and Hosts Settings, reopen Command Palette, and verify
  each remains independently usable at its destination. Administrator use
  requires consent. On builds with distinct fallback IDs, change only ordinary
  Hosts launch's fallback setting and reopen extension settings; verify that
  setting persists without changing administrator launch or Hosts Settings.
  Restore original pins, order, fallback settings, query/history and providers.

### Conditional release integration

- [ ] **Fresh-install disabled default** [ID: HFE-FIRST-RUN] [ADMIN: NO]
  In an authorized clean-install fixture containing the default-enablement fix,
  observe first Runner startup before Settings writes configuration. Hosts must
  remain disabled without transient activation, and opening Settings must retain
  that state. Never delete existing settings to simulate a clean installation.

- [ ] **Preserve Hosts settings through shared lifecycle actions** [ID: HFE-SETTINGS-SAFETY] [ADMIN: COND]
  On builds containing the relevant shared fixes, check for updates without
  installing and verify Hosts enablement is unchanged. With authorized diagnostic
  and backup-status fixtures, verify read-only status refreshes do not overwrite
  it. In a safely isolated lifecycle fixture, verify early Settings startup sees
  the fully initialized Hosts state; a temporary module-load failure preserves
  its explicit setting; changing an originally missing enabled key persists
  the requested state; and Windows shutdown/restart does not erase the settings.
  Keep these conditions independent. Do not rename installed binaries, corrupt
  settings, change ACLs or reboot this shared desktop to manufacture failures.

- [ ] **Module diagnostic events correspond to actions** [ID: HFE-TELEMETRY] [ADMIN: COND]
  When Diagnostic data and Enable viewing are authorized and enabled before
  the required PowerToys restart, exercise Hosts and open Diagnostic data viewer.
  Verify module event XML corresponds to recorded actions. Keep unrelated
  telemetry private and restore original consent and viewing preferences.
