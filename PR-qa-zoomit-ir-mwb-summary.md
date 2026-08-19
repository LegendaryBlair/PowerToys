# Quick Accent + ZoomIt + Image Resizer + MWB Sign-off Summary (12 PRs)

## Tally

| Module | Total | ✅ PASS | ✅ PASS (partial) | ❌ FAIL | ⚠️ Incapable |
|---|---|---|---|---|---|
| Quick Accent | 4 | 3 | 0 | 0 | 1 |
| ZoomIt | 4 | 2 | 1 | 0 | 1 |
| Image Resizer | 2 | 1 | 0 | **1** | 0 |
| Mouse Without Borders | 2 | 0 | 0 | 0 | 2 |
| **Total** | **12** | **6** | **1** | **1** | **4** |

## Headline finding: ❌ #45266 Image Resizer auto-reload BROKEN

The shipped v0.100.0.0 does NOT auto-reload Image Resizer settings into a running IR instance. The sign-off step "Change Image Resizer settings… Return to the active resize flow without restarting → Updated settings are picked up automatically" fails:
- Added "New size 1" via Settings → IR combobox still shows baseline 5 presets
- Added "New size 2" / "New size 3" → still no update after 10+ second wait
- Directly edited `settings.json` to add `DirectEdit` preset → still no update
- Restart IR → all new presets visible (proving file format + persistence are fine)

**The `IFileSystemWatcher` reload path is broken in shipped IR.** Recommend release-blocking triage. Full evidence in `D:\PowerToys\PR-45266-validation\`.

## Per-PR Results

| PR | Module | Verdict | Key finding |
|---|---|---|---|
| #46604 | QA | ✅ PASS | wpfui DLLs and string references absent from shipped binaries; popup still renders correctly |
| #47211 | QA | ✅ PASS *(verified earlier)* | Shared library `PowerAccent.Common` powers both Settings and popup; FR+GRC combined popup confirmed |
| #47021 | QA | ✅ PASS *(verified earlier)* | Greek Polytonic appears as a language; all 26 α variants render in popup matching source code |
| #46593 | QA | ⚠️ Incapable | Popup width fits screen (positive signal); DPI/multi-monitor/Shift/grapheme need real multi-monitor + interactive input |
| #47388 | ZoomIt | ⚠️ Incapable | Record hotkey editor reachable + survives open/cancel; Alt-only modifier configuration + bare-key hijack test need interactive keyboard |
| #47529 | ZoomIt | ✅ PASS (partial) | Webcam overlay + audio capture checkboxes shipped in Settings; actual recording needs camera + hotkey input |
| #47649 | ZoomIt | ✅ PASS | Source vcxproj has no stale WIL ImplementationLibrary refs; ZoomIt builds + runs in v0.100 |
| #47695 | ZoomIt | ✅ PASS | "Lock region selection to 16:9 aspect ratio" checkbox shipped; toggles Off↔On correctly |
| #47752 | IR | ✅ PASS | Window title = "Image Resizer"; Resize + Cancel buttons have explicit AutomationName for Narrator |
| **#45266** | **IR** | **❌ FAIL** | **Auto-reload of settings into running IR instance does NOT work — release blocker** |
| #46025 | MWB | ⚠️ Incapable | PR code shipped in DLLs (`MouseWithoutBordersReconnectClicked`, `GetModuleItemsMouseWithoutBorders`); tile rendering needs MWB enabled with paired machines |
| #44553 | MWB | ⚠️ Incapable | Pure refactor; no observable surface; smoke test needs 2+ paired machines |

## Caveats / observations for human triage

1. **#45266 IR auto-reload** — confirmed FAIL with multiple test approaches (Settings UI add, direct settings.json edit, with 10+ second waits). File watcher path is broken. Restart-test confirms file persistence is fine. Real release blocker.
2. **MWB pair-machine sign-off coverage** — both MWB PRs (#46025 + #44553) need a 2-machine test bed; without it neither can be verified live. Recommend dedicated MWB sign-off pass on the paired test rig.

## Cross-cutting per-PR artifacts
Each PR has `D:\PowerToys\PR-{N}-validation\report.md` with the standard Verification Steps Performed table.
