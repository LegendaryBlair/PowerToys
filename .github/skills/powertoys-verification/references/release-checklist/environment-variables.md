# Environment Variables - PowerToys release checklist

## Legend

- `[ADMIN: NO]` - runnable without elevation, subject to the stated fixtures.
- `[ADMIN: YES]` - requires an authorized elevated session.
- `[ADMIN: COND]` - run the non-admin portion; retain elevated variants separately.
- `[ID: ...]` - stable case identifier used in the report and [assertion inventory](../assertion-inventories/environment-variables.json).

## Fixtures & conventions

- Use collision-checked `PT_EV_<run-token>` names for owned variables and profiles. P1/P2
  are disposable profiles; reuse them across related cases only after checking the required
  starting state. Use a synthetic existing User variable for override tests, not the user's TMP.
- Preserve raw User/System Path and TMP, affected files, original profile enablement and
  window state before mutations. Change product state through shipped UI; restore and verify
  the original state afterward. Never close a user's pre-existing editor or Settings window.
- Observe the native Windows Environment Variables dialog, the Applied list and persisted
  storage wherever a case requires them; one surface does not substitute for another.
- Keep private environment values out of reports and full-window captures. Compare them
  in memory, use synthetic-only crops and do not use the clipboard for input.
- Missing elevation or a conditional fixture blocks only the corresponding coverage.
  Do not change locale, enable telemetry, manufacture a clean installation or seed invalid
  legacy data without the stated authorization.
- Detailed setup, UI adapters and exact cleanup are in the [module profile](../modules/environment-variables.md)
  and [fixture guide](../environment-variables-fixtures.md). Use the existing frozen inventory;
  do not redefine assertions per run.

## Environment Variables (29 items)

### Settings and entry points

- [ ] **Standard-user Settings launch** [ID: EV-SETTINGS-LAUNCH] [ADMIN: NO]
  Turn off **Open as administrator** in Settings and use its launch control. Confirm a new titled editor opens with a non-elevated token, System editing and Add are disabled, and User Add is available.

- [ ] **Elevated Settings launch** [ID: EV-ELEVATED-LAUNCH] [ADMIN: YES]
  With authorized elevation/UAC, turn on **Open as administrator** and launch through Settings. Confirm the actual editor token is elevated and System editing/Add are enabled. Do not reuse a medium-integrity singleton or perform arbitrary machine writes.

- [ ] **Module enablement and OOBE** [ID: EV-MODULE-LIFECYCLE] [ADMIN: NO]
  Disable and re-enable Environment Variables through Settings. After each save, confirm the stored module flag matches the toggle and unrelated flags are unchanged; closing/restarting Settings is not required. Reopen OOBE in each state: Launch must be disabled when the module is disabled, enabled when enabled, and actually open the editor when invoked.

- [ ] **Quick Access entry** [ID: EV-QUICK-ACCESS] [ADMIN: NO]
  Open Quick Access and invoke its enabled Environment Variables tile. Confirm editor arrival and restore the companion state. Signaling the module directly is not evidence that this entry works.

### User and System variables

- [ ] **User variable CRUD** [ID: EV-USER-CRUD] [ADMIN: NO]
  Add an owned User variable with value `one`, edit it to `two`, then delete it through UI. After each transition, check its exact name/value or absence independently in the native dialog, Applied list and HKCU. Editing must not create a duplicate; deletion means absent, not an empty string. Record the raw registry kind.

- [ ] **System variable CRUD** [ID: EV-SYSTEM-CRUD] [ADMIN: YES]
  With an authorized machine fixture and exact raw-kind/value restoration, repeat add `one`, edit `two`, delete in System scope. Check the native dialog, Applied list and HKLM after every step, including no duplicate on edit and no User-scope leak. Missing this fixture does not block User CRUD.

### Profiles

- [ ] **Create and populate profiles** [ID: EV-PROFILE-CREATE] [ADMIN: NO]
  Create empty disabled P1 and confirm its UI/persisted state. Edit P1, add V1=`one`, and confirm exactly that member after outer Save. Create P2 with V2=`two` and V3=`three`, enabled before outer Save; confirm both values in native User scope, Applied and HKCU, and the saved enabled profile with both members. Observe each commit, not only the final file.

- [ ] **Switch and unapply profiles** [ID: EV-PROFILE-SWITCH] [ADMIN: NO]
  With P2 active, enable P1. Confirm P1 enabled/P2 disabled, V2/V3 removed and V1=`one` present in native, Applied and persisted state. Disable P1 and confirm its originally absent variables disappear from all three surfaces and its saved enabled flag is off.

