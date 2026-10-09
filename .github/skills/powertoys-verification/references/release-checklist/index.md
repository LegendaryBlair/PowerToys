# Release checklist — per-module index

One file per module; a verification run loads only its module's file.

> **Scope:** supplied and maintained module checklists. Inclusion is not a successful
> sign-off or proof that every conditional entry is executable on the current build.

| Module | Items | File |
|---|---:|---|
| Advanced Paste | 41 | `advanced-paste.md` |
| Color Picker | 17 scenarios / 25 assertions | `color-picker.md` |
| Environment Variables | 29 scenarios / 135 assertions | `environment-variables.md` |
| File Locksmith | 10 | `file-locksmith.md` |
| Image Resizer | 18 | `image-resizer.md` |
| New+ | 9 | `new-plus.md` |
| Peek | 18 | `peek.md` |
| PowerRename | 17 | `power-rename.md` |
| PowerToys Settings | 29 | `settings.md` |
| Shortcut Guide | 19 | `shortcut-guide.md` |
| Workspaces | 40 | `workspaces.md` |

Shortcut Guide's 19 execution scenarios retain the mapping to 27 legacy requirement groups
and named assertions. Quick Access and Command Palette are evaluated independently;
animation and frame-by-frame visual effects are excluded from acceptance. SG-SEARCH retains
12 core assertions; full focus traversal, visible-focus auditing and speech are out of scope.

Environment Variables groups cases by function, with detailed child definitions in its
assertion inventory. Ordinary/elevated input scopes and originally-absent/existing-value
applied-edit fixtures remain separate; build and locale conditions are stated per case.
