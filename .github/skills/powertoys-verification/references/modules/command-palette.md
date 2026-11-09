# Command Palette (CmdPal) — module verification profile

**PT module**: `CmdPal` / display name **"Command Palette"** (WinUI 3 packaged launcher — search box + extensible result providers/aliases)
**Source**: `src\modules\cmdpal\`
**Settings**: via `Get-CmdPalSettings` (`scripts/pt-state.ps1`) — CmdPal keeps its **own** packaged-app store, **not** the PT-store `<Module>\settings.json` that `Get-PtModuleSettings` reads.
**App identity**: packaged AppX, UIA AppId **`Microsoft.CmdPal.UI`**
**Named Event**: friendly name **`CmdPal.Show`** in the `pt-shared-events.ps1` catalog (foreground-free open)
**Helpers**: shared scoped UIA, foreground/input and recording helpers. The legacy
`scripts/pt-cmdpal-recycle.ps1` entry points are retired and throw without touching the app;
they are not a supported query, health-check or lifecycle route.

> Inspect the actual target's UIA controls/patterns and foreground before choosing an action.
> AppX/WinUI identity alone does not determine accessibility or input behavior. Before opening or
> querying a borrowed palette, preserve the affected query/navigation, history/pins, window and
> provider lifetime state; otherwise use an authorized owned fixture or report that limitation.

## Entry-paths (choose by the behavior under test)

### 1. Named Event — downstream activation
```powershell
. "$skill\scripts\pt-shared-events.ps1"
Invoke-PtSharedEvent -Name 'CmdPal.Show'     # requires the target consumer and preservation plan
```
This tests the downstream action, not the physical shortcut. Identify the actual target
consumer and resulting window; event existence alone does not establish readiness or artifact identity.

### 2. Scoped query — drive a search + read results
Resolve the current query control in the exact target window, then use its supported UIA
value operation or guarded physical typing, according to the claim. Record through
`Invoke-PtWinApp`/the shared case recorder and observe query text and provider results separately.
An empty result set is not proof of a degraded process. Do not reset navigation, replace the
query with a diagnostic string, recycle the app or replay input automatically.

### 3. Activation hotkey — only when the chord binding itself is under test
Press the configured activation shortcut from a guarded, compatible foreground fixture.
Do not open/focus CmdPal first merely to test opening it; that can turn the chord into a dismiss
action. Once typing into CmdPal, guard its exact foreground HWND immediately before input.

## Recipes — control/observation map, NOT an answer key

| # | Capability | Drive (control / command) | Observe (where the result shows) |
|---|---|---|---|
| 1 | CmdPal opens & is listening | `Invoke-PtSharedEvent -Name 'CmdPal.Show'` (or the hotkey) | `Microsoft.CmdPal.UI` window appears (`winapp ui list-windows`) |
| 2 | Plain-text query returns results | Scoped current query control; UIA value operation or guarded physical typing | query text and matching provider results independently agree |
| 3 | Alias engages (`=` `<` `>` `:` `$` `??` `)`) | Guard the exact foreground HWND and type the alias when testing that input path | the intended provider activates; direct provider invocation is a different route |
| 4 | Dismiss / navigate back | Test actual Escape handling when claimed; otherwise invoke the observed Back control once | independently observe the intended page or dismissed state |
| 5 | Diagnose an unresponsive session | Capture current window/consumer identity, query, UIA state and errors without recovery | distinguish missing results, hidden/virtualized controls and provider failures; recover only as a separate authorized operation |
| 6 | A setting round-trips | edit via Settings UI → `Get-CmdPalSettings` | the CmdPal store reflects the change |

> Mapping: read the checklist item → find the capability row → drive that control and design your own
> inputs/assertions. New capability ⇒ add a row.

## BLOCKED traps
- **Input can reach another foreground window.** Guard the exact CmdPal HWND before typing.
  A successful foreground request is not proof that focus remained there. Do not infer the
  same failure on every AppX window or assume foreground works only once per session.
- **Historical query/UIA degradation observations are not a universal threshold.** Earlier runs
  saw stalled queries or sparse trees after repeated probes; neither a query count nor a
  node-count cutoff diagnoses the current build. Preserve the first failure and check current
  visibility, provider readiness and tool output. Automatic recovery can hide the PR regression.
- **Programmatic value setting and physical typing are different paths.** Confirm the current
  control's actual event/commit behavior; do not assume ValuePattern always bypasses TextChanged.
  Alias typing claims require the actual input sequence, not direct provider navigation.
- **Escape handling is target-specific.** Test it with the correct foreground/integrity and
  input mechanism. If another route is used for navigation, do not credit it as an Escape PASS.
- **`PowerToys (Preview)` can be an app-search false positive.** A result with the shortcut-arrow overlay and subtitle `PowerToys - Windows system utilities to maximize productivity` comes from **Search apps**, not the PowerToys command extension. Running it launches PowerToys and returns CmdPal home. The real extension exposes a PowerToys command page and module fallback commands such as `Toggle Shortcut Guide`; confirm those commands exist before treating the integration as available.
