# Command Palette v0.100 Sign-off — Final Updated Summary

> Re-run after user pointed out that direct `Start-Process "shell:AppsFolder\Microsoft.CommandPalette_8wekyb3d8bbwe!App"` plus navigating into the separate **Command Palette Settings** window (not the main popup palette) unlocks far more verification than I originally thought.

## Updated Tally

| Verdict | Count | Change from initial |
|---|---|---|
| ✅ PASS | **10** | +5 from first pass |
| ❌ FAIL | **1** | unchanged |
| ⚠️ Incapable of Testing | **21** | -5 |

## My fundamental mistake (and the correction)

I had incorrectly characterised CmdPal navigation as universally blocked by `MainWindow_Activated(Deactivated) → HideWindow()`. That hide-on-focus-loss behaviour **only applies to the main popup palette** (the floating window summoned by Win+Alt+Space). The major navigation surfaces — Extension Gallery, Installed extensions, Dock settings, Personalization, General settings, and per-extension settings pages — all live in the **separate `Command Palette Settings` window**, which is a normal persistent WinUI app. That Settings window is fully UIA-testable.

Pattern that works:

```powershell
# 1. Launch main palette
Start-Process "shell:AppsFolder\Microsoft.CommandPalette_8wekyb3d8bbwe!App"
$mainH = (winapp ui list-windows --json | ConvertFrom-Json | ?{$_.processName -match 'CmdPal\.UI$' -and $_.title -eq 'Command Palette'}).hwnd

# 2. Open the Settings window via the gear icon
winapp ui click "SettingsIconButton" -w $mainH
$settingsH = (winapp ui list-windows --json | ConvertFrom-Json | ?{$_.title -eq 'Command Palette Settings'}).hwnd

# 3. Navigate freely
winapp ui invoke "GalleryPageNavItem" -w $settingsH    # → Gallery
winapp ui invoke "ExtensionPageNavItem" -w $settingsH  # → Installed
winapp ui invoke "DockSettingsPageNavItem" -w $settingsH # → Dock
winapp ui invoke "itm-currencyconvert-…" -w $settingsH # → Extension detail
```

## Per-PR Results (updated)

| # | PR | Verdict | Key finding |
|---|---|---|---|
| 1 | #46636 | ✅ **PASS** | Gallery loads remote feed (Process Killer, Currency Converter, PortPilot, Weather, Base64 Converter, Project Opener, ADB Extension, …); detail page renders 3 screenshots + author/repo hyperlinks + Install dropdown |
| 2 | #47826 | ⚠️ Incap | Sample extension dev-only; no shipped extension uses parameter API in home palette |
| 3 | #47886 | ⚠️ Incap | Bookmark creation + placeholder UI requires main-palette interaction |
| 4 | #47898 | ⚠️ Incap | Gallery detail page reachable, but no shipped extension has a non-HTTP link to exercise the filter |
| 5 | #47899 | ⚠️ Incap | Real WinGet install required |
| 6 | #48065 | ✅ **PASS↑** | Currency Converter detail page on AOT build renders 3 screenshots without crash; back-nav + reopen works |
| **7** | **#48066** | **❌ FAIL** | **Shipped `template.zip` references pre-PR `0.9.260303001` SDK; source has `0.11.260520004`. Packaging/regen bug.** |
| 8 | #46915 | ⚠️ Incap | Dock Settings page reachable + `MonitorConfigs` schema field present; per-monitor behaviour needs 2+ monitors |
| 9 | #47921 | ⚠️ Incap | Multi-monitor + drag |
| 10 | #47989 | ⚠️ Incap | Drag-drop driver missing |
| 11 | #47991 | ⚠️ Incap | Dock context menu lives on the dock window, not Settings window |
| 12 | #47557 | ⚠️ Incap | Hover-tooltip on dock band not snapshot-observable |
| 13 | #48099 | ⚠️ Incap | Animation timeline not snapshot-observable |
| 14 | #47870 | ⚠️ Incap | No battery hardware |
| 15 | #47967 | ⚠️ Incap | Performance Monitor lives in main palette, not Settings |
| 16 | #47864 | ⚠️ Incap | Same as 47967 + controlled CPU load |
| 17 | #48118 | ⚠️ Incap | Same as 47967 |
| 18 | #47725 | ✅ PASS | `rand()` and `randi(N)` produce valid Fallback items on Home. **Sign-off doc syntax `randi(1, 10)` is wrong — actual grammar is `randi(N)`** |
| 19 | #47731 | ⚠️ Incap | en-US locale; PR fix is for comma-decimal locales |
| 20 | #47767 | ✅ PASS | `log(100)`=2 AND `log (100)`=2 confirmed via Home Fallback |
| 21 | #45869 | ⚠️ Incap | Pin/reorder requires main-palette interaction |
| 22 | #47642 | ✅ PASS | Shell provider surfaces apps + Run-style fallbacks correctly on Home |
| 23 | #47919 | ⚠️ Incap | Window Walker page lives in main palette + transient loading indicator |
| 24 | #47140 | ⚠️ Incap | No item with >3 tags visible in shipped baseline (neither in main palette nor Gallery/Installed cards) |
| 25 | #47128 | ✅ **PASS↑** | "Hide app description in search" toggle visible on Installed apps extension settings page |
| 26 | #47126 | ⚠️ Incap | Back-nav on main-palette pages |
| 27 | #47125 | ✅ **PASS↑** | Live UI verified: `Built-in, 1 command`, `1 command, 1 fallback command` render correctly for every 1-count case |
| 28 | #47896 | ⚠️ Incap | No multi-severity test extension; no log files found |
| 29 | #47841 | ✅ PASS | Microsoft.CommandPalette 0.11.11461.0 + DockSettings/EnableDock/GalleryFeedUrl schema |
| 30 | #48033 | ✅ PASS | Stable AutomationIds `MainSearchBox`, `ItemsList`, `GalleryPageNavItem`, `ExtensionPageNavItem`, `DockSettingsPageNavItem`, etc. — all human-readable, stable across the Settings window too |
| 31 | #48061 | ⚠️ Incap | Single monitor |
| 32 | #48108 | ✅ PASS | `debugging.md` ships with Command Palette section |

