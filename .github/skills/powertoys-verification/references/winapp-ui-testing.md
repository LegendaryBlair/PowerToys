# WinUI UI-testing mechanics (winapp ui)

> **Provenance:** Adapted from the `winui-ui-testing` skill in [microsoft/win-dev-skills](https://github.com/microsoft/win-dev-skills) (MIT, © Microsoft Corporation and Contributors), with PowerToys-specific edits. This is a **reference doc** for the `powertoys-verification` skill — it is intentionally not a standalone skill (no frontmatter), so it is not separately discovered.

Automated UI testing for WinUI 3 apps — generate a batch test script, run all tests in one pass, read results. Covers element assertions, interactions, value checking (TextBox, ComboBox, ToggleSwitch), file pickers, flyouts, dialogs, persistence, and accessibility audits.

### Documentation freshness

Use [the toolchain policy](winapp-toolchain.md) before a new run: resolve the latest official
stable tool unless explicitly pinned, then read the matching release-tag UI documentation
and installed command help/schema. This local reference retains PT-specific safety and
integration guidance; it is not an automatically updated upstream manual. Do not assume
that examples from upstream `main` work with an older installed executable.

### Approach

The goal of this skill is to validate UI and app functionality automatically, without manual interaction, by exercising the app's UI elements, verifying their state, and asserting that the app behaves as expected under test conditions.

There are two main approaches:
1. Interactive exploration — manually run the app, use `winapp ui <command>` to explore the UI tree, find AutomationIds, verify element properties, and test functionality interactively. This is useful for discovery, but slow and expensive if repeated for every test iteration.
2. Scripted batch testing — generate a `ui-tests.ps1` script that exercises all UI elements and asserts expected behavior in one pass. This allows you to run the tests automatically, capture results, and iterate quickly without manually interacting with the app each time.

Unless the user asked for interactive exploration, or you are unfamiliar with the code/app or need to explore the UI tree to discover AutomationIds for hidden or dynamically generated elements (flyouts, dialogs, lazy-loaded content), **prefer scripted batch testing** — it is faster, repeatable, and produces a record of pass/fail results that can be reviewed and acted on.

### `winapp ui` Verbs

`status`, `inspect`, `search`, `get-property`, `get-value`, `screenshot`, `invoke`, `click`, `set-value`, `focus`, `scroll`, `scroll-into-view`, `wait-for`, `list-windows`, `get-focused`. Run `winapp ui --cli-schema` for the complete command structure as JSON, or `winapp ui <verb> --help` for any single verb.

### Scoped and typed queries

Official [v0.7.1 query documentation](https://github.com/microsoft/winappCli/blob/v0.7.1/docs/ui-automation.md#scoped-and-typed-queries)
introduces `--root`, `--type` and `--class-name` for `search`, `get-property`, `get-value`
and `wait-for`. Treat this as the example's capability floor, not a hardcoded latest version;
check the selected executable's help and matching docs.

Keep module-specific query text, parent scope, type and class in the profile's interaction
table. The generic response handling belongs here, not in a separate driver section for
each card. For a row declaring all these filters, use the table's values in a recorded step:

```powershell
$arguments = @('search',$queryText,'-w',"$hwnd",'--root',$rootSelector,
    '--type',$controlType,'--class-name',$className,'--json')
$result = ConvertFrom-PtReportJson (Invoke-PtWinApp -Arguments $arguments -SkipRecording)
if ($result.matchCount -ne 1 -or @($result.matches).Count -ne 1 -or $result.hasMore -ne $false) {
    throw 'Expected one current scoped control; no action issued.'
}
$selector = $result.matches[0].selector
```

Include only the filters declared by the locator; not every control requires a root or class.
Keep sensitive query results private and output only approved metadata to the outer recorder.

All supplied filters apply to the same element. `--root` searches descendants of one unique
root, excluding the root itself; `--type` is the UIA control type, and `--class-name` is a
literal complete provider ClassName, not a CSS class or regex. Filtered queries use Control
View. Do not mix a result with a separate managed/raw-view tree and assume identical nodes.
Name-based query text follows the actual UI language; prefer stable AutomationIds when available.

Require exactly one returned match and `hasMore=false` before a single-target action.
Use its newly returned selector; do not freeze a runtime slug or HWND in the profile.
In v0.7.1 these query options do **not** attach directly to `invoke`: query first, then pass
the resolved selector. That version supports `invoke --action expand` (and other explicit
actions), without automatic pattern/ancestor fallback. This is an action contract, not proof
that every provider supports the requested pattern. Re-observe the actual result.

Increasing `inspect --depth` does not expand an app's card. Conversely, reading the state
of a visible header button does not require opening its card. For example:

```powershell
Invoke-PtWinApp -Arguments @('get-property',$buttonAutomationId,
    '-w',"$hwnd",'--property','IsEnabled','--json')
```

Record independent header-button properties before any row-expansion work. A failed expansion
cannot erase an already observed button state. Sensitive module reads still require
their documented private outer-recorded-step boundary; do not publish a full environment tree.

### Step 1: Use the Running App

If the app is already running, use its PID. **Do NOT relaunch** — use the PID already captured from the build step. If the app is not running, build and launch it using the guidance in the winui-dev-workflow skill.

### Step 2: Write the Test Script

**If you wrote the code:** Skip inspect — you already know all the AutomationIds and control structure from the XAML and code-behind. Write tests directly from that knowledge. Inspect misses popups, flyouts, dialogs, and lazy-loaded content anyway.

**If you're verifying code you didn't write:** Run inspect first to discover the UI:
```powershell
winapp ui inspect -a <PID> --interactive
```
Then read the XAML files to find AutomationIds that aren't currently visible (flyout items, dialog buttons, secondary pages).

Create a `ui-tests.ps1` file that tests all the app's requirements in one pass:

```powershell
# ui-tests.ps1
param([Parameter(Mandatory)][int]$AppPid)
# NOTE: Do NOT name the parameter $Pid — it's read-only in PowerShell

$ErrorActionPreference = 'Continue'
$pass = 0; $fail = 0; $results = @()

# Get main window HWND (avoids PopupHost interference with JSON parsing)
$windows = winapp ui list-windows -a $AppPid --json 2>$null | ConvertFrom-Json
$hwnd = ($windows | Where-Object { $_.title -ne "PopupHost" } | Select-Object -First 1).hwnd

function Test-UI {
    param([string]$Name, [scriptblock]$Script)
    # IMPORTANT: Inside $Script, use 'throw' to signal failure — NOT 'exit 1'
    # (exit terminates the entire script, not just the test)
    try {
        $output = & $Script 2>&1
        if ($LASTEXITCODE -eq 0) {
            $script:pass++; $script:results += @{ name = $Name; status = "PASS" }
        } else {
            $script:fail++; $script:results += @{ name = $Name; status = "FAIL"; detail = "$output" }
        }
    } catch {
        $script:fail++; $script:results += @{ name = $Name; status = "FAIL"; detail = "$_" }
    }
}

# ─── Element Existence ───
Test-UI "NavHome exists" { winapp ui wait-for "NavHome" -a $AppPid -t 3000 }
Test-UI "NavSettings exists" { winapp ui wait-for "NavSettings" -a $AppPid -t 3000 }

# ─── Navigation ───
Test-UI "Navigate to Settings" { winapp ui invoke "NavSettings" -a $AppPid }
Test-UI "Settings page loaded" { winapp ui wait-for "TxtUserName" -a $AppPid -t 3000 }

# ─── Interactions ───
Test-UI "Set username" { winapp ui set-value "TxtUserName" "TestUser" -a $AppPid }
Test-UI "Click Save" { winapp ui invoke "BtnSave" -a $AppPid }  # commits the TextBox binding
Test-UI "Username value set" {
    winapp ui wait-for "TxtUserName" -a $AppPid --value "TestUser" -t 2000
}

# ─── Value assertions for different control types ───
Test-UI "Theme is System default" {
    winapp ui wait-for "CmbTheme" -a $AppPid --value "System default" -t 2000
}
Test-UI "Logging is off" {
    winapp ui wait-for "TglLogging" -a $AppPid --value "Off" -t 2000
}

# ─── Accessibility Audit ───
# Only audit controls in the app's main window (exclude OS picker/popup controls)
$allElements = (winapp ui inspect -a $AppPid --interactive --json 2>$null | ConvertFrom-Json).elements
$appElements = @($allElements | Where-Object {
    $_.type -match 'Button|TextBox|ComboBox|CheckBox|ToggleSwitch|TabItem|Edit' -and
    $_.name -notmatch 'Minimize|Maximize|Close|System' -and          # window chrome
    $_.className -notmatch 'PickerHost|#32770|CabinetWClass'         # OS dialogs
})
$missingId = @($appElements | Where-Object { -not $_.automationId })
if ($missingId.Count -eq 0) {
    $pass++; $results += @{ name = "All app controls have AutomationId"; status = "PASS" }
} else {
    $fail++
    $names = ($missingId | ForEach-Object { "$($_.type) '$($_.name)'" }) -join ", "
    $results += @{ name = "AutomationId coverage"; status = "FAIL"; detail = "Missing: $names" }
}

# ─── State Screenshots (capture each meaningful state for visual review) ───
New-Item -ItemType Directory -Force -Path "screenshots" | Out-Null
winapp ui screenshot -a $AppPid -o "screenshots/01-initial.png" 2>$null
# ...take more screenshots after key interactions above (mode switches, dialogs opened, etc.)

# ─── Final Screenshot ───
winapp ui screenshot -a $AppPid -o "test-screenshot.png" 2>$null

# ─── Results ───
Write-Host "`nPassed: $pass | Failed: $fail"
$results | Where-Object { $_.status -eq "FAIL" } | ForEach-Object {
    Write-Host "  FAIL: $($_.name) — $($_.detail)" -ForegroundColor Red
}
$results | ConvertTo-Json | Out-File "test-results.json"
if ($fail -gt 0) { exit 1 } else { exit 0 }
```

### What to Test

Write tests for **every requirement** from the user's prompt:

| Requirement type | Test approach |
|---|---|
| "Has a button that does X" | `search` to verify exists, `invoke` to click, `wait-for --value` to check result |
| "Text field shows value" | `wait-for "TxtName" --value "expected"` — works for TextBox, TextBlock, labels |
| "Status bar contains text" | `wait-for "StatusBar" --value "words" --contains` — substring match for dynamic content |
| "Dropdown is set to X" | `wait-for "CmbTheme" --value "Dark"` — reads the selected item automatically |
| "Toggle is on/off" | `wait-for "TglFeature" --value "On"` — reads the toggle state |
| "Navigation between pages" | `invoke` nav item, `wait-for` a page-specific element to appear |
| "Open file dialog" | `invoke` trigger, `list-windows` to find picker HWND, interact with `-w` |
| "Save file dialog" | Same as open — find picker with `list-windows`, `set-value` filename, `invoke` Save |
| "Right-click context menu" | `click --right` on element, `invoke` the flyout MenuItem |
| "Confirmation dialog" | `invoke` trigger, `search` for dialog buttons, `invoke` Primary/Secondary/Close |
| "Data persists" | Set values, `invoke` a button (to commit bindings), verify data file on disk (`Get-Content` + `ConvertFrom-Json`) |
| "All controls accessible" | `inspect --interactive --json` + check all have AutomationId |

### Step 3: Run and Read Results

```powershell
.\ui-tests.ps1 -AppPid <PID>
```

Read `test-results.json` for structured pass/fail. Only fix code if tests fail.

### Step 3.5: Look at the Screenshots

For PowerToys verification, use `Save-PtPassiveScreenshot` for menus, overlays and held-input
observations; even a window-targeted `winapp ui screenshot` can change focus. Supply a stable
state probe and reject a capture whose before/after state differs. See
[helper workflow](helper-workflow.md#input-ownership-and-observation). For recorded native
operations use `Invoke-PtWinApp` with arguments after `winapp ui`; direct executable calls
inside legacy snippets are not automatically recorded.

UIA assertions don't see clipping, overlap, wrong theming, or controls bleeding past their container — UIA returns `PASS` while the app is visually broken. **Capture screenshots with `winapp ui screenshot` and view each PNG.**

Capture the initial state and any state after a major interaction (the State Screenshots block in the script template above handles this).

**Visual checklist — fail the run if any item is `no`:**
- [ ] No unintended scrollbars
- [ ] No text ending in `…` that shouldn't be
- [ ] Hero elements fully visible (not sliced)
- [ ] Right-edge controls fully visible
- [ ] No overlapping rows
- [ ] Content uses the available width — no asymmetric dead zones (e.g. content pinned to one edge leaving empty space on the other)
- [ ] Spacing intentional — not cramped, not unintentionally vast
- [ ] Theming matches the user's ask (Light/Dark/HighContrast if relevant)
- [ ] Focus/hover/error states render if tested

If the checklist fails, it's a bug — fix before declaring done. Window too small → grow per `winui-design` Step 4.

### Step 4: Fix and Rerun (if the user asked for it)

If tests fail:
1. Read the failure details from `test-results.json`
2. Batch-fix all issues in one pass
3. Rebuild with `.\BuildAndRun.ps1` (blocking mode — shows crash info if the fix broke something)
4. Rerun `.\ui-tests.ps1 -AppPid <PID>` (parse PID from the `launched (PID: XXXXX)` output)

**Maximum 2 fix-and-rerun cycles.** If the same tests keep failing after 2 cycles, report them as known issues and move on — do not keep iterating.

### Assertion Reference

Use `wait-for --value` as the primary assertion — it uses a smart fallback chain that reads the right value for any control type:

| Control type | `--value` reads from | Example |
|---|---|---|
| TextBlock / Label | Name property | `wait-for "LblTitle" --value "Home"` |
| TextBox / NumberBox | ValuePattern | `wait-for "TxtName" --value "John"` |
| RichEditBox | TextPattern | `wait-for "Editor" --value "Hello"` |
| ComboBox | Selected item (SelectionPattern) | `wait-for "CmbTheme" --value "Dark"` |
| ToggleSwitch | Toggle state (On/Off) | `wait-for "TglDark" --value "On"` |
| CheckBox | Toggle state (On/Off) | `wait-for "ChkAgree" --value "On"` |

**Full assertion commands:**

| Assertion | Command |
|---|---|
| Element exists | `winapp ui wait-for "Id" -a PID -t 3000` |
| Element has exact value | `winapp ui wait-for "Id" -a PID --value "expected" -t 3000` |
| Value contains text | `winapp ui wait-for "Id" -a PID --value "words" --contains -t 3000` |
| Element gone | `winapp ui wait-for "Id" -a PID --gone -t 3000` |
| Specific property | `winapp ui wait-for "Id" -a PID -p IsEnabled --value "True" -t 3000` |
| Button clickable | `winapp ui invoke "Id" -a PID` (exit code 0) |
| Set then verify | `winapp ui set-value "Id" "text" -a PID` then `wait-for --value` |
| Screenshot | `winapp ui screenshot -a PID -o path.png` |
| Dialog appeared | `winapp ui list-windows -a PID --json` (check window count) |
| Right-click menu | `winapp ui click "Id" -a PID --right` then `wait-for` menu item |
| Read raw property | `winapp ui get-property "Id" -a PID -p IsEnabled --json` |
| Read current value (no wait) | `(winapp ui get-value "Id" -a PID --json \| ConvertFrom-Json).text` — always pass `--json` when capturing into a variable (plain stdout can include advisory text like "Auto-selected HWND … from N windows"); otherwise prefer `wait-for --value` |
| Scroll item into view | `winapp ui scroll-into-view "Id" -a PID` — call before `wait-for` on virtualized ListView/repeater items below the fold |
| Set keyboard focus | `winapp ui focus "Id" -a PID` — cleaner than clicking another control to trigger a TextBox `LostFocus` commit |

### Selecting a ComboBox / dropdown item

*Reading* a ComboBox's current value is one step (`wait-for "Cmb" --value "Dark"`); **changing** the selection takes three, because a collapsed ComboBox's options are not in the UIA tree until it is expanded:

1. **Expand** - `winapp ui invoke <cmb-id>` (fires ExpandCollapsePattern; the dropdown opens).
2. **Inspect while open** - the options now appear as `ListItem`s in a popup with their **own ids** (e.g. `itm-<option>-<suffix>`), distinct from the combo's id. Resolve the target: `winapp ui search '<option text>' -w <hwnd> --json` and pick the match with `type -eq 'ListItem'`.
3. **Invoke that ListItem id** - `winapp ui invoke <itm-id>` (fires SelectionItemPattern). Verify with `wait-for <cmb-id> --value "<option>"`.

**Trap:** after expanding, do **not** invoke the option by its caption text - the text match lands on the child `Text` label, not the selectable `ListItem`, and silently no-ops. Always resolve and invoke the `itm-...` id, not the caption and not the collapsed combo id.

### Testing File Pickers

File/folder pickers (FileOpenPicker, FileSavePicker, FolderPicker) run in a separate `PickerHost` process but are fully interactable. The picker appears as an owned dialog window.

```powershell
# 1. Trigger the picker
winapp ui invoke "BtnOpenFile" -a $AppPid

# 2. Find the picker window (it's a dialog owned by the app window)
Start-Sleep 1
$allWindows = winapp ui list-windows -a $AppPid --json 2>$null | ConvertFrom-Json
$picker = $allWindows | Where-Object { $_.title -match "Open|Save" }
$pickerHwnd = $picker.hwnd

# 3. Interact with the picker using -w <HWND>
#    Type a filename:
winapp ui set-value "FileNameControlHost" "test.txt" -w $pickerHwnd
#    Click Open/Save:
winapp ui invoke "Open" -w $pickerHwnd     # or "Save", "Cancel"
#    Or cancel:
winapp ui invoke "Cancel" -w $pickerHwnd

# 4. Verify the app processed the file
winapp ui wait-for "StatusBar" -a $AppPid -p Name --value "opened" -t 3000
```

**Tip:** Use `winapp ui inspect -w <pickerHwnd> --interactive` to discover the picker's controls — they include the folder tree, file list, filename textbox, and Open/Cancel buttons.

### Testing Context Menus and Flyouts

MenuFlyouts and ContextFlyouts are fully testable. They appear in the UI automation tree when open.

```powershell
# 1. Right-click to open a ContextFlyout
winapp ui click "LstItems" -a $AppPid --right
Start-Sleep 0.5

# 2. The flyout MenuItems appear in the tree immediately
#    Find them with inspect or search:
winapp ui inspect -a $AppPid --interactive   # shows MnuCopy, MnuDelete, etc.

# 3. Click a flyout item
winapp ui invoke "MnuCopy" -a $AppPid

# 4. Verify the action
winapp ui wait-for "StatusText" -a $AppPid -p Name --value "Copied" -t 2000
```

**For MenuBar flyouts** (File, Edit, View menus):
```powershell
# Click the menu header to open
winapp ui invoke "FileMenu" -a $AppPid
Start-Sleep 0.5
# Click the sub-item
winapp ui invoke "MenuSaveAs" -a $AppPid
```

### Testing ContentDialogs

ContentDialogs are in-app controls (same window) — they appear directly in the UI tree when shown.

```powershell
# 1. Trigger the dialog
winapp ui invoke "BtnDelete" -a $AppPid
Start-Sleep 0.5

# 2. The dialog buttons appear in the tree
#    For a standard confirmation dialog:
winapp ui search "Primary" -a $AppPid --json   # finds the primary button
winapp ui invoke "Primary" -a $AppPid           # click "Yes"/"Delete"/"Save"
#    Or:
winapp ui invoke "Secondary" -a $AppPid         # click "No"/"Don't Save"
winapp ui invoke "Close" -a $AppPid             # click "Cancel"

# 3. Wait for dialog to dismiss
winapp ui wait-for "Primary" -a $AppPid --gone -t 3000
```

**Tip:** ContentDialog buttons often don't have custom AutomationIds — use `inspect` to find the actual selector (slug or text match).

### Key Gotchas

- **`set-value` does NOT commit default TextBox bindings** — WinUI 3 `x:Bind TwoWay` on TextBox.Text updates the ViewModel on `LostFocus` by default. UIA `set-value` changes the text but doesn't trigger focus events. **Fix:** apps should use `UpdateSourceTrigger=PropertyChanged` on TextBox bindings (see design skill). If the app doesn't, `invoke` a button or `click` another element after `set-value` to trigger `LostFocus`.
- **Verify persistence via the data file, not UI relaunch** — killing and relaunching a packaged app from a test script is fragile (MSIX registration timing, PID issues). Instead, check the data file on disk: `Get-Content $dataFile | ConvertFrom-Json` and verify expected values.
- **Use `$AppPid` not `$Pid`** — `$Pid` is a read-only automatic variable in PowerShell
- **Use `--value` without `-p`** — it auto-detects the right UIA pattern (TextPattern → ValuePattern → TogglePattern → SelectionPattern → Name). Only use `-p PropertyName --value` when you need a specific property like `IsEnabled`
- **File pickers need `-w <HWND>`** — they run in a separate PickerHost process, so `-a PID` won't find them. Use `list-windows` to discover the picker HWND first
- **Flyouts need a short `Start-Sleep`** after triggering — the menu items appear in the tree asynchronously

### Large text fixtures and the Windows command-line limit

A near-32767-character test value plus the executable path and CLI arguments can exceed
Windows' process command-line limit before `winapp` starts. This is a driver limitation,
not application validation. For an explicitly owned synthetic draft, use a scoped
in-process UIA `ValuePattern.SetValue` call inside the recorded step, then independently
read the actual field value and enabled state. Preserve the requested boundary rather
than reducing the test value. Keep private values out of recorded arguments and output.

### Restart actions can invalidate their own UIA target

A restart or close action may take effect while `winapp ui invoke` is still
inspecting its target. The command can then report a missing element or unsupported
pattern even though the application has exited. Preserve the command error and
check the recorded PID/start-time transition before retrying; do not conclude that
the button is inert from that error alone.

For language changes, resolve the replacement Settings window and inspect the
actual language after restart. Rollback must also handle a disappeared original
Settings process. Keep this recovery separate from the Normal-path verdict.

### CRITICAL — `invoke` vs `click`: choose the right verb

Use the selected CLI's supported action syntax and inspect the target's actual patterns.
UIA invocation dispatches a provider action rather than a physical click; it does not prove
mouse hit-testing, nor does a Button/ListItem type guarantee that the needed pattern is exposed.
Provider access and effects on focus must be observed, not inferred from WinUI/AppX identity.

Physical input needs an attached input desktop, a guarded target and compatible integrity.
SendInput can inject into equal- or lower-integrity applications; an elevated injector is not
categorically blocked from a non-elevated AppX. Foreground/hit-target changes can still dismiss
popups or send input elsewhere. See the [SendInput contract](https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-sendinput).

Prefer the appropriate UIA action when the claim permits it. Use a physical click when that route
is under test or when a safely established alternative is necessary, then observe the actual outcome.

### CRITICAL — DataTemplate AutomationId vs ListItem InvokePattern

When XAML binds `AutomationProperties.AutomationId="{x:Bind <DataProperty>}"` inside a `ListView.ItemTemplate`'s `<DataTemplate>`, the AutomationId lives on the **inner Grid (Group)** the template produces — NOT on the outer ListItem the ListView wraps around it. The outer ListItem is what carries `InvokePattern`.

Concrete example (CmdPal PR #48033 binds Command.Id this way):

```powershell
# This FAILS with "does not support any invoke pattern":
winapp ui invoke 'com.microsoft.cmdpal.calculator' -w $hwnd
#   Element grp-commicrosoftcmd-XXXX (Group) does not support any invoke pattern.
#   No invokable ancestor was found.

# This WORKS — find by Name (matches all 3 siblings), pick the ListItem child:
$r = winapp ui search 'Calculator' -w $hwnd --json | ConvertFrom-Json
$li = $r.matches | Where-Object type -eq 'ListItem' | Select-Object -First 1
winapp ui invoke $li.selector -w $hwnd    # selector like 'itm-calculator-7e3f'
```

If you encounter "does not support any invoke pattern" while trying to use a data-bound AutomationId, this is almost always the cause. The fix is to search by Name and invoke the sibling ListItem.

### CRITICAL — Message-based input (PostMessage)

Check the selected CLI's actual input capabilities before introducing a native fallback.
`PostMessage WM_KEYDOWN/WM_KEYUP` targets a window's message queue, not the physical input
stream, and is subject to [UIPI restrictions](https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-postmessagew).
It is not a way to bypass an integrity failure.

Use it only for an explicitly scoped target known to handle those messages, when the assertion
does not require a hook/raw-input/physical-key path. Check submission errors and independently
observe the handled effect; a fixed sleep is not delivery evidence. Escape handling depends on
the current control, focus and input mechanism. Invoking Back may navigate, but cannot prove Escape.

### CRITICAL — Global hotkeys / PowerToys activation chords (SendInput, verified working)

`PostMessage` above targets a specific window's queue. To fire a **global hotkey** (e.g. a PowerToys activation chord like `Win+Shift+C`) you must inject into the **system input stream** with `SendInput` so the low-level keyboard hook (`WH_KEYBOARD_LL`) sees it. This **works for Win+ chords** — the common belief that "Win+ chords can't be injected" is false; it's almost always a **marshaling bug** (`SendInput` returns `0`, `GetLastError()==87`) from building the `INPUT[]` array in PowerShell. Build the array in C#:

```powershell
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Collections.Generic;
public static class Inj {
    [StructLayout(LayoutKind.Sequential)]
    struct INPUT { public uint type; public KEYBDINPUT ki; public int p1; public int p2; }  // p1/p2 pad the union -> cb=40 on x64
    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [DllImport("user32.dll", SetLastError=true)] static extern uint SendInput(uint n, INPUT[] p, int cb);
    const uint KEYUP = 0x0002;
    static INPUT K(ushort vk, bool up){ INPUT i=new INPUT(); i.type=1; i.ki.wVk=vk; i.ki.dwFlags=up?KEYUP:0; return i; }
    public static uint Chord(ushort[] mods, ushort key){          // mods down -> key tap -> mods up (reverse)
        var l=new List<INPUT>();
        foreach(var m in mods) l.Add(K(m,false));
        l.Add(K(key,false)); l.Add(K(key,true));
        for(int i=mods.Length-1;i>=0;i--) l.Add(K(mods[i],true));
        var a=l.ToArray(); return SendInput((uint)a.Length,a,Marshal.SizeOf(typeof(INPUT)));
    }
}
"@
# LWIN=0x5B CTRL=0x11 SHIFT=0x10 ALT=0x12 ; main key VK from the module's settings.json "code"
$sent = [Inj]::Chord([uint16[]]@(0x5B,0x10), [uint16]0x43)   # Win+Shift+C (Color Picker)
if ($sent -eq 0) { throw "SendInput failed err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
```

**Caveats**:
- The injector must run at the **same or higher integrity level** as the hook owner (PowerToys runner). Default per-user installs run the runner at Medium IL, so a normal shell works; if the runner is elevated, run the injector elevated too (otherwise UIPI silently drops the injection).
- For physical-input tests implemented by a PowerToys low-level hook, the Runner must also be at the **same or higher integrity level than the foreground app**. A `RegisterHotKey` chord may still work when this condition is violated while a modifier-hold gesture produces no hook callback. Check both processes with `Test-PtRunnerAdmin` and `Test-ProcessElevated` before reporting an app-specific regression.
- Must run in the interactive desktop session.
- OS-reserved chords (Win+L, Win+Tab) are consumed by Windows before any hook and cannot be injected this way.
- Verify the result via the runner trace log line `… hotkey is invoked from Centralized keyboard hook` (`%LOCALAPPDATA%\Microsoft\PowerToys\RunnerLogs\runner-log_<date>.log`) and/or the module's observable side-effect (overlay window, spawned editor process).

### CRITICAL — Verify foreground BEFORE every SendInput targeting a specific window

`SendInput` injects into the **session-wide** input stream — it goes to whatever IS foreground at the moment. If your target window has lost foreground (very common with AppX windows), the keys silently land in another window (often your own terminal) with no error returned.

Use the shared `pt-foreground-guard.ps1` and `pt-sendinput-chord.ps1` helpers with the exact
window identity/HWND after its preservation plan is established. An AppId or a text match for
`foreground` cannot distinguish multiple windows of one process. Do not copy a second
AttachThreadInput/force-foreground implementation or assume a once-per-session reliability rule.
If the target cannot be established, stop input; UIA is an alternative only when it still tests
the claimed route.

### CRITICAL — Value setting and typed input are different paths

UIA ValuePattern sets a programmatic value. Whether that raises TextChanged, commits input or
activates a provider depends on the current control and application. Do not assume it always
bypasses TextChanged, or that a successful set-value proves the query was processed.

For CmdPal, discover the current query control and observe text and results independently.
When testing alias typing, use guarded physical input; directly opening a provider is not an
alias test. Earlier alias/event observations are version-specific troubleshooting clues, not
universal WinUI behavior or permission to replay input until results appear.

### CRITICAL — Diagnose sparse UIA trees without automatic recovery

A sparse tree may reflect a hidden/cloaked window, virtualization, a different provider or
an observation failure. Neither a fixed node-count threshold nor the number of earlier
queries establishes process degradation. Retain the original error/tree, confirm the target,
visibility and current tool capability, and use scoped pixels when needed.

Do not kill/relaunch an AppX, reset its query/navigation or repeatedly reissue the action as
an implicit probe. Recovery requires a separate authorized, identity-checked preservation and
lifecycle operation. Keep its effects separate from the original product verdict.

### Settings.json mutation safety contract

Use the real Settings UI when that route is under test; a file edit cannot rescue a failed
control, binding or IPC assertion. For an explicitly allowed configuration fixture, follow
the [paired snapshot and rollback contract](pre-flight.md#state-hygiene-critical--always-restore)
and the module's actual consumption boundary. Preserve original existence/bytes and attribute
the expected post-state before rollback. Do not assume all settings hot-reload, force-stop a
borrowed app to write its store, or claim cached-state restoration from disk equality alone.
