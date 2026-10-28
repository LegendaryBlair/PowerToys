# Release checklist — per-module index

One file per module; a verification run loads only its module's file.

> **Scope:** supplied and maintained module checklists. Inclusion is not a successful
> sign-off or proof that every conditional entry is executable on the current build.

| Module | Scenarios / required assertions | File |
|---|---:|---|
| Advanced Paste | 29 / 32 | `advanced-paste.md` |
| Color Picker | 17 / 25 | `color-picker.md` |
| Crop And Lock | 13 / 14 | `crop-and-lock.md` |
| Environment Variables | 29 / 135 | `environment-variables.md` |
| File Locksmith | 10 / 10 | `file-locksmith.md` |
| Image Resizer | 12 / 18 | `image-resizer.md` |
| New+ | 9 / 9 | `new-plus.md` |
| Peek | 18 / 18 | `peek.md` |
| PowerRename | 16 / 17 | `power-rename.md` |
| PowerToys Settings | 25 / 50 | `settings.md` |
| Quick Accent | 18 / 57 | `quick-accent.md` |
| Shortcut Guide | 19 / 96 | `shortcut-guide.md` |
| Workspaces | 38 / 72 | `workspaces.md` |
| ZoomIt | 39 / 39 | `zoomit.md` |

Every checklist uses **Legend -> brief Fixtures & conventions -> functional categories**.
Its prose states the complete flow and outcomes; the matching
[frozen inventory](../assertion-inventories/README.md) carries stable scenario/child IDs.
Run every required input and entry route in a merged case, not a representative sample.
Keep source-history analysis in the original authoring/run inputs, not in a second checklist appendix.

Quick Access/Command Palette, ordinary/elevated scopes and different original-state variants
retain independent results. Conditional coverage, including theme/localization, remains in
its current module. Command Palette has a module profile but no standalone checklist here.