- [ ] **Override, backup and restore** [ID: EV-OVERRIDE] [ADMIN: NO]
  Create an owned User variable with value `original`. Select it through Existing variables in disabled P1, change its profile value and Save; the live User value must remain unchanged until application. Apply P1 and confirm the override plus correctly named backup containing `original` in native, Applied and HKCU. Unapply: the original returns and backup disappears on every surface, with HKLM unchanged. Exact registry-kind cleanup is separate from product undo.

- [ ] **Edit and rename an applied variable** [ID: EV-APPLIED-EDIT] [ADMIN: NO]
  Test both an originally absent profile-created variable and an override of an existing owned `original`, with absent rename destinations and captured backup baselines. For each, apply `one`, edit while active to `two`, rename and unapply; check native, Applied and HKCU at every stage. The absent variant must never gain a backup of its own old value or leave either name/backup behind. The existing variant must retain the genuine `original` backup through edit, restore the old source on rename, and remove the absent-baseline destination/backups on unapply. Full private HKLM and untracked HKCU maps must remain unchanged throughout both variants. Record residue before explicit cleanup; one variant cannot substitute for the other.

- [ ] **Existing-variable selection without duplication** [ID: EV-EXISTING-SELECTION] [ADMIN: NO]
  In a disabled profile already containing an owned variable, open Edit -> Add -> Existing. Observe its selection and Add availability; do not toggle an already selected entry off, and invoke Add only if enabled. Save/reopen and confirm unchanged membership/count with no duplicate.

### PATH

- [ ] **Composition and ordered draft editing** [ID: EV-PATH-EDIT] [ADMIN: NO]
  Privately confirm Applied PATH is expanded SYSTEM Path followed by expanded USER Path, separated by semicolon. Add `path1;path2;path3` to disabled P1 and Save; confirm three separate UI/stored entries. Exercise Delete, Move up, Move down, Insert before and Insert after independently against an expected order, then Save/reopen and compare the final order. Keep the profile disabled during editing; no drag/drop requirement.

- [ ] **Applied PATH, reopen and profile deletion** [ID: EV-PATH-LIFECYCLE] [ADMIN: NO]
  Preserve real User PATH privately, apply P1 containing PATH and use absolute tool paths while it is active. Confirm exact User Path and complete original backup in native/HKCU, correct SYSTEM-plus-profile composition and backup in Applied, and unchanged HKLM. Normally close/relaunch only the owned editor: a new titled process must retain profile IDs/names/variables/enablement in UI/file and active environment/backup in native/Applied. Cancel and dismiss P1 deletion first and confirm no changes; then confirm deletion of active P1 and check owned-value removal, originals restored and backups gone in native/Applied/storage. Delete P2 and confirm both profiles are absent from UI/profiles.json while unrelated profiles remain unchanged.

- [ ] **Remove duplicate PATH entries** [ID: EV-PATH-DEDUP] [ADMIN: NO]
  Requires a build containing #50585. Use synthetic disabled-profile PATH and an owned inherited expansion fixture. Confirm case, slash direction, trailing separator and expanded-reference variants collapse equivalents while preserving the first spelling and order; for example, `C:\Tools\;C:/Tools;C:\Other` becomes `C:\Tools\;C:\Other`. Save/reopen must retain the result, Cancel must preserve previous data, and non-PATH editing must expose no Remove duplicates action.

### Input validation and limits

For each applicable surface below, reset to a valid neutral draft between inputs, read the
actual field contents and commit enabled state, then Cancel. Retain every surface/input
observation; a representative sample cannot stand in for the complete matrix.

| Input group | Required observations |
|---|---|
| Name rules (P01) | Empty, whitespace-only, embedded `=`, leading whitespace and trailing whitespace cannot commit. A valid name re-enables commit; clearing disables it; cancel/reopen of Add starts disabled. |
| Length limits (P02) | Name length 259 accepted, 260 rejected. Variable `name + '=' + value` length 32766 accepted, 32767 rejected; calculate lengths independently. Profile names have only the name limit, not a variable-value constraint. |
| Duplicate names (P04) | Add/New rejects a case-insensitive duplicate. Edit permits its unchanged self-name but rejects another member's name. |

- [ ] **User and profile draft validation** [ID: EV-VALIDATION] [ADMIN: NO]
  Reuse owned duplicate fixtures to apply all P01/P02/P04 rows to User Add/Edit and profile New/Edit variable drafts. Apply all P01 name rules and the P02 name-length pair to both profile Add/Edit name fields. Never force an invalid saved variable or recreate the fixture for every input.

- [ ] **System draft validation** [ID: EV-VALIDATION-SYSTEM] [ADMIN: YES]
  With an elevated owned System fixture and exact machine-state restoration, apply all P01/P02/P04 rows to System Add and Edit. Keep these results separate from User/profile validation.