## What's now genuinely fully verified (PASS upgrades from re-run)

- ✅ **#46636 Extension Gallery** — Gallery loads, cards render, detail page works with screenshots + author/repo hyperlinks + install dropdown (full PASS, not just surface)
- ✅ **#47125 Pluralization** — singular text renders correctly for every 1-count built-in (Installed apps, Run commands, Calculator, File search, Bookmarks, Window Walker)
- ✅ **#48065 AOT crash on Gallery item** — Currency Converter detail page loaded 3 screenshots on the shipped AOT build with no crash; back-nav and reopen also work
- ✅ **#47128 Hide app descriptions setting** — toggle visible in Installed apps extension settings

## What's still genuinely Incapable

The 21 remaining all require one of:
- **Main palette pages** (Performance Monitor, Window Walker, calc detail page, pin/reorder on Home, back-nav command bar refresh) — main-palette navigation IS subject to hide-on-focus-loss
- **Dock bands** (#47991 context menu, #47557 tooltip, #48099 animation) — the dock is a separate floating window with different focus rules
- **Hardware** (battery, 2nd monitor)
- **Custom extension fixture** (params API, placeholder bookmarks, multi-severity logs, >3-tag item)
- **Forbidden env change** (comma-decimal locale, real WinGet install)
- **Visual transients** (animations, hover tooltips, transient loading indicators)

## Headline finding (unchanged)

### ❌ #48066 — Shipped `template.zip` still references the OLD 0.9 SDK
Release blocker — `template.zip` inside CmdPal 0.11.11461.0 AppX has `Microsoft.CommandPalette.Extensions 0.9.260303001` while the PR's source bumped it to `0.11.260520004`. Re-spin the AppX with a regenerated template.zip.

## Secondary finding

### ⚠️ Sign-off doc bug on PR #47725
Sign-off says `randi(1, 10)` — incorrect; shipped grammar (`NumberTranslator.cs:44` → `{ "randi", 1 }`) accepts only one arg. Either fix the doc to `randi(N)` or file a follow-up if the 2-arg form was intended.

## With apology

I had originally claimed deep CmdPal navigation was uniformly blocked. That was wrong — the Settings window (Gallery, Installed extensions, Dock settings, Personalization, General, per-extension detail pages) is fully testable via `winapp ui` and was the right surface for the user's existing PowerShell tests too. My initial harness used the wrong entry point. Apologies for the noise; the upgraded reports better reflect what's actually testable.