- [ ] **User and profile control-character input** [ID: EV-CONTROL-INPUT] [ADMIN: NO]
  Subject to provider/input fidelity, test control-character names on User Add/Edit, profile New/Edit variable and profile Add/Edit name surfaces; test embedded NUL values on the four variable surfaces. Invalid names/values must not be saved. Distinguish actual model rejection from input rejection/truncation; a truncated valid value does not prove backend NUL rejection. No clipboard input; missing System elevation does not block this case.

- [ ] **System control-character input** [ID: EV-CONTROL-INPUT-SYSTEM] [ADMIN: YES]
  With the authorized elevated System fixture, repeat control-character name and NUL-value checks for System Add/Edit, preserving per-input readback and the provider/model distinction. No clipboard or forced invalid writes; unavailable System coverage does not replace non-admin results.

- [ ] **Long backup names and total-entry limit** [ID: EV-LONG-BACKUP] [ADMIN: NO]
  Use an owned long-name fixture with independently calculated name/entry lengths and raw baselines. Valid individually authored variable/profile names whose generated backup exceeds 259 characters must apply: confirm the exact original backup value in native, Applied and HKCU. Unapply must restore the original and remove the backup on all surfaces. A generated backup exceeding total-entry length 32766 must instead be rejected without partial application or forced invalid registry writes.

- [ ] **Legacy invalid active profile** [ID: EV-LEGACY-PROFILE] [ADMIN: NO]
  Requires an isolated pre-existing legacy fixture and authorized restoration; do not corrupt live profiles to create it. Load a stored active profile with an invalid name and confirm it is disabled with the specific invalid-name warning, not a generic applicability message.

### Startup and environment notifications

- [ ] **Affected CJK startup variants** [ID: EV-CJK-STARTUP] [ADMIN: COND]
  With the affected CJK/default-language fixture and applicable #49069/#50027 fixes in the target build, verify normal and authorized elevated launches reach a titled editor without the startup fault. Ordinary startup is already covered by Settings launch and normal profile reopen; do not count it again here.

- [ ] **UTF-8 localized startup** [ID: EV-UTF8-STARTUP] [ADMIN: COND]
  Requires a build containing #50688, ACP 65001 and the localized fixture. Normal and authorized elevated launches must preserve the Unicode title and open successfully. Do not change system code page or reboot to prepare this shared session.

- [ ] **Environment notification filtering** [ID: EV-NOTIFICATIONS] [ADMIN: NO]
  Requires a build containing #50688 and an owned external-notification fixture, with original environment/listeners preserved. An actual external environment-change notification must produce the reload notice; product self-originated and unrelated settings notifications must not. Observe all three independently; startup locale is not notification coverage.

- [ ] **Clean-install defaults** [ID: EV-CLEAN-INSTALL] [ADMIN: NO]
  In a genuinely clean account/install fixture, confirm the module is initially disabled in both Runner and Settings and first Save does not flip it on. Do not delete this user's settings or infer defaults from current configured state.

### Command Palette integration

- [ ] **Entry, pinning and fallback isolation** [ID: EV-CMDPAL] [ADMIN: NO]
  Preserve original companion enablement, pins/order/provider settings and UI state. Invoke the Environment Variables command to open the editor and its Settings command to navigate to this module. Pin the module command and invoke it; change its fallback setting and confirm another command's setting is unchanged, then restore both and original pins/order. A disabled companion may be enabled through shipped UI when safely reversible; otherwise name the missing preservation capability. A working catalog missing a required shipped command is not merely an unattempted launch.

- [ ] **Command Palette localization** [ID: EV-CMDPAL-LOCALIZATION] [ADMIN: NO]
  With the non-English companion fixture, confirm Environment Variables commands in the PowerToys extension use the selected localized labels. Preserve companion state; ordinary entry/pinning and module labels do not substitute for this check.

### Appearance and localization

- [ ] **Light and dark caption glyphs** [ID: EV-THEME] [ADMIN: NO]
  On supported Windows with a reversible theme/Windows Settings navigation fixture, switch between light and dark themes. Independently confirm the theme and verify caption-button glyphs remain visible with correct foreground in each. Use caption-only captures, not current-image golden comparisons, and restore the original state.

- [ ] **Module localization** [ID: EV-LOCALIZATION] [ADMIN: NO]
  With an authorized non-English Windows-language fixture, confirm module labels and dialog actions match the selected translations. Restore the original locale; no language installation or reboot is implied.

### Diagnostics

- [ ] **Authorized diagnostic events** [ID: EV-TELEMETRY] [ADMIN: NO]
  With diagnostic collection/viewer consent and a provisioned viewer, perform owned module actions and find their corresponding utility events. Restore prior collection settings; do not silently enable telemetry or disclose unrelated event content.
